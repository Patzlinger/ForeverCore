-- ForeverSkin – Calendar.lua: Kalender (CalendarFrame) sowie Uhr (TimeManagerFrame) und Stoppuhr (StopwatchFrame) im
-- Forever-Stil (docs/Fenster-Stil.md), erster Entwurf.
-- Kalender: Blizzards Steinrahmen und Hintergrundbilder weg; flacher Kopf mit Monat/Jahr und feiner goldener Linie,
-- Wochentage als dunklere Leiste, die Tage als flaches Raster mit feinem Rand (Maus darauf = gold, heute = gold),
-- Tage anderer Monate dezent abgedunkelt; Monats-Pfeile, Filter und Schließen flach. Bilder von Feiertagen/Terminen
-- in den Tagen bleiben. Die Termin-Fenster (Ansehen, Erstellen, Einladen) bleiben vorerst Blizzards.
-- Uhr: flaches Fenster, die Uhrzeit links in der Titelleiste statt auf Blizzards Globus; Häkchen, Auswahllisten,
-- Eingabefeld flach. Stoppuhr: flache Fläche mit dunklem Kopf und goldener Linie.
-- Die Uhr an der Minikarte (TimeManagerClockButton) gehört zu ForeverMinimap und wird hier nicht angefasst.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local HEAD = 46   -- Kalender: Höhe des Kopfs (Monat, Jahr, Pfeile) – darunter beginnen die Wochentage
local WEEKDAY = 28 -- Höhe der Wochentags-Leiste

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "calendar/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" })

local function Tex(parent, layer, sub, c, a)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    return t
end

-- Eingabefeld (InputBoxTemplate): Blizzards Rahmenteile weg, flache Fläche
local function SkinInput(box)
    if not box or done[box] or Forbidden(box) then return end
    done[box] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    local name = box:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(G(name .. suffix)) end
    end
    ns.Flat(box, C.input, { -4, 0, 0, 0 })
end

---------------------------------------------------------------------------
-- Kalender
---------------------------------------------------------------------------
-- heutiger Tag: Blizzard hängt sein "Heute"-Bild an den Tag – daran erkennen wir ihn (das Bild selbst ist unsichtbar)
local function IsToday(button)
    local today = G("CalendarTodayFrame")
    if not (today and today:IsShown()) then return false end
    local _, rel = today:GetPoint(1)
    return rel == button
end

local function SkinDay(button)
    if not button or done[button] or Forbidden(button) then return end
    done[button] = true
    -- Steinkachel (die "normale" Grafik des Tages) und Blizzards Hervorhebung weg
    ns.Hide(button.GetNormalTexture and button:GetNormalTexture())
    ns.Hide(button.GetHighlightTexture and button:GetHighlightTexture())
    ns.Flat(button, C.panel)
    ns.Hover(button, IsToday)
    -- Tage anderer Monate: Blizzards Schatten-Bilder weg, stattdessen eine schlichte dunkle Fläche (zeigt sich, wenn
    -- Blizzard den Schatten-Rahmen zeigt)
    local name = button:GetName()
    local dark = name and G(name .. "DarkFrame")
    if dark and not done[dark] then
        done[dark] = true
        ns.Hide(G(name .. "DarkFrameTop"))
        ns.Hide(G(name .. "DarkFrameBottom"))
        local shade = Tex(dark, "OVERLAY", -1, { 0, 0, 0 }, 0.45)
        shade:SetPoint("TOPLEFT", 1, -1)
        shade:SetPoint("BOTTOMRIGHT", -1, 1)
    end
end

local calSkinned
local function SkinCalendar()
    local f = G("CalendarFrame")
    if not f or calSkinned or Forbidden(f) then return end
    calSkinned = true
    -- alle Rahmen- und Hintergrundbilder des Fensters (Stein, Wochentags- und Monats-Hintergrund, Hervorhebung des
    -- Wochentags) unsichtbar – die Texte bleiben
    ns.HideTextures(f)
    local look = ns.Flat(f, C.background)
    -- Kopf: etwas dunklere Fläche mit feiner goldener Linie darunter; darunter die Wochentags-Leiste
    local head = Tex(f, "BACKGROUND", -7, C.header)
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(HEAD - 1)
    local line = Tex(f, "BORDER", -6, C.accent, 0.6)
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    ns.OnePixel(line, true)
    local week = Tex(f, "BACKGROUND", -7, C.input)
    week:SetPoint("TOPLEFT", 1, -HEAD - 1)
    week:SetPoint("TOPRIGHT", -1, -HEAD - 1)
    week:SetHeight(WEEKDAY - 1)
    if look then look.mine[head], look.mine[line], look.mine[week] = true, true, true end
    -- Wochentage in Gold (Blizzard: hellgelb auf Stein)
    for i = 1, 7 do
        local name = G("CalendarWeekday" .. i .. "Name")
        if name then name:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
    end
    -- "Heute"-Bilder (Rahmen und Leuchten) unsichtbar – der heutige Tag bekommt stattdessen den goldenen Rand
    ns.HideTextures(G("CalendarTodayFrame"))
    ns.SkinArrowOnly(G("CalendarPrevMonthButton"), "left")
    ns.SkinArrowOnly(G("CalendarNextMonthButton"), "right")
    if f.FilterButton then ns.SkinDropdown(f.FilterButton) end
    ns.SkinClose(G("CalendarCloseButton"))
    for i = 1, 42 do SkinDay(G("CalendarDayButton" .. i)) end
    ns.Watch(f)
    -- Blizzard blendet beim Monatswechsel teils Grafiken wieder ein
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        pcall(ns.HideTextures, f)
        pcall(ns.HideTextures, G("CalendarTodayFrame"))
        for i = 1, 42 do
            local b = G("CalendarDayButton" .. i)
            if b then
                ns.Hide(b.GetNormalTexture and b:GetNormalTexture())
                ns.Hide(b.GetHighlightTexture and b:GetHighlightTexture())
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Uhr und Stoppuhr
---------------------------------------------------------------------------
local clockSkinned
local function SkinClock()
    local f = G("TimeManagerFrame")
    if not f or clockSkinned or Forbidden(f) then return end
    clockSkinned = true
    ns.SkinWindow(f) -- (macht auch Blizzards Globus unsichtbar)
    -- Uhrzeit links in der Titelleiste (lag bei Blizzard auf dem Globus)
    local ticker = G("TimeManagerFrameTicker")
    if ticker then
        ticker:ClearAllPoints()
        ticker:SetPoint("LEFT", f, "TOPLEFT", 10, -12)
        ticker:SetFontObject("GameFontHighlight")
    end
    -- "Stoppuhr anzeigen": das Taschenuhr-Symbol bleibt, flacher Platz dahinter (an = gold)
    local watchCheck = G("TimeManagerStopwatchCheck")
    if watchCheck and not Forbidden(watchCheck) then
        ns.Hide(watchCheck:GetHighlightTexture())
        ns.Hide(watchCheck:GetCheckedTexture())
        ns.Flat(watchCheck, { 0.06, 0.06, 0.08, 0.85 }, -1)
        ns.Hover(watchCheck, function(b) return b:GetChecked() and true or false end)
    end
    local alarm = f.AlarmTimeFrame
    if alarm then
        for _, key in ipairs({ "HourDropdown", "MinuteDropdown", "AMPMDropdown" }) do
            if alarm[key] then ns.SkinDropdown(alarm[key]) end
        end
    end
    SkinInput(G("TimeManagerAlarmMessageEditBox"))
    for _, n in ipairs({ "TimeManagerAlarmEnabledButton", "TimeManagerMilitaryTimeCheck", "TimeManagerLocalTimeCheck" }) do
        local cb = G(n)
        if cb and not Forbidden(cb) then ns.SkinCheck(cb) end
    end
    ns.Watch(f)
end

local stopwatchSkinned
local function SkinStopwatch()
    local f = G("StopwatchFrame")
    if not f or stopwatchSkinned or Forbidden(f) then return end
    stopwatchSkinned = true
    ns.HideTextures(f)
    local look = ns.Flat(f, C.background)
    -- Kopf ("Stoppuhr" mit Schließen-Kreuz): dunklere Fläche mit feiner goldener Linie
    local tab = G("StopwatchTabFrame")
    if tab and not Forbidden(tab) then
        ns.HideTextures(tab)
        local head = Tex(f, "BACKGROUND", -7, C.header)
        head:SetPoint("TOPLEFT", tab, "TOPLEFT", 1, -1)
        head:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 0)
        local line = Tex(f, "BORDER", -6, C.accent, 0.6)
        line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
        line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
        ns.OnePixel(line, true)
        if look then look.mine[head], look.mine[line] = true, true end
    end
    ns.SkinClose(G("StopwatchCloseButton"))
    -- Start/Pause und Zurücksetzen: Symbole bleiben, nur Blizzards helle Hervorhebung weg
    for _, n in ipairs({ "StopwatchResetButton", "StopwatchPlayPauseButton" }) do
        local b = G(n)
        if b and b.GetHighlightTexture then ns.Hide(b:GetHighlightTexture()) end
    end
    ns.Watch(f)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().calendar then return end
    if not calSkinned and G("CalendarFrame") then Step("calendar", SkinCalendar) end
    if not clockSkinned and G("TimeManagerFrame") then Step("clock", SkinClock) end
    if not stopwatchSkinned and G("StopwatchFrame") then Step("stopwatch", SkinStopwatch) end
end)
