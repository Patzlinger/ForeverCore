-- ForeverHub: gemeinsame Grundlage aller Forever-Addons
-- Diese Datei liegt (identisch) in jedem Forever-Addon. Nur die neueste geladene Kopie arbeitet.
--  1. ForeverHub.UI: einheitlicher Stil (Fenster, Ueberschriften, Knoepfe, Regler, Minimap-Knopf,
--     Chat-Ausgabe, Sprache). Jedes Forever-Addon baut seine Oberflaeche damit.
--  2. Sammelknopf: Sind mindestens zwei Forever-Addons aktiv, werden deren Minimap-Knoepfe
--     ausgeblendet und in einer ausklappbaren Liste gesammelt. Klicks gehen an den Original-Knopf.
--  3. Hub-Fenster (/forever): Liste aller Forever-Addons mit direktem Weg in ihr Menue –
--     auch ohne Minimap-Knoepfe.
local ADDON_NAME = ...
local VERSION = 18
if _G.ForeverHub and (_G.ForeverHub.version or 0) >= VERSION then return end

local hub = { version = VERSION }
_G.ForeverHub = hub

---------------------------------------------------------------------------
-- 1. Gemeinsamer Stil
---------------------------------------------------------------------------
local UI = {}
hub.UI = UI

-- Sprache (gemeinsam fuer alle Forever-Addons): Deutsch gibt es nur auf einem deutschen Client; dort laesst
-- sich im Hub-Fenster (/forever) Englisch waehlen. Gespeichert in ForeverHubDB.language ("deDE"/"enUS",
-- nil = automatisch), wirksam nach /reload. UI.GetLanguage() -> "deDE" oder "enUS".
UI.GERMAN_CLIENT = GetLocale() == "deDE"
function UI.GetLanguage()
    if not UI.GERMAN_CLIENT then return "enUS" end
    local db = _G.ForeverHubDB
    if type(db) == "table" and db.language == "enUS" then return "enUS" end
    return "deDE"
end
UI.IS_DE = UI.GetLanguage() == "deDE"
function UI.T(de, en) return UI.GetLanguage() == "deDE" and de or en end
local T = UI.T
-- ForeverHubDB kommt erst mit dem ersten geladenen Forever-Addon: IS_DE danach nachziehen
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function() UI.IS_DE = UI.GetLanguage() == "deDE" end)
end

-- Forever-Core-Logo (liegt in jedem Forever-Addon unter Media\)
UI.LOGO = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Media\\ForeverCore"
UI.NAME = "Forever Core"

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
UI.GOLD = { 1, 0.82, 0 }

-- Flacher, dunkler Stil (Vorbild: ForeverQuests von flowfy): dunkle Flaechen, feine Raender,
-- Gold als einzige Akzentfarbe (Hover-Rand, Haekchen, Regler, Titellinie)
UI.COLOR = {
    background = { 0.07, 0.07, 0.09, 0.97 },
    header = { 0.11, 0.11, 0.14, 1 },
    panel = { 0.10, 0.10, 0.12, 0.95 },
    border = { 0.22, 0.22, 0.26, 1 },
    input = { 0.06, 0.06, 0.08, 1 },
    button = { 0.16, 0.16, 0.20, 1 },
    buttonHover = { 0.22, 0.22, 0.27, 1 },
    accent = { 1, 0.82, 0 },
}
local C = UI.COLOR

function UI.SetFlat(frame, bg, border)
    frame:SetBackdrop(FLAT)
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    local b = border or C.border
    frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
end

-- goldener Rand nur beim Ueberfahren (Highlight-Ebene: braucht keine Skripte, die ein Addon ueberschreiben koennte)
local function HoverEdge(frame, withFill)
    if withFill then
        local fill = frame:CreateTexture(nil, "HIGHLIGHT")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(1, 1, 1, 0.06)
    end
    local a = C.accent
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = frame:CreateTexture(nil, "HIGHLIGHT")
        t:SetColorTexture(a[1], a[2], a[3], 0.9)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
    end
end

-- Chat-Ausgabe: "ForeverXY: Text" mit goldenem Namen
function UI.Chat(addon, text)
    print("|cffffcc00" .. addon .. "|r: " .. tostring(text))
end

-- Anzeige-Fenster (XP-Leiste, Wuerfel-Fenster, Sammelliste …): dunkel, schlanker Rand
function UI.Hud(f, alpha)
    f:SetBackdrop(FLAT)
    f:SetBackdropColor(C.background[1], C.background[2], C.background[3], alpha or 0.88)
    f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
end

-- Innenrahmen fuer Listen, Textfelder und Reiter-Inhalte
function UI.Box(parent, alpha)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop(FLAT)
    b:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], alpha or C.panel[4])
    b:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    return b
end

-- Hauptfenster / Einstellungsfenster: flach und dunkel, Titelleiste mit Goldlinie,
-- verschiebbar, mit Escape schliessbar
function UI.Window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.SetFlat(f, C.background)
    f:Hide()
    if name then tinsert(UISpecialFrames, name) end

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(26)
    header:SetBackdrop({ bgFile = WHITE })
    header:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    f.header = header

    -- dezentes Logo links neben dem Titel
    local logo = header:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(UI.LOGO)
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", 8, 0)
    f.TitleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.TitleText:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    f.TitleText:SetText(title)

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.CloseButton = close
    return f
end

---------------------------------------------------------------------------
-- Abschnitte: jede Ueberschrift bekommt einen dezenten Kasten (wie in ForeverQuests).
-- Beim Oeffnen eines Fensters wird ausgemessen, was unter der Ueberschrift steht – bis zur
-- naechsten Ueberschrift in derselben Spalte – und der Kasten passend darum gezeichnet.
-- So braucht kein Addon seine Einstellungen neu anzuordnen.
---------------------------------------------------------------------------
local function NewSectionBox(parent)
    local b = {}
    b.fill = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
    b.fill:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], C.panel[4])
    b.edges = {}
    for i = 1, 4 do
        local e = parent:CreateTexture(nil, "BORDER", nil, 1)
        e:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        b.edges[i] = e
    end
    local f, e = b.fill, b.edges
    e[1]:SetPoint("TOPLEFT", f, "TOPLEFT") e[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT") e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT") e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", f, "TOPLEFT") e[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT") e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT") e[4]:SetWidth(1)
    return b
end

-- haengt ein Element (auch ueber Umwege) am unteren Rand des Fensters? (Fussleiste, Hintergrund)
local function AtBottom(obj, parent)
    for _ = 1, 6 do
        local nextObj
        for i = 1, (obj.GetNumPoints and obj:GetNumPoints() or 0) do
            local point, rel = obj:GetPoint(i)
            if (not rel or rel == parent) and point and point:find("BOTTOM") then return true end
            if rel and rel ~= parent and not nextObj then nextObj = rel end
        end
        if not nextObj or not nextObj.GetNumPoints then return false end
        obj = nextObj
    end
    return false
end

function UI.LayoutSections(parent)
    local secs = parent.fcSections
    if not secs or not parent:IsVisible() then return end
    local pl, pt = parent:GetLeft(), parent:GetTop()
    local pw = parent:GetWidth()
    if not (pl and pt and pw) then return end
    local skip = {}
    for _, s in ipairs(secs) do skip[s.fs] = true end
    if parent.header then skip[parent.header] = true end

    -- alles Sichtbare im Fenster, relativ zur linken oberen Ecke. Bei Haekchen zaehlt der Text mit.
    local items = {}
    local function Add(obj)
        if skip[obj] or not obj:IsShown() then return end
        local l, r, t, b = obj:GetLeft(), obj:GetRight(), obj:GetTop(), obj:GetBottom()
        if not (l and r and t and b) or AtBottom(obj, parent) then return end
        local label = obj.label
        if type(label) == "table" and label.GetRight and label:IsShown() and label:GetRight() then
            r = math.max(r, label:GetRight())
        end
        items[#items + 1] = { l = l - pl, r = r - pl, t = t - pt, b = b - pt }
    end
    for _, c in ipairs({ parent:GetChildren() }) do Add(c) end
    for _, r in ipairs({ parent:GetRegions() }) do
        if r:IsObjectType("FontString") then Add(r) end
    end

    local headerBottom = parent.header and parent.header:GetBottom() and (parent.header:GetBottom() - pt)
    for _, s in ipairs(secs) do
        local hl = s.x - 8
        -- rechte Grenze: schmale Ueberschriften (Spalten) enden vor der naechsten Spalte rechts davon;
        -- breite Ueberschriften (ueber beide Spalten) duerfen so breit sein wie angegeben
        local cap = pw - 6
        if s.width < 400 then
            for _, o in ipairs(secs) do
                if o.x > s.x + 20 then cap = math.min(cap, o.x - 14) end
            end
        end
        -- naechste Ueberschrift darunter, die in diese Spalte faellt
        local nextY
        for _, o in ipairs(secs) do
            if o ~= s and o.y < s.y and o.x < cap and o.x + 8 > hl then
                if not nextY or o.y > nextY then nextY = o.y end
            end
        end
        -- Inhalt des Abschnitts: unter der Ueberschrift, ueber der naechsten, links in dieser Spalte
        local bottom, right = s.y - 18, math.min(cap, s.x - 2 + s.width)
        for _, it in ipairs(items) do
            if it.l >= hl - 4 and it.l < cap and it.t <= s.y + 2 and (not nextY or it.t > nextY + 2) then
                bottom = math.min(bottom, it.b)
                right = math.max(right, it.r + 8)
            end
        end
        right = math.min(right, cap)
        local top = s.y + 9
        if headerBottom then top = math.min(top, headerBottom - 2) end
        local boxBottom = bottom - 9
        if nextY then boxBottom = math.max(boxBottom, nextY + 14) end
        s.box = s.box or NewSectionBox(parent)
        s.box.fill:ClearAllPoints()
        s.box.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", hl, top)
        s.box.fill:SetSize(right - hl, math.max(24, top - boxBottom))
        -- Linie unter der Ueberschrift ueber die ganze Kastenbreite
        s.line:ClearAllPoints()
        s.line:SetPoint("TOPLEFT", parent, "TOPLEFT", hl + 6, s.y - 17)
        s.line:SetWidth(right - hl - 12)
    end
end

-- Abschnitts-Ueberschrift: goldene Schrift mit feiner heller Linie darunter (im eigenen Kasten)
function UI.Header(parent, x, y, text, width)
    width = width or 318
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", x - 4, y - 17)
    line:SetSize(width - 4, 1)
    if not parent.fcSections then
        parent.fcSections = {}
        parent:HookScript("OnShow", function(self)
            C_Timer.After(0, function() UI.LayoutSections(self) end)
        end)
    end
    table.insert(parent.fcSections, { fs = fs, line = line, x = x, y = y, width = width })
    if parent:IsVisible() then C_Timer.After(0, function() UI.LayoutSections(parent) end) end
    return fs
end
-- Grauer Erklaertext
function UI.Hint(parent, x, y, width, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if x then fs:SetPoint("TOPLEFT", x, y) end
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Beschriftung: "label" = weiss (Werte, Regler-Titel), "field" = gold (Feldname vor Eingabe)
function UI.Text(parent, kind, text)
    local font = kind == "field" and "GameFontNormal" or "GameFontHighlightSmall"
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetText(text or "")
    return fs
end

-- Flacher Knopf. Deaktiviert (z. B. der gerade offene Reiter) = goldene Schrift und Rand.
function UI.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 22)
    UI.SetFlat(b, C.button)
    HoverEdge(b, true)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    b:SetFontString(label)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontNormalSmall")
    b:SetText(text)
    b:SetScript("OnDisable", function(self)
        self:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
    end)
    b:SetScript("OnEnable", function(self)
        self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
    b:SetPushedTextOffset(0, -1)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- kleiner Pfeil rechts im Knopf (Auswahlliste)
function UI.AddArrow(b)
    local fs = b:GetFontString()
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -22, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
    end
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetRotation(-math.pi / 2)
    arrow:SetVertexColor(0.8, 0.8, 0.8)
    return b
end

-- Haekchen als kleines Kaestchen, das sich gold fuellt; Klick auf den Text zaehlt mit.
-- onClick(checked) bekommt true/false
function UI.Check(parent, x, y, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(16, 16)
    if x then cb:SetPoint("TOPLEFT", x + 4, y - 4) end -- gleiche Lage wie das fruehere 24-px-Haekchen
    UI.SetFlat(cb, C.input)
    HoverEdge(cb, false)
    local check = cb:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    check:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    cb:SetCheckedTexture(check)
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    cb.label, cb.Text = text, text
    cb:SetHitRectInsets(0, -(text:GetStringWidth() + 10), -4, -4)
    if onClick then
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    end
    return cb
end

-- Regler im flachen Stil: duenne Leiste, goldener Griff, Gold bis zum Griff (auch fuer eigene Regler)
function UI.StyleSlider(s)
    if s.SetBackdrop then s:SetBackdrop(nil) end
    s:SetHeight(16)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetColorTexture(0.25, 0.25, 0.30, 1)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 16)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    s:SetThumbTexture(thumb)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
    return s
end

-- Schieberegler mit Titel darueber und – / + daneben.
-- opts: width, unit (z. B. " px"), format(value) -> Anzeigetext
-- onChange(value) wird nur bei Aenderungen durch den Spieler gerufen;
-- s:Load(value) setzt den Wert ohne onChange.
function UI.Slider(parent, x, y, label, minV, maxV, step, onChange, opts)
    opts = opts or {}
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", x, y)
    title:SetTextColor(0.75, 0.75, 0.75)

    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(opts.width or 170, 16)
    s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    UI.StyleSlider(s)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.title = title

    local function Show(value)
        local shown = opts.format and opts.format(value)
        if not shown then
            if math.abs(value - math.floor(value + 0.5)) < 0.001 then
                shown = string.format("%d%s", math.floor(value + 0.5), opts.unit or "")
            else
                shown = string.format("%.1f%s", value, opts.unit or "")
            end
        end
        title:SetText(label .. ": |cffffffff" .. shown .. "|r")
    end

    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if self.loading or self.lastValue == value then return end
        self.lastValue = value
        if onChange then onChange(value) end
    end)

    local minus = UI.Button(parent, "–", 20, function() s:SetValue(s:GetValue() - step) end)
    minus:SetHeight(18)
    minus:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local plus = UI.Button(parent, "+", 20, function() s:SetValue(s:GetValue() + step) end)
    plus:SetHeight(18)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)

    function s:Load(value)
        self.loading = true
        self.lastValue = value
        self:SetValue(value)
        Show(value)
        self.loading = false
    end
    return s
end

-- Eingabefeld im flachen Stil (goldener Rand, solange man tippt)
function UI.EditBox(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, height or 20)
    UI.SetFlat(box, C.input)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:HookScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    end)
    box:HookScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
    return box
end

---------------------------------------------------------------------------
-- Aufklapp-Liste im flachen Stil (statt Blizzard-Menue), Vorbild ForeverQuests.
-- items = { { title = "…" }, { radio = true, text = "…", checked = fn, onClick = fn },
--           { checkbox = true, … }, { text = "…", onClick = fn, disabled = bool }, { divider = true } }
-- opts: align = "LEFT" (linksbuendig unter dem Knopf), atCursor = true
---------------------------------------------------------------------------
local menuFrame, menuCatcher
local menuRows = {}
local MENU_ROW_H = 22

function UI.HideMenu()
    if menuFrame then menuFrame:Hide() end
end

local function MenuRow(i)
    local row = menuRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menuFrame)
    row:SetHeight(MENU_ROW_H)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.06)
    row.box = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.box:SetSize(12, 12)
    row.box:SetPoint("LEFT", 10, 0)
    UI.SetFlat(row.box, C.input)
    row.fill = row.box:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", 2, -2)
    row.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    row.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
            self.fill:SetShown(item.checked and item.checked() or false)
        else
            UI.HideMenu()
            item.onClick()
        end
    end)
    menuRows[i] = row
    return row
end

function UI.ShowMenu(owner, items, opts)
    opts = opts or {}
    if not menuFrame then
        -- unsichtbare Flaeche ueber dem Bildschirm: Klick daneben schliesst die Liste
        menuCatcher = CreateFrame("Button", nil, UIParent)
        menuCatcher:SetAllPoints(UIParent)
        menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        menuCatcher:RegisterForClicks("AnyUp")
        menuCatcher:SetScript("OnClick", UI.HideMenu)
        menuCatcher:Hide()
        menuFrame = CreateFrame("Frame", "ForeverHubMenu", UIParent, "BackdropTemplate")
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(menuCatcher:GetFrameLevel() + 10)
        menuFrame:SetClampedToScreen(true)
        menuFrame:EnableMouse(true)
        UI.SetFlat(menuFrame, C.background)
        menuFrame:SetScript("OnHide", function() menuCatcher:Hide() end)
        menuFrame:Hide()
        tinsert(UISpecialFrames, "ForeverHubMenu")
    end
    -- zweiter Klick auf denselben Knopf schliesst die Liste
    if menuFrame:IsShown() and menuFrame.owner == owner then UI.HideMenu() return end
    menuFrame.owner = owner

    local y, width = -6, 180
    for i, item in ipairs(items) do
        local row = MenuRow(i)
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
        row.text:ClearAllPoints()
        if item.divider then
            row:SetHeight(9)
            row.text:SetText("")
        elseif item.title then
            row:SetHeight(MENU_ROW_H)
            row.text:SetText(item.title)
            row.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            row.text:SetPoint("LEFT", 10, 0)
        else
            row:SetHeight(MENU_ROW_H)
            row.text:SetText(item.text)
            if item.disabled then row.text:SetTextColor(0.45, 0.45, 0.45)
            else row.text:SetTextColor(0.9, 0.9, 0.9) end
            row.text:SetPoint("LEFT", hasBox and 30 or 12, 0)
            row.fill:SetShown(hasBox and item.checked and item.checked() or false)
        end
        width = math.max(width, row.text:GetStringWidth() + (hasBox and 50 or 32))
        row:Show()
        y = y - row:GetHeight()
    end
    for i = #items + 1, #menuRows do menuRows[i]:Hide() end

    menuFrame:ClearAllPoints()
    if opts.atCursor then
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale - 2)
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

-- Auswahl-Liste fuer Einstellungen: list = { { key, label }, … }; current = Schluessel; pick(key).
-- Kurze Listen im flachen Stil, sehr lange (z. B. viele Schriften) im Blizzard-Menue mit Bildlauf.
function UI.ChoiceMenu(owner, list, current, pick)
    if #list <= 20 then
        local items = {}
        for _, c in ipairs(list) do
            items[#items + 1] = { radio = true, text = c.label, checked = function() return current() == c.key end,
                onClick = function() pick(c.key) end }
        end
        UI.ShowMenu(owner, items, { align = "LEFT" })
        return true
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            if root.SetScrollMode then root:SetScrollMode(400) end
            for _, c in ipairs(list) do
                root:CreateRadio(c.label, function() return current() == c.key end, function() pick(c.key) end)
            end
        end)
        return true
    end
    return false
end

-- Minimap-Knopf im gleichen Look fuer alle Forever-Addons
-- o = { name, icon, title, angle = function() -> Grad, setAngle = function(Grad),
--       onClick = function(button, mouseButton), lines = function() -> { "Linksklick: …", … },
--       texCoord = { l, r, t, b } (optional, z. B. Rand von Spielsymbolen abschneiden) }
function UI.MinimapButton(o)
    local b = CreateFrame("Button", o.name, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(o.icon)
    if o.texCoord then icon:SetTexCoord(unpack(o.texCoord)) end
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    function b.UpdatePosition()
        local angle = math.rad(o.angle() or 200)
        local radius = (Minimap:GetWidth() / 2) + 5
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end

    local function OnDrag()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        o.setAngle(math.deg(math.atan2(py / scale - my, px / scale - mx)))
        b.UpdatePosition()
    end
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDrag) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", o.onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(o.title)
        for _, line in ipairs(o.lines and o.lines() or {}) do
            GameTooltip:AddLine(line, 1, 1, 1)
        end
        -- im Sammelknopf (Tooltip an der Listenzeile) laesst sich nichts ziehen
        if self == b then
            GameTooltip:AddLine(T("Ziehen: Knopf verschieben", "Drag: move button"), 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b.UpdatePosition()
    return b
end

-- Zahlenfeld mit –/+ fuer genaue Werte (z. B. X/Y-Position); Eingabe mit Enter bestaetigen.
-- get() liefert den Wert, set(v) speichert ihn. Rueckgabe hat :Load() zum Neu-Anzeigen.
function UI.Number(parent, x, y, label, get, set)
    local fs = UI.Text(parent, "label", label)
    fs:SetPoint("TOPLEFT", x, y - 4)
    local e = UI.EditBox(parent, 56, 20)
    e:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    e:SetJustifyH("CENTER")
    function e:Load()
        self:SetText(string.format("%g", get() or 0))
        self:SetCursorPosition(0)
    end
    local function Store(v)
        v = tonumber(v)
        if v and v ~= get() then set(v) end
        e:Load()
    end
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:Load() self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) Store(self:GetText()) end)
    local minus = UI.Button(parent, "–", 20, function() Store((get() or 0) - 1) end)
    minus:SetPoint("LEFT", e, "RIGHT", 4, 0)
    local plus = UI.Button(parent, "+", 20, function() Store((get() or 0) + 1) end)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    return e
end

---------------------------------------------------------------------------
-- Ausrichten: Raster, Einrasten, Hilfslinien – fuer alle verschiebbaren Forever-Rahmen.
-- Rahmen, die mit UI.AddMover angemeldet sind, rasten beim Ziehen aneinander ein
-- (auch ueber Addons hinweg, z. B. Zauberleiste an Spielerrahmen).
---------------------------------------------------------------------------
local SNAP = 8          -- ab diesem Abstand (px) rastet eine Kante ein
local movers = {}
local grid, gridOwners = nil, {}

function UI.AddMover(frame) movers[#movers + 1] = frame end

-- auf halbe Pixel runden (damit Kanten unterschiedlich breiter Rahmen genau buendig sind)
function UI.Round(v) return math.floor(v * 2 + 0.5) / 2 end

-- Mitte eines Rahmens relativ zur Bildschirmmitte
function UI.CenterOffset(frame)
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return 0, 0 end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return UI.Round(cx * s - ux), UI.Round(cy * s - uy)
end

local function GridSize()
    local size
    for _, s in pairs(gridOwners) do size = math.min(size or s, s) end
    return size
end

local function DrawGrid()
    local size = GridSize()
    if not size then
        if grid then grid:Hide() end
        return
    end
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
        grid:RegisterEvent("DISPLAY_SIZE_CHANGED")
        grid:RegisterEvent("UI_SCALE_CHANGED")
        grid:SetScript("OnEvent", function() DrawGrid() end)
    end
    size = math.max(8, size)
    local w, h = UIParent:GetSize()
    local key = size .. ":" .. math.floor(w) .. ":" .. math.floor(h)
    if grid.key ~= key then -- nur neu zeichnen, wenn sich Abstand oder Bildschirm aendert
        grid.key = key
        for _, t in ipairs(grid.lines) do t:Hide() end
        local n = 0
        local function Line(vertical, offset)
            n = n + 1
            local t = grid.lines[n]
            if not t then
                t = grid:CreateTexture(nil, "BACKGROUND")
                grid.lines[n] = t
            end
            t:ClearAllPoints()
            if offset == 0 then t:SetColorTexture(1, 0.25, 0.25, 0.7) else t:SetColorTexture(0, 0, 0, 0.45) end
            if vertical then
                t:SetPoint("TOP", grid, "TOP", offset, 0)
                t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
                t:SetWidth(1)
            else
                t:SetPoint("LEFT", grid, "LEFT", 0, offset)
                t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
                t:SetHeight(1)
            end
            t:Show()
        end
        for i = 0, math.floor(w / 2 / size) do
            Line(true, i * size)
            if i > 0 then Line(true, -i * size) end
        end
        for i = 0, math.floor(h / 2 / size) do
            Line(false, i * size)
            if i > 0 then Line(false, -i * size) end
        end
    end
    grid:Show()
end

-- Raster anfordern (size) oder abmelden (nil). Sichtbar, solange irgendein Addon es will.
function UI.Grid(owner, size)
    gridOwners[owner] = size
    DrawGrid()
end

-- gelbe Hilfslinien beim Ziehen: zeigen, an welcher Kante gerade eingerastet wird
local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints(UIParent)
guides:SetFrameStrata("HIGH")
guides:Hide()
local guideV = guides:CreateTexture(nil, "OVERLAY")
guideV:SetColorTexture(1, 0.82, 0, 0.9)
guideV:SetWidth(1)
local guideH = guides:CreateTexture(nil, "OVERLAY")
guideH:SetColorTexture(1, 0.82, 0, 0.9)
guideH:SetHeight(1)

-- linke Kante, Mitte, rechte Kante (bzw. unten, Mitte, oben), relativ zur Bildschirmmitte
local function Edges(frame)
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local ux, uy = UIParent:GetCenter()
    if not (l and r and t and b and ux) then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    l, r, t, b = l * s, r * s, t * s, b * s
    return { l - ux, (l + r) / 2 - ux, r - ux }, { b - uy, (t + b) / 2 - uy, t - uy }
end

-- kleinster Versatz, mit dem eine eigene Kante auf einer Ziel-Linie liegt (nur innerhalb SNAP)
local function Best(mine, targets)
    local best, line
    for _, m in ipairs(mine) do
        for _, t in ipairs(targets) do
            local diff = t - m
            if math.abs(diff) <= SNAP and (not best or math.abs(diff) < math.abs(best)) then
                best, line = diff, t
            end
        end
    end
    return best, line
end

-- Versatz zum Einrasten: zuerst an anderen Rahmen und der Bildschirmmitte, sonst am Raster.
-- Umschalt gedrueckt = nicht einrasten.
local drag -- { frame, edges, snap, grid }
local function SnapOffset()
    if not drag or not drag.snap or IsShiftKeyDown() then return 0, 0 end
    local mx, my = Edges(drag.edges)
    if not mx then return 0, 0 end
    local tx, ty = { 0 }, { 0 } -- Bildschirmmitte
    for _, o in ipairs(movers) do
        if o ~= drag.frame and o ~= drag.edges and o:IsVisible() then
            local ox, oy = Edges(o)
            if ox then
                for _, v in ipairs(ox) do tx[#tx + 1] = v end
                for _, v in ipairs(oy) do ty[#ty + 1] = v end
            end
        end
    end
    local dx, lx = Best(mx, tx)
    local dy, ly = Best(my, ty)
    if drag.grid then
        local size = math.max(8, drag.grid)
        local function Nearest(list)
            local g = {}
            for _, v in ipairs(list) do g[#g + 1] = math.floor(v / size + 0.5) * size end
            return g
        end
        if not dx then dx = Best(mx, Nearest(mx)) end -- Raster: ohne Hilfslinie
        if not dy then dy = Best(my, Nearest(my)) end
    end
    return dx or 0, dy or 0, lx, ly
end

guides:SetScript("OnUpdate", function()
    local _, _, lx, ly = SnapOffset()
    guideV:ClearAllPoints()
    guideH:ClearAllPoints()
    if lx then
        guideV:SetPoint("TOP", guides, "TOP", lx, 0)
        guideV:SetPoint("BOTTOM", guides, "BOTTOM", lx, 0)
    end
    if ly then
        guideH:SetPoint("LEFT", guides, "LEFT", 0, ly)
        guideH:SetPoint("RIGHT", guides, "RIGHT", 0, ly)
    end
    guideV:SetShown(lx and true or false)
    guideH:SetShown(ly and true or false)
end)

-- Ziehen beginnt. o = { snap = true/false, grid = Rasterabstand oder nil,
-- edges = sichtbarer Teil, dessen Kanten zaehlen (Standard: der gezogene Rahmen) }
function UI.BeginDrag(frame, o)
    o = o or {}
    drag = { frame = frame, edges = o.edges or frame, snap = o.snap ~= false, grid = o.grid }
    guides:Show()
end

-- Ziehen beendet: Versatz (dx, dy) zurueckgeben, um den der Rahmen noch einrasten soll
function UI.EndDrag()
    local dx, dy = SnapOffset()
    drag = nil
    guides:Hide()
    return dx, dy
end

---------------------------------------------------------------------------
-- Verschiebe-Modus fuer alle: /fmove (oder Knopf im Sammelmenue) entsperrt alle aktiven
-- Forever-Addons auf einmal – nochmal sperrt alle wieder. Jedes Addon meldet sich an mit
-- UI.RegisterMovable(name, isLocked(), setLocked(locked)).
---------------------------------------------------------------------------
local movables, movableOrder = {}, {}

function UI.RegisterMovable(name, isLocked, setLocked)
    if not movables[name] then movableOrder[#movableOrder + 1] = name end
    movables[name] = { isLocked = isLocked, setLocked = setLocked }
end

-- Ist irgendein angemeldetes Addon gerade entsperrt?
function UI.AnyUnlocked()
    for _, name in ipairs(movableOrder) do
        local ok, locked = pcall(movables[name].isLocked)
        if ok and not locked then return true end
    end
    return false
end

-- Raster, solange der gemeinsame Verschiebe-Modus laeuft; endet von selbst, wenn alles gesperrt ist
local moveTicker
local function StopMoveGrid()
    UI.Grid("ForeverHub", nil)
    if moveTicker then moveTicker:Cancel() moveTicker = nil end
end

-- lock = true/false; nil = umschalten (ist etwas entsperrt -> alles sperren, sonst alles entsperren)
function UI.MoveAll(lock)
    if InCombatLockdown() then
        UI.Chat("Forever", T("Im Kampf nicht möglich.", "Not possible in combat."))
        return
    end
    if #movableOrder == 0 then
        UI.Chat("Forever", T("Kein verschiebbares Forever-Addon aktiv.", "No movable Forever addon active."))
        return
    end
    if lock == nil then lock = UI.AnyUnlocked() end
    local names = {}
    for _, name in ipairs(movableOrder) do
        local ok, err = pcall(movables[name].setLocked, lock)
        if ok then
            names[#names + 1] = name
        else
            local handler = geterrorhandler and geterrorhandler()
            if handler then pcall(handler, err) end
        end
    end
    if lock then
        StopMoveGrid()
        UI.Chat("Forever", T("Alle Rahmen gesperrt.", "All frames locked."))
    else
        UI.Grid("ForeverHub", 32)
        if not moveTicker then
            moveTicker = C_Timer.NewTicker(1, function()
                if not UI.AnyUnlocked() then StopMoveGrid() end
            end)
        end
        UI.Chat("Forever", string.format(T("Entsperrt: %s – ziehen zum Verschieben, /fmove sperrt wieder.",
            "Unlocked: %s – drag to move, /fmove locks again."), table.concat(names, ", ")))
    end
end

SLASH_FOREVERMOVE1 = "/fmove"
SlashCmdList["FOREVERMOVE"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" then UI.MoveAll(true)
    elseif msg == "unlock" then UI.MoveAll(false)
    else UI.MoveAll() end
end

---------------------------------------------------------------------------
-- 2. Sammelknopf
---------------------------------------------------------------------------
-- Bekannte Forever-Addons und der Name ihres Minimap-Knopfs (Reihenfolge = Reihenfolge in Liste und Hub-Fenster).
-- Neues Addon: hier eintragen; sein Minimap-Knopf muss so heissen und mit Linksklick das Menue oeffnen.
local KNOWN = {
    { name = "ForeverFrames", button = "ForeverFramesMinimapButton" },
    { name = "ForeverUnits",  button = "ForeverUnitsMinimapButton" },
    { name = "ForeverCast",   button = "ForeverCastMinimapButton" },
    { name = "ForeverBars",   button = "ForeverBarsMinimapButton" },
    { name = "ForeverQuests", button = "ForeverQuestsMinimapButton" },
    { name = "ForeverLoot",   button = "ForeverLootMinimapButton" },
    { name = "ForeverXP",     button = "ForeverXPMinimapButton" },
    { name = "ForeverBuffs",  button = "ForeverBuffsMinimapButton" },
    { name = "ForeverVendor", button = "ForeverVendorMinimapButton" },
    { name = "ForeverSpellbook", button = "ForeverSpellbookMinimapButton" },
    { name = "ForeverQuestmob", button = "ForeverQuestmobMinimapButton" },
    { name = "ForeverBoard",  button = "ForeverBoardMinimapButton" },
    { name = "ForeverNotes",  button = "ForeverNotesMinimapButton" },
}

-- Einstellungen (in jedem Forever-Addon als SavedVariable "ForeverHubDB" eingetragen)
local function GetDB()
    if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
    local db = _G.ForeverHubDB
    if db.angle == nil then db.angle = 195 end
    db.collect = nil -- alte Einstellung (Einzelknoepfe) gibt es nicht mehr
    return db
end

local entries = {}      -- gefundene Addons: { name, button, icon }
local hubButton, flyout
local active = false    -- true: Sammelknopf aktiv, Einzelknoepfe versteckt

local function IconOf(button)
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetDrawLayer and region:GetDrawLayer() == "ARTWORK" and region.GetTexture then
            local tex = region:GetTexture()
            if tex then return tex end
        end
    end
    return 134400 -- Fragezeichen
end

-- Ausklappbare Liste
local ROW_H = 24

local function BuildFlyout()
    flyout = CreateFrame("Frame", "ForeverHubFlyout", UIParent, "BackdropTemplate")
    flyout:SetFrameStrata("DIALOG")
    UI.Hud(flyout, 0.92)
    flyout:SetClampedToScreen(true)
    flyout:Hide()
    tinsert(UISpecialFrames, "ForeverHubFlyout") -- Escape schliesst die Liste

    local logo = flyout:CreateTexture(nil, "OVERLAY")
    logo:SetTexture(UI.LOGO)
    logo:SetSize(14, 14)
    logo:SetPoint("TOPLEFT", 6, -4)
    local title = flyout:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", logo, "RIGHT", 4, 0)
    title:SetText(UI.NAME)

    flyout.rows = {}
    for i, e in ipairs(entries) do
        local row = CreateFrame("Button", nil, flyout)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 4, -20 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -4, -20 - (i - 1) * ROW_H)
        row:RegisterForClicks("AnyUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexture(e.icon)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(e.name)

        -- Klick und Tooltip an den Original-Knopf weiterreichen
        row:SetScript("OnClick", function(_, mouseButton)
            flyout:Hide()
            local onClick = e.button:GetScript("OnClick")
            if onClick then onClick(e.button, mouseButton) end
        end)
        row:SetScript("OnEnter", function(self)
            local onEnter = e.button:GetScript("OnEnter")
            if onEnter then
                onEnter(self)
            else
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine(e.name)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        flyout.rows[i] = row
    end

    -- unten: alle Rahmen entsperren/sperren (wie /fmove)
    local sep = flyout:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.15)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 8, -22 - #entries * ROW_H)
    sep:SetPoint("TOPRIGHT", -8, -22 - #entries * ROW_H)
    local move = CreateFrame("Button", nil, flyout)
    move:SetHeight(ROW_H)
    move:SetPoint("TOPLEFT", 4, -24 - #entries * ROW_H)
    move:SetPoint("TOPRIGHT", -4, -24 - #entries * ROW_H)
    move:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local moveIcon = move:CreateTexture(nil, "ARTWORK")
    moveIcon:SetSize(18, 18)
    moveIcon:SetPoint("LEFT", 4, 0)
    local moveLabel = move:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moveLabel:SetPoint("LEFT", moveIcon, "RIGHT", 6, 0)
    local function UpdateMoveRow()
        local unlocked = UI.AnyUnlocked()
        moveIcon:SetTexture(unlocked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
        moveLabel:SetText(unlocked and T("Alle sperren", "Lock all") or T("Alle verschieben", "Move all"))
    end
    move:SetScript("OnClick", function()
        flyout:Hide()
        UI.MoveAll()
    end)
    move:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(T("Alle Forever-Rahmen", "All Forever frames"))
        GameTooltip:AddLine(T("Entsperrt alle aktiven Addons zum Verschieben – nochmal klicken sperrt alle. Auch: /fmove",
            "Unlocks all active addons for moving – click again to lock all. Also: /fmove"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    move:SetScript("OnLeave", GameTooltip_Hide)
    flyout:SetScript("OnShow", UpdateMoveRow)
    flyout:SetSize(170, 26 + (#entries + 1) * ROW_H + 4)
end

local function ToggleFlyout()
    if not flyout then BuildFlyout() end
    if flyout:IsShown() then flyout:Hide() return end
    flyout:ClearAllPoints()
    -- je nach Lage des Knopfs nach links/rechts und oben/unten aufklappen
    local x, y = hubButton:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local vertical = (y and y > h / 2) and "TOP" or "BOTTOM"
    local horizontal = (x and x > w / 2) and "RIGHT" or "LEFT"
    local other = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
    flyout:SetPoint(vertical .. horizontal, hubButton, other[vertical] .. other[horizontal], 0, 0)
    flyout:Show()
end

local function BuildHubButton()
    hubButton = UI.MinimapButton({
        name = "ForeverHubMinimapButton",
        icon = UI.LOGO,
        title = UI.NAME,
        angle = function() return GetDB().angle end,
        setAngle = function(a) GetDB().angle = a end,
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                if flyout then flyout:Hide() end
                UI.MoveAll()
            else
                ToggleFlyout()
            end
        end,
        -- nur die Bedienung; welche Addons installiert sind, zeigt die ausgeklappte Liste
        lines = function()
            return { T("Linksklick: Forever-Core-Addons zeigen", "Left-click: show Forever Core addons"),
                T("Rechtsklick: alle Rahmen verschieben/sperren (/fmove)", "Right-click: move/lock all frames (/fmove)") }
        end,
    })
end

-- ab zwei Forever-Addons immer sammeln (Einzelknoepfe versteckt), sonst wie ohne ForeverHub.
-- "Minimap-Knopf ausblenden" (im Hub-Fenster) versteckt alle Forever-Knoepfe; Zugang dann ueber /forever.
local function ApplyMode()
    active = #entries >= 2
    local hidden = GetDB().hideButton
    if active and not hubButton then BuildHubButton() end
    if hubButton then hubButton:SetShown(active and not hidden) end
    for _, e in ipairs(entries) do
        e.button:SetShown(not active and not hidden)
    end
end

local function Setup()
    if _G.ForeverHub ~= hub then return end -- eine neuere Kopie ist zustaendig
    local before = #entries
    wipe(entries)
    for _, k in ipairs(KNOWN) do
        local button = _G[k.button]
        if button then
            entries[#entries + 1] = { name = k.name, button = button, icon = IconOf(button) }
            -- falls ein Addon seinen Knopf spaeter wieder einblendet: im Sammelmodus versteckt lassen
            if not button.ffHubHooked then
                button.ffHubHooked = true
                button:HookScript("OnShow", function(self)
                    if _G.ForeverHub and _G.ForeverHub.IsCollecting and _G.ForeverHub.IsCollecting() then self:Hide() end
                end)
            end
        end
    end
    -- Liste neu bauen, falls inzwischen weitere Addons dazugekommen sind
    if flyout and #entries ~= before then flyout:Hide() flyout = nil end
    ApplyMode()
end

-- true: Einzelknoepfe sollen versteckt bleiben (gesammelt oder ganz ausgeblendet)
function hub.IsCollecting() return active or GetDB().hideButton == true end

local function SafeSetup()
    local ok, err = pcall(Setup)
    if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then pcall(handler, err) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
    -- kurz warten, damit alle Addons ihre Knoepfe angelegt haben; spaeter nochmal nachsehen,
    -- falls ein Addon seinen Knopf erst verzoegert baut
    C_Timer.After(0.5, SafeSetup)
    C_Timer.After(3, SafeSetup)
end)

---------------------------------------------------------------------------
-- 3. Hub-Fenster: alle Forever-Addons auf einen Blick, Klick oeffnet das jeweilige Menue
---------------------------------------------------------------------------
local HUB_ROW_H = 38
local hubWindow

-- Addon installiert? (auch wenn es gerade deaktiviert ist)
local function IsInstalled(name)
    if not (C_AddOns and C_AddOns.GetAddOnInfo) then return false end
    local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, name)
    return ok and reason ~= "MISSING"
end

local function EntryOf(name)
    for _, e in ipairs(entries) do
        if e.name == name then return e end
    end
end

-- Menue eines Addons oeffnen = Linksklick auf seinen (evtl. versteckten) Minimap-Knopf
local function OpenAddon(e)
    local onClick = e and e.button:GetScript("OnClick")
    if onClick then onClick(e.button, "LeftButton") end
end

local function BuildHubWindow()
    local list = {}
    for _, k in ipairs(KNOWN) do
        if IsInstalled(k.name) then list[#list + 1] = k.name end
    end

    -- Fussbereich: Sprache (nur deutscher Client), Verschieben/Minimap, Hinweis
    local bottomH = UI.GERMAN_CLIENT and 122 or 92
    local f = UI.Window("ForeverHubWindow", UI.NAME, 420, 26 + 12 + math.max(#list, 1) * HUB_ROW_H + bottomH)
    hubWindow = f
    f.rows = {}

    for i, name in ipairs(list) do
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(HUB_ROW_H)
        row:SetPoint("TOPLEFT", 10, -26 - 8 - (i - 1) * HUB_ROW_H)
        row:SetPoint("TOPRIGHT", -10, -26 - 8 - (i - 1) * HUB_ROW_H)
        if i > 1 then
            local sep = row:CreateTexture(nil, "ARTWORK")
            sep:SetColorTexture(1, 1, 1, 0.06)
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", 4, 0)
            sep:SetPoint("TOPRIGHT", -4, 0)
        end

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 4, 0)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
        row.label:SetText(name)
        row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.note:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.note:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.note:SetJustifyH("LEFT")
        row.note:SetWordWrap(false)
        local ok, _, _, notes = pcall(C_AddOns.GetAddOnInfo, name)
        row.note:SetText(ok and notes or "")

        row.open = UI.Button(row, T("Öffnen", "Open"), 84, function()
            f:Hide()
            OpenAddon(EntryOf(name))
        end)
        row.open:SetPoint("RIGHT", -4, 0)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.status:SetPoint("RIGHT", -8, 0)

        function row.Update()
            local e = EntryOf(name)
            local loaded = C_AddOns.IsAddOnLoaded(name)
            row.icon:SetTexture(e and e.icon or UI.LOGO)
            row.icon:SetDesaturated(not e)
            row.label:SetTextColor(e and 1 or 0.5, e and 0.82 or 0.5, e and 0 or 0.5)
            row.open:SetShown(e ~= nil)
            row.status:SetShown(e == nil)
            row.status:SetText(loaded and T("ohne Menü", "no menu") or T("deaktiviert", "disabled"))
        end
        f.rows[i] = row
    end

    if #list == 0 then
        UI.Hint(f, 16, -40, nil, T("Keine Forever-Addons gefunden.", "No Forever addons found."))
    end

    -- unten: alle verschieben/sperren und Minimap-Knopf
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 10, bottomH - 10)
    line:SetPoint("BOTTOMRIGHT", -10, bottomH - 10)

    -- Sprache fuer alle Forever-Addons (wirkt nach dem Neuladen)
    local lang
    if UI.GERMAN_CLIENT then
        local LANGS = {
            { key = "AUTO", label = T("Automatisch (Client)", "Automatic (client)") },
            { key = "deDE", label = "Deutsch" },
            { key = "enUS", label = "English" },
        }
        local function Current() return GetDB().language or "AUTO" end
        local function LabelOf(key)
            for _, l in ipairs(LANGS) do if l.key == key then return l.label end end
            return key
        end
        local langLabel = UI.Text(f, "label", T("Sprache", "Language"))
        langLabel:SetPoint("BOTTOMLEFT", 16, 84)
        lang = UI.AddArrow(UI.Button(f, "", 170))
        lang:SetPoint("LEFT", langLabel, "RIGHT", 10, 0)
        local reload = UI.Button(f, T("Neu laden", "Reload"), 90, function() ReloadUI() end)
        reload:SetPoint("LEFT", lang, "RIGHT", 8, 0)
        reload:Hide()
        lang:SetScript("OnClick", function(self)
            UI.ChoiceMenu(self, LANGS, Current, function(key)
                GetDB().language = key ~= "AUTO" and key or nil
                self:SetText(LabelOf(Current()))
                reload:Show()
                UI.Chat("Forever", T("Die Sprache gilt nach dem Neuladen für alle Forever-Addons.",
                    "The language applies to all Forever addons after reloading."))
            end)
        end)
        function lang.Load() lang:SetText(LabelOf(Current())) end
    end

    local move = UI.Button(f, "", 150, function()
        f:Hide()
        UI.MoveAll()
    end)
    move:SetPoint("BOTTOMLEFT", 14, 48)

    local mm = UI.Check(f, nil, nil, T("Minimap-Knopf anzeigen", "Show minimap button"), function(checked)
        GetDB().hideButton = not checked or nil
        ApplyMode()
    end)
    mm:SetPoint("LEFT", move, "RIGHT", 18, 0)

    local hint = UI.Hint(f, nil, nil, nil, T("/forever öffnet dieses Fenster · /fmove verschiebt alle Rahmen · /forever reset holt die Knöpfe zurück",
        "/forever opens this window · /fmove moves all frames · /forever reset brings the buttons back"))
    hint:SetPoint("BOTTOMLEFT", 16, 14)
    hint:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    hint:SetWordWrap(true)

    f:SetScript("OnShow", function()
        SafeSetup() -- falls seit dem Login Addons/Knoepfe dazugekommen sind
        for _, row in ipairs(f.rows) do row.Update() end
        move:SetText(UI.AnyUnlocked() and T("Alle sperren", "Lock all") or T("Alle verschieben", "Move all"))
        mm:SetChecked(not GetDB().hideButton)
        if lang then lang.Load() end
    end)
end

function hub.ToggleWindow()
    if not hubWindow then BuildHubWindow() end
    hubWindow:SetShown(not hubWindow:IsShown())
end

-- /forever: Hub-Fenster · /forever reset: Sammelknopf zuruecksetzen und wieder an die Minimap holen
SLASH_FOREVERHUB1 = "/forever"
SLASH_FOREVERHUB2 = "/fhub"
SlashCmdList["FOREVERHUB"] = function(msg)
    if _G.ForeverHub ~= hub then return end
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        local db = GetDB()
        db.angle = 195
        db.hideButton = nil
        SafeSetup()
        if hubButton then hubButton.UpdatePosition() end
        UI.Chat("Forever", active
            and T("Sammelknopf zurückgesetzt.", "Collector button reset.")
            or T("Minimap-Knöpfe wieder eingeblendet.", "Minimap buttons shown again."))
    else
        hub.ToggleWindow()
    end
end
