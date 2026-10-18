local addonName, ns = ...

---------------------------------------------------------------------------
-- Dungeonquests aus Questies Datenbank (Variante A)
--
-- Mit Questie: Die Quests jedes Dungeons kommen aus Questie – vollständig und aktuell. Ohne Questie gilt der
-- eingefrorene Stand in Data\Dungeons.lua (früher aus der Excel-Datei erzeugt, wird nicht mehr gepflegt).
--
-- Woher was kommt:
--   Dungeon-Grunddaten (Name, Stufen, Eingang, Classic/Neu, Fraktion)  -> Data\Dungeons.lua (bleibt, von Hand pflegen)
--   Zuordnung Quest -> Dungeon         -> Questie: Gebiet der Quest ("zoneOrSort") = Gebiet des Dungeons
--   Gebiet des Dungeons                -> aus den Quest-IDs, die schon in Data\Dungeons.lua stehen (häufigstes
--                                         Questie-Gebiet), sonst über den Namen des Gebiets (C_Map.GetAreaInfo)
--   Mindeststufe, Queststufe           -> Questie ("requiredLevel", "questLevel")
--   Fraktion                           -> Questie ("requiredRaces": Völker der Allianz/Horde)
--   Klasse                             -> Questie ("requiredClasses")
--   Questgeber, Ort, Koordinaten       -> Questie ("startedBy" -> NPC/Objekt mit "spawns"); Startgegenstand ("startedBy" Gegenstand)
--   Startet im Dungeon                 -> Questgeber steht im Dungeon oder Quest startet über einen Gegenstand
--   Vorquest                           -> Questie ("preQuestSingle" bzw. "preQuestGroup")
--   Questname                          -> wie bisher aus dem Spiel; nur als Rückfall Questies Name
--   Belohnungen (Gegenstände)          -> Questie kennt sie nicht: aus Data\Dungeons.lua, falls dort eingetragen;
--                                         sonst zeigt das Spiel sie, sobald die Quest im Log ist
-- Quests aus Data\Dungeons.lua, die Questie dem Dungeon nicht zuordnet, bleiben in der Liste.
-- Questie-Dateien werden nicht verändert; wir lesen nur, während das Spiel läuft (nichts wird kopiert/gespeichert).
---------------------------------------------------------------------------

local band = bit and bit.band

-- Völker als Bitmaske (wie in Questie/WoW): Allianz bzw. Horde
local ALLIANCE_RACES = 1 + 4 + 8 + 64 + 1024           -- Mensch, Zwerg, Nachtelf, Gnom, Draenei
local HORDE_RACES = 2 + 16 + 32 + 128 + 256 + 512      -- Orc, Untoter, Tauren, Troll, Goblin, Blutelf

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
            if found then return nil end -- mehrere Klassen: keine Klassenquest im engeren Sinn
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
local function FirstSpawn(spawns, dungeonAreas)
    if type(spawns) ~= "table" then return nil end
    local insideZone, insideSpot
    for zone, spots in pairs(spawns) do
        local spot = type(spots) == "table" and spots[1]
        if spot and spot[1] and spot[2] then
            if dungeonAreas[zone] then
                insideZone, insideSpot = zone, spot
            else
                return zone, spot, false
            end
        end
    end
    if insideZone then return insideZone, insideSpot, true end
end

-- Questgeber aus "startedBy" { NPCs, Objekte, Gegenstände }
local function Giver(db, startedBy, dungeonAreas)
    if type(startedBy) ~= "table" then return nil end
    for index, kind in ipairs({ "npc", "object" }) do
        local ids = startedBy[index]
        if type(ids) == "table" then
            for _, id in ipairs(ids) do
                local query = kind == "npc" and db.QueryNPCSingle or db.QueryObjectSingle
                local name = query(id, "name")
                if name then
                    local zone, spot, inside = FirstSpawn(query(id, "spawns"), dungeonAreas)
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

-- Questie-Gebiet einer Quest (Untergebiete zum Hauptgebiet zusammengefasst)
local function QuestArea(db, zoneDB, questID)
    local zone = db.QueryQuestSingle(questID, "zoneOrSort")
    if type(zone) ~= "number" or zone <= 0 then return nil end
    return (zoneDB.GetParentZoneId and zoneDB:GetParentZoneId(zone)) or zone
end

-- Gebiet eines Dungeons: häufigstes Questie-Gebiet seiner bekannten Quests
local function DungeonAreaFromQuests(db, zoneDB, dungeon)
    local counts, best, bestCount = {}, nil, 0
    for _, quest in ipairs(dungeon.quests or {}) do
        local area = quest.id and QuestArea(db, zoneDB, quest.id)
        if area then
            counts[area] = (counts[area] or 0) + 1
            local isDungeon = zoneDB.IsDungeonZone and zoneDB.IsDungeonZone(area)
            local score = counts[area] + (isDungeon and 100 or 0)
            if score > bestCount then best, bestCount = area, score end
        end
    end
    return best
end

-- Neuen Questeintrag aus Questies Daten bauen (alte Angaben, z. B. Belohnungen, bleiben, wo Questie nichts hat)
local function BuildQuest(db, questID, old, dungeonAreas)
    local quest = {}
    if old then for key, value in pairs(old) do quest[key] = value end end
    quest.id = questID
    quest.source = "questie"
    local requiredLevel = db.QueryQuestSingle(questID, "requiredLevel")
    if type(requiredLevel) == "number" and requiredLevel > 0 then quest.minLevel = requiredLevel end
    local questLevel = db.QueryQuestSingle(questID, "questLevel")
    if type(questLevel) == "number" and questLevel > 0 then quest.level = tostring(questLevel) end
    quest.faction = FactionFromRaces(db.QueryQuestSingle(questID, "requiredRaces"))
    quest.classID = ClassFromMask(db.QueryQuestSingle(questID, "requiredClasses")) or quest.classID
    local name = db.QueryQuestSingle(questID, "name")
    if name then
        quest.name = quest.name or name
        quest.nameEN = quest.nameEN or name
    end
    local giver = Giver(db, db.QueryQuestSingle(questID, "startedBy"), dungeonAreas)
    if giver then
        if giver.itemID then
            quest.giverItemID = giver.itemID
        else
            quest.giver, quest.giverEN = giver.giver, giver.giver
            quest.giverItemID = nil
            local zoneName = AreaName(giver.zoneID)
            if zoneName then quest.zone, quest.zoneEN = zoneName, zoneName end
            if giver.x and giver.y then quest.x, quest.y = giver.x, giver.y end
        end
        quest.startsInside = giver.inside or nil
    end
    for _, key in ipairs({ "preQuestSingle", "preQuestGroup" }) do
        local list = db.QueryQuestSingle(questID, key)
        if type(list) == "table" and list[1] then
            quest.prequestID = list[1]
            quest.prequest = nil
            break
        end
    end
    return quest
end

-- Hauptlauf: in einem Faden über mehrere Bilder (die Questliste ist groß), danach Fenster neu aufbauen
local function Run()
    local db, zoneDB = Module("QuestieDB"), Module("ZoneDB")
    local corrections = Module("QuestieCorrections")
    local pointers = db and db.QuestPointers
    if not (db and db.QueryQuestSingle and zoneDB and type(pointers) == "table") then return end
    local hidden = corrections and corrections.hiddenQuests or {}
    local dungeons = ns.ALL_DUNGEON_DATA or ns.DUNGEON_DATA
    if not dungeons then return end

    -- 1. Gebiet je Dungeon. Teilen sich mehrere Dungeons ein Gebiet (z. B. die Flügel des Scharlachroten Klosters),
    --    lässt sich nicht sagen, welche Quest zu welchem Flügel gehört: dort bleibt der alte Stand.
    local byArea, areaOf, report, shared = {}, {}, {}, {}
    for _, dungeon in ipairs(dungeons) do
        local area = DungeonAreaFromQuests(db, zoneDB, dungeon)
        if area then
            if byArea[area] then shared[area] = true end
            byArea[area] = dungeon
            areaOf[dungeon] = area
            report[dungeon] = { area = area, how = "ids" }
        end
    end
    for area in pairs(shared) do
        byArea[area] = nil
        for dungeon, a in pairs(areaOf) do
            if a == area then report[dungeon].how = "shared" end
        end
    end

    -- 2. alle Quests durchgehen: Quests der Dungeon-Gebiete sammeln; Dungeon-Gebiete ohne Treffer merken (Namensvergleich)
    local found, dungeonAreasSeen, count = {}, {}, 0
    for questID in pairs(pointers) do
        if not hidden[questID] then
            local area = QuestArea(db, zoneDB, questID)
            if area then
                if byArea[area] then
                    found[area] = found[area] or {}
                    found[area][#found[area] + 1] = questID
                elseif zoneDB.IsDungeonZone and zoneDB.IsDungeonZone(area) then
                    dungeonAreasSeen[area] = dungeonAreasSeen[area] or {}
                    table.insert(dungeonAreasSeen[area], questID)
                end
            end
        end
        count = count + 1
        if count % 250 == 0 then coroutine.yield() end
    end

    -- 3. Dungeons ohne bekannte Quest-IDs (z. B. neu in Forever): über den Gebietsnamen zuordnen.
    --    Tolerant verglichen: ohne Artikel ("Die", "The" …), Groß-/Kleinschreibung und Satzzeichen
    local function Simple(name)
        if not name then return nil end
        name = name:lower():gsub("%b()", "")
        for _, article in ipairs({ "die ", "der ", "das ", "the " }) do
            if name:sub(1, #article) == article then name = name:sub(#article + 1) end
        end
        return (name:gsub("[%s%p]", ""))
    end
    for area, ids in pairs(dungeonAreasSeen) do
        local areaName = Simple(AreaName(area))
        if areaName and areaName ~= "" then
            for _, dungeon in ipairs(dungeons) do
                if not areaOf[dungeon] and (Simple(dungeon.name) == areaName or Simple(dungeon.nameEN) == areaName) then
                    areaOf[dungeon], byArea[area], found[area] = area, dungeon, ids
                    report[dungeon] = { area = area, how = "name" }
                end
            end
        end
    end

    -- 4. Questlisten zusammenführen: Questie-Quests (mit alten Zusatzangaben) + alte Quests, die Questie nicht kennt
    local dungeonAreas = {}
    for area in pairs(byArea) do dungeonAreas[area] = true end
    for area, dungeon in pairs(byArea) do
        local old, merged, seen = {}, {}, {}
        for _, quest in ipairs(dungeon.quests or {}) do
            if quest.id then old[quest.id] = quest end
        end
        local fromQuestie, added = 0, 0
        for _, questID in ipairs(found[area] or {}) do
            if not seen[questID] then
                seen[questID] = true
                if not old[questID] then added = added + 1 end
                merged[#merged + 1] = BuildQuest(db, questID, old[questID], dungeonAreas)
                fromQuestie = fromQuestie + 1
            end
            if fromQuestie % 20 == 0 then coroutine.yield() end
        end
        local kept = 0
        for _, quest in ipairs(dungeon.quests or {}) do
            if not quest.id or not seen[quest.id] then
                merged[#merged + 1] = quest
                kept = kept + 1
            end
        end
        -- nach Mindeststufe ordnen (Quests ohne Angabe ans Ende)
        table.sort(merged, function(a, b)
            local la, lb = a.minLevel or 99, b.minLevel or 99
            if la ~= lb then return la < lb end
            return (a.id or 0) < (b.id or 0)
        end)
        dungeon.quests = merged
        local r = report[dungeon]
        r.questie, r.added, r.kept = fromQuestie, added, kept
    end
    ns.questieDungeonReport = { dungeons = dungeons, report = report }

    -- 5. Anzeige neu aufbauen
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

-- Start, sobald Questie fertig geladen ist (ohne Questie bleibt alles beim eingefrorenen Stand)
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

-- /fq dungeonquellen: je Dungeon, woher die Quests kommen
function ns.DebugDungeonSources()
    local prefix = ns.ChatPrefix() .. ": "
    local data = ns.questieDungeonReport
    if not data then
        print(prefix .. ns.L("DNGSRC_NONE"))
        return
    end
    for _, dungeon in ipairs(data.dungeons) do
        local r = data.report[dungeon]
        local name = dungeon.name or "?"
        if r and r.questie then
            print(prefix .. ns.L("DNGSRC_LINE", name, r.questie, r.added, r.kept, r.area,
                ns.L(r.how == "name" and "DNGSRC_BY_NAME" or "DNGSRC_BY_IDS")))
        elseif r and r.how == "shared" then
            print(prefix .. ns.L("DNGSRC_SHARED", name, #(dungeon.quests or {})))
        else
            print(prefix .. ns.L("DNGSRC_OLD", name, #(dungeon.quests or {})))
        end
    end
end
