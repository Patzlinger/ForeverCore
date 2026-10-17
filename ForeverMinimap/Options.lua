-- ForeverMinimap – Options.lua: Einstellungsfenster (Aufbau nach CLAUDE.md 7.1, ohne Bereichsliste: alles auf
-- einen Blick, zwei Spalten, Breite nach den deutschen Texten) und Minimap-Knopf
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local M = UI.MENU

local COL = 360 -- Spaltenbreite (laengster deutscher Text passt hinein)
local W = M.pad * 3 + COL * 2
local options

local function Set(key) return function(v) ns.GetDB()[key] = v if ns.ApplyAll then ns.ApplyAll() end end end
local function Get(key) return function() return ns.GetDB()[key] end end

local function Build()
    local H = 452
    options = UI.MenuWindow("ForeverMinimapOptions", T("Einstellungen", "Settings"), "ForeverMinimap", W, H)
    local x0, y0 = M.contentX, M.contentY
    local CS, DS = M.checkStep, M.choiceStep

    -- links: Form und Rahmen
    local shape = UI.MenuPanel(options, T("Form und Rahmen", "Shape and border"))
    shape:SetPoint("TOPLEFT", M.pad, M.panelTop)
    shape:SetSize(COL, 44 + DS + CS + 8)
    UI.MenuDropdown(shape, x0, y0, T("Form", "Shape"), {
        { key = "SQUARE", label = T("Eckig", "Square") },
        { key = "ROUND", label = T("Rund", "Round") },
    }, Get("shape"), Set("shape"))
    UI.MenuCheck(shape, x0, y0 - DS, T("Feiner Rahmen", "Thin border"), Get("border"), Set("border"))

    -- links: Leiste
    local barP = UI.MenuPanel(options, T("Leiste", "Bar"))
    barP:SetPoint("TOPLEFT", shape, "BOTTOMLEFT", 0, -M.pad)
    barP:SetSize(COL, 44 + CS + DS + 4 * CS + 8)
    UI.MenuCheck(barP, x0, y0, T("Leiste mit Zonenname zeigen", "Show bar with zone name"), Get("bar"), Set("bar"))
    UI.MenuDropdown(barP, x0, y0 - CS, T("Position", "Position"), {
        { key = "TOP", label = T("Über der Minimap", "Above the minimap") },
        { key = "BOTTOM", label = T("Unter der Minimap", "Below the minimap") },
    }, Get("barPosition"), Set("barPosition"))
    UI.MenuCheck(barP, x0, y0 - CS - DS, T("Uhr (Links: Wecker, Rechts: Kalender)", "Clock (left: alarm, right: calendar)"), Get("clock"), Set("clock"))
    UI.MenuCheck(barP, x0, y0 - 2 * CS - DS, T("Koordinaten auf der Karte", "Coordinates on the map"), Get("coords"), Set("coords"))
    UI.MenuCheck(barP, x0, y0 - 3 * CS - DS, T("Schwierigkeit in Instanzen", "Difficulty in instances"), Get("difficulty"), Set("difficulty"))
    UI.MenuCheck(barP, x0, y0 - 4 * CS - DS, T("Klick auf den Zonennamen: Weltkarte", "Click on the zone name: world map"), Get("barClickMap"), Set("barClickMap"))

    -- rechts: Knoepfe
    local btnP = UI.MenuPanel(options, T("Knöpfe", "Buttons"))
    btnP:SetPoint("TOPLEFT", shape, "TOPRIGHT", M.pad, 0)
    btnP:SetSize(COL, 44 + DS + 3 * CS + 8)
    UI.MenuDropdown(btnP, x0, y0, T("Knopfleiste", "Button bar"), {
        { key = "LEFT", label = T("Links neben der Karte", "Left of the map") },
        { key = "RIGHT", label = T("Rechts neben der Karte", "Right of the map") },
        { key = "OFF", label = T("Aus (nach /reload)", "Off (after /reload)") },
    }, Get("strip"), function(v)
        ns.GetDB().strip = v
        if ns.CollectEdgeButtons then ns.CollectEdgeButtons() end
        if ns.ApplyAll then ns.ApplyAll() end
    end)
    UI.MenuCheck(btnP, x0, y0 - DS, T("Nur bei Maus über der Minimap", "Only with the mouse over the minimap"), Get("stripMouseover"), Set("stripMouseover"),
        T("Post und Kalender-Einladungen bleiben immer sichtbar (goldener Rand).", "Mail and calendar invites always stay visible (gold border)."))
    UI.MenuCheck(btnP, x0, y0 - DS - CS, T("Eigene Knöpfe oben in der Leiste", "Own buttons in the top bar"), Get("toolsInBar"), Set("toolsInBar"),
        T("Post, Verfolgung, Kalender und Addon-Menü in der Leiste statt in der Knopfleiste.", "Mail, tracking, calendar and addon menu in the top bar instead of the button bar."))
    UI.MenuCheck(btnP, x0, y0 - DS - 2 * CS, T("Blizzards Kopfzeile und Knöpfe ausblenden", "Hide Blizzard's header and buttons"), Get("hideBlizzard"), Set("hideBlizzard"))

    -- rechts: Komfort
    local qol = UI.MenuPanel(options, T("Komfort", "Comfort"))
    qol:SetPoint("TOPLEFT", btnP, "BOTTOMLEFT", 0, -M.pad)
    qol:SetPoint("BOTTOMLEFT", barP, "BOTTOMRIGHT", M.pad, 0)
    qol:SetWidth(COL)
    UI.MenuCheck(qol, x0, y0, T("Rechtsklick auf die Karte: Verfolgung", "Right-click on the map: tracking"), Get("rightClickTracking"), Set("rightClickTracking"))
    UI.MenuCheck(qol, x0, y0 - CS, T("Nach 10 Sekunden wieder herauszoomen", "Zoom back out after 10 seconds"), Get("autoZoom"), Set("autoZoom"))
    UI.MenuCheck(qol, x0, y0 - 2 * CS, T("Beim Pingen zeigen, wer gepingt hat", "Show who pinged"), Get("pingNames"), Set("pingNames"))
    local hint = qol:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", x0, y0 - 3 * CS - 6)
    hint:SetWidth(COL - 28)
    hint:SetJustifyH("LEFT")
    hint:SetText(T("Position und Größe der Minimap stellst du in Blizzards Bearbeitungsmodus ein (Knopf unten). Zoomen: Mausrad.",
        "Set the minimap's position and size in Blizzard's Edit Mode (button below). Zoom: mouse wheel."))

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
    end)
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
