-- ForeverSkin – Talents.lua: Talentfenster (im Forever-Client "PlayerSpellsFrame") – erst einmal nur Rahmen und die
-- Reiter "Primär"/"Sekundär" im Forever-Stil (docs/Fenster-Stil.md). Der Inhalt (Talentbäume samt Hintergrund) bleibt
-- unangetastet: der Rahmen wird darum nur "leicht" umgestaltet (Blizzards Rahmen, Titel-Hintergrund und Porträt weg,
-- unsere Titelleiste mit goldener Linie dazu). Die Reiter stecken namenlos tief im Fenster – sie werden über ihre
-- Beschriftung gefunden. Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "talents/" .. what, err) end
end

-- Reiter "Primär"/"Sekundär" (Primary/Secondary) über die Beschriftung finden
local tabs = setmetatable({}, { __mode = "k" })
local function IsSpecTabText(text)
    if type(text) ~= "string" then return false end
    local s = text:lower()
    return s:find("prim") or s:find("sekund") or s:find("second")
end

-- gewählt = wirklich ausgewählter Reiter (nicht "gesperrt": Sekundär ist ohne zweite Talentverteilung deaktiviert)
local function Selected(b)
    if type(b.isSelected) == "boolean" then return b.isSelected end
    if b.IsSelected then
        local ok, sel = pcall(b.IsSelected, b)
        if ok and type(sel) == "boolean" then return sel end
    end
    if b.GetChecked then return b:GetChecked() and true or false end
    return b.selected == true
end

-- Luft unter den Reitern: die Reiterleiste (Elternrahmen der Reiter) etwas nach oben
local LIFT = 6
local lifted = {} -- [Leiste] = ursprünglicher y-Versatz
local function LiftTabs(f)
    for tab in pairs(tabs) do
        local bar = tab:GetParent()
        if bar and bar ~= f and not Forbidden(bar) and bar:GetNumPoints() == 1 then
            local point, rel, relPoint, x, y = bar:GetPoint(1)
            if lifted[bar] == nil then lifted[bar] = y end
            if y ~= lifted[bar] + LIFT then bar:SetPoint(point, rel, relPoint, x, lifted[bar] + LIFT) end
        end
    end
end

local function FindTabs(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("Button") or child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                if not tabs[child] and IsSpecTabText(text) then
                    tabs[child] = true
                    ns.SkinTab(child, Selected)
                end
            elseif depth < 5 then
                FindTabs(child, depth + 1)
            end
        end
    end
end

-- Blizzards Metallrahmen (NineSlice, samt braunem Balken und goldenen Ecken) und das Porträt: Blizzard blendet sie
-- beim Öffnen wieder ein – darum jedes Teil einzeln unsichtbar, bei offenem Fenster immer wieder
local function HideFrameArt(f)
    -- Blizzards Fensterhintergrund (liegt über unserer flachen Fläche)
    ns.Hide(f.Bg)
    for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
        end
    end
    -- Blizzards großes Talent-Hintergrundbild (liegt unter den Bäumen, sichtbar nur oben bei den Reitern) und die
    -- Partikel-Animation darüber: weg, dort zeigt sich unsere flache Fläche
    local talents = f.TalentsFrame
    if type(talents) == "table" and not Forbidden(talents) then
        for key, obj in pairs(talents) do
            if type(key) == "string" and type(obj) == "table" and (key == "Background" or key:find("Particles"))
                and obj.IsObjectType and obj:IsObjectType("Texture") then
                obj:SetAlpha(0)
            end
        end
    end
end

local function SkinTalents()
    local f = G("PlayerSpellsFrame")
    if not f or ns.talentsSkinned or Forbidden(f) then return end
    ns.talentsSkinned = true
    -- nur der Rahmen ("leicht": Blizzards Hintergrund mit den Talentbäumen bleibt)
    ns.SkinWindow(f, nil, true)
    Step("frame", function() HideFrameArt(f) end)
    Step("tabs", function() FindTabs(f, 1); LiftTabs(f) end)
    ns.Watch(f)
    -- Reiter entstehen teils erst beim Öffnen/Umschalten: solange offen, ab und zu nachsehen; Text mittig
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        pcall(HideFrameArt, f)
        pcall(FindTabs, f, 1)
        pcall(LiftTabs, f)
        for t in pairs(tabs) do pcall(ns.CenterText, t) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.talentsSkinned or not ns.GetDB().talents or not G("PlayerSpellsFrame") then return end
    Step("skin", SkinTalents)
end)
