local addonName, ns = ...
local L = ns.L

-- Vorangestellter Addon-Name für Chat-Meldungen (Gold wie alle Forever-Addons)
function ns.ChatPrefix()
    return "|cffffcc00" .. L("ADDON_NAME") .. "|r"
end

function ns.Print(text)
    print(ns.ChatPrefix() .. ": " .. text)
end

---------------------------------------------------------------------------
-- Die Leisten
-- buttons  = Namensanfang der Blizzard-Knöpfe (z. B. "ActionButton" -> ActionButton1 … ActionButton12)
-- count    = Anzahl Knöpfe
-- kind     = "action" (Aktionsknöpfe), "pet", "stance", "container" (ganze Blizzard-Leiste), "single"
-- blizzard = Blizzard-Leisten, die ForeverBars ausblendet (ihre Knöpfe wandern in die eigene Leiste)
---------------------------------------------------------------------------

ns.BAR_DEFS = {
    { key = "bar1", textKey = "BAR_1", kind = "action", buttons = "ActionButton", count = 12,
      blizzard = { "MainActionBar", "MainMenuBar" } },
    { key = "bar2", textKey = "BAR_2", kind = "action", buttons = "MultiBarBottomLeftButton", count = 12,
      blizzard = { "MultiBarBottomLeft" } },
    { key = "bar3", textKey = "BAR_3", kind = "action", buttons = "MultiBarBottomRightButton", count = 12,
      blizzard = { "MultiBarBottomRight" } },
    { key = "bar4", textKey = "BAR_4", kind = "action", buttons = "MultiBarRightButton", count = 12,
      blizzard = { "MultiBarRight" } },
    { key = "bar5", textKey = "BAR_5", kind = "action", buttons = "MultiBarLeftButton", count = 12,
      blizzard = { "MultiBarLeft" } },
    { key = "bar6", textKey = "BAR_6", kind = "action", buttons = "MultiBar5Button", count = 12,
      blizzard = { "MultiBar5" } },
    { key = "bar7", textKey = "BAR_7", kind = "action", buttons = "MultiBar6Button", count = 12,
      blizzard = { "MultiBar6" } },
    { key = "bar8", textKey = "BAR_8", kind = "action", buttons = "MultiBar7Button", count = 12,
      blizzard = { "MultiBar7" } },
    { key = "pet", textKey = "BAR_PET", kind = "pet", buttons = "PetActionButton", count = 10,
      blizzard = { "PetActionBar", "PetActionBarFrame" } },
    { key = "stance", textKey = "BAR_STANCE", kind = "stance", buttons = "StanceButton", count = 10,
      blizzard = { "StanceBar", "StanceBarFrame" } },
    -- Berufe: eigene Knöpfe (Bars.lua), belegt mit den Berufen und Berufs-Fähigkeiten des Charakters
    { key = "prof", textKey = "BAR_PROF", titleKey = "PROF_FRAME_TITLE", kind = "prof",
      buttons = "ForeverBarsProfButton", count = 12 },
    -- Verpflegung: Essen, Getränke, Fläschchen/Elixiere/Tränke aus den Taschen (Bars.lua)
    { key = "food", textKey = "BAR_FOOD", titleKey = "FOOD_FRAME_TITLE", kind = "food",
      buttons = "ForeverBarsFoodButton", count = 18 },
    { key = "micro", textKey = "BAR_MICRO", kind = "container", frames = { "MicroMenuContainer", "MicroMenu" } },
    -- Taschen: einzelne Taschenknöpfe (Rucksack, Taschen, Reagenzientasche, Schlüsselbund) in eigener Anordnung
    { key = "bags", textKey = "BAR_BAGS", kind = "bags", blizzard = { "BagsBar" },
      bagButtons = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
                     "CharacterBag3Slot", "CharacterReagentBag0Slot" } },
    { key = "vehicle", textKey = "BAR_VEHICLE", kind = "single", frames = { "MainMenuBarVehicleLeaveButton" } },
    -- Warteschlangen-Auge (Gruppensuche, Schlachtfeld); Blizzard setzt es mit UpdatePosition gern zurück
    { key = "queue", textKey = "BAR_QUEUE", kind = "single", frames = { "QueueStatusButton" },
      hookMethods = { "UpdatePosition" }, minSize = 45 },
    -- (Erfahrungs- und Rufleiste gehören seit 0.44b ForeverXP; Stand davor: Git-Markierung snapshot-vor-xp-rep-umbau)
}

-- Standardwerte je Leiste. x/y = nil: Standardposition (wird beim ersten Anzeigen berechnet)
-- visibility: "ALWAYS", "COMBAT" (nur im Kampf), "NOCOMBAT" (nur außerhalb), "MOUSEOVER"
-- growX/growY: Wachstumsrichtung ("RIGHT"/"LEFT", "DOWN"/"UP"); flyout: Ausklapp-Richtung von Zauber-Gruppen
-- Sichtbarkeit: visibility = "ALWAYS"/"COMBAT"/"NOCOMBAT"; fade* = bei Maus darüber einblenden;
-- hide* = in bestimmten Situationen ausblenden; useCustom/custom = eigene Makro-Bedingung
local function BarDefaults(enabled, perRow)
    -- point: Ankerpunkt, auf den sich x/y beziehen (siehe Bars.lua)
    return { enabled = enabled, buttons = 12, perRow = perRow or 12, scale = 105, spacing = 1.5, point = "CENTER",
             profRows = true, -- nur Berufeleiste: Berufe oben, Fertigkeiten unten
             alpha = 100, visibility = "ALWAYS", growX = "RIGHT", growY = "DOWN", flyout = "UP",
             onlyBackpack = false, keyring = false,
             fadeMouseover = false, fadeInCombat = true, fadeAlpha = 0, fadeDelay = 1,
             -- Rahmen um die Leiste (wie die Fenster in ForeverQuests), wahlweise mit Titel
             frame = false, frameTitle = true, frameTitleText = "", -- leerer Titel = Name der Leiste
             hideVehicle = false, hideOverride = false, hidePossess = false,
             hidePet = false, hideNoPet = false, hideStance = false,
             useCustom = false, custom = "" }
end

-- Schriftarten, die in jedem WoW-Client vorhanden sind
ns.FONTS = {
    { key = "STANDARD", textKey = "FONT_STANDARD", path = STANDARD_TEXT_FONT },
    { key = "ARIALN",   text = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "SKURRI",   text = "Skurri",       path = "Fonts\\skurri.ttf" },
    { key = "MORPHEUS", text = "Morpheus",     path = "Fonts\\MORPHEUS.TTF" },
}

ns.defaults = {
    version = 1,
    bars = {
        bar1 = BarDefaults(true), bar2 = BarDefaults(true), bar3 = BarDefaults(true),
        bar4 = BarDefaults(false, 1), bar5 = BarDefaults(false, 1),
        bar6 = BarDefaults(false), bar7 = BarDefaults(false), bar8 = BarDefaults(false),
        pet = BarDefaults(true, 10), stance = BarDefaults(true, 10), prof = BarDefaults(true, 12),
        food = BarDefaults(true, 6),
        -- (Haltungsleiste: "enabled" hängt von der Klasse ab, siehe ADDON_LOADED)
        micro = BarDefaults(true), bags = BarDefaults(true), vehicle = BarDefaults(true),
        queue = BarDefaults(true),
    },
    -- (Profile verwaltet seit 0.41b ForeverCore – je Charakter, siehe RegisterSettings am Ende dieser Datei)
    layoutVersion = 18,-- Stand der Standard-Anordnung (siehe MigrateLayout)
    skin = "FLAT",           -- Aussehen der Knöpfe (ns.SKINS in Bars.lua)
    hoverAlpha = 15,         -- Stärke des Hover-Leuchtens über den Knöpfen (%)
    procGlow = "FOREVER",    -- Leuchten bei Procs: "FOREVER" (goldener Rahmen), "BLIZZARD", "OFF"
    hideOutOfCombat = false, -- alle Leisten außerhalb des Kampfes abblenden (auf oocAlpha, Maus darüber = voll)
    oocAlpha = 30,           -- Deckkraft außerhalb des Kampfes (%)
    autoRankUp = true,       -- neu gelernten Rang automatisch auf die Aktionsknöpfe mit dem niedrigeren Rang legen
    showHotkeys = true,
    showMacroNames = false,
    showCounts = true,
    showGrid = true,
    snap = true,             -- beim Ziehen magnetisch an anderen Leisten / der Bildschirmmitte einrasten
    showBorder = true,       -- dünner Rand um die Knöpfe
    showEquipped = true,     -- grüner Rand bei ausgerüsteten Gegenständen
    iconZoom = 4,            -- Zuschnitt der Symbole in Prozent (0 = ganzes Symbol)
    font = "STANDARD",       -- Schrift der Knopftexte
    fontSize = 12,
    fontOutline = "OUTLINE", -- "NONE", "OUTLINE", "THICKOUTLINE"
    hotkeyPosition = "TOPRIGHT",
    buttonTooltip = "ALWAYS", -- Tooltip der Knöpfe: "ALWAYS", "NOCOMBAT" (nicht im Kampf), "NEVER"
    castVFX = true,           -- Zauber-Effekt auf den Knöpfen beim Zaubern
    showMinimapButton = true,
    minimapAngle = 200,       -- Position des Minimap-Symbols (Winkel in Grad)
}
ns.defaults.bars.pet.buttons = 10
ns.defaults.bars.stance.buttons = 10 -- Haltungsleiste zeigt immer so viele Knöpfe, wie der Charakter Haltungen hat
-- Standard-Anordnung (Positionen in Bars.lua, DefaultPosition): Begleiter- und Haltungsleiste halb so groß,
-- links bzw. rechts bündig über den Aktionsleisten; Berufeleiste mit Rahmen links daneben;
-- Menü und Taschen unten rechts; Erfahrung und Ruf oben mittig
ns.defaults.bars.pet.scale = 59
ns.defaults.bars.pet.point = "BOTTOMLEFT"
ns.defaults.bars.stance.scale = 59
ns.defaults.bars.stance.point = "BOTTOMRIGHT"
ns.defaults.bars.stance.growX = "LEFT" -- erster Knopf rechts, damit die Leiste rechtsbündig wächst
ns.defaults.bars.prof.point = "BOTTOMRIGHT"
ns.defaults.bars.prof.frame = true
ns.defaults.bars.prof.scale = 84
-- Verpflegungsleiste: gespiegelt zur Berufeleiste rechts neben den Aktionsleisten, gleiche Größe, mit Rahmen
ns.defaults.bars.food.buttons = 12 -- 12 Plätze, 4 breit und 3 hoch, frei belegbar
ns.defaults.bars.food.perRow = 4
ns.defaults.bars.food.point = "BOTTOMLEFT"
ns.defaults.bars.food.frame = true
ns.defaults.bars.food.scale = 84
ns.defaults.bars.prof.growX = "LEFT"
ns.defaults.bars.micro.point = "BOTTOMRIGHT"
ns.defaults.bars.micro.scale = 105  -- eigene flache Knöpfe statt Blizzards Mikromenü (angedockt: so breit wie die Karte)
ns.defaults.bars.micro.microOwn = true
-- Mit ForeverMinimap: unter der Karte und über dem Questtracker angedockt (zieht man es weg, ist es frei;
-- dort losgelassen rastet es wieder ein)
ns.defaults.bars.micro.dockMinimap = true
ns.defaults.bars.micro.microGrey = true -- nur für Blizzards Mikromenü (wenn die eigenen Knöpfe aus sind)
ns.defaults.bars.bags.scale = 160  -- Rucksack (und ausgeklappte Taschen) doppelt so groß wie früher (80 %)
ns.defaults.bars.micro.spacing = 0 -- Mikromenü-Knöpfe ohne Abstand
ns.defaults.bars.bags.point = "BOTTOMRIGHT"
ns.defaults.bars.bags.growX = "LEFT"
ns.defaults.bars.bags.collapsible = true   -- Pfeil zum Aus-/Einklappen der Taschen
ns.defaults.bars.bags.enabled = false      -- Taschenleiste standardmäßig aus (Taschen öffnen per Taste B)
-- Aktionsleisten: "100 %" sind bereits 105 % der Blizzard-Größe (siehe ns.BarScale in Bars.lua)
for i = 1, 8 do ns.defaults.bars["bar" .. i].scale = 100 end
ns.defaults.bars.bags.bagsCollapsed = true -- eingeklappt: nur der Rucksack
ns.defaults.bars.prof.buttons = 12 -- 12 Plätze, 6 breit und 2 hoch, frei belegbar
ns.defaults.bars.prof.perRow = 6
-- Berufe und Verpflegung: belegte Plätze, automatisch eingetragene, herausgezogene; Einklapp-Pfeil
for _, key in ipairs({ "prof", "food" }) do
    local bar = ns.defaults.bars[key]
    bar.slots, bar.slotsAuto, bar.excluded = {}, {}, {}
    bar.collapseArrow, bar.collapsed = true, false
end
-- Warteschlangen-Auge: standardmäßig aus (dann nicht zu sehen), eingeschaltet halb so groß
ns.defaults.bars.queue.enabled = false
ns.defaults.bars.queue.scale = 53
-- Leiste 1 macht in Fahrzeugen der Blizzard-Fahrzeugleiste Platz; die Begleiterleiste nur mit Begleiter
ns.defaults.bars.bar1.hideVehicle = true
ns.defaults.bars.bar1.hideOverride = true
ns.defaults.bars.pet.hideVehicle = true
ns.defaults.bars.pet.hideOverride = true
ns.defaults.bars.pet.hidePossess = true
ns.defaults.bars.pet.hideNoPet = true

-- Haltungsleiste standardmäßig nur bei Klassen mit Haltungen, Gestalten oder Auren
local STANCE_CLASSES = { WARRIOR = true, DRUID = true, ROGUE = true, PALADIN = true, PRIEST = true, DEATHKNIGHT = true }

-- Fehlende Werte aus den Standardwerten ergänzen (auch in verschachtelten Tabellen)
local function FillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            FillDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end
ns.FillDefaults = FillDefaults

-- Einmalige Anpassungen des Standardprofils (andere gespeicherte Profile bleiben unverändert):
--   2 (0.10.2): Vorlage "Standard (3 unten)" – alle Leisten auf Standard, Positionen neu berechnet
--   3 (0.10.3): Berufeleiste kleiner (80 %), Position neu berechnet
--   4 (0.11.1): Verpflegungsleiste 4 breit und 3 hoch, Position neu berechnet
--   5 (0.14.0): Begleiter-/Haltungsleiste etwas größer (56 %); Ränder benachbarter Knöpfe liegen jetzt
--               übereinander, darum Positionen der Standard-Anordnung neu berechnet
--   6 (0.15.0): Mikromenü und Taschenleiste kleiner (80 %), Positionen unten rechts neu berechnet
--   7 (0.15.1): Mikromenü 40 % und schwarz-weiß, Positionen unten rechts neu berechnet
--   8 (0.41b+): eigenes Mikromenü (Text-Knöpfe, 100 %), Positionen unten rechts neu berechnet
--   9 (0.41b+): Berufe/Verpflegung frei belegbar (Berufe 6 x 2, Verpflegung 4 x 3) mit Einklapp-Pfeil,
--               Positionen neu berechnet (mehr Abstand zu den Aktionsleisten für den Pfeil)
--  10 (0.41b+): breitere Einklapp-Pfeile, kleineres Mikromenü mit Symbolen – Positionen von Berufe-,
--               Verpflegungs-, Taschenleiste und Mikromenü neu berechnet
--  11 (0.41b+): noch breitere Einklapp-Pfeile – Positionen von Berufe- und Verpflegungsleiste neu berechnet
--  12 (0.41b+): Mikromenü ohne Abstand, Rucksack in Mikromenü-Größe direkt darüber
--  13 (0.41b+): Taschenleiste 20 % größer (76 %)
--  14 (0.41b+): im Standardprofil nichts am Chat angeheftet (Anheften nur per Häkchen)
--  15 (0.41b+): Warteschlangen-Auge aus und halb so groß (50 %)
--  16 (0.44b+): alles 5 % größer, Abstand 1,5, Mikromenü unter der Minimap angedockt (Anheften am Chat entfällt),
--               Positionen der Standard-Anordnung neu berechnet
--  17 (0.44b+): Taschenleiste doppelt so groß (160 %), Rucksack mit Blizzards Symbol
--  18 (0.44b+): Aktionsleisten-Größe neu gezählt (105 % heißen jetzt 100 %), Symbol-Zuschnitt 4 %, Taschenleiste aus
local LAYOUT_VERSION = 18
-- Standardgrößen vor 16 (nur Leisten, die noch darauf stehen, wachsen mit)
local OLD_SCALES = { pet = 56, stance = 56, prof = 80, food = 80, bags = 76, queue = 50 }
local STANDARD_LAYOUT_BARS = { "bar1", "bar2", "bar3", "bar6", "bar7", "bar8", "pet", "stance", "prof", "food",
                               "micro", "bags", "vehicle" }
function ns.MigrateLayout(db)
    local version = db.layoutVersion or 1
    if version >= LAYOUT_VERSION then return end
    db.layoutVersion = LAYOUT_VERSION
    if not db.bars then return end -- erster Start: es gelten ohnehin die Standardwerte
    -- Betroffen: das gespeicherte Standardprofil und, falls es aktiv ist, die aktuellen Einstellungen
    -- (Profile liegen seit 0.41b in db._fc, verwaltet von ForeverCore)
    local targets = {}
    local fc = type(db._fc) == "table" and db._fc or {}
    local stored = type(fc.profiles) == "table" and fc.profiles.Default
    if stored and stored.bars then table.insert(targets, stored) end
    if (fc.active or "Default") == "Default" then table.insert(targets, db) end
    for _, target in ipairs(targets) do
        if version < 2 then
            target.bars = CopyTable(ns.defaults.bars)
        else
            if version < 3 and target.bars.prof then
                target.bars.prof.scale = ns.defaults.bars.prof.scale
                target.bars.prof.x, target.bars.prof.y = nil, nil
            end
            if version < 4 and target.bars.food then
                target.bars.food.perRow = ns.defaults.bars.food.perRow
                target.bars.food.buttons = ns.defaults.bars.food.buttons
                target.bars.food.x, target.bars.food.y = nil, nil
            end
            if version < 5 then
                for _, key in ipairs({ "pet", "stance" }) do
                    local bar = target.bars[key]
                    if bar and (bar.scale == 50 or bar.scale == nil) then bar.scale = ns.defaults.bars[key].scale end
                end
                for _, key in ipairs(STANDARD_LAYOUT_BARS) do
                    local bar = target.bars[key]
                    if bar then bar.x, bar.y = nil, nil end
                end
            end
            if version < 6 then
                for _, key in ipairs({ "micro", "bags" }) do
                    local bar = target.bars[key]
                    if bar then
                        if bar.scale == nil or bar.scale == 100 then bar.scale = ns.defaults.bars[key].scale end
                        bar.x, bar.y = nil, nil
                    end
                end
            end
            if version < 7 and target.bars.micro then
                local micro = target.bars.micro
                if micro.scale == nil or micro.scale == 100 or micro.scale == 80 then
                    micro.scale = ns.defaults.bars.micro.scale
                end
                micro.x, micro.y = nil, nil
                if target.bars.bags then target.bars.bags.x, target.bars.bags.y = nil, nil end
            end
            if version < 8 and target.bars.micro then
                local micro = target.bars.micro
                -- 40 % war für Blizzards große Menüknöpfe gedacht; die eigenen Text-Knöpfe brauchen 100 %
                if micro.scale == nil or micro.scale == 40 or micro.scale == 80 then
                    micro.scale = ns.defaults.bars.micro.scale
                end
                micro.x, micro.y = nil, nil
                if target.bars.bags then target.bars.bags.x, target.bars.bags.y = nil, nil end
            end
            if version < 9 then
                for _, key in ipairs({ "prof", "food" }) do
                    local bar = target.bars[key]
                    if bar then
                        bar.buttons = ns.defaults.bars[key].buttons
                        bar.perRow = ns.defaults.bars[key].perRow
                        bar.x, bar.y = nil, nil
                    end
                end
            end
            if version < 18 then
                for i = 1, 8 do
                    local bar = target.bars["bar" .. i]
                    -- 105 % (Stand 16) = neue 100 %; ältere Stände (100 %) wachsen damit ebenfalls auf 105 %
                    if bar and (bar.scale == nil or bar.scale == 105 or bar.scale == 100) then bar.scale = 100 end
                end
                if target.iconZoom == nil or target.iconZoom == 8 then target.iconZoom = 4 end
                if target.bars.bags then target.bars.bags.enabled = false end
            end
            if version < 17 and target.bars.bags then
                local bags = target.bars.bags
                -- 76/80 = alte Standardgrößen (die Umrechnung auf 16 läuft gleich danach und darf nicht mehr greifen)
                if bags.scale == nil or bags.scale == 76 or bags.scale == 80 then bags.scale = ns.defaults.bars.bags.scale end
                bags.x, bags.y = nil, nil
            end
            if version < 16 then
                for key, bar in pairs(target.bars) do
                    local default = ns.defaults.bars[key]
                    if type(bar) == "table" and default then
                        if bar.scale == nil or bar.scale == (OLD_SCALES[key] or 100) then bar.scale = default.scale end
                        if key ~= "micro" and (bar.spacing == nil or bar.spacing == 1) then bar.spacing = default.spacing end
                        bar.attachChat = nil
                    end
                end
                if target.bars.micro then target.bars.micro.dockMinimap = true end
                for _, key in ipairs(STANDARD_LAYOUT_BARS) do
                    local bar = target.bars[key]
                    if bar then bar.x, bar.y = nil, nil end
                end
            end
            if version < 15 and target.bars.queue then
                local queue = target.bars.queue
                queue.enabled = false
                if queue.scale == nil or queue.scale == 100 then queue.scale = ns.defaults.bars.queue.scale end
            end
            -- (14: Anheften am Chat ausgeschaltet – entfällt seit 16 ganz, siehe oben)
            if version < 13 and target.bars.bags then
                local bags = target.bars.bags
                if bags.scale == nil or bags.scale == 63 or bags.scale == 80 or bags.scale == 100 then
                    bags.scale = ns.defaults.bars.bags.scale
                end
                bags.x, bags.y = nil, nil
            end
            if version < 12 then
                local micro, bags = target.bars.micro, target.bars.bags
                if micro then
                    if micro.spacing == nil or micro.spacing == 1 then micro.spacing = ns.defaults.bars.micro.spacing end
                    micro.x, micro.y = nil, nil
                end
                if bags then
                    if bags.scale == nil or bags.scale == 80 or bags.scale == 100 then bags.scale = ns.defaults.bars.bags.scale end
                    bags.x, bags.y = nil, nil
                end
            end
            if version < 11 then
                -- (10 und 11) Positionen neu berechnen; Mikromenü und Taschen nur, wenn von 10 noch nicht erledigt
                local keys = version < 10 and { "prof", "food", "micro", "bags" } or { "prof", "food" }
                for _, key in ipairs(keys) do
                    local bar = target.bars[key]
                    if bar then bar.x, bar.y = nil, nil end
                end
            end
        end
    end
end

-- Ältere Einstellungen speichern die Mitte der Leiste: diese Bedeutung behalten (sonst springen Leisten),
-- erst danach fehlende Werte aus den Standardwerten ergänzen
function ns.MigrateBars(bars)
    for _, cfg in pairs(bars or {}) do
        if type(cfg) == "table" and cfg.point == nil and cfg.x ~= nil then cfg.point = "CENTER" end
    end
end

---------------------------------------------------------------------------
-- Blizzard-Einstellungen (vom Spiel selbst gespeichert, daher unabhängig vom SavedVariables-Bug)
---------------------------------------------------------------------------

function ns.HasCVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) ~= nil end
    return GetCVar and GetCVar(name) ~= nil
end

function ns.GetCVarBool(name)
    if C_CVar and C_CVar.GetCVarBool then return C_CVar.GetCVarBool(name) and true or false end
    return GetCVarBool and GetCVarBool(name) and true or false
end

function ns.SetCVarBool(name, value)
    local text = value and "1" or "0"
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, text) elseif SetCVar then SetCVar(name, text) end
end

-- Zusatztaste für eine Blizzard-Aktion ("SELFCAST", "FOCUSCAST", "MOUSEOVERCAST"): "NONE", "ALT", "CTRL", "SHIFT"
function ns.GetModifier(action)
    local value = GetModifiedClick and GetModifiedClick(action)
    return value and value ~= "" and value or "NONE"
end

function ns.SetModifier(action, value)
    if not SetModifiedClick then return end
    SetModifiedClick(action, value)
    -- Zusatztasten gehören zu den Tastenbelegungen und müssen dort gespeichert werden
    local save = SaveBindings or AttemptToSaveBindings
    if save then save(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
end

function ns.ResetBar(key)
    ns.db.bars[key] = CopyTable(ns.defaults.bars[key])
    ns.RequestLayout()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        local _, class = UnitClass("player")
        ns.defaults.bars.stance.enabled = STANCE_CLASSES[class] or false
        -- Wegen des Beta-Bugs (SavedVariables werden nicht geladen) gelten notfalls die Standardwerte
        ForeverBarsDB = ForeverBarsDB or {}
        ns.MigrateBars(ForeverBarsDB.bars)
        ns.MigrateLayout(ForeverBarsDB)
        FillDefaults(ForeverBarsDB, ns.defaults)
        ns.db = ForeverBarsDB
        -- Frühere Einstellung "Nur bei Maus darüber" ist jetzt das Einblenden bei Maus darüber
        for _, cfg in pairs(ns.db.bars) do
            if cfg.visibility == "MOUSEOVER" then
                cfg.visibility = "ALWAYS"
                cfg.fadeMouseover = true
            end
        end
        self:UnregisterEvent("ADDON_LOADED")
        ns.InitProfiles()
    elseif event == "PLAYER_LOGOUT" then
        -- Aktuelle Einstellungen im aktiven Profil sichern
        if ns.SaveActiveProfile then ns.SaveActiveProfile() end
    elseif event == "PLAYER_LOGIN" then
        -- Nochmals ergänzen: ForeverCore schreibt beim Laden das Profil in dieselbe Tabelle; lief das nach uns
        -- (z. B. nach "Zurücksetzen"), fehlten sonst Werte
        FillDefaults(ns.db, ns.defaults)
        ns.CreateMinimapButton()
        -- Läuft Bartender4, lässt ForeverBars die Leisten in Ruhe (zwei Leisten-Addons stören sich)
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
        if isLoaded and isLoaded("Bartender4") then
            ns.disabledByBartender = true
            ns.Print(L("BARTENDER_ACTIVE"))
            return
        end
        ns.SetupBars()
    end
end)

---------------------------------------------------------------------------
-- Chatbefehl und Tastenkürzel
---------------------------------------------------------------------------

SLASH_FOREVERBARS1 = "/fb"
SLASH_FOREVERBARS2 = "/foreverbars"
SlashCmdList.FOREVERBARS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "move" or msg == "unlock" then
        ns.SetUnlocked(not ns.unlocked)
    elseif msg == "test" then
        if ns.SetTestMode then ns.SetTestMode(not ns.testMode) end
    elseif msg == "kb" or msg == "keybind" then
        ns.OpenKeybindMode()
    else
        ns.ToggleOptions()
    end
end

-- Blizzard-Menü "Tastaturbelegung" > "AddOns" (Belegungen stehen in Bindings.xml)
BINDING_HEADER_FOREVERBARS = L("BINDING_HEADER")
BINDING_NAME_FOREVERBARS_OPTIONS = L("BINDING_OPTIONS")
BINDING_NAME_FOREVERBARS_UNLOCK = L("BINDING_UNLOCK")
-- Verpflegungsleiste: je Platz eine Belegung (siehe Bindings.xml); bei 4 je Reihe: 1-4 Essen, 5-8 Getränke,
-- 9-12 Fläschchen/Tränke
BINDING_HEADER_FOREVERBARS_FOOD = L("BINDING_HEADER_FOOD")
for i = 1, 18 do
    _G["BINDING_NAME_CLICK ForeverBarsFoodButton" .. i .. ":LeftButton"] = L("BINDING_FOOD", i)
end
function ForeverBars_ToggleOptions() if ns.ToggleOptions then ns.ToggleOptions() end end
function ForeverBars_ToggleUnlock() if ns.SetUnlocked then ns.SetUnlocked(not ns.unlocked) end end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
ForeverHub.UI.RegisterSettings({
    addon = addonName, sv = "ForeverBarsDB", defaults = ns.defaults, version = 1,
    -- Minimap-Symbol und Stand der Standard-Anordnung gelten fuer alle Profile
    global = { "showMinimapButton", "layoutVersion", "version" },
    -- Profile aelterer Stande: Leisten-Einstellungen umrechnen (wie frueher beim Laden eines Profils)
    migrate = function(data) if ns.MigrateBars then ns.MigrateBars(data.bars) end end,
    -- eigenes Zuruecksetzen (sofort, ohne Neuladen; Positionen neu berechnet)
    reset = function() if ns.ResetAllSettings then ns.ResetAllSettings() end end,
    -- bis 0.32b hatte ForeverBars eigene Profile (profiles/activeProfile, aktiv fuer alle Charaktere):
    -- uebernehmen; das bisher aktive Profil wird das gemeinsame Profil aller Charaktere
    legacy = function(live, fc)
        if type(live.profiles) == "table" then
            for name, data in pairs(live.profiles) do
                if type(name) == "string" and type(data) == "table" then fc.profiles[name] = data end
            end
        end
        if type(live.activeProfile) == "string" then
            fc.shared = live.activeProfile
            fc.active = live.activeProfile
        end
        live.profiles, live.activeProfile = nil, nil
    end,
})