-- ForeverFrames: Einstellungsfenster, Minimap-Button, Slash-Befehl
local ADDON_NAME, ns = ...
local T, GetDB, Safe = ns.T, ns.GetDB, ns.Safe
local UI = ns.UI

---------------------------------------------------------------------------
-- Aenderungen uebernehmen
---------------------------------------------------------------------------
local function Refresh(kind)
    if kind == "layout" then
        ns.ApplyLayout()
        ns.UpdateAllButtons()
    elseif kind == "clicks" then
        ns.ApplyClicks()
    elseif kind == "blizz" then
        ns.HideBlizzard()
        ns.Chat(T("Ausgeblendete Blizzard-Rahmen kommen erst nach /reload zurück.",
            "Hidden Blizzard frames only return after /reload."))
    elseif kind == "mover" then
        ns.UpdateMover()
    else
        ns.UpdateAllButtons()
    end
end

local function KeyGet(key) return function() return GetDB()[key] end end
local function KeySet(key, refresh)
    return function(value)
        GetDB()[key] = value
        Refresh(refresh)
    end
end

local controls = {} -- alle Bedienelemente; :Load() liest den aktuellen Wert
local function Register(c)
    tinsert(controls, c)
    return c
end

local function LoadAll()
    for _, c in ipairs(controls) do
        if c.Load then c:Load() end
    end
end

---------------------------------------------------------------------------
-- Bedienelemente
---------------------------------------------------------------------------
local W = {}

-- Abschnitts-Ueberschrift: etwas groesser, mit dezentem Streifen und feiner Linie darunter,
-- damit zusammengehoerende Einstellungen sichtbar getrennt sind
-- Grundbausteine kommen aus dem gemeinsamen Forever-Stil (ForeverHub.lua)
W.Header = UI.Header
W.Hint = UI.Hint

function W.Button(parent, text, width, onClick)
    return UI.Button(parent, text, width, Safe(T("Einstellungen", "Settings"), onClick))
end

function W.Check(parent, x, y, label, key, refresh)
    local cb = UI.Check(parent, x, y, label, Safe(T("Einstellungen", "Settings"), function(checked)
        GetDB()[key] = checked
        Refresh(refresh)
    end))
    function cb:Load() self:SetChecked(GetDB()[key]) end
    return Register(cb)
end

-- Schieberegler mit – / +; mult: Anzeige = Wert * mult (z. B. 100 fuer Prozent)
function W.Slider(parent, x, y, label, key, minV, maxV, step, refresh, opts)
    opts = opts or {}
    local mult, unit, width = opts.mult or 1, opts.unit or "", opts.width or 170
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", x, y)

    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 14)
    s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    if UI.StyleSlider then
        UI.StyleSlider(s)
    else
        s:SetBackdrop({
            bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 },
        })
        s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    end
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    local function Show(value)
        local shown = value * mult
        if math.abs(shown - math.floor(shown + 0.5)) < 0.001 then
            title:SetText(string.format("%s: %d%s", label, math.floor(shown + 0.5), unit))
        else
            title:SetText(string.format("%s: %.1f%s", label, shown, unit))
        end
    end

    s:SetScript("OnValueChanged", Safe(T("Einstellungen", "Settings"), function(self, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if self.loading then return end
        if GetDB()[key] ~= value then
            GetDB()[key] = value
            Refresh(refresh)
        end
    end))

    local minus = W.Button(parent, "–", 20, function() s:SetValue(s:GetValue() - step) end)
    minus:SetPoint("LEFT", s, "RIGHT", 6, 0)
    local plus = W.Button(parent, "+", 20, function() s:SetValue(s:GetValue() + step) end)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)

    function s:Load()
        self.loading = true
        self:SetValue(GetDB()[key])
        Show(GetDB()[key])
        self.loading = false
    end
    return Register(s)
end

-- Auswahlliste (Blizzard-Menue); get/set als Funktionen, damit auch Klick-Zauber-Zeilen sie nutzen koennen
function W.Choice(parent, x, y, width, choices, get, set, label)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width + (label and 110 or 0), 22)

    local offset = 0
    if label then
        local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 0, 0)
        fs:SetWidth(106)
        fs:SetJustifyH("LEFT")
        fs:SetText(label)
        offset = 110
    end

    local b = UI.Button(holder, "", width)
    b:SetPoint("LEFT", offset, 0)
    if UI.AddArrow then UI.AddArrow(b) end
    holder.button = b

    local function Label(value)
        local list = type(choices) == "function" and choices() or choices
        for _, c in ipairs(list) do
            if c.key == value then return c.label end
        end
        return tostring(value or "")
    end

    function holder:Load()
        b:SetText(Label(get()))
        local fs = b:GetFontString()
        if fs and not UI.AddArrow then fs:SetWidth(width - 12) fs:SetWordWrap(false) end
    end

    b:SetScript("OnClick", Safe(T("Einstellungen", "Settings"), function()
        local list = type(choices) == "function" and choices() or choices
        if UI.ChoiceMenu and UI.ChoiceMenu(b, list, get, function(key)
            set(key)
            holder:Load()
        end) then return end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(b, function(_, root)
                -- lange Listen (z. B. Texturen anderer Addons) scrollbar machen
                if #list > 20 and root.SetScrollMode then root:SetScrollMode(400) end
                for _, c in ipairs(list) do
                    root:CreateRadio(c.label,
                        function() return get() == c.key end,
                        function()
                            set(c.key)
                            holder:Load()
                        end)
                end
            end)
        else
            -- Ersatz ohne Menue: der Reihe nach durchschalten
            local cur, nextKey = get(), list[1].key
            for i, c in ipairs(list) do
                if c.key == cur then nextKey = (list[i + 1] or list[1]).key end
            end
            set(nextKey)
            holder:Load()
        end
    end))
    return holder
end

function W.KeyChoice(parent, x, y, label, key, choices, refresh, width)
    return Register(W.Choice(parent, x, y, width or 150, choices, KeyGet(key), KeySet(key, refresh), label))
end

-- Farbfeld: Klick oeffnet Blizzards Farbwahl
function W.Color(parent, x, y, label, key, hasAlpha, refresh)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", x, y)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    fs:SetText(label)

    function b:Load()
        local c = GetDB()[key]
        self:SetBackdropColor(c[1], c[2], c[3], 1)
    end

    local function Store(r, g, bl, a)
        local c = GetDB()[key]
        c[1], c[2], c[3] = r, g, bl
        if hasAlpha then c[4] = a end
        b:Load()
        Refresh(refresh)
    end

    b:SetScript("OnClick", Safe(T("Farbwahl", "Color picker"), function()
        local c = GetDB()[key]
        local function Changed()
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            local a = hasAlpha and ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or c[4]
            Store(r, g, bl, a)
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3],
            opacity = c[4] or 1,
            hasOpacity = hasAlpha,
            swatchFunc = Changed,
            opacityFunc = Changed,
            cancelFunc = function(prev)
                if prev then Store(prev.r, prev.g, prev.b, prev.a or prev.opacity) end
            end,
        })
    end))
    return Register(b)
end

-- Position eines Elements: Ankerpunkt + X/Y nebeneinander
local function PositionRows(parent, x, y, prefix, refresh)
    W.KeyChoice(parent, x, y, T("Position", "Position"), prefix .. "Point", ns.POINTS, refresh, 150)
    W.Slider(parent, x, y - 30, "X", prefix .. "X", -60, 60, 1, refresh, { width = 90 })
    W.Slider(parent, x + 150, y - 30, "Y", prefix .. "Y", -60, 60, 1, refresh, { width = 90 })
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
-- Seite im zentralen Einstellungsfenster von Forever Core (verhält sich wie das bisherige eigene Fenster)
local options = UI.SettingsPanel("ForeverFramesOptions", T("ForeverFrames – Einstellungen", "ForeverFrames – Settings"), 680, 670,
    { key = "ForeverFrames", group = UI.SETTINGS_GROUPS.frames, label = T("Gruppe & Raid", "Party & raid") })

local tabs, panels = {}, {}
local function SelectTab(index)
    for i, p in ipairs(panels) do
        p:SetShown(i == index)
        if tabs[i].SetEnabled then tabs[i]:SetEnabled(i ~= index) end
    end
end

local function AddTab(title)
    local index = #panels + 1
    local p = CreateFrame("Frame", nil, options)
    p:SetPoint("TOPLEFT", 10, -92)
    p:SetPoint("BOTTOMRIGHT", -10, 44)
    p:Hide()
    p.fcReveal = function() SelectTab(index) end -- Einstellungssuche des Hubs springt in diesen Reiter
    -- kein eigener Rahmen um den Reiter: die Abschnitte haben ihre eigenen Kaesten (ForeverHub)
    panels[index] = p
    local t = W.Button(options, title, 90, function() SelectTab(index) end)
    t:SetPoint("TOPLEFT", 14 + (index - 1) * 94, -30)
    tabs[index] = t
    return p
end

local L, R = 8, 340 -- linke / rechte Spalte

---------------------------------------------------------------------------
-- Gruppe / Schlachtzug: welche Rahmen die Reiter darunter einstellen. Solange das Menue offen ist, zeigen die
-- Rahmen (und der Testmodus) die gewaehlten Einstellungen; danach gilt wieder die echte Lage.
---------------------------------------------------------------------------
local modeButtons = {}
local modeHint
local function UpdateModeButtons()
    local mode = ns.previewMode or ns.ActiveMode()
    for key, b in pairs(modeButtons) do
        if b.SetEnabled then b:SetEnabled(key ~= mode) end
    end
    local shared = T("Gemeinsam für beide: Sperren, Raster, Einrasten, Klick-Zauber, eigene Buff-Listen, Blizzard-Rahmen.",
        "Shared by both: lock, grid, snap, click casting, own buff lists, Blizzard frames.")
    modeHint:SetText(shared)
end

local function SelectMode(mode)
    ns.previewMode = mode
    -- Testmodus passend zur Ansicht: 5 Spieler in der Gruppe, mindestens 20 im Schlachtzug
    if (ns.testCount or 0) > 0 and not InCombatLockdown() then
        ns.SetTestMode(mode == "raid" and math.max(20, ns.testCount) or 5)
    end
    ns.ApplyMode(true)
    UpdateModeButtons()
    LoadAll()
end

do
    local label = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 16, -66)
    label:SetText(T("Einstellungen für:", "Settings for:"))
    local prev = label
    for _, m in ipairs({ { key = "party", text = T("Gruppe", "Party") }, { key = "raid", text = T("Schlachtzug", "Raid") } }) do
        local b = W.Button(options, m.text, 100, function() SelectMode(m.key) end)
        b:SetPoint("LEFT", prev, "RIGHT", prev == label and 10 or 4, 0)
        modeButtons[m.key] = b
        prev = b
    end
    modeHint = options:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    modeHint:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    modeHint:SetPoint("RIGHT", options, "RIGHT", -16, 0)
    modeHint:SetJustifyH("LEFT")
    modeHint:SetWordWrap(true)
end

---------------------------------------------------------------------------
-- Reiter 1: Rahmen
---------------------------------------------------------------------------
do
    local p = AddTab(T("Rahmen", "Frames"))
    W.Header(p, L, -4, T("Größe und Anordnung", "Size and layout"))
    W.Slider(p, L, -26, T("Breite", "Width"), "width", 30, 250, 1, "layout", { unit = " px" })
    W.Slider(p, L, -66, T("Höhe", "Height"), "height", 16, 150, 1, "layout", { unit = " px" })
    W.Slider(p, L, -106, T("Abstand zwischen Spielern", "Spacing between players"), "spacing", 0, 20, 1, "layout", { unit = " px" })
    W.Slider(p, L, -146, T("Abstand zwischen Gruppen", "Spacing between groups"), "groupSpacing", 0, 50, 1, "layout", { unit = " px" })
    W.Slider(p, L, -186, T("Skalierung", "Scale"), "scale", 0.5, 2, 0.05, "layout", { mult = 100, unit = " %" })
    W.Slider(p, L, -226, T("Gruppen pro Reihe", "Groups per row"), "groupsPerRow", 1, 8, 1, "layout")
    W.KeyChoice(p, L, -272, T("Anordnung", "Arrangement"), "growth", {
        { key = "DOWN", label = T("Spieler untereinander", "Players stacked") },
        { key = "RIGHT", label = T("Spieler nebeneinander", "Players side by side") },
    }, "layout", 170)

    -- Abstände: zwischen dem letzten Element eines Kastens und der nächsten Überschrift mind. ~24 px, sonst
    -- überdecken sich die Kästen (der Hub zeichnet sie bis zur nächsten Überschrift)
    W.Header(p, L, -320, T("Testmodus (ohne Gruppe einstellen)", "Test mode (configure without a group)"))
    local prev
    for i, n in ipairs({ 5, 10, 20, 40, 0 }) do
        local b = W.Button(p, n == 0 and T("Aus", "Off") or tostring(n), 52, function() ns.SetTestMode(n) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", L, -340) end
        prev = b
    end

    W.Header(p, R, -4, T("Verhalten", "Behaviour"))
    W.Check(p, R, -24, T("Rahmen sperren", "Lock frames"), "locked", "mover")
    W.Check(p, R, -48, T("Auch ohne Gruppe anzeigen", "Show when solo"), "showSolo", "layout")
    W.Check(p, R, -72, T("Mich selbst in der Gruppe zeigen", "Show myself in the group"), "showPlayer", "layout")
    W.Check(p, R, -96, T("Nach Rolle sortieren (Tank, Heiler, DD)", "Sort by role (tank, healer, damage)"), "sortByRole", "layout")
    W.Check(p, R, -120, T("Tooltip beim Überfahren", "Tooltip on mouseover"), "tooltip")
    W.Check(p, R, -144, T("Spieler außer Reichweite ausblenden", "Fade players out of range"), "rangeFade")
    W.Slider(p, R + 4, -172, T("Sichtbarkeit außer Reichweite", "Visibility out of range"), "rangeAlpha", 0.05, 1, 0.05, nil, { mult = 100, unit = " %" })

    W.Header(p, R, -236, T("Blizzard-Rahmen", "Blizzard frames"))
    W.Check(p, R, -256, T("Blizzard-Gruppenrahmen ausblenden", "Hide Blizzard party frames"), "hideBlizzParty", "blizz")
    W.Check(p, R, -280, T("Blizzard-Raidrahmen ausblenden", "Hide Blizzard raid frames"), "hideBlizzRaid", "blizz")
    W.Check(p, R, -304, T("Blizzard-Raid-Manager ausblenden", "Hide Blizzard raid manager"), "hideBlizzManager", "blizz")
    W.Hint(p, R + 4, -332, 300, T("Ausgeblendete Blizzard-Rahmen kommen erst nach /reload zurück. " ..
        "Größe und Anordnung ändern sich im Kampf erst nach dem Kampf.",
        "Hidden Blizzard frames only return after /reload. Size and layout changes made in combat apply after combat."))

    -- Position (linke obere Ecke) per Zahl, Raster und Einrasten
    W.Header(p, L, -392, T("Position (obere linke Ecke ab Bildschirmrand)", "Position (top left corner from screen edge)"))
    local function PosGet(i)
        return function()
            local pos = GetDB().pos
            if pos then return pos[i] end
            local left, top = ns.anchor:GetLeft(), ns.anchor:GetTop()
            if i == 1 then return left and UI.Round(left) or 0 end
            return top and UI.Round(top - UIParent:GetTop()) or 0
        end
    end
    local function PosSet(i)
        return Safe(T("Einstellungen", "Settings"), function(v)
            local x, y = PosGet(1)(), PosGet(2)()
            if i == 1 then x = v else y = v end
            ns.SetPosition(x, y)
        end)
    end
    local posX = Register(UI.Number(p, L + 4, -416, "X", PosGet(1), PosSet(1)))
    local posY = Register(UI.Number(p, L + 150, -416, "Y", PosGet(2), PosSet(2)))
    function ns.OnMoved()
        posX:Load()
        posY:Load()
    end
    W.Check(p, L, -444, T("Raster beim Ziehen und hier", "Grid while dragging and here"), "gridShow", "mover")
    W.Check(p, L, -468, T("Einrasten (Umschalt beim Ziehen = aus)", "Snap (Shift while dragging = off)"), "snap")
    W.Hint(p, L + 4, -496, 300, T("Raster und Einrasten wirken nur, wenn die Rahmen entsperrt sind.",
        "Grid and snapping only apply while the frames are unlocked."))
end

---------------------------------------------------------------------------
-- Reiter 2: Optik
---------------------------------------------------------------------------
do
    local p = AddTab(T("Optik", "Look"))
    W.Header(p, L, -4, T("Balken", "Bars"))
    W.KeyChoice(p, L, -26, T("Textur", "Texture"), "texture", ns.TextureChoices, nil, 170)
    W.KeyChoice(p, L, -56, T("Lebensbalken", "Health bar"), "barColorMode", {
        { key = "class", label = T("Klassenfarbe", "Class color") },
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
    }, nil)
    W.Color(p, L + 4, -84, T("Eigene Farbe Lebensbalken", "Custom health bar color"), "barColor", false)
    W.KeyChoice(p, L, -110, T("Fehlende LP", "Missing health"), "lossColorMode", {
        { key = "dark", label = T("Dunkle Klassenfarbe", "Dark class color") },
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
    }, nil)
    W.Color(p, L + 4, -138, T("Eigene Farbe fehlende LP", "Custom missing health color"), "lossColor", false)
    W.Color(p, L + 4, -164, T("Rand / Hintergrund", "Border / background"), "borderColor", true)
    W.Slider(p, L, -190, T("Randstärke", "Border size"), "borderSize", 0, 4, 1, nil, { unit = " px" })

    W.Header(p, L, -256, T("Energiebalken", "Power bar"))
    W.KeyChoice(p, L, -278, T("Anzeigen", "Show"), "powerMode", {
        { key = "all", label = T("Bei allen", "For everyone") },
        { key = "mana", label = T("Nur Mana", "Mana only") },
        { key = "none", label = T("Aus", "Off") },
    }, nil)
    W.Slider(p, L, -308, T("Höhe", "Height"), "powerHeight", 1, 20, 1, nil, { unit = " px" })

    W.Header(p, L, -370, T("Begleiter (Pet)", "Pet"))
    W.Check(p, L + 150, -367, T("anzeigen", "show"), "petShow", "layout")
    W.KeyChoice(p, L, -392, T("Position", "Position"), "petPosition", {
        { key = "RIGHT", label = T("Rechts neben dem Spieler", "Right of the player") },
        { key = "LEFT", label = T("Links neben dem Spieler", "Left of the player") },
        { key = "INSIDE", label = T("Im Rahmen (rechts)", "Inside the frame (right)") },
    }, "layout", 170)
    W.Slider(p, L, -422, T("Breite", "Width"), "petWidth", 3, 30, 1, "layout", { unit = " px" })
    W.KeyChoice(p, L, -462, T("Farbe", "Color"), "petColorMode", {
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
        { key = "owner", label = T("Klassenfarbe Besitzer", "Owner class color") },
    }, nil, 150)
    W.Color(p, L + 270, -464, "", "petColor", false)
    W.Check(p, L, -490, T("Umgekehrt (fehlende LP leeren sich unten)", "Reversed (missing health empties at the bottom)"), "petReverse")

    W.Header(p, R, -4, T("Heilung und Schilde", "Healing and shields"))
    W.Check(p, R, -24, T("Heilvorhersage (Blizzard)", "Heal prediction (Blizzard)"), "healPrediction")
    W.Color(p, R + 220, -27, "", "healColor", true)
    W.Check(p, R, -48, T("Schilde (Absorption)", "Shields (absorbs)"), "shields")
    W.Color(p, R + 220, -51, "", "shieldColor", true)
    W.KeyChoice(p, R + 4, -74, T("Schild-Anzeige", "Shield display"), "shieldStyle", {
        { key = "after", label = T("Hinter den LP", "After health") },
        { key = "right", label = T("Von rechts", "From the right") },
    }, "layout", 130)
    W.Check(p, R, -100, T("Heilabsorption", "Heal absorbs"), "healAbsorbs")
    W.Color(p, R + 220, -103, "", "healAbsorbColor", true)

    W.Header(p, R, -140, T("Hervorhebungen", "Highlights"))
    W.Check(p, R, -160, T("Aktuelles Ziel umranden", "Border around target"), "targetHighlight")
    W.Color(p, R + 220, -163, "", "targetColor", true)
    W.Check(p, R, -184, T("Mouseover aufhellen", "Brighten on mouseover"), "mouseoverHighlight")
    W.Check(p, R, -208, T("Aggro-Rand (auch Begleiter)", "Aggro border (pets too)"), "aggroBorder")
    W.Color(p, R + 220, -211, "", "aggroColor", true)
    W.Check(p, R, -232, T("Wenig Leben: Balken orange / rot", "Low health: bar orange / red"), "healthGradient")

    W.Header(p, R, -282, T("Begleiter-Beschriftung (senkrecht)", "Pet label (vertical)"))
    W.KeyChoice(p, R + 4, -304, T("Anzeigen", "Show"), "petLabel", {
        { key = "name", label = T("Name des Begleiters", "Pet name") },
        { key = "pet", label = "\"Pet\"" },
        { key = "none", label = T("Aus", "Off") },
    }, nil, 150)
    W.Slider(p, R + 4, -334, T("Schriftgröße", "Font size"), "petLabelSize", 6, 14, 1, nil)
    W.Hint(p, R + 4, -372, 300, T("Lange Namen werden auf die Höhe des Rahmens gekürzt.",
        "Long names are shortened to the frame height."))
end

---------------------------------------------------------------------------
-- Reiter 3: Texte
---------------------------------------------------------------------------
do
    local p = AddTab(T("Texte", "Texts"))
    W.KeyChoice(p, L, -4, T("Schriftart", "Font"), "font", ns.FontChoices, nil, 140)
    W.KeyChoice(p, L + 270, -4, T("Umriss", "Outline"), "fontOutline", ns.OUTLINES, nil, 120)
    W.Check(p, L + 520, -3, T("Schatten", "Shadow"), "fontShadow")

    -- Name (links oben)
    local y = -40
    W.Header(p, L, y, T("Name", "Name"))
    W.Check(p, L + 120, y + 3, T("anzeigen", "show"), "nameShow")
    W.Slider(p, L, y - 22, T("Größe", "Size"), "nameSize", 6, 30, 1, nil)
    PositionRows(p, L, y - 60, "name")
    W.KeyChoice(p, L, y - 132, T("Farbe", "Color"), "nameColorMode", {
        { key = "white", label = T("Weiß", "White") },
        { key = "class", label = T("Klassenfarbe", "Class color") },
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
    }, nil, 120)
    W.Color(p, L + 240, y - 134, "", "nameColor", false)
    W.Slider(p, L, y - 162, T("Max. Zeichen (0 = alle)", "Max. characters (0 = all)"), "nameMaxChars", 0, 20, 1, nil)

    -- Status (links unten)
    y = -276
    W.Header(p, L, y, T("Status (Tot / Offline / AFK)", "Status (dead / offline / AFK)"))
    W.Check(p, L + 220, y + 3, T("anzeigen", "show"), "statusShow")
    W.Slider(p, L, y - 22, T("Größe", "Size"), "statusSize", 6, 30, 1, nil)
    PositionRows(p, L, y - 60, "status")

    -- Lebenspunkte-Text (rechts oben)
    y = -40
    W.Header(p, R, y, T("Lebenspunkte-Text", "Health text"))
    W.Check(p, R + 160, y + 3, T("anzeigen", "show"), "hpShow")
    W.KeyChoice(p, R, y - 22, T("Format", "Format"), "hpFormat", {
        { key = "percent", label = T("Prozent (85%)", "Percent (85%)") },
        { key = "current", label = T("Aktuell (2.4K)", "Current (2.4K)") },
        { key = "deficit", label = T("Fehlend (-350)", "Deficit (-350)") },
        { key = "curmax", label = T("Aktuell/Max", "Current/max") },
        { key = "curpercent", label = T("Aktuell + Prozent", "Current + percent") },
    }, nil, 150)
    W.Slider(p, R, y - 50, T("Größe", "Size"), "hpSize", 6, 30, 1, nil)
    PositionRows(p, R, y - 88, "hp")
    W.KeyChoice(p, R, y - 160, T("Farbe", "Color"), "hpColorMode", {
        { key = "white", label = T("Weiß", "White") },
        { key = "class", label = T("Klassenfarbe", "Class color") },
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
    }, nil, 120)
    W.Color(p, R + 240, y - 162, "", "hpColor", false)
    W.Check(p, R, y - 186, T("Kurzform (12.3K)", "Short (12.3K)"), "hpShort")
    W.Check(p, R + 150, y - 186, T("Bei vollen LP leer", "Empty at full health"), "hpHideFull")

    -- Energie-Text (rechts unten)
    y = -276
    W.Header(p, R, y, T("Energie-Text", "Power text"))
    W.Check(p, R + 160, y + 3, T("anzeigen", "show"), "powerTextShow")
    W.KeyChoice(p, R, y - 22, T("Format", "Format"), "powerTextFormat", {
        { key = "percent", label = T("Prozent", "Percent") },
        { key = "current", label = T("Aktuell", "Current") },
    }, nil, 150)
    W.Slider(p, R, y - 50, T("Größe", "Size"), "powerTextSize", 6, 30, 1, nil)
    PositionRows(p, R, y - 88, "powerText")

    -- Hinweis in einem eigenen Kasten über beide Spalten (sonst ragt er aus dem linken Kasten heraus)
    W.Header(p, L, -458, T("Im Kampf", "In combat"), 648)
    W.Hint(p, L + 4, -478, 636, T("Hinweis: Im Kampf sind Lebenspunkte für Addons gesperrt. Dann zeigt der Text " ..
        "eine vereinfachte Form (\"Bei vollen LP leer\" wirkt erst wieder nach dem Kampf).",
        "Note: in combat, health values are locked for addons. The text then uses a simplified form " ..
        "(\"Empty at full health\" applies again after combat)."))
end

---------------------------------------------------------------------------
-- Reiter 4: Symbole
---------------------------------------------------------------------------
do
    local p = AddTab(T("Symbole", "Icons"))
    local function Block(x, y, title, prefix, extra)
        W.Header(p, x, y, title)
        W.Check(p, x + 200, y + 3, T("anzeigen", "show"), prefix .. "Show")
        W.Slider(p, x, y - 22, T("Größe", "Size"), prefix .. "Size", 6, 40, 1, nil)
        PositionRows(p, x, y - 60, prefix)
        if extra then extra(x, y - 130) end
    end
    Block(L, -4, T("Rolle (Tank/Heiler)", "Role (tank/healer)"), "role", function(x, y)
        W.Check(p, x, y, T("Schaden-Symbol ausblenden", "Hide damage icon"), "roleHideDamager")
    end)
    Block(R, -4, T("Anführer / Assistent", "Leader / assistant"), "leader")
    Block(L, -200, T("Zielmarkierung", "Raid marker"), "mark")
    Block(R, -200, T("Bereitschaftscheck", "Ready check"), "ready", function(x, y)
        W.Check(p, x, y, T("Vor dem Namen (statt Position oben)", "Before the name (instead of position above)"), "readyAtName")
        W.Check(p, x, y - 24, T("Wiederbelebung / Beschwörung unterwegs", "Incoming resurrection / summon"), "incomingShow")
        W.Hint(p, x + 4, y - 50, 300, T("Erscheint am Platz des Bereitschaftschecks.", "Shown in the ready check spot."))
    end)
end

---------------------------------------------------------------------------
-- Gemeinsam fuer Debuffs/Buffs
---------------------------------------------------------------------------
local GROW_CHOICES = {
    { key = "RIGHT", label = T("nach rechts", "to the right") },
    { key = "LEFT", label = T("nach links", "to the left") },
    { key = "UP", label = T("nach oben", "upwards") },
    { key = "DOWN", label = T("nach unten", "downwards") },
}

---------------------------------------------------------------------------
-- Reiter 5: Debuffs
---------------------------------------------------------------------------
do
    local p = AddTab("Debuffs")
    W.Header(p, L, -4, T("Debuff-Symbole", "Debuff icons"))
    W.KeyChoice(p, L, -26, T("Anzeigen", "Show"), "debuffMode", {
        { key = "all", label = T("Alle Debuffs", "All debuffs") },
        { key = "dispellable", label = T("Nur bannbare", "Dispellable only") },
        { key = "off", label = T("Aus", "Off") },
    }, nil, 150)
    W.Slider(p, L, -56, T("Anzahl", "Count"), "debuffNum", 1, ns.MAX_AURA_ICONS, 1, nil)
    W.Slider(p, L, -96, T("Größe", "Size"), "debuffSize", 8, 40, 1, nil, { unit = " px" })
    PositionRows(p, L, -136, "debuff")
    W.KeyChoice(p, L, -204, T("Weitere Symbole", "More icons"), "debuffGrow", GROW_CHOICES, nil, 150)
    W.Check(p, L, -232, T("Rand am Symbol in Typfarbe", "Icon border in type color"), "debuffTypeBorder")
    W.Check(p, L, -256, T("Ablaufzeit anzeigen", "Show remaining time"), "debuffCooldown")
    W.Hint(p, L + 4, -284, 300, T("Bannbare Debuffs (die du entfernen kannst) stehen immer vorne.",
        "Dispellable debuffs (that you can remove) always come first."))

    W.Header(p, L, -334, T("Restzeit auf den Symbolen (Debuffs und Buffs)", "Remaining time on icons (debuffs and buffs)"))
    W.Check(p, L, -354, T("Countdown-Scheibe", "Countdown swipe"), "auraTimerSwipe")
    W.Check(p, L, -378, T("Restzeit als Zahl", "Remaining time as number"), "auraTimerNumbers")
    W.Slider(p, L + 4, -406, T("Größe der Zahl", "Number size"), "auraTimerSize", 6, 20, 1, nil)

    W.Check(p, L, -448, T("Blizzard-Anzeige (aktualisiert auch im Kampf)", "Blizzard display (also updates in combat)"), "auraEngine")
    W.Check(p, L, -472, T("Tooltip auf Debuffs und Buffs", "Tooltip on debuffs and buffs"), "auraTooltip")

    W.Header(p, R, -4, T("Bannbare Debuffs hervorheben", "Highlight dispellable debuffs"))
    W.Check(p, R, -24, T("Nur was ich bannen kann", "Only what I can dispel"), "dispelOnlyMine")
    W.Check(p, R, -48, T("Typ-Symbol (Magie, Fluch …)", "Type icon (magic, curse …)"), "dispelShow")
    W.Slider(p, R + 4, -76, T("Größe Typ-Symbol", "Type icon size"), "dispelSize", 8, 40, 1, nil, { unit = " px" })
    PositionRows(p, R + 4, -116, "dispel")
    W.Check(p, R, -184, T("Rahmen um den Rahmen in Typfarbe", "Frame border in type color"), "dispelBorder")
    W.Slider(p, R + 4, -212, T("Rahmenstärke", "Border size"), "dispelBorderSize", 1, 6, 1, nil, { unit = " px" })

    W.Header(p, R, -276, T("Farben je Typ", "Colors per type"))
    local y = -298
    for i, t in ipairs(ns.DEBUFF_TYPES) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        W.Color(p, R + 4 + col * 150, y - row * 26, t.label, t.key, false)
    end
    W.Color(p, R + 4 + 150, y - 2 * 26, T("Ohne Typ", "No type"), "colorNone", false)

    -- Hinweis rechts in einem eigenen Kasten (über die ganze Breite ragte er aus dem linken Kasten heraus)
    W.Header(p, R, -396, T("Im Kampf", "In combat"))
    W.Hint(p, R + 4, -416, 300, T("Blizzard sperrt die Aura-Daten für Addons – die Symbole zeichnet dann die Blizzard-Anzeige. " ..
        "Typ-Symbol und Typ-Rahmen werden nach dem Kampf wieder aktualisiert. Klick-Zauber auf den Symbolen gehen auch mit Tooltip.",
        "Blizzard locks aura data for addons – the Blizzard display draws the icons then. " ..
        "Type icon and type border update again after combat. Click casting on the icons works with tooltips too."))
end

---------------------------------------------------------------------------
-- Reiter 6: Buffs
---------------------------------------------------------------------------
do
    local p = AddTab("Buffs")
    W.Header(p, L, -4, T("Buff-Symbole", "Buff icons"))
    W.KeyChoice(p, L, -26, T("Anzeigen", "Show"), "buffMode", {
        { key = "hots", label = T("Meine HoTs + Klassenliste", "My HoTs + class list") },
        { key = "custom", label = T("Nur eigene Liste", "Own list only") },
        { key = "both", label = T("HoTs + Klassen- + eigene Liste", "HoTs + class + own list") },
        { key = "off", label = T("Aus", "Off") },
    }, nil, 150)
    W.Slider(p, L, -56, T("Anzahl", "Count"), "buffNum", 1, ns.MAX_AURA_ICONS, 1, nil)
    W.Slider(p, L, -96, T("Größe", "Size"), "buffSize", 8, 40, 1, nil, { unit = " px" })
    PositionRows(p, L, -136, "buff")
    W.KeyChoice(p, L, -204, T("Weitere Symbole", "More icons"), "buffGrow", GROW_CHOICES, nil, 150)
    W.Check(p, L, -232, T("Ablaufzeit anzeigen", "Show remaining time"), "buffCooldown")
    W.Check(p, L, -256, T("HoTs/Schutz-Buffs anderer Spieler", "HoTs/protective buffs of others"), "buffOthers")
    W.Hint(p, L + 4, -284, 300, T("Alle Klassen, z. B. Verjüngung eines Druiden, Erneuerung eines Priesters. Dauerhafte Buffs wie Seelenstärke werden nie gezeigt.",
        "All classes, e.g. a druid's Rejuvenation, a priest's Renew. Permanent buffs like Fortitude are never shown."))
    W.Check(p, L, -326, T("Blizzard-Anzeige (aktualisiert auch im Kampf)", "Blizzard display (also updates in combat)"), "auraEngine")
    W.Check(p, L + 4, -350, T("Dazu kurze eigene Buffs (unter 2 Min.)", "Plus short own buffs (under 2 min)"), "buffEngineShort")

    W.Header(p, L, -398, T("Klassenliste (eingebaut)", "Class list (built-in)"))
    local classInfo = W.Hint(p, L + 4, -418, 300, "")
    classInfo:SetFontObject("GameFontHighlightSmall")
    Register({ Load = function() classInfo:SetText(ns.GetClassBuffLabels()) end })
    -- direkt unter der (unterschiedlich langen) Klassenliste
    local classHint = W.Hint(p, nil, nil, 300, "")
    classHint:SetPoint("TOPLEFT", classInfo, "BOTTOMLEFT", 0, -8)
    classHint:SetText(T("Fehlt dir ein Zauber? Trag ihn rechts in die eigene Liste ein und wähle \"HoTs + Klassen- + eigene Liste\".",
        "Missing a spell? Add it to your own list on the right and pick \"HoTs + class + own list\"."))

    W.Header(p, R, -4, T("Eigene Liste (für deine aktuelle Klasse)", "Own list (for your current class)"))
    W.Hint(p, R + 4, -22, 300, T("Zaubernamen oder Zauber-IDs, durch Komma oder neue Zeile getrennt. Beispiel: Erneuerung, Verjüngung, 774",
        "Spell names or spell IDs, separated by comma or new line. Example: Renew, Rejuvenation, 774"))

    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", R + 4, -54)
    box:SetSize(300, 150)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, 0.5)
    box:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    if UI.SetFlat and UI.COLOR then UI.SetFlat(box, UI.COLOR.input) end

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetPoint("TOPLEFT", 6, -6)
    edit:SetPoint("BOTTOMRIGHT", -6, 6)
    edit:SetMaxLetters(1000)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", Safe("Buffs", function(self)
        ns.SetCustomBuffText(self:GetText())
        ns.UpdateAllButtons()
    end))
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    Register({ Load = function() if not edit:HasFocus() then edit:SetText(ns.GetCustomBuffText()) end end })

    W.Check(p, R, -212, T("Liste: nur von mir gewirkte Buffs", "List: only buffs cast by me"), "buffCustomMine")
    W.Hint(p, R + 4, -240, 300, T("Klick außerhalb des Feldes übernimmt die Liste. Hinweis: Im Kampf kann Blizzard Zaubernamen " ..
        "sperren – dann werden nur Buffs aus der Liste erkannt, die Blizzard freigibt.",
        "Click outside the box to apply the list. Note: in combat Blizzard may lock spell names – then only " ..
        "list buffs that Blizzard allows can be recognised."))
end

---------------------------------------------------------------------------
-- Reiter 7: Klick-Zauber
---------------------------------------------------------------------------
local RefreshClickRows
do
    local p = AddTab(T("Klick-Zauber", "Click casting"))
    W.Header(p, L, -4, T("Klick auf einen Rahmen: Maustaste + Taste » Aktion", "Click on a frame: mouse button + key » action"), 648)
    W.Hint(p, L, -22, 640, T("Gilt für deine aktuelle Klasse. Zauber per Name (höchster Rang) – über \"…\" aus dem Zauberbuch wählen. " ..
        "Makro-Beispiel: /cast [@mouseover] Erneuerung. Änderungen im Kampf gelten nach dem Kampf.",
        "Applies to your current class. Spells by name (highest rank) – pick from the spellbook with \"…\". " ..
        "Macro example: /cast [@mouseover] Renew. Changes made in combat apply after combat."))

    local MAX_ROWS = 14
    local rows = {}
    local function Binding(i) return ns.GetBindings()[i] end

    local function Changed()
        ns.ApplyClicks()
        RefreshClickRows()
    end

    for i = 1, MAX_ROWS do
        local y = -50 - (i - 1) * 28
        local row = {}
        row.mouse = W.Choice(p, L, y, 120, ns.MOUSE_BUTTONS,
            function() return Binding(i) and Binding(i).button end,
            function(v) Binding(i).button = v Changed() end)
        row.mod = W.Choice(p, L + 124, y, 100, ns.MODIFIERS,
            function() return Binding(i) and Binding(i).mod end,
            function(v) Binding(i).mod = v Changed() end)
        row.action = W.Choice(p, L + 228, y, 130, ns.ACTIONS,
            function() return Binding(i) and Binding(i).action end,
            function(v) Binding(i).action = v Changed() end)

        local edit = UI.EditBox and UI.EditBox(p, 170, 20) or CreateFrame("EditBox", nil, p, "InputBoxTemplate")
        edit:SetSize(170, 20)
        edit:SetPoint("TOPLEFT", L + 368, y - 1)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnEscapePressed", function(self)
            self:SetText(Binding(i) and Binding(i).value or "")
            self:ClearFocus()
        end)
        edit:SetScript("OnEditFocusLost", Safe(T("Klick-Zauber", "Click casting"), function(self)
            local bd = Binding(i)
            if bd and bd.value ~= self:GetText() then
                bd.value = self:GetText()
                ns.ApplyClicks()
            end
        end))
        row.edit = edit

        row.pick = W.Button(p, "…", 26, function()
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(row.pick, function(_, root)
                for _, s in ipairs(ns.GetSpellbookSpells()) do
                    local label = s.icon and ("|T" .. s.icon .. ":14:14|t " .. s.name) or s.name
                    root:CreateButton(label, function()
                        local bd = Binding(i)
                        if not bd then return end
                        bd.value = s.name
                        if bd.action ~= "spell" and bd.action ~= "macro" then bd.action = "spell" end
                        Changed()
                    end)
                end
            end)
        end)
        row.pick:SetPoint("LEFT", edit, "RIGHT", 4, 0)

        row.del = W.Button(p, "X", 26, function()
            table.remove(ns.GetBindings(), i)
            Changed()
        end)
        row.del:SetPoint("LEFT", row.pick, "RIGHT", 2, 0)
        rows[i] = row
    end

    local add = W.Button(p, T("+ Neue Belegung", "+ New binding"), 150, function()
        local list = ns.GetBindings()
        if #list >= MAX_ROWS then return end
        tinsert(list, { button = 1, mod = "shift-", action = "spell", value = "" })
        Changed()
    end)
    add:SetPoint("TOPLEFT", L, -50 - MAX_ROWS * 28 - 6)

    local reset = W.Button(p, T("Standard (Ziel + Menü)", "Default (target + menu)"), 170, function()
        local _, class = UnitClass("player")
        GetDB().clicks[class or "ALL"] = nil
        Changed()
    end)
    reset:SetPoint("LEFT", add, "RIGHT", 8, 0)

    function RefreshClickRows()
        local list = ns.GetBindings()
        for i, row in ipairs(rows) do
            local bd = list[i]
            local shown = bd ~= nil
            for _, w in ipairs({ row.mouse, row.mod, row.action, row.edit, row.pick, row.del }) do
                w:SetShown(shown)
            end
            if bd then
                row.mouse:Load()
                row.mod:Load()
                row.action:Load()
                if not row.edit:HasFocus() then row.edit:SetText(bd.value or "") end
                local needsValue = bd.action == "spell" or bd.action == "macro"
                if needsValue then row.edit:Enable() else row.edit:Disable() end
                row.edit:SetAlpha(needsValue and 1 or 0.4)
            end
        end
    end
    p:SetScript("OnShow", Safe(T("Klick-Zauber", "Click casting"), RefreshClickRows))
end

---------------------------------------------------------------------------
-- Untere Leiste
---------------------------------------------------------------------------
local statusBtn = W.Button(options, T("Selbsttest", "Self-test"), 100, function() ns.RunStatus() end)
statusBtn:SetPoint("BOTTOMLEFT", 16, 14)

local resetPos = W.Button(options, T("Position zurücksetzen", "Reset position"), 160, function()
    GetDB().pos = nil
    ns.RestorePosition()
    if ns.OnMoved then ns.OnMoved() end
end)
resetPos:SetPoint("LEFT", statusBtn, "RIGHT", 6, 0)

-- Alle Einstellungen auf Standard (inkl. Position). Behalten werden nur die eigenen Inhalte:
-- Klick-Zauber-Belegungen, eigene Buff-Listen und die Lage des Minimap-Buttons.
local KEEP_ON_RESET = { clicks = true, buffCustom = true, minimapAngle = true }

local function ResetAll()
    local db = ns.GetBaseDB() -- Gruppe und gemeinsame Werte; der Schlachtzug startet danach wieder als Kopie
    for key, value in pairs(ns.DEFAULTS) do
        if not KEEP_ON_RESET[key] then db[key] = ns.CopyValue(value) end
    end
    db.pos = nil
    db.raid = nil
    ns.RestorePosition()
    ns.ApplyLayout()
    ns.UpdateAllButtons()
    ns.UpdateMover()
    LoadAll()
    ns.Chat(T("Alle Einstellungen sind auf Standard zurückgesetzt (Klick-Zauber und eigene Buff-Listen bleiben erhalten).",
        "All settings have been reset to default (click casting and own buff lists are kept)."))
    if InCombatLockdown() then
        ns.Chat(T("Größe und Position werden nach dem Kampf übernommen.", "Size and position apply after combat."))
    end
end

StaticPopupDialogs["FOREVERFRAMES_RESET_ALL"] = {
    text = T("ForeverFrames: Wirklich ALLE Einstellungen (inkl. Position) auf Standard zurücksetzen?\n\n" ..
        "Klick-Zauber und eigene Buff-Listen bleiben erhalten.",
        "ForeverFrames: Really reset ALL settings (incl. position) to default?\n\n" ..
        "Click casting and own buff lists are kept."),
    button1 = YES,
    button2 = NO,
    OnAccept = Safe(T("Zurücksetzen", "Reset"), ResetAll),
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local resetAll = W.Button(options, T("Alles zurücksetzen", "Reset everything"), 150, function()
    StaticPopup_Show("FOREVERFRAMES_RESET_ALL")
end)
resetAll:SetPoint("LEFT", resetPos, "RIGHT", 6, 0)

local closeBtn = W.Button(options, T("Schließen", "Close"), 100, function() options:Hide() end)
closeBtn:SetPoint("BOTTOMRIGHT", -16, 14)

options:SetScript("OnShow", Safe(T("Einstellungen", "Settings"), function()
    -- beim Öffnen: die Einstellungen der gerade echten Lage (Gruppe bzw. Schlachtzug)
    ns.previewMode = IsInRaid() and "raid" or "party"
    UpdateModeButtons()
    LoadAll()
    if not options.tabChosen then
        options.tabChosen = true
        SelectTab(1)
    end
    ns.UpdateGrid()
end))
options:HookScript("OnHide", function()
    pcall(ns.UpdateGrid)
    -- wieder die echte Lage zeigen
    ns.previewMode = nil
    pcall(ns.ApplyMode)
end)

function ns.ToggleOptions()
    options:SetShown(not options:IsShown())
end

---------------------------------------------------------------------------
-- Selbsttest (/ff status)
---------------------------------------------------------------------------
function ns.RunStatus()
    local function Line(ok, label, detail)
        ns.Chat(string.format("%s %s%s", ok and "|cff33ff33[OK]|r" or "|cffffcc00[!]|r", label,
            detail and ("  – " .. detail) or ""))
    end
    Line(ns.savedVarsLoaded, T("Gespeicherte Einstellungen geladen", "Saved settings loaded"),
        not ns.savedVarsLoaded and T("nein – Beta-Bug? Standardwerte aktiv", "no – beta bug? using defaults") or nil)
    Line(#ns.buttons > 0, T("Rahmen angelegt", "Frames created"), tostring(#ns.buttons))
    Line(CreateUnitHealPredictionCalculator ~= nil, T("Blizzard-Heilvorhersage", "Blizzard heal prediction"))
    Line(issecretvalue ~= nil, T("Erkennung geheimer Werte", "Secret value detection"))
    local engineOK = ns.auraEngine and ns.auraEngine.Supported()
    Line(engineOK, T("Blizzard-Anzeige für Auren (AuraContainer)", "Blizzard aura display (AuraContainer)"),
        engineOK and (GetDB().auraEngine and T("aktiv", "active") or T("ausgeschaltet", "turned off"))
        or T("auf diesem Client nicht verfügbar", "not available on this client"))
    local n = 0
    for _ in ipairs(ns.GetBindings()) do n = n + 1 end
    Line(true, T("Klick-Zauber-Belegungen", "Click casting bindings"), tostring(n))
    Line(ns.errorCount == 0, T("Fehler seit dem Login", "Errors since login"), tostring(ns.errorCount))
end

-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverFrames", function() return GetDB().locked end, function(locked)
        GetDB().locked = locked
        ns.UpdateMover()
        if options:IsShown() then LoadAll() end
    end)
end

---------------------------------------------------------------------------
-- Minimap-Button
---------------------------------------------------------------------------
do
    local mm = UI.MinimapButton({
        name = "ForeverFramesMinimapButton",
        icon = "Interface\\AddOns\\ForeverFrames\\Media\\ForeverFrames",
        title = "ForeverFrames",
        angle = function() return GetDB().minimapAngle end,
        setAngle = function(a) GetDB().minimapAngle = a end,
        onClick = Safe("Minimap", function(_, button)
            if button == "RightButton" then
                local db = GetDB()
                db.locked = not db.locked
                ns.UpdateMover()
                ns.Chat(db.locked and T("Rahmen gesperrt.", "Frames locked.")
                    or T("Rahmen entsperrt – an der blauen Leiste ziehen.", "Frames unlocked – drag the blue bar."))
            else
                ns.ToggleOptions()
            end
        end),
        lines = function()
            return {
                T("Linksklick: Einstellungen", "Left-click: settings"),
                T("Rechtsklick: Rahmen sperren/entsperren", "Right-click: lock/unlock frames"),
            }
        end,
    })
    ns.UpdateMinimapPosition = mm.UpdatePosition

    ns.On("PLAYER_LOGIN", "Minimap", mm.UpdatePosition)
end

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------
SLASH_FOREVERFRAMES1 = "/ff"
SLASH_FOREVERFRAMES2 = "/foreverframes"
SlashCmdList["FOREVERFRAMES"] = Safe(T("Befehl", "Command"), function(msg)
    msg = strtrim(msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    if cmd == "lock" then
        local db = GetDB()
        db.locked = not db.locked
        ns.UpdateMover()
        ns.Chat(db.locked and T("Rahmen gesperrt.", "Frames locked.") or T("Rahmen entsperrt.", "Frames unlocked."))
    elseif cmd == "test" then
        local n = tonumber(arg) or ((ns.testCount or 0) > 0 and 0 or 5)
        ns.SetTestMode(math.max(0, math.min(40, n)))
    elseif cmd == "status" then
        ns.RunStatus()
    else
        ns.ToggleOptions()
    end
end)
