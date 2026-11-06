local addonName, ns = ...

-- GuildBank.lua: eigenes Gildenbankfenster im Forever-Stil, solange die Gildenbank offen ist
-- (Einstellung "replaceGuildBank"). Fächer oben als Symbole, darunter die 98 Plätze des gewählten Fachs.
-- Die Gildenbank hat eigene Funktionen (keine Taschen-Nummern): Klick nimmt auf / legt ab
-- (PickupGuildBankItem), Rechtsklick legt in die eigenen Taschen (AutoStoreGuildBankItem), Shift-Klick verlinkt.
-- Blizzards Gildenbankfenster bleibt offen (sonst endet der Besuch), ist aber unsichtbar und nicht anklickbar.

local L = ns.L
local UI = ForeverHub.UI

local PAD, HEADER, FOOTER = 8, 27, 26
local TABS = 30            -- Zeile mit den Fächern
local COLUMNS, SLOTS = 14, 98
local DEFAULT_POS = { 40, 700 }

local frame, content, moneyText, withdrawText
local slots, tabButtons = {}, {}
local atGuildBank = false
local closing = false

local function Replacing() return ns.db and ns.db.replaceGuildBank end

local function CurrentTab()
    return GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 1
end

---------------------------------------------------------------------------
-- Plätze
---------------------------------------------------------------------------
local function CreateSlot(i)
    local b = CreateFrame("Button", nil, content)
    b:SetSize(ns.SLOT, ns.SLOT)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.quality = b:CreateTexture(nil, "OVERLAY")
    b.quality:SetAllPoints()
    b.quality:SetTexture("Interface\\Common\\WhiteIconFrame")
    ns.AddForeverLook(b, nil)
    b.slot = i
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetGuildBankItem then GameTooltip:SetGuildBankItem(CurrentTab(), self.slot) end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function(self, button)
        local tab = CurrentTab()
        if IsModifiedClick("CHATLINK") then
            local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, self.slot)
            if link then ChatEdit_InsertLink(link) end
        elseif button == "RightButton" then
            if AutoStoreGuildBankItem then AutoStoreGuildBankItem(tab, self.slot) end
        elseif PickupGuildBankItem then
            PickupGuildBankItem(tab, self.slot)
        end
    end)
    b:SetScript("OnDragStart", function(self) if PickupGuildBankItem then PickupGuildBankItem(CurrentTab(), self.slot) end end)
    b:SetScript("OnReceiveDrag", function(self) if PickupGuildBankItem then PickupGuildBankItem(CurrentTab(), self.slot) end end)
    slots[i] = b
    return b
end

local function UpdateSlots()
    local tab = CurrentTab()
    for i = 1, SLOTS do
        local b = slots[i]
        local texture, count, locked, isFiltered, quality
        if GetGuildBankItemInfo then texture, count, locked, isFiltered, quality = GetGuildBankItemInfo(tab, i) end
        b.icon:SetTexture(texture)
        b.icon:SetDesaturated(locked and true or false)
        b.count:SetText(count and count > 1 and count or "")
        local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        b.quality:SetShown(color ~= nil and ns.db.qualityBorder)
        if color then b.quality:SetVertexColor(color.r, color.g, color.b) end
        b:SetAlpha(isFiltered and 0.3 or 1)
    end
end

---------------------------------------------------------------------------
-- Fächer (Symbole oben); ein Klick wechselt das Fach und fragt seinen Inhalt ab
---------------------------------------------------------------------------
local function UpdateTabs()
    local count = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local current = CurrentTab()
    for i = 1, math.max(count, #tabButtons) do
        local t = tabButtons[i]
        if i <= count then
            if not t then
                t = CreateFrame("Button", nil, frame)
                t:SetSize(26, 26)
                t:SetPoint("TOPLEFT", PAD + (i - 1) * 30, -HEADER - 2)
                t.icon = t:CreateTexture(nil, "ARTWORK")
                t.icon:SetPoint("TOPLEFT", 1, -1)
                t.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                ns.AddForeverLook(t, nil)
                t.index = i
                t:SetScript("OnClick", function(self)
                    if SetCurrentGuildBankTab then SetCurrentGuildBankTab(self.index) end
                    if QueryGuildBankTab then QueryGuildBankTab(self.index) end
                    UpdateTabs()
                    UpdateSlots()
                end)
                t:HookScript("OnEnter", function(self)
                    local name = GetGuildBankTabInfo and GetGuildBankTabInfo(self.index)
                    ns.SimpleTip(self, name or "")
                end)
                t:HookScript("OnLeave", ns.HideTip)
                tabButtons[i] = t
            end
            local name, icon, isViewable = GetGuildBankTabInfo(i)
            t.icon:SetTexture(icon)
            t.icon:SetDesaturated(not isViewable)
            t:Show()
            -- gewähltes Fach: goldener Rand
            if i == current then
                t.fbagsEdge:SetBackdropBorderColor(1, 0.82, 0, 1)
            else
                ns.ApplyEdge(t, false)
            end
        elseif t then
            t:Hide()
        end
    end
end

local function UpdateMoney()
    local money = GetGuildBankMoney and GetGuildBankMoney() or 0
    moneyText:SetText(GetMoneyString(money, true))
    local withdraw = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
    -- Gildenmeister (bzw. Rang ohne Grenze): das Spiel meldet dann eine riesige Zahl (2^64) – "unbegrenzt" statt
    -- "1.8.446.744.073.71e+15 Gold"
    if withdraw and withdraw >= 1e13 then
        withdrawText:SetText(L("GUILD_WITHDRAW_LIMIT", L("GUILD_WITHDRAW_UNLIMITED")))
    elseif withdraw and withdraw >= 0 then
        withdrawText:SetText(L("GUILD_WITHDRAW_LIMIT", GetMoneyString(withdraw, true)))
    else
        withdrawText:SetText("")
    end
end

function ns.LayoutGuildBank()
    if not frame or not frame:IsShown() then return end
    UpdateTabs()
    UpdateSlots()
    UpdateMoney()
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local function CloseGuildBank()
    if C_GuildBank and C_GuildBank.CloseGuildBankFrame then pcall(C_GuildBank.CloseGuildBankFrame)
    elseif CloseGuildBankFrame then CloseGuildBankFrame() end
end

local function CreateGuildBank()
    frame = ns.CreateBagWindow("ForeverBagsGuildBank", L("GUILD_TITLE"), "guildPos", DEFAULT_POS)
    local SLOT, gap = ns.SLOT, 2
    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", PAD, -HEADER - TABS)
    local rows = math.ceil(SLOTS / COLUMNS)
    content:SetSize(COLUMNS * SLOT + (COLUMNS - 1) * gap, rows * SLOT + (rows - 1) * gap)
    for i = 1, SLOTS do
        local b = CreateSlot(i)
        -- Blizzards Reihenfolge: Spalte für Spalte (7 Plätze untereinander, 14 Spalten)
        local col, row = math.floor((i - 1) / 7), (i - 1) % 7
        b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SLOT + gap), -row * (SLOT + gap))
    end
    frame:SetSize(content:GetWidth() + 2 * PAD, HEADER + TABS + content:GetHeight() + FOOTER + 2 * PAD)

    -- Fußzeile: Einzahlen / Abheben (Blizzards Eingabefenster), Abhebe-Limit, Gold der Gilde
    local deposit = UI.Button(frame, L("GUILD_DEPOSIT"), 90, function() StaticPopup_Show("GUILDBANK_DEPOSIT") end)
    deposit:SetPoint("BOTTOMLEFT", PAD, PAD)
    local withdraw = UI.Button(frame, L("GUILD_WITHDRAW"), 90, function() StaticPopup_Show("GUILDBANK_WITHDRAW") end)
    withdraw:SetPoint("LEFT", deposit, "RIGHT", 4, 0)
    withdrawText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    withdrawText:SetPoint("LEFT", withdraw, "RIGHT", 8, 0)
    moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moneyText:SetPoint("BOTTOMRIGHT", -PAD - 16, PAD + 4)

    frame:HookScript("OnShow", ns.LayoutGuildBank)
    frame:HookScript("OnHide", function()
        if atGuildBank and not closing then CloseGuildBank() end
    end)
end

local function HideBlizzardGuildBank()
    if _G.GuildBankFrame then ns.HideBlizzardPanel(_G.GuildBankFrame) end
end

local function OnOpened()
    atGuildBank = true
    if not Replacing() then return end
    if not frame then CreateGuildBank() end
    HideBlizzardGuildBank()
    -- Blizzards Gildenbank lädt erst beim ersten Besuch (eigenes Addon) – kurz danach noch einmal
    C_Timer.After(0.1, function() if atGuildBank then HideBlizzardGuildBank() end end)
    C_Timer.After(0.5, function() if atGuildBank then HideBlizzardGuildBank() end end)
    if QueryGuildBankTab then QueryGuildBankTab(CurrentTab()) end
    frame.RestorePosition()
    frame:Show()
    if ns.OpenBags then ns.OpenBags() end
end

local function OnClosed()
    atGuildBank = false
    closing = true
    if frame then frame:Hide() end
    closing = false
    if _G.GuildBankFrame then ns.RestoreBlizzardPanel(_G.GuildBankFrame) end
end

local queued = false
local events = CreateFrame("Frame")
for _, event in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_UPDATE_TABS", "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_WITHDRAWMONEY", "GUILDBANK_ITEM_LOCK_CHANGED",
    "INVENTORY_SEARCH_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
-- Neuere Clients melden das Öffnen über die Interaktions-Ereignisse
pcall(events.RegisterEvent, events, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
pcall(events.RegisterEvent, events, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
events:SetScript("OnEvent", function(_, event, kind)
    local guildType = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
    if event == "GUILDBANKFRAME_OPENED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and guildType and kind == guildType) then
        if not atGuildBank then OnOpened() end
    elseif event == "GUILDBANKFRAME_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and guildType and kind == guildType) then
        if atGuildBank then OnClosed() end
    elseif frame and frame:IsShown() and not queued and event ~= "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        and event ~= "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        queued = true
        C_Timer.After(0.05, function()
            queued = false
            ns.LayoutGuildBank()
        end)
    end
end)
