local addonName, ns = ...

---------------------------------------------------------------------------
-- Questlog an der Weltkarte im Forever-Stil (Schritt 1)
--
-- Die Karte selbst bleibt Blizzards Karte (Questie-Symbole, Kartenklicks usw. unverändert). Neu:
--  * Rahmen, Titelleiste und Navigationsleiste der Karte im flachen Forever-Stil
--  * rechts statt Blizzards Questliste unsere eigene: alle Quests nach Gebiet, mit denselben Zeilen,
--    Tooltips, Rechtsklick-Menü (inkl. Questie), Angeheftet, "Gemeinsam" und Filtern wie der Tracker,
--    dazu Suche, Anzahl und ein Häkchen "verfolgen" je Quest
--  * Klick auf eine Quest öffnet Blizzards Detailansicht (eigene Detailansicht folgt in Schritt 2)
--
-- Blizzard-Funktionen werden nicht ersetzt: unsere Liste liegt nur über Blizzards Liste, Blizzards Rahmen
-- werden nur unsichtbar gemacht (Deckkraft 0). So bleiben Karte und Questlog auch im Kampf fehlerfrei.
-- Abschaltbar im Menü ("Questlog im Forever-Stil", gilt nach /reload).
---------------------------------------------------------------------------

local Style
local panel, scrollFrame, content, searchBox, searchHint, countText, filterButton
local logView
local updateQueued = false

local FILTER_KEY = "logFilters"
local HEADER_HEIGHT = 28

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
    button.fqBg = bg
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

    -- Titelleiste mit goldener Linie wie bei allen Forever-Fenstern; liegt über Blizzards (unsichtbarem) Rahmen
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
        -- loser Rahmen innen um die Karte
        Fade(border.InsetBorderTop)
    end
    Fade(map.NineSlice)
    Fade(map.Bg)
    Fade(map.PortraitContainer)

    -- Navigationsleiste; neue Knöpfe (beim Hineinzoomen) gleich mitgestalten
    SkinNavBar(map.NavBar)
    if type(_G.NavBar_AddButton) == "function" then
        hooksecurefunc("NavBar_AddButton", function(self)
            if self == map.NavBar then SkinNavBar(self) end
        end)
    end
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

function ns.UpdateQuestLog()
    updateQueued = false
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

-- Maus über einer Quest: ihr Gebiet auf der Karte hervorheben (wie bei Blizzards Liste)
local function HighlightOnMap(questID)
    local map = _G.WorldMapFrame
    if not map then return end
    if questID and map.SetHighlightedQuestID then
        pcall(map.SetHighlightedQuestID, map, questID)
    elseif map.ClearHighlightedQuestID then
        pcall(map.ClearHighlightedQuestID, map)
    end
end

local function CreatePanel(area)
    local color = Style.COLOR
    panel = CreateFrame("Frame", "ForeverQuestsLog", area, "BackdropTemplate")
    panel:SetAllPoints(area)
    -- über allen Teilen von Blizzards Liste; fängt deren Maus ab (Blizzards Liste darunter bleibt unberührt)
    panel:SetFrameLevel(area:GetFrameLevel() + 60)
    panel:EnableMouse(true)
    Style.SetFlat(panel, color.background)

    -- Kopfzeile: Suche | Anzahl | Filter
    local header = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(unpack(color.header))
    local accentLine = header:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("BOTTOMLEFT")
    accentLine:SetPoint("BOTTOMRIGHT")
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(color.accent[1], color.accent[2], color.accent[3], 0.6)

    filterButton = Style.CreateButton(header, ns.L("BTN_FILTER"), 42, 18, function(self)
        ns.QuestList.OpenFilterMenu(self, FILTER_KEY, ns.UpdateQuestLog)
    end, function(tooltip)
        tooltip:AddLine(ns.L("FILTER_TITLE"))
        tooltip:AddLine(ns.L("TIP_LOG_FILTER"), 1, 1, 1, true)
    end)
    filterButton:SetPoint("RIGHT", -5, 0)

    -- Anzahl der Quests im Log (rot, wenn voll), mit Tooltip
    local count = CreateFrame("Frame", nil, header)
    count:SetSize(44, 18)
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

    -- Liste mit Mausrad
    scrollFrame = CreateFrame("ScrollFrame", nil, panel)
    scrollFrame:SetPoint("TOPLEFT", 6, -(HEADER_HEIGHT + 6))
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 6)
    scrollFrame:EnableMouseWheel(true)
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)

    logView = ns.QuestList.NewView(content, "ForeverQuestsLog")
    logView.onHover = HighlightOnMap

    panel:SetScript("OnShow", RequestLogUpdate)
    panel:SetScript("OnHide", function() HighlightOnMap(nil) end)
    scrollFrame:SetScript("OnSizeChanged", RequestLogUpdate)

    -- Blizzards Detailansicht (Klick auf eine Quest) liegt an derselben Stelle: solange sie offen ist, ist
    -- unsere Liste weg, danach wieder da
    local details = _G.QuestMapFrame and _G.QuestMapFrame.DetailsFrame
    if details and details.HookScript then
        details:HookScript("OnShow", function() panel:Hide() end)
        details:HookScript("OnHide", function() panel:Show() end)
        if details:IsShown() then panel:Hide() end
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
end
