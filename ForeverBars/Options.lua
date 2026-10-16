local addonName, ns = ...
local L = ns.L

-- Menü im Stil von ForeverQuests: links die Liste der Leisten, rechts die Einstellungen der gewählten Leiste,
-- unten allgemeine Einstellungen. Alle Änderungen wirken sofort (im Kampf erst danach).

local options
local controls = {}       -- alle Bedienelemente mit :Refresh()
local barButtons = {}     -- Einträge der Leistenliste
local selectedKey = "bar1"

local WINDOW_WIDTH, WINDOW_HEIGHT = 720, 800
local PANEL_HEIGHT = 436   -- Platz für alle Einträge der Leistenliste
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

local function CreateCheckbox(parent, label, x, y, getValue, setValue)
    local checkbox = ns.Style.CreateCheckbox(parent, label)
    checkbox:SetPoint("TOPLEFT", x, y)
    checkbox:SetScript("OnClick", function(self)
        setValue(self:GetChecked() and true or false)
    end)
    checkbox.Refresh = function() checkbox:SetChecked(getValue()) end
    table.insert(controls, checkbox)
    return checkbox
end

local function CreateSlider(parent, label, x, y, width, getMin, getMax, getValue, setValue)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", x, y)
    holder:SetSize(width + 70, 40)

    local title = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(0.75, 0.75, 0.75)

    local slider = ns.Style.CreateSlider(holder, width)
    slider:SetPoint("TOPLEFT", 0, -18)

    local box = ns.Style.CreateEditBox(holder, 50, 20)
    box:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    box:SetJustifyH("CENTER")
    box:SetNumeric(true)

    slider:SetScript("OnValueChanged", function(_, value, userInput)
        value = math.floor(value + 0.5)
        box:SetText(value)
        if userInput then setValue(value) end
    end)
    box:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then setValue(math.min(getMax(), math.max(getMin(), math.floor(value)))) end
        self:ClearFocus()
        ns.RefreshOptions()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns.RefreshOptions()
    end)

    holder.Refresh = function()
        slider:SetMinMaxValues(getMin(), getMax())
        slider:SetValue(getValue())
        box:SetText(math.floor(getValue() + 0.5))
    end
    table.insert(controls, holder)
    return holder
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
        for _, choice in ipairs(choices) do
            if choice.value == getValue() then button:SetText(ChoiceText(choice)) end
        end
    end
    table.insert(controls, holder)
    return holder
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
    for i, def in ipairs(ns.BAR_DEFS) do
        local button = ns.Style.CreateButton(list, L(def.textKey), LIST_WIDTH - 24, 22, function()
            selectedKey = def.key
            ns.RefreshOptions()
        end)
        button:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 24)
        button:GetFontString():ClearAllPoints()
        button:GetFontString():SetPoint("LEFT", 8, 0)
        button.key = def.key
        button:HookScript("OnLeave", function() ns.RefreshOptions() end)
        table.insert(barButtons, button)
    end

    -- Rechts: Einstellungen der gewählten Leiste
    local bar = ns.Style.CreatePanel(options, L("SEC_BAR"))
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
    bar:SetPoint("RIGHT", -12, 0)
    bar:SetHeight(PANEL_HEIGHT)
    options.barTitle = bar.title

    CreateCheckbox(bar, L("OPT_ENABLED"), 14, -44,
        function() return SelectedConfig().enabled end,
        function(value) SelectedConfig().enabled = value; Changed() end)

    -- Zwei Reiter: "Anordnung" und "Sichtbarkeit" (je eine Seite im Feld)
    local layoutPage = CreateFrame("Frame", nil, bar)
    layoutPage:SetAllPoints()
    local visPage = CreateFrame("Frame", nil, bar)
    visPage:SetAllPoints()
    options.pages = { layout = layoutPage, visibility = visPage }
    options.tabs = {}
    local pagingPage = CreateFrame("Frame", nil, bar)
    pagingPage:SetAllPoints()
    options.pages.paging = pagingPage
    local tabX = -14
    for _, tab in ipairs({ { key = "paging", textKey = "TAB_PAGING" }, { key = "visibility", textKey = "TAB_VISIBILITY" },
                           { key = "layout", textKey = "TAB_LAYOUT" } }) do
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

    -- Reiter "Seiten" (nur Aktionsleisten): andere Belegung mit Zusatztaste, je Gestalt oder eigene Bedingung
    local pageChoices = { { value = 0, textKey = "PAGE_OFF" } }
    for page = 1, 10 do table.insert(pageChoices, { value = page, text = L("PAGE_N", page) }) end
    local modifierLabels = { pageCtrl = "PAGE_CTRL", pageAlt = "PAGE_ALT", pageShift = "PAGE_SHIFT" }
    for i, key in ipairs({ "pageCtrl", "pageAlt", "pageShift" }) do
        CreateSmallSelector(pagingPage, L(modifierLabels[key]), 14, -74 - (i - 1) * 48, 200, pageChoices,
            function() return tonumber(SelectedConfig()[key]) or 0 end,
            function(value) SelectedConfig()[key] = value; Changed() end)
    end

    -- Je Gestalt/Haltung eine Auswahl (Namen kommen vom Spiel); Leiste 1 kann "wie Blizzard" wechseln
    local MAX_STANCES = 6
    local stanceTitle = pagingPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stanceTitle:SetPoint("TOPLEFT", 290, -74)
    stanceTitle:SetTextColor(0.75, 0.75, 0.75)
    stanceTitle:SetText(L("PAGE_STANCES"))
    options.noStances = pagingPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    options.noStances:SetPoint("TOPLEFT", 290, -94)
    options.noStances:SetWidth(170)
    options.noStances:SetJustifyH("LEFT")
    options.noStances:SetText(L("PAGE_NO_STANCES"))
    local stanceChoices = { { value = "BLIZZARD", textKey = "PAGE_BLIZZARD" } }
    for _, choice in ipairs(pageChoices) do table.insert(stanceChoices, choice) end
    stanceChoices[2] = { value = 0, textKey = "PAGE_OWN" }
    options.stanceSelectors = {}
    for i = 1, MAX_STANCES do
        local selector = CreateSmallSelector(pagingPage, L("STANCE_N", i), 290, -94 - (i - 1) * 46, 170, stanceChoices,
            function()
                local value = SelectedConfig().stancePages and SelectedConfig().stancePages[i]
                if value == nil then value = selectedKey == "bar1" and "BLIZZARD" or 0 end
                return value
            end,
            function(value)
                SelectedConfig().stancePages = SelectedConfig().stancePages or {}
                SelectedConfig().stancePages[i] = value
                Changed()
            end)
        options.stanceSelectors[i] = selector
    end

    -- Eigene Bedingung für den Seitenwechsel (ersetzt die Einstellungen oben)
    CreateCheckbox(pagingPage, L("OPT_PAGING_CUSTOM"), 14, -232,
        function() return SelectedConfig().usePagingCustom end,
        function(value) SelectedConfig().usePagingCustom = value; Changed() end)
    local pagingBox = ns.Style.CreateEditBox(pagingPage, 260, 22)
    pagingBox:SetPoint("TOPLEFT", 14, -258)
    local function SavePaging(self)
        SelectedConfig().pagingCustom = strtrim(self:GetText() or "")
        Changed()
    end
    pagingBox:SetScript("OnEnterPressed", function(self) SavePaging(self); self:ClearFocus() end)
    pagingBox:HookScript("OnEditFocusLost", SavePaging)
    pagingBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    pagingBox.Refresh = function()
        if not pagingBox:HasFocus() then pagingBox:SetText(SelectedConfig().pagingCustom or "") end
    end
    table.insert(controls, pagingBox)
    local pagingHint = pagingPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pagingHint:SetPoint("TOPLEFT", 14, -286)
    pagingHint:SetWidth(260)
    pagingHint:SetJustifyH("LEFT")
    options.pagingHint = pagingHint

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
        function() return SelectedConfig().spacing or 4 end,
        function(value) SelectedConfig().spacing = value; Changed() end)
    CreateSlider(layoutPage, L("OPT_SCALE"), 14, -206, 180,
        function() return 50 end, function() return 200 end,
        function() return SelectedConfig().scale or 100 end,
        function(value) SelectedConfig().scale = value; Changed() end)
    CreateSlider(layoutPage, L("OPT_ALPHA"), 14, -250, 180,
        function() return 0 end, function() return 100 end,
        function() return SelectedConfig().alpha or 100 end,
        function(value) SelectedConfig().alpha = value; Changed() end)
    -- Position (Mitte der Leiste, von unten links); geht auch per Ziehen im entsperrten Zustand
    CreateSlider(layoutPage, L("OPT_POS_X"), 14, -294, 180,
        function() return 0 end, function() return math.floor(UIParent:GetWidth()) end,
        function() return (ns.GetBarPosition(selectedKey)) end,
        function(value) SelectedConfig().x = value; Changed() end)
    CreateSlider(layoutPage, L("OPT_POS_Y"), 14, -338, 180,
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
    -- Nur Taschenleiste
    options.backpackCheck = CreateCheckbox(layoutPage, L("OPT_ONLY_BACKPACK"), RIGHT_X, -240,
        function() return SelectedConfig().onlyBackpack end,
        function(value) SelectedConfig().onlyBackpack = value; Changed() end)
    options.keyringCheck = CreateCheckbox(layoutPage, L("OPT_KEYRING"), RIGHT_X, -264,
        function() return SelectedConfig().keyring end,
        function(value) SelectedConfig().keyring = value; Changed() end)

    -- Zentrieren: Leiste waagerecht bzw. senkrecht in die Bildschirmmitte setzen
    ns.Style.CreateButton(layoutPage, L("BTN_CENTER_X"), 170, 22, function()
        SelectedConfig().x = math.floor(UIParent:GetWidth() / 2 + 0.5)
        Changed()
        ns.RefreshOptions()
    end):SetPoint("TOPLEFT", RIGHT_X, -300)
    ns.Style.CreateButton(layoutPage, L("BTN_CENTER_Y"), 170, 22, function()
        SelectedConfig().y = math.floor(UIParent:GetHeight() / 2 + 0.5)
        Changed()
        ns.RefreshOptions()
    end):SetPoint("TOPLEFT", RIGHT_X, -326)

    local resetButton = ns.Style.CreateButton(layoutPage, L("BTN_RESET_BAR"), 170, 22, function()
        ns.ResetBar(selectedKey)
        ns.Print(L("RESET_DONE"))
        ns.RefreshOptions()
    end)
    resetButton:SetPoint("TOPLEFT", RIGHT_X, -366)

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

    -- Zwei Reiter: "Darstellung" (Aussehen der Knöpfe) und "Bedienung" (Blizzard-Einstellungen fürs Zaubern)
    local displayPage = CreateFrame("Frame", nil, general)
    displayPage:SetAllPoints()
    local controlPage = CreateFrame("Frame", nil, general)
    controlPage:SetAllPoints()
    local managePage = CreateFrame("Frame", nil, general)
    managePage:SetAllPoints()
    options.generalPages = { display = displayPage, control = controlPage, manage = managePage }
    options.generalTabs = {}
    options.generalPage = "display"
    local generalTabX = -14
    for _, tab in ipairs({ { key = "manage", textKey = "TAB_MANAGE" }, { key = "control", textKey = "TAB_CONTROL" },
                           { key = "display", textKey = "TAB_DISPLAY" } }) do
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

    -- Reiter "Verwaltung": Minimap-Symbol, Vorlagen, Export/Import
    CreateCheckbox(managePage, L("OPT_MINIMAP"), 14, -42,
        function() return ns.db.showMinimapButton end,
        function(value) ns.db.showMinimapButton = value; ns.UpdateMinimapButton() end)

    local presetChoices = {}
    for _, preset in ipairs(ns.PRESETS) do table.insert(presetChoices, { value = preset.key, textKey = preset.textKey }) end
    options.selectedPreset = ns.PRESETS[1].key
    CreateSelector(managePage, L("OPT_PRESET"), 14, -76, 200, presetChoices,
        function() return options.selectedPreset end,
        function(value) options.selectedPreset = value end)
    -- Vorlage anwenden: zweimal klicken (setzt alle Leisten zurück)
    local presetButton
    presetButton = ns.Style.CreateButton(managePage, L("BTN_PRESET_APPLY"), 170, 22, function()
        if presetButton.confirm then
            presetButton.confirm = nil
            presetButton:SetText(L("BTN_PRESET_APPLY"))
            ns.ApplyPreset(options.selectedPreset)
        else
            presetButton.confirm = true
            presetButton:SetText(L("BTN_PRESET_CONFIRM"))
            C_Timer.After(5, function()
                if presetButton.confirm then
                    presetButton.confirm = nil
                    presetButton:SetText(L("BTN_PRESET_APPLY"))
                end
            end)
        end
    end, L("TIP_PRESET"))
    presetButton:SetPoint("TOPLEFT", 380, -74)

    ns.Style.CreateButton(managePage, L("BTN_EXPORT"), 200, 24, function() ns.ShowTransferWindow("export") end,
        L("TIP_EXPORT")):SetPoint("TOPLEFT", 14, -116)
    ns.Style.CreateButton(managePage, L("BTN_IMPORT"), 200, 24, function() ns.ShowTransferWindow("import") end,
        L("TIP_IMPORT")):SetPoint("TOPLEFT", 224, -116)
    local manageHint = managePage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    manageHint:SetPoint("TOPLEFT", 14, -152)
    manageHint:SetPoint("RIGHT", -14, 0)
    manageHint:SetJustifyH("LEFT")
    manageHint:SetText(L("OPT_MANAGE_HINT"))

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
    local controlHint = controlPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    controlHint:SetPoint("TOPLEFT", 14, -200)
    controlHint:SetPoint("RIGHT", -14, 0)
    controlHint:SetJustifyH("LEFT")
    controlHint:SetText(L("OPT_CONTROL_HINT"))

    CreateCheckbox(displayPage, L("OPT_UNLOCK"), 14, -42,
        function() return ns.unlocked end,
        function(value) ns.SetUnlocked(value) end)
    CreateCheckbox(displayPage, L("OPT_GRID"), 14, -68,
        function() return ns.db.showGrid end,
        function(value) ns.db.showGrid = value; Changed() end)
    CreateCheckbox(displayPage, L("OPT_BORDER"), 14, -94,
        function() return ns.db.showBorder end,
        function(value) ns.db.showBorder = value; ns.UpdateAllButtons() end)
    CreateCheckbox(displayPage, L("OPT_HOTKEYS"), 250, -42,
        function() return ns.db.showHotkeys end,
        function(value) ns.db.showHotkeys = value; ns.UpdateAllButtons() end)
    CreateCheckbox(displayPage, L("OPT_MACRONAMES"), 250, -68,
        function() return ns.db.showMacroNames end,
        function(value) ns.db.showMacroNames = value; ns.UpdateAllButtons() end)
    CreateCheckbox(displayPage, L("OPT_EQUIPPED"), 250, -94,
        function() return ns.db.showEquipped end,
        function(value) ns.db.showEquipped = value; ns.UpdateAllButtons() end)
    CreateCheckbox(displayPage, L("OPT_COUNTS"), 490, -42,
        function() return ns.db.showCounts end,
        function(value) ns.db.showCounts = value; ns.UpdateAllButtons() end)
    CreateCheckbox(displayPage, L("OPT_SNAP"), 490, -68,
        function() return ns.db.snap end,
        function(value) ns.db.snap = value end)

    -- Schrift der Knopftexte, Position der Tastenbelegung, Zuschnitt der Symbole
    CreateSelector(displayPage, L("OPT_FONT"), 14, -128, 140, FontChoices(),
        function() return ns.db.font end,
        function(value) ns.db.font = value; ns.UpdateAllButtons() end)
    CreateSelector(displayPage, L("OPT_OUTLINE"), 360, -128, 150, OUTLINE_CHOICES,
        function() return ns.db.fontOutline end,
        function(value) ns.db.fontOutline = value; ns.UpdateAllButtons() end)
    CreateSelector(displayPage, L("OPT_HOTKEY_POS"), 14, -158, 140, HOTKEY_POS_CHOICES,
        function() return ns.db.hotkeyPosition end,
        function(value) ns.db.hotkeyPosition = value; ns.UpdateAllButtons() end)
    CreateSlider(displayPage, L("OPT_FONT_SIZE"), 14, -186, 160,
        function() return 6 end, function() return 24 end,
        function() return ns.db.fontSize end,
        function(value) ns.db.fontSize = value; ns.UpdateAllButtons() end)
    CreateSlider(displayPage, L("OPT_ZOOM"), 360, -160, 160,
        function() return 0 end, function() return 30 end,
        function() return ns.db.iconZoom end,
        function(value) ns.db.iconZoom = value; ns.UpdateAllButtons() end)

    -- Fußzeile
    ns.Style.CreateButton(options, L("BTN_KEYBIND"), 150, 26, function() ns.OpenKeybindMode() end, L("TIP_KEYBIND"))
        :SetPoint("BOTTOMLEFT", 12, 12)
    ns.Style.CreateButton(options, L("BTN_CLOSE"), 150, 26, function() options:Hide() end)
        :SetPoint("BOTTOMRIGHT", -12, 12)
    -- Alle Leisten entsperren bzw. wieder sperren (wie /fb move)
    options.unlockButton = ns.Style.CreateButton(options, L("BTN_UNLOCK"), 170, 26,
        function() ns.SetUnlocked(not ns.unlocked) end, L("TIP_UNLOCK"))
    options.unlockButton:SetPoint("BOTTOM", 0, 12)

    options:SetScript("OnShow", function() ns.RefreshOptions() end)
    options:Hide()
end

function ns.RefreshOptions()
    if not options or not options:IsShown() then return end
    options.warning:SetShown(ns.disabledByBartender == true)
    options.unlockButton:SetText(L(ns.unlocked and "BTN_LOCK" or "BTN_UNLOCK"))
    local def = ns.GetBarDef(selectedKey)
    options.barTitle:SetText(L(def.textKey))
    -- Gewählte Leiste in der Liste hervorheben
    local accent = ns.Style.COLOR.accent
    for _, button in ipairs(barButtons) do
        if button.key == selectedKey then
            button:GetFontString():SetTextColor(accent[1], accent[2], accent[3])
            button:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
        else
            button:GetFontString():SetTextColor(0.9, 0.9, 0.9)
            button:SetBackdropBorderColor(unpack(ns.Style.COLOR.border))
        end
    end
    -- Reiter: gewählte Seite zeigen und hervorheben ("Seiten" gibt es nur bei Aktionsleisten)
    local isAction = def.kind == "action"
    if options.page == "paging" and not isAction then options.page = "layout" end
    for key, page in pairs(options.pages) do page:SetShown(key == options.page) end
    for _, tab in ipairs(options.tabs) do
        tab:SetShown(tab.key ~= "paging" or isAction)
    end
    -- Gestalten des Charakters mit Namen anzeigen
    local stances = ns.GetStanceNames()
    for i, selector in ipairs(options.stanceSelectors) do
        selector:SetShown(stances[i] ~= nil)
        if stances[i] then selector.label:SetText(stances[i]) end
    end
    options.noStances:SetShown(#stances == 0)
    options.pagingHint:SetText(L("OPT_PAGING_HINT", ns.HOME_PAGES[selectedKey] or 1))
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
    -- Nur die Einstellungen zeigen, die zur gewählten Leiste passen
    local hasButtons = def.kind == "action" or def.kind == "pet" or def.kind == "stance" or def.kind == "bags"
    options.buttonsSlider:SetShown(hasButtons and def.kind ~= "bags")
    options.perRowSlider:SetShown(hasButtons)
    options.spacingSlider:SetShown(hasButtons)
    options.growXSelector:SetShown(hasButtons)
    options.growYSelector:SetShown(hasButtons)
    options.flyoutSelector:SetShown(def.kind == "action")
    options.backpackCheck:SetShown(def.kind == "bags")
    options.keyringCheck:SetShown(def.kind == "bags" and ns.HasKeyring())
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
