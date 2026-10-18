-- ForeverVendor: Daten – Klassen-Reagenzien (Vorschlaege fuer die Nachkauf-Liste)
-- id = Gegenstand, count = Zielmenge, minLevel = ab dieser Stufe gebraucht.
-- group: aus einer Gruppe wird nur der hoechste Eintrag gekauft, den die Stufe schon erlaubt
-- (z. B. Samen fuer "Wiedergeburt": immer nur die Sorte fuer den aktuellen Rang).
-- IDs aus der Classic-Aera; fehlt ein Gegenstand beim Haendler, passiert einfach nichts.
-- (Modul von ForeverHelpers; Kennung, Einstellungen und Befehle bleiben "ForeverVendor")
local _, root = ...
if root.skip and root.skip.ForeverVendor then return end -- alter Ordner ForeverVendor noch aktiv: der läuft diesmal
local ADDON_NAME = "ForeverVendor"
root.vendor = root.vendor or {}
local ns = root.vendor

ns.CLASS_REAGENTS = {
    SHAMAN = {
        { id = 17030, count = 5, minLevel = 30 },                       -- Ankh (Reinkarnation)
    },
    PALADIN = {
        { id = 17033, count = 5, minLevel = 30 },                       -- Symbol der Goettlichkeit
        { id = 21177, count = 40, minLevel = 52 },                      -- Symbol der Koenige (grosse Segen)
    },
    MAGE = {
        { id = 17031, count = 10, minLevel = 20 },                      -- Rune der Teleportation
        { id = 17032, count = 5, minLevel = 40 },                       -- Rune der Portale
        { id = 17020, count = 20, minLevel = 56 },                      -- Arkanes Pulver
    },
    PRIEST = {
        { id = 17028, count = 20, minLevel = 48, group = "candle" },    -- Heilige Kerze
        { id = 17029, count = 20, minLevel = 60, group = "candle" },    -- Geweihte Kerze
    },
    DRUID = {
        { id = 17034, count = 5, minLevel = 20, group = "seed" },       -- Ahornsamen
        { id = 17035, count = 5, minLevel = 30, group = "seed" },       -- Schlingendornsamen
        { id = 17036, count = 5, minLevel = 40, group = "seed" },       -- Eschenholzsamen
        { id = 17037, count = 5, minLevel = 50, group = "seed" },       -- Hainbuchensamen
        { id = 17038, count = 5, minLevel = 60, group = "seed" },       -- Eisenholzsamen
        { id = 17021, count = 20, minLevel = 50, group = "berry" },     -- Wilde Beeren
        { id = 17026, count = 20, minLevel = 60, group = "berry" },     -- Wilder Dornwurz
    },
    ROGUE = {
        { id = 5140, count = 10, minLevel = 22 },                       -- Blitzstrahlpulver (Verschwinden)
    },
}

-- Essen/Trinken erkennt man am Benutzen-Zauber (in jeder Spielsprache gleich)
ns.FOOD_SPELL = 433
ns.DRINK_SPELL = 430
