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
        -- Auf der Karte nur die Marker verfolgter Quests (= die Quests in unserem Tracker), nicht des ganzen Logs
        questie.db.profile.hideUntrackedQuestsMapIcons = true
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
-- Blizzards Questmarker aus? (Questie läuft, "Blizzard-Questtracker ausblenden" an und im Questlog-Rädchen nicht
-- ausdrücklich "Blizzard-Questmarker anzeigen" gewählt)
local function HideBlizzardMarkers()
    local db = ns.db
    return db and db.hideBlizzard and not db.showBlizzardMarkers and type(_G.Questie) == "table" or false
end

local function ApplyBlizzardMapMarkers()
    local db = ns.db
    if not db or type(_G.Questie) ~= "table" or not (GetCVar and SetCVar) then return end
    if HideBlizzardMarkers() then
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

-- Zusätzlich: Blizzards Quest-Symbole auf der Weltkarte direkt ausblenden (die Spieleinstellung questPOI wirkt im
-- Forever-Client nicht auf alle Symbole, z. B. die gelben "!" der Questgeber). Betrifft nur Blizzards Symbole mit
-- "Quest" in der Vorlage – nicht Questies Symbole (HereBeDragons), Weltquests und Bonusziele. Gleiche Bedingung wie
-- oben: Questie läuft und "Blizzard-Questtracker ausblenden" ist an. /fq karte zeigt die Vorlagen.
local function IsBlizzardQuestPin(template)
    template = tostring(template)
    return template:find("Quest") ~= nil and not template:find("WorldQuest") and not template:find("HereBeDragons")
        and not template:find("Questie") and not template:find("Bonus")
end

local function HideQuestPins(map, template)
    if not HideBlizzardMarkers() then return end
    if not map.EnumeratePinsByTemplate then return end
    for pin in map:EnumeratePinsByTemplate(template) do pin:Hide() end
end

local function HookMapPins()
    local map = _G.WorldMapFrame
    if not map or map.fqQuestPinHook or type(map.AcquirePin) ~= "function" then return end
    map.fqQuestPinHook = true
    hooksecurefunc(map, "AcquirePin", function(self, template)
        if IsBlizzardQuestPin(template) then HideQuestPins(self, template) end
    end)
    for template in pairs(map.pinPools or {}) do
        if IsBlizzardQuestPin(template) then HideQuestPins(map, template) end
    end
end

-- Schalter im Rädchen des Questlogs: Blizzards Questmarker (Ziele/Questgeber) auf der Karte an/aus.
-- Mit Questie: eigene Einstellung (Standard aus, sonst doppelte Marker); ohne Questie: Blizzards Spieleinstellung.
function ns.BlizzardQuestMarkersShown()
    if type(_G.Questie) == "table" then return not HideBlizzardMarkers() end
    return GetCVar and GetCVar("questPOI") ~= "0"
end

function ns.SetBlizzardQuestMarkers(show)
    if type(_G.Questie) == "table" then
        ns.db.showBlizzardMarkers = show or nil
        if show and ns.db.questieHidPOI then
            ns.db.questieHidPOI = nil
            SetCVar("questPOI", "1")
        elseif show and GetCVar("questPOI") == "0" then
            SetCVar("questPOI", "1")
        end
        pcall(ApplyBlizzardMapMarkers)
    elseif SetCVar then
        SetCVar("questPOI", show and "1" or "0")
    end
    -- Karte neu zeichnen, damit die Marker sofort kommen bzw. gehen
    local map = _G.WorldMapFrame
    if map and map.RefreshAllDataProviders then pcall(map.RefreshAllDataProviders, map) end
end

local pinStarter = CreateFrame("Frame")
pinStarter:RegisterEvent("PLAYER_LOGIN")
pinStarter:RegisterEvent("ADDON_LOADED")
pinStarter:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
    if type(_G.Questie) ~= "table" then
        if event == "PLAYER_LOGIN" then self:UnregisterAllEvents() end
        return
    end
    pcall(HookMapPins)
    if _G.WorldMapFrame and _G.WorldMapFrame.fqQuestPinHook then self:UnregisterAllEvents() end
end)

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

-- Questie-Befehle zu einer Quest als Liste { text, onClick, disabled } (leer, wenn Questie nicht läuft).
-- withWowhead: Wowhead-Link mit anbieten (nur im Questlog an der Karte)
function ns.GetQuestieActions(questID, withWowhead)
    local entries = {}
    if not ns.HasQuestie() then return entries end
    local caps = GetCapabilities(questID)

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
    if withWowhead then
        table.insert(entries, { text = ns.L("QUESTIE_WOWHEAD"), disabled = InCombatLockdown(), onClick = function() Call(function()
            Module("TrackerData").RefreshQuest(questID) -- damit der Name im Fenster steht
            Module("QuestiePopup").Show("QUESTIE_WOWHEAD_URL", questID)
        end) end })
    end
    return entries
end

-- Wowhead-Link einer Quest in Questies Fenster zum Kopieren (auch für Quests, die nicht im Questlog stehen)
function ns.ShowQuestieWowhead(questID)
    if not ns.HasQuestie() or not questID or InCombatLockdown() then return end
    pcall(function() Module("TrackerData").RefreshQuest(questID) end) -- Name fürs Fenster; ohne Log egal
    Call(function() Module("QuestiePopup").Show("QUESTIE_WOWHEAD_URL", questID) end)
end

-- Fügt die Questie-Befehle ins Rechtsklick-Menü einer Quest ein (nur wenn Questie läuft)
function ns.AddQuestieMenuItems(items, questID, inLog)
    local entries = ns.GetQuestieActions(questID, inLog)
    if #entries == 0 then return end
    table.insert(items, { divider = true })
    table.insert(items, { title = "Questie" })
    for _, entry in ipairs(entries) do table.insert(items, entry) end
end

---------------------------------------------------------------------------
-- Questie-Kartensymbole einer Quest hervorheben (Maus über einer Quest im Questlog):
-- alle Symbole dieser Quest etwas größer, alle anderen blass; beim Verlassen alles wie vorher
---------------------------------------------------------------------------
local fadedIcons, grownIcons = {}, {}
function ns.QuestieHover(questID)
    for icon, alpha in pairs(fadedIcons) do icon:SetAlpha(alpha) end
    for icon, size in pairs(grownIcons) do icon:SetSize(size[1], size[2]) end
    wipe(fadedIcons)
    wipe(grownIcons)
    if not questID or not ns.HasQuestie() then return end
    pcall(function()
        local frames = Module("QuestieMap").questIdFrames or {}
        if not frames[questID] then return end -- Questie kennt die Quest nicht: nichts abblenden
        for id, list in pairs(frames) do
            for _, name in pairs(list) do
                local icon = _G[name]
                if icon and not icon.miniMapIcon and icon:IsShown() then
                    if id == questID then
                        local w, h = icon:GetSize()
                        grownIcons[icon] = { w, h }
                        icon:SetSize(w * 1.35, h * 1.35)
                    else
                        fadedIcons[icon] = icon:GetAlpha()
                        icon:SetAlpha(0.15)
                    end
                end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Detailansicht im Questlog offen: auf der Karte nur die Marker DIESER Quest (auch wenn sie nicht verfolgt wird),
-- ohne Questgeber-Ausrufezeichen. Zurück in der Übersicht wieder die Marker aller verfolgten Quests.
-- Umsetzung: Questies Abfrage "Marker dieser Quest zeigen?" wird ergänzt (ohne Questie-Dateien zu ändern),
-- danach zeichnet Questie seine Symbole neu.
---------------------------------------------------------------------------
local focusQuestID
local availableBeforeFocus

-- Questies Zeichenfunktionen müssen in einem Coroutine-Faden laufen (sie pausieren zwischendurch): jedes Bild weiter
local function RunThreaded(fn)
    local co = coroutine.create(fn)
    local function Step()
        local ok, err = coroutine.resume(co)
        if not ok then
            print(ns.ChatPrefix() .. ": Questie - " .. tostring(err))
        elseif coroutine.status(co) ~= "dead" then
            C_Timer.After(0, Step)
        end
    end
    Step()
end

local function WrapShouldShow()
    local questieQuest = Module("QuestieQuest")
    if questieQuest.fqWrapped or type(questieQuest.ShouldShowQuestNotes) ~= "function" then return end
    questieQuest.fqWrapped = true
    local original = questieQuest.ShouldShowQuestNotes
    questieQuest.ShouldShowQuestNotes = function(self, questId)
        if focusQuestID then return questId == focusQuestID end
        return original(self, questId)
    end
end

local function RefreshQuestieIcons()
    RunThreaded(function()
        local questieQuest = Module("QuestieQuest")
        -- auch Marker einer nicht verfolgten Quest anlegen (Questie legt sie sonst erst beim Verfolgen an)
        if focusQuestID then
            local quest = Module("QuestieDB").GetQuest(focusQuestID)
            if quest then questieQuest:PopulateObjectiveNotes(quest) end
        end
        questieQuest:ShowQuestIcons()
        questieQuest:HideQuestIcons()
    end)
end

function ns.QuestieFocusDetails(questID)
    if not ns.HasQuestie() then return end
    if questID == focusQuestID then return end
    local ok = pcall(WrapShouldShow)
    if not ok then return end
    local profile = _G.Questie.db.profile
    profile.hideUntrackedQuestsMapIcons = true -- (ohne das fragt Questie gar nicht nach)
    local wasFocused = focusQuestID ~= nil
    focusQuestID = questID
    -- Questgeber-"!" in der Detailansicht aus, danach wieder wie vorher
    if questID and not wasFocused then
        availableBeforeFocus = profile.enableAvailable
        if profile.enableAvailable then
            profile.enableAvailable = false
            Call(function() Module("QuestieQuest").ToggleAvailableQuests(false) end)
        end
    elseif not questID and wasFocused then
        if availableBeforeFocus then
            profile.enableAvailable = true
            Call(function() Module("QuestieQuest").ToggleAvailableQuests(true) end)
        end
        availableBeforeFocus = nil
    end
    RefreshQuestieIcons()
end

-- Beim Ausloggen/Neuladen während offener Detailansicht: Questgeber-Einstellung zurück
do
    local logout = CreateFrame("Frame")
    logout:RegisterEvent("PLAYER_LOGOUT")
    logout:SetScript("OnEvent", function()
        if focusQuestID and availableBeforeFocus and _G.Questie and _G.Questie.db then
            _G.Questie.db.profile.enableAvailable = true
        end
    end)
end

---------------------------------------------------------------------------
-- Questreihe aus Questies Datenbank: Vorquests (rückwärts) und Folgequests (vorwärts).
-- Rückgabe: Liste { questID, name, level } in Reihenfolge, oder nil (Questie fehlt / keine Reihe)
---------------------------------------------------------------------------
local chainCache = {} -- Questreihen ändern sich nicht: einmal berechnet, gemerkt (false = keine Reihe)
function ns.GetQuestChain(questID)
    if not ns.HasQuestie() or not questID then return nil end
    local cached = chainCache[questID]
    if cached ~= nil then return cached or nil end
    local result = ns.BuildQuestChain(questID)
    -- alle Quests der Reihe teilen sich dieselbe Liste
    if result then
        for _, entry in ipairs(result) do chainCache[entry.questID] = result end
    end
    chainCache[questID] = result or false
    return result
end

function ns.BuildQuestChain(questID)
    if not ns.HasQuestie() then return nil end
    local ok, chain = pcall(function()
        local db = Module("QuestieDB")
        local function Entry(id)
            return { questID = id, name = db.QueryQuestSingle(id, "name"), level = db.QueryQuestSingle(id, "questLevel"),
                requiredLevel = db.QueryQuestSingle(id, "requiredLevel"),
                objectives = db.QueryQuestSingle(id, "objectivesText") }
        end
        local function Previous(id)
            for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
                local list = db.QueryQuestSingle(id, key)
                if type(list) == "table" and list[1] then return list[1] end
            end
        end
        local list, seen = { Entry(questID) }, { [questID] = true }
        local id = Previous(questID)
        while id and not seen[id] and #list < 15 do
            seen[id] = true
            table.insert(list, 1, Entry(id))
            id = Previous(id)
        end
        id = db.QueryQuestSingle(questID, "nextQuestInChain")
        while id and id ~= 0 and not seen[id] and #list < 25 do
            seen[id] = true
            table.insert(list, Entry(id))
            id = db.QueryQuestSingle(id, "nextQuestInChain")
        end
        return list
    end)
    if ok and chain and #chain > 1 then return chain end
end

-- Einzelheiten einer Quest, die (noch) nicht im Questlog steht – das Spiel liefert dafür nichts, Questies Datenbank
-- schon: Questziele mit Anzahl, Questgeber, Abgabe, Erfahrung, Geld. (Beschreibung und Gegenstände kennt sie nicht.)
function ns.GetQuestieQuestDetails(questID)
    if not ns.HasQuestie() then return nil end
    local ok, details = pcall(function()
        local db = Module("QuestieDB")
        local function Name(kind, id)
            local query = (kind == "npc" and db.QueryNPCSingle) or (kind == "object" and db.QueryObjectSingle)
                or db.QueryItemSingle
            return query and query(id, "name")
        end
        local result = { objectives = {}, name = db.QueryQuestSingle(questID, "name"),
            level = db.QueryQuestSingle(questID, "questLevel"), requiredLevel = db.QueryQuestSingle(questID, "requiredLevel"),
            objectivesText = db.QueryQuestSingle(questID, "objectivesText") }
        -- Ziele: [1] Gegner, [2] Objekte, [3] Gegenstände (je { id, text, anzahl })
        local objectives = db.QueryQuestSingle(questID, "objectives")
        if type(objectives) == "table" then
            for index, kind in ipairs({ "npc", "object", "item" }) do
                for _, entry in ipairs(objectives[index] or {}) do
                    local name = entry[2] or Name(kind, entry[1])
                    if name then
                        local count = tonumber(entry[3]) or 1
                        table.insert(result.objectives, name .. ": 0/" .. count)
                    end
                end
            end
        end
        -- Questgeber und Abgabe: erste bekannte Person (sonst Objekt/Gegenstand)
        local function FirstName(list)
            if type(list) ~= "table" then return nil end
            for index, kind in ipairs({ "npc", "object", "item" }) do
                local ids = list[index]
                if type(ids) == "table" and ids[1] then
                    local name = Name(kind, ids[1])
                    if name then return name end
                end
            end
        end
        result.starter = FirstName(db.QueryQuestSingle(questID, "startedBy"))
        result.finisher = FirstName(db.QueryQuestSingle(questID, "finishedBy"))
        local questXP = Module("QuestXP")
        if questXP and questXP.db and questXP.GetQuestLogRewardXP then
            result.xp = questXP:GetQuestLogRewardXP(questID)
        end
        if GetQuestLogRewardMoney then
            local okMoney, money = pcall(GetQuestLogRewardMoney, questID)
            if okMoney then result.money = money end
        end
        return result
    end)
    return ok and details or nil
end

-- Gegenstandsbelohnungen aus Questies Datenbank: Questie führt bei jedem Gegenstand, welche Quests ihn als
-- Belohnung geben ("questRewards"). Daraus wird einmal ein Verzeichnis Quest -> Gegenstände gebaut (im Hintergrund,
-- über mehrere Bilder verteilt). Feste Belohnung und Auswahl unterscheidet Questie dabei nicht.
local rewardIndex, rewardIndexState -- Verzeichnis; Stand nil (nicht begonnen) / "building" / "done"
local function BuildRewardIndex()
    rewardIndexState = "building"
    RunThreaded(function()
        local db = Module("QuestieDB")
        local index, count = {}, 0
        for itemID in pairs(db.ItemPointers or {}) do
            local quests = db.QueryItemSingle(itemID, "questRewards")
            if type(quests) == "table" then
                for _, questID in ipairs(quests) do
                    index[questID] = index[questID] or {}
                    table.insert(index[questID], itemID)
                end
            end
            count = count + 1
            if count % 400 == 0 then coroutine.yield() end
        end
        rewardIndex, rewardIndexState = index, "done"
        if ns.RequestDungeonRefresh then ns.RequestDungeonRefresh() end
    end)
end

function ns.GetQuestieRewardItems(questID)
    if not ns.HasQuestie() then return nil end
    if not rewardIndexState then pcall(BuildRewardIndex) end
    return rewardIndex and questID and rewardIndex[questID] or nil
end

-- Rufbelohnungen aus Questies Datenbank: Liste { factionID, amount }
function ns.GetQuestieReputation(questID)
    if not ns.HasQuestie() then return nil end
    local ok, list = pcall(function() return Module("QuestieDB").QueryQuestSingle(questID, "reputationReward") end)
    return ok and type(list) == "table" and list or nil
end

---------------------------------------------------------------------------
-- Questie-Kartenschalter fürs Rädchen im Questlog (ersetzen Blizzards Kartenmenü, das mit Questie nichts bewirkt)
---------------------------------------------------------------------------
function ns.GetQuestieMapToggles()
    if not ns.HasQuestie() or not (_G.Questie.db and _G.Questie.db.profile) then return nil end
    local profile = _G.Questie.db.profile
    local function Toggle(key, apply)
        return {
            checked = function() return profile[key] and true or false end,
            onClick = function() profile[key] = not profile[key]; Call(function() apply(profile[key]) end) end,
        }
    end
    local available = Toggle("enableAvailable", function(v) Module("QuestieQuest").ToggleAvailableQuests(v) end)
    local objectives = Toggle("enableObjectives", function(v) Module("QuestieQuest"):ToggleNotes(v) end)
    local turnins = Toggle("enableTurnins", function(v) Module("QuestieQuest").ToggleAvailableQuests(v) end)
    -- Niedrigstufige Quests: Questies Einstellung "alle zeigen" (2) bzw. "keine" (1)
    local lowLevel = {
        checked = function() return profile.lowLevelStyle == (_G.Questie.LOWLEVEL_ALL or 2) end,
        onClick = function()
            local all = _G.Questie.LOWLEVEL_ALL or 2
            profile.lowLevelStyle = (profile.lowLevelStyle == all) and (_G.Questie.LOWLEVEL_NONE or 1) or all
            Call(function()
                local availableQuests = Module("AvailableQuests")
                availableQuests.ResetLevelRequirementCache()
                availableQuests.CalculateAndDrawAll()
            end)
        end,
    }
    return { available = available, objectives = objectives, turnins = turnins, lowLevel = lowLevel }
end

---------------------------------------------------------------------------
-- Schutz: Ist Questie veraltet (andere Datenbank/Funktionen), darf ein Fehler darin nie ein Fehlerfenster
-- auslösen. Jede Questie-Abfrage läuft geschützt; beim ersten Fehler gibt es eine Chatmeldung und die
-- Questie-Anbindung wird für diese Sitzung abgeschaltet (alles läuft dann wie ohne Questie).
---------------------------------------------------------------------------
local questieBroken = false
local hasQuestie = ns.HasQuestie
function ns.HasQuestie()
    return not questieBroken and hasQuestie() and true or false
end

for _, key in ipairs({ "GetQuestieActions", "AddQuestieMenuItems", "QuestieHover", "QuestieFocusDetails",
    "GetQuestChain", "BuildQuestChain", "GetQuestieQuestDetails", "GetQuestieRewardItems",
    "GetQuestieReputation", "GetQuestieMapToggles", "ShowQuestieWowhead" }) do
    local fn = ns[key]
    local function Finish(ok, ...)
        if ok then return ... end
        if not questieBroken then
            questieBroken = true
            print(ns.ChatPrefix() .. ": " .. ns.L("QUESTIE_BROKEN", tostring((...))))
        end
        return nil
    end
    ns[key] = function(...) return Finish(pcall(fn, ...)) end
end
