local addonName, ns = ...

---------------------------------------------------------------------------
-- Questie-Anbindung: Ist Questie installiert, bleibt dessen Karten-, Minimap- und Tooltip-Hilfe aktiv,
-- aber sein eigener Tracker wird abgeschaltet, damit nur unserer zu sehen ist. Questie folgt dann der
-- Blizzard-Verfolgungsliste, also genau den Quests in unserem Tracker. Dazu Questie-Befehle im Rechtsklick-Menü.
-- Questie-Dateien werden dabei nicht verändert; alle Aufrufe in Questie sind abgesichert (pcall).
---------------------------------------------------------------------------

-- Questies Tracker aus. Muss vor dessen Start (PLAYER_LOGIN, danach im Hintergrund) passieren; wegen des
-- Beta-Bugs (SavedVariables fehlen) bei jedem Laden erneut, sonst stünde er wieder auf "an"
local function DisableQuestieTracker()
    local questie = _G.Questie
    if type(questie) == "table" and questie.db and questie.db.profile then
        questie.db.profile.trackerEnabled = false
    end
end

DisableQuestieTracker()
-- Falls Questies Einstellungen beim Laden unserer Dateien noch nicht angelegt sind: direkt danach setzen
if type(_G.Questie) == "table" and not _G.Questie.db and type(_G.Questie.OnInitialize) == "function" then
    hooksecurefunc(_G.Questie, "OnInitialize", DisableQuestieTracker)
end
-- Blizzards eigene Questmarker auf Karte und Minimap aus, solange Questie läuft (wie Questies Symbolthema
-- "Questie": Spieleinstellung questPOI = 0). Blizzard zeigt sie für alle verfolgten Quests – mit Questies Tracker
-- war Blizzards Verfolgungsliste leer, mit unserem Tracker nicht mehr, so lagen plötzlich beide Marker auf der Karte.
-- Hängt an "Blizzard-Questtracker ausblenden"; schaltet man das aus, kommen Blizzards Marker zurück (nur wenn wir
-- sie abgeschaltet hatten).
local function ApplyBlizzardMapMarkers()
    local db = ns.db
    if not db or type(_G.Questie) ~= "table" or not (GetCVar and SetCVar) then return end
    if db.hideBlizzard then
        if GetCVar("questPOI") ~= "0" then
            db.questieHidPOI = true
            SetCVar("questPOI", "0")
        end
        local button = _G.WorldMapQuestShowObjectives -- Blizzards Häkchen "Questziele zeigen" an der Karte
        if button and button.SetChecked then button:SetChecked(false) end
    elseif db.questieHidPOI then
        db.questieHidPOI = nil
        SetCVar("questPOI", "1")
    end
end

local guard = CreateFrame("Frame")
guard:RegisterEvent("ADDON_LOADED")
guard:RegisterEvent("PLAYER_LOGIN")
guard:SetScript("OnEvent", function(self, event)
    DisableQuestieTracker()
    if event == "PLAYER_LOGIN" then
        self:UnregisterAllEvents()
        -- vor PLAYER_ENTERING_WORLD: Questie fängt dort Blizzards "Karte geht beim Login auf" bei questPOI = 0 ab
        pcall(ApplyBlizzardMapMarkers)
        if ns.UpdateBlizzardTracker then
            hooksecurefunc(ns, "UpdateBlizzardTracker", function() pcall(ApplyBlizzardMapMarkers) end)
        end
    end
end)

-- Questie geladen und fertig gestartet?
function ns.HasQuestie()
    return type(_G.Questie) == "table" and _G.Questie.API and _G.Questie.API.isReady and type(_G.QuestieLoader) == "table"
end

local function Module(name)
    return _G.QuestieLoader:ImportModule(name)
end

-- Was Questie zu dieser Quest kann (Fokus, Abgabe zeigen, Wegpunkt); nil, wenn Questie sie nicht kennt
local function GetCapabilities(questID)
    local ok, _, caps = pcall(function()
        return Module("TrackerMapEligibility").RefreshAndGetCapabilities(questID)
    end)
    if ok then return caps end
end

local function IsFocused(questID)
    local focus = _G.Questie.db and _G.Questie.db.char and _G.Questie.db.char.TrackerFocus
    if type(focus) == "number" then return focus == questID end
    if type(focus) == "string" then return tonumber(focus:match("^(%d+) ")) == questID end
    return false
end

local function Call(fn)
    local ok, err = pcall(fn)
    if not ok then print(ns.ChatPrefix() .. ": Questie - " .. tostring(err)) end
end

-- Fügt die Questie-Befehle ins Rechtsklick-Menü einer Quest ein (nur wenn Questie läuft)
function ns.AddQuestieMenuItems(items, questID)
    if not ns.HasQuestie() then return end
    local caps = GetCapabilities(questID)
    local entries = {}

    if IsFocused(questID) then
        -- Fokus aufheben: alle Quest-Symbole wieder normal
        table.insert(entries, { text = ns.L("QUESTIE_UNFOCUS"), onClick = function() Call(function()
            Module("TrackerUtils"):UnFocus()
            Module("QuestieQuest"):ToggleNotes(true)
        end) end })
    elseif caps and caps.canFocusQuest then
        -- Fokus: Symbole aller anderen Quests auf Karte und Minimap werden blass
        table.insert(entries, { text = ns.L("QUESTIE_FOCUS"), onClick = function() Call(function()
            if Module("TrackerUtils"):FocusQuest(questID) then
                Module("QuestieQuest"):ToggleNotes(false)
            end
        end) end })
    end

    if caps and caps.canShowFinisher and caps.quest then
        -- Fertige Quest: Abgabe-NPC auf der Weltkarte zeigen und aufblinken lassen
        table.insert(entries, { text = ns.L("QUESTIE_FINISHER"), disabled = InCombatLockdown(), onClick = function() Call(function()
            local current = GetCapabilities(questID)
            if current and current.canShowFinisher then Module("TrackerUtils"):ShowFinisherOnMap(current.quest) end
        end) end })
    end

    if caps and caps.canNavigateQuest and _G.TomTom and _G.TomTom.AddWaypoint then
        -- Wegpunkt zum nächsten Ziel (braucht das Addon TomTom)
        table.insert(entries, { text = ns.L("QUESTIE_TOMTOM"), onClick = function() Call(function()
            Module("TrackerUtils").SetQuestTomTomTarget(questID)
        end) end })
    end

    -- Wowhead-Link zum Kopieren
    table.insert(entries, { text = ns.L("QUESTIE_WOWHEAD"), disabled = InCombatLockdown(), onClick = function() Call(function()
        Module("TrackerData").RefreshQuest(questID) -- damit der Name im Fenster steht
        Module("QuestiePopup").Show("QUESTIE_WOWHEAD_URL", questID)
    end) end })

    table.insert(items, { divider = true })
    table.insert(items, { title = "Questie" })
    for _, entry in ipairs(entries) do table.insert(items, entry) end
end
