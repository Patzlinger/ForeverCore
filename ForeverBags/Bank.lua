local addonName, ns = ...

-- Bank.lua: eigenes Bankfenster im Forever-Stil, solange man beim Bankier steht (Einstellung "replaceBank").
-- Gleicher Aufbau wie das Taschenfenster: je Bankfach ein unsichtbarer Rahmen mit SetID(Fach) und Blizzards
-- Taschenplatz-Knöpfe – Rechtsklick legt Gegenstände in die Taschen, Ziehen funktioniert in beide Richtungen.
-- Blizzards Bankfenster bleibt offen (sonst endet der Bankbesuch), ist aber unsichtbar und nicht anklickbar.

local L = ns.L
local UI = ForeverHub.UI

local PAD, HEADER, TOOLBAR, FOOTER = 8, 27, 28, 24
local DEFAULT_POS = { 40, 700 } -- obere linke Ecke (UIParent-Einheiten ab unten links)

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
    bank.RestorePosition()
    bank:Show()
    if ns.OpenBags then ns.OpenBags() end
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
