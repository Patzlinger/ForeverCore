local addonName, ns = ...

-- Texte auf Deutsch und Englisch. Deutsch nur bei deutschem Client (Sprachwahl im Hub, /forever), sonst Englisch.

local STRINGS = {
    deDE = {
        ADDON_NAME = "ForeverBags (Beta)",
        WINDOW_TITLE = "Taschen",
        SEARCH = "Suchen …",
        SORT = "Sortieren",
        TIP_SORT = "Taschen aufräumen (wie Blizzards Sortieren)",
        FREE_SLOTS = "%d / %d frei",
        TIP_FREE = "Freie Plätze in allen Taschen",
        OPT_TITLE = "Taschen – Einstellungen",
        SEC_GENERAL = "Allgemein",
        SEC_LOOK = "Aussehen",
        OPT_REPLACE = "Blizzards Taschenfenster ersetzen",
        OPT_REPLACE_HINT = "Aus: Blizzards Taschen öffnen sich wie gewohnt; dieses Fenster gibt es dann nur per /fbags bags oder Rechtsklick auf den Minimap-Knopf.",
        OPT_LOCK = "Fenster sperren (nicht verschiebbar)",
        OPT_COLUMNS = "Spalten",
        OPT_SCALE = "Größe",
        OPT_SPACING = "Abstand",
        OPT_QUALITY = "Rand in Qualitätsfarbe",
        OPT_NEW = "Neue Gegenstände hervorheben",
        BTN_RESET_POS = "Position zurücksetzen",
        BTN_CLOSE = "Schließen",
        POS_RESET = "Position zurückgesetzt.",
        COMBAT_LATER = "Neue Taschenplätze werden nach dem Kampf angelegt.",
        TIP_LEFT = "Linksklick: Einstellungen",
        TIP_RIGHT = "Rechtsklick: Taschen öffnen/schließen",
        BAGS_UNLOCKED = "Taschenfenster entsperrt – an der Titelleiste ziehen.",
        BAGS_LOCKED = "Taschenfenster gesperrt.",
    },
    enUS = {
        ADDON_NAME = "ForeverBags (Beta)",
        WINDOW_TITLE = "Bags",
        SEARCH = "Search …",
        SORT = "Sort",
        TIP_SORT = "Tidy up your bags (like Blizzard's sort)",
        FREE_SLOTS = "%d / %d free",
        TIP_FREE = "Free slots in all bags",
        OPT_TITLE = "Bags – Settings",
        SEC_GENERAL = "General",
        SEC_LOOK = "Look",
        OPT_REPLACE = "Replace Blizzard's bag window",
        OPT_REPLACE_HINT = "Off: Blizzard's bags open as usual; this window is then only available via /fbags bags or by right-clicking the minimap button.",
        OPT_LOCK = "Lock window (cannot be moved)",
        OPT_COLUMNS = "Columns",
        OPT_SCALE = "Size",
        OPT_SPACING = "Spacing",
        OPT_QUALITY = "Border in quality color",
        OPT_NEW = "Highlight new items",
        BTN_RESET_POS = "Reset position",
        BTN_CLOSE = "Close",
        POS_RESET = "Position reset.",
        COMBAT_LATER = "New bag slots will be created after combat.",
        TIP_LEFT = "Left-click: settings",
        TIP_RIGHT = "Right-click: open/close bags",
        BAGS_UNLOCKED = "Bag window unlocked – drag it by the title bar.",
        BAGS_LOCKED = "Bag window locked.",
    },
}

-- Aktive Sprache: gemeinsame Sprachwahl aller Forever-Addons (ForeverHub, /forever), sonst wie der Client
local function Active()
    local UI = _G.ForeverHub and _G.ForeverHub.UI
    local language = UI and UI.GetLanguage and UI.GetLanguage() or (GetLocale() == "deDE" and "deDE" or "enUS")
    return STRINGS[language] or STRINGS.enUS
end

-- Text zum Schlüssel; zusätzliche Werte werden wie bei string.format eingesetzt
function ns.L(key, ...)
    local text = Active()[key] or STRINGS.enUS[key] or key
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end
