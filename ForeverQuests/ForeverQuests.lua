local addonName, ns = ...
local L = ns.L

-- Vorangestellter Addon-Name für Chat-Meldungen (Gold wie alle Forever-Addons)
function ns.ChatPrefix()
    return "|cffffcc00" .. L("ADDON_NAME") .. "|r"
end

-- Schriftarten, die in jedem WoW-Client vorhanden sind
ns.FONTS = {
    { key = "STANDARD", textKey = "FONT_STANDARD", path = STANDARD_TEXT_FONT },
    { key = "ARIALN",   text = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "SKURRI",   text = "Skurri",       path = "Fonts\\skurri.ttf" },
    { key = "MORPHEUS", text = "Morpheus",     path = "Fonts\\MORPHEUS.TTF" },
}

-- Standardwerte; werden genutzt, falls keine gespeicherten Daten vorhanden sind
-- (wichtig wegen des Beta-Bugs, bei dem SavedVariables nicht geladen werden)
ns.defaults = {
    version = 1,
    width = 260,
    height = 528,
    -- x/y = nil bedeutet: Standardposition am rechten Bildschirmrand
    followMinimap = true, -- mit ForeverMinimap: direkt darunter und gleich breit (aus, sobald man den Tracker selbst zieht)
    hideBlizzard = true,
    hideInCombat = false,
    onlyTracked = true,
    hideObjectives = true,
    autoCollapseMinutes = 5, -- aufgeklappter Fortschritt klappt nach so vielen Minuten ohne Änderung wieder ein
    showZones = true,
    showQuestType = true,
    showQuestTooltip = true, -- Tooltip beim Darüberfahren über eine Quest im Tracker
    instanceHint = true,     -- Hinweis beim Betreten eines Dungeons
    betaDungeons = true,     -- Beta-Modus: im Dungeonfenster nur Dungeons und Quests bis Stufe 30
    showMinimapButton = true,
    minimapAngle = 220,
    trackerHidden = false,
    pinned = {},            -- angeheftete Quests: [questID] = true
    -- Schrift (Farben der Überschriften sind fest, siehe HEADER_COLORS in Tracker.lua)
    font = "STANDARD",
    fontSize = 12,
    fontOutline = false,
    -- Fenster je Gebiet/Kategorie
    backgroundTransparency = 65, -- in Prozent: 0 = undurchsichtig, 100 = unsichtbar
    -- Belohnungen markieren ab Seltenheit: 0 = aus, 2 = grün, 3 = blau, 4 = episch
    rewardHighlight = 2,
    -- Gewählte Filter im Tracker, mehrere möglich: [Filter-Schlüssel] = true (leer = Standard)
    filters = {},
    -- In Instanzen automatisch nur die Quests der Instanz zeigen
    instanceFilter = true,
    -- Sprache: "AUTO" (wie der WoW-Client), "deDE" oder "enUS"
    language = "AUTO",
}

-- Fehlende Einstellungen aus den Standardwerten ergänzen
local function FillDefaults()
    for key, value in pairs(ns.defaults) do
        if ForeverQuestsDB[key] == nil then
            -- Tabellen kopieren, damit die Standardwerte unverändert bleiben
            ForeverQuestsDB[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
end

-- Alle Einstellungen auf Standard (Knopf "Zurücksetzen" im Menü, /fq reset). Bleiben: angeheftete Quests, Sprache,
-- Profil-Verwaltung von ForeverCore (_fc) und interne Stände; gilt sofort, ohne Neuladen
local KEEP_ON_RESET = { version = true, pinned = true, language = true, _fc = true, layoutVersion = true }
function ns.ResetSettings()
    for key in pairs(ForeverQuestsDB) do
        if not KEEP_ON_RESET[key] then ForeverQuestsDB[key] = nil end
    end
    FillDefaults()
    if ns.ResetExpanded then ns.ResetExpanded() end
    if ns.UpdateBlizzardTracker then ns.UpdateBlizzardTracker() end
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    if ns.ResetPosition then ns.ResetPosition() end -- setzt auch Position/Größe neu und frischt das Menü auf
    if ns.UpdateVisibility then ns.UpdateVisibility() end
    if ns.RequestUpdate then ns.RequestUpdate() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= addonName then return end

        ForeverQuestsDB = ForeverQuestsDB or {}
        FillDefaults()
        ns.db = ForeverQuestsDB

        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Nochmals ergänzen: ForeverCore schreibt beim Laden das Profil in dieselbe Tabelle; lief das nach uns
        -- (z. B. nach "Zurücksetzen"), fehlten sonst alle Werte
        FillDefaults()
        -- Einmalig: Tracker höher (Standard 400 -> 480 -> 528), wenn die Höhe noch auf einem alten Standard steht
        if (ns.db.layoutVersion or 1) < 3 then
            if ns.db.height == 400 or ns.db.height == 480 then ns.db.height = ns.defaults.height end
            ns.db.layoutVersion = 3
        end
        if ns.ApplyBetaFilter then ns.ApplyBetaFilter() end
        ns.CreateTracker()
        ns.UpdateBlizzardTracker()
        ns.CreateMinimapButton()
    end
end)

-- Tastenkürzel (Blizzard-Menü "Tastaturbelegung" > "AddOns"; die Belegungen selbst stehen in Bindings.xml)
BINDING_HEADER_FOREVERQUESTS = L("BINDING_HEADER")
BINDING_NAME_FOREVERQUESTS_TRACKER = L("BINDING_TRACKER")
BINDING_NAME_FOREVERQUESTS_DUNGEONS = L("BINDING_DUNGEONS")
BINDING_NAME_FOREVERQUESTS_OPTIONS = L("BINDING_OPTIONS")
function ForeverQuests_ToggleTracker() if ns.ToggleTracker then ns.ToggleTracker() end end
function ForeverQuests_ToggleDungeons() if ns.ToggleDungeons then ns.ToggleDungeons() end end
function ForeverQuests_ToggleOptions() if ns.ToggleOptions then ns.ToggleOptions() end end

SLASH_FOREVERQUESTS1 = "/fq"
SLASH_FOREVERQUESTS2 = "/foreverquests"
SlashCmdList.FOREVERQUESTS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        ns.ResetSettings()
        print(ns.ChatPrefix() .. ": " .. L("RESET_DONE"))
    elseif msg == "dungeons" then
        ns.ToggleDungeons()
    elseif msg == "check" then
        -- Quest-IDs der Dungeon-Daten beim Spiel prüfen
        ns.CheckQuestIDs()
    elseif msg == "maus" or msg == "mouse" then
        -- Fehlersuche: welches Fenster bekommt die Maus?
        ns.DebugMouse()
    elseif msg == "lfg" then
        -- Zeigt, was das Spiel für die Gruppensuche anbietet (Fehlersuche)
        ns.DebugGroupFinder()
    elseif msg == "move" then
        -- Tracker entsperren bzw. wieder sperren
        ns.SetUnlocked(not ns.unlocked)
        if ns.RefreshOptions then ns.RefreshOptions() end
        print(ns.ChatPrefix() .. ": " .. L(ns.unlocked and "TRACKER_UNLOCKED" or "TRACKER_LOCKED"))
    else
        ns.ToggleOptions()
    end
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
-- Pins (angeheftete Quests) und Sprache gelten fuer alle Profile
ForeverHub.UI.RegisterSettings({ addon = "ForeverQuests", sv = "ForeverQuestsDB", defaults = ns.defaults, version = 1,
    global = { "version", "pinned", "language", "showMinimapButton" } })
