local addonName, ns = ...

-- Dungeon-Daten: TEST ohne eigene Daten. Das Dungeonfenster baut sich komplett aus dem Spiel und aus Questie auf
-- (QuestieDungeons.lua). Ohne Questie bleibt die Liste leer.
-- Der frühere, selbst gepflegte Stand (aus ForeverQuests_Dungeons.xlsx) ist gesichert:
--   C:\Users\flowf\Desktop\ForeverAddons\Backups\DungeonData_2026-10-18\Dungeons.lua
--   Git-Tag backup-dungeon-data-2026-10-18 (git show backup-dungeon-data-2026-10-18:ForeverQuests/Data/Dungeons.lua)
--
-- Aufbau eines Dungeons (wie QuestieDungeons.lua ihn füllt):
--   name, nameEN, levels ("13-18"), zone (Eingang), zoneEN, entranceX/entranceY,
--   type ("Classic"/"Neu in Forever"), faction ("Horde", "Alliance", "Both"), quests
-- Je Quest: id, minLevel, level, faction, giver (oder giverItemID), zone, x, y, prequestID, classID, startsInside

ns.DUNGEON_DATA = {}
