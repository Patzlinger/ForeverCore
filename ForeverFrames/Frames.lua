-- ForeverFrames: die Gruppen-/Raidrahmen
-- Aufbau: 8 sichere Gruppen-Header (einer pro Raidgruppe, Gruppe 1 auch fuer Party/Solo).
-- Die Header erzeugen die klickbaren Buttons; alles Sichtbare liegt in einem
-- normalen (nicht geschuetzten) Unterrahmen und darf deshalb auch im Kampf geaendert werden.
local ADDON_NAME, ns = ...
local T, IsSecret, GetDB, Safe = ns.T, ns.IsSecret, ns.GetDB, ns.Safe

local NUM_GROUPS = 8
-- Grundgroesse: "100 %" in den Einstellungen entspricht intern 110 %
local BASE_SCALE = 1.1
local MEMBERS = 5
local WHITE = "Interface\\Buttons\\WHITE8x8"

ns.headers = {}
ns.buttons = {}        -- alle sicheren Buttons (vom Header erzeugt)
local unitMap = {}     -- Einheit ("raid3", "party1", "player") -> Button

---------------------------------------------------------------------------
-- Anker und Verschiebe-Leiste
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "ForeverFramesAnchor", UIParent)
anchor:SetSize(1, 1)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
ns.anchor = anchor

function ns.RestorePosition()
    ns.OutOfCombat("position", function()
        local p = GetDB().pos
        anchor:ClearAllPoints()
        if p then
            anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2])
        else
            anchor:SetPoint("TOPLEFT", UIParent, "TOP", -476, -397) -- Standard: links unterhalb der Mitte
        end
    end)
end

local mover = CreateFrame("Frame", "ForeverFramesMover", UIParent, "BackdropTemplate")
mover:SetSize(170, 18)
mover:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 3)
mover:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
mover:SetBackdropColor(0.25, 0.2, 0, 0.9)
mover:SetBackdropBorderColor(1, 0.82, 0, 1)
mover:SetFrameStrata("HIGH")
mover:EnableMouse(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mover.text:SetPoint("CENTER")
mover.text:SetText(T("ForeverFrames – ziehen", "ForeverFrames – drag"))

---------------------------------------------------------------------------
-- Ausrichten (Raster, Einrasten aus ForeverHub.lua). "bounds" ist ein unsichtbarer Rahmen um alle
-- sichtbaren Spieler-Rahmen: an seinen Kanten rastet ForeverFrames ein – und andere
-- Forever-Rahmen (z. B. ForeverUnits) rasten daran ein.
---------------------------------------------------------------------------
local UI = ns.UI
local bounds = CreateFrame("Frame", nil, UIParent)
bounds:SetSize(1, 1)
bounds:Hide()
UI.AddMover(bounds)

function ns.UpdateBounds()
    if InCombatLockdown() then return end
    local ax, ay = anchor:GetLeft(), anchor:GetTop()
    if not (ax and ay) then return end
    local us = UIParent:GetEffectiveScale()
    local L, R, Tp, B
    local function Add(b)
        if not b:IsVisible() then return end
        local l, r, t, btm = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
        if not (l and r and t and btm) then return end
        local s = b:GetEffectiveScale() / us
        l, r, t, btm = l * s, r * s, t * s, btm * s
        L, R = math.min(L or l, l), math.max(R or r, r)
        Tp, B = math.max(Tp or t, t), math.min(B or btm, btm)
    end
    for _, b in ipairs(ns.buttons) do Add(b) end
    for _, b in ipairs(ns.fakeButtons or {}) do Add(b) end
    if not L then bounds:Hide() return end
    bounds:ClearAllPoints()
    bounds:SetPoint("TOPLEFT", anchor, "TOPLEFT", L - ax, Tp - ay)
    bounds:SetSize(math.max(1, R - L), math.max(1, Tp - B))
    bounds:Show()
end
-- Nachziehen, wenn sich etwas aendert (Anordnung, Testmodus, Gruppe, Kampfende – siehe Dateiende);
-- mehrere Anlaesse kurz hintereinander werden zusammengefasst. Dazu alle 5 s zur Sicherheit.
local boundsQueued = false
function ns.RequestBounds()
    if boundsQueued then return end
    boundsQueued = true
    C_Timer.After(0.3, function()
        boundsQueued = false
        pcall(ns.UpdateBounds)
    end)
end
ns.UI.Every(5, function() ns.UpdateBounds() end, { addon = "ForeverFrames", name = "Bounds" }) -- (gemeinsamer Takt aus ForeverCore)

-- Raster nur entsperrt und nur beim Ziehen oder bei offenen Einstellungen
-- (ein Dauer-Raster waere stoerend, solange man nur kurz entsperrt)
local dragging = false
function ns.UpdateGrid()
    local db = GetDB()
    local opts = _G.ForeverFramesOptions
    local want = db.gridShow and not db.locked and (dragging or (opts and opts:IsShown()))
    UI.Grid("ForeverFrames", want and db.gridSize or nil)
end

-- Position: linke obere Ecke, X ab linkem und Y ab oberem Bildschirmrand
function ns.SetPosition(x, y)
    GetDB().pos = { UI.Round(x), UI.Round(y) }
    ns.RestorePosition()
    if ns.OnMoved then ns.OnMoved() end
end

mover:SetScript("OnDragStart", function()
    if InCombatLockdown() then return end
    local db = GetDB()
    ns.UpdateBounds()
    anchor:StartMoving()
    dragging = true
    ns.UpdateGrid()
    UI.BeginDrag(anchor, { edges = bounds:IsShown() and bounds or mover, snap = db.snap,
        grid = db.gridShow and db.gridSize or nil })
end)
mover:SetScript("OnDragStop", Safe("Verschieben", function()
    anchor:StopMovingOrSizing()
    local dx, dy = UI.EndDrag()
    dragging = false
    ns.UpdateGrid()
    local left, top = anchor:GetLeft(), anchor:GetTop()
    if left and top then
        ns.SetPosition(left + dx, top - UIParent:GetTop() + dy)
    else
        ns.RestorePosition()
    end
end))
mover:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and ns.ToggleOptions then ns.ToggleOptions() end
end)
mover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("ForeverFrames")
    GameTooltip:AddLine(T("Ziehen: Rahmen verschieben", "Drag: move frames"), 1, 1, 1)
    GameTooltip:AddLine(T("Rechtsklick: Einstellungen", "Right-click: settings"), 1, 1, 1)
    GameTooltip:AddLine(T("Sperren in den Einstellungen oder /ff lock", "Lock in the settings or /ff lock"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
mover:SetScript("OnLeave", GameTooltip_Hide)

function ns.UpdateMover()
    mover:SetShown(not GetDB().locked)
    ns.UpdateGrid()
end

---------------------------------------------------------------------------
-- Geometrie: wo liegt Gruppe g / Spieler i (relativ zum Anker, in Header-Einheiten)
---------------------------------------------------------------------------
-- Platz fuer den Begleiter-Balken neben jedem Spieler (Pets.lua)
local function PetExtra() return ns.PetExtra and ns.PetExtra() or 0 end
local function PetLeftShift() return ns.PetLeftShift and ns.PetLeftShift() or 0 end

local function GroupOffset(g)
    local db = GetDB()
    local col = (g - 1) % db.groupsPerRow
    local row = math.floor((g - 1) / db.groupsPerRow)
    local w = db.width + PetExtra()
    if db.growth == "RIGHT" then
        local blockW = MEMBERS * w + (MEMBERS - 1) * db.spacing
        return row * (blockW + db.groupSpacing) + PetLeftShift(), -col * (db.height + db.groupSpacing)
    end
    local blockH = MEMBERS * db.height + (MEMBERS - 1) * db.spacing
    return col * (w + db.groupSpacing) + PetLeftShift(), -row * (blockH + db.groupSpacing)
end

local function MemberOffset(i)
    local db = GetDB()
    if db.growth == "RIGHT" then
        return (i - 1) * (db.width + PetExtra() + db.spacing), 0
    end
    return 0, -(i - 1) * (db.height + db.spacing)
end

---------------------------------------------------------------------------
-- Sichtbarer Teil eines Buttons
---------------------------------------------------------------------------
local function NewText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    fs:SetWordWrap(false)
    return fs
end

local function NewOverlayBar(parent, reverse)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetReverseFill(reverse)
    return bar
end

-- Heilvorhersage/Schilde starten am Ende der Lebenspunkte-Fuellung. So braucht
-- es keine Rechnung mit (evtl. geheimen) Werten: die Balken bekommen nur Werte.
local function LayoutOverlays(v)
    local w, h = v.health:GetSize()
    local fill = v.health:GetStatusBarTexture()
    for _, bar in ipairs({ v.heal, v.hotFill, v.hot, v.shield, v.absorb }) do
        bar:ClearAllPoints()
        bar:SetSize(w, h)
    end
    v.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    v.hot:SetPoint("TOPLEFT", v.heal:GetStatusBarTexture(), "TOPRIGHT")
    v.hotFill:SetPoint("TOPLEFT", v.heal:GetStatusBarTexture(), "TOPRIGHT")
    if GetDB().shieldStyle == "right" then
        v.shield:SetReverseFill(true)
        v.shield:SetPoint("TOPRIGHT", v.health, "TOPRIGHT")
    else
        v.shield:SetReverseFill(false)
        v.shield:SetPoint("TOPLEFT", v.hot:GetStatusBarTexture(), "TOPRIGHT")
    end
    v.absorb:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
end

function ns.CreateVisuals(b)
    local v = {}
    b.ff = v

    local c = CreateFrame("Frame", nil, b, "BackdropTemplate")
    c:SetAllPoints(b)
    c:SetFrameLevel(b:GetFrameLevel())
    v.content = c

    v.health = CreateFrame("StatusBar", nil, c)
    v.health:SetFrameLevel(c:GetFrameLevel() + 1)
    v.health:SetMinMaxValues(0, 1)
    v.health:SetValue(1)
    v.healthBg = v.health:CreateTexture(nil, "BACKGROUND")
    v.healthBg:SetAllPoints(v.health)

    v.power = CreateFrame("StatusBar", nil, c)
    v.power:SetFrameLevel(c:GetFrameLevel() + 1)
    v.power:SetMinMaxValues(0, 1)
    v.power:SetValue(1)
    v.powerBg = v.power:CreateTexture(nil, "BACKGROUND")
    v.powerBg:SetAllPoints(v.power)

    -- auf die Lebensleiste zugeschnittene Ebene fuer Heilvorhersage/Schilde
    v.clip = CreateFrame("Frame", nil, c)
    v.clip:SetAllPoints(v.health)
    v.clip:SetFrameLevel(c:GetFrameLevel() + 2)
    v.clip:SetClipsChildren(true)
    v.heal = NewOverlayBar(v.clip, false)
    v.hotFill = NewOverlayBar(v.clip, false) -- Grundfläche unter der Schraffur
    v.hot = NewOverlayBar(v.clip, false) -- HoTs: schraffiert, hinter der normalen Heilvorhersage
    UI.HatchBar(v.hot)
    v.shield = NewOverlayBar(v.clip, false)
    v.absorb = NewOverlayBar(v.clip, true)
    v.health:SetScript("OnSizeChanged", function() LayoutOverlays(v) end)

    -- oberste Ebene: Texte, Symbole, Hervorhebungen
    v.top = CreateFrame("Frame", nil, c)
    v.top:SetAllPoints(c)
    v.top:SetFrameLevel(c:GetFrameLevel() + 5)

    v.hover = v.top:CreateTexture(nil, "ARTWORK")
    v.hover:SetAllPoints(v.health)
    v.hover:SetColorTexture(1, 1, 1, 0.12)
    v.hover:Hide()

    v.name = NewText(v.top)
    v.hp = NewText(v.top)
    v.pw = NewText(v.top)
    v.status = NewText(v.top)

    v.role = v.top:CreateTexture(nil, "OVERLAY")
    v.leader = v.top:CreateTexture(nil, "OVERLAY")
    v.mark = v.top:CreateTexture(nil, "OVERLAY")
    v.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    v.ready = v.top:CreateTexture(nil, "OVERLAY")
    v.incoming = v.top:CreateTexture(nil, "OVERLAY") -- Wiederbelebung / Beschwoerung unterwegs
    v.combat = v.top:CreateTexture(nil, "OVERLAY", nil, 6)
    v.combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    v.combat:SetTexCoord(0.5, 1, 0, 0.49)
    v.combat:SetSize(11, 11)
    v.combat:Hide()
    for _, t in ipairs({ v.role, v.leader, v.mark, v.ready, v.incoming }) do t:Hide() end

    v.targetBorder = CreateFrame("Frame", nil, v.top, "BackdropTemplate")
    v.targetBorder:SetAllPoints(c)
    v.targetBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    v.targetBorder:Hide()

    v.aggroBorder = CreateFrame("Frame", nil, c, "BackdropTemplate")
    v.aggroBorder:SetPoint("TOPLEFT", c, "TOPLEFT", -1, 1)
    v.aggroBorder:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 1, -1)
    v.aggroBorder:SetFrameLevel(c:GetFrameLevel() + 4)
    v.aggroBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    v.aggroBorder:Hide()

    if ns.CreateAuraVisuals then ns.CreateAuraVisuals(b) end -- Debuffs/Buffs (Auras.lua)
    return v
end

-- Lebens- und Energiebalken anordnen (Energiebalken unten, falls sichtbar)
local function LayoutBars(b, showPower)
    local v, db = b.ff, GetDB()
    local bs = db.borderSize
    v.powerShown = showPower
    v.health:ClearAllPoints()
    v.health:SetPoint("TOPLEFT", v.content, "TOPLEFT", bs, -bs)
    v.health:SetPoint("TOPRIGHT", v.content, "TOPRIGHT", -bs, -bs)
    if showPower then
        v.power:ClearAllPoints()
        v.power:SetPoint("BOTTOMLEFT", v.content, "BOTTOMLEFT", bs, bs)
        v.power:SetPoint("BOTTOMRIGHT", v.content, "BOTTOMRIGHT", -bs, bs)
        v.power:SetHeight(db.powerHeight)
        v.power:Show()
        v.health:SetPoint("BOTTOMLEFT", v.power, "TOPLEFT", 0, bs)
        v.health:SetPoint("BOTTOMRIGHT", v.power, "TOPRIGHT", 0, bs)
    else
        v.power:Hide()
        v.health:SetPoint("BOTTOMLEFT", v.content, "BOTTOMLEFT", bs, bs)
        v.health:SetPoint("BOTTOMRIGHT", v.content, "BOTTOMRIGHT", -bs, bs)
    end
end

local function JustifyFor(point)
    if point:find("LEFT") then return "LEFT" end
    if point:find("RIGHT") then return "RIGHT" end
    return "CENTER"
end

local function PlaceText(v, fs, prefix, maxWidth)
    local db = GetDB()
    local outline = db.fontOutline
    fs:SetFont(ns.FontPath(), db[prefix .. "Size"], outline)
    if db.fontShadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    local point = db[prefix .. "Point"]
    fs:ClearAllPoints()
    fs:SetPoint(point, v.top, point, db[prefix .. "X"], db[prefix .. "Y"])
    fs:SetJustifyH(JustifyFor(point))
    if maxWidth then fs:SetWidth(maxWidth) end
end

local function PlaceIcon(v, tex, prefix)
    local db = GetDB()
    local point = db[prefix .. "Point"]
    tex:ClearAllPoints()
    tex:SetPoint(point, v.top, point, db[prefix .. "X"], db[prefix .. "Y"])
    tex:SetSize(db[prefix .. "Size"], db[prefix .. "Size"])
end

-- Optik eines Buttons komplett aus den Einstellungen neu aufbauen
function ns.ApplyButtonLayout(b)
    local v, db = b.ff, GetDB()
    local tex = ns.TexturePath()

    v.content:SetBackdrop({ bgFile = WHITE })
    v.content:SetBackdropColor(ns.Color("borderColor"))

    v.health:SetStatusBarTexture(tex)
    v.healthBg:SetTexture(tex)
    v.power:SetStatusBarTexture(tex)
    v.powerBg:SetTexture(tex)
    v.heal:SetStatusBarColor(ns.Color("healColor"))
    do local r, g, bl = ns.Color("healColor")
        v.hot:SetStatusBarColor(math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, bl + 0.25), 0.9)
        v.hotFill:SetStatusBarColor(math.min(1, r + 0.2), math.min(1, g + 0.2), math.min(1, bl + 0.2), 0.25) end
    v.shield:SetStatusBarColor(ns.Color("shieldColor"))
    v.absorb:SetStatusBarColor(ns.Color("healAbsorbColor"))

    PlaceText(v, v.name, "name", db.width - 4)
    PlaceText(v, v.hp, "hp")
    PlaceText(v, v.pw, "powerText")
    PlaceText(v, v.status, "status")
    v.name:SetShown(db.nameShow)

    PlaceIcon(v, v.role, "role")
    PlaceIcon(v, v.leader, "leader")
    PlaceIcon(v, v.mark, "mark")
    PlaceIcon(v, v.ready, "ready")
    PlaceIcon(v, v.incoming, "ready") -- gleicher Platz wie der Bereitschaftscheck
    if db.readyAtName and db.nameShow then
        -- links in der Namenszeile (vor dem Namen), so groß wie die Schrift – deckt den Namen nicht ab
        local size = math.min(db.readySize, (db.nameSize or 11) + 4)
        for _, t in ipairs({ v.ready, v.incoming }) do
            t:ClearAllPoints()
            t:SetPoint("LEFT", v.name, "LEFT", 0, 0)
            t:SetSize(size, size)
        end
    end

    v.targetBorder:SetBackdropBorderColor(ns.Color("targetColor"))
    v.aggroBorder:SetBackdropBorderColor(ns.Color("aggroColor"))

    LayoutBars(b, v.powerShown ~= false and db.powerMode ~= "none")
    LayoutOverlays(v)
    if ns.LayoutAuras then ns.LayoutAuras(b) end

    if b.ffFake then
        ns.UpdateFake(b)
    elseif b.ffUnit then
        ns.UpdateAll(b)
    end
end

---------------------------------------------------------------------------
-- Text-Formate (gemeinsam fuer echte Rahmen und Testmodus)
---------------------------------------------------------------------------
local function Num(v)
    if GetDB().hpShort then return ns.ShortNumber(v) end
    return v
end

-- Lebenspunkte-Text. unit = nil im Testmodus.
local function SetHealthText(v, cur, max, unit)
    local db, fs = GetDB(), v.hp
    if not db.hpShow or db.hpFormat == "none" or v.statusActive then
        fs:Hide()
        return
    end
    fs:Show()
    local fmt = db.hpFormat

    -- geheime Werte: nur Blizzard-Funktionen benutzen, die damit umgehen koennen
    if unit and IsSecret(cur, max) then
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if fmt == "percent" then
            if curve then fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve)) else fs:SetText("") end
        elseif fmt == "deficit" then
            fs:SetFormattedText("-%s", Num(UnitHealthMissing(unit, true)))
        elseif fmt == "curmax" then
            fs:SetFormattedText("%s/%s", Num(cur), Num(max))
        elseif fmt == "curpercent" and curve then
            fs:SetFormattedText("%s  %.0f%%", Num(cur), UnitHealthPercent(unit, true, curve))
        else
            fs:SetFormattedText("%s", Num(cur))
        end
        return
    end

    if not max or max <= 0 then fs:SetText("") return end
    if db.hpHideFull and cur >= max then fs:SetText("") return end
    local pct = math.floor(cur / max * 100 + 0.5)
    if fmt == "percent" then
        fs:SetFormattedText("%d%%", pct)
    elseif fmt == "deficit" then
        fs:SetFormattedText("-%s", Num(max - cur))
    elseif fmt == "curmax" then
        fs:SetFormattedText("%s/%s", Num(cur), Num(max))
    elseif fmt == "curpercent" then
        fs:SetFormattedText("%s  %d%%", Num(cur), pct)
    else
        fs:SetFormattedText("%s", Num(cur))
    end
end

local function SetPowerText(v, cur, max, unit)
    local db, fs = GetDB(), v.pw
    if not db.powerTextShow or v.statusActive then fs:Hide() return end
    fs:Show()
    if unit and IsSecret(cur, max) then
        if db.powerTextFormat == "percent" then
            local curve = CurveConstants and CurveConstants.ScaleTo100
            if curve and UnitPowerPercent then
                fs:SetFormattedText("%.0f%%", UnitPowerPercent(unit, nil, false, curve))
            else
                fs:SetText("")
            end
        else
            fs:SetFormattedText("%s", ns.ShortNumber(cur))
        end
        return
    end
    if not max or max <= 0 then fs:SetText("") return end
    if db.powerTextFormat == "percent" then
        fs:SetFormattedText("%d%%", math.floor(cur / max * 100 + 0.5))
    else
        fs:SetFormattedText("%s", ns.ShortNumber(cur))
    end
end

---------------------------------------------------------------------------
-- Aktualisieren (echte Einheiten)
---------------------------------------------------------------------------
local function TextColor(mode, customKey, unit, class)
    if mode == "class" then
        if unit then return ns.ClassColor(unit) end
        return ns.ClassColorByFile(class)
    elseif mode == "custom" then
        return ns.Color(customKey)
    end
    return 1, 1, 1
end

local function SetBarColors(v, r, g, b, offline)
    local db = GetDB()
    if offline then
        v.health:SetStatusBarColor(0.4, 0.4, 0.4)
        v.healthBg:SetVertexColor(0.15, 0.15, 0.15)
        return
    end
    if db.barColorMode == "custom" then r, g, b = ns.Color("barColor") end
    v.health:SetStatusBarColor(r, g, b)
    if db.lossColorMode == "custom" then
        v.healthBg:SetVertexColor(ns.Color("lossColor"))
    else
        v.healthBg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22)
    end
end

local function UpdateName(b)
    local v, db, unit = b.ff, GetDB(), b.ffUnit
    local name = UnitName(unit)
    if IsSecret(name) then
        v.name:SetText(name)
    else
        -- Spieler: Vor-/Nachname nach der Hub-Einstellung; NPC-Begleiter (Gefolge) behalten ihren Namen
        local isPlayer = UnitIsPlayer(unit)
        if not IsSecret(isPlayer) and isPlayer and UI.PlayerName then name = UI.PlayerName(name) end
        local lvl = db.levelShow ~= false and UnitLevel(unit)
        local prefix = (not IsSecret(lvl) and lvl and lvl > 0) and ("|cffb0b0b0" .. lvl .. "|r ") or ""
        v.name:SetText(prefix .. ns.Utf8Sub(name or "", db.nameMaxChars))
    end
    v.name:SetTextColor(TextColor(db.nameColorMode, "nameColor", unit))
    v.hp:SetTextColor(TextColor(db.hpColorMode, "hpColor", unit))
end

-- Lebensfarbe nach HP: Blizzard-Farbkurve von der normalen Balkenfarbe ueber Orange nach Rot.
-- Blizzard wertet die (evtl. gesperrten) Lebenspunkte selbst aus – das Addon rechnet nichts.
local hpCurves = {}
local function HealthCurve(r, g, b)
    local key = string.format("%.2f:%.2f:%.2f", r, g, b)
    local c = hpCurves[key]
    if c == nil then
        c = false
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
            c = C_CurveUtil.CreateColorCurve()
            if Enum and Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Linear) end
            c:AddPoint(0, CreateColor(0.9, 0.1, 0.1, 1))
            c:AddPoint(0.35, CreateColor(1, 0.55, 0.1, 1))
            c:AddPoint(0.6, CreateColor(r, g, b, 1))
            c:AddPoint(1, CreateColor(r, g, b, 1))
        end
        hpCurves[key] = c
    end
    return c
end

local function ApplyHealthGradient(b)
    local v, db = b.ff, GetDB()
    if not db.healthGradient or not v.barColor or v.offline then return end
    local curve = HealthCurve(v.barColor[1], v.barColor[2], v.barColor[3])
    if not curve then return end
    local ok = pcall(function()
        v.health:SetStatusBarColor(UnitHealthPercent(b.ffUnit, false, curve):GetRGB())
    end)
    if not ok then v.health:SetStatusBarColor(v.barColor[1], v.barColor[2], v.barColor[3]) end
end

local function UpdateHealthColor(b)
    local v = b.ff
    local r, g, bl = ns.ClassColor(b.ffUnit)
    v.offline = not UnitIsConnected(b.ffUnit)
    SetBarColors(v, r, g, bl, v.offline)
    if GetDB().barColorMode == "custom" then r, g, bl = ns.Color("barColor") end
    v.barColor = { r, g, bl }
    ApplyHealthGradient(b)
end

local function UpdateStatus(b)
    local v, unit = b.ff, b.ffUnit
    local text
    if not UnitIsConnected(unit) then
        text = "Offline"
    elseif UnitIsGhost(unit) then
        text = T("Geist", "Ghost")
    elseif UnitIsDeadOrGhost(unit) then
        text = T("Tot", "Dead")
    else
        local afk = UnitIsAFK(unit)
        if not IsSecret(afk) and afk then text = "AFK" end
    end
    v.statusActive = text ~= nil and GetDB().statusShow
    if v.statusActive then
        v.status:SetText(text)
        v.status:Show()
    else
        v.status:Hide()
    end
end

local function UpdateHealth(b)
    local v, unit = b.ff, b.ffUnit
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if IsSecret(cur, max) then
        v.health:SetMinMaxValues(0, max)
        v.health:SetValue(cur)
    else
        v.health:SetMinMaxValues(0, (max and max > 0) and max or 1)
        v.health:SetValue(cur or 0)
    end
    SetHealthText(v, cur, max, unit)
    ApplyHealthGradient(b)
end

-- Blizzard-Rechner fuer Heilvorhersage und Schilde (funktioniert mit geheimen Werten)
local calc
local function GetCalc()
    if calc == nil then
        calc = CreateUnitHealPredictionCalculator and CreateUnitHealPredictionCalculator() or false
        if calc and Enum and Enum.UnitIncomingHealClampMode then
            pcall(calc.SetIncomingHealClampMode, calc, Enum.UnitIncomingHealClampMode.MissingHealth)
        end
        if calc and Enum and Enum.UnitHealAbsorbClampMode then
            pcall(calc.SetHealAbsorbClampMode, calc, Enum.UnitHealAbsorbClampMode.CurrentHealth)
        end
    end
    return calc
end

local function UpdatePrediction(b)
    local v, db, unit = b.ff, GetDB(), b.ffUnit
    local c = GetCalc()
    if not c or not UnitGetDetailedHealPrediction then
        v.heal:SetValue(0)
        v.hot:SetValue(0)
        v.hotFill:SetValue(0)
        v.shield:SetValue(0)
        v.absorb:SetValue(0)
        return
    end
    if Enum and Enum.UnitDamageAbsorbClampMode then
        local mode = db.shieldStyle == "right" and Enum.UnitDamageAbsorbClampMode.MaximumHealth
            or Enum.UnitDamageAbsorbClampMode.MissingHealth
        pcall(c.SetDamageAbsorbClampMode, c, mode)
    end
    UnitGetDetailedHealPrediction(unit, "player", c)
    local max = UnitHealthMax(unit)
    if not IsSecret(max) and (not max or max <= 0) then max = 1 end

    -- Werte nur durchreichen (kein "x and y or 0": das waere ein Test auf einen geheimen Wert)
    v.heal:SetMinMaxValues(0, max)
    if db.healPrediction then v.heal:SetValue((c:GetIncomingHeals())) else v.heal:SetValue(0) end
    v.hot:SetMinMaxValues(0, max)
    v.hotFill:SetMinMaxValues(0, max)
    local hot = db.hotPrediction ~= false and UI.OverTimeRemaining and UI.OverTimeRemaining(unit, "heal") or 0
    v.hot:SetValue(hot)
    v.hotFill:SetValue(hot)
    v.hotOn = hot > 0
    v.shield:SetMinMaxValues(0, max)
    if db.shields then v.shield:SetValue((c:GetDamageAbsorbs())) else v.shield:SetValue(0) end
    v.absorb:SetMinMaxValues(0, max)
    if db.healAbsorbs then v.absorb:SetValue((c:GetHealAbsorbs())) else v.absorb:SetValue(0) end
end

local function PowerShouldShow(pType)
    local mode = GetDB().powerMode
    if mode == "none" then return false end
    if mode == "mana" then
        if IsSecret(pType) then return true end
        return pType == 0 -- Enum.PowerType.Mana
    end
    return true
end

local function SetPowerColor(v, pType, pToken)
    local c
    if PowerBarColor and not IsSecret(pType, pToken) then
        c = PowerBarColor[pToken] or PowerBarColor[pType]
    end
    local r, g, bl = 0, 0.45, 1
    if c then r, g, bl = c.r, c.g, c.b end
    v.power:SetStatusBarColor(r, g, bl)
    v.powerBg:SetVertexColor(r * 0.25, g * 0.25, bl * 0.25)
end

local function UpdatePowerType(b)
    local v = b.ff
    local pType, pToken = UnitPowerType(b.ffUnit)
    SetPowerColor(v, pType, pToken)
    local show = PowerShouldShow(pType)
    if show ~= v.powerShown then LayoutBars(b, show) end
end

local function UpdatePower(b)
    local v, unit = b.ff, b.ffUnit
    local cur, max = UnitPower(unit), UnitPowerMax(unit)
    if IsSecret(cur, max) then
        v.power:SetMinMaxValues(0, max)
        v.power:SetValue(cur)
    else
        v.power:SetMinMaxValues(0, (max and max > 0) and max or 1)
        v.power:SetValue(cur or 0)
    end
    SetPowerText(v, cur, max, unit)
end

-- Blizzards fertige Rollen-Symbole (Atlas); falls es eins nicht gibt, die naechste Variante
local ROLE_ATLAS = {
    TANK    = { "roleicon-tiny-tank", "UI-LFG-RoleIcon-Tank" },
    HEALER  = { "roleicon-tiny-healer", "UI-LFG-RoleIcon-Healer" },
    DAMAGER = { "roleicon-tiny-dps", "UI-LFG-RoleIcon-DPS" },
}

local function AtlasExists(name)
    if C_Texture and C_Texture.GetAtlasInfo then return C_Texture.GetAtlasInfo(name) ~= nil end
    return true
end

local function ShowRole(v, role)
    local db = GetDB()
    local atlases = role and ROLE_ATLAS[role]
    if not db.roleShow or not atlases or (role == "DAMAGER" and db.roleHideDamager) then
        v.role:Hide()
        return
    end
    for _, atlas in ipairs(atlases) do
        if AtlasExists(atlas) then
            v.role:SetTexCoord(0, 1, 0, 1)
            v.role:SetAtlas(atlas)
            v.role:Show()
            return
        end
    end
    v.role:Hide()
end

local function UpdateRole(b)
    local role = UnitGroupRolesAssigned(b.ffUnit)
    if IsSecret(role) then role = nil end
    ShowRole(b.ff, role)
end

local function ShowLeader(v, kind)
    if not GetDB().leaderShow or not kind then v.leader:Hide() return end
    v.leader:SetTexture(kind == "leader" and "Interface\\GroupFrame\\UI-Group-LeaderIcon"
        or "Interface\\GroupFrame\\UI-Group-AssistantIcon")
    v.leader:Show()
end

local function UpdateLeader(b)
    local unit, kind = b.ffUnit, nil
    local leader = UnitIsGroupLeader(unit)
    if not IsSecret(leader) and leader then
        kind = "leader"
    elseif IsInRaid() then
        local assist = UnitIsGroupAssistant(unit)
        if not IsSecret(assist) and assist then kind = "assist" end
    end
    ShowLeader(b.ff, kind)
end

local function ShowMark(v, index)
    if not GetDB().markShow or not index or index < 1 or index > 8 then v.mark:Hide() return end
    local i = index - 1
    local x, y = (i % 4) * 0.25, math.floor(i / 4) * 0.25
    v.mark:SetTexCoord(x, x + 0.25, y, y + 0.25)
    v.mark:Show()
end

local function UpdateMark(b)
    local index = GetRaidTargetIndex(b.ffUnit)
    if IsSecret(index) then index = nil end
    ShowMark(b.ff, index)
end

local READY_TEX = {
    ready = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

-- Haken (bereit), Kreuz (nicht bereit) oder Fragezeichen (wartet). Nach dem Ende des Checks liefert Blizzard
-- keinen Status mehr – dann bleibt der letzte stehen (wer nicht geantwortet hat, bekommt das Kreuz).
local function UpdateReady(b)
    local v = b.ff
    if not GetDB().readyShow or not ns.readyCheckActive then
        b.ffReadyLast = nil
        v.ready:Hide()
        return
    end
    local status = GetReadyCheckStatus(b.ffUnit)
    if IsSecret(status) or not READY_TEX[status] then status = nil end
    if status then b.ffReadyLast = status else status = b.ffReadyLast end
    if ns.readyCheckFinished and status == "waiting" then status = "notready" end
    if not status then v.ready:Hide() return end
    v.ready:SetTexture(READY_TEX[status])
    v.ready:Show()
end

-- Wiederbelebung oder Beschwoerung unterwegs (Platz des Bereitschaftschecks, der hat Vorrang)
local SUMMON_ATLAS = {}
do
    local s = Enum and Enum.SummonStatus or {}
    SUMMON_ATLAS[s.Pending or 1] = "Raid-Icon-SummonPending"
    SUMMON_ATLAS[s.Accepted or 2] = "Raid-Icon-SummonAccepted"
    SUMMON_ATLAS[s.Declined or 3] = "Raid-Icon-SummonDeclined"
end

-- Kampf-Marker (gekreuzte Schwerter) in der Ecke unten links, solange die Einheit im Kampf ist
-- Kampf-Symbol direkt hinter den Namen setzen (je nach Ausrichtung des Namens)
local function PlaceCombat(fs, icon, size)
    local ok, w = pcall(fs.GetStringWidth, fs)
    if not ok or type(w) ~= "number" then w = 0 end
    local j = fs:GetJustifyH()
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    if j == "LEFT" then icon:SetPoint("LEFT", fs, "LEFT", w + 2, 0)
    elseif j == "RIGHT" then icon:SetPoint("RIGHT", fs, "RIGHT", -(w + 2), 0)
    else icon:SetPoint("LEFT", fs, "CENTER", w / 2 + 2, 0) end
end

local function UpdateCombat(b)
    local v, unit = b.ff, b.ffUnit
    if not GetDB().combatMarker or not unit then v.combat:Hide() return end
    local c = UnitAffectingCombat(unit)
    local on = not IsSecret(c) and c and true or false
    if on then PlaceCombat(v.name, v.combat, 16) end
    v.combat:SetShown(on)
end

local function UpdateIncoming(b)
    local v, unit = b.ff, b.ffUnit
    if not GetDB().incomingShow or v.ready:IsShown() then v.incoming:Hide() return end
    local summon = C_IncomingSummon and C_IncomingSummon.HasIncomingSummon
        and C_IncomingSummon.HasIncomingSummon(unit)
    if not IsSecret(summon) and summon then
        local status = C_IncomingSummon.IncomingSummonStatus(unit)
        v.incoming:SetAtlas((not IsSecret(status) and SUMMON_ATLAS[status]) or "Raid-Icon-SummonPending")
        v.incoming:Show()
        return
    end
    local rez = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit)
    if not IsSecret(rez) and rez then
        v.incoming:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        v.incoming:SetTexCoord(0, 1, 0, 1)
        v.incoming:Show()
        return
    end
    v.incoming:Hide()
end

local function UpdateTarget(b)
    local v = b.ff
    if not GetDB().targetHighlight then v.targetBorder:Hide() return end
    local isTarget = UnitIsUnit(b.ffUnit, "target")
    v.targetBorder:SetShown(not IsSecret(isTarget) and isTarget)
end

local function UpdateThreat(b)
    local v = b.ff
    if not GetDB().aggroBorder then v.aggroBorder:Hide() return end
    local status = UnitThreatSituation(b.ffUnit)
    v.aggroBorder:SetShown(not IsSecret(status) and status ~= nil and status >= 2)
end

local function UpdateRange(b)
    local v, db, unit = b.ff, GetDB(), b.ffUnit
    if not db.rangeFade or v.isPlayer then
        v.content:SetAlpha(1)
        return
    end
    local inRange, checked = UnitInRange(unit)
    if IsSecret(inRange) or IsSecret(checked) then
        -- geheim: Blizzard setzt die Transparenz direkt aus dem Wahr/Falsch-Wert
        if v.content.SetAlphaFromBoolean then
            v.content:SetAlphaFromBoolean(inRange, 1, db.rangeAlpha)
        else
            v.content:SetAlpha(1)
        end
    elseif checked then
        v.content:SetAlpha(inRange and 1 or db.rangeAlpha)
    else
        local visible = UnitIsVisible(unit)
        v.content:SetAlpha((IsSecret(visible) or visible) and 1 or db.rangeAlpha)
    end
end

function ns.UpdateAll(b)
    local unit = b.ffUnit
    if not unit or not UnitExists(unit) then return end
    local isPlayer = UnitIsUnit(unit, "player")
    b.ff.isPlayer = unit == "player" or (not IsSecret(isPlayer) and isPlayer)
    UpdateName(b)
    UpdateHealthColor(b)
    UpdateStatus(b)
    UpdatePowerType(b)
    UpdateHealth(b)
    UpdatePower(b)
    UpdatePrediction(b)
    UpdateRole(b)
    UpdateLeader(b)
    UpdateMark(b)
    UpdateReady(b)
    UpdateIncoming(b)
    UpdateCombat(b)
    UpdateTarget(b)
    UpdateThreat(b)
    UpdateRange(b)
    if ns.UpdateAuras then ns.UpdateAuras(b) end
    if b.ffPet and b.ffPet.ffUnit and ns.UpdatePet then ns.UpdatePet(b.ffPet) end
end

local function ForEachShown(fn)
    for _, b in ipairs(ns.buttons) do
        if b.ffUnit and b:IsVisible() then fn(b) end
    end
end
ns.ForEachShown = ForEachShown

-- Hub: Einstellung "Spielernamen" geändert -> Namen neu
if UI.On then
    UI.On("NameStyleChanged", function()
        for _, b in ipairs(ns.buttons or {}) do
            if b.ffUnit and UnitExists(b.ffUnit) then pcall(ns.UpdateAll, b) end
        end
    end)
end

function ns.UpdateAllButtons()
    for _, b in ipairs(ns.buttons) do
        ns.ApplyButtonLayout(b)
    end
    for _, b in ipairs(ns.fakeButtons or {}) do
        ns.ApplyButtonLayout(b)
    end
    if ns.LayoutPets then ns.LayoutPets() end
    -- ForeverUnits (falls installiert) uebernimmt die neue Optik
    if _G.ForeverUnitsRefresh then pcall(_G.ForeverUnitsRefresh) end
end

---------------------------------------------------------------------------
-- Button-Einrichtung (wird vom Header fuer jeden neuen Button aufgerufen)
---------------------------------------------------------------------------
local function OnAttributeChanged(self, name, value)
    if name ~= "unit" then return end
    if self.ffUnit and unitMap[self.ffUnit] == self then unitMap[self.ffUnit] = nil end
    self.ffUnit = value
    if value then unitMap[value] = self end
    local ok, err = pcall(ns.UpdateAll, self)
    if not ok then ns.ReportError(T("Rahmen", "Frame"), err) end
end

local function OnEnter(self)
    local db = GetDB()
    if db.mouseoverHighlight then self.ff.hover:Show() end
    if db.tooltip and self.ffUnit then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.ffUnit)
        GameTooltip:Show()
    end
end

local function OnLeave(self)
    self.ff.hover:Hide()
    GameTooltip:Hide()
end

function ns.SetupButton(b)
    if not b or b.ff then return end
    ns.CreateVisuals(b)
    ns.OutOfCombat("klicks-" .. b:GetName(), function()
        b:RegisterForClicks("AnyUp", "AnyDown")
    end)
    b:HookScript("OnAttributeChanged", OnAttributeChanged)
    b:HookScript("OnShow", Safe(T("Rahmen", "Frame"), ns.UpdateAll))
    b:HookScript("OnEnter", OnEnter)
    b:HookScript("OnLeave", OnLeave)
    tinsert(ns.buttons, b)
    ns.ApplyButtonLayout(b)
    if ns.ApplyClicksToButton then ns.ApplyClicksToButton(b) end
    if ns.SetupPet then ns.SetupPet(b) end -- Begleiter-Balken (Pets.lua)
end

---------------------------------------------------------------------------
-- Die 8 sicheren Header
---------------------------------------------------------------------------
-- Laeuft im geschuetzten Bereich, wenn der Header einen neuen Button baut:
-- Groesse setzen und danach unsere Lua-Einrichtung aufrufen.
local INIT_SNIPPET = [[
    local header = self:GetParent()
    self:SetWidth(header:GetAttribute("ffWidth"))
    self:SetHeight(header:GetAttribute("ffHeight"))
    header:CallMethod("InitButton", self:GetName())
]]

local function InitButton(header, name)
    local ok, err = pcall(ns.SetupButton, _G[name])
    if not ok then ns.ReportError(T("Rahmen anlegen", "Create frame"), err) end
end

for g = 1, NUM_GROUPS do
    local h = CreateFrame("Frame", "ForeverFramesGroup" .. g, UIParent, "SecureGroupHeaderTemplate")
    h.InitButton = InitButton
    -- zweite Vorlage: erlaubt den geschuetzten Schnipsel, der den Begleiter mitzieht (Pets.lua)
    h:SetAttribute("template", "SecureUnitButtonTemplate,SecureHandlerAttributeTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetAttribute("groupFilter", tostring(g))
    h:SetAttribute("showRaid", true)
    h:SetAttribute("showParty", g == 1)
    h:SetAttribute("sortMethod", "INDEX")
    h:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
    h:SetAttribute("unitsPerColumn", MEMBERS)
    h:SetAttribute("maxColumns", 1)
    h:SetAttribute("ffWidth", ns.DEFAULTS.width)
    h:SetAttribute("ffHeight", ns.DEFAULTS.height)
    h:SetAttribute("initialConfigFunction", INIT_SNIPPET)
    ns.headers[g] = h
end

-- Anordnung, Groesse, Skalierung (nur ausserhalb des Kampfs moeglich)
function ns.ApplyLayout()
    ns.OutOfCombat("layout", function()
        local db = GetDB()
        local testing = (ns.testCount or 0) > 0
        -- Blizzards Gruppen-Rahmen setzt beim Neuordnen nur NEUE Ankerpunkte, ohne die alten zu
        -- loesen, und ordnet bei JEDER Einstellung sofort neu. Sonst entsteht nach "untereinander"
        -- -> "nebeneinander" eine Treppe (jeder Rahmen haengt unter UND neben dem Vorgaenger).
        -- Deshalb: Neuordnen pausieren ("_ignore"), alles einstellen, Ankerpunkte loesen,
        -- dann genau einmal neu ordnen lassen.
        for _, h in ipairs(ns.headers) do h:SetAttribute("_ignore", true) end
        for g, h in ipairs(ns.headers) do
            h:SetAttribute("ffWidth", db.width)
            h:SetAttribute("ffHeight", db.height)
            h:SetScale(db.scale * BASE_SCALE)
            if db.growth == "RIGHT" then
                h:SetAttribute("point", "LEFT")
                h:SetAttribute("xOffset", db.spacing + PetExtra())
                h:SetAttribute("yOffset", 0)
            else
                h:SetAttribute("point", "TOP")
                h:SetAttribute("xOffset", 0)
                h:SetAttribute("yOffset", -db.spacing)
            end
            -- Sortierung innerhalb der Gruppe: Reihenfolge der Gruppe oder Tank > Heiler > Schaden
            h:SetAttribute("groupBy", db.sortByRole and "ASSIGNEDROLE" or nil)
            if g == 1 then
                h:SetAttribute("showPlayer", db.showPlayer)
                h:SetAttribute("showSolo", db.showSolo)
            end
            local x, y = GroupOffset(g)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
            h:SetShown(not testing)
        end
        for _, b in ipairs(ns.buttons) do
            b:SetSize(db.width, db.height)
            b:ClearAllPoints()
        end
        for _, h in ipairs(ns.headers) do
            h:SetAttribute("_ignore", nil)
            h:SetAttribute("ffRelayout", (h:GetAttribute("ffRelayout") or 0) + 1) -- loest das Neuordnen aus
        end
    end)
    if ns.LayoutPets then ns.LayoutPets() end
    if ns.LayoutFakes then ns.LayoutFakes() end
end

-- Alle Buttons gleich zu Beginn (ausserhalb des Kampfs) erzeugen lassen:
-- dann muss im Kampf nie ein neuer Button eingerichtet werden.
function ns.PrecreateButtons()
    ns.OutOfCombat("vorab", function()
        for _, h in ipairs(ns.headers) do
            h:SetAttribute("startingIndex", -MEMBERS + 1)
            h:Show()
            h:SetAttribute("startingIndex", 1)
        end
    end)
end

---------------------------------------------------------------------------
-- Blizzard-Gruppenrahmen ausblenden (nach dem Vorbild von Cell/ElvUI)
---------------------------------------------------------------------------

-- Blizzard-Rahmen sicher ausblenden: Blizzards eigener Sichtbarkeits-Treiber (geschuetzter Code)
-- blendet aus. Direktes :Hide()/:SetParent() wuerde Blizzards Skripte im Namen dieses Addons
-- ausfuehren ("taint") und z. B. Bearbeitungsmodus, Menue oder Raid-Werkzeug stoeren.
local hiddenFrames = {}
local function HideFrame(frame)
    if not frame or hiddenFrames[frame] then return end
    hiddenFrames[frame] = true
    frame:UnregisterAllEvents()
    if not (RegisterStateDriver and pcall(RegisterStateDriver, frame, "visibility", "hide")) then
        frame:Hide()
    end
end

function ns.HideBlizzard()
    ns.OutOfCombat("blizzard", function()
        local db = GetDB()
        if db.hideBlizzParty then
            if _G.CompactPartyFrame then HideFrame(_G.CompactPartyFrame) end
            if _G.PartyFrame then
                HideFrame(_G.PartyFrame) -- die Mitglieder-Rahmen sind Kinder davon
            else
                for i = 1, 4 do HideFrame(_G["PartyMemberFrame" .. i]) end
            end
        end
        if db.hideBlizzRaid then HideFrame(_G.CompactRaidFrameContainer) end
        if db.hideBlizzManager then HideFrame(_G.CompactRaidFrameManager) end
    end)
end

---------------------------------------------------------------------------
-- Testmodus: unechte Rahmen zum Einstellen (ohne Gruppe)
---------------------------------------------------------------------------
ns.testCount = 0
ns.fakeButtons = {}
local testContainer = CreateFrame("Frame", nil, UIParent)
testContainer:SetPoint("TOPLEFT", anchor, "TOPLEFT")
testContainer:SetSize(1, 1)

local FAKE_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "WARLOCK", "SHAMAN" }
local FAKE_NAMES = { "Thorgar", "Elyndra", "Pyrothas", "Schattenklinge", "Maelwen", "Bruder Aldric",
    "Kíraya", "Morvex", "Tuluk", "Brannoc", "Sylvara", "Grimnar" }
local FAKE_POWER = { WARRIOR = 1, ROGUE = 3 } -- sonst Mana

local function FakeData(i)
    local class = FAKE_CLASSES[(i - 1) % #FAKE_CLASSES + 1]
    local max = 3000 + (i * 137) % 2000
    local pct = ({ 1, 0.85, 0.6, 1, 0.35, 0.95, 0.15, 1, 0.7, 0.5 })[(i - 1) % 10 + 1]
    local d = {
        name = FAKE_NAMES[(i - 1) % #FAKE_NAMES + 1],
        class = class,
        max = max,
        cur = math.floor(max * pct),
        powerType = FAKE_POWER[class] or 0,
        power = 0.3 + ((i * 17) % 70) / 100,
        role = (i == 1 and "TANK") or (i % 5 == 2 and "HEALER") or "DAMAGER",
        leader = i == 1,
        mark = (i == 3) and 8 or nil,
        heal = (i % 4 == 2) and math.floor(max * 0.2) or 0,
        shield = (i % 6 == 4) and math.floor(max * 0.25) or 0,
        absorb = (i % 9 == 5) and math.floor(max * 0.1) or 0,
        rangeOut = (i % 7 == 6),
    }
    if i % 11 == 9 then d.status, d.cur = T("Tot", "Dead"), 0 end
    if i % 13 == 12 then d.status = "Offline" end
    return d
end

local POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [3] = "ENERGY" }

function ns.UpdateFake(b)
    local v, d, db = b.ff, b.ffFake, GetDB()
    v.name:SetText(ns.Utf8Sub(d.name, db.nameMaxChars))
    v.name:SetTextColor(TextColor(db.nameColorMode, "nameColor", nil, d.class))
    v.hp:SetTextColor(TextColor(db.hpColorMode, "hpColor", nil, d.class))
    local r, g, bl = ns.ClassColorByFile(d.class)
    SetBarColors(v, r, g, bl, d.status == "Offline")

    v.statusActive = d.status ~= nil and db.statusShow
    v.status:SetText(d.status or "")
    v.status:SetShown(v.statusActive)

    SetPowerColor(v, d.powerType, POWER_TOKENS[d.powerType])
    local showPower = PowerShouldShow(d.powerType)
    if showPower ~= v.powerShown then LayoutBars(b, showPower) end
    v.power:SetMinMaxValues(0, 1)
    v.power:SetValue(d.power)
    SetPowerText(v, math.floor(d.power * 1000), 1000)

    v.health:SetMinMaxValues(0, d.max)
    v.health:SetValue(d.cur)
    SetHealthText(v, d.cur, d.max)

    local missing = d.max - d.cur
    v.heal:SetMinMaxValues(0, d.max)
    v.heal:SetValue(db.healPrediction and math.min(d.heal, missing) or 0)
    v.shield:SetMinMaxValues(0, d.max)
    local shield = db.shieldStyle == "right" and d.shield or math.min(d.shield, math.max(missing - d.heal, 0))
    v.shield:SetValue(db.shields and shield or 0)
    v.absorb:SetMinMaxValues(0, d.max)
    v.absorb:SetValue(db.healAbsorbs and math.min(d.absorb, d.cur) or 0)

    ShowRole(v, d.role)
    ShowLeader(v, d.leader and "leader" or nil)
    ShowMark(v, d.mark)
    v.ready:Hide()
    v.targetBorder:SetShown(db.targetHighlight and b.ffIndex == 2)
    v.aggroBorder:SetShown(db.aggroBorder and b.ffIndex == 1)
    v.content:SetAlpha((db.rangeFade and d.rangeOut) and db.rangeAlpha or 1)
    if ns.UpdateFakeAuras then ns.UpdateFakeAuras(b) end
    if ns.UpdateFakePet then ns.UpdateFakePet(b) end
end

function ns.LayoutFakes()
    local db = GetDB()
    testContainer:SetScale(db.scale * BASE_SCALE)
    for i, b in ipairs(ns.fakeButtons) do
        if i <= ns.testCount then
            local g = math.floor((i - 1) / MEMBERS) + 1
            local gx, gy = GroupOffset(g)
            local mx, my = MemberOffset((i - 1) % MEMBERS + 1)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", testContainer, "TOPLEFT", gx + mx, gy + my)
            b:SetSize(db.width, db.height)
            b:Show()
        else
            b:Hide()
        end
    end
end

function ns.SetTestMode(count)
    if InCombatLockdown() then
        ns.Chat(T("Der Testmodus geht nur außerhalb des Kampfs.", "Test mode only works out of combat."))
        return
    end
    ns.testCount = count or 0
    for i = #ns.fakeButtons + 1, ns.testCount do
        local b = CreateFrame("Frame", nil, testContainer)
        b.ffIndex = i
        b.ffFake = FakeData(i)
        ns.CreateVisuals(b)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self) if GetDB().mouseoverHighlight then self.ff.hover:Show() end end)
        b:SetScript("OnLeave", function(self) self.ff.hover:Hide() end)
        ns.fakeButtons[i] = b
        ns.ApplyButtonLayout(b)
    end
    ns.ApplyLayout()
    if ns.testCount > 0 then
        for i = 1, ns.testCount do ns.ApplyButtonLayout(ns.fakeButtons[i]) end
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local function ForUnit(fn)
    return function(unit, ...)
        local b = unit and unitMap[unit]
        if b and b:IsVisible() then fn(b, ...) end
    end
end

ns.On("UNIT_HEALTH", "Lebenspunkte", ForUnit(function(b)
    UpdateStatus(b)
    UpdateHealth(b)
    UpdatePrediction(b)
end))
ns.On("UNIT_MAXHEALTH", "Lebenspunkte", ForUnit(function(b)
    UpdateHealth(b)
    UpdatePrediction(b)
end))
ns.On("UNIT_HEAL_PREDICTION", "Heilvorhersage", ForUnit(UpdatePrediction))
ns.On("UNIT_ABSORB_AMOUNT_CHANGED", "Schilde", ForUnit(UpdatePrediction))
ns.On("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "Heilabsorption", ForUnit(UpdatePrediction))
ns.On("UNIT_POWER_UPDATE", "Energie", ForUnit(UpdatePower))
ns.On("UNIT_MAXPOWER", "Energie", ForUnit(UpdatePower))
ns.On("UNIT_DISPLAYPOWER", "Energie", ForUnit(function(b)
    UpdatePowerType(b)
    UpdatePower(b)
end))
ns.On("UNIT_LEVEL", "Name", ForUnit(function(b) UpdateName(b) end))
ns.On("UNIT_NAME_UPDATE", "Name", ForUnit(function(b)
    UpdateName(b)
    UpdateHealthColor(b)
end))
local function StatusAndColor(b)
    UpdateStatus(b)
    UpdateHealthColor(b)
    UpdateHealth(b)
    UpdatePower(b)
end
ns.On("UNIT_CONNECTION", "Status", ForUnit(StatusAndColor))
ns.On("UNIT_FLAGS", "Status", ForUnit(function(b) StatusAndColor(b) UpdateCombat(b) end))
ns.On("PLAYER_FLAGS_CHANGED", "Status", ForUnit(StatusAndColor))
ns.On("UNIT_THREAT_SITUATION_UPDATE", "Bedrohung", ForUnit(UpdateThreat))
-- im Kampf ist das nur noch ein kurzer Abgleich (Blizzard-Anzeige zeichnet selbst)
ns.On("UNIT_AURA", T("Auren", "Auras"), ForUnit(function(b) ns.UpdateAuras(b) UpdatePrediction(b) end))
-- HoT-Fläche schrumpft mit der Restdauer: sekündlich nachziehen, solange eine sichtbar ist
C_Timer.NewTicker(1, function() ForEachShown(function(b) if b.ff and b.ff.hotOn then UpdatePrediction(b) end end) end)
if UI.OnOverTimeChange then UI.OnOverTimeChange(function() ForEachShown(UpdatePrediction) end) end
ns.On("PLAYER_TARGET_CHANGED", "Ziel", function() ForEachShown(UpdateTarget) end)
ns.On("RAID_TARGET_UPDATE", "Zielmarkierung", function() ForEachShown(UpdateMark) end)
ns.On("INCOMING_RESURRECT_CHANGED", T("Wiederbelebung", "Resurrection"), ForUnit(UpdateIncoming))
ns.On("INCOMING_SUMMON_CHANGED", T("Beschwörung", "Summon"), ForUnit(function(b)
    UpdateIncoming(b)
    -- "angenommen"/"abgelehnt" nach ein paar Sekunden noch einmal pruefen
    C_Timer.After(6, function() if b.ffUnit and b:IsVisible() then pcall(UpdateIncoming, b) end end)
end))

-- Gruppe <-> Schlachtzug (oder anderer Reiter im Menue): andere Einstellungen, also Position, Anordnung und
-- Aussehen neu (Position/Anordnung im Kampf erst danach, siehe ns.OutOfCombat)
local appliedMode
function ns.ApplyMode(force)
    local mode = ns.ActiveMode()
    if mode == appliedMode and not force then return end
    appliedMode = mode
    ns.RestorePosition()
    ns.ApplyLayout()
    ns.UpdateAllButtons()
    ForEachShown(ns.UpdateAll)
    if ns.OnMoved then ns.OnMoved() end
    ns.RequestBounds()
end

local function RosterChanged()
    ns.ApplyMode()
    -- gleiche Einheit ("raid3"), aber evtl. ein anderer Spieler: alles neu
    C_Timer.After(0, Safe(T("Gruppe", "Group"), function() ForEachShown(ns.UpdateAll) end))
    -- Blizzards Raid-Stil-Partyrahmen entstehen evtl. erst beim Gruppenbeitritt
    if not InCombatLockdown() then ns.HideBlizzard() end
end
ns.On("GROUP_ROSTER_UPDATE", "Gruppe", RosterChanged)
ns.On("PARTY_LEADER_CHANGED", "Gruppe", function() ForEachShown(UpdateLeader) end)
ns.On("PLAYER_ROLES_ASSIGNED", "Gruppe", function() ForEachShown(UpdateRole) end)

local function ReadyAndIncoming(b)
    UpdateReady(b)
    UpdateIncoming(b)
end
local readyTimer
ns.On("READY_CHECK", "Bereitschaftscheck", function()
    if readyTimer then readyTimer:Cancel() readyTimer = nil end
    for _, b in ipairs(ns.buttons) do b.ffReadyLast = nil end
    ns.readyCheckActive, ns.readyCheckFinished = true, false
    ForEachShown(ReadyAndIncoming)
end)
-- Blizzard meldet die Antwort teils mit "raidN", obwohl der Rahmen "partyN"/"player" zeigt -> alle aktualisieren
ns.On("READY_CHECK_CONFIRM", "Bereitschaftscheck", function() ForEachShown(ReadyAndIncoming) end)
ns.On("READY_CHECK_FINISHED", "Bereitschaftscheck", function()
    ns.readyCheckFinished = true
    ForEachShown(ReadyAndIncoming)
    if readyTimer then readyTimer:Cancel() end
    readyTimer = C_Timer.NewTimer(6, Safe("Bereitschaftscheck", function()
        readyTimer = nil
        ns.readyCheckActive, ns.readyCheckFinished = false, false
        ForEachShown(ReadyAndIncoming)
    end))
end)

ns.On("PLAYER_ENTERING_WORLD", "Welt betreten", function()
    ns.HideBlizzard()
    RosterChanged()
end)

-- Reichweite regelmaessig pruefen
-- (gemeinsamer Takt aus ForeverCore: nur in einer Gruppe oder im Testmodus – allein gibt es keine Reichweite zu prüfen)
ns.UI.Every(0.25, function() ForEachShown(UpdateRange) end, { addon = "ForeverFrames", name = T("Reichweite", "Range"),
    when = function() return IsInGroup() or (ns.testCount or 0) > 0 end })

ns.On("PLAYER_LOGIN", "Start", function()
    appliedMode = ns.ActiveMode()
    ns.RestorePosition()
    ns.ApplyLayout()
    ns.PrecreateButtons()
    if ns.ApplyClicks then ns.ApplyClicks() end
    ns.UpdateMover()
    ns.HideBlizzard()
end)

-- Einrast-Kanten ("bounds") nachziehen, sobald sich Anordnung oder Gruppe aendert (statt jede Sekunde)
for _, name in ipairs({ "ApplyLayout", "LayoutFakes", "SetTestMode" }) do
    if ns[name] then hooksecurefunc(ns, name, ns.RequestBounds) end
end
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
    ns.On(event, T("Rahmen-Kanten", "Frame bounds"), ns.RequestBounds)
end
