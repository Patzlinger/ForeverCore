-- ForeverUnits: schlanke Einheitenrahmen (Spieler, Ziel, Ziel des Ziels, Fokus, Begleiter)
-- Core.lua: Einstellungen, Optik (eigene oder von ForeverFrames), Hilfsfunktionen, Ereignis-Verteiler
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
ns.UI = UI
local T = UI.T
ns.T = T

---------------------------------------------------------------------------
-- Die Rahmen
---------------------------------------------------------------------------
ns.UNITS = {
    { key = "player",       unit = "player",       label = T("Spieler", "Player") },
    { key = "target",       unit = "target",       label = T("Ziel", "Target") },
    { key = "targettarget", unit = "targettarget", label = T("Ziel des Ziels", "Target of target") },
    { key = "focus",        unit = "focus",        label = T("Fokus", "Focus") },
    { key = "pet",          unit = "pet",          label = T("Begleiter", "Pet") },
}

-- Einstellungen pro Rahmen
local function FrameDefaults(o)
    local d = {
        enabled = true, width = 200, height = 40, x = 0, y = 0,
        powerHeight = 12, fontSize = 12, -- 12 px: die Zahl (Schrift passt sich der Balkenhöhe an) bleibt lesbar
        portrait = "class",       -- "none" | "class" (Klassensymbol, NPCs: 2D-Porträt) | "portrait" (2D-Porträt)
        portraitSide = "LEFT",    -- "LEFT" | "RIGHT"
        nameShow = true, levelShow = false,
        classIcon = true,         -- Symbol für Elite/Rar/Boss (Blizzards Drache bzw. Stern) oben rechts am Rahmen
        hpFormat = "curpercent",  -- "none" | "percent" | "cur" | "curmax" | "curpercent" | "deficit"
        powerText = true,
        buffs = false, debuffs = false, onlyMine = true, auraSize = 20, auraNum = 8,
        dotBars = false, dotNum = 6, dotHeight = 16, -- DoT-Leisten (nur Ziel/Fokus)
        dotDirection = "drain",  -- "drain": Leiste leert sich (Restzeit) | "fill": fuellt sich
        dotPoint = "ABOVE",      -- "BELOW" | "ABOVE" | "LEFT" | "RIGHT" | "FREE" (frei verschiebbar)
        dotX = 0, dotY = 0, dotWidth = 0, -- Versatz; Breite 0 = so breit wie der Rahmen
        dotFreeX = 0, dotFreeY = -150,  -- Position, wenn "Frei verschiebbar" gewaehlt ist
        textLayout = "stacked",  -- "stacked": Name oben, LP darunter | "inline": eine Zeile
    }
    for k, v in pairs(o) do d[k] = v end
    return d
end

ns.DEFAULTS = {
    locked = true,
    tooltip = true,
    syncLook = true,               -- Optik von ForeverFrames uebernehmen (falls installiert)
    skin = "DEFAULT",              -- "DEFAULT" (wie bisher) | "FOREVER" (Testskin im Stil der Forever-Fenster)

    -- eigene Optik (gilt, wenn nicht von ForeverFrames uebernommen)
    texture = "raid",
    font = "friz",
    fontOutline = "OUTLINE",
    borderColor = { 0, 0, 0, 1 },
    borderSize = 1,
    barColorMode = "class",        -- "class" | "custom"
    barColor = { 0.2, 0.75, 0.3 },
    lossColorMode = "dark",        -- "dark" | "custom"
    lossColor = { 0.12, 0.12, 0.12 },
    healPrediction = true,
    hotPrediction = true,          -- eigene HoTs: schraffierte Fläche hinter der Heilvorhersage
    powerSeparator = true,         -- feine Trennlinie zwischen Lebens- und Ressourcenbalken
    dotAboveV1 = false,            -- Merker: DoT-Leisten einmalig nach oben gesetzt (in den Standardwerten, damit er gespeichert wird)
    playerLevelV1 = false,         -- Merker: Stufe am Spielerrahmen einmalig eingeschaltet
    powerRegen = true,             -- Spielerrahmen: Regenerationsrate (Mana/Energie) neben der Zahl der Ressource
    druidMana = true,              -- Druide in Tiergestalt: Mana als zusätzlicher Balken unter dem Spielerrahmen
    fiveSecRule = true,           -- Spielerrahmen: leuchtender Strich über dem Manabalken während der Fünf-Sekunden-Regel
    powerHV1 = false,             -- Merker: Ressourcenbalken einmalig auf 12 px (in den Standardwerten, damit er gespeichert wird)
    widthV1 = false,              -- Merker: Spieler-/Zielrahmen einmalig 10 % breiter (in den Standardwerten, damit er gespeichert wird)
    dotPrediction = true,          -- Ziel/Fokus: Schaden der eigenen DoTs als schraffierte Fläche am Lebensbalken
    combatMarker = true,           -- Schwerter-Symbol unten links, solange die Einheit im Kampf ist
    shields = true,
    healColor = { 0.3, 1, 0.45, 0.45 },
    shieldColor = { 0.85, 0.95, 1, 0.5 },
    healAbsorbColor = { 1, 0.1, 0.1, 0.55 },

    npcReactionColor = true,       -- NPCs: feindlich rot, neutral gelb, freundlich gruen
    pvpShow = true,                -- PvP-Symbol, wenn PvP aktiv ist
    leaderShow = true,
    markShow = true,
    restingShow = true,            -- Ausruhen-Symbol (Gasthaus/Hauptstadt) am Spielerrahmen
    dotOnlyHostile = true,         -- DoT-Leisten nur bei angreifbaren Zielen (z. B. nicht "Boosted Rest" beim Lagern)
    comboShow = true,              -- Kombopunkte am Ziel (Schurken, Druiden in Katzengestalt), Combo.lua
    comboPoint = "PORTRAIT",       -- "PORTRAIT" (Spalte neben dem Porträt) | "BELOW" (Balken mit Strichen) | "ABOVE" (Punkte)
    comboSize = 10,                -- Breite der Spalte bzw. Höhe der Striche / Größe der Punkte
    comboShowEmpty = true,         -- leere Punkte auch ohne Kombopunkte zeigen (bei angreifbarem Ziel)
    auraTimer = true,
    auraTooltip = true,

    hideBlizzPlayer = true,
    hideBlizzTarget = true,
    hideBlizzFocus = true,
    hideBlizzPet = true,

    minimapAngle = 170,

    gridShow = true,               -- entsperrt: Raster zum Ausrichten zeigen
    gridSize = 32,                 -- Rasterabstand
    snap = true,                   -- beim Ziehen an anderen Rahmen / am Raster einrasten

    frames = {
        -- Spieler und Ziel spiegelbildlich: gleiche Größe, gleiche Höhe, gleicher Abstand zur Bildschirmmitte
        -- (Spieler = Bezug); das Ziel des Ziels sitzt wie bisher rechts unten am Ziel (+171 / −23)
        player = FrameDefaults({ width = 233, height = 45, x = -238, y = -154, levelShow = true }),
        target = FrameDefaults({ width = 233, height = 45, x = 238, y = -154, portraitSide = "RIGHT", levelShow = true,
            buffs = true, debuffs = true, dotBars = true }),
        targettarget = FrameDefaults({ width = 110, height = 24, x = 409, y = -177, powerHeight = 0,
            fontSize = 10, portrait = "none", portraitSide = "RIGHT", hpFormat = "percent", powerText = false }),
        focus = FrameDefaults({ width = 160, height = 30, x = -426, y = -147, powerHeight = 5, fontSize = 11,
            portrait = "none", levelShow = true, hpFormat = "percent", powerText = false, debuffs = true, auraSize = 18, auraNum = 6,
            dotBars = true, dotFreeY = -100 }),
        pet = FrameDefaults({ width = 120, height = 22, x = -284, y = -196, powerHeight = 4, fontSize = 10,
            portrait = "none", hpFormat = "percent", powerText = false, textLayout = "inline" }),
    },
}

---------------------------------------------------------------------------
-- Gespeicherte Einstellungen (wegen des Beta-Bugs bei jedem Zugriff pruefen)
---------------------------------------------------------------------------
local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = Copy(v)
        elseif type(v) == "table" and type(dst[k]) == "table" then
            Fill(dst[k], v)
        end
    end
end

local db
function ns.GetDB()
    if type(_G.ForeverUnitsDB) ~= "table" then _G.ForeverUnitsDB = db or {} end
    if db ~= _G.ForeverUnitsDB then
        db = _G.ForeverUnitsDB
        Fill(db, ns.DEFAULTS)
        -- einmalig: DoT-Leisten an Ziel und Fokus einschalten (neuer Standard)
        if not db.dotDefaultV2 then
            db.frames.target.dotBars = true
            db.frames.focus.dotBars = true
            db.dotDefaultV2 = true
        end
        if not db.playerLevelV1 then
            if db.frames.player then db.frames.player.levelShow = true end
            db.playerLevelV1 = true
        end
        if not db.widthV1 then -- Spieler und Ziel (spiegelbildlich) von 212 auf 233 px, nur wenn noch der alte Standard
            for _, k in ipairs({ "player", "target" }) do
                if db.frames[k] and db.frames[k].width == 212 then db.frames[k].width = 233 end
            end
            db.widthV1 = true
        end
        if not db.powerHV1 then -- Ressourcenbalken von Spieler/Ziel von 8 auf 12 px, nur wenn noch der alte Standard
            for _, k in ipairs({ "player", "target" }) do
                if db.frames[k] and db.frames[k].powerHeight == 8 then db.frames[k].powerHeight = 12 end
            end
            db.powerHV1 = true
        end
        if not db.dotAboveV1 then
            for _, k in ipairs({ "target", "focus" }) do
                if db.frames[k] and db.frames[k].dotPoint == "BELOW" then db.frames[k].dotPoint = "ABOVE" end
            end
            db.dotAboveV1 = true
        end
    end
    return db
end
local GetDB = ns.GetDB

function ns.FrameDB(key) return GetDB().frames[key] end

function ns.ResetAll()
    -- nur die Einstellungen des aktiven Profils; Profil-Verwaltung (_fc) und Minimap-Position bleiben
    local d = GetDB()
    for key in pairs(d) do
        if not (type(key) == "string" and key:sub(1, 1) == "_") and key ~= "minimapAngle" then d[key] = nil end
    end
    db = nil
    GetDB()
end

---------------------------------------------------------------------------
-- Texturen und Schriften (eigene Optik); weitere ueber LibSharedMedia anderer Addons
---------------------------------------------------------------------------
ns.TEXTURES = {
    { key = "raid",     label = T("Raid (Blizzard)", "Raid (Blizzard)"), path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "flat",     label = T("Flach", "Flat"),       path = "Interface\\Buttons\\WHITE8x8" },
    { key = "blizzard", label = "Blizzard",               path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "gradient", label = T("Verlauf", "Gradient"), path = "Interface\\Buttons\\GreyscaleRamp64" },
    { key = "tooltip",  label = T("Weich (Tooltip)", "Soft (tooltip)"), path = "Interface\\Tooltips\\UI-Tooltip-Background" },
}
ns.FONTS = {
    { key = "friz",   label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn", label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "2002",   label = "2002",          path = "Fonts\\2002.TTF" },
    { key = "2002b",  label = T("2002 Fett", "2002 Bold"), path = "Fonts\\2002B.TTF" },
}
ns.OUTLINES = {
    { key = "",             label = T("Ohne", "None") },
    { key = "OUTLINE",      label = T("Umriss", "Outline") },
    { key = "THICKOUTLINE", label = T("Dicker Umriss", "Thick outline") },
}

local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end

local function WithSharedMedia(list, mediaType)
    local out, seen = {}, {}
    for _, e in ipairs(list) do out[#out + 1] = e seen[e.label] = true end
    local lsm = SharedMedia()
    if lsm then
        for _, name in ipairs(lsm:List(mediaType)) do
            if not seen[name] then out[#out + 1] = { key = "lsm:" .. name, label = name } end
        end
    end
    return out
end
function ns.TextureChoices() return WithSharedMedia(ns.TEXTURES, "statusbar") end
function ns.FontChoices() return WithSharedMedia(ns.FONTS, "font") end

local function MediaPath(key, list, mediaType)
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = SharedMedia()
        local path = lsm and lsm:Fetch(mediaType, key:sub(5), true)
        if path then return path end
    end
    for _, e in ipairs(list) do
        if e.key == key then return e.path end
    end
    return list[1].path
end

-- Aktuelle Optik: von ForeverFrames (falls installiert und gewuenscht) oder die eigene
function ns.HasForeverFrames() return type(_G.ForeverFramesLook) == "function" end

function ns.Look()
    local d = GetDB()
    if d.syncLook and ns.HasForeverFrames() then
        local ok, look = pcall(_G.ForeverFramesLook)
        if ok and type(look) == "table" then return look end
    end
    return {
        texture = MediaPath(d.texture, ns.TEXTURES, "statusbar"),
        font = MediaPath(d.font, ns.FONTS, "font"),
        outline = d.fontOutline, shadow = false,
        borderColor = d.borderColor, borderSize = d.borderSize,
        barColorMode = d.barColorMode, barColor = d.barColor,
        lossColorMode = d.lossColorMode, lossColor = d.lossColor,
        healPrediction = d.healPrediction, hotPrediction = d.hotPrediction, dotPrediction = d.dotPrediction,
        shields = d.shields, healAbsorbs = true,
        combatMarker = d.combatMarker,
        healColor = d.healColor, shieldColor = d.shieldColor, healAbsorbColor = d.healAbsorbColor,
    }
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
-- Gesperrte Werte ("secret values"): nicht damit rechnen oder vergleichen
local issecret = issecretvalue or function() return false end
function ns.IsSecret(...)
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return true end
    end
    return false
end
local IsSecret = ns.IsSecret

function ns.Chat(text) UI.Chat("ForeverUnits", text) end

-- Fehlerschutz (gemeinsam im ForeverHub): jeder Fehler wird nur einmal pro Stelle gemeldet
-- (und an BugSack weitergegeben)
function ns.ReportError(where, err)
    UI.ReportError(ADDON_NAME, where, err)
end

function ns.Safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ns.ReportError(where, err) end
    end
end

function ns.ClassColor(unit)
    local _, class = UnitClass(unit)
    if not IsSecret(class) and class then
        local c = (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        if c then return c.r, c.g, c.b end
    end
    return 0.5, 0.5, 0.5
end

function ns.ShortNumber(v)
    if AbbreviateNumbers then return AbbreviateNumbers(v) end
    return tostring(v)
end

-- Aenderungen an sicheren Rahmen sind im Kampf verboten: merken und nach dem Kampf ausfuehren
-- (Warteschlange im ForeverHub)
function ns.OutOfCombat(key, fn)
    return UI.AfterCombat(ADDON_NAME .. ":" .. tostring(key), fn, ADDON_NAME)
end

---------------------------------------------------------------------------
-- Ereignis-Verteiler (jeder Empfaenger einzeln abgesichert)
---------------------------------------------------------------------------
local handlers = {}
local eventFrame = CreateFrame("Frame")

local Dispatch

-- Einheiten-Ereignisse (UNIT_HEALTH, UNIT_AURA …) nur für unsere Rahmen-Einheiten abonnieren: je Einheit ein eigener
-- kleiner Rahmen mit RegisterUnitEvent. Vorher weckte jede Änderung jeder Namensplakette das Addon, nur damit es sie
-- gleich wieder verwarf.
local unitFrames = {}
local function RegisterUnitEvents(event)
    for _, u in ipairs(ns.UNITS) do
        local f = unitFrames[u.unit]
        if not f then
            f = CreateFrame("Frame")
            f:SetScript("OnEvent", function(_, ...) Dispatch(...) end)
            unitFrames[u.unit] = f
        end
        if not pcall(f.RegisterUnitEvent, f, event, u.unit) then return false end
    end
    return true
end

function ns.On(event, where, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not (event:find("^UNIT_") and RegisterUnitEvents(event)) then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
    tinsert(handlers[event], { where = where, fn = fn })
end

function Dispatch(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i].fn, ...)
        if not ok then ns.ReportError(list[i].where or event, err) end
    end
end
eventFrame:SetScript("OnEvent", function(_, ...) Dispatch(...) end)

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
-- Version 2: Ziel spiegelbildlich zum Spieler (vorher 14 px näher an der Mitte, 13 px tiefer, 1 px höher).
-- Umgesetzt wird das Ziel, wenn es noch auf dem alten Standardplatz steht oder fast spiegelbildlich (höchstens
-- 20 px daneben): dann genau an die Spiegelung des Spielers (wie er jetzt steht); das Ziel des Ziels wandert um
-- denselben Betrag mit. Weiter weg verschobene Rahmen bleiben, wo sie sind.
UI.RegisterSettings({ addon = "ForeverUnits", sv = "ForeverUnitsDB", defaults = ns.DEFAULTS, version = 2,
    migrate = function(data, from)
        if from >= 2 or type(data.frames) ~= "table" then return end
        local p, t, tt = data.frames.player, data.frames.target, data.frames.targettarget
        if type(p) ~= "table" or type(t) ~= "table" then return end
        local px, py = p.x or -238, p.y or -154
        local tx, ty = t.x or 224, t.y or -167
        local oldDefault = tx == 224 and ty == -167
        local nearMirror = math.abs(tx + px) <= 20 and math.abs(ty - py) <= 20
        if not (oldDefault or nearMirror) then return end
        local dx, dy = -px - tx, py - ty
        t.x, t.y = -px, py
        if t.height == nil or t.height == 46 then t.height = p.height or 45 end
        if type(tt) == "table" then
            tt.x, tt.y = (tt.x or 395) + dx, (tt.y or -190) + dy
        end
    end })
