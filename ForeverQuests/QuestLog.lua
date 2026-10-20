local addonName, ns = ...

---------------------------------------------------------------------------
-- Questlog an der Weltkarte im Forever-Stil
--
-- Die Karte selbst bleibt Blizzards Karte (Questie-Symbole, Kartenklicks usw. unverändert). Neu:
--  * Rahmen, Titelleiste und Navigationsleiste der Karte im flachen Forever-Stil; das Fenster lässt sich an der
--    Titelleiste verschieben und an der Ecke unten rechts größer/kleiner ziehen (Rechtsklick Titel = zurücksetzen)
--  * rechts statt Blizzards Questliste unsere eigene: alle Quests nach Gebiet, mit denselben Zeilen,
--    Tooltips, Rechtsklick-Menü (inkl. Questie), Angeheftet, "Gemeinsam" und Filtern wie der Tracker,
--    dazu Suche, Anzahl, Dungeon-Knopf und ein Häkchen "verfolgen" je Quest
--  * Klick auf eine Quest: eigene Detailansicht (Ziele, Beschreibung, Belohnungen, Knöpfe)
--
-- Blizzard-Funktionen werden nicht ersetzt: unsere Fenster liegen nur über Blizzards Liste bzw. Detailansicht,
-- Blizzards Rahmen werden nur unsichtbar gemacht (Deckkraft 0). Blizzards Detailansicht läuft unsichtbar weiter,
-- unsere folgt ihr (öffnen/zurück) – so bleiben Karte und Questlog auch im Kampf fehlerfrei.
-- Abschaltbar im Menü ("Questlog im Forever-Stil", gilt nach /reload).
---------------------------------------------------------------------------

local Style
local panel, scrollFrame, content, searchBox, searchHint, countText, filterButton
local logView
local updateQueued = false

local FILTER_KEY = "logHiddenFilters" -- im Questlog ausgeblendete Gruppen (unabhängig vom Tracker)
local HEADER_HEIGHT = 28
local MIN_SCALE, MAX_SCALE = 0.5, 1.6

-- Region nur unsichtbar machen (nicht verstecken/umbauen: Blizzard-Code bleibt unberührt)
local function Fade(region)
    if region and region.SetAlpha then region:SetAlpha(0) end
end

-- 1-px-Rand aus vier Flächen um einen Rahmen (für Knöpfe, auf denen kein Backdrop sitzt)
local function AddEdges(frame, color, layer)
    local edges = {}
    for _, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local edge = frame:CreateTexture(nil, layer or "BORDER")
        edge:SetColorTexture(unpack(color))
        edge:SetPoint(spec[1])
        edge:SetPoint(spec[2])
        if spec[3] then edge:SetHeight(1) else edge:SetWidth(1) end
        edges[#edges + 1] = edge
    end
    return edges
end

-- Titelleiste im Forever-Stil (dunkel, goldene Linie unten)
local function HeaderBar(parent, height)
    local color = Style.COLOR
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(height)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(unpack(color.header))
    local accentLine = header:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("BOTTOMLEFT")
    accentLine:SetPoint("BOTTOMRIGHT")
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(color.accent[1], color.accent[2], color.accent[3], 0.6)
    return header
end

---------------------------------------------------------------------------
-- Weltkarte: Rahmen, Titel, Navigationsleiste
---------------------------------------------------------------------------

-- Knopf der Navigationsleiste ("Welt", "Kalimdor", "Orgrimmar"): flach statt Blizzard-Pfeilform
local function SkinNavButton(button)
    if not button or button.fqSkinned then return end
    button.fqSkinned = true
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if button[getter] then Fade(button[getter](button)) end
    end
    -- weitere Blizzard-Flächen des Knopfs (Pfeilspitze, Verzierung); Text und Pfeil-Knopf bleiben
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then Fade(region) end
    end
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 1, -2)
    bg:SetPoint("BOTTOMRIGHT", -1, 2)
    bg:SetColorTexture(unpack(Style.COLOR.button))
    local edgeHost = CreateFrame("Frame", nil, button)
    edgeHost:SetPoint("TOPLEFT", 1, -2)
    edgeHost:SetPoint("BOTTOMRIGHT", -1, 2)
    edgeHost:SetFrameLevel(button:GetFrameLevel())
    local edges = AddEdges(edgeHost, Style.COLOR.border)
    button:HookScript("OnEnter", function()
        bg:SetColorTexture(unpack(Style.COLOR.buttonHover))
        local a = Style.COLOR.accent
        for _, edge in ipairs(edges) do edge:SetColorTexture(a[1], a[2], a[3], 0.9) end
    end)
    button:HookScript("OnLeave", function()
        bg:SetColorTexture(unpack(Style.COLOR.button))
        for _, edge in ipairs(edges) do edge:SetColorTexture(unpack(Style.COLOR.border)) end
    end)
    local text = button.text or button.Text or (button.GetFontString and button:GetFontString())
    if text and text.SetTextColor then text:SetTextColor(0.95, 0.95, 0.95) end
end

local function SkinNavBar(navBar)
    if not navBar then return end
    for _, region in ipairs({ navBar:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then Fade(region) end
    end
    for _, key in ipairs({ "overlay", "InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
        "InsetBorderLeft", "InsetBorderRight", "Inset" }) do
        Fade(navBar[key])
    end
    if navBar.overlay then
        for _, region in ipairs({ navBar.overlay:GetRegions() }) do Fade(region) end
    end
    SkinNavButton(navBar.homeButton)
    for _, button in ipairs(navBar.navList or {}) do SkinNavButton(button) end
end

-- Position und Größe der Karte (gespeichert in Bildschirm-Einheiten, damit die Ecke oben links beim
-- Größerziehen stehen bleibt). Im Vollbild ("maximiert") bestimmt Blizzard selbst.
local grip
local function IsMaximized(map)
    return map.IsMaximized and map:IsMaximized() or false
end

-- Breite des Questlogs rechts neben der Karte (0, wenn er zugeklappt ist)
local function SidePanelWidth(map)
    local log = map.QuestLog or _G.QuestMapFrame
    if log and log:IsShown() then return map.questLogWidth or log:GetWidth() or 0 end
    return 0
end

-- Fenstergröße der Karte frei setzen: Blizzard merkt sich die Kartengröße im Fenstermodus in minimizedWidth/-Height
-- (ohne Questlog) und setzt sie beim Öffnen/Auf-/Zuklappen des Questlogs daraus neu – darum dort mit ändern.
-- width = Breite der Karte ohne Questlog, height = Höhe
local lastCanvasUpdate = 0
local function SetMapSize(map, width, height, force)
    if not map.fqOrigSize then map.fqOrigSize = { map.minimizedWidth, map.minimizedHeight } end
    map.minimizedWidth, map.minimizedHeight = width, height
    map:SetSize(width + SidePanelWidth(map), height)
    -- Karte im Fenster neu einpassen (beim Ziehen höchstens 20-mal je Sekunde)
    local now = GetTime()
    if map.OnFrameSizeChanged and (force or now - lastCanvasUpdate > 0.05) then
        lastCanvasUpdate = now
        pcall(map.OnFrameSizeChanged, map)
    end
end

local function ApplyMapPlacement()
    local map = _G.WorldMapFrame
    if not map or not ns.db then return end
    local maximized = IsMaximized(map)
    if grip then grip:SetShown(not maximized) end
    if maximized then return end
    local scale = ns.db.mapScale or 1
    if math.abs(map:GetScale() - scale) > 0.001 then map:SetScale(scale) end
    local size = ns.db.mapSize
    if size and size.w and size.h then SetMapSize(map, size.w, size.h, true) end
    local pos = ns.db.mapPos
    if pos then
        map:ClearAllPoints()
        map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x / scale, pos.y / scale)
    end
end

local function SaveMapPlacement()
    local map = _G.WorldMapFrame
    local left, top = map:GetLeft(), map:GetTop()
    if not (left and top) then return end
    local scale = map:GetScale()
    ns.db.mapPos = { x = left * scale, y = top * scale }
    ns.db.mapScale = scale
    if map.fqOrigSize then ns.db.mapSize = { w = map.minimizedWidth, h = map.minimizedHeight } end
end

local function ResetMapPlacement()
    local map = _G.WorldMapFrame
    ns.db.mapPos, ns.db.mapScale, ns.db.mapSize = nil, nil, nil
    if IsMaximized(map) then return end
    map:SetScale(1)
    if map.fqOrigSize and map.fqOrigSize[1] then SetMapSize(map, map.fqOrigSize[1], map.fqOrigSize[2], true) end
    -- Blizzard setzt die Karte an ihren Standardplatz
    if type(_G.UpdateUIPanelPositions) == "function" then pcall(_G.UpdateUIPanelPositions, map) end
end

local function SetupMapMoving(map, top)
    map:SetMovable(true)
    map:SetClampedToScreen(true)
    top:EnableMouse(true)
    top:RegisterForDrag("LeftButton")
    top:SetScript("OnDragStart", function()
        if IsMaximized(map) then return end
        map:StartMoving()
    end)
    top:SetScript("OnDragStop", function()
        map:StopMovingOrSizing()
        if not IsMaximized(map) then SaveMapPlacement() end
    end)
    top:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ResetMapPlacement() end
    end)
    top:SetScript("OnEnter", function(self)
        local tip = Style.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine(ns.L("TIP_MAP_MOVE"), 1, 1, 1, true)
        tip:Show()
    end)
    top:SetScript("OnLeave", function() Style.GetTooltip():Hide() end)

    -- Griff unten rechts (Ecke oben links bleibt stehen):
    --   ziehen       = Breite und Höhe frei ändern
    --   Shift+ziehen = alles im gleichen Verhältnis größer/kleiner (Skalierung)
    grip = CreateFrame("Button", "ForeverQuestsMapGrip", map)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(map:GetFrameLevel() + 200)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self)
        local uiScale = UIParent:GetEffectiveScale()
        local cursorX, cursorY = GetCursorPosition()
        local scale = map:GetScale()
        self.start = { x = cursorX / uiScale, y = cursorY / uiScale, scale = scale, left = map:GetLeft() * scale,
            top = map:GetTop() * scale, width = map:GetWidth() * scale,
            mapWidth = map.minimizedWidth or (map:GetWidth() - SidePanelWidth(map)), mapHeight = map:GetHeight() }
        local scaling = IsShiftKeyDown()
        self:SetScript("OnUpdate", function()
            local s = self.start
            local x, y = GetCursorPosition()
            x, y = x / uiScale, y / uiScale
            if scaling then
                local newScale = s.scale * (s.width + (x - s.x)) / s.width
                newScale = math.max(MIN_SCALE, math.min(MAX_SCALE, newScale))
                map:SetScale(newScale)
            else
                -- Mausweg in Kartenpunkte umrechnen (die Karte ist evtl. skaliert); nach unten ziehen = höher
                local maxWidth = UIParent:GetWidth() / s.scale - SidePanelWidth(map)
                local maxHeight = UIParent:GetHeight() / s.scale
                local width = math.max(400, math.min(maxWidth, s.mapWidth + (x - s.x) / s.scale))
                local height = math.max(300, math.min(maxHeight, s.mapHeight + (s.y - y) / s.scale))
                SetMapSize(map, math.floor(width + 0.5), math.floor(height + 0.5))
            end
            local current = map:GetScale()
            map:ClearAllPoints()
            map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.left / current, s.top / current)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if map.fqOrigSize then pcall(map.OnFrameSizeChanged or function() end, map) end
        SaveMapPlacement()
    end)
    grip:SetScript("OnEnter", function(self)
        local tip = Style.GetTooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(ns.L("TIP_MAP_SCALE"), 1, 1, 1, true)
        tip:Show()
    end)
    grip:SetScript("OnLeave", function() Style.GetTooltip():Hide() end)

    -- Blizzard setzt die Karte beim Öffnen und beim Wechsel Vollbild/Fenster neu: danach unsere Werte
    map:HookScript("OnShow", function() C_Timer.After(0, ApplyMapPlacement) end)
    if type(_G.UpdateUIPanelPositions) == "function" then
        hooksecurefunc("UpdateUIPanelPositions", function(frame)
            if frame == nil or frame == map then ApplyMapPlacement() end
        end)
    end
    for _, method in ipairs({ "Maximize", "Minimize" }) do
        if type(map[method]) == "function" then
            hooksecurefunc(map, method, function() C_Timer.After(0, ApplyMapPlacement) end)
        end
    end
    -- Questlog auf-/zugeklappt: Blizzard setzt die Breite neu – unsere Kartengröße wieder anwenden
    local questLog = map.QuestLog or _G.QuestMapFrame
    if questLog then
        for _, script in ipairs({ "OnShow", "OnHide" }) do
            questLog:HookScript(script, function() C_Timer.After(0, ApplyMapPlacement) end)
        end
    end
    ApplyMapPlacement()
end

local function SkinWorldMap()
    local map = _G.WorldMapFrame
    if not map or map.fqSkinned then return end
    map.fqSkinned = true
    local color = Style.COLOR
    local border = map.BorderFrame

    -- eigener dunkler Hintergrund und 1-px-Rand um das ganze Kartenfenster
    local skin = CreateFrame("Frame", "ForeverQuestsMapSkin", map, "BackdropTemplate")
    skin:SetAllPoints(map)
    skin:SetFrameLevel(math.max(0, map:GetFrameLevel()))
    Style.SetFlat(skin, color.background)

    -- Titelleiste mit goldener Linie wie bei allen Forever-Fenstern; liegt über Blizzards (unsichtbarem) Rahmen,
    -- unter dessen Knöpfen (Schließen, Vollbild); zum Verschieben der Karte
    local top = CreateFrame("Frame", nil, border or map)
    top:SetPoint("TOPLEFT", map, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", map, "TOPRIGHT", -1, -1)
    top:SetHeight(22)
    top:SetFrameLevel(math.max(0, (border or map):GetFrameLevel()))
    local band = top:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    band:SetColorTexture(unpack(color.header))
    local line = top:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(color.accent[1], color.accent[2], color.accent[3], 0.6)

    -- Blizzards Steinrahmen, Porträt (Buch oben links) und Kopf-Verzierung unsichtbar
    if border then
        Fade(border.NineSlice)
        Fade(border.Bg)
        Fade(border.TopTileStreaks)
        Fade(border.PortraitContainer)
        Fade(border.portrait)
        if border.TitleContainer and border.TitleContainer.TitleText then
            border.TitleContainer.TitleText:SetTextColor(1, 1, 1)
        end
        Fade(border.InsetBorderTop)
    end
    Fade(map.NineSlice)
    Fade(map.Bg)
    Fade(map.PortraitContainer)
    top.fqOwn = true

    -- Alle übrigen Blizzard-Flächen von Fenster und Rahmen (Eck-Verzierungen, Kanten): nur Texturen, kein Text,
    -- keine Knöpfe, nicht die Karte selbst (ScrollContainer) und nicht unsere eigenen Teile
    local function FadeTextures(frame)
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "Texture" then Fade(region) end
        end
    end
    FadeTextures(map)
    if border then
        FadeTextures(border)
        for _, child in ipairs({ border:GetChildren() }) do
            local objectType = child.GetObjectType and child:GetObjectType()
            if not child.fqOwn and objectType ~= "Button" and objectType ~= "CheckButton" then FadeTextures(child) end
        end
    end
    local questMap = _G.QuestMapFrame
    if questMap then
        FadeTextures(questMap)
        Fade(questMap.Background)
        Fade(questMap.BorderFrame)
    end

    -- Weitere Rahmen um die Karte (z. B. Blizzards zweiter Rahmen fürs kleine Fenster mit Stein-/Gold-Ecken):
    -- alle Kind-Rahmen des Fensters bis zwei Ebenen tief – außer Karte, Questlog, Navigationsleiste, Knöpfen,
    -- Kartenknöpfen (overlayFrames) und unseren eigenen Teilen
    local keep = { [map.ScrollContainer or false] = true, [questMap or false] = true, [map.NavBar or false] = true,
        [skin] = true, [top] = true }
    for _, overlay in ipairs(map.overlayFrames or {}) do keep[overlay] = true end
    local function FadeDecorations(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            local objectType = child.GetObjectType and child:GetObjectType()
            if not keep[child] and not child.fqOwn and objectType == "Frame" then
                FadeTextures(child)
                if child.NineSlice then Fade(child.NineSlice) end
                if depth > 1 then FadeDecorations(child, depth - 1) end
            end
        end
    end
    FadeDecorations(map, 2)
    for _, key in ipairs({ "MiniBorderFrame", "BorderFrameMini", "Inset", "InsetBorder" }) do
        local frame = map[key]
        if frame then
            FadeTextures(frame)
            if frame.NineSlice then Fade(frame.NineSlice) end
        end
    end

    -- Schließen-Knopf kleiner; Vollbild-Knopf ganz weg (Karte bleibt im Fenster, verschieb- und skalierbar)
    local close = border and border.CloseButton or map.CloseButton
    if close and close.SetScale then close:SetScale(0.75) end
    local maximize = (border and border.MaximizeMinimizeFrame) or map.MaximizeMinimizeFrame
    if maximize then
        maximize:Hide()
        maximize:HookScript("OnShow", maximize.Hide)
    end
    if IsMaximized(map) and map.Minimize then pcall(map.Minimize, map) end

    -- Navigationsleiste; neue Knöpfe (beim Hineinzoomen) gleich mitgestalten
    SkinNavBar(map.NavBar)
    if type(_G.NavBar_AddButton) == "function" then
        hooksecurefunc("NavBar_AddButton", function(self)
            if self == map.NavBar then SkinNavBar(self) end
        end)
    end

    SetupMapMoving(map, top)
end

---------------------------------------------------------------------------
-- Questie-Knopf in der Navigationsleiste (rechts, neben "Welt › Kalimdor › …") statt Questies eigenem Kartenknopf.
-- Gleiche Bedienung: Linksklick Questie an/aus, Rechtsklick Questies Menü. Questies Knopf wird nur unsichtbar.
---------------------------------------------------------------------------
local questieMapButton
local function QuestieOriginalButton()
    local questie = _G.Questie
    return type(questie) == "table" and questie.WorldMap and questie.WorldMap.Button or nil
end

-- Schrift weiß bei eingeblendeten Questie-Symbolen, grau bei ausgeblendeten; Knopf ganz rechts in der Leiste
-- (rechts bündig mit der Karte, auf Höhe der Navigationsleiste – beides neu berechnet, falls sich die Karte ändert)
local function UpdateQuestieMapButton()
    if not questieMapButton then return end
    local enabled = _G.Questie and _G.Questie.db and _G.Questie.db.profile.enabled ~= false
    questieMapButton:GetFontString():SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5)
    local map = _G.WorldMapFrame
    local navBar, container = map and map.NavBar, map and map.ScrollContainer
    questieMapButton:ClearAllPoints()
    if navBar and container and navBar:GetRight() and container:GetRight() then
        questieMapButton:SetPoint("RIGHT", navBar, "RIGHT", container:GetRight() - navBar:GetRight(), 0)
    elseif navBar then
        questieMapButton:SetPoint("RIGHT", navBar, "RIGHT", -2, 0)
    end
end

local function SetupQuestieMapButton()
    local map = _G.WorldMapFrame
    local original = QuestieOriginalButton()
    if questieMapButton or not map or not original then return questieMapButton ~= nil end
    local anchor = map.NavBar or map
    questieMapButton = Style.CreateButton(map, "Questie", 64, 22, nil, nil)
    questieMapButton:SetFrameLevel(anchor:GetFrameLevel() + 10)
    questieMapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    map:HookScript("OnSizeChanged", UpdateQuestieMapButton)
    if map.ScrollContainer then map.ScrollContainer:HookScript("OnSizeChanged", UpdateQuestieMapButton) end
    questieMapButton:SetScript("OnClick", function(self, button)
        local handler = original.OnMouseDown or original:GetScript("OnMouseDown")
        if handler then pcall(handler, original, button) end
        UpdateQuestieMapButton()
        if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
    end)
    questieMapButton.tooltip = function(tip)
        local profile = _G.Questie and _G.Questie.db and _G.Questie.db.profile
        tip:AddLine("Questie", 1, 0.82, 0)
        tip:AddLine(ns.L(profile and profile.enabled == false and "TIP_QUESTIE_SHOW" or "TIP_QUESTIE_HIDE"), 1, 1, 1)
        tip:AddLine(ns.L("TIP_QUESTIE_MENU"), 1, 1, 1)
    end
    -- Questies eigener Knopf: unsichtbar und ohne Maus (bleibt angelegt, damit Questie nichts vermisst)
    original:SetAlpha(0)
    original:EnableMouse(false)
    hooksecurefunc(original, "Show", function(self) self:SetAlpha(0) end)
    UpdateQuestieMapButton()
    map:HookScript("OnShow", UpdateQuestieMapButton)
    return true
end

-- Questie legt seinen Knopf erst beim Start an: ein paar Mal nachsehen
local function TrySetupQuestieMapButton(tries)
    if type(_G.Questie) ~= "table" then return end
    if SetupQuestieMapButton() then return end
    if (tries or 0) < 20 then C_Timer.After(1, function() TrySetupQuestieMapButton((tries or 0) + 1) end) end
end

-- /fq ecke: Maus auf eine Stelle der Karte legen, Befehl abschicken -> zeigt alle sichtbaren Texturen genau dort
-- (zum Finden von Blizzard-Verzierungen, die noch durchscheinen)
function ns.DebugMapCorner()
    local prefix = ns.ChatPrefix() .. ": "
    local found = 0
    local function Walk(frame, depth)
        if depth > 8 or not frame.GetRegions then return end
        for _, region in ipairs({ frame:GetRegions() }) do
            -- sichtbar = eigene Deckkraft mal die des Rahmens (Texturen haben keine "effektive" Deckkraft)
            local alpha = (region.GetAlpha and region:GetAlpha() or 1) * (frame.GetEffectiveAlpha and frame:GetEffectiveAlpha() or 1)
            if region.GetObjectType and region:GetObjectType() == "Texture" and region:IsVisible()
                and alpha > 0.05 and region:IsMouseOver() then
                found = found + 1
                if found <= 25 then
                    print(prefix .. (region:GetDebugName() or "?") .. "  " .. tostring(region:GetAtlas() or region:GetTexture()))
                end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsVisible() then Walk(child, depth + 1) end
        end
    end
    if _G.WorldMapFrame then Walk(_G.WorldMapFrame, 0) end
    if found == 0 then print(prefix .. "keine Textur unter der Maus") end
end

---------------------------------------------------------------------------
-- Unsere Questliste
---------------------------------------------------------------------------

-- Bereich von Blizzards Questliste (darüber legen wir unsere)
local function QuestsArea()
    local questMap = _G.QuestMapFrame
    if questMap and questMap.QuestsFrame then return questMap.QuestsFrame end
    local scroll = _G.QuestScrollFrame
    return scroll and scroll:GetParent() or nil
end

local function SearchText()
    local text = searchBox and strtrim(searchBox:GetText() or "") or ""
    return text ~= "" and text or nil
end

-- Fußzeile: abgabebereite Quests im Log (auch nicht verfolgte) und die Erfahrung, die das Abgeben bringt
local readyFooter
local function UpdateReadyFooter()
    if not readyFooter then return end
    local count, xp = 0, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 and C_QuestLog.IsComplete(info.questID) then
            count = count + 1
            xp = xp + (GetQuestLogRewardXP and GetQuestLogRewardXP(info.questID) or 0)
        end
    end
    if count == 0 then
        readyFooter.text:SetText("|cff8a8a8a" .. ns.L("LOG_READY_NONE") .. "|r")
    else
        local xpText = xp > 0 and ("  ·  |cff9999ff+" .. (BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp) .. " "
            .. ns.L("LOG_XP") .. "|r") or ""
        readyFooter.text:SetText(ns.L("LOG_READY", count) .. xpText)
    end
end

local function UpdateCount()
    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    numQuests = numQuests or 0
    local max = (C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or _G.MAX_QUESTS or 25
    local full = numQuests >= max
    countText:SetText((full and "|cffff4040" or "|cffbbbbbb") .. numQuests .. "/" .. max .. "|r")
end

local RenderDetails, details -- Detailansicht (weiter unten)
local OpenLogMenu -- Rädchen-Menü (weiter unten)

function ns.UpdateQuestLog()
    updateQueued = false
    if details and details:IsVisible() then RenderDetails() end
    if not panel or not panel:IsVisible() then return end
    local width = scrollFrame:GetWidth()
    if not width or width < 10 then
        -- noch nicht angeordnet (erster Aufbau): gleich danach noch einmal
        if not updateQueued then
            updateQueued = true
            C_Timer.After(0, ns.UpdateQuestLog)
        end
        return
    end
    local search = SearchText()
    local filtered = ns.QuestList.HasFilters(FILTER_KEY)
    local _, height = ns.QuestList.Render(logView, { all = true, filterKey = FILTER_KEY, search = search }, width,
        function()
            if search then return ns.L("LOG_EMPTY_SEARCH") end
            if filtered then return ns.L("EMPTY_FILTER") end
            return ns.L("EMPTY_LOG")
        end)
    filterButton:SetText(filtered and ("|cff00ff00" .. ns.L("BTN_FILTER") .. "|r") or ns.L("BTN_FILTER"))
    UpdateCount()
    UpdateReadyFooter()
    local maxScroll = math.max(0, height - scrollFrame:GetHeight())
    if scrollFrame:GetVerticalScroll() > maxScroll then scrollFrame:SetVerticalScroll(maxScroll) end
    if scrollFrame.UpdateBar then scrollFrame.UpdateBar() end
end

local function RequestLogUpdate()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.05, ns.UpdateQuestLog)
end

-- Maus über einer Quest: alle ihre Marker auf der Karte hervorheben (Questie-Symbole größer, andere blass;
-- dazu Blizzards eigene Hervorhebung des Questgebiets)
local function HighlightOnMap(questID)
    if ns.QuestieHover then ns.QuestieHover(questID) end
    local map = _G.WorldMapFrame
    if not map then return end
    if questID and map.SetHighlightedQuestID then
        pcall(map.SetHighlightedQuestID, map, questID)
    elseif map.ClearHighlightedQuestID then
        pcall(map.ClearHighlightedQuestID, map)
    end
end

-- Scrollbereich mit Mausrad und schlankem Rollbalken (rechts, nur wenn der Inhalt länger ist);
-- Balken und Mausrad bleiben gekoppelt. Gibt ScrollFrame und Inhalt zurück
local function CreateScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local color = Style.COLOR
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(5)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 0, 0)
    bar:SetFrameLevel(scroll:GetFrameLevel() + 5)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0, 0, 0, 0.35)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(5, 40)
    thumb:SetColorTexture(color.border[1] + 0.2, color.border[2] + 0.2, color.border[3] + 0.2, 1)
    bar:SetThumbTexture(thumb)
    -- Maus darüber: Griff in Gold (wie Knöpfe und Regler der Forever-Fenster)
    bar:SetScript("OnEnter", function() thumb:SetColorTexture(color.accent[1], color.accent[2], color.accent[3], 0.9) end)
    bar:SetScript("OnLeave", function()
        thumb:SetColorTexture(color.border[1] + 0.2, color.border[2] + 0.2, color.border[3] + 0.2, 1)
    end)
    bar:Hide()

    local syncing = false
    local function MaxScroll() return math.max(0, child:GetHeight() - scroll:GetHeight()) end
    -- Bereich und Griffgröße an den Inhalt anpassen (nach jedem Neuaufbau und bei Größenänderung)
    function scroll.UpdateBar()
        local maxScroll = MaxScroll()
        if maxScroll < 1 then
            bar:Hide()
            if scroll:GetVerticalScroll() > 0 then scroll:SetVerticalScroll(0) end
            return
        end
        local h, total = scroll:GetHeight(), child:GetHeight()
        thumb:SetHeight(math.max(20, h * h / math.max(total, 1)))
        syncing = true
        bar:SetMinMaxValues(0, maxScroll)
        bar:SetValue(math.min(scroll:GetVerticalScroll(), maxScroll))
        syncing = false
        bar:Show()
    end
    -- Balken gezogen -> Liste folgt
    bar:SetScript("OnValueChanged", function(_, value)
        if syncing then return end
        scroll:SetVerticalScroll(math.min(MaxScroll(), math.max(0, value)))
    end)
    -- Liste gerollt (Mausrad, Code) -> Balken folgt
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        if not bar:IsShown() then return end
        syncing = true
        bar:SetValue(offset)
        syncing = false
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.min(MaxScroll(), math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(_, delta)
        scroll:SetVerticalScroll(math.min(MaxScroll(), math.max(0, scroll:GetVerticalScroll() - delta * 30)))
    end)
    child:SetScript("OnSizeChanged", function() scroll.UpdateBar() end)
    scroll:HookScript("OnSizeChanged", function() scroll.UpdateBar() end)
    scroll.bar = bar
    return scroll, child
end

-- Alle Quests im Log verfolgen bzw. keine (Blizzard begrenzt die Zahl verfolgter Quests, darüber hinaus passiert nichts)
local function WatchAll(watch)
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID and info.questID > 0 then
            local watched = C_QuestLog.GetQuestWatchType(info.questID) ~= nil
            if watch and not watched and C_QuestLog.AddQuestWatch then
                C_QuestLog.AddQuestWatch(info.questID)
            elseif not watch and watched then
                C_QuestLog.RemoveQuestWatch(info.questID)
            end
        end
    end
    ns.RequestUpdate()
end

function OpenLogMenu(owner)
    local items = { { title = ns.L("LOG_MENU_TITLE") } }
    -- mit Questie: dessen Kartensymbole (statt Blizzards Kartenmenü, das mit Questie nichts bewirkt)
    local toggles = ns.GetQuestieMapToggles and ns.GetQuestieMapToggles()
    if toggles then
        for _, entry in ipairs({
            { "LOG_MENU_Q_AVAILABLE", toggles.available }, { "LOG_MENU_Q_OBJECTIVES", toggles.objectives },
            { "LOG_MENU_Q_TURNINS", toggles.turnins }, { "LOG_MENU_Q_LOWLEVEL", toggles.lowLevel },
        }) do
            table.insert(items, { checkbox = true, text = ns.L(entry[1]), checked = entry[2].checked,
                onClick = entry[2].onClick })
        end
    end
    table.insert(items, {
        checkbox = true,
        text = ns.L("LOG_MENU_MARKERS"),
        checked = function() return ns.BlizzardQuestMarkersShown and ns.BlizzardQuestMarkersShown() or false end,
        onClick = function()
            if ns.SetBlizzardQuestMarkers then ns.SetBlizzardQuestMarkers(not ns.BlizzardQuestMarkersShown()) end
        end,
    })
    table.insert(items, { divider = true })
    table.insert(items, { text = ns.L("LOG_MENU_TRACK_ALL"), onClick = function() WatchAll(true) end })
    table.insert(items, { text = ns.L("LOG_MENU_TRACK_NONE"), onClick = function() WatchAll(false) end })
    table.insert(items, { divider = true })
    -- Einstellungen von ForeverQuests (gleiches Fenster wie /fq bzw. das Zahnrad am Tracker)
    table.insert(items, { text = ns.L("LOG_MENU_OPTIONS"), onClick = function() if ns.ToggleOptions then ns.ToggleOptions() end end })
    ns.Style.ShowMenu(owner, items)
end

-- Blizzards Kartenmenü (gelber Pfeil oben rechts: Questziele, Queststufen, niedrigstufige Quests …) steuert nur
-- Blizzards Marker – mit Questie sind die aus, das Menü bewirkt dann nichts. Darum mit Questie ausblenden; die
-- Questie-Schalter stehen in unserem Rädchen. Erkennung: Aufklappknopf der Karte oben rechts.
local function FadeMapTrackingMenu()
    local map = _G.WorldMapFrame
    if not map or type(_G.Questie) ~= "table" then return end
    for _, frame in ipairs(map.overlayFrames or {}) do
        local point = frame.GetPoint and frame:GetPoint(1)
        local name = frame.GetDebugName and frame:GetDebugName() or ""
        local isFloor = name:find("Floor") ~= nil
        if not isFloor and (name:find("Tracking") or (frame.SetupMenu and point == "TOPRIGHT")) then
            Fade(frame)
            if frame.EnableMouse then frame:EnableMouse(false) end
        end
    end
end

-- Blizzards Rädchen (Questlog-Einstellungen) unsichtbar und ohne Maus – ersetzt durch unseres
local function FadeBlizzardSettings(area)
    for _, holder in ipairs({ area, _G.QuestScrollFrame, _G.QuestMapFrame }) do
        local dropdown = holder and (holder.SettingsDropdown or holder.SettingsButton)
        if dropdown then
            Fade(dropdown)
            if dropdown.EnableMouse then dropdown:EnableMouse(false) end
        end
    end
    -- Blizzards Rollbalken der Questliste: gehört zu Blizzards Liste unter unserer und bewegt nichts
    local blizzScroll = _G.QuestScrollFrame
    local blizzBar = blizzScroll and (blizzScroll.ScrollBar or (blizzScroll.GetName and blizzScroll:GetName()
        and _G[blizzScroll:GetName() .. "ScrollBar"]))
    if blizzBar then
        Fade(blizzBar)
        if blizzBar.EnableMouse then blizzBar:EnableMouse(false) end
        if blizzBar.HookScript and not blizzBar.fqFaded then
            blizzBar.fqFaded = true
            blizzBar:HookScript("OnShow", function(self) self:SetAlpha(0) end)
        end
    end
end

local function CreatePanel(area)
    local color = Style.COLOR
    FadeBlizzardSettings(area)
    pcall(FadeMapTrackingMenu)
    panel = CreateFrame("Frame", "ForeverQuestsLog", area, "BackdropTemplate")
    panel:SetAllPoints(area)
    -- über allen Teilen von Blizzards Liste; fängt deren Maus ab (Blizzards Liste darunter bleibt unberührt)
    panel:SetFrameLevel(area:GetFrameLevel() + 60)
    panel:EnableMouse(true)
    Style.SetFlat(panel, color.background)

    -- Kopfzeile: Suche | Anzahl | Filter | Dungeons | Rädchen
    local header = HeaderBar(panel, HEADER_HEIGHT)

    -- Rädchen (statt Blizzards, dessen "Questziele anzeigen" mit Questie nichts bewirkt): Questmarker, alle/keine verfolgen
    local gearButton = Style.CreateButton(header, "", 18, 18, OpenLogMenu, ns.L("TIP_LOG_MENU"))
    gearButton:SetPoint("RIGHT", -5, 0)
    local gear = gearButton:CreateTexture(nil, "ARTWORK")
    gear:SetPoint("TOPLEFT", 2, -2)
    gear:SetPoint("BOTTOMRIGHT", -2, 2)
    gear:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    gear:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local dungeonButton = Style.CreateButton(header, ns.L("BTN_DUNGEONS"), 62, 18,
        function() if ns.ToggleDungeons then ns.ToggleDungeons() end end,
        function(tooltip) tooltip:AddLine(ns.L("TIP_DUNGEONS")) end)
    dungeonButton:SetPoint("RIGHT", gearButton, "LEFT", -4, 0)

    filterButton = Style.CreateButton(header, ns.L("BTN_FILTER"), 42, 18, function(self)
        ns.QuestList.OpenFilterMenu(self, FILTER_KEY, ns.UpdateQuestLog)
    end, function(tooltip)
        tooltip:AddLine(ns.L("FILTER_TITLE"))
        tooltip:AddLine(ns.L("TIP_LOG_FILTER"), 1, 1, 1, true)
    end)
    filterButton:SetPoint("RIGHT", dungeonButton, "LEFT", -4, 0)

    -- Anzahl der Quests im Log (rot, wenn voll), mit Tooltip
    local count = CreateFrame("Frame", nil, header)
    count:SetSize(40, 18)
    count:SetPoint("RIGHT", filterButton, "LEFT", -4, 0)
    count:EnableMouse(true)
    countText = count:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("RIGHT")
    count:SetScript("OnEnter", function(self)
        local tip = Style.GetTooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(ns.L("TIP_LOG_COUNT"), 1, 1, 1)
        tip:Show()
    end)
    count:SetScript("OnLeave", function() Style.GetTooltip():Hide() end)

    searchBox = Style.CreateEditBox(header, 100, 18)
    searchBox:SetPoint("LEFT", 5, 0)
    searchBox:SetPoint("RIGHT", count, "LEFT", -6, 0)
    searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 7, 0)
    searchHint:SetPoint("RIGHT", -4, 0)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetWordWrap(false)
    searchHint:SetText(ns.L("LOG_SEARCH"))
    local function UpdateHint()
        searchHint:SetShown(searchBox:GetText() == "" and not searchBox:HasFocus())
    end
    searchBox:HookScript("OnEditFocusGained", UpdateHint)
    searchBox:HookScript("OnEditFocusLost", UpdateHint)
    searchBox:SetScript("OnTextChanged", function()
        UpdateHint()
        scrollFrame:SetVerticalScroll(0)
        RequestLogUpdate()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Fußzeile: abgabebereite Quests und ihre Erfahrung
    readyFooter = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    readyFooter:SetPoint("BOTTOMLEFT", 1, 1)
    readyFooter:SetPoint("BOTTOMRIGHT", -1, 1)
    readyFooter:SetHeight(20)
    readyFooter:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    readyFooter:SetBackdropColor(unpack(color.header))
    local footerLine = readyFooter:CreateTexture(nil, "ARTWORK")
    footerLine:SetPoint("TOPLEFT")
    footerLine:SetPoint("TOPRIGHT")
    footerLine:SetHeight(1)
    footerLine:SetColorTexture(color.accent[1], color.accent[2], color.accent[3], 0.35)
    readyFooter.text = readyFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    readyFooter.text:SetPoint("LEFT", 8, 0)
    readyFooter.text:SetPoint("RIGHT", -8, 0)
    readyFooter.text:SetJustifyH("LEFT")
    readyFooter.text:SetWordWrap(false)

    scrollFrame, content = CreateScroll(panel)
    scrollFrame:SetPoint("TOPLEFT", 6, -(HEADER_HEIGHT + 6))
    scrollFrame:SetPoint("BOTTOMRIGHT", readyFooter, "TOPRIGHT", -5, 4)

    logView = ns.QuestList.NewView(content, "ForeverQuestsLog")
    logView.onHover = HighlightOnMap

    panel:SetScript("OnShow", RequestLogUpdate)
    panel:SetScript("OnHide", function() HighlightOnMap(nil) end)
    scrollFrame:SetScript("OnSizeChanged", RequestLogUpdate)
end

---------------------------------------------------------------------------
-- Detailansicht einer Quest – ein Baustein, den der Questlog an der Karte und das Dungeonfenster benutzen
-- (ns.CreateQuestDetailView). Steht die Quest im Questlog: alles aus dem Spiel (Ziele mit Fortschritt,
-- Beschreibung, Belohnungen). Sonst (nur Dungeonfenster): Questziele, Questgeber, Abgabe, Erfahrung, Geld und Ruf
-- aus Questies Datenbank, Gegenstände/Zauber, soweit der Server sie nachlädt. Die Questreihe kommt immer aus Questie.
---------------------------------------------------------------------------

local blizzardDetails, detailBlocker
local logDetail -- Detailansicht im Questlog an der Karte
local FactionName, ReputationRewards, SpellRewards -- (weiter unten)
local RenderDetailView

-- Fließtext / Überschriften (werden bei jedem Aufbau wiederverwendet)
local function DetailText(dv, index)
    local text = dv.texts[index]
    if not text then
        text = dv.content:CreateFontString(nil, "OVERLAY")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        text.line = dv.content:CreateTexture(nil, "ARTWORK")
        text.line:SetHeight(1)
        dv.texts[index] = text
    end
    text.line:Hide()
    return text
end

-- Gegenstände mit gedrückter Shift-Taste: Blizzards GameTooltip samt Vergleich mit der getragenen Ausrüstung
-- (wie im Dungeonfenster); sonst unser eigener Tooltip ohne Vergleich
local function RewardTooltip(self)
    local compare = IsShiftKeyDown() and self.kind ~= "currency" and self.kind ~= "spell"
    local tip = compare and GameTooltip or Style.GetTooltip()
    if compare then Style.GetTooltip():Hide() elseif GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local questID = self.dv and self.dv.questID
    -- Belohnung einer anderen Quest (Ende der Questreihe): nicht über den Questlog dieser Quest nachschlagen
    local inLog = questID and not self.otherQuest and C_QuestLog.GetLogIndexForQuestID(questID)
    local shown = false
    if self.kind == "currency" then
        if self.currencyID and tip.SetCurrencyByID then
            shown = pcall(tip.SetCurrencyByID, tip, self.currencyID) and tip:NumLines() > 0
        end
    elseif self.kind == "spell" then
        if self.spellID and tip.SetSpellByID then
            shown = pcall(tip.SetSpellByID, tip, self.spellID) and tip:NumLines() > 0
        end
    else
        if inLog and tip.SetQuestLogItem then
            C_QuestLog.SetSelectedQuest(questID)
            shown = pcall(tip.SetQuestLogItem, tip, self.kind, self.index, questID) and tip:NumLines() > 0
        end
        if not shown and self.itemID and tip.SetItemByID then
            shown = pcall(tip.SetItemByID, tip, self.itemID) and tip:NumLines() > 0
        end
    end
    if not shown then tip:AddLine(self.name:GetText() or "?", 1, 1, 1) end
    tip:Show()
    if compare and shown and GameTooltip_ShowCompareItem then pcall(GameTooltip_ShowCompareItem, GameTooltip) end
end

-- Belohnungs-Feld: Symbol mit Anzahl, Name in Seltenheitsfarbe; Shift-Klick verlinkt, Strg-Klick = Anprobe
local function RewardButton(dv, index)
    local button = dv.rewards[index]
    if button then return button end
    button = CreateFrame("Button", nil, dv.content, "BackdropTemplate")
    button.dv = dv
    Style.SetFlat(button, Style.COLOR.panel)
    button:SetHeight(32)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(26, 26)
    button.icon:SetPoint("LEFT", 3, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", 1, 0)
    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.name:SetPoint("LEFT", button.icon, "RIGHT", 5, 0)
    button.name:SetPoint("RIGHT", -3, 0)
    button.name:SetJustifyH("LEFT")
    button.name:SetMaxLines(2)
    button:SetScript("OnEnter", function(self)
        local a = Style.COLOR.accent
        self:SetBackdropBorderColor(a[1], a[2], a[3], 0.9)
        RewardTooltip(self)
        self:RegisterEvent("MODIFIER_STATE_CHANGED") -- Shift drücken/loslassen, während die Maus darauf ist
    end)
    button:SetScript("OnEvent", function(self) if self:IsMouseOver() then RewardTooltip(self) end end)
    button:SetScript("OnLeave", function(self)
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        self:SetBackdropBorderColor(unpack(Style.COLOR.border))
        Style.GetTooltip():Hide()
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function(self)
        if self.kind == "currency" or self.kind == "spell" or not IsModifiedClick() then return end
        local questID = self.dv.questID
        local link
        if questID and not self.otherQuest and C_QuestLog.GetLogIndexForQuestID(questID) and GetQuestLogItemLink then
            C_QuestLog.SetSelectedQuest(questID)
            link = GetQuestLogItemLink(self.kind, self.index)
        elseif self.itemID and C_Item and C_Item.GetItemInfo then
            link = select(2, C_Item.GetItemInfo(self.itemID))
        end
        if link then HandleModifiedItemClick(link) end
    end)
    dv.rewards[index] = button
    return button
end

-- Belohnungen einer nicht angenommenen Quest vom Server nachladen (klappt nicht bei jedem Server/jeder Quest;
-- dann bleibt es bei Erfahrung, Geld und Ruf). Offene Tooltips/Detailansichten werden danach neu gefüllt.
local requestedRewards = {}
local function RequestRewardData(questID)
    if requestedRewards[questID] then return end
    requestedRewards[questID] = true
    if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, questID) end
    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        pcall(C_TaskQuest.RequestPreloadRewardData, questID)
    end
end

-- Gegenstands-Belohnungen einer Quest (auch ohne sie im Log zu haben), soweit das Spiel sie kennt
local function PreloadedItemRewardList(questID)
    local list = {}
    if not (GetNumQuestLogRewards and GetQuestLogRewardInfo) then return list end
    local ok, num = pcall(GetNumQuestLogRewards, questID)
    for i = 1, (ok and num or 0) do
        local okInfo, name, texture, count, quality, _, itemID = pcall(GetQuestLogRewardInfo, i, questID)
        if okInfo and name then
            list[#list + 1] = { kind = "reward", index = i, name = name, texture = texture, count = count,
                quality = quality, itemID = itemID }
        end
    end
    return list
end

-- Belohnungen aus Questies Datenbank (wenn das Spiel für die Quest keine liefert): Name, Symbol und Seltenheit
-- kommen aus dem Spiel über die Gegenstands-ID (noch nicht geladene Gegenstände werden angefordert)
local function QuestieRewardEntries(questID)
    local list = {}
    for _, itemID in ipairs(ns.GetQuestieRewardItems and ns.GetQuestieRewardItems(questID) or {}) do
        local name, _, quality, _, _, _, _, _, _, texture
        if C_Item and C_Item.GetItemInfo then name, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID) end
        if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        texture = texture or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
        list[#list + 1] = { kind = "item", itemID = itemID, name = name or ns.L("ITEM_LOADING", itemID),
            texture = texture, quality = quality }
    end
    return list
end

-- Belohnungen einer nicht angenommenen Quest: vom Spiel (falls der Server sie nachgeladen hat), sonst aus Questie
local function NotInLogRewardList(questID)
    local list = PreloadedItemRewardList(questID)
    if #list == 0 then list = QuestieRewardEntries(questID) end
    return list
end

-- Gegenstands-IDs der Belohnungen einer Quest (für die Karten im Dungeonfenster): im Questlog vollständig
-- (feste Belohnungen und Auswahl), sonst die festen Belohnungen, soweit der Server sie nachgeladen hat.
-- Fehlen sie noch, wird das Nachladen angestoßen (die Karten füllen sich danach von selbst).
function ns.QuestRewardItemIDs(questID)
    local ids = {}
    if not questID then return ids end
    local inLog = C_QuestLog.GetLogIndexForQuestID(questID)
    for _, entry in ipairs(inLog and PreloadedItemRewardList(questID) or NotInLogRewardList(questID)) do
        if entry.itemID then ids[#ids + 1] = entry.itemID end
    end
    if inLog and GetNumQuestLogChoices and GetQuestLogChoiceInfo then
        local previous = C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(questID)
        for i = 1, GetNumQuestLogChoices(questID) do
            local itemID = select(6, GetQuestLogChoiceInfo(i))
            if itemID then ids[#ids + 1] = itemID end
        end
        C_QuestLog.SetSelectedQuest(previous or 0)
    end
    if #ids == 0 and not inLog then RequestRewardData(questID) end
    return ids
end

local function PreloadedItemRewards(questID)
    local lines = {}
    for _, entry in ipairs(NotInLogRewardList(questID)) do
        local color = entry.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
        local text = (entry.texture and ("|T" .. entry.texture .. ":14:14:0:0|t ") or "")
            .. (color and color.hex or "|cffffffff") .. entry.name .. "|r"
        if entry.count and entry.count > 1 then text = text .. " |cffaaaaaax" .. entry.count .. "|r" end
        lines[#lines + 1] = text
    end
    return lines
end

-- Tooltip der Questreihe wie im Tracker: Quest im Log = genau der Tracker-Tooltip; sonst derselbe Aufbau aus
-- Questies Daten (Name in Schwierigkeitsfarbe mit Stufe, Questziel, Ziele, Questgeber, Belohnungen, Stand)
local function ChainTooltip(self)
    local entry = self.entry
    if not entry then return end
    if self.inLog then
        ns.QuestList.ShowQuestTooltip(self, entry.questID, true)
        return
    end
    local tip = Style.GetTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = 1, 0.82, 0
    local color = ns.QuestList.LevelColor(entry.level)
    if color then r, g, b = color.r, color.g, color.b end
    local title = entry.name or ("Quest #" .. entry.questID)
    if entry.level and entry.level > 0 then title = title .. " (" .. entry.level .. ")" end
    tip:AddLine(title, r, g, b)
    for _, line in ipairs(entry.objectives or {}) do
        if type(line) == "string" and line ~= "" then tip:AddLine(line, 1, 1, 1, true) end
    end
    local info = ns.GetQuestieQuestDetails and ns.GetQuestieQuestDetails(entry.questID)
    if info then
        if #info.objectives > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(info.objectives) do
                local text = self.done and line:gsub(": 0/(%d+)$", ": %1/%1") or line
                local shade = self.done and 0.5 or 1
                tip:AddLine("- " .. text, shade, shade, shade, true)
            end
        end
        if info.starter or info.finisher then
            tip:AddLine(" ")
            if info.starter then tip:AddLine(ns.L("TIP_CHAIN_STARTER", info.starter), 0.75, 0.75, 0.75, true) end
            if info.finisher then tip:AddLine(ns.L("TIP_CHAIN_FINISHER", info.finisher), 0.75, 0.75, 0.75, true) end
        end
        RequestRewardData(entry.questID)
        local reps = ReputationRewards(entry.questID)
        local money = info.money or 0
        local items = PreloadedItemRewards(entry.questID)
        local spells = SpellRewards(entry.questID)
        if (info.xp and info.xp > 0) or money > 0 or #reps > 0 or #items > 0 or #spells > 0 then
            tip:AddLine(" ")
            tip:AddLine(ns.L("TIP_REWARDS"), 1, 0.82, 0)
            for _, line in ipairs(items) do tip:AddLine(line) end
            for _, spell in ipairs(spells) do
                tip:AddLine((spell.texture and ("|T" .. spell.texture .. ":14:14:0:0|t ") or "") .. spell.name, 0.9, 0.9, 0.9)
            end
            if money > 0 then
                tip:AddLine(GetMoneyString and GetMoneyString(money) or GetCoinTextureString(money), 1, 1, 1)
            end
            if info.xp and info.xp > 0 then
                tip:AddLine(ns.L("TIP_XP", BreakUpLargeNumbers and BreakUpLargeNumbers(info.xp) or info.xp), 0.6, 0.6, 1)
            end
            for _, rep in ipairs(reps) do
                tip:AddLine(ns.L("DETAIL_REPUTATION", (rep.amount > 0 and "+" or "") .. rep.amount,
                    FactionName(rep.factionID)), 0.25, 0.55, 1)
            end
        end
    end
    tip:AddLine(" ")
    if self.done then
        tip:AddLine(ns.L("TIP_CHAIN_DONE"), 0.45, 0.85, 0.45)
    else
        tip:AddLine(ns.L("TIP_CHAIN_OPEN"), 0.7, 0.7, 0.7)
    end
    if entry.requiredLevel and entry.requiredLevel > 0 then
        tip:AddLine(ns.L("TIP_CHAIN_REQUIRED", entry.requiredLevel), 0.75, 0.75, 0.75)
    end
    if ns.db.showQuestIDs then tip:AddLine(ns.L("TIP_CHAIN_ID", entry.questID), 0.5, 0.5, 0.5) end
    if ns.AddAltLines then ns.AddAltLines(tip, entry.questID) end
    tip:Show()
end

-- Tooltip einer beliebigen Quest (z. B. im Dungeonfenster): wie in der Questreihe – im Questlog der Tracker-Tooltip,
-- sonst aus Questies Daten mit Zielen, Questgeber und Belohnungen (vom Server nachgeladen; der Tooltip füllt sich nach)
function ns.ShowQuestInfoTooltip(owner, questID)
    if not owner or not questID then return end
    Style = Style or ns.Style
    local info = ns.GetQuestieQuestDetails and ns.GetQuestieQuestDetails(questID) or {}
    owner.view = owner.view or { anchor = "ANCHOR_RIGHT" }
    owner.entry = { questID = questID, name = C_QuestLog.GetTitleForQuestID(questID) or info.name,
        level = info.level, requiredLevel = info.requiredLevel, objectives = info.objectivesText }
    owner.inLog = C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
    owner.done = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) or false
    ChainTooltip(owner)
end

-- Zeile der Questreihe (Pool je Ansicht): nicht anklickbar, Tooltip beim Darüberfahren
ns.ChainTooltip = ChainTooltip -- auch für die Questreihe am Quest-Dialog (QuestDialog.lua)

local function ChainRow(dv, index)
    local row = dv.chain[index]
    if row then return row end
    row = CreateFrame("Frame", nil, dv.content)
    row.view = { anchor = "ANCHOR_RIGHT" } -- Tooltip-Seite für den Tracker-Tooltip
    row:EnableMouse(true)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetPoint("TOPLEFT")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    row:SetScript("OnEnter", ChainTooltip)
    row:SetScript("OnLeave", function() Style.GetTooltip():Hide() end)
    -- Rechtsklick: Wowhead-Link (wie im Dungeonfenster; Questies Fenster zum Kopieren, darum nur mit Questie)
    row:SetScript("OnMouseUp", function(self, button)
        local questID = button == "RightButton" and self.entry and self.entry.questID
        if not questID or not (ns.HasQuestie and ns.HasQuestie() and ns.ShowQuestieWowhead) then return end
        Style.ShowMenu(self, {
            { title = C_QuestLog.GetTitleForQuestID(questID) or self.entry.name or ("Quest " .. questID) },
            { text = ns.L("QUESTIE_WOWHEAD"), disabled = InCombatLockdown(), onClick = function() ns.ShowQuestieWowhead(questID) end },
        })
    end)
    dv.chain[index] = row
    return row
end

-- alle angelegten Detailansichten (für das Nachladen von Questdaten)
local detailViews = {}

-- Nachgeladene Questdaten angekommen: offenen Tooltip der Questreihe und offene Ansichten neu füllen
do
    local loader = CreateFrame("Frame")
    for _, event in ipairs({ "QUEST_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(loader.RegisterEvent, loader, event)
    end
    local queued = false
    loader:SetScript("OnEvent", function()
        local tip = Style and Style.GetTooltip()
        local owner = tip and tip:IsShown() and tip:GetOwner()
        if owner and owner.entry and not owner.inLog then
            C_Timer.After(0, function()
                if tip:GetOwner() == owner and owner:IsMouseOver() then ChainTooltip(owner) end
            end)
        end
        if queued then return end
        queued = true
        C_Timer.After(0.3, function()
            queued = false
            for _, dv in ipairs(detailViews) do
                if dv.frame:IsVisible() and dv.questID and not C_QuestLog.GetLogIndexForQuestID(dv.questID) then
                    RenderDetailView(dv)
                end
            end
        end)
    end)
end

-- Name einer Fraktion (für Rufbelohnungen)
function FactionName(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(factionID)
        if data and data.name then return data.name end
    end
    if GetFactionInfoByID then
        local name = GetFactionInfoByID(factionID)
        if name then return name end
    end
    return "#" .. tostring(factionID)
end

-- Ruf-Belohnungen: aus Questies Datenbank (genaue Werte), sonst vom Spiel
function ReputationRewards(questID)
    local list = {}
    local fromQuestie = ns.GetQuestieReputation and ns.GetQuestieReputation(questID)
    if fromQuestie then
        for _, pair in ipairs(fromQuestie) do
            if pair[1] and pair[2] and pair[2] ~= 0 then list[#list + 1] = { factionID = pair[1], amount = pair[2] } end
        end
    end
    if #list == 0 and GetNumQuestLogRewardFactions and GetQuestLogRewardFactionInfo then
        local ok, num = pcall(GetNumQuestLogRewardFactions, questID)
        for i = 1, (ok and num or 0) do
            local factionID, amount = GetQuestLogRewardFactionInfo(i)
            if factionID and amount and amount ~= 0 then
                -- ältere Spielversionen liefern den Wert mal 100
                if math.abs(amount) >= 5000 then amount = math.floor(amount / 100 + 0.5) end
                list[#list + 1] = { factionID = factionID, amount = amount }
            end
        end
    end
    return list
end

-- Zauber-Belohnungen (erlernte Zauber/Fähigkeiten)
function SpellRewards(questID)
    local list = {}
    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestRewardSpells then
        local ok, spells = pcall(C_QuestInfoSystem.GetQuestRewardSpells, questID)
        for _, spellID in ipairs(ok and spells or {}) do
            local info = C_QuestInfoSystem.GetQuestRewardSpellInfo and C_QuestInfoSystem.GetQuestRewardSpellInfo(questID, spellID)
            local name, texture = info and info.name, info and info.texture
            if not name and C_Spell and C_Spell.GetSpellInfo then
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                name, texture = spellInfo and spellInfo.name, spellInfo and spellInfo.iconID
            end
            if name then list[#list + 1] = { kind = "spell", spellID = spellID, name = name, texture = texture } end
        end
    elseif GetNumQuestLogRewardSpells and GetQuestLogRewardSpell then
        local ok, num = pcall(GetNumQuestLogRewardSpells, questID)
        for i = 1, (ok and num or 0) do
            local texture, name, _, _, _, _, _, _, spellID = GetQuestLogRewardSpell(i, questID)
            if name then list[#list + 1] = { kind = "spell", spellID = spellID, name = name, texture = texture } end
        end
    end
    return list
end

local function QualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

-- Aufbau einer Detailansicht (dv = Ansicht aus ns.CreateQuestDetailView)
RenderDetailView = function(dv)
    local questID = dv.questID
    if not questID then return end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex and not dv.allowNotInLog then
        -- Quest nicht (mehr) im Log (abgegeben/abgebrochen)
        if dv.onMissing then dv.onMissing() end
        return
    end
    local fonts = ns.QuestList.Fonts()
    local width = math.max(50, dv.scroll:GetWidth() - 4)
    local content = dv.content
    content:SetWidth(width)
    local accent = Style.COLOR.accent
    local y, n, used = 4, 0, 0

    local function Section(label)
        n = n + 1
        local text = DetailText(dv, n)
        text:SetFontObject(fonts.header)
        text:SetTextColor(accent[1], accent[2], accent[3])
        text:SetWidth(width - 4)
        text:SetText(label)
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
        text:Show()
        y = y + text:GetStringHeight() + 3
        text.line:SetColorTexture(accent[1], accent[2], accent[3], 0.35)
        text.line:ClearAllPoints()
        text.line:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
        text.line:SetWidth(width - 4)
        text.line:Show()
        y = y + 5
    end
    local function Paragraph(value, font, cr, cg, cb, indent)
        if not value or value == "" then return end
        n = n + 1
        local text = DetailText(dv, n)
        text:SetFontObject(font)
        text:SetTextColor(cr, cg, cb)
        text:SetWidth(width - 4 - (indent or 0))
        text:SetText(value)
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", content, "TOPLEFT", 2 + (indent or 0), -y)
        text:Show()
        y = y + text:GetStringHeight() + 4
    end
    local function Grid(list)
        local columnWidth = math.floor((width - 4 - 4) / 2)
        for i, entry in ipairs(list) do
            used = used + 1
            local button = RewardButton(dv, used)
            button.kind, button.index, button.itemID, button.currencyID = entry.kind, entry.index, entry.itemID,
                entry.currencyID
            button.spellID, button.otherQuest = entry.spellID, entry.otherQuest
            button.icon:SetTexture(entry.texture or 134400)
            button.count:SetText((entry.count and entry.count > 1) and entry.count or "")
            button.name:SetText(entry.name)
            button.name:SetTextColor(QualityColor(entry.quality))
            button:SetWidth(columnWidth)
            button:ClearAllPoints()
            local column = (i - 1) % 2
            button:SetPoint("TOPLEFT", content, "TOPLEFT", 2 + column * (columnWidth + 4), -y)
            button:Show()
            if column == 1 or i == #list then y = y + 36 end
        end
    end

    local rewards, choices, currencies, spells, reputations = {}, {}, {}, {}, {}
    local money, xp, title, honor = 0, 0, nil, 0
    if logIndex then
        -- Quest im Questlog: alles aus dem Spiel
        local info = C_QuestLog.GetInfo(logIndex) or {}
        local r, g, b = 1, 0.82, 0
        local levelColor = ns.QuestList.LevelColor(info.level)
        if levelColor then r, g, b = levelColor.r, levelColor.g, levelColor.b end
        local titleText = info.title or C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID)
        if info.level and info.level > 0 then titleText = titleText .. " (" .. info.level .. ")" end
        dv.title:SetText(titleText)
        dv.title:SetTextColor(r, g, b)

        -- Text der Quest steht bei der "ausgewählten" Quest
        C_QuestLog.SetSelectedQuest(questID)
        local description, objectiveText
        if GetQuestLogQuestText then description, objectiveText = GetQuestLogQuestText(logIndex) end

        local typeText = ns.QuestList.QuestTypeText(questID, nil)
        local isComplete = C_QuestLog.IsComplete(questID)
        if typeText ~= "" or isComplete then
            Paragraph(((typeText ~= "" and ("|cff88ccff" .. typeText .. "|r  ")) or "")
                .. (isComplete and ("|cff00ff00" .. ns.L("READY_TO_TURN_IN") .. "|r") or ""), fonts.objective, 1, 1, 1)
        end
        Section(ns.L("DETAIL_OBJECTIVES"))
        Paragraph(objectiveText, fonts.quest, 1, 1, 1)
        for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
            if objective.text and objective.text ~= "" then
                if objective.finished then
                    Paragraph("- " .. objective.text, fonts.objective, 0.45, 0.85, 0.45, 6)
                else
                    Paragraph("- " .. objective.text, fonts.objective, 0.85, 0.85, 0.85, 6)
                end
            end
        end
        y = y + 4
        if description and description ~= "" then
            Section(ns.L("DETAIL_DESCRIPTION"))
            Paragraph(description, fonts.objective, 0.75, 0.75, 0.75)
            y = y + 4
        end

        for i = 1, (GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0) do
            local name, texture, count, quality, _, itemID = GetQuestLogRewardInfo(i, questID)
            if name then rewards[#rewards + 1] = { kind = "reward", index = i, name = name, texture = texture,
                count = count, quality = quality, itemID = itemID } end
        end
        for i = 1, (GetNumQuestLogChoices and GetNumQuestLogChoices(questID) or 0) do
            local name, texture, count, quality, _, itemID = GetQuestLogChoiceInfo(i)
            if name then choices[#choices + 1] = { kind = "choice", index = i, name = name, texture = texture,
                count = count, quality = quality, itemID = itemID } end
        end
        if C_QuestLog.GetQuestRewardCurrencies then
            local ok, list = pcall(C_QuestLog.GetQuestRewardCurrencies, questID)
            for _, currency in ipairs(ok and list or {}) do
                currencies[#currencies + 1] = { kind = "currency", name = currency.name, texture = currency.texture,
                    count = currency.totalRewardAmount or currency.baseRewardAmount, quality = currency.quality,
                    currencyID = currency.currencyID }
            end
        end
        money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
        xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
        spells = SpellRewards(questID)
        reputations = ReputationRewards(questID)
        title = GetQuestLogRewardTitle and GetQuestLogRewardTitle() or nil
        honor = GetQuestLogRewardHonor and GetQuestLogRewardHonor(questID) or 0
    else
        -- Quest nicht im Log (Dungeonfenster): Spiel, soweit es sie kennt, sonst Questies Datenbank
        local info = ns.GetQuestieQuestDetails and ns.GetQuestieQuestDetails(questID) or { objectives = {} }
        local level = info.level
        local r, g, b = 1, 0.82, 0
        local levelColor = ns.QuestList.LevelColor(level)
        if levelColor then r, g, b = levelColor.r, levelColor.g, levelColor.b end
        local titleText = C_QuestLog.GetTitleForQuestID(questID) or info.name or ("Quest " .. questID)
        if level and level > 0 then titleText = titleText .. " (" .. level .. ")" end
        dv.title:SetText(titleText)
        dv.title:SetTextColor(r, g, b)

        -- Stand: schon erledigt / Stufe fehlt noch / noch nicht angenommen
        local done = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID)
        if done then
            Paragraph("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " .. ns.L("TIP_CHAIN_DONE"), fonts.objective, 0.45, 0.85, 0.45)
        elseif info.requiredLevel and info.requiredLevel > UnitLevel("player") then
            Paragraph(ns.L("DETAIL_NEEDS_LEVEL", info.requiredLevel), fonts.objective, 1, 0.35, 0.35)
        else
            Paragraph(ns.L("DETAIL_NOT_ACCEPTED"), fonts.objective, 0.7, 0.7, 0.7)
        end

        Section(ns.L("DETAIL_OBJECTIVES"))
        for _, line in ipairs(info.objectivesText or {}) do
            if type(line) == "string" and line ~= "" then Paragraph(line, fonts.quest, 1, 1, 1) end
        end
        for _, line in ipairs(info.objectives or {}) do
            local text = done and line:gsub(": 0/(%d+)$", ": %1/%1") or line
            Paragraph("- " .. text, fonts.objective, done and 0.45 or 0.85, done and 0.85 or 0.85, done and 0.45 or 0.85, 6)
        end
        y = y + 4
        if info.starter or info.finisher then
            Section(ns.L("DETAIL_GIVERS"))
            if info.starter then Paragraph(ns.L("TIP_CHAIN_STARTER", info.starter), fonts.objective, 0.85, 0.85, 0.85) end
            if info.finisher then Paragraph(ns.L("TIP_CHAIN_FINISHER", info.finisher), fonts.objective, 0.85, 0.85, 0.85) end
            y = y + 4
        end

        RequestRewardData(questID)
        rewards = NotInLogRewardList(questID)
        spells = SpellRewards(questID)
        reputations = ReputationRewards(questID)
        money = info.money or 0
        xp = info.xp or 0
    end
    dv.id:SetText(ns.db.showQuestIDs and ("#" .. questID) or "")

    -- Questreihe (aus Questies Datenbank): erledigt = Haken, diese Quest = gold, offen = grau; mit Quest-ID.
    -- Nicht anklickbar, aber Maus darüber zeigt einen Tooltip.
    local chain = ns.GetQuestChain and ns.GetQuestChain(questID)
    local rowsUsed = 0
    if chain then
        Section(ns.L("DETAIL_CHAIN") .. "  |cff8a8a8a" .. #chain .. "|r")
        for i, entry in ipairs(chain) do
            local label = (entry.name or ("Quest #" .. entry.questID))
                .. ((entry.level and entry.level > 0) and (" (" .. entry.level .. ")") or "")
            local done = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(entry.questID)
            local inLog = C_QuestLog.GetLogIndexForQuestID(entry.questID) ~= nil
            local text, font, cr, cg, cb = i .. ". " .. label, fonts.objective, 0.6, 0.6, 0.6
            -- erledigt = grün mit Haken; gold nur der Teil, der gerade im Questlog bearbeitet wird; sonst grau
            if done then
                text, cr, cg, cb = text .. "  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t", 0.45, 0.85, 0.45
            elseif inLog then
                font, cr, cg, cb = fonts.quest, accent[1], accent[2], accent[3]
                if entry.questID ~= questID then
                    text = text .. "  |cff88ccff" .. ns.L("DETAIL_IN_LOG") .. "|r"
                end
            end
            if ns.db.showQuestIDs then text = text .. "  |cff6a6a6a#" .. entry.questID .. "|r" end
            rowsUsed = rowsUsed + 1
            local row = ChainRow(dv, rowsUsed)
            row.entry, row.done, row.inLog, row.current = entry, done, inLog, entry.questID == questID
            row.text:SetFontObject(font)
            row.text:SetTextColor(cr, cg, cb)
            row.text:SetWidth(width - 8)
            row.text:SetText(text)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -y)
            row:SetSize(width - 8, row.text:GetStringHeight() + 2)
            row:Show()
            y = y + row:GetHeight() + 2
        end
        y = y + 4
    end
    for i = rowsUsed + 1, #dv.chain do dv.chain[i]:Hide() end

    -- Gegenstände vom letzten Teil der Questreihe (wenn das nicht diese Quest ist): als echte Belohnungen,
    -- mit Hinweis, aus welchem Teil sie stammen
    local finalRewards, finalLabel = {}, nil
    local last = chain and chain[#chain]
    if last and last.questID ~= questID then
        local lastInLog = C_QuestLog.GetLogIndexForQuestID(last.questID) ~= nil
        finalRewards = lastInLog and PreloadedItemRewardList(last.questID) or NotInLogRewardList(last.questID)
        if #finalRewards == 0 and not lastInLog then RequestRewardData(last.questID) end
        for _, entry in ipairs(finalRewards) do entry.otherQuest = true end
        finalLabel = ns.L("CHAIN_FINAL_REWARDS", #chain, #chain,
            C_QuestLog.GetTitleForQuestID(last.questID) or last.name or ("Quest #" .. last.questID))
    end

    -- Belohnungen
    local hasTitle = title and title ~= ""
    if #rewards + #choices + #currencies + #spells + #reputations + #finalRewards > 0 or money > 0 or xp > 0
        or hasTitle or honor > 0 then
        Section(ns.L("TIP_REWARDS"))
        Grid(rewards)
        Grid(currencies)
        if #choices > 0 then
            Paragraph(ns.L("TIP_CHOICES"), fonts.objective, 0.75, 0.75, 0.75)
            Grid(choices)
        end
        if #spells > 0 then
            Paragraph(ns.L("DETAIL_SPELLS"), fonts.objective, 0.75, 0.75, 0.75)
            Grid(spells)
        end
        if money > 0 then
            Paragraph(GetMoneyString and GetMoneyString(money) or GetCoinTextureString(money), fonts.quest, 1, 1, 1)
        end
        if xp > 0 then
            Paragraph(ns.L("TIP_XP", BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp), fonts.quest, 0.6, 0.6, 1)
        end
        for _, rep in ipairs(reputations) do
            local sign = rep.amount > 0 and "+" or ""
            Paragraph(ns.L("DETAIL_REPUTATION", sign .. rep.amount, FactionName(rep.factionID)), fonts.quest,
                0.25, 0.55, 1)
        end
        if honor > 0 then Paragraph(ns.L("DETAIL_HONOR", honor), fonts.quest, 0.9, 0.35, 0.25) end
        if hasTitle then Paragraph(ns.L("DETAIL_TITLE", title), fonts.quest, 1, 0.82, 0) end
        if #finalRewards > 0 then
            y = y + 2
            Paragraph(finalLabel, fonts.objective, 0.53, 0.8, 1)
            Grid(finalRewards)
        end
    elseif not logIndex then
        Section(ns.L("TIP_REWARDS"))
        Paragraph(ns.L("DETAIL_REWARDS_UNKNOWN"), fonts.objective, 0.6, 0.6, 0.6)
    end

    for i = n + 1, #dv.texts do
        dv.texts[i]:Hide()
        dv.texts[i].line:Hide()
    end
    for i = used + 1, #dv.rewards do dv.rewards[i]:Hide() end
    content:SetHeight(math.max(1, y + 6))
    if dv.onRendered then dv.onRendered(dv) end
end

-- Neue Detailansicht anlegen: Rahmen mit Kopf (Zurück | Name | Quest-ID) und Scrollbereich.
-- opts: allowNotInLog (auch Quests außerhalb des Logs), onBack, onMissing, footerHeight (Platz für Knöpfe unten)
function ns.CreateQuestDetailView(parent, opts)
    opts = opts or {}
    Style = Style or ns.Style
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:EnableMouse(true)
    Style.SetFlat(frame, Style.COLOR.background)
    frame:Hide()
    local dv = { frame = frame, texts = {}, rewards = {}, chain = {}, allowNotInLog = opts.allowNotInLog,
        onMissing = opts.onMissing }

    -- Kopf; Rechtsklick = dasselbe Menü wie im Tracker (nur bei Quests im Questlog)
    local header = HeaderBar(frame, HEADER_HEIGHT)
    header:EnableMouse(true)
    header:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and dv.questID and C_QuestLog.GetLogIndexForQuestID(dv.questID) then
            ns.QuestList.OpenMenu(self, dv.questID)
        end
    end)
    local back = Style.CreateButton(header, "<", 22, 18, function()
        if opts.onBack then opts.onBack(dv) else frame:Hide() end
    end, ns.L(opts.backTipKey or "TIP_BACK"))
    back:SetPoint("LEFT", 5, 0)
    dv.id = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dv.id:SetPoint("RIGHT", -8, 0)
    dv.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dv.title:SetPoint("LEFT", back, "RIGHT", 6, 0)
    dv.title:SetPoint("RIGHT", dv.id, "LEFT", -6, 0)
    dv.title:SetJustifyH("LEFT")
    dv.title:SetWordWrap(false)
    dv.header = header

    dv.scroll, dv.content = CreateScroll(frame)
    dv.scroll:SetPoint("TOPLEFT", 8, -(HEADER_HEIGHT + 6))
    dv.scroll:SetPoint("BOTTOMRIGHT", -8, (opts.footerHeight or 0) + 6)
    dv.scroll:SetScript("OnSizeChanged", function() if frame:IsShown() and dv.questID then RenderDetailView(dv) end end)

    function dv:Show(questID)
        if not questID or questID == 0 then return end
        if self.questID ~= questID then self.scroll:SetVerticalScroll(0) end
        self.questID = questID
        frame:Show()
        if self.scroll:GetWidth() < 10 then
            C_Timer.After(0, function() if frame:IsShown() then RenderDetailView(self) end end)
        else
            RenderDetailView(self)
        end
    end
    function dv:Refresh()
        if frame:IsShown() and self.questID then RenderDetailView(self) end
    end
    function dv:Hide() frame:Hide() end

    detailViews[#detailViews + 1] = dv
    return dv
end

---------------------------------------------------------------------------
-- Detailansicht im Questlog an der Karte (folgt Blizzards unsichtbarer Detailansicht)
---------------------------------------------------------------------------

-- Blizzards Detailansicht verlassen (unsere folgt ihr und schließt mit)
local function BackToList()
    if type(_G.QuestMapFrame_ReturnFromQuestDetails) == "function" then
        _G.QuestMapFrame_ReturnFromQuestDetails()
    elseif blizzardDetails then
        blizzardDetails:Hide()
    end
    if details then details:Hide() end
    if panel then panel:Show() end
end

local detailButtons
local function UpdateDetailButtons()
    local questID = logDetail and logDetail.questID
    if not questID or not detailButtons then return end
    -- schon gemeinsam: "Nicht mehr gemeinsam machen", sonst "Der Gruppe vorschlagen" (nur in einer Gruppe)
    local isGroupQuest = ns.IsGroupQuest and ns.IsGroupQuest(questID)
    detailButtons.suggest:SetText(ns.L(isGroupQuest and "GQ_LEAVE" or "MENU_SUGGEST"))
    local canSuggest = isGroupQuest or IsInGroup()
    detailButtons.suggest:SetEnabled(canSuggest and true or false)
    detailButtons.suggest:SetAlpha(canSuggest and 1 or 0.45)
    detailButtons.pin:SetText(ns.L(ns.db.pinned[questID] and "BTN_UNPIN" or "BTN_PIN"))
    local canShare = IsInGroup() and C_QuestLog.IsPushableQuest(questID)
    detailButtons.share:SetEnabled(canShare)
    detailButtons.share:SetAlpha(canShare and 1 or 0.45)
end

RenderDetails = function()
    if logDetail then RenderDetailView(logDetail) end
end

local function ShowDetails(questID)
    if not logDetail or not questID or questID == 0 then return end
    -- Karte: nur die Marker dieser Quest
    if ns.QuestieFocusDetails then ns.QuestieFocusDetails(questID) end
    if panel then panel:Hide() end
    if blizzardDetails then blizzardDetails:SetAlpha(0) end
    logDetail:Show(questID)
end

local function CreateDetails(area)
    blizzardDetails = _G.QuestMapFrame and _G.QuestMapFrame.DetailsFrame
    logDetail = ns.CreateQuestDetailView(_G.QuestMapFrame or area, {
        footerHeight = 50,
        onBack = BackToList,
        onMissing = BackToList, -- Quest abgegeben/abgebrochen: zurück zur Liste
    })
    logDetail.onRendered = UpdateDetailButtons
    details = logDetail.frame
    details:SetAllPoints(area)
    details:SetFrameLevel(area:GetFrameLevel() + 80)
    -- Detailansicht offen = auf der Karte nur deren Marker; zu (zurück zur Liste, Karte zu) = alle verfolgten
    details:SetScript("OnShow", function()
        if logDetail.questID and ns.QuestieFocusDetails then ns.QuestieFocusDetails(logDetail.questID) end
    end)
    details:SetScript("OnHide", function()
        if ns.QuestieFocusDetails then ns.QuestieFocusDetails(nil) end
    end)

    -- Knöpfe unten in zwei Reihen:
    --   oben:  Der Gruppe vorschlagen (bzw. Nicht mehr gemeinsam) | Teilen
    --   unten: Anheften | Abbrechen
    local footer = CreateFrame("Frame", nil, details)
    footer:SetPoint("BOTTOMLEFT", 6, 6)
    footer:SetPoint("BOTTOMRIGHT", -6, 6)
    footer:SetHeight(44)
    detailButtons = {}
    local function Act(fn) return function() if logDetail.questID then fn(logDetail.questID) end end end
    detailButtons.suggest = Style.CreateButton(footer, "", 10, 20, Act(function(questID)
        if ns.IsGroupQuest and ns.IsGroupQuest(questID) then
            ns.RemoveGroupQuest(questID, true)
        elseif ns.SuggestQuest then
            ns.SuggestQuest(questID)
        end
        C_Timer.After(0.2, UpdateDetailButtons)
    end))
    detailButtons.share = Style.CreateButton(footer, ns.L("MENU_SHARE"), 10, 20, Act(ns.QuestList.Share))
    detailButtons.pin = Style.CreateButton(footer, "", 10, 20, Act(function(questID)
        ns.QuestList.TogglePinned(questID)
        UpdateDetailButtons()
    end))
    detailButtons.abandon = Style.CreateButton(footer, "|cffff5555" .. ns.L("BTN_ABANDON") .. "|r", 10, 20,
        Act(ns.QuestList.Abandon))
    local function Row(buttons, y)
        local total = footer:GetWidth()
        local w = (total - 4 * (#buttons - 1)) / #buttons
        for i, button in ipairs(buttons) do
            button:SetWidth(w)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", footer, "TOPLEFT", (i - 1) * (w + 4), y)
        end
    end
    footer:SetScript("OnSizeChanged", function()
        local total = footer:GetWidth()
        if not total or total < 50 then return end
        Row({ detailButtons.suggest, detailButtons.share }, 0)
        Row({ detailButtons.pin, detailButtons.abandon }, -24)
    end)

    -- Blizzards (unsichtbare) Detailansicht: unsere zeigt sich mit ihr und schließt mit ihr.
    -- Ein Blocker über ihr fängt die Maus ab, falls sie größer ist als unser Fenster.
    if blizzardDetails then
        blizzardDetails:SetAlpha(0)
        detailBlocker = CreateFrame("Frame", nil, details)
        detailBlocker:SetAllPoints(blizzardDetails)
        detailBlocker:SetFrameLevel(math.max(0, details:GetFrameLevel() - 1))
        detailBlocker:EnableMouse(true)
        blizzardDetails:HookScript("OnShow", function(self)
            ShowDetails(self.questID or C_QuestLog.GetSelectedQuest())
        end)
        blizzardDetails:HookScript("OnHide", function()
            details:Hide()
            if panel then panel:Show() end
        end)
    end
    if type(_G.QuestMapFrame_ShowQuestDetails) == "function" then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID) ShowDetails(questID) end)
    end
    if blizzardDetails and blizzardDetails:IsShown() then
        ShowDetails(blizzardDetails.questID or C_QuestLog.GetSelectedQuest())
    end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local function Setup()
    if panel or not ns.db or not ns.db.questLogSkin then return end
    if not _G.WorldMapFrame then return end
    local area = QuestsArea()
    if not area then return end
    Style = ns.Style
    local ok, err = pcall(SkinWorldMap)
    if not ok then print(ns.ChatPrefix() .. ": Weltkarte - " .. tostring(err)) end
    TrySetupQuestieMapButton(0)
    CreatePanel(area)
    ok, err = pcall(CreateDetails, area)
    if not ok then print(ns.ChatPrefix() .. ": Questdetails - " .. tostring(err)) end
    if panel:IsVisible() then RequestLogUpdate() end
end

local starter = CreateFrame("Frame")
starter:RegisterEvent("PLAYER_LOGIN")
starter:RegisterEvent("ADDON_LOADED")
starter:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
    if not ns.db then return end
    Setup()
    -- falls Blizzard die Karte erst beim ersten Öffnen fertig baut: dann einrichten
    if not panel and _G.WorldMapFrame and not self.hooked then
        self.hooked = true
        _G.WorldMapFrame:HookScript("OnShow", Setup)
    end
    if panel then self:UnregisterAllEvents() end
end)

-- /fq karte: zeigt den Aufbau von Weltkarte und Questlog (zur Fehlersuche beim Gestalten)
function ns.DebugMap()
    local prefix = ns.ChatPrefix() .. ": "
    local function Dump(label, frame)
        if not frame then print(prefix .. label .. " fehlt") return end
        local names = {}
        for key, value in pairs(frame) do
            if type(value) == "table" and type(key) == "string" and value.GetObjectType then
                names[#names + 1] = key .. "(" .. value:GetObjectType() .. ")"
            end
        end
        table.sort(names)
        print(prefix .. label .. ": " .. table.concat(names, ", "))
    end
    local map = _G.WorldMapFrame
    Dump("WorldMapFrame", map)
    Dump("BorderFrame", map and map.BorderFrame)
    Dump("NavBar", map and map.NavBar)
    Dump("QuestMapFrame", _G.QuestMapFrame)
    Dump("QuestsFrame", QuestsArea())
    -- Kartensymbole nach Vorlage (welche Symbole von wem kommen)
    if map and map.pinPools then
        local templates = {}
        for template, pool in pairs(map.pinPools) do
            local shown = 0
            if pool.EnumerateActive then for _ in pool:EnumerateActive() do shown = shown + 1 end end
            templates[#templates + 1] = tostring(template) .. "=" .. shown
        end
        table.sort(templates)
        print(prefix .. "Kartensymbole: " .. table.concat(templates, ", "))
    end
end
