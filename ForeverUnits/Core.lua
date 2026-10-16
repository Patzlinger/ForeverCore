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
        powerHeight = 8, fontSize = 12,
        portrait = "class",       -- "none" | "class" (Klassensymbol, NPCs: 2D-Porträt) | "portrait" (2D-Porträt)
        portraitSide = "LEFT",    -- "LEFT" | "RIGHT"
        nameShow = true, levelShow = false,
        hpFormat = "curpercent",  -- "none" | "percent" | "cur" | "curmax" | "curpercent" | "deficit"
        powerText = true,
        buffs = false, debuffs = false, onlyMine = true, auraSize = 20, auraNum = 8,
        dotBars = false, dotNum = 6, dotHeight = 16, -- DoT-Leisten (nur Ziel/Fokus)
        dotDirection = "drain",  -- "drain": Leiste leert sich (Restzeit) | "fill": fuellt sich
        dotPoint = "BELOW",      -- "BELOW" | "ABOVE" | "LEFT" | "RIGHT" | "FREE" (frei verschiebbar)
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
    shields = true,
    healColor = { 0.3, 1, 0.45, 0.45 },
    shieldColor = { 0.85, 0.95, 1, 0.5 },
    healAbsorbColor = { 1, 0.1, 0.1, 0.55 },

    npcReactionColor = true,       -- NPCs: feindlich rot, neutral gelb, freundlich gruen
    pvpShow = true,                -- PvP-Symbol, wenn PvP aktiv ist
    leaderShow = true,
    markShow = true,
    restingShow = true,            -- Ausruhen-Symbol (Gasthaus/Hauptstadt) am Spielerrahmen
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
        player = FrameDefaults({ x = -250, y = -200 }),
        target = FrameDefaults({ x = 250, y = -200, portraitSide = "RIGHT", levelShow = true,
            buffs = true, debuffs = true, dotBars = true }),
        targettarget = FrameDefaults({ width = 110, height = 24, x = 418, y = -208, powerHeight = 0,
            fontSize = 10, portrait = "none", portraitSide = "RIGHT", hpFormat = "percent", powerText = false }),
        focus = FrameDefaults({ width = 160, height = 30, x = -250, y = -110, powerHeight = 5, fontSize = 11,
            portrait = "none", levelShow = true, hpFormat = "percent", powerText = false, debuffs = true, auraSize = 18, auraNum = 6,
            dotBars = true, dotFreeY = -100 }),
        pet = FrameDefaults({ width = 120, height = 22, x = -290, y = -238, powerHeight = 4, fontSize = 10,
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
    end
    return db
end
local GetDB = ns.GetDB

function ns.FrameDB(key) return GetDB().frames[key] end

function ns.ResetAll()
    wipe(GetDB())
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
        healPrediction = d.healPrediction, shields = d.shields, healAbsorbs = true,
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

-- Fehlerschutz: jeder Fehler wird nur einmal pro Stelle gemeldet (und an BugSack weitergegeben)
local reported = {}
function ns.ReportError(where, err)
    if reported[where] then return end
    reported[where] = true
    ns.Chat(string.format(T("|cffff4444Fehler in %s|r – das Addon läuft weiter. (%s)",
        "|cffff4444Error in %s|r – the addon keeps running. (%s)"), where, tostring(err)))
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, err) end
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
local pending, pendingOrder = {}, {}
function ns.OutOfCombat(key, fn)
    if InCombatLockdown() then
        if not pending[key] then tinsert(pendingOrder, key) end
        pending[key] = fn
        return false
    end
    fn()
    return true
end

---------------------------------------------------------------------------
-- Ereignis-Verteiler (jeder Empfaenger einzeln abgesichert)
---------------------------------------------------------------------------
local handlers = {}
local eventFrame = CreateFrame("Frame")

function ns.On(event, where, fn)
    if not handlers[event] then
        handlers[event] = {}
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    tinsert(handlers[event], { where = where, fn = fn })
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i].fn, ...)
        if not ok then ns.ReportError(list[i].where or event, err) end
    end
end)

ns.On("PLAYER_REGEN_ENABLED", T("Nach dem Kampf", "After combat"), function()
    local order = pendingOrder
    pendingOrder = {}
    for _, key in ipairs(order) do
        local fn = pending[key]
        pending[key] = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then ns.ReportError(key, err) end
        end
    end
end)
