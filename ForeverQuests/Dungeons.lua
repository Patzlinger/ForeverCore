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
local levelTabActive = false -- Reiter "Mein Levelbereich"
local LEVEL_EARLY = 2        -- Dungeons schon so viele Level vor dem Mindestlevel zeigen
local QUEST_LEVEL_RANGE = 5  -- Quests höchstens so viele Level über/unter dem eigenen Level
local refreshPending = false

-- Beta-Modus: in der Beta geht es nur bis Stufe 30 – Dungeons und Quests darüber werden ausgeblendet.
-- Die Daten aus der Excel-Datei bleiben vollständig (ALL_DUNGEONS); ns.DUNGEON_DATA ist die angezeigte Auswahl.
local BETA_MAX_LEVEL = 30
local ALL_DUNGEONS = ns.DUNGEON_DATA

local function FirstNumber(text)
    return tonumber(tostring(text or ""):match("%d+"))
end

function ns.ApplyBetaFilter()
    selectedDungeon = nil -- die Auswahl zeigt sonst auf einen Dungeon der alten Liste
    if not (ns.db and ns.db.betaDungeons) then
        ns.DUNGEON_DATA = ALL_DUNGEONS
        return
    end
    local list = {}
    for _, dungeon in ipairs(ALL_DUNGEONS) do
        local minLevel = FirstNumber(dungeon.levels)
        if not minLevel or minLevel <= BETA_MAX_LEVEL then
            -- Kopie des Dungeons mit nur den Quests bis Stufe 30 (Mindeststufe bzw. Questlevel aus der Excel-Datei)
            local copy = {}
            for key, value in pairs(dungeon) do copy[key] = value end
            copy.quests = {}
            for _, quest in ipairs(dungeon.quests or {}) do
                local level = quest.minLevel or FirstNumber(quest.level)
                if not level or level <= BETA_MAX_LEVEL then table.insert(copy.quests, quest) end
            end
            table.insert(list, copy)
        end
    end
    ns.DUNGEON_DATA = list
end

local LIST_WIDTH = 290
local LIST_ROW_HEIGHT = 44
local HEADER_HEIGHT = 40
local FOOTER_HEIGHT = 40

-- Farben im flachen, dunklen Stil
local COLOR = {
    background = { 0.07, 0.07, 0.09, 0.97 },
    header = { 0.11, 0.11, 0.14, 1 },
    panel = { 0.10, 0.10, 0.12, 0.95 },
    border = { 0.22, 0.22, 0.26, 1 },
    card = { 0.13, 0.13, 0.16, 1 },
    cardHover = { 0.18, 0.18, 0.22, 1 },
    accent = { 1, 0.82, 0 },
}
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
local unknownQuests = {}     -- Quests, die der Server nicht kennt (oder die nach mehreren Anfragen nicht kamen)
local REQUEST_RETRY_SECONDS = 5
local REQUEST_MAX_TRIES = 3

-- Questdaten beim Server anfordern. Kommt keine Antwort, wird es nach ein paar Sekunden erneut versucht;
-- nach mehreren erfolglosen Versuchen gilt die Quest als unbekannt.
local function RequestQuestData(questID)
    if unknownQuests[questID] or not C_QuestLog.RequestLoadQuestByID then return end
    local last = requestedQuests[questID]
    if last and GetTime() - last < REQUEST_RETRY_SECONDS then return end
    local tries = requestTries[questID] or 0
    if tries >= REQUEST_MAX_TRIES then
        unknownQuests[questID] = true
        return
    end
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

local function GetQuestTooltipText(questID)
    if not questID then return nil end
    if questTextCache[questID] then return questTextCache[questID] end
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
    if questID and unknownQuests[questID] then return ns.L("QUEST_UNKNOWN", questID) end
    return ns.L("QUEST_FALLBACK", questID or 0)
end

-- Anzeigename: aus dem Spiel, sonst aus der Excel-Datei, sonst Platzhalter.
-- Kennt das Spiel die Quest-ID nicht, steht "(Not available in Beta)" dahinter.
local function QuestName(quest)
    local title = GetGameQuestTitle(quest.id)
    if title then return title end
    local name = Localized(quest, "name")
    if name and quest.id and unknownQuests[quest.id] then
        return name .. " " .. ns.L("NOT_IN_BETA")
    end
    return name or QuestIDFallback(quest.id)
end

-- Questlevel: aus der Excel-Datei (nur bei Quests ohne ID eingetragen) oder aus dem Spiel
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

-- Questgeber: Name aus der Excel-Datei oder - wenn die Quest von einem Gegenstand startet -
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

-- Reiter "Mein Levelbereich": Dungeon passt, wenn das eigene Level im Levelbereich liegt
-- (ein paar Level vorher zählt schon mit)
local function IsDungeonInMyRange(dungeon)
    local minLevel, maxLevel = (dungeon.levels or ""):match("(%d+)%D+(%d+)")
    minLevel, maxLevel = tonumber(minLevel), tonumber(maxLevel)
    if not minLevel then return true end
    local level = UnitLevel("player")
    return level >= minLevel - LEVEL_EARLY and level <= maxLevel
end

-- Quest passt, wenn die erforderliche Stufe erreicht ist und das Questlevel nah am eigenen Level liegt
local function IsQuestInMyRange(quest)
    local level = UnitLevel("player")
    if quest.minLevel and level < quest.minLevel then return false end
    local questLevel = QuestLevel(quest)
    if questLevel and math.abs(questLevel - level) > QUEST_LEVEL_RANGE then return false end
    return true
end

-- Filter ohne "Abgeschlossene ausblenden" (Reiter Levelbereich und Fraktion)
local function PassesBaseFilters(quest)
    if levelTabActive and not IsQuestInMyRange(quest) then return false end
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

-- Zeile für die Quest-Karte, z. B. "Questkette (2/3): A › B › C" (nil, wenn die Quest allein steht).
-- Erledigte Teile grün, die aktuelle Quest weiß, offene Teile grau.
local function ChainText(quest)
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

-- Tooltip des Knopfs "Gruppe": jede Quest des Dungeons, die jemand in der Gruppe hat, und wem sie fehlt
local function FillGroupTooltip(tooltip, dungeon)
    tooltip:AddLine(ns.L("TIP_GROUP_TITLE"), 1, 0.82, 0)
    local any, seen = false, {}
    for _, quest in ipairs(dungeon and dungeon.quests or {}) do
        if quest.id and not seen[quest.id] and PassesBaseFilters(quest) then
            seen[quest.id] = true
            local have, missing = GetGroupQuestStatus(quest.id, true)
            if #have > 0 then
                any = true
                local right
                if #missing == 0 then
                    right = "|cff33ff99" .. ns.L("GROUP_ALL") .. "|r"
                else
                    right = "|cffff7070" .. ns.L("GROUP_MISSING") .. " " .. table.concat(missing, ", ") .. "|r"
                end
                tooltip:AddDoubleLine(QuestName(quest), right, 1, 1, 1)
            end
        end
    end
    if not any then tooltip:AddLine(ns.L("TIP_GROUP_NONE"), 0.7, 0.7, 0.7, true) end
end

-- Levelbereich eingefärbt nach Schwierigkeit für den eigenen Charakter (anhand des Mindestlevels)
local function ColoredLevels(levels)
    if not levels then return "" end
    local minLevel = tonumber(levels:match("%d+"))
    if minLevel and GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(minLevel)
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
    if QuestMapQuestOptions_ShareQuest then
        QuestMapQuestOptions_ShareQuest(quest.id)
    else
        C_QuestLog.SetSelectedQuest(quest.id)
        QuestLogPushQuest()
    end
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
-- Dungeon-Name (wie in der Excel-Datei) -> Seite in AtlasLoot; mehrere Seiten = Auswahl der Flügel
local ATLASLOOT_PAGES = {
    ["Ragefireabgrund"] = "Ragefire",
    ["Die Halle der Thanen"] = "TheHallOfThanes",
    ["Die Höhlen des Wehklagens"] = "WailingCaverns",
    ["Die Ruinen von Lordaeron"] = "TheRuinsOfLordaeron",
    ["Die Todesminen"] = "TheDeadmines",
    ["Burg Shadowfang"] = "ShadowfangKeep",
    ["Das Verlies"] = "TheStockade",
    ["Blackfathom-Tiefe"] = "BlackfathomDeeps",
    ["Ausgrabungsstätte: Sumpfland"] = "ExcavationSiteWetlands",
    ["Das Scharlachrote Kloster"] = {
        { "ScarletMonasteryGraveyard", "WING_GRAVEYARD" }, { "ScarletMonasteryLibrary", "WING_LIBRARY" },
        { "ScarletMonasteryArmory", "WING_ARMORY" }, { "ScarletMonasteryCathedral", "WING_CATHEDRAL" },
    },
    ["Dalaran (City of Dalaran)"] = "TheCityOfDalaran",
    ["Gnomeregan"] = "Gnomeregan",
    ["Der Kral von Razorfen"] = "RazorfenKraul",
    ["The Drowned City"] = "TheDrownedCity",
    ["Die Hügel von Razorfen"] = "RazorfenDowns",
    ["Feste Krol'dok"] = "KroldokStronghold",
    ["Uldaman"] = "Uldaman",
    ["Zul'Farrak"] = "Zul'Farrak",
    ["Maraudon"] = "Maraudon",
    ["Das Gefängnis von Alcaz"] = "AlcazPrison",
    ["Der Tempel von Atal'Hakkar"] = "TheTempleOfAtal'Hakkar",
    ["Blackrocktiefen"] = "BlackrockDepths",
    ["Untere Blackrockspitze"] = "LowerBlackrockSpire",
    ["Düsterbruch (Ost, Nord, West)"] = {
        { "DireMaulEast", "WING_EAST" }, { "DireMaulWest", "WING_WEST" }, { "DireMaulNorth", "WING_NORTH" },
    },
    ["Die Schwarzschlundfeste"] = "BlackmawHold",
    ["Obere Blackrockspitze"] = "UpperBlackrockSpire",
    ["Die Terrasse des Formers"] = "ShapersTerrace",
    ["Scholomance"] = "Scholomance",
    ["Stratholme (Live und Dead)"] = "Stratholme",
}

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

local function ShowAtlasLoot(owner, dungeon)
    local pages = dungeon and ATLASLOOT_PAGES[dungeon.name]
    if type(pages) == "string" then
        OpenAtlasLoot(pages)
    elseif type(pages) == "table" then
        -- Dungeon mit mehreren Flügeln: Flügel auswählen
        local items = {}
        for _, wing in ipairs(pages) do
            table.insert(items, { text = ns.L(wing[2]), onClick = function() OpenAtlasLoot(wing[1]) end })
        end
        ns.Style.ShowMenu(owner, items)
    end
end

---------------------------------------------------------------------------
-- Belohnungen (Gegenstände anhand ihrer Item-ID)
---------------------------------------------------------------------------

local REWARD_ROW_HEIGHT = 26
local RequestRefresh, RefreshDetail
local pendingItems = {}
-- Welche Quests ihre Belohnungen gerade ausgeklappt zeigen (standardmäßig eingeklappt)
local rewardsExpanded = {}

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
local function GetRewardInfo(itemID)
    local name, link, quality = C_Item.GetItemInfo(itemID)
    local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    if not name and not pendingItems[itemID] and Item and Item.CreateFromItemID then
        pendingItems[itemID] = true
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            pendingItems[itemID] = nil
            RequestRefresh()
        end)
    end
    return name, link, quality, icon
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

    -- Maus drüber: Gegenstands-Tooltip; Shift-Klick: im Chat verlinken
    button:SetScript("OnEnter", function(self)
        ns.Style.GetTooltip():SetOwner(self, "ANCHOR_RIGHT")
        ns.Style.GetTooltip():SetItemByID(self.itemID)
        ns.Style.GetTooltip():Show()
    end)
    button:SetScript("OnLeave", function() ns.Style.GetTooltip():Hide() end)
    button:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick() then
            HandleModifiedItemClick(self.link)
        end
    end)
    return button
end

-- Zeigt die Belohnungen einer Quest: eingeklappt nur die Zeile "Belohnungen (3)",
-- ausgeklappt zusätzlich die Gegenstände in zwei Spalten. Gibt die benötigte Höhe zurück.
local function LayoutRewards(entry, quest, width)
    local rewards = quest.rewards
    entry.rewardButtons = entry.rewardButtons or {}
    if not rewards or #rewards == 0 then
        entry.rewardToggle:Hide()
        for _, button in ipairs(entry.rewardButtons) do button:Hide() end
        return 0
    end

    local expanded = rewardsExpanded[quest] == true
    entry.rewardToggle.text:SetText(ns.L("REWARDS_COUNT", #rewards))
    entry.rewardToggle.arrow:SetRotation(expanded and -math.pi / 2 or 0)
    entry.rewardToggle:Show()
    if not expanded then
        for _, button in ipairs(entry.rewardButtons) do button:Hide() end
        return 19 -- nur die Zeile zum Ausklappen
    end

    local columnWidth = math.floor((width - 6) / 2)
    for i, itemID in ipairs(rewards) do
        local button = entry.rewardButtons[i]
        if not button then
            button = CreateRewardButton(entry.rewardArea)
            entry.rewardButtons[i] = button
        end
        local name, link, quality, icon = GetRewardInfo(itemID)
        button.itemID = itemID
        button.link = link
        button.icon:SetTexture(icon or 134400) -- 134400 = Fragezeichen-Symbol
        local r, g, b = GetQualityColor(quality)
        button.border:SetColorTexture(r, g, b, 1)
        button.name:SetText(name or ns.L("ITEM_LOADING", itemID))
        button.name:SetTextColor(r, g, b)

        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", entry.rewardArea, "TOPLEFT", column * (columnWidth + 6), -row * REWARD_ROW_HEIGHT)
        button:SetWidth(columnWidth)
        button:Show()
    end
    for i = #rewards + 1, #entry.rewardButtons do
        entry.rewardButtons[i]:Hide()
    end
    local rows = math.ceil(#rewards / 2)
    entry.rewardArea:SetSize(width, rows * REWARD_ROW_HEIGHT)
    return rows * REWARD_ROW_HEIGHT + 22 -- inkl. Zeile "Belohnungen"
end

---------------------------------------------------------------------------
-- Rechte Seite: Quests des gewählten Dungeons
---------------------------------------------------------------------------

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
        -- Klick auf die Karte klappt die Belohnungen auf bzw. zu; Shift-Klick verlinkt die Quest im Chat
        entry:SetScript("OnClick", function(self)
            local quest = self.quest
            if quest and IsModifiedClick("CHATLINK") then
                LinkQuestInChat(quest)
                return
            end
            if not quest or not quest.rewards or #quest.rewards == 0 then return end
            rewardsExpanded[quest] = not rewardsExpanded[quest]
            RefreshDetail()
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
            rewardsExpanded[quest] = not rewardsExpanded[quest]
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

RefreshDetail = function()
    refreshPending = false
    if not window or not window:IsShown() then return end

    local dungeon = selectedDungeon
    atlasButton:SetShown(dungeon ~= nil and ATLASLOOT_PAGES[dungeon.name] ~= nil and IsAtlasLootAvailable())
    -- "Alle teilen" (ohne Gruppe blass) und "Gruppe" (nur in einer Gruppe)
    shareAllButton:SetShown(#GetQuestsInLog(dungeon) > 0)
    shareAllButton:SetAlpha(IsInGroup() and 1 or 0.45)
    groupButton:SetShown(dungeon ~= nil and IsInGroup())
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
    if not dungeon then
        detailTitle:SetText(ns.L(levelTabActive and "NO_DUNGEON_LEVEL" or "NO_DUNGEON"))
        detailExtra:SetText("")
        LayoutPills({})
        detailEmpty:Hide()
        return
    end

    -- Kopfbereich: Titel und Plaketten
    detailTitle:SetText(Localized(dungeon, "name"))
    local pillList = {}
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
    for _, quest in ipairs(dungeon.quests or {}) do
        if IsQuestVisible(quest) then
            shown = shown + 1
            local entry = GetQuestEntry(shown)
            entry.quest = quest

            local status = GetQuestStatus(quest.id) or "OPEN"
            local style = STATUS[status]
            entry.stripe:SetColorTexture(style.stripe[1], style.stripe[2], style.stripe[3], 1)
            if status == "DONE" then done = done + 1 end

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
            if quest.giverItemID then
                if quest.zone then table.insert(parts, where) end
            else
                table.insert(parts, (GiverText(quest, true) or "?") .. " |cff888888–|r " .. where)
            end
            -- Hinweis, wenn man die Quest erst im Dungeon bekommt
            if quest.startsInside then table.insert(parts, "|cff4fc3f7" .. ns.L("STARTS_INSIDE") .. "|r") end
            if quest.minLevel then table.insert(parts, "|cff888888" .. ns.L("FROM_LEVEL") .. "|r " .. quest.minLevel) end
            -- Fraktion nur nennen, wenn sie vom Dungeon abweicht

            local className = ClassText(quest)
            if className then table.insert(parts, className) end
            if quest.id then table.insert(parts, "|cff666666ID " .. quest.id .. "|r") end
            local lines = { table.concat(parts, "   ") }
            local extraParts = {}
            -- Questkette (enthält auch die Vorquest); ohne Kette nur die Vorquest
            local chainText = ChainText(quest)
            local prequest = PrequestText(quest)
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
            local hasShare = status == "ACTIVE"
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
            entry.desc:SetText(GetQuestTooltipText(quest.id) or "")

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

            local rewardHeight = LayoutRewards(entry, quest, width - 24)
            local height = math.max(entry.title:GetStringHeight(), 16) + entry.desc:GetStringHeight() + entry.info:GetStringHeight() + 20
                + rewardHeight + giverItemHeight
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", questContent, "TOPLEFT", 0, -y)
            entry:SetSize(width, height)
            entry:Show()
            y = y + height + 4
        end
    end
    questContent:SetHeight(math.max(1, y))

    -- Zusammenfassung bzw. Hinweis, wenn nichts angezeigt wird
    if total == 0 then
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
    C_Timer.After(0.15, RefreshDetail)
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
        if (filter == "" or haystack:find(filter, 1, true)) and (not levelTabActive or IsDungeonInMyRange(dungeon)) then
            table.insert(visible, dungeon)
            if dungeon == selectedDungeon then selectedVisible = true end
        end
    end
    -- Ist der gewählte Dungeon im Levelbereich nicht dabei, den ersten passenden wählen
    if levelTabActive and not selectedVisible then
        selectedDungeon = visible[1]
    end

    local shown = 0
    for _, dungeon in ipairs(visible) do
        do
            shown = shown + 1
            local button = GetListButton(shown)
            button.dungeon = dungeon
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", listContent, "TOPLEFT", 4, -(shown - 1) * LIST_ROW_HEIGHT)
            button:SetWidth(width - 8)

            -- Dungeons der Gegenfraktion grau
            local ownFaction = IsMyFaction(dungeon.faction)
            button.name:SetText(Localized(dungeon, "name"))
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

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() window:Hide() end)

    -- Linkes Feld: Suche und Dungeon-Liste
    local listPanel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    SetFlat(listPanel, COLOR.panel)
    listPanel:SetPoint("TOPLEFT", 12, -(HEADER_HEIGHT + 12))
    listPanel:SetPoint("BOTTOMLEFT", 12, FOOTER_HEIGHT + 4)
    listPanel:SetWidth(LIST_WIDTH)

    searchBox = CreateFrame("EditBox", nil, listPanel, "BackdropTemplate")
    SetFlat(searchBox, { 0.06, 0.06, 0.08, 1 })
    searchBox:SetHeight(28)
    -- Reiter: alle Dungeons / nur der eigene Levelbereich
    local tabWidth = math.floor((LIST_WIDTH - 22) / 2)
    local tabs = {}
    local function UpdateTabs()
        for _, tab in ipairs(tabs) do
            local active = tab.levelTab == levelTabActive
            if active then
                tab:SetBackdropColor(0.30, 0.25, 0.05, 1)
                tab:GetFontString():SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3])
            else
                tab:SetBackdropColor(0.16, 0.16, 0.20, 1)
                tab:GetFontString():SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end
    local function SelectTab(levelTab)
        levelTabActive = levelTab
        UpdateTabs()
        listScroll:SetVerticalScroll(0)
        questScroll:SetVerticalScroll(0)
        RefreshList()
        RefreshDetail()
    end
    local allTab = ns.Style.CreateButton(listPanel, ns.L("TAB_ALL"), tabWidth, 24, function() SelectTab(false) end)
    allTab:SetPoint("TOPLEFT", 8, -8)
    allTab.levelTab = false
    local levelTab = ns.Style.CreateButton(listPanel, ns.L("TAB_MY_LEVEL"), tabWidth, 24, function() SelectTab(true) end,
        function(tooltip) tooltip:AddLine(ns.L("TIP_MY_LEVEL"), 1, 1, 1, true) end)
    levelTab:SetPoint("LEFT", allTab, "RIGHT", 6, 0)
    levelTab.levelTab = true
    tabs = { allTab, levelTab }
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

    -- Hinweis rechts in der Fußleiste
    local linkHint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    linkHint:SetPoint("BOTTOMRIGHT", -26, 16)
    linkHint:SetText(ns.L("LINK_HINT"))


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
    window:SetScript("OnEvent", function(_, event)
        RequestRefresh()
        -- Beim Levelaufstieg kann sich der Levelbereich der Liste ändern
        if event == "PLAYER_LEVEL_UP" and window:IsShown() then RefreshList() end
    end)

    -- Neue Fenster sind sofort sichtbar; erst verstecken, damit ToggleDungeons es beim ersten Mal öffnet
    window:Hide()
end

-- Nach einem Sprachwechsel: Fenster mit neuen Texten neu aufbauen (beim nächsten Öffnen)
function ns.ResetDungeonWindow()
    if not window then return end
    local wasShown = window:IsShown()
    window:UnregisterAllEvents()
    window:Hide()
    window = nil
    listButtons, questEntries, pills = {}, {}, {}
    if wasShown then ns.ToggleDungeons() end
end

function ns.HideDungeons()
    if window then window:Hide() end
end

function ns.ToggleDungeons()
    if not window then CreateWindow() end
    window:SetShown(not window:IsShown())
end

-- Dungeonfenster öffnen und einen bestimmten Dungeon auswählen
function ns.ShowDungeon(dungeon)
    if not window then CreateWindow() end
    selectedDungeon = dungeon
    -- Im Reiter "Mein Levelbereich" wäre der Dungeon evtl. ausgeblendet: dann auf "Alle Dungeons" wechseln
    if levelTabActive and not IsDungeonInMyRange(dungeon) then
        levelTabActive = false
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
-- Instanz-ID (aus GetInstanceInfo) -> Dungeon-Name in den Daten (für die Classic-Dungeons)
local INSTANCE_IDS = {
    [389] = "Ragefireabgrund", [43] = "Die Höhlen des Wehklagens", [36] = "Die Todesminen",
    [33] = "Burg Shadowfang", [48] = "Blackfathom-Tiefe", [34] = "Das Verlies", [90] = "Gnomeregan",
    [47] = "Der Kral von Razorfen", [189] = "Das Scharlachrote Kloster", [129] = "Die Hügel von Razorfen",
    [70] = "Uldaman", [209] = "Zul'Farrak", [349] = "Maraudon", [109] = "Der Tempel von Atal'Hakkar",
    [230] = "Blackrocktiefen", [229] = "Untere Blackrockspitze", [429] = "Düsterbruch (Ost, Nord, West)",
    [289] = "Scholomance", [329] = "Stratholme (Live und Dead)",
}
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
    local dataName = instanceID and INSTANCE_IDS[instanceID]
    if dataName then
        for _, dungeon in ipairs(ns.DUNGEON_DATA) do
            if dungeon.name == dataName then return dungeon end
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
    hintFrame.shareButton:SetAlpha((IsInGroup() and inLog > 0) and 1 or 0.45)
    hintFrame.titleText:SetText(ns.L("HINT_TITLE"))
    hintFrame.text:SetText(ns.L("HINT_TEXT", Localized(dungeon, "name"), inLog, missing))
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
