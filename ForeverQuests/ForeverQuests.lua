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
    height = 400,
    -- x/y = nil bedeutet: Standardposition am rechten Bildschirmrand
    hideBlizzard = true,
    hideInCombat = false,
    onlyTracked = true,
    hideObjectives = true,
    autoCollapseMinutes = 5, -- aufgeklappter Fortschritt klappt nach so vielen Minuten ohne Änderung wieder ein
    showZones = true,
    showQuestType = true,
    showQuestTooltip = true, -- Tooltip beim Darüberfahren über eine Quest im Tracker
    instanceHint = true,     -- Hinweis beim Betreten eines Dungeons
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName ~= addonName then return end

        ForeverQuestsDB = ForeverQuestsDB or {}
        for key, value in pairs(ns.defaults) do
            if ForeverQuestsDB[key] == nil then
                -- Tabellen kopieren, damit die Standardwerte unverändert bleiben
                ForeverQuestsDB[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
        ns.db = ForeverQuestsDB

        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
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
        ns.ResetPosition()
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
