-- ForeverCast – Mirror.lua: Atem-, Erschöpfungs- und Totstellen-Leiste ("Mirror Timer") im Look von ForeverCast,
-- übereinander direkt über der eigenen Zauberleiste (über der Zeile mit Schaden/Heilung). Blizzards Leisten werden
-- dann nur unsichtbar gehalten (UI.HideBlizzard: Alpha 0, kein Hide – kein taint). Einstellung "showMirror".
-- Werte kommen wie bei Blizzard aus MIRROR_TIMER_* und GetMirrorTimerProgress (Millisekunden).
local _, ns = ...
local UI = ForeverHub.UI
local T = UI.T

local HEIGHT, GAP = 14, 3
local COLOR_OF = { BREATH = "breath", EXHAUSTION = "exhaustion", FEIGNDEATH = "feign" }
local issecret = issecretvalue or function() return false end

local slots = {}   -- Leisten (Wiederverwendung)
local active = {}  -- [timer] = Leiste
local order = {}   -- sichtbare Leisten von unten nach oben

local function DB() return ns.GetDB() end

local function Layout()
    local anchor = _G.ForeverCastAnchor
    if not anchor then return end
    for i, f in ipairs(order) do
        f:ClearAllPoints()
        -- über der Zauberleiste und der Zeile "≈ Schaden · Krit" darüber
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 18 + (i - 1) * (HEIGHT + GAP))
        f:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 18 + (i - 1) * (HEIGHT + GAP))
    end
end

local function OnUpdate(f)
    local value = GetMirrorTimerProgress and GetMirrorTimerProgress(f.timer)
    if value == nil or issecret(value) or not f.max or f.max <= 0 then return end
    f.bar:SetValue(value / f.max)
    f.time:SetText(string.format("%d s", math.max(0, math.floor(value / 1000 + 0.5))))
end

local function Slot()
    for _, f in ipairs(slots) do
        if not f.timer then return f end
    end
    local anchor = _G.ForeverCastAnchor or UIParent
    local f = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    f:SetHeight(HEIGHT)
    local bar = CreateFrame("StatusBar", nil, f)
    ns.StyleBox(f, bar)
    ns.StyleBar(bar)
    bar:SetMinMaxValues(0, 1)
    f.bar = bar
    f.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetPoint("LEFT", 4, 0)
    f.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("RIGHT", -4, 0)
    ns.Text(f.label, 10)
    ns.Text(f.time, 10)
    f:Hide()
    slots[#slots + 1] = f
    return f
end

local function Color(f)
    local c = ns.COLORS[COLOR_OF[f.timer] or "exhaustion"]
    f.bar:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3])
end

local function SetPaused(f, paused)
    f:SetScript("OnUpdate", (paused and paused ~= 0) and nil or OnUpdate)
end

local function Start(timer, value, maxvalue, paused, label)
    if not DB().showMirror or not timer or timer == "UNKNOWN" or issecret(timer) then return end
    local f = active[timer]
    if not f then
        f = Slot()
        f.timer = timer
        active[timer] = f
        order[#order + 1] = f
    end
    f.max = (not issecret(maxvalue) and tonumber(maxvalue)) or 0
    f.label:SetText(label or "")
    Color(f)
    if not issecret(value) and value and f.max > 0 then f.bar:SetValue(value / f.max) end
    SetPaused(f, paused)
    OnUpdate(f)
    f:Show()
    Layout()
end

local function Stop(timer)
    local f = active[timer]
    if not f then return end
    active[timer] = nil
    f.timer = nil
    f:SetScript("OnUpdate", nil)
    f:Hide()
    for i, o in ipairs(order) do
        if o == f then table.remove(order, i) break end
    end
    Layout()
end

local function StopAll()
    for timer in pairs(active) do Stop(timer) end
end

local function KeepBlizzardInvisible()
    local when = function() return DB().showMirror end
    if _G.MirrorTimerContainer then
        UI.HideBlizzard(_G.MirrorTimerContainer, { when = when })
    else
        for i = 1, 3 do
            local f = _G["MirrorTimer" .. i]
            if f then UI.HideBlizzard(f, { when = when }) end
        end
    end
end

local function ScanRunning()
    if not GetMirrorTimerInfo then return end
    for i = 1, 3 do
        local ok, timer, value, maxvalue, _, paused, label = pcall(GetMirrorTimerInfo, i)
        if ok and timer and timer ~= "UNKNOWN" then Start(timer, value, maxvalue, paused, label) end
    end
end

-- Einstellungen übernehmen (aus ForeverCast.lua ApplySettings)
function ns.ApplyMirror()
    if DB().showMirror then
        KeepBlizzardInvisible()
        ScanRunning()
        for _, f in ipairs(order) do Color(f) end
    else
        StopAll()
        if _G.MirrorTimerContainer then
            UI.ShowBlizzard(_G.MirrorTimerContainer)
        else
            for i = 1, 3 do if _G["MirrorTimer" .. i] then UI.ShowBlizzard(_G["MirrorTimer" .. i]) end end
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("MIRROR_TIMER_START")
ev:RegisterEvent("MIRROR_TIMER_STOP")
ev:RegisterEvent("MIRROR_TIMER_PAUSE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(function(...)
        if event == "MIRROR_TIMER_START" then
            local timer, value, maxvalue, _, paused, label = ...
            Start(timer, value, maxvalue, paused, label)
        elseif event == "MIRROR_TIMER_STOP" then
            Stop((...))
        elseif event == "MIRROR_TIMER_PAUSE" then
            local timer, paused = ...
            if active[timer] then SetPaused(active[timer], paused) end
        else
            ScanRunning()
        end
    end, ...)
    if not ok then UI.ReportError("ForeverCast", "Atem/Erschöpfung", err) end
end)

-- für den Test-Durchlauf (/fcast test)
function ns.TestMirror()
    if not DB().showMirror then return end
    local f = Slot()
    f.timer = "TEST"
    active.TEST = f
    order[#order + 1] = f
    f.max = 1
    f.label:SetText(T("Atem (Test)", "Breath (test)"))
    local c = ns.COLORS.breath
    f.bar:GetStatusBarTexture():SetVertexColor(c[1], c[2], c[3])
    f.bar:SetValue(0.6)
    f.time:SetText("36 s")
    f:Show()
    Layout()
    C_Timer.After(3, function() Stop("TEST") end)
end
