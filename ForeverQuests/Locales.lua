local addonName, ns = ...

-- Alle sichtbaren Texte des Addons auf Deutsch und Englisch.
-- Die Sprache wird im Menü gewählt ("Automatisch" = Sprache des WoW-Clients).

local STRINGS = {
    deDE = {
        ADDON_NAME = "ForeverQuests (Beta)",
        LOADED = "geladen. Menü: /fq",
        RESET_DONE = "Position und Größe zurückgesetzt.",
        TRACKER_UNLOCKED = "Tracker entsperrt.",
        TRACKER_LOCKED = "Tracker gesperrt.",

        -- Schriften
        FONT_STANDARD = "Standard",

        -- Tracker
        TRACKER_TITLE = "Quests",
        TAG_CLASS = "[Klasse]", TAG_REPUTATION = "[Ruf]", TAG_PROFESSION = "[Beruf]",
        PINNED = "Angeheftet",
        OTHER = "Sonstige",
        COMPLETE_TAG = "(Fertig)",
        READY_TO_TURN_IN = "Bereit zur Abgabe",
        EMPTY_INSTANCE = "Keine Quests für diese Instanz",
        EMPTY_FILTER = "Keine Quests für diesen Filter",
        EMPTY_TRACKED = "Keine verfolgten Quests",
        EMPTY_LOG = "Keine Quests im Questlog",
        BTN_DUNGEONS = "Dungeons", TIP_DUNGEONS = "Dungeon-Quests anzeigen",
        BTN_FILTER = "Filter", TIP_FILTER_ACTIVE = "Aktiv: %s",
        BTN_MENU = "Menü", TIP_MENU = "Menü öffnen",
        UNLOCK_HINT = "Tracker entsperrt\nZiehen zum Verschieben\nEcke unten rechts: Größe",
        TIP_GROUP_TOGGLE = "Klicken: Gebiet ein-/ausklappen",
        TIP_QUEST_ITEM = "Questgegenstand – benutzen über die Tasche oder das Questlog",
        TIP_REWARD_CHEST = "Die Truhe erscheint bei Belohnungen ab der im Menü eingestellten Seltenheit.",
        BINDING_HEADER = "ForeverQuests (Beta)",
        BINDING_TRACKER = "Questtracker ein-/ausblenden",
        BINDING_DUNGEONS = "Dungeonfenster öffnen/schließen",
        BINDING_OPTIONS = "Menü öffnen/schließen",
        TIP_REWARDS = "Belohnungen:", TIP_CHOICES = "Eine davon wählen:", TIP_XP = "%s Erfahrung",
        TIP_QUEST_HINT = "Linksklick: auf-/zuklappen  ·  Rechtsklick: Menü  ·  Shift-Klick: nicht mehr verfolgen",

        -- Rechtsklick-Menü
        MENU_DETAILS = "Questdetails anzeigen",
        MENU_PIN = "Quest anheften", MENU_UNPIN = "Nicht mehr anheften",
        MENU_SHARE = "Quest teilen", MENU_UNTRACK = "Nicht mehr verfolgen", MENU_ABANDON = "Quest abbrechen",

        -- Filter
        FILTER_TITLE = "Quests filtern (mehrere möglich)",
        FILTER_DEFAULT = "Standard (laut Menü)",
        FILTER_ALL = "Alle Quests im Questlog",
        FILTER_ZONE = "Aktuelles Gebiet",
        FILTER_DUNGEON = "Dungeon",
        FILTER_RAID = "Schlachtzug",
        FILTER_GROUP = "Gruppe / Elite",
        FILTER_PVP = "PvP",
        FILTER_CLASS = "Klasse",
        FILTER_PROFESSION = "Beruf",
        FILTER_REPUTATION = "Ruf",
        FILTER_COMPLETE = "Bereit zur Abgabe",
        FILTER_REWARD = "Mit Beutetruhe",
        FILTER_PINNED = "Angeheftet",
        FILTER_INSTANCE = "Aktuelle Instanz (automatisch)",
        FILTER_INSTANCE_TOGGLE = "In Instanzen nur Instanz-Quests",

        -- Menü
        OPT_TITLE = "Einstellungen",
        SEC_DISPLAY = "Anzeige", SEC_LOOKS = "Schrift & Aussehen", SEC_LAYOUT = "Position & Größe",
        OPT_UNLOCK = "Tracker entsperren (verschieben/Größe)",
        OPT_HIDE_BLIZZARD = "Blizzard-Questtracker ausblenden",
        OPT_HIDE_COMBAT = "Tracker im Kampf ausblenden",
        OPT_ONLY_TRACKED = "Nur verfolgte Quests anzeigen",
        OPT_COLLAPSE = "Questfortschritt einklappen (nur Namen)",
        OPT_ZONES = "Gebiete als Überschrift anzeigen",
        OPT_QUEST_TYPE = "Questtyp anzeigen (Klasse/Ruf)",
        OPT_MINIMAP = "Minimap-Button anzeigen",
        OPT_INSTANCE = "In Instanzen nur Instanz-Quests zeigen",
        OPT_LANGUAGE = "Sprache", LANG_AUTO = "Automatisch (Client)",
        OPT_REWARDS = "Belohnungen",
        OPT_REWARDS_HINT = "Quests mit Gegenstandsbelohnungen ab dieser Seltenheit bekommen eine kleine Beutetruhe.",
        REWARD_OFF = "Aus",
        REWARD_GREEN = "|cff1eff00Grün|r und besser",
        REWARD_BLUE = "|cff0070ddBlau|r und besser",
        REWARD_EPIC = "|cffa335eeEpisch|r",
        OPT_FONT = "Schriftart", OPT_OUTLINE = "Schrift mit Umrandung",
        OPT_FONT_SIZE = "Schriftgröße", OPT_TRANSPARENCY = "Hintergrund-Transparenz (%)",
        OPT_AUTO_COLLAPSE = "Fortschritt wieder einklappen nach (Minuten)",
        OPT_QUEST_TOOLTIP = "Quest-Tooltip im Tracker anzeigen",
        OPT_INSTANCE_HINT = "Hinweis beim Betreten eines Dungeons",
        OPT_WIDTH = "Breite", OPT_HEIGHT = "Höhe",
        OPT_POS_X = "Position X (von links)", OPT_POS_Y = "Position Y (von unten)",
        BTN_RESET = "Zurücksetzen", TIP_RESET = "Position und Größe des Trackers zurücksetzen",
        BTN_CLOSE = "Schließen",

        -- Dungeon-Fenster
        DUNGEONS_TITLE = "Dungeons",
        DUNGEONS_COUNT = "%d Dungeons",
        SEARCH_PLACEHOLDER = "Dungeon oder Gebiet suchen …",
        ONLY_MY_FACTION = "Nur Quests meiner Fraktion",
        HIDE_COMPLETED = "Abgeschlossene ausblenden",
        REMAINING_COUNT = "%d verbleibend",
        TAB_ALL = "Alle Dungeons",
        TAB_MY_LEVEL = "Mein Levelbereich",
        TIP_MY_LEVEL = "Zeigt nur Dungeons, deren Levelbereich zu deinem Level passt (ab 2 Level vorher), "
            .. "und nur Quests, deren erforderliche Stufe du erreicht hast und deren Questlevel höchstens "
            .. "5 Level von deinem entfernt ist.",
        NO_DUNGEON_LEVEL = "Kein Dungeon in deinem Levelbereich",
        NO_QUESTS_REMAINING = "Alle Quests dieses Dungeons hast du schon abgeschlossen.\n\n"
            .. "|cff888888Häkchen „Abgeschlossene ausblenden“ unten abwählen, um sie zu sehen.|r",
        GROUP_HAS_QUEST = "In der Gruppe:",
        CHECK_START = "Prüfe %d Quest-IDs … (dauert etwa 15 Sekunden)",
        CHECK_RUNNING = "Die Prüfung läuft bereits.",
        CHECK_UNKNOWN = "Unbekannte Quest-ID %d: %s (%s)",
        CHECK_NAME = "Name weicht ab (ID %d): Excel „%s“ / Spiel „%s“",
        CHECK_MORE = "… und %d weitere Meldungen",
        CHECK_DONE = "Fertig: %d in Ordnung, %d unbekannt, %d mit abweichendem Namen.",
        FACTION_HORDE = "Horde", FACTION_ALLIANCE = "Allianz", FACTION_BOTH = "Beide Fraktionen",
        STATUS_DONE = "Abgeschlossen", STATUS_ACTIVE = "Im Questlog",
        NO_DUNGEON = "Kein Dungeon ausgewählt",
        LEVEL = "Level %s",
        NEW_IN_FOREVER = "Neu in Forever", NEW_TAG = "NEU",
        FROM_LEVEL = "Erforderliche Stufe",
        PREQUEST = "Vorquest:",
        STARTS_INSIDE = "Startet im Dungeon",
        STARTED_BY_ITEM = "Startet durch:",
        TIP_LFG = "In der Gruppensuche vorauswählen und nach Gruppen suchen",
        LFG_COMBAT = "Die Gruppensuche kann im Kampf nicht geöffnet werden.",
        LFG_UNAVAILABLE = "Die Gruppensuche konnte nicht geöffnet werden (/fq lfg zeigt Details).",
        LFG_NOT_FOUND = "%s steht nicht in der Gruppensuche (/fq lfg zeigt die Einträge).",
        CLASS_FALLBACK = "Klasse %d",
        QUEST_CHAIN = "Questkette (%d/%d):",
        GROUP_MISSING = "Fehlt bei:", GROUP_ALL = "alle haben sie", YOU = "Du",
        BTN_GROUP = "Gruppe", TIP_GROUP_TITLE = "Gruppenabgleich (Quests im Questlog)",
        TIP_GROUP_NONE = "Niemand in der Gruppe hat eine Quest dieses Dungeons im Questlog.",
        LINK_HINT = "Shift-Klick auf eine Quest: im Chat verlinken",
        HINT_TITLE = "Dungeon betreten", BTN_SHOW = "Ansehen",
        HINT_TEXT = "|cffffd100%s|r\n|cff33ff99%d Quest(s) dabei|r  ·  |cffff7070%d fehlen dir noch|r",
        QUEST_FALLBACK = "Quest %d (wird geladen …)",
        QUEST_UNKNOWN = "Quest %d (Not available in Beta)",
        NOT_IN_BETA = "(Not available in Beta)",
        QUEST_GIVER = "Questgeber",
        QUEST_COUNT_ONE = "1 Quest", QUEST_COUNT = "%d Quests", DONE_COUNT = "%d abgeschlossen",
        NO_QUESTS_DUNGEON = "Für diesen Dungeon sind noch keine Quests eingetragen.",
        NO_QUESTS_FACTION = "Keine Quests für deine Fraktion eingetragen.\n\n"
            .. "|cff888888Häkchen „Nur Quests meiner Fraktion“ unten links abwählen.|r",
        REWARDS_COUNT = "Belohnungen (%d)",
        ITEM_LOADING = "Gegenstand %d |cff777777(lädt …)|r",
        BTN_WAYPOINT = "Kartenpunkt", TIP_WAYPOINT = "Kartenpunkt zum Questgeber setzen",
        BTN_SHARE = "Teilen", TIP_SHARE = "Quest mit deiner Gruppe teilen",
        SHARE_NO_GROUP = "Zum Teilen musst du in einer Gruppe sein.",
        SHARE_NOT_PUSHABLE = "Diese Quest kann nicht geteilt werden.",
        BTN_SHARE_ALL = "Alle teilen", BTN_SHARE_QUESTS = "Quests teilen",
        TIP_SHARE_ALL = "Teilt alle Quests dieses Dungeons aus deinem Questlog mit der Gruppe",
        SHARE_ALL_DONE = "%d Quest(s) werden nacheinander geteilt.",
        SHARE_ALL_NONE = "Keine teilbaren Quests dieses Dungeons in deinem Questlog.",        BTN_ATLASLOOT = "Bosse & Beute", TIP_ATLASLOOT = "Öffnet diesen Dungeon in AtlasLoot (Bosse und Beute)",
        ATLASLOOT_FAILED = "AtlasLoot konnte nicht geöffnet werden.",
        ATLASLOOT_COMBAT = "AtlasLoot kann im Kampf nicht geöffnet werden.",
        WING_GRAVEYARD = "Friedhof", WING_LIBRARY = "Bibliothek", WING_ARMORY = "Waffenkammer", WING_CATHEDRAL = "Kathedrale",
        WING_EAST = "Ost", WING_WEST = "West", WING_NORTH = "Nord",
        NO_COORDS = "Für diese Quest sind keine Koordinaten eingetragen.",
        NO_WAYPOINT = "Für %s kann kein Kartenpunkt gesetzt werden.",
        THIS_ZONE = "dieses Gebiet",
        WAYPOINT_SET = "Kartenpunkt gesetzt: %s, %s (%s, %s)",

        -- Minimap-Button
        MM_LEFT = "Linksklick: Menü öffnen",
        MM_RIGHT = "Rechtsklick: Tracker ein-/ausblenden",
        MM_DRAG = "Ziehen: Button verschieben",
    },

    enUS = {
        ADDON_NAME = "ForeverQuests (Beta)",
        LOADED = "loaded. Menu: /fq",
        RESET_DONE = "Position and size reset.",
        TRACKER_UNLOCKED = "Tracker unlocked.",
        TRACKER_LOCKED = "Tracker locked.",

        FONT_STANDARD = "Default",

        TRACKER_TITLE = "Quests",
        TAG_CLASS = "[Class]", TAG_REPUTATION = "[Rep]", TAG_PROFESSION = "[Profession]",
        PINNED = "Pinned",
        OTHER = "Other",
        COMPLETE_TAG = "(Complete)",
        READY_TO_TURN_IN = "Ready to turn in",
        EMPTY_INSTANCE = "No quests for this instance",
        EMPTY_FILTER = "No quests for this filter",
        EMPTY_TRACKED = "No tracked quests",
        EMPTY_LOG = "No quests in quest log",
        BTN_DUNGEONS = "Dungeons", TIP_DUNGEONS = "Show dungeon quests",
        BTN_FILTER = "Filter", TIP_FILTER_ACTIVE = "Active: %s",
        BTN_MENU = "Menu", TIP_MENU = "Open menu",
        UNLOCK_HINT = "Tracker unlocked\nDrag to move\nBottom-right corner: resize",
        TIP_GROUP_TOGGLE = "Click: collapse/expand zone",
        TIP_QUEST_ITEM = "Quest item – use it from your bags or the quest log",
        TIP_REWARD_CHEST = "The chest appears for rewards of the rarity set in the menu or better.",
        BINDING_HEADER = "ForeverQuests (Beta)",
        BINDING_TRACKER = "Show/hide quest tracker",
        BINDING_DUNGEONS = "Open/close dungeon window",
        BINDING_OPTIONS = "Open/close menu",
        TIP_REWARDS = "Rewards:", TIP_CHOICES = "Choose one:", TIP_XP = "%s experience",
        TIP_QUEST_HINT = "Left-click: expand/collapse  ·  Right-click: menu  ·  Shift-click: stop tracking",

        MENU_DETAILS = "Show quest details",
        MENU_PIN = "Pin quest", MENU_UNPIN = "Unpin quest",
        MENU_SHARE = "Share quest", MENU_UNTRACK = "Stop tracking", MENU_ABANDON = "Abandon quest",

        FILTER_TITLE = "Filter quests (several possible)",
        FILTER_DEFAULT = "Default (as in menu)",
        FILTER_ALL = "All quests in quest log",
        FILTER_ZONE = "Current zone",
        FILTER_DUNGEON = "Dungeon",
        FILTER_RAID = "Raid",
        FILTER_GROUP = "Group / Elite",
        FILTER_PVP = "PvP",
        FILTER_CLASS = "Class",
        FILTER_PROFESSION = "Profession",
        FILTER_REPUTATION = "Reputation",
        FILTER_COMPLETE = "Ready to turn in",
        FILTER_REWARD = "With loot chest",
        FILTER_PINNED = "Pinned",
        FILTER_INSTANCE = "Current instance (automatic)",
        FILTER_INSTANCE_TOGGLE = "In instances: instance quests only",

        OPT_TITLE = "Settings",
        SEC_DISPLAY = "Display", SEC_LOOKS = "Font & Appearance", SEC_LAYOUT = "Position & Size",
        OPT_UNLOCK = "Unlock tracker (move/resize)",
        OPT_HIDE_BLIZZARD = "Hide Blizzard quest tracker",
        OPT_HIDE_COMBAT = "Hide tracker in combat",
        OPT_ONLY_TRACKED = "Show tracked quests only",
        OPT_COLLAPSE = "Collapse quest progress (names only)",
        OPT_ZONES = "Show zones as headers",
        OPT_QUEST_TYPE = "Show quest type (class/rep)",
        OPT_MINIMAP = "Show minimap button",
        OPT_INSTANCE = "In instances, show instance quests only",
        OPT_LANGUAGE = "Language", LANG_AUTO = "Automatic (client)",
        OPT_REWARDS = "Rewards",
        OPT_REWARDS_HINT = "Quests with item rewards of at least this quality get a small loot chest.",
        REWARD_OFF = "Off",
        REWARD_GREEN = "|cff1eff00Green|r and better",
        REWARD_BLUE = "|cff0070ddBlue|r and better",
        REWARD_EPIC = "|cffa335eeEpic|r",
        OPT_FONT = "Font", OPT_OUTLINE = "Outlined font",
        OPT_FONT_SIZE = "Font size", OPT_TRANSPARENCY = "Background transparency (%)",
        OPT_AUTO_COLLAPSE = "Collapse progress again after (minutes)",
        OPT_QUEST_TOOLTIP = "Show quest tooltip in the tracker",
        OPT_INSTANCE_HINT = "Show a hint when entering a dungeon",
        OPT_WIDTH = "Width", OPT_HEIGHT = "Height",
        OPT_POS_X = "Position X (from left)", OPT_POS_Y = "Position Y (from bottom)",
        BTN_RESET = "Reset", TIP_RESET = "Reset tracker position and size",
        BTN_CLOSE = "Close",

        DUNGEONS_TITLE = "Dungeons",
        DUNGEONS_COUNT = "%d dungeons",
        SEARCH_PLACEHOLDER = "Search dungeon or zone …",
        ONLY_MY_FACTION = "Only quests for my faction",
        HIDE_COMPLETED = "Hide completed",
        REMAINING_COUNT = "%d remaining",
        TAB_ALL = "All dungeons",
        TAB_MY_LEVEL = "My level range",
        TIP_MY_LEVEL = "Shows only dungeons whose level range fits your level (from 2 levels before), "
            .. "and only quests whose required level you have reached and whose quest level is at most "
            .. "5 levels away from yours.",
        NO_DUNGEON_LEVEL = "No dungeon in your level range",
        NO_QUESTS_REMAINING = "You have already completed all quests of this dungeon.\n\n"
            .. "|cff888888Uncheck “Hide completed” at the bottom to see them.|r",
        GROUP_HAS_QUEST = "In group:",
        CHECK_START = "Checking %d quest IDs … (takes about 15 seconds)",
        CHECK_RUNNING = "The check is already running.",
        CHECK_UNKNOWN = "Unknown quest ID %d: %s (%s)",
        CHECK_NAME = "Name differs (ID %d): Excel “%s” / game “%s”",
        CHECK_MORE = "… and %d more messages",
        CHECK_DONE = "Done: %d OK, %d unknown, %d with a different name.",
        FACTION_HORDE = "Horde", FACTION_ALLIANCE = "Alliance", FACTION_BOTH = "Both factions",
        STATUS_DONE = "Completed", STATUS_ACTIVE = "In quest log",
        NO_DUNGEON = "No dungeon selected",
        LEVEL = "Level %s",
        NEW_IN_FOREVER = "New in Forever", NEW_TAG = "NEW",
        FROM_LEVEL = "Required level",
        PREQUEST = "Prequest:",
        STARTS_INSIDE = "Starts inside the dungeon",
        STARTED_BY_ITEM = "Started by:",
        TIP_LFG = "Preselect in the group finder and search for groups",
        LFG_COMBAT = "The group finder cannot be opened in combat.",
        LFG_UNAVAILABLE = "The group finder could not be opened (/fq lfg shows details).",
        LFG_NOT_FOUND = "%s is not listed in the group finder (/fq lfg shows the entries).",
        CLASS_FALLBACK = "Class %d",
        QUEST_CHAIN = "Quest chain (%d/%d):",
        GROUP_MISSING = "Missing:", GROUP_ALL = "everyone has it", YOU = "You",
        BTN_GROUP = "Group", TIP_GROUP_TITLE = "Group check (quests in quest log)",
        TIP_GROUP_NONE = "Nobody in your group has a quest of this dungeon in their quest log.",
        LINK_HINT = "Shift-click a quest: link it in chat",
        HINT_TITLE = "Dungeon entered", BTN_SHOW = "Show",
        HINT_TEXT = "|cffffd100%s|r\n|cff33ff99%d quest(s) with you|r  ·  |cffff7070%d still missing|r",
        QUEST_FALLBACK = "Quest %d (loading …)",
        QUEST_UNKNOWN = "Quest %d (Not available in Beta)",
        NOT_IN_BETA = "(Not available in Beta)",
        QUEST_GIVER = "Quest giver",
        QUEST_COUNT_ONE = "1 quest", QUEST_COUNT = "%d quests", DONE_COUNT = "%d completed",
        NO_QUESTS_DUNGEON = "No quests have been entered for this dungeon yet.",
        NO_QUESTS_FACTION = "No quests entered for your faction.\n\n"
            .. "|cff888888Uncheck “Only quests for my faction” at the bottom left.|r",
        REWARDS_COUNT = "Rewards (%d)",
        ITEM_LOADING = "Item %d |cff777777(loading …)|r",
        BTN_WAYPOINT = "Map pin", TIP_WAYPOINT = "Set a map pin to the quest giver",
        BTN_SHARE = "Share", TIP_SHARE = "Share this quest with your group",
        SHARE_NO_GROUP = "You need to be in a group to share quests.",
        SHARE_NOT_PUSHABLE = "This quest cannot be shared.",
        BTN_SHARE_ALL = "Share all", BTN_SHARE_QUESTS = "Share quests",
        TIP_SHARE_ALL = "Shares all quests of this dungeon from your quest log with your group",
        SHARE_ALL_DONE = "Sharing %d quest(s) one after another.",
        SHARE_ALL_NONE = "No shareable quests of this dungeon in your quest log.",        BTN_ATLASLOOT = "Bosses & loot", TIP_ATLASLOOT = "Opens this dungeon in AtlasLoot (bosses and loot)",
        ATLASLOOT_FAILED = "AtlasLoot could not be opened.",
        ATLASLOOT_COMBAT = "AtlasLoot cannot be opened in combat.",
        WING_GRAVEYARD = "Graveyard", WING_LIBRARY = "Library", WING_ARMORY = "Armory", WING_CATHEDRAL = "Cathedral",
        WING_EAST = "East", WING_WEST = "West", WING_NORTH = "North",
        NO_COORDS = "No coordinates have been entered for this quest.",
        NO_WAYPOINT = "Cannot set a map pin for %s.",
        THIS_ZONE = "this zone",
        WAYPOINT_SET = "Map pin set: %s, %s (%s, %s)",

        MM_LEFT = "Left-click: open menu",
        MM_RIGHT = "Right-click: show/hide tracker",
        MM_DRAG = "Drag: move button",
    },
}

-- Auswahl im Menü
ns.LANGUAGES = {
    { value = "AUTO", textKey = "LANG_AUTO" },
    { value = "deDE", text = "Deutsch" },
    { value = "enUS", text = "English" },
}

-- Deutsch gibt es nur, wenn der WoW-Client auf Deutsch läuft; sonst ist immer Englisch aktiv
local GERMAN_CLIENT = GetLocale() == "deDE"

if not GERMAN_CLIENT then
    -- Deutsch aus der Auswahl im Menü entfernen
    for i = #ns.LANGUAGES, 1, -1 do
        if ns.LANGUAGES[i].value == "deDE" then
            table.remove(ns.LANGUAGES, i)
        end
    end
end

-- Aktive Sprache: Menü-Einstellung (nur bei deutschem Client), sonst Englisch
function ns.GetLanguage()
    if not GERMAN_CLIENT then
        return "enUS"
    end
    local language = ns.db and ns.db.language
    if language == "enUS" then
        return "enUS"
    end
    return "deDE" -- "Automatisch" oder "Deutsch"
end

-- Text zu einem Schlüssel; weitere Werte werden wie bei string.format eingesetzt
-- (fehlt ein Text, wird der englische genommen)
function ns.L(key, ...)
    local text = STRINGS[ns.GetLanguage()][key] or STRINGS.enUS[key] or key
    if select("#", ...) > 0 then
        return text:format(...)
    end
    return text
end
