local addonName, ns = ...

---------------------------------------------------------------------------
-- Dungeonfenster nur aus Spiel- und Questie-Daten (TEST: keine selbst gepflegten Daten)
--
-- Woher was kommt:
--   Welche Dungeons es gibt        -> Questie: Dungeon-Tabelle (ZoneDB:GetDungeons); gezeigt werden nur Dungeons,
--                                     zu denen Questie Quests kennt und die keine Schlachtfelder sind
--                                     (Schlachtfeld = überwiegend PvP-Quests, Questie: QuestieDB.IsPvPQuest)
--   Name                           -> Spiel (Gebietsname in der Client-Sprache, C_Map.GetAreaInfo); Rückfall Questie
--   Englischer Name                -> Questie (Dungeon-Tabelle)
--   Eingang (Gebiet, Koordinaten)  -> Questie (Dungeon-Tabelle), Gebietsname aus dem Spiel
--   Stufenbereich                  -> Spiel: Gruppensuche (C_LFGList), sonst aus den Quests: niedrigste
--                                     Mindeststufe bis höchste Queststufe (Questie)
--   Classic / Neu in Forever       -> aus der Gebiets-ID: ab 15000 = neu (Forever-/Season-Gebiete), sonst Classic
--   Fraktion                       -> aus den Quests: alle Allianz = Allianz, alle Horde = Horde, sonst beide
--   Quests des Dungeons            -> Questie: Gebiet der Quest ("zoneOrSort") = Gebiet des Dungeons
--   Mindest-/Queststufe            -> Questie ("requiredLevel", "questLevel")
--   Fraktion/Klasse der Quest      -> Questie ("requiredRaces", "requiredClasses")
--   Questgeber, Ort, Koordinaten   -> Questie ("startedBy" -> NPC/Objekt mit "spawns"); Startgegenstand ebenso
--   Startet im Dungeon             -> Questgeber steht im Dungeon oder Quest startet über einen Gegenstand
--   Vorquest                       -> Questie ("preQuestSingle"/"preQuestGroup")
--   Questname, Beschreibung        -> Spiel (wie bisher), Questies Name nur als Rückfall
--   Belohnungen                    -> Spiel (sobald die Quest im Log ist / vom Server nachgeladen)
-- Questie-Dateien werden nicht verändert; wir lesen nur, während das Spiel läuft (nichts wird kopiert/gespeichert).
---------------------------------------------------------------------------

local band = bit and bit.band

-- Völker als Bitmaske (wie in Questie/WoW): Allianz bzw. Horde
local ALLIANCE_RACES = 1 + 4 + 8 + 64 + 1024           -- Mensch, Zwerg, Nachtelf, Gnom, Draenei
local HORDE_RACES = 2 + 16 + 32 + 128 + 256 + 512      -- Orc, Untoter, Tauren, Troll, Goblin, Blutelf
local NEW_AREA_FROM = 15000                            -- Gebiets-IDs ab hier: neu in Forever (bzw. Season-Inhalte)

ns.questieDungeonReport = nil -- Ergebnis für /fq dungeonquellen

local function Module(name) return _G.QuestieLoader:ImportModule(name) end

local function FactionFromRaces(mask)
    if not band or not mask or mask == 0 then return "Both" end
    local alliance, horde = band(mask, ALLIANCE_RACES) ~= 0, band(mask, HORDE_RACES) ~= 0
    if alliance and not horde then return "Alliance" end
    if horde and not alliance then return "Horde" end
    return "Both"
end

-- Klasse aus der Bitmaske: genau eine Klasse -> Klassen-ID (1 = Krieger, 2 = Paladin …), sonst nil
local function ClassFromMask(mask)
    if not band or not mask or mask == 0 then return nil end
    local found
    for classID = 1, 13 do
        if band(mask, 2 ^ (classID - 1)) ~= 0 then
            if found then return nil end
            found = classID
        end
    end
    return found
end

local function AreaName(areaID)
    if not areaID or not C_Map or not C_Map.GetAreaInfo then return nil end
    local ok, name = pcall(C_Map.GetAreaInfo, areaID)
    return ok and name or nil
end

-- erster Ort einer Spawn-Liste { [Gebiet] = { {x, y}, … } } – bevorzugt außerhalb des Dungeons
local function FirstSpawn(spawns, insideAreas)
    if type(spawns) ~= "table" then return nil end
    local insideZone, insideSpot
    for zone, spots in pairs(spawns) do
        local spot = type(spots) == "table" and spots[1]
        if spot and spot[1] and spot[2] then
            if insideAreas[zone] then
                insideZone, insideSpot = zone, spot
            else
                return zone, spot, false
            end
        end
    end
    if insideZone then return insideZone, insideSpot, true end
end

-- Questgeber aus "startedBy" { NPCs, Objekte, Gegenstände }
local function Giver(db, startedBy, insideAreas)
    if type(startedBy) ~= "table" then return nil end
    for index, kind in ipairs({ "npc", "object" }) do
        local ids = startedBy[index]
        if type(ids) == "table" then
            for _, id in ipairs(ids) do
                local query = kind == "npc" and db.QueryNPCSingle or db.QueryObjectSingle
                local name = query(id, "name")
                if name then
                    local zone, spot, inside = FirstSpawn(query(id, "spawns"), insideAreas)
                    return { giver = name, zoneID = zone, x = spot and math.floor(spot[1] + 0.5),
                        y = spot and math.floor(spot[2] + 0.5), inside = inside }
                end
            end
        end
    end
    local items = startedBy[3]
    if type(items) == "table" and items[1] then
        return { itemID = items[1], inside = true } -- Startgegenstand: fällt in aller Regel im Dungeon
    end
end

-- Questeintrag aus Questies Daten
local function BuildQuest(db, questID, insideAreas)
    local quest = { id = questID, source = "questie" }
    local requiredLevel = db.QueryQuestSingle(questID, "requiredLevel")
    if type(requiredLevel) == "number" and requiredLevel > 0 then quest.minLevel = requiredLevel end
    local questLevel = db.QueryQuestSingle(questID, "questLevel")
    if type(questLevel) == "number" and questLevel > 0 then quest.level = tostring(questLevel) end
    quest.faction = FactionFromRaces(db.QueryQuestSingle(questID, "requiredRaces"))
    quest.classID = ClassFromMask(db.QueryQuestSingle(questID, "requiredClasses"))
    local name = db.QueryQuestSingle(questID, "name")
    if name then quest.name, quest.nameEN = name, name end
    local giver = Giver(db, db.QueryQuestSingle(questID, "startedBy"), insideAreas)
    if giver then
        if giver.itemID then
            quest.giverItemID = giver.itemID
        else
            quest.giver, quest.giverEN = giver.giver, giver.giver
            local zoneName = AreaName(giver.zoneID)
            if zoneName then quest.zone, quest.zoneEN = zoneName, zoneName end
            quest.x, quest.y = giver.x, giver.y
        end
        quest.startsInside = giver.inside or nil
    end
    for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
        local list = db.QueryQuestSingle(questID, key)
        if type(list) == "table" and list[1] then
            quest.prequestID = list[1]
            break
        end
    end
    return quest
end

-- Stufenbereich aus der Gruppensuche des Spiels (Eintrag, dessen Name den Dungeonnamen enthält)
local function Simple(name)
    if not name then return nil end
    name = name:lower():gsub("%b()", "")
    for _, article in ipairs({ "die ", "der ", "das ", "the " }) do
        if name:sub(1, #article) == article then name = name:sub(#article + 1) end
    end
    return (name:gsub("[%s%p]", ""))
end

local lfgActivities
local function LFGLevels(names)
    if lfgActivities == nil then
        lfgActivities = {}
        if C_LFGList and C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableActivities
            and C_LFGList.GetActivityInfoTable then
            for _, categoryID in ipairs(C_LFGList.GetAvailableCategories() or {}) do
                for _, activityID in ipairs(C_LFGList.GetAvailableActivities(categoryID) or {}) do
                    local info = C_LFGList.GetActivityInfoTable(activityID)
                    if info then lfgActivities[#lfgActivities + 1] = info end
                end
            end
        end
    end
    for _, info in ipairs(lfgActivities) do
        local full = Simple(info.fullName or info.shortName)
        for _, name in ipairs(names) do
            local simple = Simple(name)
            if full and simple and simple ~= "" and full:find(simple, 1, true) then
                local minLevel = info.minLevelSuggestion or info.minLevel
                local maxLevel = info.maxLevelSuggestion or info.maxLevel
                if minLevel and minLevel > 0 and maxLevel and maxLevel >= minLevel then
                    return minLevel .. "-" .. maxLevel
                end
            end
        end
    end
end

-- Hauptlauf (in einem Faden über mehrere Bilder): Dungeons und Quests sammeln, Fenster neu aufbauen
local function Run()
    local db, zoneDB = Module("QuestieDB"), Module("ZoneDB")
    local corrections = Module("QuestieCorrections")
    local pointers = db and db.QuestPointers
    local questieDungeons = zoneDB and zoneDB.GetDungeons and zoneDB:GetDungeons()
    if not (db and db.QueryQuestSingle and type(pointers) == "table" and type(questieDungeons) == "table") then return end
    local hidden = corrections and corrections.hiddenQuests or {}

    -- Gebiet -> Dungeon-Gebiet (Hauptgebiet und seine Nebengebiete, z. B. Flügel)
    local mainOf = {}
    for areaID, entry in pairs(questieDungeons) do
        mainOf[areaID] = areaID
        for _, alt in ipairs(entry[2] or {}) do mainOf[alt] = areaID end
    end

    -- 1. Quests den Dungeons zuordnen
    local questsOf, count = {}, 0
    for questID in pairs(pointers) do
        if not hidden[questID] then
            local zone = db.QueryQuestSingle(questID, "zoneOrSort")
            if type(zone) == "number" and zone > 0 then
                local main = mainOf[zone] or mainOf[(zoneDB.GetParentZoneId and zoneDB:GetParentZoneId(zone)) or -1]
                if main then
                    questsOf[main] = questsOf[main] or {}
                    table.insert(questsOf[main], questID)
                end
            end
        end
        count = count + 1
        if count % 250 == 0 then coroutine.yield() end
    end

    -- 2. Dungeons bauen
    local result, report = {}, {}
    for areaID, ids in pairs(questsOf) do
        local entry = questieDungeons[areaID]
        local pvp = 0
        if db.IsPvPQuest then
            for _, questID in ipairs(ids) do if db.IsPvPQuest(questID) then pvp = pvp + 1 end end
        end
        if pvp * 2 < #ids then -- überwiegend PvP-Quests = Schlachtfeld: weglassen
            local insideAreas = { [areaID] = true }
            for _, alt in ipairs(entry[2] or {}) do insideAreas[alt] = true end
            local quests, minLevel, maxLevel, horde, alliance = {}, nil, nil, false, false
            for n, questID in ipairs(ids) do
                local quest = BuildQuest(db, questID, insideAreas)
                quests[#quests + 1] = quest
                if quest.minLevel then minLevel = math.min(minLevel or 999, quest.minLevel) end
                local level = tonumber(quest.level)
                if level then maxLevel = math.max(maxLevel or 0, level) end
                if quest.faction == "Horde" then horde = true
                elseif quest.faction == "Alliance" then alliance = true
                else horde, alliance = true, true end
                if n % 20 == 0 then coroutine.yield() end
            end
            table.sort(quests, function(a, b)
                local la, lb = a.minLevel or 99, b.minLevel or 99
                if la ~= lb then return la < lb end
                return a.id < b.id
            end)
            local nameEN = entry[1]
            local name = (zoneDB.GetLocalizedDungeonName and zoneDB:GetLocalizedDungeonName(areaID)) or AreaName(areaID) or nameEN
            local location = type(entry[4]) == "table" and entry[4][1]
            local levels = LFGLevels({ name, nameEN })
            local levelSource = "lfg"
            if not levels and minLevel then
                levels = minLevel .. "-" .. math.max(maxLevel or minLevel, minLevel)
                levelSource = "quests"
            end
            local dungeon = {
                name = name, nameEN = nameEN, levels = levels,
                zone = location and AreaName(location[1]), zoneEN = location and AreaName(location[1]),
                entranceX = location and location[2], entranceY = location and location[3],
                type = areaID >= NEW_AREA_FROM and "Neu in Forever" or "Classic",
                faction = (horde and not alliance) and "Horde" or (alliance and not horde) and "Alliance" or "Both",
                quests = quests, areaID = areaID,
            }
            result[#result + 1] = dungeon
            report[dungeon] = { area = areaID, quests = #quests, levelSource = levels and levelSource or "none" }
        end
    end
    table.sort(result, function(a, b)
        local la = tonumber((a.levels or ""):match("%d+")) or 99
        local lb = tonumber((b.levels or ""):match("%d+")) or 99
        if la ~= lb then return la < lb end
        return (a.name or "") < (b.name or "")
    end)

    -- 3. Liste des Dungeonfensters ersetzen (dieselbe Tabelle, die Dungeons.lua als Gesamtliste hält)
    local all = ns.ALL_DUNGEON_DATA or ns.DUNGEON_DATA
    wipe(all)
    for _, dungeon in ipairs(result) do all[#all + 1] = dungeon end
    ns.questieDungeonReport = { dungeons = all, report = report }

    if ns.ApplyBetaFilter then ns.ApplyBetaFilter() end
    if ns.InvalidateDungeonCaches then ns.InvalidateDungeonCaches() end
    if ns.ResetDungeonWindow then ns.ResetDungeonWindow() end
end

local function Start()
    local co = coroutine.create(Run)
    local function Step()
        local ok, err = coroutine.resume(co)
        if not ok then
            print(ns.ChatPrefix() .. ": Questie-Dungeondaten - " .. tostring(err))
        elseif coroutine.status(co) ~= "dead" then
            C_Timer.After(0, Step)
        end
    end
    Step()
end

-- Start, sobald Questie fertig geladen ist (ohne Questie bleibt die Liste leer)
local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_LOGIN")
starter:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local questie = _G.Questie
    if type(questie) ~= "table" or not questie.API or type(_G.QuestieLoader) ~= "table" then return end
    if questie.API.isReady then
        C_Timer.After(2, Start)
    elseif questie.API.RegisterOnReady then
        pcall(questie.API.RegisterOnReady, function() C_Timer.After(2, Start) end)
    end
end)

-- /fq dungeonquellen: je Dungeon, was gefunden wurde
function ns.DebugDungeonSources()
    local prefix = ns.ChatPrefix() .. ": "
    local data = ns.questieDungeonReport
    if not data then
        print(prefix .. ns.L("DNGSRC_NONE"))
        return
    end
    print(prefix .. ns.L("DNGSRC_COUNT", #data.dungeons))
    for _, dungeon in ipairs(data.dungeons) do
        local r = data.report[dungeon] or {}
        print(prefix .. ns.L("DNGSRC_LINE", dungeon.name or "?", r.quests or 0, dungeon.levels or "?",
            ns.L("DNGSRC_LVL_" .. (r.levelSource or "none"):upper()), dungeon.type or "?", r.area or 0))
    end
end
