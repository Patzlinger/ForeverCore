local addonName, ns = ...

-- Dungeon-Questdaten. Früher aus ForeverQuests_Dungeons.xlsx erzeugt – die Excel-Datei wird nicht mehr gebraucht.
-- Ist Questie installiert, holt QuestieDungeons.lua die Quests jedes Dungeons aus Questies Datenbank; diese Datei
-- liefert dann nur noch die Dungeon-Grunddaten (Name, Stufen, Eingang, Typ, Fraktion) und die Gegenstands-
-- belohnungen. Ohne Questie gilt der Questbestand hier als eingefrorener Stand. Änderungen direkt hier eintragen.
--
-- Je Dungeon: name, nameEN, levels, zone (Eingang), zoneEN, entranceX/entranceY,
--   type ("Classic"/"Neu in Forever"), faction ("Horde", "Alliance", "Both"), quests
-- Je Quest:   id, minLevel, faction, giver, giverEN (oder giverItemID), zone, zoneEN, x, y,
--   prequestID (oder prequest = Name), classID, startsInside (true = startet im Dungeon), rewards (Item-IDs)
--   name, nameEN, level nur bei Quests ohne ID (sonst kommen sie aus dem Spiel)
-- Felder mit "EN" werden bei englischer Sprache angezeigt (falls eingetragen).

ns.DUNGEON_DATA = {
    {
        name = "Ragefireabgrund",
        nameEN = "Ragefire Chasm",
        levels = "13-18",
        zone = "Orgrimmar",
        zoneEN = "Orgrimmar",
        type = "Classic",
        faction = "Horde",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Halle der Thanen",
        nameEN = "Hall of Thanes",
        levels = "13-18",
        zone = "Ironforge (Old Ironforge)",
        zoneEN = "Ironforge",
        type = "Neu in Forever",
        faction = "Alliance",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Höhlen des Wehklagens",
        nameEN = "Wailing Caverns",
        levels = "15-25",
        zone = "Brachland",
        zoneEN = "The Barrens",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Ruinen von Lordaeron",
        nameEN = "Ruins of Lordaeron",
        levels = "15-20",
        zone = "Tirisfal",
        zoneEN = "Tirisfal Glades",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Todesminen",
        nameEN = "The Deadmines",
        levels = "18-23",
        zone = "Westfall",
        zoneEN = "Westfall",
        type = "Classic",
        faction = "Alliance",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Burg Shadowfang",
        nameEN = "Shadowfang Keep",
        levels = "22-30",
        zone = "Silberwald",
        zoneEN = "Silverpine Forest",
        type = "Classic",
        faction = "Horde",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Das Verlies",
        nameEN = "The Stockade",
        levels = "24-30",
        zone = "Stormwind",
        zoneEN = "Stormwind",
        type = "Classic",
        faction = "Alliance",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Blackfathom-Tiefe",
        nameEN = "Blackfathom Deeps",
        levels = "24-32",
        zone = "Ashenvale",
        zoneEN = "Ashenvale",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Ausgrabungsstätte: Sumpfland",
        nameEN = "Excavation Site: Wetlands",
        levels = "26-31",
        zone = "Sumpfland",
        zoneEN = "Wetlands",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Das Scharlachrote Kloster",
        nameEN = "Scarlet Monastery",
        levels = "26-45",
        zone = "Tirisfal",
        zoneEN = "Tirisfal Glades",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Dalaran (City of Dalaran)",
        nameEN = "City of Dalaran",
        levels = "28-33",
        zone = "Alteracgebirge",
        zoneEN = "Alterac Mountains",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Gnomeregan",
        nameEN = "Gnomeregan",
        levels = "29-38",
        zone = "Dun Morogh",
        zoneEN = "Dun Morogh",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Der Kral von Razorfen",
        nameEN = "Razorfen Kraul",
        levels = "30-40",
        zone = "Brachland",
        zoneEN = "The Barrens",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "The Drowned City",
        nameEN = "The Drowned City",
        levels = "35-40",
        zone = "Gillijim's Isle",
        zoneEN = "Gillijim's Isle",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Hügel von Razorfen",
        nameEN = "Razorfen Downs",
        levels = "37-43",
        zone = "Brachland",
        zoneEN = "The Barrens",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Feste Krol'dok",
        nameEN = "Krol'dok Stronghold",
        levels = "40-45",
        zone = "Flusslande",
        zoneEN = "Riverglades",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Uldaman",
        nameEN = "Uldaman",
        levels = "42-52",
        zone = "Ödland",
        zoneEN = "Badlands",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Zul'Farrak",
        nameEN = "Zul'Farrak",
        levels = "44-54",
        zone = "Tanaris",
        zoneEN = "Tanaris",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Maraudon",
        nameEN = "Maraudon",
        levels = "46-55",
        zone = "Desolace",
        zoneEN = "Desolace",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Das Gefängnis von Alcaz",
        nameEN = "Alcaz Prison",
        levels = "48-53",
        zone = "Marschen von Dustwallow (Alcaz Island)",
        zoneEN = "Dustwallow Marsh",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Der Tempel von Atal'Hakkar",
        nameEN = "Swamp of Sorrows",
        levels = "50-56",
        zone = "Swamp of Sorrows",
        type = "Classic",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Blackrocktiefen hier geht’s weiter",
        levels = "52-60",
        type = "Classic",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Untere Blackrockspitze",
        levels = "55-60",
        type = "Classic",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Düsterbruch (Ost, Nord, West)",
        levels = "55-60",
        type = "Classic",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Schwarzschlundfeste",
        nameEN = "Blackmaw Hold",
        levels = "55-60",
        zone = "Azshara",
        zoneEN = "Azshara",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Obere Blackrockspitze",
        levels = "58-60",
        type = "Classic",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Die Terrasse des Formers",
        nameEN = "The Shaper's Terrace",
        levels = "58-60",
        zone = "Un'Goro-Krater",
        zoneEN = "Un'Goro Crater",
        type = "Neu in Forever",
        faction = "Both",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Scholomance",
        levels = "58-60",
        type = "Classic",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
    {
        name = "Stratholme (Live und Dead)",
        levels = "58-60",
        type = "Classic",
        quests = {}, -- Quests kommen aus Questie (Test ohne alte Daten, Sicherung: Backups\DungeonData_2026-10-18)
    },
}
