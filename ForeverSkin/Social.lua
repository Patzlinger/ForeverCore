-- ForeverSkin – Social.lua: Sozialfenster (FriendsFrame) im Forever-Stil (docs/Fenster-Stil.md), erster Entwurf.
--  * Rahmen flach mit Titelleiste, Innenfläche flach, unten eine Fußleiste mit feiner goldener Linie, darin die Knöpfe
--  * Reiter unten (Kontakte, Wer, Schlachtzug …) und oben (Freunde, Ignoriert …) flach, gewählter gold
--  * Battle.net-Leiste und Status-Auswahl flach; Freunde, Wer-Liste und Ignorierliste als graue Zeilen mit feinem
--    Rand (Maus darauf und gewählt = gold); Blizzards Farbton der Freunde (online/offline) bleibt darüber
--  * Wer: Spaltenköpfe flach, Suchfeld flach; Schlachtzug: Knöpfe und "Alle Assistent" flach
-- Die Schlachtzug-Gruppen selbst (geschützte Einheiten-Knöpfe) und das Fenster "Freunde von Freunden" bleiben Blizzards.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FOOTER = 40

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "social/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" })

-- Ankerpunkt nur neu setzen, wenn er nicht schon so ist (sonst würde das Fenster ständig neu berechnet)
local function Anchor(obj, point, rel, relPoint, x, y)
    if not obj or not rel or Forbidden(obj) then return end
    local p, r, rp, ox, oy = obj:GetPoint(1)
    if obj:GetNumPoints() == 1 and p == point and r == rel and rp == relPoint
        and math.abs((ox or 0) - x) < 0.5 and math.abs((oy or 0) - y) < 0.5 then return end
    obj:ClearAllPoints()
    obj:SetPoint(point, rel, relPoint, x, y)
end

-- Fußleiste: dunklere Fläche mit feiner goldener Linie (wie ns.ContentBox, aber Blizzards Innenfläche bleibt sichtbar)
local footers = setmetatable({}, { __mode = "k" })
local function Footer(f, h)
    if footers[f] then return end
    footers[f] = true
    local foot = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    foot:SetTexture(WHITE)
    foot:SetVertexColor(C.header[1], C.header[2], C.header[3], 1)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(h)
    local line = f:CreateTexture(nil, "BORDER", nil, -6)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
    line:SetPoint("BOTTOMLEFT", foot, "TOPLEFT")
    line:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    ns.OnePixel(line, true)
end

-- Suchfeld (Wer): Blizzards Rahmen weg, flaches Eingabefeld (Lupe, Hinweistext und X bleiben)
local function SkinSearch(box)
    if not box or done[box] or Forbidden(box) then return end
    done[box] = true
    local keep = {}
    for _, key in ipairs({ "searchIcon", "SearchIcon", "Instructions", "clearButton" }) do
        local t = box[key]
        if type(t) == "table" and t.IsObjectType and t:IsObjectType("Texture") then keep[t] = true end
    end
    ns.HideTextures(box, keep)
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid", "Backdrop" }) do ns.Hide(box[key]) end
    ns.Flat(box, C.input, { -4, 0, 0, 0 })
end

local function Buttons(list)
    for _, n in ipairs(list) do
        local b = G(n)
        if b and not Forbidden(b) then ns.SkinButton(b) end
    end
end

-- Reiter oben (Freunde, Kürzlich, Ignoriert …): gewählt = von Blizzard gesperrt bzw. isSelected
local function TabSelected(tab)
    if type(tab.isSelected) == "boolean" then return tab.isSelected end
    return tab.IsEnabled and not tab:IsEnabled()
end
local function SkinTopTabs(f)
    local header = f.FriendsTabHeader
    local system = header and header.TabSystem
    if not system or Forbidden(system) then return end
    for _, tab in ipairs({ system:GetChildren() }) do
        if not done[tab] and not Forbidden(tab) and tab:IsObjectType("Button") then
            local label = tab.GetText and tab:GetText()
            if type(label) == "string" and label ~= "" then
                done[tab] = true
                ns.SkinTab(tab, TabSelected)
            end
        end
    end
end

-- Zeile einer Liste: grauer Balken mit feinem Rand und 2 px Lücke zur nächsten; Blizzards Leucht-Grafik weg
local function SkinRow(row, selected)
    if done[row] or Forbidden(row) then return end
    done[row] = true
    ns.Hide(row.highlight)
    ns.Hide(row.GetHighlightTexture and row:GetHighlightTexture())
    ns.Flat(row, C.button, { 0, 1, 0, 1 })
    ns.Hover(row, selected)
end

local function FriendSelected(row)
    local f = G("FriendsFrame")
    return f and row.buttonType ~= nil and f.selectedFriendType == row.buttonType and f.selectedFriend == row.id
end
local function WhoSelected(row)
    local who = G("WhoFrame")
    return who and row.index ~= nil and who.selectedWho == row.index
end
local function IgnoreSelected(row)
    if not IgnoreList_GetSelected then return false end
    local ok, kind, index = pcall(IgnoreList_GetSelected)
    return ok and kind ~= nil and kind == row.type and index == row.index
end

local function SkinRows(box, test, selected)
    if not (box and box.ForEachFrame) or Forbidden(box) then return end
    box:ForEachFrame(function(row)
        if test(row) then SkinRow(row, selected) end
    end)
end

-- Battle.net-Leiste oben (Name, Kontakte-Knopf) und Status-Auswahl
local function SkinBattlenet(f)
    local header = f.FriendsTabHeader
    local bn = header and header.BattlenetFrame
    if bn and not done[bn] and not Forbidden(bn) then
        done[bn] = true
        ns.HideTextures(bn)
        ns.Flat(bn, C.input)
        local menu = bn.ContactsMenuButton
        if menu and not Forbidden(menu) then
            ns.HideTextures(menu, type(menu.Icon) == "table" and { [menu.Icon] = true } or nil)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                if menu[get] then ns.Hide(menu[get](menu)) end
            end
            ns.Flat(menu, C.button, 2)
            ns.Hover(menu)
        end
    end
    if header and header.StatusDropdown then ns.SkinDropdown(header.StatusDropdown) end
end

-- Wer: Spaltenköpfe als flache Knöpfe, in Spalte 2 die Auswahlliste (Zone/Gilde/Volk)
local function SkinWho()
    for i = 1, 4 do
        local col = G("WhoFrameColumnHeader" .. i)
        if col and not done[col] and not Forbidden(col) then
            done[col] = true
            ns.SkinButton(col)
            ns.Refit(col, { 1, 4, 1, 4 })
        end
    end
    local dd = G("WhoFrameDropdown")
    if dd and not Forbidden(dd) then
        ns.Hide(dd.TabHighlight)
        ns.SkinDropdown(dd)
    end
    SkinSearch(G("WhoFrameEditBox"))
    local inset = G("WhoFrameListInset")
    if inset and not Forbidden(inset) then
        ns.Hide(inset.NineSlice)
        ns.Hide(inset.Bg)
    end
end

-- Schlachtzug (Blizzards RaidFrame hängt nur, solange der Reiter offen ist, im Sozialfenster)
local function SkinRaid()
    Buttons({ "RaidFrameConvertToRaidButton", "RaidFrameRaidInfoButton" })
    local cb = G("RaidFrameAllAssistCheckButton")
    if cb and not Forbidden(cb) then ns.SkinCheck(cb) end
end

-- Ignorierliste (eigenes kleines Fenster rechts am Sozialfenster)
local function SkinIgnore(f)
    local win = f.IgnoreListWindow
    if not win or done[win] or Forbidden(win) then return end
    done[win] = true
    ns.noGold[win] = true
    ns.SkinWindow(win)
    Footer(win, 36)
    if win.UnignorePlayerButton then ns.SkinButton(win.UnignorePlayerButton) end
    ns.Watch(win)
end

-- Laufleisten in allen Unterrahmen gold
local function SkinBars(frame, depth)
    if not frame or Forbidden(frame) then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                if not done[child] then
                    done[child] = true
                    ns.SkinScrollBar(child)
                end
            elseif depth < 5 then
                SkinBars(child, depth + 1)
            end
        end
    end
end

-- Reiter unten: flach, gewählter gold, 8 px Abstand (nur sichtbare Reiter, Blizzard blendet z. B. Schnellbeitritt aus)
local function SkinBottomTabs(f)
    for i = 1, 6 do
        local tab = G("FriendsFrameTab" .. i)
        if tab and not done[tab] and not Forbidden(tab) then
            done[tab] = true
            ns.SkinTab(tab, function(t)
                return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) == t:GetID()
            end)
        end
    end
end

-- feste Plätze (Blizzard setzt beim Reiterwechsel einiges neu): Innenflächen enden über der Fußleiste, Knöpfe
-- mittig darin, 10 vom Rand, 8 dazwischen
local GAP = 8 -- Luft zwischen Innenfläche und goldener Linie der Fußleiste
local function Place(f)
    local y = FOOTER / 2
    local inset = f.Inset or G("FriendsFrameInset")
    if inset then ns.Fit(f, inset, nil, FOOTER + GAP, nil, true) end
    local whoInset = G("WhoFrameListInset")
    if whoInset and whoInset:IsVisible() then ns.Fit(f, whoInset, nil, FOOTER + GAP, nil, true) end
    -- Listen, die Blizzard nicht an der Innenfläche, sondern am Fenster aufhängt (Schnellbeitritt), enden ebenfalls
    -- über der Fußleiste (die Laufleiste hängt an der Liste und wandert mit)
    local quick = G("QuickJoinFrame")
    local quickBox = quick and quick.ScrollBox
    if quickBox and quickBox:IsVisible() then ns.Fit(f, quickBox, nil, FOOTER + GAP + 4) end
    -- Status-Auswahl ganz links zwischen Titelleiste und Innenfläche (Blizzard hängt sie an die Battle.net-Leiste)
    local header = f.FriendsTabHeader
    if header and header.StatusDropdown then Anchor(header.StatusDropdown, "LEFT", f, "TOPLEFT", 10, -53) end
    -- Reiter oben in die Innenfläche eingerückt, die Freundesliste darunter
    local system = header and header.TabSystem
    if system and system:IsVisible() then
        Anchor(system, "TOPLEFT", f, "TOPLEFT", 12, -90)
        local list = G("FriendsListFrame")
        if list and list.ScrollBox and list.ScrollBox:IsVisible() then ns.Fit(f, list.ScrollBox, 120, FOOTER + GAP + 4) end
        local allies = G("RecentAlliesFrame")
        if allies and allies.List and allies.List:IsVisible() then ns.Fit(f, allies.List, 120) end
    end
    -- Suchfeld (Wer) wie bei Blizzard knapp über der Innenflächen-Unterkante
    local edit = G("WhoFrameEditBox")
    if edit and not Forbidden(edit) and edit:GetNumPoints() == 2 then
        local parent = edit:GetParent()
        local p1, _, _, x1, y1 = edit:GetPoint(1)
        local p2, _, _, x2 = edit:GetPoint(2)
        local want = FOOTER + GAP + 6
        if math.abs((y1 or 0) - want) > 0.5 then
            edit:ClearAllPoints()
            edit:SetPoint(p1, parent, p1, x1, want)
            edit:SetPoint(p2, parent, p2, x2, want)
        end
    end
    Anchor(G("FriendsFrameAddFriendButton"), "LEFT", f, "BOTTOMLEFT", 10, y)
    Anchor(G("FriendsFrameSendMessageButton"), "RIGHT", f, "BOTTOMRIGHT", -10, y)
    local invite, add, refresh = G("WhoFrameGroupInviteButton"), G("WhoFrameAddFriendButton"), G("WhoFrameWhoButton")
    Anchor(invite, "RIGHT", f, "BOTTOMRIGHT", -10, y)
    Anchor(add, "RIGHT", invite, "LEFT", -8, 0)
    Anchor(refresh, "RIGHT", add, "LEFT", -8, 0)
    local raid = G("RaidFrame")
    if raid and raid:GetParent() == f then
        Anchor(G("RaidFrameConvertToRaidButton"), "RIGHT", raid, "BOTTOMRIGHT", -10, y)
        -- obere Zeile ("Alle Assistent", Rollen-Anzahl, Info) mittig zwischen goldener Linie (23) und Innenfläche (60)
        Anchor(G("RaidFrameAllAssistCheckButton"), "LEFT", raid, "TOPLEFT", 58, -42)
        if raid.RoleCount then Anchor(raid.RoleCount, "CENTER", raid, "TOP", 12, -42) end
        Anchor(G("RaidFrameRaidInfoButton"), "RIGHT", raid, "TOPRIGHT", -10, -42)
        local notIn = raid.RaidFrameNotInRaid
        local desc = notIn and notIn.ScrollingDescription
        if desc and desc:IsVisible() then ns.Fit(f, desc, nil, FOOTER + GAP + 4, nil, true) end
    end
    local join = quick and quick.JoinQueueButton
    if join then Anchor(join, "RIGHT", f, "BOTTOMRIGHT", -10, y) end
    -- Reiter unten direkt am Fenster angeheftet (wie beim Briefkasten), 8 Abstand untereinander
    local prev
    for i = 1, 6 do
        local tab = G("FriendsFrameTab" .. i)
        if tab and tab:IsShown() then
            if prev then Anchor(tab, "LEFT", prev, "RIGHT", 8, 0) else Anchor(tab, "TOPLEFT", f, "BOTTOMLEFT", 6, 1) end
            pcall(ns.CenterText, tab)
            prev = tab
        end
    end
    local win = f.IgnoreListWindow
    local unignore = win and win.UnignorePlayerButton
    if unignore then Anchor(unignore, "CENTER", win, "BOTTOM", 0, 18) end
end

local function Rows(f)
    local list = G("FriendsListFrame")
    SkinRows(list and list.ScrollBox, function(row) return type(row.travelPassButton) == "table" end, FriendSelected)
    local who = G("WhoFrame")
    SkinRows(who and who.ScrollBox, function(row) return type(row.Name) == "table" and type(row.Level) == "table" end,
        WhoSelected)
    local win = f.IgnoreListWindow
    SkinRows(win and win.ScrollBox, function(row) return type(row.name) == "table" end, IgnoreSelected)
end

local skinned
local function SkinSocial()
    local f = G("FriendsFrame")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.SkinWindow(f)
    Footer(f, FOOTER)
    Step("tabs", function() SkinBottomTabs(f) SkinTopTabs(f) end)
    Step("battlenet", function() SkinBattlenet(f) end)
    Step("buttons", function()
        Buttons({ "FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton", "WhoFrameGroupInviteButton",
            "WhoFrameAddFriendButton", "WhoFrameWhoButton" })
        local quick = G("QuickJoinFrame")
        if quick and quick.JoinQueueButton then ns.SkinButton(quick.JoinQueueButton) end -- (Beitrittsanfrage)
    end)
    Step("who", SkinWho)
    Step("raid", SkinRaid)
    Step("ignore", function() SkinIgnore(f) end)
    Step("bars", function() SkinBars(f, 1) end)
    Step("rows", function() Rows(f) end)
    Step("place", function() Place(f) end)
    ns.Watch(f)
    f:HookScript("OnShow", function() C_Timer.After(0, function() pcall(Place, f) pcall(Rows, f) end) end)
    -- solange offen: neue Zeilen (Listen holen sie beim Blättern nach), Reiter, Schlachtzug und Plätze prüfen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        if type(f.NineSlice) == "table" then ns.Hide(f.NineSlice) end
        pcall(SkinTopTabs, f)
        pcall(SkinRaid)
        pcall(SkinBars, f, 1)
        pcall(Rows, f)
        pcall(Place, f)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if skinned or not ns.GetDB().social or not G("FriendsFrame") then return end
    Step("skin", SkinSocial)
end)
