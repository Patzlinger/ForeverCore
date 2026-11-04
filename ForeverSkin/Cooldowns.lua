-- ForeverSkin – Cooldowns.lua: Abklingzeiten-Manager (CooldownViewerSettings) im Forever-Stil (docs/Fenster-Stil.md).
-- Flacher Rahmen mit Titelleiste, Spezialisierungs-Symbol klein links, Seitenreiter als flache Kästchen, ohne
-- Suchleiste, Kategorie-Überschriften (auch auf der Gruppen-Buff-Seite) als flache Balken mit feinem Pfeil, Zauber
-- als Plätze wie in ForeverBags, Balken-Einträge flach, Fußleiste mit goldener Linie (Layout-Auswahl,
-- "Änderungen rückgängig"). Die Layout-Dialoge bleiben vorerst Blizzards.
-- Symbole können im Kampf gesperrt sein: wir lesen sie nie, sondern versetzen nur ihre Ränder.
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FOOTER = 34 -- Höhe der Fußleiste
local BOX_TOP = 64 -- obere Kante des Inhaltskastens (unter Suchleiste)

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "cooldowns/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" }) -- schon umgestaltete Teile
local arrows = setmetatable({}, { __mode = "k" }) -- [Überschrift] = unser Pfeil

-- Seitenreiter (Zauber, Auren, Gruppen-Buffs): flaches Kästchen, das Symbol bleibt; gewählt = goldener Rand
local function TabSelected(tab)
    local sel = tab.SelectedTexture
    if type(sel) == "table" and sel.IsShown then return sel:IsShown() end
    return tab.GetChecked and tab:GetChecked() or false
end
local function SkinSideTab(tab)
    if done[tab] or Forbidden(tab) then return end
    done[tab] = true
    local keep = {}
    for _, key in ipairs({ "Icon", "Mask", "NewOptionsFrame" }) do
        if type(tab[key]) == "table" then keep[tab[key]] = true end
    end
    ns.HideTextures(tab, keep)
    for _, key in ipairs({ "Background", "SelectedTexture", "TabGlow", "HighlightTexture" }) do ns.Hide(tab[key]) end
    ns.Flat(tab, ns.C.background, 2)
    ns.Hover(tab, TabSelected)
end

-- Kategorie-Überschrift ("Wichtig", "Nützlich" …): flacher Balken, Titel gold, rechts feiner Pfeil
-- (zugeklappt nach rechts, aufgeklappt nach unten)
local function SkinHeader(header)
    if done[header] or Forbidden(header) then return end
    done[header] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
        ns.Hide(header[key])
    end
    ns.Flat(header, ns.C.header)
    ns.Hover(header)
    local arrow = header:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetVertexColor(0.8, 0.8, 0.82)
    arrows[header] = arrow
end

-- (Kategorien fragen wir über IsCollapsed, die Abschnitte der Gruppen-Buff-Seite merken es nur in isCollapsed)
local function HeaderArrow(header)
    local arrow = arrows[header]
    local cat = header:GetParent()
    if not arrow or not cat then return end
    local collapsed = cat.isCollapsed
    if cat.IsCollapsed then
        local ok, value = pcall(cat.IsCollapsed, cat)
        collapsed = ok and value
    end
    arrow:SetRotation(collapsed and 0 or -math.pi / 2)
end

-- Zauber-Platz wie in ForeverBags: dunkles Feld, 1-px-Rand, Maus darauf = gold, Symbol 1 px eingerückt.
-- Balken-Einträge: der Platz nur um das Symbol links, der Balken daneben flach (Füllung bleibt Blizzards Farbe)
local function SkinItem(item)
    if done[item] or Forbidden(item) or type(item.Icon) ~= "table" then return end
    done[item] = true
    ns.Hide(item.Highlight)
    local icon = item.Icon
    local bar = item.Bar
    if type(bar) == "table" and bar.GetStatusBarTexture then
        local w = math.floor((item:GetWidth() or 317) + 0.5)
        ns.Flat(item, { 0.06, 0.06, 0.08, 0.85 }, { 0, 0, math.max(0, w - 38), 0 })
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetSize(36, 36)
        local fill = bar.FillTexture or bar:GetStatusBarTexture()
        local keep = fill and { [fill] = true } or nil
        ns.HideTextures(bar, keep)
        ns.Flat(bar, ns.C.input, -1)
        if fill and fill.SetTexture then fill:SetTexture(WHITE) end
    else
        ns.Flat(item, { 0.06, 0.06, 0.08, 0.85 })
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    ns.Hover(item)
end

-- Einfügemarke beim Ziehen: Blizzards Leucht-Grafik unsichtbar, dafür eine feine goldene Linie (rot, wo man nicht
-- ablegen darf). Die Richtung ergibt sich aus der Form der Marke (hoch = zwischen Symbolen, breit = zwischen Balken)
local function SkinMarker(marker)
    if not marker or done[marker] or Forbidden(marker) then return end
    done[marker] = true
    local holder = CreateFrame("Frame", nil, marker)
    holder:SetAllPoints()
    local line = holder:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetTexture(WHITE)
    line:SetPoint("CENTER")
    holder:SetScript("OnUpdate", function()
        local tex = marker.Texture
        if type(tex) == "table" and tex.SetAlpha then tex:SetAlpha(0) end
        local w, h = marker:GetWidth() or 8, marker:GetHeight() or 52
        if h >= w then line:SetSize(2, math.max(20, h - 8)) else line:SetSize(math.max(20, w - 8), 2) end
        local g = 1 -- (Blizzard färbt die Marke rot, wo man nicht ablegen darf: Grün-Anteil klein)
        if type(tex) == "table" and tex.GetVertexColor then g = select(2, tex:GetVertexColor()) end
        if g and g < 0.5 then
            line:SetVertexColor(1, 0.3, 0.3, 0.9)
        else
            line:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.95)
        end
    end)
end

-- Spezialisierungs-Symbol klein und eckig mit goldenem Rand links in der Titelleiste (statt Blizzards Porträt);
-- übernommen aus Blizzards (unsichtbarem) Porträt
local portrait, portraitEdge
local function Portrait(f)
    local src = f.PortraitContainer and f.PortraitContainer.portrait
    if type(src) ~= "table" or not src.GetTexture then return end
    if not portrait then
        portraitEdge = f:CreateTexture(nil, "ARTWORK", nil, 1)
        portraitEdge:SetTexture(WHITE)
        portraitEdge:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.8)
        portraitEdge:SetSize(19, 19)
        portraitEdge:SetPoint("TOPLEFT", 6, -3)
        portrait = f:CreateTexture(nil, "ARTWORK", nil, 2)
        portrait:SetPoint("TOPLEFT", portraitEdge, "TOPLEFT", 1, -1)
        portrait:SetPoint("BOTTOMRIGHT", portraitEdge, "BOTTOMRIGHT", -1, 1)
        portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local tex = src:GetTexture()
    if tex and not (issecretvalue and issecretvalue(tex)) then
        portrait:SetTexture(tex)
        portrait:Show()
        portraitEdge:Show()
    else
        portrait:Hide()
        portraitEdge:Hide()
    end
end

-- Kategorien und ihre Einträge (Blizzard holt sie aus Pools – neue kommen beim Umschalten dazu); gleich gebaut
-- sind die Abschnitte der Gruppen-Buff-Seite ("Stärkungszauber", "Nicht angezeigt")
local function ScanList(content)
    if not content or Forbidden(content) then return end
    for _, cat in ipairs({ content:GetChildren() }) do
        if not Forbidden(cat) and type(cat.Header) == "table" and type(cat.Container) == "table" then
            SkinHeader(cat.Header)
            HeaderArrow(cat.Header)
            for _, item in ipairs({ cat.Container:GetChildren() }) do SkinItem(item) end
        end
    end
end
local function ScanContent(f)
    local content = f.CooldownScroll and f.CooldownScroll.Content
    if content then
        SkinMarker(content.ReorderMarker)
        ScanList(content)
    end
    local groups = f.GroupBuffFilter and f.GroupBuffFilter.Scroll
    if groups then
        ScanList(groups.Content)
        if groups.ScrollBar then ns.SkinScrollBar(groups.ScrollBar) end
    end
end

-- Suche brauchen wir nicht (auf Wunsch): unsichtbar und nicht anklickbar; das Zahnrad daneben (Einstellungen)
-- wandert rechts über den Inhaltskasten
local function HideSearch(f)
    local box = f.SearchBox
    if type(box) ~= "table" or Forbidden(box) then return end
    if box:GetAlpha() > 0 then box:SetAlpha(0) end
    if box:IsMouseEnabled() then box:EnableMouse(false) end
    if box.HasFocus and box:HasFocus() then box:ClearFocus() end
    if (box:GetText() or "") ~= "" then box:SetText("") end -- (alter Suchtext würde sonst unsichtbar weiter filtern)
    local clear = box.clearButton
    if type(clear) == "table" and clear.IsMouseEnabled and clear:IsMouseEnabled() then clear:EnableMouse(false) end
end

-- feste Plätze: Liste über der Fußleiste enden lassen, Knöpfe mittig in der Fußleiste (nur setzen, wenn abweichend)
local function SetBottom(obj, point, x, y)
    if not obj or Forbidden(obj) then return end
    local p, rel, rp, ox, oy = obj:GetPoint(1)
    if obj:GetNumPoints() == 1 and p == point and rel == obj:GetParent() and rp == point
        and math.abs((ox or 0) - x) < 0.5 and math.abs((oy or 0) - y) < 0.5 then return end
    obj:ClearAllPoints()
    obj:SetPoint(point, x, y)
end
local function Place(f)
    for _, area in ipairs({ f.CooldownScroll, f.GroupBuffFilter }) do
        if type(area) == "table" then ns.Fit(f, area, nil, FOOTER + 12, nil, true) end
    end
    local undo = f.UndoButton
    if undo then SetBottom(undo, "BOTTOMRIGHT", -10, math.floor((FOOTER - (undo:GetHeight() or 22)) / 2 + 0.5)) end
    local layout = f.LayoutDropdown
    if layout then SetBottom(layout, "BOTTOMLEFT", 10, math.floor((FOOTER - (layout:GetHeight() or 26)) / 2 + 0.5)) end
    HideSearch(f)
    local gear = f.SettingsDropdown
    if gear then SetBottom(gear, "TOPRIGHT", -12, -(23 + math.floor((BOX_TOP - 23 - (gear:GetHeight() or 16)) / 2 + 0.5))) end
    Portrait(f)
end

local skinned
local function SkinCooldowns(f)
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.SkinWindow(f)
    Step("box", function() ns.ContentBox(f, FOOTER, BOX_TOP) end)
    Step("tabs", function()
        for _, tab in ipairs(type(f.TabButtons) == "table" and f.TabButtons or {}) do SkinSideTab(tab) end
    end)
    Step("layout", function() if f.LayoutDropdown then ns.SkinDropdown(f.LayoutDropdown) end end)
    Step("undo", function() if f.UndoButton then ns.SkinButton(f.UndoButton) end end)
    Step("scroll", function()
        local bar = f.CooldownScroll and f.CooldownScroll.ScrollBar
        if bar then ns.SkinScrollBar(bar) end
    end)
    Step("content", function() ScanContent(f) end)
    Step("place", function() Place(f) end)
    ns.Watch(f)
    -- Blizzard baut die Liste beim Umschalten, Suchen und Ziehen neu auf und blendet Rahmen teils wieder ein
    f:HookScript("OnShow", function()
        pcall(ScanContent, f)
        pcall(Place, f)
    end)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(ScanContent, f)
        pcall(Place, f)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if skinned or not ns.GetDB().cooldowns then return end
    local f = G("CooldownViewerSettings")
    if f then Step("skin", function() SkinCooldowns(f) end) end
end)
