-- ForeverPlates: Seite im gemeinsamen Einstellungsfenster (Gruppe "Rahmen") mit zwei Reitern, Minimap-Knopf
-- und Befehl /fplates
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI
local T = UI.T
local Safe = ns.Safe

local ToggleOptions
do
    local options = UI.SettingsPanel("ForeverPlatesOptions", T("ForeverPlates – Einstellungen", "ForeverPlates – Settings"), 720, 800,
        { key = "ForeverPlates", group = UI.SETTINGS_GROUPS.frames, label = T("Namensplaketten", "Nameplates") })
    local W = 330
    local controls = {}

    -- Reiter (wie ForeverUnits): Knöpfe oben, je Reiter ein Bereich
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
        p:SetPoint("TOPLEFT", 0, -38) -- etwas Luft zwischen Reiter-Knöpfen und den Kästen
        p:SetPoint("BOTTOMRIGHT", 0, 40)
        p:Hide()
        p.fcReveal = function() SelectTab(index) end -- Einstellungssuche des Hubs springt in diesen Reiter
        panels[index] = p
        local t = UI.Button(options, title, 110, function() SelectTab(index) end)
        t:SetPoint("TOPLEFT", 14 + (index - 1) * 114, -32)
        tabs[index] = t
        return p
    end

    -- Spalten mit fortlaufender Höhe: Abschnitt, Haken (eingerückt = Unterpunkt), Regler
    local parent
    local col = { x = 18, y = -32 }
    local function Column(x) col.x, col.y = x, -32 end
    local function Header(text)
        UI.Header(parent, col.x, col.y, text, W)
        col.y = col.y - 22
    end
    local function Check(label, key, sub, after)
        local cb = UI.Check(parent, col.x - 4 + (sub and 18 or 0), col.y, label, Safe(T("Einstellungen", "Settings"),
            function(checked)
                ns.GetDB()[key] = checked
                if after then after() end
                ns.ApplyAll()
            end))
        controls[#controls + 1] = { cb = cb, key = key }
        col.y = col.y - 24
        return cb
    end
    local function Slider(label, key, minV, maxV, step, unit, sub, format, after)
        local s = UI.Slider(parent, col.x + (sub and 18 or 0), col.y - 4, label, minV, maxV, step,
            Safe(T("Einstellungen", "Settings"), function(v)
                ns.GetDB()[key] = v
                if after then after() end
                ns.ApplyAll()
            end), { width = 180, unit = unit, format = format })
        controls[#controls + 1] = { slider = s, key = key }
        col.y = col.y - 42
        return s
    end
    -- Abstand zum nächsten Abschnitt: mind. ~22 px, sonst überdecken sich die Kästen (der Hub zeichnet sie bis zur
    -- nächsten Überschrift)
    local function Gap() col.y = col.y - 22 end
    local function Hint(text, height)
        UI.Hint(parent, col.x + 18, col.y - 2, W - 24, text)
        col.y = col.y - height
    end
    -- Farbfeld rechts neben dem nächsten Haken: Klick öffnet Blizzards Farbwahl
    local function ColorSwatch(key)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(18, 18)
        b:SetPoint("TOPLEFT", col.x + 230, col.y)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
        local function Load()
            local c = ns.GetDB()[key]
            b:SetBackdropColor(c[1], c[2], c[3], 1)
        end
        local function Store(r, g, bl)
            local c = ns.GetDB()[key]
            c[1], c[2], c[3] = r, g, bl
            Load()
            ns.ApplyAll()
        end
        b:SetScript("OnClick", Safe(T("Farbwahl", "Color picker"), function()
            local c = ns.GetDB()[key]
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c[1], g = c[2], b = c[3], hasOpacity = false,
                swatchFunc = function() Store(ColorPickerFrame:GetColorRGB()) end,
                cancelFunc = function(prev) if prev then Store(prev.r, prev.g, prev.b) end end,
            })
        end))
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(T("Farbe wählen", "Choose color"))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        controls[#controls + 1] = { refresh = Load }
        return b
    end
    -- Auswahl: Beschriftung links, Knopf mit Pfeil rechts, Liste wie im Hub
    local function Choice(label, key, listFn)
        local fs = UI.Text(parent, "label", label)
        fs:SetPoint("TOPLEFT", col.x, col.y - 4)
        local b = UI.Button(parent, "", 170, nil)
        b:SetPoint("TOPLEFT", col.x + 120, col.y)
        if UI.AddArrow then UI.AddArrow(b) end
        local function LabelOf(v)
            for _, e in ipairs(listFn()) do if e.key == v then return e.label end end
            return tostring(v)
        end
        b:SetScript("OnClick", function(self)
            UI.ChoiceMenu(self, listFn(), function() return ns.GetDB()[key] end, function(v)
                ns.GetDB()[key] = v
                self:SetText(LabelOf(v))
                ns.ApplyAll()
            end)
        end)
        controls[#controls + 1] = { refresh = function() b:SetText(LabelOf(ns.GetDB()[key])) end }
        col.y = col.y - 28
    end

    ---------------------------------------------------------------------------
    -- Reiter 1: Anzeige
    ---------------------------------------------------------------------------
    parent = AddTab(T("Anzeige", "Display"))
    Column(18)
    Header(T("Leben", "Health"))
    Check(T("Leben auf der Leiste anzeigen", "Show health on the bar"), "healthText")
    Check(T("als Zahl (links)", "as a number (left)"), "healthValue", true)
    Check(T("in Prozent (rechts)", "in percent (right)"), "healthPercent", true)
    Check(T("nur wenn nicht voll", "only when not full"), "healthOnlyDamaged", true)
    ColorSwatch("executeColor")
    Check(T("Finishing-Bereich färben", "Color the execute range"), "execute")
    Slider(T("Finishing unter", "Execute below"), "executeAt", 5, 50, 5, " %", true)
    Gap()
    Header(T("Bedrohung", "Threat"))
    Check(T("Bedrohung anzeigen", "Show threat"), "threat")
    Check(T("Prozent neben der Leiste", "Percent next to the bar"), "threatText", true)
    Check(T("Leiste in Bedrohungsfarbe (nach Rolle)", "Bar in threat color (by role)"), "threatColorBar", true)
    Check(T("Immer als Tank werten", "Always count me as tank"), "threatTank", true)
    Check(T("Nur in Gruppen (solo aus)", "Only in groups (off when solo)"), "threatGroupOnly", true)
    Hint(T("Schaden/Heilung: grün = sicher, gelb = knapp, orange = Aggro wackelt, rot = du hast Aggro. "
        .. "Tank: umgekehrt (grün = sichere Aggro). Rolle aus der Gruppe oder per Haken.",
        "Damage/healing: green = safe, yellow = close, orange = slipping, red = you have aggro. "
        .. "Tank: reversed (green = solid aggro). Role from your group or the checkbox."), 46)
    Gap()
    Header(T("Sonstiges", "Other"))
    Check(T("Combopunkte auf dem Ziel", "Combo points on your target"), "combo")
    Check(T("Questgegner markieren (! bzw. Questie-Symbol)", "Mark quest mobs (! or Questie icon)"), "quest", false,
        function() ns.ApplyQuestie() end)
    Check(T("„keine Sicht“, wenn ein Zauber am Ziel scheitert", "\"no sight\" when a spell fails on the target"), "los")
    Check(T("Große Raidmarker über der Plakette", "Large raid markers above the plate"), "raidMarker")
    Slider(T("Größe", "Size"), "raidMarkerSize", 16, 40, 2, " px", true)

    Column(374)
    Header(T("Zauberleiste", "Cast bar"))
    Check(T("Eigene schmale Zauberleiste", "Own slim cast bar"), "castbar")
    Check(T("Ziel klein darunter („Ziel“ rot = auf dich)", "Target small below (\"Target\" red = on you)"), "castTarget", true)
    Check(T("Grün, wenn meine Unterbrechung bereit ist", "Green when my interrupt is ready"), "interruptHint", true)
    Slider(T("Höhe", "Height"), "castHeight", 6, 16, 1, " px", true)
    Gap()
    Header(T("Auren", "Auras"))
    Check(T("Schwächungen oben", "Debuffs on top"), "debuffs")
    Check(T("nur meine (DoTs)", "only mine (DoTs)"), "debuffsMine", true)
    Slider(T("Größe", "Size"), "debuffSize", 12, 32, 1, " px", true)
    Check(T("Kontrolleffekte (CC) groß an der Seite", "Crowd control (CC) large at the side"), "cc")
    Check(T("links statt rechts", "left instead of right"), "ccLeft", true)
    Slider(T("Größe", "Size"), "ccSize", 16, 40, 1, " px", true)
    Check(T("Stärkungen anzeigen", "Show buffs"), "buffs")
    Check(T("nur entfernbare (Purge)", "only purgeable"), "buffsPurgeable", true)
    Slider(T("Größe", "Size"), "buffSize", 10, 28, 1, " px", true)
    Gap()
    -- Bedrohungsfarben: eigene Farbe je Stufe (gilt, wenn "Leiste in Bedrohungsfarbe" an ist)
    Header(T("Farben nach Bedrohung", "Colors by threat"))
    Check(T("Eigene Farben (statt nach Rolle)", "Own colors (instead of by role)"), "threatCustom")
    local function ColorRow(label, key)
        local fs = UI.Text(parent, "label", label)
        fs:SetPoint("TOPLEFT", col.x + 18, col.y - 4)
        ColorSwatch(key)
        col.y = col.y - 24
    end
    ColorRow(T("Du hast Aggro", "You have aggro"), "threatColAggro")
    ColorRow(T("Aggro wackelt (du verlierst sie)", "Aggro slipping (you're losing it)"), "threatColLosing")
    ColorRow(T("Aggro droht (du ziehst sie gleich)", "Aggro close (you're about to pull)"), "threatColGaining")
    ColorRow(T("Keine Aggro", "No aggro"), "threatColNone")

    ---------------------------------------------------------------------------
    -- Reiter 2: Aussehen
    ---------------------------------------------------------------------------
    parent = AddTab(T("Aussehen", "Look"))
    Column(18)
    Header(T("Look", "Look"))
    Check(T("Wie ForeverFrames (Textur und Schrift)", "Like ForeverFrames (texture and font)"), "syncLook")
    Choice(T("Leistentextur", "Bar texture"), "texture", function() return ns.TextureChoices() end)
    Choice(T("Schrift", "Font"), "font", function() return ns.FontChoices() end)
    Choice(T("Schriftrand", "Font edge"), "fontOutline", function() return ns.OUTLINES end)
    Slider(T("Schriftgröße", "Font size"), "fontSizeAdd", -2, 4, 1, nil, true,
        function(v) return (v > 0 and "+" or "") .. v end)
    Check(T("Forever-Rahmen (dunkler Grund, feiner Rand)", "Forever frame (dark background, fine border)"), "skin")
    Check(T("Stufe neben dem Namen", "Level next to the name"), "showLevel")
    Check(T("Symbol für Elite, Rar und Boss", "Icon for elite, rare and boss"), "classIcon")
    Check(T("Andere dämpfen, solange ein Ziel gewählt ist", "Dim the others while you have a target"), "dimOthers")
    Gap()
    Header(T("Verbündete", "Allies"))
    Check(T("Nur Name in Klassenfarbe", "Name only, in class color"), "friendlySimple", false,
        function() ns.ApplyFriendly() end)
    Hint(T("Verbündete behalten Blizzards Plakette; in Dungeons und Raids sperrt Blizzard sie für Addons.",
        "Allies keep Blizzard's plate; in dungeons and raids Blizzard locks them for addons."), 34)

    Column(374)
    Header(T("Größe und Lage", "Size and position"))
    Slider(T("Breite", "Width"), "width", 0, 250, 5, " px", true,
        function(v) if v <= 0 then return T("wie Blizzard", "like Blizzard") end end)
    Slider(T("Höhe der Leiste", "Bar height"), "barHeight", 6, 24, 1, " px", true)
    Slider(T("Höher über dem Gegner", "Higher above the enemy"), "offsetY", 0, 60, 2, " px", true)
    Slider(T("Ziel vergrößern", "Enlarge target"), "targetScale", 100, 140, 5, " %", true)
    Check(T("Plaketten stapeln statt überlappen", "Stack plates instead of overlapping"), "stack", false,
        function() ns.ApplyFriendly() end)
    Check(T("Nicht mit der Entfernung verkleinern", "Don't shrink with distance"), "noShrink", false,
        function() ns.ApplyFriendly() end)

    ---------------------------------------------------------------------------
    -- Reiter 3: Schadenszahlen (Blizzards eigene Zahlen über dem Gegner, Core.lua ApplyWorldText)
    ---------------------------------------------------------------------------
    parent = AddTab(T("Schadenszahlen", "Damage text"))
    local function WT() ns.ApplyWorldText() end
    local function Seconds(v) return string.format("%.1f s", v / 10) end
    local function Hundredths(v) return string.format("%.2f", v / 100) end
    Column(18)
    Header(T("Position", "Position"))
    Check(T("Über der Namensplakette aufsteigen", "Rise above the nameplate"), "dmgRaise", false, WT)
    Slider(T("Wie viel höher", "How much higher"), "dmgHeight", 0, 15, 1, " %", true, nil, WT)
    Hint(T("Blizzard zeichnet die Zahlen selbst in der Spielwelt – sie lassen sich nicht an die Plakette hängen, "
        .. "starten aber so weiter oben (Anteil der Bildschirmhöhe). Stil und Bewegung bleiben Blizzards.",
        "Blizzard draws the numbers in the game world itself – they can't be attached to the plate, but this "
        .. "makes them start higher (share of the screen height). Style and motion stay Blizzard's."), 60)
    Gap()
    Header(T("Bewegung (Zusatz)", "Motion (extra)"))
    Check(T("Bewegung selbst einstellen", "Adjust the motion"), "dmgCustom", false, WT)
    Slider(T("Größe", "Size"), "dmgScale", 50, 200, 10, " %", true, nil, WT)
    Slider(T("Dauer", "Duration"), "dmgDuration", 5, 30, 1, nil, true, Seconds, WT)
    Slider(T("Bogen (Schwerkraft)", "Arc (gravity)"), "dmgGravity", 0, 200, 10, nil, true, Hundredths, WT)
    Slider(T("Seitliche Streuung", "Sideways spread"), "dmgSpread", 0, 100, 5, nil, true, Hundredths, WT)
    Check(T("Klassischer Stil", "Classic style"), "dmgClassic", true, WT)
    Hint(T("Aus = wieder Blizzards Werte (deine vorherigen Einstellungen kommen zurück).",
        "Off = Blizzard's values again (your previous settings come back)."), 34)

    Column(374)
    Header(T("Symbol des Zaubers", "Spell icon"))
    Hint(T("Ein Symbol neben der Zahl geht hier nicht: welcher Zauber wie viel Schaden gemacht hat, steht nur im "
        .. "Kampflog – und das ist in diesem Client für Addons gesperrt.",
        "An icon next to the number isn't possible here: which spell did how much damage is only in the combat "
        .. "log – and this client locks it for addons."), 60)

    UI.Hint(options, 18, -764, 680, T(
        "Gegner bekommen eigene Plaketten; Blizzards Plakette bleibt unsichtbar "
        .. "darunter (Position, Klicks). Klickfläche und Abstände: Blizzards Optionen (Esc » Optionen » Namensplaketten).",
        "Enemies get our own plates; Blizzard's plate stays invisible underneath "
        .. "(position, clicks). Click area and spacing: Blizzard's options (Esc » Options » Nameplates)."))

    SelectTab(1)
    options:SetScript("OnShow", function()
        local d = ns.GetDB()
        for _, c in ipairs(controls) do
            if c.cb then c.cb:SetChecked(d[c.key] and true or false) end
            if c.slider then c.slider:Load(d[c.key]) end
            if c.refresh then c.refresh() end
        end
    end)

    function ToggleOptions() options:SetShown(not options:IsShown()) end
    ns.ToggleOptions = ToggleOptions
end

UI.MinimapButton({
    name = "ForeverPlatesMinimapButton",
    icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    title = "ForeverPlates",
    angle = function() return ns.GetDB().minimapAngle end,
    setAngle = function(a) ns.GetDB().minimapAngle = a end,
    onClick = Safe("Minimap", function() ToggleOptions() end),
    lines = function()
        return { T("Linksklick: Einstellungen", "Left-click: settings") }
    end,
})

SLASH_FOREVERPLATES1 = "/fplates"
SLASH_FOREVERPLATES2 = "/foreverplates"
SlashCmdList["FOREVERPLATES"] = Safe("Befehl", function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "skin" then
        local d = ns.GetDB()
        d.skin = not d.skin
        ns.ApplyAll()
        UI.Chat("ForeverPlates", d.skin and T("Forever-Rahmen an.", "Forever frame on.")
            or T("Forever-Rahmen aus.", "Forever frame off."))
    else
        ToggleOptions()
    end
end)
