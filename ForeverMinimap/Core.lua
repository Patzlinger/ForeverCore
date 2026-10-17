-- ForeverMinimap (Prototyp): Blizzards Minimap im Forever-Core-Stil – rund oder eckig, schlichter Rahmen,
-- schmale Leiste mit Zone, Uhr und Koordinaten, Knoepfe nur bei Bedarf.
-- Core.lua: Einstellungen, Start, Chatbefehl
--
-- Grundsatz: Die Blizzard-Minimap bleibt die Minimap (Pings, Verfolgung, Zoom, Bearbeitungsmodus fuer Position und
-- Groesse funktionieren unveraendert). ForeverMinimap
--   * aendert nur die Form (SetMaskTexture – das macht Blizzard selbst genauso) und legt eigene Flaechen daneben,
--   * blendet Blizzards Knoepfe nur optisch aus (Alpha 0 per UI.HideBlizzard, nie Hide/SetParent/SetScript),
--   * ersetzt keine Blizzard-Funktionen; eigene Knoepfe rufen Blizzards Funktionen auf (Kalender, Uhr, Verfolgung).
local ADDON_NAME, ns = ...

local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua in ForeverCore)
ns.UI = UI
local T = UI.T
ns.T = T

---------------------------------------------------------------------------
-- Einstellungen (SavedVariables, Profile verwaltet ForeverCore)
---------------------------------------------------------------------------
ns.DEFAULTS = {
    -- Form und Rahmen
    shape = "SQUARE",        -- "SQUARE" (eckig) oder "ROUND" (rund)
    border = true,           -- feiner Rahmen um Minimap und Leiste
    mapScale = 113,          -- Kartengroesse in % von Blizzards Minimap (198 px); Position/Gesamtgroesse: Bearbeitungsmodus
    -- Leiste
    bar = true,              -- Leiste mit Zonenname
    barPosition = "TOP",     -- "TOP" (ueber der Minimap) oder "BOTTOM" (darunter)
    clock = true,            -- Uhr in der Leiste (Format wie Blizzards Uhr: 24 h / Ortszeit)
    coords = true,           -- Koordinaten (nur draussen; in Instanzen gibt es keine)
    difficulty = true,       -- in Instanzen: Schwierigkeit (z. B. "Heroisch")
    barClickMap = true,      -- Klick auf den Zonennamen oeffnet die Weltkarte
    -- Knoepfe (ab Version 2: senkrechte Knopfleiste neben der Karte)
    strip = "LEFT",          -- Knopfleiste "LEFT"/"RIGHT" neben der Minimap oder "OFF" (Knoepfe am Rand bleiben, wo sie sind)
    stripMouseover = true,   -- Knopfleiste nur, solange die Maus ueber Minimap/Leisten ist (Post/Einladungen bleiben sichtbar)
    toolsInBar = false,      -- eigene Knoepfe (Post, Verfolgung, Kalender, Addon-Menue) oben in der Leiste statt seitlich
    hideBlizzard = true,     -- Blizzards Kopfzeile, Rahmen und Knoepfe ausblenden (Ersatz: Leiste und eigene Knoepfe)
    -- Komfort
    rightClickTracking = true, -- Rechtsklick auf die Minimap: Verfolgung (Kraeuter, Erze, Personen …)
    autoZoom = true,         -- nach 10 Sekunden wieder ganz herauszoomen
    pingNames = true,        -- beim Pingen kurz zeigen, wer gepingt hat
    minimapAngle = 190,
}

local function FillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil and value ~= nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
end

function ns.GetDB()
    if type(_G.ForeverMinimapDB) ~= "table" then _G.ForeverMinimapDB = {} end
    FillDefaults(_G.ForeverMinimapDB, ns.DEFAULTS)
    return _G.ForeverMinimapDB
end

function ns.Chat(text) UI.Chat(ADDON_NAME, text) end
function ns.Safe(where, fn) return UI.Safe(ADDON_NAME, where, fn) end

-- Gesperrte Werte (Kampf, "secret values") nie anfassen
local canaccessvalue = _G.canaccessvalue
function ns.CanRead(...)
    if not canaccessvalue then return true end
    return canaccessvalue(...)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", ns.Safe(T("Start", "Start"), function()
    ns.GetDB()
    if ns.SetupMap then ns.SetupMap() end
    if ns.SetupOptions then ns.SetupOptions() end
end))

---------------------------------------------------------------------------
-- Chatbefehl
---------------------------------------------------------------------------
SLASH_FOREVERMINIMAP1 = "/fmm"
SLASH_FOREVERMINIMAP2 = "/foreverminimap"
SlashCmdList["FOREVERMINIMAP"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "square" or msg == "eckig" then
        ns.GetDB().shape = "SQUARE"
        if ns.ApplyAll then ns.ApplyAll() end
    elseif msg == "round" or msg == "rund" then
        ns.GetDB().shape = "ROUND"
        if ns.ApplyAll then ns.ApplyAll() end
    else
        if ns.ToggleOptions then ns.ToggleOptions() end
    end
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = ADDON_NAME, sv = "ForeverMinimapDB", defaults = ns.DEFAULTS, version = 2,
    -- Version 2: statt "buttons" (Leiste/links/rechts) eine senkrechte Knopfleiste; eigene Knoepfe raus aus der Leiste
    migrate = function(data, from)
        if from < 2 then
            data.strip = data.buttons == "RIGHT" and "RIGHT" or "LEFT"
            data.stripMouseover = data.buttonsMouseover ~= false
            data.toolsInBar = false
            data.buttons, data.buttonsMouseover, data.edgeMouseover = nil, nil, nil
        end
    end })
