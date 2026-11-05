local addonName, ns = ...

-- Fenster mit allen Dungeons und ihren Quests (Daten aus Data\Dungeons.lua)

local window
local listScroll, listContent, searchBox
local detailTitle, detailExtra, detailEmpty, questScroll, questContent, pillRow, atlasButton, shareAllButton, groupButton
local listButtons = {}
local questEntries = {}
local pills = {}
local selectedDungeon
local onlyOwnFaction = true
local hideCompleted = false -- Häkchen "Abgeschlossene ausblenden"
local levelTabActive = true -- Reiter "Mein Levelbereich" (standardmäßig gewählt)
local raidTabActive = false  -- Reiter "Schlachtzüge" (die anderen Reiter zeigen nur Dungeons)
local logTabActive = false   -- Reiter "Questlog" (eigene Quests nach Gebieten)
local LEVEL_EARLY = 2        -- Dungeons schon so viele Level vor dem Mindestlevel zeigen
local refreshPending = false

-- Gesamtliste der Dungeons (füllt QuestieDungeons.lua); ns.DUNGEON_DATA ist die angezeigte Liste
local ALL_DUNGEONS = ns.DUNGEON_DATA
ns.ALL_DUNGEON_DATA = ALL_DUNGEONS -- vollständige Liste (QuestieDungeons.lua ergänzt sie mit Questies Daten)

-- (früher Beta-Modus "nur bis Stufe 30"; entfernt – was es in der Beta nicht gibt, meldet jetzt der Server,
-- siehe "Not available in Beta")
function ns.ApplyBetaFilter()
    selectedDungeon = nil -- die Auswahl zeigt sonst auf einen Dungeon der alten Liste
    ns.DUNGEON_DATA = ALL_DUNGEONS
end

local LIST_WIDTH = 320 -- (Platz für vier Reiter: Mein Level, Dungeons, Schlachtzüge, Questlog)
local LIST_ROW_HEIGHT = 44
local HEADER_HEIGHT = 40
local FOOTER_HEIGHT = 40

-- Farben im flachen, dunklen Stil
-- Grundfarben zentral aus ForeverCore (über ns.Style.COLOR), dazu die eigenen Kartenfarben des Dungeonfensters
local COLOR = setmetatable({
    card = { 0.13, 0.13, 0.16, 1 },
    cardHover = { 0.18, 0.18, 0.22, 1 },
}, { __index = ns.Style.COLOR })
local FLAT_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
-- Fraktionsnamen kommen aus Locales.lua
local FACTION_TEXT_KEY = { Horde = "FACTION_HORDE", Alliance = "FACTION_ALLIANCE", Both = "FACTION_BOTH" }
local function FactionText(faction)
    return ns.L(FACTION_TEXT_KEY[faction] or faction)
end
local FACTION_PILL = {
    Horde = { 0.55, 0.10, 0.10, 0.8 },
    Alliance = { 0.12, 0.25, 0.60, 0.8 },
    Both = { 0.22, 0.22, 0.26, 1 },
}
local FACTION_ICON = {
    Horde = "Interface\\FriendsFrame\\PlusManz-Horde",
    Alliance = "Interface\\FriendsFrame\\PlusManz-Alliance",
}
local STATUS = {
    DONE = { textKey = "STATUS_DONE", stripe = { 0.2, 0.8, 0.3 }, pill = { 0.12, 0.40, 0.18, 0.9 } },
    ACTIVE = { textKey = "STATUS_ACTIVE", stripe = { 1, 0.82, 0 }, pill = { 0.45, 0.35, 0.05, 0.9 } },
    READY = { textKey = "STATUS_READY", stripe = { 0.2, 0.8, 0.3 }, pill = { 0.12, 0.40, 0.18, 0.9 } }, -- (Questlog: abgabebereit)
    OPEN = { stripe = { 0.35, 0.35, 0.40 } },
}

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------

local function SetFlat(frame, bg, border)
    frame:SetBackdrop(FLAT_BACKDROP)
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border or COLOR.border))
end

-- Questfortschritt anhand der Quest-ID: "DONE", "ACTIVE", "OPEN" oder nil (keine ID)
-- Text aus dem Quest-Tooltip des Spiels (Ziel/Beschreibung), über die Quest-ID.
-- Ist die Quest noch nicht geladen, wird sie angefordert; das Fenster aktualisiert sich danach.
local questTextCache = {}
local questTitleCache = {}   -- Questname aus Zeile 1 des Quest-Tooltips
local requestedQuests = {}   -- [questID] = Zeitpunkt der letzten Anfrage beim Server
local requestTries = {}      -- [questID] = Anzahl der Anfragen
-- Quests, die es in der Beta nicht gibt: NUR wenn der Server das ausdrücklich meldet (QUEST_DATA_LOAD_RESULT mit
-- "nicht erfolgreich"). Bleibt eine Antwort einfach aus, gilt die Quest NICHT als unbekannt.
local unknownQuests = {}
local REQUEST_RETRY_SECONDS = 5
local REQUEST_MAX_TRIES = 3

-- Questdaten beim Server anfordern. Kommt keine Antwort, wird es nach ein paar Sekunden erneut versucht
-- (höchstens ein paar Mal).
local function RequestQuestData(questID)
    if unknownQuests[questID] or not C_QuestLog.RequestLoadQuestByID then return end
    local last = requestedQuests[questID]
    if last and GetTime() - last < REQUEST_RETRY_SECONDS then return end
    local tries = requestTries[questID] or 0
    if tries >= REQUEST_MAX_TRIES then return end
    requestTries[questID] = tries + 1
    requestedQuests[questID] = GetTime()
    C_QuestLog.RequestLoadQuestByID(questID)
    -- Falls keine Antwort kommt: Fenster später neu aufbauen, dabei wird erneut angefragt
    C_Timer.After(REQUEST_RETRY_SECONDS + 0.5, function()
        if ns.RequestDungeonRefresh then ns.RequestDungeonRefresh() end
    end)
end

-- Antwort des Servers: "nicht erfolgreich" heißt, die Quest-ID gibt es im Spiel (noch) nicht
local questLoadListener = CreateFrame("Frame")
questLoadListener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
questLoadListener:SetScript("OnEvent", function(_, _, questID, success)
    if questID and success == false then unknownQuests[questID] = true end
end)

-- Gibt es keine einzige Quest des Dungeons in der Beta? (nur, was der Server ausdrücklich als unbekannt meldet)
-- Seit dem Live-Start meldet der Server bei JEDER angefragten Quest "nicht erfolgreich" – der frühere Vermerk "Not
-- available in Beta" stand dadurch überall. Er wird nicht mehr gezeigt (die Antwort dient nur noch dazu, nicht
-- endlos nachzufragen).
local SHOW_NOT_IN_BETA = false
local function DungeonNotInBeta(dungeon)
    if not SHOW_NOT_IN_BETA then return false end
    local any = false
    for _, quest in ipairs(dungeon.quests or {}) do
        if quest.id then
            if not unknownQuests[quest.id] then return false end
            any = true
        end
    end
    return any
end

-- Einmal je Sitzung alle Dungeonquests beim Server prüfen (gestaffelt, damit nichts ruckelt):
-- Quests mit bekanntem Namen gibt es; die übrigen werden angefragt, die Antwort setzt ggf. "Not available in Beta"
local betaCheckStarted = false
local function CheckAllDungeonQuests()
    -- Ohne den Vermerk "Not available in Beta" bringt die Prüfung nichts mehr – sie fragte Hunderte Quests an, und jede
    -- Antwort baute das offene Fenster neu auf (Ruckeln). Daher abgeschaltet.
    if not SHOW_NOT_IN_BETA then return end
    if betaCheckStarted or not C_QuestLog.RequestLoadQuestByID or #(ns.DUNGEON_DATA or {}) == 0 then return end
    betaCheckStarted = true
    local pending = {}
    for _, dungeon in ipairs(ns.DUNGEON_DATA) do
        for _, quest in ipairs(dungeon.quests or {}) do
            if quest.id and not C_QuestLog.GetTitleForQuestID(quest.id) then pending[#pending + 1] = quest.id end
        end
    end
    local index = 0
    local function Next()
        for _ = 1, 10 do
            index = index + 1
            local questID = pending[index]
            if not questID then
                C_Timer.After(2, function() if ns.RequestDungeonRefresh then ns.RequestDungeonRefresh() end end)
                return
            end
            RequestQuestData(questID)
        end
        C_Timer.After(0.2, Next)
    end
    Next()
end

local tooltipFailedAt = {} -- [questID] = Zeitpunkt, an dem der Tooltip zuletzt noch keinen Text hatte
local function GetQuestTooltipText(questID)
    if not questID then return nil end
    if questTextCache[questID] then return questTextCache[questID] end
    -- Tooltip ohne Text nicht bei jedem Neuaufbau erneut lesen (teuer), sondern höchstens alle paar Sekunden
    local failed = tooltipFailedAt[questID]
    if failed and GetTime() - failed < REQUEST_RETRY_SECONDS then return nil end
    tooltipFailedAt[questID] = GetTime()
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink("quest:" .. questID)
        -- Zeile 1 ist der Questname: merken, falls das Spiel ihn sonst noch nicht liefert
        local firstLine = data and data.lines and data.lines[1] and data.lines[1].leftText
        if firstLine and firstLine ~= "" and not (RETRIEVING_DATA and firstLine:find(RETRIEVING_DATA, 1, true)) then
            questTitleCache[questID] = firstLine
        end
        if data and data.lines and #data.lines > 1 then
            local parts = {}
            for i = 2, #data.lines do -- Zeile 1 ist der Questname
                local line = data.lines[i].leftText
                -- Abschnitt "Anforderungen:" weglassen (er steht am Ende des Tooltips)
                local trimmed = line and strtrim(line) or ""
                if trimmed == (QUEST_TOOLTIP_REQUIREMENTS or "Anforderungen:")
                    or trimmed == "Anforderungen:" or trimmed == "Requirements:" then
                    break
                end
                if trimmed ~= "" then
                    table.insert(parts, line)
                end
            end
            local text = table.concat(parts, "  ")
            if text ~= "" and not (RETRIEVING_DATA and text:find(RETRIEVING_DATA, 1, true)) then
                questTextCache[questID] = text
                tooltipFailedAt[questID] = nil
                return text
            end
        end
    end
    RequestQuestData(questID)
    return nil
end

local function GetQuestStatus(questID)
    if not questID then return nil end
    if C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return "DONE"
    end
    if C_QuestLog.GetLogIndexForQuestID(questID) then
        return "ACTIVE"
    end
    return "OPEN"
end

-- Name in der aktiven Sprache: bei Englisch das Feld "...EN" (falls eingetragen), sonst das deutsche
local function Localized(tbl, field)
    if ns.GetLanguage() == "enUS" then
        local value = tbl[field .. "EN"]
        if value and value ~= "" then return value end
    end
    return tbl[field]
end

-- Questname aus dem Spiel (über die Quest-ID, in der Client-Sprache).
-- Noch nicht geladene Quests werden angefordert; das Fenster aktualisiert sich, sobald die Daten da sind.
local function GetGameQuestTitle(questID)
    if not questID then return nil end
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then return title end
    -- Zweite Quelle: Name aus dem Quest-Tooltip des Spiels (füllt questTitleCache)
    if not questTitleCache[questID] then GetQuestTooltipText(questID) end
    if questTitleCache[questID] then return questTitleCache[questID] end
    RequestQuestData(questID)
    return nil
end

-- Platzhalter ohne Namen: "Quest 1234 (wird geladen …)" bzw. "Unbekannte Quest (ID 1234)"
local function QuestIDFallback(questID)
    if SHOW_NOT_IN_BETA and questID and unknownQuests[questID] then return ns.L("QUEST_UNKNOWN", questID) end
    return ns.L("QUEST_FALLBACK", questID or 0)
end

-- Anzeigename: aus dem Spiel, sonst aus Questies Daten, sonst Platzhalter.
-- Kennt das Spiel die Quest-ID nicht, steht "(Not available in Beta)" dahinter.
local function QuestName(quest)
    local title = GetGameQuestTitle(quest.id)
    if title then return title end
    local name = Localized(quest, "name")
    if SHOW_NOT_IN_BETA and name and quest.id and unknownQuests[quest.id] then
        return name .. " " .. ns.L("NOT_IN_BETA")
    end
    return name or QuestIDFallback(quest.id)
end

-- Questlevel: aus Questies Daten oder aus dem Spiel
local function QuestLevel(quest)
    local level = tonumber((quest.level or ""):match("%d+"))
    if not level and quest.id and C_QuestLog.GetQuestDifficultyLevel then
        level = C_QuestLog.GetQuestDifficultyLevel(quest.id)
        if level == 0 then level = nil end
    end
    return level
end

-- Vorquest: Quest-ID -> Name aus dem Spiel, sonst der eingetragene Name
local function PrequestText(quest)
    if quest.prequestID then
        return GetGameQuestTitle(quest.prequestID) or QuestIDFallback(quest.prequestID)
    end
    return quest.prequest
end

-- Questgeber: Name aus Questies Daten oder - wenn die Quest von einem Gegenstand startet -
-- Symbol und Name des Gegenstands aus dem Spiel (über die Item-ID).
-- Noch nicht geladene Gegenstände werden angefordert (Ereignis ITEM_DATA_LOAD_RESULT aktualisiert das Fenster).
local requestedItems = {}
local function GiverText(quest, withIcon)
    local itemID = quest.giverItemID
    if not itemID then return Localized(quest, "giver") end
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name then
        if not requestedItems[itemID] and C_Item.RequestLoadItemDataByID then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return ns.L("ITEM_LOADING", itemID)
    end
    local icon = withIcon and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    return (icon and ("|T" .. icon .. ":14:14:0:0|t ") or "") .. "[" .. name .. "]"
end

-- Klasse: Klassen-ID -> Klassenname in der Client-Sprache
local function ClassText(quest)
    if quest.classID then
        local name = GetClassInfo and GetClassInfo(quest.classID)
        if not name and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
            local info = C_CreatureInfo.GetClassInfo(quest.classID)
            name = info and info.className
        end
        return name or ns.L("CLASS_FALLBACK", quest.classID)
    end
    return quest.class
end

local function IsMyFaction(faction)
    return not faction or faction == "Both" or faction == UnitFactionGroup("player")
end

local function IsCompleted(quest)
    return quest.id ~= nil and C_QuestLog.IsQuestFlaggedCompleted(quest.id)
end

-- Reiter "Mein Level": Dungeon passt, wenn das eigene Level im Levelbereich liegt; Dungeons, deren Mindestlevel
-- bis zu N Level über dem eigenen liegt, zählen mit (N = Regler unten im Fenster, 0–10, Standard 2)
local function IsDungeonInMyRange(dungeon)
    local minLevel, maxLevel = (dungeon.levels or ""):match("(%d+)%D+(%d+)")
    minLevel, maxLevel = tonumber(minLevel), tonumber(maxLevel)
    if not minLevel then return true end
    local level = UnitLevel("player")
    local above = ns.db and tonumber(ns.db.dungeonLevelAbove) or LEVEL_EARLY
    return level >= minLevel - above and level <= maxLevel
end

-- Filter ohne "Abgeschlossene ausblenden" (Fraktion). Der Reiter "Mein Level" filtert nur die Dungeons der Liste,
-- nicht die Quests darin – im passenden Dungeon sind alle seine Quests zu sehen.
local function PassesBaseFilters(quest)
    return not onlyOwnFaction or IsMyFaction(quest.faction)
end

local function IsQuestVisible(quest)
    if hideCompleted and IsCompleted(quest) then return false end
    return PassesBaseFilters(quest)
end

-- Verbleibende (noch nicht abgeschlossene) und abgeschlossene Quests eines Dungeons
local function CountQuests(dungeon)
    local remaining, completed = 0, 0
    for _, quest in ipairs(dungeon.quests or {}) do
        if PassesBaseFilters(quest) then
            if IsCompleted(quest) then completed = completed + 1 else remaining = remaining + 1 end
        end
    end
    return remaining, completed
end

-- Reiter "Questlog": die Quests aus dem eigenen Questlog als Karten im Stil der Dungeonquests. Links stehen wie bei
-- den Dungeons Einträge – "Alle Quests" (QUESTLOG) und je Gebiet (Überschrift im Questlog) einer. Wird bei jedem
-- Anzeigen neu aus dem Questlog gelesen; Tracker und Questlog der Weltkarte bleiben unverändert.
local QUESTLOG = { name = "", isLog = true, quests = {} }
local logZones = {}     -- [Gebietsname] = Eintrag (bleibt erhalten, damit die Auswahl beim Neuaufbau bestehen bleibt)
local logZoneOrder = {} -- Gebiete in der Reihenfolge des Questlogs
local logQuestCache = {} -- [Quest-ID] = Eintrag (bleibt über Neuaufbauten erhalten)
local function RefreshLogQuests()
    QUESTLOG.name = ns.L("QUESTLOG_ALL")
    for _, z in pairs(logZones) do z.quests = {} end
    wipe(logZoneOrder)
    local quests, zone = {}, nil
    local num = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, num do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                zone = info.title
            elseif not info.isHidden and info.questID and info.questID > 0 then
                -- dieselbe Tabelle je Quest behalten (z. B. merkt sich das Fenster daran, ob die Belohnungen offen sind)
                local quest = logQuestCache[info.questID]
                if not quest then
                    quest = { id = info.questID, isLog = true }
                    logQuestCache[info.questID] = quest
                end
                quest.name, quest.zone = info.title, zone
                quest.level = (info.level and info.level > 0) and tostring(info.level) or nil
                quests[#quests + 1] = quest
                local key = zone or "?"
                local entry = logZones[key]
                if not entry then
                    entry = { name = key, isLog = true, quests = {} }
                    logZones[key] = entry
                end
                if #entry.quests == 0 then logZoneOrder[#logZoneOrder + 1] = entry end
                table.insert(entry.quests, quest)
            end
        end
    end
    QUESTLOG.quests = quests
    return quests
end

-- Questlog-Quest abgabebereit (alle Ziele erfüllt)?
local function IsLogQuestReady(questID)
    return questID and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) and true or false
end

local function LogReadyCount(entry)
    local n = 0
    for _, quest in ipairs((entry or QUESTLOG).quests) do
        if IsLogQuestReady(quest.id) then n = n + 1 end
    end
    return n
end

-- Ziele einer Questlog-Quest mit Fortschritt (erfüllte grün), je Ziel eine Zeile; ohne Ziele der Questtext
local function LogObjectivesText(questID)
    local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" or #objectives == 0 then return GetQuestTooltipText(questID) or "" end
    local lines = {}
    for _, o in ipairs(objectives) do
        if o.text and o.text ~= "" then
            lines[#lines + 1] = (o.finished and "|cff55cc66" or "|cffdddddd") .. "• " .. o.text .. "|r"
        end
    end
    return table.concat(lines, "\n")
end

-- Quest im Chat verlinken: echter Questlink (über die ID), sonst der Name in eckigen Klammern
local function LinkQuestInChat(quest)
    local link = quest.id and GetQuestLink and GetQuestLink(quest.id)
    if not link then link = "[" .. QuestName(quest) .. "]" end
    -- In ein offenes Chat-Eingabefeld einfügen, sonst das Chat-Eingabefeld mit dem Link öffnen
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
    if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then return end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

---------------------------------------------------------------------------
-- Questketten: aus den Vorquests (ID oder Name) aller Dungeon-Quests gebildet
---------------------------------------------------------------------------

local CHAIN_MAX_STEPS = 12 -- Schutz gegen Schleifen in den Daten
local chainIndex           -- wird beim ersten Gebrauch aufgebaut

local function ChainKey(name) return (name or ""):lower():gsub("%s+", " ") end

local function BuildChainIndex()
    chainIndex = { byID = {}, byName = {}, nextOf = {} }
    for _, dungeon in ipairs(ns.DUNGEON_DATA) do
        for _, quest in ipairs(dungeon.quests or {}) do
            if quest.id and not chainIndex.byID[quest.id] then chainIndex.byID[quest.id] = quest end
            for _, name in ipairs({ quest.name, quest.nameEN }) do
                if name and not chainIndex.byName[ChainKey(name)] then chainIndex.byName[ChainKey(name)] = quest end
            end
        end
    end
end

-- Vorgänger einer Quest: Quest aus den Daten, sonst ein Platzhalter mit ID bzw. Name
local function ChainPrevious(quest)
    if quest.prequestID then
        return chainIndex.byID[quest.prequestID] or { id = quest.prequestID, external = true }
    elseif quest.prequest then
        return chainIndex.byName[ChainKey(quest.prequest)] or { name = quest.prequest, external = true }
    end
end

-- Nachfolger: die erste Quest in den Daten, deren Vorquest diese Quest ist
local function ChainNext(quest)
    if chainIndex.nextOf[quest] == nil then
        local found = false -- false = kein Nachfolger (zwischengespeichert)
        for _, dungeon in ipairs(ns.DUNGEON_DATA) do
            for _, other in ipairs(dungeon.quests or {}) do
                if other ~= quest and ChainPrevious(other) == quest then
                    found = other
                    break
                end
            end
            if found then break end
        end
        chainIndex.nextOf[quest] = found
    end
    return chainIndex.nextOf[quest] or nil
end

-- Ganze Kette, in der die Quest steht (vom Anfang bis zum Ende), und ihre Position darin
local function GetQuestChain(quest)
    if not chainIndex then BuildChainIndex() end
    local before, seen = {}, { [quest] = true }
    local current = quest
    for _ = 1, CHAIN_MAX_STEPS do
        local previous = ChainPrevious(current)
        if not previous or seen[previous] then break end
        seen[previous] = true
        table.insert(before, 1, previous)
        if previous.external then break end
        current = previous
    end
    local chain = before
    table.insert(chain, quest)
    local position = #chain
    current = quest
    for _ = 1, CHAIN_MAX_STEPS do
        local nextQuest = ChainNext(current)
        if not nextQuest or seen[nextQuest] then break end
        seen[nextQuest] = true
        table.insert(chain, nextQuest)
        current = nextQuest
    end
    return chain, position
end

-- Zeile für die Quest-Karte. Mit Questie: kurz "Questreihe 2/5" – die ganze Reihe steht wie im Questlog in der
-- Detailansicht (Klick auf die Karte). Ohne Questie wie bisher: "Questkette (2/3): A › B › C".
-- Erledigte Teile grün, die aktuelle Quest weiß, offene Teile grau. nil, wenn die Quest allein steht.
local function ChainText(quest)
    local questieChain = quest.id and ns.GetQuestChain and ns.GetQuestChain(quest.id)
    if questieChain then
        for i, entry in ipairs(questieChain) do
            if entry.questID == quest.id then
                return "|cff888888" .. ns.L("QUEST_CHAIN_SHORT", i, #questieChain) .. "|r"
            end
        end
    end
    local chain, position = GetQuestChain(quest)
    if #chain < 2 then return nil end
    local names = {}
    for i, part in ipairs(chain) do
        local name = part.external and (GetGameQuestTitle(part.id) or part.name or QuestIDFallback(part.id))
            or QuestName(part)
        local color = "|cff9a9a9a"
        if i == position then
            color = "|cffffffff"
        elseif part.id and C_QuestLog.IsQuestFlaggedCompleted(part.id) then
            color = "|cff55cc66"
        end
        table.insert(names, color .. name .. "|r")
    end
    return "|cff888888" .. ns.L("QUEST_CHAIN", position, #chain) .. "|r " .. table.concat(names, " |cff666666›|r ")
end

-- Alle anderen Gruppenmitglieder (Einheiten wie "party1")
local function GetGroupUnits()
    local units = {}
    if not IsInGroup() then return units end
    local prefix, count = "party", GetNumSubgroupMembers()
    if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            table.insert(units, unit)
        end
    end
    return units
end

-- Wer in der Gruppe die Quest im Questlog hat und wem sie fehlt.
-- Rückgabe: Liste "hat sie", Liste "fehlt" (Namen). includeSelf = den eigenen Charakter mitzählen ("Du").
local function GetGroupQuestStatus(questID, includeSelf)
    local have, missing = {}, {}
    if not questID or not C_QuestLog.IsUnitOnQuest then return have, missing end
    if includeSelf then
        table.insert(C_QuestLog.GetLogIndexForQuestID(questID) and have or missing, ns.L("YOU"))
    end
    for _, unit in ipairs(GetGroupUnits()) do
        table.insert(C_QuestLog.IsUnitOnQuest(unit, questID) and have or missing, (UnitName(unit)))
    end
    return have, missing
end

---------------------------------------------------------------------------
-- Gruppenabgleich "Wer hat was?" (Knopf "Gruppe", Tooltip)
-- Mitspieler mit ForeverQuests melden auf Anfrage unsichtbar ihren Stand zu den Dungeonquests:
--   L = im Questlog, F = im Questlog und fertig, C = schon erledigt, N = noch nicht (fehlt)
-- Ohne ForeverQuests verrät das Spiel nur, ob jemand die Quest gerade im Log hat (sonst "fehlt?").
-- Nachrichten (Kennung "FQDNG"):  Q|<id>,<id>,…  Anfrage   R|<id>:<Stand>,…  Antwort
---------------------------------------------------------------------------
local DNG_PREFIX = "FQDNG"
local issecret = issecretvalue or function() return false end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, DNG_PREFIX) end
local groupReplies = {}   -- [Vorname] = { [questID] = Stand }
local groupProgress = {}  -- [Vorname] = { [questID] = { erledigt, nötig } } (Questziele, nur Quests im Log)
local lastRequest = {}    -- [Dungeon] = Zeitpunkt der letzten Anfrage

local function DngChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function DngSend(message)
    local channel = DngChannel()
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, DNG_PREFIX, message, channel)
    end
end

-- nur der Vorname (Forever liefert Namen teils mit Nachnamen/Realm)
local function DngShortName(name)
    if not name or issecret(name) then return nil end
    if Ambiguate then name = Ambiguate(name, "short") end
    return name:match("^[^%s%-]+") or name
end

-- eigener Stand zu einer Quest
local function MyDungeonState(questID)
    if C_QuestLog.GetLogIndexForQuestID(questID) then
        return C_QuestLog.IsComplete(questID) and "F" or "L"
    end
    if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) then return "C" end
    return "N"
end

-- eigener Fortschritt einer Quest im Log: Summe der erfüllten / nötigen Questziele (nil, wenn unbekannt)
local function MyQuestProgress(questID)
    if not C_QuestLog.GetLogIndexForQuestID(questID) or not C_QuestLog.GetQuestObjectives then return nil end
    local ok, done, total = pcall(function()
        local d, t = 0, 0
        for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
            local need = tonumber(objective.numRequired) or 0
            if need <= 0 then need = 1 end
            local have = tonumber(objective.numFulfilled) or (objective.finished and need or 0)
            if objective.finished then have = need end
            d, t = d + math.min(have, need), t + need
        end
        return d, t
    end)
    if ok and total and total > 0 then return done, total end
end

local function DungeonQuestIDs(dungeon)
    local ids, seen = {}, {}
    for _, quest in ipairs(dungeon and dungeon.quests or {}) do
        if quest.id and not seen[quest.id] and PassesBaseFilters(quest) then
            seen[quest.id] = true
            ids[#ids + 1] = quest.id
        end
    end
    return ids
end

-- Anfrage an die Gruppe (höchstens alle 5 Sekunden je Dungeon); in Stücken, damit keine Nachricht zu lang wird
local function RequestGroupStatus(dungeon)
    if not dungeon or not IsInGroup() then return end
    local now = GetTime()
    if lastRequest[dungeon] and now - lastRequest[dungeon] < 5 then return end
    lastRequest[dungeon] = now
    local ids, chunk = DungeonQuestIDs(dungeon), {}
    for i, id in ipairs(ids) do
        chunk[#chunk + 1] = id
        if #chunk == 25 or i == #ids then
            DngSend("Q|" .. table.concat(chunk, ","))
            wipe(chunk)
        end
    end
end

-- Stand eines Mitspielers: aus seiner Antwort, sonst nur "hat sie im Log" / "unbekannt"
local function MemberState(unit, name, questID)
    local reply = groupReplies[name]
    if reply and reply[questID] then return reply[questID], true end
    if C_QuestLog.IsUnitOnQuest and C_QuestLog.IsUnitOnQuest(unit, questID) then return "L", false end
    return "?", false
end

local STATE_COLORS = { L = "|cff33ff99", F = "|cffffd100", C = "|cff888888", N = "|cffff7070", ["?"] = "|cffcc8888" }

-- Tooltip des Knopfs "Gruppe": je Quest des Dungeons jedes Gruppenmitglied in der Farbe seines Stands
local function FillGroupTooltip(tooltip, dungeon)
    RequestGroupStatus(dungeon)
    tooltip:AddLine(ns.L("TIP_GROUP_TITLE"), 1, 0.82, 0)
    local units = GetGroupUnits()
    local anyMissing = false
    for _, questID in ipairs(DungeonQuestIDs(dungeon)) do
        local parts, allDone = {}, true
        local mine = MyDungeonState(questID)
        parts[1] = STATE_COLORS[mine] .. ns.L("YOU") .. "|r"
        if mine == "N" then allDone = false end
        for _, unit in ipairs(units) do
            local name = DngShortName(UnitName(unit))
            if name then
                local state, known = MemberState(unit, name, questID)
                if state == "N" or state == "?" then allDone = false end
                parts[#parts + 1] = STATE_COLORS[state] .. name .. ((not known and state == "?") and "?" or "") .. "|r"
            end
        end
        if not allDone then anyMissing = true end
        local quest
        for _, entry in ipairs(dungeon.quests) do if entry.id == questID then quest = entry break end end
        tooltip:AddDoubleLine(quest and QuestName(quest) or ("Quest " .. questID), table.concat(parts, "  "), 1, 1, 1)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(ns.L("TIP_GROUP_LEGEND"), 0.7, 0.7, 0.7, true)
    if not anyMissing then tooltip:AddLine(ns.L("GROUP_ALL"), 0.2, 1, 0.6) end
end

-- Antworten empfangen bzw. auf Anfragen antworten; offenen Tooltip des Knopfs neu füllen
do
    local comms = CreateFrame("Frame")
    comms:RegisterEvent("CHAT_MSG_ADDON")
    comms:RegisterEvent("GROUP_ROSTER_UPDATE")
    comms:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
        if event == "GROUP_ROSTER_UPDATE" then
            if not IsInGroup() then wipe(groupReplies) wipe(groupProgress) end
            return
        end
        if prefix ~= DNG_PREFIX or issecret(message) or issecret(sender) or type(message) ~= "string" then return end
        local name = DngShortName(sender)
        if not name or name == DngShortName(UnitName("player")) then return end
        local kind, rest = strsplit("|", message, 2)
        if kind == "Q" and rest then
            -- Antwort je Quest: "<id>:<Stand>", bei Quests im Log mit Fortschritt "<id>:L2/5" (ältere Versionen lesen
            -- nur den Buchstaben und überspringen den Rest – bleibt verträglich)
            local parts = {}
            for id in rest:gmatch("%d+") do
                local questID = tonumber(id)
                local entry = questID .. ":" .. MyDungeonState(questID)
                local done, total = MyQuestProgress(questID)
                if done then entry = entry .. done .. "/" .. total end
                parts[#parts + 1] = entry
            end
            if #parts > 0 then DngSend("R|" .. table.concat(parts, ",")) end
        elseif kind == "R" and rest then
            local reply = groupReplies[name] or {}
            groupReplies[name] = reply
            local progress = groupProgress[name] or {}
            groupProgress[name] = progress
            for id, state, done, total in rest:gmatch("(%d+):(%a)(%d*)/?(%d*)") do
                reply[tonumber(id)] = state
                progress[tonumber(id)] = (done ~= "" and total ~= "") and { tonumber(done), tonumber(total) } or nil
            end
            if ns.RefreshDungeonHint then ns.RefreshDungeonHint() end
            local tip = ns.Style.GetTooltip()
            if groupButton and tip:IsShown() and tip:GetOwner() == groupButton and groupButton:IsMouseOver() then
                groupButton:GetScript("OnEnter")(groupButton)
            end
        end
    end)
end

-- Gruppe im Hinweis "Dungeon betreten": je Mitspieler, wie viele Dungeonquests er dabeihat, wie weit er ist,
-- welche er hat, die dir fehlen, und welche deiner Quests ihm fehlen. Ohne ForeverQuests beim Mitspieler kennt das
-- Spiel nur, ob er eine Quest im Log hat (kein Fortschritt, "fehlt" unbekannt). nil ohne Gruppe.
local function GroupHintText(dungeon)
    if not dungeon or not IsInGroup() then return nil end
    local ids = DungeonQuestIDs(dungeon)
    local lines = { "|cffffd100" .. ns.L("HINT_GROUP") .. "|r" }
    for _, unit in ipairs(GetGroupUnits()) do
        local name = DngShortName(UnitName(unit))
        if name then
            local count, extra, missing, done, total = 0, 0, 0, 0, 0
            local answered = groupReplies[name] ~= nil
            for _, questID in ipairs(ids) do
                local mine = MyDungeonState(questID)
                local theirs = MemberState(unit, name, questID)
                local theyHave = theirs == "L" or theirs == "F"
                local iHave = mine == "L" or mine == "F"
                if theyHave then
                    count = count + 1
                    local p = groupProgress[name] and groupProgress[name][questID]
                    if p then done, total = done + p[1], total + p[2] end
                end
                if theyHave and mine == "N" then extra = extra + 1 end
                if iHave and answered and theirs == "N" then missing = missing + 1 end
            end
            local text = ns.L("HINT_MEMBER", name, count)
            if total > 0 then text = text .. ns.L("HINT_MEMBER_PROGRESS", math.floor(done / total * 100 + 0.5)) end
            if extra > 0 then text = text .. " |cff33ff99" .. ns.L("HINT_MEMBER_EXTRA", extra) .. "|r" end
            if missing > 0 then text = text .. " |cffff7070" .. ns.L("HINT_MEMBER_MISSING", missing) .. "|r" end
            if not answered then text = text .. " |cff8a8a8a" .. ns.L("HINT_MEMBER_UNKNOWN") .. "|r" end
            lines[#lines + 1] = text
        end
    end
    return #lines > 1 and table.concat(lines, "\n") or nil
end

-- Levelbereich eingefärbt nach Schwierigkeit für den eigenen Charakter (anhand des Mindestlevels)
local function ColoredLevels(levels)
    if not levels then return "" end
    local minLevel = tonumber(levels:match("%d+"))
    local LevelColor = (_G.ForeverHub and _G.ForeverHub.UI and _G.ForeverHub.UI.LevelColor) or _G.GetQuestDifficultyColor
    if minLevel and LevelColor then
        local color = LevelColor(minLevel)
        return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, levels)
    end
    return levels
end

local function EnableWheelScroll(scrollFrame, child)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        local newScroll = self:GetVerticalScroll() - delta * 50
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, newScroll)))
    end)
end

-- Kleine farbige Plakette mit Text (z. B. "Level 13-18", "Horde", "NEU")
local function CreatePill(parent)
    local pill = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pill:SetHeight(20)
    pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pill.text:SetPoint("CENTER", 0, 0)
    return pill
end

local function SetPill(pill, text, bg)
    SetFlat(pill, bg, { bg[1] + 0.08, bg[2] + 0.08, bg[3] + 0.08, 1 })
    pill.text:SetText(text)
    pill:SetWidth(pill.text:GetStringWidth() + 16)
    pill:Show()
end

-- Gebietsname -> Karten-ID, damit ein Kartenpunkt gesetzt werden kann
local mapIDsByName
local function FindMapID(zoneName)
    if not zoneName or not C_Map or not C_Map.GetMapChildrenInfo then return nil end
    if not mapIDsByName then
        mapIDsByName = {}
        local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
        -- 946 = ganze Welt (Retail), 947 = Azeroth
        for _, rootID in ipairs({ 946, 947 }) do
            for _, info in ipairs(C_Map.GetMapChildrenInfo(rootID, nil, true) or {}) do
                local key = info.name and info.name:lower()
                if key and (info.mapType == zoneType or not mapIDsByName[key]) then
                    mapIDsByName[key] = info.mapID
                end
            end
        end
    end
    return mapIDsByName[zoneName:lower()]
end

local function SetWaypoint(quest)
    local prefix = ns.ChatPrefix() .. ": "
    if not quest.x or not quest.y then
        print(prefix .. ns.L("NO_COORDS"))
        return
    end
    -- Kartenname kommt vom Client: deutschen und englischen Gebietsnamen versuchen
    local mapID = quest.mapID or FindMapID(quest.zone) or FindMapID(quest.zoneEN)
    if not mapID or (C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID)) then
        print(prefix .. ns.L("NO_WAYPOINT", Localized(quest, "zone") or ns.L("THIS_ZONE")))
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, quest.x / 100, quest.y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    print(prefix .. ns.L("WAYPOINT_SET", GiverText(quest) or ns.L("QUEST_GIVER"),
        Localized(quest, "zone") or "?", quest.x, quest.y))
    -- Option: Weltkarte gleich an dieser Stelle öffnen; das Dungeonfenster rückt dahinter (Klick holt es zurück)
    if ns.db.waypointOpensMap and not InCombatLockdown() then
        local map = _G.WorldMapFrame
        if map then
            if not map:IsShown() then
                if OpenWorldMap then OpenWorldMap(mapID) elseif ToggleWorldMap then ToggleWorldMap() end
            end
            if map.SetMapID then map:SetMapID(mapID) end
            if window then window:SetFrameStrata("LOW") end
        end
    end
end

-- Quest aus dem eigenen Questlog mit der Gruppe teilen
local function CanShareQuest(quest)
    return IsInGroup() and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(quest.id)
end

local function ShareQuest(quest)
    local prefix = ns.ChatPrefix() .. ": "
    if not quest.id or not C_QuestLog.GetLogIndexForQuestID(quest.id) then return end
    if not IsInGroup() then
        print(prefix .. ns.L("SHARE_NO_GROUP"))
        return
    end
    if C_QuestLog.IsPushableQuest and not C_QuestLog.IsPushableQuest(quest.id) then
        print(prefix .. ns.L("SHARE_NOT_PUSHABLE"))
        return
    end
    ns.PushQuest(quest.id) -- Tracker.lua: im Kampf erst danach
end

-- Quests eines Dungeons, die im eigenen Questlog stehen (jede Quest-ID nur einmal)
local function GetQuestsInLog(dungeon)
    local list, seen = {}, {}
    for _, quest in ipairs(dungeon and dungeon.quests or {}) do
        if quest.id and not seen[quest.id] and C_QuestLog.GetLogIndexForQuestID(quest.id) then
            seen[quest.id] = true
            table.insert(list, quest)
        end
    end
    return list
end

local SHARE_ALL_DELAY = 1.5 -- Sekunden zwischen zwei geteilten Quests

-- Alle teilbaren Quests des Dungeons nacheinander mit der Gruppe teilen
local function ShareAllQuests(dungeon)
    local prefix = ns.ChatPrefix() .. ": "
    if not IsInGroup() then
        print(prefix .. ns.L("SHARE_NO_GROUP"))
        return
    end
    local list = {}
    for _, quest in ipairs(GetQuestsInLog(dungeon)) do
        if CanShareQuest(quest) then table.insert(list, quest) end
    end
    if #list == 0 then
        print(prefix .. ns.L("SHARE_ALL_NONE"))
        return
    end
    for i, quest in ipairs(list) do
        C_Timer.After((i - 1) * SHARE_ALL_DELAY, function() ShareQuest(quest) end)
    end
    print(prefix .. ns.L("SHARE_ALL_DONE", #list))
end

---------------------------------------------------------------------------
-- AtlasLoot: Bosse und Beute des Dungeons anzeigen (nur wenn AtlasLoot installiert ist)
---------------------------------------------------------------------------

local ATLASLOOT_MODULE = "AtlasLootClassic_DungeonsAndRaids"
-- Die Seite eines Dungeons in AtlasLoot wird über die Gebiets-ID gesucht (AtlasLoot-Seiten tragen "MapID" =
-- Gebiets-ID, Dungeons haben sie aus Questie) – keine selbst gepflegte Zuordnung mehr.

local function IsAtlasLootAvailable()
    local AL = _G.AtlasLoot
    return AL and AL.GUI and AL.GUI.frame and AL.Loader and AL.ItemDB and AL.db and AL.db.GUI and true or false
end

-- Öffnet AtlasLoot auf der Seite des Dungeons. AtlasLoot selbst wird dabei nicht verändert:
-- es wird nur die gewünschte Seite vorgewählt und das Fenster geöffnet.
local function OpenAtlasLoot(page)
    local prefix = ns.ChatPrefix() .. ": "
    local AL = _G.AtlasLoot
    if not IsAtlasLootAvailable() then
        print(prefix .. ns.L("ATLASLOOT_FAILED"))
        return
    end
    if InCombatLockdown() then
        print(prefix .. ns.L("ATLASLOOT_COMBAT"))
        return
    end
    -- Die Beutedaten lädt AtlasLoot erst bei Bedarf; danach die Seite auswählen
    local state = AL.Loader:LoadModule(ATLASLOOT_MODULE, function()
        local frame, db = AL.GUI.frame, AL.db.GUI
        local moduleData = AL.ItemDB:Get(ATLASLOOT_MODULE)
        if not (moduleData and moduleData[page] and db.selected and frame.moduleSelect) then
            print(prefix .. ns.L("ATLASLOOT_FAILED"))
            return
        end
        db.selected[1] = ATLASLOOT_MODULE
        db.selected[2] = page
        db.selected[3] = 1
        if moduleData[page].gameVersion and moduleData[page].gameVersion ~= 0 then
            db.selectedGameVersion = moduleData[page].gameVersion
        end
        if not frame:IsShown() then frame:Show() end
        -- Dungeonfenster bleibt offen: AtlasLoot auf dieselbe Ebene holen und davorlegen.
        -- Ein Klick auf eines der beiden Fenster holt es wieder nach vorn.
        if window then frame:SetFrameStrata(window:GetFrameStrata()) end
        frame:Raise()
        -- AtlasLoot wählt beim Öffnen evtl. den aktuellen Dungeon; unsere Seite danach erneut setzen
        db.selected[2] = page
        frame.moduleSelect:SetSelected(ATLASLOOT_MODULE)
    end)
    if state ~= nil and state ~= true then
        print(prefix .. ns.L("ATLASLOOT_FAILED"))
    end
end

-- AtlasLoot-Seiten eines Dungeons: alle Seiten, deren Gebiet ("MapID") das Gebiet des Dungeons oder eines
-- seiner Flügel ist. Mehrere Treffer (z. B. Flügel) = Auswahl.
local function ShowAtlasLoot(owner, dungeon)
    local AL = _G.AtlasLoot
    if not (dungeon and dungeon.areaID and IsAtlasLootAvailable()) then return end
    local areas = { [dungeon.areaID] = true }
    for _, alt in ipairs(dungeon.altAreas or {}) do areas[alt] = true end
    AL.Loader:LoadModule(ATLASLOOT_MODULE, function()
        local moduleData = AL.ItemDB:Get(ATLASLOOT_MODULE)
        local found = {}
        for key, page in pairs(type(moduleData) == "table" and moduleData or {}) do
            if type(page) == "table" and (areas[page.MapID] or areas[page.AreaID]) then
                found[#found + 1] = { key = key, name = page.name or key }
            end
        end
        -- Rückfall über den Namen: AtlasLoots Seiten der neuen Forever-Dungeons haben keine Gebiets-ID, nur
        -- einen (englischen) Namen wie "Hall of Thanes". Verglichen ohne Farbcodes, Artikel und Satzzeichen.
        if #found == 0 then
            local function Simple(text)
                if type(text) ~= "string" then return nil end
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower():gsub("%b()", "")
                for _, article in ipairs({ "die ", "der ", "das ", "the " }) do
                    if text:sub(1, #article) == article then text = text:sub(#article + 1) end
                end
                return (text:gsub("[%s%p]", ""))
            end
            local wanted = {}
            for _, name in ipairs({ dungeon.nameEN, dungeon.name }) do
                local simple = Simple(name)
                if simple and simple ~= "" then wanted[#wanted + 1] = simple end
            end
            for key, page in pairs(type(moduleData) == "table" and moduleData or {}) do
                local pageName = type(page) == "table" and Simple(page.name)
                if pageName and pageName ~= "" then
                    for _, simple in ipairs(wanted) do
                        -- Seitenname beginnt mit dem Dungeonnamen (AtlasLoot hängt teils einen Zusatz an)
                        if pageName:sub(1, #simple) == simple or simple:sub(1, #pageName) == pageName then
                            found[#found + 1] = { key = key, name = page.name or key }
                            break
                        end
                    end
                end
            end
        end
        table.sort(found, function(a, b) return tostring(a.name) < tostring(b.name) end)
        if #found == 1 then
            OpenAtlasLoot(found[1].key)
        elseif #found > 1 then
            local items = {}
            for _, page in ipairs(found) do
                table.insert(items, { text = tostring(page.name), onClick = function() OpenAtlasLoot(page.key) end })
            end
            ns.Style.ShowMenu(owner, items)
        else
            print(ns.ChatPrefix() .. ": " .. ns.L("ATLASLOOT_NOT_FOUND"))
        end
    end)
end

---------------------------------------------------------------------------
-- Belohnungen (Gegenstände anhand ihrer Item-ID)
---------------------------------------------------------------------------

local REWARD_ROW_HEIGHT = 26
local RequestRefresh, RefreshDetail
local pendingItems = {}
-- Welche Quests ihre Belohnungen gerade ausgeklappt zeigen (standardmäßig eingeklappt)
local rewardsExpanded = {}
-- Belohnungen aufgeklappt? Ohne eigene Wahl: Dungeonquests aufgeklappt, Questlog-Karten zugeklappt (übersichtlicher)
function ns.RewardsExpanded(quest)
    local v = rewardsExpanded[quest]
    if v == nil then return not quest.isLog end
    return v
end
local function ToggleRewards(quest)
    rewardsExpanded[quest] = not ns.RewardsExpanded(quest)
end

local function GetQualityColor(quality)
    if quality and C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then return r, g, b end
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return 0.6, 0.6, 0.6
end

-- Name, Link, Seltenheit und Symbol eines Gegenstands. Ist er noch nicht geladen,
-- wird er angefordert und das Fenster danach aktualisiert.
-- Antwortet der Server nicht (seit dem Live-Start bei manchen Gegenständen), wird nach ITEM_RETRY Sekunden erneut
-- gefragt (höchstens ITEM_MAX_TRIES-mal); bis dahin steht der Name aus Questies Gegenstandsdaten da.
local ITEM_RETRY, ITEM_MAX_TRIES = 8, 3
local itemTries = {}
local function QuestieItemName(itemID)
    local loader = _G.QuestieLoader
    local db = type(loader) == "table" and loader.ImportModule and loader:ImportModule("QuestieDB")
    if not (db and db.QueryItemSingle) then return nil end
    local ok, name = pcall(db.QueryItemSingle, itemID, "name")
    return ok and type(name) == "string" and name ~= "" and name or nil
end
local function GetRewardInfo(itemID)
    local name, link, quality = C_Item.GetItemInfo(itemID)
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    local asked = pendingItems[itemID]
    if not name and (itemTries[itemID] or 0) < ITEM_MAX_TRIES
        and (not asked or GetTime() - asked > ITEM_RETRY) and Item and Item.CreateFromItemID then
        pendingItems[itemID] = GetTime()
        itemTries[itemID] = (itemTries[itemID] or 0) + 1
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            pendingItems[itemID] = nil
            RequestRefresh()
        end)
        -- falls keine Antwort kommt: später neu aufbauen, dabei wird erneut gefragt
        C_Timer.After(ITEM_RETRY + 0.5, function() if pendingItems[itemID] then RequestRefresh() end end)
    end
    -- Server hat auf alle Anfragen nicht geantwortet: Gegenstand gibt es dort (so) offenbar nicht
    local unknown = not name and (itemTries[itemID] or 0) >= ITEM_MAX_TRIES
        and pendingItems[itemID] ~= nil and GetTime() - pendingItems[itemID] > ITEM_RETRY
    if not name then name = QuestieItemName(itemID) end
    return name, link, quality, icon, unknown
end

-- Echte Belohnungen vom Spiel: Questies Daten stammen aus dem ursprünglichen Classic, Forever hat manche Belohnungen
-- geändert. Was das Spiel selbst liefert (Quest im Questlog, Questtext beim NPC – Annehmen und Abgeben), wird
-- kontoweit gemerkt (ForeverQuestsSeen.rewards[Quest-ID] = { Gegenstands-IDs }; Daten, keine Einstellung) und ersetzt
-- auf den Karten Questies Liste.
do
    local function Store()
        if type(_G.ForeverQuestsSeen) ~= "table" then _G.ForeverQuestsSeen = {} end
        local s = _G.ForeverQuestsSeen
        if type(s.rewards) ~= "table" then s.rewards = {} end
        return s.rewards
    end
    function ns.SeenQuestRewards(questID) return questID and Store()[questID] or nil end
    local logRead = {} -- [Quest-ID] = in dieser Sitzung schon aus dem Questlog gelesen
    function ns.ReadLogRewardsOnce(questID)
        if not questID or logRead[questID] or not ns.QuestRewardItemIDs
            or not C_QuestLog.GetLogIndexForQuestID(questID) then return end
        logRead[questID] = true
        ns.RememberQuestRewards(questID, ns.QuestRewardItemIDs(questID))
    end
    function ns.RememberQuestRewards(questID, ids)
        if not questID or type(ids) ~= "table" or #ids == 0 then return end
        local old = Store()[questID]
        local same = old and #old == #ids
        if same then for i, id in ipairs(ids) do if old[i] ~= id then same = false break end end end
        if same then return end
        Store()[questID] = ids
        RequestRefresh()
    end
    -- Questtext beim NPC (Annehmen / Abgeben): feste Belohnungen und Auswahl
    local function ItemIDOf(kind, i)
        local ok, _, _, _, _, _, itemID = pcall(GetQuestItemInfo, kind, i)
        if ok and type(itemID) == "number" and itemID > 0 then return itemID end
        local okLink, link = pcall(GetQuestItemLink, kind, i)
        local id = okLink and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        return id
    end
    local npc = CreateFrame("Frame")
    npc:RegisterEvent("QUEST_DETAIL")
    npc:RegisterEvent("QUEST_COMPLETE")
    npc:SetScript("OnEvent", function()
        C_Timer.After(0.2, function()
            local questID = GetQuestID and GetQuestID()
            if not questID or questID == 0 or not GetQuestItemInfo then return end
            local ids = {}
            for i = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do ids[#ids + 1] = ItemIDOf("reward", i) end
            for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do ids[#ids + 1] = ItemIDOf("choice", i) end
            -- (eine fehlende ID = Daten noch nicht da: dann lieber nichts merken als eine halbe Liste)
            local count = (GetNumQuestRewards and GetNumQuestRewards() or 0) + (GetNumQuestChoices and GetNumQuestChoices() or 0)
            if #ids > 0 and #ids == count then ns.RememberQuestRewards(questID, ids) end
        end)
    end)
end

local function CreateRewardButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(REWARD_ROW_HEIGHT - 2)

    -- Rand in Seltenheitsfarbe hinter dem Symbol
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetSize(24, 24)
    button.border:SetPoint("LEFT")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(22, 22)
    button.icon:SetPoint("CENTER", button.border, "CENTER")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetPoint("LEFT", button.border, "RIGHT", 6, 0)
    button.name:SetPoint("RIGHT", -2, 0)
    button.name:SetJustifyH("LEFT")
    button.name:SetWordWrap(false)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    -- Maus drüber: Gegenstands-Tooltip; mit gedrückter Shift-Taste zusätzlich der Vergleich mit der getragenen
    -- Ausrüstung (Blizzards GameTooltip, der die Vergleichs-Tooltips mitbringt); Shift-Klick: im Chat verlinken
    -- Ohne Shift unser eigener Tooltip (kennt keinen Vergleich – Blizzards GameTooltip vergleicht bei der
    -- Spieleinstellung "immer vergleichen" sonst ständig), mit Shift Blizzards GameTooltip samt Vergleich
    local function ShowItem(self)
        local own = ns.Style.GetTooltip()
        if self.unknown then
            -- Server kennt den Gegenstand nicht: statt Blizzards dauerhaftem "Frage … ab" eine Erklärung
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            own:SetOwner(self, "ANCHOR_RIGHT")
            own:AddLine(self.fallbackName or ("#" .. tostring(self.itemID)), 0.7, 0.7, 0.7)
            own:AddLine(ns.L("ITEM_NOT_ON_SERVER"), 1, 1, 1, true)
            own:Show()
            return
        end
        if IsShiftKeyDown() then
            own:Hide()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
            if GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
        else
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            own:SetOwner(self, "ANCHOR_RIGHT")
            own:SetItemByID(self.itemID)
            own:Show()
        end
    end
    button:SetScript("OnEnter", function(self)
        ShowItem(self)
        self:RegisterEvent("MODIFIER_STATE_CHANGED") -- Shift drücken/loslassen, während die Maus darauf ist
    end)
    button:SetScript("OnEvent", function(self) if self:IsMouseOver() then ShowItem(self) end end)
    button:SetScript("OnLeave", function(self)
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        GameTooltip:Hide()
        ns.Style.GetTooltip():Hide()
    end)
    button:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick() then
            HandleModifiedItemClick(self.link)
        end
    end)
    return button
end

-- Zeigt die Belohnungen einer Quest: eingeklappt nur die Zeile "Belohnungen (3)",
-- ausgeklappt zusätzlich die Gegenstände in zwei Spalten. Gibt die benötigte Höhe zurück.
local function LayoutRewards(entry, quest, width, chain)
    local own = quest.rewards or {}
    entry.rewardButtons = entry.rewardButtons or {}
    -- Gegenstände vom letzten Teil der Questreihe (wenn die Karte gerade einen früheren Teil zeigt):
    -- als echte Belohnungen darunter, mit Hinweis, aus welchem Teil sie stammen
    local final = {}
    local last = chain and chain[#chain]
    if last and last.questID ~= quest.id and ns.QuestRewardItemIDs then
        final = ns.SeenQuestRewards(last.questID) or ns.QuestRewardItemIDs(last.questID)
    end
    if entry.finalLabel then entry.finalLabel:Hide() end
    if #own + #final == 0 then
        entry.rewardToggle:Hide()
        for _, button in ipairs(entry.rewardButtons) do button:Hide() end
        return 0
    end

    local expanded = ns.RewardsExpanded(quest) -- Standard: aufgeklappt (Questlog-Karten: zugeklappt)
    entry.rewardToggle.text:SetText(ns.L("REWARDS_COUNT", #own + #final))
    entry.rewardToggle.arrow:SetRotation(expanded and -math.pi / 2 or 0)
    entry.rewardToggle:Show()
    if not expanded then
        for _, button in ipairs(entry.rewardButtons) do button:Hide() end
        return 19 -- nur die Zeile zum Ausklappen
    end

    -- eigene Belohnungen, danach (mit Überschrift) die vom Ende der Reihe
    local rewards, offsetOf = {}, {}
    for _, itemID in ipairs(own) do rewards[#rewards + 1] = itemID end
    local ownRows = math.ceil(#own / 2)
    local labelHeight = 0
    if #final > 0 then
        if not entry.finalLabel then
            entry.finalLabel = entry.rewardArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            entry.finalLabel:SetJustifyH("LEFT")
            entry.finalLabel:SetTextColor(0.53, 0.8, 1)
        end
        local name = GetGameQuestTitle(last.questID) or last.name or QuestIDFallback(last.questID)
        entry.finalLabel:SetWidth(width)
        entry.finalLabel:SetText(ns.L("CHAIN_FINAL_REWARDS", #chain, #chain, name))
        entry.finalLabel:ClearAllPoints()
        entry.finalLabel:SetPoint("TOPLEFT", entry.rewardArea, "TOPLEFT", 0, -(ownRows * REWARD_ROW_HEIGHT + 2))
        entry.finalLabel:Show()
        labelHeight = entry.finalLabel:GetStringHeight() + 6
        for i, itemID in ipairs(final) do
            rewards[#rewards + 1] = itemID
            offsetOf[#rewards] = i
        end
    end

    local columnWidth = math.floor((width - 6) / 2)
    for i, itemID in ipairs(rewards) do
        local button = entry.rewardButtons[i]
        if not button then
            button = CreateRewardButton(entry.rewardArea)
            entry.rewardButtons[i] = button
        end
        local name, link, quality, icon, unknown = GetRewardInfo(itemID)
        button.itemID = itemID
        button.link = link
        button.unknown, button.fallbackName = unknown, name
        button.icon:SetTexture(icon or 134400) -- 134400 = Fragezeichen-Symbol
        button.icon:SetDesaturated(unknown and true or false)
        local r, g, b = GetQualityColor(quality)
        button.border:SetColorTexture(r, g, b, 1)
        button.name:SetText(name or ns.L("ITEM_LOADING", itemID))
        if unknown then
            button.name:SetTextColor(0.5, 0.5, 0.5) -- (auf dem Server nicht gefunden, siehe Tooltip)
        else
            button.name:SetTextColor(r, g, b)
        end

        local position = offsetOf[i] or i -- Platz innerhalb der eigenen Gruppe
        local column = (position - 1) % 2
        local top = offsetOf[i] and (ownRows * REWARD_ROW_HEIGHT + labelHeight) or 0
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", entry.rewardArea, "TOPLEFT", column * (columnWidth + 6),
            -(top + math.floor((position - 1) / 2) * REWARD_ROW_HEIGHT))
        button:SetWidth(columnWidth)
        button:Show()
    end
    for i = #rewards + 1, #entry.rewardButtons do
        entry.rewardButtons[i]:Hide()
    end
    local height = (ownRows + math.ceil(#final / 2)) * REWARD_ROW_HEIGHT + labelHeight
    entry.rewardArea:SetSize(width, height)
    return height + 22 -- inkl. Zeile "Belohnungen"
end

---------------------------------------------------------------------------
-- Rechte Seite: Quests des gewählten Dungeons
---------------------------------------------------------------------------

-- Rechtsklick-Menü einer Quest im Dungeonfenster (Karte, Vorquest, Zeile der Questreihe): Wowhead-Link wie im
-- Tracker (Questies Fenster zum Kopieren, darum nur mit Questie)
local function OpenQuestMenu(owner, questID)
    if not questID then return end
    local items = { { title = GetGameQuestTitle(questID) or QuestIDFallback(questID) } }
    if ns.ShowQuestieWowhead and ns.HasQuestie and ns.HasQuestie() then
        table.insert(items, { text = ns.L("QUESTIE_WOWHEAD"), disabled = InCombatLockdown(),
            onClick = function() ns.ShowQuestieWowhead(questID) end })
    end
    if #items > 1 then ns.Style.ShowMenu(owner, items) end
end

local function GetQuestEntry(index)
    local entry = questEntries[index]
    if not entry then
        entry = CreateFrame("Button", nil, questContent, "BackdropTemplate")
        SetFlat(entry, COLOR.card)
        entry:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(COLOR.cardHover))
        end)
        entry:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(COLOR.card))
        end)
        -- Klick auf die Karte klappt die Belohnungen ein bzw. aus; Shift-Klick verlinkt die Quest im Chat;
        -- Rechtsklick öffnet das Menü der Quest (Wowhead-Link)
        entry:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        entry:SetScript("OnClick", function(self, button)
            local quest = self.quest
            if quest and button == "RightButton" then
                OpenQuestMenu(self, quest.id)
                return
            end
            if quest and IsModifiedClick("CHATLINK") then
                LinkQuestInChat(quest)
                return
            end
            if quest and self.rewardToggle and self.rewardToggle:IsShown() then
                ToggleRewards(quest)
                RefreshDetail()
            end
        end)
        -- Maus über der Karte: Tooltip der Quest (wie im Tracker bzw. aus Questies Daten, mit Belohnungen)
        entry:HookScript("OnEnter", function(self)
            if self.quest and self.quest.id and ns.ShowQuestInfoTooltip then ns.ShowQuestInfoTooltip(self, self.quest.id) end
        end)
        entry:HookScript("OnLeave", function(self)
            local tip = ns.Style.GetTooltip()
            if tip:GetOwner() == self then tip:Hide() end
        end)

        -- Knopf für den Kartenpunkt zum Questgeber (nur wenn Koordinaten eingetragen sind)
        entry.waypointButton = ns.Style.CreateButton(entry, ns.L("BTN_WAYPOINT"), 74, 16, function(self)
            SetWaypoint(self:GetParent().quest)
        end, function(tooltip) tooltip:AddLine(ns.L("TIP_WAYPOINT")) end)

        -- Knopf zum Teilen (nur bei Quests im eigenen Questlog); ohne Gruppe ausgegraut
        entry.shareButton = ns.Style.CreateButton(entry, ns.L("BTN_SHARE"), 54, 16, function(self)
            ShareQuest(self:GetParent().quest)
        end, function(tooltip)
            tooltip:AddLine(ns.L("TIP_SHARE"))
            local quest = entry.quest
            if not IsInGroup() then
                tooltip:AddLine(ns.L("SHARE_NO_GROUP"), 1, 0.3, 0.3)
            elseif quest and not CanShareQuest(quest) then
                tooltip:AddLine(ns.L("SHARE_NOT_PUSHABLE"), 1, 0.3, 0.3)
            end
        end)

        -- Farbstreifen links: grün = abgeschlossen, gelb = im Questlog, grau = offen
        entry.stripe = entry:CreateTexture(nil, "ARTWORK")
        entry.stripe:SetPoint("TOPLEFT", 1, -1)
        entry.stripe:SetPoint("BOTTOMLEFT", 1, 1)
        entry.stripe:SetWidth(3)

        -- Kompakte Karte: Titelzeile mit Plaketten, darunter meist nur eine Infozeile
        entry.title = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        entry.title:SetPoint("TOPLEFT", 12, -7)
        entry.title:SetJustifyH("LEFT")
        entry.title:SetWordWrap(true)

        entry.levelPill = CreatePill(entry)
        entry.statusPill = CreatePill(entry)
        entry.levelPill:SetHeight(16)
        entry.statusPill:SetHeight(16)
        entry.levelPill:SetPoint("TOPRIGHT", -8, -5)
        entry.waypointButton:SetPoint("TOPRIGHT", -8, -5)

        -- Fraktionswappen zwischen Status und Level: Allianz, Horde oder beide
        entry.factionFrame = CreateFrame("Frame", nil, entry)
        entry.factionFrame:SetSize(16, 16)
        entry.factionFrame:SetPoint("RIGHT", entry.levelPill, "LEFT", -4, 0)
        entry.factionFrame.icons = {}
        for i = 1, 2 do
            local icon = entry.factionFrame:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", (i - 1) * 17, 0)
            entry.factionFrame.icons[i] = icon
        end
        entry.factionFrame:EnableMouse(true)
        entry.factionFrame:SetScript("OnEnter", function(self)
            if not self.faction then return end
            ns.Style.GetTooltip():SetOwner(self, "ANCHOR_TOP")
            ns.Style.GetTooltip():AddLine(FactionText(self.faction), 1, 1, 1)
            ns.Style.GetTooltip():Show()
        end)
        entry.factionFrame:SetScript("OnLeave", function() ns.Style.GetTooltip():Hide() end)
        entry.statusPill:SetPoint("RIGHT", entry.factionFrame, "LEFT", -4, 0)

        entry.info = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- Zweite Zeile: Text aus dem Quest-Tooltip des Spiels (höchstens zwei Zeilen)
        entry.desc = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        entry.desc:SetPoint("TOPLEFT", entry.title, "BOTTOMLEFT", 0, -3)
        entry.desc:SetJustifyH("LEFT")
        entry.desc:SetTextColor(0.72, 0.72, 0.72)
        if entry.desc.SetMaxLines then entry.desc:SetMaxLines(2) end

        entry.info:SetPoint("TOPLEFT", entry.desc, "BOTTOMLEFT", 0, -3)

        -- Startet die Quest durch einen Gegenstand: eigene Zeile mit Symbol und Namen.
        -- Maus drüber = Gegenstands-Tooltip, Shift-Klick = im Chat verlinken (wie bei den Belohnungen)
        entry.giverItem = CreateRewardButton(entry)
        entry.giverItem:SetPoint("TOPLEFT", entry.desc, "BOTTOMLEFT", 0, -3)
        entry.giverItem:Hide()
        entry.info:SetJustifyH("LEFT")
        entry.info:SetSpacing(2)

        -- Belohnungen unter den Infozeilen
        -- Zeile "Belohnungen (3)" mit Pfeil: Klick klappt die Gegenstände auf und zu
        local toggle = CreateFrame("Button", nil, entry)
        toggle:SetHeight(16)
        toggle:SetPoint("TOPLEFT", entry.info, "BOTTOMLEFT", -2, -3)
        toggle.arrow = toggle:CreateTexture(nil, "OVERLAY")
        toggle.arrow:SetSize(10, 10)
        toggle.arrow:SetPoint("LEFT", 2, 0)
        toggle.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        toggle.text = toggle:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        toggle.text:SetPoint("LEFT", toggle.arrow, "RIGHT", 6, 0)
        toggle.text:SetTextColor(0.75, 0.75, 0.75)
        toggle:SetScript("OnEnter", function(self) self.text:SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3]) end)
        toggle:SetScript("OnLeave", function(self) self.text:SetTextColor(0.75, 0.75, 0.75) end)
        toggle:SetScript("OnClick", function(self)
            local quest = self:GetParent().quest
            if not quest then return end
            ToggleRewards(quest)
            RefreshDetail()
        end)
        toggle:SetWidth(160)
        entry.rewardToggle = toggle

        entry.rewardArea = CreateFrame("Frame", nil, entry)
        entry.rewardArea:SetPoint("TOPLEFT", toggle, "BOTTOMLEFT", 2, -2)
        entry.rewardArea:SetSize(1, 1)

        questEntries[index] = entry
    end
    return entry
end

-- Gebiets-Überschrift im Reiter Questlog ("Alle Quests"): Gebietsname in Gold mit Anzahl, darunter feine Linie
local zoneHeaders = {}
local ZONE_HEADER_HEIGHT = 22
local function GetZoneHeader(index)
    local h = zoneHeaders[index]
    if not h then
        h = CreateFrame("Frame", nil, questContent)
        h:SetHeight(ZONE_HEADER_HEIGHT)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.text:SetPoint("LEFT", 2, 1)
        h.text:SetJustifyH("LEFT")
        local line = h:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT", 0, 3)
        line:SetPoint("BOTTOMRIGHT", 0, 3)
        line:SetHeight(1)
        line:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.35)
        zoneHeaders[index] = h
    end
    return h
end

local function LayoutPills(list)
    local x = 0
    for i, data in ipairs(list) do
        local pill = pills[i]
        if not pill then
            pill = CreatePill(pillRow)
            pills[i] = pill
        end
        SetPill(pill, data[1], data[2])
        pill:ClearAllPoints()
        pill:SetPoint("LEFT", pillRow, "LEFT", x, 0)
        x = x + pill:GetWidth() + 6
    end
    for i = #list + 1, #pills do
        pills[i]:Hide()
    end
end

-- Karten des Dungeons: Quests derselben Questreihe (aus Questie) werden zu EINER Karte zusammengefasst.
-- Die Karte zeigt die nächste noch offene Quest der Reihe (sonst die letzte); die ganze Reihe steht darunter.
local function BuildCards(dungeon)
    local cards, byKey = {}, {}
    local dungeonQuestIDs = {} -- alle Quests des Dungeons (eine fehlende Vorquest darunter ist keine "Vorquest außerhalb")
    for _, quest in ipairs(dungeon.quests or {}) do
        if quest.id then dungeonQuestIDs[quest.id] = true end
    end
    for _, quest in ipairs(dungeon.quests or {}) do
        if IsQuestVisible(quest) then
            -- Questlog: jede Quest eine eigene Karte, ohne Questreihe (übersichtlicher)
            local chain = quest.id and not quest.isLog and ns.GetQuestChain and ns.GetQuestChain(quest.id)
            -- Kennt Questie keine Reihe (z. B. bei neuen Forever-Quests fehlen dort die Verknüpfungen), gelten
            -- gleichnamige Quests desselben Dungeons als eine Reihe
            local key = (quest.isLog and ("log:" .. tostring(quest.id))) or (chain and ("chain:" .. chain[1].questID))
                or ("name:" .. tostring(QuestName(quest)):lower())
            local card = byKey[key]
            if not card then
                card = { members = {}, chain = chain }
                byKey[key] = card
                cards[#cards + 1] = card
            end
            table.insert(card.members, quest)
        end
    end
    for _, card in ipairs(cards) do
        -- Gleichnamige Quests ohne Questie-Reihe: Reihenfolge nach Quest-ID (so vergibt Blizzard sie in der Regel)
        if not card.chain and #card.members > 1 then
            table.sort(card.members, function(a, b) return (a.id or 0) < (b.id or 0) end)
            card.chain = {}
            for _, member in ipairs(card.members) do
                card.chain[#card.chain + 1] = { questID = member.id, name = QuestName(member),
                    level = tonumber(member.level), requiredLevel = member.minLevel }
            end
        end
        -- Reihenfolge innerhalb der Reihe wie in der Kette
        local position = {}
        if card.chain then
            for i, entry in ipairs(card.chain) do position[entry.questID] = i end
            table.sort(card.members, function(a, b) return (position[a.id] or 99) < (position[b.id] or 99) end)
        end
        card.done = 0
        for _, member in ipairs(card.members) do
            if GetQuestStatus(member.id) == "DONE" then
                card.done = card.done + 1
            elseif not card.quest then
                card.quest = member
            end
        end
        card.quest = card.quest or card.members[#card.members]

        -- Vorquest: Nur wenn man die Dungeonquest noch gar nicht annehmen kann (nicht im Log, nicht erledigt und
        -- laut Questie fehlt eine Vorquest außerhalb des Dungeons), zeigt die Karte die Vorquest, die man zuerst
        -- in der offenen Welt erledigen muss (mit Questgeber und Kartenpunkt). Sie gehört dann auch in die Reihe.
        local quest = card.quest
        if quest and quest.id and GetQuestStatus(quest.id) == "OPEN" and ns.GetMissingPrequest then
            local missingID = ns.GetMissingPrequest(quest.id)
            if missingID and not dungeonQuestIDs[missingID] then
                local prequest = ns.BuildQuestieQuest and ns.BuildQuestieQuest(missingID, dungeon)
                if prequest then
                    prequest.isPrequest = true
                    card.quest = prequest
                    local inChain = false
                    for _, entry in ipairs(card.chain or {}) do
                        if entry.questID == missingID then inChain = true break end
                    end
                    if not inChain then
                        local entry = { questID = missingID, name = prequest.name, level = tonumber(prequest.level),
                            requiredLevel = prequest.minLevel }
                        if card.chain then
                            local copy = { entry }
                            for _, e in ipairs(card.chain) do copy[#copy + 1] = e end
                            card.chain = copy
                        else
                            card.chain = { entry, { questID = quest.id, name = QuestName(quest),
                                level = tonumber(quest.level), requiredLevel = quest.minLevel } }
                        end
                    end
                end
            end
        end
    end
    return cards
end

-- Questreihe auf der Karte: untereinander wie im Questlog (nummeriert, erledigt mit Haken, diese Quest gold,
-- im Questlog weiß, offen grau, mit Quest-ID); jede Zeile zeigt beim Darüberfahren den Tooltip der Quest.
-- Gibt die benötigte Höhe zurück (0 ohne Reihe).
local CHAIN_ROW_HEIGHT = 14
local function ChainLine(index, entry, quest)
    local name = GetGameQuestTitle(entry.questID) or entry.name or QuestIDFallback(entry.questID)
    local level = (entry.level and entry.level > 0) and (" (" .. entry.level .. ")") or ""
    local doneQuest = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(entry.questID)
    local inLog = C_QuestLog.GetLogIndexForQuestID(entry.questID) ~= nil
    local color, suffix = "|cff9a9a9a", ""
    -- erledigt = grün mit Haken; gold nur der Teil, der gerade im Questlog bearbeitet wird; sonst grau
    if doneQuest then
        color, suffix = "|cff55cc66", " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
    elseif inLog then
        color, suffix = "|cffffd100", " |cff88ccff" .. ns.L("DETAIL_IN_LOG") .. "|r"
    end
    local id = ns.db.showQuestIDs and ("  |cff6a6a6a#" .. entry.questID .. "|r") or ""
    return "   " .. color .. index .. ". " .. name .. level .. "|r" .. suffix .. id
end

local function LayoutCardChain(entry, chain, quest, width)
    entry.chainRows = entry.chainRows or {}
    local rows = entry.chainRows
    if not chain then
        for _, row in ipairs(rows) do row:Hide() end
        return 0
    end
    local a = COLOR.accent
    local y = 3
    for i = 0, #chain do
        local row = rows[i + 1]
        if not row then
            row = CreateFrame("Frame", nil, entry)
            row:EnableMouse(true)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("TOPLEFT")
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
            row.highlight:SetAllPoints()
            row.highlight:SetColorTexture(1, 1, 1, 0.06)
            row:SetScript("OnEnter", function(self)
                if self.questID and ns.ShowQuestInfoTooltip then ns.ShowQuestInfoTooltip(self, self.questID) end
            end)
            row:SetScript("OnLeave", function(self)
                local tip = ns.Style.GetTooltip()
                if tip:GetOwner() == self then tip:Hide() end
            end)
            -- Rechtsklick: Menü der Quest (Wowhead-Link)
            row:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" and self.questID then OpenQuestMenu(self, self.questID) end
            end)
            rows[i + 1] = row
        end
        if i == 0 then
            -- Überschrift "Questreihe 5" (ohne Tooltip)
            row.questID = nil
            row.text:SetText(string.format("|cff%02x%02x%02x%s|r |cff8a8a8a%d|r", a[1] * 255, a[2] * 255, a[3] * 255,
                ns.L("DETAIL_CHAIN"), #chain))
        else
            row.questID = chain[i].questID
            row.text:SetText(ChainLine(i, chain[i], quest))
        end
        row.highlight:SetShown(i > 0)
        row.text:SetWidth(width)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", entry.info, "BOTTOMLEFT", 0, -y)
        row:SetSize(width, CHAIN_ROW_HEIGHT)
        row:Show()
        y = y + CHAIN_ROW_HEIGHT
    end
    for i = #chain + 2, #rows do rows[i]:Hide() end
    return y
end

RefreshDetail = function()
    refreshPending = false
    if not window or not window:IsShown() then return end

    local dungeon = selectedDungeon
    local isLog = dungeon ~= nil and dungeon.isLog == true
    if isLog then
        RefreshLogQuests()
        -- Gebiet ohne Quests mehr (alle abgegeben): das erste verbliebene Gebiet zeigen
        if #dungeon.quests == 0 then
            dungeon = logZoneOrder[1]
            selectedDungeon = dungeon
            isLog = dungeon ~= nil
            if window and window:IsShown() and ns.RefreshDungeonList then C_Timer.After(0, ns.RefreshDungeonList) end
        end
    end
    atlasButton:SetShown(dungeon ~= nil and dungeon.areaID ~= nil and IsAtlasLootAvailable())
    -- "Alle teilen" (ohne Gruppe blass) und "Gruppe" (nur in einer Gruppe) – beim Questlog nicht (gilt Dungeons)
    shareAllButton:SetShown(not isLog and #GetQuestsInLog(dungeon) > 0)
    shareAllButton:SetAlpha(IsInGroup() and 1 or 0.45)
    groupButton:SetShown(dungeon ~= nil and not isLog and IsInGroup())
    -- Sichtbare Knöpfe von rechts nach links anordnen: [Gruppe] [Alle teilen] [Bosse & Beute]
    local headerAnchor
    for _, button in ipairs({ atlasButton, shareAllButton, groupButton }) do
        if button:IsShown() then
            button:ClearAllPoints()
            if headerAnchor then
                button:SetPoint("RIGHT", headerAnchor, "LEFT", -6, 0)
            else
                button:SetPoint("TOPRIGHT", -16, -16)
            end
            headerAnchor = button
        end
    end
    for _, entry in ipairs(questEntries) do entry:Hide() end
    for _, h in ipairs(zoneHeaders) do h:Hide() end
    if not dungeon then
        detailTitle:SetText(ns.L(logTabActive and "TAB_QUESTLOG" or raidTabActive and "NO_RAID"
            or levelTabActive and "NO_DUNGEON_LEVEL" or "NO_DUNGEON"))
        detailExtra:SetText("")
        LayoutPills({})
        -- Reiter Questlog ohne Quests: Hinweis; gar keine Dungeondaten: Questie fehlt, ist veraltet oder lädt noch
        if logTabActive then
            detailEmpty:SetText(ns.L("QUESTLOG_EMPTY"))
            detailEmpty:Show()
        elseif #(ns.ALL_DUNGEON_DATA or {}) == 0 then
            detailEmpty:SetText(ns.L("NO_DUNGEON_DATA"))
            detailEmpty:Show()
        else
            detailEmpty:Hide()
        end
        return
    end

    -- Kopfbereich: Titel und Plaketten
    detailTitle:SetText(Localized(dungeon, "name"))
    local pillList = {}
    if isLog then
        table.insert(pillList, { ns.L("QUESTLOG_COUNT", #dungeon.quests), { 0.18, 0.18, 0.22, 1 } })
        local ready = LogReadyCount(dungeon)
        if ready > 0 then table.insert(pillList, { ns.L("READY_COUNT", ready), STATUS.READY.pill }) end
    end
    if dungeon.levels then
        table.insert(pillList, { ns.L("LEVEL", ColoredLevels(dungeon.levels)), { 0.18, 0.18, 0.22, 1 } })
    end
    if dungeon.zone then
        table.insert(pillList, { Localized(dungeon, "zone"), { 0.18, 0.18, 0.22, 1 } })
    end
    if dungeon.faction then
        table.insert(pillList, { FactionText(dungeon.faction), FACTION_PILL[dungeon.faction] or COLOR.card })
    end
    if dungeon.type == "Neu in Forever" then
        table.insert(pillList, { ns.L("NEW_IN_FOREVER"), { 0.08, 0.35, 0.50, 0.9 } })
    end
    LayoutPills(pillList)

    -- Quests als Karten
    local width = math.max(1, questScroll:GetWidth() - 2)
    questContent:SetWidth(width)
    local y, shown, done, total = 0, 0, 0, #(dungeon.quests or {})
    local lastZone, headerCount = nil, 0
    for _, card in ipairs(BuildCards(dungeon)) do
        local quest = card.quest
        -- "Alle Quests": vor jedem neuen Gebiet eine Überschrift (Gebiet in Gold, Anzahl, feine Linie)
        if dungeon == QUESTLOG and quest.zone ~= lastZone then
            lastZone = quest.zone
            headerCount = headerCount + 1
            local h = GetZoneHeader(headerCount)
            local zone = logZones[quest.zone or "?"]
            h.text:SetText((quest.zone or "?") .. (zone and ("  |cff8a8a8a" .. #zone.quests .. "|r") or ""))
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", questContent, "TOPLEFT", 0, -y - (headerCount > 1 and 6 or 0))
            h:SetWidth(width)
            h:Show()
            y = y + ZONE_HEADER_HEIGHT + (headerCount > 1 and 6 or 0)
        end
        do
            shown = shown + 1
            local entry = GetQuestEntry(shown)
            entry.quest = quest

            local status = GetQuestStatus(quest.id) or "OPEN"
            if quest.isLog and status == "ACTIVE" and IsLogQuestReady(quest.id) then status = "READY" end
            local style = STATUS[status]
            entry.stripe:SetColorTexture(style.stripe[1], style.stripe[2], style.stripe[3], 1)
            done = done + card.done
            -- Quest im Questlog: echte Belohnungen vom Spiel lesen und merken (einmal je Sitzung und Quest)
            ns.ReadLogRewardsOnce(quest.id)
            -- gemerkte echte Belohnungen gehen vor Questies Daten
            local seen = ns.SeenQuestRewards(quest.id)
            if seen then
                quest.rewards = seen
            -- Belohnungen aus dem Spiel (im Questlog vollständig, sonst soweit der Server sie nachlädt)
            elseif (not quest.rewards or #quest.rewards == 0) and ns.QuestRewardItemIDs then
                local ids = ns.QuestRewardItemIDs(quest.id)
                if #ids > 0 then quest.rewards = ids end
            end

            SetPill(entry.levelPill, ns.L("LEVEL", QuestLevel(quest) or "?"), { 0.20, 0.20, 0.25, 1 })
            if style.textKey then
                SetPill(entry.statusPill, ns.L(style.textKey), style.pill)
            else
                entry.statusPill:Hide()
            end

            entry.title:SetText(QuestName(quest))
            if status == "DONE" then
                entry.title:SetTextColor(0.55, 0.55, 0.55)
            else
                entry.title:SetTextColor(1, 0.82, 0)
            end

            local where = Localized(quest, "zone") or "?"
            if quest.x and quest.y then
                where = where .. " |cff888888(" .. quest.x .. ", " .. quest.y .. ")|r"
            end
            -- Zeile 1: Questgeber, Ort und Kurzangaben; Zeile 2 nur bei Vorquest/Notiz.
            -- Ist der Questgeber ein Gegenstand, steht er in einer eigenen Zeile darüber (entry.giverItem)
            local parts = {}
            if quest.isLog then
                -- Questlog: Gebiet (Überschrift im Questlog) und, falls die Quest zu einem Dungeon gehört, dieser
                if quest.zone then table.insert(parts, "|cff888888" .. quest.zone .. "|r") end
                local inDungeon = ns.DungeonForQuest and ns.DungeonForQuest(quest.id)
                if inDungeon then
                    table.insert(parts, "|cff4fc3f7" .. ns.L("QUESTLOG_DUNGEON", Localized(inDungeon, "name")) .. "|r")
                end
            elseif quest.giverItemID then
                if quest.zone then table.insert(parts, where) end
            else
                table.insert(parts, (GiverText(quest, true) or "?") .. " |cff888888–|r " .. where)
            end
            -- Hinweis, wenn man die Quest erst im Dungeon bekommt
            -- Vorquest (außerhalb des Dungeons): zuerst erledigen, damit es mit den Dungeonquests weitergeht
            if quest.isPrequest then table.insert(parts, 1, "|cffff9933" .. ns.L("PREQUEST_NEEDED") .. "|r") end
            if quest.startsInside then table.insert(parts, "|cff4fc3f7" .. ns.L("STARTS_INSIDE") .. "|r") end
            if quest.minLevel then table.insert(parts, "|cff888888" .. ns.L("FROM_LEVEL") .. "|r " .. quest.minLevel) end
            -- Fraktion nur nennen, wenn sie vom Dungeon abweicht

            local className = ClassText(quest)
            if className then table.insert(parts, className) end
            if quest.id and ns.db.showQuestIDs then table.insert(parts, "|cff666666ID " .. quest.id .. "|r") end
            local lines = { table.concat(parts, "   ") }
            local extraParts = {}
            -- Questkette (enthält auch die Vorquest); ohne Kette nur die Vorquest
            -- Questreihe aus Questie: als eigene Zeilen mit Tooltip (LayoutCardChain); sonst kurze Kette im Text
            local questieChain = card.chain -- aus Questie bzw. gleichnamige Quests (siehe BuildCards)
            local chainText = (not questieChain) and ChainText(quest) or nil
            -- "Vorquest: …" nur ohne Questreihe – mit Reihe steht die Vorquest schon darin
            local prequest = (not questieChain) and PrequestText(quest) or nil
            if chainText then
                table.insert(extraParts, chainText)
            elseif prequest then
                table.insert(extraParts, "|cff888888" .. ns.L("PREQUEST") .. "|r " .. prequest)
            end
            if quest.note then table.insert(extraParts, "|cff9a9a9a" .. quest.note .. "|r") end
            if #extraParts > 0 then table.insert(lines, table.concat(extraParts, "   ")) end
            -- Gruppenabgleich: wer die Quest hat und wem sie fehlt (nur wenn sie jemand hat, auch man selbst)
            if quest.id and IsInGroup() then
                local have, missing = GetGroupQuestStatus(quest.id, false)
                if #have > 0 or status == "ACTIVE" then
                    local groupParts = {}
                    if #have > 0 then
                        table.insert(groupParts, "|cff33ff99" .. ns.L("GROUP_HAS_QUEST") .. "|r " .. table.concat(have, ", "))
                    end
                    if #missing > 0 then
                        table.insert(groupParts, "|cffff7070" .. ns.L("GROUP_MISSING") .. "|r " .. table.concat(missing, ", "))
                    end
                    if #groupParts > 0 then table.insert(lines, table.concat(groupParts, "   ")) end
                end
            end

            -- Rechts Platz für die Plaketten lassen
            -- Reihenfolge rechts in der Titelzeile: [Status] [Fraktion] [Level] [Teilen] [Kartenpunkt]
            local hasWaypoint = quest.x ~= nil and quest.y ~= nil
            local hasShare = status == "ACTIVE" or status == "READY"
            entry.waypointButton:SetShown(hasWaypoint)
            entry.shareButton:SetShown(hasShare)
            -- Ohne Gruppe bzw. bei nicht teilbaren Quests nur blass anzeigen (Tooltip nennt den Grund)
            entry.shareButton:SetAlpha(hasShare and CanShareQuest(quest) and 1 or 0.45)
            local anchor -- Element, links neben das das nächste gesetzt wird
            entry.shareButton:ClearAllPoints()
            if hasWaypoint then anchor = entry.waypointButton end
            if hasShare then
                if anchor then
                    entry.shareButton:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
                else
                    entry.shareButton:SetPoint("TOPRIGHT", -8, -5)
                end
                anchor = entry.shareButton
            end
            entry.levelPill:ClearAllPoints()
            if anchor then
                entry.levelPill:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
            else
                entry.levelPill:SetPoint("TOPRIGHT", -8, -5)
            end
            -- Fraktionswappen setzen (bei "Beide" zwei Wappen nebeneinander)
            local factionIcons = {}
            if quest.faction == "Alliance" or quest.faction == "Both" then table.insert(factionIcons, FACTION_ICON.Alliance) end
            if quest.faction == "Horde" or quest.faction == "Both" then table.insert(factionIcons, FACTION_ICON.Horde) end
            entry.factionFrame.faction = quest.faction
            for i, icon in ipairs(entry.factionFrame.icons) do
                if factionIcons[i] then
                    icon:SetTexture(factionIcons[i])
                    icon:Show()
                else
                    icon:Hide()
                end
            end
            entry.factionFrame:SetWidth(math.max(1, #factionIcons * 17 - 1))
            if #factionIcons > 0 then
                entry.statusPill:SetPoint("RIGHT", entry.factionFrame, "LEFT", -4, 0)
            else
                entry.statusPill:SetPoint("RIGHT", entry.levelPill, "LEFT", -4, 0)
            end

            local pillSpace = entry.levelPill:GetWidth() + (entry.statusPill:IsShown() and entry.statusPill:GetWidth() + 4 or 0)
                + (#factionIcons > 0 and entry.factionFrame:GetWidth() + 4 or 0)
                + (hasWaypoint and entry.waypointButton:GetWidth() + 4 or 0)
                + (hasShare and entry.shareButton:GetWidth() + 4 or 0) + 20
            entry.title:SetWidth(math.max(80, width - 12 - pillSpace))
            entry.info:SetWidth(width - 24)
            entry.info:SetText(table.concat(lines, "\n"))
            entry.desc:SetWidth(width - 24)
            -- Questlog: die Ziele mit Fortschritt (je Ziel eine Zeile); Dungeonquests: Text aus dem Quest-Tooltip
            if entry.desc.SetMaxLines then entry.desc:SetMaxLines(quest.isLog and 8 or 2) end
            entry.desc:SetText((quest.isLog and LogObjectivesText(quest.id)) or GetQuestTooltipText(quest.id) or "")

            -- Startgegenstand: Symbol in Seltenheitsfarbe, "Startet durch: [Name]"
            local giverItemHeight = 0
            entry.info:ClearAllPoints()
            if quest.giverItemID then
                local button = entry.giverItem
                local itemName, link, quality, icon = GetRewardInfo(quest.giverItemID)
                local r, g, b = GetQualityColor(quality)
                button.itemID = quest.giverItemID
                button.link = link
                button.icon:SetTexture(icon or 134400)
                button.border:SetColorTexture(r, g, b, 1)
                button.name:SetTextColor(r, g, b)
                button.name:SetText("|cff888888" .. ns.L("STARTED_BY_ITEM") .. "|r "
                    .. (itemName and ("[" .. itemName .. "]") or ns.L("ITEM_LOADING", quest.giverItemID)))
                button:SetWidth(width - 24)
                button:Show()
                entry.info:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -3)
                giverItemHeight = button:GetHeight() + 3
            else
                entry.giverItem:Hide()
                entry.info:SetPoint("TOPLEFT", entry.desc, "BOTTOMLEFT", 0, -3)
            end

            local chainHeight = LayoutCardChain(entry, questieChain, quest, width - 24)
            entry.rewardToggle:ClearAllPoints()
            entry.rewardToggle:SetPoint("TOPLEFT", entry.info, "BOTTOMLEFT", -2, -3 - chainHeight)
            local rewardHeight = LayoutRewards(entry, quest, width - 24, questieChain)
            local height = math.max(entry.title:GetStringHeight(), 16) + entry.desc:GetStringHeight() + entry.info:GetStringHeight() + 20
                + rewardHeight + giverItemHeight + chainHeight
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", questContent, "TOPLEFT", 0, -y)
            entry:SetSize(width, height)
            entry:Show()
            y = y + height + 4
        end
    end
    questContent:SetHeight(math.max(1, y))

    -- Zusammenfassung bzw. Hinweis, wenn nichts angezeigt wird
    if isLog then
        detailExtra:SetText(ns.L("QUESTLOG_COUNT", total) .. "  ·  " .. ns.L("READY_COUNT", LogReadyCount(dungeon)))
        detailEmpty:SetText(ns.L("QUESTLOG_EMPTY"))
        detailEmpty:SetShown(shown == 0)
    elseif total == 0 then
        detailExtra:SetText("")
        detailEmpty:SetText(ns.L("NO_QUESTS_DUNGEON"))
        detailEmpty:Show()
    elseif shown == 0 then
        detailExtra:SetText("")
        local remaining, completed = CountQuests(dungeon)
        if hideCompleted and completed > 0 and remaining == 0 then
            detailExtra:SetText(ns.L("REMAINING_COUNT", 0) .. "  ·  " .. ns.L("DONE_COUNT", completed))
            detailEmpty:SetText(ns.L("NO_QUESTS_REMAINING"))
        else
            detailExtra:SetText("")
            detailEmpty:SetText(ns.L("NO_QUESTS_FACTION"))
        end
        detailEmpty:Show()
    else
        detailEmpty:Hide()
        -- Verbleibend = noch nicht abgeschlossen (mit den aktuellen Filtern)
        local remaining, completed = CountQuests(dungeon)
        detailExtra:SetText(ns.L("REMAINING_COUNT", remaining) .. "  ·  " .. ns.L("DONE_COUNT", completed))
    end
end

RequestRefresh = function()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.4, RefreshDetail) -- (mehrere Ereignisse kurz hintereinander = ein Neuaufbau)
end
ns.RequestDungeonRefresh = RequestRefresh -- für erneute Questdaten-Anfragen (siehe RequestQuestData)

---------------------------------------------------------------------------
-- Linke Seite: Liste der Dungeons
---------------------------------------------------------------------------

local RefreshList

---------------------------------------------------------------------------
-- Gruppensuche ("Suche nach Gruppe"): Dungeon dort vorauswählen und nach Gruppen dafür suchen
---------------------------------------------------------------------------

-- Name in Wörter zerlegen: klein, ohne Klammerzusatz, ohne Satzzeichen und Artikel, ohne End-"s"
-- (damit "Scharlachrote Kloster" und "Scharlachrotes Kloster - Friedhof" zusammenpassen)
local IGNORED_WORDS = { der = true, die = true, das = true, the = true, of = true, ["-"] = true }
local function NameWords(name)
    local words = {}
    name = (name or ""):lower():gsub("%b()", " "):gsub("[%p]", " ")
    for word in name:gmatch("%S+") do
        if not IGNORED_WORDS[word] then
            words[(word:gsub("s$", ""))] = true
        end
    end
    return words
end

-- Passt ein Eintrag der Gruppensuche zu unserem Dungeon? (alle Wörter unseres Namens kommen darin vor)
local function MatchesLFGName(dungeon, lfgName)
    local lfgWords = NameWords(lfgName)
    for _, name in ipairs({ dungeon.name, dungeon.nameEN }) do
        local words = NameWords(name)
        if next(words) then
            local all = true
            for word in pairs(words) do
                if not lfgWords[word] then all = false break end
            end
            if all then return true end
        end
    end
    return false
end

-- Einträge ("Aktivitäten") der Gruppensuche, die zum Dungeon passen.
-- Rückgabe: Liste der Aktivitäts-IDs und die Kategorie, in der sie stehen
local function FindGroupFinderActivities(dungeon)
    local found, foundCategory = {}, nil
    if not (C_LFGList and C_LFGList.GetAvailableActivities and C_LFGList.GetActivityInfoTable) then return found end
    local categories = C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableCategories() or { 2 }
    for _, categoryID in ipairs(categories) do
        for _, activityID in ipairs(C_LFGList.GetAvailableActivities(categoryID) or {}) do
            local info = C_LFGList.GetActivityInfoTable(activityID)
            local name = info and (info.fullName or info.shortName)
            if name and MatchesLFGName(dungeon, name) then
                table.insert(found, activityID)
                foundCategory = foundCategory or categoryID
            end
        end
        if foundCategory then break end -- nur die erste passende Kategorie (z. B. "Dungeons")
    end
    return found, foundCategory
end

-- Variante mit Kategorien und Suchliste (LFGListFrame): Filter auf den Dungeon setzen, dann suchen
local function OpenListGroupFinder(activities, categoryID)
    if PVEFrame_ShowFrame and LFGListPVEStub then
        PVEFrame_ShowFrame("GroupFinderFrame", LFGListPVEStub)
    elseif LFGListFrame and ShowUIPanel then
        ShowUIPanel(LFGListFrame)
    end
    local frame = LFGListFrame
    if not (frame and frame.SearchPanel) then return false end
    -- Vorauswahl: im erweiterten Filter nur diesen Dungeon (bzw. seine Flügel) auswählen
    local preselected = false
    if C_LFGList.GetAdvancedFilter and C_LFGList.SaveAdvancedFilter then
        local filter = C_LFGList.GetAdvancedFilter()
        if type(filter) == "table" and type(filter.activities) == "table" then
            filter.activities = activities
            C_LFGList.SaveAdvancedFilter(filter)
            preselected = true
        end
    end
    local panel = frame.SearchPanel
    if LFGListSearchPanel_Clear then LFGListSearchPanel_Clear(panel) end
    -- Ohne erweiterten Filter: Suchtext auf den Dungeon setzen
    if not preselected and C_LFGList.SetSearchToActivity then C_LFGList.SetSearchToActivity(activities[1]) end
    if LFGListSearchPanel_SetCategory then
        LFGListSearchPanel_SetCategory(panel, categoryID, 0, frame.baseFilters)
    end
    if LFGListFrame_SetActivePanel then LFGListFrame_SetActivePanel(frame, panel) end
    if LFGListSearchPanel_DoSearch then LFGListSearchPanel_DoSearch(panel) end
    return true
end

-- Variante "Suche nach Gruppe" (Classic-Stil, LFGParentFrame mit Reiter "Durchsuchen" = LFGBrowseFrame):
-- Reiter Durchsuchen öffnen, Kategorie setzen, im Filter "Nach Aktivität filtern" nur diesen Dungeon
-- anhaken und suchen
local function OpenBrowseGroupFinder(activities, categoryID)
    if not LFGParentFrame then return false end
    if ShowLFGParentFrame then
        ShowLFGParentFrame(2) -- 2 = Reiter "Durchsuchen"
    else
        if ShowUIPanel then ShowUIPanel(LFGParentFrame) else LFGParentFrame:Show() end
        if LFGParentFrameTab2_OnClick then LFGParentFrameTab2_OnClick() end
    end
    local browse = LFGBrowseFrame
    if browse then
        -- Kategorie (z. B. "Dungeons") einstellen
        local categoryDropdown = browse.CategoryDropdown or browse.CategoryDropDown
        if categoryDropdown and categoryDropdown.SetValue and categoryID
            and not (categoryDropdown.GetValue and categoryDropdown:GetValue() == categoryID) then
            categoryDropdown:SetValue(categoryID)
        end
        -- Aktivitätsfilter: alles abwählen, dann nur diesen Dungeon (bzw. seine Flügel) anhaken
        local activityDropdown = browse.ActivityDropdown or browse.ActivityDropDown
        if activityDropdown and activityDropdown.ValueReset and activityDropdown.ValueSetSelected then
            activityDropdown:ValueReset()
            for _, activityID in ipairs(activities) do
                activityDropdown:ValueSetSelected(activityID, true)
            end
        end
    end
    -- Suche mit dem Filter starten
    if LFGBrowse_DoSearch then
        LFGBrowse_DoSearch()
    elseif C_LFGList.Search then
        C_LFGList.Search(categoryID, activities)
    end
    return true
end

local function OpenInGroupFinder(dungeon)
    local prefix = ns.ChatPrefix() .. ": "
    if InCombatLockdown() then
        print(prefix .. ns.L("LFG_COMBAT"))
        return
    end
    if not C_LFGList then
        print(prefix .. ns.L("LFG_UNAVAILABLE"))
        return
    end
    local activities, categoryID = FindGroupFinderActivities(dungeon)
    if #activities == 0 then
        print(prefix .. ns.L("LFG_NOT_FOUND", Localized(dungeon, "name")))
        return
    end
    -- Forever nutzt "Suche nach Gruppe" (Classic-Stil); die andere Variante nur, falls es die nicht gibt
    local opened = OpenBrowseGroupFinder(activities, categoryID) or OpenListGroupFinder(activities, categoryID)
    if not opened then
        print(prefix .. ns.L("LFG_UNAVAILABLE"))
        return
    end
    -- Dungeonfenster hinter die Gruppensuche legen (ein Klick darauf holt es wieder nach vorn)
    if window then window:SetFrameStrata("LOW") end
end

-- /fq lfg: zeigt, was das Spiel für die Gruppensuche anbietet (zur Fehlersuche)
function ns.DebugGroupFinder()
    local prefix = ns.ChatPrefix() .. ": "
    local function yes(value) return value and "|cff33ff99ja|r" or "|cffff7070nein|r" end
    print(prefix .. "C_LFGList " .. yes(C_LFGList) .. ", LFGListFrame " .. yes(LFGListFrame)
        .. ", PVEFrame " .. yes(PVEFrame) .. ", LFGParentFrame " .. yes(LFGParentFrame)
        .. ", LFGBrowseFrame " .. yes(LFGBrowseFrame))
    if not (C_LFGList and C_LFGList.GetAvailableCategories) then return end
    print(prefix .. "Erweiterter Filter: " .. yes(C_LFGList.GetAdvancedFilter))
    for _, categoryID in ipairs(C_LFGList.GetAvailableCategories() or {}) do
        local info = C_LFGList.GetLfgCategoryInfo and C_LFGList.GetLfgCategoryInfo(categoryID)
        local activities = C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities(categoryID) or {}
        local sample = {}
        for i = 1, math.min(3, #activities) do
            local activity = C_LFGList.GetActivityInfoTable(activities[i])
            table.insert(sample, activity and activity.fullName or "?")
        end
        print(prefix .. string.format("Kategorie %d (%s): %d Einträge, z. B. %s", categoryID,
            info and info.name or "?", #activities, table.concat(sample, ", ")))
    end
    -- Aufbau des erweiterten Filters (welche Felder es gibt)
    if C_LFGList.GetAdvancedFilter then
        local filter = C_LFGList.GetAdvancedFilter()
        local fields = {}
        if type(filter) == "table" then
            for key, value in pairs(filter) do table.insert(fields, key .. "=" .. type(value)) end
        end
        print(prefix .. "Filterfelder: " .. (#fields > 0 and table.concat(fields, ", ") or "keine"))
    end
    -- Treffer für den im Dungeonfenster gewählten Dungeon
    local dungeon = selectedDungeon or ns.DUNGEON_DATA[1]
    if not dungeon then return end -- (noch) keine Dungeons geladen
    local activities, categoryID = FindGroupFinderActivities(dungeon)
    local names = {}
    for _, activityID in ipairs(activities) do
        local activity = C_LFGList.GetActivityInfoTable(activityID)
        table.insert(names, activityID .. " " .. (activity and activity.fullName or "?"))
    end
    print(prefix .. string.format("%s -> Kategorie %s: %s", Localized(dungeon, "name"), tostring(categoryID),
        #names > 0 and table.concat(names, "; ") or "keine Treffer"))
    -- Sichtbare Fenster der Gruppensuche (Name des offenen Fensters hilft beim Anpassen)
    local shown = {}
    for _, name in ipairs({ "PVEFrame", "LFGListFrame", "LFGParentFrame", "LFGBrowseFrame", "LFGListingFrame" }) do
        local frame = _G[name]
        if frame and frame.IsShown and frame:IsShown() then table.insert(shown, name) end
    end
    print(prefix .. "Offen: " .. (#shown > 0 and table.concat(shown, ", ") or "keins"))
end

-- Auge-Symbol der Gruppensuche (erstes Bild der Augen-Animation)
local function SetEyeTexture(texture)
    if texture:SetTexture("Interface\\LFGFrame\\LFG-Eye") ~= false then
        texture:SetTexCoord(0, 0.125, 0, 0.25)
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Für den Tracker: Auge-Symbol, Gruppensuche öffnen und Dungeon zu einer Questlog-Überschrift finden
ns.SetEyeTexture = SetEyeTexture
ns.OpenInGroupFinder = OpenInGroupFinder
local headerDungeons = {} -- Zwischenspeicher: Überschrift -> Dungeon (false = keiner)
function ns.FindDungeonForHeader(header)
    if not header then return nil end
    if headerDungeons[header] == nil then
        headerDungeons[header] = false
        for _, dungeon in ipairs(ns.DUNGEON_DATA) do
            if MatchesLFGName(dungeon, header) then
                headerDungeons[header] = dungeon
                break
            end
        end
    end
    return headerDungeons[header] or nil
end

local function GetListButton(index)
    local button = listButtons[index]
    if not button then
        button = CreateFrame("Button", nil, listContent)
        button:SetHeight(LIST_ROW_HEIGHT - 4)

        button.background = button:CreateTexture(nil, "BACKGROUND")
        button.background:SetAllPoints()

        -- Leiste links beim ausgewählten Dungeon
        button.selectBar = button:CreateTexture(nil, "ARTWORK")
        button.selectBar:SetPoint("TOPLEFT")
        button.selectBar:SetPoint("BOTTOMLEFT")
        button.selectBar:SetWidth(3)
        button.selectBar:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.05)

        -- Auge vor dem Namen: Klick öffnet die Gruppensuche mit diesem Dungeon vorausgewählt
        button.eye = CreateFrame("Button", nil, button)
        button.eye:SetSize(20, 20)
        button.eye:SetHitRectInsets(-4, -4, -4, -4) -- etwas größere Klickfläche
        button.eye:SetPoint("LEFT", 8, 0)
        button.eye.icon = button.eye:CreateTexture(nil, "ARTWORK")
        button.eye.icon:SetAllPoints()
        SetEyeTexture(button.eye.icon)
        button.eye:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button.eye:SetScript("OnClick", function(self)
            local dungeon = self:GetParent().dungeon
            if dungeon then OpenInGroupFinder(dungeon) end
        end)
        button.eye:SetScript("OnEnter", function(self)
            ns.Style.GetTooltip():SetOwner(self, "ANCHOR_RIGHT")
            ns.Style.GetTooltip():AddLine(ns.L("TIP_LFG"), 1, 1, 1)
            ns.Style.GetTooltip():Show()
        end)
        button.eye:SetScript("OnLeave", function() ns.Style.GetTooltip():Hide() end)

        button.name = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        button.name:SetPoint("TOPLEFT", 34, -6)
        button.name:SetPoint("RIGHT", -40, 0)
        button.name:SetJustifyH("LEFT")
        button.name:SetWordWrap(false)

        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.sub:SetPoint("TOPLEFT", button.name, "BOTTOMLEFT", 0, -4)
        button.sub:SetPoint("RIGHT", -40, 0)
        button.sub:SetJustifyH("LEFT")
        button.sub:SetWordWrap(false)

        button.factionIcon = button:CreateTexture(nil, "OVERLAY")
        button.factionIcon:SetSize(16, 16)
        button.factionIcon:SetPoint("TOPRIGHT", -10, -5)

        -- Anzahl der Quests als kleine Plakette
        button.countPill = CreatePill(button)
        button.countPill:SetHeight(16)
        button.countPill:SetPoint("BOTTOMRIGHT", -8, 5)

        -- Dünner Fortschrittsbalken unten: Anteil der abgeschlossenen Quests (grün)
        button.progressBg = button:CreateTexture(nil, "ARTWORK")
        button.progressBg:SetHeight(2)
        button.progressBg:SetPoint("BOTTOMLEFT", 34, 2)
        button.progressBg:SetPoint("BOTTOMRIGHT", -44, 2)
        button.progressBg:SetColorTexture(1, 1, 1, 0.08)
        button.progressFill = button:CreateTexture(nil, "OVERLAY")
        button.progressFill:SetHeight(2)
        button.progressFill:SetPoint("BOTTOMLEFT", button.progressBg, "BOTTOMLEFT")
        button.progressFill:SetColorTexture(0.2, 0.8, 0.3, 0.9)

        button:SetScript("OnClick", function(self)
            if window.BringToFront then window.BringToFront() end
            selectedDungeon = self.dungeon
            questScroll:SetVerticalScroll(0)
            RefreshList()
            RefreshDetail()
        end)
        listButtons[index] = button
    end
    return button
end

RefreshList = function()
    CheckAllDungeonQuests() -- einmalig: welche Quests gibt es in der Beta nicht?
    local filter = searchBox and strtrim(searchBox:GetText() or ""):lower() or ""
    local width = math.max(1, listScroll:GetWidth())
    listContent:SetWidth(width)

    -- Sichtbare Dungeons bestimmen (Suche und Reiter "Mein Levelbereich")
    local visible = {}
    local selectedVisible = false
    for _, dungeon in ipairs(ns.DUNGEON_DATA) do
        -- Suche findet deutsche und englische Namen
        local haystack = (dungeon.name .. " " .. (dungeon.nameEN or "") .. " " .. (dungeon.zone or "") .. " "
            .. (dungeon.zoneEN or "")):lower()
        if (filter == "" or haystack:find(filter, 1, true)) and (not levelTabActive or IsDungeonInMyRange(dungeon))
            and raidTabActive == (dungeon.isRaid == true) then
            table.insert(visible, dungeon)
            if dungeon == selectedDungeon then selectedVisible = true end
        end
    end
    -- Reiter "Questlog": links "Alle Quests" und je Gebiet ein Eintrag (ohne Auge und Wappen; Anzahl der Quests,
    -- Balken = Anteil der abgabebereiten); die Suche findet Gebiets- und Questnamen
    if logTabActive then
        RefreshLogQuests()
        -- (nur die Gebiete – "Alle Quests" auf Wunsch entfernt)
        local entries = {}
        for _, zone in ipairs(logZoneOrder) do
            local hit = filter == "" or zone.name:lower():find(filter, 1, true)
            if not hit then
                for _, quest in ipairs(zone.quests) do
                    if (quest.name or ""):lower():find(filter, 1, true) then hit = true break end
                end
            end
            if hit then entries[#entries + 1] = zone end
        end
        local found = false
        for _, e in ipairs(entries) do if e == selectedDungeon then found = true end end
        if not found then selectedDungeon = entries[1] end
        for i, e in ipairs(entries) do
            local button = GetListButton(i)
            button.dungeon = e
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, -(i - 1) * LIST_ROW_HEIGHT)
            button:SetWidth(width - 8)
            button.eye:Hide()
            button.factionIcon:Hide()
            button.name:SetText(e == QUESTLOG and ns.L("QUESTLOG_ALL") or e.name)
            if e == QUESTLOG then
                button.name:SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3])
            else
                button.name:SetTextColor(0.95, 0.95, 0.95)
            end
            local count, ready = #e.quests, LogReadyCount(e)
            button.sub:SetText("|cff8a8a8a" .. ns.L("QUESTLOG_COUNT", count) .. "  ·  " .. ns.L("READY_COUNT", ready) .. "|r")
            if count > 0 then SetPill(button.countPill, count, { 0.22, 0.22, 0.27, 1 }) else button.countPill:Hide() end
            button.progressBg:SetShown(count > 0)
            if count > 0 and ready > 0 then
                local barWidth = math.max(1, width - 8 - 34 - 44)
                button.progressFill:SetWidth(math.max(1, barWidth * ready / count))
                button.progressFill:Show()
            else
                button.progressFill:Hide()
            end
            local selected = e == selectedDungeon
            button.selectBar:SetShown(selected)
            button.background:SetColorTexture(1, 1, 1, selected and 0.08 or 0)
            button:Show()
        end
        for i = #entries + 1, #listButtons do listButtons[i]:Hide() end
        listContent:SetHeight(math.max(1, #entries * LIST_ROW_HEIGHT))
        return
    end
    -- Ist der gewählte Dungeon im Reiter nicht dabei, den ersten passenden wählen (auch nach dem Reiter "Questlog")
    if not selectedVisible and (levelTabActive or raidTabActive or (selectedDungeon and (selectedDungeon.isRaid
        or selectedDungeon.isLog))) then
        selectedDungeon = visible[1]
    end

    local shown = 0
    for _, dungeon in ipairs(visible) do
        do
            shown = shown + 1
            local button = GetListButton(shown)
            button.dungeon = dungeon
            button.eye:Show()
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, -(shown - 1) * LIST_ROW_HEIGHT)
            button:SetWidth(width - 8)

            -- Dungeons der Gegenfraktion grau
            local ownFaction = IsMyFaction(dungeon.faction)
            -- Gibt es keine seiner Quests in der Beta (vom Server gemeldet): Vermerk hinter dem Namen
            button.name:SetText(Localized(dungeon, "name")
                .. (DungeonNotInBeta(dungeon) and (" |cff8a8a8a" .. ns.L("NOT_IN_BETA") .. "|r") or ""))
            if ownFaction then
                button.name:SetTextColor(0.95, 0.95, 0.95)
            else
                button.name:SetTextColor(0.45, 0.45, 0.45)
            end

            local sub = ColoredLevels(dungeon.levels)
            if dungeon.zone then sub = sub .. "   |cff8a8a8a" .. Localized(dungeon, "zone") .. "|r" end
            if dungeon.type == "Neu in Forever" then sub = sub .. "   |cff4fc3f7" .. ns.L("NEW_TAG") .. "|r" end
            button.sub:SetText(sub)

            local icon = FACTION_ICON[dungeon.faction]
            if icon then
                button.factionIcon:SetTexture(icon)
                button.factionIcon:SetDesaturated(false) -- Wappen immer farbig
                button.factionIcon:Show()
            else
                button.factionIcon:Hide()
            end

            -- Anzahl der verbleibenden (noch nicht abgeschlossenen) Quests mit den aktuellen Filtern
            local count, completed = CountQuests(dungeon)
            if count > 0 then
                SetPill(button.countPill, count, { 0.22, 0.22, 0.27, 1 })
            else
                button.countPill:Hide()
            end
            -- Fortschrittsbalken: abgeschlossen / alle Quests (mit den aktuellen Filtern)
            local total = count + completed
            button.progressBg:SetShown(total > 0)
            if total > 0 and completed > 0 then
                local barWidth = math.max(1, width - 8 - 34 - 44)
                button.progressFill:SetWidth(math.max(1, barWidth * completed / total))
                button.progressFill:Show()
            else
                button.progressFill:Hide()
            end

            local selected = dungeon == selectedDungeon
            button.selectBar:SetShown(selected)
            if selected then
                button.background:SetColorTexture(1, 1, 1, 0.08)
            else
                button.background:SetColorTexture(0, 0, 0, 0)
            end
            button:Show()
        end
    end
    for i = shown + 1, #listButtons do
        listButtons[i]:Hide()
    end
    listContent:SetHeight(math.max(1, shown * LIST_ROW_HEIGHT))
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function CreateWindow()
    window = CreateFrame("Frame", "ForeverQuestsDungeons", UIParent, "BackdropTemplate")
    window:SetSize(960, 660)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true) -- per Klick vor andere Fenster (z. B. AtlasLoot) holen
    -- Nach dem Öffnen der Gruppensuche liegt das Fenster weiter hinten: Klick holt es wieder nach vorn
    local function BringToFront() window:SetFrameStrata("DIALOG") end
    window.BringToFront = BringToFront
    window:HookScript("OnMouseDown", BringToFront)
    window:SetMovable(true)
    window:SetResizable(true)
    window:SetResizeBounds(780, 520, 1600, 1100)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    SetFlat(window, COLOR.background)
    tinsert(UISpecialFrames, "ForeverQuestsDungeons") -- mit Escape schließbar

    -- Titelleiste (zum Verschieben)
    local header = CreateFrame("Frame", nil, window, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(unpack(COLOR.header))
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    header:HookScript("OnMouseDown", BringToFront)

    local accentLine = header:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("BOTTOMLEFT")
    accentLine:SetPoint("BOTTOMRIGHT")
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.6)

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 16, 0)
    titleText:SetText(ns.L("DUNGEONS_TITLE"))
    local titleSub = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    titleSub:SetPoint("LEFT", titleText, "RIGHT", 10, -1)
    titleSub:SetText(ns.L("ADDON_NAME") .. "  ·  " .. ns.L("DUNGEONS_COUNT", #ns.DUNGEON_DATA))

    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    local close
    if hubUI and hubUI.CloseButton then
        close = hubUI.CloseButton(header, function() window:Hide() end)
        close:SetPoint("RIGHT", -8, 0)
    else
        close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
        close:SetPoint("RIGHT", -6, 0)
        close:SetScript("OnClick", function() window:Hide() end)
    end

    -- Linkes Feld: Suche und Dungeon-Liste
    local listPanel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    SetFlat(listPanel, COLOR.panel)
    listPanel:SetPoint("TOPLEFT", 12, -(HEADER_HEIGHT + 12))
    listPanel:SetPoint("BOTTOMLEFT", 12, FOOTER_HEIGHT + 4)
    listPanel:SetWidth(LIST_WIDTH)

    searchBox = CreateFrame("EditBox", nil, listPanel, "BackdropTemplate")
    SetFlat(searchBox, { 0.06, 0.06, 0.08, 1 })
    searchBox:SetHeight(28)
    -- Reiter: alle Dungeons / nur der eigene Levelbereich / Schlachtzüge / Questlog
    local tabWidth = math.floor((LIST_WIDTH - 16 - 18) / 4)
    local tabs = {}
    local function CurrentTab()
        if logTabActive then return "log" end
        if raidTabActive then return "raid" end
        return levelTabActive and "level" or "all"
    end
    local function UpdateTabs()
        -- Level-Regler unten nur im Reiter "Mein Level"
        if window.levelFilter then window.levelFilter:SetShown(levelTabActive) end
        if window.linkHint then window.linkHint:SetShown(not levelTabActive) end
        for _, tab in ipairs(tabs) do
            local active = tab.key == CurrentTab()
            if active then
                tab:SetBackdropColor(0.30, 0.25, 0.05, 1)
                tab:GetFontString():SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3])
            else
                tab:SetBackdropColor(0.16, 0.16, 0.20, 1)
                tab:GetFontString():SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end
    local function SelectTab(key)
        levelTabActive = key == "level"
        raidTabActive = key == "raid"
        logTabActive = key == "log"
        UpdateTabs()
        listScroll:SetVerticalScroll(0)
        questScroll:SetVerticalScroll(0)
        RefreshList()
        RefreshDetail()
    end
    local allTab = ns.Style.CreateButton(listPanel, ns.L("TAB_ALL"), tabWidth, 24, function() SelectTab("all") end)
    allTab.key = "all"
    local levelTab = ns.Style.CreateButton(listPanel, ns.L("TAB_MY_LEVEL"), tabWidth, 24, function() SelectTab("level") end,
        function(tooltip) tooltip:AddLine(ns.L("TIP_MY_LEVEL"), 1, 1, 1, true) end)
    levelTab.key = "level"
    local raidTab = ns.Style.CreateButton(listPanel, ns.L("TAB_RAIDS"), tabWidth, 24, function() SelectTab("raid") end,
        function(tooltip) tooltip:AddLine(ns.L("TIP_RAIDS"), 1, 1, 1, true) end)
    raidTab.key = "raid"
    local logTab = ns.Style.CreateButton(listPanel, ns.L("TAB_QUESTLOG"), tabWidth, 24, function() SelectTab("log") end,
        function(tooltip) tooltip:AddLine(ns.L("TIP_QUESTLOG"), 1, 1, 1, true) end)
    logTab.key = "log"
    -- Reihenfolge: Mein Levelbereich (Standard) | Dungeons | Schlachtzüge | Questlog
    levelTab:SetPoint("TOPLEFT", 8, -8)
    allTab:SetPoint("LEFT", levelTab, "RIGHT", 6, 0)
    raidTab:SetPoint("LEFT", allTab, "RIGHT", 6, 0)
    logTab:SetPoint("LEFT", raidTab, "RIGHT", 6, 0)
    tabs = { levelTab, allTab, raidTab, logTab }
    -- Breite nach Textlänge verteilen ("Mein Levelbereich" passte nicht in ein Viertel): jeder Reiter bekommt
    -- seinen Text + Rand, der übrige Platz wird gleichmäßig aufgeteilt
    do
        local total, natural, sum = LIST_WIDTH - 16 - 6 * (#tabs - 1), {}, 0
        for i, tab in ipairs(tabs) do
            local fs = tab:GetFontString()
            natural[i] = math.ceil((fs and fs:GetStringWidth() or 0) + 12)
            sum = sum + natural[i]
        end
        local extra = (total - sum) / #tabs
        for i, tab in ipairs(tabs) do
            tab:SetWidth(extra >= 0 and math.floor(natural[i] + extra) or math.floor(total / #tabs))
        end
    end
    -- Nach dem Darüberfahren die Reiterfarbe wiederherstellen
    for _, tab in ipairs(tabs) do tab:HookScript("OnLeave", UpdateTabs) end
    UpdateTabs()
    window.UpdateTabs = UpdateTabs -- für ns.ShowDungeon

    searchBox:SetPoint("TOPLEFT", 8, -40)
    searchBox:SetPoint("TOPRIGHT", -8, -40)
    searchBox:SetFontObject("GameFontHighlight")
    searchBox:SetTextInsets(28, 8, 0, 0)
    searchBox:SetAutoFocus(false)
    local searchIcon = searchBox:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 9, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.6, 0.6, 0.6)
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", 28, 0)
    placeholder:SetText(ns.L("SEARCH_PLACEHOLDER"))
    searchBox:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        listScroll:SetVerticalScroll(0)
        RefreshList()
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.8)
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(COLOR.border))
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    listScroll = CreateFrame("ScrollFrame", nil, listPanel)
    listScroll:SetPoint("TOPLEFT", 1, -76)
    listScroll:SetPoint("BOTTOMRIGHT", -1, 4)
    listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetSize(1, 1)
    listScroll:SetScrollChild(listContent)
    EnableWheelScroll(listScroll, listContent)

    -- Rechtes Feld: Dungeon-Kopf und Quests
    local detailPanel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    SetFlat(detailPanel, COLOR.panel)
    detailPanel:SetPoint("TOPLEFT", listPanel, "TOPRIGHT", 10, 0)
    detailPanel:SetPoint("BOTTOMRIGHT", -12, FOOTER_HEIGHT + 4)

    detailTitle = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    detailTitle:SetPoint("TOPLEFT", 20, -18)
    detailTitle:SetPoint("RIGHT", -330, 0)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetTextColor(1, 1, 1)

    -- Knopf oben rechts: Dungeon in AtlasLoot öffnen (nur sichtbar, wenn AtlasLoot geladen ist)
    atlasButton = ns.Style.CreateButton(detailPanel, ns.L("BTN_ATLASLOOT"), 120, 22, function(self)
        ShowAtlasLoot(self, selectedDungeon)
    end, function(tooltip) tooltip:AddLine(ns.L("TIP_ATLASLOOT")) end)
    atlasButton:SetPoint("TOPRIGHT", -16, -16)
    atlasButton:Hide()

    -- Knopf "Alle teilen": nur sichtbar, wenn Quests dieses Dungeons im Questlog stehen
    shareAllButton = ns.Style.CreateButton(detailPanel, ns.L("BTN_SHARE_ALL"), 90, 22, function()
        ShareAllQuests(selectedDungeon)
    end, function(tooltip)
        tooltip:AddLine(ns.L("TIP_SHARE_ALL"), 1, 1, 1, true)
        if not IsInGroup() then tooltip:AddLine(ns.L("SHARE_NO_GROUP"), 1, 0.3, 0.3) end
    end)
    shareAllButton:Hide()

    -- Knopf "Gruppe": Gruppenabgleich als Tooltip (wer welche Quest hat, wem sie fehlt)
    groupButton = ns.Style.CreateButton(detailPanel, ns.L("BTN_GROUP"), 70, 22, nil, function(tooltip)
        FillGroupTooltip(tooltip, selectedDungeon)
    end)
    groupButton:Hide()

    pillRow = CreateFrame("Frame", nil, detailPanel)
    pillRow:SetHeight(20)
    pillRow:SetPoint("TOPLEFT", detailTitle, "BOTTOMLEFT", 0, -10)
    pillRow:SetPoint("RIGHT", -20, 0)

    detailExtra = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailExtra:SetPoint("TOPLEFT", pillRow, "BOTTOMLEFT", 0, -10)
    detailExtra:SetPoint("RIGHT", -20, 0)
    detailExtra:SetJustifyH("LEFT")
    detailExtra:SetTextColor(0.65, 0.65, 0.65)

    local divider = detailPanel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 16, -112)
    divider:SetPoint("TOPRIGHT", -16, -112)

    questScroll = CreateFrame("ScrollFrame", nil, detailPanel)
    questScroll:SetPoint("TOPLEFT", 16, -124)
    questScroll:SetPoint("BOTTOMRIGHT", -16, 12)
    questContent = CreateFrame("Frame", nil, questScroll)
    questContent:SetSize(1, 1)
    questScroll:SetScrollChild(questContent)
    EnableWheelScroll(questScroll, questContent)

    detailEmpty = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    detailEmpty:SetPoint("CENTER", questScroll, "CENTER", 0, 30)
    detailEmpty:SetWidth(420)
    detailEmpty:SetJustifyH("CENTER")
    -- Fußleiste: Fraktionsfilter und Hinweis
    local factionCheck = ns.Style.CreateCheckbox(window, ns.L("ONLY_MY_FACTION"))
    factionCheck:SetPoint("BOTTOMLEFT", 16, 13)
    factionCheck:SetChecked(onlyOwnFaction)
    -- Zweites Häkchen: abgeschlossene Quests ausblenden
    local completedCheck = ns.Style.CreateCheckbox(window, ns.L("HIDE_COMPLETED"))
    completedCheck:SetPoint("LEFT", factionCheck.label, "RIGHT", 24, 0)
    completedCheck:SetChecked(hideCompleted)
    completedCheck:SetScript("OnClick", function(self)
        hideCompleted = self:GetChecked() and true or false
        questScroll:SetVerticalScroll(0)
        RefreshList()
        RefreshDetail()
    end)

    factionCheck:SetScript("OnClick", function(self)
        onlyOwnFaction = self:GetChecked() and true or false
        RefreshList()
        RefreshDetail()
    end)

    -- Nur im Reiter "Mein Level": Regler, wie viele Level über dem eigenen ein Dungeon beginnen darf (0–10)
    local levelFilter = CreateFrame("Frame", nil, window)
    levelFilter:SetSize(300, 20)
    levelFilter:SetPoint("LEFT", completedCheck.label, "RIGHT", 24, 0)
    levelFilter.text = levelFilter:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    levelFilter.text:SetPoint("LEFT")
    local levelSlider = ns.Style.CreateSlider(levelFilter, 120)
    levelSlider:SetMinMaxValues(0, 10)
    levelSlider:SetPoint("LEFT", levelFilter.text, "RIGHT", 10, 0)
    local function ShowLevelValue(value)
        levelFilter.text:SetText(ns.L("LEVEL_ABOVE", value))
    end
    levelSlider:SetValue(tonumber(ns.db.dungeonLevelAbove) or LEVEL_EARLY)
    ShowLevelValue(tonumber(ns.db.dungeonLevelAbove) or LEVEL_EARLY)
    levelSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        ShowLevelValue(value)
        if ns.db.dungeonLevelAbove == value then return end
        ns.db.dungeonLevelAbove = value
        listScroll:SetVerticalScroll(0)
        RefreshList()
        RefreshDetail()
    end)
    levelFilter:SetShown(levelTabActive)
    window.levelFilter = levelFilter

    -- Hinweis rechts in der Fußleiste
    local linkHint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    linkHint:SetPoint("BOTTOMRIGHT", -26, 16)
    linkHint:SetText(ns.L("LINK_HINT"))
    -- im Reiter "Mein Level" steht dort der Level-Regler: Hinweis dann ausblenden (sonst überlagern sie sich)
    linkHint:SetShown(not levelTabActive)
    window.linkHint = linkHint


    -- Ecke unten rechts: Größe ändern
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() window:StopMovingOrSizing() end)
    window:SetScript("OnSizeChanged", function()
        if window:IsShown() then
            RefreshList()
            RequestRefresh()
        end
    end)

    window:SetScript("OnShow", function()
        BringToFront()
        -- Menü und Dungeon-Fenster nie gleichzeitig offen
        if ns.HideOptions then ns.HideOptions() end
        if not selectedDungeon then
            -- Standard: erster Dungeon, der zum eigenen Level passt, sonst der erste
            local level = UnitLevel("player")
            for _, dungeon in ipairs(ns.DUNGEON_DATA) do
                local maxLevel = tonumber((dungeon.levels or ""):match("%d+%D+(%d+)"))
                if maxLevel and level <= maxLevel then
                    selectedDungeon = dungeon
                    break
                end
            end
            selectedDungeon = selectedDungeon or ns.DUNGEON_DATA[1]
        end
        RefreshList()
        RefreshDetail()
    end)

    -- Status (im Questlog / abgeschlossen) aktuell halten, solange das Fenster offen ist
    -- QUEST_DATA_LOAD_RESULT: angeforderte Questdaten (für den Tooltip-Text) sind da
    -- GROUP_ROSTER_UPDATE / UNIT_QUEST_LOG_CHANGED: Anzeige, wer in der Gruppe die Quest hat
    local events = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_DATA_LOAD_RESULT",
        "GROUP_ROSTER_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "ITEM_DATA_LOAD_RESULT" }
    for _, event in ipairs(events) do
        window:RegisterEvent(event)
    end
    window:SetScript("OnEvent", function(_, event, id, success)
        if not window:IsShown() then return end
        -- Daten-Antworten kommen auch für Anfragen anderer Addons (Questie, Taschen, Tooltips) – nur bei eigenen
        -- Anfragen neu aufbauen, sonst baute sich das Fenster ständig neu auf
        if event == "QUEST_DATA_LOAD_RESULT" and (not success or not requestedQuests[id]) then return end
        if event == "ITEM_DATA_LOAD_RESULT" and not requestedItems[id] then return end
        if event == "QUEST_DATA_LOAD_RESULT" then tooltipFailedAt[id] = nil end
        RequestRefresh()
        -- Quest angenommen, abgegeben oder abgebrochen: Anzahl beim Eintrag "Questlog" aktuell halten
        if (event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED") and window:IsShown() then
            C_Timer.After(0.3, function() if window and window:IsShown() then RefreshList() end end)
        end
        -- Beim Levelaufstieg kann sich der Levelbereich der Liste ändern
        if event == "PLAYER_LEVEL_UP" and window:IsShown() then RefreshList() end
    end)

    -- Neue Fenster sind sofort sichtbar; erst verstecken, damit ToggleDungeons es beim ersten Mal öffnet
    window:Hide()
end

-- Schutz gegen Fehler (z. B. Questie oder AtlasLoot fehlt oder ist veraltet): Ein Fehler im Fenster wird
-- abgefangen und einmal im Chat gemeldet, statt als Fehlerfenster aufzugehen - das Dungeonfenster bleibt benutzbar.
local reportedErrors = {}
local function Guarded(fn, what)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not reportedErrors[what] then
            reportedErrors[what] = true
            print(ns.ChatPrefix() .. ": " .. ns.L("DUNGEON_ERROR", what, tostring(err)))
        end
    end
end
RefreshList = Guarded(RefreshList, "Liste")
ns.RefreshDungeonList = function() if window and window:IsShown() then RefreshList() end end
RefreshDetail = Guarded(RefreshDetail, "Quests")
ShowAtlasLoot = Guarded(ShowAtlasLoot, "AtlasLoot")
OpenAtlasLoot = Guarded(OpenAtlasLoot, "AtlasLoot")

-- Fenster bauen; geht dabei etwas schief, wird das halbfertige Fenster verworfen (nächster Versuch beim Öffnen)
local function EnsureWindow()
    if window then return true end
    local ok, err = pcall(CreateWindow)
    if ok and window then return true end
    if window then window:Hide() end
    window = nil
    listButtons, questEntries, pills, zoneHeaders = {}, {}, {}, {}
    print(ns.ChatPrefix() .. ": " .. ns.L("DUNGEON_ERROR", "Fenster", tostring(err)))
    return false
end

-- Nach einem Sprachwechsel: Fenster mit neuen Texten neu aufbauen (beim nächsten Öffnen)
-- Quests der Dungeons haben sich geändert (Questie-Daten nachgeladen): Zwischenspeicher leeren
-- Schnittstelle für andere Forever-Addons (ForeverAlts): zu welchem Dungeon eine Quest gehört, Dungeon öffnen
local apiQuestIndex -- [questID] = Dungeon (beim Neuaufbau der Dungeondaten verworfen)
local function DungeonByQuest(questID)
    if not apiQuestIndex then
        apiQuestIndex = {}
        for _, dungeon in ipairs(ns.ALL_DUNGEON_DATA or {}) do
            for _, quest in ipairs(dungeon.quests or {}) do
                if quest.id then apiQuestIndex[quest.id] = dungeon end
            end
        end
    end
    return questID and apiQuestIndex[questID]
end
ns.DungeonForQuest = DungeonByQuest -- (Questlog-Karten: "Dungeon: …")
do
    local HUB = _G.ForeverHub and _G.ForeverHub.UI
    if HUB and HUB.API then
        HUB.API.ForeverQuests = {
            DungeonOfQuest = function(questID)
                local dungeon = DungeonByQuest(questID)
                return dungeon and Localized(dungeon, "name"), dungeon and dungeon.isRaid == true
            end,
            ShowDungeonOfQuest = function(questID)
                local dungeon = DungeonByQuest(questID)
                if dungeon then ns.ShowDungeon(dungeon) end
            end,
            -- Dungeonfenster öffnen/schließen (z. B. ForeverSkin: Reiter an "Suche nach Gruppe")
            Toggle = function() ns.ToggleDungeons() end,
        }
    end
end

function ns.InvalidateDungeonCaches()
    chainIndex = nil
    apiQuestIndex = nil
    wipe(headerDungeons)
end

function ns.ResetDungeonWindow()
    if not window then return end
    local wasShown = window:IsShown()
    window:UnregisterAllEvents()
    window:Hide()
    window = nil
    listButtons, questEntries, pills, zoneHeaders = {}, {}, {}, {}
    if wasShown then ns.ToggleDungeons() end
end

function ns.HideDungeons()
    if window then window:Hide() end
end
function ns.ToggleDungeons()
    if not EnsureWindow() then return end
    window:SetShown(not window:IsShown())
end

-- Dungeonfenster im Reiter "Questlog" öffnen (Knopf "Log" im Tracker); ist er schon offen, schließen
function ns.ToggleQuestLogTab()
    if not EnsureWindow() then return end
    if window:IsShown() and logTabActive then
        window:Hide()
        return
    end
    logTabActive, levelTabActive, raidTabActive = true, false, false
    RefreshLogQuests()
    selectedDungeon = logZoneOrder[1] -- (erstes Gebiet des Questlogs)
    if window.UpdateTabs then window.UpdateTabs() end
    if searchBox and searchBox:GetText() ~= "" then searchBox:SetText("") end
    questScroll:SetVerticalScroll(0)
    if window:IsShown() then
        RefreshList()
        RefreshDetail()
    else
        window:Show()
    end
end

-- Dungeonfenster öffnen und einen bestimmten Dungeon auswählen
function ns.ShowDungeon(dungeon)
    if not EnsureWindow() then return end
    selectedDungeon = dungeon
    -- Passenden Reiter wählen: Schlachtzüge bzw. "Alle Dungeons", wenn der Dungeon im aktuellen Reiter fehlt
    local isRaid = dungeon and dungeon.isRaid == true
    if logTabActive or raidTabActive ~= isRaid or (levelTabActive and not IsDungeonInMyRange(dungeon)) then
        raidTabActive = isRaid
        levelTabActive = false
        logTabActive = false
        if window.UpdateTabs then window.UpdateTabs() end
    end
    if searchBox and searchBox:GetText() ~= "" then searchBox:SetText("") end
    questScroll:SetVerticalScroll(0)
    if window:IsShown() then
        RefreshList()
        RefreshDetail()
    else
        window:Show()
    end
end

---------------------------------------------------------------------------
-- Hinweis beim Betreten eines Dungeons: wie viele Quests man dabeihat und wie viele noch fehlen
---------------------------------------------------------------------------

local HINT_DURATION = 15 -- Sekunden, bis der Hinweis von selbst verschwindet
local hintFrame
local lastHintInstance

-- Name vereinfachen: Kleinbuchstaben, ohne Klammerzusatz und ohne Artikel am Anfang
local function SimplifyName(name)
    name = (name or ""):lower():gsub("%s*%b()", ""):gsub("^der ", ""):gsub("^die ", ""):gsub("^das ", ""):gsub("^the ", "")
    return strtrim(name)
end

-- Dungeon in den Daten zur aktuellen Instanz: zuerst über den Namen, dann über die Instanz-ID
local function FindCurrentDungeon(instanceName, instanceID)
    local target = SimplifyName(instanceName)
    if target ~= "" then
        for _, dungeon in ipairs(ns.DUNGEON_DATA) do
            for _, name in ipairs({ dungeon.name, dungeon.nameEN }) do
                local simple = SimplifyName(name)
                if simple ~= "" and (simple == target or target:find(simple, 1, true) == 1 or simple:find(target, 1, true) == 1) then
                    return dungeon
                end
            end
        end
    end
    -- über die Instanz-ID: Questie kennt zu jeder Instanz das Gebiet (instanceIdToAreaId)
    local zoneDB = instanceID and _G.QuestieLoader and _G.QuestieLoader:ImportModule("ZoneDB")
    local areaID = zoneDB and zoneDB.instanceIdToAreaId and zoneDB.instanceIdToAreaId[instanceID]
    if areaID then
        for _, dungeon in ipairs(ns.DUNGEON_DATA) do
            if dungeon.areaID == areaID then return dungeon end
            for _, alt in ipairs(dungeon.altAreas or {}) do
                if alt == areaID then return dungeon end
            end
        end
    end
end

-- Quests des Dungeons mit ID (eigene Fraktion): im Questlog bzw. noch nicht angenommen und schon möglich
local function CountHintQuests(dungeon)
    local inLog, missing, seen = 0, 0, {}
    local level = UnitLevel("player")
    for _, quest in ipairs(dungeon.quests or {}) do
        if quest.id and not seen[quest.id] and IsMyFaction(quest.faction) then
            seen[quest.id] = true
            if C_QuestLog.GetLogIndexForQuestID(quest.id) then
                inLog = inLog + 1
            elseif not C_QuestLog.IsQuestFlaggedCompleted(quest.id) and (not quest.minLevel or level >= quest.minLevel) then
                missing = missing + 1
            end
        end
    end
    return inLog, missing
end

-- Text des Hinweises (eigene Quests, darunter die Gruppe); die Fensterhöhe wächst mit
function ns.RefreshDungeonHint()
    if not hintFrame or not hintFrame.dungeon then return end
    local dungeon = hintFrame.dungeon
    local text = ns.L("HINT_TEXT", Localized(dungeon, "name"), hintFrame.inLog or 0, hintFrame.missing or 0)
    local group = GroupHintText(dungeon)
    if group then text = text .. "\n\n" .. group end
    -- mit ForeverAlts: welche Twinks Quests für diesen Dungeon im Log haben
    local HUB = _G.ForeverHub and _G.ForeverHub.UI
    local alts = HUB and HUB.API and HUB.API.ForeverAlts
    if alts and alts.CharsWithQuest then
        local counts, order = {}, {}
        for _, questID in ipairs(DungeonQuestIDs(dungeon)) do
            local ok, list = pcall(alts.CharsWithQuest, questID)
            for _, alt in ipairs(ok and list or {}) do
                local key = alt.coloredName or alt.name or "?"
                if not counts[key] then order[#order + 1] = key end
                counts[key] = (counts[key] or 0) + 1
            end
        end
        if #order > 0 then
            local parts = {}
            for _, key in ipairs(order) do parts[#parts + 1] = key .. " (" .. counts[key] .. ")" end
            text = text .. "\n\n" .. ns.L("HINT_ALTS", table.concat(parts, ", "))
        end
    end
    hintFrame:SetWidth(group and 460 or 360)
    hintFrame.text:SetText(text)
    hintFrame:SetHeight(math.max(128, 50 + hintFrame.text:GetStringHeight() + 48))
end

local function ShowDungeonHint(dungeon, inLog, missing)
    if not hintFrame then
        hintFrame = ns.Style.CreateWindow("ForeverQuestsDungeonHint", 360, 128, ns.L("HINT_TITLE"))
        hintFrame:ClearAllPoints()
        hintFrame:SetPoint("TOP", 0, -140)
        hintFrame.text = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hintFrame.text:SetPoint("TOPLEFT", 16, -50)
        hintFrame.text:SetPoint("RIGHT", -16, 0)
        hintFrame.text:SetJustifyH("LEFT")
        hintFrame.showButton = ns.Style.CreateButton(hintFrame, ns.L("BTN_SHOW"), 84, 24, function()
            hintFrame:Hide()
            if hintFrame.dungeon then ns.ShowDungeon(hintFrame.dungeon) end
        end)
        hintFrame.showButton:SetPoint("BOTTOMRIGHT", -12, 12)
        -- Quests aus dem eigenen Questlog mit der Gruppe teilen (ohne Gruppe bzw. ohne Quests blass)
        hintFrame.shareButton = ns.Style.CreateButton(hintFrame, ns.L("BTN_SHARE_QUESTS"), 110, 24, function()
            if hintFrame.dungeon then ShareAllQuests(hintFrame.dungeon) end
        end, function(tooltip)
            tooltip:AddLine(ns.L("TIP_SHARE_ALL"), 1, 1, 1, true)
            if not IsInGroup() then
                tooltip:AddLine(ns.L("SHARE_NO_GROUP"), 1, 0.3, 0.3, true)
            elseif hintFrame.inLog == 0 then
                tooltip:AddLine(ns.L("SHARE_ALL_NONE"), 1, 0.3, 0.3, true)
            end
        end)
        hintFrame.shareButton:SetPoint("RIGHT", hintFrame.showButton, "LEFT", -6, 0)
    end
    hintFrame.dungeon = dungeon
    hintFrame.inLog = inLog
    hintFrame.missing = missing
    hintFrame.shareButton:SetAlpha((IsInGroup() and inLog > 0) and 1 or 0.45)
    hintFrame.titleText:SetText(ns.L("HINT_TITLE"))
    ns.RefreshDungeonHint()
    -- Stand der Mitspieler erfragen (Antworten füllen den Hinweis nach)
    RequestGroupStatus(dungeon)
    hintFrame:Show()
    -- Nach einer Weile von selbst ausblenden (nur, wenn es noch derselbe Hinweis ist)
    local shownAt = GetTime()
    hintFrame.shownAt = shownAt
    C_Timer.After(HINT_DURATION, function()
        if hintFrame.shownAt == shownAt then hintFrame:Hide() end
    end)
end

local function CheckInstanceHint()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" then
        lastHintInstance = nil -- Instanz verlassen: beim nächsten Betreten wieder hinweisen
        return
    end
    if not ns.db or not ns.db.instanceHint then return end
    local instanceName, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local key = tostring(instanceID or instanceName)
    if key == lastHintInstance then return end
    lastHintInstance = key
    local dungeon = FindCurrentDungeon(instanceName, instanceID)
    if not dungeon then return end
    -- Immer anzeigen, auch wenn man keine Quests dabeihat und keine fehlen
    local inLog, missing = CountHintQuests(dungeon)
    ShowDungeonHint(dungeon, inLog, missing)
end

local hintWatcher = CreateFrame("Frame")
hintWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
hintWatcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
hintWatcher:SetScript("OnEvent", function()
    -- Kurz warten, bis Instanz- und Questdaten nach dem Ladebildschirm bereitstehen
    C_Timer.After(3, CheckInstanceHint)
end)

---------------------------------------------------------------------------
-- /fq check: alle Quest-IDs der Dungeon-Daten beim Spiel prüfen
---------------------------------------------------------------------------

local CHECK_TIMEOUT = 15   -- Sekunden, die auf Antworten vom Server gewartet wird
local CHECK_MAX_LINES = 25 -- höchstens so viele Einzelmeldungen im Chat
local checkRunning = false

-- Vergleich von Questnamen ohne Groß-/Kleinschreibung, Leerzeichen und "…"/"..."
local function NormalizeName(name)
    return (name or ""):lower():gsub("…", "..."):gsub("%s+", "")
end

function ns.CheckQuestIDs()
    local prefix = ns.ChatPrefix() .. ": "
    if checkRunning then
        print(prefix .. ns.L("CHECK_RUNNING"))
        return
    end

    -- Alle Quests mit ID sammeln
    local pending, entries = {}, {}
    for _, dungeon in ipairs(ns.DUNGEON_DATA) do
        for _, quest in ipairs(dungeon.quests or {}) do
            -- Jeder Eintrag wird verglichen, auch wenn dieselbe ID in mehreren Dungeons vorkommt
            if quest.id then
                pending[quest.id] = true
                table.insert(entries, { quest = quest, dungeon = dungeon })
            end
        end
    end
    if #entries == 0 then return end

    checkRunning = true
    print(prefix .. ns.L("CHECK_START", #entries))

    local results = {} -- [questID] = true (bekannt) / false (unbekannt)
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    listener:SetScript("OnEvent", function(_, _, questID, success)
        if pending[questID] then
            results[questID] = success and true or false
        end
    end)

    for _, entry in ipairs(entries) do
        local id = entry.quest.id
        if C_QuestLog.GetTitleForQuestID(id) then
            results[id] = true
        elseif C_QuestLog.RequestLoadQuestByID then
            C_QuestLog.RequestLoadQuestByID(id)
        end
    end

    C_Timer.After(CHECK_TIMEOUT, function()
        listener:UnregisterAllEvents()
        checkRunning = false
        local english = ns.GetLanguage() == "enUS"
        local ok, unknown, renamed, lines = 0, 0, 0, 0
        local function Report(text)
            lines = lines + 1
            if lines <= CHECK_MAX_LINES then print(prefix .. text) end
        end
        for _, entry in ipairs(entries) do
            local quest, id = entry.quest, entry.quest.id
            local title = C_QuestLog.GetTitleForQuestID(id)
            local dungeonName = (english and entry.dungeon.nameEN) or entry.dungeon.name
            if not title and results[id] ~= true then
                unknown = unknown + 1
                Report(ns.L("CHECK_UNKNOWN", id, quest.name or "?", dungeonName))
            else
                -- Name mit dem Namen in der Client-Sprache vergleichen (nur, wenn einer eingetragen ist;
                -- bei Quests mit ID kommt der Name sonst ohnehin aus dem Spiel)
                local expected = GetLocale() == "deDE" and quest.name or (quest.nameEN or quest.name)
                if title and expected and NormalizeName(title) ~= NormalizeName(expected) then
                    renamed = renamed + 1
                    Report(ns.L("CHECK_NAME", id, expected, title))
                else
                    ok = ok + 1
                end
            end
        end
        if lines > CHECK_MAX_LINES then
            print(prefix .. ns.L("CHECK_MORE", lines - CHECK_MAX_LINES))
        end
        print(prefix .. ns.L("CHECK_DONE", ok, unknown, renamed))
    end)
end
