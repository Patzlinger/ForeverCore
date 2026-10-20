-- ForeverSkin – Settings.lua: Blizzards Optionen-Fenster (Spieleinstellungen), Stufe 1 – Rahmen und Gerüst:
-- dunkles flaches Fenster mit Titelleiste, flache Reiter "Spiel/Addons", flaches Suchfeld, flache Knöpfe
-- ("Standard", "Schließen"), goldene Laufleisten, Liste links und Einstellungsbereich rechts als flache Kästen,
-- Bereichsüberschriften (Gameplay, Zugänglichkeit, System) gold mit feiner Linie, Abschnitte rechts ("Maus") gold.
-- Stufe 2: die einzelnen Einstellungen – Haken als goldene Kästchen, flache Regler, Auswahllisten und Knöpfe flach.
-- Dieses Fenster ist das empfindlichste im Spiel (Tastenbelegung, Bearbeitungsmodus, Kampf-Einstellungen): darum nur
-- Grafiken unsichtbar (SetAlpha), eigene Texturen und Schriftfarben – nichts in Blizzards Tabellen, nichts ersetzt.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local CONTROL_W = 200 -- einheitliche Breite für Auswahllisten und einzelne Knöpfe in den Zeilen
local headers = setmetatable({}, { __mode = "k" })

-- Bereichsüberschrift links (roter Balken bei Blizzard) wie die Bereiche in der Liste des Forever-Einstellungsfensters:
-- klein, gold, in Großbuchstaben, ohne Balken
local function SkinCategoryHeader(element)
    local label = element.Label or element.Text or element.Title
    ns.HideTextures(element)
    if element.Background then ns.Hide(element.Background) end
    if not (label and label.SetTextColor) then return end
    if not headers[element] then
        headers[element] = true
        label:SetFontObject("GameFontNormalSmall")
        label:SetAlpha(0.85)
    end
    label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    local text = label:GetText()
    if type(text) == "string" and text ~= text:upper() then label:SetText(text:upper()) end
end

-- Einträge der Liste links: hell wie im Forever-Einstellungsfenster, der gewählte gold. Blizzard färbt sie selbst
-- (normal gold, gewählt weiß) – wir drehen das um und merken uns, was wir gesetzt haben, damit wir Blizzards eigene
-- Änderungen (anderer Eintrag gewählt) erkennen
local ours = setmetatable({}, { __mode = "k" })
local function SkinCategoryEntry(element)
    local label = element.Label or element.Text
    if not (label and label.GetTextColor) then return end
    local r, g, b = label:GetTextColor()
    local key = string.format("%.2f%.2f%.2f", r or 0, g or 0, b or 0)
    if ours[label] == key then return end -- unverändert seit unserem letzten Setzen
    local gold = r and r > 0.9 and g > 0.7 and b < 0.3
    local white = r and r > 0.9 and g > 0.9 and b > 0.9
    if gold then
        label:SetTextColor(0.9, 0.9, 0.9)       -- normal: hell
    elseif white then
        label:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) -- gewählt: gold
    end
    r, g, b = label:GetTextColor()
    ours[label] = string.format("%.2f%.2f%.2f", r or 0, g or 0, b or 0)
end

-- aufgeklappt? (Blizzards +/−: Atlas bzw. Textur mit "minus"/"expanded" = offen)
local function IsExpanded(toggle)
    local t = toggle.GetNormalTexture and toggle:GetNormalTexture()
    local name = t and ((t.GetAtlas and t:GetAtlas()) or (t.GetTexture and t:GetTexture()))
    name = type(name) == "string" and name:lower() or ""
    return name:find("minus") ~= nil or name:find("expanded") ~= nil or name:find("collapse") ~= nil
end

-- Elemente der Liste links: Überschriften erkennen (haben einen Hintergrund-Balken, sind keine Kategorie);
-- +/− zum Auf-/Zuklappen (Reiter "Addons") als feiner Pfeil
local function SkinCategoryList(list)
    local box = list and list.ScrollBox
    if not (box and box.ForEachFrame) then return end
    box:ForEachFrame(function(element)
        if element.Toggle then ns.SkinToggle(element.Toggle, IsExpanded(element.Toggle)) end
        local header = false
        if headers[element] then
            header = true
        elseif element.Background and not element.Toggle and not element.isCategory then
            local data = element.GetElementData and element:GetElementData()
            local isHeader = type(data) == "table" and (data.isHeader or data.header or data.category == nil)
            header = isHeader or (element.Background:GetObjectType() == "Texture" and not (element.GetText and element:GetText()))
        end
        if header then SkinCategoryHeader(element) else SkinCategoryEntry(element) end
    end)
end

-- Regler mit Pfeilen links/rechts (MinimalSliderWithSteppers): Schiene, Schieber, feine Pfeile
local function SkinStepperSlider(s)
    if type(s) ~= "table" then return end
    ns.SkinSlider(s.Slider or s)
    ns.SkinArrowOnly(s.Back or s.BackButton, "left")
    ns.SkinArrowOnly(s.Forward or s.ForwardButton, "right")
end

-- Auswahlliste mit Pfeilen links/rechts ("Umschalttaste"): flacher Knopf, feine Pfeile
local function SkinDropdownControl(control)
    if type(control) ~= "table" then return end
    local dd = control.Dropdown or control.DropDown or (control.IsObjectType and control:IsObjectType("Button") and control)
    if dd then ns.SkinDropdown(dd) end
    ns.SkinArrowOnly(control.DecrementButton or control.LeftButton, "left")
    ns.SkinArrowOnly(control.IncrementButton or control.RightButton, "right")
end

-- Spalte der Bedienelemente: so weit vom linken Zeilenrand wie die Haken (an einem Haken abgemessen);
-- labelX: Spalte der Namen (an einer Zeile mit Namen abgemessen)
local controlX, labelX
local function AlignDropdown(element, dd)
    if not controlX or not (element:GetLeft() and dd:GetLeft()) then return end
    -- alle Auswahllisten in EINER Spalte: rechts neben der Haken-Spalte (so passt es auch in Zeilen mit Haken davor);
    -- der linke Pfeil hängt bei Blizzard an der Liste und wandert mit
    local want = controlX + 52
    if math.abs((dd:GetLeft() - element:GetLeft()) - want) <= 0.5 then return end
    dd:ClearAllPoints()
    dd:SetPoint("LEFT", element, "LEFT", want, 0)
end

-- Regler mit Pfeilen (MinimalSliderWithSteppers): die Schiene in dieselbe Spalte wie die Auswahllisten und gleich
-- breit; Pfeile und Zahl hängen am Rahmen des Reglers und wandern mit
-- Lage der Pfeile einer ausgerichteten Auswahlliste (vom linken Zeilenrand): linker Rand des linken Pfeils, rechter
-- Rand des rechten – die Regler-Pfeile kommen genau dorthin, damit alle Pfeile in einer Reihe stehen
local arrowL, arrowR
local function MeasureArrows(element, control)
    if arrowL then return end
    local dec, inc = control.DecrementButton or control.LeftButton, control.IncrementButton or control.RightButton
    if dec and inc and dec:GetLeft() and inc:GetRight() and element:GetLeft() then
        arrowL, arrowR = dec:GetLeft() - element:GetLeft(), inc:GetRight() - element:GetLeft()
    end
end

local sliderGaps = setmetatable({}, { __mode = "k" }) -- [Regler] = { links, Pfeile zusammen, Pfeil-Abstände } (einmal)
local function AlignSlider(element, holder)
    local slider = holder.Slider
    if not (controlX and slider and element:GetLeft() and holder:GetLeft() and slider:GetLeft()) then return end
    -- einmal messen: wächst die Schiene nicht mit dem Rahmen, würde er sonst bei jedem Durchgang breiter
    local gaps = sliderGaps[holder]
    if not gaps then
        local back, fwd = holder.Back or holder.BackButton, holder.Forward or holder.ForwardButton
        gaps = { slider:GetLeft() - holder:GetLeft(), (holder:GetWidth() or 0) - (slider:GetWidth() or 0),
            back and back:GetLeft() and (back:GetLeft() - holder:GetLeft()) or nil,
            fwd and fwd:GetRight() and (holder:GetRight() - fwd:GetRight()) or nil }
        sliderGaps[holder] = gaps
    end
    local inner, extra = gaps[1], gaps[2] -- Platz links (Pfeil), Pfeile links und rechts zusammen
    local want = controlX + 52 - inner
    local width = CONTROL_W + extra
    -- Pfeile genau unter die Pfeile der Auswahllisten (wenn schon gemessen)
    if arrowL and gaps[3] and gaps[4] then
        want = arrowL - gaps[3]
        width = (arrowR - arrowL) + gaps[3] + gaps[4]
    end
    if math.abs((holder:GetLeft() - element:GetLeft()) - want) > 0.5 then
        holder:ClearAllPoints()
        holder:SetPoint("LEFT", element, "LEFT", want, 0)
    end
    if extra > 0 and math.abs((holder:GetWidth() or 0) - width) > 0.5 then holder:SetWidth(width) end
end

-- Zeilen rechts: Abschnitts-Überschriften ("Maus", "Kamera" …) gold; Bedienelemente im Forever-Stil (Stufe 2)
local function SkinSettingsList(list)
    local box = list and list.ScrollBox
    if not (box and box.ForEachFrame) then return end
    box:ForEachFrame(function(element)
        local cb = element.Checkbox or element.CheckBox
        local slider = element.SliderWithSteppers or element.Slider
        local control = element.Control or element.DropDown or element.Dropdown
        local title = element.Title
        -- Abschnitt = nur Überschrift, kein Bedienelement
        if title and title.SetTextColor and not (cb or slider or control or element.Button or element.Button1) then
            title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            return
        end
        if cb then
            ns.SkinCheck(cb)
            ns.PlaceCheck(cb)
            if not controlX and cb:GetLeft() and element:GetLeft() then controlX = cb:GetLeft() - element:GetLeft() end
        end
        if slider then
            SkinStepperSlider(slider)
            if slider.Slider then AlignSlider(element, slider) end
        end
        -- Tastaturbelegung: Tasten-Paar in dieselbe Spalte (der zweite Knopf hängt am ersten)
        if element.Button1 and element.Button2 and element.Button1.GetLeft then AlignDropdown(element, element.Button1) end
        if control then
            SkinDropdownControl(control)
            local dd = control.Dropdown or control.DropDown
            if dd then
                ns.DropdownColor(dd)
                -- alle Auswahllisten gleich breit (Blizzard macht sie je nach Seite verschieden breit)
                if math.abs((dd:GetWidth() or 0) - CONTROL_W) > 0.5 then dd:SetWidth(CONTROL_W) end
                -- und an derselben Stelle – auch in Zeilen mit Haken davor
                AlignDropdown(element, dd)
                MeasureArrows(element, control)
            end
        end
        -- Name der Einstellung hell (Blizzard: gold) – ausgegraute bleiben grau; gold sind nur die Überschriften
        local label = element.Text or element.Label
        -- Spalte der Namen (für linksbündige Knöpfe ohne Namen) an einer Zeile mit Namen abmessen
        if not labelX and label and label.GetLeft and label:GetLeft() and element:GetLeft() and label:IsShown()
            and (label:GetText() or "") ~= "" then
            labelX = label:GetLeft() - element:GetLeft()
        end
        if label and label.GetTextColor and label.SetTextColor then
            local r, g, b = label:GetTextColor()
            if r and r > 0.9 and g > 0.7 and b < 0.3 then label:SetTextColor(0.92, 0.92, 0.92) end
        end
        -- Knöpfe (z. B. Tastenbelegung "Nicht belegt", "Ausführen")
        for _, key in ipairs({ "Button", "Button1", "Button2" }) do
            local b = element[key]
            if type(b) == "table" and b.IsObjectType and b:IsObjectType("Button") and not b:IsObjectType("CheckButton") then
                ns.SkinButton(b)
                -- einzelne Knöpfe (z. B. "Tutorial-Neustart", "Zurücksetzen") so breit wie die Auswahllisten und in
                -- derselben Spalte; Tasten-Paare (Tastenbelegung) bleiben, wie sie sind
                if key == "Button" then
                    local label = element.Text or element.Label
                    local named = label and label.GetText and (label:GetText() or "") ~= "" and label:IsShown()
                    if named or not labelX then
                        -- Knopf mit Namen davor: in die Spalte der Auswahllisten, gleich breit
                        if math.abs((b:GetWidth() or 0) - CONTROL_W) > 0.5 then b:SetWidth(CONTROL_W) end
                        AlignDropdown(element, b)
                    else
                        -- Knopf ohne Namen (Tastaturbelegung: "Klickzauber", "Bewegungstasten" …): linksbündig ab der
                        -- Spalte der Namen bis zum Ende der Auswahllisten-Spalte
                        local left, right = labelX, (controlX or labelX) + 52 + CONTROL_W
                        if element:GetLeft() and b:GetLeft() and (math.abs((b:GetLeft() - element:GetLeft()) - left) > 0.5
                            or math.abs((b:GetWidth() or 0) - (right - left)) > 0.5) then
                            b:ClearAllPoints()
                            b:SetPoint("LEFT", element, "LEFT", left, 0)
                            b:SetWidth(right - left)
                        end
                    end
                end
            end
        end
    end)
end

-- offene Auswahlliste (Blizzards Menü-System): flach und dunkel mit goldener Linie oben. Blizzards Menüs verbieten
-- eigene Grafiken (CreateTexture ist dort gesperrt) – darum ein EIGENER Rahmen dahinter, der dem offenen Menü folgt;
-- am Menü selbst werden nur Blizzards Grafiken unsichtbar gemacht (SetAlpha ist erlaubt)
local menuBack
function ns.SkinOpenMenu()
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    local menu = manager and manager.GetOpenMenu and manager:GetOpenMenu()
    if not (menu and menu.IsShown and menu:IsShown()) then
        if menuBack then menuBack:Hide() end
        return
    end
    for _, r in ipairs({ menu:GetRegions() }) do
        if r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "NineSlice", "Background", "Bg" }) do
        if type(menu[key]) == "table" and menu[key].SetAlpha then menu[key]:SetAlpha(0) end
    end
    if not menuBack then
        menuBack = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ns.UI.SetFlat(menuBack, C.background)
        local line = menuBack:CreateTexture(nil, "ARTWORK")
        line:SetTexture(WHITE)
        line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
        line:SetPoint("TOPLEFT", 1, -1)
        line:SetPoint("TOPRIGHT", -1, -1)
        line:SetHeight(1)
        menuBack:EnableMouse(false)
    end
    if menuBack.menu ~= menu then
        menuBack.menu = menu
        menuBack:ClearAllPoints()
        menuBack:SetAllPoints(menu)
    end
    menuBack:SetFrameStrata(menu:GetFrameStrata())
    menuBack:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
    menuBack:Show()
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
    -- Titelleiste wie bei Forever Core: Logo und Titel links
    local logo = f:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(ns.UI.LOGO)
    logo:SetSize(16, 16)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    local function Title()
        title:SetText((blizzTitle and blizzTitle.GetText and blizzTitle:GetText()) or _G.SETTINGS_TITLE or "")
    end
    Title()
    f:HookScript("OnShow", Title)
    -- Schließen: hier heißt der Text-Knopf unten "CloseButton" und das X oben "ClosePanelButton" – SkinClose macht
    -- aus Knöpfen mit Text flache Text-Knöpfe, aus dem X das feine Kreuz; das X passend zur Titelleiste
    for _, b in ipairs({ f.CloseButton, f.ClosePanelButton }) do
        if b then
            local label = b.GetText and b:GetText()
            ns.SkinClose(b)
            if not (type(label) == "string" and label ~= "") then
                b:SetSize(20, 20)
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
            end
        end
    end
    ns.SkinButton(f.ApplyButton)
    for _, tab in ipairs({ f.GameTab, f.AddOnsTab }) do
        if tab then
            ns.SkinTab(tab, function(t)
                return t.isSelected or (t.SelectedTexture and t.SelectedTexture:IsShown()) or (t.IsEnabled and not t:IsEnabled())
            end)
            -- Blizzards Reiter sind viel höher als ihr Text: Fläche oben kürzen (Text sitzt unten)
            ns.Refit(tab, { 0, math.max(0, (tab:GetHeight() or 30) - 26), 0, 2 })
        end
    end
    SkinSearchBox(f.SearchBox)

    -- wie das Forever-Einstellungsfenster: Liste links auf leicht abgesetzter Fläche mit Trennlinie rechts, rechts
    -- kein Kasten (sonst ragte unten Text über die Kastenkante – die Liste endet einfach an ihrer Unterkante)
    local list = f.CategoryList
    if list then
        ns.HideTextures(list)
        if list.NineSlice then ns.Hide(list.NineSlice) end
        -- Fläche von der Titelleiste bis ganz unten durchgehend (wie die Liste im Forever-Einstellungsfenster), mit
        -- Trennlinie rechts; die Reiter "Spiel/Addons" sitzen oben darin
        local nav = f:CreateTexture(nil, "BACKGROUND", nil, -6)
        nav:SetTexture(WHITE)
        nav:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 0.6)
        nav:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -24)
        nav:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
        nav:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        local navLine = f:CreateTexture(nil, "BORDER", nil, -5)
        navLine:SetTexture(WHITE)
        navLine:SetVertexColor(C.border[1], C.border[2], C.border[3], 1)
        navLine:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
        navLine:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 0, 0)
        navLine:SetWidth(1)
        -- feine goldene Linie unter den Reitern "Spiel/Addons"
        if f.GameTab then
            local tabLine = f:CreateTexture(nil, "ARTWORK")
            tabLine:SetTexture(WHITE)
            tabLine:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
            tabLine:SetPoint("TOPLEFT", f.GameTab, "BOTTOMLEFT", -2, -6)
            tabLine:SetPoint("RIGHT", nav, "RIGHT", -8, 0)
            tabLine:SetHeight(1)
        end
        ns.SkinScrollBar(list.ScrollBar)
    end
    local container = f.Container
    local settingsList = container and container.SettingsList
    if container then
        ns.HideTextures(container)
        if container.NineSlice then ns.Hide(container.NineSlice) end
    end
    if settingsList then
        ns.HideTextures(settingsList)
        ns.SkinScrollBar(settingsList.ScrollBar)
        local head = settingsList.Header
        if head then
            ns.SkinButton(head.DefaultsButton)
            if head.Title then head.Title:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
            -- Blizzards brauner Trennbalken unter dem Seitentitel -> feine goldene Linie
            ns.HideTextures(head)
            if head.Divider then ns.Hide(head.Divider) end
            local line = head:CreateTexture(nil, "ARTWORK")
            line:SetTexture(WHITE)
            line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
            line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
            line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
            line:SetHeight(1)
        end
    end
    ns.Watch(f)

    -- Liste und Einstellungen baut Blizzard beim Öffnen einer Seite und beim Scrollen neu: solange das Fenster offen
    -- ist, in JEDEM Bild die sichtbaren Zeilen prüfen (sonst blitzten Blizzards Grafiken kurz auf; schon umgestaltete
    -- Zeilen kosten fast nichts). Dazu eine gerade offene Auswahlliste flach und dunkel.
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnHide", function() if menuBack then menuBack:Hide() end end)
    watch:SetScript("OnUpdate", function()
        for _, tab in ipairs({ f.GameTab, f.AddOnsTab }) do if tab then pcall(ns.CenterText, tab) end end
        pcall(SkinCategoryList, list)
        pcall(SkinSettingsList, settingsList)
        pcall(ns.SkinOpenMenu)
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
