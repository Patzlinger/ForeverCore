-- ForeverMinimap – Options.lua: Einstellungsfenster (Aufbau nach CLAUDE.md 7.1, ohne Bereichsliste: alles auf
-- einen Blick – zwei Spalten mit je zwei Feldern, darunter ein breites Feld; Breite nach den deutschen Texten)
-- und Minimap-Knopf
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local M = UI.MENU

local COL = 360 -- Spaltenbreite (laengster deutscher Text passt hinein)
local W = M.pad * 3 + COL * 2
local options

local function Set(key) return function(v) ns.GetDB()[key] = v if ns.ApplyAll then ns.ApplyAll() end end end
local function Get(key) return function() return ns.GetDB()[key] end end

local function Build()
    local CS, DS, SS = M.checkStep, M.choiceStep, M.sliderStep
    local x0, y0 = M.contentX, M.contentY
    local topH = 44 + DS + CS + SS + 4          -- Form und Rahmen
    local barH = 44 + CS + DS + 5 * CS + 4      -- Leiste
    local btnH = 44 + DS + 4 * CS + SS + 4      -- Knoepfe
    local clockH = 44 + CS + DS + 2 * CS + 4    -- Uhr und Koordinaten
    local leftH, rightH = topH + M.pad + barH, btnH + M.pad + clockH
    local colH = math.max(leftH, rightH)
    local qolH = 44 + 3 * CS + 8                -- Komfort (breit, zwei Spalten innen)
    local H = -M.panelTop + colH + M.pad + qolH + M.pad + M.footerHeight + M.pad
    -- Seite im zentralen Einstellungsfenster von Forever Core (verhält sich wie das bisherige eigene Fenster)
    options = UI.SettingsPanel("ForeverMinimapOptions", T("Einstellungen", "Settings"), W, H,
        { key = "ForeverMinimap", group = UI.SETTINGS_GROUPS.nav, label = "Minimap", kind = "menu", subtitle = "ForeverMinimap" })

    -- Zeilen untereinander: jede Funktion setzt ein Element und rueckt weiter
    local function Rows(panel)
        local y = y0
        local r = {}
        function r.Check(label, key, tip) UI.MenuCheck(panel, x0, y, label, Get(key), Set(key), tip) y = y - CS end
        function r.Drop(label, list, key, set) UI.MenuDropdown(panel, x0, y, label, list, Get(key), set or Set(key)) y = y - DS end
        function r.Slider(label, minV, maxV, step, key) UI.MenuSlider(panel, x0, y - 4, label, minV, maxV, step, Get(key), Set(key)) y = y - SS end
        return r
    end

    -- links oben: Form und Rahmen
    local shape = UI.MenuPanel(options, T("Form und Rahmen", "Shape and border"))
    shape:SetPoint("TOPLEFT", M.pad, M.panelTop)
    shape:SetSize(COL, topH)
    local r = Rows(shape)
    r.Drop(T("Form", "Shape"), { { key = "SQUARE", label = T("Eckig", "Square") }, { key = "ROUND", label = T("Rund", "Round") } }, "shape")
    r.Check(T("Feiner Rahmen", "Thin border"), "border")
    r.Slider(T("Kartengröße (%)", "Map size (%)"), 80, 150, 1, "mapScale")

    -- links unten: Leiste
    local barP = UI.MenuPanel(options, T("Leiste", "Bar"))
    barP:SetPoint("TOPLEFT", shape, "BOTTOMLEFT", 0, -M.pad)
    barP:SetSize(COL, colH - topH - M.pad)
    r = Rows(barP)
    r.Check(T("Leiste mit Zonenname zeigen", "Show bar with zone name"), "bar")
    r.Drop(T("Position", "Position"), {
        { key = "TOP", label = T("Über der Minimap", "Above the minimap") },
        { key = "BOTTOM", label = T("Unter der Minimap", "Below the minimap") },
    }, "barPosition")
    r.Check(T("Ruhegebiet: „zZ“ hinter dem Namen", "Resting area: \"zZ\" after the name"), "restInfo")
    r.Check(T("Schwierigkeit in Instanzen", "Difficulty in instances"), "difficulty")
    r.Check(T("Haltbarkeit unter 30 % (Amboss)", "Durability below 30 % (anvil)"), "durability")
    r.Check(T("Warteschlangen-Auge unten rechts in der Karte", "Queue eye in the bottom right of the map"), "queueDock",
        T("Solange ForeverBars das Auge nicht in seiner eigenen Leiste führt.", "As long as ForeverBars does not show the eye in its own bar."))
    r.Check(T("Klick auf den Zonennamen: Weltkarte", "Click on the zone name: world map"), "barClickMap")

    -- rechts oben: Knoepfe
    local btnP = UI.MenuPanel(options, T("Knöpfe", "Buttons"))
    btnP:SetPoint("TOPLEFT", shape, "TOPRIGHT", M.pad, 0)
    btnP:SetSize(COL, btnH)
    r = Rows(btnP)
    r.Drop(T("Knopfleiste", "Button bar"), {
        { key = "LEFT", label = T("Links neben der Karte", "Left of the map") },
        { key = "RIGHT", label = T("Rechts neben der Karte", "Right of the map") },
        { key = "OFF", label = T("Aus (nach /reload)", "Off (after /reload)") },
    }, "strip", function(v)
        ns.GetDB().strip = v
        if ns.CollectEdgeButtons then ns.CollectEdgeButtons() end
        if ns.ApplyAll then ns.ApplyAll() end
    end)
    r.Check(T("Nur bei Maus über der Minimap", "Only with the mouse over the minimap"), "stripMouseover",
        T("Post und Kalender-Einladungen bleiben immer sichtbar (goldener Rand).", "Mail and calendar invites always stay visible (gold border)."))
    r.Check(T("Eigene Knöpfe oben in der Leiste", "Own buttons in the top bar"), "toolsInBar",
        T("Post, Verfolgung, Kalender und Einstellungen in der Leiste statt in der Knopfleiste.", "Mail, tracking, calendar and settings in the top bar instead of the button bar."))
    r.Check(T("Knöpfe anderer Addons im gleichen Look", "Other addons' buttons in the same look"), "squareForeign",
        T("Eckig bei eckiger, rund bei runder Karte. Ausschalten gilt nach /reload.", "Square on a square map, round on a round one. Turning it off applies after /reload."))
    r.Check(T("Blizzards Kopfzeile und Knöpfe ausblenden", "Hide Blizzard's header and buttons"), "hideBlizzard")
    r.Slider(T("Deckkraft der Knopfleiste (%)", "Button bar opacity (%)"), 0, 100, 5, "stripAlpha")

    -- rechts unten: Uhr und Koordinaten
    local clockP = UI.MenuPanel(options, T("Uhr und Koordinaten", "Clock and coordinates"))
    clockP:SetPoint("TOPLEFT", btnP, "BOTTOMLEFT", 0, -M.pad)
    clockP:SetSize(COL, colH - btnH - M.pad)
    r = Rows(clockP)
    r.Check(T("Uhr (Links: Wecker, Rechts: Kalender)", "Clock (left: alarm, right: calendar)"), "clock")
    r.Drop(T("Zeit", "Time"), {
        { key = "LOCAL", label = T("Ortszeit", "Local time") },
        { key = "SERVER", label = T("Serverzeit", "Server time") },
    }, "clockSource")
    r.Check(T("24 Stunden", "24 hours"), "clock24")
    r.Check(T("Koordinaten (Klick: Kartenmarkierung)", "Coordinates (click: waypoint)"), "coords",
        T("Klick: Markierung setzen · Umschalt-Klick: auch in die offene Chat-Eingabe · Rechtsklick: entfernen",
          "Click: set waypoint · Shift-click: also into the open chat input · Right-click: remove"))

    -- unten breit: Komfort (zwei Spalten)
    local qol = UI.MenuPanel(options, T("Komfort", "Comfort"))
    qol:SetPoint("TOPLEFT", barP, "BOTTOMLEFT", 0, -M.pad)
    qol:SetPoint("TOPRIGHT", clockP, "BOTTOMRIGHT", 0, -M.pad)
    qol:SetHeight(qolH)
    UI.MenuCheck(qol, x0, y0, T("Rechtsklick auf die Karte: Verfolgung", "Right-click on the map: tracking"), Get("rightClickTracking"), Set("rightClickTracking"))
    UI.MenuCheck(qol, x0, y0 - CS, T("Nach 10 Sekunden zurück auf die Grundstufe", "Back to the base zoom after 10 seconds"), Get("autoZoom"), Set("autoZoom"))
    UI.MenuCheck(qol, x0, y0 - 2 * CS, T("Beim Pingen zeigen, wer gepingt hat", "Show who pinged"), Get("pingNames"), Set("pingNames"))
    local x1 = COL + M.pad + x0
    UI.MenuCheck(qol, x1, y0, T("In Städten und Gasthäusern näher heran", "Closer zoom in cities and inns"), Get("cityZoom"), Set("cityZoom"))
    UI.MenuSlider(qol, x1, y0 - CS - 4, T("Zoomstufe dort (0–5)", "Zoom level there (0–5)"), 0, 5, 1, Get("cityZoomLevel"), Set("cityZoomLevel"))

    -- Fussleiste
    local reset = UI.MenuButton(options, T("Zurücksetzen", "Reset"), M.footerWidth, M.footerHeight, function()
        if UI.ResetProfile and UI.ResetProfile(ADDON_NAME) then
            ns.Chat(T("Gilt nach dem Neuladen (/reload).", "Applies after reloading (/reload)."))
            if UI.ShowProfiles then UI.ShowProfiles() end
        end
    end, T("Setzt das Profil dieses Charakters auf Standard (gilt nach dem Neuladen).", "Resets this character's profile to defaults (applies after reloading)."))
    reset:SetPoint("BOTTOMLEFT", M.pad, M.pad)
    local edit = UI.MenuButton(options, T("Im Bearbeitungsmodus verschieben", "Move in Edit Mode"), 220, M.footerHeight, function()
        options:Hide()
        ns.OpenEditMode()
    end, T("Position und Gesamtgröße der Minimap verwaltet Blizzards Bearbeitungsmodus. Zoomen: Mausrad.",
        "Blizzard's Edit Mode manages the minimap's position and overall size. Zoom: mouse wheel."))
    edit:SetPoint("LEFT", reset, "RIGHT", M.pad, 0)
    local close = UI.MenuButton(options, T("Schließen", "Close"), M.footerWidth, M.footerHeight, function() options:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -M.pad - 16, M.pad)
end
function ns.ToggleOptions()
    if not options then Build() end
    options:SetShown(not options:IsShown())
end

---------------------------------------------------------------------------
-- Minimap-Knopf (gemeinsame Vorlage; ab zwei Forever-Addons im Sammelknopf)
---------------------------------------------------------------------------
function ns.SetupOptions()
    if ns.minimapButton then return end
    ns.minimapButton = UI.MinimapButton({
        name = "ForeverMinimapMinimapButton",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        texCoord = { 0.08, 0.92, 0.08, 0.92 },
        title = "ForeverMinimap",
        angle = function() return ns.GetDB().minimapAngle end,
        setAngle = function(a) ns.GetDB().minimapAngle = a end,
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                local d = ns.GetDB()
                d.shape = d.shape == "SQUARE" and "ROUND" or "SQUARE"
                if ns.ApplyAll then ns.ApplyAll() end
            else
                ns.ToggleOptions()
            end
        end,
        lines = function()
            return { T("Linksklick: Einstellungen", "Left-click: settings"),
                     T("Rechtsklick: rund / eckig", "Right-click: round / square") }
        end,
    })
end

-- Eintrag im zentralen Einstellungsfenster schon beim Laden (die Seite selbst entsteht erst beim ersten Öffnen)
if UI.RegisterSettingsLink then
    UI.RegisterSettingsLink({ key = "ForeverMinimap", group = UI.SETTINGS_GROUPS.nav, label = "Minimap",
        open = function() ns.ToggleOptions() end })
end
