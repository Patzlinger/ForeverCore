-- ForeverSkin – Communities.lua: Fenster "Gilde & Communitys" (CommunitiesFrame) im Forever-Stil
-- (docs/Fenster-Stil.md) – erster Schritt: Rahmen, Liste links, Innenrahmen, Laufleisten, Knöpfe oben rechts.
-- Die Bilder im Inhalt (z. B. der Drache auf der Gildenseite) bleiben: der Rahmen wird nur "leicht" umgestaltet,
-- an Innenflächen verschwinden nur Blizzards Rahmen (NineSlice). Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

-- Rand links so breit wie rechts: rechts = Abstand des Inhalts zur Fensterkante, links = Abstand der Liste zur Kante
-- unserer Fläche. Die Fläche (samt Titelleiste) reicht links entsprechend über Blizzards Fensterkante hinaus –
-- Blizzards Inhalt bleibt, wo er ist. Gemessen bei jedem Durchgang (die Aufteilung ändert sich z. B. beim Verkleinern)
local currentGrow
local function EvenMargins(f)
    local list = f.CommunitiesList
    if type(list) ~= "table" or Forbidden(list) or not (list:GetLeft() and f:GetLeft() and f:GetRight()) then return end
    local maxRight
    for _, child in ipairs({ f:GetChildren() }) do
        if child ~= list and not Forbidden(child) and child:IsShown() and child:GetRight()
            and (child:GetWidth() or 0) > 150 and (child:GetHeight() or 0) > 100 and child:GetRight() <= f:GetRight() + 1 then
            maxRight = math.max(maxRight or 0, child:GetRight())
        end
    end
    if not maxRight then return end
    local rightMargin = math.max(0, f:GetRight() - maxRight)
    local grow = math.floor(rightMargin - (list:GetLeft() - f:GetLeft()) + 0.5)
    if grow == currentGrow then return end
    currentGrow = grow
    local look = ns.Flat(f, C.background, { -grow, 0, 0, 0 })
    if look and look.head then
        look.head:ClearAllPoints()
        look.head:SetPoint("TOPLEFT", look.fill, "TOPLEFT", 1, -1)
        look.head:SetPoint("TOPRIGHT", look.fill, "TOPRIGHT", -1, -1)
    end
end

-- Porträt oben links (hier "PortraitOverlay" mit Gildenwappen, dazu das übliche PortraitContainer): unsichtbar
local function HidePortrait(f)
    for _, key in ipairs({ "PortraitOverlay", "PortraitContainer", "PortraitFrame", "Portrait" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
        end
    end
end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "communities/" .. what, err) end
end

-- Liste links (Gilde, Communitys, "Community beitreten"): blauer Hintergrund und Zierecken weg, flache Fläche
local function SkinList(list)
    if type(list) ~= "table" or Forbidden(list) then return end
    for _, key in ipairs({ "Bg", "Background", "FilligreeOverlay", "TopFiller", "BottomFiller" }) do ns.Hide(list[key]) end
    local inset = list.InsetFrame
    if type(inset) == "table" and not Forbidden(inset) then ns.SkinInset(inset) end
end

-- in allen Unterrahmen: Blizzards Innenrahmen (NineSlice) unsichtbar, Laufleisten gold – Bilder bleiben
local done = setmetatable({}, { __mode = "k" })
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
            local isBar = type(child.Track) == "table" and (child.Track.Thumb or child.Back)
            if isBar then
                if not done[child] then
                    done[child] = true
                    ns.SkinScrollBar(child)
                end
            elseif depth < 4 then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Verkleinern/Vergrößern oben rechts: nur feine Pfeile (ohne Blizzards roten Knopf)
local function SkinMaxMin(f)
    local mm = f.MaximizeMinimizeFrame
    if type(mm) ~= "table" or Forbidden(mm) then return end
    ns.HideTextures(mm)
    ns.SkinArrowOnly(mm.MaximizeButton, "up")
    ns.SkinArrowOnly(mm.MinimizeButton, "down")
end

-- Blizzard sperrt den Knopf (ausgegraut), solange es nichts zu verkleinern gibt (keine Gilde/Community) – unser feiner
-- Pfeil zeigte das nicht: dann ganz ausblenden, sonst sichtbar
local function MaxMinShown(f)
    local mm = f.MaximizeMinimizeFrame
    if type(mm) ~= "table" or Forbidden(mm) then return end
    local usable = false
    for _, b in ipairs({ mm.MaximizeButton or false, mm.MinimizeButton or false }) do
        if b and b:IsShown() and b:IsEnabled() then usable = true end
    end
    mm:SetAlpha(usable and 1 or 0)
end

local function SkinCommunities()
    local f = G("CommunitiesFrame")
    if not f or ns.communitiesSkinned or Forbidden(f) then return end
    ns.communitiesSkinned = true
    ns.SkinWindow(f, nil, true)
    ns.Hide(f.Bg)
    Step("margins", function() EvenMargins(f) end)
    Step("portrait", function() HidePortrait(f) end)
    Step("list", function() SkinList(f.CommunitiesList) end)
    Step("maxmin", function() SkinMaxMin(f); MaxMinShown(f) end)
    Step("scan", function() Scan(f, 1) end)
    ns.Watch(f)
    -- Blizzard baut Seiten beim Umschalten (Gilde, Chat, Mitglieder …) neu und blendet Rahmen beim Öffnen wieder
    -- ein: solange offen, ab und zu nachsehen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        if type(f.NineSlice) == "table" then ns.Hide(f.NineSlice) end
        pcall(HidePortrait, f)
        pcall(MaxMinShown, f)
        pcall(EvenMargins, f)
        pcall(SkinList, f.CommunitiesList)
        pcall(Scan, f, 1)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.communitiesSkinned or not ns.GetDB().communities or not G("CommunitiesFrame") then return end
    Step("skin", SkinCommunities)
end)
