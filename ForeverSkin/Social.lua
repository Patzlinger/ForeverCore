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
    if rel then ns.Anchor(obj, point, rel, relPoint, x, y) end
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
    ns.SkinSearchBox(box, { -4, 0, 0, 0 })
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
    -- Oberkante der Innenfläche (Blizzard setzt sie je nach Reiter anders), gemessen vom oberen Fensterrand
    local insetTop = inset and inset:GetTop() and f:GetTop() and math.floor(f:GetTop() - inset:GetTop() + 0.5) or 60
    -- Status-Auswahl links in der Ecke, mittig zwischen goldener Linie (23) und Innenfläche (Blizzard hängt sie an
    -- die Battle.net-Leiste)
    local header = f.FriendsTabHeader
    if header and header.StatusDropdown then
        Anchor(header.StatusDropdown, "LEFT", f, "TOPLEFT", 8, -math.floor((23 + insetTop) / 2 + 0.5))
    end
    -- Reiter oben links in der Ecke der Innenfläche (6 Luft), die Freundesliste darunter
    local system = header and header.TabSystem
    if system and system:IsVisible() and inset then
        Anchor(system, "TOPLEFT", inset, "TOPLEFT", 6, -6)
        local below = insetTop + 6 + math.floor(system:GetHeight() or 24) + 6
        local list = G("FriendsListFrame")
        if list and list.ScrollBox and list.ScrollBox:IsVisible() then ns.Fit(f, list.ScrollBox, below, FOOTER + GAP + 4) end
        local allies = G("RecentAlliesFrame")
        if allies and allies.List and allies.List:IsVisible() then ns.Fit(f, allies.List, below) end
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

---------------------------------------------------------------------------
-- Neues Sozialfenster (SocialUIFrame: Seitenreiter rechts, Battle.net-Leiste, Suche/Filter, Freundes-Karten) – das
-- öffnet Forever mit O. Seitenreiter bleiben Blizzards (wie an der Gruppensuche). Teile nach Art gesucht, weil die
-- Reiter-Seiten (Freunde, Kürzlich, Schnellbeitritt, Anfragen, Schlachtzug …) erst beim Öffnen entstehen.
---------------------------------------------------------------------------
local socialFrames = setmetatable({}, { __mode = "k" }) -- Text-Knöpfe, deren rote Grafiken laufend weg bleiben
local tints = setmetatable({}, { __mode = "k" })        -- [Karte] = eigene Farbton-Fläche
local headArrows = setmetatable({}, { __mode = "k" })   -- [Überschrift] = Pfeil

local function SideTab(b)
    return type(b.SelectedTexture) == "table" and type(b.Icon) == "table" and type(b.Background) == "table"
end

-- Symbol-Knopf (Menü, Einladen …): Blizzards Kasten weg, Symbol bleibt, flache Fläche dahinter
local function SkinSquare(b)
    if not b or done[b] or Forbidden(b) then return end
    done[b] = true
    local keep = {}
    for _, key in ipairs({ "Icon", "ActionIcon" }) do if type(b[key]) == "table" then keep[b[key]] = true end end
    ns.HideTextures(b, keep)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
    ns.Flat(b, C.button, 3)
    ns.Hover(b)
end

-- Trennlinie (Blizzards "perks-divider"): unsichtbar, eigene feine goldene Linie an ihrer Stelle
local function GoldDivider(owner, tex)
    if type(tex) ~= "table" or done[tex] then return end
    done[tex] = true
    tex:SetAlpha(0)
    local line = owner:CreateTexture(nil, "BORDER", nil, 2)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
    line:SetPoint("LEFT", tex, "LEFT", 4, 0)
    line:SetPoint("RIGHT", tex, "RIGHT", -4, 0)
    ns.OnePixel(line, true)
end

-- Gruppen-Überschrift ("Favoriten 1/1", "Freundesliste 1/3"): flacher Balken, rechts feiner Pfeil statt Blizzards
-- Minus/Plus (zugeklappt nach rechts, aufgeklappt nach unten)
local function SkinListHeader(h)
    if done[h] or Forbidden(h) then return end
    done[h] = true
    ns.HideTextures(h)
    ns.Flat(h, C.header)
    ns.Hover(h)
    local cb = h.CollapseButton
    if type(cb) == "table" and not Forbidden(cb) then
        cb:SetAlpha(0)
        local arrow = h:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(10, 10)
        arrow:SetPoint("CENTER", cb, "CENTER")
        arrow:SetVertexColor(0.8, 0.8, 0.82)
        headArrows[h] = arrow
    end
end
local function HeaderArrow(h)
    local arrow, cb = headArrows[h], h.CollapseButton
    if not arrow or type(cb) ~= "table" then return end
    local tex = (cb.GetNormalTexture and cb:GetNormalTexture()) or cb.Icon
    local atlas = tex and tex.GetAtlas and tex:GetAtlas()
    local collapsed = type(atlas) == "string" and (atlas:lower():find("plus") or atlas:lower():find("expand")) and true
        or (h.IsCollapsed and h:IsCollapsed()) or false
    arrow:SetRotation(collapsed and 0 or -math.pi / 2)
end

-- Freundes-Karte: grauer Balken mit feinem Rand (Maus darauf = gold), darüber ein dezenter Farbton nach Art –
-- Battle.net blau, WoW-Freund gold, offline ohne (Blizzard setzt dafür sein Hintergrundbild, das unsichtbar bleibt)
local function CardTint(card)
    local tint = tints[card]
    local atlas = card.Background and card.Background.GetAtlas and card.Background:GetAtlas()
    atlas = type(atlas) == "string" and atlas:lower() or ""
    if atlas:find("battlenet") then
        tint:SetVertexColor(0.10, 0.30, 0.50, 0.35)
    elseif atlas:find("disabled") then
        tint:SetVertexColor(0, 0, 0, 0)
    else
        tint:SetVertexColor(0.45, 0.35, 0.05, 0.25)
    end
end
local function SkinCard(card)
    if not done[card] and not Forbidden(card) then
        done[card] = true
        ns.Hide(card.Background)
        ns.Hide(card.GetHighlightTexture and card:GetHighlightTexture())
        ns.Flat(card, C.button, { 0, 2, 0, 2 })
        ns.Hover(card)
        local tint = card:CreateTexture(nil, "BACKGROUND", nil, -7)
        tint:SetTexture(WHITE)
        tint:SetPoint("TOPLEFT", 1, -3)
        tint:SetPoint("BOTTOMRIGHT", -1, 3)
        tints[card] = tint
        for _, key in ipairs({ "PartyButton", "RAFSummonButton" }) do SkinSquare(card[key]) end
    end
    if tints[card] then CardTint(card) end
end

local function SkinSocialSearch(box)
    if not box or done[box] or Forbidden(box) then return end
    done[box] = true
    ns.Hide(box.NineSlice)
    SkinSearch(box)
end

local function ScanSocial(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] and not SideTab(child) then
            if child.TopDivider then GoldDivider(child, child.TopDivider) end
            if child.BottomDivider then GoldDivider(child, child.BottomDivider) end
            if type(child.ScrollBox) == "table" and child.ScrollBox.ForEachFrame then socialFrames[child.ScrollBox] = "list" end
            -- Auswahl-Knöpfe: der Forever-Client meldet sie nicht immer als "DropdownButton" – darum auch an ihrem
            -- Aufbau erkennen (Menü-Funktion SetupMenu bzw. Pfeil + Text)
            local isDropdown = child:IsObjectType("DropdownButton") or (child:IsObjectType("Button")
                and (type(child.SetupMenu) == "function" or (type(child.Arrow) == "table" and type(child.Text) == "table")))
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif isDropdown and type(child.Icon) == "table" and not child.Text then
                SkinSquare(child) -- (Battle.net-Menü "≡": Symbol-Knopf)
            elseif isDropdown then
                done[child] = true
                ns.SkinDropdown(child) -- (Online-Status, Filter)
            elseif child:IsObjectType("EditBox") and (type(child.searchIcon) == "table" or type(child.NineSlice) == "table") then
                SkinSocialSearch(child)
            elseif child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                if type(text) == "string" and text ~= "" and (type(child.Left) == "table" or child.buttonArtKit) then
                    done[child] = true
                    ns.SkinButton(child)
                    socialFrames[child] = "button"
                end
            elseif depth < 5 then
                ScanSocial(child, depth + 1)
            end
        end
    end
end

local function SocialRows()
    for obj, kind in pairs(socialFrames) do
        if kind == "list" and obj:IsVisible() then
            obj:ForEachFrame(function(entry)
                if type(entry.CollapseButton) == "table" then
                    SkinListHeader(entry)
                    HeaderArrow(entry)
                elseif type(entry.Background) == "table" and (entry.FriendName or entry.PresenceHolder) then
                    SkinCard(entry)
                end
            end)
        elseif kind == "button" and obj:IsVisible() then
            -- (rote Knöpfe: Blizzard setzt die Grafiken teils neu)
            for _, k in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(obj[k]) end
            ns.HideTextures(obj)
        end
    end
end

-- kleine Fenster daneben: Ignorierliste (Fenster mit Titelleiste), Battle.net-Nachricht und "nicht verfügbar"
-- (Dialoge: flach mit goldener Linie oben)
local function SkinSideDialog(d)
    if not d or done[d] or Forbidden(d) then return end
    done[d] = true
    ns.Hide(d.Border)
    ns.Flat(d, C.background)
    local line = d:CreateTexture(nil, "BORDER", nil, -6)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", -1, -1)
    ns.OnePixel(line, true)
    local edit = d.EditBox
    if type(edit) == "table" and not Forbidden(edit) then
        ns.HideTextures(edit)
        ns.Flat(edit, C.input, { -4, 2, -4, 2 })
    end
    for _, key in ipairs({ "UpdateButton", "CancelButton" }) do if d[key] then ns.SkinButton(d[key]) end end
end

local socialSkinned
local function SkinSocialUI()
    local f = G("SocialUIFrame")
    if not f or socialSkinned or Forbidden(f) then return end
    socialSkinned = true
    ns.SkinWindow(f)
    Step("bnet", function()
        local bar = f.BattleNetBar
        if not bar then return end
        ns.Hide(bar.Background)
        local box = bar.ControlsContainer
        if box then
            ns.Hide(box.BattleNetBackground)
            local tag = box.PersonalBattleTagDisplay
            if tag and not Forbidden(tag) then ns.Flat(tag, C.input) end
        end
    end)
    Step("ignore", function()
        local win = f.IgnoreListFrame
        if win and not Forbidden(win) then
            ns.noGold[win] = true
            ns.SkinWindow(win)
            for _, key in ipairs({ "BlockButton", "UnblockButton" }) do if win[key] then ns.SkinButton(win[key]) end end
            if win.ScrollBox then socialFrames[win.ScrollBox] = "list" end
        end
    end)
    Step("dialogs", function()
        SkinSideDialog(f.BattleNetBroadcastFrame)
        SkinSideDialog(f.BattleNetUnavailableNoticeFrame)
    end)
    Step("scan", function() ScanSocial(f, 1) end)
    Step("rows", SocialRows)
    ns.Watch(f)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(ScanSocial, f, 1)
        pcall(SocialRows)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().social then return end
    if not skinned and G("FriendsFrame") then Step("skin", SkinSocial) end
    if not socialSkinned and G("SocialUIFrame") then Step("socialui", SkinSocialUI) end
end)
