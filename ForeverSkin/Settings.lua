-- ForeverSkin – Settings.lua: Blizzards Optionen-Fenster (Spieleinstellungen), Stufe 1 – Rahmen und Gerüst:
-- dunkles flaches Fenster mit Titelleiste, flache Reiter "Spiel/Addons", flaches Suchfeld, flache Knöpfe
-- ("Standard", "Schließen"), goldene Laufleisten, Liste links und Einstellungsbereich rechts als flache Kästen,
-- Bereichsüberschriften (Gameplay, Zugänglichkeit, System) gold mit feiner Linie, Abschnitte rechts ("Maus") gold.
-- Die einzelnen Einstellungen (Haken, Regler, Auswahllisten) bleiben vorerst Blizzards – Stufe 2.
-- Dieses Fenster ist das empfindlichste im Spiel (Tastenbelegung, Bearbeitungsmodus, Kampf-Einstellungen): darum nur
-- Grafiken unsichtbar (SetAlpha), eigene Texturen und Schriftfarben – nichts in Blizzards Tabellen, nichts ersetzt.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local headers = setmetatable({}, { __mode = "k" })

-- Bereichsüberschrift links (roter Balken bei Blizzard): Balken weg, Schrift gold, feine Linie darunter
local function SkinCategoryHeader(element)
    local label = element.Label or element.Text or element.Title
    ns.HideTextures(element)
    if element.Background then ns.Hide(element.Background) end
    if label and label.SetTextColor then label:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
    if headers[element] then return end
    headers[element] = true
    local line = element:CreateTexture(nil, "ARTWORK")
    line:SetTexture(WHITE)
    line:SetVertexColor(1, 1, 1, 0.08)
    line:SetPoint("BOTTOMLEFT", 6, 1)
    line:SetPoint("BOTTOMRIGHT", -6, 1)
    line:SetHeight(1)
end

-- Elemente der Liste links: Überschriften erkennen (haben einen Hintergrund-Balken, sind keine Kategorie)
local function SkinCategoryList(list)
    local box = list and list.ScrollBox
    if not (box and box.ForEachFrame) then return end
    box:ForEachFrame(function(element)
        if element.Background and not element.Toggle and not element.isCategory then
            local data = element.GetElementData and element:GetElementData()
            local isHeader = type(data) == "table" and (data.isHeader or data.header or data.category == nil)
            if isHeader or element.Background:GetObjectType() == "Texture" and not (element.GetText and element:GetText()) then
                SkinCategoryHeader(element)
            end
        end
    end)
end

-- Abschnitts-Überschriften rechts ("Maus", "Kamera" …): gold
local function SkinSettingsList(list)
    local box = list and list.ScrollBox
    if not (box and box.ForEachFrame) then return end
    box:ForEachFrame(function(element)
        local title = element.Title
        -- Abschnitt = nur Überschrift, kein Bedienelement
        if title and title.SetTextColor and not (element.Checkbox or element.CheckBox or element.SliderWithSteppers
            or element.Slider or element.Control or element.Button or element.DropDown or element.Dropdown) then
            title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        end
    end)
end

local function SkinSearchBox(box)
    if not box then return end
    local keep = {}
    for _, key in ipairs({ "searchIcon", "SearchIcon", "Instructions", "clearButton" }) do
        if type(box[key]) == "table" and box[key].IsObjectType and box[key]:IsObjectType("Texture") then keep[box[key]] = true end
    end
    ns.HideTextures(box, keep)
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    ns.Flat(box, C.input, { -4, 2, 0, 2 })
end

local function SkinSettings()
    local f = _G.SettingsPanel
    if not f or ns.settingsSkinned then return end
    ns.settingsSkinned = true
    -- Titel steht bei diesem Fenster im Rahmen (NineSlice.Text) – der wird unsichtbar, darum eigener Titel
    local blizzTitle = f.NineSlice and f.NineSlice.Text
    ns.SkinWindow(f)
    if blizzTitle and blizzTitle.GetText then
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", f, "TOP", 0, -6)
        title:SetText(blizzTitle:GetText() or "")
        f:HookScript("OnShow", function() title:SetText(blizzTitle:GetText() or "") end)
    end
    ns.SkinClose(f.CloseButton)
    ns.SkinButton(f.ClosePanelButton)
    ns.SkinButton(f.ApplyButton)
    for _, tab in ipairs({ f.GameTab, f.AddOnsTab }) do
        if tab then
            ns.SkinTab(tab, function(t)
                return t.isSelected or (t.SelectedTexture and t.SelectedTexture:IsShown()) or (t.IsEnabled and not t:IsEnabled())
            end)
        end
    end
    SkinSearchBox(f.SearchBox)

    -- Liste links und Einstellungsbereich rechts als flache Kästen (wie die Seiten im Forever-Einstellungsfenster)
    local list = f.CategoryList
    if list then
        ns.HideTextures(list)
        if list.NineSlice then ns.Hide(list.NineSlice) end
        ns.Flat(list, C.panel)
        ns.SkinScrollBar(list.ScrollBar)
    end
    local container = f.Container
    local settingsList = container and container.SettingsList
    if container then
        ns.HideTextures(container)
        if container.NineSlice then ns.Hide(container.NineSlice) end
        ns.Flat(container, C.panel)
    end
    if settingsList then
        ns.HideTextures(settingsList)
        ns.SkinScrollBar(settingsList.ScrollBar)
        local head = settingsList.Header
        if head then
            ns.SkinButton(head.DefaultsButton)
            if head.Title then head.Title:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
        end
    end
    ns.Watch(f)

    -- Liste und Einstellungen baut Blizzard beim Öffnen einer Seite und beim Scrollen neu: solange das Fenster offen
    -- ist, fünfmal je Sekunde die sichtbaren Zeilen prüfen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        pcall(SkinCategoryList, list)
        pcall(SkinSettingsList, settingsList)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not ns.GetDB().settings then return end
    local ok, err = pcall(SkinSettings)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "settings", err) end
end)
