local addonName, ns = ...

-- Bank.lua: eigenes Bankfenster im Forever-Stil, solange man beim Bankier steht (Einstellung "replaceBank").
-- Gleicher Aufbau wie das Taschenfenster: je Bankfach ein unsichtbarer Rahmen mit SetID(Fach) und Blizzards
-- Taschenplatz-Knöpfe – Rechtsklick legt Gegenstände in die Taschen, Ziehen funktioniert in beide Richtungen.
-- Blizzards Bankfenster bleibt offen (sonst endet der Bankbesuch), ist aber unsichtbar und nicht anklickbar.

local L = ns.L
local UI = ForeverHub.UI

local PAD, HEADER, TOOLBAR, FOOTER = 8, 27, 28, 30 -- (Fußzeile mit Platz für "Kaufen" in voller Höhe)
local BAGBAR, BAGSLOT = 48, 30 -- Zeile "Taschenplätze" unter den Bankplätzen (Höhe samt Luft, Kantenlänge eines Platzes)
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
        bank:SetSize(math.max(width + 2 * PAD, 330), HEADER + TOOLBAR + height + BAGBAR + FOOTER + 2 * PAD)
    end
    freeText:SetText(L("FREE_SLOTS", total - used, total))
    if ns.UpdateBankPurchase then ns.UpdateBankPurchase() end
    if ns.UpdateBankBagBar then ns.UpdateBankBagBar() end
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
    -- Inhalt einer Tabelle als kurzer Text (Felder = Werte)
    local function Fields(t)
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            if type(v) ~= "table" and type(v) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    if C_Bank then
        local names = {}
        for k in pairs(C_Bank) do names[#names + 1] = k end
        table.sort(names)
        Say("C_Bank: " .. table.concat(names, ", "))
        if C_Bank.FetchPurchasedBankTabData then
            local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
            if ok and type(data) == "table" and data[1] then Say("Fach 1: " .. Fields(data[1])) end
        end
        if C_Bank.FetchNextPurchasableBankTabData then
            local ok, data = pcall(C_Bank.FetchNextPurchasableBankTabData, bankType)
            Say("Nächster kaufbarer Platz: " .. (ok and Fields(data) or "Fehler"))
        end
        for _, fn in ipairs({ "CanPurchaseBankTab", "HasMaxBankTabs", "FetchBankLockedReason", "CanUseBank" }) do
            if C_Bank[fn] then Say(fn .. ": " .. Try(C_Bank[fn], bankType)) end
        end
    end
    local bag = ns.BankIDs()[1]
    if bag and C_Container.GetContainerNumFreeSlots then
        Say("Freie Plätze Fach " .. bag .. ": " .. Try(C_Container.GetContainerNumFreeSlots, bag))
    end
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

---------------------------------------------------------------------------
-- Weiteren Bankplatz kaufen (wie Blizzards "Taschenplätze … Kosten … Kaufen"): der Forever-Client nutzt dafür
-- Blizzards Bankfächer (C_Bank). Unten rechts: Preis und "Kaufen" – mit Rückfrage; danach erscheint der neue
-- Platz von selbst (BANK_TABS_CHANGED). Nur sichtbar, wenn das Spiel einen Kauf erlaubt.
---------------------------------------------------------------------------
local buyButton, buyText
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:12:12:2:0|t"
local function Money(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN:format("Gold") end
    if s > 0 then parts[#parts + 1] = s .. COIN:format("Silver") end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COIN:format("Copper") end
    return table.concat(parts, " ")
end

local function BankType() return Enum and Enum.BankType and Enum.BankType.Character end

-- nächster kaufbarer Platz: kann man kaufen? Preis (Kupfer)?
local function NextPurchase()
    if not (C_Bank and C_Bank.CanPurchaseBankTab and BankType()) then return false end
    local ok, can = pcall(C_Bank.CanPurchaseBankTab, BankType())
    if not (ok and can) then return false end
    local cost
    if C_Bank.FetchNextPurchasableBankTabData then
        local okData, data = pcall(C_Bank.FetchNextPurchasableBankTabData, BankType())
        if okData and type(data) == "table" then cost = data.tabCost or data.cost end
    end
    return true, cost
end

ns.BankMoney = Money

-- nächsten Platz kaufen: C_Bank.PurchaseBankTab ist geschützt – ein Addon darf sie nicht selbst aufrufen (auch nicht aus
-- einem eigenen Rückfrage-Fenster: ADDON_ACTION_FORBIDDEN, Fehler vom 2026-11-13). Wie Baganator: ein durchsichtiger
-- Knopf mit Blizzards eigener Vorlage "BankPanelPurchaseButtonScriptTemplate" liegt über unserem Knopf; sein Klick
-- führt Blizzards Kauf-Rückfrage aus (Blizzard-Code, kein Taint), die Bankart steht im Attribut "overrideBankType".
local function BuyProxy(owner)
    if owner.buyProxy ~= nil then return owner.buyProxy or nil end
    local ok, proxy = pcall(CreateFrame, "Button", nil, owner:GetParent(), "BankPanelPurchaseButtonScriptTemplate")
    if not ok or not proxy then
        owner.buyProxy = false
        return nil
    end
    proxy:SetAttribute("overrideBankType", BankType())
    proxy:SetAllPoints(owner)
    proxy:SetFrameLevel(owner:GetFrameLevel() + 10)
    proxy:Hide()
    -- Maus: Hinweistexte und Hervorhebung bleiben die des darunterliegenden Knopfs
    proxy:HookScript("OnEnter", function()
        local fn = owner:GetScript("OnEnter")
        if fn then fn(owner) end
        if owner.LockHighlight then owner:LockHighlight() end
    end)
    proxy:HookScript("OnLeave", function()
        local fn = owner:GetScript("OnLeave")
        if fn then fn(owner) end
        if owner.UnlockHighlight then owner:UnlockHighlight() end
    end)
    owner.buyProxy = proxy
    return proxy
end

-- Kauf-Knopf über dem Knopf "owner" ein-/ausblenden (im Kampf nicht anfassen: der Knopf ist geschützt)
local function ShowBuyProxy(owner, shown)
    local proxy = BuyProxy(owner)
    if not proxy or InCombatLockdown() then return end
    proxy:SetShown(shown and true or false)
end

-- Rückfall (Vorlage fehlt im Client): nur ein Hinweis
function ns.BuyBankSlot()
    local can, cost = NextPurchase()
    if not can then return end
    ns.Print(L("BUY_BANK_BLIZZARD") .. (cost and (" (" .. Money(cost) .. ")") or ""))
end

function ns.UpdateBankPurchase()
    if not buyButton then return end
    local can, cost = NextPurchase()
    buyButton:SetShown(can)
    buyText:SetShown(can)
    local affordable = false
    if can then
        buyText:SetText(L("BUY_BANK_NEXT") .. " " .. (cost and Money(cost) or "?"))
        affordable = not cost or (GetMoney and GetMoney() >= cost)
        buyButton:SetEnabled(affordable)
        buyButton:SetAlpha(affordable and 1 or 0.45)
        buyText:SetTextColor(affordable and 1 or 1, affordable and 1 or 0.35, affordable and 1 or 0.35)
    end
    ShowBuyProxy(buyButton, can and affordable)
end

---------------------------------------------------------------------------
-- Taschenleiste der Bank ("Taschenplätze", wie bei Blizzard): der Forever-Client führt die klassischen
-- Bank-Taschenplätze als Bankfächer (C_Bank). Fach 1 ("Reiter 1") ist die Grundbank; jedes weitere gekaufte Fach ist
-- ein Taschenplatz, in den eine Tasche gehört (Ausrüstungsplatz über C_Bank.BankBagTypeAndIDToInvSlot). Gesperrte
-- Plätze zeigen ein Schloss – der erste kauft per Klick (mit Rückfrage).
---------------------------------------------------------------------------
local bagBar, bagButtons = nil, {}
-- (Schloss aus den Haustierkämpfen: sitzt mittig in seinem Bild – das LFG-Schloss hatte einen ungleichen Rand)
local LOCK = "Interface\\PetBattles\\PetBattle-LockIcon"
local EMPTY_BAG = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function PurchasedTabIDs()
    local ids = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and BankType() then
        local ok, list = pcall(C_Bank.FetchPurchasedBankTabIDs, BankType())
        if ok and type(list) == "table" then ids = list end
    end
    return ids
end

local function MaxTabs()
    if C_Bank and C_Bank.FetchMaxNumBankTabs and BankType() then
        local ok, n = pcall(C_Bank.FetchMaxNumBankTabs, BankType())
        if ok and type(n) == "number" then return n end
    end
    return 9 -- (Grundfach + 8 Taschenplätze wie in Blizzards Fenster)
end

-- Ausrüstungsplatz der Bank-Tasche Nr. i (1 = erster Taschenplatz) bzw. des Fachs tabID. Der klassische Weg
-- (BankButtonIDToInvSlotID(i, 1), so zählen Baganator/Syndicator und Blizzards Rechtsklick-Ablage) kann von
-- C_Bank.BankBagTypeAndIDToInvSlot(Art, Fach) abweichen – dann lag eine neu gekaufte Tasche im einen Platz, wir zeigten
-- und belegten aber den anderen ("erst Platz kaufen", Platz sieht leer aus). Darum: den Platz nehmen, in dem wirklich eine
-- Tasche steckt; sonst den klassischen.
local function InvSlotFor(i, tabID)
    local classic
    if BankButtonIDToInvSlotID then
        local ok, slot = pcall(BankButtonIDToInvSlotID, i, 1)
        if ok and type(slot) == "number" then classic = slot end
    end
    local tabbed
    if tabID and C_Bank and C_Bank.BankBagTypeAndIDToInvSlot then
        local ok, slot = pcall(C_Bank.BankBagTypeAndIDToInvSlot, BankType(), tabID)
        if ok and type(slot) == "number" then tabbed = slot end
    end
    if classic and GetInventoryItemID and GetInventoryItemID("player", classic) then return classic end
    if tabbed and GetInventoryItemID and GetInventoryItemID("player", tabbed) then return tabbed end
    return classic or tabbed
end

local function BagButton(i)
    local b = bagButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, bagBar)
    b:SetSize(BAGSLOT, BAGSLOT)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnClick", function(self)
        if self.locked then
            if self.buyable and ns.BuyBankSlot then ns.BuyBankSlot() end
            return
        end
        if not self.invSlot then return end
        if CursorHasItem and CursorHasItem() then
            if PutItemInBag then PutItemInBag(self.invSlot) end
        elseif PickupInventoryItem then
            PickupInventoryItem(self.invSlot)
        end
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if not self.locked and self.invSlot and PutItemInBag then PutItemInBag(self.invSlot) end
    end)
    b:SetScript("OnDragStart", function(self)
        if not self.locked and self.invSlot and PickupInventoryItem then PickupInventoryItem(self.invSlot) end
    end)
    b:SetScript("OnEnter", function(self)
        local tip = GameTooltip
        tip:SetOwner(self, "ANCHOR_TOP")
        if self.locked then
            tip:AddLine(L("BANKBAG_LOCKED"), 1, 0.82, 0)
            if self.buyable then
                tip:AddLine(L("BUY_BANK_NEXT") .. " " .. (self.cost and ns.BankMoney(self.cost) or "?"), 1, 1, 1)
                tip:AddLine(L("BANKBAG_CLICK_BUY"), 0.7, 0.7, 0.7)
            end
        elseif self.invSlot and GetInventoryItemLink("player", self.invSlot) then
            tip:SetInventoryItem("player", self.invSlot)
        else
            tip:AddLine(L("BANKBAG_EMPTY"), 1, 0.82, 0)
            tip:AddLine(L("BANKBAG_DROP"), 0.7, 0.7, 0.7, true)
        end
        tip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- erst nach den Skripten: dunkle Fläche, feiner Rand, Maus = gold (wie die Taschenplätze; hängt sich an)
    if ns.AddForeverLook then ns.AddForeverLook(b) end
    bagButtons[i] = b
    return b
end

function ns.UpdateBankBagBar()
    if not bagBar then return end
    local ids = PurchasedTabIDs()
    local count = math.max(0, MaxTabs() - 1)
    local canBuy, cost = NextPurchase()
    local firstLocked = true
    for i = 1, count do
        local b = BagButton(i)
        b:ClearAllPoints()
        b:SetPoint("LEFT", bagBar.label, "RIGHT", 8 + (i - 1) * (BAGSLOT + 4), 0)
        local tabID = ids[i + 1] -- (ids[1] = Grundfach)
        b.invSlot = tabID and InvSlotFor(i, tabID) or nil
        b.locked = tabID == nil
        b.buyable = b.locked and firstLocked and canBuy
        b.cost = cost
        ShowBuyProxy(b, b.buyable and (not cost or (GetMoney and GetMoney() >= cost)))
        b.icon:ClearAllPoints()
        if b.locked then
            firstLocked = false
            -- Schloss als kleines Symbol genau in der Mitte des Platzes
            b.icon:SetSize(16, 16)
            b.icon:SetPoint("CENTER")
            b.icon:SetTexture(LOCK)
            b.icon:SetTexCoord(0, 1, 0, 1)
            b.icon:SetDesaturated(not b.buyable)
            b.icon:SetAlpha(b.buyable and 1 or 0.6)
        else
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            local tex = b.invSlot and GetInventoryItemTexture("player", b.invSlot)
            b.icon:SetTexture(tex or EMPTY_BAG)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b.icon:SetDesaturated(false)
            b.icon:SetAlpha(tex and 1 or 0.5)
        end
        b:Show()
    end
    for i = count + 1, #bagButtons do bagButtons[i]:Hide() end
end

local function CloseBank()
    if C_Bank and C_Bank.CloseBankFrame then pcall(C_Bank.CloseBankFrame)
    elseif CloseBankFrame then CloseBankFrame() end
end

local function CreateBank()
    bank = ns.CreateBagWindow("ForeverBagsBank", L("BANK_TITLE"), "bankPos", DEFAULT_POS)
    -- standardmäßig 5 % größer (eine mit dem Griff unten rechts selbst gesetzte Größe übernimmt der Hub beim Öffnen)
    bank:SetScale(1.05)

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

    -- Taschenleiste unter den Bankplätzen: "Taschenplätze:" und die Plätze, rechts daneben Preis und "Kaufen"
    bagBar = CreateFrame("Frame", nil, bank)
    bagBar:SetHeight(BAGSLOT)
    bagBar:SetPoint("TOPLEFT", content, "BOTTOMLEFT", 0, -10)
    bagBar:SetPoint("RIGHT", bank, "RIGHT", -PAD, 0)
    bagBar.label = bagBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bagBar.label:SetPoint("LEFT", 0, 0)
    bagBar.label:SetText(L("BANKBAG_LABEL"))

    buyButton = UI.Button(bank, L("BUY_BANK"), 90, function() ns.BuyBankSlot() end)
    -- unten rechts in der Fußzeile (auf Höhe von "… frei"); die Ecke rechts bleibt für den Größen-Griff frei
    -- genau aufs Bildschirmraster (auf halben Pixeln fiel die feine Linie oben weg)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(buyButton, "BOTTOMRIGHT", bank, "BOTTOMRIGHT", -PAD - 16, PAD)
    else
        buyButton:SetPoint("BOTTOMRIGHT", bank, "BOTTOMRIGHT", -PAD - 16, PAD)
    end
    buyButton:HookScript("OnEnter", function(self) ns.SimpleTip(self, L("TIP_BUY_BANK")) end)
    buyButton:HookScript("OnLeave", ns.HideTip)
    buyText = bank:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buyText:SetPoint("RIGHT", buyButton, "LEFT", -6, 0)
    buyButton:Hide()
    buyText:Hide()

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
    "BANK_TABS_CHANGED", "PLAYER_MONEY", "BANK_TAB_SETTINGS_UPDATED", "PLAYERBANKBAGSLOTS_CHANGED",
    "BAG_CONTAINER_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do -- nachgeladene Gegenstandsdaten (sonst leere Plätze)
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
