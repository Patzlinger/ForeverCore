-- ForeverMinimap – Map.lua: Form, Rahmen, Leiste (Zone, Ruhe, Haltbarkeit, Warteschlange, Uhr), Koordinaten,
-- Knopfleiste (eckig als Spalte, rund als Bogen um die Karte), Komfort (Zoom, Pings)
local _, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local BAR_H = 22        -- Hoehe der Leiste
local TOOL = 18         -- Knopfgroesse in der Leiste (wenn die eigenen Knoepfe dort sitzen)
local ITEM = 26         -- Knopfgroesse in der Knopfleiste
local STRIP_W = 32      -- Breite der Knopfleiste (eine Spalte)
local MARK = 16         -- kleine Anzeigen in der Leiste (Haltbarkeit, Warteschlange)
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ROUND_MASK = CIRCLE -- gleiche Kreismaske wie der Ring dahinter (deckungsgleich)

local bar, ring, edges, coordBox, pingText, strip
local tools = {}        -- eigene Knoepfe in Reihenfolge
local edgeButtons = {}  -- Minimap-Knoepfe am Rand (Forever-Knopf, andere Addons) – kommen in die Knopfleiste
local hovering = false

local function DB() return ns.GetDB() end
local function IsRound() return DB().shape ~= "SQUARE" end

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
-- Leiste: Zonenname (Gebietsfarbe), Ruhe-Hinweis, Schwierigkeit
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
    -- Ruhegebiet (Stadt, Gasthaus): dezentes "zZ" direkt hinter dem Namen
    if d.restInfo and IsResting and IsResting() then suffix = suffix .. "  |cff7f9fd0zZ|r" end
    if d.difficulty and GetInstanceInfo then
        local _, instanceType, _, difficultyName = GetInstanceInfo()
        if instanceType and instanceType ~= "none" and type(difficultyName) == "string" and difficultyName ~= "" then
            suffix = suffix .. "  |cff8a8a8a" .. difficultyName .. "|r"
        end
    end
    bar.zone:SetText(text .. suffix)
end

---------------------------------------------------------------------------
-- Uhr: Ortszeit oder Serverzeit, 24 oder 12 Stunden (eigene Einstellung)
---------------------------------------------------------------------------
local function ClockText(source)
    local d = DB()
    source = source or d.clockSource
    local h, m
    if source == "SERVER" and GetGameTime then
        h, m = GetGameTime()
    else
        local t = date("*t")
        h, m = t.hour, t.min
    end
    if d.clock24 ~= false then return string.format("%02d:%02d", h, m) end
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d %s", h12, m, h < 12 and "AM" or "PM")
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

---------------------------------------------------------------------------
-- Koordinaten (nur draussen; in Instanzen liefert das Spiel keine Position) – Klick setzt eine Kartenmarkierung
---------------------------------------------------------------------------
local function PlayerPosition()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not (mapID and ns.CanRead(mapID)) then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not (ok and pos and pos.GetXY) then return end
    local x, y = pos:GetXY()
    if not (ns.CanRead(x, y) and type(x) == "number" and type(y) == "number") or (x == 0 and y == 0) then return end
    return mapID, x, y
end

local function UpdateCoords()
    if not coordBox then return end
    if not DB().coords then coordBox:Hide() return end
    local mapID, x, y = PlayerPosition()
    if mapID then
        coordBox.text:SetFormattedText("%.1f  %.1f", x * 100, y * 100)
        coordBox:SetWidth(coordBox.text:GetStringWidth() + 10)
        coordBox:Show()
    else
        coordBox:Hide()
    end
end

local function SetWaypointHere()
    local mapID, x, y = PlayerPosition()
    if not (mapID and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
        ns.Chat(T("Auf dieser Karte geht keine Markierung.", "No waypoint possible on this map."))
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true
end

local function CoordClick(_, button)
    if button == "RightButton" then
        if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
        ns.Chat(T("Kartenmarkierung entfernt.", "Waypoint removed."))
        return
    end
    if not SetWaypointHere() then return end
    if IsShiftKeyDown() then
        -- Link nur in eine schon offene Chat-Eingabe einfuegen (die Eingabe selbst oeffnen wir nicht)
        local link = C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
        if not (link and ChatEdit_InsertLink and ChatEdit_InsertLink(link)) then
            ns.Chat(T("Markierung gesetzt. Zum Teilen erst die Chat-Eingabe öffnen, dann Umschalt-Klick.",
                "Waypoint set. To share it, open the chat input first, then shift-click."))
        end
    else
        ns.Chat(T("Kartenmarkierung gesetzt.", "Waypoint set."))
    end
end

---------------------------------------------------------------------------
-- Haltbarkeit: kleines Amboss-Symbol in der Leiste, sobald ein Teil unter die Grenze faellt
---------------------------------------------------------------------------
local DURA_LIMIT = 30
local function Durability()
    local lowest, list = 100, {}
    if not GetInventoryItemDurability then return lowest, list end
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = math.floor(cur / max * 100 + 0.5)
            if pct < 100 then list[#list + 1] = { slot = slot, pct = pct } end
            if pct < lowest then lowest = pct end
        end
    end
    table.sort(list, function(a, b) return a.pct < b.pct end)
    return lowest, list
end

local function UpdateDurability()
    if not bar then return end
    local lowest = Durability()
    local show = DB().durability and lowest < DURA_LIMIT
    bar.dura:SetShown(show)
    if show then
        -- unter 10 % (oder kaputt): rot, sonst orange
        if lowest < 10 then bar.dura.icon:SetVertexColor(1, 0.35, 0.3) else bar.dura.icon:SetVertexColor(1, 0.75, 0.35) end
    end
end

---------------------------------------------------------------------------
-- Warteschlangen-Auge: in der Leiste, solange ForeverBars es nicht in seiner eigenen Leiste fuehrt
---------------------------------------------------------------------------
local function BarsOwnsQueue()
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverBars")) then return false end
    local bdb = _G.ForeverBarsDB
    local q = bdb and bdb.bars and bdb.bars.queue
    return q and q.enabled == true
end

local function QueueDocked()
    return DB().queueDock and _G.QueueStatusButton ~= nil and not BarsOwnsQueue()
end

local queueX = -40 -- Platz in der Leiste (von rechts), wird beim Anordnen gesetzt
local function PlaceQueue()
    local q = _G.QueueStatusButton
    if not (q and bar and QueueDocked()) then return end
    q.fmmPlacing = true
    if q.SetIgnoreParentAlpha then q:SetIgnoreParentAlpha(true) end -- Elternrahmen (z. B. Mikromenue) evtl. unsichtbar
    local pScale = (q:GetParent() and q:GetParent():GetEffectiveScale()) or 1
    q:SetScale((MARK + 4) * bar:GetEffectiveScale() / (math.max(1, q:GetWidth()) * pScale))
    local k = bar:GetEffectiveScale() / q:GetEffectiveScale()
    q:ClearAllPoints()
    q:SetPoint("RIGHT", bar, "RIGHT", queueX * k, 0)
    q:SetFrameStrata(bar:GetFrameStrata())
    q:SetFrameLevel(bar:GetFrameLevel() + 4)
    q.fmmPlacing = false
end

---------------------------------------------------------------------------
-- Leiste bauen
---------------------------------------------------------------------------
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
    if IsResting and IsResting() then GameTooltip:AddLine(T("Ruhegebiet: Erholung wird gesammelt (zZ)", "Resting area: rested XP builds up (zZ)"), 0.5, 0.62, 0.82) end
    if DB().barClickMap then GameTooltip:AddLine(T("Klick: Weltkarte", "Click: world map"), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function SmallFlat(parent, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size, size)
    UI.SetFlat(b, { C.button[1], C.button[2], C.button[3], 0.85 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    return b
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
        GameTooltip:AddDoubleLine(T("Ortszeit", "Local time"), ClockText("LOCAL"), 0.85, 0.85, 0.85, 1, 1, 1)
        GameTooltip:AddDoubleLine(T("Serverzeit", "Server time"), ClockText("SERVER"), 0.85, 0.85, 0.85, 1, 1, 1)
        GameTooltip:AddLine(T("Links: Uhr und Wecker · Rechts: Kalender", "Left: clock and alarm · Right: calendar"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    bar.clockButton:SetScript("OnLeave", function() GameTooltip_Hide() ns.UpdateHoverSoon() end)

    -- Haltbarkeit (nur bei niedrigem Wert)
    bar.dura = SmallFlat(bar, MARK)
    bar.dura:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.dura.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    bar.dura.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.dura:Hide()
    bar.dura:SetScript("OnClick", function()
        if ToggleCharacter and not InCombatLockdown() then ToggleCharacter("PaperDollFrame") end
    end)
    bar.dura:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local lowest, list = Durability()
        GameTooltip:AddLine(string.format(T("Haltbarkeit: %d %%", "Durability: %d %%"), lowest))
        for i, e in ipairs(list) do
            if i > 8 then break end
            local link = GetInventoryItemLink and GetInventoryItemLink("player", e.slot)
            local r = e.pct < 10 and 1 or (e.pct < DURA_LIMIT and 1 or 0.85)
            local g = e.pct < 10 and 0.35 or (e.pct < DURA_LIMIT and 0.75 or 0.85)
            GameTooltip:AddDoubleLine(link or ("#" .. e.slot), e.pct .. " %", 1, 1, 1, r, g, 0.3)
        end
        GameTooltip:AddLine(T("Klick: Charakterfenster", "Click: character window"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    bar.dura:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip_Hide()
        ns.UpdateHoverSoon()
    end)

    -- Koordinaten unten mittig auf der Karte; Klick: Kartenmarkierung
    coordBox = CreateFrame("Button", nil, Minimap, "BackdropTemplate")
    coordBox:SetHeight(14)
    coordBox:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    coordBox:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
    UI.SetFlat(coordBox, { C.background[1], C.background[2], C.background[3], 0.7 }, { 0, 0, 0, 0 })
    coordBox:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    coordBox:SetScript("OnClick", CoordClick)
    coordBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(T("Koordinaten", "Coordinates"))
        GameTooltip:AddLine(T("Klick: Kartenmarkierung hier setzen", "Click: set a waypoint here"), 1, 1, 1)
        GameTooltip:AddLine(T("Umschalt-Klick: zusätzlich in die offene Chat-Eingabe", "Shift-click: also into the open chat input"), 1, 1, 1)
        GameTooltip:AddLine(T("Rechtsklick: Markierung entfernen", "Right-click: remove waypoint"), 1, 1, 1)
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    coordBox:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        GameTooltip_Hide()
        ns.UpdateHoverSoon()
    end)
    coordBox.text = coordBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordBox.text:SetPoint("CENTER")
    coordBox.text:SetTextColor(0.85, 0.85, 0.85)

    -- Wer hat gepingt? (kurz oben auf der Karte)
    pingText = Minimap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pingText:SetPoint("TOP", Minimap, "TOP", 0, -6)
    pingText:Hide()
end

-- Anzeigen rechts in der Leiste anordnen: Uhr ganz rechts, davor Warteschlange und Haltbarkeit (nah an der Uhr);
-- liefert den freien Rand fuer weitere Knoepfe und den Zonennamen
local function LayoutBar()
    local d = DB()
    local x = -7
    if d.clock then x = x - (bar.clock:GetStringWidth() + 6) end
    local q = _G.QueueStatusButton
    if q and QueueDocked() and q:IsShown() then
        queueX = x
        PlaceQueue()
        x = x - (MARK + 4) - 3
    end
    if bar.dura:IsShown() then
        bar.dura:ClearAllPoints()
        bar.dura:SetPoint("RIGHT", bar, "RIGHT", x, 0)
        x = x - MARK - 3
    end
    return x
end

---------------------------------------------------------------------------
-- Eigene Knoepfe (flach wie die Knopfleiste von ForeverChat)
---------------------------------------------------------------------------
local function OpenTracking()
    local tb = _G.MinimapCluster and _G.MinimapCluster.Tracking and _G.MinimapCluster.Tracking.Button
    if tb and tb.OpenMenu then pcall(tb.OpenMenu, tb) end
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
    -- Fernglas fuellt sein Symbol mehr aus als die anderen: etwas mehr Innenabstand
    { key = "tracking", icon = "Interface\\Icons\\INV_Misc_Spyglass_03", inset = 4,
      tip = function() GameTooltip:AddLine(T("Verfolgung", "Tracking")) GameTooltip:AddLine(T("Auch: Rechtsklick auf die Minimap", "Also: right-click the minimap"), 0.6, 0.6, 0.6) end,
      click = OpenTracking },
    { key = "calendar", calendar = true,
      tip = function()
          GameTooltip:AddLine(T("Kalender", "Calendar"))
          local n = PendingInvites()
          if n > 0 then GameTooltip:AddLine(string.format(T("%d offene Einladungen", "%d pending invites"), n), 1, 0.82, 0) end
      end,
      click = function() if ToggleCalendar then ToggleCalendar() end end,
      alert = function() return PendingInvites() > 0 end },
    -- (kein Knopf fuer Blizzards Addon-Menue: die Addons sitzen mit ihren eigenen Knoepfen schon in der Leiste)
    { key = "settings", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      tip = function() GameTooltip:AddLine(T("ForeverMinimap-Einstellungen", "ForeverMinimap settings")) GameTooltip:AddLine("/fmm", 0.6, 0.6, 0.6) end,
      click = function() if ns.ToggleOptions then ns.ToggleOptions() end end },
}

-- heutiger Tag (fuer das Kalendersymbol)
local function Today()
    local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    return (t and t.monthDay) or tonumber(date("%d"))
end

local function HasAtlas(name) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil end

-- Kalendersymbol: 1. Blizzards Kalender mit eingezeichnetem Tag (Retail-Grafik), 2. klassisches Kalenderblatt
-- mit dunkler Tageszahl, 3. Notizzettel mit heller Zahl
local function SetCalendarIcon(b)
    local day = Today()
    if b.calendarDay == day then return end
    b.calendarDay = day
    local atlas = "ui-hud-calendar-" .. day .. "-up"
    b.icon:SetTexCoord(0, 1, 0, 1)
    if HasAtlas(atlas) then
        b.icon:SetAtlas(atlas)
        b.day:Hide()
        return
    end
    if b.icon:SetTexture("Interface\\Calendar\\UI-Calendar-Button") then
        b.icon:SetTexCoord(0, 0.390625, 0, 0.78125)
        b.day:SetTextColor(0.1, 0.1, 0.1)
        b.day:SetShadowColor(0, 0, 0, 0)
    else
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_05")
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.day:SetTextColor(1, 1, 1)
        b.day:SetShadowColor(0, 0, 0, 1)
    end
    b.day:SetText(day)
    b.day:Show()
end

---------------------------------------------------------------------------
-- Rund oder eckig: gleicher Knopf, zwei Looks (rund im runden Kartenmodus, damit alles zusammenpasst)
---------------------------------------------------------------------------
local function NewMask(frame, anchor, inset)
    local m = frame:CreateMaskTexture()
    m:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset or 0, -(inset or 0))
    m:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -(inset or 0), inset or 0)
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return m
end

-- runde Teile einmalig anlegen: Ring (Randfarbe), Scheibe (Knopffarbe), Kreismaske fuer das Symbol
local function EnsureRound(b)
    if b.fmmRound then return b.fmmRound end
    local r = {}
    r.ring = b:CreateTexture(nil, "BACKGROUND", nil, -7)
    r.ring:SetAllPoints()
    r.ring:SetColorTexture(1, 1, 1, 1)
    r.ring:AddMaskTexture(NewMask(b, b, 0))
    r.disc = b:CreateTexture(nil, "BACKGROUND", nil, -6)
    r.disc:SetPoint("TOPLEFT", 1, -1)
    r.disc:SetPoint("BOTTOMRIGHT", -1, 1)
    r.disc:SetColorTexture(C.button[1], C.button[2], C.button[3], 0.9)
    r.disc:AddMaskTexture(NewMask(b, b, 1))
    local icon = b.fmmIcon or b.icon
    if icon then r.iconMask = NewMask(b, icon, 0) end
    r.icon = icon
    b.fmmRound = r
    return r
end

-- Look umschalten; gold = Hover oder Hinweis (Post, Einladung)
local function StyleItem(b, round, gold)
    local edge = gold and C.accent or C.border
    if round then
        local r = EnsureRound(b)
        r.ring:Show() r.disc:Show()
        r.ring:SetVertexColor(edge[1], edge[2], edge[3], 1)
        if r.icon and not r.masked then r.icon:AddMaskTexture(r.iconMask) r.masked = true end
    elseif b.fmmRound then
        local r = b.fmmRound
        r.ring:Hide() r.disc:Hide()
        if r.icon and r.masked then r.icon:RemoveMaskTexture(r.iconMask) r.masked = false end
    end
    -- eigene Knoepfe: Backdrop; fremde: eigene Kanten/Flaeche (fmmSquareParts)
    if b.fmmTool then
        if round then
            b:SetBackdropColor(0, 0, 0, 0)
            b:SetBackdropBorderColor(0, 0, 0, 0)
        else
            b:SetBackdropColor(C.button[1], C.button[2], C.button[3], 0.85)
            b:SetBackdropBorderColor(edge[1], edge[2], edge[3], gold and 0.9 or 1)
        end
    end
    for _, t in ipairs(b.fmmSquareParts or {}) do t:SetShown(not round) end
end

local function ToolButton(def)
    local b = CreateFrame("Button", nil, Minimap, "BackdropTemplate")
    UI.SetFlat(b, { C.button[1], C.button[2], C.button[3], 0.85 })
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b.fmmTool = true
    local inset = def.inset or 2
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", inset, -inset)
    b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    if def.calendar then
        b.day = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.day:SetPoint("CENTER", 0, -2)
        b.day:SetShadowOffset(1, -1)
        SetCalendarIcon(b)
    else
        b.icon:SetTexture(def.icon)
        if def.icon ~= UI.LOGO then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    b.def = def
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function() if def.click then def.click() end end)
    b:SetScript("OnEnter", function(self)
        StyleItem(self, IsRound() and self.fmmInStrip, true)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        def.tip()
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    b:SetScript("OnLeave", function()
        ns.UpdateTools()
        GameTooltip_Hide()
        ns.UpdateHoverSoon()
    end)
    return b
end

---------------------------------------------------------------------------
-- Knopfleiste neben der Minimap: eigene Knoepfe (Post, Verfolgung, Kalender, Einstellungen), ein dezenter
-- Trennstrich, dann die Minimap-Knoepfe am Rand (Forever-Sammelknopf, andere Addons wie BugSack).
--   eckig: senkrechte Spalte, genau so hoch wie Karte + Kopfleiste; reicht der Platz nicht, wird der letzte Platz
--          ein Pfeil "weitere Knoepfe" und die Leiste waechst in weitere Spalten nach aussen (nie hoeher)
--   rund:  runde Knoepfe auf einem Bogen um die Karte; aufgeklappt ein zweiter Bogen weiter aussen
-- Fremde Knoepfe (keine Blizzard-Rahmen) bekommen auf Wunsch denselben Look wie die eigenen; ihre Klicks,
-- Tooltips und Menues bleiben unveraendert; Ziehen ist in der Leiste aus.
---------------------------------------------------------------------------
local GAP, PAD, SEP = 3, 3, 9
local expanded = false
local moreButton, separator

local function BuildStrip()
    strip = CreateFrame("Frame", "ForeverMinimapStrip", Minimap, "BackdropTemplate")
    strip:SetWidth(STRIP_W)
    strip:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    UI.SetFlat(strip, { C.header[1], C.header[2], C.header[3], 0.92 })
    strip:EnableMouse(true)
    strip:SetScript("OnEnter", function() ns.UpdateHover() end)
    strip:SetScript("OnLeave", function() ns.UpdateHoverSoon() end)

    -- dezenter Strich zwischen eigenen Knoepfen und denen der Addons
    separator = strip:CreateTexture(nil, "ARTWORK")
    separator:SetColorTexture(1, 1, 1, 0.14)
    separator:SetSize(ITEM - 6, 1)

    -- Pfeil "weitere Knoepfe" (nur, wenn nicht alle hineinpassen)
    moreButton = SmallFlat(strip, ITEM)
    moreButton.fmmTool = true
    moreButton:SetFrameLevel(strip:GetFrameLevel() + 3)
    moreButton.icon:ClearAllPoints()
    moreButton.icon:SetSize(12, 12)
    moreButton.icon:SetPoint("CENTER")
    moreButton.icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    moreButton:SetScript("OnClick", function()
        expanded = not expanded
        ns.UpdateTools()
    end)
    moreButton:SetScript("OnEnter", function(self)
        StyleItem(self, IsRound(), true)
        GameTooltip:SetOwner(self, DB().strip == "RIGHT" and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
        GameTooltip:AddLine(expanded and T("Weniger Knöpfe", "Fewer buttons") or T("Weitere Knöpfe", "More buttons"))
        GameTooltip:Show()
        ns.UpdateHover()
    end)
    moreButton:SetScript("OnLeave", function(self)
        StyleItem(self, IsRound(), false)
        GameTooltip_Hide()
        ns.UpdateHoverSoon()
    end)
end

-- runde Minimap-Grafik (Rahmen, Hintergrund, Hover-Schein) erkennen: per Datei oder Lage im Knopf
local ROUND_ART = {
    ["interface\\minimap\\minimap-trackingborder"] = true, ["interface\\minimap\\ui-minimap-background"] = true,
    ["interface\\minimap\\ui-minimap-zoombutton-highlight"] = true,
    [136430] = true, [136467] = true, [136477] = true,
}
local function IsRoundArt(tex)
    local f = tex.GetTexture and tex:GetTexture()
    if type(f) == "string" then
        if ROUND_ART[f:lower():gsub("/", "\\")] then return true end
    elseif f and ROUND_ART[f] then
        return true
    end
    local layer = tex.GetDrawLayer and tex:GetDrawLayer()
    if layer == "BACKGROUND" then return true end                           -- runder Hintergrund
    if layer == "OVERLAY" and (tex:GetWidth() or 0) >= 45 then return true end -- grosser Ring um den Knopf
    return false
end

-- fremden Knopf in den eigenen Look bringen (einmalig)
local function SkinForeign(b)
    if b.fmmSkinned then return end
    b.fmmSkinned = true
    local icon = b.icon or b.Icon
    for _, r in ipairs({ b:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r ~= icon then
            if IsRoundArt(r) then
                r:SetAlpha(0)
            elseif not icon and r:GetDrawLayer() == "ARTWORK" then
                icon = r
            end
        end
    end
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then hl:SetAlpha(0) end
    -- eckig: flache Flaeche, feiner Rand, goldener Rand beim Darueberfahren (Ebene HIGHLIGHT zeigt sich von selbst)
    b.fmmSquareParts = {}
    local bg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(C.button[1], C.button[2], C.button[3], 0.85)
    tinsert(b.fmmSquareParts, bg)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        for _, layer in ipairs({ "BORDER", "HIGHLIGHT" }) do
            local e = b:CreateTexture(nil, layer, nil, 7)
            if layer == "BORDER" then e:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
            else e:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9) end
            e:SetPoint(side[1]) e:SetPoint(side[2])
            if side[3] then e:SetWidth(side[3]) else e:SetHeight(side[4]) end
            tinsert(b.fmmSquareParts, e)
        end
    end
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    b.fmmIcon = icon
    -- rund: goldener Ring beim Darueberfahren
    b:HookScript("OnEnter", function(self) if IsRound() and self.fmmRound then StyleItem(self, true, true) end end)
    b:HookScript("OnLeave", function(self) if IsRound() and self.fmmRound then StyleItem(self, true, false) end end)
end

-- fremden Knopf an seinen Platz setzen (auch, wenn sein Addon ihn spaeter zurueckschiebt)
local function PlaceForeign(b)
    if not b.fmmRel then return end
    b.fmmPlacing = true
    if DB().squareForeign then
        SkinForeign(b)
        b:SetScale(1)
        b:SetSize(ITEM, ITEM)
        b:ClearAllPoints()
        b:SetPoint(b.fmmPoint, b.fmmRel, b.fmmRelPoint, b.fmmX, b.fmmY)
        StyleItem(b, IsRound(), false)
    else
        local s = ITEM / math.max(1, b:GetWidth())
        b:SetScale(s)
        b:ClearAllPoints()
        b:SetPoint(b.fmmPoint, b.fmmRel, b.fmmRelPoint, b.fmmX / s, b.fmmY / s)
    end
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

-- Plaetze fuer die Eintraege berechnen. Rueckgabe: je Eintrag { point, rel, relPoint, x, y, angle } oder false
-- (eingeklappt/nicht sichtbar), Platz des Pfeils, Breite der Leiste
local function LayoutSquare(items, side, height)
    local avail = height - 2 * PAD
    local total = 0
    for i, it in ipairs(items) do total = total + it.h + (i > 1 and GAP or 0) end
    local overflow = total > avail
    local point = side == "RIGHT" and "TOPLEFT" or "TOPRIGHT"
    local dir = side == "RIGHT" and 1 or -1
    local col, y = 0, 0
    local function Next(h)
        if y > 0 and y + h > avail then col, y = col + 1, 0 end
        local px, py = dir * (PAD + col * (ITEM + GAP)), -(PAD + y)
        y = y + h + GAP
        return { point = point, rel = strip, relPoint = point, x = px, y = py }
    end
    local positions, stop = {}, false
    for i, it in ipairs(items) do
        if overflow and not expanded and y + it.h > avail - (ITEM + GAP) then stop = true end
        if stop or (it.sep and y == 0 and col > 0) then positions[i] = false
        else positions[i] = Next(it.h) end
    end
    local more
    if overflow then
        if expanded then more = Next(ITEM)
        else more = { point = point, rel = strip, relPoint = point, x = dir * PAD, y = -(PAD + avail - ITEM) } end
    end
    local cols = (overflow and not expanded) and 1 or (col + 1)
    return positions, more, cols * (ITEM + GAP) - GAP + 2 * PAD
end

local function LayoutRound(items, side)
    local mapR = Minimap:GetWidth() / 2
    local baseR = mapR + ITEM / 2 + 5
    local maxSpan = math.rad(150)               -- Bogen von oben-seitlich bis unten-seitlich
    local center = side == "RIGHT" and 0 or math.pi
    local dirA = side == "RIGHT" and -1 or 1    -- Richtung "nach unten" auf dem Bogen
    local total = 0
    for i, it in ipairs(items) do total = total + (it.h + (i > 1 and GAP or 0)) / baseR end
    local overflow = total > maxSpan
    local ringNo, used = 0, 0
    local function Next(h)
        local r = baseR + ringNo * (ITEM + GAP)
        local need = (h + GAP) / r
        if used > 0 and used + h / r > maxSpan then ringNo, used = ringNo + 1, 0 r = baseR + ringNo * (ITEM + GAP) need = (h + GAP) / r end
        local a = center - dirA * (maxSpan / 2) + dirA * (used + (h / 2) / r)
        used = used + need
        return { point = "CENTER", rel = Minimap, relPoint = "CENTER", x = math.cos(a) * r, y = math.sin(a) * r, angle = a }
    end
    local positions, stop = {}, false
    for i, it in ipairs(items) do
        if overflow and not expanded and used + (it.h + ITEM + 2 * GAP) / baseR > maxSpan then stop = true end
        if stop or (it.sep and used == 0 and ringNo > 0) then positions[i] = false
        else positions[i] = Next(it.h) end
    end
    local more
    if overflow then more = Next(ITEM) end
    local rings = (overflow and not expanded) and 1 or (ringNo + 1)
    return positions, more, rings * (ITEM + GAP) + 10
end

-- Knoepfe anordnen und ein-/ausblenden (Post/Einladung: goldener Rand, auch ohne Maus sichtbar)
function ns.UpdateTools()
    if not strip then return end
    local d = DB()
    local side = d.strip == "RIGHT" and "RIGHT" or "LEFT"
    local useStrip = d.strip == "LEFT" or d.strip == "RIGHT"
    local inBar = d.toolsInBar and d.bar
    local round = IsRound()
    local show = hovering or not d.stripMouseover
    if not hovering and d.stripMouseover then expanded = false end -- beim Verlassen wieder einklappen

    -- Leiste rechts anordnen (Uhr, Warteschlange, Haltbarkeit); der Rest ist Platz fuer Knoepfe und Zonennamen
    local barX = -7
    if bar and bar:IsShown() then barX = LayoutBar() end

    -- Flaeche der Knopfleiste: eckig neben Karte + Kopfleiste (oben/unten buendig); rund unsichtbar, nur fuer die Maus
    local barShown = d.bar and bar
    local topRef = (barShown and d.barPosition ~= "BOTTOM" and bar) or Minimap
    local bottomRef = (barShown and d.barPosition == "BOTTOM" and bar) or Minimap
    local height = Minimap:GetHeight() + (barShown and BAR_H or 0)
    strip:ClearAllPoints()
    if round then topRef, bottomRef = Minimap, Minimap end
    if side == "RIGHT" then
        strip:SetPoint("TOPLEFT", topRef, "TOPRIGHT", round and 0 or 4, 0)
        strip:SetPoint("BOTTOMLEFT", bottomRef, "BOTTOMRIGHT", round and 0 or 4, 0)
    else
        strip:SetPoint("TOPRIGHT", topRef, "TOPLEFT", round and 0 or -4, 0)
        strip:SetPoint("BOTTOMRIGHT", bottomRef, "BOTTOMLEFT", round and 0 or -4, 0)
    end

    -- Eintraege: eigene Knoepfe, Trennstrich, fremde Knoepfe
    local items, prev = {}, nil
    local ownCount = 0
    for _, b in ipairs(tools) do
        local wanted = ToolVisible(b)
        b.alert = b.def.alert and b.def.alert()
        b.fmmInStrip = false
        b:ClearAllPoints()
        if b.def.calendar then SetCalendarIcon(b) end -- neuer Tag
        if wanted and inBar then
            b:SetSize(TOOL, TOOL)
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -2, 0)
            else b:SetPoint("RIGHT", bar, "RIGHT", barX, 0) end
            prev = b
            b:SetShown(show or b.alert)
            b:SetAlpha(1)
            StyleItem(b, false, b.alert or b:IsMouseOver())
        elseif wanted and useStrip then
            b:SetSize(ITEM, ITEM)
            b.fmmInStrip = true
            items[#items + 1] = { button = b, h = ITEM }
            ownCount = ownCount + 1
        else
            b:Hide()
        end
    end
    local foreign = useStrip and SortedForeign() or {}
    if ownCount > 0 and #foreign > 0 then items[#items + 1] = { sep = true, h = SEP } end
    for _, b in ipairs(foreign) do items[#items + 1] = { button = b, h = ITEM, foreign = true } end

    local positions, more, width
    if round then positions, more, width = LayoutRound(items, side)
    else positions, more, width = LayoutSquare(items, side, height) end
    local park = more or positions[1] or { point = "CENTER", rel = strip, relPoint = "CENTER", x = 0, y = 0 }

    separator:Hide()
    for i, it in ipairs(items) do
        local pos = positions[i]
        if it.sep then
            if pos then
                separator:ClearAllPoints()
                if pos.angle then
                    separator:SetPoint("CENTER", pos.rel, pos.relPoint, pos.x, pos.y)
                    separator:SetRotation(pos.angle + math.pi / 2) -- quer zum Bogen
                else
                    local dir = side == "RIGHT" and 1 or -1
                    separator:SetPoint("CENTER", strip, pos.point, pos.x + dir * (ITEM / 2), pos.y - SEP / 2)
                    separator:SetRotation(0)
                end
                separator:Show()
            end
        elseif not it.foreign then
            local b = it.button
            if pos then
                b:SetPoint(pos.point, pos.rel, pos.relPoint, pos.x, pos.y)
                b:Show()
                b:SetAlpha((show or b.alert) and 1 or 0)
                StyleItem(b, round, b.alert or b:IsMouseOver())
            else
                b:Hide()
            end
        else
            local b = it.button
            local p = pos or park
            b.fmmPoint, b.fmmRel, b.fmmRelPoint, b.fmmX, b.fmmY = p.point, p.rel, p.relPoint, p.x, p.y
            PlaceForeign(b)
            b:SetAlpha((pos and show) and 1 or 0)
            b:EnableMouse(pos ~= false and pos ~= nil)
        end
    end
    if more then
        moreButton:ClearAllPoints()
        moreButton:SetPoint(more.point, more.rel, more.relPoint, more.x, more.y)
        -- Pfeil zeigt nach aussen (aufklappen) bzw. zur Karte (einklappen)
        local outward = (side == "LEFT") ~= expanded
        moreButton.icon:SetRotation(outward and math.pi / 2 or -math.pi / 2)
        StyleItem(moreButton, round, moreButton:IsMouseOver())
        moreButton:Show()
    else
        moreButton:Hide()
    end
    strip:SetWidth(width)
    strip:SetShown(useStrip and #items > 0)
    strip:SetAlpha(show and 1 or 0)
    -- Flaeche und Rand einstellbar durchsichtig (rund: keine Flaeche – die Knoepfe sitzen frei am Bogen)
    local a = round and 0 or (d.stripAlpha or 50) / 100
    strip:SetBackdropColor(C.header[1], C.header[2], C.header[3], a)
    strip:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], round and 0 or math.min(1, a + 0.2))

    -- Zonenname bis an Anzeigen/Knoepfe heran (abgeschnitten statt ueberlappt)
    if bar and bar:IsShown() then
        local right = barX
        if inBar then
            for _, b in ipairs(tools) do if b:IsShown() then right = right - (TOOL + 2) end end
        end
        bar.zone:SetPoint("RIGHT", bar, "RIGHT", right - 2, 0)
    end
end

---------------------------------------------------------------------------
-- Maus ueber Minimap/Leisten: Knoepfe zeigen
---------------------------------------------------------------------------
local function IsOverAny()
    if Minimap:IsMouseOver() or (bar and bar:IsShown() and bar:IsMouseOver()) then return true end
    if strip and strip:IsShown() and strip:IsMouseOver() then return true end
    if moreButton and moreButton:IsShown() and moreButton:IsMouseOver() then return true end
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
-- Zoom: in Staedten/Rastgebieten naeher heran, draussen weit; nach 10 s zurueck auf diese Grundstufe
---------------------------------------------------------------------------
local function InCity()
    if IsResting and IsResting() then return true end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local info = mapID and ns.CanRead(mapID) and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.City or false
end

local function BaseZoom()
    local d = DB()
    if d.cityZoom and InCity() then
        return math.min(d.cityZoomLevel or 2, Minimap:GetZoomLevels() - 1)
    end
    return 0
end

local zoomToken, lastBase = 0, nil
local settingZoom = false
local function SetZoomSafe(z)
    settingZoom = true
    pcall(Minimap.SetZoom, Minimap, z)
    if Minimap.ZoomIn then Minimap.ZoomIn:SetEnabled(z < Minimap:GetZoomLevels() - 1) end
    if Minimap.ZoomOut then Minimap.ZoomOut:SetEnabled(z > 0) end
    settingZoom = false
end

local function ScheduleZoomOut()
    if settingZoom or not DB().autoZoom then return end
    zoomToken = zoomToken + 1
    local token = zoomToken
    C_Timer.After(10, function()
        if token ~= zoomToken or not DB().autoZoom then return end
        local base = BaseZoom()
        if Minimap:GetZoom() ~= base then SetZoomSafe(base) end
    end)
end

-- Gebiet gewechselt: neue Grundstufe nur setzen, wenn sie sich aendert (eigenes Zoomen bleibt sonst unberuehrt)
local function ApplyAreaZoom()
    local base = BaseZoom()
    if base ~= lastBase then
        lastBase = base
        SetZoomSafe(base)
    end
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
        coordBox:ClearAllPoints()
        coordBox:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
    end
    UpdateZone()
    UpdateClock()
    UpdateCoords()
    UpdateDurability()
    lastBase = nil
    ApplyAreaZoom()
    ns.UpdateHover()
    -- andere Forever-Addons (z. B. ForeverQuests unter der Minimap) neu ausrichten lassen
    if UI.Fire then UI.Fire("ForeverMinimap.Layout") end
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
    -- Groesse im Bearbeitungsmodus geaendert: Nachbarn (ForeverQuests) neu ausrichten
    if _G.MinimapCluster and _G.MinimapCluster.SetEditModeScale then
        hooksecurefunc(_G.MinimapCluster, "SetEditModeScale", function()
            C_Timer.After(0, function() if UI.Fire then UI.Fire("ForeverMinimap.Layout") end end)
        end)
    end

    Minimap:HookScript("OnEnter", function() ns.UpdateHover() end)
    Minimap:HookScript("OnLeave", function() ns.UpdateHoverSoon() end)
    Minimap:HookScript("OnMouseUp", function(_, button)
        if button == "RightButton" and DB().rightClickTracking then OpenTracking() end
    end)
    hooksecurefunc(Minimap, "SetZoom", ScheduleZoomOut)

    -- Warteschlangen-Auge: Blizzard zeigt/versteckt es selbst; wir halten es an seinem Platz in der Leiste
    local q = _G.QueueStatusButton
    if q then
        hooksecurefunc(q, "SetPoint", function(self) if not self.fmmPlacing and QueueDocked() then PlaceQueue() end end)
        q:HookScript("OnShow", function() ns.UpdateTools() end)
        q:HookScript("OnHide", function() ns.UpdateTools() end)
    end

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
        "PLAYER_DIFFICULTY_CHANGED", "UPDATE_PENDING_MAIL", "MAIL_CLOSED", "CALENDAR_UPDATE_PENDING_INVITES",
        "MINIMAP_PING", "MINIMAP_UPDATE_ZOOM", "ADDON_LOADED", "PLAYER_UPDATE_RESTING",
        "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }) do
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
        elseif event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_EQUIPMENT_CHANGED" then
            UpdateDurability()
            ns.UpdateTools()
        else
            UpdateZone()
            ApplyAreaZoom()
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
