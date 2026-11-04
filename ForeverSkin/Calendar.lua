-- ForeverSkin – Calendar.lua: Kalender (CalendarFrame) sowie Uhr (TimeManagerFrame) und Stoppuhr (StopwatchFrame) im
-- Forever-Stil (docs/Fenster-Stil.md), erster Entwurf.
-- Kalender: Blizzards Steinrahmen und Hintergrundbilder weg; flacher Kopf mit Monat/Jahr und feiner goldener Linie,
-- Wochentage als dunklere Leiste, die Tage als flaches Raster mit feinem Rand (Maus darauf = gold, heute = gold),
-- Tage anderer Monate dezent abgedunkelt; Monats-Pfeile, Filter und Schließen flach. Bilder von Feiertagen/Terminen
-- in den Tagen bleiben. Die Termin-Fenster (Ansehen, Erstellen, Einladen …) wie unsere Fenster mit Titelleiste.
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

-- Termin-Fenster (Feiertag, Schlachtzug-Sperre, Termin ansehen, Termin erstellen/bearbeiten, Masseneinladung,
-- Terminauswahl, Bildauswahl): gleich gebaut wie unsere Fenster – flache Fläche, dunkle Titelleiste (23) mit goldener
-- Linie, Titel darin, Schließen-Kreuz oben rechts; darin Knöpfe, Eingabefelder, Auswahllisten, Häkchen, Laufleisten
-- und Textkästen flach, Blizzards Trennlinien als feine goldene Linie, kein Leuchten der Zusage-Knöpfe
local EVENT_FRAMES = { "CalendarViewHolidayFrame", "CalendarViewRaidFrame", "CalendarViewEventFrame",
    "CalendarCreateEventFrame", "CalendarMassInviteFrame", "CalendarEventPickerFrame", "CalendarTexturePickerFrame" }

local function Divider(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        local tex = r:IsObjectType("Texture") and r.GetTexture and r:GetTexture()
        if type(tex) == "string" and tex:lower():find("divider") and not done[r] then
            done[r] = true
            r:SetAlpha(0)
            local line = Tex(frame, "BORDER", 1, C.accent, 0.5)
            line:SetPoint("LEFT", r, "LEFT", 6, 0)
            line:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            ns.OnePixel(line, true)
        end
    end
end

local function ScanEvent(frame, depth)
    Divider(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            -- Textkästen (Beschreibung, Einladungsliste: Blizzards dunkle Tooltip-Kästen) flach
            if type(child.NineSlice) == "table" and not child:IsObjectType("Button") then
                ns.Hide(child.NineSlice)
                ns.Flat(child, C.input)
            end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("DropdownButton") then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("CheckButton") and (child:GetWidth() or 0) <= 32 then
                done[child] = true
                ns.SkinCheck(child)
            elseif child:IsObjectType("EditBox") and type(child.Left) == "table" and type(child.Right) == "table" then
                SkinInput(child)
            elseif child:IsObjectType("Button") and type(child.Left) == "table" and type(child.Right) == "table" then
                done[child] = true
                ns.SkinButton(child)
                -- (Zusage-Knöpfe leuchten bei Blizzard, solange man nicht geantwortet hat – kein Leuchten)
                if type(child.flashTexture) == "table" then child.flashTexture:SetTexture(nil) end
            elseif not child:IsObjectType("Button") and depth < 4 then
                ScanEvent(child, depth + 1)
            end
        end
    end
end

-- Spaltenköpfe der Einladungsliste (Name, Klasse, Status): Blizzard richtet sie erst an der ersten Zeile aus, solange
-- die Liste noch abgerufen wird, lagen sie übereinander – bis dahin eigene feste Plätze
local function SortButtons()
    for _, list in ipairs({ G("CalendarCreateEventInviteList") or false, G("CalendarViewEventInviteList") or false }) do
        if list and not Forbidden(list) then
            local name = list:GetName()
            for _, s in ipairs({ { "NameSortButton", "BOTTOMLEFT", 12 }, { "ClassSortButton", "BOTTOM", 20 },
                { "StatusSortButton", "BOTTOMRIGHT", -30 } }) do
                local b = G(name .. s[1])
                -- (nur, solange Blizzard sie noch an der Oberkante der Liste hat – danach gilt Blizzards Ausrichtung)
                local p = b and b:GetNumPoints() == 1 and b:GetPoint(1)
                if p == "BOTTOM" then
                    b:ClearAllPoints()
                    b:SetPoint(s[2], list, s[2] == "BOTTOM" and "TOP" or (s[2] == "BOTTOMLEFT" and "TOPLEFT" or "TOPRIGHT"), s[3], 0)
                end
            end
        end
    end
end

-- Termin erstellen: Blizzards braune Knopfleiste weg, unten eine Fußleiste mit feiner goldener Linie, die Knöpfe
-- mittig darin (10 vom Rand)
local CREATE_FOOTER = 40
local function CreateFooter(f)
    if done.createFooter then return end
    done.createFooter = true
    ns.Hide(G("CalendarCreateEventFrameButtonBackground"))
    local foot = Tex(f, "BACKGROUND", -7, C.header)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(CREATE_FOOTER)
    local line = Tex(f, "BORDER", -6, C.accent, 0.35)
    line:SetPoint("BOTTOMLEFT", foot, "TOPLEFT")
    line:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    ns.OnePixel(line, true)
    -- Einladungsliste etwas kürzer: "Spielername" und "Einladen" hängen an ihrer Unterkante und lagen sonst auf der
    -- goldenen Linie der Fußleiste
    local list = G("CalendarCreateEventInviteList")
    if list and not Forbidden(list) and (list:GetHeight() or 0) > 100 then list:SetHeight(list:GetHeight() - 12) end
    local y = CREATE_FOOTER / 2
    for _, s in ipairs({ { "CalendarCreateEventMassInviteButton", "LEFT", 10 }, { "CalendarCreateEventRaidInviteButton", "LEFT", 10 },
        { "CalendarCreateEventCreateButton", "RIGHT", -10 } }) do
        local b = G(s[1])
        if b and not Forbidden(b) then
            b:ClearAllPoints()
            b:SetPoint(s[2], f, "BOTTOM" .. s[2], s[3], y)
        end
    end
end

local function SkinEventFrame(f)
    if not f or Forbidden(f) then return end
    if f == G("CalendarCreateEventFrame") then CreateFooter(f) end
    if not done[f] then
        done[f] = true
        ns.Hide(f.Border)
        local look = ns.Flat(f, C.background)
        local head = Tex(f, "BACKGROUND", -7, C.header)
        head:SetPoint("TOPLEFT", 1, -1)
        head:SetPoint("TOPRIGHT", -1, -1)
        head:SetHeight(22)
        local line = Tex(f, "BORDER", -6, C.accent, 0.6)
        line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
        line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
        ns.OnePixel(line, true)
        if look then look.mine[head], look.mine[line] = true, true end
        -- Titel-Schild (DialogHeader): Grafik weg, der Titel mittig in unsere Titelleiste
        local header = f.Header
        if type(header) == "table" and not Forbidden(header) then
            ns.HideTextures(header)
            header:ClearAllPoints()
            header:SetPoint("CENTER", f, "TOP", 0, -12)
        end
        local name = f:GetName()
        local close = name and (G(name .. "CloseButton") or G(name:gsub("Frame$", "") .. "CloseButton"))
        if close and not Forbidden(close) then
            ns.SkinClose(close)
            close:ClearAllPoints()
            close:SetPoint("CENTER", f, "TOPRIGHT", -12, -12)
        end
        ns.Watch(f)
        -- Blizzard füllt die Fenster beim Öffnen (Auswahllisten, Einladungsliste) – dann noch einmal durchsehen
        f:HookScript("OnShow", function(self)
            pcall(ScanEvent, self, 1)
            pcall(SortButtons)
        end)
        -- solange offen: Spaltenköpfe prüfen (die Liste lädt nach)
        local watch = CreateFrame("Frame", nil, f)
        local waited = 0
        watch:SetScript("OnUpdate", function(_, elapsed)
            waited = waited + elapsed
            if waited < 0.3 then return end
            waited = 0
            pcall(SortButtons)
        end)
    end
    ScanEvent(f, 1)
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
    if not calSkinned and G("CalendarFrame") then
        Step("calendar", SkinCalendar)
        for _, n in ipairs(EVENT_FRAMES) do Step("event", function() SkinEventFrame(G(n)) end) end
    end
    if not clockSkinned and G("TimeManagerFrame") then Step("clock", SkinClock) end
    if not stopwatchSkinned and G("StopwatchFrame") then Step("stopwatch", SkinStopwatch) end
end)
