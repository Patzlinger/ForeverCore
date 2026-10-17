-- ForeverMinimap – Map.lua: Form, Rahmen, Leiste (Zone, Uhr, Koordinaten), Knoepfe, Komfort
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local BAR_H = 22        -- Hoehe der Leiste
local TOOL = 18         -- Knopfgroesse in der Leiste (wenn die eigenen Knoepfe dort sitzen)
local ITEM = 26         -- Knopfgroesse in der senkrechten Knopfleiste
local STRIP_W = 32      -- Breite der senkrechten Knopfleiste (eine Spalte)
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ROUND_MASK = CIRCLE -- gleiche Kreismaske wie der Ring dahinter (deckungsgleich)

local bar, ring, edges, coordBox, pingText, strip
local tools = {}        -- eigene Knoepfe in Reihenfolge
local edgeButtons = {}  -- Minimap-Knoepfe am Rand (Forever-Knopf, andere Addons) – kommen in die Knopfleiste
local hovering = false

local function DB() return ns.GetDB() end

-- Fuer andere Addons (z. B. LibDBIcon) und die Forever-Knoepfe am Rand: Form der Minimap
function _G.GetMinimapShape()
    return DB().shape == "SQUARE" and "SQUARE" or "ROUND"
end

---------------------------------------------------------------------------
-- Form und Rahmen
---------------------------------------------------------------------------
-- Rahmen eckig: vier 1-px-Kanten aussen um Minimap und Leiste; rund: dunkler Ring hinter der Karte
local function BuildFrame()
    local container = Minimap:GetParent()
    ring = CreateFrame("Frame", nil, container)
    ring:SetFrameLevel(math.max(0, Minimap:GetFrameLevel() - 1))
    ring:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 2, -2)
    ring.tex = ring:CreateTexture(nil, "BACKGROUND")
    ring.tex:SetAllPoints()
    ring.tex:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    ring.mask = ring:CreateMaskTexture()
    ring.mask:SetAllPoints()
    ring.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    edges = CreateFrame("Frame", nil, Minimap)
    edges:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    edges.lines = {}
    for i = 1, 4 do
        local t = edges:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
        edges.lines[i] = t
    end
end

-- Kanten um ein Rechteck (oben links / unten rechts), 1 px ausserhalb
local function PlaceEdges(top, bottom)
    local l = edges.lines
    for _, t in ipairs(l) do t:ClearAllPoints() end
    l[1]:SetPoint("BOTTOMLEFT", top, "TOPLEFT", -1, 0) l[1]:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 1, 0) l[1]:SetHeight(1)
    l[2]:SetPoint("TOPLEFT", bottom, "BOTTOMLEFT", -1, 0) l[2]:SetPoint("TOPRIGHT", bottom, "BOTTOMRIGHT", 1, 0) l[2]:SetHeight(1)
    l[3]:SetPoint("TOPRIGHT", top, "TOPLEFT", 0, 0) l[3]:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMLEFT", 0, 0) l[3]:SetWidth(1)
    l[4]:SetPoint("TOPLEFT", top, "TOPRIGHT", 0, 0) l[4]:SetPoint("BOTTOMLEFT", bottom, "BOTTOMRIGHT", 0, 0) l[4]:SetWidth(1)
end

-- Kartengroesse (Blizzard-Standard 198 px); danach einmal neu zeichnen lassen (Zoom kurz hin und zurueck)
local BASE_SIZE = 198
local function ApplySize()
    local size = math.floor(BASE_SIZE * (DB().mapScale or 113) / 100 + 0.5)
    if math.abs(Minimap:GetWidth() - size) < 0.5 then return end
    Minimap:SetSize(size, size)
    local z = Minimap:GetZoom()
    local levels = Minimap:GetZoomLevels()
    pcall(Minimap.SetZoom, Minimap, z > 0 and z - 1 or math.min(z + 1, levels - 1))
    pcall(Minimap.SetZoom, Minimap, z)
end

function ns.ApplyShape()
    local d = DB()
    local square = d.shape == "SQUARE"
    ApplySize()
    pcall(Minimap.SetMaskTexture, Minimap, square and SQUARE_MASK or ROUND_MASK)
    -- Archaeologie-/Questbereich-Ringe passen nicht zur eckigen Karte
    if Minimap.SetArchBlobRingScalar then pcall(Minimap.SetArchBlobRingScalar, Minimap, square and 0 or 1) end
    if Minimap.SetQuestBlobRingScalar then pcall(Minimap.SetQuestBlobRingScalar, Minimap, square and 0 or 1) end
    if ring then
        if square then ring.tex:RemoveMaskTexture(ring.mask) else ring.tex:AddMaskTexture(ring.mask) end
        -- eckig zeichnen die Kanten den Rahmen (auch um die Leiste), rund der Ring
        ring:SetShown(d.border and not square)
        edges:SetShown(d.border and square)
    end
    if UI.RefreshMinimapButtons then UI.RefreshMinimapButtons() end
end

---------------------------------------------------------------------------
-- Blizzard-Teile ausblenden (nur Alpha, nicht anklickbar; Funktionen bleiben erreichbar)
---------------------------------------------------------------------------
local function BlizzParts()
    local mc = _G.MinimapCluster
    local list = {}
    local function Add(frame, children, noMouse)
        if frame then list[#list + 1] = { frame = frame, children = children, noMouse = noMouse or { frame } } end
    end
    if mc then
        Add(mc.ZoneTextButton, true)
        Add(mc.BorderTop, true)
        if mc.Tracking then Add(mc.Tracking, true, { mc.Tracking.Button }) end
        if mc.IndicatorFrame then
            Add(mc.IndicatorFrame, true, { mc.IndicatorFrame.MailFrame, mc.IndicatorFrame.CraftingOrderFrame })
        end
        Add(mc.InstanceDifficulty, true)
        Add(mc.DielFrame, true)
    end
    Add(_G.GameTimeFrame, true)
    Add(_G.TimeManagerClockButton, true)
    Add(_G.AddonCompartmentFrame, true)
    Add(_G.ExpansionLandingPageMinimapButton, true)
    Add(Minimap.ZoomIn, false)
    Add(Minimap.ZoomOut, false)
    Add(Minimap.ZoomHitArea, false)
    Add(_G.MinimapCompassTexture, false, {})
    Add(_G.MinimapCompassTextureUnderlay, false, {})
    return list
end

function ns.ApplyBlizzard()
    local d = DB()
    local hide = d.hideBlizzard
    for _, p in ipairs(BlizzParts()) do
        if hide then
            UI.HideBlizzard(p.frame, { children = p.children, noMouse = p.noMouse })
        else
            UI.ShowBlizzard(p.frame)
        end
    end
    -- Blizzards eigene Koordinaten unter der Karte (Einstellung minimapShowPlayerCoords): aus, solange unsere an sind
    local mc = _G.MinimapCluster
    local coords = mc and mc.MinimapContainer and mc.MinimapContainer.PlayerCoords
    if coords then
        if d.coords then UI.HideBlizzard(coords, { children = true, noMouse = {} }) else UI.ShowBlizzard(coords) end
    end
end

---------------------------------------------------------------------------
-- Leiste: Zonenname (in Gebietsfarbe), Schwierigkeit, Uhr
---------------------------------------------------------------------------
local ZONE_COLORS = {
    sanctuary = { 0.41, 0.80, 0.94 }, arena = { 1, 0.10, 0.10 }, friendly = { 0.10, 1, 0.10 },
    hostile = { 1, 0.10, 0.10 }, contested = { 1, 0.70, 0 }, combat = { 1, 0.10, 0.10 },
}

-- PvP-Art des Gebiets: Retail/Forever C_PvP.GetZonePVPInfo, aeltere Clients GetZonePVPInfo
local function ZonePVP()
    local fn = (C_PvP and C_PvP.GetZonePVPInfo) or _G.GetZonePVPInfo
    if not fn then return nil end
    local ok, pvp, isArena, faction = pcall(fn)
    if not ok then return nil end
    return pvp, isArena, faction
end

local function UpdateZone()
    if not bar then return end
    local d = DB()
    local text = GetMinimapZoneText and GetMinimapZoneText() or ""
    local pvp = ZonePVP()
    local col = ZONE_COLORS[pvp or ""] or C.accent
    bar.zone:SetTextColor(col[1], col[2], col[3])
    local suffix = ""
    if d.difficulty and GetInstanceInfo then
        local _, instanceType, _, difficultyName = GetInstanceInfo()
        if instanceType and instanceType ~= "none" and type(difficultyName) == "string" and difficultyName ~= "" then
            suffix = "  |cff8a8a8a" .. difficultyName .. "|r"
        end
    end
    bar.zone:SetText(text .. suffix)
end

local function ClockText()
    if _G.GameTime_GetTime then
        local ok, s = pcall(_G.GameTime_GetTime, false)
        if ok and type(s) == "string" then return s end
    end
    return date("%H:%M")
end

local function UpdateClock()
    if not bar then return end
    local show = DB().clock
    bar.clock:SetShown(show)
    if not show then return end
    bar.clock:SetText(ClockText())
    -- Wecker der Blizzard-Uhr klingelt: Uhr gold
    local cb = _G.TimeManagerClockButton
    if cb and cb.alarmFiring then
        bar.clock:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    else
        bar.clock:SetTextColor(0.85, 0.85, 0.85)
    end
end

-- Koordinaten (nur draussen; in Instanzen liefert das Spiel keine Position)
local function UpdateCoords()
    if not coordBox then return end
    if not DB().coords then coordBox:Hide() return end
    local x, y
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID and ns.CanRead(mapID) then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok and pos and pos.GetXY then
            x, y = pos:GetXY()
            if not (ns.CanRead(x, y) and type(x) == "number" and type(y) == "number") or (x == 0 and y == 0) then x = nil end
        end
    end
    if x then
        coordBox.text:SetFormattedText("%.1f  %.1f", x * 100, y * 100)
        coordBox:SetWidth(coordBox.text:GetStringWidth() + 10)
        coordBox:Show()
    else
        coordBox:Hide()
    end
end

local function ZoneTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(GetZoneText and GetZoneText() or "", 1, 1, 1)
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if sub ~= "" then GameTooltip:AddLine(sub, 0.85, 0.85, 0.85) end
    local pvp, _, faction = ZonePVP()
    local labels = {
        sanctuary = T("Zuflucht (kein PvP)", "Sanctuary (no PvP)"),
        friendly = faction and string.format(T("Freundlich (%s)", "Friendly (%s)"), faction) or T("Freundlich", "Friendly"),
        hostile = faction and string.format(T("Feindlich (%s)", "Hostile (%s)"), faction) or T("Feindlich", "Hostile"),
        contested = T("Umkämpft", "Contested"), arena = T("Freies PvP", "Free-for-all PvP"), combat = T("Kampfgebiet", "Combat zone"),
    }
    if pvp and labels[pvp] then
        local col = ZONE_COLORS[pvp] or C.accent
        GameTooltip:AddLine(labels[pvp], col[1], col[2], col[3])
    end
    if DB().barClickMap then GameTooltip:AddLine(T("Klick: Weltkarte", "Click: world map"), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function BuildBar()
    bar = CreateFrame("Button", "ForeverMinimapBar", Minimap, "BackdropTemplate")
    bar:SetHeight(BAR_H)
    bar:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    UI.SetFlat(bar, { C.header[1], C.header[2], C.header[3], 0.92 }, { 0, 0, 0, 0 })
    bar.line = bar:CreateTexture(nil, "ARTWORK")
    bar.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
    bar.line:SetHeight(1)
    bar.clock = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.clock:SetPoint("RIGHT", -7, 0)
    bar.zone = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.zone:SetPoint("LEFT", 7, 0)
    bar.zone:SetJustifyH("LEFT")
    bar.zone:SetWordWrap(false)
    bar:RegisterForClicks("LeftButtonUp")
    bar:SetScript("OnClick", function()
        if DB().barClickMap and ToggleWorldMap then ToggleWorldMap() end
    end)
    bar:SetScript("OnEnter", function(self) ZoneTooltip(self) ns.UpdateHover() end)
    bar:SetScript("OnLeave", function() GameTooltip_Hide() ns.UpdateHoverSoon() end)

    -- Uhr: eigener Knopf ueber dem Text (Links: Uhr/Wecker, Rechts: Kalender)
    bar.clockButton = CreateFrame("Button", nil, bar)
    bar.clockButton:SetPoint("TOPLEFT", bar.clock, "TOPLEFT", -3, 3)
    bar.clockButton:SetPoint("BOTTOMRIGHT", bar.clock, "BOTTOMRIGHT", 3, -3)
    bar.clockButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.clockButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ToggleCalendar then ToggleCalendar() end
        else
            if not _G.TimeManager_Toggle and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_TimeManager") end
            if _G.TimeManager_Toggle then _G.TimeManager_Toggle() end
        end
    end)
    bar.clockButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ClockText(), 1, 1, 1)
        if GetGameTime then
            local h, m = GetGameTime()
            GameTooltip:AddLine(string.format(T("Serverzeit %02d:%02d", "Server time %02d:%02d"), h, m), 0.85, 0.85, 0.85)
        end
        GameTooltip:AddLine(T("Links: Uhr und Wecker · Rechts: Kalender", "Left: clock and alarm · Right: calendar"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    bar.clockButton:SetScript("OnLeave", function() GameTooltip_Hide() ns.UpdateHoverSoon() end)

    -- Koordinaten unten mittig auf der Karte, kleiner dunkler Kasten
    coordBox = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
    coordBox:SetHeight(14)
    coordBox:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    coordBox:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
    UI.SetFlat(coordBox, { C.background[1], C.background[2], C.background[3], 0.7 }, { 0, 0, 0, 0 })
    coordBox:EnableMouse(false)
    coordBox.text = coordBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordBox.text:SetPoint("CENTER")
    coordBox.text:SetTextColor(0.85, 0.85, 0.85)

    -- Wer hat gepingt? (kurz oben auf der Karte)
    pingText = Minimap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pingText:SetPoint("TOP", Minimap, "TOP", 0, -6)
    pingText:Hide()
end

---------------------------------------------------------------------------
-- Eigene Knoepfe (flach wie die Knopfleiste von ForeverChat)
---------------------------------------------------------------------------
local function OpenTracking()
    local tb = _G.MinimapCluster and _G.MinimapCluster.Tracking and _G.MinimapCluster.Tracking.Button
    if tb and tb.OpenMenu then pcall(tb.OpenMenu, tb) end
end

local function OpenCompartment()
    local ac = _G.AddonCompartmentFrame
    if ac and ac.OpenMenu then pcall(ac.OpenMenu, ac) end
end

local function HasMail() return HasNewMail and HasNewMail() end
local function PendingInvites()
    return C_Calendar and C_Calendar.GetNumPendingInvites and (C_Calendar.GetNumPendingInvites() or 0) or 0
end

local TOOL_DEFS = {
    { key = "mail", icon = "Interface\\Icons\\INV_Letter_15",
      tip = function()
          GameTooltip:AddLine(T("Neue Post", "New mail"))
          if GetLatestThreeSenders then
              for _, sender in ipairs({ GetLatestThreeSenders() }) do GameTooltip:AddLine(sender, 1, 1, 1) end
          end
      end,
      shown = HasMail, alert = HasMail },
    { key = "tracking", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
      tip = function() GameTooltip:AddLine(T("Verfolgung", "Tracking")) GameTooltip:AddLine(T("Auch: Rechtsklick auf die Minimap", "Also: right-click the minimap"), 0.6, 0.6, 0.6) end,
      click = OpenTracking },
    { key = "calendar", icon = "Interface\\Icons\\INV_Misc_Note_05",
      tip = function()
          GameTooltip:AddLine(T("Kalender", "Calendar"))
          local n = PendingInvites()
          if n > 0 then GameTooltip:AddLine(string.format(T("%d offene Einladungen", "%d pending invites"), n), 1, 0.82, 0) end
      end,
      click = function() if ToggleCalendar then ToggleCalendar() end end,
      alert = function() return PendingInvites() > 0 end },
    { key = "addons", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      tip = function() GameTooltip:AddLine(T("Addon-Menü", "Addon menu")) GameTooltip:AddLine(T("Einträge anderer Addons", "Entries of other addons"), 0.6, 0.6, 0.6) end,
      click = OpenCompartment,
      shown = function() return _G.AddonCompartmentFrame ~= nil end },
}

local function ToolButton(def)
    local b = CreateFrame("Button", nil, Minimap, "BackdropTemplate")
    UI.SetFlat(b, { C.button[1], C.button[2], C.button[3], 0.85 })
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexture(def.icon)
    if def.icon ~= UI.LOGO then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b.def = def
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() if def.click then def.click() end end)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        def.tip()
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    b:SetScript("OnLeave", function(self)
        ns.UpdateTools()
        GameTooltip_Hide()
        ns.UpdateHoverSoon()
    end)
    return b
end

---------------------------------------------------------------------------
-- Senkrechte Knopfleiste neben der Minimap: eigene Knoepfe (Post, Verfolgung, Kalender, Addon-Menue) und die
-- Minimap-Knoepfe am Rand (Forever-Sammelknopf, andere Addons wie BugSack) – auf Wunsch nur bei Mausover.
-- Die Leiste ist genau so hoch wie Karte + Kopfleiste. Passen nicht alle Knoepfe hinein, wird der letzte Platz
-- ein Pfeil "weitere Knoepfe": aufgeklappt waechst die Leiste in weitere Spalten nach aussen (nie hoeher).
-- Fremde Knoepfe werden nur verschoben und verkleinert (keine Blizzard-Rahmen); Ziehen ist dort aus.
---------------------------------------------------------------------------
local GAP, PAD = 3, 3
local expanded = false
local moreButton

local function BuildStrip()
    strip = CreateFrame("Frame", "ForeverMinimapStrip", Minimap, "BackdropTemplate")
    strip:SetWidth(STRIP_W)
    strip:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    UI.SetFlat(strip, { C.header[1], C.header[2], C.header[3], 0.92 })
    strip:EnableMouse(true)
    strip:SetScript("OnEnter", function() ns.UpdateHover() end)
    strip:SetScript("OnLeave", function() ns.UpdateHoverSoon() end)

    -- Pfeil "weitere Knoepfe" (nur, wenn nicht alle in eine Spalte passen)
    moreButton = CreateFrame("Button", nil, strip, "BackdropTemplate")
    moreButton:SetSize(ITEM, ITEM)
    moreButton:SetFrameLevel(strip:GetFrameLevel() + 3)
    UI.SetFlat(moreButton, { C.button[1], C.button[2], C.button[3], 0.85 })
    moreButton.icon = moreButton:CreateTexture(nil, "ARTWORK")
    moreButton.icon:SetSize(12, 12)
    moreButton.icon:SetPoint("CENTER")
    moreButton.icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    moreButton:SetScript("OnClick", function()
        expanded = not expanded
        ns.UpdateTools()
    end)
    moreButton:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, DB().strip == "RIGHT" and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
        GameTooltip:AddLine(expanded and T("Weniger Knöpfe", "Fewer buttons") or T("Weitere Knöpfe", "More buttons"))
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    moreButton:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip_Hide()
        ns.UpdateHoverSoon()
    end)
end

-- fremden Knopf an seinen Platz in der Leiste setzen (auch, wenn sein Addon ihn spaeter zurueckschiebt)
local function PlaceForeign(b)
    if not b.fmmPoint then return end
    local s = ITEM / math.max(1, b:GetWidth())
    b.fmmPlacing = true
    b:SetScale(s)
    b:ClearAllPoints()
    b:SetPoint(b.fmmPoint, strip, b.fmmPoint, b.fmmX / s, b.fmmY / s)
    b:SetFrameLevel(strip:GetFrameLevel() + 2)
    b.fmmPlacing = false
end

local function SortedForeign()
    local list = {}
    for b in pairs(edgeButtons) do
        if b:IsShown() then list[#list + 1] = b end
    end
    table.sort(list, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
    return list
end

local function ToolVisible(b)
    local def = b.def
    return not def.shown or def.shown()
end

-- Knoepfe anordnen und ein-/ausblenden (Post/Einladung: goldener Rand, auch ohne Maus sichtbar)
function ns.UpdateTools()
    if not strip then return end
    local d = DB()
    local side = d.strip == "RIGHT" and "RIGHT" or "LEFT"
    local useStrip = d.strip == "LEFT" or d.strip == "RIGHT"
    local inBar = d.toolsInBar and d.bar
    local show = hovering or not d.stripMouseover
    if not hovering and d.stripMouseover then expanded = false end -- beim Verlassen wieder einklappen

    -- Hoehe = Karte + Kopfleiste; oben und unten buendig
    local barShown = d.bar and bar
    local topRef = (barShown and d.barPosition ~= "BOTTOM" and bar) or Minimap
    local bottomRef = (barShown and d.barPosition == "BOTTOM" and bar) or Minimap
    local height = Minimap:GetHeight() + (barShown and BAR_H or 0)
    strip:ClearAllPoints()
    if side == "RIGHT" then
        strip:SetPoint("TOPLEFT", topRef, "TOPRIGHT", 4, 0)
        strip:SetPoint("BOTTOMLEFT", bottomRef, "BOTTOMRIGHT", 4, 0)
    else
        strip:SetPoint("TOPRIGHT", topRef, "TOPLEFT", -4, 0)
        strip:SetPoint("BOTTOMRIGHT", bottomRef, "BOTTOMLEFT", -4, 0)
    end

    -- Liste der Knoepfe in der Leiste: eigene, dann fremde
    local items, prev = {}, nil
    for _, b in ipairs(tools) do
        local wanted = ToolVisible(b)
        local alert = b.def.alert and b.def.alert()
        b:ClearAllPoints()
        b.alert = alert
        if wanted and inBar then
            b:SetSize(TOOL, TOOL)
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -2, 0)
            else b:SetPoint("RIGHT", d.clock and bar.clock or bar, d.clock and "LEFT" or "RIGHT", d.clock and -6 or -4, 0) end
            prev = b
            b:SetShown(show or alert)
            b:SetAlpha(1)
        elseif wanted and useStrip then
            b:SetSize(ITEM, ITEM)
            items[#items + 1] = b
        else
            b:Hide()
        end
        if alert then
            b:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        elseif not b:IsMouseOver() then
            b:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end
    end
    if useStrip then
        for _, b in ipairs(SortedForeign()) do items[#items + 1] = b end
    end

    -- Platz je Spalte; reicht er nicht, wird der letzte Platz der Pfeil
    local perCol = math.max(1, math.floor((height - 2 * PAD + GAP) / (ITEM + GAP)))
    local overflow = #items > perCol
    local slots = #items
    if overflow then
        if expanded then slots = #items + 1 else slots = perCol end
    end
    local shownItems = (overflow and not expanded) and (perCol - 1) or #items
    local cols = math.max(1, math.ceil(slots / perCol))
    local point = side == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
    local dir = side == "RIGHT" and 1 or -1
    local function Slot(i) -- Spalte fuer Spalte von der Karte weg
        local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
        return dir * (PAD + col * (ITEM + GAP)), -(PAD + row * (ITEM + GAP))
    end
    for i, b in ipairs(items) do
        local isTool = b.def ~= nil
        if i <= shownItems then
            local x, y = Slot(i)
            if isTool then
                b:ClearAllPoints()
                b:SetPoint(point, strip, point, x, y)
                b:Show()
                b:SetAlpha((show or b.alert) and 1 or 0)
            else
                b.fmmPoint, b.fmmX, b.fmmY = point, x, y
                PlaceForeign(b)
                b:SetAlpha(show and 1 or 0)
                b:EnableMouse(true)
            end
        else
            -- eingeklappt: unsichtbar und nicht anklickbar auf dem Platz des Pfeils (bleibt eingesammelt)
            if isTool then
                b:Hide()
            else
                local x, y = Slot(perCol)
                b.fmmPoint, b.fmmX, b.fmmY = point, x, y
                PlaceForeign(b)
                b:SetAlpha(0)
                b:EnableMouse(false)
            end
        end
    end
    if overflow then
        local x, y = Slot(expanded and (#items + 1) or perCol)
        moreButton:ClearAllPoints()
        moreButton:SetPoint(point, strip, point, x, y)
        -- Pfeil zeigt nach aussen (aufklappen) bzw. zur Karte (einklappen)
        local outward = (side == "LEFT") ~= expanded
        moreButton.icon:SetRotation(outward and math.pi / 2 or -math.pi / 2)
        moreButton:Show()
    else
        moreButton:Hide()
    end
    strip:SetWidth(cols * (ITEM + GAP) - GAP + 2 * PAD)
    strip:SetShown(useStrip and #items > 0)
    strip:SetAlpha(show and 1 or 0)

    -- Zonenname bis an Knoepfe/Uhr heran (abgeschnitten statt ueberlappt)
    if bar and bar:IsShown() then
        local right = -7
        if d.clock then right = right - (bar.clock:GetStringWidth() + 8) end
        if inBar then
            for _, b in ipairs(tools) do if b:IsShown() then right = right - (TOOL + 2) end end
        end
        bar.zone:SetPoint("RIGHT", bar, "RIGHT", right, 0)
    end
end

---------------------------------------------------------------------------
-- Maus ueber Minimap/Leisten: Knoepfe zeigen
---------------------------------------------------------------------------
local function IsOverAny()
    if Minimap:IsMouseOver() or (bar and bar:IsShown() and bar:IsMouseOver()) then return true end
    if strip and strip:IsShown() and strip:IsMouseOver() then return true end
    for _, b in ipairs(tools) do if b:IsShown() and b:IsMouseOver() then return true end end
    for b in pairs(edgeButtons) do if b:IsShown() and b:IsMouseOver() then return true end end
    return false
end

function ns.UpdateHover()
    hovering = IsOverAny()
    ns.UpdateTools()
end

function ns.UpdateHoverSoon()
    C_Timer.After(0.1, ns.UpdateHover)
end

-- Minimap-Knoepfe am Rand einsammeln: benannte Knoepfe direkt an der Minimap, die nicht von Blizzard sind
local BLIZZ_PREFIX = { "Minimap", "MiniMap", "GameTime", "TimeManager", "Queue", "AddonCompartment", "ExpansionLanding" }
local OWN = { ForeverMinimapBar = true, ForeverMinimapStrip = true }
local function IsForeignButton(child)
    if not (child.GetObjectType and child:GetObjectType() == "Button") then return false end
    local name = child:GetName()
    if type(name) ~= "string" or OWN[name] then return false end
    for _, p in ipairs(BLIZZ_PREFIX) do if name:sub(1, #p) == p then return false end end
    return true
end

function ns.CollectEdgeButtons()
    local d = DB()
    if d.strip ~= "LEFT" and d.strip ~= "RIGHT" then return end
    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not edgeButtons[child] and IsForeignButton(child) then
            edgeButtons[child] = true
            child:HookScript("OnEnter", function() ns.UpdateHover() end)
            child:HookScript("OnLeave", function() ns.UpdateHoverSoon() end)
            child:HookScript("OnShow", function() ns.UpdateTools() end)
            child:HookScript("OnHide", function() ns.UpdateTools() end)
            -- sein Addon setzt ihn neu (z. B. nach Ziehen oder Formwechsel): zurueck an den Platz in der Leiste
            hooksecurefunc(child, "SetPoint", function(self) if not self.fmmPlacing then PlaceForeign(self) end end)
            if child.RegisterForDrag then child:RegisterForDrag() end -- in der Leiste nicht ziehbar
        end
    end
    ns.UpdateTools()
end

---------------------------------------------------------------------------
-- Komfort: Rechtsklick = Verfolgung, automatisch herauszoomen, wer hat gepingt
---------------------------------------------------------------------------
local zoomToken = 0
local function ScheduleZoomOut()
    if not DB().autoZoom then return end
    zoomToken = zoomToken + 1
    local token = zoomToken
    C_Timer.After(10, function()
        if token ~= zoomToken or not DB().autoZoom then return end
        if Minimap:GetZoom() > 0 then
            Minimap:SetZoom(0)
            if Minimap.ZoomIn then Minimap.ZoomIn:Enable() end
            if Minimap.ZoomOut then Minimap.ZoomOut:Disable() end
        end
    end)
end

local pingToken = 0
local function ShowPing(unit)
    if not (DB().pingNames and unit and pingText) then return end
    -- Name nur weiterreichen (im Kampf evtl. gesperrt: anzeigen ja, vergleichen nein)
    if not pcall(pingText.SetText, pingText, UnitName(unit)) then return end
    local _, class = UnitClass(unit)
    local col = ns.CanRead(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if col then pingText:SetTextColor(col.r, col.g, col.b) else pingText:SetTextColor(1, 1, 1) end
    pingText:Show()
    pingToken = pingToken + 1
    local token = pingToken
    C_Timer.After(3, function() if token == pingToken then pingText:Hide() end end)
end

---------------------------------------------------------------------------
-- Alles anwenden
---------------------------------------------------------------------------
function ns.ApplyAll()
    local d = DB()
    ns.ApplyShape()
    ns.ApplyBlizzard()
    if bar then
        bar:ClearAllPoints()
        bar.line:ClearAllPoints()
        if d.barPosition == "BOTTOM" then
            bar:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, 0)
            bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
            bar.line:SetPoint("TOPLEFT") bar.line:SetPoint("TOPRIGHT")
        else
            bar:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", 0, 0)
            bar:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", 0, 0)
            bar.line:SetPoint("BOTTOMLEFT") bar.line:SetPoint("BOTTOMRIGHT")
        end
        bar:SetShown(d.bar)
        -- eckiger Rahmen umschliesst Karte und Leiste
        if d.bar and d.barPosition == "BOTTOM" then PlaceEdges(Minimap, bar)
        elseif d.bar then PlaceEdges(bar, Minimap)
        else PlaceEdges(Minimap, Minimap) end
        -- Koordinaten nicht unter die Leiste legen
        coordBox:ClearAllPoints()
        coordBox:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
    end
    UpdateZone()
    UpdateClock()
    UpdateCoords()
    ns.UpdateHover()
end

function ns.SetupMap()
    if ns.mapReady or not Minimap then return end
    ns.mapReady = true
    BuildFrame()
    BuildBar()
    BuildStrip()
    for _, def in ipairs(TOOL_DEFS) do tools[#tools + 1] = ToolButton(def) end

    -- Blizzard setzt Form und Rahmen neu, wenn sich "Minimap drehen" aendert: danach wieder anwenden
    if _G.MinimapCluster and _G.MinimapCluster.UpdateMinimapConfig then
        hooksecurefunc(_G.MinimapCluster, "UpdateMinimapConfig", function() ns.ApplyShape() ns.ApplyBlizzard() end)
    end

    Minimap:HookScript("OnEnter", function() ns.UpdateHover() end)
    Minimap:HookScript("OnLeave", function() ns.UpdateHoverSoon() end)
    Minimap:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" and DB().rightClickTracking then OpenTracking() end
    end)
    hooksecurefunc(Minimap, "SetZoom", ScheduleZoomOut)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
        "PLAYER_DIFFICULTY_CHANGED", "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "CALENDAR_UPDATE_PENDING_INVITES",
        "MINIMAP_PING", "MINIMAP_UPDATE_ZOOM", "ADDON_LOADED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", ns.Safe(T("Ereignis", "Event"), function(_, event, arg1)
        if event == "MINIMAP_PING" then
            ShowPing(arg1)
        elseif event == "MINIMAP_UPDATE_ZOOM" then
            ScheduleZoomOut()
        elseif event == "ADDON_LOADED" then
            -- Blizzards Uhr (bei Bedarf geladen) und spaet geladene Addons mit Minimap-Knopf
            if arg1 == "Blizzard_TimeManager" then ns.ApplyBlizzard() end
            C_Timer.After(1, ns.CollectEdgeButtons)
        elseif event == "UPDATE_PENDING_MAIL" or event == "MAIL_CLOSED" or event == "CALENDAR_UPDATE_PENDING_INVITES" then
            ns.UpdateTools()
        else
            UpdateZone()
            if event == "PLAYER_ENTERING_WORLD" then ns.ApplyAll() end
        end
    end))

    -- Uhr und Koordinaten: ein sparsamer Takt (4x pro Sekunde), nur solange die Minimap sichtbar ist
    C_Timer.NewTicker(0.25, function()
        if not Minimap:IsVisible() then return end
        UpdateClock()
        UpdateCoords()
    end)

    ns.ApplyAll()
    C_Timer.After(2, ns.CollectEdgeButtons)
    C_Timer.After(6, ns.CollectEdgeButtons)
end

-- Bearbeitungsmodus oeffnen (Position und Groesse der Minimap verwaltet Blizzard)
function ns.OpenEditMode()
    if InCombatLockdown() then
        ns.Chat(T("Im Kampf nicht möglich.", "Not possible in combat."))
        return
    end
    if _G.EditModeManagerFrame and ShowUIPanel then ShowUIPanel(_G.EditModeManagerFrame) end
end
