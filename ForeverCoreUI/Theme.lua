-- ForeverCoreUI – Theme.lua: PROTOTYP "Runen"-Design (dunkles Blau, goldener Rahmen, dezenter Runenkreis).
-- Legt hinter jedes Forever-Fenster (alles, was über UI.Window / UI.RegisterWindow läuft) eine zusätzliche Ebene aus
-- Texturen; der normale flache Stil bleibt darunter unverändert – ausschalten = wie vorher. Einstellung:
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
local function Build(f)
    local t = { list = {} }
    local function New(sub)
        local x = f:CreateTexture(nil, "BACKGROUND", nil, sub)
        t.list[#t.list + 1] = x
        return x
    end
    t.bg = New(1)
    t.bg:SetPoint("TOPLEFT", 1, -1)
    t.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    t.bg:SetColorTexture(1, 1, 1, 1)
    Gradient(t.bg, TOP, BOTTOM)

    t.runes = New(2)
    t.runes:SetTexture(RUNES)
    t.runes:SetAlpha(RUNES_ALPHA)
    local function Place()
        local w, h = f:GetSize()
        local size = math.max(64, math.min(w, h) * 0.92)
        t.runes:SetSize(size, size)
        t.runes:ClearAllPoints()
        t.runes:SetPoint("CENTER", f, "CENTER", (w - size) / 2 - 10, 0)
    end
    Place()
    f:HookScript("OnSizeChanged", Place)

    -- goldener Innenrahmen mit Eckmarken
    local function Line(a1, r1, a2, r2, w, h, alpha, x1, y1, x2, y2)
        local l = New(3)
        l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], alpha)
        l:SetPoint(a1, f, r1, x1, y1)
        if a2 then l:SetPoint(a2, f, r2, x2, y2) end
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
    f.fcTheme = t
    return t
end

-- Design auf ein Fenster anwenden bzw. wieder wegnehmen (je nach Einstellung)
function Theme.Apply(f)
    if not f or not f.CreateTexture then return end
    local on = Theme.IsOn()
    local t = f.fcTheme
    if on and not t then t = Build(f) end
    if t then
        for _, x in ipairs(t.list) do x:SetShown(on) end
    end
    -- Titelleiste: bläulich statt grau; beim Ausschalten die alte Farbe zurück
    local h = f.header
    if h and h.SetBackdropColor then
        if on then
            if not f.fcThemeHeader then f.fcThemeHeader = { h:GetBackdropColor() } end
            h:SetBackdropColor(HEADER[1], HEADER[2], HEADER[3], 1)
        elseif f.fcThemeHeader then
            local c = f.fcThemeHeader
            h:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
            f.fcThemeHeader = nil
        end
    end
end

function Theme.Refresh()
    for f in pairs(SHARED.windows or {}) do
        local ok, err = pcall(Theme.Apply, f)
        if not ok and UI.ReportError then UI.ReportError("ForeverCoreUI", "Theme", err) end
    end
end

UI.On("ThemeChanged", Theme.Refresh)

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
