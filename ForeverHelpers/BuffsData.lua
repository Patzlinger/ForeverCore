-- ForeverBuffs: Buff-Daten (Classic-Zauber-IDs)
-- Jede Familie: lines = Zauber-Reihen mit allen Raengen (aufsteigend), also = Gruppen-Varianten,
-- die ebenfalls zaehlen (z. B. "Gebet der Seelenstaerke"), supersede = Reihe X wird durch Reihe Y
-- ersetzt (Frostruestung -> Eisruestung), self = man soll es selbst tragen, group = auch fuer
-- die Gruppe, optional = nur wenn in den Optionen eingeschaltet.
-- (Modul von ForeverHelpers; Kennung, Einstellungen und Befehle bleiben "ForeverBuffs")
local _, root = ...
if root.skip and root.skip.ForeverBuffs then return end -- alter Ordner ForeverBuffs noch aktiv: der läuft diesmal
local ADDON_NAME = "ForeverBuffs"
root.buffs = root.buffs or {}
local ns = root.buffs

ns.BUFFS = {
    -- Priester
    { key = "fort", class = "PRIEST", minLevel = 1, self = true, group = true,
      lines = { { 1243, 1244, 1245, 2791, 10937, 10938 } }, also = { 21562, 21564 } },
    { key = "innerfire", class = "PRIEST", self = true,
      lines = { { 588, 7128, 602, 1006, 10951, 10952 } } },
    { key = "spirit", class = "PRIEST", minLevel = 30, self = true, group = true,
      lines = { { 14752, 14818, 14819, 27841 } }, also = { 27681 } },
    { key = "shadowprot", class = "PRIEST", minLevel = 30, group = true, optional = true,
      lines = { { 976, 10957, 10958 } }, also = { 27683 } },
    -- Magier
    { key = "intellect", class = "MAGE", minLevel = 14, self = true, group = true,
      lines = { { 1459, 1460, 1461, 10156, 10157 } }, also = { 23028 } },
    { key = "magearmor", class = "MAGE", self = true,
      lines = { { 168, 7300, 7301 }, { 7302, 7320, 10219, 10220 }, { 6117, 22782, 22783 } }, supersede = { [1] = 2 } },
    -- Druide
    { key = "motw", class = "DRUID", minLevel = 1, self = true, group = true,
      lines = { { 1126, 5232, 6756, 5234, 8907, 9884, 9885 } }, also = { 21849, 21850 } },
    { key = "thorns", class = "DRUID", self = true,
      lines = { { 467, 782, 1075, 8914, 9756, 9910 } } },
    -- Paladin: irgendein Segen / irgendeine Aura
    { key = "blessing", class = "PALADIN", self = true,
      lines = { { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, { 19742, 19850, 19852, 19853, 19854, 25290 },
          { 20217 }, { 1038 }, { 19977, 19978, 19979 } },
      also = { 25782, 25916, 25894, 25918, 25898, 25895, 25890 } },
    { key = "aura", class = "PALADIN", self = true,
      lines = { { 465, 10290, 643, 10291, 1032, 10292, 10293 }, { 7294, 10298, 10299, 10300, 10301 }, { 19746 },
          { 19876, 19895, 19896 }, { 19888, 19897, 19898 }, { 19891, 19899, 19900 }, { 20218 } } },
    -- Hexenmeister
    { key = "demonarmor", class = "WARLOCK", self = true,
      lines = { { 687, 696 }, { 706, 1086, 11733, 11734, 11735 } }, supersede = { [1] = 2 } },
    -- Krieger (Schlachtruf haelt 2 Minuten – Erinnerung ausserhalb des Kampfs)
    { key = "battleshout", class = "WARRIOR", self = true,
      lines = { { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } } },
    -- Schamane
    { key = "lshield", class = "SHAMAN", self = true,
      lines = { { 324, 325, 905, 945, 8134, 10431, 10432 } } },
    -- Jaeger: irgendein Aspekt
    { key = "aspect", class = "HUNTER", self = true,
      lines = { { 13165, 14318, 14319, 14320, 14321, 14322, 25296 }, { 13163 }, { 5118 }, { 13159 } } },
    { key = "trueshot", class = "HUNTER", self = true,
      lines = { { 19506, 20905, 20906 } } },
}

-- Essen/Trinken beim Haendler gibt es in Stufen-Abschnitten: so erkennt das Addon,
-- ob fuer deine Stufe etwas Besseres moeglich waere.
ns.FOOD_TIERS = { 1, 5, 15, 25, 35, 45 }

-- Zauber, deren Namen Essen bzw. Trinken kennzeichnen (Name in der Spielsprache)
ns.FOOD_SPELL = 433
ns.DRINK_SPELL = 430

ns.SOUL_SHARD = 6265

-- Schamanen-Waffenverzauberungen (alle Raenge), Reihenfolge = Vorzug beim Klick
ns.SHAMAN_IMBUES = {
    { 8232, 8235, 10486, 16362 },                      -- Windzorn
    { 8024, 8027, 8030, 16339, 16341, 16342 },         -- Flammenzunge
    { 8033, 8038, 10456, 16355, 16356 },               -- Frostbrand
    { 8017, 8018, 8019, 10399, 16314, 16315, 16316 },  -- Felsbeisser
}
