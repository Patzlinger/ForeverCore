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
    -- Erfahrung und Ruf: Blizzard zeigt in der ersten Statusleiste beim Leveln die Erfahrung,
    -- in der zweiten den beobachteten Ruf (ältere Namen als Ersatz)
    { key = "xp", textKey = "BAR_XP", kind = "container",
      frames = { "MainStatusTrackingBarContainer", "MainMenuExpBar" } },
    { key = "rep", textKey = "BAR_REP", kind = "container",
      frames = { "SecondaryStatusTrackingBarContainer", "ReputationWatchBar" } },
}

-- Standardwerte je Leiste. x/y = nil: Standardposition (wird beim ersten Anzeigen berechnet)
-- visibility: "ALWAYS", "COMBAT" (nur im Kampf), "NOCOMBAT" (nur außerhalb), "MOUSEOVER"
-- growX/growY: Wachstumsrichtung ("RIGHT"/"LEFT", "DOWN"/"UP"); flyout: Ausklapp-Richtung von Zauber-Gruppen
-- Sichtbarkeit: visibility = "ALWAYS"/"COMBAT"/"NOCOMBAT"; fade* = bei Maus darüber einblenden;
-- hide* = in bestimmten Situationen ausblenden; useCustom/custom = eigene Makro-Bedingung
local function BarDefaults(enabled, perRow)
    -- point: Ankerpunkt, auf den sich x/y beziehen (siehe Bars.lua)
    return { enabled = enabled, buttons = 12, perRow = perRow or 12, scale = 100, spacing = 1, point = "CENTER",
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
        xp = BarDefaults(true), rep = BarDefaults(true), queue = BarDefaults(true),
    },
    profiles = {},           -- gespeicherte Profile: [Name] = Kopie der Einstellungen (siehe Profiles.lua)
    activeProfile = "Default", -- aktives Profil; "Default" gibt es immer
    layoutVersion = 4,         -- Stand der Standard-Anordnung (siehe MigrateLayout)
    skin = "FLAT",           -- Aussehen der Knöpfe (ns.SKINS in Bars.lua)
    hoverAlpha = 15,         -- Stärke des Hover-Leuchtens über den Knöpfen (%)
    procGlow = "FOREVER",    -- Leuchten bei Procs: "FOREVER" (goldener Rahmen), "BLIZZARD", "OFF"
    hideOutOfCombat = false, -- alle Leisten außerhalb des Kampfes ausblenden
    showHotkeys = true,
    showMacroNames = false,
    showCounts = true,
    showGrid = true,
    snap = true,             -- beim Ziehen magnetisch an anderen Leisten / der Bildschirmmitte einrasten
    showBorder = true,       -- dünner Rand um die Knöpfe
    showEquipped = true,     -- grüner Rand bei ausgerüsteten Gegenständen
    iconZoom = 8,            -- Zuschnitt der Symbole in Prozent (0 = ganzes Symbol)
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
ns.defaults.bars.pet.scale = 50
ns.defaults.bars.pet.point = "BOTTOMLEFT"
ns.defaults.bars.stance.scale = 50
ns.defaults.bars.stance.point = "BOTTOMRIGHT"
ns.defaults.bars.stance.growX = "LEFT" -- erster Knopf rechts, damit die Leiste rechtsbündig wächst
ns.defaults.bars.prof.point = "BOTTOMRIGHT"
ns.defaults.bars.prof.frame = true
ns.defaults.bars.prof.scale = 80
-- Verpflegungsleiste: gespiegelt zur Berufeleiste rechts neben den Aktionsleisten, gleiche Größe, mit Rahmen
ns.defaults.bars.food.buttons = 12 -- festes Raster: 4 breit, 3 Reihen (Essen, Getränke, Fläschchen)
ns.defaults.bars.food.perRow = 4
ns.defaults.bars.food.foodExcluded = {} -- mit Shift herausgezogene Gegenstände
ns.defaults.bars.food.foodOrder = {}    -- je Reihe die selbst einsortierte Reihenfolge
ns.defaults.bars.food.point = "BOTTOMLEFT"
ns.defaults.bars.food.frame = true
ns.defaults.bars.food.scale = 80
ns.defaults.bars.prof.growX = "LEFT"
ns.defaults.bars.micro.point = "BOTTOMRIGHT"
ns.defaults.bars.bags.point = "BOTTOMRIGHT"
ns.defaults.bars.bags.growX = "LEFT"
ns.defaults.bars.xp.point = "TOP"
ns.defaults.bars.rep.point = "TOP"
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
local LAYOUT_VERSION = 4
function ns.MigrateLayout(db)
    local version = db.layoutVersion or 1
    if version >= LAYOUT_VERSION then return end
    db.layoutVersion = LAYOUT_VERSION
    if not db.bars then return end -- erster Start: es gelten ohnehin die Standardwerte
    -- Betroffen: das gespeicherte Standardprofil und, falls es aktiv ist, die aktuellen Einstellungen
    local targets = {}
    if db.profiles and db.profiles.Default and db.profiles.Default.bars then table.insert(targets, db.profiles.Default) end
    if (db.activeProfile or "Default") == "Default" then table.insert(targets, db) end
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
