-- ForeverCast – Look.lua: Optik aller Leisten (eigene Zauberleiste, Ziel/Fokus, Atem/Erschöpfung).
--   "forever" (Standard): flach und dunkel mit feinem Rand und Goldlinie oben wie die Forever-Fenster, gedämpfte
--                         Farben; Textur und Schrift wie ForeverFrames (falls aktiv), sonst Raid-Textur und Friz.
--   "clean":              der frühere Look – Blizzards Balken-Textur, weicher bronzener Tooltip-Rand, kräftige Farben.
-- Wird VOR ForeverCast.lua geladen: die Farbtabellen (ns.COLORS) werden dort direkt benutzt und hier beim Wechsel
-- nur umgefüllt. Rahmen, Balken und Texte melden sich an (StyleBox/StyleBar/Text) und werden bei ns.Restyle() neu
-- gezeichnet.
local _, ns = ...
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CLEAN_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local FOREVER_TEX = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
local FOREVER_FONT = "Fonts\\FRIZQT__.TTF"

local SOFT_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

ns.LOOKS = {
    { key = "forever", label = T("Forever (flach, Goldlinie)", "Forever (flat, gold line)") },
    { key = "clean",   label = T("Clean (bisheriger Look)", "Clean (previous look)") },
}

local PALETTE = {
    clean = {
        cast = { 1, 0.7, 0 }, channel = { 0.3, 0.6, 1 }, queue = { 0.2, 1, 0.2 }, fail = { 1, 0.15, 0.15 },
        idle = { 0.4, 0.4, 0.4 }, flight = { 0.6, 0.45, 1 }, locked = { 0.6, 0.6, 0.6 },
        breath = { 0, 0.5, 1 }, exhaustion = { 1, 0.9, 0 }, feign = { 1, 0.7, 0 },
    },
    forever = {
        cast = { 0.86, 0.66, 0.26 }, channel = { 0.36, 0.56, 0.86 }, queue = { 0.38, 0.78, 0.42 },
        fail = { 0.78, 0.26, 0.24 }, idle = { 0.32, 0.32, 0.34 }, flight = { 0.56, 0.46, 0.84 },
        locked = { 0.5, 0.5, 0.54 }, breath = { 0.32, 0.56, 0.9 }, exhaustion = { 0.88, 0.62, 0.22 },
        feign = { 0.86, 0.7, 0.3 },
    },
}

-- feste Tabellen, deren Inhalt beim Look-Wechsel ausgetauscht wird (ForeverCast.lua hält Verweise darauf)
ns.COLORS = {}
for k in pairs(PALETTE.forever) do ns.COLORS[k] = {} end

function ns.LookMode()
    local d = _G.ForeverCastDB
    return (type(d) == "table" and d.look == "clean") and "clean" or "forever"
end

local function ApplyPalette()
    local p = PALETTE[ns.LookMode()]
    for k, c in pairs(p) do
        local t = ns.COLORS[k]
        t[1], t[2], t[3] = c[1], c[2], c[3]
    end
end
ApplyPalette()

-- Textur, Schrift, Umriss (Forever-Look: wie ForeverFrames, falls aktiv)
function ns.Media()
    if ns.LookMode() == "clean" then return CLEAN_TEX, nil, nil end
    if type(_G.ForeverFramesLook) == "function" then
        local ok, look = pcall(_G.ForeverFramesLook)
        if ok and type(look) == "table" and look.texture and look.font then
            return look.texture, look.font, look.outline or ""
        end
    end
    return FOREVER_TEX, FOREVER_FONT, ""
end

local boxes, bars, texts = {}, {}, {}

local function Inset(region, px, parent)
    if not region then return end
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", px, -px)
    region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -px, px)
end

local function ApplyBox(f, inner)
    if ns.LookMode() == "clean" then
        if f.fcSkin then
            f.fcSkin.bg:Hide()
            for _, e in ipairs(f.fcSkin.edges) do e:Hide() end
        end
        if f.SetBackdrop then
            f:SetBackdrop(SOFT_BACKDROP)
            f:SetBackdropColor(0, 0, 0, 0.55)
            f:SetBackdropBorderColor(0.6, 0.55, 0.45, 0.7)
        end
        Inset(inner, 3, f)
        return
    end
    if f.SetBackdrop then f:SetBackdrop(nil) end
    local s = f.fcSkin
    if not s then
        s = { edges = {} }
        s.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        s.bg:SetAllPoints()
        local sides = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
            { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }
        for i, side in ipairs(sides) do
            local e = f:CreateTexture(nil, "BORDER", nil, 7)
            e:SetTexture(WHITE)
            e:SetPoint(side[1])
            e:SetPoint(side[2])
            if side[3] then e:SetHeight(1) else e:SetWidth(1) end
            s.edges[i] = e
        end
        f.fcSkin = s
    end
    s.bg:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.8)
    s.bg:Show()
    for i, e in ipairs(s.edges) do
        if i == 1 then
            e:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7) -- Goldlinie oben
        else
            e:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
        end
        e:Show()
    end
    Inset(inner, 1, f)
end

-- Rahmen (mit BackdropTemplate) im aktuellen Look; inner = Balken/Symbol darin (Abstand zum Rand je Look)
function ns.StyleBox(f, inner)
    boxes[f] = inner or false
    ApplyBox(f, inner or nil)
end

function ns.StyleBar(bar)
    bars[bar] = true
    bar:SetStatusBarTexture((ns.Media()))
end

-- Text in Grundgröße; im Clean-Look Blizzards Schriftobjekte wie früher
local function ApplyText(fs, size)
    local _, font, outline = ns.Media()
    if not font then
        fs:SetFontObject(size >= 12 and "GameFontHighlight" or "GameFontHighlightSmall")
        return
    end
    if not pcall(fs.SetFont, fs, font, size, outline) then pcall(fs.SetFont, fs, FOREVER_FONT, size, outline) end
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(outline == "" and 1 or 0, outline == "" and -1 or 0)
end

function ns.Text(fs, size)
    texts[fs] = size
    ApplyText(fs, size)
end

-- alles neu im aktuellen Look (Wechsel im Menü, ForeverFrames-Optik geändert)
function ns.Restyle()
    ApplyPalette()
    for f, inner in pairs(boxes) do ApplyBox(f, inner or nil) end
    local tex = ns.Media()
    for bar in pairs(bars) do bar:SetStatusBarTexture(tex) end
    for fs, size in pairs(texts) do ApplyText(fs, size) end
    if ns.OnRestyle then ns.OnRestyle() end
end

---------------------------------------------------------------------------
-- "Unterbrochen von Name" (eigene Leiste und Ziel/Fokus)
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function Yes(v) if v == nil or issecret(v) then return nil end return v end

function ns.InterruptedText(by)
    local who, class
    if Yes(by) and GetPlayerInfoByGUID then
        local _, c, _, _, _, name = GetPlayerInfoByGUID(by)
        if Yes(name) then who, class = name, Yes(c) end
    end
    -- kein Spieler (NPC, Begleiter) oder ohne Daten: über eine Einheit in der Nähe (Ziel, Plakette, Gruppe …)
    if not who and Yes(by) and UnitTokenFromGUID then
        local ok, token = pcall(UnitTokenFromGUID, by)
        if ok and Yes(token) then
            local name = UnitName(token)
            if Yes(name) then
                who = name
                if Yes(UnitIsPlayer(token)) then class = Yes((select(2, UnitClass(token)))) end
            end
        end
    end
    if not who then return T("Unterbrochen", "Interrupted") end
    if class and UI.PlayerName then who = UI.PlayerName(who) end
    local col = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    return T("Unterbrochen von ", "Interrupted by ") .. (col and col:WrapTextInColorCode(who) or who)
end
