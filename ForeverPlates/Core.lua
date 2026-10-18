-- ForeverPlates (Prototyp): Blizzards Namensplaketten verbessern – Leben in % und als Zahl, Bedrohung mit Prozent
-- (Leiste färbt sich je nach Rolle), schmale eigene Zauberleiste mit Ziel-Plakette und Unterbrechen-Hinweis, eigene
-- DoTs oben, Kontrolleffekte (CC) groß an der Seite, Buffs wahlweise, Finishing-Bereich, Combopunkte auf dem Ziel,
-- Questgegner, große Raidmarker und schlichte Plaketten für Verbündete. Schalter "Forever-Stil": dieselben Plaketten
-- im Look der Forever-Fenster (flache Leiste, dunkler Grund, feiner Rand, Ziel mit Goldrand).
-- Regeln: Blizzards Teile werden nie versteckt oder umgehängt (nur durchsichtig gemacht), eigene Teile liegen auf
-- einer eigenen Ebene darüber. Geheime Werte (Leben, Bedrohung, Zauberinfos) gehen nur in Anzeige-Funktionen
-- (SetText, SetAlpha, SetTimerDuration, …FromBoolean) und werden nie verglichen oder verrechnet.
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SHIELD = "Interface\\AddOns\\ForeverPlates\\Media\\Shield"
local FONT = STANDARD_TEXT_FONT

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------
ns.DEFAULTS = {
    skin = false,             -- Stufe 2: Forever-Stil
    healthText = true,        -- Leben auf der Leiste
    healthValue = true,       --   als Zahl (links)
    healthPercent = true,     --   in Prozent (rechts)
    healthOnlyDamaged = false,-- nur wenn nicht voll
    healthFriendly = false,   -- auch bei Verbündeten
    threat = true,            -- Bedrohung
    threatText = true,        --   Prozent neben der Leiste
    threatColorBar = true,    --   Leiste in Bedrohungsfarbe
    threatTank = false,       --   immer als Tank werten (sonst: Gruppenrolle)
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
    combo = true,             -- Combopunkte auf dem Ziel
    friendlySimple = true,    -- Verbündete: nur Name in Klassenfarbe
    quest = true,             -- Questgegner-Symbol
    raidMarker = true,        -- großer Raidmarker über der Plakette
    raidMarkerSize = 26,
    minimapAngle = 320,
}

local db
local function GetDB()
    if type(_G.ForeverPlatesDB) ~= "table" then _G.ForeverPlatesDB = db or {} end
    db = _G.ForeverPlatesDB
    for k, v in pairs(ns.DEFAULTS) do
        if db[k] == nil then db[k] = v end
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
local COL = {
    cast = { 1, 0.72, 0.2 },          -- unterbrechbar
    castReady = { 0.35, 0.9, 0.45 },  -- unterbrechbar und meine Unterbrechung ist bereit
    castLocked = { 0.5, 0.5, 0.55 },  -- nicht unterbrechbar
    interrupted = { 0.9, 0.25, 0.25 },
    execute = { 0.95, 0.3, 0.55 },
    comboOn = { 1, 0.82, 0.15 },
    comboOff = { 0.12, 0.12, 0.14 },
}
-- Bedrohung: Status 0 = wenig, 1 = mehr als der Tank (noch nicht übernommen), 2 = Aggro wackelt, 3 = sichere Aggro
local THREAT_DPS = { [0] = { 0.55, 0.85, 0.55 }, [1] = { 1, 0.85, 0.2 }, [2] = { 1, 0.5, 0.1 }, [3] = { 1, 0.22, 0.22 } }
local THREAT_TANK = { [0] = { 1, 0.22, 0.22 }, [1] = { 1, 0.5, 0.1 }, [2] = { 1, 0.85, 0.2 }, [3] = { 0.3, 0.85, 0.45 } }

local colorObj = {}
local function ColorObj(c)
    local o = colorObj[c]
    if not o and CreateColor then
        o = CreateColor(c[1], c[2], c[3], 1)
        colorObj[c] = o
    end
    return o
end

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

local function Font(fs, size, flags)
    fs:SetFont(FONT, size, flags or "OUTLINE")
    fs:SetShadowOffset(0, 0)
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
    -- nicht unterbrechbar: kleines Schild links vor der Leiste
    cb.shield = cb:CreateTexture(nil, "OVERLAY")
    cb.shield:SetAtlas("nameplates-InterruptShield")
    cb.shield:SetSize(10, 12)
    cb.shield:SetPoint("RIGHT", cb, "LEFT", -1, 0)
    cb.shield:SetAlpha(0)
    cb.text = cb:CreateFontString(nil, "OVERLAY")
    Font(cb.text, 8)
    cb.text:SetJustifyH("LEFT")
    cb.text:SetWordWrap(false)
    cb.text:SetPoint("LEFT", cb, "LEFT", 3, 0)
    cb.text:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
    -- Ziel-Plakette rechts neben der Leiste: höchstens 20 % der Plakettenbreite, längere Namen werden abgeschnitten
    local tag = CreateFrame("Frame", nil, fp.overlay)
    tag:Hide()
    tag.bg = tag:CreateTexture(nil, "BACKGROUND")
    tag.bg:SetPoint("TOPLEFT", -1, 1)
    tag.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    tag.bg:SetColorTexture(0, 0, 0, 0.75)
    tag.text = tag:CreateFontString(nil, "OVERLAY")
    Font(tag.text, 8)
    tag.text:SetPoint("LEFT", 2, 0)
    tag.text:SetPoint("RIGHT", -2, 0)
    tag.text:SetJustifyH("CENTER")
    tag.text:SetWordWrap(false)
    cb.tag = tag
    cb:HookScript("OnHide", function() tag:Hide() end)
    fp.cast = cb
end

-- Zauberleiste direkt unter der Lebensleiste; mit Ziel-Plakette 80 %, sonst volle Breite
local function LayoutCastRow(fp)
    local cb, tag = fp.cast, fp.cast.tag
    local h = db.castHeight
    local w = fp.overlay:GetWidth() or 0
    if IsSecret(w) then w = 0 end
    tag:ClearAllPoints()
    tag:SetPoint("TOPRIGHT", fp.overlay, "BOTTOMRIGHT", 0, -2)
    tag:SetSize(math.max(20, math.floor(w * 0.2 + 0.5)), h)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", fp.overlay, "BOTTOMLEFT", 0, -2)
    if tag:IsShown() then
        cb:SetPoint("BOTTOMRIGHT", tag, "BOTTOMLEFT", -2, 0)
    else
        cb:SetPoint("TOPRIGHT", fp.overlay, "BOTTOMRIGHT", 0, -2)
        cb:SetHeight(h)
    end
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

local function Setup(frame)
    if frame.fpl then return frame.fpl end
    local hb = HealthBar(frame)
    if not hb then return end
    local fp = { frame = frame, hb = hb, auras = {} }
    frame.fpl = fp
    -- eigene Ebene als Kind der Lebensleiste: blendet Blizzard die Leiste aus (z. B. "nur Name"), verschwindet sie mit
    local o = CreateFrame("Frame", nil, hb)
    o:SetAllPoints(hb)
    o:SetFrameLevel(hb:GetFrameLevel() + 8)
    fp.overlay = o

    -- Finishing-Farbe über der Füllung (Deckkraft per Kurve: nur unter der Schwelle sichtbar)
    fp.exec = o:CreateTexture(nil, "ARTWORK", nil, 1)
    fp.exec:SetAllPoints(hb:GetStatusBarTexture())
    fp.exec:SetColorTexture(COL.execute[1], COL.execute[2], COL.execute[3], 1)
    fp.exec:SetAlpha(0)

    fp.hpValue = o:CreateFontString(nil, "OVERLAY")
    Font(fp.hpValue, 9)
    fp.hpValue:SetPoint("LEFT", o, "LEFT", 3, 0)
    fp.hpPct = o:CreateFontString(nil, "OVERLAY")
    Font(fp.hpPct, 9)
    fp.hpPct:SetPoint("RIGHT", o, "RIGHT", -3, 0)

    -- Bedrohung: kleines Schild in Bedrohungsfarbe mit der Prozentzahl darin
    local badge = CreateFrame("Frame", nil, o)
    badge:SetSize(20, 22)
    badge:Hide()
    badge.edge = badge:CreateTexture(nil, "BACKGROUND")
    badge.edge:SetTexture(SHIELD)
    badge.edge:SetPoint("TOPLEFT", -1, 1)
    badge.edge:SetPoint("BOTTOMRIGHT", 1, -2)
    badge.edge:SetVertexColor(0, 0, 0, 0.95)
    badge.fill = badge:CreateTexture(nil, "ARTWORK")
    badge.fill:SetTexture(SHIELD)
    badge.fill:SetAllPoints()
    badge.gloss = badge:CreateTexture(nil, "ARTWORK", nil, 1)
    badge.gloss:SetTexture(SHIELD)
    badge.gloss:SetPoint("TOPLEFT", 3, -2)
    badge.gloss:SetPoint("BOTTOMRIGHT", -3, 8)
    badge.gloss:SetVertexColor(1, 1, 1, 0.18)
    fp.threatBadge = badge
    fp.threatText = badge:CreateFontString(nil, "OVERLAY")
    Font(fp.threatText, 8)
    fp.threatText:SetPoint("CENTER", badge, "CENTER", 0, 2)
    fp.threatText:SetTextColor(1, 1, 1)

    fp.quest = o:CreateTexture(nil, "OVERLAY")
    fp.quest:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    fp.quest:SetSize(14, 14)
    fp.quest:SetPoint("BOTTOMRIGHT", o, "TOPLEFT", -1, 1)
    fp.quest:Hide()

    fp.raid = o:CreateTexture(nil, "OVERLAY")
    fp.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    fp.raid:Hide()

    BuildCast(fp)
    BuildCombo(fp)
    -- alles richtet sich nach der Breite der Plakette (Blizzard ändert sie mit der Plakettengröße)
    o:SetScript("OnSizeChanged", function()
        if fp.unit and fp.Relayout then fp.Relayout(fp) end
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
        local timer = layer:CreateFontString(nil, "OVERLAY")
        Font(timer, kind == "cc" and 11 or 9)
        if kind == "cc" then
            timer:SetPoint("CENTER", button, "CENTER", 0, 0)
        else
            timer:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
        end
        if button.SetDurationText then
            local opts = { textFormatter = TimeFormatter() }
            if not pcall(button.SetDurationText, button, timer, opts) then pcall(button.SetDurationText, button, timer) end
        end
        local stacks = layer:CreateFontString(nil, "OVERLAY")
        Font(stacks, 8)
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
local NAME_SPACE = 14 -- Platz für Blizzards Namen über der Leiste

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
                c:ClearAllPoints()
                if kind == "debuffs" then
                    c:SetPoint("BOTTOMLEFT", fp.overlay, "TOPLEFT", 0, NAME_SPACE)
                elseif kind == "buffs" then
                    c:SetPoint("BOTTOMLEFT", fp.overlay, "TOPLEFT", 0, NAME_SPACE + DebuffRowHeight())
                elseif db.ccLeft then
                    c:SetPoint("RIGHT", fp.overlay, "LEFT", -4, 0)
                else
                    c:SetPoint("LEFT", fp.overlay, "RIGHT", 4, 0)
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
    -- Blizzards eigene Auren durchsichtig, solange unsere da sind (nur bei Gegnern)
    local ours = supported and want and (db.debuffs or db.cc or db.buffs)
    local af = fp.frame.AurasFrame
    if af then
        Mute(af, ours)
        Mute(af.DebuffListFrame, ours)
        Mute(af.BuffListFrame, ours)
        Mute(af.CrowdControlListFrame, ours)
        Mute(af.LossOfControlFrame, ours)
    end
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

local function UpdateHealth(fp)
    local unit, d = fp.unit, db
    local show = d.healthText and (fp.enemy or d.healthFriendly)
    if not show then
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
    if d.execute and fp.enemy and UnitHealthPercent and ExecCurve() then
        fp.exec:SetAlpha(UnitHealthPercent(unit, true, ExecCurve()))
    else
        fp.exec:SetAlpha(0)
    end
end

local function ThreatInfo(unit)
    if not UnitDetailedThreatSituation then return end
    local ok, _, status, pct = pcall(UnitDetailedThreatSituation, "player", unit)
    if ok then return status, pct end
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

local function UpdateThreat(fp)
    local d = db
    local col, show = nil, false
    if d.threat and fp.enemy and not fp.isPlayer then
        local status, pct = ThreatInfo(fp.unit)
        if IsSecret(status) then
            -- Stufe geheim: nur die Zahl, Schild neutral grau
            if d.threatText and Has(pct) then
                fp.threatText:SetFormattedText("%.0f", pct)
                fp.threatBadge.fill:SetVertexColor(0.45, 0.45, 0.5, 1)
                show = true
            end
        elseif status then
            local c = (IsTank() and THREAT_TANK or THREAT_DPS)[status]
            if d.threatText and c then
                if Has(pct) then fp.threatText:SetFormattedText("%.0f", pct) else fp.threatText:SetText("") end
                -- etwas gedämpft, damit die weiße Zahl im Schild lesbar bleibt
                fp.threatBadge.fill:SetVertexColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8, 1)
                show = true
            end
            -- Schadensklassen: Leiste erst färben, wenn es eng wird; Tanks: immer (rot = Aggro verloren)
            if d.threatColorBar and c and (IsTank() or status > 0) then col = c end
        end
    end
    fp.threatBadge:SetShown(show)
    if col then
        fp.threatCol = col
        fp.hb:SetStatusBarColor(col[1], col[2], col[3])
    elseif fp.threatCol then
        fp.threatCol = nil
        if fp.baseCol then fp.hb:SetStatusBarColor(fp.baseCol[1], fp.baseCol[2], fp.baseCol[3]) end
    end
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
    tag.text:SetText(name)
    local col = Yes(class) and C_ClassColor and C_ClassColor.GetClassColor(class)
    if col then tag.text:SetTextColor(col.r, col.g, col.b) else tag.text:SetTextColor(1, 1, 1) end
    -- auf mich: Plakette rot hinterlegt
    local me = not IsSecret(name) and name == UnitName("player")
    if me then tag.bg:SetColorTexture(0.6, 0.08, 0.08, 0.9) else tag.bg:SetColorTexture(0, 0, 0, 0.75) end
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
    fp.castNotInt = notInt
    fp.casting = true
    CastColor(fp)
    UpdateCastTarget(fp)
    cb:Show()
end

local function EndCast(fp, interrupted)
    local cb = fp.cast
    if not fp.unit then cb:Hide() return end
    -- gleich der nächste Zauber (z. B. Kanalisieren nach dem Wirken)?
    if Has((CastInfo(fp.unit))) then UpdateCast(fp) return end
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
        HidePlaque(fp)
        cb.text:SetText(T("Unterbrochen", "Interrupted"))
        cb.fading = true
        cb:Show()
        local token = {}
        cb.fadeToken = token
        C_Timer.After(0.6, function()
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
    if IsSecret(cp, max) or not max or max <= 0 then return 0, 0 end
    return cp or 0, math.min(max, 7)
end

local function UpdateCombo(fp)
    local cp, max = 0, 0
    if db.combo and fp.enemy and fp.isTarget then cp, max = ComboCount() end
    local shown = cp > 0
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
    local blizz = fp.frame.RaidTargetFrame
    local idx
    if db.raidMarker and fp.unit then
        idx = GetRaidTargetIndex(fp.unit)
        if IsSecret(idx) then idx = "secret" end
    end
    if idx == "secret" or not db.raidMarker or not fp.enemy then
        -- Wert geheim oder aus: Blizzards eigenen Marker zeigen
        fp.raid:Hide()
        Mute(blizz, false)
        return
    end
    Mute(blizz, true)
    if idx and SetRaidTargetIconTexture then
        local size = db.raidMarkerSize
        fp.raid:SetSize(size, size)
        fp.raid:ClearAllPoints()
        fp.raid:SetPoint("BOTTOM", fp.overlay, "TOP", 0, NAME_SPACE + DebuffRowHeight() + 2)
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

local function UpdateQuest(fp)
    fp.quest:SetShown(db.quest and fp.unit and fp.enemy and not fp.isPlayer and IsQuestUnit(fp.unit) and true or false)
end

---------------------------------------------------------------------------
-- Forever-Stil (Stufe 2)
---------------------------------------------------------------------------
local function ApplySkin(fp)
    local hb = fp.hb
    local tex = hb:GetStatusBarTexture()
    if db.skin then
        if not fp.skin then
            local s = {}
            s.bg = hb:CreateTexture(nil, "BACKGROUND", nil, -7)
            s.bg:SetPoint("TOPLEFT", hb, "TOPLEFT", 0, 0)
            s.bg:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
            s.bg:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.9)
            s.gloss = fp.overlay:CreateTexture(nil, "ARTWORK", nil, 2)
            s.gloss:SetPoint("TOPLEFT", tex, "TOPLEFT")
            s.gloss:SetPoint("TOPRIGHT", tex, "TOPRIGHT")
            s.gloss:SetHeight(3)
            s.gloss:SetColorTexture(1, 1, 1, 0.12)
            s.edges = Edges(fp.overlay, "OVERLAY", hb, 0, 0, 0, 1, 1)
            fp.skin = s
        end
        if fp.origAtlas == nil then fp.origAtlas = tex.GetAtlas and tex:GetAtlas() or false end
        tex:SetTexture(WHITE)
        if hb.bgTexture then hb.bgTexture:SetAlpha(0) end
        fp.skin.bg:Show()
        fp.skin.gloss:Show()
        local e = fp.isTarget and C.accent or { 0, 0, 0 }
        SetEdgesColor(fp.skin.edges, e[1], e[2], e[3], 1)
        for _, t in ipairs(fp.skin.edges) do t:Show() end
    elseif fp.skin then
        if fp.origAtlas then tex:SetAtlas(fp.origAtlas) end
        if hb.bgTexture then hb.bgTexture:SetAlpha(1) end
        fp.skin.bg:Hide()
        fp.skin.gloss:Hide()
        for _, t in ipairs(fp.skin.edges) do t:Hide() end
    end
end

---------------------------------------------------------------------------
-- Plakette befüllen / leeren
---------------------------------------------------------------------------
local function UpdateTargetState(fp)
    local t = UnitIsUnit(fp.unit, "target")
    fp.isTarget = Yes(t)
end

local function Refresh(fp)
    if not fp.unit then return end
    local unit = fp.unit
    local can = UnitCanAttack("player", unit)
    fp.enemy = IsSecret(can) or can and true or false
    fp.isPlayer = Yes(UnitIsPlayer(unit))
    UpdateTargetState(fp)
    -- Blizzards Zauberleiste und Lebenstext durchsichtig, solange unsere da sind
    local cbc = fp.frame.CastBarsContainer
    local ownCast = db.castbar and fp.enemy
    if cbc then
        Mute(cbc, ownCast)
        Mute(cbc.castBar, ownCast)
    end
    Mute(fp.frame.castBar ~= (cbc and cbc.castBar) and fp.frame.castBar or nil, ownCast)
    local ownHealth = db.healthText and (fp.enemy or db.healthFriendly)
    Mute(fp.hb.Text, ownHealth)
    Mute(fp.hb.LeftText, ownHealth)
    Mute(fp.hb.RightText, ownHealth)
    fp.Relayout = function()
        LayoutCastRow(fp)
        UpdateCombo(fp)
    end
    LayoutCastRow(fp)
    PlaceThreatText(fp)
    ApplySkin(fp)
    fp.exec:SetAllPoints(fp.hb:GetStatusBarTexture())
    UpdateHealth(fp)
    UpdateThreat(fp)
    UpdateCombo(fp)
    UpdateCast(fp)
    UpdateRaid(fp)
    UpdateQuest(fp)
    LayoutAuras(fp)
    fp.overlay:Show()
end

local function Attach(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit, issecure and issecure())
    local frame = plate and plate.UnitFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local fp = Setup(frame)
    if not fp then return end
    -- falls die Plakette noch unter altem Namen geführt wird
    if fp.unit and plates[fp.unit] == fp then plates[fp.unit] = nil end
    fp.unit = unit
    local r, g, b = fp.hb:GetStatusBarColor()
    fp.baseCol = { r, g, b }
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
    ReleaseAuras(fp)
    fp.cast:SetScript("OnUpdate", nil)
    fp.cast:Hide()
    fp.overlay:Hide()
    fp.unit = nil
end

function ns.ApplyAll()
    GetDB()
    for _, fp in pairs(plates) do Refresh(fp) end
end

-- Blizzard setzt die Leistenfarbe neu (Reaktion, angetippt …): merken und Bedrohungsfarbe wieder drüber
if CompactUnitFrame_UpdateHealthColor then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(frame)
        local fp = frame and frame.fpl
        if not fp or not fp.unit then return end
        local r, g, b = fp.hb:GetStatusBarColor()
        fp.baseCol = { r, g, b }
        if fp.threatCol then fp.hb:SetStatusBarColor(fp.threatCol[1], fp.threatCol[2], fp.threatCol[3]) end
    end)
end

---------------------------------------------------------------------------
-- Verbündete: Blizzards eigene Schalter "nur Name" und "Name in Klassenfarbe" (vorherige Werte werden gemerkt)
---------------------------------------------------------------------------
local FRIEND_CVARS = {
    nameplateShowOnlyNameForFriendlyPlayerUnits = "1",
    nameplateUseClassColorForFriendlyPlayerUnitNames = "1",
}
function ns.ApplyFriendly()
    UI.AfterCombat("ForeverPlatesFriendly", function()
        local d = GetDB()
        d._savedCVars = d._savedCVars or {}
        for cvar, want in pairs(FRIEND_CVARS) do
            local cur = C_CVar.GetCVar(cvar)
            if cur ~= nil then
                if d.friendlySimple then
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

local H = {}
H.NAME_PLATE_UNIT_ADDED = function(unit) Attach(unit) end
H.NAME_PLATE_UNIT_REMOVED = function(unit) Detach(unit) end
H.PLAYER_TARGET_CHANGED = function()
    ForAll(function(fp)
        UpdateTargetState(fp)
        UpdateCombo(fp)
        if db.skin then ApplySkin(fp) end
    end)
end
H.UNIT_HEALTH = function(unit) local fp = plates[unit] if fp then UpdateHealth(fp) end end
H.UNIT_MAXHEALTH = H.UNIT_HEALTH
H.UNIT_THREAT_LIST_UPDATE = function(unit) local fp = plates[unit] if fp then UpdateThreat(fp) end end
H.UNIT_THREAT_SITUATION_UPDATE = function() for _, fp in pairs(plates) do UpdateThreat(fp) end end
H.PLAYER_REGEN_ENABLED = H.UNIT_THREAT_SITUATION_UPDATE
H.PLAYER_REGEN_DISABLED = H.UNIT_THREAT_SITUATION_UPDATE
H.PLAYER_ROLES_ASSIGNED = H.UNIT_THREAT_SITUATION_UPDATE
H.GROUP_ROSTER_UPDATE = H.UNIT_THREAT_SITUATION_UPDATE
H.UNIT_FACTION = function(unit) local fp = plates[unit] if fp then Refresh(fp) end end
local function CastStart(unit) local fp = plates[unit] if fp then UpdateCast(fp) end end
local function CastStop(unit) local fp = plates[unit] if fp then EndCast(fp, false) end end
H.UNIT_SPELLCAST_START = CastStart
H.UNIT_SPELLCAST_CHANNEL_START = CastStart
H.UNIT_SPELLCAST_DELAYED = CastStart
H.UNIT_SPELLCAST_CHANNEL_UPDATE = CastStart
H.UNIT_SPELLCAST_EMPOWER_START = CastStart
H.UNIT_SPELLCAST_STOP = CastStop
H.UNIT_SPELLCAST_CHANNEL_STOP = CastStop
H.UNIT_SPELLCAST_EMPOWER_STOP = CastStop
H.UNIT_SPELLCAST_FAILED = CastStop
H.UNIT_SPELLCAST_INTERRUPTED = function(unit) local fp = plates[unit] if fp then EndCast(fp, true) end end
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
H.UNIT_POWER_UPDATE = function(unit, powerType)
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
    for event in pairs(H) do pcall(ev.RegisterEvent, ev, event) end
    ns.ApplyFriendly()
    for _, plate in pairs(C_NamePlate.GetNamePlates(issecure and issecure()) or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and not IsSecret(unit) then Attach(unit) end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Safe("Start", function() ns.Start() end))

UI.RegisterSettings({ addon = "ForeverPlates", sv = "ForeverPlatesDB", defaults = ns.DEFAULTS, version = 1 })
