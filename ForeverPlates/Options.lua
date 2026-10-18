-- ForeverPlates: Seite im gemeinsamen Einstellungsfenster (Gruppe "Rahmen"), Minimap-Knopf und Befehl /fplates
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI
local T = UI.T
local Safe = ns.Safe

local ToggleOptions
do
    local options = UI.SettingsPanel("ForeverPlatesOptions", T("ForeverPlates – Einstellungen (Prototyp)",
        "ForeverPlates – Settings (prototype)"), 720, 800,
        { key = "ForeverPlates", group = UI.SETTINGS_GROUPS.frames, label = T("Namensplaketten", "Nameplates") })
    local W = 330
    local controls = {}

    -- Spalten mit fortlaufender Höhe: Abschnitt, Haken (eingerückt = Unterpunkt), Regler
    local col = { x = 18, y = -32 }
    local function Column(x) col.x, col.y = x, -32 end
    local function Header(text)
        UI.Header(options, col.x, col.y, text, W)
        col.y = col.y - 22
    end
    local function Check(label, key, sub, after)
        local cb = UI.Check(options, col.x - 4 + (sub and 18 or 0), col.y, label, Safe(T("Einstellungen", "Settings"),
            function(checked)
                ns.GetDB()[key] = checked
                if after then after() end
                ns.ApplyAll()
            end))
        controls[#controls + 1] = { cb = cb, key = key }
        col.y = col.y - 24
        return cb
    end
    local function Slider(label, key, minV, maxV, step, unit, sub)
        local s = UI.Slider(options, col.x + (sub and 18 or 0), col.y - 4, label, minV, maxV, step,
            Safe(T("Einstellungen", "Settings"), function(v)
                ns.GetDB()[key] = v
                ns.ApplyAll()
            end), { width = 180, unit = unit })
        controls[#controls + 1] = { slider = s, key = key }
        col.y = col.y - 42
        return s
    end
    local function Gap() col.y = col.y - 12 end

    -- linke Spalte
    Column(18)
    Header(T("Leben", "Health"))
    Check(T("Leben auf der Leiste anzeigen", "Show health on the bar"), "healthText")
    Check(T("als Zahl (links)", "as a number (left)"), "healthValue", true)
    Check(T("in Prozent (rechts)", "in percent (right)"), "healthPercent", true)
    Check(T("nur wenn nicht voll", "only when not full"), "healthOnlyDamaged", true)
    Check(T("auch bei Verbündeten", "on allies too"), "healthFriendly", true)
    Check(T("Finishing-Bereich färben", "Color the execute range"), "execute")
    Slider(T("Finishing unter", "Execute below"), "executeAt", 5, 50, 5, " %", true)
    Gap()
    Header(T("Bedrohung", "Threat"))
    Check(T("Bedrohung anzeigen", "Show threat"), "threat")
    Check(T("Prozent neben der Leiste", "Percent next to the bar"), "threatText", true)
    Check(T("Leiste in Bedrohungsfarbe (nach Rolle)", "Bar in threat color (by role)"), "threatColorBar", true)
    Check(T("Immer als Tank werten", "Always count me as tank"), "threatTank", true)
    UI.Hint(options, col.x + 18, col.y - 2, W - 24, T(
        "Schaden/Heilung: grün = sicher, gelb = knapp, orange = Aggro wackelt, rot = du hast Aggro. "
        .. "Tank: umgekehrt (grün = sichere Aggro). Rolle aus der Gruppe oder per Haken.",
        "Damage/healing: green = safe, yellow = close, orange = slipping, red = you have aggro. "
        .. "Tank: reversed (green = solid aggro). Role from your group or the checkbox."))
    col.y = col.y - 46
    Gap()
    Header(T("Zauberleiste", "Cast bar"))
    Check(T("Eigene schmale Zauberleiste", "Own slim cast bar"), "castbar")
    Check(T("Ziel-Plakette am Ende (rot = auf dich)", "Target tag at the end (red = on you)"), "castTarget", true)
    Check(T("Grün, wenn meine Unterbrechung bereit ist", "Green when my interrupt is ready"), "interruptHint", true)
    Slider(T("Höhe", "Height"), "castHeight", 6, 16, 1, " px", true)

    -- rechte Spalte
    Column(374)
    Header(T("Aussehen", "Look"))
    Check(T("Forever-Stil (flach, dunkel, Ziel mit Goldrand)", "Forever style (flat, dark, target with gold edge)"), "skin")
    UI.Hint(options, col.x + 18, col.y - 2, W - 24, T(
        "Aus: Blizzards Plaketten mit unseren Zusätzen. An: dieselben Plaketten im Look der Forever-Fenster.",
        "Off: Blizzard's nameplates with our additions. On: the same nameplates in the Forever window look."))
    col.y = col.y - 34
    Gap()
    Header(T("Auren", "Auras"))
    Check(T("Schwächungen oben", "Debuffs on top"), "debuffs")
    Check(T("nur meine (DoTs)", "only mine (DoTs)"), "debuffsMine", true)
    Slider(T("Größe", "Size"), "debuffSize", 12, 32, 1, " px", true)
    Slider(T("Anzahl", "Count"), "debuffMax", 1, 10, 1, nil, true)
    Check(T("Kontrolleffekte (CC) groß an der Seite", "Crowd control (CC) large at the side"), "cc")
    Check(T("links statt rechts", "left instead of right"), "ccLeft", true)
    Slider(T("Größe", "Size"), "ccSize", 16, 40, 1, " px", true)
    Check(T("Stärkungen anzeigen", "Show buffs"), "buffs")
    Check(T("nur entfernbare (Purge)", "only purgeable"), "buffsPurgeable", true)
    Slider(T("Größe", "Size"), "buffSize", 10, 28, 1, " px", true)
    Slider(T("Anzahl", "Count"), "buffMax", 1, 8, 1, nil, true)
    Gap()
    Header(T("Sonstiges", "Other"))
    Check(T("Combopunkte auf dem Ziel", "Combo points on your target"), "combo")
    Check(T("Questgegner markieren (!)", "Mark quest mobs (!)"), "quest")
    Check(T("Große Raidmarker über der Plakette", "Large raid markers above the plate"), "raidMarker")
    Slider(T("Größe", "Size"), "raidMarkerSize", 16, 40, 2, " px", true)
    Check(T("Verbündete: nur Name in Klassenfarbe", "Allies: name only, in class color"), "friendlySimple", false,
        function() ns.ApplyFriendly() end)

    UI.Hint(options, 18, -760, 680, T(
        "Prototyp – noch nicht im Release. Blizzards Plaketten bleiben bestehen (nichts wird versteckt oder "
        .. "umgehängt); ersetzte Teile werden nur durchsichtig. Größe und Abstand der Plaketten selbst: Blizzards "
        .. "Optionen (Esc » Optionen » Namensplaketten).",
        "Prototype – not in the release yet. Blizzard's nameplates stay in place (nothing is hidden or reparented); "
        .. "replaced parts only become transparent. Size and spacing of the plates themselves: Blizzard's options "
        .. "(Esc » Options » Nameplates)."))

    options:SetScript("OnShow", function()
        local d = ns.GetDB()
        for _, c in ipairs(controls) do
            if c.cb then c.cb:SetChecked(d[c.key] and true or false) end
            if c.slider then c.slider:Load(d[c.key]) end
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
        UI.Chat("ForeverPlates", d.skin and T("Forever-Stil an.", "Forever style on.")
            or T("Forever-Stil aus.", "Forever style off."))
    else
        ToggleOptions()
    end
end)
