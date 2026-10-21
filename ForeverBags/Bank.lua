local addonName, ns = ...

-- Bank.lua: eigenes Bankfenster im Forever-Stil, solange man beim Bankier steht (Einstellung "replaceBank").
-- Gleicher Aufbau wie das Taschenfenster: je Bankfach ein unsichtbarer Rahmen mit SetID(Fach) und Blizzards
-- Taschenplatz-Knöpfe – Rechtsklick legt Gegenstände in die Taschen, Ziehen funktioniert in beide Richtungen.
-- Blizzards Bankfenster bleibt offen (sonst endet der Bankbesuch), ist aber unsichtbar und nicht anklickbar.

local L = ns.L
local UI = ForeverHub.UI

local PAD, HEADER, TOOLBAR, FOOTER = 8, 27, 28, 24
local DEFAULT_POS = "CENTER" -- noch nie verschoben: Bildschirmmitte; danach die gemerkte Lage (Ziehen speichert sie)

local bank, content, freeText
local frames, buttons = {}, {}
local atBank = false
local closing = false

local function Replacing() return ns.db and ns.db.replaceBank end

local function CreateSlot(bag, slot)
    local parent = frames[bag]
    if not parent then
        parent = CreateFrame("Frame", nil, content)
        parent:SetAllPoints(content)
        parent:SetID(bag)
        frames[bag] = parent
    end
    local button = CreateFrame("ItemButton", "ForeverBagsBankSlot" .. (bag < 0 and ("m" .. -bag) or bag) .. "_" .. slot,
        parent, "ContainerFrameItemButtonTemplate")
    button:SetID(slot)
    if button.SetBagID then pcall(button.SetBagID, button, bag) end
    button:SetSize(ns.SLOT, ns.SLOT)
    -- Blizzards Vorlage dunkelt Gegenstände ab, die nicht zum "aktuellen Zusammenhang" passen – bei der neuen Bank
    -- hängt der am (unsichtbaren) Blizzard-Bankfenster und traf unsere Bankplätze: alles dunkel und nicht klickbar.
    -- Wie Blizzards eigene Bankknöpfe: "gilt hier nicht" (nie abdunkeln).
    local dna = ItemButtonUtil and ItemButtonUtil.ItemContextMatchResult and ItemButtonUtil.ItemContextMatchResult.DoesNotApply
    if dna ~= nil then
        button.GetItemContextMatchResult = function() return dna end
    end
    if button.ItemContextOverlay then button.ItemContextOverlay:Hide() end
    ns.StyleSlot(button, bag)
    buttons[bag] = buttons[bag] or {}
    buttons[bag][slot] = button
    return button
end

function ns.LayoutBank()
    if not bank or not bank:IsShown() then return end
    local columns = math.max(6, ns.db.bankColumns or 14)
    local gap = math.max(0, ns.db.spacing or 2)
    local SLOT = ns.SLOT
    local index, used, total = 0, 0, 0
    for _, bag in ipairs(ns.BankIDs()) do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        for slot, button in pairs(buttons[bag] or {}) do
            if slot > size then button:Hide() end
        end
        for slot = 1, size do
            local button = buttons[bag] and buttons[bag][slot]
            if not button and not InCombatLockdown() then button = CreateSlot(bag, slot) end
            if button then
                if not InCombatLockdown() then
                    local col, row = index % columns, math.floor(index / columns)
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SLOT + gap), -row * (SLOT + gap))
                end
                ns.UpdateSlot(button, bag, slot)
                if button.ItemContextOverlay then button.ItemContextOverlay:Hide() end
                index = index + 1
                total = total + 1
                if C_Container.GetContainerItemID(bag, slot) then used = used + 1 end
            end
        end
    end
    local rows = math.max(1, math.ceil(index / columns))
    local width = columns * SLOT + (columns - 1) * gap
    local height = rows * SLOT + (rows - 1) * gap
    if not InCombatLockdown() then
        content:SetSize(width, height)
        bank:SetSize(math.max(width + 2 * PAD, 330), HEADER + TOOLBAR + height + FOOTER + 2 * PAD)
    end
    freeText:SetText(L("FREE_SLOTS", total - used, total))
end

-- /fbags bankcheck: Zustand des ersten Bankplatzes und was unter der Maus liegt (zur Fehlersuche)
function ns.BankCheck()
    local function Say(text) print("|cffffcc00ForeverBags|r: " .. tostring(text)) end
    Say("Fächer: " .. table.concat(ns.BankIDs(), ", ") .. " · Bank offen: " .. tostring(atBank))
    -- je Fach die Größe, dazu, was das Spiel als gekauft meldet (Fehlersuche "nicht gekaufte Plätze sichtbar")
    local sizes = {}
    for _, bag in ipairs(ns.BankIDs()) do sizes[#sizes + 1] = bag .. "=" .. (C_Container.GetContainerNumSlots(bag) or 0) end
    Say("Größen: " .. table.concat(sizes, ", "))
    local function Try(fn, ...)
        if type(fn) ~= "function" then return "–" end
        local ok, a = pcall(fn, ...)
        if not ok then return "Fehler" end
        if type(a) == "table" then return "#" .. #a end
        return tostring(a)
    end
    local bankType = Enum and Enum.BankType and Enum.BankType.Character
    Say(string.format("Gekauft: Fächer-Liste %s, Fächer-Anzahl %s, Bank-Taschenplätze %s, Enum Bankfach %s",
        Try(C_Bank and C_Bank.FetchPurchasedBankTabData, bankType), Try(C_Bank and C_Bank.FetchNumPurchasedBankTabs, bankType),
        Try(GetNumBankSlots), tostring(Enum and Enum.BagIndex and Enum.BagIndex.CharacterBankTab_1)))
    local bag = ns.BankIDs()[1]
    local b = bag and buttons[bag] and buttons[bag][1]
    if not b then Say("kein Bankplatz angelegt") return end
    local info = C_Container.GetContainerItemInfo(bag, 1)
    local ctx = b.GetItemContextMatchResult and select(2, pcall(b.GetItemContextMatchResult, b))
    Say(string.format("Platz 1: sichtbar=%s Deckkraft=%.2f effektiv=%.2f aktiv=%s Maus=%s gefiltert=%s gesperrt=%s Kontext=%s Overlay=%s",
        tostring(b:IsVisible()), b:GetAlpha(), b:GetEffectiveAlpha(), tostring(b.IsEnabled and b:IsEnabled()),
        tostring(b:IsMouseEnabled()), tostring(info and info.isFiltered), tostring(info and info.isLocked),
        tostring(ctx), tostring(b.ItemContextOverlay and b.ItemContextOverlay:IsShown())))
    if bank then Say(string.format("Bankfenster: Ebene %s/%d", bank:GetFrameStrata(), bank:GetFrameLevel())) end
    -- Blizzards Fenster: offen, sichtbar, Deckkraft, Ebene
    for _, name in ipairs({ "BankFrame", "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local f = _G[name]
        if f then
            Say(string.format("%s: offen=%s Deckkraft=%.2f effektiv=%.2f Ebene %s/%d", name, tostring(f:IsShown()),
                f:GetAlpha(), f:GetEffectiveAlpha(), f:GetFrameStrata(), f:GetFrameLevel()))
        end
    end
    local bb = _G.ForeverBagsFrame
    if bb then Say(string.format("Taschenfenster: Ebene %s/%d", bb:GetFrameStrata(), bb:GetFrameLevel())) end
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    for _, f in ipairs(foci or {}) do
        local alpha = f and f.GetEffectiveAlpha and string.format(" (effektiv %.2f)", f:GetEffectiveAlpha()) or ""
        Say("Unter der Maus: " .. tostring(f and f.GetDebugName and f:GetDebugName() or f) .. alpha)
    end
end

local function CloseBank()
    if C_Bank and C_Bank.CloseBankFrame then pcall(C_Bank.CloseBankFrame)
    elseif CloseBankFrame then CloseBankFrame() end
end

local function CreateBank()
    bank = ns.CreateBagWindow("ForeverBagsBank", L("BANK_TITLE"), "bankPos", DEFAULT_POS)

    -- Werkzeugzeile: Sortieren, Reagenzien einlagern (falls das Spiel das kann)
    local sort = UI.Button(bank, L("SORT"), 70, function()
        if C_Container.SortBankBags then C_Container.SortBankBags() end
    end)
    sort:SetPoint("TOPRIGHT", -PAD, -HEADER - 4)
    sort:HookScript("OnEnter", function(self) ns.SimpleTip(self, L("TIP_SORT_BANK")) end)
    sort:HookScript("OnLeave", ns.HideTip)
    local canDeposit = (C_Bank and C_Bank.AutoDepositItemsIntoBank) or DepositReagentBank
    if canDeposit then
        local deposit = UI.Button(bank, L("DEPOSIT_REAGENTS"), 150, function()
            if C_Bank and C_Bank.AutoDepositItemsIntoBank then
                pcall(C_Bank.AutoDepositItemsIntoBank, Enum and Enum.BankType and Enum.BankType.Character or 0)
            elseif DepositReagentBank then
                DepositReagentBank()
            end
        end)
        deposit:SetPoint("TOPLEFT", PAD, -HEADER - 4)
    end

    content = CreateFrame("Frame", nil, bank)
    content:SetPoint("TOPLEFT", PAD, -HEADER - TOOLBAR)
    content:SetSize(1, 1)
    freeText = bank:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("BOTTOMLEFT", PAD, PAD + 2)

    bank:HookScript("OnShow", ns.LayoutBank)
    -- Taschen bleiben rechts angedockt: nach dem Verschieben und wenn die Bank ihre Größe ändert
    bank:HookScript("OnSizeChanged", function() if ns.DockBagsToBank then ns.DockBagsToBank() end end)
    bank.header:HookScript("OnDragStop", function()
        C_Timer.After(0, function() if ns.DockBagsToBank then ns.DockBagsToBank() end end)
    end)
    -- Unser Fenster zu = Bankbesuch beenden (wie bei Blizzards Bankfenster)
    bank:HookScript("OnHide", function()
        if atBank and not closing then CloseBank() end
    end)
end

local function OnBankOpened()
    atBank = true
    if not Replacing() then return end
    if not bank then CreateBank() end
    ns.HideBlizzardPanel(_G.BankFrame)
    C_Timer.After(0.2, function() if atBank then ns.HideBlizzardPanel(_G.BankFrame) end end) -- Fächer laden nach
    -- einmalig: neue Standardlage (Mitte, Taschen rechts daneben) – alte gespeicherte Lage verwerfen
    if not ns.db.bankPosV2 then
        ns.db.bankPos = nil
        ns.db.bankPosV2 = true
    end
    bank.RestorePosition()
    bank:Show()
    if ns.OpenBags then ns.OpenBags() end
    -- Taschen rechts an die Bank (auch wenn sie schon offen waren); nach dem ersten Aufbau noch einmal
    if ns.DockBagsToBank then
        ns.DockBagsToBank()
        C_Timer.After(0.05, ns.DockBagsToBank)
    end
end

local function OnBankClosed()
    atBank = false
    closing = true
    if bank then bank:Hide() end
    closing = false
    ns.RestoreBlizzardPanel(_G.BankFrame)
end

local queued = false
local events = CreateFrame("Frame")
for _, event in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "INVENTORY_SEARCH_UPDATE", "PLAYERREAGENTBANKSLOTS_CHANGED",
    "BANK_TABS_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        OnBankOpened()
    elseif event == "BANKFRAME_CLOSED" then
        OnBankClosed()
    elseif bank and bank:IsShown() and not queued then
        queued = true
        C_Timer.After(0.05, function()
            queued = false
            ns.LayoutBank()
        end)
    end
end)
