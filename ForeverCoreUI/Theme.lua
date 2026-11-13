-- ForeverCoreUI – Theme.lua: PROTOTYP "Runen"-Design (dunkles Blau, goldener Rahmen, dezenter Runenkreis).
-- Legt hinter jedes Forever-Fenster (alles, was über UI.Window / UI.RegisterWindow läuft – auch Dungeonfenster,
-- Taschen, Bank, Twinks – und über Theme.Register die von ForeverSkin umgestalteten Blizzard-Fenster) eine
-- zusätzliche Ebene aus Texturen; der normale flache Stil bleibt darunter unverändert – ausschalten = wie vorher.
-- Diese Datei ist die EINE gemeinsame Grundlage der Runen-Optik: Farben und Grafik nur hier ändern. Einstellung:
-- ForeverHubDB.theme = "runes" (nil = Standard). Umschalten per Knopf links neben dem Suchfeld des Einstellungsfensters.
-- Zum Entfernen: diese Datei, Media\ThemeRunes.tga, tools\make-theme-art.ps1, die Zeile "Theme.lua" in der .toc und die
-- zwei Zeilen "UI.Theme" in ForeverHub.lua (UI.RegisterWindow, SettingsWindow) löschen.
local hub = _G.ForeverHub
if type(hub) ~= "table" or type(hub.UI) ~= "table" or hub.UI.Theme then return end
local UI = hub.UI
local SHARED = hub.shared
local T = UI.T

-- Feinjustierung: Farben (r, g, b[, a]) und Deckkraft
local TOP = { 0.075, 0.115, 0.215 }       -- Verlauf oben
local BOTTOM = { 0.040, 0.060, 0.125 }    -- Verlauf unten
local GOLD = { 0.87, 0.69, 0.27 }
local HEADER = { 0.07, 0.10, 0.19 }       -- Titelleiste (statt Grau)
local RUNES_ALPHA = 0.13
local FRAME_ALPHA = 0.55
local RUNES = "Interface\\AddOns\\" .. tostring(select(1, ...) or "ForeverCoreUI") .. "\\Media\\ThemeRunes"

local Theme = {}
UI.Theme = Theme

-- Gemeinsame Grundlage für ALLE Forever-Fenster (2026-11-13): außer den beim Hub angemeldeten Fenstern
-- (UI.RegisterWindow) können sich weitere Rahmen anmelden – Theme.Register(frame, opts) –, z. B. die von ForeverSkin
-- umgestalteten Blizzard-Fenster. Zustand je Fenster steht in eigenen (schwachen) Tabellen, NICHT im Rahmen selbst:
-- in Blizzard-Rahmen legen wir keine eigenen Werte ab (Taint-Regel).
--   opts.anchor  = Fläche, an der sich Verlauf, Runen und Goldrahmen ausrichten (Standard: der Rahmen selbst)
--   opts.own     = function(textur) – wird für jede angelegte Textur aufgerufen (ForeverSkin merkt sie als eigene)
--   opts.onApply = function(an, farben) – eigene Teile umfärben (farben.header, farben.gold)
local state = setmetatable({}, { __mode = "k" }) -- [Fenster] = { list = Texturen, header = alte Titelfarbe }
local extra = setmetatable({}, { __mode = "k" }) -- [Rahmen] = opts (nicht über UI.RegisterWindow angemeldet)

function Theme.IsOn()
    local db = _G.ForeverHubDB
    return type(db) == "table" and db.theme == "runes"
end
function Theme.Set(on)
    if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
    _G.ForeverHubDB.theme = on and "runes" or nil
end

local function Gradient(tex, top, bottom)
    if tex.SetGradient and CreateColor then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], 1),
            CreateColor(top[1], top[2], top[3], 1))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], 1, top[1], top[2], top[3], 1)
    else
        tex:SetColorTexture(top[1], top[2], top[3], 1)
    end
end

-- Texturen einmal je Fenster anlegen (sie liegen auf dem Fenster selbst, unter allen Kindern)
local function Build(f, opts)
    local t = { list = {} }
    local anchor = (opts and opts.anchor) or f
    local function New(sub)
        local x = f:CreateTexture(nil, "BACKGROUND", nil, sub)
        t.list[#t.list + 1] = x
        if opts and opts.own then pcall(opts.own, x) end
        return x
    end
    t.bg = New(1)
    t.bg:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, -1)
    t.bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -1, 1)
    t.bg:SetColorTexture(1, 1, 1, 1)
    Gradient(t.bg, TOP, BOTTOM)

    t.runes = New(2)
    t.runes:SetTexture(RUNES)
    t.runes:SetAlpha(RUNES_ALPHA)
    local function Place()
        local w, h = anchor:GetSize()
        if not w or not h or w <= 0 or h <= 0 then return end
        local size = math.max(64, math.min(w, h) * 0.92)
        t.runes:SetSize(size, size)
        t.runes:ClearAllPoints()
        t.runes:SetPoint("CENTER", anchor, "CENTER", (w - size) / 2 - 10, 0)
    end
    Place()
    t.place = Place
    f:HookScript("OnSizeChanged", Place)
    f:HookScript("OnShow", Place) -- (Blizzard-Fenster haben ihre Größe oft erst beim Öffnen)

    -- goldener Innenrahmen mit Eckmarken
    local function Line(a1, r1, a2, r2, w, h, alpha, x1, y1, x2, y2)
        local l = New(3)
        l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], alpha)
        l:SetPoint(a1, anchor, r1, x1, y1)
        if a2 then l:SetPoint(a2, anchor, r2, x2, y2) end
        if w then l:SetWidth(w) end
        if h then l:SetHeight(h) end
    end
    local I = 4 -- Abstand zum Fensterrand
    Line("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1, FRAME_ALPHA, I, -I, -I, -I)
    Line("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1, FRAME_ALPHA, I, I, -I, I)
    Line("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil, FRAME_ALPHA, I, -I, I, I)
    Line("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil, FRAME_ALPHA, -I, -I, -I, I)
    local C = 12 -- Eckmarken (L-Form)
    for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local p, sx, sy = corner[1], corner[2], corner[3]
        Line(p, p, nil, nil, C, 2, 1, sx * (I - 1), sy * (I - 1))
        Line(p, p, nil, nil, 2, C, 1, sx * (I - 1), sy * (I - 1))
    end
    state[f] = t
    return t
end

local COLORS = { header = HEADER, gold = GOLD, top = TOP, bottom = BOTTOM }
-- Farben der Runen-Optik für Teile, die keine Fenster sind (z. B. Knöpfe und Leisten von ForeverBars): nur lesen.
-- Zusammen mit Theme.IsOn() und der Nachricht "ThemeChanged" (UI.On) nutzen.
Theme.COLORS = COLORS

-- Design auf ein Fenster anwenden bzw. wieder wegnehmen (je nach Einstellung)
function Theme.Apply(f)
    if not f or not f.CreateTexture or (f.IsForbidden and f:IsForbidden()) then return end
    local on = Theme.IsOn()
    local opts = extra[f]
    local t = state[f]
    if on and not t then t = Build(f, opts) end
    if t then
        for _, x in ipairs(t.list) do x:SetShown(on) end
        if on and t.place then t.place() end
    end
    -- Titelleiste: bläulich statt grau; beim Ausschalten die alte Farbe zurück (nur eigene Forever-Fenster –
    -- angemeldete fremde Rahmen färben ihre Teile selbst über opts.onApply)
    local h = not opts and f.header
    if h and h.SetBackdropColor and t then
        if on then
            if not t.header then t.header = { h:GetBackdropColor() } end
            h:SetBackdropColor(HEADER[1], HEADER[2], HEADER[3], 1)
        elseif t.header then
            local c = t.header
            h:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
            t.header = nil
        end
    end
    if opts and opts.onApply then pcall(opts.onApply, on, COLORS) end
end

-- Weiteren Rahmen anmelden (siehe oben); wirkt sofort und bei jedem Umschalten
function Theme.Register(f, opts)
    if not f or not f.CreateTexture or extra[f] then return end
    extra[f] = opts or {}
    local ok, err = pcall(Theme.Apply, f)
    if not ok and UI.ReportError then UI.ReportError("ForeverCoreUI", "Theme/Register", err) end
end

function Theme.Refresh()
    local function Each(list)
        for f in pairs(list or {}) do
            local ok, err = pcall(Theme.Apply, f)
            if not ok and UI.ReportError then UI.ReportError("ForeverCoreUI", "Theme", err) end
        end
    end
    Each(SHARED.windows)
    Each(extra)
end

UI.On("ThemeChanged", Theme.Refresh)

-- Abfrage /frunen: welche Forever-Fenster haben die Runen-Optik noch NICHT? Geprüft werden alle Rahmen, die es
-- gerade gibt (viele Fenster entstehen erst beim ersten Öffnen – also vorher öffnen): Name beginnt mit "Forever",
-- eigene Hintergrundfläche, mindestens 180 x 120 groß und weder selbst noch über ein Elternfenster angemeldet.
-- Andere Addons hängen eigene Prüfungen an (Theme.reporters: function(liste) – ForeverSkin meldet umgestaltete
-- Blizzard-Fenster ohne Optik).
Theme.reporters = {}
function Theme.Report()
    local missing = {}
    local function Covered(f)
        local p, n = f, 0
        while p and n < 12 do
            if SHARED.windows[p] or extra[p] then return true end
            p = p.GetParent and p:GetParent()
            n = n + 1
        end
        return false
    end
    local f = EnumerateFrames()
    while f do
        if not (f.IsForbidden and f:IsForbidden()) then
            local name = f.GetName and f:GetName()
            if type(name) == "string" and name:find("^Forever") and f.GetBackdrop and f:GetBackdrop()
                and (f:GetWidth() or 0) >= 180 and (f:GetHeight() or 0) >= 120 and not Covered(f) then
                missing[#missing + 1] = name
            end
        end
        f = EnumerateFrames(f)
    end
    for _, fn in ipairs(Theme.reporters) do pcall(fn, missing) end
    table.sort(missing)
    local chat = function(text) UI.Chat("Forever Core UI", text) end
    if #missing == 0 then
        chat(T("Runen-Optik: alle bisher geöffneten Fenster haben sie. (Fenster, die noch nie offen waren, vorher öffnen.)",
            "Runes design: all windows opened so far have it. (Open windows that were never shown first.)"))
        return
    end
    chat(string.format(T("Runen-Optik fehlt bei %d Fenster(n):", "Runes design missing on %d window(s):"), #missing))
    for _, name in ipairs(missing) do chat("  " .. name) end
end

SLASH_FOREVERRUNEN1 = "/frunen"
SLASH_FOREVERRUNEN2 = "/foreverrunen"
SlashCmdList["FOREVERRUNEN"] = function()
    local ok, err = pcall(Theme.Report)
    if not ok and UI.ReportError then UI.ReportError("ForeverCoreUI", "Theme/Report", err) end
end

-- Knopf links neben dem Suchfeld des Einstellungsfensters (wird von SettingsWindow aufgerufen)
function Theme.AddButton(f)
    if f.themeBtn or not f.search then return end
    local function Label() return Theme.IsOn() and T("Design: Runen", "Design: Runes") or T("Design: Standard", "Design: Standard") end
    local btn = UI.Button(f, Label(), 120, function(self)
        Theme.Set(not Theme.IsOn())
        UI.Fire("ThemeChanged")
        self:SetText(Label())
    end)
    btn:SetPoint("RIGHT", f.search, "LEFT", -6, 0)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(T("Design (Prototyp)", "Design (prototype)"))
        GameTooltip:AddLine(T("Wechselt zwischen dem flachen Standard-Stil und dem Runen-Design (dunkles Blau, Gold).",
            "Switches between the flat default style and the runes design (dark blue, gold)."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local function Level() btn:SetFrameLevel(f:GetFrameLevel() + 60) end
    hooksecurefunc(f, "SetFrameLevel", Level)
    Level()
    f.themeBtn = btn
end

-- beim Laden: schon vorhandene Fenster (Einstellung wird erst mit den gespeicherten Werten bekannt)
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Theme.Refresh()
end)
