-- ForeverHub: gemeinsame Grundlage aller Forever-Addons
-- Liegt (seit 0.41b) nur noch im Hauptaddon ForeverCore. Alle anderen Forever-Addons tragen
-- "## Dependencies: ForeverCore" – ForeverCore laedt damit immer vor ihnen, ForeverHub.UI steht bereit.
--  1. ForeverHub.UI: einheitlicher Stil (Fenster, Ueberschriften, Knoepfe, Regler, Minimap-Knopf,
--     Chat-Ausgabe, Sprache). Jedes Forever-Addon baut seine Oberflaeche damit.
--  2. Sammelknopf: Die Minimap-Knoepfe der Forever-Addons bleiben versteckt; der eine Forever-Core-UI-Knopf oeffnet
--     das gemeinsame Einstellungsfenster (Umschalt: Hub-Fenster, Rechtsklick: /fmove).
--  3. Hub-Fenster (/forever): Liste aller Forever-Addons mit direktem Weg in ihr Menue –
--     auch ohne Minimap-Knoepfe. Addons dort ein-/ausschalten (gilt nach dem Neuladen);
--     beim allerersten Start oeffnet es sich einmal als Begruessung.
--     ForeverCore selbst steht nicht in der Liste (ohne ForeverCore laeuft kein Forever-Addon).
--  4. Eintrag "Forever Core UI" im Blizzard-Optionsmenue (Reiter AddOns) mit Unterseite je Addon.
--  5. Eintrag "Forever Core UI" im Addon-Menue an der Minimap (falls der Client es hat).
--
-- Uebergang: Addons bis 0.32b hatten eine eigene Kopie dieser Datei. Laedt so ein altes Addon (ohne Abhaengigkeit)
-- vor ForeverCore, uebernimmt trotzdem die neueste Version. Ab v21 teilen alle Kopien ihren Zustand (hub.shared: Anmeldungen fuer /fmove, Einrast-Rahmen,
-- Raster, Warteschlange "nach dem Kampf"), und die Funktionen frueher geladener Kopien werden auf
-- die neueste umgeleitet – Addons, die sich bei einer aelteren Kopie angemeldet haben, gehen nicht verloren.
local ADDON_NAME = ...
local VERSION = 74
local PREV = _G.ForeverHub
if PREV and (PREV.version or 0) >= VERSION then return end

local hub = { version = VERSION }
_G.ForeverHub = hub
local SHARED = (PREV and PREV.shared) or {}
hub.shared = SHARED
SHARED.uiTables = SHARED.uiTables or {} -- UI-Tabellen aelterer Kopien (werden am Dateiende umgeleitet)
if PREV and PREV.UI then tinsert(SHARED.uiTables, PREV.UI) end

---------------------------------------------------------------------------
-- 1. Gemeinsamer Stil
---------------------------------------------------------------------------
local UI = {}
hub.UI = UI
-- Schnittstellen zwischen Forever-Addons (v49), statt eigener globaler Namen: ein Addon legt seine Funktionen unter
-- UI.API.<Addonname> = { … } ab, ein anderes ruft sie nur auf, wenn es sie gibt (das Addon kann fehlen)
SHARED.api = SHARED.api or {}
UI.API = SHARED.api

-- Sprache (gemeinsam fuer alle Forever-Addons): Deutsch gibt es nur auf einem deutschen Client; dort laesst
-- sich im Hub-Fenster (/forever) Englisch waehlen. Gespeichert in ForeverHubDB.language ("deDE"/"enUS",
-- nil = automatisch), wirksam nach /reload. UI.GetLanguage() -> "deDE" oder "enUS".
UI.GERMAN_CLIENT = GetLocale() == "deDE"
function UI.GetLanguage()
    if not UI.GERMAN_CLIENT then return "enUS" end
    local db = _G.ForeverHubDB
    if type(db) == "table" and db.language == "enUS" then return "enUS" end
    return "deDE"
end
UI.IS_DE = UI.GetLanguage() == "deDE"
function UI.T(de, en) return UI.GetLanguage() == "deDE" and de or en end
local T = UI.T

-- Spielernamen (gemeinsam für alle Forever-Addons): In Forever heißen Spieler "Vorname Nachname" – je nach Quelle kommt
-- der volle Name (Chat, Würfe, Addon-Nachrichten, teils Einheiten) oder nur der Vorname. Für Rahmen, Plaketten, Würfe
-- usw. reicht meist weniger. ForeverHubDB.nameStyle: "first" (Hexeron) | "initial" (Hexeron S., Standard) | "full".
-- NUR für Spieler aufrufen – auch NPC-Namen haben Leerzeichen. Realm ("-Server") fällt immer weg; geheime Namen
-- kommen unverändert zurück (dürfen nicht zerlegt werden). Volle Namen bleiben dort, wo sie gebraucht werden
-- (Charakter-Übersicht, Tooltip, Chat).
UI.NAME_STYLES = { "first", "initial", "full" }
function UI.NameStyle()
    local db = _G.ForeverHubDB
    local style = type(db) == "table" and db.nameStyle
    return (style == "first" or style == "full") and style or "initial"
end
function UI.PlayerName(name, style)
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return name end
    name = name:match("^([^%-]+)") or name
    style = style or UI.NameStyle()
    if style == "full" then return name end
    local first, rest = name:match("^(%S+)%s+(%S.*)$")
    if not first then return name end
    if style == "first" then return first end
    -- erster Buchstabe des Nachnamens (UTF-8: auch Umlaute)
    local initial = rest:match("^[%z\1-\127\194-\244][\128-\191]*") or rest:sub(1, 1)
    return first .. " " .. initial .. "."
end
-- ForeverHubDB kommt erst mit dem ersten geladenen Forever-Addon: IS_DE danach nachziehen
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function() UI.IS_DE = UI.GetLanguage() == "deDE" end)
end

-- Forever-Core-UI-Logo (liegt in jedem Forever-Addon unter Media\)
UI.LOGO = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Media\\ForeverCore"
UI.NAME = "Forever Core UI"

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
UI.GOLD = { 1, 0.82, 0 }

-- Flacher, dunkler Stil (Vorbild: ForeverQuests von flowfy): dunkle Flaechen, feine Raender,
-- Gold als einzige Akzentfarbe (Hover-Rand, Haekchen, Regler, Titellinie)
UI.COLOR = {
    background = { 0.07, 0.07, 0.09, 0.97 },
    header = { 0.11, 0.11, 0.14, 1 },
    panel = { 0.10, 0.10, 0.12, 0.95 },
    border = { 0.22, 0.22, 0.26, 1 },
    input = { 0.06, 0.06, 0.08, 1 },
    button = { 0.16, 0.16, 0.20, 1 },
    buttonHover = { 0.22, 0.22, 0.27, 1 },
    accent = { 1, 0.82, 0 },
}
local C = UI.COLOR

function UI.SetFlat(frame, bg, border)
    frame:SetBackdrop(FLAT)
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    local b = border or C.border
    frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
end

-- goldener Rand nur beim Ueberfahren (Highlight-Ebene: braucht keine Skripte, die ein Addon ueberschreiben koennte)
local function HoverEdge(frame, withFill)
    if withFill then
        local fill = frame:CreateTexture(nil, "HIGHLIGHT")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(1, 1, 1, 0.06)
    end
    local a = C.accent
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = frame:CreateTexture(nil, "HIGHLIGHT")
        t:SetColorTexture(a[1], a[2], a[3], 0.9)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    end
end

-- Nachrichten zwischen Forever-Addons (ohne Blizzard-Tabellen wie EventRegistry):
--   UI.On("Name", fn)        -> fn wird bei jedem UI.Fire("Name", ...) aufgerufen (abgesichert)
--   UI.Fire("Name", ...)     -> z. B. "ForeverMinimap.Layout", wenn sich Groesse/Leiste der Minimap aendern
SHARED.signals = SHARED.signals or {}
function UI.On(name, fn)
    local list = SHARED.signals[name] or {}
    SHARED.signals[name] = list
    tinsert(list, fn)
end
function UI.Fire(name, ...)
    for _, fn in ipairs(SHARED.signals[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then UI.ReportError("Forever", name, err) end
    end
end

-- Stufenfarbe (Gegner, Quests, Dungeons) nach den klassischen Erfahrungsregeln – Forever levelt wie Classic.
-- Blizzards GetCreatureDifficultyColor/GetQuestDifficultyColor rechnen im Forever-Client mit der Retail-Grenze
-- und faerben Gegner zu frueh grau (z. B. Stufe 15 fuer einen 21er, obwohl es noch Erfahrung gibt).
--   UI.GrayLevel(spielerStufe) -> hoechste Stufe, die keine Erfahrung mehr gibt
--   UI.LevelColor(stufe)       -> { r, g, b } rot / orange / gelb / gruen / grau
function UI.GrayLevel(p)
    p = p or UnitLevel("player")
    if type(p) ~= "number" or p <= 5 then return 0 end
    if p <= 39 then return p - math.floor(p / 10) - 5 end
    if p <= 59 then return p - math.floor(p / 5) - 1 end
    return p - 9
end

local LEVEL_FALLBACK = {
    impossible = { r = 1, g = 0.10, b = 0.10 }, verydifficult = { r = 1, g = 0.50, b = 0.25 },
    difficult = { r = 1, g = 0.82, b = 0 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
    trivial = { r = 0.50, g = 0.50, b = 0.50 },
}
function UI.LevelColor(level)
    local function Pick(key)
        local blizz = _G.QuestDifficultyColors and _G.QuestDifficultyColors[key]
        return blizz or LEVEL_FALLBACK[key]
    end
    local p = UnitLevel("player")
    if type(level) ~= "number" or type(p) ~= "number" or level <= 0 then return Pick("difficult") end
    local diff = level - p
    if diff >= 5 then return Pick("impossible") end
    if diff >= 3 then return Pick("verydifficult") end
    if diff >= -2 then return Pick("difficult") end
    if level > UI.GrayLevel(p) then return Pick("standard") end
    return Pick("trivial")
end

-- Chat-Ausgabe: "ForeverXY: Text" mit goldenem Namen
function UI.Chat(addon, text)
    print("|cffffcc00" .. addon .. "|r: " .. tostring(text))
end

---------------------------------------------------------------------------
-- Gemeinsame Helfer (statt in jedem Addon eigene)
---------------------------------------------------------------------------
-- Fehlerschutz: ein Fehler legt nicht das ganze Addon lahm. Jeder Fehler wird nur EINMAL pro Stelle
-- im Chat gemeldet und immer an die Fehleranzeige (BugSack) weitergegeben. UI.ErrorCount(addon) = Anzahl.
SHARED.errors = SHARED.errors or {}           -- [Addon] = Anzahl seit dem Login
SHARED.reportedErrors = SHARED.reportedErrors or {} -- ["Addon|Stelle"] = true
function UI.ReportError(addon, where, err)
    addon = addon or "Forever"
    where = tostring(where or "?")
    SHARED.errors[addon] = (SHARED.errors[addon] or 0) + 1
    local key = addon .. "|" .. where
    if SHARED.reportedErrors[key] then return end
    SHARED.reportedErrors[key] = true
    UI.Chat(addon, string.format(T("|cffff4444Fehler in %s|r – das Addon läuft weiter. (%s)",
        "|cffff4444Error in %s|r – the addon keeps running. (%s)"), where, tostring(err)))
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, err) end
end

function UI.ErrorCount(addon) return SHARED.errors[addon] or 0 end

-- fn abgesichert ausfuehren lassen: UI.Safe("ForeverXY", "Stelle", fn) liefert eine geschuetzte Funktion
function UI.Safe(addon, where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then UI.ReportError(addon, where, err) end
    end
end

-- Aenderungen an geschuetzten Rahmen sind im Kampf verboten: sofort ausfuehren oder bis nach dem Kampf
-- merken. Gleicher Schluessel = nur der letzte Auftrag zaehlt. Rueckgabe: true = sofort erledigt.
-- Schluessel mit Addon-Namen beginnen ("ForeverFrames:layout"), damit sich Addons nicht ueberschreiben.
SHARED.combatQueue = SHARED.combatQueue or { jobs = {}, order = {} }
function UI.AfterCombat(key, fn, addon)
    if not InCombatLockdown() then
        local ok, err = pcall(fn)
        if not ok then UI.ReportError(addon, key, err) end
        return true
    end
    local q = SHARED.combatQueue
    if not q.jobs[key] then tinsert(q.order, key) end
    q.jobs[key] = { fn = fn, addon = addon }
    return false
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if _G.ForeverHub ~= hub then return end -- nur die neueste Kopie arbeitet die Liste ab
        local q = SHARED.combatQueue
        local order = q.order
        q.order = {}
        for _, key in ipairs(order) do
            local job = q.jobs[key]
            q.jobs[key] = nil
            if job then
                local ok, err = pcall(job.fn)
                if not ok then UI.ReportError(job.addon, key, err) end
            end
        end
    end)
end

-- Blizzard-Teil taint-frei unsichtbar machen: Alpha 0 (auch fuer Unterrahmen) und gegen Zuruecksetzen
-- absichern. SetAlpha startet keine Blizzard-Skripte (anders als Hide/SetParent) -> kein taint; der Rahmen
-- behaelt seinen Platz, nichts verrutscht. Geht auch im Kampf.
--  opts.when()   -> nur unsichtbar halten, solange das true liefert (z. B. Einstellung "ausblenden")
--  opts.children -> Unterrahmen mit einsammeln (Standard: true)
--  opts.noMouse  -> Liste von Rahmen, die nicht mehr anklickbar sein sollen (z. B. Auswahl im Bearbeitungsmodus)
-- Nicht geeignet fuer Rahmen mit geschuetzten, anklickbaren Knoepfen (die blieben unsichtbar klickbar).
-- Erneuter Aufruf sammelt neu hinzugekommene Unterrahmen ein. UI.ShowBlizzard(frame) macht es rueckgaengig.
local settingBlizzAlpha = false
local function HoldAlpha(f, root)
    if not f or not f.SetAlpha or f.fcHideRoot then return end
    f.fcHideRoot = root
    root.fcHideParts[#root.fcHideParts + 1] = f
    hooksecurefunc(f, "SetAlpha", function(self, a)
        local r = self.fcHideRoot
        if settingBlizzAlpha or not r or not r.fcHideActive or (r.fcHideWhen and not r.fcHideWhen()) then return end
        if a and a > 0 then
            settingBlizzAlpha = true
            self:SetAlpha(0)
            settingBlizzAlpha = false
        end
    end)
end

local function CollectChildren(f, root, depth)
    if depth <= 0 or not f.GetChildren then return end
    for _, c in ipairs({ f:GetChildren() }) do
        HoldAlpha(c, root)
        CollectChildren(c, root, depth - 1)
    end
end

function UI.HideBlizzard(frame, opts)
    if not frame then return end
    opts = opts or {}
    frame.fcHideParts = frame.fcHideParts or {}
    frame.fcHideWhen = opts.when or frame.fcHideWhen
    frame.fcHideActive = true
    HoldAlpha(frame, frame)
    if opts.children ~= false then CollectChildren(frame, frame, 3) end
    if frame.fcHideWhen and not frame.fcHideWhen() then return end
    settingBlizzAlpha = true
    for _, p in ipairs(frame.fcHideParts) do p:SetAlpha(0) end
    settingBlizzAlpha = false
    for _, m in ipairs(opts.noMouse or {}) do
        if m and m.EnableMouse then m:EnableMouse(false) end
    end
    frame.fcHideNoMouse = opts.noMouse or frame.fcHideNoMouse
end

function UI.ShowBlizzard(frame)
    if not (frame and frame.fcHideParts) then return end
    frame.fcHideActive = false
    settingBlizzAlpha = true
    for _, p in ipairs(frame.fcHideParts) do p:SetAlpha(1) end
    settingBlizzAlpha = false
    for _, m in ipairs(frame.fcHideNoMouse or {}) do
        if m and m.EnableMouse then m:EnableMouse(true) end
    end
end

-- Anzeige-Fenster (XP-Leiste, Wuerfel-Fenster, Sammelliste …): dunkel, schlanker Rand
function UI.Hud(f, alpha)
    f:SetBackdrop(FLAT)
    f:SetBackdropColor(C.background[1], C.background[2], C.background[3], alpha or 0.88)
    f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
end

-- Innenrahmen fuer Listen, Textfelder und Reiter-Inhalte
function UI.Box(parent, alpha)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop(FLAT)
    b:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], alpha or C.panel[4])
    b:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    return b
end

-- Hauptfenster / Einstellungsfenster: flach und dunkel, Titelleiste mit Goldlinie,
-- verschiebbar, mit Escape schliessbar
-- Gemeinsamer Takt für alle Forever-Addons: statt vieler einzelner Zeitschleifen (C_Timer.NewTicker) läuft ein einziger
-- unsichtbarer Rahmen. Jede Aufgabe hat ihr Intervall und optional eine Bedingung "when" (nur dann wird sie
-- ausgeführt – z. B. nur in einer Gruppe, nur wenn sichtbar). Startzeiten werden verteilt, damit nicht alle Aufgaben
-- im selben Bild rechnen. Fehler einer Aufgabe werden einmal gemeldet, die anderen laufen weiter.
--   local task = UI.Every(0.25, fn, { addon = "ForeverUnits", name = "Ziel des Ziels", when = function() ... end })
--   UI.StopEvery(task)
-- Der Rahmen hat kein Elternteil: er läuft auch bei ausgeblendeter Oberfläche (Alt+Z) weiter, wie C_Timer.
SHARED.tasks = SHARED.tasks or {}
local tasks = SHARED.tasks
if not SHARED.taskDriver then
    local driver = CreateFrame("Frame")
    SHARED.taskDriver = driver
    driver:SetScript("OnUpdate", function(_, elapsed)
        for i = 1, #tasks do
            local t = tasks[i]
            if t and not t.stopped then
                t.acc = t.acc + elapsed
                if t.acc >= t.interval then
                    t.acc = t.acc - t.interval
                    if t.acc > t.interval then t.acc = 0 end -- nach einer Ladepause nicht nachholen
                    local run = true
                    if t.when then
                        local ok, res = pcall(t.when)
                        run = ok and res and true or false
                    end
                    if run then
                        local ok, err = pcall(t.fn)
                        if not ok and not t.reported then
                            t.reported = true
                            if UI.ReportError then UI.ReportError(t.addon or "ForeverCore", t.name or "Takt", err) end
                        end
                    end
                end
            end
        end
    end)
end

function UI.Every(interval, fn, opts)
    opts = opts or {}
    local t = { interval = math.max(0.01, interval or 1), fn = fn, when = opts.when, addon = opts.addon, name = opts.name }
    t.acc = math.random() * t.interval -- Startzeiten verteilen
    tasks[#tasks + 1] = t
    return t
end

function UI.StopEvery(t) if t then t.stopped = true end end

-- Schließen-Kreuz im Forever-Stil: zwei feine, gedrehte Linien (keine Blizzard-Grafik – Blizzards UIPanelCloseButton
-- wurde in diesem Client zeitweise nicht mehr gezeichnet). Grau, beim Darüberfahren gold.
function UI.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b.lines = {}
    for i, angle in ipairs({ 45, -45 }) do
        local line = b:CreateTexture(nil, "ARTWORK")
        line:SetSize(12, 2)
        line:SetPoint("CENTER")
        line:SetColorTexture(1, 1, 1, 1)
        line:SetRotation(math.rad(angle))
        line:SetVertexColor(0.75, 0.75, 0.78, 1)
        b.lines[i] = line
    end
    local function Color(r, g, bl) for _, l in ipairs(b.lines) do l:SetVertexColor(r, g, bl, 1) end end
    b:SetScript("OnEnter", function() Color(C.accent[1], C.accent[2], C.accent[3]) end)
    b:SetScript("OnLeave", function() Color(0.75, 0.75, 0.78) end)
    b:SetScript("OnMouseDown", function() for _, l in ipairs(b.lines) do l:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function() for _, l in ipairs(b.lines) do l:SetPoint("CENTER", 0, 0) end end)
    b:SetScript("OnClick", onClick)
    return b
end

function UI.Window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.SetFlat(f, C.background)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(26)
    header:SetBackdrop({ bgFile = WHITE })
    header:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    f.header = header

    -- dezentes Logo links neben dem Titel
    local logo = header:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(UI.LOGO)
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 8, 0)
    f.TitleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.TitleText:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    f.TitleText:SetText(title)

    local close = UI.CloseButton(header, function() f:Hide() end)
    close:SetPoint("RIGHT", -4, 0)
    f.CloseButton = close
    -- jedes benannte Forever-Fenster ist mit der Maus skalierbar (Griff unten rechts)
    if name then UI.MakeResizable(f) end
    UI.RegisterWindow(f)
    return f
end

---------------------------------------------------------------------------
-- Fenster-Stapel: das zuletzt geoeffnete bzw. angeklickte Forever-Fenster liegt ueber allen anderen.
-- Alle Einstellungsfenster teilen sich die Ebene DIALOG; ohne Ordnung verzahnen sich ihre Bedienelemente
-- (Unterebenen ueberschneiden sich). Gilt addon-uebergreifend (gemeinsamer Zustand SHARED.windows).
---------------------------------------------------------------------------
SHARED.windows = SHARED.windows or {}
local LEVEL_LIMIT = 8000

-- hoechste Unterebene eines Fensters samt seiner Bedienelemente
local function HighestLevel(frame, depth)
    local top = frame:GetFrameLevel()
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            top = math.max(top, HighestLevel(child, depth - 1))
        end
    end
    return top
end

-- Ebenen neu durchnummerieren, wenn sie zu hoch werden (Reihenfolge bleibt erhalten)
local function Renumber(strata)
    local list = {}
    for w in pairs(SHARED.windows) do
        if w:GetFrameStrata() == strata then list[#list + 1] = w end
    end
    table.sort(list, function(a, b) return a:GetFrameLevel() < b:GetFrameLevel() end)
    local level = 10
    for _, w in ipairs(list) do
        w:SetFrameLevel(level)
        level = HighestLevel(w, 5) + 10
    end
end

function UI.BringToFront(f, again)
    local strata = f:GetFrameStrata()
    local top = 0
    for w in pairs(SHARED.windows) do
        if w ~= f and w:IsShown() and w:GetFrameStrata() == strata then
            top = math.max(top, HighestLevel(w, 5))
        end
    end
    if top < f:GetFrameLevel() then return end -- liegt schon oben
    local level = top + 10
    if level > LEVEL_LIMIT and not again then
        Renumber(strata)
        return UI.BringToFront(f, true)
    end
    f:SetFrameLevel(math.min(level, LEVEL_LIMIT))
end

-- Fenster anmelden: beim Oeffnen und beim Anklicken (Flaeche oder Titelleiste) nach oben.
-- Auch fuer Fenster mit eigener Stil-Datei nutzbar (ForeverQuests/ForeverBars: Style.CreateWindow).
function UI.RegisterWindow(f)
    if not f or SHARED.windows[f] then return end
    SHARED.windows[f] = true
    local function Front() UI.BringToFront(f) end
    f:HookScript("OnShow", Front)
    f:HookScript("OnMouseDown", Front)
    if f.header and f.header.HookScript then f.header:HookScript("OnMouseDown", Front) end
end

---------------------------------------------------------------------------
-- Fenstergroesse mit der Maus: Griff unten rechts.
--  mode "scale" (Standard): das ganze Fenster wird groesser/kleiner (Inhalt bleibt wie angeordnet)
--  mode "size": echte Groesse aendern (fuer Fenster, deren Inhalt mitwaechst, z. B. ForeverSpellbook);
--               opts.minW/minH/maxW/maxH, opts.onResize(w, h)
-- Gespeichert je Fenstername in ForeverHubDB.windows; Rechtsklick auf den Griff = Standardgroesse.
---------------------------------------------------------------------------
local function WindowDB(name)
    if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
    local db = _G.ForeverHubDB
    db.windows = db.windows or {}
    db.windows[name] = db.windows[name] or {}
    return db.windows[name]
end

-- Fenster an seiner linken oberen Ecke festhalten (damit Skalieren/Groesse nicht "wegspringt")
local function PinTopLeft(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function CursorUI()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

function UI.MakeResizable(f, opts)
    opts = opts or {}
    local name = f:GetName()
    if not name then return end
    f.fcResize = { mode = opts.mode or "scale", opts = opts, defW = f:GetWidth(), defH = f:GetHeight() }
    local info = f.fcResize

    if not f.fcGrip then
        local grip = CreateFrame("Button", nil, f)
        grip:SetSize(14, 14) -- in der Ecke, frei von Knoepfen, die 16 px vom Rand sitzen
        grip:SetPoint("BOTTOMRIGHT", -1, 1)
        grip:SetFrameLevel(f:GetFrameLevel() + 20)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:RegisterForClicks("RightButtonUp")
        f.fcGrip = grip

        grip:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(T("Größe ändern", "Resize"))
            GameTooltip:AddLine(T("Ziehen: größer/kleiner · Rechtsklick: Standardgröße",
                "Drag: bigger/smaller · Right-click: default size"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        grip:SetScript("OnLeave", GameTooltip_Hide)

        -- Rechtsklick: zuruecksetzen
        grip:SetScript("OnClick", function()
            local i = f.fcResize
            local db = WindowDB(name)
            PinTopLeft(f)
            if i.mode == "size" then
                db.w, db.h = nil, nil
                f:SetSize(i.defW, i.defH)
                if i.opts.onResize then i.opts.onResize(i.defW, i.defH) end
            else
                db.scale = nil
                local left, top = f:GetLeft() * f:GetScale(), f:GetTop() * f:GetScale()
                f:SetScale(1)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end)

        grip:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local i = f.fcResize
            PinTopLeft(f)
            if i.mode == "size" then
                f:SetResizable(true)
                local o = i.opts
                if f.SetResizeBounds then
                    f:SetResizeBounds(o.minW or i.defW, o.minH or i.defH, o.maxW or 2000, o.maxH or 1400)
                end
                f:StartSizing("BOTTOMRIGHT")
                return
            end
            -- Skalieren: neue Groesse aus der Mausbewegung, linke obere Ecke bleibt stehen
            local startScale = f:GetScale()
            local w, h = f:GetWidth() * startScale, f:GetHeight() * startScale
            local left, top = f:GetLeft() * startScale, f:GetTop() * startScale
            local cx, cy = CursorUI()
            self:SetScript("OnUpdate", function()
                local x, y = CursorUI()
                local factor = ((w + x - cx) / w + (h + cy - y) / h) / 2
                local s = math.max(0.6, math.min(1.6, startScale * factor))
                f:SetScale(s)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / s, top / s)
            end)
        end)
        grip:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            local i = f.fcResize
            local db = WindowDB(name)
            if i.mode == "size" then
                f:StopMovingOrSizing()
                PinTopLeft(f)
                db.w, db.h = math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5)
                if i.opts.onResize then i.opts.onResize(f:GetWidth(), f:GetHeight()) end
            else
                self:SetScript("OnUpdate", nil)
                db.scale = math.floor(f:GetScale() * 100 + 0.5) / 100
            end
        end)

        -- gespeicherte Groesse beim ersten Oeffnen uebernehmen (gespeicherte Werte gibt es erst nach dem Laden)
        f:HookScript("OnShow", function()
            if f.fcResizeApplied then return end
            f.fcResizeApplied = true
            local i = f.fcResize
            local db = WindowDB(name)
            if i.mode == "size" and db.w and db.h then
                f:SetSize(db.w, db.h)
                if i.opts.onResize then i.opts.onResize(db.w, db.h) end
            elseif i.mode == "scale" and db.scale then
                f:SetScale(db.scale)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- Abschnitte: jede Ueberschrift bekommt einen dezenten Kasten (wie in ForeverQuests).
-- Beim Oeffnen eines Fensters wird ausgemessen, was unter der Ueberschrift steht – bis zur
-- naechsten Ueberschrift in derselben Spalte – und der Kasten passend darum gezeichnet.
-- So braucht kein Addon seine Einstellungen neu anzuordnen.
---------------------------------------------------------------------------
local function NewSectionBox(parent)
    local b = {}
    b.fill = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], C.panel[4])
    b.edges = {}
    for i = 1, 4 do
        local e = parent:CreateTexture(nil, "BORDER", nil, 1)
        e:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        b.edges[i] = e
    end
    local f, e = b.fill, b.edges
    e[1]:SetPoint("TOPLEFT", f, "TOPLEFT") e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT") e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT") e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", f, "TOPLEFT") e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT") e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT") e[4]:SetWidth(1)
    return b
end

-- haengt ein Element (auch ueber Umwege) am unteren Rand des Fensters? (Fussleiste, Hintergrund)
local function AtBottom(obj, parent)
    for _ = 1, 6 do
        local nextObj
        for i = 1, (obj.GetNumPoints and obj:GetNumPoints() or 0) do
            local point, rel = obj:GetPoint(i)
            if (not rel or rel == parent) and point and point:find("BOTTOM") then return true end
            if rel and rel ~= parent and not nextObj then nextObj = rel end
        end
        if not nextObj or not nextObj.GetNumPoints then return false end
        obj = nextObj
    end
    return false
end

function UI.LayoutSections(parent)
    local secs = parent.fcSections
    if not secs or not parent:IsVisible() then return end
    local pl, pt = parent:GetLeft(), parent:GetTop()
    local pw = parent:GetWidth()
    if not (pl and pt and pw) then return end
    local skip = {}
    for _, s in ipairs(secs) do skip[s.fs] = true end
    if parent.header then skip[parent.header] = true end

    -- alles Sichtbare im Fenster, relativ zur linken oberen Ecke. Bei Haekchen zaehlt der Text mit.
    local items = {}
    local function Add(obj)
        if skip[obj] or not obj:IsShown() then return end
        local l, r, t, b = obj:GetLeft(), obj:GetRight(), obj:GetTop(), obj:GetBottom()
        if not (l and r and t and b) or AtBottom(obj, parent) then return end
        local label = obj.label
        if type(label) == "table" and label.GetRight and label:IsShown() and label:GetRight() then
            r = math.max(r, label:GetRight())
        end
        items[#items + 1] = { l = l - pl, r = r - pl, t = t - pt, b = b - pt }
    end
    for _, c in ipairs({ parent:GetChildren() }) do Add(c) end
    for _, r in ipairs({ parent:GetRegions() }) do
        if r:IsObjectType("FontString") then Add(r) end
    end

    -- Kasten-Regeln wie im Menü von ForeverBars (v59): 12 px zwischen den Kästen (neben- und untereinander), Kästen
    -- über die volle Breite (rechts 12 px vor dem Rand des Seitenbereichs bzw. des Fensters), Kästen einer Reihe
    -- gleich hoch. Ein Kasten reicht bis kurz vor den nächsten Kasten darunter, die letzten Kästen jeder Spalte enden
    -- auf gleicher Höhe. Die Lage der Bedienelemente bestimmt weiter die Seite selbst.
    local GAP, MARGIN = 12, 12
    local maxRight = pw - MARGIN
    local win = _G.ForeverSettingsWindow
    local area = win and win.content
    if area and area:GetRight() then
        local p = parent
        for _ = 1, 8 do
            if not p then break end
            if p == area then maxRight = area:GetRight() - pl - MARGIN break end
            p = p:GetParent()
        end
    end

    local headerBottom = parent.header and parent.header:GetBottom() and (parent.header:GetBottom() - pt)
    local boxes = {}
    for _, s in ipairs(secs) do
        local hl = s.x - 8
        -- rechte Grenze: schmale Überschriften (Spalten) enden 12 px vor dem Kasten der nächsten Spalte rechts davon,
        -- sonst (und bei breiten Überschriften) am rechten Rand
        local cap = maxRight
        if s.width < 400 then
            for _, o in ipairs(secs) do
                if o.x > s.x + 20 then cap = math.min(cap, o.x - 8 - GAP) end
            end
        end
        -- nächste Überschrift darunter, die in diese Spalte fällt (breite Überschriften gelten für alle Spalten)
        local nextY
        for _, o in ipairs(secs) do
            if o ~= s and o.y < s.y and ((o.x < cap and o.x + 8 > hl) or o.width >= 400) then
                if not nextY or o.y > nextY then nextY = o.y end
            end
        end
        -- Inhalt des Abschnitts: unter der Überschrift, über der nächsten, links in dieser Spalte
        local bottom = s.y - 18
        for _, it in ipairs(items) do
            if it.l >= hl - 4 and it.l < cap and it.t <= s.y + 2 and (not nextY or it.t > nextY + 2) then
                bottom = math.min(bottom, it.b)
            end
        end
        local top = s.y + 9
        if headerBottom then top = math.min(top, headerBottom - 2) end
        local boxBottom
        if nextY then
            -- bis 12 px vor den nächsten Kasten; reicht der Inhalt tiefer, mindestens 6 px unter den Inhalt
            -- (der Abstand zum nächsten Kasten bleibt dann trotzdem mindestens 4 px)
            boxBottom = math.max(math.min(nextY + 9 + GAP, bottom - 6), nextY + 13)
        else
            boxBottom = bottom - 10
        end
        boxes[#boxes + 1] = { s = s, hl = hl, right = cap, top = top, bottom = boxBottom, last = nextY == nil }
    end
    -- die letzten Kästen der Spalten enden auf gleicher Höhe (wie die unteren Kästen bei ForeverBars)
    local lowest
    for _, b in ipairs(boxes) do
        if b.last and (not lowest or b.bottom < lowest) then lowest = b.bottom end
    end
    for _, b in ipairs(boxes) do
        if b.last and lowest then b.bottom = lowest end
        local s = b.s
        s.box = s.box or NewSectionBox(parent)
        s.box.fill:ClearAllPoints()
        s.box.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", b.hl, b.top)
        s.box.fill:SetSize(math.max(24, b.right - b.hl), math.max(24, b.top - b.bottom))
        -- Linie unter der Überschrift über die ganze Kastenbreite
        s.line:ClearAllPoints()
        s.line:SetPoint("TOPLEFT", parent, "TOPLEFT", b.hl + 6, s.y - 17)
        s.line:SetWidth(math.max(1, b.right - b.hl - 12))
    end
end

-- Abschnitts-Ueberschrift: goldene Schrift mit feiner heller Linie darunter (im eigenen Kasten)
function UI.Header(parent, x, y, text, width)
    width = width or 318
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", x - 4, y - 17)
    line:SetSize(width - 4, 1)
    if not parent.fcSections then
        parent.fcSections = {}
        parent:HookScript("OnShow", function(self)
            C_Timer.After(0, function() UI.LayoutSections(self) end)
        end)
    end
    table.insert(parent.fcSections, { fs = fs, line = line, x = x, y = y, width = width })
    if parent:IsVisible() then C_Timer.After(0, function() UI.LayoutSections(parent) end) end
    return fs
end
-- Grauer Erklaertext
function UI.Hint(parent, x, y, width, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if x then fs:SetPoint("TOPLEFT", x, y) end
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Beschriftung: "label" = weiss (Werte, Regler-Titel), "field" = gold (Feldname vor Eingabe)
function UI.Text(parent, kind, text)
    local font = kind == "field" and "GameFontNormal" or "GameFontHighlightSmall"
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Flacher Knopf. Deaktiviert (z. B. der gerade offene Reiter) = goldene Schrift und Rand.
function UI.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    UI.SetFlat(b, C.button)
    HoverEdge(b, true)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    b:SetFontString(label)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontNormalSmall")
    b:SetText(text)
    b:SetScript("OnDisable", function(self)
        self:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
    end)
    b:SetScript("OnEnable", function(self)
        self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
    b:SetPushedTextOffset(0, -1)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- kleiner Pfeil rechts im Knopf (Auswahlliste)
function UI.AddArrow(b)
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -22, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    b.fcArrow = true -- Auswahlliste: ihr Text ist ein Wert, kein Name (die Einstellungssuche überspringt ihn)
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetRotation(-math.pi / 2)
    arrow:SetVertexColor(0.8, 0.8, 0.8)
    return b
end

-- Haekchen als kleines Kaestchen, das sich gold fuellt; Klick auf den Text zaehlt mit.
-- onClick(checked) bekommt true/false
function UI.Check(parent, x, y, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    if x then cb:SetPoint("TOPLEFT", x + 4, y - 4) end -- gleiche Lage wie das fruehere 24-px-Haekchen
    UI.SetFlat(cb, C.input)
    HoverEdge(cb, false)
    local check = cb:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    check:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    cb:SetCheckedTexture(check)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    cb.label, cb.Text = text, text
    cb:SetHitRectInsets(0, -(text:GetStringWidth() + 10), -4, -4)
    if onClick then
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    end
    return cb
end

-- Regler im flachen Stil: duenne Leiste, goldener Griff, Gold bis zum Griff (auch fuer eigene Regler)
function UI.StyleSlider(s)
    if s.SetBackdrop then s:SetBackdrop(nil) end
    s:SetHeight(16)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(0.25, 0.25, 0.30, 1)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 16)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    s:SetThumbTexture(thumb)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
    return s
end

-- Schieberegler mit Titel darueber und – / + daneben.
-- opts: width, unit (z. B. " px"), format(value) -> Anzeigetext
-- onChange(value) wird nur bei Aenderungen durch den Spieler gerufen;
-- s:Load(value) setzt den Wert ohne onChange.
function UI.Slider(parent, x, y, label, minV, maxV, step, onChange, opts)
    opts = opts or {}
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", x, y)
    title:SetTextColor(0.75, 0.75, 0.75)

    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(opts.width or 170, 16)
    s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    UI.StyleSlider(s)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.title = title

    local function Show(value)
        local shown = opts.format and opts.format(value)
        if not shown then
            if math.abs(value - math.floor(value + 0.5)) < 0.001 then
                shown = string.format("%d%s", math.floor(value + 0.5), opts.unit or "")
            else
                shown = string.format("%.1f%s", value, opts.unit or "")
            end
        end
        title:SetText(label .. ": |cffffffff" .. shown .. "|r")
    end

    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if self.loading or self.lastValue == value then return end
        self.lastValue = value
        if onChange then onChange(value) end
    end)

    local minus = UI.Button(parent, "–", 20, function() s:SetValue(s:GetValue() - step) end)
    minus:SetHeight(18)
    minus:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local plus = UI.Button(parent, "+", 20, function() s:SetValue(s:GetValue() + step) end)
    plus:SetHeight(18)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)

    function s:Load(value)
        self.loading = true
        self.lastValue = value
        self:SetValue(value)
        Show(value)
        self.loading = false
    end
    return s
end

-- Eingabefeld im flachen Stil (goldener Rand, solange man tippt)
function UI.EditBox(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, height or 20)
    UI.SetFlat(box, C.input)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    end)
    box:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
    return box
end

---------------------------------------------------------------------------
-- Aufklapp-Liste im flachen Stil (statt Blizzard-Menue), Vorbild ForeverQuests.
-- items = { { title = "…" }, { radio = true, text = "…", checked = fn, onClick = fn },
--           { checkbox = true, … }, { text = "…", onClick = fn, disabled = bool }, { divider = true } }
-- opts: align = "LEFT" (linksbuendig unter dem Knopf), atCursor = true
---------------------------------------------------------------------------
local menuFrame, menuCatcher
local menuRows = {}
local MENU_ROW_H = 22

function UI.HideMenu()
    if menuFrame then menuFrame:Hide() end
end

local function MenuRow(i)
    local row = menuRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menuFrame)
    row:SetHeight(MENU_ROW_H)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.06)
    row.box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.box:SetSize(12, 12)
    row.box:SetPoint("LEFT", 10, 0)
    UI.SetFlat(row.box, C.input)
    row.fill = row.box:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", 2, -2)
    row.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    row.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", 8, 0)
    row.line:SetPoint("RIGHT", -8, 0)
    row.line:SetColorTexture(1, 1, 1, 0.1)
    row:SetScript("OnClick", function(self)
        local item = self.item
        if not item or not item.onClick then return end
        if item.checkbox then
            item.onClick()
            self.fill:SetShown(item.checked and item.checked() or false)
        else
            UI.HideMenu()
            item.onClick()
        end
    end)
    menuRows[i] = row
    return row
end

function UI.ShowMenu(owner, items, opts)
    opts = opts or {}
    if not menuFrame then
        -- unsichtbare Flaeche ueber dem Bildschirm: Klick daneben schliesst die Liste
        menuCatcher = CreateFrame("Button", nil, UIParent)
        menuCatcher:SetAllPoints(UIParent)
        menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        menuCatcher:RegisterForClicks("AnyUp")
        menuCatcher:SetScript("OnClick", UI.HideMenu)
        menuCatcher:Hide()
        menuFrame = CreateFrame("Frame", "ForeverHubMenu", UIParent, "BackdropTemplate")
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(menuCatcher:GetFrameLevel() + 10)
        menuFrame:SetClampedToScreen(true)
        menuFrame:EnableMouse(true)
        UI.SetFlat(menuFrame, C.background)
        menuFrame:SetScript("OnHide", function() menuCatcher:Hide() end)
        menuFrame:Hide()
        tinsert(UISpecialFrames, "ForeverHubMenu")
    end
    -- zweiter Klick auf denselben Knopf schliesst die Liste
    if menuFrame:IsShown() and menuFrame.owner == owner then UI.HideMenu() return end
    menuFrame.owner = owner

    local y, width = -6, 180
    for i, item in ipairs(items) do
        local row = MenuRow(i)
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 1, y)
        row:SetPoint("RIGHT", -1, 0)
        local hasBox = (item.radio or item.checkbox) and true or false
        local clickable = item.onClick ~= nil and not item.disabled
        row.line:SetShown(item.divider == true)
        row.box:SetShown(hasBox)
        row.highlight:SetShown(clickable)
        row:EnableMouse(clickable)
        row.text:ClearAllPoints()
        if item.divider then
            row:SetHeight(9)
            row.text:SetText("")
        elseif item.title then
            row:SetHeight(MENU_ROW_H)
            row.text:SetText(item.title)
            row.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            row.text:SetPoint("LEFT", 10, 0)
        else
            row:SetHeight(MENU_ROW_H)
            row.text:SetText(item.text)
            if item.disabled then row.text:SetTextColor(0.45, 0.45, 0.45)
            else row.text:SetTextColor(0.9, 0.9, 0.9) end
            row.text:SetPoint("LEFT", hasBox and 30 or 12, 0)
            row.fill:SetShown(hasBox and item.checked and item.checked() or false)
        end
        width = math.max(width, row.text:GetStringWidth() + (hasBox and 50 or 32))
        row:Show()
        y = y - row:GetHeight()
    end
    for i = #items + 1, #menuRows do menuRows[i]:Hide() end

    menuFrame:ClearAllPoints()
    if opts.atCursor then
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale - 2)
    elseif opts.align == "LEFT" then
        width = math.max(width, owner:GetWidth())
        menuFrame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    else
        menuFrame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    end
    menuFrame:SetSize(width, -y + 6)
    menuCatcher:Show()
    menuFrame:Show()
end

-- Auswahl-Liste fuer Einstellungen: list = { { key, label }, … }; current = Schluessel; pick(key).
-- Kurze Listen im flachen Stil, sehr lange (z. B. viele Schriften) im Blizzard-Menue mit Bildlauf.
function UI.ChoiceMenu(owner, list, current, pick)
    if #list <= 20 then
        local items = {}
        for _, c in ipairs(list) do
            items[#items + 1] = { radio = true, text = c.label, checked = function() return current() == c.key end,
                onClick = function() pick(c.key) end }
        end
        UI.ShowMenu(owner, items, { align = "LEFT" })
        return true
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            if root.SetScrollMode then root:SetScrollMode(400) end
            for _, c in ipairs(list) do
                root:CreateRadio(c.label, function() return current() == c.key end, function() pick(c.key) end)
            end
        end)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Menue-Bausteine nach CLAUDE.md 7.1 (Masse aus dem ForeverQuests-Menue, von flowfy festgelegt).
-- Neue Einstellungsfenster werden damit gebaut; aeltere (UI.Window/UI.Header) bleiben vorerst unveraendert.
-- Jedes Bedienelement hat :Refresh() und meldet sich beim Fenster an – beim Oeffnen zeigt es die aktuellen Werte.
---------------------------------------------------------------------------
UI.MENU = { pad = 12, headerHeight = 40, panelTop = -52, contentX = 14, contentY = -44, checkStep = 24,
            sliderStep = 46, choiceStep = 30, dropdownX = 136, footerWidth = 150, footerHeight = 26,
            sidebarWidth = 200 }

local function SetAccentBorder(frame, on)
    if on then
        frame:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    else
        frame:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end
end

-- Eigener Tooltip im Forever-Stil: dunkel, graue Raender, goldene Linie oben (Blizzards Zierrand ausgeblendet)
local menuTip
function UI.GetTooltip()
    if menuTip then return menuTip end
    local tip = CreateFrame("GameTooltip", "ForeverHubTooltip", UIParent, "GameTooltipTemplate")
    tip:SetFrameStrata("TOOLTIP")
    local bg = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.97)
    local edges = {}
    local function Edge(p1, p2, horizontal)
        local e = tip:CreateTexture(nil, "BACKGROUND", nil, -7)
        e:SetColorTexture(1, 1, 1, 1)
        e:SetPoint(p1)
        e:SetPoint(p2)
        if horizontal then e:SetHeight(1) else e:SetWidth(1) end
        edges[#edges + 1] = e
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    -- Rand rundum gold wie ForeverTooltip (dort abschaltbar: "Rahmen rundum gold" aus = grau mit Goldlinie oben) (v55)
    tip:HookScript("OnShow", function()
        local grey = _G.ForeverTooltipDB and _G.ForeverTooltipDB.goldEdge == false
        for i, e in ipairs(edges) do
            if grey and i > 1 then e:SetVertexColor(C.border[1], C.border[2], C.border[3], C.border[4] or 1)
            else e:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7) end
        end
    end)
    local function HideNineSlice(self) if self.NineSlice then self.NineSlice:Hide() end end
    HideNineSlice(tip)
    tip:HookScript("OnShow", HideNineSlice)
    menuTip = tip
    return tip
end

-- Tooltip: Text oder Funktion(tip)
local function ShowMenuTip(owner, tooltip)
    if not tooltip then return end
    local tip = UI.GetTooltip()
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    if type(tooltip) == "function" then tooltip(tip) else tip:AddLine(tooltip, 1, 1, 1, true) end
    tip:Show()
end

local function RegisterControl(parent, control)
    local w = parent.menuWindow or parent
    w.menuControls = w.menuControls or {}
    tinsert(w.menuControls, control)
end

-- Fenster: Titelleiste 40 hoch mit grossem Titel und Untertitel, nur die Titelleiste verschiebt
function UI.MenuWindow(name, title, subtitle, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    UI.SetFlat(f, C.background)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(UI.MENU.headerHeight)
    header:SetBackdrop({ bgFile = WHITE })
    header:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    f.header = header

    f.TitleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.TitleText:SetPoint("LEFT", 16, 0)
    f.TitleText:SetText(title or "")
    f.SubText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.SubText:SetPoint("LEFT", f.TitleText, "RIGHT", 10, -1)
    f.SubText:SetText(subtitle or "")
    local close = UI.CloseButton(header, function() f:Hide() end)
    close:SetPoint("RIGHT", -8, 0)
    f.CloseButton = close

    f.menuWindow = f
    function f:RefreshAll()
        for _, c in ipairs(self.menuControls or {}) do if c.Refresh then c:Refresh() end end
    end
    f:HookScript("OnShow", function(self) self:RefreshAll() end)
    f:HookScript("OnHide", UI.HideMenu) -- offene Auswahlliste schliessen
    if name then UI.MakeResizable(f) end
    UI.RegisterWindow(f)
    return f
end

-- Feld (Abschnitt): Flaeche, Ueberschrift bei 14/-12, Trennlinie bei -30; Inhalt ab 14/-44
function UI.MenuPanel(parent, title)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    UI.SetFlat(p, C.panel)
    p.menuWindow = parent.menuWindow or parent
    if title then
        p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p.title:SetPoint("TOPLEFT", 14, -12)
        p.title:SetText(title)
        local line = p:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 12, -30)
        line:SetPoint("TOPRIGHT", -12, -30)
    end
    return p
end

-- Knopf: Hover = hellere Flaeche + goldener Rand, Tooltip im eigenen Stil; Hoehe 22 (Feld) bzw. 26 (Fussleiste)
function UI.MenuButton(parent, text, width, height, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height or 22)
    UI.SetFlat(b, C.button)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    b:SetFontString(label)
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text or "")
    b.tooltip = tooltip
    b:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropColor(C.buttonHover[1], C.buttonHover[2], C.buttonHover[3], 1)
        SetAccentBorder(self, true)
        ShowMenuTip(self, self.tooltip)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
        SetAccentBorder(self, false)
        UI.GetTooltip():Hide()
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Haekchen: Kaestchen 16, Beschriftung GameFontHighlight 8 px daneben (mit anklickbar), Hover goldener Rand
function UI.MenuCheck(parent, x, y, label, get, set, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    cb:SetPoint("TOPLEFT", x, y)
    UI.SetFlat(cb, C.input)
    local mark = cb:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    cb:SetCheckedTexture(mark)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb.label:SetJustifyH("LEFT")
    cb.label:SetText(label)
    cb.Text = cb.label
    cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 10), -3, -3)
    cb:SetScript("OnEnter", function(self) SetAccentBorder(self, true) ShowMenuTip(self, tooltip) end)
    cb:SetScript("OnLeave", function(self) SetAccentBorder(self, false) UI.GetTooltip():Hide() end)
    cb:SetScript("OnClick", function(self) if set then set(self:GetChecked() and true or false) end end)
    function cb:Refresh() if get then self:SetChecked(get() and true or false) end end
    RegisterControl(parent, cb)
    return cb
end

-- Zahl anzeigen: ganze Zahlen ohne Nachkommastellen
local function FormatNumber(v)
    if math.abs(v - math.floor(v + 0.5)) < 0.001 then return tostring(math.floor(v + 0.5)) end
    return string.format("%.1f", v)
end

-- Zahlenfeld 50 x 20: Enter uebernimmt (auf min/max begrenzt), Escape verwirft
local function MenuNumberBox(parent, get, set, minV, maxV, step)
    local e = UI.EditBox(parent, 50, 20)
    e:SetJustifyH("CENTER")
    local function Apply(self)
        local text = (self:GetText() or ""):gsub(",", ".") -- Komma als Dezimalzeichen erlauben
        local v = tonumber(text)
        if v then
            if step and step > 0 then v = math.floor(v / step + 0.5) * step end
            if minV then v = math.max(minV, v) end
            if maxV then v = math.min(maxV, v) end
            set(v)
        end
        self:SetText(FormatNumber(get() or 0))
        self:ClearFocus()
    end
    e:SetScript("OnEnterPressed", Apply)
    e:SetScript("OnEscapePressed", function(self) self:SetText(FormatNumber(get() or 0)) self:ClearFocus() end)
    return e
end

-- Regler: graue Beschriftung, 18 px darunter die Leiste (230 breit), rechts daneben (12 px) das Zahlenfeld
function UI.MenuSlider(parent, x, y, label, minV, maxV, step, get, set, opts)
    opts = opts or {}
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", x, y)
    title:SetTextColor(0.75, 0.75, 0.75)
    title:SetText(label)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(opts.width or 230, 16)
    s:SetPoint("TOPLEFT", x, y - 18)
    UI.StyleSlider(s)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.title = title
    local box = MenuNumberBox(parent, get, function(v) s:SetValue(v) end, minV, maxV, step)
    box:SetPoint("LEFT", s, "RIGHT", 12, 0)
    s.box = box
    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        box:SetText(FormatNumber(value))
        if self.loading or self.lastValue == value then return end
        self.lastValue = value
        set(value)
    end)
    function s:Refresh()
        local v = get() or minV
        self.loading = true
        self.lastValue = v
        self:SetValue(v)
        box:SetText(FormatNumber(v))
        self.loading = false
    end
    RegisterControl(parent, s)
    return s
end

-- Auswahlfeld: Beschriftung links, Knopf 136 px weiter rechts (158 x 22) mit Pfeil; Liste im Forever-Stil
-- list = { { key = …, label = … }, … }
function UI.MenuDropdown(parent, x, y, label, list, get, set, width)
    local b = UI.MenuButton(parent, "", width or 158, 22)
    b:SetPoint("TOPLEFT", x + UI.MENU.dropdownX, y)
    UI.AddArrow(b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", b, "LEFT", -UI.MENU.dropdownX, 0)
    fs:SetText(label)
    b.label = fs
    local function LabelOf(key)
        for _, c in ipairs(list) do if c.key == key then return c.label end end
        return tostring(key or "")
    end
    b:SetScript("OnClick", function(self)
        local items = {}
        for _, c in ipairs(list) do
            items[#items + 1] = { radio = true, text = c.label, checked = function() return get() == c.key end,
                onClick = function() set(c.key) self:Refresh() end }
        end
        UI.ShowMenu(self, items, { align = "LEFT" })
    end)
    function b:Refresh() self:SetText(LabelOf(get())) end
    RegisterControl(parent, b)
    return b
end

-- Zahl mit Beschriftung (z. B. X/Y-Position): Beschriftung GameFontHighlight, Zahlenfeld 50 x 20 daneben
function UI.MenuNumber(parent, x, y, label, get, set, minV, maxV)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y - 3)
    fs:SetText(label)
    local box = MenuNumberBox(parent, get, set, minV, maxV, 1)
    box:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    function box:Refresh() self:SetText(FormatNumber(get() or 0)) end
    RegisterControl(parent, box)
    return box
end

-- Bereichsliste links (grosse Menues): Eintraege 20 hoch im 22er-Raster, gewaehlter Eintrag gold
-- items = { { key = …, label = … } }; onSelect(key)
function UI.MenuSidebar(parent, x, y, items, onSelect, width)
    local list = CreateFrame("Frame", nil, parent)
    list:SetPoint("TOPLEFT", x, y)
    list:SetSize(width or UI.MENU.sidebarWidth, #items * 22)
    list.buttons = {}
    for i, item in ipairs(items) do
        local b = UI.MenuButton(list, item.label, width or UI.MENU.sidebarWidth, 20)
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        local fs = b:GetFontString()
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 10, 0)
        fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        b.key = item.key
        b:SetScript("OnClick", function() list:Select(item.key) end)
        local leave = b:GetScript("OnLeave")
        b:SetScript("OnLeave", function(self)
            leave(self)
            if list.selected == self.key then SetAccentBorder(self, true) end
        end)
        list.buttons[i] = b
    end
    function list:Select(key)
        self.selected = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            SetAccentBorder(b, on)
            b:GetFontString():SetTextColor(on and C.accent[1] or 1, on and C.accent[2] or 1, on and C.accent[3] or 1)
        end
        if onSelect then onSelect(key) end
    end
    return list
end

-- Form der Minimap hat sich geaendert (ForeverMinimap): alle Forever-Knoepfe am Rand neu setzen
function UI.RefreshMinimapButtons()
    for _, b in ipairs(SHARED.minimapButtons or {}) do
        if b.UpdatePosition then b.UpdatePosition() end
    end
end

-- Minimap-Knopf im gleichen Look fuer alle Forever-Addons
-- o = { name, icon, title, angle = function() -> Grad, setAngle = function(Grad),
--       onClick = function(button, mouseButton), lines = function() -> { "Linksklick: …", … },
--       texCoord = { l, r, t, b } (optional, z. B. Rand von Spielsymbolen abschneiden) }
function UI.MinimapButton(o)
    local b = CreateFrame("Button", o.name, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(o.icon)
    if o.texCoord then icon:SetTexCoord(unpack(o.texCoord)) end
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    -- rund: auf dem Kreis um die Minimap; eckig (GetMinimapShape() == "SQUARE", z. B. ForeverMinimap):
    -- an der Kante des Quadrats entlang
    function b.UpdatePosition()
        local angle = math.rad(o.angle() or 200)
        local radius = (Minimap:GetWidth() / 2) + 5
        local x, y = math.cos(angle), math.sin(angle)
        local shape = _G.GetMinimapShape and _G.GetMinimapShape()
        if shape == "SQUARE" then
            local m = math.max(math.abs(x), math.abs(y))
            x, y = x / m, y / m
        end
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
    end
    SHARED.minimapButtons = SHARED.minimapButtons or {}
    tinsert(SHARED.minimapButtons, b)

    local function OnDrag()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        o.setAngle(math.deg(math.atan2(py / scale - my, px / scale - mx)))
        b.UpdatePosition()
    end
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDrag) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", o.onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(o.title)
        for _, line in ipairs(o.lines and o.lines() or {}) do
            GameTooltip:AddLine(line, 1, 1, 1)
        end
        -- im Sammelknopf (Tooltip an der Listenzeile) laesst sich nichts ziehen
        if self == b then
            GameTooltip:AddLine(T("Ziehen: Knopf verschieben", "Drag: move button"), 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b.UpdatePosition()
    return b
end

-- Zahlenfeld mit –/+ fuer genaue Werte (z. B. X/Y-Position); Eingabe mit Enter bestaetigen.
-- get() liefert den Wert, set(v) speichert ihn. Rueckgabe hat :Load() zum Neu-Anzeigen.
function UI.Number(parent, x, y, label, get, set)
    local fs = UI.Text(parent, "label", label)
    fs:SetPoint("TOPLEFT", x, y - 4)
    local e = UI.EditBox(parent, 56, 20)
    e:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    e:SetJustifyH("CENTER")
    function e:Load()
        self:SetText(string.format("%g", get() or 0))
        self:SetCursorPosition(0)
    end
    local function Store(v)
        v = tonumber(v)
        if v and v ~= get() then set(v) end
        e:Load()
    end
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:Load() self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) Store(self:GetText()) end)
    local minus = UI.Button(parent, "–", 20, function() Store((get() or 0) - 1) end)
    minus:SetPoint("LEFT", e, "RIGHT", 4, 0)
    local plus = UI.Button(parent, "+", 20, function() Store((get() or 0) + 1) end)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    return e
end

---------------------------------------------------------------------------
-- Ausrichten: Raster, Einrasten, Hilfslinien – fuer alle verschiebbaren Forever-Rahmen.
-- Rahmen, die mit UI.AddMover angemeldet sind, rasten beim Ziehen aneinander ein
-- (auch ueber Addons hinweg, z. B. Zauberleiste an Spielerrahmen).
---------------------------------------------------------------------------
local SNAP = 8          -- ab diesem Abstand (px) rastet eine Kante ein
SHARED.movers = SHARED.movers or {}
SHARED.gridOwners = SHARED.gridOwners or {}
local movers = SHARED.movers
local grid, gridOwners = nil, SHARED.gridOwners

function UI.AddMover(frame, addon, opts)
    movers[#movers + 1] = frame
    if addon and UI.TagMover then UI.TagMover(frame, addon, opts) end
end

-- auf halbe Pixel runden (damit Kanten unterschiedlich breiter Rahmen genau buendig sind)
function UI.Round(v) return math.floor(v * 2 + 0.5) / 2 end

-- Mitte eines Rahmens relativ zur Bildschirmmitte
function UI.CenterOffset(frame)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return 0, 0 end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return UI.Round(cx * s - ux), UI.Round(cy * s - uy)
end

local function GridSize()
    local size
    for _, s in pairs(gridOwners) do size = math.min(size or s, s) end
    return size
end

local function DrawGrid()
    local size = GridSize()
    if not size then
        if grid then grid:Hide() end
        return
    end
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
        grid:RegisterEvent("DISPLAY_SIZE_CHANGED")
        grid:RegisterEvent("UI_SCALE_CHANGED")
        grid:SetScript("OnEvent", function() DrawGrid() end)
    end
    size = math.max(8, size)
    local w, h = UIParent:GetSize()
    local key = size .. ":" .. math.floor(w) .. ":" .. math.floor(h)
    if grid.key ~= key then -- nur neu zeichnen, wenn sich Abstand oder Bildschirm aendert
        grid.key = key
        for _, t in ipairs(grid.lines) do t:Hide() end
        local n = 0
        local function Line(vertical, offset)
            n = n + 1
            local t = grid.lines[n]
            if not t then
                t = grid:CreateTexture(nil, "BACKGROUND")
                grid.lines[n] = t
            end
            t:ClearAllPoints()
            if offset == 0 then t:SetColorTexture(1, 0.25, 0.25, 0.7) else t:SetColorTexture(0, 0, 0, 0.45) end
            if vertical then
                t:SetPoint("TOP", grid, "TOP", offset, 0)
                t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
                t:SetWidth(1)
            else
                t:SetPoint("LEFT", grid, "LEFT", 0, offset)
                t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
                t:SetHeight(1)
            end
            t:Show()
        end
        for i = 0, math.floor(w / 2 / size) do
            Line(true, i * size)
            if i > 0 then Line(true, -i * size) end
        end
        for i = 0, math.floor(h / 2 / size) do
            Line(false, i * size)
            if i > 0 then Line(false, -i * size) end
        end
    end
    grid:Show()
end

-- Raster anfordern (size) oder abmelden (nil). Sichtbar, solange irgendein Addon es will.
function UI.Grid(owner, size)
    gridOwners[owner] = size
    DrawGrid()
end

-- gelbe Hilfslinien beim Ziehen: zeigen, an welcher Kante gerade eingerastet wird
local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints(UIParent)
guides:SetFrameStrata("HIGH")
guides:Hide()
local guideV = guides:CreateTexture(nil, "OVERLAY")
guideV:SetColorTexture(1, 0.82, 0, 0.9)
guideV:SetWidth(1)
local guideH = guides:CreateTexture(nil, "OVERLAY")
guideH:SetColorTexture(1, 0.82, 0, 0.9)
guideH:SetHeight(1)

-- linke Kante, Mitte, rechte Kante (bzw. unten, Mitte, oben), relativ zur Bildschirmmitte
local function Edges(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local ux, uy = UIParent:GetCenter()
    if not (l and r and t and b and ux) then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l, r, t, b = l * s, r * s, t * s, b * s
    return { l - ux, (l + r) / 2 - ux, r - ux }, { b - uy, (t + b) / 2 - uy, t - uy }
end

-- kleinster Versatz, mit dem eine eigene Kante auf einer Ziel-Linie liegt (nur innerhalb SNAP)
local function Best(mine, targets)
    local best, line
    for _, m in ipairs(mine) do
        for _, t in ipairs(targets) do
            local diff = t - m
            if math.abs(diff) <= SNAP and (not best or math.abs(diff) < math.abs(best)) then
                best, line = diff, t
            end
        end
    end
    return best, line
end

-- Versatz zum Einrasten: zuerst an anderen Rahmen und der Bildschirmmitte, sonst am Raster.
-- Umschalt gedrueckt = nicht einrasten.
local drag -- { frame, edges, snap, grid }
-- Einrasten gilt fuer alle Forever-Rahmen gemeinsam: ForeverHubDB.noSnap schaltet es aus (Hub-Fenster, /fmove snap)
local function SnapDB()
    if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
    return _G.ForeverHubDB
end
function UI.SnapEnabled() return not SnapDB().noSnap end
function UI.SetSnapEnabled(on) SnapDB().noSnap = (not on) or nil end

local function SnapOffset()
    if not drag or not drag.snap or IsShiftKeyDown() or SnapDB().noSnap then return 0, 0 end
    local mx, my = Edges(drag.edges)
    if not mx then return 0, 0 end
    local tx, ty = { 0 }, { 0 } -- Bildschirmmitte
    for _, o in ipairs(movers) do
        if o ~= drag.frame and o ~= drag.edges and o:IsVisible() then
            local ox, oy = Edges(o)
            if ox then
                for _, v in ipairs(ox) do tx[#tx + 1] = v end
                for _, v in ipairs(oy) do ty[#ty + 1] = v end
            end
        end
    end
    local dx, lx = Best(mx, tx)
    local dy, ly = Best(my, ty)
    if drag.grid then
        local size = math.max(8, drag.grid)
        local function Nearest(list)
            local g = {}
            for _, v in ipairs(list) do g[#g + 1] = math.floor(v / size + 0.5) * size end
            return g
        end
        if not dx then dx = Best(mx, Nearest(mx)) end -- Raster: ohne Hilfslinie
        if not dy then dy = Best(my, Nearest(my)) end
    end
    return dx or 0, dy or 0, lx, ly
end

guides:SetScript("OnUpdate", function()
    local _, _, lx, ly = SnapOffset()
    guideV:ClearAllPoints()
    guideH:ClearAllPoints()
    if lx then
        guideV:SetPoint("TOP", guides, "TOP", lx, 0)
        guideV:SetPoint("BOTTOM", guides, "BOTTOM", lx, 0)
    end
    if ly then
        guideH:SetPoint("LEFT", guides, "LEFT", 0, ly)
        guideH:SetPoint("RIGHT", guides, "RIGHT", 0, ly)
    end
    guideV:SetShown(lx and true or false)
    guideH:SetShown(ly and true or false)
end)

-- Fuer Rahmen, die beim Ziehen selbst nachgefuehrt werden (z. B. ForeverBars): Versatz (dx, dy), um den der gerade
-- gezogene Rahmen an andere Rahmen, die Bildschirmmitte oder das Raster einrasten wuerde (Umschalt/Schalter aus = 0, 0)
function UI.SnapOffset()
    local dx, dy = SnapOffset()
    return dx, dy
end

-- Ziehen beginnt. o = { snap = true/false, grid = Rasterabstand oder nil,
-- edges = sichtbarer Teil, dessen Kanten zaehlen (Standard: der gezogene Rahmen) }
function UI.BeginDrag(frame, o)
    o = o or {}
    drag = { frame = frame, edges = o.edges or frame, snap = o.snap ~= false, grid = o.grid }
    guides:Show()
end

-- Ziehen beendet: Versatz (dx, dy) zurueckgeben, um den der Rahmen noch einrasten soll
function UI.EndDrag()
    local dx, dy = SnapOffset()
    drag = nil
    guides:Hide()
    return dx, dy
end

---------------------------------------------------------------------------
-- Verschiebe-Modus fuer alle: /fmove (oder Knopf im Sammelmenue) entsperrt alle aktiven
-- Forever-Addons auf einmal – nochmal sperrt alle wieder. Jedes Addon meldet sich an mit
-- UI.RegisterMovable(name, isLocked(), setLocked(locked)).
---------------------------------------------------------------------------
SHARED.movables = SHARED.movables or {}
SHARED.movableOrder = SHARED.movableOrder or {}
local movables, movableOrder = SHARED.movables, SHARED.movableOrder

function UI.RegisterMovable(name, isLocked, setLocked)
    if not movables[name] then movableOrder[#movableOrder + 1] = name end
    -- Entsperren über den Hub weckt die gelben Rahmen der Fenster (UI.WakeMoverOutlines, siehe unten)
    movables[name] = { isLocked = isLocked, setLocked = function(lock, ...)
        setLocked(lock, ...)
        if not lock and UI.WakeMoverOutlines then UI.WakeMoverOutlines() end
    end }
end

-- Ist irgendein angemeldetes Addon gerade entsperrt?
function UI.AnyUnlocked()
    for _, name in ipairs(movableOrder) do
        local ok, locked = pcall(movables[name].isLocked)
        if ok and not locked then return true end
    end
    return false
end

-- Entsperrte Fenster (v72): jedes mit UI.AddMover(frame, "Addonname") angemeldete Fenster bekommt, solange sein Addon
-- entsperrt ist (bzw. bei Addons ohne eigenen Schalter: solange irgendetwas entsperrt ist), einen gelben Rahmen wie die
-- entsperrten Aktionsleisten; Rechtsklick darauf öffnet die Einstellungen des Addons. opts.noRightClick = das Fenster
-- hat schon einen eigenen Rechtsklick (nur der Rahmen kommt vom Hub).
SHARED.tagged = SHARED.tagged or setmetatable({}, { __mode = "k" })
local tagged = SHARED.tagged
local outlines = setmetatable({}, { __mode = "k" })
local MOVER_GOLD = { 1, 0.82, 0 }

local function AddonUnlocked(addon)
    local m = movables[addon]
    if m then
        local ok, locked = pcall(m.isLocked)
        return ok and not locked
    end
    return UI.AnyUnlocked()
end

-- Hinweis beim Darüberfahren über entsperrte Fenster (wie bei den Aktionsleisten): was Maustasten hier tun
function UI.ShowMoverTip(owner, title, noRightClick)
    local tip = UI.GetTooltip and UI.GetTooltip() or GameTooltip
    tip:SetOwner(owner, "ANCHOR_TOP")
    tip:AddLine(title, 1, 0.82, 0)
    tip:AddLine(T("Linke Maustaste halten: verschieben (Umschalt = nicht einrasten)", "Hold left mouse button: move (Shift = no snapping)"), 1, 1, 1, true)
    tip:AddLine(T("Rechtsklick: Einstellungen dieses Addons", "Right-click: settings for this addon"), 1, 1, 1, true)
    tip:Show()
end
function UI.HideMoverTip(owner)
    local tip = UI.GetTooltip and UI.GetTooltip() or GameTooltip
    if not owner or tip:GetOwner() == owner then tip:Hide() end
end

function UI.TagMover(frame, addon, opts)
    if not frame or not addon then return end
    local t = tagged[frame]
    if t then t.addon = addon return end
    t = { addon = addon }
    tagged[frame] = t
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnEnter", function(self) if AddonUnlocked(t.addon) then UI.ShowMoverTip(self, t.addon) end end)
        pcall(frame.HookScript, frame, "OnLeave", function(self) UI.HideMoverTip(self) end)
    end
    if not (opts and opts.noRightClick) and frame.HookScript then
        pcall(frame.HookScript, frame, "OnMouseUp", function(self, button)
            if button ~= "RightButton" or InCombatLockdown() or not self:IsVisible() then return end
            if AddonUnlocked(t.addon) then UI.OpenSettings(t.addon) end
        end)
    end
end

local function Outline(frame, addon)
    local o = outlines[frame]
    if o then return o end
    o = CreateFrame("Frame", nil, UIParent)
    o:SetFrameStrata("FULLSCREEN")
    o:EnableMouse(false) -- Ziehen und Klicken gehen durch zum Fenster darunter
    o:SetAllPoints(frame)
    local fill = o:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(MOVER_GOLD[1], MOVER_GOLD[2], MOVER_GOLD[3], 0.10)
    local function Edge(p1, p2, w, h)
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(MOVER_GOLD[1], MOVER_GOLD[2], MOVER_GOLD[3], 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 2)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    Edge("TOPLEFT", "BOTTOMLEFT", 2, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 2, nil)
    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    o.label:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 1, 2)
    o.label:SetTextColor(MOVER_GOLD[1], MOVER_GOLD[2], MOVER_GOLD[3])
    o.label:SetText(addon)
    outlines[frame] = o
    return o
end

do -- (eigener Block: hält die Zahl der lokalen Variablen auf oberster Ebene klein)
    local function UpdateOutlines()
        if _G.ForeverHub ~= hub then return end
        for frame, t in pairs(tagged) do
            local show = frame:IsVisible() and AddonUnlocked(t.addon)
            local o = outlines[frame]
            if show then
                Outline(frame, t.addon):Show()
            elseif o then
                o:Hide()
            end
        end
    end

    -- Rahmen nachführen (v73): schnell (0,3 s) nur, solange etwas entsperrt ist – danach hält der Zeitgeber an. Gestartet
    -- beim Entsperren über den Hub (UI.MoveAll, angemeldete Sperr-Schalter); entsperrt sich ein Addon an seinem eigenen
    -- Schalter vorbei, merkt es die langsame Rückfall-Prüfung (alle 2 s, nur "ist irgendetwas entsperrt?").
    local outlineTicker
    local function StartOutlines()
        if outlineTicker or _G.ForeverHub ~= hub then return end
        UpdateOutlines()
        outlineTicker = C_Timer.NewTicker(0.3, function()
            UpdateOutlines()
            if not UI.AnyUnlocked() and outlineTicker then
                outlineTicker:Cancel()
                outlineTicker = nil
            end
        end)
    end
    UI.WakeMoverOutlines = StartOutlines
    C_Timer.NewTicker(2, function()
        if outlineTicker or _G.ForeverHub ~= hub or not next(tagged) then return end
        if UI.AnyUnlocked() then StartOutlines() end
    end)
end

-- Raster, solange der gemeinsame Verschiebe-Modus laeuft; endet von selbst, wenn alles gesperrt ist
local moveTicker
local function StopMoveGrid()
    UI.Grid("ForeverHub", nil)
    if moveTicker then moveTicker:Cancel() moveTicker = nil end
end

-- lock = true/false; nil = umschalten (ist etwas entsperrt -> alles sperren, sonst alles entsperren)
function UI.MoveAll(lock, force)
    if InCombatLockdown() and not force then
        UI.Chat("Forever", T("Im Kampf nicht möglich.", "Not possible in combat."))
        return
    end
    if #movableOrder == 0 then
        UI.Chat("Forever", T("Kein verschiebbares Forever-Addon aktiv.", "No movable Forever addon active."))
        return
    end
    if lock == nil then lock = UI.AnyUnlocked() end
    local names = {}
    for _, name in ipairs(movableOrder) do
        local ok, err = pcall(movables[name].setLocked, lock)
        if ok then
            names[#names + 1] = name
        else
            local handler = geterrorhandler and geterrorhandler()
            if handler then pcall(handler, err) end
        end
    end
    if lock then
        StopMoveGrid()
        UI.Chat("Forever", T("Alle Rahmen gesperrt.", "All frames locked."))
    else
        UI.Grid("ForeverHub", 32)
        if not moveTicker then
            moveTicker = C_Timer.NewTicker(1, function()
                if not UI.AnyUnlocked() then StopMoveGrid() end
            end)
        end
        UI.Chat("Forever", string.format(T("Entsperrt: %s – ziehen zum Verschieben, /fmove sperrt wieder.",
            "Unlocked: %s – drag to move, /fmove locks again."), table.concat(names, ", ")))
    end
end

-- Schnelltastenbelegung (Blizzards Modus "Tasten per Maus belegen") beendet den Verschiebe-Modus (v64): entsperrte
-- Rahmen fangen sonst die Maus ab, und beim Belegen würde man aus Versehen Rahmen verschieben. Gilt für jeden Weg in
-- den Modus (ForeverBars, Blizzards Menü, Befehl).
do
    local function EndMoveForKeybind()
        if _G.ForeverHub ~= hub or InCombatLockdown() or not UI.AnyUnlocked() then return end
        UI.MoveAll(true)
        UI.Chat("Forever", T("Schnelltastenbelegung: Verschieben beendet.", "Quick keybind mode: moving ended."))
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        local owner = {}
        pcall(EventRegistry.RegisterCallback, EventRegistry, "QuickKeybindFrame.QuickKeybindModeEnabled",
            function() pcall(EndMoveForKeybind) end, owner)
    end
    -- (Rückfall, falls der Modus ohne diese Meldung aufgeht)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        local qk = _G.QuickKeybindFrame
        if qk and qk.HookScript then qk:HookScript("OnShow", function() pcall(EndMoveForKeybind) end) end
    end)
end

-- Kampfbeginn: Verschiebe-Modus beenden (alles sperren) und das Einstellungsfenster schließen, damit nichts im Weg ist
-- und keine entsperrten Rahmen Klicks abfangen. Die Addons sperren nur ihre eigenen Schalter (pcall je Addon).
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function()
        if _G.ForeverHub ~= hub then return end
        local was = UI.AnyUnlocked()
        if was then pcall(UI.MoveAll, true, true) end
        UI.CloseSettings()
        if was then UI.Chat("Forever", T("Kampf: Verschieben beendet, Fenster geschlossen.", "Combat: move mode ended, windows closed.")) end
    end)
end

SLASH_FOREVERMOVE1 = "/fmove"
SlashCmdList["FOREVERMOVE"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" then UI.MoveAll(true)
    elseif msg == "unlock" then UI.MoveAll(false)
    elseif msg == "snap" then
        UI.SetSnapEnabled(not UI.SnapEnabled())
        UI.Chat("Forever", UI.SnapEnabled() and T("Einrasten beim Verschieben: an (Umschalt = kurz aus).", "Snapping while moving: on (Shift = off for one move).")
            or T("Einrasten beim Verschieben: aus.", "Snapping while moving: off."))
    else UI.MoveAll() end
end

---------------------------------------------------------------------------
-- 2. Sammelknopf
---------------------------------------------------------------------------
-- Bekannte Forever-Addons und der Name ihres Minimap-Knopfs (Reihenfolge = Reihenfolge in Liste und Hub-Fenster).
-- Neues Addon: hier eintragen; sein Minimap-Knopf muss so heissen und mit Linksklick das Menue oeffnen.
-- cmd = Chatbefehl (Anzeige im Blizzard-Optionsmenue)
local KNOWN = {
    { name = "ForeverFrames", button = "ForeverFramesMinimapButton", cmd = "/ff" },
    { name = "ForeverUnits",  button = "ForeverUnitsMinimapButton", cmd = "/fu" },
    { name = "ForeverCast",   button = "ForeverCastMinimapButton", cmd = "/fcast" },
    { name = "ForeverBars",   button = "ForeverBarsMinimapButton", cmd = "/fb" },
    { name = "ForeverQuests", button = "ForeverQuestsMinimapButton", cmd = "/fq" },
    { name = "ForeverChat",   button = "ForeverChatMinimapButton", cmd = "/fchat" },
    { name = "ForeverMinimap", button = "ForeverMinimapMinimapButton", cmd = "/fmm" },
    -- ForeverLoot, ForeverBuffs und ForeverVendor sind seit 0.44b+ Module von ForeverHelpers
    { name = "ForeverHelpers", button = "ForeverHelpersMinimapButton", cmd = "/fhelp" },
    { name = "ForeverSpellbook", button = "ForeverSpellbookMinimapButton", cmd = "/fsb" },
    { name = "ForeverBags",   button = "ForeverBagsMinimapButton", cmd = "/fbags" },
    { name = "ForeverTooltip", button = "ForeverTooltipMinimapButton", cmd = "/ftip" },
    { name = "ForeverPlates", button = "ForeverPlatesMinimapButton", cmd = "/fplates" },
    -- ownButton: eigener Knopf bleibt neben dem Forever-Core-UI-Knopf sichtbar (in ForeverMinimaps Knopfleiste gleich
    -- darunter) – die Twink-Übersicht ist ein Fenster zum schnellen Nachsehen, keine Einstellung (v58)
    { name = "ForeverAlts",   button = "ForeverAltsMinimapButton", cmd = "/falts", ownButton = true },
    { name = "ForeverQuestmob", button = "ForeverQuestmobMinimapButton" },
    { name = "ForeverBoard",  button = "ForeverBoardMinimapButton" },
    { name = "ForeverNotes",  button = "ForeverNotesMinimapButton" },
}
-- Hauptaddon (nur der Hub, kein eigenes Menue): steht nicht in der Liste, haelt aber Hub, Optionsmenue
-- und Addon-Menue-Eintrag am Leben, auch wenn alle anderen Forever-Addons ausgeschaltet sind
local CORE = "ForeverCore"
local function CoreLoaded() return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(CORE) end

-- Bearbeitungsmodus-Anker ausgeschalteter Addons: Blizzard speichert im Layout Anker an Addon-Rahmen
-- (z. B. "MainStatusTrackingBarContainer an ForeverBars_xp"). Ist das Addon aus, fehlt der Rahmen ->
-- LUA_WARNING "Couldn't find region named …" und die Leiste verliert ihren Platz. Dann springt ein
-- unsichtbarer Platzhalter gleichen Namens an Blizzards Standardstelle ein (Mitte der Leiste = Mitte des
-- Platzhalters, wie beim Halter). Verschiebt man die Leiste danach im Bearbeitungsmodus, speichert Blizzard
-- einen neuen Anker und der Platzhalter wird nicht mehr gebraucht.
-- Muss beim Laden der Datei passieren (vor EDIT_MODE_LAYOUTS_UPDATED). Neues Addon mit solchen Halter-Rahmen: hier eintragen.
local EDITMODE_ANCHORS = {
    { addon = "ForeverBars", name = "ForeverBars_xp",    point = "BOTTOM",      x = 0,    y = 7 },
    { addon = "ForeverBars", name = "ForeverBars_rep",   point = "BOTTOM",      x = 0,    y = 21 },
    { addon = "ForeverBars", name = "ForeverBars_micro", point = "BOTTOMRIGHT", x = -170, y = 20 },
    { addon = "ForeverBars", name = "ForeverBars_bags",  point = "BOTTOMRIGHT", x = -110, y = 60 },
}

-- Charakter für Blizzards Addon-Verwaltung: der Name (wie in Blizzards Addon-Liste, BugGrabber, AtlasLoot) – NICHT
-- die GUID; mit der GUID las das Spiel den falschen Zustand und ordnete An/Aus keinem Charakter zu (v62)
local function AddonChar()
    return (UnitNameUnmodified and UnitNameUnmodified("player")) or UnitName("player")
end

local function WillLoad(addon)
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return true end
    if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) then return true end
    local ok, _, _, _, loadable, reason = pcall(C_AddOns.GetAddOnInfo, addon)
    if ok and reason == "MISSING" then return false end
    local char = AddonChar()
    local okState, state = pcall(C_AddOns.GetAddOnEnableState, addon, char)
    if okState and type(state) == "number" then return state > 0 end
    return not ok or loadable ~= false
end

for _, a in ipairs(EDITMODE_ANCHORS) do
    if not _G[a.name] and not WillLoad(a.addon) then
        local stand = CreateFrame("Frame", a.name, UIParent)
        stand:SetSize(1, 1)
        stand:SetPoint(a.point, UIParent, a.point, a.x, a.y)
    end
end

-- Einstellungen (in jedem Forever-Addon als SavedVariable "ForeverHubDB" eingetragen)
local function GetDB()
    if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
    local db = _G.ForeverHubDB
    if db.angle == nil then db.angle = 195 end
    db.collect = nil -- alte Einstellung (Einzelknoepfe) gibt es nicht mehr
    return db
end

local entries = {}      -- gefundene Addons: { name, button, icon }
local hubButton
local active = false    -- true: Sammelknopf aktiv, Einzelknoepfe versteckt

-- Logo aus der .toc (## IconTexture) – gibt es auch für ausgeschaltete Addons und Addons ohne Minimap-Knopf (v65)
local function TocIcon(name)
    local ok, tex = pcall(C_AddOns.GetAddOnMetadata, name, "IconTexture")
    if ok and type(tex) == "string" and tex ~= "" then return tex end
end

local function IconOf(button)
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetDrawLayer and region:GetDrawLayer() == "ARTWORK" and region.GetTexture then
            local tex = region:GetTexture()
            if tex then return tex end
        end
    end
    return 134400 -- Fragezeichen
end

local function BuildHubButton()
    hubButton = UI.MinimapButton({
        name = "ForeverHubMinimapButton",
        icon = UI.LOGO,
        title = UI.NAME,
        angle = function() return GetDB().angle end,
        setAngle = function(a) GetDB().angle = a end,
        -- Linksklick: das gemeinsame Einstellungsfenster (alle Addons als Seiten), Umschalt: Hub-Übersicht
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                UI.MoveAll()
            elseif IsShiftKeyDown() then
                hub.ToggleWindow()
            elseif _G.ForeverSettingsWindow and _G.ForeverSettingsWindow:IsShown() then
                UI.CloseSettings()
            else
                UI.OpenSettings()
            end
        end,
        lines = function()
            return { T("Linksklick: Einstellungen aller Forever-Addons", "Left-click: settings of all Forever addons"),
                T("Umschalt+Linksklick: Übersicht (/forever)", "Shift-left-click: overview (/forever)"),
                T("Rechtsklick: alle Rahmen verschieben/sperren (/fmove)", "Right-click: move/lock all frames (/fmove)") }
        end,
    })
end

-- Ein Knopf für alles: sobald ein Forever-Addon da ist, bleiben dessen eigene Minimap-Knöpfe versteckt
-- (v53; vorher erst ab zwei Addons, mit ausklappbarer Liste).
-- "Minimap-Knopf ausblenden" (im Hub-Fenster) versteckt alle Forever-Knoepfe; Zugang dann ueber /forever.
local function ApplyMode()
    active = #entries >= 1
    local hidden = GetDB().hideButton
    if active and not hubButton then BuildHubButton() end
    if hubButton then hubButton:SetShown(active and not hidden) end
    for _, e in ipairs(entries) do
        e.button:SetShown((e.ownButton or not active) and not hidden)
    end
end

local RegisterSettings -- Eintrag im Blizzard-Optionsmenue (Abschnitt 4), wird weiter unten belegt
local RegisterCompartment -- Eintrag im Addon-Menue an der Minimap (Abschnitt 5)

local function Setup()
    if _G.ForeverHub ~= hub then return end -- eine neuere Kopie ist zustaendig
    local before = #entries
    wipe(entries)
    for _, k in ipairs(KNOWN) do
        local button = _G[k.button]
        if button then
            entries[#entries + 1] = { name = k.name, button = button, icon = IconOf(button), cmd = k.cmd, ownButton = k.ownButton }
            -- falls ein Addon seinen Knopf spaeter wieder einblendet: im Sammelmodus versteckt lassen
            -- (ausser Knoepfen, die sichtbar bleiben sollen – dann nur, wenn alle Forever-Knoepfe aus sind)
            if not button.ffHubHooked then
                button.ffHubHooked = true
                button.ffOwnButton = k.ownButton
                button:HookScript("OnShow", function(self)
                    local h = _G.ForeverHub
                    if self.ffOwnButton then
                        if GetDB().hideButton then self:Hide() end
                    elseif h and h.IsCollecting and h.IsCollecting() then
                        self:Hide()
                    end
                end)
            end
        end
    end
    -- Liste neu bauen, falls inzwischen weitere Addons dazugekommen sind
    ApplyMode()
    if RegisterSettings then RegisterSettings() end
    if RegisterCompartment then RegisterCompartment() end
end

-- true: Einzelknoepfe sollen versteckt bleiben (gesammelt oder ganz ausgeblendet)
function hub.IsCollecting() return active or GetDB().hideButton == true end

local function SafeSetup()
    local ok, err = pcall(Setup)
    if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then pcall(handler, err) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
    -- kurz warten, damit alle Addons ihre Knoepfe angelegt haben; spaeter nochmal nachsehen,
    -- falls ein Addon seinen Knopf erst verzoegert baut
    C_Timer.After(0.5, SafeSetup)
    C_Timer.After(3, SafeSetup)
end)

---------------------------------------------------------------------------
-- 3. Hub-Fenster: alle Forever-Addons auf einen Blick – ein-/ausschalten und ins Menue springen
---------------------------------------------------------------------------
local HUB_ROW_H = 34
local HUB_INTRO_H = 46
local hubWindow

-- Addon installiert? (auch wenn es gerade deaktiviert ist)
local function IsInstalled(name)
    if not (C_AddOns and C_AddOns.GetAddOnInfo) then return false end
    local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, name)
    return ok and reason ~= "MISSING"
end

local function EntryOf(name)
    for _, e in ipairs(entries) do
        if e.name == name then return e end
    end
end

-- Menue eines Addons oeffnen = Linksklick auf seinen (evtl. versteckten) Minimap-Knopf
local function OpenAddon(e)
    local onClick = e and e.button:GetScript("OnClick")
    if onClick then onClick(e.button, "LeftButton") end
end

-- Ein- und Ausschalten ueber Blizzards Addon-Verwaltung (wie die Addon-Liste) – wirkt nach dem Neuladen.
-- Standard: fuer alle Charaktere; Einstellung "nur dieser Charakter" (ForeverHubDB.perCharacter).
-- Gelesen wird immer der Stand des aktuellen Charakters (der zaehlt beim naechsten Laden).
local function IsLoaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

local function IsEnabled(name)
    if not (C_AddOns and C_AddOns.GetAddOnEnableState) then return IsLoaded(name) end
    local ok, state = pcall(C_AddOns.GetAddOnEnableState, name, AddonChar())
    if not ok or type(state) ~= "number" then return IsLoaded(name) end
    return state > 0
end

local function SetEnabled(name, on)
    if not C_AddOns then return end
    local fn = on and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn
    if not fn then return end
    -- "nur dieser Charakter": nur für ihn; sonst für alle – und zusätzlich für diesen Charakter, falls er in Blizzards
    -- Addon-Liste eine eigene Einstellung hat (die ginge sonst vor)
    if GetDB().perCharacter then
        pcall(fn, name, AddonChar())
    else
        pcall(fn, name)
        pcall(fn, name, AddonChar())
    end
    -- sofort speichern (sonst verwirft Blizzards Addon-Liste die Aenderung beim naechsten Schliessen)
    if C_AddOns.SaveAddOns then pcall(C_AddOns.SaveAddOns) end
end

-- geaendert, aber noch nicht neu geladen?
local function IsPending(name) return IsLoaded(name) ~= IsEnabled(name) end

-- für den Einrichtungsassistenten (Setup.lua): installierte Forever-Addons und An/Aus wie im Hub-Fenster
hub.setup = {
    Addons = function()
        local list = {}
        for _, k in ipairs(KNOWN) do
            if IsInstalled(k.name) then list[#list + 1] = { name = k.name, icon = TocIcon(k.name) } end
        end
        return list
    end,
    IsEnabled = IsEnabled, SetEnabled = SetEnabled, IsPending = IsPending, GetDB = GetDB,
    ApplyMode = function() ApplyMode() end,
}

local function BuildHubWindow()
    local list, cmdOf = {}, {}
    for _, k in ipairs(KNOWN) do
        if IsInstalled(k.name) then
            list[#list + 1] = k.name
            cmdOf[k.name] = k.cmd
        end
    end

    -- Aufbau (v57): oben die Addons als Kacheln in zwei Spalten – Klick auf die Kachel schaltet das Addon an/aus
    -- (gilt nach dem Neuladen; "Öffnen" gibt es nicht mehr, dafür steht jedes Addon links in der Liste). Darunter
    -- zwei Kästen: "Allgemein" (Sprache, Spielernamen, Einrasten, Minimap-Knopf) und "Werkzeuge".
    local W = 700
    local COLS, TILE_H, TILE_GAP = 2, 40, 6
    local tileW = math.floor((W - 24 - TILE_GAP) / COLS)
    local rowsN = math.max(1, math.ceil(#list / COLS))
    local listTop = 26 + HUB_INTRO_H + 24                 -- unter Einleitung und Überschrift "Addons"
    local tilesEnd = listTop + rowsN * (TILE_H + TILE_GAP)
    local generalY = tilesEnd + 56                        -- Überschrift "Allgemein"
    local toolsY = generalY + 132                         -- Überschrift "Werkzeuge" (mind. ~24 px Luft zum Kasten davor)
    local H = toolsY + 96
    local f = UI.SettingsPanel("ForeverHubWindow", UI.NAME, W, H,
        { key = "ForeverCore", group = UI.SETTINGS_GROUPS.core, label = T("Übersicht", "Overview") })
    hubWindow = f
    f.rows = {}

    local intro = UI.Hint(f, 16, -34, W - 32, "")
    intro:SetWordWrap(true)

    local reload -- Knopf "Neu laden", erscheint, sobald etwas erst nach dem Neuladen gilt
    local langChanged = false
    local function Refresh()
        local pending = langChanged
        for _, row in ipairs(f.rows) do
            row.Update()
            if IsPending(row.name) then pending = true end
        end
        if reload then reload:SetShown(pending) end
    end
    f.Refresh = Refresh

    ---------------------------------------------------------------------------
    -- Addons
    ---------------------------------------------------------------------------
    UI.Header(f, 16, -(listTop - 22), T("Addons", "Addons"), W - 24)
    for i, name in ipairs(list) do
        local col, rowIndex = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local tile = CreateFrame("Button", nil, f)
        tile.name = name
        tile:SetSize(tileW, TILE_H)
        tile:SetPoint("TOPLEFT", 12 + col * (tileW + TILE_GAP), -(listTop + rowIndex * (TILE_H + TILE_GAP)))
        local hl = tile:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)

        -- Häkchen = Addon aktiv; Klick irgendwo auf die Kachel schaltet um
        tile.check = UI.Check(tile, nil, nil, "", function(checked)
            SetEnabled(name, checked)
            Refresh()
        end)
        tile.check:SetPoint("LEFT", 8, 0)
        tile:SetScript("OnClick", function()
            SetEnabled(name, not IsEnabled(name))
            Refresh()
        end)
        tile.icon = tile:CreateTexture(nil, "ARTWORK")
        tile.icon:SetSize(24, 24)
        tile.icon:SetPoint("LEFT", 32, 0)
        tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tile.label:SetPoint("TOPLEFT", tile.icon, "TOPRIGHT", 8, 2)
        tile.label:SetText(name)
        if cmdOf[name] then
            tile.cmd = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tile.cmd:SetPoint("LEFT", tile.label, "RIGHT", 6, 0)
            tile.cmd:SetTextColor(0.55, 0.55, 0.55)
            tile.cmd:SetText(cmdOf[name])
        end
        tile.note = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tile.note:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -2)
        tile.note:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
        tile.note:SetJustifyH("LEFT")
        tile.note:SetWordWrap(false)
        local ok, _, _, notes = pcall(C_AddOns.GetAddOnInfo, name)
        tile.notes = ok and notes or ""
        tile.note:SetText(tile.notes)
        -- statt der Beschreibung: "an/aus nach Neuladen", solange die Änderung noch nicht gilt
        tile.status = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tile.status:SetPoint("TOPLEFT", tile.label, "BOTTOMLEFT", 0, -2)
        tile:SetScript("OnEnter", function(self)
            local tip = UI.GetTooltip()
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:AddLine(name, C.accent[1], C.accent[2], C.accent[3])
            if self.notes ~= "" then tip:AddLine(self.notes, 1, 1, 1, true) end
            tip:AddLine(T("Klick: an/aus – gilt nach dem Neuladen.", "Click: on/off – applies after reloading."), 0.6, 0.6, 0.6)
            tip:Show()
        end)
        tile:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)

        function tile.Update()
            local e = EntryOf(name)
            local enabled = IsEnabled(name)
            local pending = IsPending(name)
            tile.check:SetChecked(enabled)
            tile.icon:SetTexture(TocIcon(name) or e and e.icon or UI.LOGO)
            tile.icon:SetDesaturated(not enabled)
            tile.label:SetTextColor(enabled and C.accent[1] or 0.5, enabled and C.accent[2] or 0.5, enabled and C.accent[3] or 0.5)
            tile.note:SetShown(not pending)
            tile.status:SetShown(pending)
            if pending then
                tile.status:SetText(enabled and T("an nach dem Neuladen", "on after reloading")
                    or T("aus nach dem Neuladen", "off after reloading"))
            end
        end
        f.rows[i] = tile
    end
    if #list == 0 then
        UI.Hint(f, 16, -listTop, nil, T("Keine Forever-Addons gefunden.", "No Forever addons found."))
    end

    -- unter den Kacheln: alle an/aus, nur dieser Charakter, Neu laden
    local function SetAll(on)
        for _, name in ipairs(list) do SetEnabled(name, on) end
        Refresh()
        if not on and not IsInstalled(CORE) then
            UI.Chat("Forever", T("Ohne Forever-Addons gibt es auch kein Hub-Fenster mehr – wieder einschalten dann über die Addon-Liste (Charakterauswahl).",
                "Without Forever addons there is no hub window either – turn them back on via the addon list (character selection)."))
        end
    end
    local allOn = UI.Button(f, T("Alle an", "All on"), 90, function() SetAll(true) end)
    allOn:SetPoint("TOPLEFT", 16, -(tilesEnd + 4))
    local allOff = UI.Button(f, T("Alle aus", "All off"), 90, function() SetAll(false) end)
    allOff:SetPoint("LEFT", allOn, "RIGHT", 6, 0)
    local perChar = UI.Check(f, nil, nil, T("nur dieser Charakter", "this character only"), function(checked)
        GetDB().perCharacter = checked or nil
    end)
    perChar:SetPoint("LEFT", allOff, "RIGHT", 16, 0)
    reload = UI.Button(f, T("Neu laden", "Reload"), 110, function() ReloadUI() end)
    reload:SetPoint("TOPRIGHT", -16, -(tilesEnd + 4))
    reload:GetFontString():SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    reload:Hide()

    ---------------------------------------------------------------------------
    -- Allgemein: Sprache, Spielernamen, Einrasten, Minimap-Knopf
    ---------------------------------------------------------------------------
    UI.Header(f, 16, -generalY, T("Allgemein", "General"), W - 24)
    local lang
    if UI.GERMAN_CLIENT then
        local LANGS = {
            { key = "AUTO", label = T("Automatisch (Client)", "Automatic (client)") },
            { key = "deDE", label = "Deutsch" },
            { key = "enUS", label = "English" },
        }
        local function Current() return GetDB().language or "AUTO" end
        local function LabelOf(key)
            for _, l in ipairs(LANGS) do if l.key == key then return l.label end end
            return key
        end
        local langLabel = UI.Text(f, "label", T("Sprache", "Language"))
        langLabel:SetPoint("TOPLEFT", 20, -(generalY + 26))
        lang = UI.AddArrow(UI.Button(f, "", 180))
        lang:SetPoint("TOPLEFT", 110, -(generalY + 22))
        lang:SetScript("OnClick", function(self)
            UI.ChoiceMenu(self, LANGS, Current, function(key)
                GetDB().language = key ~= "AUTO" and key or nil
                self:SetText(LabelOf(Current()))
                langChanged = true
                Refresh()
                UI.Chat("Forever", T("Die Sprache gilt nach dem Neuladen für alle Forever-Addons.",
                    "The language applies to all Forever addons after reloading."))
            end)
        end)
        function lang.Load() lang:SetText(LabelOf(Current())) end
    end

    local NAME_CHOICES = {
        { key = "first", label = T("Nur Vorname", "First name only") },
        { key = "initial", label = T("Vorname + Initiale", "First name + initial") },
        { key = "full", label = T("Voller Name", "Full name") },
    }
    local function NameLabel(key)
        for _, c in ipairs(NAME_CHOICES) do if c.key == key then return c.label end end
        return key
    end
    local namesLabel = UI.Text(f, "label", T("Spielernamen", "Player names"))
    namesLabel:SetPoint("TOPLEFT", 360, -(generalY + 26))
    local names = UI.AddArrow(UI.Button(f, "", 180))
    names:SetPoint("TOPLEFT", 470, -(generalY + 22))
    names:SetScript("OnClick", function(self)
        UI.ChoiceMenu(self, NAME_CHOICES, UI.NameStyle, function(key)
            GetDB().nameStyle = key ~= "initial" and key or nil
            self:SetText(NameLabel(UI.NameStyle()))
            UI.Fire("NameStyleChanged")
        end)
    end)
    names:SetScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(T("Spielernamen", "Player names"))
        tip:AddLine(T("Für Einheiten- und Gruppenrahmen, Namensplaketten, Würfe und Flüster-Fenster. Charakter-Übersicht, Tooltip und Chat zeigen immer den vollen Namen.",
            "For unit and group frames, nameplates, loot rolls and whisper windows. Character overview, tooltip and chat always show the full name."), 1, 1, 1, true)
        tip:Show()
    end)
    names:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)
    function names.Load() names:SetText(NameLabel(UI.NameStyle())) end

    local snapCheck = UI.Check(f, 16, -(generalY + 58), T("Einrasten beim Verschieben", "Snap while moving"), function(checked)
        UI.SetSnapEnabled(checked)
    end)
    snapCheck:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine(T("Einrasten", "Snapping"))
        tip:AddLine(T("Entsperrte Rahmen rasten an anderen Rahmen, der Bildschirmmitte und dem Raster ein. Umschalt beim Ziehen = kurz nicht einrasten. Auch: /fmove snap",
            "Unlocked frames snap to other frames, the screen center and the grid. Hold Shift while dragging to skip it. Also: /fmove snap"), 1, 1, 1, true)
        tip:Show()
    end)
    snapCheck:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    local mm = UI.Check(f, 356, -(generalY + 58), T("Minimap-Knopf anzeigen", "Show minimap button"), function(checked)
        GetDB().hideButton = not checked or nil
        ApplyMode()
    end)

    -- Blizzard-Fenster verschiebbar (Movers.lua, v62)
    local blizzMove = UI.Check(f, 16, -(generalY + 84), T("Blizzard-Fenster verschiebbar", "Movable Blizzard windows"),
        function(checked) if UI.SetBlizzMove then UI.SetBlizzMove(checked) end end)
    blizzMove:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine(T("Blizzard-Fenster verschiebbar", "Movable Blizzard windows"))
        tip:AddLine(T("Charakter, Händler, Post, Berufe, Lehrer, Talente, Auktionshaus, Freunde … an einer freien Stelle mit der linken Maustaste ziehen. Die Lage wird gemerkt.",
            "Drag the character, vendor, mail, professions, trainer, talents, auction house, friends … windows at a free spot with the left mouse button. The position is remembered."), 1, 1, 1, true)
        tip:Show()
    end)
    blizzMove:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    local blizzReset = UI.Button(f, T("Fensterpositionen zurücksetzen", "Reset window positions"), 220, function()
        if UI.ResetBlizzPositions then UI.ResetBlizzPositions() end
        UI.Chat("Forever", T("Blizzard-Fenster stehen beim nächsten Öffnen wieder an ihrem Platz.",
            "Blizzard windows are back in their place the next time you open them."))
    end)
    blizzReset:SetPoint("TOPLEFT", 360, -(generalY + 82))

    ---------------------------------------------------------------------------
    -- Werkzeuge: andere Addons, Profile, Details, alle verschieben
    ---------------------------------------------------------------------------
    UI.Header(f, 16, -toolsY, T("Werkzeuge", "Tools"), W - 24)
    local conflictsBtn = UI.Button(f, T("Andere Addons …", "Other addons …"), 150, function()
        if UI.ShowConflicts then UI.ShowConflicts(true) end
    end)
    conflictsBtn:SetPoint("TOPLEFT", 16, -(toolsY + 22))
    conflictsBtn:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine(T("Andere Addons", "Other addons"))
        tip:AddLine(T("Hast du für Leisten, Taschen, Rahmen, Chat … schon ein anderes Addon (z. B. Bartender4, Bagnon, Cell), wählst du hier, welches laufen soll.",
            "If you already use another addon for bars, bags, frames, chat … (e.g. Bartender4, Bagnon, Cell), choose here which one should run."), 1, 1, 1, true)
        tip:Show()
    end)
    conflictsBtn:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)

    local profilesBtn = UI.Button(f, T("Profile und Austausch …", "Profiles and transfer …"), 180, function()
        if UI.ShowProfiles then UI.ShowProfiles() end
    end)
    profilesBtn:SetPoint("LEFT", conflictsBtn, "RIGHT", 8, 0)

    local move = UI.Button(f, "", 150, function()
        UI.CloseSettings()
        UI.MoveAll()
    end)
    move:SetPoint("LEFT", profilesBtn, "RIGHT", 8, 0)

    -- Details! (falls aktiv): eigenes Profil im Forever-Look bzw. zurück zum vorherigen
    local detailsBtn = UI.Button(f, "", 170, function(self)
        if UI.DetailsForeverActive and UI.DetailsForeverActive() then UI.DetailsRestore() else UI.DetailsApplyForever() end
        if self.Update then self.Update() end
    end)
    detailsBtn:SetPoint("LEFT", move, "RIGHT", 8, 0)
    function detailsBtn.Update()
        local available = UI.DetailsAvailable and UI.DetailsAvailable()
        detailsBtn:SetShown(available)
        if not available then return end
        detailsBtn:SetText(UI.DetailsForeverActive() and T("Details: vorheriges Profil", "Details: previous profile")
            or T("Details im Forever-Look", "Details in the Forever look"))
    end
    detailsBtn:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine("Details!")
        tip:AddLine(T("Legt eine Kopie deines Details-Profils namens „Forever Core“ an und gibt dort allen Fenstern den Forever-Look. Dein bisheriges Profil bleibt unverändert; ein zweiter Klick wechselt zurück.",
            "Creates a copy of your Details profile named \"Forever Core\" and gives all windows the Forever look there. Your previous profile stays unchanged; a second click switches back."), 1, 1, 1, true)
        tip:Show()
    end)
    detailsBtn:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)

    local hint = UI.Hint(f, 20, -(toolsY + 54), W - 40, T("/forever öffnet diese Seite · /fmove verschiebt alle Rahmen · /forever reset holt die Knöpfe zurück",
        "/forever opens this page · /fmove moves all frames · /forever reset brings the buttons back"))
    hint:SetWordWrap(true)

    f:SetScript("OnShow", function()
        SafeSetup() -- falls seit dem Login Addons/Knoepfe dazugekommen sind
        if f.welcome then
            f.TitleText:SetText(T("Willkommen bei Forever Core UI", "Welcome to Forever Core UI"))
            intro:SetText("|cffffd100" .. T("Wähle, welche Addons du nutzen möchtest (Klick auf die Kachel) – danach „Neu laden“. ",
                "Choose which addons you want to use (click a tile) – then \"Reload\". ") .. "|r"
                .. T("Diese Seite öffnet sich nur dieses eine Mal von selbst; später findest du sie mit /forever, über den Forever-Core-UI-Knopf an der Minimap oder unter Esc » Optionen » AddOns.",
                "This page only opens by itself this once; later you'll find it via /forever, the Forever Core UI minimap button or Esc » Options » AddOns."))
        else
            f.TitleText:SetText(UI.NAME)
            intro:SetText(T("Klick auf eine Kachel schaltet das Addon an oder aus (gilt nach dem Neuladen). Die Einstellungen jedes Addons findest du links in der Liste.",
                "Click a tile to turn the addon on or off (applies after reloading). Each addon's settings are in the list on the left."))
        end
        Refresh()
        move:SetText(UI.AnyUnlocked() and T("Alle sperren", "Lock all") or T("Alle verschieben", "Move all"))
        mm:SetChecked(not GetDB().hideButton)
        snapCheck:SetChecked(UI.SnapEnabled())
        blizzMove:SetChecked(not UI.BlizzMoveEnabled or UI.BlizzMoveEnabled())
        perChar:SetChecked(GetDB().perCharacter and true or false)
        detailsBtn.Update()
        if lang then lang.Load() end
        names.Load()
    end)
    f:HookScript("OnHide", function() f.welcome = nil end)
end

function hub.ToggleWindow()
    if not hubWindow then BuildHubWindow() end
    hubWindow:SetShown(not hubWindow:IsShown())
end

-- Begruessung: nur beim allerersten Start (ForeverHubDB.welcomeDone, gilt fuer den ganzen Account)
function hub.ShowWelcome()
    if not hubWindow then BuildHubWindow() end
    hubWindow:Hide()
    hubWindow.welcome = true
    hubWindow:Show()
end

---------------------------------------------------------------------------
-- 3c. Zentrales Einstellungsfenster: links eine Liste aller installierten Forever-Addons (nach Bereichen), rechts
-- immer genau eine Seite. Feste Größe nach dem größten bisherigen Einzelfenster (ForeverBars 720 × 832).
-- Ein Addon baut seine Seite mit UI.SettingsPanel(...) statt mit seinem bisherigen Fenster: Inhalt, Anordnung,
-- Abstände und die eigene Titelleiste der Seite bleiben genau wie im alten Fenster (1:1). Die Seite verhält sich wie
-- das alte Fenster: :Show()/:Hide()/:SetShown()/:IsShown() öffnen bzw. schließen das große Fenster auf dieser Seite –
-- Minimap-Knöpfe, Befehle und "Einstellungen"-Knöpfe landen so automatisch auf dem richtigen Eintrag.
-- Addons, die ihr Fenster erst beim ersten Öffnen bauen, melden vorab einen Eintrag an: UI.RegisterSettingsLink(...).
---------------------------------------------------------------------------
local NAV_W = 196
local NAV_ROW = 26 -- Höhe eines Eintrags in der Liste
local PAGE_W, PAGE_H = 720, 832
local settingsWin
local settingsPages = {}      -- { key, group, label, frame?, open? }
local settingsCurrent
-- feste Reihenfolge der Bereiche (unbekannte kommen ans Ende); Namen erst beim Anzeigen übersetzen
-- (beim Laden von ForeverCore ist die gewählte Sprache noch nicht bekannt)
local GROUP_ORDER = { "core", "frames", "bars", "nav", "comfort", "helpers" }
local GROUP_LABEL = {
    core = function() return UI.NAME end, -- Startseite: Übersicht aller Forever-Addons (früheres Hub-Fenster)
    frames = function() return T("Rahmen", "Frames") end,
    bars = function() return T("Leisten", "Bars") end,
    nav = function() return T("Orientierung", "Navigation") end,
    comfort = function() return T("Komfort", "Comfort") end,
    helpers = function() return T("Helfer", "Helpers") end,
}
UI.SETTINGS_GROUPS = { core = "core", frames = "frames", bars = "bars", nav = "nav", comfort = "comfort", helpers = "helpers" }

---------------------------------------------------------------------------
-- Einstellungssuche (v60, nach dem Vorbild von ForeverBars) oben rechts in der Titelleiste jeder Seite: findet
-- Einstellungen aller Addons nach Namen, öffnet die passende Seite (und den Reiter) und lässt die Einstellung kurz
-- golden aufleuchten. Gesucht wird in allen Texten der Seiten (Haken, Regler, Knöpfe, Überschriften), noch nicht
-- gebaute Seiten werden dafür einmal still gebaut. Ein Addon mit eigener Suche meldet stattdessen seine Einträge:
-- UI.RegisterSearch(key, function() return { { label, path, go = function() … end }, … } end).
-- Reiter: ein Reiter-Bereich mit .fcReveal = function() … end wird vor dem Aufleuchten geöffnet.
---------------------------------------------------------------------------
local searchProviders = {}
local searchBuilding      -- true, solange Seiten nur für die Suche gebaut werden (sie sollen sich nicht öffnen)
local searchIndex         -- zwischengespeichert, bis das Fenster schließt oder eine Seite dazukommt

function UI.RegisterSearch(key, provider)
    searchProviders[key] = provider
    searchIndex = nil
end

local function SearchText(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("\n", " ")
    return strtrim(s)
end

-- alle Texte einer Seite einsammeln (graue Erklärtexte, Eingabefelder und Werte in Auswahllisten nicht)
local function CrawlPage(frame, page, path, list, depth)
    if depth > 10 or frame:IsObjectType("EditBox") or frame.fcSimpleHidden then return end
    local isControl = frame ~= page.frame and (frame:IsObjectType("Button") or frame:IsObjectType("Slider"))
    if not (isControl and frame.fcArrow) then
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("FontString") and r ~= page.frame.TitleText and r ~= page.frame.SubText and not r.fcSimpleHidden then
                local text = r:GetText()
                local font = r:GetFontObject()
                local fname = font and font.GetName and font:GetName() or ""
                if text and text ~= "" and not fname:find("Disable") then
                    text = SearchText(text)
                    if #text >= 3 and #text <= 60 and text:find("%a%a") then
                        list[#list + 1] = { label = text, path = path, page = page, control = isControl and frame or r }
                    end
                end
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do CrawlPage(child, page, path, list, depth + 1) end
end

local function BuildSearchIndex()
    if searchIndex then return searchIndex end
    -- noch nicht gebaute Seiten einmal still bauen (ohne sie zu öffnen)
    searchBuilding = true
    for _, page in ipairs(settingsPages) do
        if not page.frame and page.open and not page.opening then
            page.opening = true
            local ok, err = pcall(page.open)
            page.opening = nil
            if not ok then UI.ReportError("ForeverCore", "Search " .. tostring(page.key), err) end
        end
    end
    searchBuilding = nil
    local list = {}
    for _, page in ipairs(settingsPages) do
        -- die Seite selbst ist auch ein Treffer
        local group = GROUP_LABEL[page.group] and GROUP_LABEL[page.group]() or tostring(page.group)
        list[#list + 1] = { label = page.label, path = group, page = page }
        local provider = searchProviders[page.key]
        if provider then
            local ok, entries = pcall(provider)
            if ok and type(entries) == "table" then
                for _, e in ipairs(entries) do
                    if e.label and e.label ~= "" then
                        list[#list + 1] = { label = e.label, page = page, go = e.go,
                            path = e.path and (page.label .. " » " .. e.path) or page.label }
                    end
                end
            end
        elseif page.frame then
            CrawlPage(page.frame, page, page.label, list, 1)
        end
    end
    searchIndex = list
    return list
end

local function BuildSearch(f)
    local search = UI.EditBox(f, 200, 22)
    search:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -40, -3) -- mittig in der Titelleiste der Seite, vor dem Kreuz
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 7, 0)
    placeholder:SetText(T("Einstellung suchen …", "Search settings …"))
    f.search = search

    -- goldener Rahmen, der kurz um die gefundene Einstellung aufleuchtet
    local flash = CreateFrame("Frame", nil, f, "BackdropTemplate")
    flash:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    flash:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
    flash:SetFrameStrata("FULLSCREEN")
    flash:EnableMouse(false)
    flash:Hide()
    local function Flash(control)
        if not control or not control:IsVisible() then return end
        flash:ClearAllPoints()
        flash:SetPoint("TOPLEFT", control, "TOPLEFT", -4, 4)
        local label = control.GetObjectType and control:GetObjectType() == "CheckButton" and control.label
        if type(label) == "table" and label.GetRight then
            flash:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 4, -4)
            flash:SetPoint("BOTTOM", control, "BOTTOM", 0, -4)
        else
            flash:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 4, -4)
        end
        flash:Show()
        flash.token = (flash.token or 0) + 1
        local token = flash.token
        C_Timer.After(1.5, function() if flash.token == token then flash:Hide() end end)
    end

    local function GoTo(entry)
        UI.OpenSettings(entry.page.key)
        if entry.go then
            local ok, err = pcall(entry.go)
            if not ok then UI.ReportError("ForeverCore", "Search " .. tostring(entry.page.key), err) end
            return
        end
        local control = entry.control
        if not control then return end
        -- Reiter öffnen, in denen die Einstellung liegt (von außen nach innen)
        local chain, p = {}, control:GetParent()
        while p and p ~= entry.page.frame do
            if p.fcReveal then table.insert(chain, 1, p) end
            p = p:GetParent()
        end
        for _, tab in ipairs(chain) do
            if not tab:IsShown() then pcall(tab.fcReveal) end
        end
        C_Timer.After(0, function() Flash(control) end) -- nach dem Anordnen der Seite
    end

    -- Trefferliste unter dem Suchfeld
    local results = CreateFrame("Frame", nil, f, "BackdropTemplate")
    UI.SetFlat(results, C.background)
    results:SetFrameStrata("FULLSCREEN_DIALOG")
    results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -4)
    results:SetWidth(360)
    results:EnableMouse(true)
    results:Hide()
    local MAX_RESULTS = 14
    local rows = {}
    for i = 1, MAX_RESULTS do
        local row = CreateFrame("Button", nil, results)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 20)
        row:SetPoint("RIGHT", -1, 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetPoint("RIGHT", -10, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        -- Eintrag "Nichts gefunden" (ohne entry) ist nicht anklickbar
        row:SetScript("OnClick", function(self)
            if not self.entry then return end
            results:Hide()
            search:ClearFocus()
            GoTo(self.entry)
        end)
        rows[i] = row
    end

    local function UpdateResults()
        local text = strtrim(search:GetText() or ""):lower()
        placeholder:SetShown(text == "" and not search:HasFocus())
        if text == "" then results:Hide() return end
        local count, seen = 0, {}
        for _, entry in ipairs(BuildSearchIndex()) do
            local key = (entry.path or "") .. entry.label
            if count < MAX_RESULTS and not seen[key] and entry.label:lower():find(text, 1, true) then
                seen[key] = true
                count = count + 1
                local row = rows[count]
                row.entry = entry
                row.text:SetText((entry.path and ("|cff8a8a8a" .. entry.path .. " »|r ") or "") .. entry.label)
                row:Show()
            end
        end
        for i = count + 1, MAX_RESULTS do rows[i]:Hide() end
        if count == 0 then
            rows[1].entry = nil
            rows[1].text:SetText("|cff8a8a8a" .. T("Nichts gefunden", "Nothing found") .. "|r")
            rows[1]:Show()
            count = 1
        end
        results:SetHeight(count * 20 + 8)
        results:Show()
    end
    search:SetScript("OnTextChanged", UpdateResults)
    search:HookScript("OnEditFocusGained", function() placeholder:Hide() end)
    search:HookScript("OnEditFocusLost", function() placeholder:SetShown(strtrim(search:GetText() or "") == "") end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        results:Hide()
    end)
    search:SetScript("OnEnterPressed", function(self)
        local first = rows[1]
        if results:IsShown() and first:IsShown() and first.entry then
            results:Hide()
            self:ClearFocus()
            GoTo(first.entry)
        end
    end)
    f:HookScript("OnHide", function()
        results:Hide()
        search:SetText("")
        search:ClearFocus()
        searchIndex = nil -- Texte (z. B. Sprache) beim nächsten Mal neu einlesen
    end)
end

---------------------------------------------------------------------------
-- Einfach-Modus (TEST, v74): Knopf oben im Einstellungsfenster. Blendet je Seite Experten-Abschnitte/-Reiter aus und
-- rückt die Elemente darunter nach oben (Lücken schließen). Die Seiten der Addons bleiben unangetastet; Experte =
-- alles wie zuvor. Zum Entfernen: diesen Block, die Zeile "UI.Simple.Apply(page)" in UI.OpenSettings, den Knopf in
-- SettingsWindow und die zwei "fcSimpleHidden"-Zeilen in CrawlPage löschen.
---------------------------------------------------------------------------
UI.Simple = {}
do
    local S = UI.Simple

    function S.IsOn() return type(_G.ForeverHubDB) == "table" and _G.ForeverHubDB.simpleMode == true end
    function S.Set(on)
        if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
        _G.ForeverHubDB.simpleMode = on and true or nil
    end

    -- Was im Einfach-Modus wegfällt (nach Überschrift bzw. Reitername). Funktionen, damit die Sprache erst beim Anzeigen gilt.
    local RULES = {
        ForeverUnits = function() return {
            tabs = { T("Optik", "Look") },
            sections = { T("Ausrichten (wenn entsperrt)", "Alignment (when unlocked)"), T("Alles", "Everything"),
                T("DoT-Leisten (nur Ziel und Fokus)", "DoT bars (target and focus only)"),
                T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)") } } end,
        ForeverFrames = function() return { tabs = { T("Optik", "Look"), T("Symbole", "Icons") } } end,
        ForeverPlates = function() return {
            tabs = { T("Schadenszahlen", "Damage text") },
            sections = { T("Sonstiges", "Other"), T("Farben nach Bedrohung", "Colors by threat"), T("Verbündete", "Allies") } } end,
        ForeverCast = function() return {
            sections = { T("Spell-Queue-Fenster", "Spell queue window"), T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)"),
                T("Look", "Look") } } end,
        ["ForeverHelpers.vendor"] = function() return {
            sections = { T("Grenzen beim Nachkaufen", "Restock limits"), T("Munition (Jäger)", "Ammo (hunter)"), T("Anzeige", "Display"),
                T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)") } } end,
        ["ForeverHelpers.loot"] = function() return { sections = { T("Position", "Position"), T("Testmodus", "Test mode") } } end,
        ["ForeverHelpers.buffs"] = function() return { sections = { T("Eigene Liste", "Own list"), T("Anzeige", "Display") } } end,
        ForeverAlts = function() return { sections = { T("Mit anderen Forever-Addons", "With other Forever addons") } } end,
        ForeverChat = function() return {
            sections = { T("Position und Sperre", "Position and lock"), T("Instant Messaging", "Instant messaging"), T("Farben", "Colors") } } end,
        ForeverTooltip = function() return { sections = { T("Ort", "Position") } } end,
    }

    -- alles auf den ursprünglichen Stand zurück (Zeige-Zustand, Positionen, Abschnittsliste)
    function S.Restore(panel)
        local st = panel.fcSimple
        if not st then return end
        for _, it in ipairs(st.items) do
            if it.hid then it.obj:Show() it.obj.fcSimpleHidden = nil end
            if it.moved then
                it.obj:ClearAllPoints()
                for _, p in ipairs(it.pts) do it.obj:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            end
        end
        panel.fcSections = st.allSecs
        for _, s in ipairs(st.allSecs) do
            s.y = s.origY or s.y
            if s.box then
                s.box.fill:Show()
                for _, e in ipairs(s.box.edges) do e:Show() end
            end
        end
        panel.fcSimple = nil
    end

    function S.Panel(panel, rule)
        S.Restore(panel)
        local secs = panel.fcSections
        if not rule or not rule.set or not secs then return end
        local isHidden, anyHidden = {}, false
        for _, s in ipairs(secs) do
            local text = s.fs:GetText()
            if text and rule.set[text] then isHidden[s] = true anyHidden = true end
        end
        if not anyHidden then return end

        -- Spalte und Bereich jedes Abschnitts (gleiche Regeln wie UI.LayoutSections), mit den ursprünglichen Werten
        local GAP = 12
        local info = {}
        for _, s in ipairs(secs) do
            s.origY = s.y
            local cap = math.huge
            if s.width < 400 then
                for _, o in ipairs(secs) do
                    if o.x > s.x + 20 then cap = math.min(cap, o.x - 8 - GAP) end
                end
            end
            local hl, nextY = s.x - 8, nil
            for _, o in ipairs(secs) do
                if o ~= s and o.y < s.y and ((o.x < cap and o.x + 8 > hl) or o.width >= 400) then
                    if not nextY or o.y > nextY then nextY = o.y end
                end
            end
            info[s] = { hl = hl, cap = cap, top = s.y, nextY = nextY, delta = nextY and (s.y - nextY) or 0 }
        end
        local hiddenList = {}
        for _, s in ipairs(secs) do if isHidden[s] then hiddenList[#hiddenList + 1] = info[s] end end

        -- Wie weit rückt ein Element an (x, y) nach oben, bzw. fällt es in einen ausgeblendeten Abschnitt?
        local function Place(x, y)
            local shift = 0
            for _, h in ipairs(hiddenList) do
                if x >= h.hl - 4 and x < h.cap then
                    if y <= h.top + 2 and (not h.nextY or y > h.nextY + 2) then return true, 0 end
                    if h.nextY and y <= h.nextY + 2 then shift = shift + h.delta end
                end
            end
            return false, shift
        end

        local skip = {}
        for _, s in ipairs(secs) do if s.box then skip[s.box.fill] = true end end
        if panel.header then skip[panel.header] = true end
        local items = {}
        local function Add(obj)
            if skip[obj] then return end
            local n = obj.GetNumPoints and obj:GetNumPoints() or 0
            local pts, x, y = {}, nil, nil
            for i = 1, n do
                local point, rel, relPoint, px, py = obj:GetPoint(i)
                pts[i] = { point, rel, relPoint, px, py }
                if rel == panel and point == "TOPLEFT" and not x then x, y = px, py end
            end
            if x then items[#items + 1] = { obj = obj, pts = pts, x = x, y = y } end
        end
        for _, c in ipairs({ panel:GetChildren() }) do Add(c) end
        for _, r in ipairs({ panel:GetRegions() }) do Add(r) end

        for _, it in ipairs(items) do
            local hide, shift = Place(it.x, it.y)
            if hide then
                if it.obj:IsShown() then it.obj:Hide() it.obj.fcSimpleHidden = true it.hid = true end
            elseif shift ~= 0 then
                it.obj:ClearAllPoints()
                for _, p in ipairs(it.pts) do
                    it.obj:SetPoint(p[1], p[2], p[3], p[4], p[2] == panel and (p[5] + shift) or p[5])
                end
                it.moved = true
            end
        end

        local visible = {}
        for _, s in ipairs(secs) do
            if isHidden[s] then
                if s.box then
                    s.box.fill:Hide()
                    for _, e in ipairs(s.box.edges) do e:Hide() end
                end
            else
                local _, shift = Place(s.x, s.y)
                s.y = s.y + shift
                visible[#visible + 1] = s
            end
        end
        panel.fcSimple = { items = items, allSecs = secs }
        panel.fcSections = visible
        C_Timer.After(0, function() UI.LayoutSections(panel) end)
    end

    -- Reiter-Knöpfe ausblenden, die übrigen rücken nach links
    function S.Tabs(frame, rule)
        local old = frame.fcSimpleTabs
        if old then
            for _, t in ipairs(old) do
                t.b:Show()
                t.b:ClearAllPoints()
                for _, p in ipairs(t.pts) do t.b:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
            end
            frame.fcSimpleTabs = nil
        end
        if not rule or not rule.tabs then return end
        local names = {}
        for _, n in ipairs(rule.tabs) do names[n] = true end
        local row, rowY = {}, nil
        for _, c in ipairs({ frame:GetChildren() }) do
            if c:IsObjectType("Button") and c.GetText and names[c:GetText() or ""] then
                local point, rel, _, _, py = c:GetPoint(1)
                if point == "TOPLEFT" and rel == frame then rowY = py break end
            end
        end
        if not rowY then return end
        for _, c in ipairs({ frame:GetChildren() }) do
            if c:IsObjectType("Button") and c:GetNumPoints() == 1 then
                local point, rel, relPoint, px, py = c:GetPoint(1)
                if point == "TOPLEFT" and rel == frame and math.abs(py - rowY) < 0.5 then
                    row[#row + 1] = { b = c, pts = { { point, rel, relPoint, px, py } }, x = px }
                end
            end
        end
        table.sort(row, function(a, b) return a.x < b.x end)
        local cursor, activeHidden, firstVisible = row[1].x, false, nil
        for _, t in ipairs(row) do
            if names[t.b:GetText() or ""] then
                if not t.b:IsEnabled() then activeHidden = true end
                t.b:Hide()
            else
                t.b:ClearAllPoints()
                t.b:SetPoint("TOPLEFT", frame, "TOPLEFT", cursor, rowY)
                cursor = cursor + t.b:GetWidth() + 4
                firstVisible = firstVisible or t.b
            end
        end
        frame.fcSimpleTabs = row
        if activeHidden and firstVisible then firstVisible:Click() end
    end

    local function Walk(frame, fn, depth)
        if frame.fcSections then fn(frame) end
        if depth >= 5 then return end
        for _, c in ipairs({ frame:GetChildren() }) do Walk(c, fn, depth + 1) end
    end

    function S.Apply(page)
        local frame = page and page.frame
        if not frame then return end
        local make = S.IsOn() and RULES[page.key]
        local rule = make and make() or nil
        if rule then
            rule.set = {}
            for _, n in ipairs(rule.sections or {}) do rule.set[n] = true end
        end
        Walk(frame, function(panel) S.Panel(panel, rule) end, 0)
        S.Tabs(frame, rule)
        searchIndex = nil -- Suche neu aufbauen (versteckte Einstellungen nicht anbieten)
    end

    function S.Label()
        if S.IsOn() then return T("Ansicht: Einfach", "View: Simple") end
        return T("Ansicht: Experte", "View: Expert")
    end

    function S.Refresh()
        if settingsWin and settingsWin.simpleBtn then settingsWin.simpleBtn:SetText(S.Label()) end
        if settingsCurrent then S.Apply(settingsCurrent) end
    end
end

local function SettingsWindow()
    if settingsWin then return settingsWin end
    local f = UI.Window("ForeverSettingsWindow", UI.NAME, NAV_W + 2 + PAGE_W, PAGE_H)
    settingsWin = f
    -- linke Liste (unter der Titelleiste)
    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 1, -27)
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(NAV_W)
    UI.SetFlat(nav, { C.panel[1], C.panel[2], C.panel[3], 0.6 })
    nav:SetBackdropBorderColor(0, 0, 0, 0)
    local navLine = nav:CreateTexture(nil, "ARTWORK")
    navLine:SetPoint("TOPRIGHT")
    navLine:SetPoint("BOTTOMRIGHT")
    navLine:SetWidth(1)
    navLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    f.nav = nav
    f.navButtons, f.navHeaders = {}, {}
    -- rechts: Platz für die Seiten (über die volle Höhe – die Seite bringt ihre eigene Titelleiste mit)
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", NAV_W + 1, 0)
    content:SetPoint("BOTTOMRIGHT", -1, 1)
    content:SetClipsChildren(true) -- nichts ragt über den Rand (Auswahllisten und Tooltips sind eigene Fenster)
    f.content = content
    -- Ebenen immer relativ zum Fenster: "zuletzt geöffnet liegt oben" hebt das Fenster an – feste Ebenen rutschten
    -- dabei hinter den Fensterhintergrund (Seiten wirkten abgedunkelt und ließen sich nicht anklicken)
    -- (auch alle Unterflächen darin, z. B. die Reiter-Flächen von ForeverUnits/ForeverFrames: sie wanderten sonst nicht
    -- mit und lagen hinter dem Fensterhintergrund) – nur anheben, wo nötig, die Reihenfolge untereinander bleibt
    local function KeepAbove(parent, depth)
        if depth > 8 then return end
        local level = parent:GetFrameLevel()
        for _, child in ipairs({ parent:GetChildren() }) do
            if child:GetFrameLevel() <= level then child:SetFrameLevel(level + 1) end
            KeepAbove(child, depth + 1)
        end
    end
    local function Levels()
        local base = f:GetFrameLevel()
        content:SetFrameLevel(base + 2)
        KeepAbove(content, 1)
        if f.CloseButton then f.CloseButton:SetFrameLevel(base + 60) end -- Schließen-Kreuz über der Titelleiste der Seite
        if f.search then f.search:SetFrameLevel(base + 60) end -- Suchfeld ebenso
        if f.simpleBtn then f.simpleBtn:SetFrameLevel(base + 60) end -- Einfach-/Experten-Knopf ebenso
    end
    BuildSearch(f)
    -- Einfach-Modus (Test): Knopf links neben dem Suchfeld
    f.simpleBtn = UI.Button(f, UI.Simple.Label(), 124, function()
        UI.Simple.Set(not UI.Simple.IsOn())
        UI.Simple.Refresh()
    end)
    f.simpleBtn:SetPoint("RIGHT", f.search, "LEFT", -6, 0)
    f.simpleBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(T("Einfach / Experte", "Simple / Expert"))
        GameTooltip:AddLine(T("Einfach zeigt nur die wichtigsten Einstellungen, Experte alle. Klick schaltet um.",
            "Simple shows only the most important settings, Expert shows all. Click to switch."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.simpleBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    hooksecurefunc(f, "SetFrameLevel", Levels)
    f.fcLevels = Levels
    Levels()
    -- passt das Fenster nicht auf den Bildschirm, beim Öffnen verkleinern (größer ziehen geht weiter mit dem Griff)
    f:HookScript("OnShow", function(self)
        Levels()
        local h = UIParent:GetHeight()
        if h and h > 0 and PAGE_H * self:GetScale() > h - 20 then self:SetScale((h - 20) / PAGE_H) end
        if settingsCurrent and settingsCurrent.frame then settingsCurrent.frame:fcRawShow() end
    end)
    f:HookScript("OnHide", function()
        -- Seite verstecken: beim nächsten Öffnen lädt sie ihre Werte neu (OnShow), ihr OnHide läuft wie beim alten Fenster
        if settingsCurrent and settingsCurrent.frame then settingsCurrent.frame:fcRawHide() end
    end)
    return f
end

local function GroupIndex(group)
    for i, g in ipairs(GROUP_ORDER) do if g == group then return i end end
    GROUP_ORDER[#GROUP_ORDER + 1] = group
    return #GROUP_ORDER
end

local function LayoutNav()
    local f = SettingsWindow()
    for _, b in ipairs(f.navButtons) do b:Hide() end
    for _, h in ipairs(f.navHeaders) do h:Hide() end
    local y, bi, hi = -10, 0, 0
    for _, group in ipairs(GROUP_ORDER) do
        local any = false
        for _, page in ipairs(settingsPages) do if page.group == group then any = true break end end
        if any then
            hi = hi + 1
            local h = f.navHeaders[hi]
            if not h then
                h = f.nav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- Bereich: klein, gold
                f.navHeaders[hi] = h
            end
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 14, y)
            h:SetAlpha(0.85)
            h:SetText(string.upper(GROUP_LABEL[group] and GROUP_LABEL[group]() or tostring(group)))
            h:Show()
            y = y - 18
            for _, page in ipairs(settingsPages) do
                if page.group == group then
                    bi = bi + 1
                    local b = f.navButtons[bi]
                    if not b then
                        b = CreateFrame("Button", nil, f.nav)
                        b:SetHeight(NAV_ROW)
                        b.hl = b:CreateTexture(nil, "BACKGROUND")
                        b.hl:SetAllPoints()
                        b.hl:SetColorTexture(1, 1, 1, 0.06)
                        b.hl:Hide()
                        b.sel = b:CreateTexture(nil, "BACKGROUND")
                        b.sel:SetAllPoints()
                        b.sel:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
                        b.mark = b:CreateTexture(nil, "ARTWORK")
                        b.mark:SetPoint("TOPLEFT")
                        b.mark:SetPoint("BOTTOMLEFT")
                        b.mark:SetWidth(3)
                        b.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
                        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- Addon-Namen gut lesbar
                        b.text:SetPoint("LEFT", 16, 0)
                        b:SetScript("OnEnter", function(self) self.hl:Show() end)
                        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
                        f.navButtons[bi] = b
                    end
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", 4, y)
                    b:SetPoint("TOPRIGHT", -5, y)
                    b.text:SetText(page.label)
                    local selected = page == settingsCurrent
                    b.sel:SetShown(selected)
                    b.mark:SetShown(selected)
                    b.text:SetTextColor(selected and C.accent[1] or 0.9, selected and C.accent[2] or 0.9, selected and C.accent[3] or 0.9)
                    b:SetScript("OnClick", function() UI.OpenSettings(page.key) end)
                    b:Show()
                    y = y - (NAV_ROW + 1)
                end
            end
            y = y - 10
        end
    end
end

local function FindPage(which)
    for _, page in ipairs(settingsPages) do
        if which ~= nil and (page.frame == which or page.key == which) then return page end
    end
end

-- Eintrag anlegen bzw. finden (Reihenfolge innerhalb eines Bereichs = Reihenfolge der Anmeldung)
local function PageEntry(key, group, label)
    local page = FindPage(key)
    if not page then
        page = { key = key }
        settingsPages[#settingsPages + 1] = page
    end
    page.group = group or page.group or T("Weitere", "More")
    page.label = label or page.label or key
    GroupIndex(page.group)
    return page
end

function UI.OpenSettings(which)
    if searchBuilding then return end -- Seite wird nur für die Suche gebaut, nicht öffnen
    local f = SettingsWindow()
    -- ohne bestimmte Seite: bei offenem Fenster die aktuelle, sonst die Startseite "Forever Core UI » Übersicht" (v56)
    local page = FindPage(which) or (f:IsShown() and settingsCurrent) or FindPage("ForeverCore") or settingsCurrent
        or settingsPages[1]
    if not page then return end
    if not page.frame then
        -- Seite wird erst jetzt gebaut (Addon baut sein Fenster beim ersten Öffnen): dessen Öffnen landet wieder hier
        if page.open and not page.opening then
            page.opening = true
            local ok, err = pcall(page.open)
            page.opening = nil
            if not ok then UI.ReportError("ForeverCore", "Settings " .. tostring(page.key), err) end
        end
        if not page.frame then return end
    end
    if settingsCurrent and settingsCurrent ~= page and settingsCurrent.frame then settingsCurrent.frame:fcRawHide() end
    settingsCurrent = page
    UI.Simple.Apply(page) -- Einfach-Modus (Test)
    page.frame:ClearAllPoints()
    page.frame:SetPoint("TOPLEFT", f.content, "TOPLEFT", page.frame.fcInsetX or 0,
        (page.frame.fcShift or 0) - (page.frame.fcInsetY or 0))
    LayoutNav()
    if f:IsShown() then page.frame:fcRawShow() else f:Show() end
    if f.fcLevels then f.fcLevels() end -- neue Seite (evtl. eben erst gebaut) über den Fensterhintergrund
end

function UI.CloseSettings()
    if settingsWin and settingsWin:IsShown() then settingsWin:Hide() end
end

-- gleiche Seite nochmal = schließen (wie bisher der Minimap-Knopf / Befehl)
function UI.ToggleSettings(which)
    local f = SettingsWindow()
    local page = FindPage(which)
    if f:IsShown() and page and page == settingsCurrent then f:Hide() return end
    UI.OpenSettings(which)
end

-- Eintrag für ein Addon, das seine Seite erst beim ersten Öffnen baut. info = { key, group, label, open }
function UI.RegisterSettingsLink(info)
    local page = PageEntry(info.key, info.group, info.label)
    page.open = info.open
    if settingsWin and settingsWin:IsShown() then LayoutNav() end
end

-- Startseite: die Übersicht aller Forever-Addons (früher eigenes Hub-Fenster) steht als erster Eintrag ganz oben;
-- die Seite selbst entsteht beim ersten Öffnen (BuildHubWindow)
UI.RegisterSettingsLink({ key = "ForeverCore", group = UI.SETTINGS_GROUPS.core, label = T("Übersicht", "Overview"),
    open = function() hub.ToggleWindow() end })

-- Seite anlegen (statt eines eigenen Fensters).
-- info = { key, group, label, kind } – kind: nil (wie UI.Window, Titelleiste 26), "menu" (wie UI.MenuWindow bzw.
-- Style.CreateWindow aus ForeverBars/ForeverQuests, Titelleiste 40, Titel groß, Untertitel)
function UI.SettingsPanel(name, title, width, height, info)
    info = info or {}
    local f = SettingsWindow()
    local p = CreateFrame("Frame", name, f.content)
    p:SetSize(width, height)
    p:SetPoint("TOPLEFT")
    p:Hide()
    -- echte Anzeige-Funktionen fürs große Fenster; nach außen verhält sich die Seite wie das alte Fenster
    p.fcRawShow, p.fcRawHide, p.fcRawIsShown = p.Show, p.Hide, p.IsShown
    function p:Show() UI.OpenSettings(self) end
    function p:Hide()
        if settingsCurrent and settingsCurrent.frame == self then UI.CloseSettings() end
    end
    function p:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function p:IsShown()
        return settingsWin ~= nil and settingsWin:IsShown() and settingsCurrent ~= nil and settingsCurrent.frame == self
    end
    p.IsVisible = p.IsShown
    -- Viele Seiten setzen ihr OnShow/OnHide noch mit SetScript (wie beim alten Fenster). SetScript wirft aber alle
    -- HookScript-Haken weg – darunter die Abschnitts-Kästen von UI.Header und RefreshAll/HideMenu. Darum bleiben die
    -- Handler der Seite fest; SetScript("OnShow"/"OnHide") legt nur die Funktion des Addons darin ab (v48).
    local rawSetScript, rawGetScript = p.SetScript, p.GetScript
    p.fcScripts = {}
    for _, event in ipairs({ "OnShow", "OnHide" }) do
        rawSetScript(p, event, function(self, ...)
            local fn = self.fcScripts[event]
            if fn then fn(self, ...) end
        end)
    end
    function p:SetScript(event, fn)
        if event == "OnShow" or event == "OnHide" then self.fcScripts[event] = fn else rawSetScript(self, event, fn) end
    end
    function p:GetScript(event)
        if event == "OnShow" or event == "OnHide" then return self.fcScripts[event] end
        return rawGetScript(self, event)
    end

    -- Titelleiste der Seite wie im alten Fenster (über die volle Breite des Seitenbereichs)
    -- Einheitlich für alle Seiten: flache Titelleiste 26 hoch, genau auf Höhe der Titelleiste des großen Fensters.
    -- Seiten aus Fenstern mit höherer Titelleiste (40: UI.MenuWindow, Style.CreateWindow von ForeverBars/ForeverQuests)
    -- rücken um den Unterschied nach oben (p.fcShift) – ihr Inhalt behält alle Abstände untereinander.
    local menu = info.kind == "menu"
    local shift = (menu and UI.MENU.headerHeight or 26) - 26
    p.fcShift = shift
    -- Seiten mit automatischen Kästen (UI.Header) rücken etwas nach rechts unten, damit rundherum – vor allem unter
    -- der Titelleiste – so viel Luft ist wie im Menü von ForeverBars (v60). Die Titelleiste bleibt oben (hängt am
    -- Seitenbereich, nicht an der Seite). Menü-Seiten (ForeverBars, ForeverQuests, ForeverMinimap) haben ihre Maße schon.
    p.fcInsetX, p.fcInsetY = menu and 0 or 4, menu and 0 or 16
    local header = CreateFrame("Frame", nil, p, "BackdropTemplate")
    header:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -1)
    header:SetPoint("RIGHT", f.content, "RIGHT", -1, 0)
    header:SetHeight(26)
    header:SetBackdrop({ bgFile = WHITE })
    header:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    -- Titelleiste verschiebt das große Fenster (wie vorher die eigene)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    p.header = header
    -- Titel wie bei allen Seiten, dahinter klein und grau der Untertitel (z. B. Addon-Name)
    p.TitleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.TitleText:SetPoint("LEFT", 10, 0)
    p.SubText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.SubText:SetPoint("LEFT", p.TitleText, "RIGHT", 10, 0)
    p.SubText:SetText(info.subtitle or "")
    p.TitleText:SetText(title or "")
    p.titleText, p.subText = p.TitleText, p.SubText -- (Schreibweise von Style.CreateWindow)
    p.CloseButton = f.CloseButton
    -- Bausteine aus UI.Menu*: :Refresh() beim Öffnen, offene Auswahlliste beim Schließen zu
    p.menuWindow = p
    function p:RefreshAll()
        for _, c in ipairs(self.menuControls or {}) do if c.Refresh then c:Refresh() end end
    end
    p:HookScript("OnShow", function(self) self:RefreshAll() end)
    p:HookScript("OnHide", function() if UI.HideMenu then UI.HideMenu() end end)

    local page = PageEntry(info.key or name, info.group, info.label or title)
    page.frame = p
    if not searchBuilding then searchIndex = nil end -- neue Seite: Suche neu einlesen
    if settingsWin:IsShown() then LayoutNav() end
    return p
end

---------------------------------------------------------------------------
-- 3b. Andere bekannte Addons für dieselbe Aufgabe (z. B. Bartender4 und ForeverBars): der Spieler wählt je Paar,
-- welches laufen soll – das andere wird über Blizzards Addon-Verwaltung ausgeschaltet (gilt nach dem Neuladen,
-- jederzeit umkehrbar). Erscheint beim ersten Start neben der Begrüßung und später nur, wenn ein neues Paar dazukommt;
-- sonst über "Andere Addons …" im Hub-Fenster. Addon-Pakete wie ElvUI sind bewusst nicht dabei (sie würden ganz
-- abgeschaltet).
---------------------------------------------------------------------------
-- (als Funktion: die Texte erst beim Anzeigen übersetzen – beim Laden ist die Hub-Sprache noch nicht bekannt)
local function ConflictDefs() return {
    { forever = "ForeverBars",    topic = T("Aktionsleisten", "Action bars"),        others = { "Bartender4", "Dominos" } },
    { forever = "ForeverBags",    topic = T("Taschen", "Bags"),                      others = { "Baganator", "Bagnon", "AdiBags", "ArkInventory", "BetterBags", "Combuctor" } },
    { forever = "ForeverFrames",  topic = T("Gruppen- und Raidrahmen", "Party and raid frames"), others = { "Cell", "Grid2", "VuhDo" } },
    { forever = "ForeverUnits",   topic = T("Einheitenrahmen", "Unit frames"),       others = { "ShadowedUnitFrames", "PitBull4", "XPerl" } },
    { forever = "ForeverChat",    topic = "Chat",                                    others = { "Prat-3.0", "Chattynator" } },
    { forever = "ForeverMinimap", topic = "Minimap",                                 others = { "SexyMap", "BasicMinimap" } },
    { forever = "ForeverCast",    topic = T("Zauberleiste", "Cast bar"),             others = { "Quartz" } },
    { forever = "ForeverQuests",  topic = T("Questtracker", "Quest tracker"),        others = { "!KalielsTracker" } },
    { forever = "ForeverTooltip", topic = "Tooltip",                                 others = { "TipTac", "TinyTooltip" } },
    { forever = "ForeverPlates",  topic = T("Namensplaketten", "Nameplates"),        others = { "BetterBlizzPlates", "Plater", "Kui_Nameplates", "TidyPlates_ThreatPlates", "Platynator" } },
} end

-- Leatrix Plus: ein Addon mit vielen Einzelfunktionen. Statt es ganz abzuschalten, schalten wir nur die Funktionen
-- aus, die ein Forever-Addon übernimmt (Leatrix liest seine Einstellungen LeaPlusDB beim eigenen ADDON_LOADED –
-- ForeverCore lädt vorher und setzt sie unmittelbar davor). Alle übrigen Leatrix-Funktionen laufen weiter.
-- Standard: das Forever-Addon gewinnt; im Fenster "Andere Addons" umstellbar ("Leatrix" = Forever-Addon aus).
local LEATRIX = "Leatrix_Plus"
local function LeatrixDefs() return {
    { forever = "ForeverMinimap", topic = "Minimap",                         keys = { "MinimapModder" },
      feature = T("Minimap verbessern", "Enhance minimap") },
    { forever = "ForeverTooltip", topic = "Tooltip",                         keys = { "TipModEnable" },
      feature = T("Tooltip verbessern", "Enhance tooltip") },
    -- (Händler absichtlich nicht: doppelt verkaufen/reparieren schadet nicht – abschalten könnte die Automatik kosten)
    { forever = "ForeverChat",    topic = "Chat",                            keys = { "NoChatButtons", "MoveChatEditBoxToTop", "UseArrowKeysInChat" },
      feature = T("Chat-Knöpfe, Eingabe oben, Pfeiltasten", "Chat buttons, editbox on top, arrow keys") },
    { forever = "ForeverBars",    topic = T("Aktionsleisten", "Action bars"), keys = { "HideKeybindText", "HideMacroText" },
      feature = T("Tasten-/Makrotext ausblenden", "Hide keybind/macro text") },
} end

local function LeatrixKey(d) return d.forever .. ">" .. LEATRIX end

-- vor Leatrix' eigenem Laden: gewünschte Werte in LeaPlusDB setzen (gilt ab diesem Laden)
local function ApplyLeatrix()
    local lea = _G.LeaPlusDB
    if type(lea) ~= "table" then return end
    local db = GetDB()
    db.leatrixOff = db.leatrixOff or {}
    local choice = db.conflictChoice or {}
    local turnedOff = {}
    for _, d in ipairs(LeatrixDefs()) do
        local useLeatrix = choice[LeatrixKey(d)] == "other"
        if not useLeatrix and IsEnabled(d.forever) then
            local any = false
            for _, k in ipairs(d.keys) do
                if lea[k] == "On" then
                    lea[k] = "Off"
                    db.leatrixOff[k] = true
                    any = true
                end
            end
            if any then turnedOff[#turnedOff + 1] = d end
        elseif useLeatrix then
            -- zurück zu Leatrix: was wir abgeschaltet hatten, wieder an
            for _, k in ipairs(d.keys) do
                if db.leatrixOff[k] then
                    lea[k] = "On"
                    db.leatrixOff[k] = nil
                end
            end
        end
    end
    if #turnedOff > 0 then
        -- kurz Bescheid geben (nach dem Laden, damit der Chat schon da ist)
        C_Timer.After(6, function()
            for _, d in ipairs(turnedOff) do
                UI.Chat("Forever", string.format(T("Leatrix Plus: „%s“ ausgeschaltet – %s übernimmt das. Umstellen: /forever » Andere Addons.",
                    "Leatrix Plus: \"%s\" turned off – %s handles that. Change it: /forever » Other addons."), d.feature, d.forever))
            end
        end)
    end
end
do
    local lf = CreateFrame("Frame")
    lf:RegisterEvent("ADDON_LOADED")
    lf:SetScript("OnEvent", function(self, _, name)
        if name == LEATRIX then
            pcall(ApplyLeatrix)
            self:UnregisterAllEvents()
        end
    end)
end

local function AddonTitle(name)
    local ok, _, title = pcall(C_AddOns.GetAddOnInfo, name)
    title = ok and title or name
    return (tostring(title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Paare, bei denen beide installiert sind: { c = Eintrag, other = Name }
local function ConflictPairs()
    local list = {}
    for _, c in ipairs(ConflictDefs()) do
        if IsInstalled(c.forever) then
            for _, other in ipairs(c.others) do
                if IsInstalled(other) then list[#list + 1] = { c = c, other = other } end
            end
        end
    end
    -- Leatrix Plus: einzelne Funktionen statt des ganzen Addons
    if IsInstalled(LEATRIX) then
        for _, d in ipairs(LeatrixDefs()) do
            if IsInstalled(d.forever) then list[#list + 1] = { c = d, other = LEATRIX, leatrix = d } end
        end
    end
    return list
end

-- noch ungeklärt: beide eingeschaltet
local function OpenConflicts()
    local n = {}
    for _, p in ipairs(ConflictPairs()) do
        if not p.leatrix and IsEnabled(p.c.forever) and IsEnabled(p.other) then n[#n + 1] = p end
    end
    return n
end
UI.OpenConflicts = OpenConflicts

local conflictWindow
local CONFLICT_ROW_H = 52

local function BuildConflictWindow()
    local pairsList = ConflictPairs()
    local f = UI.Window("ForeverHubConflicts", T("Andere Addons erkannt", "Other addons detected"), 460,
        26 + 64 + math.max(#pairsList, 1) * CONFLICT_ROW_H + 52)
    f:SetFrameStrata("DIALOG")
    conflictWindow = f
    f.rows = {}
    local intro = UI.Hint(f, 16, -34, 428, T("Für diese Aufgaben hast du schon ein anderes Addon. Wähle je Zeile, welches laufen soll – das andere wird ausgeschaltet (gilt nach „Neu laden“, jederzeit hier umkehrbar).",
        "You already use another addon for these tasks. Pick which one should run in each row – the other one is turned off (applies after \"Reload\", you can switch back here any time)."))
    intro:SetWordWrap(true)

    local reload = UI.Button(f, T("Neu laden", "Reload"), 110, function() ReloadUI() end)
    reload:SetPoint("BOTTOMRIGHT", -14, 14)
    reload:GetFontString():SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    local close = UI.Button(f, T("Später", "Later"), 90, function() f:Hide() end)
    close:SetPoint("BOTTOMLEFT", 14, 14)

    local function Refresh()
        local pending = f.needReload or false -- (Leatrix-Wahl gilt ebenfalls erst nach dem Neuladen)
        for _, row in ipairs(f.rows) do
            row.Update()
            if IsPending(row.pair.c.forever) or IsPending(row.pair.other) then pending = true end
        end
        reload:SetShown(pending)
    end
    f.Refresh = Refresh

    local top = -26 - 64
    for i, p in ipairs(pairsList) do
        local row = CreateFrame("Frame", nil, f)
        row.pair = p
        row:SetHeight(CONFLICT_ROW_H)
        row:SetPoint("TOPLEFT", 10, top - (i - 1) * CONFLICT_ROW_H)
        row:SetPoint("TOPRIGHT", -10, top - (i - 1) * CONFLICT_ROW_H)
        if i > 1 then
            local sep = row:CreateTexture(nil, "ARTWORK")
            sep:SetColorTexture(1, 1, 1, 0.06)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", 4, 0)
            sep:SetPoint("TOPRIGHT", -4, 0)
        end
        row.topic = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.topic:SetPoint("TOPLEFT", 8, -6)
        row.topic:SetText(p.c.topic)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.status:SetPoint("LEFT", row.topic, "RIGHT", 10, 0)
        local otherTitle = AddonTitle(p.other)
        if p.leatrix then otherTitle = "Leatrix Plus: " .. p.leatrix.feature end
        -- Wahl: Forever-Addon nutzen (anderes aus) oder das andere (Forever-Addon aus)
        row.useForever = UI.Button(row, p.c.forever, 200, function()
            SetEnabled(p.c.forever, true)
            if not p.leatrix then SetEnabled(p.other, false) end -- Leatrix bleibt an, nur die Funktion geht aus
            GetDB().conflictChoice = GetDB().conflictChoice or {}
            GetDB().conflictChoice[p.c.forever .. ">" .. p.other] = "forever"
            f.needReload = true
            Refresh()
        end)
        row.useForever:SetPoint("BOTTOMLEFT", 6, 6)
        row.useOther = UI.Button(row, otherTitle, 200, function()
            if not p.leatrix then SetEnabled(p.other, true) end
            SetEnabled(p.c.forever, false)
            GetDB().conflictChoice = GetDB().conflictChoice or {}
            GetDB().conflictChoice[p.c.forever .. ">" .. p.other] = "other"
            f.needReload = true
            Refresh()
        end)
        row.useOther:SetPoint("LEFT", row.useForever, "RIGHT", 12, 0)
        function row.Update()
            local fe, oe = IsEnabled(p.c.forever), IsEnabled(p.other)
            local pending = IsPending(p.c.forever) or IsPending(p.other)
            if p.leatrix then
                -- Leatrix-Funktion: läuft, wenn man "Leatrix" gewählt hat oder das Forever-Addon aus ist
                local choice = (GetDB().conflictChoice or {})[p.c.forever .. ">" .. p.other]
                oe = oe and (choice == "other" or not fe)
                fe = fe and not oe
                pending = IsPending(p.c.forever)
            end
            local text
            if fe and oe then
                text = "|cffff8040" .. T("beide aktiv – bitte wählen", "both active – please choose") .. "|r"
            elseif fe then
                text = T("aktiv: ", "active: ") .. p.c.forever
            elseif oe then
                text = T("aktiv: ", "active: ") .. otherTitle
            else
                text = T("beide aus", "both off")
            end
            if pending then text = text .. "  |cffffd100" .. T("(nach Neuladen)", "(after reload)") .. "|r" end
            row.status:SetText(text)
            -- gewählte Seite in Gold
            row.useForever:GetFontString():SetTextColor(fe and C.accent[1] or 0.85, fe and C.accent[2] or 0.85, fe and C.accent[3] or 0.85)
            row.useOther:GetFontString():SetTextColor(oe and C.accent[1] or 0.85, oe and C.accent[2] or 0.85, oe and C.accent[3] or 0.85)
        end
        f.rows[i] = row
    end
    if #pairsList == 0 then
        UI.Hint(f, 16, top - 6, 428, T("Keine anderen Addons für dieselben Aufgaben gefunden.", "No other addons for the same tasks found."))
    end
    f:SetScript("OnShow", Refresh)
end

function UI.ShowConflicts(nextToHub)
    if not conflictWindow then BuildConflictWindow() end
    conflictWindow:ClearAllPoints()
    if nextToHub and hubWindow and hubWindow:IsShown() then
        conflictWindow:SetPoint("TOPLEFT", hubWindow, "TOPRIGHT", 8, 0)
    else
        conflictWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
    conflictWindow:Show()
    if conflictWindow.Refresh then conflictWindow.Refresh() end
end

-- nach dem Start: ungeklärte Paare, nach denen noch nie gefragt wurde -> einmal fragen
local function MaybeAskConflicts(withWelcome)
    local open = OpenConflicts()
    if #open == 0 then return end
    local db = GetDB()
    db.conflictAsked = db.conflictAsked or {}
    local new = false
    for _, p in ipairs(open) do
        local key = p.c.forever .. ">" .. p.other
        if not db.conflictAsked[key] then
            db.conflictAsked[key] = true
            new = true
        end
    end
    if new or withWelcome then UI.ShowConflicts(withWelcome) end
end

local function MaybeWelcome()
    if _G.ForeverHub ~= hub or InCombatLockdown() then return end -- im Kampf: beim naechsten Laden
    local db = GetDB()
    -- seit v71: Einrichtungsassistent (Setup.lua) einmal je Charakter (ForeverHubDB.setupDone["Name-Realm"]); sofort
    -- merken, damit er auch nach einfachem Schließen nicht wiederkommt. Die Frage nach anderen Addons kommt am Ende.
    local charKey = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    db.setupDone = db.setupDone or {}
    if UI.ShowSetup and not db.setupDone[charKey] then
        db.setupDone[charKey] = true
        local first = not db.welcomeDone
        db.welcomeDone = true
        UI.ShowSetup(function() pcall(MaybeAskConflicts, first) end)
        return
    end
    if db.welcomeDone then
        pcall(MaybeAskConflicts, false) -- neues Addon-Paar seit dem letzten Mal? einmal fragen
        return
    end
    db.welcomeDone = true -- sofort merken: erscheint auch dann nie wieder, wenn man es einfach schliesst
    hub.ShowWelcome()
    pcall(MaybeAskConflicts, true) -- beim ersten Start: als einzige Frage gleich neben der Begrüßung
end
events:HookScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(4, function() pcall(MaybeWelcome) end) end
end)

---------------------------------------------------------------------------
-- 4. Blizzard-Optionsmenue (Reiter "AddOns"): Eintrag "Forever Core UI" mit Uebersicht und je Addon
-- eine Unterseite mit Knopf ins eigene Einstellungsfenster. Die Fenster selbst bleiben eigenstaendig.
---------------------------------------------------------------------------
local settingsCategory
local settingsPages = {} -- [Addon-Name] = true, sobald eingetragen

-- Optionsmenue schliessen (nur ausserhalb des Kampfes) und das Addon-Fenster oeffnen
local function OpenFromSettings(name)
    if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
    if name then OpenAddon(EntryOf(name)) else hub.ToggleWindow() end
end

local function NotesOf(name)
    local ok, _, _, notes = pcall(C_AddOns.GetAddOnInfo, name)
    return ok and notes or ""
end

-- Kopf einer Seite: Logo/Symbol, Titel, Untertitel
local function PageHeader(page, icon, title, subtitle)
    local ic = page:CreateTexture(nil, "ARTWORK")
    ic:SetSize(32, 32)
    ic:SetPoint("TOPLEFT", 16, -16)
    ic:SetTexture(icon)
    local t = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", ic, "TOPRIGHT", 10, -1)
    t:SetText(title)
    local s = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
    s:SetPoint("RIGHT", page, "RIGHT", -16, 0)
    s:SetJustifyH("LEFT")
    s:SetText(subtitle or "")
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 16, -60)
    line:SetPoint("TOPRIGHT", -16, -60)
end

-- Uebersichtsseite "Forever Core UI": alle geladenen Forever-Addons mit "Öffnen"
local function BuildOverview()
    local page = CreateFrame("Frame")
    PageHeader(page, UI.LOGO, UI.NAME, "Less clutter. More control. Just the essentials.")
    UI.Hint(page, 16, -72, 560, T("Jedes Forever-Addon hat ein eigenes Einstellungsfenster. Hier öffnest du es direkt "
        .. "– oder über die Unterpunkte links, den Minimap-Knopf bzw. /forever.",
        "Every Forever addon has its own settings window. Open it right here – or via the entries on the left, "
        .. "the minimap button or /forever."))
    page.rows = {}
    local function Refresh()
        for i, e in ipairs(entries) do
            local row = page.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, page)
                row:SetSize(560, 30)
                row:SetPoint("TOPLEFT", 16, -112 - (i - 1) * 32)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", 4, 0)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                row.label:SetWidth(130)
                row.label:SetJustifyH("LEFT")
                row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.note:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
                row.note:SetPoint("RIGHT", row, "RIGHT", -96, 0)
                row.note:SetJustifyH("LEFT")
                row.note:SetWordWrap(false)
                row.open = UI.Button(row, T("Öffnen", "Open"), 84)
                row.open:SetPoint("RIGHT", -4, 0)
                page.rows[i] = row
            end
            row.icon:SetTexture(e.icon)
            row.label:SetText(e.name)
            row.note:SetText(NotesOf(e.name))
            row.open:SetScript("OnClick", function() OpenFromSettings(e.name) end)
            row:Show()
        end
        for i = #entries + 1, #page.rows do page.rows[i]:Hide() end
    end
    page:SetScript("OnShow", Refresh)

    local hubBtn = UI.Button(page, T("Hub-Fenster öffnen", "Open hub window"), 150, function() OpenFromSettings(nil) end)
    hubBtn:SetPoint("BOTTOMLEFT", 16, 16)
    local move = UI.Button(page, T("Alle verschieben/sperren", "Move/lock all"), 170, function()
        if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
        UI.MoveAll()
    end)
    move:SetPoint("LEFT", hubBtn, "RIGHT", 8, 0)
    return page
end

-- Unterseite eines Addons: Beschreibung, Knopf ins Einstellungsfenster, Chatbefehl
local function BuildAddonPage(e)
    local page = CreateFrame("Frame")
    PageHeader(page, e.icon, e.name, NotesOf(e.name))
    local open = UI.Button(page, T("Einstellungen öffnen", "Open settings"), 180, function() OpenFromSettings(e.name) end)
    open:SetHeight(26)
    open:SetPoint("TOPLEFT", 16, -76)
    if e.cmd then
        local hint = UI.Hint(page, nil, nil, nil, string.format(T("Auch im Chat: %s", "Also in chat: %s"), e.cmd))
        hint:SetPoint("LEFT", open, "RIGHT", 12, 0)
    end
    UI.Hint(page, 16, -114, 560, T("Die Einstellungen öffnen sich im eigenen Forever-Fenster, damit du beim Einstellen "
        .. "das Spiel siehst.", "Settings open in their own Forever window so you can see the game while adjusting them."))
    return page
end

RegisterSettings = function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    if #entries == 0 and not CoreLoaded() then return end
    if not settingsCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(BuildOverview(), UI.NAME)
        Settings.RegisterAddOnCategory(settingsCategory)
    end
    if not Settings.RegisterCanvasLayoutSubcategory then return end
    for _, e in ipairs(entries) do
        if not settingsPages[e.name] then
            settingsPages[e.name] = true
            Settings.RegisterCanvasLayoutSubcategory(settingsCategory, BuildAddonPage(e), e.name)
        end
    end
end

---------------------------------------------------------------------------
-- 5. Addon-Menue an der Minimap (Retail: Knopf neben der Minimap mit allen Addons ohne eigenen Knopf).
-- Ein einziger Eintrag "Forever Core UI" fuer alle Forever-Addons: Linksklick Hub-Fenster, Rechtsklick
-- alle Rahmen verschieben/sperren. Gibt es das Menue im Client nicht, passiert nichts.
---------------------------------------------------------------------------
RegisterCompartment = function()
    if SHARED.compartment or (#entries == 0 and not CoreLoaded()) then return end
    local menu = _G.AddonCompartmentFrame
    if not (menu and menu.RegisterAddon) then return end
    SHARED.compartment = true
    local ok = pcall(menu.RegisterAddon, menu, {
        text = UI.NAME,
        icon = UI.LOGO,
        notCheckable = true,
        -- je nach Client-Version: (Knopfname, …) oder (…, { buttonName = … })
        func = function(a, b)
            local mouseButton = type(a) == "string" and a or (type(b) == "table" and b.buttonName) or "LeftButton"
            local current = _G.ForeverHub
            if mouseButton == "RightButton" then
                current.UI.MoveAll()
            elseif current.ToggleWindow then
                current.ToggleWindow()
            end
        end,
        funcOnEnter = function(button)
            GameTooltip:SetOwner(button or UIParent, "ANCHOR_LEFT")
            GameTooltip:AddLine(UI.NAME)
            GameTooltip:AddLine(T("Linksklick: alle Forever-Addons", "Left-click: all Forever addons"), 1, 1, 1)
            GameTooltip:AddLine(T("Rechtsklick: alle Rahmen verschieben/sperren", "Right-click: move/lock all frames"), 1, 1, 1)
            GameTooltip:Show()
        end,
        funcOnLeave = function() GameTooltip:Hide() end,
    })
    if not ok then SHARED.compartment = nil end
end

-- Blizzard-Optionsmenue direkt bei "Forever Core UI" oeffnen (fuer /forever options)
function hub.OpenSettings()
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

-- Knopf "Forever Core UI" (früher "Forever Core UI") am Spielmenue (Escape): ein EIGENER Knopf direkt unter dem Menue – nicht in Blizzards
-- Knopfliste. (Frueher per GameMenuFrame:AddButton eingehaengt: das machte die Knoepfe des Menues "von einem Addon
-- beruehrt", und Blizzard blockierte danach geschuetzte Aktionen daraus – ADDON_ACTION_FORBIDDEN "callback()".)
-- Spielmenü im Forever-Stil (v61): Blizzards Rahmen, Kopf und rote Knopfgrafiken werden nur unsichtbar gemacht
-- (SetAlpha) – Knöpfe, Reihenfolge und Funktionen bleiben Blizzards eigene, nichts wird in ihre Tabellen
-- geschrieben. Dahinter liegt eine eigene flache Fläche (Titelleiste mit goldener Linie, flache Knöpfe wie im Hub),
-- unten darin mit Trennlinie der Hub-Knopf. Nicht, wenn ElvUI das Menü schon umgestaltet.
do
    local menu = _G.GameMenuFrame
    if menu and menu.HookScript then
        local b, skin, menuFont
        local backs =setmetatable({}, { __mode = "k" })  -- [Blizzard-Knopf] = unsere flache Fläche dahinter
        local function OpenHub()
            if _G.ForeverHub ~= hub then return end
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end
            HideUIPanel(menu)
            hub.ToggleWindow()
        end
        local function Skinned()
            local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
            return not (loaded and loaded("ElvUI"))
        end
        local function Hide(obj) if obj and obj.SetAlpha then obj:SetAlpha(0) end end
        local function MenuButtons()
            local list = {}
            for _, c in ipairs({ menu:GetChildren() }) do
                if c:IsObjectType("Button") and c:IsShown() and c ~= menu.CloseButton and c:GetText() then
                    list[#list + 1] = c
                end
            end
            return list
        end
        local function Back(button)
            local back = backs[button]
            if not back then
                back = CreateFrame("Frame", nil, skin, "BackdropTemplate")
                UI.SetFlat(back, C.button)
                backs[button] = back
            end
            back:ClearAllPoints()
            back:SetAllPoints(button)
            if not back.hl then
                back.hl = back:CreateTexture(nil, "ARTWORK")
                back.hl:SetPoint("TOPLEFT", 1, -1)
                back.hl:SetPoint("BOTTOMRIGHT", -1, 1)
                back.hl:SetColorTexture(1, 1, 1, 0.06)
            end
            back.hover = nil
            back.hl:Hide()
            back:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
            back:Show()
        end
        -- Maus über einem Knopf: goldener Rand und leichte Aufhellung wie beim Forever-Core-UI-Knopf. Ohne Haken an
        -- Blizzards Knöpfen – solange das Menü offen ist, schaut die Fläche selbst nach, wo die Maus ist.
        local function UpdateHover()
            for button, back in pairs(backs) do
                local over = back:IsShown() and button:IsShown() and button:IsMouseOver() or false
                if over ~= (back.hover or false) then
                    back.hover = over
                    back.hl:SetShown(over)
                    local c = over and C.accent or C.border
                    back:SetBackdropBorderColor(c[1], c[2], c[3], over and 0.9 or 1)
                end
            end
        end
        local function BuildSkin()
            skin = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            UI.SetFlat(skin, C.background)
            skin:EnableMouse(false)
            skin:SetScript("OnUpdate", UpdateHover) -- läuft nur, solange das Menü (und damit die Fläche) sichtbar ist
            local head = skin:CreateTexture(nil, "ARTWORK")
            head:SetPoint("TOPLEFT", 1, -1)
            head:SetPoint("TOPRIGHT", -1, -1)
            head:SetHeight(26)
            head:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
            local line = skin:CreateTexture(nil, "ARTWORK", nil, 2)
            line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
            line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
            line:SetHeight(1)
            line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
            skin.title = skin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            skin.title:SetPoint("CENTER", head, "CENTER")
            skin.divider = skin:CreateTexture(nil, "ARTWORK")
            skin.divider:SetHeight(1)
            skin.divider:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
        end
        local function Layout()
            local buttons = MenuButtons()
            local first, last
            for _, btn in ipairs(buttons) do
                if not last or (btn:GetBottom() or 0) < (last:GetBottom() or 0) then last = btn end
                if not first or (btn:GetTop() or 0) > (first:GetTop() or 0) then first = btn end
            end
            local style = Skinned() and last ~= nil
            if style then
                if not skin then BuildSkin() end
                -- Blizzards Rahmen, Kopf und Hintergrund unsichtbar (die Knöpfe selbst bleiben bedienbar)
                for _, r in ipairs({ menu:GetRegions() }) do if r:IsObjectType("Texture") then Hide(r) end end
                Hide(menu.Border)
                Hide(menu.Header)
                for _, back in pairs(backs) do back:Hide() end
                for _, btn in ipairs(buttons) do
                    for _, r in ipairs({ btn:GetRegions() }) do if r:IsObjectType("Texture") then Hide(r) end end
                    Hide(btn:GetNormalTexture())
                    Hide(btn:GetPushedTexture())
                    Hide(btn:GetHighlightTexture())
                    Hide(btn:GetDisabledTexture())
                    Back(btn)
                end
                local title = menu.Header and menu.Header.Text and menu.Header.Text:GetText()
                skin.title:SetText(title or _G.MAINMENU_BUTTON or "Menu")
                skin:SetFrameStrata(menu:GetFrameStrata())
                skin:SetFrameLevel(math.max(1, menu:GetFrameLevel() - 1)) -- hinter dem Menü
            end
            -- Hub-Knopf: im Forever-Stil unter dem letzten Knopf in derselben Fläche, sonst wie bisher unter dem Menü
            if not b then
                b = UI.Button(UIParent, UI.NAME, 150, OpenHub) -- "Forever Core UI"
                -- Forever-Core-UI-Symbol links vor dem Text (Text dafür etwas nach rechts)
                local label = b:GetFontString()
                if label then
                    label:ClearAllPoints()
                    label:SetPoint("CENTER", 10, 0)
                    local logo = b:CreateTexture(nil, "OVERLAY")
                    logo:SetTexture(UI.LOGO)
                    logo:SetSize(16, 16)
                    logo:SetPoint("RIGHT", label, "LEFT", -6, 0)
                end
            end
            b:SetFrameStrata(menu:GetFrameStrata())
            b:SetFrameLevel(menu:GetFrameLevel() + 5)
            b:ClearAllPoints()
            if style then
                b:SetSize(last:GetWidth(), last:GetHeight())
                b:SetPoint("TOP", last, "BOTTOM", 0, -19)
                -- gleiche Schrift wie Blizzards Knöpfe
                -- (als Schriftobjekt, sonst setzt der Knopf beim Überfahren wieder seine kleine Schrift)
                local theirs = last:GetFontString()
                if theirs and theirs:GetFont() then
                    local font, size, flags = theirs:GetFont()
                    menuFont = menuFont or CreateFont("ForeverCoreGameMenuFont")
                    menuFont:SetFont(font, size, flags or "")
                    menuFont:SetTextColor(theirs:GetTextColor())
                    b:SetNormalFontObject(menuFont)
                    b:SetHighlightFontObject(menuFont)
                end
                skin.divider:ClearAllPoints()
                skin.divider:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -9)
                skin.divider:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -9)
                -- Fläche nach den Knöpfen ausgerichtet (nicht nach Blizzards Rahmen): Titelleiste, darunter rundum
                -- derselbe Abstand von 14 px zu den Knöpfen
                local GAP = 14
                skin:ClearAllPoints()
                skin:SetPoint("TOPLEFT", first, "TOPLEFT", -GAP - 4, 27 + GAP)
                skin:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", GAP + 4, -GAP - 4)
                skin:Show()
            else
                b:SetSize(150, 22)
                b:SetPoint("TOP", menu, "BOTTOM", 0, -6)
                if skin then skin:Hide() end
            end
            b:Show()
        end
        menu:HookScript("OnShow", function()
            if _G.ForeverHub ~= hub then return end
            Layout()
            C_Timer.After(0, function() if menu:IsShown() then Layout() end end) -- nach Blizzards Aufbau der Knöpfe
        end)
        menu:HookScript("OnHide", function()
            if b then b:Hide() end
            if skin then skin:Hide() end
        end)
    end
end

-- /forever: Hub-Fenster · /forever reset: Sammelknopf zuruecksetzen und wieder an die Minimap holen
SLASH_FOREVERHUB1 = "/forever"
SLASH_FOREVERHUB2 = "/fhub"
SlashCmdList["FOREVERHUB"] = function(msg)
    if _G.ForeverHub ~= hub then return end
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        local db = GetDB()
        db.angle = 195
        db.hideButton = nil
        SafeSetup()
        if hubButton then hubButton.UpdatePosition() end
        UI.Chat("Forever", active
            and T("Sammelknopf zurückgesetzt.", "Collector button reset.")
            or T("Minimap-Knöpfe wieder eingeblendet.", "Minimap buttons shown again."))
    elseif msg == "options" or msg == "optionen" then
        hub.OpenSettings()
    elseif msg == "profile" or msg == "profiles" then
        UI.ShowProfiles()
    elseif msg == "export" then
        UI.ShowTransfer("export")
    elseif msg == "import" then
        UI.ShowTransfer("import")
    elseif msg == "leistung" or msg == "performance" or msg == "perf" then
        UI.ShowPerformance()
    elseif msg == "einrichtung" or msg == "setup" then
        if UI.ShowSetup then UI.ShowSetup() end
    else
        hub.ToggleWindow()
    end
end

-- /forever leistung: Rechenzeit und Speicher je geladenem Forever-Addon im Chat (liest nur, ändert nichts).
-- Rechenzeit über C_AddOnProfiler (falls der Client es anbietet): Schnitt der letzten Sekunden, Schnitt der Sitzung und
-- Spitze in Millisekunden je Bild; Speicher über GetAddOnMemoryUsage
function UI.ShowPerformance()
    local P = C_AddOnProfiler
    local M = Enum and Enum.AddOnProfilerMetric
    local hasProfiler = P and P.GetAddOnMetric and M ~= nil
    if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
    local rows = {}
    local num = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or 0
    for i = 1, num do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and name:find("^Forever") and C_AddOns.IsAddOnLoaded(name) then
            local row = { name = name }
            if hasProfiler then
                local function Metric(key)
                    if not M[key] then return nil end
                    local ok, v = pcall(P.GetAddOnMetric, name, M[key])
                    return ok and type(v) == "number" and v or nil
                end
                row.recent, row.session, row.peak = Metric("RecentAverageTime"), Metric("SessionAverageTime"), Metric("PeakTime")
                -- wie oft ein Bild über 50 bzw. 100 ms brauchte (einmal = Lade-Hänger, steigend = Ruckler im Spiel)
                row.over50, row.over100 = Metric("CountTimeOver50Ms"), Metric("CountTimeOver100Ms")
            end
            local ok, kb = pcall(GetAddOnMemoryUsage, name)
            row.kb = ok and type(kb) == "number" and kb or nil
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b) return (a.recent or a.kb or 0) > (b.recent or b.kb or 0) end)
    UI.Chat("Forever", T("Leistung der Forever-Addons", "Performance of the Forever addons")
        .. (hasProfiler and T(" (ms je Bild: aktuell / Sitzung / Spitze (Bilder über 50/100 ms), Speicher – Spitzen gelten seit dem Spielstart, auch über /reload)",
            " (ms per frame: recent / session / peak (frames over 50/100 ms), memory – peaks count since the game started, also across /reload)")
            or T(" (Rechenzeit misst dieser Client nicht – nur Speicher)", " (this client doesn't measure CPU time – memory only)")))
    local function MS(v) return v and string.format("%.2f", v) or "–" end
    for _, r in ipairs(rows) do
        local mem = r.kb and (r.kb >= 1024 and string.format("%.1f MB", r.kb / 1024) or string.format("%d KB", r.kb)) or "–"
        local over = (r.over50 or r.over100) and string.format("  (%s/%s)", r.over50 and math.floor(r.over50) or "–",
            r.over100 and math.floor(r.over100) or "–") or ""
        local cpu = hasProfiler and (MS(r.recent) .. " / " .. MS(r.session) .. " / " .. MS(r.peak) .. over .. "  ·  ") or ""
        print(string.format("   |cffffcc00%s|r  %s%s", r.name, cpu, mem))
    end
end

---------------------------------------------------------------------------
-- 8. Einstellungen fuer alle Forever-Addons: Profile, Versionen, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
-- Jedes Addon meldet seine SavedVariable beim Laden der Datei an (Grundlage: Profile aus ForeverBars):
--   UI.RegisterSettings({
--       addon = "ForeverXP", sv = "ForeverXPDB",   -- Addon-Name und Name der SavedVariable
--       defaults = DEFAULTS,                        -- optional: Standardwerte (prueft Importe auf passende Typen)
--       version = 1,                                -- Aufbau-Version der Einstellungen (bei Umbauten erhoehen)
--       migrate = function(data, fromVersion) end,  -- optional: aeltere Profile umrechnen
--       global = { "showMinimapButton" },           -- gelten fuer alle Profile (minimapAngle immer)
--       keepOnReset = { "clicks" },                 -- optional: bleiben beim Zuruecksetzen erhalten
--       reset = function() end,                     -- optional: eigenes Zuruecksetzen ohne Neuladen
--   })
-- Arbeitsweise (kein Addon braucht eigenen Umschalt-Code):
--   * Die Tabelle des Addons enthaelt immer die Einstellungen des gerade aktiven Profils. Profile liegen
--     in tabelle._fc (Schluessel mit "_" gehoeren nie ins Profil).
--   * Jeder Charakter nutzt das gemeinsame Profil ("Standard") oder auf Wunsch ein eigenes.
--   * Wechseln, Zuruecksetzen und Importieren gelten nach dem Neuladen: beim Laden (ADDON_LOADED, bevor das
--     Addon seine Einstellungen liest) wird das richtige Profil in die Tabelle geschrieben – in dieselbe Tabelle.
--   * Export: ein Text fuer mehrere Addons ("FC1:" + CBOR, komprimiert, Base64 ueber C_EncodingUtil).
--     Importe sind reine Daten (kein Programmcode); nur einfache Werte mit passenden Typen werden uebernommen.
SHARED.settings = SHARED.settings or {}
SHARED.settingsOrder = SHARED.settingsOrder or {}
local SETTINGS, SETTINGS_ORDER = SHARED.settings, SHARED.settingsOrder
local DEFAULT_PROFILE = "Default"
UI.DEFAULT_PROFILE = DEFAULT_PROFILE

local function CharKey()
    local name = UnitName("player")
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. (GetRealmName and GetRealmName() or "")
end

local function CharName()
    local name = UnitName("player")
    return type(name) == "string" and name or "?"
end

function UI.ProfileLabel(name)
    if name == DEFAULT_PROFILE then return T("Standard", "Default") end
    return tostring(name)
end

local function IsGlobal(o, key)
    if type(key) ~= "string" then return false end
    return key:sub(1, 1) == "_" or o.globalSet[key] == true
end

-- nur einfache Werte (Text, Zahl, ja/nein) und Tabellen daraus; Tiefe begrenzt
local function CleanCopy(v, depth)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" or depth > 20 then return nil end
    local out = {}
    for k, val in pairs(v) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            local c = CleanCopy(val, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end

-- Profil-Kopie der aktuellen Einstellungen (ohne globale und "_"-Schluessel)
local function Snapshot(o, live, version)
    local copy = {}
    for k, v in pairs(live) do
        if not IsGlobal(o, k) then copy[k] = CleanCopy(v, 1) end
    end
    copy._v = version or o.version
    return copy
end

local function Fc(live)
    local fc = live._fc
    if type(fc) ~= "table" then fc = {} live._fc = fc end
    if type(fc.profiles) ~= "table" then fc.profiles = {} end
    if type(fc.chars) ~= "table" then fc.chars = {} end
    if type(fc.shared) ~= "string" then fc.shared = DEFAULT_PROFILE end
    return fc
end

-- Profil in die Tabelle des Addons schreiben (gleiche Tabelle; globale Schluessel bleiben, aeltere Profile
-- werden umgerechnet)
local function LoadInto(o, live, data)
    for k in pairs(live) do
        if not IsGlobal(o, k) then live[k] = nil end
    end
    local copy = CleanCopy(data or {}, 1) or {}
    local from = tonumber(copy._v) or 0
    copy._v = nil
    if o.migrate and from < o.version then
        local ok, err = pcall(o.migrate, copy, from)
        if not ok then UI.ReportError(o.addon, "Settings", err) end
    end
    for k, v in pairs(copy) do
        if not IsGlobal(o, k) then live[k] = v end
    end
end

-- welches Profil dieser Charakter laden soll (eigenes, sonst das gemeinsame)
local function WantedProfile(fc, key)
    local own = key and fc.chars[key]
    if own and fc.profiles[own] then return own end
    if key then fc.chars[key] = nil end
    if not fc.profiles[fc.shared] then fc.shared = DEFAULT_PROFILE end
    return fc.shared
end

-- Importe: nur einfache Werte; wo ein Standardwert existiert, muss der Typ passen
local function Filter(o, data, version)
    local out = {}
    if type(data) == "table" then
        for k, v in pairs(data) do
            if type(k) == "string" and not IsGlobal(o, k) then
                local d = o.defaults and o.defaults[k]
                if d == nil or type(d) == type(v) then
                    local c = CleanCopy(v, 1)
                    if c ~= nil then out[k] = c end
                end
            end
        end
    end
    out._v = tonumber(version) or 0
    return out
end

-- beim Laden des Addons: richtiges Profil in seine Tabelle schreiben
local function Activate(o)
    if o.ready then return end
    local live = _G[o.sv]
    if type(live) ~= "table" then live = {} _G[o.sv] = live end
    local fresh = type(live._fc) ~= "table"
    local fc = Fc(live)
    if fresh and o.legacy then -- z. B. ForeverBars: bisherige eigene Profile uebernehmen
        local ok, err = pcall(o.legacy, live, fc)
        if not ok then UI.ReportError(o.addon, "Settings", err) end
    end
    -- Die Tabelle enthaelt den Stand des zuletzt aktiven Profils: zuerst dort sichern
    -- (beim ersten Start mit dem Baustein werden die bisherigen Einstellungen das gemeinsame Profil)
    if fc.discardActive then
        fc.discardActive = nil
    else
        fc.profiles[fc.active or fc.shared] = Snapshot(o, live, fc.v or 0)
    end
    if not fc.profiles[DEFAULT_PROFILE] then fc.profiles[DEFAULT_PROFILE] = { _v = o.version } end
    local key = CharKey()
    local pend = fc.pending
    fc.pending = nil
    if type(pend) == "table" then
        if type(pend.reset) == "string" and fc.profiles[pend.reset] then
            local old, new = fc.profiles[pend.reset], { _v = o.version }
            for _, k in ipairs(o.keepOnReset or {}) do new[k] = old[k] end
            fc.profiles[pend.reset] = new
        end
        if type(pend.import) == "table" and type(pend.importName) == "string" then
            fc.profiles[pend.importName] = pend.import
            if pend.forChar and pend.forChar == key then fc.chars[key] = pend.importName end
        end
    end
    local wanted = WantedProfile(fc, key)
    LoadInto(o, live, fc.profiles[wanted])
    fc.active = wanted
    fc.v = o.version
    o.ready = true
end

local settingsEvents = CreateFrame("Frame")
settingsEvents:RegisterEvent("ADDON_LOADED")
settingsEvents:SetScript("OnEvent", function(_, _, name)
    -- o.loadAddon: Modul in einem gemeinsamen Addon (z. B. ForeverLoot in ForeverHelpers) – Name der Einstellungen bleibt
    for _, addon in ipairs(SETTINGS_ORDER) do
        local o = SETTINGS[addon]
        if o and not o.ready and (o.loadAddon or o.addon) == name then
            local ok, err = pcall(Activate, o)
            if not ok then UI.ReportError(addon, "Settings", err) end
        end
    end
end)

function UI.RegisterSettings(o)
    if type(o) ~= "table" or type(o.addon) ~= "string" or type(o.sv) ~= "string" then return end
    o.version = o.version or 1
    o.globalSet = { minimapAngle = true }
    for _, k in ipairs(o.global or {}) do o.globalSet[k] = true end
    if not SETTINGS[o.addon] then tinsert(SETTINGS_ORDER, o.addon) end
    SETTINGS[o.addon] = o
end

-- angemeldet und geladen: Beschreibung, Tabelle, Profil-Verwaltung
local function Ready(addon)
    local o = SETTINGS[addon]
    if not (o and o.ready and type(_G[o.sv]) == "table") then return end
    local live = _G[o.sv]
    return o, live, Fc(live)
end

function UI.SettingsAddons()
    local list = {}
    for _, addon in ipairs(SETTINGS_ORDER) do
        if Ready(addon) then list[#list + 1] = addon end
    end
    return list
end

-- Profilnamen eines Addons (Standard zuerst, dann alphabetisch)
function UI.ProfileNames(addon)
    local _, _, fc = Ready(addon)
    local names = {}
    if not fc then return names end
    for name in pairs(fc.profiles) do
        if name ~= DEFAULT_PROFILE then names[#names + 1] = name end
    end
    table.sort(names)
    tinsert(names, 1, DEFAULT_PROFILE)
    return names
end

-- aktives Profil dieses Charakters; own = true, wenn er ein eigenes hat
function UI.CurrentProfile(addon)
    local _, _, fc = Ready(addon)
    if not fc then return nil end
    local key = CharKey()
    return fc.active, key and fc.chars[key] ~= nil, fc.shared
end

-- gilt nach dem Neuladen? (Wahl weicht vom geladenen Profil ab)
function UI.ProfilePending(addon)
    local _, _, fc = Ready(addon)
    if not fc then return false end
    if fc.pending or fc.discardActive then return true end
    local key = CharKey()
    local own = key and fc.chars[key]
    local wanted = (own and fc.profiles[own]) and own or fc.shared
    return wanted ~= fc.active
end

-- Profil fuer diesen Charakter waehlen (nil = gemeinsames Profil); gilt nach dem Neuladen
function UI.UseProfile(addon, name)
    local _, _, fc = Ready(addon)
    local key = CharKey()
    if not (fc and key) then return end
    if name and fc.profiles[name] then fc.chars[key] = name else fc.chars[key] = nil end
end

-- Neues Profil aus den aktuellen Einstellungen; gilt sofort fuer diesen Charakter (kein Neuladen noetig)
function UI.NewProfile(addon, name)
    local o, live, fc = Ready(addon)
    local key = CharKey()
    name = strtrim(tostring(name or ""))
    if not (o and key) or name == "" then return false end
    if fc.active and not fc.discardActive then fc.profiles[fc.active] = Snapshot(o, live) end
    fc.profiles[name] = Snapshot(o, live)
    fc.chars[key] = name
    if not fc.discardActive and not fc.pending then fc.active = name end
    return true
end

-- Profil loeschen (Standard bleibt); Charaktere damit nutzen danach das gemeinsame Profil
function UI.DeleteProfile(addon, name)
    local _, _, fc = Ready(addon)
    if not fc or name == DEFAULT_PROFILE or not fc.profiles[name] then return false end
    fc.profiles[name] = nil
    for k, v in pairs(fc.chars) do if v == name then fc.chars[k] = nil end end
    if fc.shared == name then fc.shared = DEFAULT_PROFILE end
    if fc.active == name then fc.discardActive = true end -- geladene Einstellungen nicht zuruecksichern
    return true
end

-- Profil dieses Charakters auf Standardwerte; true = gilt nach dem Neuladen
function UI.ResetProfile(addon)
    local o, _, fc = Ready(addon)
    if not o then return false end
    if o.reset then
        local ok, err = pcall(o.reset)
        if not ok then UI.ReportError(addon, "Reset", err) end
        return false
    end
    fc.pending = fc.pending or {}
    fc.pending.reset = fc.active
    return true
end

-- Export: ein Text fuer die gewaehlten Addons (jeweils das Profil, das dieser Charakter gerade nutzt)
local EXPORT_PREFIX = "FC1:"
local function Encoder()
    local E = C_EncodingUtil
    if E and E.SerializeCBOR and E.DeserializeCBOR and E.CompressString and E.DecompressString
        and E.EncodeBase64 and E.DecodeBase64 then return E end
end

function UI.ExportSettings(addons)
    local E = Encoder()
    if not E then return nil, T("Dieser Client kann keine Einstellungen kodieren.", "This client cannot encode settings.") end
    local payload = { fc = 1, suite = C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("ForeverCore", "Version"),
        w = math.floor(UIParent:GetWidth() + 0.5), h = math.floor(UIParent:GetHeight() + 0.5),
        char = CharName(), addons = {} }
    local count = 0
    for _, addon in ipairs(addons or {}) do
        local o, live = Ready(addon)
        if o then
            payload.addons[addon] = { v = o.version, data = Snapshot(o, live) }
            count = count + 1
        end
    end
    if count == 0 then return nil, T("Keine Addons gewählt.", "No addons selected.") end
    local ok, text = pcall(function() return E.EncodeBase64(E.CompressString(E.SerializeCBOR(payload))) end)
    if not ok or type(text) ~= "string" then return nil, T("Kodieren fehlgeschlagen.", "Encoding failed.") end
    return EXPORT_PREFIX .. text
end

-- Text lesen: Tabelle { addons = { [Addon] = { v, data } }, w, h, char, suite } oder nil, Fehlertext
function UI.ReadSettingsText(text)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then return nil end
    if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, T("Kein Forever-Core-UI-Text (beginnt mit „FC1:“).", "Not a Forever Core UI text (starts with \"FC1:\").")
    end
    local E = Encoder()
    if not E then return nil, T("Dieser Client kann keine Einstellungen lesen.", "This client cannot read settings.") end
    local ok, value = pcall(function()
        return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(text:sub(#EXPORT_PREFIX + 1))))
    end)
    if not ok or type(value) ~= "table" or type(value.addons) ~= "table" then
        return nil, T("Text ist unvollständig oder beschädigt.", "Text is incomplete or damaged.")
    end
    return value
end

-- Import vormerken (gilt nach dem Neuladen): Profil "name" je gewaehltem Addon, auf Wunsch fuer diesen Charakter
function UI.ImportSettings(payload, addons, name, forChar)
    name = strtrim(tostring(name or ""))
    if name == "" then name = "Import" end
    local key = CharKey()
    local count = 0
    for _, addon in ipairs(addons or {}) do
        local o, _, fc = Ready(addon)
        local entry = payload and payload.addons and payload.addons[addon]
        if o and type(entry) == "table" and type(entry.data) == "table" then
            fc.pending = fc.pending or {}
            fc.pending.import = Filter(o, entry.data, entry.v)
            fc.pending.importName = name
            fc.pending.forChar = forChar and key or nil
            count = count + 1
        end
    end
    return count
end

---------------------------------------------------------------------------
-- Fenster "Profile und Austausch" (Aufbau nach CLAUDE.md 7.1, ohne Bereichsliste: alles auf einen Blick)
---------------------------------------------------------------------------
local M = UI.MENU
local profileWindow, transferWindow

-- Knopf, der beim ersten Klick nachfragt und erst beim zweiten ausfuehrt
local function ConfirmButton(parent, text, width, onConfirm, tooltip)
    local b
    b = UI.MenuButton(parent, text, width, 22, function()
        if b.confirm then
            b.confirm = nil
            b:SetText(text)
            onConfirm()
        else
            b.confirm = true
            b:SetText(T("Sicher? Nochmal", "Sure? Again"))
            C_Timer.After(4, function() if b.confirm then b.confirm = nil b:SetText(text) end end)
        end
    end, tooltip)
    return b
end

local function AnyPending()
    for _, addon in ipairs(UI.SettingsAddons()) do
        if UI.ProfilePending(addon) then return true end
    end
    return false
end

local function BuildTransferWindow()
    local W, H = 680, 480
    local f = UI.MenuWindow("ForeverCoreTransfer", T("Austausch", "Transfer"), UI.NAME, W, H)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    transferWindow = f

    -- links: welche Addons
    local left = UI.MenuPanel(f, T("Addons", "Addons"))
    left:SetPoint("TOPLEFT", M.pad, M.panelTop)
    left:SetPoint("BOTTOMLEFT", M.pad, M.pad + M.footerHeight + M.pad)
    left:SetWidth(200)
    f.checks = {}

    -- rechts: Text
    local right = UI.MenuPanel(f, "")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", M.pad, 0)
    right:SetPoint("BOTTOMRIGHT", -M.pad, M.pad + M.footerHeight + M.pad)
    f.textTitle = right.title
    f.hint = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", M.contentX, M.contentY)
    f.hint:SetPoint("RIGHT", -M.contentX, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetWordWrap(true)

    local boxBg = CreateFrame("Frame", nil, right, "BackdropTemplate")
    UI.SetFlat(boxBg, C.input)
    boxBg:SetPoint("TOPLEFT", M.contentX, M.contentY - 36)
    boxBg:SetPoint("BOTTOMRIGHT", -M.contentX, 78)
    local scroll = CreateFrame("ScrollFrame", nil, boxBg)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(W - 200 - 4 * M.pad - 2 * M.contentX - 12)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, box:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)
    boxBg:EnableMouse(true)
    boxBg:SetScript("OnMouseDown", function() box:SetFocus() end)
    f.box = box

    -- nur beim Importieren: Profilname und "fuer diesen Charakter"
    local nameLabel = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("BOTTOMLEFT", M.contentX, 48)
    nameLabel:SetText(T("Als Profil", "As profile"))
    local nameBox = UI.EditBox(right, 158, 22)
    nameBox:SetPoint("LEFT", nameLabel, "LEFT", M.dropdownX, 0)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.forChar = UI.MenuCheck(right, M.contentX, -1000, "", nil, nil)
    f.forChar:ClearAllPoints()
    f.forChar:SetPoint("BOTTOMLEFT", M.contentX, 20)
    f.importParts = { nameLabel, nameBox, f.forChar }
    f.info = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.info:SetPoint("BOTTOMLEFT", M.contentX, 20)
    f.info:SetPoint("RIGHT", -M.contentX, 0)
    f.info:SetJustifyH("LEFT")

    -- Fussleiste
    f.action = UI.MenuButton(f, "", M.footerWidth, M.footerHeight)
    f.action:SetPoint("BOTTOMLEFT", M.pad, M.pad)
    local close = UI.MenuButton(f, T("Schließen", "Close"), M.footerWidth, M.footerHeight, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -M.pad - 16, M.pad)

    local function Selected()
        local list = {}
        for _, cb in ipairs(f.checks) do
            if cb:IsShown() and cb:IsEnabled() and cb:GetChecked() then list[#list + 1] = cb.addon end
        end
        return list
    end

    local function Checks(addons, enabledFn)
        for _, cb in ipairs(f.checks) do cb:Hide() end
        for i, addon in ipairs(addons) do
            local cb = f.checks[i]
            if not cb then
                cb = UI.MenuCheck(left, M.contentX, M.contentY - (i - 1) * M.checkStep, "", nil, function() f.OnChecks() end)
                f.checks[i] = cb
            end
            cb.addon = addon
            cb.label:SetText(addon)
            cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 10), -3, -3)
            local on = enabledFn(addon)
            cb:SetEnabled(on)
            cb:SetChecked(on)
            cb.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
            cb:Show()
        end
    end

    function f.ShowExport()
        f.mode = "export"
        f.TitleText:SetText(T("Exportieren", "Export"))
        f.textTitle:SetText(T("Text zum Sichern oder Weitergeben", "Text to back up or share"))
        f.hint:SetText(T("Mit Strg+C kopieren. Enthält von jedem gewählten Addon das Profil, das dieser Charakter gerade nutzt.",
            "Copy with Ctrl+C. Contains, for each selected addon, the profile this character is using right now."))
        for _, p in ipairs(f.importParts) do p:Hide() end
        f.info:Show()
        Checks(UI.SettingsAddons(), function() return true end)
        f.action:SetText(T("Alles markieren", "Select all"))
        f.action:SetScript("OnClick", function() box:SetFocus() box:HighlightText() end)
        f.OnChecks = function()
            local text, err = UI.ExportSettings(Selected())
            box:SetText(text or "")
            f.info:SetText(err or string.format(T("%d Zeichen · erstellt bei %d × %d (UI-Einheiten)", "%d characters · made at %d × %d (UI units)"),
                #(text or ""), UIParent:GetWidth(), UIParent:GetHeight()))
            box:SetFocus()
            box:HighlightText()
        end
        f:Show()
        f.OnChecks()
    end

    function f.ShowImport()
        f.mode = "import"
        f.TitleText:SetText(T("Importieren", "Import"))
        f.textTitle:SetText(T("Text einfügen (Strg+V)", "Paste text (Ctrl+V)"))
        f.hint:SetText(T("Wird als neues Profil gespeichert – deine bisherigen Profile bleiben erhalten. Gilt nach dem Neuladen.",
            "Saved as a new profile – your existing profiles are kept. Applies after reloading."))
        for _, p in ipairs(f.importParts) do p:Show() end
        nameBox:SetText("Import")
        f.forChar.label:SetText(string.format(T("ab jetzt für %s verwenden", "use for %s from now on"), CharName()))
        f.forChar:SetHitRectInsets(0, -(f.forChar.label:GetStringWidth() + 10), -3, -3)
        f.forChar:SetChecked(true)
        f.info:Hide()
        box:SetText("")
        Checks({}, function() return false end)
        f.action:SetText(T("Übernehmen & neu laden", "Apply & reload"))
        f.OnChecks = function() end
        f.action:SetScript("OnClick", function()
            local payload, err = UI.ReadSettingsText(box:GetText())
            if not payload then
                UI.Chat("Forever", err or T("Bitte zuerst einen Text einfügen.", "Please paste a text first."))
                return
            end
            local n = UI.ImportSettings(payload, Selected(), nameBox:GetText(), f.forChar:GetChecked())
            if n > 0 then ReloadUI() else UI.Chat("Forever", T("Keine passenden Addons gewählt.", "No matching addons selected.")) end
        end)
        box:SetScript("OnTextChanged", function(self, user)
            if f.mode ~= "import" or not user then return end
            local payload, err = UI.ReadSettingsText(self:GetText())
            if not payload then
                Checks({}, function() return false end)
                f.hint:SetText(err or "")
                return
            end
            local names = {}
            for addon in pairs(payload.addons) do if type(addon) == "string" then names[#names + 1] = addon end end
            table.sort(names)
            Checks(names, function(addon) return Ready(addon) ~= nil end)
            local w, h = tonumber(payload.w), tonumber(payload.h)
            local note = string.format(T("Von %s, %d Addons.", "From %s, %d addons."), tostring(payload.char or "?"), #names)
            if w and h and (math.abs(w - UIParent:GetWidth()) > 40 or math.abs(h - UIParent:GetHeight()) > 40) then
                note = note .. " |cffffd100" .. string.format(T("Erstellt bei %d × %d, hier %d × %d: Positionen können abweichen (danach mit /fmove anpassen).",
                    "Made at %d × %d, here %d × %d: positions may differ (adjust with /fmove afterwards)."),
                    w, h, UIParent:GetWidth(), UIParent:GetHeight()) .. "|r"
            end
            f.hint:SetText(note .. " " .. T("Ausgegraute Addons sind hier nicht aktiv.", "Greyed-out addons are not active here."))
        end)
        f:Show()
        box:SetFocus()
    end
end

function UI.ShowTransfer(mode)
    if not transferWindow then BuildTransferWindow() end
    if mode == "import" then transferWindow.ShowImport() else transferWindow.ShowExport() end
end

local function BuildProfileWindow()
    local addons = UI.SettingsAddons()
    local ROW = 28
    local topH = 44 + math.max(#addons, 1) * ROW + 8
    local bottomH = 44 + 5 * 30 + 8
    local W = 680
    local H = M.headerHeight + M.pad + topH + M.pad + bottomH + M.pad + M.footerHeight + M.pad + 2
    local f = UI.MenuWindow("ForeverCoreProfiles", T("Profile", "Profiles"), UI.NAME, W, H)
    profileWindow = f

    -- oben: je Addon das Profil dieses Charakters
    local top = UI.MenuPanel(f, "")
    top:SetPoint("TOPLEFT", M.pad, M.panelTop)
    top:SetPoint("TOPRIGHT", -M.pad, M.panelTop)
    top:SetHeight(topH)
    f.topTitle = top.title

    local rows = {}
    for i, addon in ipairs(addons) do
        local y = M.contentY - (i - 1) * ROW
        local list = {}
        local dd = UI.MenuDropdown(top, M.contentX, y, addon, list,
            function()
                local active, own = UI.CurrentProfile(addon)
                local key = CharKey()
                local _, _, fc = Ready(addon)
                local chosen = fc and key and fc.chars[key]
                return chosen or ""
            end,
            function(key)
                UI.UseProfile(addon, key ~= "" and key or nil)
                f:RefreshAll()
            end, 200)
        dd.list = list
        dd.addon = addon
        local status = top:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        status:SetPoint("LEFT", dd, "RIGHT", 10, 0)
        local reset = ConfirmButton(top, T("Zurücksetzen", "Reset"), 110, function()
            if UI.ResetProfile(addon) then f:RefreshAll() end
        end, T("Setzt das Profil, das dieser Charakter in diesem Addon nutzt, auf Standardwerte (gilt nach dem Neuladen).",
            "Resets the profile this character uses in this addon to defaults (applies after reloading)."))
        reset:SetPoint("TOPRIGHT", -M.contentX, y)
        rows[i] = { dd = dd, status = status, addon = addon }
    end
    if #addons == 0 then
        local none = top:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        none:SetPoint("TOPLEFT", M.contentX, M.contentY)
        none:SetText(T("Noch kein Addon nutzt die gemeinsame Profil-Verwaltung.", "No addon uses the shared profile management yet."))
    end

    -- unten links: fuer alle Addons auf einmal
    local half = (W - 3 * M.pad) / 2
    local all = UI.MenuPanel(f, T("Für alle Addons", "For all addons"))
    all:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -M.pad)
    all:SetSize(half, bottomH)
    local ownBtn = UI.MenuButton(all, "", half - 2 * M.contentX, 22, function()
        for _, addon in ipairs(UI.SettingsAddons()) do UI.NewProfile(addon, CharName()) end
        f:RefreshAll()
    end, T("Speichert die aktuellen Einstellungen aller Addons als Profil mit dem Namen dieses Charakters und nutzt es ab sofort hier.",
        "Saves the current settings of all addons as a profile named after this character and uses it here from now on."))
    ownBtn:SetPoint("TOPLEFT", M.contentX, M.contentY)
    f.ownBtn = ownBtn
    local sharedBtn = UI.MenuButton(all, T("Alle auf das gemeinsame Profil", "All on the shared profile"), half - 2 * M.contentX, 22, function()
        for _, addon in ipairs(UI.SettingsAddons()) do UI.UseProfile(addon, nil) end
        f:RefreshAll()
    end, T("Dieser Charakter nutzt wieder in allen Addons das gemeinsame Profil (gilt nach dem Neuladen).",
        "This character uses the shared profile in all addons again (applies after reloading)."))
    sharedBtn:SetPoint("TOPLEFT", M.contentX, M.contentY - 30)
    local nameBox = UI.EditBox(all, 150, 22)
    nameBox:SetPoint("TOPLEFT", M.contentX, M.contentY - 60)
    local function SaveNamed()
        local name = strtrim(nameBox:GetText() or "")
        if name == "" then return end
        for _, addon in ipairs(UI.SettingsAddons()) do UI.NewProfile(addon, name) end
        nameBox:SetText("")
        nameBox:ClearFocus()
        f:RefreshAll()
    end
    nameBox:SetScript("OnEnterPressed", SaveNamed)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local saveBtn = UI.MenuButton(all, T("Als Profil speichern", "Save as profile"), half - 2 * M.contentX - 156, 22, SaveNamed,
        T("Speichert die aktuellen Einstellungen aller Addons unter diesem Namen und nutzt das Profil ab sofort hier.",
        "Saves the current settings of all addons under this name and uses the profile here from now on."))
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)
    -- Profil loeschen (in allen Addons, die es haben)
    local delList = {}
    local delChoice
    local delDD = UI.MenuDropdown(all, M.contentX, M.contentY - 90, T("Löschen", "Delete"), delList,
        function() return delChoice end, function(key) delChoice = key end, 100)
    delDD:ClearAllPoints()
    delDD:SetPoint("TOPLEFT", M.contentX + 56, M.contentY - 90)
    delDD.label:ClearAllPoints()
    delDD.label:SetPoint("TOPLEFT", all, "TOPLEFT", M.contentX, M.contentY - 94)
    local delBtn = ConfirmButton(all, T("Löschen", "Delete"), half - 2 * M.contentX - 56 - 106, function()
        if not delChoice then return end
        for _, addon in ipairs(UI.SettingsAddons()) do UI.DeleteProfile(addon, delChoice) end
        delChoice = nil
        f:RefreshAll()
    end)
    delBtn:SetPoint("LEFT", delDD, "RIGHT", 6, 0)
    -- Alles auf Standard: in jedem Addon das Profil dieses Charakters zuruecksetzen (wie die Knoepfe oben je Addon)
    local resetAll = ConfirmButton(all, T("Alles auf Standard zurücksetzen", "Reset everything to defaults"), half - 2 * M.contentX, function()
        for _, addon in ipairs(UI.SettingsAddons()) do UI.ResetProfile(addon) end
        f:RefreshAll()
    end, T("Setzt in allen Addons das Profil, das dieser Charakter nutzt, auf Standardwerte (gilt nach dem Neuladen). Andere Profile bleiben erhalten.",
        "Resets the profile this character uses in every addon to defaults (applies after reloading). Other profiles are kept."))
    resetAll:SetPoint("TOPLEFT", M.contentX, M.contentY - 120)

    -- unten rechts: Austausch
    local tr = UI.MenuPanel(f, T("Austausch", "Transfer"))
    tr:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -M.pad)
    tr:SetSize(half, bottomH)
    local trHint = tr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    trHint:SetPoint("TOPLEFT", M.contentX, M.contentY)
    trHint:SetPoint("RIGHT", -M.contentX, 0)
    trHint:SetJustifyH("LEFT")
    trHint:SetWordWrap(true)
    trHint:SetText(T("Ein Text für deine komplette Forever-Oberfläche – zum Sichern oder Weitergeben. Häkchen je Addon.",
        "One text for your complete Forever interface – to back up or share. One checkbox per addon."))
    local exp = UI.MenuButton(tr, T("Exportieren …", "Export …"), (half - 2 * M.contentX - 6) / 2, 22, function() UI.ShowTransfer("export") end)
    exp:SetPoint("TOPLEFT", M.contentX, M.contentY - 46)
    local imp = UI.MenuButton(tr, T("Importieren …", "Import …"), (half - 2 * M.contentX - 6) / 2, 22, function() UI.ShowTransfer("import") end)
    imp:SetPoint("LEFT", exp, "RIGHT", 6, 0)
    local trNote = tr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    trNote:SetPoint("TOPLEFT", M.contentX, M.contentY - 78)
    trNote:SetPoint("RIGHT", -M.contentX, 0)
    trNote:SetJustifyH("LEFT")
    trNote:SetWordWrap(true)
    trNote:SetText(T("Importe werden als neues Profil gespeichert; nichts Bestehendes geht verloren.",
        "Imports are saved as a new profile; nothing existing is lost."))

    -- Fussleiste
    local reload = UI.MenuButton(f, T("Neu laden", "Reload"), M.footerWidth, M.footerHeight, function() ReloadUI() end,
        T("Profilwechsel, Zurücksetzen und Importe gelten nach dem Neuladen.", "Profile changes, resets and imports apply after reloading."))
    reload:SetPoint("BOTTOMLEFT", M.pad, M.pad)
    reload:GetFontString():SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    local close = UI.MenuButton(f, T("Schließen", "Close"), M.footerWidth, M.footerHeight, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -M.pad - 16, M.pad)

    -- Listen und Texte vor dem Auffrischen der Bedienelemente neu fuellen
    local baseRefresh = f.RefreshAll
    function f:RefreshAll()
        f.topTitle:SetText(string.format(T("Profile von %s", "Profiles of %s"), CharName()))
        ownBtn:SetText(string.format(T("Eigenes Profil für %s", "Own profile for %s"), CharName()))
        for _, r in ipairs(rows) do
            wipe(r.dd.list)
            local _, _, shared = UI.CurrentProfile(r.addon)
            r.dd.list[1] = { key = "", label = string.format(T("Gemeinsam (%s)", "Shared (%s)"), UI.ProfileLabel(shared or DEFAULT_PROFILE)) }
            for _, name in ipairs(UI.ProfileNames(r.addon)) do
                r.dd.list[#r.dd.list + 1] = { key = name, label = UI.ProfileLabel(name) }
            end
            local active = UI.CurrentProfile(r.addon)
            if UI.ProfilePending(r.addon) then
                r.status:SetText("|cffffd100" .. T("gilt nach dem Neuladen", "applies after reload") .. "|r")
            else
                r.status:SetText(string.format(T("geladen: %s", "loaded: %s"), UI.ProfileLabel(active or DEFAULT_PROFILE)))
            end
        end
        wipe(delList)
        local seen = {}
        for _, addon in ipairs(UI.SettingsAddons()) do
            for _, name in ipairs(UI.ProfileNames(addon)) do
                if name ~= DEFAULT_PROFILE and not seen[name] then
                    seen[name] = true
                    delList[#delList + 1] = { key = name, label = name }
                end
            end
        end
        if delChoice and not seen[delChoice] then delChoice = nil end
        reload:SetShown(AnyPending())
        baseRefresh(self)
    end
end

function UI.ShowProfiles()
    if not profileWindow then BuildProfileWindow() end
    if profileWindow:IsShown() then profileWindow:RefreshAll() else profileWindow:Show() end
end

---------------------------------------------------------------------------
-- 9. Details! (falls installiert) im Forever-Look – nur auf Wunsch, ohne fremde Profile anzufassen
---------------------------------------------------------------------------
-- * Skin "Forever Core" wird ueber Details' eigene Schnittstelle angemeldet (no_cache: nichts landet in Details'
--   gespeicherten Daten). Man kann ihn auch in Details selbst je Fenster waehlen.
-- * UI.DetailsApplyForever(): sichert das aktuelle Details-Profil als Kopie "Forever Core", wechselt (nur fuer diesen
--   Charakter – Details merkt sich das aktive Profil je Charakter) dorthin und gibt dort allen Fenstern den Skin.
--   Das bisherige Profil bleibt unveraendert; UI.DetailsRestore() wechselt zurueck.
local DETAILS_NAME = "Forever Core"

local function DetailsReady()
    local D = _G.Details
    return D and D.InstallSkin and D.GetProfile and D.ApplyProfile and D.SaveProfile and D.GetCurrentProfileName and D
end

-- Transparenz wie in ForeverQuests (dessen Einstellung "Hintergrund-Transparenz", Standard 65 % = 35 % Deckkraft)
local function QuestsAlpha()
    local q = _G.ForeverQuestsDB
    local tr = q and tonumber(q.backgroundTransparency) or 65
    return math.max(0.15, 1 - tr / 100)
end

-- Flaeche wie der Chat (ForeverChat: Deckkraft der Flaeche, Standard 20 %); ohne ForeverChat wie ForeverQuests
local function ChatAlpha()
    local c = _G.ForeverChatDB
    local v = c and tonumber(c.bgAlpha)
    if v then return math.max(0.05, v / 100) end
    return QuestsAlpha()
end

-- schlichte, einfarbige Leisten-Textur (fuer Details' Titelleiste) in LibSharedMedia anmelden
local FLAT_TEX = "Forever Flat"
local function RegisterFlatTexture()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm and not lsm:IsValid("statusbar", FLAT_TEX) then lsm:Register("statusbar", FLAT_TEX, WHITE) end
    return lsm ~= nil
end

-- feine goldene Linie unter Details' Titelleiste (nur solange ein Fenster unseren Skin nutzt)
local function DetailsAccent(instance)
    local tb = instance and instance.baseframe and instance.baseframe.titleBar
    if not tb then return end
    if not tb.fcAccent then
        tb.fcAccent = tb:CreateTexture(nil, "OVERLAY")
        tb.fcAccent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        tb.fcAccent:SetHeight(1)
        tb.fcAccent:SetPoint("BOTTOMLEFT")
        tb.fcAccent:SetPoint("BOTTOMRIGHT")
    end
    tb.fcAccent:SetShown(instance.skin == DETAILS_NAME and instance.titlebar_shown ~= false)
end

-- Look wie ForeverQuests: Titelleiste in Kopffarbe, Flaeche hinter den Balken wie dessen Fenster (Feldfarbe,
-- gleiche Transparenz, feiner grauer Rand), Titel gold, Balken in Klassenfarbe
local function DetailsSkin()
    local font = "Friz Quadrata TT"
    local bar = [[Interface\AddOns\Details\images\bar_background]]
    local a = QuestsAlpha()
    local titleTex = RegisterFlatTexture() and FLAT_TEX or "Details Flat"
    return {
        file = [[Interface\AddOns\Details\images\skins\simplygray_skin.blp]],
        author = "Forever Core UI", version = "1.1", site = "", no_cache = true,
        desc = "Like the Forever Core UI windows: header in Forever color, transparent body, fine border, gold title.",
        can_change_alpha_head = true,
        icon_anchor_main = { -1, -5 }, icon_anchor_plugins = { -7, -13 }, icon_plugins_size = { 19, 18 },
        micro_frames = { color = { 0.75, 0.75, 0.75, 1 }, font = font, size = 10, textymod = 1 },
        icon_point_anchor = { -37, 0 }, left_corner_anchor = { -107, 0 }, right_corner_anchor = { 96, 0 },
        icon_point_anchor_bottom = { -37, 12 }, left_corner_anchor_bottom = { -107, 0 }, right_corner_anchor_bottom = { 96, 0 },
        icon_ignore_alpha = true, icon_titletext_position = { 3, 4 },
        callback = function(_, instance) DetailsAccent(instance) end,
        instance_cprops = {
            menu_icons_alpha = 0.92,
            hide_in_combat_type = 1,
            -- alte Skin-Grafik (Ecken/Seiten) unsichtbar – Titelleiste und Rand zeichnen wir flach
            color = { C.header[1], C.header[2], C.header[3], 0 },
            show_sidebars = false,
            -- Titelleiste wie in ForeverQuests
            titlebar_shown = true,
            titlebar_height = 20,
            titlebar_texture = titleTex,
            titlebar_texture_color = { C.header[1], C.header[2], C.header[3], a },
            -- Flaeche hinter den Balken wie die Chat-Flaeche (Farbe und Durchsichtigkeit aus ForeverChat)
            bg_r = C.background[1], bg_g = C.background[2], bg_b = C.background[3], bg_alpha = ChatAlpha(),
            backdrop_texture = "Details Ground",
            fullborder_shown = true, fullborder_color = { C.border[1], C.border[2], C.border[3], 1 }, fullborder_size = 1,
            rowareaborder_shown = false,
            color_buttons = { 0.85, 0.85, 0.85, 1 },
            menu_anchor = { 14, 2, side = 2 }, menu_anchor_down = { 14, -2 },
            instance_button_anchor = { -27, 1 },
            attribute_text = {                                                  -- Titel in Gold (Akzentfarbe)
                enabled = true, shadow = true, side = 1, text_color = { C.accent[1], C.accent[2], C.accent[3], 1 },
                custom_text = "{name}", text_face = font, anchor = { -15, 5 }, text_size = 11, enable_custom_text = false,
            },
            menu_icons = { true, true, true, true, true, false, space = -1, shadow = true },
            desaturated_menu = false,
            show_statusbar = false,
            statusbar_info = { alpha = 1, overlay = { 0, 0, 0 } },
            micro_displays_side = 2,
            toolbar_side = 1, bars_grow_direction = 1, bars_sort_direction = 1,
            window_scale = 1,
            hide_icon = true,
            auto_hide_menu = { left = false, right = false },
            wallpaper = { enabled = false },
            row_info = {
                texture = "Details Flat", texture_file = bar,
                texture_class_colors = true,                                    -- Klassenfarben wie in ForeverFrames
                texture_background = "Details Flat", texture_background_file = bar,
                texture_background_class_color = false,
                fixed_texture_background_color = { C.panel[1], C.panel[2], C.panel[3], 0.25 }, -- dezent wie Quest-Zeilen
                texture_highlight = [[Interface\FriendsFrame\UI-FriendsList-Highlight]],
                font_face = font, font_face_file = STANDARD_TEXT_FONT, font_size = 11,
                textL_outline = false, textR_outline = false,
                fixed_text_color = { 1, 1, 1 },
                textL_show_number = true,
                height = 18, space = { right = -10, left = 3, between = 1 },
                alpha = 1, no_icon = false, start_after_icon = false,
                use_spec_icons = true, icon_file = [[Interface\AddOns\Details\images\spec_icons_normal_alpha]],
                backdrop = { enabled = false, size = 12, color = { 1, 1, 1, 1 }, texture = "Details BarBorder 2" },
                percent_type = 1,
            },
        },
    }
end

-- Skin anmelden (Details laedt vor ForeverCore; sonst beim ADDON_LOADED von Details). force: neu anmelden, z. B.
-- damit eine geaenderte Transparenz in ForeverQuests uebernommen wird
local function InstallDetailsSkin(force)
    local D = DetailsReady()
    if not D or (SHARED.detailsSkin and not force) then return end
    local ok = pcall(D.InstallSkin, D, DETAILS_NAME, DetailsSkin())
    if ok then SHARED.detailsSkin = true end
    -- Skin gewechselt (auch zu einem anderen): goldene Linie ein-/ausblenden
    if ok and not SHARED.detailsHooked and D.ChangeSkin then
        SHARED.detailsHooked = true
        hooksecurefunc(D, "ChangeSkin", function(instance) pcall(DetailsAccent, instance) end)
    end
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_LOGIN" or name == "Details" then InstallDetailsSkin() end
        -- Fenster mit unserem Skin bekommen nach dem Laden die aktuelle Fassung (neue Version, Transparenz)
        if event == "PLAYER_LOGIN" then
            C_Timer.After(4, function()
                local D = DetailsReady()
                if not (D and D.ListInstances) then return end
                InstallDetailsSkin(true)
                for _, instance in D:ListInstances() do
                    if instance and instance.skin == DETAILS_NAME and instance.ChangeSkin then
                        pcall(instance.ChangeSkin, instance, DETAILS_NAME)
                    end
                end
                -- Standard (v50): Forever-Look einmal je Charakter automatisch (Details merkt sich das Profil je
                -- Charakter). Wer einmal "vorheriges Profil" gewählt hat, bekommt es nie wieder automatisch.
                local db = GetDB()
                local char = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
                db.detailsAuto = type(db.detailsAuto) == "table" and db.detailsAuto or {}
                if not db.detailsOptOut and not db.detailsAuto[char] and not InCombatLockdown() then
                    db.detailsAuto[char] = true
                    if not UI.DetailsForeverActive() then pcall(UI.DetailsApplyForever) end
                end
            end)
        end
    end)
end

function UI.DetailsAvailable() return DetailsReady() ~= nil end

function UI.DetailsForeverActive()
    local D = DetailsReady()
    return D and D:GetCurrentProfileName() == DETAILS_NAME or false
end

-- Standardplatz des ersten Details-Fensters: 310 x 158, rechts 4 und unten 50 vom Bildschirmrand
-- (Details rechnet die Position als Mitte relativ zur Bildschirmmitte)
local DETAILS_W, DETAILS_H, DETAILS_RIGHT, DETAILS_BOTTOM = 310, 158, 4, 50
local function DetailsDefaultPosition(D)
    local instance = D.GetInstance and D:GetInstance(1)
    if not (instance and instance.baseframe and instance.mostrando == "normal") then return end
    local x = UIParent:GetWidth() / 2 - DETAILS_RIGHT - DETAILS_W / 2
    local y = -UIParent:GetHeight() / 2 + DETAILS_BOTTOM + DETAILS_H / 2
    instance:RestoreMainWindowPosition({ x = x, y = y, largura = DETAILS_W, altura = DETAILS_H })
    instance:SaveMainWindowPosition()
end

function UI.DetailsApplyForever()
    local D = DetailsReady()
    if not D then return false end
    if InCombatLockdown() then UI.Chat("Forever", T("Im Kampf nicht möglich.", "Not possible in combat.")) return false end
    InstallDetailsSkin(true) -- aktuelle Transparenz aus ForeverQuests
    local current = D:GetCurrentProfileName()
    if current ~= DETAILS_NAME then
        GetDB().detailsPrevious = current
        -- Kopie des aktuellen Stands (Fenster, Positionen, Einstellungen); ein frueheres "Forever Core" bleibt, wie es ist
        local fresh = not D:GetProfile(DETAILS_NAME, false)
        if fresh then D:SaveProfile(DETAILS_NAME) end
        D:ApplyProfile(DETAILS_NAME)
        -- nur beim ersten Anlegen: erstes Fenster an den Forever-Standardplatz (unten rechts ueber Menue und Taschen)
        if fresh then pcall(DetailsDefaultPosition, D) end
    end
    if D.ListInstances then
        for _, instance in D:ListInstances() do
            if instance and instance.ChangeSkin then pcall(instance.ChangeSkin, instance, DETAILS_NAME) end
        end
    end
    UI.Chat("Forever", string.format(T("Details nutzt jetzt das Profil „%s“ im Forever-Look. Dein bisheriges Profil „%s“ ist unverändert.",
        "Details now uses the profile \"%s\" in the Forever look. Your previous profile \"%s\" is unchanged."), DETAILS_NAME, tostring(current)))
    return true
end

function UI.DetailsRestore()
    local D = DetailsReady()
    local prev = GetDB().detailsPrevious
    if not (D and prev and D:GetProfile(prev, false)) then return false end
    if InCombatLockdown() then UI.Chat("Forever", T("Im Kampf nicht möglich.", "Not possible in combat.")) return false end
    GetDB().detailsOptOut = true -- bewusst zurück: nicht mehr automatisch umstellen
    D:ApplyProfile(prev)
    UI.Chat("Forever", string.format(T("Details nutzt wieder dein Profil „%s“.", "Details uses your profile \"%s\" again."), prev))
    return true
end

-- Details-Fenster rasten ein wie Forever-Rahmen (v63): beim Ziehen eines Details-Fensters die gelben Hilfslinien,
-- nach dem Loslassen rastet es (samt seiner Details-Gruppe) an Forever-Rahmen, der Bildschirmmitte und am Raster
-- ein; umgekehrt rasten Forever-Rahmen an Details-Fenstern ein. Gilt mit dem gemeinsamen Schalter "Einrasten"
-- (Umschalt = frei). Details' eigenes Ziehen ist nicht von außen erreichbar (Details222 ist privat) – wir erkennen
-- es an baseframe.isMoving (Details setzt es beim Ziehen) und verschieben erst danach; Details selbst bleibt
-- unverändert. Hat Details das Fenster gerade an ein anderes Details-Fenster gehängt, gilt dessen Einrasten.
do
    local proxies = {}   -- [baseframe] = unsichtbarer Rahmen über Fläche + Titelleiste (die sichtbaren Kanten)
    local watched = {}   -- [baseframe] = Zustand beim Ziehen
    local function Proxy(instance)
        local bf = instance.baseframe
        local p = proxies[bf]
        if not p then
            p = CreateFrame("Frame", nil, bf)
            proxies[bf] = p
            UI.AddMover(p)
        end
        local tb = bf.titleBar
        p:ClearAllPoints()
        p:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT")
        p:SetPoint("TOPLEFT", (tb and tb:IsShown()) and tb or bf, "TOPLEFT")
        return p
    end
    local function Links(instance)
        local n = 0
        for _ in pairs(instance.snap or {}) do n = n + 1 end
        return n
    end
    -- Details-Gruppe (über instance.snap verbunden) einsammeln
    local function Group(D, instance)
        local list, seen = {}, {}
        local function Add(inst)
            if not inst or seen[inst] then return end
            seen[inst] = true
            list[#list + 1] = inst
            for _, id in pairs(inst.snap or {}) do Add(D:GetInstance(id)) end
        end
        Add(instance)
        return list
    end
    local function Shift(D, instance, dx, dy)
        local group = Group(D, instance)
        for _, inst in ipairs(group) do
            local bf = inst.baseframe
            -- nur Fenster verschieben, die am Bildschirm hängen; die anderen hängen an ihnen und folgen
            local point, rel, relPoint, x, y = bf:GetPoint(1)
            if point and (rel == nil or rel == UIParent) then
                local s = UIParent:GetEffectiveScale() / bf:GetEffectiveScale()
                bf:ClearAllPoints()
                bf:SetPoint(point, UIParent, relPoint, x + dx * s, y + dy * s)
            end
        end
        for _, inst in ipairs(group) do pcall(inst.SaveMainWindowPosition, inst) end
    end
    local active = false
    local function Watch()
        local D = DetailsReady()
        if not (D and D.ListInstances) then return end
        for _, instance in D:ListInstances() do
            local bf = instance and instance.baseframe
            if bf and instance.ativa then
                local state = watched[bf]
                if bf.isMoving and not state then
                    watched[bf] = { links = Links(instance) }
                    UI.BeginDrag(bf, { edges = Proxy(instance) })
                elseif not bf.isMoving and state then
                    watched[bf] = nil
                    local dx, dy = UI.EndDrag()
                    if Links(instance) <= state.links and (dx ~= 0 or dy ~= 0) then pcall(Shift, D, instance, dx, dy) end
                elseif not proxies[bf] then
                    Proxy(instance)
                end
            end
        end
    end
    UI.Every(0.05, Watch, { addon = "ForeverCore", name = "Details einrasten", when = function() return active end })
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        -- erst wenn Details da ist; Titelleiste kann sich mit dem Skin ändern -> Kanten nach dem Laden neu
        C_Timer.After(5, function()
            local D = DetailsReady()
            if not (D and D.ListInstances) then return end
            active = true
            if D.ChangeSkin then
                hooksecurefunc(D, "ChangeSkin", function(instance)
                    if instance and instance.baseframe and proxies[instance.baseframe] then pcall(Proxy, instance) end
                end)
            end
        end)
    end)
end

---------------------------------------------------------------------------
-- Schaden/Heilung ueber Zeit (DoT/HoT) der eigenen Auren auf einer Einheit (v67):
-- UI.OverTimeRemaining(unit, "heal"|"damage") -> noch ausstehende Menge (Zahl, 0 wenn keine/nicht lesbar).
-- Menge je Zauber aus der Zauberbeschreibung ("... 1.234 ueber 12 Sek."), anteilig nach Restdauer.
-- Schaetzung: nutzt die aktuellen Werte des Spielers, keine Tick-Genauigkeit.
---------------------------------------------------------------------------
UI.HATCH_TEXTURE = "Interface\\RaidFrame\\Shield-Overlay" -- Schraffur fuer Vorhersage-Balken

local function Secret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
    return false
end

local overInfo = {} -- [spellID] = { amount, seconds, kind } | false (keine Ueber-Zeit-Wirkung)
local HEAL_WORDS = { "heil", "heal", "gesundheit", "health" }
local DMG_WORDS = { "schaden", "damage" }

local function FirstPos(text, words)
    local best
    for _, w in ipairs(words) do
        local p = text:find(w, 1, true)
        if p and (not best or p < best) then best = p end
    end
    return best
end

local function ToNumber(s) return tonumber((s:gsub("[%.,%s]", ""))) end

local function ParseOver(desc)
    desc = desc:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local pos, finish, seconds = desc:find("über%s+(%d+[%.,]?%d*)%s*[Ss]e")
    if not pos then pos, finish, seconds = desc:find("over%s+(%d+[%.,]?%d*)%s*[Ss]e") end
    if not pos then return nil end
    seconds = tonumber((seconds:gsub(",", ".")))
    -- Menge: erst hinter der Zeitangabe ("ueber 12 Sek. 1234 Gesundheit"), sonst die letzte Zahl davor
    local amount, at = desc:sub(finish + 1):match("^[^%d]*(%d[%d%.,]*)()")
    if amount then
        local rest = desc:sub(finish + at, finish + at + 12):lower()
        if rest:match("^%s*sek") or rest:match("^%s*sec") or rest:match("^%s*min") then amount = nil end
    end
    local segment
    if amount then
        segment = desc:sub(math.max(1, pos - 40), finish + at + 30):lower()
    else
        for n in desc:sub(1, pos - 1):gmatch("(%d[%d%.,]*)") do amount = n end
        segment = desc:sub(math.max(1, pos - 60), finish + 30):lower()
    end
    amount = amount and ToNumber(amount)
    if not (amount and amount > 0 and seconds and seconds > 0) then return nil end
    local h, d = FirstPos(segment, HEAL_WORDS), FirstPos(segment, DMG_WORDS)
    local kind = (h and (not d or h < d)) and "heal" or (d and "damage") or nil
    if not kind then return nil end
    return { amount = amount, seconds = seconds, kind = kind }
end

local function OverInfo(spellID)
    local cached = overInfo[spellID]
    if cached ~= nil then return cached or nil end
    local desc = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
    if type(desc) ~= "string" or Secret(desc) or desc == "" then
        if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, spellID) end
        return nil -- noch nicht geladen: spaeter nochmal
    end
    local info = ParseOver(desc)
    overInfo[spellID] = info or false
    return info
end

local function Raw(unit, filter)
    local list = {}
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        local ok, res = pcall(C_UnitAuras.GetUnitAuras, unit, filter)
        if ok and type(res) == "table" then list = res end
    end
    if #list == 0 and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or not a then break end
            list[#list + 1] = a
        end
    end
    return list
end

local function Mine(a)
    local src, mine = a.sourceUnit, a.isFromPlayerOrPlayerPet
    if Secret(src, mine) then return false end
    return mine == true or src == "player" or src == "pet" or src == "vehicle"
end

-- Eigene Auren: erst mit Filter "PLAYER"; liefert der nichts, alle Auren holen und selbst nach Quelle filtern
local function CollectAuras(unit, filter)
    local list = Raw(unit, filter)
    if #list > 0 or not filter:find("|PLAYER", 1, true) then return list end
    local base = filter:gsub("|PLAYER", "")
    local out = {}
    for _, a in ipairs(Raw(unit, base)) do
        if Mine(a) then out[#out + 1] = a end
    end
    return out
end

-- Im Kampf sind Aura-Daten gesperrt. Ersatz: eigene Zauber merken (Zauber-ID, Ziel, Ablauf) und daraus rechnen.
-- tracked[GUID][Art][Zauber-ID] = { amount, seconds, expires }; ausserhalb des Kampfes wird es aus den echten Auren erneuert.
local tracked, pendingCast, overCbs = {}, {}, {}
function UI.OnOverTimeChange(fn) overCbs[#overCbs + 1] = fn end
local function NotifyOver() for _, fn in ipairs(overCbs) do pcall(fn) end end

local function UnitGuid(unit)
    local ok, g = pcall(UnitGUID, unit)
    if ok and g and not Secret(g) then return g end
end

local function NameIs(tok, name)
    if not UnitExists(tok) then return false end
    local n1 = UnitName(tok)
    if n1 and not Secret(n1) and n1 == name then return true end
    local n2 = GetUnitName and GetUnitName(tok, true)
    return n2 and not Secret(n2) and n2 == name or false
end

local function ResolveGuid(targetName, kind)
    if type(targetName) ~= "string" or Secret(targetName) then return nil end
    if targetName == "" then return kind == "heal" and UnitGuid("player") or nil end
    local tokens = { "target", "focus", "mouseover", "player", "pet", "softenemy", "softfriend" }
    for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
    for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
    for _, tok in ipairs(tokens) do
        if NameIs(tok, targetName) then
            local g = UnitGuid(tok)
            if g then return g end
        end
    end
end

local function Track(guid, kind, spellID, info, expires)
    local t = tracked[guid]
    if not t then t = {} tracked[guid] = t end
    local k = t[kind]
    if not k then k = {} t[kind] = k end
    k[spellID] = { amount = info.amount, seconds = info.seconds, expires = expires }
end

local overEvents = CreateFrame("Frame")
overEvents:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
overEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
overEvents:SetScript("OnEvent", function(_, event, _, a, b, c)
    if event == "UNIT_SPELLCAST_SENT" then -- Einheit, Zielname, Zauber-GUID, Zauber-ID
        if b and not Secret(b) and c and not Secret(c) then pendingCast[b] = { target = a, spellID = c } end
    else -- Einheit, Zauber-GUID, Zauber-ID
        if not a or Secret(a) then return end
        local p = pendingCast[a]
        pendingCast[a] = nil
        if not p then return end
        local info = OverInfo(p.spellID)
        if not info then return end
        local guid = ResolveGuid(p.target, info.kind)
        if not guid then return end
        local old = tracked[guid] and tracked[guid][info.kind] and tracked[guid][info.kind][p.spellID]
        local now = GetTime()
        local carry = (old and old.expires > now) and math.min(old.expires - now, info.seconds * 0.3) or 0
        Track(guid, info.kind, p.spellID, info, now + info.seconds + carry)
        NotifyOver()
    end
end)

-- GUID einer Einheit. Namensplaketten ("nameplateN") sind im Kampf oft gesperrt: dann ueber Ziel/Fokus/Mouseover
-- gleichsetzen, sonst die zuletzt ausserhalb des Kampfes gelesene GUID dieser Plakette nehmen.
do -- eigener Block: spart oberste Locals (Grenze 200)
local plateGuids = {}
local function GuidOf(unit)
    local g = UnitGuid(unit)
    if g then
        if unit:find("^nameplate") then plateGuids[unit] = g end
        return g
    end
    for _, tok in ipairs({ "target", "focus", "mouseover", "softenemy" }) do
        local ok, same = pcall(UnitIsUnit, unit, tok)
        if ok and same and not Secret(same) then
            local tg = UnitGuid(tok)
            if tg then return tg end
        end
    end
    return plateGuids[unit]
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    f:SetScript("OnEvent", function(_, _, unit) if unit then plateGuids[unit] = nil end end)
end

function UI.OverTimeRemaining(unit, kind)
    local filter = kind == "heal" and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
    local now, total, found = GetTime(), 0, false
    local guid = GuidOf(unit)
    local fresh = {}
    for _, a in ipairs(CollectAuras(unit, filter)) do
        local id, expires = a.spellId, a.expirationTime
        if id and expires and not Secret(id, expires) and expires > now then
            local info = OverInfo(id)
            if info and info.kind == kind then
                found = true
                total = total + info.amount * math.min(1, (expires - now) / info.seconds)
                fresh[id] = { amount = info.amount, seconds = info.seconds, expires = expires }
            end
        end
    end
    if guid then
        if found then
            tracked[guid] = tracked[guid] or {}
            tracked[guid][kind] = fresh
        elseif not (InCombatLockdown and InCombatLockdown()) then
            if tracked[guid] then tracked[guid][kind] = nil end -- ausserhalb des Kampfes: keine Aura = nichts offen
        else
            local k = tracked[guid] and tracked[guid][kind]
            if k then
                for id, e in pairs(k) do
                    if e.expires <= now then k[id] = nil
                    else total = total + e.amount * math.min(1, (e.expires - now) / e.seconds) end
                end
            end
        end
    end
    return total
end
end

-- Fehlersuche: /fover [Einheit] listet die eigenen HoTs/DoTs und was daraus gelesen wurde
SLASH_FOREVEROVER1 = "/fover"
SlashCmdList.FOREVEROVER = function(msg)
    local unit = (msg and msg:match("%S+")) or "target"
    local function P(t) UI.Chat("HoT/DoT", t) end
    if not UnitExists(unit) then P("Einheit '" .. unit .. "' gibt es nicht (Ziel wählen oder /fover player).") return end
    P("Einheit: " .. tostring(UnitName(unit)) .. " | GetUnitAuras: " .. tostring(C_UnitAuras and C_UnitAuras.GetUnitAuras ~= nil) .. ", Beschreibung: "
        .. tostring(C_Spell and C_Spell.GetSpellDescription ~= nil))
    do
        local g, n = UnitGuid(unit), 0
        for _, kinds in pairs(tracked) do for _, k in pairs(kinds) do for _ in pairs(k) do n = n + 1 end end end
        P(string.format("Kampfsperre: %s | GUID lesbar: %s | verfolgte Zauber gesamt: %d",
            tostring(InCombatLockdown and InCombatLockdown()), tostring(g ~= nil), n))
    end
    for _, filter in ipairs({ "HELPFUL|PLAYER", "HARMFUL|PLAYER", "HELPFUL", "HARMFUL" }) do
        local list = CollectAuras(unit, filter)
        P(filter .. ": " .. #list .. " Auren")
        for _, a in ipairs(list) do
            local id = a.spellId
            if Secret(id) then P("  (geheim)") else
                local desc = C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id)
                local info = ParseOver(type(desc) == "string" and desc or "")
                P(string.format("  %s (%s): %s", tostring(a.name), tostring(id),
                    info and string.format("%s %d über %ss", info.kind, info.amount, info.seconds)
                    or ("nicht erkannt – " .. tostring(desc):sub(1, 90))))
            end
        end
    end
    P(string.format("Summe: Heilung %d, Schaden %d", UI.OverTimeRemaining(unit, "heal"), UI.OverTimeRemaining(unit, "damage")))
end

---------------------------------------------------------------------------
-- Aeltere, frueher geladene Kopien auf diese (neueste) umleiten: Addons, die sich dort ihre
-- UI-Tabelle gemerkt haben, rufen damit ab sofort die neuen Funktionen auf (gemeinsamer Zustand).
-- Hinweis: Kopien vor v21 hatten noch keinen gemeinsamen Zustand – was sich dort beim Laden
-- angemeldet hat, kennt erst die naechste Version dieses Addons.
---------------------------------------------------------------------------
for _, old in ipairs(SHARED.uiTables) do
    if old ~= UI then
        for key, value in pairs(UI) do
            if type(value) == "function" then old[key] = value end
        end
    end
end
