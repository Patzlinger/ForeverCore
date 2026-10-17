local addonName, ns = ...
local L = ns.L

-- Menü im Stil von ForeverQuests: links die Liste der Leisten, rechts die Einstellungen der gewählten Leiste,
-- unten allgemeine Einstellungen. Alle Änderungen wirken sofort (im Kampf erst danach).

local options
local controls = {}       -- alle Bedienelemente mit :Refresh()
local barButtons = {}     -- Einträge der Leistenliste
local selectedKey = "bar1"
local searchIndex = {}    -- für die Suche: { label, control, page } je Einstellung
local pageInfo = {}       -- [Seite] = wo sie im Menü liegt (Ansicht, Reiter, Name für die Suche)

local WINDOW_WIDTH, WINDOW_HEIGHT = 720, 810
local PANEL_HEIGHT = 446   -- Platz für alle Einträge der Leistenliste
local GENERAL_HEIGHT = 236 -- Feld "Allgemein"
local LIST_WIDTH = 200
local DROPDOWN_X = 150

local VISIBILITY_CHOICES = {
    { value = "ALWAYS", textKey = "VIS_ALWAYS" },
    { value = "COMBAT", textKey = "VIS_COMBAT" },
    { value = "NOCOMBAT", textKey = "VIS_NOCOMBAT" },
}

local GROW_X_CHOICES = {
    { value = "RIGHT", textKey = "GROW_RIGHT" },
    { value = "LEFT", textKey = "GROW_LEFT" },
}
local GROW_Y_CHOICES = {
    { value = "DOWN", textKey = "GROW_DOWN" },
    { value = "UP", textKey = "GROW_UP" },
}
-- Seite des Einklapp-Pfeils (Berufe, Verpflegung)
local ARROW_SIDE_CHOICES = {
    { value = "AUTO", textKey = "SIDE_AUTO" },
    { value = "LEFT", textKey = "SIDE_LEFT" },
    { value = "RIGHT", textKey = "SIDE_RIGHT" },
    { value = "TOP", textKey = "SIDE_TOP" },
    { value = "BOTTOM", textKey = "SIDE_BOTTOM" },
}
local FLYOUT_CHOICES = {
    { value = "UP", textKey = "DIR_UP" },
    { value = "DOWN", textKey = "DIR_DOWN" },
    { value = "LEFT", textKey = "DIR_LEFT" },
    { value = "RIGHT", textKey = "DIR_RIGHT" },
}
local OUTLINE_CHOICES = {
    { value = "NONE", textKey = "OUTLINE_NONE" },
    { value = "OUTLINE", textKey = "OUTLINE_THIN" },
    { value = "THICKOUTLINE", textKey = "OUTLINE_THICK" },
}
local HOTKEY_POS_CHOICES = {
    { value = "TOPRIGHT", textKey = "POS_TOPRIGHT" },
    { value = "TOPLEFT", textKey = "POS_TOPLEFT" },
    { value = "TOP", textKey = "POS_TOP" },
}

-- Schriftarten als Auswahl (Namen fest oder aus den Texten)
local function FontChoices()
    local choices = {}
    for _, font in ipairs(ns.FONTS) do
        table.insert(choices, { value = font.key, textKey = font.textKey, text = font.text })
    end
    return choices
end

local function SelectedConfig()
    return ns.db.bars[selectedKey]
end

-- Änderung übernehmen; im Kampf Hinweis, dass sie danach kommt
local function Changed()
    if InCombatLockdown() then ns.Print(L("COMBAT_QUEUED")) end
    ns.RequestLayout()
end

---------------------------------------------------------------------------
-- Bausteine (wie in ForeverQuests)
---------------------------------------------------------------------------

-- Einstellung für die Suche merken
local function AddSearch(label, control, page)
    if label and label ~= "" then table.insert(searchIndex, { label = label, control = control, page = page }) end
    return control
end

local function CreateCheckbox(parent, label, x, y, getValue, setValue)
    local checkbox = ns.Style.CreateCheckbox(parent, label)
    checkbox:SetPoint("TOPLEFT", x, y)
    checkbox:SetScript("OnClick", function(self)
        setValue(self:GetChecked() and true or false)
    end)
    checkbox.Refresh = function() checkbox:SetChecked(getValue()) end
    table.insert(controls, checkbox)
    return AddSearch(label, checkbox, parent)
end

-- step (optional): Schrittweite, z. B. 0.5 für den Abstand; sonst ganze Zahlen
local function CreateSlider(parent, label, x, y, width, getMin, getMax, getValue, setValue, step)
    step = step or 1
    local function Round(value) return math.floor(value / step + 0.5) * step end
    local function Format(value)
        value = Round(value)
        return value == math.floor(value) and tostring(math.floor(value)) or string.format("%.1f", value)
    end
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width + 70, 40)

    local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(0.75, 0.75, 0.75)

    local slider = ns.Style.CreateSlider(holder, width)
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetValueStep(step)

    local box = ns.Style.CreateEditBox(holder, 50, 20)
    box:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    box:SetJustifyH("CENTER")
    box:SetNumeric(step == 1) -- Kommazahlen brauchen Punkt/Komma

    slider:SetScript("OnValueChanged", function(_, value, userInput)
        box:SetText(Format(value))
        if userInput then setValue(Round(value)) end
    end)
    box:SetScript("OnEnterPressed", function(self)
        local text = (self:GetText() or ""):gsub(",", ".")
        local value = tonumber(text)
        if value then setValue(math.min(getMax(), math.max(getMin(), Round(value)))) end
        self:ClearFocus()
        ns.RefreshOptions()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns.RefreshOptions()
    end)

    holder.Refresh = function()
        slider:SetMinMaxValues(getMin(), getMax())
        local value = getValue() or getMin()
        slider:SetValue(value)
        box:SetText(Format(value))
    end
    table.insert(controls, holder)
    return AddSearch(label, holder, parent)
end

-- Text einer Auswahl: aus den Übersetzungen (textKey) oder fest (text, z. B. Schriftnamen)
local function ChoiceText(choice)
    return choice.textKey and L(choice.textKey) or choice.text or tostring(choice.value)
end

-- Auswahlknopf mit Liste; compact = Beschriftung über dem Knopf statt links daneben
local function CreateSelectorBase(parent, label, x, y, width, choices, getValue, setValue, compact)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    local text = holder:CreateFontString(nil, "OVERLAY", compact and "GameFontHighlightSmall" or "GameFontHighlight")
    text:SetText(label)
    holder.label = text -- Beschriftung lässt sich später ändern (z. B. Namen der Gestalten)

    local button = ns.Style.CreateDropdown(holder, width)
    holder.button = button
    if compact then
        holder:SetSize(width, 40)
        text:SetPoint("TOPLEFT", 0, 0)
        text:SetTextColor(0.75, 0.75, 0.75)
        button:SetPoint("TOPLEFT", 0, -16)
    else
        holder:SetSize(DROPDOWN_X + width, 24)
        text:SetPoint("LEFT", 0, 0)
        button:SetPoint("LEFT", DROPDOWN_X - 14, 0)
    end
    button:SetScript("OnClick", function(self)
        local items = {}
        for _, choice in ipairs(choices) do
            table.insert(items, {
                radio = true,
                text = ChoiceText(choice),
                checked = function() return getValue() == choice.value end,
                onClick = function()
                    setValue(choice.value)
                    ns.RefreshOptions()
                end,
            })
        end
        ns.Style.ShowMenu(self, items, { align = "LEFT" })
    end)
    holder.Refresh = function()
        button:SetText("")
        for _, choice in ipairs(choices) do
            if choice.value == getValue() then button:SetText(ChoiceText(choice)) end
        end
    end
    table.insert(controls, holder)
    return AddSearch(label, holder, parent)
end

-- Knopf, der auch in der Suche auftaucht
local function CreateSearchButton(parent, text, width, height, onClick, tooltip)
    local button = ns.Style.CreateButton(parent, text, width, height, onClick, tooltip)
    return AddSearch(text, button, parent)
end

-- Überschrift innerhalb einer Seite (goldene Schrift, dünne Linie)
local function CreateHeading(parent, text, x, y, width)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x - 2, y - 18)
    line:SetWidth(width)
    return title
end

local function CreateSelector(parent, label, x, y, width, choices, getValue, setValue)
    return CreateSelectorBase(parent, label, x, y, width, choices, getValue, setValue, false)
end

local function CreateSmallSelector(parent, label, x, y, width, choices, getValue, setValue)
    return CreateSelectorBase(parent, label, x, y, width, choices, getValue, setValue, true)
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------

local function CreateOptions()
    options = ns.Style.CreateWindow("ForeverBarsOptions", WINDOW_WIDTH, WINDOW_HEIGHT, L("OPT_TITLE"))
    options.subText:SetText(L("ADDON_NAME"))
    options:SetScript("OnHide", function() ns.Style.HideMenu() end)

    -- Hinweis, solange Bartender4 aktiv ist
    options.warning = options:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    options.warning:SetPoint("TOPLEFT", 16, -48)
    options.warning:SetPoint("RIGHT", -16, 0)
    options.warning:SetJustifyH("LEFT")
    options.warning:SetTextColor(1, 0.45, 0.45)
    options.warning:SetText(L("BARTENDER_ACTIVE"))

    -- Links: Liste der Leisten
    local list = ns.Style.CreatePanel(options, L("SEC_BARS"))
    list:SetPoint("TOPLEFT", 12, -68)
    list:SetSize(LIST_WIDTH, PANEL_HEIGHT)
    local function ListButton(text, y, key, onClick)
        -- 19 hoch im 21er-Raster: so passen alle 18 Leisten und "Profile" ins Feld
        local button = ns.Style.CreateButton(list, text, LIST_WIDTH - 24, 19, onClick)
        button:SetPoint("TOPLEFT", 12, y)
        button:GetFontString():ClearAllPoints()
        button:GetFontString():SetPoint("LEFT", 8, 0)
        button.key = key
        button:HookScript("OnLeave", function() ns.RefreshOptions() end)
        table.insert(barButtons, button)
        return button
    end
    local listY = -38
    for _, def in ipairs(ns.BAR_DEFS) do
        local button = ListButton(L(def.textKey), listY, def.key, function()
            selectedKey = def.key
            options.view = "bar"
            ns.RefreshOptions()
        end)
        table.insert(searchIndex, { label = L(def.textKey), control = button, barKey = def.key })
        listY = listY - 21
    end
    -- Unterpunkt "Profile" (Vorlagen, gespeicherte Profile, Export/Import), etwas abgesetzt
    local profileEntry = ListButton(L("SEC_PROFILES"), listY - 4, "profiles", function()
        options.view = "profiles"
        ns.RefreshOptions()
    end)
    table.insert(searchIndex, { label = L("SEC_PROFILES"), control = profileEntry, view = "profiles" })
    options.view = "bar"

    -- Rechts: Einstellungen der gewählten Leiste
    local bar = ns.Style.CreatePanel(options, L("SEC_BAR"))
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
    bar:SetPoint("RIGHT", -12, 0)
    bar:SetHeight(PANEL_HEIGHT)
    options.barTitle = bar.title
    options.barPanel = bar
    pageInfo[bar] = { view = "bar", path = L("SEC_BAR") }

    -- Erfahrungsleiste von ForeverXP: statt der Einstellungen ein Hinweis mit Knopf ins ForeverXP-Menü
    local external = CreateFrame("Frame", nil, bar)
    external:SetAllPoints()
    local externalText = external:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    externalText:SetPoint("TOPLEFT", 14, -48)
    externalText:SetPoint("RIGHT", -14, 0)
    externalText:SetJustifyH("LEFT")
    externalText:SetText(L("XP_EXTERNAL_TEXT"))
    ns.Style.CreateButton(external, L("BTN_OPEN_FOREVERXP"), 220, 24, function()
        -- ForeverBars-Menü bleibt offen; ForeverXP öffnet sein eigenes Fenster
        if SlashCmdList and SlashCmdList.FOREVERXP then SlashCmdList.FOREVERXP("") end
    end):SetPoint("TOPLEFT", externalText, "BOTTOMLEFT", 0, -14)
    external:Hide()
    options.externalXP = external

    options.enabledCheck = CreateCheckbox(bar, L("OPT_ENABLED"), 14, -44,
        function() return SelectedConfig().enabled end,
        function(value) SelectedConfig().enabled = value; Changed() end)

    -- Zwei Reiter: "Anordnung" und "Sichtbarkeit" (je eine Seite im Feld)
    local layoutPage = CreateFrame("Frame", nil, bar)
    layoutPage:SetAllPoints()
    local visPage = CreateFrame("Frame", nil, bar)
    visPage:SetAllPoints()
    options.pages = { layout = layoutPage, visibility = visPage }
    options.tabs = {}
    pageInfo[layoutPage] = { view = "bar", page = "layout", path = L("TAB_LAYOUT") }
    pageInfo[visPage] = { view = "bar", page = "visibility", path = L("TAB_VISIBILITY") }
    local tabX = -14
    for _, tab in ipairs({ { key = "visibility", textKey = "TAB_VISIBILITY" }, { key = "layout", textKey = "TAB_LAYOUT" } }) do
        local button = ns.Style.CreateButton(bar, L(tab.textKey), 96, 20, function()
            options.page = tab.key
            ns.RefreshOptions()
        end)
        button:SetPoint("TOPRIGHT", tabX, -8)
        button.key = tab.key
        button:HookScript("OnLeave", function() ns.RefreshOptions() end)
        table.insert(options.tabs, button)
        tabX = tabX - 100
    end
    options.page = "layout"

    -- Linke Spalte: Anzahl, Reihen, Abstand (nur Leisten mit einzelnen Knöpfen), Größe, Deckkraft, Position
    options.buttonsSlider = CreateSlider(layoutPage, L("OPT_BUTTONS"), 14, -74, 180,
        function() return 1 end, function() return math.max(1, ns.GetMaxButtons(selectedKey)) end,
        function() return SelectedConfig().buttons or 1 end,
        function(value) SelectedConfig().buttons = value; Changed() end)
    options.perRowSlider = CreateSlider(layoutPage, L("OPT_PER_ROW"), 14, -118, 180,
        function() return 1 end, function() return math.max(1, ns.GetMaxButtons(selectedKey)) end,
        function() return SelectedConfig().perRow or 1 end,
        function(value) SelectedConfig().perRow = value; Changed() end)
    options.spacingSlider = CreateSlider(layoutPage, L("OPT_SPACING"), 14, -162, 180,
        function() return 0 end, function() return 20 end,
        function() return SelectedConfig().spacing or 1.5 end,
        function(value) SelectedConfig().spacing = value; Changed() end, 0.5)
    options.scaleSlider = CreateSlider(layoutPage, L("OPT_SCALE"), 14, -206, 180,
        function() return 50 end, function() return 200 end,
        function() return SelectedConfig().scale or 100 end,
        function(value) SelectedConfig().scale = value; Changed() end)
    options.alphaSlider = CreateSlider(layoutPage, L("OPT_ALPHA"), 14, -250, 180,
        function() return 0 end, function() return 100 end,
        function() return SelectedConfig().alpha or 100 end,
        function(value) SelectedConfig().alpha = value; Changed() end)
    -- Position (Mitte der Leiste, von unten links); geht auch per Ziehen im entsperrten Zustand
    options.posXSlider = CreateSlider(layoutPage, L("OPT_POS_X"), 14, -294, 180,
        function() return 0 end, function() return math.floor(UIParent:GetWidth()) end,
        function() return (ns.GetBarPosition(selectedKey)) end,
        function(value) SelectedConfig().x = value; Changed() end)
    options.posYSlider = CreateSlider(layoutPage, L("OPT_POS_Y"), 14, -338, 180,
        function() return 0 end, function() return math.floor(UIParent:GetHeight()) end,
        function() return select(2, ns.GetBarPosition(selectedKey)) end,
        function(value) SelectedConfig().y = value; Changed() end)

    -- Rechte Spalte: Wachstumsrichtung, Ausklapp-Richtung, Taschen, Zentrieren
    local RIGHT_X = 290
    options.growXSelector = CreateSmallSelector(layoutPage, L("OPT_GROW_X"), RIGHT_X, -92, 170, GROW_X_CHOICES,
        function() return SelectedConfig().growX or "RIGHT" end,
        function(value) SelectedConfig().growX = value; Changed() end)
    options.growYSelector = CreateSmallSelector(layoutPage, L("OPT_GROW_Y"), RIGHT_X, -140, 170, GROW_Y_CHOICES,
        function() return SelectedConfig().growY or "DOWN" end,
        function(value) SelectedConfig().growY = value; Changed() end)
    options.flyoutSelector = CreateSmallSelector(layoutPage, L("OPT_FLYOUT"), RIGHT_X, -188, 170, FLYOUT_CHOICES,
        function() return SelectedConfig().flyout or "UP" end,
        function(value) SelectedConfig().flyout = value; Changed() end)
    -- Nur Berufe- und Verpflegungsleiste: Pfeil auf der Innenseite zum Ein-/Ausklappen
    options.collapseArrowCheck = CreateCheckbox(layoutPage, L("OPT_COLLAPSE_ARROW"), RIGHT_X, -192,
        function() return SelectedConfig().collapseArrow end,
        function(value) SelectedConfig().collapseArrow = value; Changed(); ns.RefreshOptions() end)
    -- Auf welcher Seite der Leiste der Pfeil sitzt
    options.arrowSideSelector = CreateSmallSelector(layoutPage, L("OPT_ARROW_SIDE"), RIGHT_X + 16, -216, 154, ARROW_SIDE_CHOICES,
        function() return SelectedConfig().arrowSide or "AUTO" end,
        function(value) SelectedConfig().arrowSide = value; Changed() end)
    -- Nur Taschenleiste (an der Stelle der Ausklapp-Richtung, die es nur bei Aktionsleisten gibt)
    -- Taschenleiste ausklappbar: eingeklappt nur der Rucksack, ein Pfeil klappt die Taschen aus
    options.backpackCheck = CreateCheckbox(layoutPage, L("OPT_BAGS_COLLAPSIBLE"), RIGHT_X, -192,
        function() return SelectedConfig().collapsible end,
        function(value) SelectedConfig().collapsible = value; Changed() end)
    -- Nur Mikromenü: schwarz-weiß (goldener Rand beim Darüberfahren bleibt)
    -- Nur Mikromenü: eigene flache Text-Knöpfe statt Blizzards Knöpfe
    options.microOwnCheck = CreateCheckbox(layoutPage, L("OPT_MICRO_OWN"), RIGHT_X, -146,
        function() return SelectedConfig().microOwn end,
        function(value) SelectedConfig().microOwn = value; Changed(); ns.RefreshOptions() end)
    options.microGreyCheck = CreateCheckbox(layoutPage, L("OPT_MICRO_GREY"), RIGHT_X, -170,
        function() return SelectedConfig().microGrey end,
        function(value) SelectedConfig().microGrey = value; ns.StyleMicroMenu() end)
    options.keyringCheck = CreateCheckbox(layoutPage, L("OPT_KEYRING"), RIGHT_X, -216,
        function() return SelectedConfig().keyring end,
        function(value) SelectedConfig().keyring = value; Changed() end)
    -- Nur Verpflegungs- und Berufeleiste: herausgezogene Knöpfe und eigene Reihenfolge zurücksetzen
    options.foodResetButton = CreateSearchButton(layoutPage, L("BTN_FOOD_RESET"), 170, 20, function()
        if selectedKey == "prof" then ns.ProfResetChoices() else ns.FoodResetChoices() end
        ns.Print(L("FOOD_RESET_DONE"))
    end, L("TIP_FOOD_RESET"))
    options.foodResetButton:SetPoint("TOPLEFT", RIGHT_X, -214)
    -- Rahmen um die Leiste (wie die Fenster in ForeverQuests)
    options.frameCheck = CreateCheckbox(layoutPage, L("OPT_FRAME"), RIGHT_X, -244,
        function() return SelectedConfig().frame end,
        function(value) SelectedConfig().frame = value; Changed(); ns.RefreshOptions() end)
    options.frameTitleCheck = CreateCheckbox(layoutPage, L("OPT_FRAME_TITLE"), RIGHT_X + 16, -268,
        function() return SelectedConfig().frameTitle end,
        function(value) SelectedConfig().frameTitle = value; Changed(); ns.RefreshOptions() end)
    -- Eigener Titel (leer = Name der Leiste); Enter oder Verlassen des Feldes übernimmt
    local titleBox = ns.Style.CreateEditBox(layoutPage, 154, 22)
    titleBox:SetPoint("TOPLEFT", RIGHT_X + 16, -290)
    local titlePlaceholder = titleBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    titlePlaceholder:SetPoint("LEFT", 7, 0)
    titlePlaceholder:SetText(L("OPT_FRAME_TITLE_TEXT"))
    local function SaveTitle(self)
        SelectedConfig().frameTitleText = strtrim(self:GetText() or "")
        Changed()
    end
    titleBox:SetScript("OnEnterPressed", function(self) SaveTitle(self); self:ClearFocus() end)
    titleBox:HookScript("OnEditFocusLost", SaveTitle)
    titleBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleBox:SetScript("OnTextChanged", function(self)
        titlePlaceholder:SetShown((self:GetText() or "") == "" and not self:HasFocus())
    end)
    titleBox:HookScript("OnEditFocusGained", function() titlePlaceholder:Hide() end)
    titleBox.Refresh = function()
        if not titleBox:HasFocus() then titleBox:SetText(SelectedConfig().frameTitleText or "") end
        titlePlaceholder:SetShown((titleBox:GetText() or "") == "" and not titleBox:HasFocus())
    end
    table.insert(controls, titleBox)
    AddSearch(L("OPT_FRAME_TITLE_TEXT"), titleBox, layoutPage)
    options.frameTitleBox = titleBox

    -- Zentrieren: Leiste waagerecht bzw. senkrecht in die Bildschirmmitte setzen
    options.centerXButton = CreateSearchButton(layoutPage, L("BTN_CENTER_X"), 170, 22, function()
        ns.SetBarCenter(selectedKey, UIParent:GetWidth() / 2, nil)
        Changed()
        ns.RefreshOptions()
    end)
    options.centerXButton:SetPoint("TOPLEFT", RIGHT_X, -326)
    options.centerYButton = CreateSearchButton(layoutPage, L("BTN_CENTER_Y"), 170, 22, function()
        ns.SetBarCenter(selectedKey, nil, UIParent:GetHeight() / 2)
        Changed()
        ns.RefreshOptions()
    end)
    options.centerYButton:SetPoint("TOPLEFT", RIGHT_X, -352)

    local resetButton = CreateSearchButton(layoutPage, L("BTN_RESET_BAR"), 170, 22, function()
        ns.ResetBar(selectedKey)
        ns.Print(L("RESET_DONE"))
        ns.RefreshOptions()
    end)
    resetButton:SetPoint("TOPLEFT", RIGHT_X, -390)

    -- Reihenfolge der beiden Spalten; RefreshOptions setzt die gerade sichtbaren lückenlos untereinander
    -- (je Zeile: Element, Höhe, Einrückung; spacer = zusätzlicher Abstand)
    options.layoutPage = layoutPage
    options.layoutColumns = {
        { x = 14, rows = {
            { options.buttonsSlider, 44 }, { options.perRowSlider, 44 }, { options.spacingSlider, 44 },
            { options.scaleSlider, 44 }, { options.alphaSlider, 44 }, { options.posXSlider, 44 },
            { options.posYSlider, 50 },
        } },
        { x = RIGHT_X, rows = {
            { options.growXSelector, 48 }, { options.growYSelector, 48 }, { options.flyoutSelector, 48 },
            { options.microOwnCheck, 24 }, { options.microGreyCheck, 24 }, { options.collapseArrowCheck, 24 },
            { options.arrowSideSelector, 46, 16 },
            { options.backpackCheck, 24 }, { options.keyringCheck, 24 }, { options.foodResetButton, 30 },
            { options.frameCheck, 24 }, { options.frameTitleCheck, 22, 16 }, { titleBox, 32, 16 },
            { spacer = 8 }, { options.centerXButton, 26 }, { options.centerYButton, 38 }, { resetButton, 26 },
        } },
    }

    -- Reiter "Sichtbarkeit": wann die Leiste zu sehen ist
    -- Links: Grundeinstellung und Einblenden bei Maus darüber
    CreateSmallSelector(visPage, L("OPT_VISIBILITY"), 14, -74, 200, VISIBILITY_CHOICES,
        function() return SelectedConfig().visibility end,
        function(value) SelectedConfig().visibility = value; Changed() end)
    CreateCheckbox(visPage, L("OPT_FADE"), 14, -126,
        function() return SelectedConfig().fadeMouseover end,
        function(value) SelectedConfig().fadeMouseover = value; Changed() end)
    CreateCheckbox(visPage, L("OPT_FADE_COMBAT"), 14, -150,
        function() return SelectedConfig().fadeInCombat end,
        function(value) SelectedConfig().fadeInCombat = value end)
    CreateSlider(visPage, L("OPT_FADE_ALPHA"), 14, -180, 180,
        function() return 0 end, function() return 100 end,
        function() return SelectedConfig().fadeAlpha or 0 end,
        function(value) SelectedConfig().fadeAlpha = value end)
    CreateSlider(visPage, L("OPT_FADE_DELAY"), 14, -224, 180,
        function() return 0 end, function() return 10 end,
        function() return SelectedConfig().fadeDelay or 0 end,
        function(value) SelectedConfig().fadeDelay = value end)

    -- Rechts: in bestimmten Situationen ausblenden
    local hideTitle = visPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hideTitle:SetPoint("TOPLEFT", 290, -74)
    hideTitle:SetTextColor(0.75, 0.75, 0.75)
    hideTitle:SetText(L("OPT_HIDE_WHEN"))
    local hideOptions = {
        { key = "hideVehicle", textKey = "HIDE_VEHICLE" },
        { key = "hideOverride", textKey = "HIDE_OVERRIDE" },
        { key = "hidePossess", textKey = "HIDE_POSSESS" },
        { key = "hidePet", textKey = "HIDE_PET" },
        { key = "hideNoPet", textKey = "HIDE_NOPET" },
        { key = "hideStance", textKey = "HIDE_STANCE" },
    }
    for i, option in ipairs(hideOptions) do
        CreateCheckbox(visPage, L(option.textKey), 290, -92 - (i - 1) * 24,
            function() return SelectedConfig()[option.key] end,
            function(value) SelectedConfig()[option.key] = value; Changed() end)
    end

    -- Unten: eigene Makro-Bedingung (ersetzt alle Einstellungen oben)
    CreateCheckbox(visPage, L("OPT_CUSTOM"), 14, -280,
        function() return SelectedConfig().useCustom end,
        function(value) SelectedConfig().useCustom = value; Changed() end)
    local customBox = ns.Style.CreateEditBox(visPage, 440, 22)
    customBox:SetPoint("TOPLEFT", 14, -306)
    local function SaveCustom(self)
        SelectedConfig().custom = strtrim(self:GetText() or "")
        Changed()
    end
    customBox:SetScript("OnEnterPressed", function(self) SaveCustom(self); self:ClearFocus() end)
    customBox:HookScript("OnEditFocusLost", SaveCustom)
    customBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    customBox.Refresh = function()
        if not customBox:HasFocus() then customBox:SetText(SelectedConfig().custom or "") end
    end
    table.insert(controls, customBox)
    local customHint = visPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    customHint:SetPoint("TOPLEFT", 14, -334)
    customHint:SetPoint("RIGHT", -14, 0)
    customHint:SetJustifyH("LEFT")
    customHint:SetText(L("OPT_CUSTOM_HINT"))

    -- Unten: Allgemein (gilt für alle Leisten)
    local general = ns.Style.CreatePanel(options, L("SEC_GENERAL"))
    general:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -10)
    general:SetPoint("RIGHT", -12, 0)
    general:SetHeight(GENERAL_HEIGHT)

    -- Reiter: "Darstellung" (Aussehen der Knöpfe), "Schrift" (Texte auf den Knöpfen),
    -- "Bedienung" (Blizzard-Einstellungen fürs Zaubern), "Verwaltung" (Minimap-Symbol)
    local displayPage = CreateFrame("Frame", nil, general)
    displayPage:SetAllPoints()
    local fontPage = CreateFrame("Frame", nil, general)
    fontPage:SetAllPoints()
    local controlPage = CreateFrame("Frame", nil, general)
    controlPage:SetAllPoints()
    local managePage = CreateFrame("Frame", nil, general)
    managePage:SetAllPoints()
    options.generalPages = { display = displayPage, font = fontPage, control = controlPage, manage = managePage }
    local generalPath = L("SEC_GENERAL") .. " » "
    pageInfo[displayPage] = { general = "display", path = generalPath .. L("TAB_DISPLAY") }
    pageInfo[fontPage] = { general = "font", path = generalPath .. L("TAB_FONT") }
    pageInfo[controlPage] = { general = "control", path = generalPath .. L("TAB_CONTROL") }
    pageInfo[managePage] = { general = "manage", path = generalPath .. L("TAB_MANAGE") }
    options.generalTabs = {}
    options.generalPage = "display"
    local generalTabX = -14
    for _, tab in ipairs({ { key = "manage", textKey = "TAB_MANAGE" }, { key = "control", textKey = "TAB_CONTROL" },
                           { key = "font", textKey = "TAB_FONT" }, { key = "display", textKey = "TAB_DISPLAY" } }) do
        local button = ns.Style.CreateButton(general, L(tab.textKey), 110, 20, function()
            options.generalPage = tab.key
            ns.RefreshOptions()
        end)
        button:SetPoint("TOPRIGHT", generalTabX, -8)
        button.key = tab.key
        button:HookScript("OnLeave", function() ns.RefreshOptions() end)
        table.insert(options.generalTabs, button)
        generalTabX = generalTabX - 116
    end

    -- Reiter "Verwaltung": Minimap-Symbol; Vorlagen, Profile und Export/Import liegen unter "Profile"
    CreateCheckbox(managePage, L("OPT_MINIMAP"), 14, -42,
        function() return ns.db.showMinimapButton end,
        function(value) ns.db.showMinimapButton = value; ns.UpdateMinimapButton() end)
    local manageHint = managePage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    manageHint:SetPoint("TOPLEFT", 14, -72)
    manageHint:SetPoint("RIGHT", -14, 0)
    manageHint:SetJustifyH("LEFT")
    manageHint:SetText(L("OPT_MANAGE_MOVED"))

    -- Alles zurücksetzen: zweimal klicken (Einstellungen und Positionen; gespeicherte Profile bleiben)
    local resetAllButton
    resetAllButton = CreateSearchButton(managePage, L("BTN_RESET_ALL"), 260, 24, function()
        if resetAllButton.confirm then
            resetAllButton.confirm = nil
            resetAllButton:SetText(L("BTN_RESET_ALL"))
            ns.ResetAllSettings()
        else
            resetAllButton.confirm = true
            resetAllButton:SetText(L("BTN_PRESET_CONFIRM"))
            C_Timer.After(5, function()
                if resetAllButton.confirm then
                    resetAllButton.confirm = nil
                    resetAllButton:SetText(L("BTN_RESET_ALL"))
                end
            end)
        end
    end, L("TIP_RESET_ALL"))
    resetAllButton:SetPoint("TOPLEFT", 14, -100)

    -- Rechts statt der Leisten-Einstellungen: "Profile" (Vorlagen, gespeicherte Profile, Export/Import)
    local profilePanel = ns.Style.CreatePanel(options, L("SEC_PROFILES"))
    profilePanel:SetAllPoints(bar)
    options.profilePanel = profilePanel
    pageInfo[profilePanel] = { view = "profiles", path = L("SEC_PROFILES") }
    -- Breite der rechten Fläche: Fenster minus Liste und Ränder (12 + 200 + 12 ... 12)
    local PROFILE_WIDTH = WINDOW_WIDTH - LIST_WIDTH - 36 - 28
    local BUTTON_X = DROPDOWN_X - 14 + 168 -- rechts neben den Auswahlfeldern (160 breit)

    -- Gespeicherte Profile: wählen, laden, löschen; aktuelle Einstellungen unter einem Namen speichern
    CreateHeading(profilePanel, L("PROFILE_SAVED_TITLE"), 14, -44, PROFILE_WIDTH)
    local profileChoices = {}
    local profileSelector = CreateSelector(profilePanel, L("OPT_PROFILE"), 14, -76, 160, profileChoices,
        function() return options.selectedProfile end,
        function(value) options.selectedProfile = value end)
    profileSelector.Refresh = function()
        -- Auswahl-Liste aus den gespeicherten Profilen neu füllen (Standardprofil zuerst)
        wipe(profileChoices)
        for _, name in ipairs(ns.GetProfileNames()) do
            table.insert(profileChoices, { value = name, text = ns.ProfileLabel(name) })
        end
        if options.selectedProfile and not ns.HasProfile(options.selectedProfile) then options.selectedProfile = nil end
        if not options.selectedProfile then options.selectedProfile = ns.GetActiveProfile() end
        profileSelector.button:SetText(options.selectedProfile and ns.ProfileLabel(options.selectedProfile) or L("PROFILE_NONE"))
    end
    -- Aktives Profil oben rechts in der Überschrift
    options.activeProfileText = profilePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    options.activeProfileText:SetPoint("TOPRIGHT", -14, -47)
    CreateSearchButton(profilePanel, L("BTN_PROFILE_LOAD"), 82, 22, function()
        if options.selectedProfile then ns.LoadProfile(options.selectedProfile) end
    end):SetPoint("TOPLEFT", BUTTON_X, -77)
    -- Löschen: zweimal klicken
    local deleteButton
    deleteButton = CreateSearchButton(profilePanel, L("BTN_PROFILE_DELETE"), 82, 22, function()
        if not options.selectedProfile then return end
        if deleteButton.confirm then
            deleteButton.confirm = nil
            deleteButton:SetText(L("BTN_PROFILE_DELETE"))
            ns.DeleteProfile(options.selectedProfile)
            if options.selectedProfile ~= ns.DEFAULT_PROFILE then options.selectedProfile = nil end
            ns.RefreshOptions()
        else
            deleteButton.confirm = true
            deleteButton:SetText(L("BTN_CONFIRM_SHORT"))
            C_Timer.After(5, function()
                if deleteButton.confirm then
                    deleteButton.confirm = nil
                    deleteButton:SetText(L("BTN_PROFILE_DELETE"))
                end
            end)
        end
    end)
    deleteButton:SetPoint("TOPLEFT", BUTTON_X + 88, -77)
    local nameLabel = profilePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", 14, -114)
    nameLabel:SetText(L("OPT_PROFILE_NAME"))
    local nameBox = ns.Style.CreateEditBox(profilePanel, 160, 22)
    nameBox:SetPoint("TOPLEFT", DROPDOWN_X - 14, -110)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local function SaveProfile()
        if ns.SaveProfile(nameBox:GetText()) then
            options.selectedProfile = strtrim(nameBox:GetText())
            nameBox:SetText("")
            nameBox:ClearFocus()
            ns.RefreshOptions()
        end
    end
    nameBox:SetScript("OnEnterPressed", SaveProfile)
    CreateSearchButton(profilePanel, L("BTN_PROFILE_SAVE"), 170, 22, SaveProfile, L("TIP_PROFILE_SAVE"))
        :SetPoint("TOPLEFT", BUTTON_X, -110)

    -- Export/Import als Text (gespeicherte Profile sind enthalten)
    CreateHeading(profilePanel, L("PROFILE_TRANSFER_TITLE"), 14, -156, PROFILE_WIDTH)
    CreateSearchButton(profilePanel, L("BTN_EXPORT"), 220, 24, function() ns.ShowTransferWindow("export") end,
        L("TIP_EXPORT")):SetPoint("TOPLEFT", 14, -186)
    CreateSearchButton(profilePanel, L("BTN_IMPORT"), 220, 24, function() ns.ShowTransferWindow("import") end,
        L("TIP_IMPORT")):SetPoint("TOPLEFT", 244, -186)
    local profileHint = profilePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    profileHint:SetPoint("TOPLEFT", 14, -224)
    profileHint:SetPoint("RIGHT", -14, 0)
    profileHint:SetJustifyH("LEFT")
    profileHint:SetText(L("OPT_MANAGE_HINT"))

    -- Reiter "Bedienung": diese Einstellungen sind Blizzard-Einstellungen (auch im Blizzard-Menü sichtbar)
    local MODIFIER_CHOICES = {
        { value = "NONE", textKey = "MOD_NONE" },
        { value = "ALT", textKey = "MOD_ALT" },
        { value = "CTRL", textKey = "MOD_CTRL" },
        { value = "SHIFT", textKey = "MOD_SHIFT" },
    }
    local TOOLTIP_CHOICES = {
        { value = "ALWAYS", textKey = "TIP_ALWAYS" },
        { value = "NOCOMBAT", textKey = "TIP_NOCOMBAT" },
        { value = "NEVER", textKey = "TIP_NEVER" },
    }
    -- Nur ändern, wenn nicht im Kampf (manche Blizzard-Einstellungen sind im Kampf gesperrt)
    local function OutOfCombat(func)
        return function(value)
            if InCombatLockdown() then
                ns.Print(L("NOT_IN_COMBAT"))
                ns.RefreshOptions() -- Häkchen/Auswahl wieder auf den echten Wert setzen
                return
            end
            func(value)
        end
    end
    options.controlRows = {}
    local function Track(control, cvar) control.cvar = cvar; table.insert(options.controlRows, control); return control end

    Track(CreateCheckbox(controlPage, L("OPT_KEYDOWN"), 14, -42,
        function() return ns.GetCVarBool("ActionButtonUseKeyDown") end,
        OutOfCombat(function(value) ns.SetCVarBool("ActionButtonUseKeyDown", value) end)), "ActionButtonUseKeyDown")
    Track(CreateCheckbox(controlPage, L("OPT_LOCK_BUTTONS"), 360, -42,
        function() return ns.GetCVarBool("lockActionBars") end,
        OutOfCombat(function(value) ns.SetCVarBool("lockActionBars", value) end)), "lockActionBars")
    Track(CreateCheckbox(controlPage, L("OPT_MOUSEOVER_CAST"), 14, -68,
        function() return ns.GetCVarBool("enableMouseoverCast") end,
        OutOfCombat(function(value) ns.SetCVarBool("enableMouseoverCast", value) end)), "enableMouseoverCast")
    Track(CreateSelector(controlPage, L("OPT_MOUSEOVER_KEY"), 360, -70, 140, MODIFIER_CHOICES,
        function() return ns.GetModifier("MOUSEOVERCAST") end,
        OutOfCombat(function(value) ns.SetModifier("MOUSEOVERCAST", value) end)), "enableMouseoverCast")
    Track(CreateSelector(controlPage, L("OPT_SELFCAST_KEY"), 14, -102, 140, MODIFIER_CHOICES,
        function() return ns.GetModifier("SELFCAST") end,
        OutOfCombat(function(value) ns.SetModifier("SELFCAST", value) end)))
    Track(CreateSelector(controlPage, L("OPT_FOCUSCAST_KEY"), 360, -102, 140, MODIFIER_CHOICES,
        function() return ns.GetModifier("FOCUSCAST") end,
        OutOfCombat(function(value) ns.SetModifier("FOCUSCAST", value) end)))
    Track(CreateCheckbox(controlPage, L("OPT_AUTO_SELFCAST"), 14, -134,
        function() return ns.GetCVarBool("autoSelfCast") end,
        OutOfCombat(function(value) ns.SetCVarBool("autoSelfCast", value) end)), "autoSelfCast")
    CreateCheckbox(controlPage, L("OPT_CAST_VFX"), 360, -134,
        function() return ns.db.castVFX end,
        function(value) ns.db.castVFX = value; ns.UpdateAllButtons() end)
    CreateSelector(controlPage, L("OPT_BUTTON_TOOLTIP"), 14, -166, 170, TOOLTIP_CHOICES,
        function() return ns.db.buttonTooltip end,
        function(value) ns.db.buttonTooltip = value end)
    -- Neuer Rang gelernt: auf den Aktionsknöpfen den niedrigeren Rang dieses Zaubers ersetzen
    CreateCheckbox(controlPage, L("OPT_AUTO_RANK"), 360, -168,
        function() return ns.db.autoRankUp end,
        function(value) ns.db.autoRankUp = value end)
    local controlHint = controlPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    controlHint:SetPoint("TOPLEFT", 14, -200)
    controlHint:SetPoint("RIGHT", -14, 0)
    controlHint:SetJustifyH("LEFT")
    controlHint:SetText(L("OPT_CONTROL_HINT"))

    -- Reiter "Darstellung": Aussehen der Knöpfe und Leisten
    CreateCheckbox(displayPage, L("OPT_UNLOCK"), 14, -42,
        function() return ns.unlocked end,
        function(value) ns.SetUnlocked(value) end)
    CreateCheckbox(displayPage, L("OPT_GRID"), 14, -68,
        function() return ns.db.showGrid end,
        function(value) ns.db.showGrid = value; Changed() end)
    CreateCheckbox(displayPage, L("OPT_BORDER"), 14, -94,
        function() return ns.db.showBorder end,
        function(value) ns.db.showBorder = value; ns.UpdateAllButtons(); Changed() end) -- Abstände ändern sich mit
    CreateCheckbox(displayPage, L("OPT_SNAP"), 250, -42,
        function() return ns.db.snap end,
        function(value) ns.db.snap = value end)
    CreateCheckbox(displayPage, L("OPT_EQUIPPED"), 250, -68,
        function() return ns.db.showEquipped end,
        function(value) ns.db.showEquipped = value; ns.UpdateAllButtons() end)
    -- Zahlen bei Abklingzeiten: Blizzard-Einstellung (gilt für alle Abklingzeiten im Spiel)
    options.cooldownCheck = CreateCheckbox(displayPage, L("OPT_CD_NUMBERS"), 250, -94,
        function() return ns.GetCVarBool("countdownForCooldowns") end,
        function(value) ns.SetCVarBool("countdownForCooldowns", value) end)
    -- Alle Leisten außerhalb des Kampfes ausblenden (entsperrt bleiben sie sichtbar)
    CreateCheckbox(displayPage, L("OPT_HIDE_OOC"), 14, -120,
        function() return ns.db.hideOutOfCombat end,
        function(value) ns.db.hideOutOfCombat = value; Changed() end)
    -- Wie stark außerhalb des Kampfes abgeblendet wird (Maus darüber und im Kampf: voll sichtbar)
    CreateSlider(displayPage, L("OPT_OOC_ALPHA"), 360, -108, 160,
        function() return 0 end, function() return 100 end,
        function() return ns.db.oocAlpha or 30 end,
        function(value) ns.db.oocAlpha = value end)

    local skinChoices = {}
    for _, skin in ipairs(ns.SKINS) do table.insert(skinChoices, { value = skin.key, textKey = skin.textKey }) end
    CreateSelector(displayPage, L("OPT_SKIN"), 14, -154, 140, skinChoices,
        function() return ns.db.skin end,
        function(value) ns.db.skin = value; ns.UpdateAllButtons(); Changed() end) -- Randstärke ändert die Abstände
    CreateSelector(displayPage, L("OPT_PROC_GLOW"), 360, -154, 150, ns.GLOW_STYLES,
        function() return ns.db.procGlow end,
        function(value) ns.db.procGlow = value; ns.RefreshGlows() end)
    CreateSlider(displayPage, L("OPT_ZOOM"), 14, -182, 160,
        function() return 0 end, function() return 30 end,
        function() return ns.db.iconZoom end,
        function(value) ns.db.iconZoom = value; ns.UpdateAllButtons() end)
    -- Stärke des Hover-Leuchtens (0 = aus)
    CreateSlider(displayPage, L("OPT_HOVER_ALPHA"), 360, -182, 160,
        function() return 0 end, function() return 60 end,
        function() return ns.db.hoverAlpha or 15 end,
        function(value) ns.db.hoverAlpha = value; ns.UpdateAllButtons() end)

    -- Reiter "Schrift": Texte auf den Knöpfen
    CreateCheckbox(fontPage, L("OPT_HOTKEYS"), 14, -42,
        function() return ns.db.showHotkeys end,
        function(value) ns.db.showHotkeys = value; ns.UpdateAllButtons() end)
    CreateCheckbox(fontPage, L("OPT_MACRONAMES"), 250, -42,
        function() return ns.db.showMacroNames end,
        function(value) ns.db.showMacroNames = value; ns.UpdateAllButtons() end)
    CreateCheckbox(fontPage, L("OPT_COUNTS"), 490, -42,
        function() return ns.db.showCounts end,
        function(value) ns.db.showCounts = value; ns.UpdateAllButtons() end)
    CreateSelector(fontPage, L("OPT_FONT"), 14, -76, 140, FontChoices(),
        function() return ns.db.font end,
        function(value) ns.db.font = value; ns.UpdateAllButtons() end)
    CreateSelector(fontPage, L("OPT_OUTLINE"), 360, -76, 150, OUTLINE_CHOICES,
        function() return ns.db.fontOutline end,
        function(value) ns.db.fontOutline = value; ns.UpdateAllButtons() end)
    CreateSelector(fontPage, L("OPT_HOTKEY_POS"), 14, -106, 140, HOTKEY_POS_CHOICES,
        function() return ns.db.hotkeyPosition end,
        function(value) ns.db.hotkeyPosition = value; ns.UpdateAllButtons() end)
    CreateSlider(fontPage, L("OPT_FONT_SIZE"), 14, -138, 160,
        function() return 6 end, function() return 24 end,
        function() return ns.db.fontSize end,
        function(value) ns.db.fontSize = value; ns.UpdateAllButtons() end)

    -- Fußzeile
    ns.Style.CreateButton(options, L("BTN_KEYBIND"), 150, 26, function() ns.OpenKeybindMode() end, L("TIP_KEYBIND"))
        :SetPoint("BOTTOMLEFT", 12, 12)
    ns.Style.CreateButton(options, L("BTN_CLOSE"), 150, 26, function() options:Hide() end)
        :SetPoint("BOTTOMRIGHT", -12, 12)
    -- Alle Leisten entsperren bzw. wieder sperren (wie /fb move)
    options.unlockButton = ns.Style.CreateButton(options, L("BTN_UNLOCK"), 170, 26,
        function() ns.SetUnlocked(not ns.unlocked) end, L("TIP_UNLOCK"))
    options.unlockButton:SetPoint("BOTTOMLEFT", 170, 12)
    -- Testmodus: alle Leisten, Proc-Leuchten und Abklingzeiten zur Vorschau (wie /fb test)
    options.testButton = CreateSearchButton(options, L("BTN_TEST"), 170, 26,
        function() ns.SetTestMode(not ns.testMode) end, L("TIP_TEST"))
    options.testButton:SetPoint("BOTTOMLEFT", 348, 12)
    pageInfo[options] = { path = L("OPT_TITLE") }

    ---------------------------------------------------------------------------
    -- Suche in der Titelleiste: Einstellungen nach Namen finden und direkt hinspringen
    ---------------------------------------------------------------------------
    local search = ns.Style.CreateEditBox(options.header, 200, 22)
    search:SetPoint("RIGHT", options.header, "RIGHT", -40, 0)
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 7, 0)
    placeholder:SetText(L("SEARCH_PLACEHOLDER"))
    options.search = search

    -- Goldener Rahmen, der kurz um die gefundene Einstellung aufleuchtet
    local flash = CreateFrame("Frame", nil, options, "BackdropTemplate")
    flash:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    local accent = ns.Style.COLOR.accent
    flash:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    flash:SetFrameStrata("FULLSCREEN")
    flash:EnableMouse(false)
    flash:Hide()
    local function Flash(control)
        if not control or not control:IsVisible() then return end
        flash:ClearAllPoints()
        flash:SetPoint("TOPLEFT", control, "TOPLEFT", -4, 4)
        if control:GetObjectType() == "CheckButton" and control.label then
            flash:SetPoint("BOTTOMRIGHT", control.label, "BOTTOMRIGHT", 4, -4)
            flash:SetPoint("BOTTOM", control, "BOTTOM", 0, -4)
        else
            flash:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 4, -4)
        end
        flash:Show()
        flash.token = (flash.token or 0) + 1
        local token = flash.token
        C_Timer.After(1.5, function() if flash.token == token then flash:Hide() end end)
    end

    -- Wo liegt eine Einstellung? (Seite des Bedienelements, notfalls dessen Eltern)
    local function InfoFor(entry)
        if entry.barKey then return { view = "bar", path = L("SEC_BARS") } end
        if entry.view then return { view = entry.view, path = L("SEC_PROFILES") } end
        local frame = entry.page
        while frame and not pageInfo[frame] do frame = frame:GetParent() end
        return frame and pageInfo[frame] or {}
    end

    local function GoTo(entry)
        local info = InfoFor(entry)
        if entry.barKey then selectedKey = entry.barKey end
        if info.view then options.view = info.view end
        if info.page then options.page = info.page end
        if info.general then options.generalPage = info.general end
        ns.RefreshOptions()
        -- Einstellung gibt es nur bei bestimmten Leisten: die erste passende Leiste wählen
        if info.view == "bar" and info.page and not entry.control:IsVisible() then
            local previous = selectedKey
            local found = false
            for _, def in ipairs(ns.BAR_DEFS) do
                selectedKey = def.key
                options.page = info.page
                ns.RefreshOptions()
                if entry.control:IsVisible() then found = true break end
            end
            if not found then
                selectedKey = previous
                ns.RefreshOptions()
            end
        end
        Flash(entry.control)
    end

    -- Trefferliste unter dem Suchfeld
    local results = CreateFrame("Frame", nil, options, "BackdropTemplate")
    ns.Style.SetFlat(results, ns.Style.COLOR.background)
    results:SetFrameStrata("FULLSCREEN_DIALOG")
    results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -4)
    results:SetWidth(320)
    results:EnableMouse(true)
    results:Hide()
    local MAX_RESULTS = 12
    local resultRows = {}
    for i = 1, MAX_RESULTS do
        local row = CreateFrame("Button", nil, results)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 20)
        row:SetPoint("RIGHT", -1, 0)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetPoint("RIGHT", -10, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        -- Eintrag "nichts gefunden" (ohne entry) ist nicht anklickbar
        row:SetScript("OnClick", function(self)
            if not self.entry then return end
            results:Hide()
            search:ClearFocus()
            GoTo(self.entry)
        end)
        resultRows[i] = row
    end

    local function UpdateResults()
        local text = strtrim(search:GetText() or ""):lower()
        placeholder:SetShown(text == "" and not search:HasFocus())
        if text == "" then
            results:Hide()
            return
        end
        local count, seen = 0, {}
        for _, entry in ipairs(searchIndex) do
            local info = InfoFor(entry)
            local key = (info.path or "") .. entry.label
            if count < MAX_RESULTS and not seen[key] and entry.label:lower():find(text, 1, true) then
                seen[key] = true
                count = count + 1
                local row = resultRows[count]
                row.entry = entry
                local path = info.path and ("|cff8a8a8a" .. info.path .. " »|r ") or ""
                row.text:SetText(path .. entry.label)
                row:Show()
            end
        end
        for i = count + 1, MAX_RESULTS do resultRows[i]:Hide() end
        if count == 0 then
            resultRows[1].entry = nil
            resultRows[1].text:SetText("|cff8a8a8a" .. L("SEARCH_NONE") .. "|r")
            resultRows[1]:Show()
            count = 1
        end
        results:SetHeight(count * 20 + 8)
        results:Show()
    end
    search:SetScript("OnTextChanged", UpdateResults)
    search:HookScript("OnEditFocusGained", function() placeholder:Hide() end)
    search:HookScript("OnEditFocusLost", function() placeholder:SetShown(strtrim(search:GetText() or "") == "") end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        results:Hide()
    end)
    search:SetScript("OnEnterPressed", function(self)
        local first = resultRows[1]
        if results:IsShown() and first:IsShown() and first.entry then
            results:Hide()
            self:ClearFocus()
            GoTo(first.entry)
        end
    end)

    options:SetScript("OnShow", function() ns.RefreshOptions() end)
    options:HookScript("OnHide", function() results:Hide() end)
    options:Hide()
end

function ns.RefreshOptions()
    if not options or not options:IsShown() then return end
    options.warning:SetShown(ns.disabledByBartender == true)
    options.unlockButton:SetText(L(ns.unlocked and "BTN_LOCK" or "BTN_UNLOCK"))
    options.testButton:SetText(L(ns.testMode and "BTN_TEST_OFF" or "BTN_TEST"))
    local def = ns.GetBarDef(selectedKey)
    options.barTitle:SetText(L(def.textKey))
    -- Rechts entweder die Einstellungen der Leiste oder "Profile"
    local showProfiles = options.view == "profiles"
    options.barPanel:SetShown(not showProfiles)
    options.profilePanel:SetShown(showProfiles)
    local activeKey = showProfiles and "profiles" or selectedKey
    -- Gewählten Eintrag in der Liste hervorheben
    local accent = ns.Style.COLOR.accent
    for _, button in ipairs(barButtons) do
        if button.key == activeKey then
            button:GetFontString():SetTextColor(accent[1], accent[2], accent[3])
            button:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
        else
            button:GetFontString():SetTextColor(0.9, 0.9, 0.9)
            button:SetBackdropBorderColor(unpack(ns.Style.COLOR.border))
        end
    end
    -- Erfahrungsleiste von ForeverXP: nur der Hinweis, keine eigenen Einstellungen
    local external = ns.IsExternal and ns.IsExternal(selectedKey)
    options.externalXP:SetShown(external)
    options.enabledCheck:SetShown(not external)
    for _, button in ipairs(barButtons) do
        if button.key == "xp" then
            button:SetText(L("BAR_XP") .. (ns.IsExternal and ns.IsExternal("xp") and " |cff8a8a8a(ForeverXP)|r" or ""))
        end
    end
    -- Reiter: gewählte Seite zeigen und hervorheben
    for key, page in pairs(options.pages) do page:SetShown(not external and key == options.page) end
    for _, tab in ipairs(options.tabs) do tab:SetShown(not external) end
    for _, tab in ipairs(options.tabs) do
        if tab.key == options.page then
            tab:GetFontString():SetTextColor(accent[1], accent[2], accent[3])
            tab:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
        else
            tab:GetFontString():SetTextColor(0.9, 0.9, 0.9)
            tab:SetBackdropBorderColor(unpack(ns.Style.COLOR.border))
        end
    end
    -- Reiter im Feld "Allgemein"
    for key, page in pairs(options.generalPages) do page:SetShown(key == options.generalPage) end
    for _, tab in ipairs(options.generalTabs) do
        if tab.key == options.generalPage then
            tab:GetFontString():SetTextColor(accent[1], accent[2], accent[3])
            tab:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
        else
            tab:GetFontString():SetTextColor(0.9, 0.9, 0.9)
            tab:SetBackdropBorderColor(unpack(ns.Style.COLOR.border))
        end
    end
    -- Blizzard-Einstellungen, die es in diesem Spiel nicht gibt, ausblenden
    for _, control in ipairs(options.controlRows) do
        control:SetShown(not control.cvar or ns.HasCVar(control.cvar))
    end
    options.cooldownCheck:SetShown(ns.HasCVar("countdownForCooldowns"))
    -- Nur die Einstellungen zeigen, die zur gewählten Leiste passen
    local hasButtons = def.kind == "action" or def.kind == "pet" or def.kind == "stance" or def.kind == "bags"
        or def.kind == "prof" or def.kind == "food"
    options.frameTitleCheck:SetShown(SelectedConfig().frame == true)
    options.frameTitleBox:SetShown(SelectedConfig().frame == true and SelectedConfig().frameTitle == true)
    if options.activeProfileText then
        options.activeProfileText:SetText(L("PROFILE_ACTIVE", ns.ProfileLabel(ns.GetActiveProfile())))
    end
    -- Taschen und Haltungen: Anzahl ergibt sich von selbst
    options.buttonsSlider:SetShown(hasButtons and def.kind ~= "bags" and def.kind ~= "stance")
    options.spacingSlider:SetShown(hasButtons or def.key == "micro")
    options.growXSelector:SetShown(hasButtons)
    options.growYSelector:SetShown(hasButtons)
    options.flyoutSelector:SetShown(def.kind == "action")
    options.backpackCheck:SetShown(def.kind == "bags")
    options.collapseArrowCheck:SetShown(def.kind == "prof" or def.kind == "food")
    options.arrowSideSelector:SetShown((def.kind == "prof" or def.kind == "food") and SelectedConfig().collapseArrow == true)
    options.perRowSlider:SetShown(hasButtons)
    options.keyringCheck:SetShown(def.kind == "bags" and ns.HasKeyring())
    options.foodResetButton:SetShown(def.kind == "food" or def.kind == "prof")
    options.microOwnCheck:SetShown(def.key == "micro")
    options.microGreyCheck:SetShown(def.key == "micro" and not SelectedConfig().microOwn)
    -- Spalten im Reiter "Anordnung" lückenlos von oben nach unten anordnen
    for _, column in ipairs(options.layoutColumns or {}) do
        local y = -74
        for _, row in ipairs(column.rows) do
            if row.spacer then
                y = y - row.spacer
            elseif row[1] and row[1]:IsShown() then
                row[1]:ClearAllPoints()
                row[1]:SetPoint("TOPLEFT", options.layoutPage, "TOPLEFT", column.x + (row[3] or 0), y)
                y = y - row[2]
            end
        end
    end
    for _, control in ipairs(controls) do
        control.Refresh()
    end
end

function ns.HideOptions()
    if options then options:Hide() end
end

-- Menü öffnen und direkt die Einstellungen einer bestimmten Leiste zeigen (Rechtsklick auf eine entsperrte Leiste)
function ns.ShowBarOptions(key)
    if not ns.db or not ns.GetBarDef(key) then return end
    if not options then CreateOptions() end
    selectedKey = key
    options.view = "bar"
    if options:IsShown() then
        ns.RefreshOptions()
    else
        options:Show()
    end
end

function ns.ToggleOptions()
    if not ns.db then return end
    if not options then CreateOptions() end
    options:SetShown(not options:IsShown())
end
