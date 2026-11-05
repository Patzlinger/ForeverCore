-- ForeverUnits: Einstellungsfenster, Minimap-Knopf, Slash-Befehl
local ADDON_NAME, ns = ...
local T, GetDB, Safe, UI = ns.T, ns.GetDB, ns.Safe, ns.UI

---------------------------------------------------------------------------
-- Bedienelemente (alle mit get/set, damit sie fuer jeden Rahmen funktionieren)
---------------------------------------------------------------------------
local controls = {}
local function Register(c) controls[#controls + 1] = c return c end
local function LoadAll()
    for _, c in ipairs(controls) do c:Load() end
end

local function Apply() ns.ApplyAll() end
local SETTINGS = T("Einstellungen", "Settings")

-- Werte: global oder vom gerade gewaehlten Rahmen
local editKey = "player"
local function G(key)
    return { get = function() return GetDB()[key] end, set = function(v) GetDB()[key] = v end }
end
local function F(key)
    return { get = function() return ns.FrameDB(editKey)[key] end, set = function(v) ns.FrameDB(editKey)[key] = v end }
end

local function Check(p, x, y, label, acc, after)
    local cb = UI.Check(p, x, y, label, Safe(SETTINGS, function(checked)
        acc.set(checked)
        ;(after or Apply)()
    end))
    function cb:Load() self:SetChecked(acc.get() and true or false) end
    return Register(cb)
end

local function Slider(p, x, y, label, minV, maxV, step, acc, opts)
    local s = UI.Slider(p, x, y, label, minV, maxV, step, Safe(SETTINGS, function(v)
        acc.set(v)
        Apply()
    end), opts)
    Register({ Load = function() s:Load(acc.get()) end })
    return s
end

-- Zahlenfeld mit –/+ fuer genaue Werte (aus ForeverHub.lua)
local function Number(p, x, y, label, acc)
    return Register(UI.Number(p, x, y, label, acc.get, Safe(SETTINGS, function(v)
        acc.set(v)
        Apply()
    end)))
end

-- Auswahlliste (Blizzard-Menue)
local function Choice(p, x, y, label, width, choices, acc, after)
    local holder = CreateFrame("Frame", nil, p)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width + 110, 22)
    local fs = UI.Text(holder, "label", label)
    fs:SetPoint("LEFT", 0, 0)
    fs:SetWidth(106)
    local b = UI.Button(holder, "", width)
    b:SetPoint("LEFT", 110, 0)
    if UI.AddArrow then UI.AddArrow(b) end

    local function List() return type(choices) == "function" and choices() or choices end
    function holder:Load()
        local cur, text = acc.get(), nil
        for _, c in ipairs(List()) do if c.key == cur then text = c.label end end
        b:SetText(text or tostring(cur or ""))
        local bfs = b:GetFontString()
        if bfs and not UI.AddArrow then bfs:SetWidth(width - 12) bfs:SetWordWrap(false) end
    end
    local function Pick(key)
        acc.set(key)
        holder:Load()
        ;(after or Apply)()
    end
    b:SetScript("OnClick", Safe(SETTINGS, function()
        local list = List()
        if UI.ChoiceMenu and UI.ChoiceMenu(b, list, acc.get, Pick) then return end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(b, function(_, root)
                if #list > 20 and root.SetScrollMode then root:SetScrollMode(400) end
                for _, c in ipairs(list) do
                    root:CreateRadio(c.label, function() return acc.get() == c.key end, function() Pick(c.key) end)
                end
            end)
        else
            local cur, nextKey = acc.get(), list[1].key
            for i, c in ipairs(list) do
                if c.key == cur then nextKey = (list[i + 1] or list[1]).key end
            end
            Pick(nextKey)
        end
    end))
    return Register(holder)
end

-- Farbfeld: Klick oeffnet Blizzards Farbwahl
local function Color(p, x, y, label, key, hasAlpha)
    local b = CreateFrame("Button", nil, p, "BackdropTemplate")
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", x, y)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    local fs = UI.Text(p, "label", label)
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    function b:Load()
        local c = GetDB()[key]
        self:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    local function Store(r, g, bl, a)
        local c = GetDB()[key]
        c[1], c[2], c[3] = r, g, bl
        if hasAlpha then c[4] = a end
        b:Load()
        Apply()
    end
    b:SetScript("OnClick", Safe(T("Farbwahl", "Color picker"), function()
        local c = GetDB()[key]
        local function Changed()
            local r, g, bl = ColorPickerFrame:GetColorRGB()
            local a = hasAlpha and ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or c[4]
            Store(r, g, bl, a)
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = hasAlpha,
            swatchFunc = Changed, opacityFunc = Changed,
            cancelFunc = function(prev) if prev then Store(prev.r, prev.g, prev.b, prev.a or prev.opacity) end end,
        })
    end))
    return Register(b)
end

---------------------------------------------------------------------------
-- Fenster mit Reitern
---------------------------------------------------------------------------
-- Seite im zentralen Einstellungsfenster von Forever Core UI (verhält sich wie das bisherige eigene Fenster)
local options = UI.SettingsPanel("ForeverUnitsOptions", T("ForeverUnits – Einstellungen", "ForeverUnits – Settings"), 660, 640,
    { key = "ForeverUnits", group = UI.SETTINGS_GROUPS.frames, label = T("Einheitenrahmen", "Unit frames") })

local tabs, panels = {}, {}
local function SelectTab(index)
    for i, p in ipairs(panels) do
        p:SetShown(i == index)
        tabs[i]:SetEnabled(i ~= index)
    end
end

local function AddTab(title)
    local index = #panels + 1
    local p = CreateFrame("Frame", nil, options)
    p:SetPoint("TOPLEFT", 10, -62)
    p:SetPoint("BOTTOMRIGHT", -10, 14)
    p:Hide()
    p.fcReveal = function() SelectTab(index) end -- Einstellungssuche des Hubs springt in diesen Reiter
    -- kein eigener Rahmen um den Reiter: die Abschnitte haben ihre eigenen Kaesten (ForeverHub)
    panels[index] = p
    local t = UI.Button(options, title, 100, function() SelectTab(index) end)
    t:SetPoint("TOPLEFT", 14 + (index - 1) * 104, -30)
    tabs[index] = t
    return p
end

local L, R = 8, 330 -- linke / rechte Spalte

---------------------------------------------------------------------------
-- Reiter 1: Allgemein
---------------------------------------------------------------------------
do
    local p = AddTab(T("Allgemein", "General"))
    UI.Header(p, L, -4, T("Bedienung", "Controls"))
    -- Abstände: zwischen dem letzten Element eines Kastens und der nächsten Überschrift mind. ~24 px, und Texte
    -- nicht breiter als die Spalte – sonst überdecken sich die Kästen (der Hub zeichnet sie bis zur nächsten Überschrift)
    Check(p, L, -24, T("Rahmen sperren (entsperrt verschiebbar)", "Lock frames (unlocked: drag to move)"), G("locked"))
    Check(p, L, -48, T("Tooltip beim Überfahren", "Tooltip on mouseover"), G("tooltip"))
    local resetPos = UI.Button(p, T("Positionen zurücksetzen", "Reset positions"), 180, Safe(SETTINGS, function()
        for key, f in pairs(GetDB().frames) do
            f.x, f.y = ns.DEFAULTS.frames[key].x, ns.DEFAULTS.frames[key].y
        end
        Apply()
    end))
    resetPos:SetPoint("TOPLEFT", L + 4, -80)

    UI.Header(p, L, -128, T("Symbole und Farben", "Icons and colors"))
    Check(p, L, -148, T("PvP-Symbol (wenn PvP aktiv ist)", "PvP icon (when PvP is active)"), G("pvpShow"))
    Check(p, L, -172, T("Anführer-Krone", "Leader crown"), G("leaderShow"))
    Check(p, L, -196, T("Zielmarkierung", "Raid marker"), G("markShow"))
    Check(p, L, -220, T("Ausruhen-Symbol (Gasthaus/Hauptstadt)", "Resting icon (inn/capital)"), G("restingShow"))
    Check(p, L, -244, T("NPCs in Reaktionsfarbe (rot/gelb)", "NPCs in reaction color (red/yellow)"), G("npcReactionColor"))

    UI.Header(p, L, -290, T("Auren", "Auras"))
    Check(p, L, -310, T("Restzeit als Scheibe", "Remaining time as swipe"), G("auraTimer"))
    Check(p, L, -334, T("Tooltip auf Auren (Klicks gehen durch)", "Tooltip on auras (clicks pass through)"), G("auraTooltip"))
    Check(p, L, -358, T("DoT-Leisten nur bei angreifbaren Zielen", "DoT bars only on attackable targets"), G("dotOnlyHostile"))

    UI.Header(p, L, -404, T("Ausrichten (wenn entsperrt)", "Alignment (when unlocked)"))
    Check(p, L, -424, T("Raster anzeigen", "Show grid"), G("gridShow"))
    Check(p, L, -448, T("Einrasten (Rahmen, Mitte, Raster)", "Snap (frames, center, grid)"), G("snap"))
    Slider(p, L, -478, T("Rasterabstand", "Grid spacing"), 8, 128, 4, G("gridSize"), { unit = " px" })
    UI.Hint(p, L + 4, -518, 300, T("Beim Ziehen Umschalt halten = ohne Einrasten. Genaue Position: X/Y im Reiter Rahmen.",
        "Hold Shift while dragging = no snapping. Exact position: X/Y in the Frames tab."))

    UI.Header(p, R, -4, T("Blizzard-Rahmen ausblenden", "Hide Blizzard frames"))
    local function Blizz() ns.HideBlizzard() end
    Check(p, R, -24, T("Spieler", "Player"), G("hideBlizzPlayer"), Blizz)
    Check(p, R, -48, T("Ziel (inkl. Ziel des Ziels)", "Target (incl. target of target)"), G("hideBlizzTarget"), Blizz)
    Check(p, R, -72, T("Fokus", "Focus"), G("hideBlizzFocus"), Blizz)
    Check(p, R, -96, T("Begleiter", "Pet"), G("hideBlizzPet"), Blizz)
    UI.Hint(p, R + 4, -126, 300, T("Ausgeblendete Blizzard-Rahmen kommen erst nach /reload zurück.",
        "Hidden Blizzard frames only return after /reload."))

    UI.Header(p, R, -180, T("Alles", "Everything"))
    StaticPopupDialogs["FOREVERUNITS_RESET"] = {
        text = T("Alle Einstellungen von ForeverUnits zurücksetzen?", "Reset all ForeverUnits settings?"),
        button1 = YES, button2 = NO,
        OnAccept = function()
            ns.ResetAll()
            Apply()
            LoadAll()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local resetAll = UI.Button(p, T("Alles zurücksetzen", "Reset everything"), 180, function()
        StaticPopup_Show("FOREVERUNITS_RESET")
    end)
    resetAll:SetPoint("TOPLEFT", R + 4, -202)
    Check(p, R, -228, T("Kampf-Marker (Schwerter)", "Combat marker (swords)"), G("combatMarker"))

    UI.Header(p, R, -252, T("Kombopunkte (Ziel)", "Combo points (target)"))
    Check(p, R, -272, T("Kombopunkte anzeigen", "Show combo points"), G("comboShow"))
    Choice(p, R, -300, T("Ort", "Place"), 170, {
        { key = "PORTRAIT", label = T("Spalte außen am Porträt", "Column outside the portrait") },
        { key = "BELOW",    label = T("Balken mit Strichen unten", "Bar with segments below") },
        { key = "ABOVE",    label = T("Punkte oben", "Dots above") },
    }, G("comboPoint"))
    Check(p, R, -328, T("Leere Punkte zeigen (angreifbares Ziel)", "Show empty points (attackable target)"), G("comboShowEmpty"))
    Slider(p, R, -358, T("Größe", "Size"), 4, 16, 1, G("comboSize"), { unit = " px" })
    UI.Hint(p, R + 4, -398, 300, T("Nur für Schurken und Druiden (Katzengestalt). Entsperrt zeigt ein Platzhalter die Lage.",
        "Rogues and druids (cat form) only. When unlocked, a placeholder shows where they sit."))
end

---------------------------------------------------------------------------
-- Reiter 2: Rahmen (Einstellungen pro Rahmen)
---------------------------------------------------------------------------
do
    local p = AddTab(T("Rahmen", "Frames"))
    local frameChoices = {}
    for _, info in ipairs(ns.UNITS) do frameChoices[#frameChoices + 1] = { key = info.key, label = info.label } end
    Choice(p, L, -4, T("Rahmen bearbeiten", "Edit frame"), 170, frameChoices,
        { get = function() return editKey end, set = function(v) editKey = v end }, LoadAll)

    UI.Header(p, L, -40, T("Größe", "Size"))
    Check(p, L, -60, T("Rahmen anzeigen", "Show frame"), F("enabled"))
    Slider(p, L, -90, T("Breite", "Width"), 60, 400, 2, F("width"), { unit = " px" })
    Slider(p, L, -130, T("Höhe", "Height"), 14, 80, 1, F("height"), { unit = " px" })
    Slider(p, L, -170, T("Energiebalken (0 = aus)", "Power bar (0 = off)"), 0, 20, 1, F("powerHeight"), { unit = " px" })
    Slider(p, L, -210, T("Schriftgröße", "Font size"), 7, 20, 1, F("fontSize"))

    UI.Header(p, L, -270, T("Porträt", "Portrait"))
    Choice(p, L, -292, T("Anzeigen", "Show"), 170, {
        { key = "none", label = T("Aus", "Off") },
        { key = "class", label = T("Klassensymbol (NPCs: Porträt)", "Class icon (NPCs: portrait)") },
        { key = "portrait", label = T("2D-Porträt", "2D portrait") },
    }, F("portrait"))
    Choice(p, L, -320, T("Seite", "Side"), 170, {
        { key = "LEFT", label = T("Links", "Left") },
        { key = "RIGHT", label = T("Rechts", "Right") },
    }, F("portraitSide"))

    UI.Header(p, L, -368, T("DoT-Leisten (nur Ziel und Fokus)", "DoT bars (target and focus only)"))
    Check(p, L, -388, T("Meine DoTs als Leisten, kürzeste oben", "My DoTs as bars, shortest on top"), F("dotBars"))
    Choice(p, L, -414, T("Leiste", "Bar"), 170, {
        { key = "drain", label = T("Läuft ab (Restzeit)", "Drains (time left)") },
        { key = "fill", label = T("Füllt sich (vergangene Zeit)", "Fills (time passed)") },
    }, F("dotDirection"))
    Choice(p, L, -440, T("Position", "Position"), 170, {
        { key = "BELOW", label = T("Unter dem Rahmen", "Below the frame") },
        { key = "ABOVE", label = T("Über dem Rahmen", "Above the frame") },
        { key = "LEFT", label = T("Links daneben", "To the left") },
        { key = "RIGHT", label = T("Rechts daneben", "To the right") },
        { key = "FREE", label = T("Frei verschiebbar", "Free (movable)") },
    }, F("dotPoint"))
    Slider(p, L, -468, "X", -200, 200, 1, F("dotX"), { width = 110 })
    Slider(p, L + 160, -468, "Y", -200, 200, 1, F("dotY"), { width = 90 })
    Slider(p, L, -504, T("Anzahl", "Count"), 1, 10, 1, F("dotNum"), { width = 110 })
    Slider(p, L + 160, -504, T("Höhe", "Height"), 10, 30, 1, F("dotHeight"), { width = 90, unit = " px" })
    Slider(p, L, -540, T("Breite (0 = wie Rahmen)", "Width (0 = like frame)"), 0, 400, 2, F("dotWidth"), { unit = " px" })
    UI.Header(p, R, -448, T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)"))
    Number(p, R + 4, -470, "X", F("x"))
    Number(p, R + 150, -470, "Y", F("y"))

    local dotHint = UI.Hint(p, R + 4, -506, 300, "")
    Register({ Load = function()
        dotHint:SetText(ns.dotBarBinding
            and T("DoT-Leisten: Restzeit läuft als Balken und Zahl. Zahl orange = Auffrischfenster (unter 30 %), rot = gleich vorbei.",
                "DoT bars: remaining time runs as bar and number. Orange number = refresh window (below 30 %), red = about to expire.")
            or T("DoT-Leisten: Zahl orange = Auffrischfenster (unter 30 %), rot = gleich vorbei. Ob der Balken sichtbar abläuft, zeigt sich beim ersten DoT.",
                "DoT bars: orange number = refresh window (below 30 %), red = about to expire. Whether the bar runs visibly shows with the first DoT."))
    end })

    UI.Header(p, R, -40, T("Texte", "Texts"))
    Choice(p, R, -62, T("Anordnung", "Layout"), 170, {
        { key = "stacked", label = T("Name oben, LP darunter", "Name on top, health below") },
        { key = "inline", label = T("Alles in einer Zeile", "All in one line") },
    }, F("textLayout"))
    Check(p, R, -88, T("Name", "Name"), F("nameShow"))
    Check(p, R, -112, T("Stufe + Elite/Rar", "Level + elite/rare"), F("levelShow"))
    Check(p, R + 160, -112, T("Elite/Rar-Symbol", "Elite/rare icon"), F("classIcon"))
    Choice(p, R, -138, T("Lebenspunkte", "Health"), 170, {
        { key = "none", label = T("Aus", "Off") },
        { key = "percent", label = "80%" },
        { key = "cur", label = "12.3K" },
        { key = "curmax", label = "12.3K / 15K" },
        { key = "curpercent", label = "12.3K · 80%" },
        { key = "deficit", label = T("Fehlend (-2.7K)", "Missing (-2.7K)") },
    }, F("hpFormat"))
    Check(p, R, -164, T("Energie als Zahl (ab 7 px Balkenhöhe)", "Power as number (from 7 px bar height)"), F("powerText"))

    Check(p, R, -188, T("Regeneration/s", "Regeneration/s"), G("powerRegen"))
    Check(p, R + 130, -188, T("5-Sekunden-Regel (Strich)", "Five-second rule (marker)"), G("fiveSecRule"))

    UI.Header(p, R, -212, T("Auren", "Auras"))
    Check(p, R, -232, T("Buffs", "Buffs"), F("buffs"))
    Check(p, R, -256, T("Debuffs", "Debuffs"), F("debuffs"))
    Check(p, R, -280, T("Nur meine Debuffs", "Only my debuffs"), F("onlyMine"))
    Slider(p, R, -310, T("Größe", "Size"), 10, 40, 1, F("auraSize"), { unit = " px" })
    Slider(p, R, -350, T("Anzahl", "Count"), 1, 16, 1, F("auraNum"))
    UI.Hint(p, R + 4, -388, 300, T("Mit DoT-Leisten stehen bei \"Nur meine Debuffs\" hier die der anderen. " ..
        "Auren zeichnet die Blizzard-Anzeige – auch im Kampf aktuell.",
        "With DoT bars, \"Only my debuffs\" shows the others' debuffs here. " ..
        "Auras are drawn by the Blizzard display – up to date in combat too."))
end

---------------------------------------------------------------------------
-- Reiter 3: Optik
---------------------------------------------------------------------------
do
    local p = AddTab(T("Optik", "Look"))
    UI.Header(p, L, -4, T("Wie ForeverFrames", "Like ForeverFrames"))
    Check(p, L, -24, T("Optik von ForeverFrames übernehmen", "Use the ForeverFrames look"), G("syncLook"))
    local syncHint = UI.Hint(p, L + 4, -52, 300, "")
    Register({ Load = function()
        syncHint:SetText(ns.HasForeverFrames()
            and T("Textur, Schrift, Rand und Farben kommen dann aus ForeverFrames – Änderungen dort gelten sofort auch hier.",
                "Texture, font, border and colors then come from ForeverFrames – changes there apply here right away.")
            or T("ForeverFrames ist nicht installiert – es gilt die eigene Optik.",
                "ForeverFrames is not installed – your own look below applies."))
    end })

    UI.Header(p, L, -100, T("Eigene Optik", "Own look"))
    Choice(p, L, -122, T("Textur", "Texture"), 170, ns.TextureChoices, G("texture"))
    Choice(p, L, -150, T("Schrift", "Font"), 170, ns.FontChoices, G("font"))
    Choice(p, L, -178, T("Schriftrand", "Font outline"), 170, ns.OUTLINES, G("fontOutline"))
    Slider(p, L, -208, T("Randstärke", "Border size"), 0, 4, 1, G("borderSize"), { unit = " px" })
    Color(p, L + 4, -248, T("Rand / Hintergrund", "Border / background"), "borderColor", true)

    UI.Header(p, R, -4, T("Farben (eigene Optik)", "Colors (own look)"))
    Choice(p, R, -26, T("Lebensbalken", "Health bar"), 170, {
        { key = "class", label = T("Klassenfarbe", "Class color") },
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
    }, G("barColorMode"))
    Color(p, R + 4, -54, T("Eigene Farbe Lebensbalken", "Custom health bar color"), "barColor", false)
    Choice(p, R, -80, T("Fehlende LP", "Missing health"), 170, {
        { key = "dark", label = T("Dunkle Balkenfarbe", "Dark bar color") },
        { key = "custom", label = T("Eigene Farbe", "Custom color") },
    }, G("lossColorMode"))
    Color(p, R + 4, -108, T("Eigene Farbe fehlende LP", "Custom missing health color"), "lossColor", false)
    Check(p, R, -128, T("Trennlinie Leben / Ressource", "Divider line health / resource"), G("powerSeparator"))

    UI.Header(p, R, -152, T("Heilung und Schilde (eigene Optik)", "Healing and shields (own look)"))
    Check(p, R, -172, T("Heilvorhersage", "Heal prediction"), G("healPrediction"))
    Color(p, R + 220, -175, "", "healColor", true)
    Check(p, R, -196, T("Schilde (Absorption)", "Shields (absorbs)"), G("shields"))
    Color(p, R + 220, -199, "", "shieldColor", true)
    Check(p, R, -220, T("HoT-Vorhersage", "HoT prediction"), G("hotPrediction"))
    Check(p, R + 130, -220, T("DoT-Schaden am Ziel", "DoT damage on target"), G("dotPrediction"))

    UI.Header(p, R, -244, T("Skin (Test)", "Skin (test)"))
    Choice(p, R, -266, T("Aussehen", "Style"), 170, {
        { key = "DEFAULT", label = T("Standard", "Default") },
        { key = "FOREVER", label = T("Forever (Test)", "Forever (test)") },
    }, G("skin"))
    UI.Hint(p, R + 4, -294, 300, T("Nur das Aussehen, im Stil der Forever-Fenster: feine Kante mit Goldlinie, dunkle Fugen, gedeckte Balken mit leichtem Glanz, Namensband, goldene/silberne Eckklammern bei Elite/Rare, goldene Kante bei Maus darüber, rote Oberkante am Spieler im Kampf. Funktionen bleiben, wie sie sind.",
        "Look only, in the style of the Forever windows: fine edge with a gold line, dark seams, muted bars with a soft shine, name band, gold/silver corner brackets for elite/rare, gold edge on mouse-over, red top edge on the player in combat. Functions stay as they are."))
end

options:SetScript("OnShow", Safe(SETTINGS, function()
    LoadAll()
    if not options.ffTab then
        options.ffTab = true
        SelectTab(1)
    end
end))

function ns.ToggleOptions()
    options:SetShown(not options:IsShown())
end

-- nach dem Ziehen eines Rahmens: X/Y im offenen Fenster aktualisieren
function ns.OnMoved()
    if options:IsShown() then LoadAll() end
end

---------------------------------------------------------------------------
-- Minimap-Knopf und Befehle
---------------------------------------------------------------------------
local function ToggleLock()
    local d = GetDB()
    d.locked = not d.locked
    Apply()
    if options:IsShown() then LoadAll() end
    ns.Chat(d.locked and T("Rahmen gesperrt.", "Frames locked.")
        or T("Rahmen entsperrt – zum Verschieben ziehen.", "Frames unlocked – drag to move."))
end

-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverUnits", function() return GetDB().locked end, function(locked)
        GetDB().locked = locked
        Apply()
        if options:IsShown() then LoadAll() end
    end)
end

local mm = UI.MinimapButton({
    name = "ForeverUnitsMinimapButton",
    icon = "Interface\\AddOns\\ForeverUnits\\Media\\ForeverUnits",
    title = "ForeverUnits",
    angle = function() return GetDB().minimapAngle end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = Safe("Minimap", function(_, button)
        if button == "RightButton" then ToggleLock() else ns.ToggleOptions() end
    end),
    lines = function()
        return {
            T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Rahmen sperren/entsperren", "Right-click: lock/unlock frames"),
        }
    end,
})
ns.On("PLAYER_LOGIN", "Minimap", mm.UpdatePosition)

SLASH_FOREVERUNITS1 = "/fu"
SLASH_FOREVERUNITS2 = "/foreverunits"
SlashCmdList["FOREVERUNITS"] = Safe(T("Befehl", "Command"), function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" then
        ToggleLock()
    elseif msg == "reset" then
        for key, f in pairs(GetDB().frames) do
            f.x, f.y = ns.DEFAULTS.frames[key].x, ns.DEFAULTS.frames[key].y
        end
        Apply()
        ns.Chat(T("Positionen zurückgesetzt.", "Positions reset."))
    else
        ns.ToggleOptions()
    end
end)
