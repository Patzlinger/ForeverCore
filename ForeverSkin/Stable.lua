-- ForeverSkin – Stable.lua: Stall (StableFrame, nur Jäger beim Stallmeister) im Forever-Stil (docs/Fenster-Stil.md),
-- erster Entwurf.
--  * Rahmen flach mit Titelleiste (Jäger-Symbol klein links), ohne Holzleiste und Hilfe-Knopf
--  * Liste links: flache Fläche, Kategorien als flache Balken mit feinem Pfeil, je Begleiter ein grauer Balken mit
--    rundem Porträt (feiner Ring, gewählt = gold); Suchleiste, Filter und Zähler flach
--  * Mitte: das 3D-Modell samt Hintergrund bleibt Blizzards, nur ein feiner Rand; Knöpfe und Spezialisierung flach
--  * Unten "Aktive Begleiter" auf einer dunklen Leiste mit feiner goldener Linie, die Plätze als runde Porträts mit
--    Ring (gewählt bzw. Maus darauf = gold) – wie die Visitenkarte der NPC-Fenster
-- Nichts hier ist geschützt; Blizzards Grafiken werden nur unsichtbar, nichts in Blizzards Tabellen geschrieben.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HUNTER_ICON = "Interface\\Icons\\ClassIcon_Hunter"

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "stable/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" })
local rings = setmetatable({}, { __mode = "k" }) -- [Knopf/Zeile] = Ring-Textur (Farbe je nach Zustand)
local arrows = setmetatable({}, { __mode = "k" }) -- [Kategorie] = Pfeil

-- runde Fläche (Ring, Fuge) über eine Kreis-Maske
local function Disk(parent, layer, sub, size, c)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    t:SetSize(size, size)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
    return t
end

-- Porträt rund zuschneiden (Blizzards Bild aus der Anzeige-ID des Begleiters)
local function RoundIcon(icon, parent)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
end

-- Suchfeld: Blizzards Rahmen weg, flaches Eingabefeld (Lupe, Hinweistext und X bleiben)
local function SkinSearch(box)
    if not box or done[box] or Forbidden(box) then return end
    done[box] = true
    local keep = {}
    for _, key in ipairs({ "searchIcon", "SearchIcon", "Instructions", "clearButton" }) do
        local t = box[key]
        if type(t) == "table" and t.IsObjectType and t:IsObjectType("Texture") then keep[t] = true end
    end
    ns.HideTextures(box, keep)
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    ns.Flat(box, C.input, { -4, 0, 0, 0 })
end

-- Jäger-Symbol klein und eckig mit goldenem Rand links in der Titelleiste (statt Blizzards Porträt)
local function TitleIcon(f)
    if done.titleIcon then return end
    done.titleIcon = true
    local edge = f:CreateTexture(nil, "ARTWORK", nil, 1)
    edge:SetTexture(WHITE)
    edge:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    edge:SetSize(19, 19)
    edge:SetPoint("TOPLEFT", 6, -3)
    local icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
    icon:SetTexture(HUNTER_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Kategorie in der Liste ("Wildheit", "Hartnäckigkeit" …): flacher Balken, rechts feiner Pfeil
local function SkinCategory(cat)
    if done[cat] or Forbidden(cat) then return end
    done[cat] = true
    for _, key in ipairs({ "LeftPiece", "RightPiece", "CenterPiece", "CollapseIcon", "CollapseIconAlphaAdd" }) do
        ns.Hide(cat[key])
    end
    ns.Flat(cat, C.header, { 0, 0, 0, 4 }) -- (Blizzards Grafik sitzt 2 höher als der Knopf)
    ns.Hover(cat)
    local arrow = cat:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -10, 2)
    arrow:SetVertexColor(0.8, 0.8, 0.82)
    arrows[cat] = arrow
end
local function CategoryArrow(cat)
    local arrow, icon = arrows[cat], cat.CollapseIcon
    if not arrow or type(icon) ~= "table" or not icon.GetAtlas then return end
    local atlas = icon:GetAtlas()
    local collapsed = type(atlas) == "string" and atlas:find("expand") ~= nil
    arrow:SetRotation(collapsed and 0 or -math.pi / 2)
end

-- Begleiter in der Liste: grauer Balken (Maus darauf und gewählt = gold), links ein rundes Porträt mit feinem Ring,
-- daneben Name und Art
local function RowSelected(row)
    if type(row.isSelected) == "boolean" then return row.isSelected end
    return type(row.Selected) == "table" and row.Selected:IsShown()
end
local function SkinRow(row)
    if done[row] or Forbidden(row) or type(row.Portrait) ~= "table" then return end
    done[row] = true
    for _, key in ipairs({ "Background", "Selected" }) do ns.Hide(row[key]) end
    ns.Hide(row.GetHighlightTexture and row:GetHighlightTexture())
    ns.Flat(row, C.button)
    ns.Hover(row, RowSelected)
    local portrait = row.Portrait
    ns.Hide(portrait.Border)
    portrait:ClearAllPoints()
    portrait:SetPoint("LEFT", row, "LEFT", 7, 0)
    portrait:SetSize(42, 42)
    local ring = Disk(row, "BORDER", 1, 46, C.border)
    ring:SetPoint("CENTER", portrait, "CENTER")
    local gap = Disk(row, "BORDER", 2, 44, C.background)
    gap:SetPoint("CENTER", portrait, "CENTER")
    rings[row] = ring
    local icon = portrait.Icon
    if type(icon) == "table" then
        icon:ClearAllPoints()
        icon:SetAllPoints(portrait)
        RoundIcon(icon, portrait)
    end
    if type(portrait.FavoriteIcon) == "table" then
        portrait.FavoriteIcon:SetSize(18, 18)
        portrait.FavoriteIcon:ClearAllPoints()
        portrait.FavoriteIcon:SetPoint("TOPLEFT", -4, 4)
    end
    if type(row.Name) == "table" then
        row.Name:ClearAllPoints()
        row.Name:SetPoint("LEFT", row, "LEFT", 60, 7)
        row.Name:SetPoint("RIGHT", row, "RIGHT", -10, 7)
    end
end

-- aktive Begleiter: runde Porträts mit Ring und feiner Fuge (wie die NPC-Visitenkarte), Blizzards Ringe weg
local function SkinActive(button)
    if done[button] or Forbidden(button) then return end
    done[button] = true
    for _, key in ipairs({ "Background", "Border", "Highlight" }) do ns.Hide(button[key]) end
    local ring = Disk(button, "BACKGROUND", -8, 62, C.border)
    ring:SetPoint("CENTER")
    local gap = Disk(button, "BACKGROUND", -7, 58, C.background)
    gap:SetPoint("CENTER")
    rings[button] = ring
    local icon = button.Icon
    if type(icon) == "table" then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER")
        icon:SetSize(55, 55)
        RoundIcon(icon, button)
    end
end

-- Ringe: grau, gewählt bzw. Maus darauf gold
local function UpdateRings()
    for owner, ring in pairs(rings) do
        if owner:IsVisible() then
            local lit = owner.isSelected or owner:IsMouseOver()
            local c = lit and C.accent or C.border
            ring:SetVertexColor(c[1], c[2], c[3], lit and 0.95 or 1)
        end
    end
end

-- Leiste "Aktive Begleiter": dunkle Fläche mit feiner goldener Linie oben statt Blizzards Holz-Leiste
local function SkinActiveBar(f)
    local list = f.ActivePetList
    if not list or done[list] or Forbidden(list) then return end
    done[list] = true
    ns.Hide(list.ActivePetListBG)
    ns.Hide(list.ActivePetListBGBar)
    local scene = f.PetModelScene
    local band = list:CreateTexture(nil, "BACKGROUND", nil, -8)
    band:SetTexture(WHITE)
    band:SetVertexColor(C.header[1], C.header[2], C.header[3], 0.92)
    band:SetPoint("BOTTOMLEFT", scene, "BOTTOMLEFT", 1, 1)
    band:SetPoint("BOTTOMRIGHT", scene, "BOTTOMRIGHT", -1, 1)
    band:SetHeight(90)
    local line = list:CreateTexture(nil, "BORDER", nil, -6)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35)
    line:SetPoint("BOTTOMLEFT", band, "TOPLEFT")
    line:SetPoint("BOTTOMRIGHT", band, "TOPRIGHT")
    ns.OnePixel(line, true)
    for _, b in ipairs(type(list.PetButtons) == "table" and list.PetButtons or {}) do SkinActive(b) end
    if list.BeastMasterSecondaryPetButton then SkinActive(list.BeastMasterSecondaryPetButton) end
end

-- Liste links: Blizzards Hintergrund-Bild und Innenrahmen weg, flache Fläche; Zähler und Filterleiste flach
local function SkinList(f)
    local list = f.StabledPetList
    if not list or done[list] or Forbidden(list) then return end
    done[list] = true
    ns.Hide(list.Background)
    if list.Inset then
        ns.Hide(list.Inset.NineSlice)
        ns.HideTextures(list.Inset)
    end
    ns.Flat(list, C.panel, { 4, 0, 0, 2 })
    local counter = list.ListCounter
    if counter and not Forbidden(counter) then
        -- (die Pfote bleibt: einzige Grafik mit Atlas "paw")
        local keep = {}
        for _, r in ipairs({ counter:GetRegions() }) do
            local atlas = r.IsObjectType and r:IsObjectType("Texture") and r.GetAtlas and r:GetAtlas()
            if type(atlas) == "string" and atlas:find("paw") then keep[r] = true end
        end
        ns.HideTextures(counter, keep)
        if counter.NineSlice then ns.Hide(counter.NineSlice) end
        ns.Flat(counter, C.input)
    end
    local bar = list.FilterBar
    if bar and not Forbidden(bar) then
        ns.Hide(bar.Background)
        SkinSearch(bar.SearchBox)
        if bar.FilterDropdown then ns.SkinDropdown(bar.FilterDropdown) end
    end
    if list.ScrollBar then ns.SkinScrollBar(list.ScrollBar) end
end

-- Mitte: Modell bleibt, Blizzards Innenrahmen und Schatten weg, feiner Rand; Spezialisierung und Knöpfe flach
local function SkinScene(f)
    local scene = f.PetModelScene
    if not scene or done[scene] or Forbidden(scene) then return end
    done[scene] = true
    if scene.Inset then
        ns.Hide(scene.Inset.NineSlice)
        ns.HideTextures(scene.Inset)
    end
    if scene.PetModelSceneShadow then
        ns.HideTextures(scene.PetModelSceneShadow)
        for _, child in ipairs({ scene.PetModelSceneShadow:GetChildren() }) do ns.HideTextures(child) end
    end
    ns.Flat(scene, { 0, 0, 0, 0 })
    local info = scene.PetInfo
    if info and info.Specialization then ns.SkinDropdown(info.Specialization) end
    for _, key in ipairs({ "StableTogglePetButton", "ReleasePetButton" }) do
        if f[key] then ns.SkinButton(f[key]) end
    end
end

-- Liste: Zeilen holt Blizzard beim Blättern nach – solange offen, neue umgestalten
local function Rows(f)
    local box = f.StabledPetList and f.StabledPetList.ScrollBox
    if not (box and box.ForEachFrame) or Forbidden(box) then return end
    box:ForEachFrame(function(entry)
        if type(entry.CollapseIcon) == "table" then
            SkinCategory(entry)
            CategoryArrow(entry)
        elseif type(entry.Portrait) == "table" then
            SkinRow(entry)
        end
    end)
end

local skinned
local function SkinStable()
    local f = G("StableFrame")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.SkinWindow(f, nil, true)
    for _, key in ipairs({ "Bg", "Topper" }) do ns.Hide(f[key]) end
    Step("help", function()
        local help = f.MainHelpButton
        if help and not Forbidden(help) then
            help:SetAlpha(0)
            help:EnableMouse(false)
        end
    end)
    Step("title", function() TitleIcon(f) end)
    Step("list", function() SkinList(f) end)
    Step("scene", function() SkinScene(f) end)
    Step("active", function() SkinActiveBar(f) end)
    Step("rows", function() Rows(f) end)
    ns.Watch(f)
    -- solange offen: neue Zeilen, Pfeile und Ringe; Rahmen und Porträt, falls Blizzard sie wieder einblendet
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        pcall(UpdateRings) -- (in jedem Bild: der Ring folgt der Maus ohne Verzögerung)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(Rows, f)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if skinned or not ns.GetDB().stable or not G("StableFrame") then return end
    Step("skin", SkinStable)
end)
