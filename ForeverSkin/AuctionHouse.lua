-- ForeverSkin – AuctionHouse.lua: Auktionshaus (AuctionHouseFrame, Blizzards modernes Auktionshaus) im Forever-Stil
-- (docs/Fenster-Stil.md), erster Entwurf.
--  * Rahmen flach mit Titelleiste, links "Dein Gold" (Blizzards Geldleiste unten unsichtbar – doppelt)
--  * Reiter unten (Kaufen, Verkaufen, Auktionen) flach, gewählter gold, direkt am Fenster
--  * Suchleiste: Favoriten-Stern und Suchfeld flach, Filter als flache Auswahlliste, "Suchen" flach
--  * Kategorien links: flache Fläche, je Kategorie ein grauer Balken (Maus darauf und gewählt = gold)
--  * Ergebnislisten: flache Fläche statt Blizzards Hintergrundbild, Spaltenköpfe als flache Knöpfe (Sortierpfeil
--    bleibt), je Zeile ein grauer Balken mit feinem Rand (Maus darauf und gewählt = gold)
--  * alle Text-Knöpfe flach, Auswahllisten flach, Laufleisten gold
-- Die Teile werden nach ihrer Art gesucht (das Auktionshaus baut viele Seiten), nicht nach Namen. Geld-Eingaben und
-- der Gegenstands-Platz beim Verkaufen bleiben vorerst Blizzards. Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "auction/" .. what, err) end
end

local SCALE = 1.05 -- Auktionshaus 5 % größer als bei Blizzard
local done = setmetatable({}, { __mode = "k" })
local textButtons = setmetatable({}, { __mode = "k" }) -- Text-Knöpfe, deren Grafiken laufend unsichtbar bleiben

local function Anchor(obj, point, rel, relPoint, x, y)
    if rel then ns.Anchor(obj, point, rel, relPoint, x, y) end
end

-- Text-Knopf flach; Blizzard setzt die roten Grafiken (z. B. "Suchen", "Kaufen") teils neu – darum laufend
local function FlatButton(b)
    ns.SkinButton(b)
    textButtons[b] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

-- Suchfeld: Blizzards Rahmen weg, flaches Eingabefeld (Lupe, Hinweistext und X bleiben)
local function SkinSearch(box)
    if not box or done[box] or Forbidden(box) then return end
    done[box] = true
    ns.SkinSearchBox(box, { -4, 0, 0, 0 })
end

-- Symbol-Knopf (Favoriten-Stern, Aktualisieren): Blizzards Kasten weg, Symbol bleibt, flache Fläche dahinter
local function SkinSquare(b)
    if not b or done[b] or Forbidden(b) then return end
    done[b] = true
    local icon = b.Icon or b.icon
    ns.HideTextures(b, type(icon) == "table" and { [icon] = true } or nil)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
    ns.Flat(b, C.button, 2)
    ns.Hover(b)
end

-- Kategorie links: grauer Balken, gewählt (Blizzards "SelectedTexture" sichtbar) bzw. Maus darauf = gold
local function CategorySelected(b) return type(b.SelectedTexture) == "table" and b.SelectedTexture:IsShown() end
-- Blizzards Grafiken der Kategorie unsichtbar – auch immer wieder: beim Auf-/Zuklappen setzt Blizzard sie neu (z. B.
-- die dunkleren Unterkategorien), sonst erschien nach dem ersten Klick Blizzards Aussehen
local function HideCategoryArt(b)
    for _, key in ipairs({ "Lines", "NormalTexture", "HighlightTexture", "SelectedTexture" }) do ns.Hide(b[key]) end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end
local function SkinCategory(b)
    if done[b] or Forbidden(b) then return end
    done[b] = true
    HideCategoryArt(b)
    ns.Flat(b, C.button, { 0, 1, 0, 1 })
    ns.Hover(b, CategorySelected)
end

-- Ältere Auswahlliste (UIDropDownMenuTemplate, z. B. "Dauer" beim Verkaufen): Rahmen ohne eigenen Knopf-Typ, mit
-- Left/Middle/Right-Grafik und einem Pfeil-Knopf (.Button) – flach wie unsere Auswahllisten, eigener feiner Pfeil
local function SkinOldDropdown(dd)
    if done[dd] or Forbidden(dd) then return end
    done[dd] = true
    for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(dd[key]) end
    local name = dd:GetName()
    if name then for _, s in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(G(name .. s)) end end
    local button = dd.Button
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    local look = ns.Flat(dd, C.button)
    if look then
        -- sichtbare Fläche: wie Blizzards Kasten (die Vorlage hat links und oben/unten leeren Rand)
        look.fill:ClearAllPoints()
        look.fill:SetPoint("TOPLEFT", dd, "TOPLEFT", 18, -2)
        look.fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        local arrow = dd:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(10, 10)
        arrow:SetPoint("RIGHT", look.fill, "RIGHT", -8, 0)
        arrow:SetRotation(-math.pi / 2)
        arrow:SetVertexColor(0.8, 0.8, 0.82)
        look.mine[arrow] = true
    end
    ns.Hover(dd)
    if dd.Text and dd.Text.SetTextColor then dd.Text:SetTextColor(0.95, 0.95, 0.95) end
end

-- Reiter innerhalb einer Seite (z. B. "Auktionen" / "Gebote"): flach, Text mittig, TAB_UP höher als bei Blizzard
-- (Luft zum Kasten darunter); gezählt wird je Reiter einmal auf Blizzards Lage
local TAB_UP = 4
local innerTabs = setmetatable({}, { __mode = "k" })
local fillInset = setmetatable({}, { __mode = "k" }) -- [Reiter] = zuletzt gesetzter Ausgleich unserer Fläche
local function TabSelectedInner(t)
    if type(t.isSelected) == "boolean" then return t.isSelected end
    return t.IsEnabled and not t:IsEnabled()
end
local raised = setmetatable({}, { __mode = "k" }) -- [Reiter] = von uns gesetztes y
local function RaiseTab(tab)
    if tab:GetNumPoints() ~= 1 or not ns.CanMove(tab) then return end
    local p, rel, rp, x, y = tab:GetPoint(1)
    if innerTabs[rel] then return end -- (hängt am Reiter davor: rutscht mit)
    if raised[tab] and math.abs((y or 0) - raised[tab]) < 0.01 then return end
    raised[tab] = (y or 0) + TAB_UP
    tab:SetPoint(p, rel, rp, x, (y or 0) + TAB_UP)
end

-- Zeile einer Ergebnisliste: grauer Balken mit feinem Rand (statt Blizzards Streifen), gewählt bzw. Maus darauf gold
local function RowSelected(row) return type(row.SelectedHighlight) == "table" and row.SelectedHighlight:IsShown() end
local function SkinRow(row)
    if done[row] or Forbidden(row) then return end
    done[row] = true
    for _, key in ipairs({ "NormalTexture", "HighlightTexture", "SelectedHighlight" }) do ns.Hide(row[key]) end
    ns.Hide(row.GetNormalTexture and row:GetNormalTexture())
    ns.Flat(row, C.button, { 0, 1, 0, 1 })
    ns.Hover(row, RowSelected)
end

-- Spaltenkopf ("Preis", "Name" …): flacher Knopf, der Sortierpfeil bleibt (gold)
local function SkinHeader(h)
    if done[h] or Forbidden(h) then return end
    done[h] = true
    ns.SkinButton(h)
    local arrow = h.Arrow
    if type(arrow) == "table" and arrow.SetAlpha then
        arrow:SetAlpha(1)
        arrow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    end
end

-- Fläche (Liste, Seite) mit Blizzards Hintergrundbild und Innenrahmen: beides weg, flache Fläche
local function SkinPanel(frame)
    if done[frame] or Forbidden(frame) then return end
    done[frame] = true
    ns.Hide(frame.Background)
    ns.Hide(frame.NineSlice)
    ns.Flat(frame, C.panel)
end

-- Listen (Kategorien, Ergebnisse): Zeilen holt Blizzard beim Blättern nach – solange offen, neue umgestalten
local lists = setmetatable({}, { __mode = "k" }) -- [ScrollBox] = "category" | "items"
local function Rows()
    for box, kind in pairs(lists) do
        if box:IsVisible() and box.ForEachFrame then
            box:ForEachFrame(function(entry)
                if kind == "category" then
                    if type(entry.SelectedTexture) == "table" then SkinCategory(entry) end
                    if done[entry] then HideCategoryArt(entry) end
                elseif type(entry.SelectedHighlight) == "table" or type(entry.HighlightTexture) == "table" then
                    SkinRow(entry)
                end
            end)
        end
    end
end

-- alle Seiten durchsuchen: Flächen, Listen, Spaltenköpfe, Laufleisten, Auswahllisten, Suchfelder, Text-Knöpfe
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            local name = (child:GetName() or ""):lower()
            if type(child.NineSlice) == "table" and not child:IsObjectType("Button") then
                ns.Hide(child.NineSlice)
                if type(child.Background) == "table" and child.Background.IsObjectType
                    and child.Background:IsObjectType("Texture") then SkinPanel(child) end
            end
            if type(child.HeaderContainer) == "table" and type(child.ScrollBox) == "table" then
                lists[child.ScrollBox] = "items"
                for _, h in ipairs({ child.HeaderContainer:GetChildren() }) do
                    if h:IsObjectType("Button") then SkinHeader(h) end
                end
            end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("DropdownButton") or type(child.SetupMenu) == "function" then
                done[child] = true
                ns.SkinDropdown(child)
            elseif not child:IsObjectType("Button") and type(child.Button) == "table" and type(child.Text) == "table"
                and (type(child.Left) == "table" or type(child.Middle) == "table") then
                SkinOldDropdown(child) -- (ältere Auswahlliste, z. B. "Dauer")
            elseif child:IsObjectType("EditBox") and (type(child.searchIcon) == "table" or type(child.SearchIcon) == "table") then
                SkinSearch(child)
            elseif child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                local key = ((ns.KeyOf(frame, child) or "") .. "|" .. name):lower()
                local isTab = type(child.SetTabSelected) == "function"
                    or (key:find("tab") and not key:find("table") and depth > 1) -- (Kaufen/Verkaufen/Auktionen: Stufe 1)
                if type(text) == "string" and text ~= "" and isTab and not (key:find("buytab") or key:find("selltab")
                    or key:find("|auctionstab") or key:find("^auctionstab")) then
                    -- Reiter innerhalb einer Seite ("Auktionen" / "Gebote")
                    done[child] = true
                    ns.SkinTab(child, function(t)
                        if type(t.isSelected) == "boolean" then return t.isSelected end
                        return t.IsEnabled and not t:IsEnabled()
                    end)
                    innerTabs[child] = true
                elseif type(text) == "string" and text ~= "" and type(child.Left) == "table" and type(child.Right) == "table"
                    and not name:find("money") then
                    done[child] = true
                    FlatButton(child)
                end
            elseif depth < 6 then
                Scan(child, depth + 1)
            end
        end
    end
end

local function Place(f)
    -- Geldleiste unten unsichtbar (Kontostand steht oben links in der Titelleiste); ihr Platz bleibt (Blizzard hängt
    -- Seiten daran auf)
    for _, key in ipairs({ "MoneyFrameInset", "MoneyFrameBorder" }) do
        local obj = f[key]
        if type(obj) == "table" and obj:GetAlpha() > 0 then obj:SetAlpha(0) end
    end
    -- Reiter direkt am Fenster angeheftet, 8 Abstand – auf gleicher Höhe wie weitere Reiter anderer Addons daneben
    -- (z. B. Auctionator: deren Oberkante zählt), sonst 1 unter dem Fenster
    -- Die Knöpfe selbst bleiben fest (1 unter dem Fenster): Auctionators Reiter hängen an unseren – sie an deren Höhe
    -- zu schieben zog jene mit (die Reiter wanderten Bild für Bild). Nur unsere Fläche wird auf Auctionators Höhe gesetzt.
    local tabY = 1
    local bottom = f:GetBottom()
    local function FindForeignTab(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            local name = not Forbidden(child) and child:GetName()
            if name and name:find("Auctionator") and child:IsObjectType("Button") and child:IsShown()
                and child:GetTop() and bottom and child:GetTop() - bottom < 40 then
                return child
            end
            if depth < 2 and not Forbidden(child) then
                local found = FindForeignTab(child, depth + 1)
                if found then return found end
            end
        end
    end
    local foreign = FindForeignTab(f, 1)
    local prev
    for _, key in ipairs({ "BuyTab", "SellTab", "AuctionsTab" }) do
        local tab = f[key]
        if tab and tab:IsShown() then
            if prev then Anchor(tab, "LEFT", prev, "RIGHT", 8, 0) else Anchor(tab, "TOPLEFT", f, "BOTTOMLEFT", 6, tabY) end
            ns.HideTextures(tab) -- (Blizzard zeigt beim Umschalten seine Reiter-Grafiken wieder)
            -- unsere Fläche auf die Höhe der fremden Reiter (nur die Fläche – der Knopf bleibt, siehe oben)
            local d = 0
            if foreign and foreign:GetTop() and tab:GetTop() then d = math.floor(foreign:GetTop() - tab:GetTop() + 0.5) end
            local key2 = "b" .. d
            if fillInset[tab] ~= key2 then
                fillInset[tab] = key2
                ns.Flat(tab, C.button, { 0, -d, 0, d })
                local selected = TabSelectedInner(tab) -- (gleiche Regel wie TabSelected weiter unten)
                ns.EdgeColor(tab, selected and C.accent or C.border, selected and 0.9 or 1)
            end
            pcall(ns.CenterText, tab)
            prev = tab
        end
    end
    -- Reiter innerhalb der Seiten: Text mittig, etwas höher (Luft zum Kasten)
    local groups = {}
    for tab in pairs(innerTabs) do
        if tab:IsVisible() then
            ns.HideTextures(tab)
            pcall(RaiseTab, tab)
            local parent = tab:GetParent()
            groups[parent] = groups[parent] or {}
            table.insert(groups[parent], tab)
        end
    end
    -- alle Reiter einer Seite gleich hoch und auf gleicher Höhe wie ein nicht gewählter (Blizzard setzt den gewählten
    -- tiefer und größer – "Auktionen" sah dann anders aus als "Gebote"). Nur unsere Fläche wird ausgerichtet (Blizzards
    -- Knopf bleibt, wo er ist – die Reiter hängen aneinander, Verschieben zog die anderen mit)
    for _, list in pairs(groups) do
        local ref
        for _, tab in ipairs(list) do
            if not TabSelectedInner(tab) then ref = tab break end
        end
        local refTop, refBottom = ref and ref:GetTop(), ref and ref:GetBottom()
        for _, tab in ipairs(list) do
            local top, bot = tab:GetTop(), tab:GetBottom()
            local t, b = 0, 0
            if ref and refTop and refBottom and top and bot then
                t, b = math.floor(top - refTop + 0.5), math.floor(refBottom - bot + 0.5)
            end
            local key = t .. ":" .. b
            if fillInset[tab] ~= key then
                fillInset[tab] = key
                ns.Flat(tab, C.button, { 0, t, 0, b })
                local selected = TabSelectedInner(tab)
                ns.EdgeColor(tab, selected and C.accent or C.border, selected and 0.9 or 1)
            end
            pcall(ns.CenterText, tab)
        end
    end
    -- rote Knöpfe flach halten
    for b in pairs(textButtons) do
        if b:IsVisible() then
            for _, k in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[k]) end
            ns.HideTextures(b)
        end
    end
end

local function TabSelected(tab)
    if type(tab.isSelected) == "boolean" then return tab.isSelected end
    return tab.IsEnabled and not tab:IsEnabled()
end

local skinned
local function SkinAuctionHouse()
    local f = G("AuctionHouseFrame")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.SkinWindow(f)
    Step("tabs", function()
        for _, key in ipairs({ "BuyTab", "SellTab", "AuctionsTab" }) do
            if f[key] then ns.SkinTab(f[key], TabSelected) end
        end
    end)
    Step("search", function()
        local bar = f.SearchBar
        if not bar then return end
        SkinSquare(bar.FavoritesSearchButton)
        SkinSearch(bar.SearchBox)
        if bar.FilterButton then ns.SkinDropdown(bar.FilterButton) end
        if bar.SearchButton then FlatButton(bar.SearchButton) end
    end)
    Step("categories", function()
        local list = f.CategoriesList
        if not list then return end
        SkinPanel(list)
        if list.ScrollBox then lists[list.ScrollBox] = "category" end
    end)
    Step("scan", function() Scan(f, 1) end)
    Step("rows", Rows)
    Step("place", function() Place(f) end)
    -- Standard 5 % größer (auf Wunsch) – beim Öffnen, außerhalb des Kampfes
    local function Scale()
        if not InCombatLockdown() and math.abs((f:GetScale() or 1) - SCALE) > 0.001 then f:SetScale(SCALE) end
    end
    Scale()
    f:HookScript("OnShow", Scale)
    -- Nach jedem Klick sofort nachsehen (und im nächsten Bild noch einmal): Blizzard setzt beim Klicken Reiter- und
    -- Kategorie-Grafiken neu – sonst waren sie bis zum nächsten Durchgang kurz zu sehen
    local function Refresh()
        if not f:IsVisible() then return end
        pcall(Scan, f, 1)
        pcall(Rows)
        pcall(Place, f)
    end
    local clicks = CreateFrame("Frame", nil, f)
    clicks:RegisterEvent("GLOBAL_MOUSE_UP")
    clicks:SetScript("OnEvent", function()
        Refresh()
        C_Timer.After(0, Refresh)
    end)
    ns.Watch(f)
    -- Blizzard baut Seiten beim Reiterwechsel und Suchen; solange offen, neue Teile umgestalten
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.2) then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(Scan, f, 1)
        pcall(Rows)
        pcall(Place, f)
        local refresh = nil
        for box in pairs(lists) do
            local owner = box:GetParent()
            refresh = owner and owner.RefreshFrame and owner.RefreshFrame.RefreshButton
            if refresh then pcall(SkinSquare, refresh) end
        end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if skinned or not ns.GetDB().auction or not G("AuctionHouseFrame") then return end
    Step("skin", SkinAuctionHouse)
end)
