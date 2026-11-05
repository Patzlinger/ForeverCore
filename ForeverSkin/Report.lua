-- ForeverSkin – Report.lua: Fenster "Spieler melden" (ReportFrame, "Der WoW-Kundensupport") im Forever-Stil
-- (docs/Fenster-Stil.md), erster Entwurf: flache Fläche, dunkle Titelleiste mit goldener Linie (Titel bleibt mittig),
-- Inhalt in unserem Kasten, unten eine dunklere Leiste für "Melden"; Auswahllisten, Knöpfe, Textfeld und Häkchen flach,
-- unser Schließen-Kreuz. Teile werden allgemein nach Art gesucht (Blizzard baut den Inhalt je nach Meldung um).
-- Blizzard lädt das Fenster erst beim ersten Melden (Blizzard_ReportFrame).
local _, ns = ...
local C = ns.C

local TITLE = 23   -- Höhe unserer Titelleiste
local FOOTER = 36  -- untere Leiste mit "Melden"

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "report/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" })

-- Auswahlliste? (das Spiel meldet die Art nicht immer als "DropdownButton" – dann am Aufbau erkennen)
local function IsDropdown(child)
    return (child.IsObjectType and child:IsObjectType("DropdownButton")) or type(child.SetupMenu) == "function"
        or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
end

local function SkinEdit(box)
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    ns.Flat(box, C.input, { -4, 0, 0, 0 })
end

local function Scan(frame, depth, close)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= close and not Forbidden(child) and not done[child] then
            -- Textkasten (Kommentar) und andere Innenflächen mit Blizzard-Rahmen: flach
            if type(child.NineSlice) == "table" and not child:IsObjectType("Button") then
                ns.Hide(child.NineSlice)
                ns.Flat(child, C.input)
            end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif IsDropdown(child) then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("CheckButton") and (child:GetWidth() or 0) <= 32 then
                done[child] = true
                ns.SkinCheck(child)
            elseif child:IsObjectType("EditBox") then
                done[child] = true
                if type(child.Left) == "table" then SkinEdit(child) end
            elseif child:IsObjectType("Button") and (type(child.Left) == "table"
                or (child.GetText and child:GetText() and child:GetText() ~= "")) then
                done[child] = true
                ns.SkinButton(child)
            elseif not child:IsObjectType("Button") and depth < 4 then
                Scan(child, depth + 1, close)
            end
        end
    end
end

-- Je nach Spielstand heißt das Fenster "ReportFrame" (neue Meldung) oder "ReportCheatingDialog" (ältere Fassung) –
-- beide, jedes einmal
local NAMES = { "ReportFrame", "ReportCheatingDialog" }
local skinned = {}
local function SkinReport(f)
    if not f or skinned[f] or Forbidden(f) then return end
    skinned[f] = true
    ns.noGold[f] = true -- (kein Kontostand in der Titelleiste)
    ns.SkinWindow(f)
    -- Blizzards Rahmen samt Kopf-Schild (DialogBorderTemplate)
    for _, key in ipairs({ "Border", "Header" }) do
        local part = f[key]
        if type(part) == "table" and not Forbidden(part) then
            ns.HideTextures(part)
            if type(part.NineSlice) == "table" then ns.Hide(part.NineSlice) end
        end
    end
    ns.ContentBox(f, FOOTER, TITLE + 8)
    local close = ns.FindCloseButton(f)
    Step("scan", function() Scan(f, 1, close) end)
    ns.Watch(f)
    -- Blizzard baut den Inhalt je nach Meldung (Spieler, Gildensuche, Chat …) neu: beim Öffnen nochmal durchsehen
    f:HookScript("OnShow", function(self) pcall(Scan, self, 1, close) end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().report then return end
    for _, name in ipairs(NAMES) do
        local f = G(name)
        if f and not skinned[f] then Step("skin", function() SkinReport(f) end) end
    end
end)
