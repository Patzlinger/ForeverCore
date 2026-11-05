-- ForeverSkin – Wardrobe.lua: Fenster "Vorlagen" (Transmogrifikation, WardrobeFrame) im Forever-Stil
-- (docs/Fenster-Stil.md) – auf Wunsch nur Rahmen, Auswahllisten, Knöpfe und Suchleiste. Der Hintergrund, die runden
-- Platz-Symbole und die Vorschau-Modelle bleiben Blizzards. Teile werden allgemein nach Art gesucht (Auswahlliste,
-- Eingabefeld, Reiter, Blätter-Pfeile). Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "wardrobe/" .. what, err) end
end

-- Schlüssel eines Unter-Rahmens in seinem Eltern-Rahmen – nur lesen
local KeyOf = ns.KeyOf

-- Suchleiste: Blizzards Rahmen weg, flaches Eingabefeld (gemeinsam in Core.lua)
local function SkinSearch(box) ns.SkinSearchBox(box, { -4, 2, 0, 2 }) end

-- Reiter ("Gegenstände", "Sets"): gewählt = von Blizzard gesperrt (PanelTemplates)
local function TabSelected(tab)
    if type(tab.isSelected) == "boolean" then return tab.isSelected end
    return tab.IsEnabled and not tab:IsEnabled()
end

-- Hintergrund der Sammlungsseiten (Leder-Kachel, Schattenkanten, Ecken – Blizzards CollectionsBackgroundTemplate):
-- unsichtbar, darunter unsere flache Fläche. Nur Grafiken mit diesen Schlüsseln – Symbole und Modelle bleiben
local function IsBackgroundKey(k)
    return k == "Bg" or k == "Background" or k:find("^BackgroundTile") or k:find("^BGCorner") or k:find("^Shadow")
        or k:find("^OverlayShadow") or k:find("Corner")
end
local function HideBackground(frame)
    for k, v in pairs(frame) do
        if type(k) == "string" and type(v) == "table" and v.IsObjectType and v:IsObjectType("Texture")
            and IsBackgroundKey(k) and v:GetParent() == frame then
            v:SetAlpha(0)
        end
    end
end

-- Anzahl (z. B. Spielzeuge "12/150"): Fortschrittsbalken flach – Rahmen weg, dunkle Fläche, goldene Füllung, Text bleibt
local function SkinProgress(bar)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= fill and not ns.IsMine(bar, r) then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "border", "Border", "NineSlice" }) do ns.Hide(bar[key]) end
    ns.Flat(bar, ns.C.input, -1)
    if fill then
        fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        bar:SetStatusBarColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 0.8)
    end
end

local done = setmetatable({}, { __mode = "k" })
local tabs = setmetatable({}, { __mode = "k" }) -- Reiter: Text mittig im Kasten halten (Blizzard setzt ihn tiefer)
local centered = setmetatable({}, { __mode = "k" }) -- andere Knöpfe, deren Text mittig bleiben soll ("Filter")

-- Reiter etwas tiefer (auf Wunsch): TAB_DOWN unter Blizzards Lage; setzt Blizzard den Anker neu, gilt dessen Lage
-- als neue Grundlage
local TAB_DOWN = 4
local tabSet = setmetatable({}, { __mode = "k" }) -- [Reiter] = von uns gesetzter y-Versatz
local function LowerTab(tab)
    if tab:GetNumPoints() ~= 1 then return end
    local p, rel, rp, x, y = tab:GetPoint(1)
    if tabSet[tab] and math.abs(y - tabSet[tab]) < 0.01 then return end
    tabSet[tab] = y - TAB_DOWN
    tab:SetPoint(p, rel, rp, x, y - TAB_DOWN)
end
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then HideBackground(child) end
        if not Forbidden(child) and not done[child] then
            if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end -- (Innenrahmen samt Zierecken)
            local key = ((KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
            local isDropdown = (child.IsObjectType and child:IsObjectType("DropdownButton"))
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if child:IsObjectType("Button") and key:find("filter") and not isDropdown then
                -- "Filter" ist hier ein Knopf mit Text (keine Auswahlliste): flacher Text-Knopf mit Kasten
                done[child] = true
                ns.SkinButton(child)
                centered[child] = true -- (Text mittig halten)
            elseif child:IsObjectType("StatusBar") then
                done[child] = true
                SkinProgress(child) -- (Anzahl gesammelt)
            elseif isDropdown then
                done[child] = true
                ns.SkinDropdown(child) -- (Klasse, Filter)
            elseif child:IsObjectType("EditBox") then
                done[child] = true
                SkinSearch(child)
            elseif child:IsObjectType("Button") and (key:find("prev") or key:find("next")) then
                done[child] = true
                ns.SkinArrowOnly(child, key:find("prev") and "left" or "right") -- (Blättern unten: nur der Pfeil)
            elseif child:IsObjectType("Button") and key:find("tab") then
                local label = child.GetText and child:GetText()
                if type(label) == "string" and label ~= "" then
                    done[child] = true
                    ns.SkinTab(child, TabSelected)
                    tabs[child] = true
                end
            elseif not child:IsObjectType("Button") and depth < 5 then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Zierecken unten (braune Schnörkel) liegen als eigene Grafiken in den Innenflächen: schmale Ecken-Grafiken weg
local function HideCorners(frame, depth)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r.GetTexture and r:GetTexture()
            local s = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
            if s:find("corner") then r:SetAlpha(0) end
        end
    end
    if depth < 4 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) then HideCorners(child, depth + 1) end
        end
    end
end

-- im Forever-Client heißt das Fenster "CollectionsJournal" (Sammlungen, darin WardrobeCollectionFrame); beim
-- Transmogrifizierer ggf. "WardrobeFrame" – beide, jedes einmal
local skinned = {}
local function SkinWardrobe(f)
    if not f or skinned[f] or Forbidden(f) then return end
    skinned[f] = true
    ns.SkinWindow(f, nil, true)
    ns.Hide(f.Bg)
    HideBackground(f)
    Step("scan", function() Scan(f, 1) end)
    Step("corners", function() HideCorners(f, 1) end)
    Step("tabs", function()
        for t in pairs(tabs) do
            ns.CenterText(t)
            LowerTab(t)
        end
    end)
    ns.Watch(f)
    -- Blizzard blendet Rahmen und Porträt beim Öffnen teils wieder ein, Seiten entstehen beim Umschalten
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.3) then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then
                ns.Hide(f[key])
                ns.HideTextures(f[key])
            end
        end
        pcall(Scan, f, 1)
        pcall(HideCorners, f, 1)
        for t in pairs(tabs) do
            pcall(ns.CenterText, t)
            pcall(LowerTab, t)
        end
        for b in pairs(centered) do pcall(ns.CenterText, b) end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().wardrobe then return end
    for _, name in ipairs({ "CollectionsJournal", "WardrobeFrame" }) do
        local f = G(name)
        if f and not skinned[f] then Step("skin", function() SkinWardrobe(f) end) end
    end
end)
