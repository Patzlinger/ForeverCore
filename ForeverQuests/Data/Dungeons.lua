local addonName, ns = ...

-- Dungeon-Daten: keine eigenen Daten. Das Dungeonfenster baut sich komplett aus dem Spiel und aus Questie auf
-- (QuestieDungeons.lua). Ohne Questie bleibt die Liste leer.
--
-- Aufbau eines Dungeons (wie QuestieDungeons.lua ihn füllt):
--   name, nameEN, levels ("13-18"), zone (Eingang), zoneEN, entranceX/entranceY, areaID, altAreas, isRaid,
--   type ("Classic"/"Neu in Forever"), faction ("Horde", "Alliance", "Both"), quests
-- Je Quest: id, minLevel, level, faction, giver (oder giverItemID), zone, x, y, prequestID, classID, startsInside

ns.DUNGEON_DATA = {}
