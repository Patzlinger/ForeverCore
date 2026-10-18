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

local FILTER_KEY = "logFilters"
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

local function ApplyMapPlacement()
    local map = _G.WorldMapFrame
    if not map or not ns.db then return end
    local maximized = IsMaximized(map)
    if grip then grip:SetShown(not maximized) end
    if maximized then return end
    local scale = ns.db.mapScale or 1
    if math.abs(map:GetScale() - scale) > 0.001 then map:SetScale(scale) end
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
end

local function ResetMapPlacement()
    local map = _G.WorldMapFrame
    ns.db.mapPos, ns.db.mapScale = nil, nil
    if IsMaximized(map) then return end
    map:SetScale(1)
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

    -- Griff unten rechts: ziehen = größer/kleiner (Ecke oben links bleibt stehen)
    grip = CreateFrame("Button", "ForeverQuestsMapGrip", map)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(map:GetFrameLevel() + 200)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self)
        local cursorX = GetCursorPosition() / UIParent:GetEffectiveScale()
        local scale = map:GetScale()
        self.start = { x = cursorX, scale = scale, left = map:GetLeft() * scale, top = map:GetTop() * scale,
            width = map:GetWidth() * scale }
        self:SetScript("OnUpdate", function()
            local s = self.start
            local x = GetCursorPosition() / UIParent:GetEffectiveScale()
            local newScale = s.scale * (s.width + (x - s.x)) / s.width
            newScale = math.max(MIN_SCALE, math.min(MAX_SCALE, newScale))
            map:SetScale(newScale)
            map:ClearAllPoints()
            map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.left / newScale, s.top / newScale)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
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
    local maxScroll = math.max(0, height - scrollFrame:GetHeight())
    if scrollFrame:GetVerticalScroll() > maxScroll then scrollFrame:SetVerticalScroll(maxScroll) end
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

-- Scrollbereich mit Mausrad; gibt ScrollFrame und Inhalt zurück
local function CreateScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)
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

    scrollFrame, content = CreateScroll(panel)
    scrollFrame:SetPoint("TOPLEFT", 6, -(HEADER_HEIGHT + 6))
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 6)

    logView = ns.QuestList.NewView(content, "ForeverQuestsLog")
    logView.onHover = HighlightOnMap

    panel:SetScript("OnShow", RequestLogUpdate)
    panel:SetScript("OnHide", function() HighlightOnMap(nil) end)
    scrollFrame:SetScript("OnSizeChanged", RequestLogUpdate)
end

---------------------------------------------------------------------------
-- Detailansicht einer Quest
---------------------------------------------------------------------------

local detailScroll, detailContent, detailTitle, detailID, detailButtons
local detailQuestID
local detailTexts, rewardButtons = {}, {}
local blizzardDetails, detailBlocker

-- Fließtext / Überschriften der Detailansicht (werden bei jedem Aufbau wiederverwendet)
local function DetailText(index)
    local text = detailTexts[index]
    if not text then
        text = detailContent:CreateFontString(nil, "OVERLAY")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        text.line = detailContent:CreateTexture(nil, "ARTWORK")
        text.line:SetHeight(1)
        detailTexts[index] = text
    end
    text.line:Hide()
    return text
end

local function RewardTooltip(self)
    local tip = Style.GetTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
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
        C_QuestLog.SetSelectedQuest(detailQuestID)
        if tip.SetQuestLogItem then
            shown = pcall(tip.SetQuestLogItem, tip, self.kind, self.index, detailQuestID) and tip:NumLines() > 0
        end
        if not shown and self.itemID and tip.SetItemByID then
            shown = pcall(tip.SetItemByID, tip, self.itemID) and tip:NumLines() > 0
        end
    end
    if not shown then tip:AddLine(self.name:GetText() or "?", 1, 1, 1) end
    tip:Show()
end

-- Belohnungs-Feld: Symbol mit Anzahl, Name in Seltenheitsfarbe; Shift-Klick verlinkt, Strg-Klick = Anprobe
local function RewardButton(index)
    local button = rewardButtons[index]
    if button then return button end
    button = CreateFrame("Button", nil, detailContent, "BackdropTemplate")
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
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(Style.COLOR.border))
        Style.GetTooltip():Hide()
    end)
    button:SetScript("OnClick", function(self)
        if self.kind == "currency" or self.kind == "spell" or not IsModifiedClick() then return end
        C_QuestLog.SetSelectedQuest(detailQuestID)
        local link = GetQuestLogItemLink and GetQuestLogItemLink(self.kind, self.index)
        if link then HandleModifiedItemClick(link) end
    end)
    rewardButtons[index] = button
    return button
end

-- Zeilen der Questreihe (Pool): nicht anklickbar, Tooltip mit Name, ID, Stufen und Stand
local chainRows = {}
local function ChainTooltip(self)
    local entry = self.entry
    if not entry then return end
    local tip = Style.GetTooltip()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    local r, g, b = 1, 0.82, 0
    local color = ns.QuestList.LevelColor(entry.level)
    if color then r, g, b = color.r, color.g, color.b end
    tip:AddLine(entry.name or ("Quest #" .. entry.questID), r, g, b)
    tip:AddLine(ns.L("TIP_CHAIN_ID", entry.questID), 0.6, 0.6, 0.6)
    if entry.level and entry.level > 0 then tip:AddLine(ns.L("TIP_CHAIN_LEVEL", entry.level), 1, 1, 1) end
    if entry.requiredLevel and entry.requiredLevel > 0 then
        tip:AddLine(ns.L("TIP_CHAIN_REQUIRED", entry.requiredLevel), 1, 1, 1)
    end
    tip:AddLine(" ")
    if self.current then
        tip:AddLine(ns.L("TIP_CHAIN_CURRENT"), Style.COLOR.accent[1], Style.COLOR.accent[2], Style.COLOR.accent[3])
    elseif self.done then
        tip:AddLine(ns.L("TIP_CHAIN_DONE"), 0.45, 0.85, 0.45)
    elseif self.inLog then
        tip:AddLine(ns.L("DETAIL_IN_LOG"), 0.53, 0.8, 1)
    else
        tip:AddLine(ns.L("TIP_CHAIN_OPEN"), 0.7, 0.7, 0.7)
    end
    -- Quest im Log: Ziele mit Fortschritt
    if self.inLog and not self.current then
        for _, objective in ipairs(C_QuestLog.GetQuestObjectives(entry.questID) or {}) do
            if objective.text and objective.text ~= "" then
                local shade = objective.finished and 0.5 or 1
                tip:AddLine("- " .. objective.text, shade, shade, shade, true)
            end
        end
    end
    tip:Show()
end

local function ChainRow(index)
    local row = chainRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, detailContent)
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
    chainRows[index] = row
    return row
end

-- Name einer Fraktion (für Rufbelohnungen)
local function FactionName(factionID)
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
local function ReputationRewards(questID)
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
local function SpellRewards(questID)
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

local function UpdateDetailButtons()
    local questID = detailQuestID
    if not questID then return end
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
    local questID = detailQuestID
    local logIndex = questID and C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then
        -- Quest nicht (mehr) im Log (abgegeben/abgebrochen): zurück zur Liste
        BackToList()
        return
    end
    local fonts = ns.QuestList.Fonts()
    local info = C_QuestLog.GetInfo(logIndex) or {}
    local width = math.max(50, detailScroll:GetWidth() - 4)
    detailContent:SetWidth(width)

    -- Kopf: Name in Schwierigkeitsfarbe mit Stufe und Typ
    local r, g, b = 1, 0.82, 0
    local levelColor = ns.QuestList.LevelColor(info.level)
    if levelColor then r, g, b = levelColor.r, levelColor.g, levelColor.b end
    local titleText = info.title or C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID)
    if info.level and info.level > 0 then titleText = titleText .. " (" .. info.level .. ")" end
    detailTitle:SetText(titleText)
    detailTitle:SetTextColor(r, g, b)
    detailID:SetText("#" .. questID)

    -- Text der Quest steht bei der "ausgewählten" Quest (Blizzards Detailansicht hat sie schon ausgewählt)
    C_QuestLog.SetSelectedQuest(questID)
    local description, objectiveText
    if GetQuestLogQuestText then description, objectiveText = GetQuestLogQuestText(logIndex) end

    local y, n = 4, 0
    local accent = Style.COLOR.accent
    local function Section(label)
        n = n + 1
        local text = DetailText(n)
        text:SetFontObject(fonts.header)
        text:SetTextColor(accent[1], accent[2], accent[3])
        text:SetWidth(width - 4)
        text:SetText(label)
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 2, -y)
        text:Show()
        y = y + text:GetStringHeight() + 3
        text.line:SetColorTexture(accent[1], accent[2], accent[3], 0.35)
        text.line:ClearAllPoints()
        text.line:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 2, -y)
        text.line:SetWidth(width - 4)
        text.line:Show()
        y = y + 5
    end
    local function Paragraph(value, font, cr, cg, cb, indent)
        if not value or value == "" then return end
        n = n + 1
        local text = DetailText(n)
        text:SetFontObject(font)
        text:SetTextColor(cr, cg, cb)
        text:SetWidth(width - 4 - (indent or 0))
        text:SetText(value)
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 2 + (indent or 0), -y)
        text:Show()
        y = y + text:GetStringHeight() + 4
    end

    -- Typ (Klasse, Ruf, Gruppe …) und "Fertig"
    local typeText = ns.QuestList.QuestTypeText(questID, nil)
    local isComplete = C_QuestLog.IsComplete(questID)
    if typeText ~= "" or isComplete then
        Paragraph(((typeText ~= "" and ("|cff88ccff" .. typeText .. "|r  ")) or "")
            .. (isComplete and ("|cff00ff00" .. ns.L("READY_TO_TURN_IN") .. "|r") or ""), fonts.objective, 1, 1, 1)
    end

    -- Ziele: Kurztext und Fortschritt
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

    -- Beschreibung
    if description and description ~= "" then
        Section(ns.L("DETAIL_DESCRIPTION"))
        Paragraph(description, fonts.objective, 0.75, 0.75, 0.75)
        y = y + 4
    end

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
            if entry.questID == questID then
                font, cr, cg, cb = fonts.quest, accent[1], accent[2], accent[3]
            elseif done then
                text, cr, cg, cb = text .. "  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t", 0.45, 0.85, 0.45
            elseif inLog then
                text, cr, cg, cb = text .. "  |cff88ccff" .. ns.L("DETAIL_IN_LOG") .. "|r", 0.9, 0.9, 0.9
            end
            text = text .. "  |cff6a6a6a#" .. entry.questID .. "|r"
            rowsUsed = rowsUsed + 1
            local row = ChainRow(rowsUsed)
            row.entry, row.done, row.inLog, row.current = entry, done, inLog, entry.questID == questID
            row.text:SetFontObject(font)
            row.text:SetTextColor(cr, cg, cb)
            row.text:SetWidth(width - 8)
            row.text:SetText(text)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 6, -y)
            row:SetSize(width - 8, row.text:GetStringHeight() + 2)
            row:Show()
            y = y + row:GetHeight() + 2
        end
        y = y + 4
    end
    for i = rowsUsed + 1, #chainRows do chainRows[i]:Hide() end

    -- Belohnungen: feste Gegenstände, Auswahl, Währungen, Geld, Erfahrung
    local rewards, choices, currencies = {}, {}, {}
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
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    local spells = SpellRewards(questID)
    local reputations = ReputationRewards(questID)
    local title = GetQuestLogRewardTitle and GetQuestLogRewardTitle() or nil
    local honor = GetQuestLogRewardHonor and GetQuestLogRewardHonor(questID) or 0

    local used = 0
    local function Grid(list)
        local columnWidth = math.floor((width - 4 - 4) / 2)
        for i, entry in ipairs(list) do
            used = used + 1
            local button = RewardButton(used)
            button.kind, button.index, button.itemID, button.currencyID = entry.kind, entry.index, entry.itemID,
                entry.currencyID
            button.spellID = entry.spellID
            button.icon:SetTexture(entry.texture or 134400)
            button.count:SetText((entry.count and entry.count > 1) and entry.count or "")
            button.name:SetText(entry.name)
            button.name:SetTextColor(QualityColor(entry.quality))
            button:SetWidth(columnWidth)
            button:ClearAllPoints()
            local column = (i - 1) % 2
            button:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 2 + column * (columnWidth + 4), -y)
            button:Show()
            if column == 1 or i == #list then y = y + 36 end
        end
    end
    local hasTitle = title and title ~= ""
    if #rewards + #choices + #currencies + #spells + #reputations > 0 or money > 0 or xp > 0 or hasTitle
        or honor > 0 then
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
    end

    for i = n + 1, #detailTexts do
        detailTexts[i]:Hide()
        detailTexts[i].line:Hide()
    end
    for i = used + 1, #rewardButtons do rewardButtons[i]:Hide() end
    detailContent:SetHeight(math.max(1, y + 6))
    UpdateDetailButtons()
end

local function ShowDetails(questID)
    if not details or not questID or questID == 0 then return end
    if detailQuestID ~= questID then detailScroll:SetVerticalScroll(0) end
    detailQuestID = questID
    if panel then panel:Hide() end
    if blizzardDetails then blizzardDetails:SetAlpha(0) end
    details:Show()
    if detailScroll:GetWidth() < 10 then
        C_Timer.After(0, function() if details:IsShown() then RenderDetails() end end)
    else
        RenderDetails()
    end
end

local function CreateDetails(area)
    local color = Style.COLOR
    blizzardDetails = _G.QuestMapFrame and _G.QuestMapFrame.DetailsFrame
    details = CreateFrame("Frame", "ForeverQuestsLogDetails", _G.QuestMapFrame or area, "BackdropTemplate")
    details:SetAllPoints(area)
    details:SetFrameLevel(area:GetFrameLevel() + 80)
    details:EnableMouse(true)
    Style.SetFlat(details, color.background)
    details:Hide()

    -- Kopf: Zurück | Name | Quest-ID; Rechtsklick auf den Kopf = dasselbe Menü wie im Tracker
    local header = HeaderBar(details, HEADER_HEIGHT)
    header:EnableMouse(true)
    header:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and detailQuestID then ns.QuestList.OpenMenu(self, detailQuestID) end
    end)
    local back = Style.CreateButton(header, "<", 22, 18, BackToList, ns.L("TIP_BACK"))
    back:SetPoint("LEFT", 5, 0)
    detailID = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailID:SetPoint("RIGHT", -8, 0)
    detailTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailTitle:SetPoint("LEFT", back, "RIGHT", 6, 0)
    detailTitle:SetPoint("RIGHT", detailID, "LEFT", -6, 0)
    detailTitle:SetJustifyH("LEFT")
    detailTitle:SetWordWrap(false)

    -- Knöpfe unten in zwei Reihen:
    --   oben:  Der Gruppe vorschlagen (bzw. Nicht mehr gemeinsam) | Teilen
    --   unten: Anheften | Abbrechen
    local footer = CreateFrame("Frame", nil, details)
    footer:SetPoint("BOTTOMLEFT", 6, 6)
    footer:SetPoint("BOTTOMRIGHT", -6, 6)
    footer:SetHeight(44)
    detailButtons = {}
    local function Act(fn) return function() if detailQuestID then fn(detailQuestID) end end end
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
    local function Row(buttons, y, reserve)
        local total = footer:GetWidth()
        local w = (total - reserve - 4 * (#buttons - 1)) / #buttons
        for i, button in ipairs(buttons) do
            button:SetWidth(w)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", footer, "TOPLEFT", (i - 1) * (w + 4), y)
        end
    end
    local function Layout()
        local total = footer:GetWidth()
        if not total or total < 50 then return end
        Row({ detailButtons.suggest, detailButtons.share }, 0, 0)
        Row({ detailButtons.pin, detailButtons.abandon }, -24, 0)
    end
    footer:SetScript("OnSizeChanged", Layout)

    detailScroll, detailContent = CreateScroll(details)
    detailScroll:SetPoint("TOPLEFT", 8, -(HEADER_HEIGHT + 6))
    detailScroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -2, 6)
    detailScroll:SetScript("OnSizeChanged", function() if details:IsShown() then RenderDetails() end end)

    -- Blizzards (unsichtbare) Detailansicht: unsere zeigt sich mit ihr und schließt mit ihr.
    -- Ein Blocker über ihr fängt die Maus ab, falls sie größer ist als unser Fenster.
    if blizzardDetails then
        blizzardDetails:SetAlpha(0)
        detailBlocker = CreateFrame("Frame", nil, details)
        detailBlocker:SetAllPoints(blizzardDetails)
        detailBlocker:SetFrameLevel(details:GetFrameLevel() - 1)
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
