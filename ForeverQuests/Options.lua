local addonName, ns = ...
local L = ns.L

local options
local controls = {}

local PANEL_WIDTH = 322
local PANEL_HEIGHT = 394
local DROPDOWN_X = 150

---------------------------------------------------------------------------
-- Bausteine: Häkchen, Schieberegler, Auswahl (Aussehen aus Style.lua)
---------------------------------------------------------------------------

local function CreateCheckbox(parent, label, x, y, getValue, setValue)
    local checkbox = ns.Style.CreateCheckbox(parent, label)
    checkbox:SetPoint("TOPLEFT", x, y)
    checkbox:SetScript("OnClick", function(self)
        setValue(self:GetChecked() and true or false)
    end)
    checkbox.Refresh = function()
        checkbox:SetChecked(getValue())
    end
    table.insert(controls, checkbox)
end

local function CreateSlider(parent, label, x, y, width, getMin, getMax, getValue, setValue)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    title:SetTextColor(0.75, 0.75, 0.75)

    local slider = ns.Style.CreateSlider(parent, width)
    slider:SetPoint("TOPLEFT", x, y - 18)

    -- Eingabefeld für genaue Werte
    local box = ns.Style.CreateEditBox(parent, 50, 20)
    box:SetPoint("LEFT", slider, "RIGHT", 12, 0)
    box:SetJustifyH("CENTER")
    box:SetNumeric(true)

    slider:SetScript("OnValueChanged", function(self, value, userInput)
        value = math.floor(value + 0.5)
        box:SetText(value)
        if userInput then
            setValue(value)
        end
    end)

    box:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())
        if value then
            value = math.min(getMax(), math.max(getMin(), math.floor(value)))
            setValue(value)
        end
        self:ClearFocus()
        ns.RefreshOptions()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        ns.RefreshOptions()
    end)

    slider.Refresh = function()
        slider:SetMinMaxValues(getMin(), getMax())
        local value = getValue() or getMin() -- fehlender Wert: kein Fehler, Regler steht am Anfang
        slider:SetValue(value)
        box:SetText(math.floor(value + 0.5))
    end
    table.insert(controls, slider)
end

-- Auswahlknopf, der beim Anklicken eine Liste öffnet.
-- choices = { { value = ..., text = ... }, ... }; onChange (optional) wird nach der Auswahl aufgerufen
local function CreateSelector(parent, label, x, y, width, choices, key, onChange)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", x, y)
    text:SetText(label)

    local button = ns.Style.CreateDropdown(parent, width)
    button:SetPoint("LEFT", text, "LEFT", DROPDOWN_X - 14, 0)

    local function Choose(value)
        ns.db[key] = value
        if onChange then
            onChange()
        else
            ns.RequestUpdate()
        end
        ns.RefreshOptions()
    end

    -- Liste im eigenen flachen Stil (siehe Style.ShowMenu), linksbündig unter dem Knopf
    button:SetScript("OnClick", function(self)
        local items = {}
        for _, choice in ipairs(choices) do
            table.insert(items, {
                radio = true,
                text = choice.text,
                checked = function() return ns.db[key] == choice.value end,
                onClick = function() Choose(choice.value) end,
            })
        end
        ns.Style.ShowMenu(self, items, { align = "LEFT" })
    end)

    button.Refresh = function()
        for _, choice in ipairs(choices) do
            if choice.value == ns.db[key] then
                button:SetText(choice.text)
            end
        end
    end
    table.insert(controls, button)
end

-- Auswahllisten (Texte jeweils in der aktuellen Sprache)

local function FontChoices()
    local choices = {}
    for _, font in ipairs(ns.FONTS) do
        table.insert(choices, { value = font.key, text = font.textKey and L(font.textKey) or font.text })
    end
    return choices
end

local function RewardChoices()
    return {
        { value = 0, text = L("REWARD_OFF") },
        { value = 2, text = L("REWARD_GREEN") },
        { value = 3, text = L("REWARD_BLUE") },
        { value = 4, text = L("REWARD_EPIC") },
    }
end

local function LanguageChoices()
    local choices = {}
    for _, language in ipairs(ns.LANGUAGES) do
        table.insert(choices, { value = language.value, text = language.textKey and L(language.textKey) or language.text })
    end
    return choices
end

-- Häkchen, das direkt einen gespeicherten Wert umschaltet
local function CreateSettingCheckbox(parent, label, x, y, key, onChange)
    CreateCheckbox(parent, label, x, y,
        function() return ns.db[key] end,
        function(value)
            ns.db[key] = value
            if onChange then onChange() end
            ns.RequestUpdate()
        end)
end

-- Schieberegler, der direkt einen gespeicherten Wert ändert
local function CreateLayoutSlider(parent, label, x, y, key, getMin, getMax)
    CreateSlider(parent, label, x, y, 230, getMin, getMax,
        function() return ns.db[key] end,
        function(value)
            ns.db[key] = value
            ns.ApplyLayout()
        end)
end

---------------------------------------------------------------------------
-- Menüfenster
---------------------------------------------------------------------------

local function CreateOptions()
    -- Seite im zentralen Einstellungsfenster von Forever Core (verhält sich wie das bisherige eigene Fenster)
    local HUB = _G.ForeverHub.UI
    options = HUB.SettingsPanel("ForeverQuestsOptions", L("OPT_TITLE"), 680, 644,
        { key = "ForeverQuests", group = HUB.SETTINGS_GROUPS.nav, label = HUB.T("Quest- und Dungeontracker", "Quest & dungeon tracker"), kind = "menu" })
    options.subText:SetText(L("ADDON_NAME"))
    -- Beim Schließen des Menüs wird der Tracker wieder gesperrt
    options:SetScript("OnHide", function()
        ns.SetUnlocked(false)
        ns.Style.HideMenu() -- offene Auswahlliste mitschließen
    end)

    -- Linkes Feld: Anzeige
    local display = ns.Style.CreatePanel(options, L("SEC_DISPLAY"))
    display:SetPoint("TOPLEFT", 12, -52)
    display:SetSize(PANEL_WIDTH, PANEL_HEIGHT)

    local rowY = -44
    local function NextRow()
        local y = rowY
        rowY = rowY - 24
        return y
    end
    CreateCheckbox(display, L("OPT_UNLOCK"), 14, NextRow(),
        function() return ns.unlocked end,
        function(value) ns.SetUnlocked(value) end)
    CreateSettingCheckbox(display, L("OPT_HIDE_BLIZZARD"), 14, NextRow(), "hideBlizzard", ns.UpdateBlizzardTracker)
    CreateSettingCheckbox(display, L("OPT_HIDE_COMBAT"), 14, NextRow(), "hideInCombat", ns.UpdateVisibility)
    CreateSettingCheckbox(display, L("OPT_ONLY_TRACKED"), 14, NextRow(), "onlyTracked")
    CreateSettingCheckbox(display, L("OPT_COLLAPSE"), 14, NextRow(), "hideObjectives", ns.ResetExpanded)
    CreateSettingCheckbox(display, L("OPT_ZONES"), 14, NextRow(), "showZones")
    CreateSettingCheckbox(display, L("OPT_QUEST_TYPE"), 14, NextRow(), "showQuestType")
    CreateSettingCheckbox(display, L("OPT_MINIMAP"), 14, NextRow(), "showMinimapButton", ns.UpdateMinimapButton)
    CreateSettingCheckbox(display, L("OPT_INSTANCE"), 14, NextRow(), "instanceFilter")

    -- Sprache: sofort wirksam, Fenster werden mit den neuen Texten neu aufgebaut
    CreateSelector(display, L("OPT_LANGUAGE"), 14, -270, 158, LanguageChoices(), "language", ns.OnLanguageChanged)

    CreateSelector(display, L("OPT_REWARDS"), 14, -300, 158, RewardChoices(), "rewardHighlight")
    -- Stufenbereich hinter dem Gebietsnamen auf der Weltkarte (ZoneLevels.lua)
    CreateSettingCheckbox(display, L("OPT_ZONE_LEVELS"), 14, -342, "zoneLevels")
    local rewardHint = display:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rewardHint:SetPoint("TOPLEFT", 14, -322)
    rewardHint:SetWidth(PANEL_WIDTH - 28)
    rewardHint:SetJustifyH("LEFT")
    rewardHint:SetText(L("OPT_REWARDS_HINT"))

    -- Rechtes Feld: Schrift und Aussehen (die Farben der Überschriften sind fest)
    local looks = ns.Style.CreatePanel(options, L("SEC_LOOKS"))
    looks:SetPoint("TOPLEFT", display, "TOPRIGHT", 12, 0)
    looks:SetSize(PANEL_WIDTH, PANEL_HEIGHT)

    CreateSelector(looks, L("OPT_FONT"), 14, -44, 158, FontChoices(), "font")
    CreateSettingCheckbox(looks, L("OPT_OUTLINE"), 14, -72, "fontOutline")
    CreateSlider(looks, L("OPT_FONT_SIZE"), 14, -100, 230,
        function() return 8 end, function() return 20 end,
        function() return ns.db.fontSize end,
        function(value)
            ns.db.fontSize = value
            ns.RequestUpdate()
        end)
    CreateSlider(looks, L("OPT_TRANSPARENCY"), 14, -146, 230,
        function() return 0 end, function() return 100 end,
        function() return ns.db.backgroundTransparency end,
        function(value)
            ns.db.backgroundTransparency = value
            ns.RequestUpdate()
        end)
    -- Nach wie vielen Minuten ohne Fortschritt eine automatisch aufgeklappte Quest wieder einklappt
    CreateSlider(looks, L("OPT_AUTO_COLLAPSE"), 14, -192, 230,
        function() return 1 end, function() return 60 end,
        function() return ns.db.autoCollapseMinutes end,
        function(value)
            ns.db.autoCollapseMinutes = value
        end)
    -- Tooltip mit Beschreibung, Zielen und Belohnungen beim Darüberfahren im Tracker
    CreateSettingCheckbox(looks, L("OPT_QUEST_TOOLTIP"), 14, -246, "showQuestTooltip")
    -- Hinweisfenster beim Betreten eines Dungeons (Quests dabei / fehlen noch)
    CreateSettingCheckbox(looks, L("OPT_INSTANCE_HINT"), 14, -270, "instanceHint")
    -- Questlog an der Weltkarte im Forever-Stil (Blizzards Rahmen kommt erst nach /reload zurück)
    CreateSettingCheckbox(looks, L("OPT_QUESTLOG"), 14, -294, "questLogSkin")
    -- Dungeonfenster: Klick auf "Kartenpunkt" öffnet auch gleich die Weltkarte an dieser Stelle
    CreateSettingCheckbox(looks, L("OPT_WAYPOINT_MAP"), 14, -318, "waypointOpensMap")
    -- Quest-IDs (Tracker, Questlog, Dungeonfenster); danach alles neu zeichnen
    -- Questgegenstände: zugehörige Quest und Zustand im Tooltip (Questie.lua)
    CreateSettingCheckbox(looks, L("OPT_ITEM_QUESTS"), 14, -366, "itemQuestTooltip")
    CreateSettingCheckbox(looks, L("OPT_QUEST_IDS"), 14, -342, "showQuestIDs", function()
        if ns.RequestUpdate then ns.RequestUpdate() end
        if ns.RequestDungeonRefresh then ns.RequestDungeonRefresh() end
    end)

    -- Unten: Position und Größe
    local function screenWidth() return math.floor(UIParent:GetWidth()) end
    local function screenHeight() return math.floor(UIParent:GetHeight()) end

    local layout = ns.Style.CreatePanel(options, L("SEC_LAYOUT"))
    layout:SetPoint("TOPLEFT", display, "BOTTOMLEFT", 0, -12)
    layout:SetSize(PANEL_WIDTH * 2 + 12, 128)
    CreateLayoutSlider(layout, L("OPT_WIDTH"), 14, -44, "width", function() return 200 end, function() return 800 end)
    CreateLayoutSlider(layout, L("OPT_HEIGHT"), 14, -86, "height", function() return 100 end, function() return 1200 end)
    CreateLayoutSlider(layout, L("OPT_POS_X"), PANEL_WIDTH + 26, -44, "x", function() return 0 end, screenWidth)
    CreateLayoutSlider(layout, L("OPT_POS_Y"), PANEL_WIDTH + 26, -86, "y", function() return 0 end, screenHeight)

    -- Fußleiste
    ns.Style.CreateButton(options, L("BTN_RESET"), 150, 26, function()
        ns.ResetSettings()
        print(ns.ChatPrefix() .. ": " .. L("RESET_DONE"))
    end, L("TIP_RESET"))
        :SetPoint("BOTTOMLEFT", 12, 12)

    ns.Style.CreateButton(options, L("BTN_CLOSE"), 150, 26, function() options:Hide() end)
        :SetPoint("BOTTOMRIGHT", -12, 12)

    options:SetScript("OnShow", function()
        -- Menü und Dungeon-Fenster nie gleichzeitig offen
        if ns.HideDungeons then ns.HideDungeons() end
        ns.RefreshOptions()
    end)
    -- Neue Fenster sind sofort sichtbar; erst verstecken, damit ToggleOptions es beim ersten Mal öffnet
    options:Hide()
end

-- Alle Regler, Häkchen und Auswahlknöpfe auf die aktuellen Werte setzen
function ns.RefreshOptions()
    if not options or not options:IsShown() then return end
    for _, control in ipairs(controls) do
        control.Refresh()
    end
end

function ns.HideOptions()
    if options then options:Hide() end
end

function ns.ToggleOptions()
    if not options then CreateOptions() end
    if options:IsShown() then
        options:Hide()
    else
        options:Show()
        ns.RefreshOptions()
    end
end

-- Sprache gewechselt: Tracker neu beschriften, Menü und Dungeon-Fenster mit neuen Texten neu aufbauen
function ns.OnLanguageChanged()
    if ns.UpdateTrackerTexts then ns.UpdateTrackerTexts() end
    if ns.ResetDungeonWindow then ns.ResetDungeonWindow() end
    if options then
        local wasShown = options:IsShown()
        local unlocked = ns.unlocked
        options:SetScript("OnHide", nil)
        options:Hide()
        options = nil
        wipe(controls)
        if wasShown then
            ns.ToggleOptions()
            ns.SetUnlocked(unlocked)
            ns.RefreshOptions()
        end
    end
end

-- Eintrag im zentralen Einstellungsfenster schon beim Laden (die Seite selbst entsteht erst beim ersten Öffnen)
do
    local HUB = _G.ForeverHub and _G.ForeverHub.UI
    if HUB and HUB.RegisterSettingsLink then
        HUB.RegisterSettingsLink({ key = "ForeverQuests", group = HUB.SETTINGS_GROUPS.nav, label = HUB.T("Quest- und Dungeontracker", "Quest & dungeon tracker"),
            open = function() ns.ToggleOptions() end })
    end
end
