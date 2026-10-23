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
local LIST_TOP, FOOT = 141, 68        -- Liste ab hier (unter Visitenkarte, Reitern, Filter), Höhe der unteren Leiste
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
                    copper = info.price or 0, -- (Preis je Kauf in Kupfer, für den Gesamtpreis im Mengen-Fenster)
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
-- Rückmeldung beim Klicken (Waren-Zeilen und Knöpfe unten): gedrückt = kurz dunkler, ausgeführt = kurzes goldenes
-- Aufleuchten, bei Käufen dazu rechts "+Anzahl", das nach oben weggleitet
---------------------------------------------------------------------------
local function Feedback(frame)
    if frame.fbPress then return end
    frame.fbPress = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    frame.fbPress:SetPoint("TOPLEFT", 1, -1)
    frame.fbPress:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.fbPress:SetColorTexture(0, 0, 0, 0.3)
    frame.fbPress:Hide()
    frame:HookScript("OnMouseDown", function(self) self.fbPress:Show() end)
    frame:HookScript("OnMouseUp", function(self) self.fbPress:Hide() end)
    frame:HookScript("OnHide", function(self) self.fbPress:Hide() end)
    -- goldenes Aufleuchten
    local glow = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    glow:SetAlpha(0)
    local ag = glow:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.45)
    fade:SetToAlpha(0)
    fade:SetDuration(0.5)
    fade:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function() glow:SetAlpha(0) end)
    frame.fbGlow = ag
    -- "+Anzahl"
    local plus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plus:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    plus:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    plus:SetAlpha(0)
    local pg = plus:CreateAnimationGroup()
    local move = pg:CreateAnimation("Translation")
    move:SetOffset(0, 14)
    move:SetDuration(0.7)
    move:SetSmoothing("OUT")
    local pfade = pg:CreateAnimation("Alpha")
    pfade:SetFromAlpha(1)
    pfade:SetToAlpha(0)
    pfade:SetDuration(0.7)
    pg:SetScript("OnFinished", function() plus:SetAlpha(0) end)
    frame.fbPlus, frame.fbPlusAnim = plus, pg
end

local function Flash(frame, amount)
    if not (frame and frame.fbGlow) then return end
    frame.fbGlow:Stop()
    frame.fbGlow:Play()
    if amount and frame.fbPlus then
        frame.fbPlus:SetText("+" .. amount)
        frame.fbPlusAnim:Stop()
        frame.fbPlusAnim:Play()
    end
end

---------------------------------------------------------------------------
-- Kaufen
---------------------------------------------------------------------------
-- Menge kaufen (in Stück, wie Blizzards Mengen-Fenster): das Spiel erlaubt je Kauf höchstens einen Stapel – größere
-- Mengen darum in mehreren Schritten mit kurzer Pause
local function BuyUnits(index, units)
    local maxStack = math.max(1, GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or 1)
    local remaining = units
    local function Step()
        if remaining <= 0 or not (panel and panel:IsShown()) then return end
        local n = math.min(remaining, maxStack)
        BuyMerchantItem(index, n)
        remaining = remaining - n
        if remaining > 0 then C_Timer.After(0.25, Step) end
    end
    Step()
end

StaticPopupDialogs["FOREVERSKIN_MERCHANT_BUY"] = {
    text = "%s",
    button1 = YES or "Ja", button2 = NO or "Nein",
    OnAccept = function(_, data)
        if not data then return end
        if data.units then BuyUnits(data.index, data.units) else BuyMerchantItem(data.index) end
        Flash(data.row, data.amount)
    end,
    timeout = 0, hideOnEscape = true, whileDead = true,
}

-- Kauf ausführen (units = nil: ein Kauf wie bei Blizzards Rechtsklick); Sonderwährung vorher fragen
local function Purchase(e, units, row)
    local amount = units or math.max(1, e.stack or 1)
    if e.ext then
        -- Sonderwährung (Ehre, Marken …): Rückmeldung erst nach dem Ja
        StaticPopup_Show("FOREVERSKIN_MERCHANT_BUY", string.format(T("%s für %s kaufen?", "Buy %s for %s?"),
            (e.link or e.name) .. (amount > 1 and (" ×" .. amount) or ""), e.price), nil,
            { index = e.index, units = units, row = row, amount = amount })
    else
        if units then BuyUnits(e.index, units) else BuyMerchantItem(e.index) end
        Flash(row, amount)
    end
end

---------------------------------------------------------------------------
-- Menge wählen (Umschalt + Rechtsklick): kleines Fenster im Forever-Stil
---------------------------------------------------------------------------
local amountFrame
local function AmountFrame()
    if amountFrame then return amountFrame end
    local a = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    a:SetSize(250, 138)
    a:SetPoint("CENTER", panel, "CENTER", 0, 20)
    a:SetFrameLevel(panel:GetFrameLevel() + 60)
    a:EnableMouse(true)
    UI.SetFlat(a, C.background)
    local head = a:CreateTexture(nil, "BORDER")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(22)
    head:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
    local line = a:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    ns.OnePixel(line, true)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    a.title = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    a.title:SetPoint("LEFT", head, "LEFT", 8, 0)
    a.title:SetPoint("RIGHT", head, "RIGHT", -8, 0)
    a.title:SetJustifyH("LEFT")
    a.title:SetWordWrap(false)
    -- Menge: −  [Zahl]  +   Max
    a.minus = UI.Button(a, "−", 26)
    a.minus:SetPoint("TOPLEFT", 12, -36)
    a.edit = UI.EditBox(a, 80, 22)
    a.edit:SetPoint("LEFT", a.minus, "RIGHT", 6, 0)
    a.edit:SetNumeric(true)
    a.edit:SetJustifyH("CENTER")
    a.plus = UI.Button(a, "+", 26)
    a.plus:SetPoint("LEFT", a.edit, "RIGHT", 6, 0)
    a.max = UI.Button(a, T("Max", "Max"), 60)
    a.max:SetPoint("LEFT", a.plus, "RIGHT", 10, 0)
    a.total = a:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    a.total:SetPoint("TOPLEFT", a.minus, "BOTTOMLEFT", 0, -12)
    a.total:SetPoint("RIGHT", a, "RIGHT", -12, 0)
    a.total:SetJustifyH("LEFT")
    a.buy = UI.Button(a, T("Kaufen", "Buy"), 100)
    a.buy:SetPoint("BOTTOMRIGHT", -12, 10)
    a.cancel = UI.Button(a, CANCEL or T("Abbrechen", "Cancel"), 100)
    a.cancel:SetPoint("RIGHT", a.buy, "LEFT", -10, 0)
    a:Hide()

    local function Value() return tonumber(a.edit:GetText()) or 0 end
    local function Clamp(v)
        local step = a.step or 1
        v = math.floor(v / step + 0.5) * step
        return math.max(step, math.min(v, a.limit or v))
    end
    local function Update()
        local e = a.entry
        if not e then return end
        local v = Value()
        local cost = (e.copper or 0) * v / math.max(1, e.stack or 1)
        local text = (e.copper and e.copper > 0) and Money(cost, cost > GetMoney() and "|cffff5555" or nil) or e.price
        a.total:SetText(T("Gesamt: ", "Total: ") .. (text or ""))
        a.buy:SetEnabled(v > 0)
    end
    local function Set(v)
        a.edit:SetText(tostring(Clamp(v)))
        Update()
    end
    a.minus:SetScript("OnClick", function() Set(Value() - (a.step or 1)) end)
    a.plus:SetScript("OnClick", function() Set(Value() + (a.step or 1)) end)
    a.max:SetScript("OnClick", function() Set(a.limit or Value()) end)
    a.edit:SetScript("OnTextChanged", function(_, user) if user then Update() end end)
    local function Confirm()
        local e, v = a.entry, Clamp(Value())
        a:Hide()
        if e and v > 0 then Purchase(e, v, a.row) end
    end
    a.buy:SetScript("OnClick", Confirm)
    a.cancel:SetScript("OnClick", function() a:Hide() end)
    a.edit:SetScript("OnEnterPressed", Confirm)
    a.edit:SetScript("OnEscapePressed", function() a:Hide() end)
    a.Update, a.Set = Update, Set
    amountFrame = a
    return a
end

local function AskAmount(e, row)
    local a = AmountFrame()
    a.entry, a.row = e, row
    local step = math.max(1, e.stack or 1)
    -- Obergrenze: so viel, wie das Geld erlaubt (bei Gold-Preis), und der Vorrat des Händlers
    local limit = 999 * step
    if e.copper and e.copper > 0 then limit = math.min(limit, math.floor(GetMoney() / e.copper) * step) end
    if e.available and e.available >= 0 then limit = math.min(limit, e.available * step) end
    a.step, a.limit = step, math.max(step, limit)
    a.title:SetText(e.link or e.name)
    a:Show()
    a.Set(math.max(step, GetMerchantItemMaxStack and GetMerchantItemMaxStack(e.index) or step))
    a.edit:SetFocus()
    a.edit:HighlightText()
end

local function Buy(e, stack, row)
    if e.buyback then
        BuybackItem(e.index)
        Flash(row, e.stack or 1)
        return
    end
    if stack then
        AskAmount(e, row) -- Umschalt: Menge wählen
    else
        Purchase(e, nil, row)
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
            Buy(e, IsShiftKeyDown(), self)
        elseif not e.buyback and PickupMerchantItem then
            PickupMerchantItem(e.index)
        end
    end)
    row:SetScript("OnDragStart", function(self)
        local e = self.entry
        if e and not e.buyback and PickupMerchantItem then PickupMerchantItem(e.index) end
    end)
    Feedback(row)
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
    panel.help:SetText(tab == "buy"
        and T("Rechtsklick: kaufen · Umschalt+Rechtsklick: Menge wählen\nUmschalt+Linksklick: Link in den Chat · Strg+Klick: Anprobe",
            "Right-click: buy · Shift+right-click: choose amount\nShift+left-click: link to chat · Ctrl+click: try on")
        or T("Rechtsklick: zurückkaufen\nUmschalt+Linksklick: Link in den Chat · Strg+Klick: Anprobe",
            "Right-click: buy back\nShift+left-click: link to chat · Ctrl+click: try on"))
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
    -- Sonderwährungen, die dieser Händler verlangt (Bestand mit Symbol), wie unten bei Blizzard – das eigene Gold
    -- steht in der Titelleiste (Stilregel, ns.HeaderGold), hier nicht doppelt
    local parts = {}
    if GetMerchantCurrencies and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for _, id in ipairs({ GetMerchantCurrencies() }) do
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info and info.iconFileID then
                parts[#parts + 1] = (info.quantity or 0) .. " |T" .. info.iconFileID .. ":14:14:0:0|t"
            end
        end
    end
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
        Flash(self) -- kurzes goldenes Aufleuchten als Rückmeldung
        C_Timer.After(0.3, function() pcall(Refresh) end)
    end)
    Feedback(b) -- gedrückt = kurz dunkler
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
    -- kurzer Hinweis zur Bedienung oben in der Fußleiste
    panel.help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.help:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 40)
    panel.help:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 40)
    panel.help:SetJustifyH("CENTER")
    panel.help:SetWordWrap(true) -- zwei Zeilen (eine war zu lang und wurde abgeschnitten)
    panel.help:SetSpacing(2)

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
