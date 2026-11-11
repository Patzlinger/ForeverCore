-- ForeverPlates: eigene Namensplaketten für Gegner – Name und Stufe, Leben in % und als Zahl, Bedrohung als
-- Schild mit Prozent (Leiste färbt sich je nach Rolle), schmale Zauberleiste mit Ziel-Plakette und Unterbrechen-
-- Hinweis, eigene DoTs oben, Kontrolleffekte (CC) groß an der Seite, Buffs wahlweise, Finishing-Bereich, Combopunkte
-- auf dem Ziel, Questgegner und große Raidmarker. Zwei Looks: "Forever" (flach, dunkel) und "Klassisch".
-- Aufbau: Blizzards Plakette bleibt als unsichtbarer Träger – sie übernimmt Position, Abstände, Skalierung,
-- Anklicken und die Leistenfarbe (angetippt, Reaktion). Bei Gegnern wird sie nur durchsichtig (nie versteckt oder
-- umgehängt), unsere Plakette hängt am Plaketten-Rahmen darüber. Verbündete behalten Blizzards Plakette (wahlweise
-- nur Name in Klassenfarbe); in Instanzen sperrt Blizzard deren Plaketten ohnehin für Addons.
-- Geheime Werte (Leben, Bedrohung, Zauberinfos) gehen nur in Anzeige-Funktionen (SetText, SetValue, SetAlpha,
-- SetTimerDuration, …FromBoolean) und werden nie verglichen oder verrechnet.
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR
local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT = STANDARD_TEXT_FONT

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------
ns.DEFAULTS = {
    skin = true,              -- Forever-Rahmen: dunkler Grund, feiner Rand, Glanzkante
    syncLook = true,          -- Textur und Schrift wie ForeverFrames (falls installiert)
    texture = "raid",         -- Leistentextur (Liste wie ForeverFrames/ForeverUnits)
    font = "friz",
    fontOutline = "",         -- "" = weicher Schatten, sonst Umriss
    fontSizeAdd = 0,          -- Schrift größer/kleiner
    width = 0,                -- Breite der Plakette, 0 = wie Blizzards Plakette (passt zur Klickfläche)
    barHeight = 12,           -- Höhe der Lebensleiste
    offsetY = 14,             -- Plakette höher über dem Gegner (Modell bleibt sichtbar)
    targetScale = 110,        -- Ziel etwas größer (Prozent)
    dimOthers = true,         -- übrige Plaketten leicht gedämpft, solange ein Ziel gewählt ist
    showLevel = true,         -- Stufe neben dem Namen
    classIcon = true,         -- Symbol für Elite/Rar/Boss vor der Stufe
    dotPrediction = true,     -- Schaden der eigenen DoTs als schraffierte Fläche auf der Lebensleiste (rot = tödlich)
    healthText = true,        -- Leben auf der Leiste
    healthValue = true,       --   als Zahl (links)
    healthPercent = true,     --   in Prozent (rechts)
    healthOnlyDamaged = false,-- nur wenn nicht voll
    threat = true,            -- Bedrohung
    threatText = true,        --   Prozent neben der Leiste
    threatColorBar = true,    --   Leiste in Bedrohungsfarbe
    threatColorTankOnly = true, --   … nur als Tank in einer Gruppe (solo und als Schaden/Heiler ohne Farben)
    threatLead = true,        --   als Tank: Abstand des Nächsten ("Nächster 85 %") statt der eigenen 100 %
    rangeFade = false,        -- Gegner außerhalb der Reichweite des eigenen Zaubers blasser (Reichweiten-Takt)
    threatTank = false,       --   immer als Tank werten (sonst: Gruppenrolle)
    -- eigene Farben je Bedrohungsstufe (statt der Farben nach Rolle); gelten dann für alle Rollen und alle Stufen
    threatCustom = false,
    threatColAggro = { 0.78, 0.26, 0.26 },   -- du hast sicher Aggro (Stufe 3)
    threatColLosing = { 0.86, 0.48, 0.2 },   -- du hast Aggro, verlierst sie gleich (Stufe 2)
    threatColGaining = { 0.85, 0.72, 0.3 },  -- keine Aggro, ziehst sie gleich (Stufe 1)
    threatColNone = { 0.45, 0.68, 0.45 },    -- keine Aggro (Stufe 0)
    stack = true,             -- Plaketten stapeln statt überlappen (Blizzard-Schalter)
    noShrink = true,          -- nicht mit der Entfernung verkleinern (sonst wird kleine Schrift unleserlich)
    los = true,               -- "keine Sicht" am Ziel, wenn ein Zauber daran scheitert
    castbar = true,           -- eigene schmale Zauberleiste
    castHeight = 9,
    castTarget = true,        --   Plakette mit dem Ziel am Ende
    interruptHint = true,     --   grün, wenn unterbrechbar und meine Unterbrechung bereit ist
    debuffs = true,           -- Schwächungen oben
    debuffsMine = true,       --   nur meine (DoTs)
    debuffSize = 20,
    debuffMax = 6,
    cc = true,                -- Kontrolleffekte an der Seite
    ccSize = 26,
    ccLeft = false,
    buffs = false,            -- Stärkungen (wahlweise)
    buffsPurgeable = true,    --   nur entfernbare
    buffSize = 16,
    buffMax = 4,
    execute = true,           -- Finishing-Bereich
    executeAt = 20,
    executeColor = { 1, 0.2, 0.85 }, -- auffallend: leuchtendes Pink-Magenta (frei wählbar)
    combo = true,             -- Combopunkte auf dem Ziel
    friendlySimple = true,    -- Verbündete: nur Name in Klassenfarbe
    enemyClassColor = true,   -- gegnerische Spieler (andere Fraktion): Leiste in Klassenfarbe statt Feindrot
    quest = true,             -- Questgegner-Symbol
    raidMarker = true,        -- großer Raidmarker über der Plakette
    raidMarkerSize = 26,
    -- Schadenszahlen über dem Gegner (Blizzards eigene, ApplyWorldText): Standard nur höher (über die Plakette)
    dmgRaise = true,
    dmgHeight = 5,            -- Bildschirmhöhe in Prozent, um die die Zahlen höher starten
    dmgCustom = false,        -- Zusatz: Bewegung anpassen (erst zuschalten)
    dmgScale = 100,           -- Größe in Prozent
    dmgDuration = 10,         -- Dauer in Zehntelsekunden
    dmgGravity = 50,          -- Schwerkraft (Bogen) in Hundertstel
    dmgSpread = 0,            -- seitliche Streuung in Hundertstel
    dmgClassic = false,       -- klassischer Stil (Blizzard-Schalter)
    minimapAngle = 320,
}

local db
local function GetDB()
    if type(_G.ForeverPlatesDB) ~= "table" then _G.ForeverPlatesDB = db or {} end
    db = _G.ForeverPlatesDB
    for k, v in pairs(ns.DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for i, x in pairs(v) do copy[i] = x end
                db[k] = copy
            else
                db[k] = v
            end
        end
    end
    -- einmalig: eigene Plaketten mit Forever-Look als neuer Standard (vorher Blizzards Plakette mit Zusätzen)
    if not db.ownPlatesV2 then
        db.skin = true
        db.healthFriendly = nil
        db.ownPlatesV2 = true
    end
    return db
end
ns.GetDB = GetDB

local issecret = issecretvalue or function() return false end
local function IsSecret(...)
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return true end
    end
    return false
end
-- "gibt es einen Wert?" – auch geheime Werte zählen (die dürfen nicht direkt geprüft werden)
local function Has(v) return IsSecret(v) or (v ~= nil and v ~= false) end
local function Yes(v) return not IsSecret(v) and v and true or false end

local function Safe(where, fn) return UI.Safe("ForeverPlates", where, fn) end
ns.Safe = Safe

-- Blizzard-Teil durchsichtig halten – auch wenn Blizzard ihn selbst wieder sichtbar stellt (z. B. Zauberleiste
-- beim Einblenden). Nie verstecken oder umhängen, nur Deckkraft.
local function Mute(region, on)
    if not region or not region.SetAlpha then return end
    on = on and true or false
    if on and not region.fpMuteHooked then
        region.fpMuteHooked = true
        hooksecurefunc(region, "SetAlpha", function(self)
            if self.fpMuted and not self.fpMuting then
                self.fpMuting = true
                self:SetAlpha(0)
                self.fpMuting = nil
            end
        end)
    end
    if region.fpMuted == on then return end
    region.fpMuted = on
    region:SetAlpha(on and 0 or 1)
end

---------------------------------------------------------------------------
-- Farben
---------------------------------------------------------------------------
-- gedämpft wie die Forever-Fenster (keine knalligen Grundfarben)
local COL = {
    cast = { 0.82, 0.62, 0.28 },      -- unterbrechbar
    castReady = { 0.36, 0.7, 0.44 },  -- unterbrechbar und meine Unterbrechung ist bereit
    castLocked = { 0.42, 0.42, 0.47 },-- nicht unterbrechbar
    interrupted = { 0.66, 0.24, 0.24 },
    comboOn = { 1, 0.82, 0 },         -- Goldton der Forever-Fenster
    comboOff = { 0.12, 0.12, 0.14 },
    los = { 1, 0.45, 0.35 },
}
-- Bedrohung: Status 0 = wenig, 1 = mehr als der Tank (noch nicht übernommen), 2 = Aggro wackelt, 3 = sichere Aggro
local THREAT_DPS = { [0] = { 0.45, 0.68, 0.45 }, [1] = { 0.85, 0.72, 0.3 }, [2] = { 0.86, 0.48, 0.2 }, [3] = { 0.78, 0.26, 0.26 } }
local THREAT_TANK = { [0] = { 0.78, 0.26, 0.26 }, [1] = { 0.86, 0.48, 0.2 }, [2] = { 0.85, 0.72, 0.3 }, [3] = { 0.4, 0.7, 0.45 } }

-- Blizzards Leistenfarben (Reaktion, Klasse) etwas entsättigen und abdunkeln, damit sie zum Stil passen
local function Soften(r, g, b)
    if IsSecret(r, g, b) or not r then return r, g, b end
    local l = r * 0.3 + g * 0.59 + b * 0.11
    local k = 0.82
    return (r * 0.72 + l * 0.28) * k, (g * 0.72 + l * 0.28) * k, (b * 0.72 + l * 0.28) * k
end

local colorObj = {}
local function ColorObj(c)
    local o = colorObj[c]
    if not o and CreateColor then
        o = CreateColor(c[1], c[2], c[3], 1)
        colorObj[c] = o
    end
    return o
end

-- Aggro-Text als Tank: Farbe, wenn ich die Aggro habe bzw. sie verloren habe (rot)
local TANK_TEXT_OK = { 0.55, 0.85, 0.6 }
local TANK_TEXT_LOST = { 1, 0.3, 0.3 }

local function IsTank()
    if db.threatTank then return true end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    return role == "TANK"
end

---------------------------------------------------------------------------
-- Kurven (Blizzard rechnet geheime Lebenswerte selbst um)
---------------------------------------------------------------------------
local notFullCurve, execCurve, execAt
local function NotFullCurve()
    if notFullCurve == nil then
        notFullCurve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0.0, 1)
            c:AddPoint(1.0, 0)
            notFullCurve = c
        end
    end
    return notFullCurve or nil
end

-- 1 unter der Schwelle, sonst 0 (als Deckkraft der Finishing-Farbe)
local function ExecCurve()
    local at = db.executeAt
    if execAt ~= at then
        execAt, execCurve = at, false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Linear)
            local t = at / 100
            c:AddPoint(0.0, 1)
            c:AddPoint(t, 1)
            c:AddPoint(t + 0.001, 0)
            c:AddPoint(1.0, 0)
            execCurve = c
        end
    end
    return execCurve or nil
end

---------------------------------------------------------------------------
-- Unterbrechen: Zauber je Klasse, bereit = keine Abklingzeit (nur wenn das Spiel die Zeit verrät)
---------------------------------------------------------------------------
local KICKS = {
    WARRIOR = { 6552, 72 }, ROGUE = { 1766 }, MAGE = { 2139 }, SHAMAN = { 57994, 8042 }, PALADIN = { 96231 },
    DEATHKNIGHT = { 47528 }, DRUID = { 106839 }, HUNTER = { 147362, 187707 }, MONK = { 116705 },
    DEMONHUNTER = { 183752 }, PRIEST = { 15487 }, WARLOCK = { 19647 }, EVOKER = { 351338 },
}
local kickSpell
local function FindKick()
    kickSpell = nil
    local _, class = UnitClass("player")
    for _, id in ipairs(KICKS[class] or {}) do
        local known = (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and (IsSpellKnown(id) or IsSpellKnown(id, true)))
        if known then kickSpell = id return end
    end
end

local function KickReady()
    if not kickSpell then return false end
    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(kickSpell)
        if type(info) == "table" then start, dur = info.startTime, info.duration end
    elseif GetSpellCooldown then
        start, dur = GetSpellCooldown(kickSpell)
    end
    if IsSecret(start, dur) or not start or not dur then return false end
    return dur <= 1.5 or (start + dur - GetTime()) <= 0.1
end

---------------------------------------------------------------------------
-- Aufbau je Plakette (Blizzard verwendet Plaketten wieder – alles wird einmal angelegt und dann neu befüllt)
---------------------------------------------------------------------------
local plates = {}   -- unit -> fp
ns.plates = plates

local function HealthBar(frame)
    return frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
end

ns.TEXTURES = {
    { key = "raid",     label = T("Raid (Blizzard)", "Raid (Blizzard)"), path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "flat",     label = T("Flach", "Flat"),       path = "Interface\\Buttons\\WHITE8x8" },
    { key = "blizzard", label = "Blizzard",               path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "gradient", label = T("Verlauf", "Gradient"), path = "Interface\\Buttons\\GreyscaleRamp64" },
}
ns.FONTS = {
    { key = "friz",   label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn", label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "2002",   label = "2002",          path = "Fonts\\2002.TTF" },
    { key = "2002b",  label = T("2002 Fett", "2002 Bold"), path = "Fonts\\2002B.TTF" },
}
ns.OUTLINES = {
    { key = "",        label = T("Weicher Schatten", "Soft shadow") },
    { key = "OUTLINE", label = T("Umriss", "Outline") },
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

-- aktuelle Optik: von ForeverFrames (abgestimmt) oder die eigene
function ns.HasForeverFrames() return type(_G.ForeverFramesLook) == "function" end
local function Look()
    local d = db or GetDB()
    if d.syncLook and ns.HasForeverFrames() then
        local ok, look = pcall(_G.ForeverFramesLook)
        if ok and type(look) == "table" and look.texture and look.font then
            return look.texture, look.font, look.outline or ""
        end
    end
    return MediaPath(d.texture, ns.TEXTURES, "statusbar"), MediaPath(d.font, ns.FONTS, "font"), d.fontOutline or ""
end

local texts = setmetatable({}, { __mode = "k" }) -- alle Texte: Grundgröße und feste Umriss-Wahl
-- Gesperrte Texte (z. B. auf Symbolen, die Blizzards Auren-Anzeige verwaltet) nie anfassen
local function SetLookFont(fs, size, flags)
    if fs.IsForbidden and fs:IsForbidden() then return end
    local _, path, outline = Look()
    local fl = flags or outline
    if fl == "NONE" then fl = "" end
    size = size + ((db and db.fontSizeAdd) or 0)
    if not pcall(fs.SetFont, fs, path, size, fl) then
        if not pcall(fs.SetFont, fs, FONT, size, fl) then return end
    end
    pcall(fs.SetShadowColor, fs, 0, 0, 0, 1)
    pcall(fs.SetShadowOffset, fs, fl == "" and 1 or 0, fl == "" and -1 or 0)
end

-- keep = false: nur einmal setzen, nicht in die Liste für spätere Schriftwechsel (Auren-Symbole)
local function Font(fs, size, flags, keep)
    if keep ~= false then texts[fs] = { size, flags } end
    SetLookFont(fs, size, flags)
end

local function ApplyFonts()
    for fs, t in pairs(texts) do SetLookFont(fs, t[1], t[2]) end
end

local function NewText(parent, layer)
    return parent:CreateFontString(nil, layer or "OVERLAY")
end

local function Edges(parent, layer, target, r, g, b, a, out)
    local list = {}
    out = out or 1
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, -1 },
        { "TOPLEFT", "BOTTOMLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local t = parent:CreateTexture(nil, layer)
        t:SetColorTexture(r, g, b, a)
        if i <= 2 then
            t:SetPoint(p[1], target, p[1], -out, p[4] * out)
            t:SetPoint(p[2], target, p[2], out, p[4] * out)
            t:SetHeight(1)
        else
            t:SetPoint(p[1], target, p[1], p[3] * out, out)
            t:SetPoint(p[2], target, p[2], p[3] * out, -out)
            t:SetWidth(1)
        end
        list[i] = t
    end
    return list
end

local function SetEdgesColor(list, r, g, b, a)
    for _, t in ipairs(list) do t:SetColorTexture(r, g, b, a) end
end

local CastOnUpdate
local function BuildCast(fp)
    local cb = CreateFrame("StatusBar", nil, fp.overlay)
    cb:SetStatusBarTexture(WHITE)
    cb:SetMinMaxValues(0, 1)
    cb:Hide()
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -1, 1)
    bg:SetPoint("BOTTOMRIGHT", 1, -1)
    bg:SetColorTexture(0, 0, 0, 0.75)
    local gloss = cb:CreateTexture(nil, "ARTWORK", nil, 2)
    gloss:SetPoint("TOPLEFT", cb:GetStatusBarTexture(), "TOPLEFT")
    gloss:SetPoint("TOPRIGHT", cb:GetStatusBarTexture(), "TOPRIGHT")
    gloss:SetHeight(3)
    gloss:SetColorTexture(1, 1, 1, 0.18)
    Edges(cb, "OVERLAY", cb, 0, 0, 0, 1, 1)
    local spark = cb:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetWidth(2)
    spark:SetPoint("TOP", cb:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    spark:SetPoint("BOTTOM", cb:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    spark:SetColorTexture(1, 1, 0.9, 0.9)
    cb.spark = spark
    -- nicht unterbrechbar: kleines Schild links vor der Leiste
    cb.shield = cb:CreateTexture(nil, "OVERLAY")
    cb.shield:SetAtlas("nameplates-InterruptShield")
    cb.shield:SetSize(10, 12)
    cb.shield:SetPoint("RIGHT", cb, "LEFT", -1, 0)
    cb.shield:SetAlpha(0)
    cb.text = NewText(cb)
    Font(cb.text, 8)
    cb.text:SetJustifyH("LEFT")
    cb.text:SetWordWrap(false)
    cb.text:SetPoint("LEFT", cb, "LEFT", 3, 0)
    cb.text:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
    -- Ziel-Plakette rechts neben der Leiste: 30 % der Plakettenbreite, längere Namen werden abgeschnitten
    -- Zeile unter der Zauberleiste, ganz klein: "Ziel Name" (beim Unterbrechen "von Name")
    local tag = CreateFrame("Frame", nil, fp.overlay)
    tag:Hide()
    tag.label = NewText(tag)
    Font(tag.label, 7)
    tag.label:SetPoint("LEFT", 0, 0)
    tag.label:SetTextColor(0.62, 0.62, 0.66)
    tag.text = NewText(tag)
    Font(tag.text, 7)
    tag.text:SetPoint("LEFT", tag.label, "RIGHT", 3, 0)
    tag.text:SetPoint("RIGHT", 0, 0)
    tag.text:SetJustifyH("LEFT")
    tag.text:SetWordWrap(false)
    cb.tag = tag
    cb:HookScript("OnHide", function() tag:Hide() end)
    fp.cast = cb
end

-- Zauberleiste direkt unter der Lebensleiste, genauso breit; die Ziel-Zeile darunter
local function LayoutCastRow(fp)
    local cb, tag = fp.cast, fp.cast.tag
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", fp.overlay, "BOTTOMLEFT", 0, -2)
    cb:SetPoint("TOPRIGHT", fp.overlay, "BOTTOMRIGHT", 0, -2)
    cb:SetHeight(db.castHeight)
    tag:ClearAllPoints()
    tag:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 1, -2)
    tag:SetPoint("TOPRIGHT", cb, "BOTTOMRIGHT", -1, -2)
    tag:SetHeight(9)
end

local function BuildCombo(fp)
    fp.combo = {}
    for i = 1, 7 do
        local t = fp.overlay:CreateTexture(nil, "OVERLAY")
        t:SetSize(9, 5)
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        local edge = fp.overlay:CreateTexture(nil, "ARTWORK")
        edge:SetPoint("TOPLEFT", t, -1, 1)
        edge:SetPoint("BOTTOMRIGHT", t, 1, -1)
        edge:SetColorTexture(0, 0, 0, 0.9)
        edge:Hide()
        t.edge = edge
        fp.combo[i] = t
    end
end

local function Setup(plate, frame)
    if frame.fpl then return frame.fpl end
    local hb = HealthBar(frame)
    if not hb then return end
    local fp = { plate = plate, frame = frame, hb = hb, auras = {} }
    frame.fpl = fp
    -- unsere Plakette: Kind des Plaketten-Rahmens (nicht von Blizzards UnitFrame, das bei Gegnern durchsichtig ist),
    -- mittig auf Blizzards Lebensleiste – dort, wo man klickt
    local root = CreateFrame("Frame", nil, plate)
    -- Blizzard verkleinert Plaketten mit der Entfernung; kleine Schrift wird dabei verwaschen hochgerechnet.
    -- Unsere Plakette bleibt deshalb immer in der Größe der Oberfläche (scharf), nur die Lage folgt Blizzard.
    if root.SetIgnoreParentScale then root:SetIgnoreParentScale(true) end
    root:SetPoint("CENTER", hb, "CENTER", 0, 0)
    root:SetFrameLevel(frame:GetFrameLevel() + 10)
    root:Hide()
    fp.root = root
    local o = CreateFrame("StatusBar", nil, root)
    o:SetAllPoints(root)
    o:SetStatusBarTexture(WHITE)
    o:SetMinMaxValues(0, 1)
    o:SetValue(1)
    fp.bar, fp.overlay = o, o
    -- Schaden der eigenen DoTs: schraffierte Fläche vom Ende der Lebensleiste nach links (geklippt auf die Leiste)
    local clip = CreateFrame("Frame", nil, o)
    clip:SetAllPoints(o)
    clip:SetFrameLevel(o:GetFrameLevel() + 1)
    clip:SetClipsChildren(true)
    local dotFill = CreateFrame("StatusBar", nil, clip) -- Grundfläche unter der Schraffur
    dotFill:SetStatusBarTexture(WHITE)
    dotFill:SetReverseFill(true)
    dotFill:SetMinMaxValues(0, 1)
    dotFill:SetValue(0)
    dotFill:SetPoint("TOPRIGHT", o:GetStatusBarTexture(), "TOPRIGHT")
    fp.dotFill = dotFill
    local dot = CreateFrame("StatusBar", nil, clip)
    UI.HatchBar(dot)
    dot:SetReverseFill(true)
    dot:SetMinMaxValues(0, 1)
    dot:SetValue(0)
    dot:SetPoint("TOPRIGHT", o:GetStatusBarTexture(), "TOPRIGHT")
    o:HookScript("OnSizeChanged", function(_, w, h) dot:SetSize(w, h) dotFill:SetSize(w, h) end)
    fp.dot = dot
    fp.bg = o:CreateTexture(nil, "BACKGROUND")
    fp.bg:SetAllPoints()
    fp.gloss = o:CreateTexture(nil, "ARTWORK", nil, 2)
    fp.gloss:SetPoint("TOPLEFT", o:GetStatusBarTexture(), "TOPLEFT")
    fp.gloss:SetPoint("TOPRIGHT", o:GetStatusBarTexture(), "TOPRIGHT")
    fp.gloss:SetHeight(3)
    fp.gloss:SetColorTexture(1, 1, 1, 0.12)
    fp.edges = Edges(o, "OVERLAY", o, 0, 0, 0, 1, 1)

    -- Name links über der Leiste, Stufe rechts daneben
    fp.name = NewText(o)
    Font(fp.name, 9)
    fp.name:SetJustifyH("LEFT")
    fp.name:SetWordWrap(false)
    fp.level = NewText(o)
    Font(fp.level, 9)
    fp.level:SetJustifyH("RIGHT")
    -- Elite/Rar/Boss: Blizzards Symbol direkt vor der Stufe
    fp.classIcon = o:CreateTexture(nil, "OVERLAY")
    fp.classIcon:SetSize(1, 12)
    fp.classIcon:Hide()

    -- Finishing-Farbe über der Füllung (Deckkraft per Kurve: nur unter der Schwelle sichtbar)
    fp.exec = o:CreateTexture(nil, "ARTWORK", nil, 1)
    fp.exec:SetAllPoints(o:GetStatusBarTexture())
    fp.exec:SetColorTexture(1, 1, 1, 1) -- Farbe aus den Einstellungen (ApplyLook)
    fp.exec:SetAlpha(0)

    -- Zahlen in der Leiste liegen in einem eigenen Rahmen über der DoT-Schraffur (Kind-Rahmen der Leiste zeichnen sonst
    -- über deren Texten)
    local numbers = CreateFrame("Frame", nil, o)
    numbers:SetAllPoints(o)
    numbers:SetFrameLevel(o:GetFrameLevel() + 8)
    fp.hpValue = NewText(numbers)
    Font(fp.hpValue, 9)
    fp.hpValue:SetPoint("LEFT", o, "LEFT", 3, 0)
    fp.hpPct = NewText(numbers)
    Font(fp.hpPct, 9)
    fp.hpPct:SetPoint("RIGHT", o, "RIGHT", -3, 0)

    -- Bedrohung: klein "Aggro", darunter die Prozentzahl in Bedrohungsfarbe
    local badge = CreateFrame("Frame", nil, o)
    badge:SetSize(34, 22)
    badge:Hide()
    badge.label = NewText(badge)
    Font(badge.label, 7)
    badge.label:SetText("Aggro")
    badge.label:SetTextColor(0.62, 0.62, 0.66)
    badge.label:SetPoint("TOP", badge, "TOP", 0, 0)
    fp.threatBadge = badge
    fp.threatText = NewText(badge)
    Font(fp.threatText, 10)
    fp.threatText:SetPoint("TOP", badge.label, "BOTTOM", 0, -1)

    -- keine Sicht: nach "nicht im Sichtfeld" beim Zaubern auf dieses Ziel
    fp.los = NewText(o)
    Font(fp.los, 8)
    fp.los:SetTextColor(COL.los[1], COL.los[2], COL.los[3])
    fp.los:SetText(T("keine Sicht", "no sight"))
    fp.los:Hide()

    fp.quest = o:CreateTexture(nil, "OVERLAY")
    fp.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon") -- oder Questies Symbol (UpdateQuest)
    fp.quest:SetSize(14, 14)
    fp.quest:SetPoint("BOTTOMRIGHT", o, "TOPLEFT", -1, 1)
    fp.quest:Hide()

    fp.raid = o:CreateTexture(nil, "OVERLAY")
    fp.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    fp.raid:Hide()

    BuildCast(fp)
    BuildCombo(fp)
    -- alles richtet sich nach der Breite der Plakette (Blizzards Leiste ändert sie mit der Plakettengröße)
    o:SetScript("OnSizeChanged", function()
        if fp.unit and fp.Relayout then fp.Relayout(fp) end
    end)
    hb:HookScript("OnSizeChanged", function()
        if fp.unit and fp.Resize then fp.Resize(fp) end
    end)
    return fp
end

---------------------------------------------------------------------------
-- Auren (Blizzard-Anzeige "AuraContainer": das Spiel zeichnet selbst, auch mit geheimen Werten)
---------------------------------------------------------------------------
local AF = AuraUtil and AuraUtil.AuraFilters or {}
local function Filter(...)
    local s = table.concat({ ... }, "|")
    if AuraUtil and AuraUtil.IsValidFilterString then
        local ok, valid = pcall(AuraUtil.IsValidFilterString, s)
        if ok and not valid then return nil end
    end
    return s
end

local function AuraFilters()
    local d = db
    local cc = AF.CrowdControl or "CROWD_CONTROL"
    local np = AF.IncludeNameplateOnly or "INCLUDE_NAME_PLATE_ONLY"
    local deb = d.debuffsMine and Filter("HARMFUL", "PLAYER", np, "!" .. cc) or Filter("HARMFUL", np, "!" .. cc)
    return {
        debuffs = deb or (d.debuffsMine and "HARMFUL|PLAYER" or "HARMFUL"),
        cc = Filter("HARMFUL", cc, np) or Filter("HARMFUL", cc),
        buffs = d.buffsPurgeable and (Filter("HELPFUL", AF.Dispellable or "DISPELLABLE") or "HELPFUL") or "HELPFUL",
    }
end

local function FlowRight(c, upward)
    local axisEnum = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local dirEnum = AnchorUtil and AnchorUtil.FlowDirection
    if not (axisEnum and dirEnum and c.SetFlowLayoutAxis) then return false end
    local axis = axisEnum.Horizontal or axisEnum.HORIZONTAL or axisEnum.X
    local fwd = dirEnum.Right or dirEnum.Forward
    local vert = upward and (dirEnum.Up or fwd) or (dirEnum.Down or dirEnum.Backward)
    if axis == nil or fwd == nil or vert == nil then return false end
    return pcall(function()
        c:SetFlowLayoutAxis(axis)
        c:SetFlowLayoutGrowthDirection(fwd, vert)
        c:SetFlowLayoutAnchorPoint(upward and "BOTTOMLEFT" or "TOPLEFT")
        c:SetFlowLayoutMaximumLineSize(2000) -- eine Reihe
    end)
end

-- Restzeit: unter 10 s mit Kommastelle, ab 1 Min. als m:ss
local timeFormatter
local function TimeFormatter()
    if timeFormatter == nil then
        timeFormatter = false
        if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
            local ok, fmt = pcall(function()
                local f = C_StringUtil.CreateNumericRuleFormatter()
                f:AddBreakpoint({ threshold = 0, step = 0.1, format = "%.1f" })
                f:AddBreakpoint({ threshold = 10, step = 1, format = "%d" })
                f:AddBreakpoint({ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } })
                return f
            end)
            if ok then timeFormatter = fmt end
        end
    end
    return timeFormatter or nil
end

-- w x h: Debuffs etwas flacher als breit (wie Blizzard), CC quadratisch mit Goldrand
local function MakeInit(w, h, kind)
    return function(button)
        button:SetSize(w, h)
        button:EnableMouse(false)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if kind == "cc" then
            bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        else
            bg:SetColorTexture(0, 0, 0, 1)
        end
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        local cut = (1 - (h - 2) / (w - 2)) * 0.42
        icon:SetTexCoord(0.08, 0.92, 0.08 + cut, 0.92 - cut)
        button:SetIcon(icon)
        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:EnableMouse(false)
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        if button.SetDurationCooldown then pcall(button.SetDurationCooldown, button, cd) end
        local layer = CreateFrame("Frame", nil, button)
        layer:SetAllPoints()
        layer:SetFrameLevel(cd:GetFrameLevel() + 2)
        local timer = NewText(layer)
        Font(timer, kind == "cc" and 11 or 9, "OUTLINE", false)
        if kind == "cc" then
            timer:SetPoint("CENTER", button, "CENTER", 0, 0)
        else
            timer:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
        end
        if button.SetDurationText then
            local opts = { textFormatter = TimeFormatter() }
            if not pcall(button.SetDurationText, button, timer, opts) then pcall(button.SetDurationText, button, timer) end
        end
        local stacks = NewText(layer)
        Font(stacks, 8, "OUTLINE", false)
        stacks:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        if button.SetApplicationCount then pcall(button.SetApplicationCount, button, stacks) end
    end
end

local function AuraSpec(kind)
    local d = db
    if kind == "debuffs" then
        return d.debuffs, d.debuffSize, math.floor(d.debuffSize * 0.75 + 0.5), d.debuffMax
    elseif kind == "cc" then
        return d.cc, d.ccSize, d.ccSize, 3
    end
    return d.buffs, d.buffSize, math.floor(d.buffSize * 0.75 + 0.5), d.buffMax
end

local function AuraSupported()
    return AuraContainerSortDirection ~= nil and AuraContainerSortMethod ~= nil
end

-- Ein Container je Art; ändert sich Größe oder Filter, wird ein frischer angelegt
-- (vorhandene Symbole übernehmen neue Größen nicht)
local function EnsureContainer(fp, kind, filter)
    local _, w, h, num = AuraSpec(kind)
    local sig = table.concat({ w, h, filter }, ":")
    local c = fp.auras[kind]
    if not c or c.fpSig ~= sig then
        if c then pcall(c.ClearAuraGroups, c) pcall(c.SetUnit, c, nil) c:Hide() end
        local ok
        ok, c = pcall(CreateFrame, "AuraContainer", nil, fp.overlay, "CustomAuraContainerTemplate")
        if not ok or not c then return nil end
        local sort = kind == "debuffs" and (AuraContainerSortMethod.ExpirationOnly or AuraContainerSortMethod.Default)
            or AuraContainerSortMethod.Default
        ok = pcall(c.AddAuraGroup, c, "fp", filter, {
            maxFrameCount = num,
            sortMethod = sort,
            sortDirection = AuraContainerSortDirection.Normal,
            initializeFrame = MakeInit(w, h, kind),
        })
        if not ok then c:Hide() return nil end
        if c.SetEditModePreviewEnabled then pcall(c.SetEditModePreviewEnabled, c, false) end
        c.fpSig = sig
        fp.auras[kind] = c
        c.fpUnit = nil
    end
    pcall(c.SetAuraGroupMaxFrameCount, c, "fp", num)
    local layout = { elementWidth = w, elementHeight = h, elementSpacing = 2, lineSpacing = 2, layoutIndex = 1 }
    if not FlowRight(c, kind ~= "cc") then
        layout.growthDirection = "RIGHT_UP"
        layout.wrapAfter = 2000
    end
    pcall(c.SetAuraGroupLayout, c, "fp", layout)
    return c
end

-- Höhe der Debuff-Reihe (für Buffs und Raidmarker darüber)
local function DebuffRowHeight()
    if not (db.debuffs and AuraSupported()) then return 0 end
    return math.floor(db.debuffSize * 0.75 + 0.5) + 2
end
-- Oberer Bereich, von unten nach oben: (Combopunkte) – Name/Stufe – DoTs – Buffs – Raidmarker
local function TopOffset(fp)
    return fp.comboShown and 7 or 2
end

local function PlaceTop(fp)
    local o = fp.overlay
    local y = TopOffset(fp)
    fp.name:ClearAllPoints()
    fp.name:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 1, y + 2) -- 2 px höher: Unterlängen (g, j, y) ragen sonst in die Leiste
    fp.name:SetPoint("RIGHT", fp.classIcon, "LEFT", -2, 0)
    fp.level:ClearAllPoints()
    fp.level:SetPoint("BOTTOMRIGHT", o, "TOPRIGHT", -1, y)
    fp.classIcon:ClearAllPoints()
    fp.classIcon:SetPoint("RIGHT", fp.level, "LEFT", -1, 0)
    local top = y + 13
    local deb = fp.auras.debuffs
    if deb then
        deb:ClearAllPoints()
        deb:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, top + 1)
    end
    local buffs = fp.auras.buffs
    if buffs then
        buffs:ClearAllPoints()
        buffs:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, top + 1 + DebuffRowHeight())
    end
    fp.quest:ClearAllPoints()
    fp.quest:SetPoint("RIGHT", fp.name, "LEFT", -1, 0)
    fp.los:ClearAllPoints()
    fp.los:SetPoint("BOTTOMRIGHT", fp.level, "TOPRIGHT", 0, 1)
    fp.raid:ClearAllPoints()
    local above = top + 3 + DebuffRowHeight() + ((db.buffs and AuraSupported()) and (math.floor(db.buffSize * 0.75 + 0.5) + 2) or 0)
    fp.raid:SetPoint("BOTTOM", o, "TOP", 0, above)
end

local function LayoutAuras(fp)
    local supported = AuraSupported()
    local filters = supported and AuraFilters() or {}
    local want = fp.enemy and fp.unit
    for _, kind in ipairs({ "debuffs", "cc", "buffs" }) do
        local on = supported and want and (AuraSpec(kind))
        local c = fp.auras[kind]
        if on then c = EnsureContainer(fp, kind, filters[kind]) end
        if c then
            if on then
                if kind == "cc" then
                    c:ClearAllPoints()
                    if db.ccLeft then
                        c:SetPoint("RIGHT", fp.overlay, "LEFT", -4, 0)
                    else
                        c:SetPoint("LEFT", fp.overlay, "RIGHT", 4, 0)
                    end
                end
                c:Show()
                if c.fpUnit ~= fp.unit then
                    pcall(c.SetUnit, c, fp.unit)
                    c.fpUnit = fp.unit
                end
            else
                if c.fpUnit then pcall(c.SetUnit, c, nil) c.fpUnit = nil end
                c:Hide()
            end
        end
    end
    PlaceTop(fp)
end

local function ReleaseAuras(fp)
    for _, c in pairs(fp.auras) do
        if c.fpUnit then pcall(c.SetUnit, c, nil) c.fpUnit = nil end
        c:Hide()
    end
end

---------------------------------------------------------------------------
-- Leben, Finishing, Bedrohung
---------------------------------------------------------------------------
local function Abbrev(v)
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok then return s end
    end
    if IsSecret(v) then return v end
    return tostring(v)
end

-- Leistenfarbe: Bedrohung, sonst die Farbe, die Blizzard für seine (unsichtbare) Leiste ausrechnet
local function ApplyBarColor(fp)
    local c = fp.threatCol or fp.baseCol
    if c then fp.bar:SetStatusBarColor(c[1], c[2], c[3]) end
end

local function CopyBlizzardColor(fp)
    local r, g, b = fp.hb:GetStatusBarColor()
    -- gegnerische Spieler (z. B. andere Fraktion): Klassenfarbe statt Blizzards Rot (Einstellung "enemyClassColor");
    -- ist die Klasse gesperrt oder unbekannt, bleibt es bei Blizzards Farbe
    if db.enemyClassColor and fp.enemy and fp.isPlayer and fp.unit then
        local _, class = UnitClass(fp.unit)
        local col = Yes(class) and C_ClassColor and C_ClassColor.GetClassColor(class)
        if col then r, g, b = col.r, col.g, col.b end
    end
    r, g, b = Soften(r, g, b)
    fp.baseCol = { r, g, b }
    ApplyBarColor(fp)
end

-- Schaden der eigenen DoTs auf dem Gegner (Schätzung aus den Zauberbeschreibungen); rot = voraussichtlich tödlich
local function UpdateDot(fp)
    local unit = fp.unit
    local dmg = 0
    if db.dotPrediction and fp.enemy and unit and UI.OverTimeRemaining then
        -- Im Kampf sind Plaketten-Einheiten ("nameplateN") und ihre GUID gesperrt – die Rahmen (Ziel/Fokus) lesen über
        -- "target"/"focus". Darum: ist das diese Plakette (über den Plaketten-Rahmen verglichen, das geht auch im Kampf),
        -- mit "target"/"focus" abfragen wie die Einheitenrahmen.
        local query = unit
        if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
            for _, token in ipairs({ "target", "focus" }) do
                local tp = C_NamePlate.GetNamePlateForUnit(token)
                if tp and tp.UnitFrame and tp.UnitFrame.fpl == fp then query = token break end
            end
        end
        dmg = UI.OverTimeRemaining(query, "damage")
    end
    local bw, bh = fp.bar:GetSize()
    if bw and bw > 0 then fp.dot:SetSize(bw, bh) fp.dotFill:SetSize(bw, bh) end -- Größe sicherstellen (wie bei den Rahmen)
    fp.dot:SetMinMaxValues(0, UnitHealthMax(unit))
    fp.dot:SetValue(dmg)
    fp.dotFill:SetMinMaxValues(0, UnitHealthMax(unit))
    fp.dotFill:SetValue(dmg)
    fp.dotOn = dmg > 0
    if dmg > 0 then
        local cur = UnitHealth(unit)
        if not IsSecret(cur) and cur and dmg >= cur then fp.dot:SetStatusBarColor(1, 0.85, 0.85, 1) fp.dotFill:SetStatusBarColor(1, 0.05, 0.05, 0.8)
        else fp.dot:SetStatusBarColor(1, 0.6, 0.35, 1) fp.dotFill:SetStatusBarColor(0.9, 0.2, 0.1, 0.5) end
    end
end

local function UpdateHealth(fp)
    local unit, d = fp.unit, db
    -- StatusBar verträgt geheime Werte
    fp.bar:SetMinMaxValues(0, UnitHealthMax(unit))
    fp.bar:SetValue(UnitHealth(unit))
    UpdateDot(fp)
    if not d.healthText then
        fp.hpValue:SetText("")
        fp.hpPct:SetText("")
    else
        if d.healthValue then fp.hpValue:SetText(Abbrev(UnitHealth(unit))) else fp.hpValue:SetText("") end
        if d.healthPercent then
            local p
            if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
                p = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
            else
                local h, m = UnitHealth(unit), UnitHealthMax(unit)
                if not IsSecret(h, m) and m and m > 0 then p = h / m * 100 end
            end
            if Has(p) then fp.hpPct:SetFormattedText("%.0f%%", p) else fp.hpPct:SetText("") end
        else
            fp.hpPct:SetText("")
        end
        local a = 1
        if d.healthOnlyDamaged and UnitHealthPercent and NotFullCurve() then
            a = UnitHealthPercent(unit, true, NotFullCurve())
        end
        fp.hpValue:SetAlpha(a)
        fp.hpPct:SetAlpha(a)
    end
    -- Finishing-Bereich
    -- (bei fremd getaggten, für mich grauen Mobs bleibt die Leiste grau: kein Finishing-Bereich)
    local tapped = UnitIsTapDenied and UnitIsTapDenied(unit)
    if d.execute and fp.enemy and UnitHealthPercent and ExecCurve() and (IsSecret(tapped) or not tapped) then
        fp.exec:SetAlpha(UnitHealthPercent(unit, true, ExecCurve()))
    else
        fp.exec:SetAlpha(0)
    end
end

local function ThreatInfo(unit)
    if not UnitDetailedThreatSituation then return end
    local ok, tanking, status, pct = pcall(UnitDetailedThreatSituation, "player", unit)
    if not ok then return end
    -- "tanking" (erster Rückgabewert) = ich habe die Aggro: dann nie Stufe 0/1 (falls die Stufe zu niedrig geliefert wird)
    if not IsSecret(tanking) and tanking == true and not IsSecret(status) and (status == nil or status < 2) then
        status = 3
    end
    return status, pct, tanking
end

local function PlaceThreatText(fp)
    local badge = fp.threatBadge
    badge:ClearAllPoints()
    if db.ccLeft then
        badge:SetPoint("LEFT", fp.overlay, "RIGHT", 4, 0)
    else
        badge:SetPoint("RIGHT", fp.overlay, "LEFT", -4, 0)
    end
end

-- Deckkraft einer Plakette: andere leicht gedämpft, solange ein Ziel gewählt ist (dimOthers), und außerhalb der
-- Reichweite des eigenen Zaubers deutlich blasser (rangeFade). fp.inRange setzt der Reichweiten-Takt (unten);
-- ist der Wert gesperrt (secret), entscheidet Blizzard über SetAlphaFromBoolean.
local RANGE_ALPHA = 0.45
function ns.ApplyPlateAlpha(fp)
    local dim = db.dimOthers and not fp.isTarget and Yes(UnitExists("target"))
    local a = dim and 0.7 or 1
    local inRange = fp.inRange
    if not db.rangeFade or inRange == nil or not fp.enemy then
        fp.root:SetAlpha(a)
    elseif IsSecret(inRange) then
        if fp.root.SetAlphaFromBoolean then fp.root:SetAlphaFromBoolean(inRange, a, a * RANGE_ALPHA) else fp.root:SetAlpha(a) end
    else
        fp.root:SetAlpha(inRange and a or a * RANGE_ALPHA)
    end
end

-- Tank-Vorsprung: wie nah ist der Mitspieler (oder Begleiter) mit der meisten Bedrohung daran, mir die Aggro zu
-- nehmen? Das Spiel liefert für jeden die Prozent bis zum Übernehmen (110 %/130 % schon eingerechnet; 100 = zieht).
-- Rückgabe: höchster Wert (0, wenn keiner), oder nil, wenn ein Wert gesperrt ist (dann bleibt die eigene Anzeige).
local LEAD_SHOW = 60 -- darunter keine Anzeige (bei vielen Gegnern nur die kritischen)
local function GroupLead(unit)
    local best = 0
    local function Check(u)
        if not UnitExists(u) or UnitIsUnit(u, "player") then return true end
        local ok, _, _, pct = pcall(UnitDetailedThreatSituation, u, unit)
        if not ok then return true end
        if IsSecret(pct) then return false end
        if pct and pct > best then best = pct end
        return true
    end
    local raid = IsInRaid()
    local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for i = 1, n do
        if not Check((raid and "raid" or "party") .. i) then return nil end
        if not Check((raid and "raidpet" or "partypet") .. i) then return nil end
    end
    if not Check("pet") then return nil end
    return best
end

local function UpdateThreat(fp)
    local d = db
    local col, show = nil, false
    fp.threatBadge.label:SetText("Aggro")
    if d.threat and fp.enemy and not fp.isPlayer and (IsInGroup() or UnitExists("pet")) then
        local status, pct, tanking = ThreatInfo(fp.unit)
        if IsSecret(status) then
            -- Stufe geheim: nur die Zahl; als Tank färbt Blizzards Farbrechnung nach "habe ich die Aggro?" auch mit
            -- gesperrtem Wert (grün = Aggro, rot = verloren), sonst neutral weiß
            if d.threatText and Has(pct) then
                fp.threatText:SetFormattedText("%.0f%%", pct)
                local colored = false
                if IsTank() and tanking ~= nil and C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean and ColorObj(TANK_TEXT_OK) then
                    colored = pcall(function()
                        local c = C_CurveUtil.EvaluateColorFromBoolean(tanking, ColorObj(TANK_TEXT_OK), ColorObj(TANK_TEXT_LOST))
                        fp.threatText:SetTextColor(c:GetRGBA())
                    end)
                end
                if not colored then fp.threatText:SetTextColor(0.9, 0.9, 0.9) end
                show = true
            end
        elseif status then
            local c
            if d.threatCustom then
                -- eigene Farben: Stufe 0 keine Aggro, 1 Aggro droht, 2 Aggro wackelt, 3 Aggro
                local key = ({ [0] = "threatColNone", "threatColGaining", "threatColLosing", "threatColAggro" })[status]
                c = key and type(d[key]) == "table" and d[key] or nil
            else
                c = (IsTank() and THREAT_TANK or THREAT_DPS)[status]
            end
            if d.threatText and c then
                if Has(pct) then fp.threatText:SetFormattedText("%.0f%%", pct) else fp.threatText:SetText("") end
                -- Text etwas heller als die Leistenfarbe, damit er neben der Leiste lesbar bleibt
                fp.threatText:SetTextColor(math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15))
                show = true
            end
            -- Schadensklassen: Leiste erst färben, wenn es eng wird; Tanks: immer (rot = Aggro verloren)
            -- eigene Farben: jede Stufe färbt (auch "keine Aggro")
            -- Standard (threatColorTankOnly): Farben nur, wenn man in einer Gruppe als Tank eingetragen ist (oder
            -- "Immer als Tank werten"); solo und als Schaden/Heiler bleibt die Leiste ohne Bedrohungsfarbe
            local colorsOn = d.threatColorBar and (not d.threatColorTankOnly or (IsInGroup() and IsTank()))
            if colorsOn and c and (d.threatCustom or IsTank() or status > 0) then col = c end
            if not colorsOn and d.threatText then fp.threatText:SetTextColor(0.9, 0.9, 0.9) end
            -- Als Tank in einer Gruppe: Aggro verloren (Stufe 0/1) = Text rot, unabhängig von den Leistenfarben
            if d.threatText and c and IsInGroup() and IsTank() and status < 2 then
                fp.threatText:SetTextColor(TANK_TEXT_LOST[1], TANK_TEXT_LOST[2], TANK_TEXT_LOST[3])
            end
            -- Als Tank (in einer Gruppe, ich habe die Aggro): statt der eigenen 100 % der Abstand des Nächsten –
            -- "Nächster 85 %"; unter LEAD_SHOW gar nichts (wenig Text an der Seite, auch bei vielen Gegnern)
            if d.threatLead and d.threatText and status >= 2 and IsInGroup() and IsTank() then
                local lead = GroupLead(fp.unit)
                if lead then
                    if lead >= LEAD_SHOW then
                        local lc = THREAT_DPS[lead >= 100 and 3 or (lead >= 85 and 2 or 1)]
                        fp.threatBadge.label:SetText(T("Nächster", "Next"))
                        fp.threatText:SetFormattedText("%.0f%%", lead)
                        fp.threatText:SetTextColor(math.min(1, lc[1] + 0.15), math.min(1, lc[2] + 0.15), math.min(1, lc[3] + 0.15))
                        show = true
                    else
                        show = false
                    end
                end
            end
        end
    end
    fp.threatBadge:SetShown(show)
    fp.threatCol = col
    ApplyBarColor(fp)
end

-- Fehlersuche: /fplates threat – warum ist die Leiste (nicht) in Bedrohungsfarbe? (Ziel wählen, im Kampf aufrufen)
function ns.ThreatDiag()
    local function P(t) UI.Chat("ForeverPlates", t) end
    local function S(v) if IsSecret(v) then return "geheim" end return tostring(v) end
    local d = db
    P(string.format("Rolle: %s | Gruppe: %s | als Tank gewertet: %s | Begleiter: %s", S(UnitGroupRolesAssigned("player")),
        tostring(IsInGroup()), tostring(IsTank()), tostring(UnitExists("pet"))))
    P(string.format("Optionen: Bedrohung %s | Leiste färben %s | nur als Tank %s | eigene Farben %s | immer Tank %s",
        tostring(d.threat), tostring(d.threatColorBar), tostring(d.threatColorTankOnly), tostring(d.threatCustom), tostring(d.threatTank)))
    if not UnitExists("target") then P("Kein Ziel – Gegner anwählen.") return end
    local ok, tanking, status, pct, raw = pcall(UnitDetailedThreatSituation, "player", "target")
    P(string.format("Ziel: aufrufbar %s | tanking %s | Stufe %s | Prozent %s | roh %s", tostring(ok), S(tanking), S(status), S(pct), S(raw)))
    for unit, fp in pairs(plates) do
        if fp.isTarget then
            P(string.format("Plakette %s: Gegner %s | Leistenfarbe aus Bedrohung: %s", unit, tostring(fp.enemy), fp.threatCol and "ja" or "nein"))
        end
    end
end

---------------------------------------------------------------------------
-- Name und Stufe
---------------------------------------------------------------------------
local CLASS_ATLAS = {
    elite = "Interface\\AddOns\\ForeverCore\\Media\\EliteGold", worldboss = "Interface\\AddOns\\ForeverCore\\Media\\EliteGold",
    rareelite = "Interface\\AddOns\\ForeverCore\\Media\\RareEliteSilver", rare = "Interface\\AddOns\\ForeverCore\\Media\\RareSilver",
}
-- Eigene Grafik (Pfad) oder Blizzard-Atlas; false, wenn nicht ladbar
local function SetClassTex(tex, src)
    if src:find("^Interface") then tex:SetTexture(src) tex:SetTexCoord(0, 1, 0, 1) return true end
    return tex:SetAtlas(src)
end
local function UpdateName(fp)
    local unit = fp.unit
    local nm = UnitName(unit)
    if fp.isPlayer and UI.PlayerName then nm = UI.PlayerName(nm) end
    fp.name:SetText(nm)
    local r, g, b = 1, 1, 1
    if fp.isPlayer then
        local _, class = UnitClass(unit)
        local col = Yes(class) and C_ClassColor and C_ClassColor.GetClassColor(class)
        if col then r, g, b = col.r, col.g, col.b end
    end
    fp.name:SetTextColor(r, g, b)
    local cls = UnitClassification and UnitClassification(unit)
    if IsSecret(cls) then cls = nil end
    -- Symbol für Elite/Rar/Boss (Blizzards Drache bzw. Stern); ohne Symbol bleibt nur ein schmaler Platzhalter
    local atlas = db.classIcon and cls and CLASS_ATLAS[cls]
    if atlas and SetClassTex(fp.classIcon, atlas) ~= false then
        fp.classIcon:SetSize(12, 12)
        fp.classIcon:Show()
    else
        fp.classIcon:SetSize(1, 12)
        fp.classIcon:Hide()
        atlas = nil
    end
    if not db.showLevel then fp.level:SetText("") return end
    local level = UnitLevel(unit)
    if IsSecret(level) then fp.level:SetText("") return end
    if not level or level <= 0 then
        fp.level:SetText("??")
        fp.level:SetTextColor(1, 0.2, 0.2)
        return
    end
    -- mit Symbol kein "+"/"R" an der Zahl
    local mark = ""
    if not atlas then
        mark = (cls == "elite" or cls == "rareelite" or cls == "worldboss") and "+" or ""
        if cls == "rare" or cls == "rareelite" then mark = mark .. "R" end
    end
    fp.level:SetText(level .. mark)
    local col = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
    if col then fp.level:SetTextColor(col.r, col.g, col.b) else fp.level:SetTextColor(1, 0.82, 0) end
end

---------------------------------------------------------------------------
-- Zauberleiste
---------------------------------------------------------------------------
local function CastInfo(unit)
    local name, _, _, s, e, _, _, notInt = UnitCastingInfo(unit)
    if Has(name) then return name, s, e, notInt, false end
    if UnitChannelInfo then
        local n2, _, _, s2, e2, _, notInt2 = UnitChannelInfo(unit)
        if Has(n2) then return n2, s2, e2, notInt2, true end
    end
end

CastOnUpdate = function(self)
    local now = GetTime()
    if now >= self.e then
        self:SetScript("OnUpdate", nil)
        self:SetValue(self.channel and self.s or self.e)
        return
    end
    self:SetValue(self.channel and (self.s + self.e - now) or now)
end

local function CastColor(fp)
    local cb = fp.cast
    local notInt = fp.castNotInt
    local free = (db.interruptHint and KickReady()) and COL.castReady or COL.cast
    local tex = cb:GetStatusBarTexture()
    if IsSecret(notInt) then
        if tex.SetVertexColorFromBoolean and ColorObj(free) then
            tex:SetVertexColorFromBoolean(notInt, ColorObj(COL.castLocked), ColorObj(free))
        else
            tex:SetVertexColor(COL.cast[1], COL.cast[2], COL.cast[3])
        end
        if cb.shield.SetAlphaFromBoolean then cb.shield:SetAlphaFromBoolean(notInt, 1, 0) else cb.shield:SetAlpha(0) end
    else
        local c = notInt and COL.castLocked or free
        tex:SetVertexColor(c[1], c[2], c[3])
        cb.shield:SetAlpha(notInt and 1 or 0)
    end
end

local function HidePlaque(fp)
    local tag = fp.cast.tag
    tag.text:SetText("")
    tag:Hide()
    LayoutCastRow(fp)
end

local function UpdateCastTarget(fp)
    local cb = fp.cast
    if not db.castTarget then HidePlaque(fp) return end
    local unit = fp.unit
    local name, class
    if UnitSpellTargetName then
        name = UnitSpellTargetName(unit)
        class = UnitSpellTargetClass and UnitSpellTargetClass(unit)
    end
    if not Has(name) then
        -- kein eigenes Zauberziel: das aktuelle Ziel des Gegners
        local tu = unit .. "target"
        if Yes(UnitExists(tu)) then
            name = UnitName(tu)
            class = nil
            if Yes(UnitIsPlayer(tu)) then class = select(2, UnitClass(tu)) end
        end
    end
    if not Has(name) then HidePlaque(fp) return end
    local tag = cb.tag
    -- Spieler (mit Klasse) gekürzt nach der Hub-Einstellung
    tag.text:SetText((Yes(class) and UI.PlayerName) and UI.PlayerName(name) or name)
    local col = Yes(class) and C_ClassColor and C_ClassColor.GetClassColor(class)
    if col then tag.text:SetTextColor(col.r, col.g, col.b) else tag.text:SetTextColor(1, 1, 1) end
    -- auf mich: "Ziel" rot
    local me = not IsSecret(name) and name == UnitName("player")
    tag.label:SetText(T("Ziel", "Target"))
    if me then tag.label:SetTextColor(1, 0.3, 0.3) else tag.label:SetTextColor(0.62, 0.62, 0.66) end
    tag:Show()
    LayoutCastRow(fp)
end

local function UpdateCast(fp)
    local cb = fp.cast
    if not (db.castbar and fp.enemy and fp.unit) then cb:Hide() return end
    local unit = fp.unit
    local name, s, e, notInt, channel = CastInfo(unit)
    if not Has(name) then
        if not cb.fading then cb:Hide() end
        return
    end
    cb.fading = nil
    cb:SetScript("OnUpdate", nil)
    local timed = false
    local dur
    if channel then
        dur = UnitChannelDuration and UnitChannelDuration(unit)
    else
        dur = UnitCastingDuration and UnitCastingDuration(unit)
    end
    local dirs = Enum and Enum.StatusBarTimerDirection
    if dur and cb.SetTimerDuration and dirs then
        local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
        timed = pcall(cb.SetTimerDuration, cb, dur, interp, channel and dirs.RemainingTime or dirs.ElapsedTime)
    end
    if not timed then
        if cb.ClearTimerDuration then pcall(cb.ClearTimerDuration, cb) end
        if not IsSecret(s, e) and s and e and e > s then
            cb.s, cb.e, cb.channel = s / 1000, e / 1000, channel
            cb:SetMinMaxValues(cb.s, cb.e)
            cb:SetScript("OnUpdate", CastOnUpdate)
            CastOnUpdate(cb)
        else
            cb:SetMinMaxValues(0, 1)
            cb:SetValue(1)
        end
    end
    cb.text:SetText(name)
    cb.text:SetTextColor(1, 1, 1)
    cb.spark:Show()
    fp.castNotInt = notInt
    fp.casting = true
    CastColor(fp)
    UpdateCastTarget(fp)
    cb:Show()
end

local function EndCast(fp, interrupted, by)
    local cb = fp.cast
    if not fp.unit then cb:Hide() return end
    if not interrupted then
        -- "Unterbrochen" wird gerade angezeigt: das gleich folgende "Zauber beendet" nicht drüberzeichnen
        if cb.fading then return end
        -- gleich der nächste Zauber (z. B. Kanalisieren nach dem Wirken)?
        if Has((CastInfo(fp.unit))) then UpdateCast(fp) return end
    end
    -- Bei "unterbrochen" meldet das Spiel den Zauber oft noch kurz als laufend – deshalb dort keine Prüfung auf einen
    -- neuen Zauber (die hat die Anzeige früher sofort überschrieben). Ein wirklich neuer Zauber kommt mit eigenem Start.
    local was = fp.casting or (GetTime() - (cb.ended or 0) < 0.3)
    fp.casting = false
    cb.ended = GetTime()
    if interrupted and was and db.castbar and fp.enemy then
        cb:SetScript("OnUpdate", nil)
        if cb.ClearTimerDuration then pcall(cb.ClearTimerDuration, cb) end
        cb:SetMinMaxValues(0, 1)
        cb:SetValue(1)
        cb:GetStatusBarTexture():SetVertexColor(COL.interrupted[1], COL.interrupted[2], COL.interrupted[3])
        cb.shield:SetAlpha(0)
        cb.spark:Hide()
        HidePlaque(fp)
        -- wer unterbrochen hat: GUID aus dem Ereignis; ist sie geheim, aber ich habe eben selbst unterbrochen -> ich
        local who, whoClass
        if Yes(by) and GetPlayerInfoByGUID then
            local _, class, _, _, _, name = GetPlayerInfoByGUID(by)
            if Yes(name) then who, whoClass = name, Yes(class) and class or nil end
        end
        -- kein Spieler (Begleiter, NPC) oder Spieler ohne Daten: über eine Einheit in der Nähe (Gruppe, Plakette …)
        if not who and Yes(by) and UnitTokenFromGUID then
            local ok, token = pcall(UnitTokenFromGUID, by)
            if ok and Yes(token) then
                local name = UnitName(token)
                if Yes(name) then
                    who = name
                    if Yes(UnitIsPlayer(token)) then whoClass = select(2, UnitClass(token)) end
                end
            end
        end
        if not who and GetTime() - (ns.lastKick or 0) < 0.6 then
            who = UnitName("player")
            whoClass = select(2, UnitClass("player"))
        end
        if who then
            if whoClass and UI.PlayerName then who = UI.PlayerName(who) end
            local col = whoClass and C_ClassColor and C_ClassColor.GetClassColor(whoClass)
            local shown = col and col:WrapTextInColorCode(who) or who
            cb.text:SetText(T("Unterbrochen von ", "Interrupted by ") .. shown)
        else
            cb.text:SetText(T("Unterbrochen", "Interrupted"))
        end
        cb.fading = true
        cb:Show()
        local token = {}
        cb.fadeToken = token
        C_Timer.After(0.8, function()
            if cb.fadeToken == token and cb.fading then
                cb.fading = nil
                cb:Hide()
            end
        end)
    elseif not cb.fading then
        cb:Hide()
    end
end

---------------------------------------------------------------------------
-- Combopunkte (nur auf der Plakette des Ziels), Raidmarker, Questgegner
---------------------------------------------------------------------------
local function ComboCount()
    local pt = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
    local cp, max = UnitPower("player", pt), UnitPowerMax("player", pt)
    if GetComboPoints then
        local ok, onTarget = pcall(GetComboPoints, "player", "target")
        if ok and not IsSecret(onTarget) then cp = onTarget end
    end
    if IsSecret(cp, max) or not max or max <= 0 then return 0, 0 end
    return cp or 0, math.min(max, 7)
end

local function UpdateCombo(fp)
    local cp, max = 0, 0
    if db.combo and fp.enemy and fp.isTarget then cp, max = ComboCount() end
    local shown = cp > 0
    if fp.comboShown ~= shown then
        fp.comboShown = shown
        PlaceTop(fp) -- Name und DoTs rücken über die Combopunkte
    end
    -- als Leiste direkt auf dem Lebensbalken, genauso breit: gleich große Abschnitte mit 1 px Lücke
    local width = fp.overlay:GetWidth() or 0
    if IsSecret(width) then width = 0 end
    local gap = 1
    local seg = max > 0 and (width - (max - 1) * gap) / max or 0
    for i, t in ipairs(fp.combo) do
        if shown and i <= max and seg > 0 then
            t:ClearAllPoints()
            t:SetSize(seg, 4)
            t:SetPoint("BOTTOMLEFT", fp.overlay, "TOPLEFT", (i - 1) * (seg + gap), 2)
            local c = i <= cp and COL.comboOn or COL.comboOff
            t:SetVertexColor(c[1], c[2], c[3], 1)
            t:Show()
            t.edge:Show()
        else
            t:Hide()
            t.edge:Hide()
        end
    end
end

local function UpdateRaid(fp)
    local idx
    if db.raidMarker and fp.unit then
        idx = GetRaidTargetIndex(fp.unit)
        if IsSecret(idx) then idx = nil end
    end
    if idx and SetRaidTargetIconTexture then
        local size = db.raidMarkerSize
        fp.raid:SetSize(size, size)
        SetRaidTargetIconTexture(fp.raid, idx)
        fp.raid:Show()
    else
        fp.raid:Hide()
    end
end

-- Questgegner: Quest-Zeilen im Tooltip der Einheit (eigene, noch offene Ziele), sonst Blizzards Abfrage
local function IsQuestUnit(unit)
    if Yes(UnitIsPlayer(unit)) then return false end
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        local ok, s = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
        if ok and Yes(s) then return false end
    end
    local LT = Enum and Enum.TooltipDataLineType
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
    local lines = type(data) == "table" and data.lines
    if lines and LT then
        local me, guid = UnitName("player"), UnitGUID("player")
        local any, mine = false, true
        for _, line in ipairs(lines) do
            local t = line.type
            if IsSecret(t) then break end
            if t == LT.QuestTitle then
                any, mine = true, true
            elseif t == LT.QuestPlayer then
                mine = (not IsSecret(line.guid) and line.guid == guid) or (not IsSecret(line.leftText) and line.leftText == me)
            elseif t == LT.QuestObjective then
                any = true
                local txt = line.leftText
                local done = line.completed == true
                if not done and type(txt) == "string" and not IsSecret(txt) then
                    local cur, goal = txt:match("(%d+)%s*/%s*(%d+)")
                    if cur then
                        done = tonumber(cur) >= tonumber(goal)
                    else
                        local pct = txt:match("(%d+)%s*%%")
                        done = pct ~= nil and tonumber(pct) >= 100
                    end
                end
                if mine and not done then return true end
            end
        end
        if any then return false end
    end
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, r = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        return ok and Yes(r)
    end
    return false
end

-- Questie: dessen Symbol (Schwert = töten, Hand = einsammeln …) an unserem Platz vor dem Namen. Questies eigenes
-- Plaketten-Symbol hängt am Plaketten-Rahmen und läge sonst neben unserer Aggro-Anzeige – es wird solange
-- abgeschaltet (wie Questies Tracker in ForeverQuests) und wieder eingeschaltet, wenn wir die Markierung abschalten.
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local questieNameplate
local function QuestieNameplate()
    if questieNameplate == nil then
        questieNameplate = false
        local loader = _G.QuestieLoader
        if type(loader) == "table" and type(loader.ImportModule) == "function" then
            local ok, mod = pcall(loader.ImportModule, loader, "QuestieNameplate")
            if ok and type(mod) == "table" and type(mod.GetIcon) == "function" then questieNameplate = mod end
        end
    end
    return questieNameplate or nil
end

function ns.ApplyQuestie()
    local q = _G.Questie
    local profile = type(q) == "table" and q.db and q.db.profile
    if not profile then return end
    local d = GetDB()
    if d.quest then
        if profile.nameplateEnabled then
            profile.nameplateEnabled = false
            d._questieNameplateOff = true
            local mod = QuestieNameplate()
            if mod and mod.HideCurrentFrames then pcall(mod.HideCurrentFrames, mod) end
        end
    elseif d._questieNameplateOff then
        profile.nameplateEnabled = true
        d._questieNameplateOff = nil
    end
end

local function QuestieIcon(unit)
    local mod = QuestieNameplate()
    if not mod then return end
    local guid = UnitGUID(unit)
    if not guid or IsSecret(guid) then return end
    local ok, icon = pcall(mod.GetIcon, guid)
    if ok and icon and not IsSecret(icon) then return icon end
end

local function UpdateQuest(fp)
    local show = false
    if db.quest and fp.unit and fp.enemy and not fp.isPlayer then
        local icon = QuestieIcon(fp.unit)
        if icon then
            fp.quest:SetTexture(icon)
            show = true
        elseif IsQuestUnit(fp.unit) then
            fp.quest:SetTexture(QUEST_ICON)
            show = true
        end
    end
    fp.quest:SetShown(show)
end

---------------------------------------------------------------------------
-- Looks: "Forever" (flach, dunkel, feiner Rand) und "Klassisch" (Blizzard-Leiste mit Glanz); Ziel mit Goldrand
---------------------------------------------------------------------------
-- ignoriert unsere Plakette Blizzards Skalierung, braucht sie selbst die Oberflächen-Skalierung
local fp_ignoreScale = CreateFrame("Frame").SetIgnoreParentScale ~= nil

local function UIScale()
    if not fp_ignoreScale then return 1 end
    local s = UIParent:GetEffectiveScale()
    return (not IsSecret(s) and s and s > 0) and s or 1
end

local function ApplyLook(fp)
    local forever = db.skin
    local tex = Look()
    fp.bar:SetStatusBarTexture(tex)
    fp.cast:SetStatusBarTexture(tex)
    if forever then
        fp.bg:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.9)
    else
        fp.bg:SetColorTexture(0, 0, 0, 0.55)
    end
    fp.gloss:SetShown(forever)
    local e = fp.isTarget and C.accent or { 0, 0, 0 }
    SetEdgesColor(fp.edges, e[1], e[2], e[3], (forever or fp.isTarget) and 1 or 0.8)
    -- Ziel etwas größer, die anderen leicht gedämpft (solange ein Ziel gewählt ist)
    fp.root:SetScale(UIScale() * (fp.isTarget and (db.targetScale / 100) or 1))
    ns.ApplyPlateAlpha(fp)
    -- Status-Textur kann neu sein: Finishing-Farbe und Glanz wieder daran
    tex = fp.bar:GetStatusBarTexture()
    local ec = type(db.executeColor) == "table" and db.executeColor or ns.DEFAULTS.executeColor
    fp.exec:SetColorTexture(ec[1] or 1, ec[2] or 0.2, ec[3] or 0.85, 1)
    fp.exec:ClearAllPoints()
    fp.exec:SetAllPoints(tex)
    fp.gloss:ClearAllPoints()
    fp.gloss:SetPoint("TOPLEFT", tex, "TOPLEFT")
    fp.gloss:SetPoint("TOPRIGHT", tex, "TOPRIGHT")
    fp.gloss:SetHeight(3)
end

-- Breite wie Blizzards Leiste (= Klickfläche) oder fest eingestellt
local function Resize(fp)
    local w = db.width
    if not w or w <= 0 then
        w = fp.hb:GetWidth()
        if IsSecret(w) or not w or w < 30 then w = 110 end
    end
    fp.root:SetSize(w, db.barHeight)
    -- höher setzen (Blizzards Klickfläche bleibt an ihrem Platz, sie ist ohnehin größer als die Leiste)
    fp.root:ClearAllPoints()
    fp.root:SetPoint("CENTER", fp.hb, "CENTER", 0, db.offsetY or 0)
end

---------------------------------------------------------------------------
-- Plakette befüllen / leeren
---------------------------------------------------------------------------
local function UpdateTargetState(fp)
    local t = UnitIsUnit(fp.unit, "target")
    fp.isTarget = Yes(t)
end

local function ReleaseOwn(fp)
    ReleaseAuras(fp)
    fp.cast:SetScript("OnUpdate", nil)
    fp.cast:Hide()
    fp.root:Hide()
end

local function Refresh(fp)
    if not fp.unit then return end
    local unit = fp.unit
    local can = UnitCanAttack("player", unit)
    fp.enemy = IsSecret(can) or can and true or false
    fp.isPlayer = Yes(UnitIsPlayer(unit))
    -- Verbündete: Blizzards Plakette wie gewohnt
    if not fp.enemy then
        Mute(fp.frame, false)
        ReleaseOwn(fp)
        return
    end
    Mute(fp.frame, true)
    UpdateTargetState(fp)
    fp.Resize = Resize
    fp.Relayout = function()
        LayoutCastRow(fp)
        UpdateCombo(fp)
        PlaceTop(fp)
    end
    Resize(fp)
    fp.root:Show()
    ApplyLook(fp)
    CopyBlizzardColor(fp)
    LayoutCastRow(fp)
    PlaceThreatText(fp)
    UpdateName(fp)
    UpdateHealth(fp)
    UpdateThreat(fp)
    UpdateCombo(fp)
    UpdateCast(fp)
    UpdateRaid(fp)
    UpdateQuest(fp)
    LayoutAuras(fp)
end

local function Attach(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit, issecure and issecure())
    local frame = plate and plate.UnitFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local fp = Setup(plate, frame)
    if not fp then return end
    -- falls die Plakette noch unter altem Namen geführt wird
    if fp.unit and plates[fp.unit] == fp then plates[fp.unit] = nil end
    fp.unit = unit
    fp.threatCol = nil
    fp.casting = false
    fp.cast.fading = nil
    plates[unit] = fp
    Refresh(fp)
end

local function Detach(unit)
    local fp = plates[unit]
    if not fp then return end
    plates[unit] = nil
    ReleaseOwn(fp)
    fp.unit = nil
end

if UI.On then UI.On("NameStyleChanged", function() if ns.ApplyAll then ns.ApplyAll() end end) end

function ns.ApplyAll()
    GetDB()
    ApplyFonts()
    for _, fp in pairs(plates) do Refresh(fp) end
end

-- Blizzard rechnet die Leistenfarbe neu (Reaktion, angetippt …): auf unsere Leiste übernehmen
if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local fp = frame and frame.fpl
        if fp and fp.unit and fp.enemy then CopyBlizzardColor(fp) end
    end)
end

---------------------------------------------------------------------------
-- Verbündete: Blizzards eigene Schalter "nur Name" und "Name in Klassenfarbe" (vorherige Werte werden gemerkt)
---------------------------------------------------------------------------
-- Schalter -> { gewünschter Wert, Einstellung, die ihn einschaltet }
local FRIEND_CVARS = {
    nameplateShowOnlyNameForFriendlyPlayerUnits = { "1", "friendlySimple" },
    nameplateUseClassColorForFriendlyPlayerUnitNames = { "1", "friendlySimple" },
    nameplateMotion = { "1", "stack" },            -- 1 = stapeln, 0 = überlappen
    -- das Spiel verkleinert Plaketten mit der Entfernung (eigene Skalierung, nicht abschaltbar per Addon-Rahmen):
    -- kleinste und größte Größe gleich -> immer volle Größe, Schrift bleibt lesbar
    nameplateMinScale = { "1", "noShrink" },
    nameplateMaxScale = { "1", "noShrink" },
}
function ns.ApplyFriendly()
    UI.AfterCombat("ForeverPlatesFriendly", function()
        local d = GetDB()
        d._savedCVars = d._savedCVars or {}
        for cvar, info in pairs(FRIEND_CVARS) do
            local want, key = info[1], info[2]
            local cur = C_CVar.GetCVar(cvar)
            if cur ~= nil then
                if d[key] then
                    if cur ~= want then
                        if d._savedCVars[cvar] == nil then d._savedCVars[cvar] = cur end
                        C_CVar.SetCVar(cvar, want)
                    end
                elseif d._savedCVars[cvar] ~= nil then
                    C_CVar.SetCVar(cvar, d._savedCVars[cvar])
                    d._savedCVars[cvar] = nil
                end
            end
        end
    end, "ForeverPlates")
end

---------------------------------------------------------------------------
-- Schadenszahlen: Blizzard zeichnet sie selbst in der Spielwelt (kein Rahmen, nicht an die Plakette hängbar).
-- Über Blizzards eigene Einstellungen starten sie weiter oben – über der Plakette statt dahinter; Stil und
-- Bewegung bleiben Blizzards. Zusatz (erst zuschalten): Größe, Dauer, Bogen, Streuung, klassischer Stil.
-- Vorherige Werte werden gemerkt (_savedCVars) und beim Abschalten zurückgesetzt.
-- Namen im Forever-Client mit "_v2" (per /run geprüft, 2026-10-20).
---------------------------------------------------------------------------
local function Num(v) return string.format("%.3f", v) end
local WORLD_CVARS = {
    WorldTextScreenY_v2 = function(d) return d.dmgRaise and Num(d.dmgHeight / 100) end,
    WorldTextCritScreenY_v2 = function(d) return d.dmgRaise and Num(d.dmgHeight / 100) end,
    WorldTextScale_v2 = function(d) return d.dmgCustom and Num(d.dmgScale / 100) end,
    WorldTextRampDuration_v2 = function(d) return d.dmgCustom and Num(d.dmgDuration / 10) end,
    WorldTextGravity_v2 = function(d) return d.dmgCustom and Num(d.dmgGravity / 100) end,
    WorldTextRandomXY_v2 = function(d) return d.dmgCustom and Num(d.dmgSpread / 100) end,
    classicStyleWorldText = function(d) return d.dmgCustom and d.dmgClassic and "1" end,
}
local function Same(a, b)
    local x, y = tonumber(a), tonumber(b)
    if x and y then return math.abs(x - y) < 0.0005 end
    return a == b
end
function ns.ApplyWorldText()
    UI.AfterCombat("ForeverPlatesWorldText", function()
        local d = GetDB()
        d._savedCVars = d._savedCVars or {}
        for cvar, wantFn in pairs(WORLD_CVARS) do
            local cur = C_CVar.GetCVar(cvar)
            if cur ~= nil then -- gibt es die Einstellung in diesem Client?
                local want = wantFn(d)
                if want then
                    if not Same(cur, want) then
                        if d._savedCVars[cvar] == nil then d._savedCVars[cvar] = cur end
                        C_CVar.SetCVar(cvar, want)
                    end
                elseif d._savedCVars[cvar] ~= nil then
                    C_CVar.SetCVar(cvar, d._savedCVars[cvar])
                    d._savedCVars[cvar] = nil
                end
            end
        end
    end, "ForeverPlates")
end

---------------------------------------------------------------------------
-- Reichweite (rangeFade): alle 0,2 s über den gemeinsamen Takt des Hubs, nur für sichtbare Gegner-Plaketten.
-- Maßstab ist ein Zauber der eigenen Klasse (Name -> höchster bekannter Rang), Nahkämpfer: automatischer Angriff.
-- Die Sichtlinie kann das Spiel vorab nicht prüfen – nur die Entfernung.
---------------------------------------------------------------------------
local RANGE_SPELLS = {
    MAGE = { 133, 116, 5143 }, WARLOCK = { 686, 172 }, PRIEST = { 585, 589 }, DRUID = { 5176, 8921 },
    SHAMAN = { 403, 8042 }, HUNTER = { 75, 3044 },
}
local MELEE_SPELL = 6603 -- automatischer Angriff
local rangeSpell
local function FindRangeSpell()
    rangeSpell = nil
    local _, class = UnitClass("player")
    for _, id in ipairs(RANGE_SPELLS[class] or {}) do
        local known = (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id)) or (IsSpellKnown and IsSpellKnown(id))
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if known and name then rangeSpell = name return end
    end
    rangeSpell = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(MELEE_SPELL) or nil
end
local function InRange(unit)
    if not (rangeSpell and C_Spell and C_Spell.IsSpellInRange) then return nil end
    local ok, r = pcall(C_Spell.IsSpellInRange, rangeSpell, unit)
    if not ok then return nil end
    return r -- true/false, nil = nicht prüfbar (dann nicht dämpfen), evtl. geheim
end
UI.Every(0.2, function()
    for _, fp in pairs(plates) do
        if fp.enemy and fp.unit then
            local r = InRange(fp.unit)
            if IsSecret(r) or r ~= fp.inRange then
                fp.inRange = r
                ns.ApplyPlateAlpha(fp)
            end
        end
    end
end, { addon = "ForeverPlates", name = "Reichweite", when = function() return db and db.rangeFade and next(plates) ~= nil end })
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("SPELLS_CHANGED")
    f:SetScript("OnEvent", function() pcall(FindRangeSpell) end)
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local function ForAll(fn)
    for _, fp in pairs(plates) do fn(fp) end
end

local questPending = false
local function QueueQuest()
    if questPending then return end
    questPending = true
    C_Timer.After(0.4, function()
        questPending = false
        for _, fp in pairs(plates) do UpdateQuest(fp) end
    end)
end

local function ClearLos()
    for _, fp in pairs(plates) do fp.los:Hide() end
end

local H = {}
H.NAME_PLATE_UNIT_ADDED = function(unit) Attach(unit) end
H.NAME_PLATE_UNIT_REMOVED = function(unit) Detach(unit) end
H.PLAYER_TARGET_CHANGED = function()
    ClearLos()
    ForAll(function(fp)
        UpdateTargetState(fp)
        UpdateCombo(fp)
        if fp.enemy and fp.unit then ApplyLook(fp) UpdateDot(fp) end
    end)
end
H.UNIT_HEALTH = function(unit) local fp = plates[unit] if fp and fp.enemy then UpdateHealth(fp) end end
H.UNIT_MAXHEALTH = H.UNIT_HEALTH
H.UNIT_FLAGS = H.UNIT_HEALTH -- Tap-Status (grau/getaggt) ändert sich -> Finishing-Bereich neu entscheiden
H.UNIT_AURA = function(unit) local fp = plates[unit] if fp and fp.enemy and db.dotPrediction then UpdateDot(fp) end end
if UI.OnOverTimeChange then UI.OnOverTimeChange(function() for _, fp in pairs(plates) do if fp.enemy and fp.unit then UpdateDot(fp) end end end) end
C_Timer.NewTicker(1, function() for _, fp in pairs(plates) do if fp.dotOn and fp.unit then UpdateDot(fp) end end end)
H.UNIT_THREAT_LIST_UPDATE = function(unit) local fp = plates[unit] if fp then UpdateThreat(fp) end end
H.UNIT_THREAT_SITUATION_UPDATE = function() for _, fp in pairs(plates) do UpdateThreat(fp) end end
H.PLAYER_REGEN_ENABLED = H.UNIT_THREAT_SITUATION_UPDATE
H.PLAYER_REGEN_DISABLED = H.UNIT_THREAT_SITUATION_UPDATE
H.PLAYER_ROLES_ASSIGNED = H.UNIT_THREAT_SITUATION_UPDATE
H.GROUP_ROSTER_UPDATE = H.UNIT_THREAT_SITUATION_UPDATE
H.UNIT_FACTION = function(unit) local fp = plates[unit] if fp then Refresh(fp) end end
H.UNIT_NAME_UPDATE = function(unit) local fp = plates[unit] if fp and fp.enemy then UpdateName(fp) end end
H.UNIT_LEVEL = H.UNIT_NAME_UPDATE
H.UNIT_CLASSIFICATION_CHANGED = H.UNIT_NAME_UPDATE
local function CastStart(unit) local fp = plates[unit] if fp then UpdateCast(fp) end end
local function CastStop(unit) local fp = plates[unit] if fp then EndCast(fp, false) end end
H.UNIT_SPELLCAST_START = CastStart
H.UNIT_SPELLCAST_CHANNEL_START = CastStart
H.UNIT_SPELLCAST_DELAYED = CastStart
H.UNIT_SPELLCAST_CHANNEL_UPDATE = CastStart
H.UNIT_SPELLCAST_EMPOWER_START = CastStart
H.UNIT_SPELLCAST_STOP = CastStop
H.UNIT_SPELLCAST_EMPOWER_STOP = CastStop
H.UNIT_SPELLCAST_FAILED = CastStop
H.UNIT_SPELLCAST_INTERRUPTED = function(unit, _, _, by) local fp = plates[unit] if fp then EndCast(fp, true, by) end end
-- Kanalisieren: ein Unterbrecher im Ereignis heißt "unterbrochen"
H.UNIT_SPELLCAST_CHANNEL_STOP = function(unit, _, _, by)
    local fp = plates[unit]
    if fp then EndCast(fp, Has(by), by) end
end
H.UNIT_SPELLCAST_INTERRUPTIBLE = function(unit)
    local fp = plates[unit]
    if fp and fp.casting then fp.castNotInt = false CastColor(fp) end
end
H.UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(unit)
    local fp = plates[unit]
    if fp and fp.casting then fp.castNotInt = true CastColor(fp) end
end
H.UNIT_TARGET = function(unit) local fp = plates[unit] if fp and fp.casting then UpdateCastTarget(fp) end end
H.SPELL_UPDATE_COOLDOWN = function()
    if not db.interruptHint then return end
    for _, fp in pairs(plates) do if fp.casting then CastColor(fp) end end
end
H.SPELLS_CHANGED = function() FindKick() end
H.UI_ERROR_MESSAGE = function(_, msg)
    if not db.los or IsSecret(msg) or msg ~= SPELL_FAILED_LINE_OF_SIGHT then return end
    for _, fp in pairs(plates) do
        if fp.isTarget and fp.enemy then
            fp.los:Show()
            local token = {}
            fp.losToken = token
            C_Timer.After(3, function() if fp.losToken == token then fp.los:Hide() end end)
        end
    end
end
-- ein Zauber hat geklappt: Sicht ist wieder da
H.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit ~= "player" then return end
    ClearLos()
    -- eigene Unterbrechung merken (falls das Spiel den Unterbrecher geheim hält)
    if kickSpell and not IsSecret(spellID) and spellID == kickSpell then ns.lastKick = GetTime() end
end
H.UNIT_POWER_FREQUENT = function(unit, powerType)
    if unit ~= "player" or IsSecret(powerType) or powerType ~= "COMBO_POINTS" then return end
    for _, fp in pairs(plates) do if fp.isTarget then UpdateCombo(fp) end end
end

H.RAID_TARGET_UPDATE = function() for _, fp in pairs(plates) do UpdateRaid(fp) end end
H.QUEST_LOG_UPDATE = QueueQuest
H.UNIT_QUEST_LOG_CHANGED = QueueQuest
H.QUEST_ACCEPTED = QueueQuest
H.QUEST_REMOVED = QueueQuest

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, ...)
    local fn = H[event]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then UI.ReportError("ForeverPlates", event, err) end
    end
end)

local started = false
function ns.Start()
    if started then return end
    started = true
    GetDB()
    FindKick()
    -- Diese Ereignisse wertet nur der Spieler aus ("unit ~= player" -> zurück): nicht für jede Einheit wecken lassen
    local playerOnly = { UNIT_SPELLCAST_SUCCEEDED = true, UNIT_POWER_FREQUENT = true, UNIT_QUEST_LOG_CHANGED = true }
    for event in pairs(H) do
        if playerOnly[event] then pcall(ev.RegisterUnitEvent, ev, event, "player")
        else pcall(ev.RegisterEvent, ev, event) end
    end
    ns.ApplyFriendly()
    ns.ApplyWorldText()
    ns.ApplyQuestie()
    C_Timer.After(3, function() pcall(ns.ApplyQuestie) end) -- Questie legt seine Einstellungen evtl. erst später an
    for _, plate in pairs(C_NamePlate.GetNamePlates(issecure and issecure()) or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and not IsSecret(unit) then Attach(unit) end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Safe("Start", function() ns.Start() end))

UI.RegisterSettings({ addon = "ForeverPlates", sv = "ForeverPlatesDB", defaults = ns.DEFAULTS, version = 1 })
