-- ForeverSkin – Merchant.lua: eigene Händler-Ansicht im Forever-Stil (neues Konzept statt Blizzards Raster).
-- Liegt über Blizzards Händlerfenster (das offen bleibt, damit Verkaufen per Rechtsklick in der Tasche usw. weiter
-- geht) und nutzt nur Blizzards Kauf-Funktionen (BuyMerchantItem, BuybackItem, RepairAllItems …).
--  * oben Titelleiste und Visitenkarte (Porträt, Name, Titel), darunter Reiter "Händler/Rückkauf" und Suche
--  * eine Liste aller Waren (kein Blättern, Mausrad): Symbol mit Stapelzahl, Name in Qualitätsfarbe, Preis
--    (rot = zu teuer), Vorrat rechts; Maus darüber = Tooltip
--  * unten feste Leiste: Reparieren, Gildenbank-Reparatur, Plunder verkaufen links, Geld rechts
-- Bedienung wie bei Blizzard: Rechtsklick kaufen (Umschalt = ganzer Stapel), Linksklick aufnehmen, Strg = Anprobe,
-- Umschalt + Linksklick = Link in den Chat. Waren mit Sonderwährung fragen vor dem Kauf nach.
local _, ns = ...
local C, T = ns.C, ns.T
local UI = ns.UI

local W, H = 384, 520                 -- Größe (wie das Gesprächsfenster)
local ROW_H, ICON = 40, 34
local LIST_TOP, FOOT = 141, 40        -- Liste ab hier (unter Visitenkarte, Reitern, Filter), Höhe der unteren Leiste
local panel, rows, list, scrollBar = nil, {}, nil, nil
local tab = "buy"                     -- "buy" oder "buyback"
local offset, filter = 0, ""
local entries = {}

local function G(name) return _G[name] end

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------
local function MerchantInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" then return info end
    end
    if GetMerchantItemInfo then
        local name, tex, price, stack, avail, purchasable, usable, ext = GetMerchantItemInfo(i)
        return { name = name, texture = tex, price = price, stackCount = stack, numAvailable = avail,
            isPurchasable = purchasable, isUsable = usable, hasExtendedCost = ext }
    end
end

local function Quality(link)
    if not link then return nil end
    local q = select(3, (C_Item and C_Item.GetItemInfo or GetItemInfo)(link))
    return q
end

-- Geld mit Münz-Symbolen (eigene Fassung: GetCoinTextureString lieferte in Forever nur die nackte Zahl)
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:12:12:2:0|t"
local function Money(copper, color)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or g) .. COIN:format("Gold") end
    if s > 0 then parts[#parts + 1] = s .. COIN:format("Silver") end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COIN:format("Copper") end
    local text = table.concat(parts, " ")
    if color then text = color .. text .. "|r" end
    return text
end
ns.Money = Money

-- Preis als Text: Geld (rot, wenn zu teuer) und Sonderwährungen (Symbol + Anzahl)
local function PriceText(i, price, ext)
    local parts = {}
    if price and price > 0 then
        parts[#parts + 1] = Money(price, price > GetMoney() and "|cffff5555" or nil)
    end
    if ext and GetMerchantItemCostInfo then
        for k = 1, (GetMerchantItemCostInfo(i) or 0) do
            local tex, value = GetMerchantItemCostItem(i, k)
            if tex and value then parts[#parts + 1] = value .. " |T" .. tex .. ":14:14:0:0|t" end
        end
    end
    return table.concat(parts, "   ")
end

local function Collect()
    wipe(entries)
    local f = filter:lower()
    if tab == "buy" then
        -- "Nicht benutzbare ausblenden": was Blizzard als für dich nicht benutzbar meldet (auch Waffen/Rüstung, die du
        -- nicht tragen kannst – die zeigt Blizzard rot)
        local hideUnusable = ns.GetDB().merchantHideUnusable
        for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
            local info = MerchantInfo(i)
            if info and info.name and (f == "" or info.name:lower():find(f, 1, true))
                and not (hideUnusable and info.isUsable == false) then
                local link = GetMerchantItemLink and GetMerchantItemLink(i)
                entries[#entries + 1] = {
                    index = i, name = info.name, icon = info.texture, link = link, quality = Quality(link),
                    stack = info.stackCount or 1, available = info.numAvailable or -1, usable = info.isUsable ~= false,
                    ext = info.hasExtendedCost, price = PriceText(i, info.price, info.hasExtendedCost),
                }
            end
        end
    else
        for i = 1, (GetNumBuybackItems and GetNumBuybackItems() or 0) do
            local name, icon, price, quantity = GetBuybackItemInfo(i)
            if name and (f == "" or name:lower():find(f, 1, true)) then
                local link = GetBuybackItemLink and GetBuybackItemLink(i)
                entries[#entries + 1] = { index = i, name = name, icon = icon, link = link, quality = Quality(link),
                    stack = quantity or 1, available = -1, usable = true, buyback = true,
                    price = PriceText(i, price, false) }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Kaufen
---------------------------------------------------------------------------
StaticPopupDialogs["FOREVERSKIN_MERCHANT_BUY"] = {
    text = "%s",
    button1 = YES or "Ja", button2 = NO or "Nein",
    OnAccept = function(_, data) if data then BuyMerchantItem(data.index, data.qty) end end,
    timeout = 0, hideOnEscape = true, whileDead = true,
}

local function Buy(e, stack)
    if e.buyback then
        BuybackItem(e.index)
        return
    end
    local qty = 1
    if stack then
        local max = GetMerchantItemMaxStack and GetMerchantItemMaxStack(e.index) or 1
        qty = math.max(1, math.floor((max or 1) / math.max(1, e.stack)))
    end
    if e.ext then
        -- Sonderwährung (Ehre, Marken …): vorher fragen
        StaticPopup_Show("FOREVERSKIN_MERCHANT_BUY", string.format(T("%s für %s kaufen?", "Buy %s for %s?"),
            (e.link or e.name) .. (qty > 1 and (" ×" .. qty) or ""), e.price), nil, { index = e.index, qty = qty })
    else
        BuyMerchantItem(e.index, qty)
    end
end

---------------------------------------------------------------------------
-- Liste
---------------------------------------------------------------------------
local Refresh

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    UI.SetFlat(row, C.button)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetPoint("TOPLEFT", 1, -1)
    row.hl:SetPoint("BOTTOMRIGHT", -1, 1)
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON - 2, ICON - 2)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.iconEdge = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconEdge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
    row.iconEdge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    row.iconEdge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.price:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.price:SetJustifyH("LEFT")
    row.stock = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.stock:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.buyback then GameTooltip:SetBuybackItem(e.index) else GameTooltip:SetMerchantItem(e.index) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        local e = self.entry
        if not e then return end
        if IsModifiedClick("DRESSUP") and e.link then DressUpItemLink(e.link) return end
        if button == "LeftButton" and IsModifiedClick("CHATLINK") and e.link then ChatEdit_InsertLink(e.link) return end
        if button == "RightButton" then
            Buy(e, IsShiftKeyDown())
        elseif not e.buyback and PickupMerchantItem then
            PickupMerchantItem(e.index)
        end
    end)
    row:SetScript("OnDragStart", function(self)
        local e = self.entry
        if e and not e.buyback and PickupMerchantItem then PickupMerchantItem(e.index) end
    end)
    rows[i] = row
    return row
end

local function VisibleRows()
    return math.max(1, math.floor((list:GetHeight() + 4) / (ROW_H + 4)))
end

function Refresh()
    if not (panel and panel:IsShown()) then return end
    Collect()
    local visible = VisibleRows()
    offset = math.max(0, math.min(offset, #entries - visible))
    for i = 1, visible do
        local row = Row(i)
        local e = entries[offset + i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * (ROW_H + 4))
        row:SetPoint("RIGHT", list, "RIGHT", -10, 0)
        if e then
            row.entry = e
            row.icon:SetTexture(e.icon)
            row.icon:SetDesaturated(not e.usable)
            row.icon:SetVertexColor(e.usable and 1 or 1, e.usable and 1 or 0.3, e.usable and 1 or 0.3)
            row.count:SetText((e.stack and e.stack > 1) and e.stack or "")
            local r, g, b = 1, 1, 1
            if e.quality and GetItemQualityColor then r, g, b = GetItemQualityColor(e.quality) end
            row.name:SetText(e.name)
            row.name:SetTextColor(r, g, b)
            row.iconEdge:SetBackdropBorderColor(r * 0.8, g * 0.8, b * 0.8, (e.quality and e.quality >= 2) and 1 or 0.4)
            row.price:SetText(e.price ~= "" and e.price or T("kostenlos", "free"))
            row.stock:SetText(e.available and e.available >= 0 and string.format(T("Vorrat %d", "Stock %d"), e.available) or "")
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
    -- Bildlauf-Anzeige rechts (goldener Balken: wo man in der Liste ist)
    if #entries > visible then
        local h = list:GetHeight()
        local thumb = math.max(20, h * visible / #entries)
        scrollBar.thumb:SetHeight(thumb)
        scrollBar.thumb:ClearAllPoints()
        scrollBar.thumb:SetPoint("TOP", scrollBar, "TOP", 0, -(h - thumb) * offset / (#entries - visible))
        scrollBar:Show()
    else
        scrollBar:Hide()
    end
    panel.empty:SetShown(#entries == 0)
    -- Reiter, Reparieren, Geld
    for _, t in ipairs(panel.tabs) do
        local on = t.key == tab
        t:SetBackdropBorderColor(on and C.accent[1] or C.border[1], on and C.accent[2] or C.border[2], on and C.accent[3] or C.border[3], 1)
        t:GetFontString():SetTextColor(on and C.accent[1] or 0.9, on and C.accent[2] or 0.9, on and C.accent[3] or 0.9)
    end
    local canRepair = CanMerchantRepair and CanMerchantRepair() and true or false
    local cost = canRepair and GetRepairAllCost and GetRepairAllCost() or 0
    panel.repair:SetShown(canRepair)
    panel.repairOne:SetShown(canRepair and ShowRepairCursor ~= nil)
    panel.guildRepair:SetShown(canRepair and CanGuildBankRepair and CanGuildBankRepair() and true or false)
    panel.junk:SetShown(C_MerchantFrame and C_MerchantFrame.SellAllJunkItems ~= nil)
    -- ausgegraut, wenn nichts zu reparieren ist (bzw. bei der Gildenbank: nicht genug in der Gildenkasse)
    panel.repair:SetUsable(cost > 0 and cost <= GetMoney())
    panel.repairOne:SetUsable(cost > 0)
    local guildMoney = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
    panel.guildRepair:SetUsable(cost > 0 and (not guildMoney or guildMoney < 0 or guildMoney >= cost))
    panel.hideUnusable:SetShown(tab == "buy")
    panel.hideUnusable:SetChecked(ns.GetDB().merchantHideUnusable and true or false)
    local x = 10
    for _, b in ipairs({ panel.repair, panel.repairOne, panel.guildRepair, panel.junk }) do
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, 6)
            x = x + b:GetWidth() + 6
        end
    end
    -- Geld und die Sonderwährungen, die dieser Händler verlangt (Bestand mit Symbol), wie unten bei Blizzard
    local parts = {}
    if GetMerchantCurrencies and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for _, id in ipairs({ GetMerchantCurrencies() }) do
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info and info.iconFileID then
                parts[#parts + 1] = (info.quantity or 0) .. " |T" .. info.iconFileID .. ":14:14:0:0|t"
            end
        end
    end
    parts[#parts + 1] = Money(GetMoney())
    panel.money:SetText(table.concat(parts, "    "))
end
ns.RefreshMerchant = Refresh

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------
local function IconButton(icon, tip, onClick)
    local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
    b:SetSize(28, 28)
    UI.SetFlat(b, C.button)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexture(icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        tip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        if self.usable == false then return end
        onClick()
        C_Timer.After(0.3, function() pcall(Refresh) end)
    end)
    -- benutzbar oder ausgegraut (Tooltip bleibt, Klick tut dann nichts)
    function b:SetUsable(on)
        self.usable = on and true or false
        self.icon:SetDesaturated(not on)
        self:SetAlpha(on and 1 or 0.45)
    end
    return b
end

local function Build(f)
    -- Blizzards Händlerfenster selbst unsichtbar machen (Porträt-Ring, Titelleiste und rotes X ragten sonst über
    -- unsere Ansicht hinaus); es bleibt offen und bedienbar für Verkaufen aus der Tasche
    ns.HideTextures(f)
    for _, key in ipairs({ "NineSlice", "Bg", "Background", "PortraitContainer", "TopTileStreaks", "TitleBg", "Inset",
        "TitleContainer" }) do
        local obj = f[key]
        if type(obj) == "table" and obj.SetAlpha then obj:SetAlpha(0) end
    end
    for _, n in ipairs({ "MerchantFramePortrait", "MerchantFrameTitleText", "MerchantFrameInset", "MerchantFrameCloseButton" }) do
        local obj = G(n)
        if obj and obj.SetAlpha then obj:SetAlpha(0) end
    end
    local blizzClose = f.CloseButton or G("MerchantFrameCloseButton")
    if blizzClose then
        blizzClose:SetAlpha(0)
        blizzClose:EnableMouse(false)
    end
    panel = CreateFrame("Frame", "ForeverSkinMerchant", f, "BackdropTemplate")
    panel:SetAllPoints(f)
    panel:SetFrameStrata(f:GetFrameStrata())
    panel:SetFrameLevel(f:GetFrameLevel() + 100) -- über allen Teilen von Blizzards Fenster
    panel:EnableMouse(true)
    -- Ziehen an der Ansicht = Ziehen am Händlerfenster (dort hängt das Verschieben von ForeverCore samt Merken)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function()
        local fn = f:GetScript("OnDragStart")
        if fn then fn(f, "LeftButton") elseif f:IsMovable() then f:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function()
        local fn = f:GetScript("OnDragStop")
        if fn then fn(f) else f:StopMovingOrSizing() end
    end)
    -- Rahmen, Titelleiste, Visitenkarte wie bei den anderen Fenstern
    ns.SkinWindow(panel)
    ns.ContentBox(panel, FOOT, nil, true)
    local close = UI.CloseButton(panel, function() if CloseMerchant then CloseMerchant() else HideUIPanel(f) end end)
    close:SetPoint("TOPRIGHT", -4, -2)

    -- Reiter und Suche
    panel.tabs = {}
    for i, def in ipairs({ { "buy", T("Händler", "Vendor") }, { "buyback", T("Rückkauf", "Buyback") } }) do
        local t = UI.Button(panel, def[2], 100, function()
            tab = def[1]
            offset = 0
            Refresh()
        end)
        t.key = def[1]
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + (i - 1) * 106, -87)
        panel.tabs[i] = t
    end
    local search = UI.EditBox(panel, 140, 22)
    search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -87)
    local hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 7, 0)
    hint:SetText(T("Suchen …", "Search …"))
    search:SetScript("OnTextChanged", function(self)
        filter = strtrim(self:GetText() or "")
        hint:SetShown(filter == "" and not self:HasFocus())
        offset = 0
        Refresh()
    end)
    search:HookScript("OnEditFocusGained", function() hint:Hide() end)
    search:HookScript("OnEditFocusLost", function() hint:SetShown(filter == "") end)
    search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    panel.search = search
    -- Haken "Nicht benutzbare ausblenden" (gemerkt)
    panel.hideUnusable = UI.Check(panel, 10, -113, T("Nicht benutzbare ausblenden", "Hide unusable"), function(checked)
        ns.GetDB().merchantHideUnusable = checked
        offset = 0
        Refresh()
    end)

    -- Liste mit Mausrad und goldener Bildlauf-Anzeige
    list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, FOOT + 8)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * (IsShiftKeyDown() and 5 or 1)
        Refresh()
    end)
    scrollBar = CreateFrame("Frame", nil, list)
    scrollBar:SetPoint("TOPRIGHT", 0, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollBar:SetWidth(4)
    local track = scrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(C.input[1], C.input[2], C.input[3], 1)
    scrollBar.thumb = scrollBar:CreateTexture(nil, "ARTWORK")
    scrollBar.thumb:SetWidth(4)
    scrollBar.thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.85)
    panel.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("TOP", 0, -20)
    panel.empty:SetText(T("Nichts gefunden", "Nothing found"))

    -- untere Leiste: Reparieren, Gildenbank, Plunder links; Geld rechts
    panel.repair = IconButton("Interface\\Icons\\Trade_BlackSmithing", function(tip)
        tip:AddLine(REPAIR_ALL_ITEMS or T("Alles reparieren", "Repair all"))
        local cost = GetRepairAllCost and GetRepairAllCost()
        if cost and cost > 0 then tip:AddLine(Money(cost), 1, 1, 1) end
    end, function() if RepairAllItems then RepairAllItems() end end)
    panel.repairOne = IconButton("Interface\\Icons\\INV_Hammer_20", function(tip)
        tip:AddLine(REPAIR_AN_ITEM or T("Einzelnen Gegenstand reparieren", "Repair an item"))
        tip:AddLine(T("Danach auf den Gegenstand klicken (Tasche oder Charakter).", "Then click the item (bag or character)."),
            1, 1, 1, true)
    end, function()
        if InRepairMode and InRepairMode() then HideRepairCursor() elseif ShowRepairCursor then ShowRepairCursor() end
    end)
    panel.guildRepair = IconButton("Interface\\Icons\\INV_Shirt_GuildTabard_01", function(tip)
        tip:AddLine(GUILDBANK_REPAIR or T("Über die Gildenbank reparieren", "Repair with guild funds"))
    end, function() if RepairAllItems then RepairAllItems(true) end end)
    panel.junk = IconButton("Interface\\Icons\\INV_Misc_Bag_10", function(tip)
        tip:AddLine(SELL_ALL_JUNK_ITEMS or T("Plunder verkaufen", "Sell junk"))
    end, function() if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then pcall(C_MerchantFrame.SellAllJunkItems) end end)
    panel.money = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.money:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 13)

    -- Blizzards Reiter unter dem Fenster werden nicht gebraucht
    for i = 1, 2 do
        local t = G("MerchantFrameTab" .. i)
        if t then
            t:SetAlpha(0)
            t:EnableMouse(false)
        end
    end
end

local function Card()
    ns.NpcCard(panel, "npc", T("Händler", "Vendor"), function() return T("Händler", "Vendor") end)
end
function ns.RefreshMerchantCard() if panel and panel:IsShown() then pcall(Card) end end

function ns.SetupMerchant()
    local f = G("MerchantFrame")
    if not f or panel then return end
    Build(f)
    local function Size()
        if math.abs(f:GetWidth() - W) > 0.5 then f:SetWidth(W) end
        if math.abs(f:GetHeight() - H) > 0.5 then f:SetHeight(H) end
    end
    f:HookScript("OnShow", function()
        Size()
        tab, offset = "buy", 0
        panel.search:SetText("")
        Card()
        C_Timer.After(0, function() pcall(Size) pcall(Refresh) end)
    end)
    -- Blizzard ändert Größe und Inhalt beim Aktualisieren: danach wieder unsere Größe und neue Liste
    for _, fn in ipairs({ "MerchantFrame_Update", "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, function() pcall(Size) pcall(Refresh) end) end
    end
    local events = CreateFrame("Frame")
    for _, e in ipairs({ "MERCHANT_UPDATE", "PLAYER_MONEY", "GET_ITEM_INFO_RECEIVED", "UPDATE_INVENTORY_DURABILITY",
        "MERCHANT_FILTER_ITEM_UPDATE", "BAG_UPDATE_DELAYED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    local queued = false
    events:SetScript("OnEvent", function()
        if queued or not panel:IsShown() then return end
        queued = true
        C_Timer.After(0.1, function() queued = false pcall(Refresh) end)
    end)
    ns.Scaled(f)
end
