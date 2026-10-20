-- ForeverCast – Units.lua: Zauberleisten für Ziel und Fokus (standardmäßig aus; Einstellungen » "Zauberleisten
-- für Ziel und Fokus"). ForeverUnits blendet Blizzards Ziel-/Fokusrahmen (und damit deren Zauberleisten) aus –
-- diese Leisten ersetzen sie.
--   * angedockt (Standard): direkt unter dem ForeverUnits-Rahmen, so breit wie er. ForeverUnits hält den Platz frei
--     (fragt _G.ForeverCastDockHeight(key)) und legt dort einen Andockpunkt b.fcCastDock an; Auren rücken darunter.
--   * frei (nicht angedockt oder ohne ForeverUnits): eigener Anker, verschiebbar, solange ForeverCast entsperrt ist.
-- Anzeige wie die Zauberleiste von ForeverPlates: nicht unterbrechbar = grau mit Schild, gesperrte Zeiten (secret)
-- über Blizzards Timer-Balken, "Unterbrochen von Name" kurz stehen lassen. Werte werden nie verglichen/verrechnet,
-- wenn sie geheim sind.
local _, ns = ...
local UI = ForeverHub.UI
local T = UI.T

local issecret = issecretvalue or function() return false end
-- vorhanden (auch geheim – dann darf nur angezeigt werden)
local function Has(v)
    if issecret(v) then return true end
    return v ~= nil and v ~= ""
end

local UNITS = {
    target = { unit = "target", dbKey = "targetBar", posKey = "targetPos", label = T("Ziel", "Target"), y = -60 },
    focus  = { unit = "focus",  dbKey = "focusBar",  posKey = "focusPos",  label = T("Fokus", "Focus"), y = -100 },
}
local ORDER = { "target", "focus" }
local bars = {}

local function DB() return ns.GetDB() end
local function Enabled(key) return DB()[UNITS[key].dbKey] and true or false end
local function UnitFrame(key) return _G["ForeverUnits_" .. key] end

-- ForeverUnits fragt beim Anordnen, wie viel Platz es unter dem Rahmen freihalten soll
function _G.ForeverCastDockHeight(key)
    if not UNITS[key] or not Enabled(key) or not DB().unitDock then return 0 end
    return DB().unitHeight or 18
end

local function ColorObj(c) return CreateColor and CreateColor(c[1], c[2], c[3], 1) end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------
local function Create(key)
    local info = UNITS[key]
    local a = CreateFrame("Frame", "ForeverCast" .. (key == "target" and "Target" or "Focus") .. "Anchor", UIParent)
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:SetFrameStrata("MEDIUM")
    a:Hide()

    local iconBox = CreateFrame("Frame", nil, a, "BackdropTemplate")
    iconBox:SetPoint("TOPLEFT")
    iconBox:SetPoint("BOTTOMLEFT")
    a.icon = iconBox:CreateTexture(nil, "ARTWORK")
    a.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.StyleBox(iconBox, a.icon)
    a.iconBox = iconBox
    -- Schild über dem Symbol: Zauber kann nicht unterbrochen werden
    a.shield = iconBox:CreateTexture(nil, "OVERLAY")
    a.shield:SetAtlas("nameplates-InterruptShield") -- wie ForeverPlates
    a.shield:SetPoint("CENTER", iconBox, "CENTER", 0, 0)
    a.shield:SetAlpha(0)

    local box = CreateFrame("Frame", nil, a, "BackdropTemplate")
    box:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 2, 0)
    box:SetPoint("BOTTOMRIGHT")
    local bar = CreateFrame("StatusBar", nil, box)
    ns.StyleBox(box, bar)
    ns.StyleBar(bar)
    bar:SetMinMaxValues(0, 1)
    a.box, a.bar = box, bar

    a.spark = bar:CreateTexture(nil, "OVERLAY")
    a.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    a.spark:SetBlendMode("ADD")
    a.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)

    a.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a.time:SetPoint("RIGHT", -4, 0)
    a.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a.name:SetPoint("LEFT", 4, 0)
    a.name:SetPoint("RIGHT", a.time, "LEFT", -4, 0)
    a.name:SetJustifyH("LEFT")
    a.name:SetWordWrap(false)
    ns.Text(a.name, 10)
    ns.Text(a.time, 10)

    -- Verschieben (nur frei platziert und entsperrt)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", function()
        if ns.IsLocked() or a.docked then return end
        a:StartMoving()
        a.dragging = true
        UI.Grid("ForeverCastUnits", 32)
        UI.BeginDrag(a, { grid = 32 })
    end)
    box:SetScript("OnDragStop", function()
        if not a.dragging then return end
        a.dragging = nil
        a:StopMovingOrSizing()
        local dx, dy = UI.EndDrag()
        UI.Grid("ForeverCastUnits", nil)
        local x, y = UI.CenterOffset(a)
        DB()[info.posKey] = { UI.Round(x + dx), UI.Round(y + dy) }
        ns.PlaceUnit(key)
    end)
    UI.AddMover(box)

    a.key, a.unit = key, info.unit
    bars[key] = a
    return a
end

-- Lage und Größe: angedockt am Andockpunkt von ForeverUnits, sonst frei
function ns.PlaceUnit(key)
    local a = bars[key] or Create(key)
    local d = DB()
    local h = d.unitHeight or 18
    local frame = UnitFrame(key)
    local dock = d.unitDock and frame and frame.fcCastDock
    a:ClearAllPoints()
    a.docked = dock and true or false
    if dock then
        a:SetPoint("TOPLEFT", dock, "TOPLEFT")
        a:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT")
    else
        a:SetSize(d.unitWidth or 220, h)
        local pos = d[UNITS[key].posKey]
        a:SetPoint("CENTER", UIParent, "CENTER", pos and pos[1] or 0, pos and pos[2] or UNITS[key].y)
    end
    a.iconBox:SetWidth(h)
    a.shield:SetSize(h * 1.1, h * 1.1)
    a.spark:SetSize(math.max(8, h * 0.6), h * 1.6)
    a.box:EnableMouse(not ns.IsLocked() and not a.docked)
end

---------------------------------------------------------------------------
-- Zauber
---------------------------------------------------------------------------
local function CastInfo(unit)
    local name, _, tex, s, e, _, _, notInt = UnitCastingInfo(unit)
    if Has(name) then return name, tex, s, e, notInt, false end
    if UnitChannelInfo then
        local n2, _, tex2, s2, e2, _, notInt2 = UnitChannelInfo(unit)
        if Has(n2) then return n2, tex2, s2, e2, notInt2, true end
    end
end

local function OnUpdate(a)
    local now = GetTime()
    if now >= a.e then
        a:SetScript("OnUpdate", nil)
        a.bar:SetValue(a.channel and 0 or 1)
        a.time:SetText("")
        return
    end
    local total = a.e - a.s
    local value = a.channel and (a.e - now) or (now - a.s)
    a.bar:SetValue(total > 0 and value / total or 1)
    a.time:SetText(string.format("%.1f", a.e - now))
end

local function Color(a)
    local C = ns.COLORS
    local free = a.channel and C.channel or C.cast
    local tex = a.bar:GetStatusBarTexture()
    local notInt = a.notInt
    if issecret(notInt) then
        if tex.SetVertexColorFromBoolean and ColorObj(free) then
            tex:SetVertexColorFromBoolean(notInt, ColorObj(C.locked), ColorObj(free))
        else
            tex:SetVertexColor(free[1], free[2], free[3])
        end
        if a.shield.SetAlphaFromBoolean then a.shield:SetAlphaFromBoolean(notInt, 1, 0) else a.shield:SetAlpha(0) end
    else
        local c = notInt and C.locked or free
        tex:SetVertexColor(c[1], c[2], c[3])
        a.shield:SetAlpha(notInt and 1 or 0)
    end
end

local function Start(key)
    local a = bars[key]
    if not a or not Enabled(key) then return end
    local unit = a.unit
    local name, tex, s, e, notInt, channel = CastInfo(unit)
    if not Has(name) then
        if not a.fading and not a.placeholder then a:Hide() end
        return
    end
    a.fading, a.placeholder, a.fadeToken = nil, nil, nil
    a:SetScript("OnUpdate", nil)
    a:SetAlpha(1)
    a.channel = channel
    a.time:SetText("")
    local timed = false
    local dur
    if channel then
        dur = UnitChannelDuration and UnitChannelDuration(unit)
    else
        dur = UnitCastingDuration and UnitCastingDuration(unit)
    end
    local dirs = Enum and Enum.StatusBarTimerDirection
    -- gesperrte Zeiten (secret): Blizzards Timer füllt den Balken
    if (issecret(s) or issecret(e)) and dur and a.bar.SetTimerDuration and dirs then
        local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
        timed = pcall(a.bar.SetTimerDuration, a.bar, dur, interp, channel and dirs.RemainingTime or dirs.ElapsedTime)
    end
    if not timed then
        if a.bar.ClearTimerDuration then pcall(a.bar.ClearTimerDuration, a.bar) end
        a.bar:SetMinMaxValues(0, 1)
        if not issecret(s) and not issecret(e) and s and e and e > s then
            a.s, a.e = s / 1000, e / 1000
            a:SetScript("OnUpdate", OnUpdate)
            OnUpdate(a)
        else
            a.bar:SetValue(1)
        end
    end
    a.icon:SetTexture(tex)
    a.name:SetText(name)
    a.name:SetTextColor(1, 1, 1)
    a.spark:Show()
    a.notInt = notInt
    a.casting = true
    Color(a)
    a:Show()
end

local function Stop(key, interrupted, by)
    local a = bars[key]
    if not a then return end
    if not interrupted then
        if a.fading then return end -- "Unterbrochen" steht gerade: nicht überschreiben
        if Has((CastInfo(a.unit))) then Start(key) return end -- gleich der nächste Zauber
    end
    local was = a.casting or (GetTime() - (a.ended or 0) < 0.3)
    a.casting = false
    a.ended = GetTime()
    a:SetScript("OnUpdate", nil)
    if interrupted and was and Enabled(key) then
        if a.bar.ClearTimerDuration then pcall(a.bar.ClearTimerDuration, a.bar) end
        a.bar:SetMinMaxValues(0, 1)
        a.bar:SetValue(1)
        local c = ns.COLORS.fail
        a.bar:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3])
        a.shield:SetAlpha(0)
        a.spark:Hide()
        a.time:SetText("")
        a.name:SetText(ns.InterruptedText(by))
        a.fading = true
        a:Show()
        local token = {}
        a.fadeToken = token
        C_Timer.After(0.8, function()
            if a.fadeToken == token and a.fading then
                a.fading = nil
                if not a.placeholder then a:Hide() end
            end
        end)
        return
    end
    if not a.placeholder then a:Hide() end
end

-- Platzhalter zum Verschieben (frei platziert, ForeverCast entsperrt)
local function Placeholder(a)
    a.placeholder = true
    a:SetScript("OnUpdate", nil)
    if a.bar.ClearTimerDuration then pcall(a.bar.ClearTimerDuration, a.bar) end
    a.bar:SetMinMaxValues(0, 1)
    a.bar:SetValue(1)
    local c = ns.COLORS.idle
    a.bar:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3])
    a.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    a.shield:SetAlpha(0)
    a.spark:Hide()
    a.time:SetText("")
    a.name:SetText(string.format(T("%s-Zauberleiste – ziehen", "%s cast bar – drag"), UNITS[a.key].label))
    a:SetAlpha(1)
    a:Show()
end

-- Einstellungen übernehmen (aus ForeverCast.lua ApplySettings)
function ns.ApplyUnits()
    -- ForeverUnits hält den Platz unter dem Rahmen frei bzw. gibt ihn wieder her
    if UI.Fire then UI.Fire("ForeverCastDock") end
    for _, key in ipairs(ORDER) do
        if Enabled(key) or bars[key] then
            local a = bars[key] or Create(key)
            ns.PlaceUnit(key)
            a.placeholder = nil
            if not Enabled(key) then
                a:SetScript("OnUpdate", nil)
                a:Hide()
            elseif not ns.IsLocked() and not a.docked then
                Placeholder(a)
            else
                a:Hide()
                Start(key)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local KEY_OF = { target = "target", focus = "focus" }
local ev = CreateFrame("Frame")
local UNIT_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}
for _, e in ipairs(UNIT_EVENTS) do pcall(ev.RegisterUnitEvent, ev, e, "target", "focus") end
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, unit, _, _, by)
    if event == "PLAYER_LOGIN" then
        -- ForeverUnits ist dann aufgebaut: Platz freihalten lassen und andocken
        C_Timer.After(0.5, function() pcall(ns.ApplyUnits) end)
        return
    end
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        local key = event == "PLAYER_TARGET_CHANGED" and "target" or "focus"
        local a = bars[key]
        if a and not a.placeholder then
            a.fading, a.casting = nil, false
            a:SetScript("OnUpdate", nil)
            a:Hide()
            pcall(Start, key)
        end
        return
    end
    local key = KEY_OF[unit]
    if not key or not bars[key] or bars[key].placeholder or not Enabled(key) then return end
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        pcall(Stop, key, true, by)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        pcall(Stop, key, false)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        local a = bars[key]
        if a.casting then
            a.notInt = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
            pcall(Color, a)
        end
    else
        pcall(Start, key)
    end
end)
