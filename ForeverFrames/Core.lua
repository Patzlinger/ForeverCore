-- ForeverFrames: schlanke Gruppen-/Raidrahmen im Stil von Cell, gebaut fuer WoW Forever
-- Core.lua: Einstellungen, Hilfsfunktionen, Ereignis-Verteiler
local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Sprache: deutscher Client auf Deutsch, alle anderen auf Englisch
---------------------------------------------------------------------------
ns.UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
ns.IS_DE = ns.UI.IS_DE
ns.T = ns.UI.T
local T = ns.T

---------------------------------------------------------------------------
-- Einstellungen (SavedVariables)
---------------------------------------------------------------------------
ns.DEFAULTS = {
    -- Rahmen / Anordnung (gesperrt starten; entsperren per Menue, Minimap-Rechtsklick oder /fmove)
    locked = true,
    gridShow = true,      -- Raster beim Ziehen / bei offenen Einstellungen (nur entsperrt)
    gridSize = 32,
    snap = true,          -- an anderen Forever-Rahmen, Bildschirmmitte und Raster einrasten
    scale = 1,
    width = 80,
    height = 44,
    spacing = 3,          -- Abstand zwischen zwei Spielern
    groupSpacing = 6,     -- Abstand zwischen zwei Gruppen
    growth = "DOWN",      -- "DOWN": Spieler untereinander, Gruppen nebeneinander; "RIGHT": umgekehrt
    groupsPerRow = 8,     -- nach so vielen Gruppen wird umgebrochen
    showSolo = true,
    sortByRole = false,               -- innerhalb der Gruppe: Tank > Heiler > Schaden
    showPlayer = true,
    hideBlizzParty = true,
    hideBlizzRaid = true,
    hideBlizzManager = false,
    rangeFade = true,
    rangeAlpha = 0.35,
    tooltip = true,

    -- Optik
    texture = "raid",
    barColorMode = "class",          -- "class" | "custom"
    healthGradient = false,          -- Lebensbalken bei wenig Leben orange / rot faerben
    barColor = { 0.2, 0.75, 0.3 },
    lossColorMode = "dark",          -- "dark" (dunkle Klassenfarbe) | "custom"
    lossColor = { 0.12, 0.12, 0.12 },
    borderColor = { 0, 0, 0, 1 },
    borderSize = 1,
    powerMode = "all",               -- "all" | "mana" | "none"
    powerHeight = 4,
    healPrediction = true,
    healColor = { 0.3, 1, 0.45, 0.45 },
    shields = true,
    shieldColor = { 0.85, 0.95, 1, 0.5 },
    shieldStyle = "after",           -- "after": hinter den Lebenspunkten | "right": von rechts über die Leiste
    healAbsorbs = true,
    healAbsorbColor = { 1, 0.1, 0.1, 0.55 },
    targetHighlight = true,
    targetColor = { 1, 0.85, 0.2, 1 },
    mouseoverHighlight = true,
    aggroBorder = true,
    aggroColor = { 1, 0.1, 0.1, 1 },

    -- Schrift
    font = "friz",
    fontOutline = "OUTLINE",         -- "" | "OUTLINE" | "THICKOUTLINE"
    fontShadow = false,

    -- Name
    -- Aufteilung: oberes Drittel Name, Mitte Lebenspunkte, unteres Drittel frei fuer Symbole
    nameShow = true, nameSize = 11, namePoint = "TOP", nameX = 0, nameY = -4,
    nameColorMode = "white", nameColor = { 1, 1, 1 }, nameMaxChars = 0,
    -- Lebenspunkte-Text
    hpShow = true, hpFormat = "percent", hpSize = 10, hpPoint = "CENTER", hpX = 0, hpY = 2,
    hpColorMode = "white", hpColor = { 1, 1, 1 }, hpShort = true, hpHideFull = true,
    -- Energie-Text
    powerTextShow = false, powerTextFormat = "percent", powerTextSize = 8,
    powerTextPoint = "BOTTOMRIGHT", powerTextX = -2, powerTextY = 6,
    -- Status (Tot / Offline / AFK)
    statusShow = true, statusSize = 10, statusPoint = "CENTER", statusX = 0, statusY = 2,

    -- Symbole
    roleShow = true, roleSize = 11, rolePoint = "TOPLEFT", roleX = 2, roleY = -2, roleHideDamager = true,
    leaderShow = true, leaderSize = 11, leaderPoint = "TOPRIGHT", leaderX = -2, leaderY = -2,
    markShow = true, markSize = 14, markPoint = "TOP", markX = 0, markY = 5,
    readyShow = true, readySize = 18, readyPoint = "CENTER", readyX = 0, readyY = 0,
    incomingShow = true,              -- Symbol fuer Wiederbelebung / Beschwoerung unterwegs

    -- Debuffs
    debuffMode = "all",               -- "all" | "dispellable" | "off"
    debuffNum = 3, debuffSize = 14, debuffPoint = "BOTTOMLEFT", debuffX = 2, debuffY = 6, debuffGrow = "RIGHT",
    debuffTypeBorder = true,          -- Rand am Symbol in Typfarbe
    debuffCooldown = true,
    auraTimerSwipe = true,            -- Countdown-Scheibe auf Debuff-/Buff-Symbolen
    auraTimerNumbers = true,          -- Restzeit als Zahl
    auraTimerSize = 9,
    dispelShow = true,                -- Typ-Symbol fuer bannbare Debuffs
    dispelSize = 14, dispelPoint = "RIGHT", dispelX = -2, dispelY = 2,
    dispelBorder = true,              -- Rahmen um den Button in Typfarbe
    dispelBorderSize = 2,
    dispelOnlyMine = true,            -- nur Debuffs, die ICH bannen kann
    colorMagic = { 0.2, 0.6, 1 },
    colorCurse = { 0.6, 0, 1 },
    colorDisease = { 0.6, 0.4, 0 },
    colorPoison = { 0, 0.6, 0 },
    colorBleed = { 1, 0.2, 0.2 },
    colorNone = { 0.5, 0, 0 },
    -- Buffs
    buffMode = "hots",                -- "hots" | "custom" | "both" | "off"
    buffNum = 3, buffSize = 14, buffPoint = "BOTTOMRIGHT", buffX = -2, buffY = 6, buffGrow = "LEFT",
    buffCooldown = true,
    buffCustomMine = true,            -- eigene Liste: nur von mir gewirkte Buffs
    buffOthers = true,                -- auch HoTs/Schutz-Buffs anderer Spieler (alle Klassen) zeigen
    buffCustom = {},                  -- [KLASSE] = "Erneuerung, Verjüngung, 774"
    auraTooltip = true,               -- Tooltip beim Drueberfahren (Klicks gehen trotzdem durch)
    auraEngine = true,                -- Blizzard-Anzeige (AuraContainer): Spiel zeichnet Auren, auch im Kampf
    buffEngineShort = false,          -- Blizzard-Anzeige: zusaetzlich weitere kurze eigene Buffs (< 2 Min.)

    -- Begleiter (Pet)
    petShow = true,
    petPosition = "RIGHT",            -- "RIGHT" | "LEFT" (neben dem Besitzer) | "INSIDE" (im Rahmen, rechts)
    petWidth = 12,
    petLabel = "name",                -- "none" | "pet" | "name" (senkrecht)
    petLabelSize = 8,
    petGap = 1,
    petColorMode = "custom",          -- "custom" | "owner" (Klassenfarbe des Besitzers)
    petColor = { 0.35, 0.8, 0.35 },
    petReverse = false,               -- false: fehlende LP verschwinden oben

    minimapAngle = 220,
    clicks = {}, -- [KLASSE] = { { button = 1, mod = "", action = "target", value = "" }, ... }
}

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = CopyValue(x) end
    return t
end
ns.CopyValue = CopyValue

-- Wegen des Beta-Bugs wird ForeverFramesDB bei jedem Zugriff neu geprueft;
-- fehlende Werte werden mit den Standardwerten aufgefuellt.
-- "__fresh" markiert eine selbst angelegte (also NICHT geladene) Tabelle.
local db
function ns.GetDB()
    if type(_G.ForeverFramesDB) ~= "table" then
        _G.ForeverFramesDB = db or { __fresh = true }
    end
    db = _G.ForeverFramesDB
    for k, v in pairs(ns.DEFAULTS) do
        if db[k] == nil then db[k] = CopyValue(v) end
    end
    return db
end

-- Farbe aus den Einstellungen als r, g, b, a
function ns.Color(key)
    local c = ns.GetDB()[key] or ns.DEFAULTS[key]
    return c[1], c[2], c[3], c[4] or 1
end

---------------------------------------------------------------------------
-- Auswahllisten
---------------------------------------------------------------------------
ns.TEXTURES = {
    { key = "raid",     label = T("Raid (Blizzard)", "Raid (Blizzard)"), path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "flat",     label = T("Flach", "Flat"),       path = "Interface\\Buttons\\WHITE8x8" },
    { key = "blizzard", label = "Blizzard",               path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "raidres",  label = T("Raid-Ressource (Blizzard)", "Raid resource (Blizzard)"), path = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill" },
    { key = "skills",   label = T("Fertigkeiten-Balken", "Skills bar"), path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
    { key = "barfill",  label = T("Zielrahmen-Füllung", "Target frame fill"), path = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
    { key = "gradient", label = T("Verlauf", "Gradient"), path = "Interface\\Buttons\\GreyscaleRamp64" },
    { key = "tooltip",  label = T("Weich (Tooltip)", "Soft (tooltip)"), path = "Interface\\Tooltips\\UI-Tooltip-Background" },
}

ns.FONTS = {
    { key = "friz",     label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn",   label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus", label = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri",   label = "Skurri",        path = "Fonts\\SKURRI.TTF" },
    { key = "2002",     label = "2002",          path = "Fonts\\2002.TTF" },
    { key = "2002b",    label = T("2002 Fett", "2002 Bold"), path = "Fonts\\2002B.TTF" },
}

-- Weitere Texturen und Schriften von anderen Addons (Details, Plater, Questie ... bringen
-- "LibSharedMedia" mit). Gespeichert als "lsm:Name"; fehlt das Addon spaeter, gilt der Standard.
local function SharedMedia()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function WithSharedMedia(builtIn, mediaType)
    local list, seen = {}, {}
    for _, e in ipairs(builtIn) do
        list[#list + 1] = e
        seen[e.label] = true
    end
    local lsm = SharedMedia()
    if lsm then
        for _, name in ipairs(lsm:List(mediaType)) do
            if not seen[name] then
                list[#list + 1] = { key = "lsm:" .. name, label = name }
            end
        end
    end
    return list
end

function ns.TextureChoices() return WithSharedMedia(ns.TEXTURES, "statusbar") end
function ns.FontChoices() return WithSharedMedia(ns.FONTS, "font") end

local function SharedPath(key, mediaType)
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = SharedMedia()
        return lsm and lsm:Fetch(mediaType, key:sub(5), true)
    end
end

ns.OUTLINES = {
    { key = "",             label = T("Ohne", "None") },
    { key = "OUTLINE",      label = T("Umriss", "Outline") },
    { key = "THICKOUTLINE", label = T("Dicker Umriss", "Thick outline") },
}

ns.POINTS = {
    { key = "TOPLEFT",     label = T("Oben links", "Top left") },
    { key = "TOP",         label = T("Oben", "Top") },
    { key = "TOPRIGHT",    label = T("Oben rechts", "Top right") },
    { key = "LEFT",        label = T("Links", "Left") },
    { key = "CENTER",      label = T("Mitte", "Center") },
    { key = "RIGHT",       label = T("Rechts", "Right") },
    { key = "BOTTOMLEFT",  label = T("Unten links", "Bottom left") },
    { key = "BOTTOM",      label = T("Unten", "Bottom") },
    { key = "BOTTOMRIGHT", label = T("Unten rechts", "Bottom right") },
}

local function FindPath(list, key)
    for _, e in ipairs(list) do
        if e.key == key then return e.path end
    end
    return list[1].path
end

function ns.TexturePath()
    local key = ns.GetDB().texture
    return SharedPath(key, "statusbar") or FindPath(ns.TEXTURES, key)
end

function ns.FontPath()
    local key = ns.GetDB().font
    return SharedPath(key, "font") or FindPath(ns.FONTS, key)
end

-- Fuer ForeverUnits: aktuelle Optik zum Angleichen der Einheitenrahmen
function _G.ForeverFramesLook()
    local db = ns.GetDB()
    return {
        texture = ns.TexturePath(), font = ns.FontPath(),
        outline = db.fontOutline, shadow = db.fontShadow,
        borderColor = db.borderColor, borderSize = db.borderSize,
        barColorMode = db.barColorMode, barColor = db.barColor,
        lossColorMode = db.lossColorMode == "custom" and "custom" or "dark", lossColor = db.lossColor,
        healPrediction = db.healPrediction, shields = db.shields, healAbsorbs = db.healAbsorbs,
        healColor = db.healColor, shieldColor = db.shieldColor, healAbsorbColor = db.healAbsorbColor,
    }
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
-- "Geheime Werte" (secret values): im Kampf gesperrte Zahlen/Texte.
-- Mit ihnen darf nicht gerechnet oder verglichen werden.
local issecret = issecretvalue or function() return false end
function ns.IsSecret(...)
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return true end
    end
    return false
end
local IsSecret = ns.IsSecret

function ns.Chat(text)
    ns.UI.Chat("ForeverFrames", text)
end

-- Fehlerschutz (gemeinsam im ForeverHub): ein Fehler in einem Teil legt nicht das ganze Addon lahm.
-- Jeder Fehler wird nur EINMAL pro Stelle im Chat gemeldet (und an BugSack weitergegeben).
ns.errorCount = 0
function ns.ReportError(where, err)
    ns.errorCount = ns.errorCount + 1
    ns.UI.ReportError(ADDON_NAME, where, err)
end

function ns.Safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.ReportError(where, err) end
    end
end

-- Klassenfarbe einer Einheit (grau, wenn unbekannt)
function ns.ClassColor(unit)
    local _, class = UnitClass(unit)
    if not IsSecret(class) and class then
        local c = (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        if c then return c.r, c.g, c.b end
    end
    return 0.5, 0.5, 0.5
end

function ns.ClassColorByFile(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 0.5, 0.5, 0.5
end

-- Text auf n Zeichen kuerzen (UTF-8-sicher, damit Umlaute nicht zerbrechen)
function ns.Utf8Sub(s, n)
    if not n or n <= 0 then return s end
    local count, i, len = 0, 1, #s
    while i <= len do
        count = count + 1
        if count > n then return s:sub(1, i - 1) end
        local c = s:byte(i)
        if c >= 240 then i = i + 4 elseif c >= 224 then i = i + 3 elseif c >= 192 then i = i + 2 else i = i + 1 end
    end
    return s
end

-- Zahl kurz: 12.3K / 1.2M (nimmt auch geheime Werte)
function ns.ShortNumber(v)
    if AbbreviateNumbers then return AbbreviateNumbers(v) end
    return tostring(v)
end

---------------------------------------------------------------------------
-- Aenderungen an sicheren Rahmen sind im Kampf verboten:
-- dann wird die Aufgabe gemerkt und nach dem Kampf ausgefuehrt (Warteschlange im ForeverHub).
---------------------------------------------------------------------------
function ns.OutOfCombat(key, fn)
    return ns.UI.AfterCombat(ADDON_NAME .. ":" .. tostring(key), fn, ADDON_NAME)
end

---------------------------------------------------------------------------
-- Ereignis-Verteiler (jeder Empfaenger einzeln abgesichert)
---------------------------------------------------------------------------
local handlers = {}
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame

function ns.On(event, where, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- Abgesichert: gibt es ein Event auf diesem Client nicht, wird es uebersprungen
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    tinsert(handlers[event], { where = where, fn = fn })
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local h = list[i]
        local ok, err = pcall(h.fn, ...)
        if not ok then ns.ReportError(h.where or event, err) end
    end
end)


ns.savedVarsLoaded = nil
ns.On("ADDON_LOADED", "Laden", function(name)
    if name ~= ADDON_NAME then return end
    ns.savedVarsLoaded = type(_G.ForeverFramesDB) == "table" and not _G.ForeverFramesDB.__fresh
    ns.GetDB().__fresh = nil
end)

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
ns.UI.RegisterSettings({ addon = "ForeverFrames", sv = "ForeverFramesDB", defaults = ns.DEFAULTS, version = 1,
    keepOnReset = { "clicks", "buffCustom" } })
