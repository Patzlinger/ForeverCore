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

-- Feste Spalten der Bedienelemente (vom linken Zeilenrand, ab der Haken-Spalte controlX – an einem Haken
-- abgemessen): linker Pfeil ARROW_GAP hinter dem Haken (gut 10 px Luft zum Kästchen), daneben Liste bzw. Schiene
-- (CONTROL_W breit), dahinter der rechte Pfeil. Regler und Auswahllisten werden Teil für Teil an diese Stellen gesetzt
-- (Blizzard baut beide verschieden auf – abmessen und verschieben ergab keine saubere Reihe). labelX: Spalte der Namen.
local controlX, labelX
local ARROW_GAP, ARROW_W, PAD = 34, 16, 4
local function BodyX() return controlX + ARROW_GAP + ARROW_W + PAD end

-- ein Teil an seine Stelle (nur wenn es woanders steht – sonst würde Blizzard in jedem Bild neu anordnen)
local function Put(region, element, x, width)
    if not (region and region.GetLeft and region:GetLeft() and element:GetLeft()) then return end
    local off = region:GetLeft() - element:GetLeft()
    if math.abs(off - x) > 0.5 or (width and math.abs((region:GetWidth() or 0) - width) > 0.5) then
        region:ClearAllPoints()
        region:SetPoint("LEFT", element, "LEFT", x, 0)
        if width then region:SetWidth(width) end
    end
end

-- Pfeil-Knopf nach seiner MITTE setzen (Blizzards Pfeil-Knöpfe sind bei Listen breiter als bei Reglern – der Pfeil
-- sitzt mittig im Knopf, nach der linken Kante gesetzt lagen die Listen-Pfeile darum weiter rechts)
local function PutCenter(region, element, cx)
    if not (region and region.GetCenter and element:GetLeft()) then return end
    local x = region:GetCenter()
    if not x then return end
    if math.abs((x - element:GetLeft()) - cx) > 0.5 then
        region:ClearAllPoints()
        region:SetPoint("CENTER", element, "LEFT", cx, 0)
    end
end

-- Pfeil – Mitte – Pfeil in die festen Spalten
local function PlaceRow(element, left, middle, right)
    if not controlX then return end
    PutCenter(left, element, controlX + ARROW_GAP + ARROW_W / 2)
    Put(middle, element, BodyX(), CONTROL_W)
    PutCenter(right, element, BodyX() + CONTROL_W + PAD + ARROW_W / 2)
end

-- Knopf oder Liste ohne Pfeile in die Spalte der Listen
local function AlignDropdown(element, dd)
    if not controlX then return end
    Put(dd, element, BodyX())
end

-- Regler: Pfeile und Schiene in die festen Spalten, die Zahl (z. B. "5.5") rechts hinter den rechten Pfeil
local function AlignSlider(element, holder)
    local back, fwd = holder.Back or holder.BackButton, holder.Forward or holder.ForwardButton
    PlaceRow(element, back, holder.Slider, fwd)
    if not (controlX and fwd) then return end
    for _, r in ipairs({ holder:GetRegions() }) do
        if r:IsObjectType("FontString") and r:IsShown() then Put(r, element, BodyX() + CONTROL_W + PAD + ARROW_W + 8) end
    end
    for _, key in ipairs({ "RightText", "MaxText", "Label" }) do
        local t = holder[key]
        if type(t) == "table" and t.IsObjectType and t:IsObjectType("FontString") then
            Put(t, element, BodyX() + CONTROL_W + PAD + ARROW_W + 8)
        end
    end
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
                -- Pfeile links/rechts der Liste: unter Blizzards Namen oder allgemein die Knöpfe neben der Liste
                local dec = control.DecrementButton or control.LeftButton or dd.DecrementButton
                local inc = control.IncrementButton or control.RightButton or dd.IncrementButton
                if not (dec and inc) then
                    local ddLeft = dd:GetLeft()
                    for _, child in ipairs({ control:GetChildren() }) do
                        if child ~= dd and child:IsObjectType("Button") and child:GetLeft() and ddLeft then
                            if child:GetLeft() < ddLeft then dec = dec or child else inc = inc or child end
                        end
                    end
                end
                -- alle Auswahllisten gleich breit und mit ihren Pfeilen in den festen Spalten (wie die Regler) – auch
                -- mit Haken davor
                PlaceRow(element, dec, dd, inc)
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
                        if controlX then Put(b, element, BodyX(), CONTROL_W) end
                    else
                        -- Knopf ohne Namen (Tastaturbelegung: "Klickzauber", "Bewegungstasten" …): linksbündig ab der
                        -- Spalte der Namen bis zum Ende der Auswahllisten-Spalte
                        local left, right = labelX, (controlX and BodyX() or labelX) + CONTROL_W
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
-- Gilt für ALLE Menüs dieser Art (auch Rechtsklick auf Einheiten und Einheitenfenster) samt Untermenüs: das
-- Hauptmenü kennt Blizzards Menü-Verwaltung, Untermenüs werden (nur solange ein Menü offen ist, gedrosselt) unter
-- den Rahmen gesucht – Menü-Rahmen erkennt man an ihrer Menü-Beschreibung
local menuBacks = {}                                  -- [Menü] = eigener Rahmen dahinter
local knownMenus = setmetatable({}, { __mode = "k" }) -- gefundene Menü-Rahmen (auch Untermenüs)
local function BackFor(menu)
    local back = menuBacks[menu]
    if not back then
        back = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ns.UI.SetFlat(back, C.background)
        local line = back:CreateTexture(nil, "ARTWORK")
        line:SetTexture(WHITE)
        line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
        line:SetPoint("TOPLEFT", 1, -1)
        line:SetPoint("TOPRIGHT", -1, -1)
        ns.OnePixel(line, true)
        back:EnableMouse(false)
        back:SetAllPoints(menu)
        menuBacks[menu] = back
    end
    return back
end
local function SkinMenuFrame(menu)
    if not (menu and menu.IsShown and menu:IsShown()) or (menu.IsForbidden and menu:IsForbidden()) then return end
    for _, r in ipairs({ menu:GetRegions() }) do
        if r:IsObjectType("Texture") then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "NineSlice", "Background", "Bg" }) do
        if type(menu[key]) == "table" and menu[key].SetAlpha then menu[key]:SetAlpha(0) end
    end
    local back = BackFor(menu)
    back:SetFrameStrata(menu:GetFrameStrata())    back:SetFrameLevel(math.max(0, menu:GetFrameLevel() - 1))
    back:Show()
end
-- Untermenü: wie das Hauptmenü gebaut – kein Knopf (Auswahllisten-Knöpfe tragen ebenfalls eine Menü-Beschreibung!),
-- gleicher Eltern-Rahmen und gleiche Bildschirmebene wie das offene Hauptmenü
-- (Seit 2026-11-07 auch Untermenüs, die am Hauptmenü bzw. an einem anderen Menü selbst hängen oder auf einer anderen
-- Bildschirmebene liegen – z. B. "Schlagwörter hinzufügen" im Rechtsklick-Menü der Freundesliste blieb sonst alt)
local function IsMenuFrame(frame, root)
    if type(frame) ~= "table" or (frame.IsForbidden and frame:IsForbidden()) then return false end
    if not (frame.GetObjectType and frame:GetObjectType() == "Frame") then return false end
    if not (type(frame.menuDescription) == "table" or type(frame.GetMenuDescription) == "function") then return false end
    local parent = frame:GetParent()
    return parent == root:GetParent() or knownMenus[parent] == true
end
local lastSearch = 0
function ns.SkinOpenMenu()
    local manager = Menu and Menu.GetManager and Menu.GetManager()
    local root = manager and manager.GetOpenMenu and manager:GetOpenMenu()
    local open = root and root.IsShown and root:IsShown()
    if open then
        knownMenus[root] = true
        -- Untermenüs suchen (höchstens fünfmal je Sekunde, nur bei offenem Menü). Sie hängen am selben Eltern-Rahmen
        -- wie das Hauptmenü – darum nur dessen Unter-Rahmen durchsehen statt aller Rahmen des Spiels (das ruckelte)
        local now = GetTime()
        local parent = root:GetParent()
        if now - lastSearch > 0.2 and parent and parent.GetChildren then
            lastSearch = now
            for _, frame in ipairs({ parent:GetChildren() }) do
                if not knownMenus[frame] and frame:IsShown() and IsMenuFrame(frame, root) then knownMenus[frame] = true end
            end
            -- Untermenüs, die an einem offenen Menü selbst hängen (auch mehrere Stufen tief)
            local list = {}
            for menu in pairs(knownMenus) do if menu:IsShown() then list[#list + 1] = menu end end
            local i = 1
            while list[i] and i < 20 do
                for _, frame in ipairs({ list[i]:GetChildren() }) do
                    if not knownMenus[frame] and frame:IsShown() and IsMenuFrame(frame, root) then
                        knownMenus[frame] = true
                        list[#list + 1] = frame
                    end
                end
                i = i + 1
            end
        end
    end
    for menu in pairs(knownMenus) do
        if open and menu:IsShown() then SkinMenuFrame(menu) end
    end
    for menu, back in pairs(menuBacks) do
        if not (open and menu:IsShown()) then back:Hide() end
    end
end

-- überall (nicht nur in umgestalteten Fenstern): ein kleiner Taktgeber, der nur arbeitet, solange ein Menü offen ist;
-- dazu gleich beim Öffnen (Haken an Blizzards Menü-Verwaltung), damit kein Blizzard-Menü aufblitzt
local menuDriver = CreateFrame("Frame")
local menuWaited = 0
menuDriver:SetScript("OnUpdate", function(_, elapsed)
    menuWaited = menuWaited + elapsed
    if menuWaited < 0.05 then return end
    menuWaited = 0
    if not ns.GetDB().menus then return end
    pcall(ns.SkinOpenMenu)
end)
local menuHooked = false
local function HookMenuManager()
    local manager = not menuHooked and Menu and Menu.GetManager and Menu.GetManager()
    if not manager then return end
    menuHooked = true
    for _, method in ipairs({ "OpenMenu", "OpenContextMenu" }) do
        if type(manager[method]) == "function" then
            hooksecurefunc(manager, method, function()
                if ns.GetDB().menus then pcall(ns.SkinOpenMenu) end
            end)
        end
    end
end
local menuEvents = CreateFrame("Frame")
menuEvents:RegisterEvent("PLAYER_LOGIN")
menuEvents:SetScript("OnEvent", function() pcall(HookMenuManager) end)

local function SkinSearchBox(box) ns.SkinSearchBox(box, { -4, 2, 0, 2 }) end

local function SkinSettings()
    local f = _G.SettingsPanel
    if not f or ns.settingsSkinned then return end
    ns.settingsSkinned = true
    -- Titel steht bei diesem Fenster im Rahmen (NineSlice.Text) – der wird unsichtbar, darum eigener Titel
    local blizzTitle = f.NineSlice and f.NineSlice.Text
    ns.SkinWindow(f)
    -- Titelleiste wie bei Forever Core UI: Logo und Titel links
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
        ns.OnePixel(navLine, false)
        -- feine goldene Linie unter den Reitern "Spiel/Addons"
        if f.GameTab then
            local tabLine = f:CreateTexture(nil, "ARTWORK")
            tabLine:SetTexture(WHITE)
            tabLine:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
            tabLine:SetPoint("TOPLEFT", f.GameTab, "BOTTOMLEFT", -2, -6)
            tabLine:SetPoint("RIGHT", nav, "RIGHT", -8, 0)
            ns.OnePixel(tabLine, true)
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
            ns.OnePixel(line, true)
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
