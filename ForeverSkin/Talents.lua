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

local function Selected(b)
    if b.GetChecked and b:GetChecked() then return true end
    if b.isSelected or b.selected then return true end
    return b.IsEnabled and not b:IsEnabled()
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
    for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
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
    Step("tabs", function() FindTabs(f, 1) end)
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
