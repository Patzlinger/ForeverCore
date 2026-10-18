local addonName, ns = ...

-- Gemeinsamer flacher, dunkler Stil für Tracker, Menü und Fenster

local Style = {}
ns.Style = Style

-- Farben zentral aus ForeverCore (UI.COLOR): dieselbe Tabelle wie bei allen Forever-Addons – ändert man dort
-- einen Farbton, ändert er sich überall. Fenster, Positionen und Menüs dieses Addons bleiben, wie sie sind.
-- (Rückfall nur, falls ForeverCore fehlt – ist aber Abhängigkeit.)
local HUB_UI = _G.ForeverHub and _G.ForeverHub.UI
Style.COLOR = (HUB_UI and HUB_UI.COLOR) or {
    background = { 0.07, 0.07, 0.09, 0.97 },
    header = { 0.11, 0.11, 0.14, 1 },
    panel = { 0.10, 0.10, 0.12, 0.95 },
    border = { 0.22, 0.22, 0.26, 1 },
    input = { 0.06, 0.06, 0.08, 1 },
    button = { 0.16, 0.16, 0.20, 1 },
    buttonHover = { 0.22, 0.22, 0.27, 1 },
    accent = { 1, 0.82, 0 },
}
local COLOR = Style.COLOR

Style.BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

function Style.SetFlat(frame, bg, border)
    frame:SetBackdrop(Style.BACKDROP)
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border or COLOR.border))
end

local function SetAccentBorder(frame, on)
    if on then
        frame:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
    else
        frame:SetBackdropBorderColor(unpack(COLOR.border))
    end
end

-- Eigener Tooltip im Stil der Addon-Fenster: dunkler Hintergrund, dünner grauer Rand, goldene Linie oben.
-- Funktioniert wie der normale Spiel-Tooltip (AddLine, SetItemByID, …); der Spiel-Tooltip bleibt unverändert.
local tooltipFrame
function Style.GetTooltip()
    if tooltipFrame then return tooltipFrame end
    local tip = CreateFrame("GameTooltip", "ForeverQuestsTooltip", UIParent, "GameTooltipTemplate")
    tip:SetFrameStrata("TOOLTIP")

    -- Hintergrund und Rand als Flächen ganz unten (die Textzeilen liegen darüber)
    local background = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints()
    background:SetColorTexture(COLOR.background[1], COLOR.background[2], COLOR.background[3], 0.97)
    local function Edge(point1, point2, horizontal, color)
        local edge = tip:CreateTexture(nil, "BACKGROUND", nil, -7)
        edge:SetColorTexture(unpack(color))
        edge:SetPoint(point1)
        edge:SetPoint(point2)
        if horizontal then edge:SetHeight(1) else edge:SetWidth(1) end
    end
    Edge("TOPLEFT", "TOPRIGHT", true, { COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.7 })
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true, COLOR.border)
    Edge("TOPLEFT", "BOTTOMLEFT", false, COLOR.border)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false, COLOR.border)

    -- Den normalen verzierten Rand des Spiel-Tooltips ausblenden (auch, wenn das Spiel ihn wieder einschaltet)
    local function HideDefaultBorder(self)
        if self.NineSlice then self.NineSlice:Hide() end
    end
    HideDefaultBorder(tip)
    tip:HookScript("OnShow", HideDefaultBorder)

    tooltipFrame = tip
    return tip
end

-- Tooltip: Text oder Funktion, die den Tooltip befüllt
local function ShowTooltip(owner, tooltip)
    if not tooltip then return end
    local tip = Style.GetTooltip()
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    if type(tooltip) == "function" then
        tooltip(tip)
    else
        tip:AddLine(tooltip)
    end
    tip:Show()
end

---------------------------------------------------------------------------
-- Fenster mit Titelleiste
---------------------------------------------------------------------------

function Style.CreateWindow(name, width, height, titleText)
    local window = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    window:SetSize(width, height)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    Style.SetFlat(window, COLOR.background)
    tinsert(UISpecialFrames, name) -- mit Escape schließbar

    -- Titelleiste zum Verschieben
    local header = CreateFrame("Frame", nil, window, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(40)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(unpack(COLOR.header))
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    local accentLine = header:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("BOTTOMLEFT")
    accentLine:SetPoint("BOTTOMRIGHT")
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.6)

    window.titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    window.titleText:SetPoint("LEFT", 16, 0)
    window.titleText:SetText(titleText)
    window.subText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.subText:SetPoint("LEFT", window.titleText, "RIGHT", 10, -1)

    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    local close
    if hubUI and hubUI.CloseButton then
        close = hubUI.CloseButton(header, function() window:Hide() end)
        close:SetPoint("RIGHT", -8, 0)
    else
        close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
        close:SetPoint("RIGHT", -6, 0)
        close:SetScript("OnClick", function() window:Hide() end)
    end

    window.header = header
    -- beim Forever-Hub anmelden: das zuletzt geoeffnete/angeklickte Forever-Fenster liegt oben (kein Ineinander-Clippen)
    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    if hubUI and hubUI.RegisterWindow then hubUI.RegisterWindow(window) end
    return window
end

-- Dunkles Feld mit optionaler Überschrift
function Style.CreatePanel(parent, title)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    Style.SetFlat(panel, COLOR.panel)
    if title then
        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.title:SetPoint("TOPLEFT", 14, -12)
        panel.title:SetText(title)
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", 12, -30)
        line:SetPoint("TOPRIGHT", -12, -30)
    end
    return panel
end

---------------------------------------------------------------------------
-- Bedienelemente
---------------------------------------------------------------------------

-- Flacher Knopf; :SetText funktioniert wie bei normalen Knöpfen
function Style.CreateButton(parent, text, width, height, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height or 22)
    Style.SetFlat(button, COLOR.button)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetText(text)
    button.tooltip = tooltip
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLOR.buttonHover))
        SetAccentBorder(self, true)
        ShowTooltip(self, self.tooltip)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLOR.button))
        SetAccentBorder(self, false)
        Style.GetTooltip():Hide()
    end)
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

-- Auswahlknopf mit Pfeil (öffnet eine Liste)
function Style.CreateDropdown(parent, width)
    local button = Style.CreateButton(parent, "", width, 22)
    local label = button:GetFontString()
    label:ClearAllPoints()
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -22, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetRotation(-math.pi / 2)
    arrow:SetVertexColor(0.8, 0.8, 0.8)
    return button
end

-- Häkchen als kleines Kästchen, das sich gold füllt; Klick auf den Text zählt mit
function Style.CreateCheckbox(parent, label)
    local checkbox = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    checkbox:SetSize(16, 16)
    Style.SetFlat(checkbox, COLOR.input)
    local check = checkbox:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    check:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)
    checkbox:SetCheckedTexture(check)

    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    checkbox.label:SetText(label)
    checkbox:SetHitRectInsets(0, -(checkbox.label:GetStringWidth() + 10), -3, -3)

    checkbox:SetScript("OnEnter", function(self) SetAccentBorder(self, true) end)
    checkbox:SetScript("OnLeave", function(self) SetAccentBorder(self, false) end)
    return checkbox
end

-- Schieberegler: dünne Leiste, goldener Anteil bis zum Griff
function Style.CreateSlider(parent, width)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetSize(width, 16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(0.25, 0.25, 0.30, 1)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 16)
    thumb:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)
    slider:SetThumbTexture(thumb)

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.5)
    return slider
end

---------------------------------------------------------------------------
-- Aufklapp-Liste (z. B. für den Filter)
--
-- items = {
--   { title = "Überschrift" },
--   { radio = true, text = "...", checked = function() ... end, onClick = function() ... end },
--   { checkbox = true, text = "...", checked = function() ... end, onClick = function() ... end },
--   { text = "...", onClick = function() ... end, disabled = false, color = { r, g, b } },  -- normaler Eintrag
--   { divider = true },
-- }
-- opts (optional): atCursor = true (an der Mausposition), align = "LEFT" (linksbündig unter dem Knopf)
-- Häkchen-Einträge (checkbox) lassen die Liste beim Klick offen, alle anderen schließen sie.
---------------------------------------------------------------------------

local menuFrame, menuCatcher
local menuRows = {}
local MENU_ROW_HEIGHT = 22

function Style.HideMenu()
    if menuFrame then menuFrame:Hide() end
end

local function GetMenuRow(index)
    local row = menuRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, menuFrame)
    row:SetHeight(MENU_ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    row.highlight = highlight

    -- Kästchen links: hohl = aus, gold gefüllt = an
    row.box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.box:SetSize(12, 12)
    row.box:SetPoint("LEFT", 10, 0)
    Style.SetFlat(row.box, COLOR.input)
    row.fill = row.box:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", 2, -2)
    row.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    row.fill:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 30, 0)
    row.text:SetJustifyH("LEFT")

    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("LEFT", 8, 0)
    row.line:SetPoint("RIGHT", -8, 0)
    row.line:SetColorTexture(1, 1, 1, 0.1)

    row:SetScript("OnClick", function(self)
        local item = self.item
        if not item or not item.onClick then return end
        if item.checkbox then
            item.onClick()
            -- Alle Kästchen neu setzen (ein Klick kann auch andere Einträge ändern)
            for _, other in ipairs(menuRows) do
                local otherItem = other.item
                if other:IsShown() and otherItem and (otherItem.radio or otherItem.checkbox) then
                    other.fill:SetShown(otherItem.checked and otherItem.checked() or false)
                end
            end
        else
            Style.HideMenu()
            item.onClick()
        end
    end)
    menuRows[index] = row
    return row
end

function Style.ShowMenu(owner, items, opts)
    opts = opts or {}
    if not menuFrame then
        -- Unsichtbare Fläche über dem ganzen Bildschirm: Klick daneben schließt die Liste
        menuCatcher = CreateFrame("Button", nil, UIParent)
        menuCatcher:SetAllPoints(UIParent)
        menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        menuCatcher:RegisterForClicks("AnyUp")
        menuCatcher:SetScript("OnClick", Style.HideMenu)
        menuCatcher:Hide()

        menuFrame = CreateFrame("Frame", "ForeverQuestsPopupMenu", UIParent, "BackdropTemplate")
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(menuCatcher:GetFrameLevel() + 10)
        menuFrame:SetClampedToScreen(true)
        menuFrame:EnableMouse(true)
        Style.SetFlat(menuFrame, COLOR.background)
        menuFrame:SetScript("OnHide", function() menuCatcher:Hide() end)
        menuFrame:Hide()
        tinsert(UISpecialFrames, "ForeverQuestsPopupMenu") -- mit Escape schließbar
    end

    -- Zweiter Klick auf denselben Knopf schließt die Liste
    if menuFrame:IsShown() and menuFrame.owner == owner then
        Style.HideMenu()
        return
    end
    menuFrame.owner = owner

    local y, width = -6, 180
    for i, item in ipairs(items) do
        local row = GetMenuRow(i)
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 1, y)
        row:SetPoint("RIGHT", -1, 0)
        local hasBox = (item.radio or item.checkbox) and true or false
        local clickable = item.onClick ~= nil and not item.disabled
        row.line:SetShown(item.divider == true)
        row.box:SetShown(hasBox)
        row.highlight:SetShown(clickable)
        row:EnableMouse(clickable)

        if item.divider then
            row:SetHeight(9)
            row.text:SetText("")
        elseif item.title then
            row:SetHeight(MENU_ROW_HEIGHT)
            row.text:SetText(item.title)
            row.text:SetTextColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3])
            row.text:SetPoint("LEFT", 10, 0)
        else
            row:SetHeight(MENU_ROW_HEIGHT)
            row.text:SetText(item.text)
            if item.disabled then
                row.text:SetTextColor(0.45, 0.45, 0.45)
            elseif item.color then
                row.text:SetTextColor(unpack(item.color))
            else
                row.text:SetTextColor(0.9, 0.9, 0.9)
            end
            row.text:SetPoint("LEFT", hasBox and 30 or 12, 0)
            row.fill:SetShown(hasBox and item.checked and item.checked() or false)
        end
        width = math.max(width, row.text:GetStringWidth() + (hasBox and 50 or 32))
        row:Show()
        y = y - row:GetHeight()
    end
    for i = #items + 1, #menuRows do
        menuRows[i]:Hide()
    end

    menuFrame:ClearAllPoints()
    if opts.atCursor then
        local x, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 2, cursorY / scale - 2)
    elseif opts.align == "LEFT" then
        width = math.max(width, owner:GetWidth())
        menuFrame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    else
        menuFrame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
    end
    menuFrame:SetSize(width, -y + 6)
    menuCatcher:Show()
    menuFrame:Show()
end

-- Eingabefeld
function Style.CreateEditBox(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, height or 20)
    Style.SetFlat(box, COLOR.input)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEditFocusGained", function(self) SetAccentBorder(self, true) end)
    box:SetScript("OnEditFocusLost", function(self) SetAccentBorder(self, false) end)
    return box
end
