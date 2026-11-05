-- ForeverUnits: Aufbau und Aktualisierung der Einheitenrahmen
-- Im Kampf koennen Werte "geheim" sein: sie werden nur an Blizzard-Funktionen weitergereicht
-- (Balken, Texte, Farbkurven) – nie damit gerechnet oder verglichen.
local ADDON_NAME, ns = ...
local T, GetDB, FrameDB, IsSecret, Safe = ns.T, ns.GetDB, ns.FrameDB, ns.IsSecret, ns.Safe

local WHITE = "Interface\\Buttons\\WHITE8x8"
ns.frames = {}            -- Schluessel ("target") -> Rahmen
local byUnit = {}         -- Einheit ("target") -> Rahmen

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------
local function NewText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetWordWrap(false)
    return fs
end

local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    return bar
end

local function NewOverlay(parent, reverse)
    local bar = NewBar(parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetValue(0)
    bar:SetReverseFill(reverse)
    return bar
end

-- Heilvorhersage/Schilde beginnen am Ende der Lebenspunkte-Fuellung (keine Rechnung noetig)
local function LayoutOverlays(v)
    local w, h = v.health:GetSize()
    local fill = v.health:GetStatusBarTexture()
    for _, bar in ipairs({ v.heal, v.hotFill, v.hot, v.dotFill, v.dot, v.shield, v.absorb }) do
        bar:ClearAllPoints()
        bar:SetSize(w, h)
    end
    v.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    v.hot:SetPoint("TOPLEFT", v.heal:GetStatusBarTexture(), "TOPRIGHT")
    v.hotFill:SetPoint("TOPLEFT", v.heal:GetStatusBarTexture(), "TOPRIGHT")
    v.dot:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    v.dotFill:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    v.shield:SetPoint("TOPLEFT", v.hot:GetStatusBarTexture(), "TOPRIGHT")
    v.absorb:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
end

---------------------------------------------------------------------------
-- Tooltip, Verschieben
---------------------------------------------------------------------------
local UI = ns.UI
local Round = UI.Round

local function SavePosition(b, dx, dy)
    local f = FrameDB(b.key)
    local x, y = UI.CenterOffset(b)
    f.x = Round(x + (dx or 0))
    f.y = Round(y + (dy or 0))
end

---------------------------------------------------------------------------
-- Ausrichten (Raster, Einrasten, Hilfslinien) kommt aus ForeverHub.lua – gemeinsam mit
-- den anderen Forever-Addons, damit z. B. die Zauberleiste am Spielerrahmen einrastet.
---------------------------------------------------------------------------
function ns.UpdateGrid()
    local d = GetDB()
    UI.Grid("ForeverUnits", (not d.locked and d.gridShow) and d.gridSize or nil)
end

ns.AddMover = UI.AddMover
function ns.BeginDrag(frame)
    local d = GetDB()
    UI.BeginDrag(frame, { snap = d.snap, grid = d.gridShow and d.gridSize or nil })
end
function ns.EndDrag() return UI.EndDrag() end

local function OnEnter(self)
    if GetDB().tooltip and UnitExists(self.unit) then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end
end

local function OnLeave() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- Rahmen anlegen
---------------------------------------------------------------------------
local function CreateUnitFrame(info)
    local b = CreateFrame("Button", "ForeverUnits_" .. info.key, UIParent, "SecureUnitButtonTemplate")
    b.key, b.unit, b.label = info.key, info.unit, info.label
    b:SetAttribute("unit", info.unit)
    b:SetAttribute("*type1", "target")       -- Linksklick: anvisieren
    b:SetAttribute("*type2", "togglemenu")   -- Rechtsklick: Blizzard-Menue
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:SetScript("OnDragStart", function(self)
        if not GetDB().locked and not InCombatLockdown() then
            self:StartMoving()
            ns.BeginDrag(self)
        end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local dx, dy = ns.EndDrag(self)
        if not InCombatLockdown() then
            SavePosition(self, dx, dy)
            ns.Layout(self)
            if ns.OnMoved then ns.OnMoved() end -- Zahlen in den Einstellungen nachziehen
        end
    end)
    ns.AddMover(b, "ForeverUnits")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)

    local v = {}
    b.v = v
    local c = CreateFrame("Frame", nil, b, "BackdropTemplate")
    c:SetAllPoints(b)
    c:SetFrameLevel(b:GetFrameLevel())
    v.content = c

    v.portrait = c:CreateTexture(nil, "ARTWORK")

    v.health = NewBar(c)
    v.health:SetFrameLevel(c:GetFrameLevel() + 1)
    v.healthBg = v.health:CreateTexture(nil, "BACKGROUND")
    v.healthBg:SetAllPoints(v.health)
    v.power = NewBar(c)
    v.power:SetFrameLevel(c:GetFrameLevel() + 1)
    v.powerBg = v.power:CreateTexture(nil, "BACKGROUND")
    v.powerBg:SetAllPoints(v.power)

    v.clip = CreateFrame("Frame", nil, c)
    v.clip:SetAllPoints(v.health)
    v.clip:SetFrameLevel(c:GetFrameLevel() + 2)
    v.clip:SetClipsChildren(true)
    v.heal = NewOverlay(v.clip, false)
    v.hotFill = NewOverlay(v.clip, false) -- Grundfläche unter der Schraffur
    v.dotFill = NewOverlay(v.clip, true) -- Grundfläche unter der DoT-Schraffur
    v.hot = NewOverlay(v.clip, false) -- eigene HoTs: schraffiert
    v.dot = NewOverlay(v.clip, true)  -- eigene DoTs auf dem Ziel: schraffiert, vom Lebensbalken-Ende nach links
    for _, bar in ipairs({ v.hot, v.dot }) do
        bar:SetStatusBarTexture(UI.HATCH_TEXTURE)
        bar:GetStatusBarTexture():SetHorizTile(true)
        bar:GetStatusBarTexture():SetVertTile(true)
    end
    v.shield = NewOverlay(v.clip, false)
    v.absorb = NewOverlay(v.clip, true)
    v.health:SetScript("OnSizeChanged", function() LayoutOverlays(v) end)

    v.top = CreateFrame("Frame", nil, c)
    v.top:SetAllPoints(c)
    v.top:SetFrameLevel(c:GetFrameLevel() + 5)
    v.level = NewText(v.top)
    v.name = NewText(v.top)
    v.hp = NewText(v.top)
    v.pw = NewText(v.top)
    v.status = NewText(v.top)
    v.pvp = v.top:CreateTexture(nil, "OVERLAY")
    v.combat = v.top:CreateTexture(nil, "OVERLAY", nil, 6)
    v.combat:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    v.combat:SetTexCoord(0.5, 1, 0, 0.49)
    v.combat:SetSize(14, 14)
    v.combat:Hide()
    v.leader = v.top:CreateTexture(nil, "OVERLAY")
    v.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    v.mark = v.top:CreateTexture(nil, "OVERLAY")
    v.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    -- Elite/Rar/Boss: Blizzards Symbol (wie an Blizzards Namensplaketten) an der oberen rechten Ecke
    v.classIcon = v.top:CreateTexture(nil, "OVERLAY", nil, 2)
    v.classIcon:SetSize(20, 20)
    v.classIcon:SetPoint("CENTER", c, "TOPRIGHT", -3, -3)
    for _, t in ipairs({ v.pvp, v.leader, v.mark, v.classIcon }) do t:Hide() end
    v.resting = v.top:CreateTexture(nil, "OVERLAY")
    v.resting:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    v.resting:SetTexCoord(0, 0.5, 0, 0.421875)
    v.resting:Hide()

    -- Verschiebe-Hinweis (nur entsperrt)
    v.mover = v.top:CreateTexture(nil, "OVERLAY")
    v.mover:SetAllPoints(c)
    v.mover:SetColorTexture(1, 0.82, 0, 0.12)
    v.moverText = v.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v.moverText:SetPoint("BOTTOM", c, "TOP", 0, 2)
    v.moverText:SetText(info.label)
    v.mover:Hide()
    v.sep = v.top:CreateTexture(nil, "OVERLAY", nil, 5) -- feine Trennlinie zwischen Lebens- und Ressourcenbalken
    v.sep:SetColorTexture(UI.COLOR.accent[1], UI.COLOR.accent[2], UI.COLOR.accent[3], 0.6)
    v.sep:Hide()
    v.moverText:Hide()

    v.auras = {}
    ns.frames[info.key] = b
    byUnit[info.unit] = b
    return b
end

---------------------------------------------------------------------------
-- Auren (Blizzard-Anzeige "AuraContainer": das Spiel zeichnet selbst, auch im Kampf)
---------------------------------------------------------------------------
local function AurasSupported()
    return AuraContainerSortDirection ~= nil and AuraContainerSortMethod ~= nil
end

local function MakeInitializer(size)
    local d = GetDB()
    local timer, tooltip = d.auraTimer, d.auraTooltip
    return function(button)
        button:SetSize(size, size)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)
        if timer then
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:EnableMouse(false)
            cd:SetReverse(true)
            cd:SetDrawEdge(false)
            cd:SetHideCountdownNumbers(true)
            button:SetDurationCooldown(cd)
        end
        -- Tooltip beim Drueberfahren, Klicks gehen durch auf den Rahmen
        if tooltip and button.SetMouseClickEnabled and button.SetMouseMotionEnabled then
            button:EnableMouse(true)
            button:SetMouseClickEnabled(false)
            button:SetMouseMotionEnabled(true)
        else
            button:EnableMouse(false)
        end
    end
end

-- Fluss-Layout: von links nach rechts, neue Zeilen nach unten (oder nach oben, upward = true)
local function FlowRight(c, lineSize, upward)
    local axisEnum = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local dirEnum = AnchorUtil and AnchorUtil.FlowDirection
    if not (axisEnum and dirEnum and c.SetFlowLayoutAxis) then return false end
    local axis = axisEnum.Horizontal or axisEnum.HORIZONTAL or axisEnum.X
    local fwd = dirEnum.Right or dirEnum.Forward or dirEnum.FORWARD or dirEnum.Positive
    local down = dirEnum.Down or dirEnum.Backward or dirEnum.BACKWARD or dirEnum.Negative
    local up = dirEnum.Up or fwd
    if axis == nil or fwd == nil or down == nil then return false end
    return pcall(function()
        c:SetFlowLayoutAxis(axis)
        c:SetFlowLayoutGrowthDirection(fwd, upward and up or down)
        c:SetFlowLayoutAnchorPoint(upward and "BOTTOMLEFT" or "TOPLEFT")
        c:SetFlowLayoutMaximumLineSize(math.max(1, lineSize))
    end)
end

-- Ein Container pro Aura-Art; aendert sich das Aussehen, wird ein frischer angelegt
-- (vorhandene Symbole uebernehmen neue Groessen nicht, und Gruppen neu anlegen vertraegt er nicht)
local function EnsureAuraContainer(b, kind, filter, num, size)
    local d = GetDB()
    local sig = table.concat({ size, tostring(d.auraTimer), tostring(d.auraTooltip) }, ":")
    local c = b.v.auras[kind]
    if not c or c.fuSig ~= sig then
        if c then pcall(c.ClearAuraGroups, c) c:Hide() end
        local ok
        ok, c = pcall(CreateFrame, "AuraContainer", nil, b.v.top, "CustomAuraContainerTemplate")
        if not ok or not c then return nil end
        ok = pcall(c.AddAuraGroup, c, "fu", filter, {
            maxFrameCount = num,
            sortMethod = AuraContainerSortMethod.Default,
            sortDirection = AuraContainerSortDirection.Normal,
            initializeFrame = MakeInitializer(size),
        })
        if not ok then c:Hide() return nil end
        c.fuSig, c.fuUnit = sig, nil
        b.v.auras[kind] = c
    end
    pcall(c.SetAuraGroupFilterString, c, "fu", filter)
    pcall(c.SetAuraGroupMaxFrameCount, c, "fu", num)
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = 2, lineSpacing = 2, layoutIndex = 1 }
    if not FlowRight(c, b:GetWidth()) then
        layout.growthDirection = "RIGHT_DOWN"
        layout.wrapAfter = b:GetWidth()
    end
    pcall(c.SetAuraGroupLayout, c, "fu", layout)
    return c
end

-- Neues Ziel/Fokus: komplett neu einlesen. Sonst behaelt die Anzeige die Symbole des alten
-- Ziels (deren Ablauf meldet das Spiel nicht mehr) und Buffs stapeln sich doppelt.
-- Dafuer kurz auf eine andere Einheit umstellen und sofort zurueck.
local function RefreshAuraUnit(b)
    local other = b.unit == "player" and "target" or "player"
    -- DoT-Leisten nur bei angreifbaren Zielen (Einstellung): auf einem selbst oder Gruppenmitgliedern stünden sonst
    -- eigene Schwächungszauber wie "Boosted Rest" vom Lagern als Leiste mit Restzeit. Blizzards Anzeige kann
    -- einzelne Zauber nicht ausschließen – deshalb die ganze Leiste nur bei Gegnern.
    local dc = b.v.auras.dots
    if dc and b.fuDotsWanted ~= nil then
        local show = b.fuDotsWanted
        if show and GetDB().dotOnlyHostile and UnitExists(b.unit) then
            local can = UnitCanAttack("player", b.unit)
            if not IsSecret(can) and not can then show = false end
        end
        pcall(dc.SetShown, dc, show and true or false)
    end
    for _, c in pairs(b.v.auras) do
        if c:IsShown() then
            pcall(c.SetUnit, c, other)
            pcall(c.SetUnit, c, b.unit)
        end
    end
end
ns.RefreshAuraUnit = RefreshAuraUnit

---------------------------------------------------------------------------
-- DoT-Leisten: meine DoTs auf Ziel/Fokus untereinander, kuerzeste Restzeit oben.
-- Auch hier zeichnet die Blizzard-Anzeige: Symbol, Restzeit als Zahl (Farbe nach
-- verbleibendem Anteil: weiss -> orange im Auffrischfenster -> rot) und Ablauf-Scheibe.
---------------------------------------------------------------------------
-- Restzeit-Format: unter 10 s mit Kommastelle, ab 1 Min. als m:ss
local timeFormatter
local function TimeFormatter()
    if timeFormatter == nil then
        timeFormatter = false
        if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
            local ok, fmt = pcall(function()
                local f = C_StringUtil.CreateNumericRuleFormatter()
                f:AddBreakpoint({ threshold = 0, step = 0.1, format = "%.1f" })
                f:AddBreakpoint({ threshold = 10, step = 1, format = "%d" })
                f:AddBreakpoint({ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } })
                return f
            end)
            if ok then timeFormatter = fmt end
        end
    end
    return timeFormatter or nil
end

-- Textfarbe nach verbleibendem Anteil (in Prozent)
local timerCurve
local function TimerCurve()
    if timerCurve == nil then
        timerCurve = false
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
            local c = C_CurveUtil.CreateColorCurve()
            if Enum and Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
            c:AddPoint(0, CreateColor(1, 0.25, 0.25, 1))
            c:AddPoint(15, CreateColor(1, 0.25, 0.25, 1))
            c:AddPoint(30, CreateColor(1, 0.6, 0.1, 1))   -- Auffrischfenster
            c:AddPoint(30.01, CreateColor(1, 1, 1, 1))
            timerCurve = c
        end
    end
    return timerCurve or nil
end

-- Falls der Client eine Balken-Bindung kennt, laeuft die Leiste sichtbar ab (sonst bleibt sie voll)
local BAR_BINDINGS = { "SetDurationStatusBar", "SetDurationBar", "SetTimerStatusBar", "SetDurationProgressBar" }
ns.dotBarBinding = nil

-- drain = true: Leiste leert sich (zeigt die Restzeit), false: Leiste fuellt sich (vergangene Zeit)
local function MakeDotInitializer(width, height, drain)
    local d = GetDB()
    local tooltip = d.auraTooltip
    return function(button)
        button:SetSize(width, height)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.7)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetSize(height - 2, height - 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)

        local look = ns.currentLook or ns.Look()
        local tex = look.texture or WHITE
        -- farbige Flaeche hinter dem Balken; beim Leeren deckt der (dunkle) Balken sie von rechts ab
        local fill = button:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", icon, "TOPRIGHT", 1, 0)
        fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        fill:SetTexture(tex)
        fill:SetVertexColor(0.55, 0.3, 0.8, 0.85)
        fill:SetShown(drain)
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetAllPoints(fill)
        bar:SetStatusBarTexture(tex)
        if drain then
            -- Blizzard fuellt mit der vergangenen Zeit: dunkel von rechts -> die Farbe schrumpft nach links
            bar:SetStatusBarColor(0, 0, 0, 0.8)
            bar:SetReverseFill(true)
        else
            bar:SetStatusBarColor(0.55, 0.3, 0.8, 0.85)
        end
        bar:SetMinMaxValues(0, 1)
        local bound = false
        for _, m in ipairs(BAR_BINDINGS) do
            if button[m] and pcall(button[m], button, bar) then
                ns.dotBarBinding = m
                bound = true
                break
            end
        end
        -- ohne Bindung: Leiste bleibt voll stehen
        if not bound then bar:SetValue(drain and 0 or 1) end

        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:EnableMouse(false)
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        button:SetDurationCooldown(cd)

        local textLayer = CreateFrame("Frame", nil, button)
        textLayer:SetAllPoints(button)
        textLayer:SetFrameLevel(bar:GetFrameLevel() + 2)
        local fontSize = math.max(8, height - 5)
        local timer = textLayer:CreateFontString(nil, "OVERLAY")
        timer:SetFont(look.font or STANDARD_TEXT_FONT, fontSize, "OUTLINE")
        timer:SetPoint("RIGHT", button, "RIGHT", -4, 0)
        if button.SetDurationText then
            local opts = { textFormatter = TimeFormatter() }
            local curve = TimerCurve()
            if curve and Enum and Enum.DurationTextBindingProperty then
                opts.textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingPercent }
            end
            if not pcall(button.SetDurationText, button, timer, opts) then
                pcall(button.SetDurationText, button, timer)
            end
        end
        local stacks = textLayer:CreateFontString(nil, "OVERLAY")
        stacks:SetFont(look.font or STANDARD_TEXT_FONT, math.max(7, fontSize - 2), "OUTLINE")
        stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
        if button.SetApplicationCount then pcall(button.SetApplicationCount, button, stacks) end

        if tooltip and button.SetMouseClickEnabled and button.SetMouseMotionEnabled then
            button:EnableMouse(true)
            button:SetMouseClickEnabled(false)
            button:SetMouseMotionEnabled(true)
        else
            button:EnableMouse(false)
        end
    end
end

local function EnsureDotContainer(b, num, width, height, drain, upward)
    local d = GetDB()
    local sig = table.concat({ "dots", width, height, tostring(d.auraTooltip), tostring(drain),
        tostring(ns.currentLook and ns.currentLook.texture) }, ":")
    local c = b.v.auras.dots
    if not c or c.fuSig ~= sig then
        if c then pcall(c.ClearAuraGroups, c) c:Hide() end
        local ok
        ok, c = pcall(CreateFrame, "AuraContainer", nil, b.v.top, "CustomAuraContainerTemplate")
        if not ok or not c then return nil end
        ok = pcall(c.AddAuraGroup, c, "fu_dots", "HARMFUL|PLAYER", {
            maxFrameCount = num,
            sortMethod = AuraContainerSortMethod.Expiration or AuraContainerSortMethod.Default,
            sortDirection = AuraContainerSortDirection.Normal,
            initializeFrame = MakeDotInitializer(width, height, drain),
        })
        if not ok then c:Hide() return nil end
        c.fuSig = sig
        b.v.auras.dots = c
    end
    pcall(c.SetAuraGroupMaxFrameCount, c, "fu_dots", num)
    -- eine Leiste pro Zeile: Zeilenlaenge = Leistenbreite
    local layout = { elementWidth = width, elementHeight = height, elementSpacing = 1, lineSpacing = 1, layoutIndex = 1 }
    if not FlowRight(c, width, upward) then
        layout.growthDirection = upward and "RIGHT_UP" or "RIGHT_DOWN"
        layout.wrapAfter = width
    end
    pcall(c.SetAuraGroupLayout, c, "fu_dots", layout)
    return c
end

-- Frei verschiebbare DoT-Leisten: eigener Anker am Bildschirm (pro Rahmen), entsperrt ziehbar
local dotAnchors = {}
local function DotAnchor(b)
    local a = dotAnchors[b.key]
    if a then return a end
    a = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    a:SetFrameStrata("DIALOG")
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")
    a:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    a:SetBackdropColor(0.2, 0.5, 1, 0.4)
    a:SetBackdropBorderColor(0.4, 0.7, 1, 1)
    a.text = a:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a.text:SetPoint("CENTER")
    a.text:SetText(string.format(T("DoT-Leisten (%s)\nziehen", "DoT bars (%s)\ndrag"), b.label))
    a:Hide()
    a:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
            ns.BeginDrag(self)
        end
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local dx, dy = ns.EndDrag(self)
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            local f = FrameDB(b.key)
            f.dotFreeX = Round(cx - ux + dx)
            f.dotFreeY = Round(cy - uy + dy)
            ns.UpdateDotAnchor(b)
        end
    end)
    ns.AddMover(a, "ForeverUnits")
    dotAnchors[b.key] = a
    return a
end

local function LayoutAuras(b)
    local f = FrameDB(b.key)
    local supported = AurasSupported()
    local dotsOn = supported and f.dotBars and (b.key == "target" or b.key == "focus")
    -- Kombopunkte als Balken unter dem Rahmen (Combo.lua): Auren und DoT-Leisten rücken darunter
    local y = -3 - (ns.ComboSpace and ns.ComboSpace(b, "BELOW") or 0)
    -- Zauberleiste von ForeverCast (Ziel/Fokus, angedockt): Platz direkt darunter, Andockpunkt b.fcCastDock
    local castH = _G.ForeverCastDockHeight and _G.ForeverCastDockHeight(b.key) or 0
    if castH > 0 then
        b.fcCastDock = b.fcCastDock or CreateFrame("Frame", nil, b)
        b.fcCastDock:ClearAllPoints()
        b.fcCastDock:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, y)
        b.fcCastDock:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, y)
        b.fcCastDock:SetHeight(castH)
        y = y - castH - 3
    elseif b.fcCastDock then
        b.fcCastDock:ClearAllPoints()
        b.fcCastDock:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, y)
        b.fcCastDock:SetSize(1, 1)
    end
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        local wanted = supported and f[kind]
        local c = b.v.auras[kind]
        if wanted then
            -- Mit DoT-Leisten stehen meine Debuffs schon dort: in der Reihe dann nur die der
            -- anderen ("!PLAYER" = nicht von mir) – derselbe DoT eines anderen Hexenmeisters
            -- erscheint so hier, meiner nicht doppelt.
            local filter
            if kind == "buffs" then
                filter = "HELPFUL"
            elseif dotsOn then
                filter = "HARMFUL|!PLAYER"
            else
                filter = f.onlyMine and "HARMFUL|PLAYER" or "HARMFUL"
            end
            c = EnsureAuraContainer(b, kind, filter, math.min(f.auraNum, 16), f.auraSize)
        end
        if c then
            if wanted then
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, y)
                c:Show()
                y = y - f.auraSize - 2
            else
                c:Hide()
            end
        end
    end
    -- DoT-Leisten (nur Ziel und Fokus) unter den Auren
    local dotsWanted = dotsOn
    local dc = b.v.auras.dots
    local where = f.dotPoint or "BELOW"
    if dotsWanted then
        dc = EnsureDotContainer(b, math.min(f.dotNum, 10), f.dotWidth > 0 and f.dotWidth or f.width,
            f.dotHeight, f.dotDirection ~= "fill", where == "ABOVE")
    end
    if dc then
        if dotsWanted then
            local dx, dy = f.dotX or 0, f.dotY or 0
            dc:ClearAllPoints()
            if where == "ABOVE" then
                dc:SetPoint("BOTTOMLEFT", b, "TOPLEFT", dx, 3 + dy + (ns.ComboSpace and ns.ComboSpace(b, "ABOVE") or 0))
            elseif where == "LEFT" then
                dc:SetPoint("TOPRIGHT", b, "TOPLEFT", -3 + dx - (ns.ComboSpace and ns.ComboSpace(b, "LEFT") or 0), dy)
            elseif where == "RIGHT" then
                dc:SetPoint("TOPLEFT", b, "TOPRIGHT", 3 + dx + (ns.ComboSpace and ns.ComboSpace(b, "RIGHT") or 0), dy)
            elseif where == "FREE" then
                -- eigener Anker: Leisten haengen nicht mehr am Rahmen
                local a = DotAnchor(b)
                local w = f.dotWidth > 0 and f.dotWidth or f.width
                a:SetSize(w, math.max(f.dotHeight, math.min(f.dotNum, 10) * (f.dotHeight + 1)))
                a:ClearAllPoints()
                a:SetPoint("CENTER", UIParent, "CENTER", f.dotFreeX or 0, f.dotFreeY or -150)
                dc:SetPoint("TOPLEFT", a, "TOPLEFT", dx, dy)
            else
                dc:SetPoint("TOPLEFT", b, "BOTTOMLEFT", dx, y + dy)
            end
            dc:Show()
            b.fuDotsWanted = true -- RefreshAuraUnit blendet sie bei nicht angreifbaren Zielen aus
        else
            dc:Hide()
            b.fuDotsWanted = false
        end
    end
    ns.UpdateDotAnchor(b)
    RefreshAuraUnit(b)
end

-- Anker der freien DoT-Leisten: immer da (auch ohne Ziel), sichtbar nur entsperrt + "Frei"
function ns.UpdateDotAnchor(b)
    if b.key ~= "target" and b.key ~= "focus" then return end
    local f = FrameDB(b.key)
    local a = DotAnchor(b)
    local w = f.dotWidth > 0 and f.dotWidth or f.width
    a:SetSize(w, math.max(f.dotHeight, math.min(f.dotNum, 10) * (f.dotHeight + 1)))
    a:ClearAllPoints()
    a:SetPoint("CENTER", UIParent, "CENTER", f.dotFreeX or 0, f.dotFreeY or -150)
    local show = f.dotBars and f.dotPoint == "FREE" and not GetDB().locked
    a:SetShown(show and true or false)
    a:EnableMouse(show and true or false)
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------
local function Look() return ns.currentLook or ns.Look() end

local function BarColor(unit)
    local look = Look()
    local isPlayer = UnitIsPlayer(unit)
    if IsSecret(isPlayer) then isPlayer = true end
    if not isPlayer then
        local tapped = UnitIsTapDenied(unit)
        if not IsSecret(tapped) and tapped then return 0.5, 0.5, 0.5 end
        if GetDB().npcReactionColor then
            local reaction = UnitReaction(unit, "player")
            local c = not IsSecret(reaction) and reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
            if c and reaction < 5 then return c.r, c.g, c.b end -- feindlich/neutral immer in Reaktionsfarbe
        end
    end
    if look.barColorMode == "custom" then
        local c = look.barColor
        return c[1], c[2], c[3]
    end
    if isPlayer then return ns.ClassColor(unit) end
    return 0.2, 0.75, 0.3
end

-- Spieler, der offline ist? (gesperrte Werte zaehlen als "nein")
local function IsOffline(unit)
    local isPlayer, connected = UnitIsPlayer(unit), UnitIsConnected(unit)
    if IsSecret(isPlayer, connected) then return false end
    return isPlayer and not connected
end

-- Füllfarbe eines Balkens. Skin "Forever": Farbe etwas gedeckter (ein Fünftel Richtung Grau, wie die Erfahrungs-
-- leiste von ForeverBars) und mit leichtem Glanz – senkrechter Verlauf, unten dunkler, oben heller.
-- Ohne Skin: wie bisher (ein früherer Verlauf wird dabei auf Weiß zurückgesetzt). Gibt die benutzte Farbe zurück.
local function SetBarFill(bar, r, g, bl)
    local tex = bar:GetStatusBarTexture()
    local canGradient = tex and tex.SetGradient and CreateColor
    if GetDB().skin == "FOREVER" then
        local gray = (r + g + bl) / 3
        r, g, bl = r * 0.8 + gray * 0.2, g * 0.8 + gray * 0.2, bl * 0.8 + gray * 0.2
        if canGradient then
            bar:SetStatusBarColor(1, 1, 1)
            tex:SetGradient("VERTICAL", CreateColor(r * 0.72, g * 0.72, bl * 0.72, 1),
                CreateColor(math.min(1, r * 1.12), math.min(1, g * 1.12), math.min(1, bl * 1.12), 1))
            return r, g, bl
        end
    elseif canGradient then
        tex:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
    end
    bar:SetStatusBarColor(r, g, bl)
    return r, g, bl
end
ns.SetBarFill = SetBarFill

local function UpdateColor(b)
    local v, look = b.v, Look()
    if IsOffline(b.unit) then
        SetBarFill(v.health, 0.4, 0.4, 0.4)
        v.healthBg:SetVertexColor(0.15, 0.15, 0.15)
        return
    end
    local r, g, bl = SetBarFill(v.health, BarColor(b.unit))
    if look.lossColorMode == "custom" then
        local c = look.lossColor
        v.healthBg:SetVertexColor(c[1], c[2], c[3])
    elseif GetDB().skin == "FOREVER" then
        -- verlorene Lebenspunkte: sehr dunkle Klassenfarbe, fast schwarz – die Füllung hebt sich klar ab
        v.healthBg:SetVertexColor(r * 0.16 + 0.03, g * 0.16 + 0.03, bl * 0.16 + 0.04)
    else
        v.healthBg:SetVertexColor(r * 0.22, g * 0.22, bl * 0.22)
    end
end

local CLASSIFICATION = { elite = "+", rareelite = "R+", rare = "R", worldboss = "B" }
-- Blizzards Symbole (dieselben wie an den Namensplaketten dieses Clients)
local CLASS_ATLAS = {
    elite = "Interface\\AddOns\\ForeverCore\\Media\\EliteGold", worldboss = "Interface\\AddOns\\ForeverCore\\Media\\EliteGold",
    rareelite = "Interface\\AddOns\\ForeverCore\\Media\\EliteSilver", rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}
ns.CLASS_ATLAS = CLASS_ATLAS

-- Eigene Grafik (Pfad) oder Blizzard-Atlas; false, wenn nicht ladbar
local function SetClassTex(tex, src)
    if src:find("^Interface") then tex:SetTexture(src) tex:SetTexCoord(0, 1, 0, 1) return true end
    return tex:SetAtlas(src)
end

local function UpdateName(b)
    local v, f, unit = b.v, FrameDB(b.key), b.unit
    local name = UnitName(unit)
    -- Spieler: Vor-/Nachname nach der Hub-Einstellung (Standard "Hexeron S."); NPC-Namen bleiben (haben auch Leerzeichen)
    local isPlayer = UnitIsPlayer(unit)
    if not IsSecret(isPlayer) and isPlayer and UI.PlayerName then name = UI.PlayerName(name) end
    v.name:SetText(name)
    -- Skin: Eckklammern für Elite/Rare (unabhängig davon, ob die Stufe angezeigt wird)
    local cls0 = UnitClassification(unit)
    if IsSecret(cls0) then cls0 = nil end
    if ns.SkinClassification then ns.SkinClassification(b, cls0) end
    -- Symbol für Elite/Rar/Boss (an Spielern nie: die sind "normal")
    local atlas = f.classIcon and cls0 and CLASS_ATLAS[cls0]
    if atlas and SetClassTex(v.classIcon, atlas) ~= false then v.classIcon:Show() else v.classIcon:Hide() end
    if not f.levelShow then v.level:SetText("") return end
    local level = UnitLevel(unit)
    if IsSecret(level) then v.level:SetText(level) v.level:SetTextColor(1, 0.82, 0) return end
    local text = (level and level > 0) and tostring(level) or "??"
    local cls = UnitClassification(unit)
    if not IsSecret(cls) and CLASSIFICATION[cls] and not (atlas and v.classIcon:IsShown()) then text = text .. CLASSIFICATION[cls] end
    v.level:SetText(text)
    -- Farbe nach den klassischen Erfahrungsregeln (gemeinsam im Hub; Blizzards Funktion faerbt zu frueh grau)
    if level and level > 0 then
        local c = UI.LevelColor(level)
        v.level:SetTextColor(c.r, c.g, c.b)
    else
        v.level:SetTextColor(1, 0.1, 0.1) -- "??" = viel hoeher als man selbst
    end
end

local function SetHealthText(v, f, unit, cur, max)
    local fmt, fs = f.hpFormat, v.hp
    if fmt == "none" or v.statusActive then fs:Hide() return end
    fs:Show()
    local Num = ns.ShortNumber
    if IsSecret(cur, max) then
        local curve = CurveConstants and CurveConstants.ScaleTo100
        if (fmt == "percent" or fmt == "curpercent") and curve and UnitHealthPercent then
            if fmt == "percent" then
                fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, curve))
            else
                fs:SetFormattedText("%s · %.0f%%", Num(cur), UnitHealthPercent(unit, true, curve))
            end
        elseif fmt == "curmax" then
            fs:SetFormattedText("%s / %s", Num(cur), Num(max))
        elseif fmt == "deficit" and UnitHealthMissing then
            fs:SetFormattedText("-%s", Num(UnitHealthMissing(unit, true)))
        else
            fs:SetFormattedText("%s", Num(cur))
        end
        return
    end
    if not max or max <= 0 then fs:SetText("") return end
    local pct = math.floor(cur / max * 100 + 0.5)
    if fmt == "percent" then
        fs:SetFormattedText("%d%%", pct)
    elseif fmt == "cur" then
        fs:SetText(Num(cur))
    elseif fmt == "curmax" then
        fs:SetFormattedText("%s / %s", Num(cur), Num(max))
    elseif fmt == "deficit" then
        fs:SetText(cur >= max and "" or ("-" .. Num(max - cur)))
    else
        fs:SetFormattedText("%s · %d%%", Num(cur), pct)
    end
end

local function UpdateStatus(b)
    local v, unit = b.v, b.unit
    local text
    if IsOffline(unit) then
        text = "Offline"
    else
        local ghost, dead = UnitIsGhost(unit), UnitIsDead(unit)
        if not IsSecret(ghost) and ghost then
            text = T("Geist", "Ghost")
        elseif not IsSecret(dead) and dead then
            text = T("Tot", "Dead")
        end
    end
    v.statusActive = text ~= nil
    v.status:SetText(text or "")
    v.status:SetShown(v.statusActive)
end

local function UpdateHealth(b)
    local v, unit = b.v, b.unit
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if IsSecret(cur, max) then
        v.health:SetMinMaxValues(0, max)
        v.health:SetValue(cur)
    else
        v.health:SetMinMaxValues(0, (max and max > 0) and max or 1)
        v.health:SetValue(cur or 0)
    end
    SetHealthText(v, FrameDB(b.key), unit, cur, max)
end

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
        if calc and Enum and Enum.UnitDamageAbsorbClampMode then
            pcall(calc.SetDamageAbsorbClampMode, calc, Enum.UnitDamageAbsorbClampMode.MissingHealth)
        end
    end
    return calc
end

local function UpdatePrediction(b)
    local v, look, unit = b.v, Look(), b.unit
    local c = GetCalc()
    if not c or not UnitGetDetailedHealPrediction then
        v.heal:SetValue(0) v.hot:SetValue(0) v.hotFill:SetValue(0) v.dot:SetValue(0) v.dotFill:SetValue(0) v.shield:SetValue(0) v.absorb:SetValue(0)
        return
    end
    UnitGetDetailedHealPrediction(unit, "player", c)
    local max = UnitHealthMax(unit)
    if not IsSecret(max) and (not max or max <= 0) then max = 1 end
    v.heal:SetMinMaxValues(0, max)
    if look.healPrediction ~= false then v.heal:SetValue((c:GetIncomingHeals())) else v.heal:SetValue(0) end
    -- eigene HoTs (Freund) bzw. DoTs (Feind): schraffierte Fläche, Schätzung aus den Zauberbeschreibungen
    v.hot:SetMinMaxValues(0, max)
    v.hotFill:SetMinMaxValues(0, max)
    v.dot:SetMinMaxValues(0, max)
    v.dotFill:SetMinMaxValues(0, max)
    local hot, dot = 0, 0
    if UI.OverTimeRemaining then
        local hostile = UnitCanAttack("player", unit)
        if not IsSecret(hostile) and hostile then
            if look.dotPrediction ~= false and (b.key == "target" or b.key == "focus" or b.key == "targettarget") then
                dot = UI.OverTimeRemaining(unit, "damage")
            end
        elseif look.hotPrediction ~= false then
            hot = UI.OverTimeRemaining(unit, "heal")
        end
    end
    v.hot:SetValue(hot)
    v.hotFill:SetValue(hot)
    v.dot:SetValue(dot)
    v.dotFill:SetValue(dot)
    v.overOn = hot > 0 or dot > 0
    if dot > 0 then
        local cur = UnitHealth(unit)
        local lethal = not IsSecret(cur) and cur and dot >= cur
        if lethal then v.dot:SetStatusBarColor(1, 0.85, 0.85, 1) v.dotFill:SetStatusBarColor(1, 0.05, 0.05, 0.8)
        else v.dot:SetStatusBarColor(1, 0.6, 0.35, 1) v.dotFill:SetStatusBarColor(0.9, 0.2, 0.1, 0.5) end
    end
    v.shield:SetMinMaxValues(0, max)
    if look.shields ~= false then v.shield:SetValue((c:GetDamageAbsorbs())) else v.shield:SetValue(0) end
    v.absorb:SetMinMaxValues(0, max)
    if look.healAbsorbs ~= false then v.absorb:SetValue((c:GetHealAbsorbs())) else v.absorb:SetValue(0) end
end

-- Kampf-Marker (gekreuzte Schwerter) unten links, solange die Einheit im Kampf ist
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
    local v, unit = b.v, b.unit
    if Look().combatMarker == false or not unit or not UnitExists(unit) then v.combat:Hide() return end
    local c = UnitAffectingCombat(unit)
    local on = not IsSecret(c) and c and true or false
    if on then PlaceCombat(v.name, v.combat, 20) end
    v.combat:SetShown(on)
end

local function UpdatePower(b)
    local v, f, unit = b.v, FrameDB(b.key), b.unit
    if f.powerHeight <= 0 then return end
    local pType, pToken = UnitPowerType(unit)
    local c = PowerBarColor and not IsSecret(pType, pToken) and (PowerBarColor[pToken] or PowerBarColor[pType])
    local r, g, bl = 0, 0.45, 1
    if c then r, g, bl = c.r, c.g, c.b end
    r, g, bl = SetBarFill(v.power, r, g, bl)
    v.powerBg:SetVertexColor(r * 0.25, g * 0.25, bl * 0.25)
    local cur, max = UnitPower(unit), UnitPowerMax(unit)
    if IsSecret(cur, max) then
        v.power:SetMinMaxValues(0, max)
        v.power:SetValue(cur)
    else
        v.power:SetMinMaxValues(0, (max and max > 0) and max or 1)
        v.power:SetValue(cur or 0)
    end
    if f.powerText and f.powerHeight >= 7 then
        if IsSecret(cur, max) or (max and max > 0) then
            v.pw:SetFormattedText("%s", ns.ShortNumber(cur))
        else
            v.pw:SetText("")
        end
    end
end

-- Porträt: Klassensymbol (Spieler) oder 2D-Porträt (NPCs bzw. immer)
local function UpdatePortrait(b)
    local v, f, unit = b.v, FrameDB(b.key), b.unit
    if f.portrait == "none" then return end
    if f.portrait == "class" then
        local isPlayer = UnitIsPlayer(unit)
        local _, class = UnitClass(unit)
        if not IsSecret(isPlayer, class) and isPlayer and class then
            local atlas = "classicon-" .. class:lower()
            if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
                v.portrait:SetTexCoord(0, 1, 0, 1) -- Zuschnitt vom vorigen Porträt zuruecksetzen
                v.portrait:SetAtlas(atlas)
                return
            elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
                v.portrait:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
                v.portrait:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
                return
            end
        end
    end
    SetPortraitTexture(v.portrait, unit)
    v.portrait:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- nur den Rand weg, nicht hineinzoomen
end

-- Ausruhen (Gasthaus/Hauptstadt): nur am Spielerrahmen
local function UpdateResting(b)
    if b.key ~= "player" then b.v.resting:Hide() return end
    local resting = GetDB().restingShow and IsResting()
    b.v.resting:SetShown(not IsSecret(resting) and resting and true or false)
end

-- PvP-Symbol, nur wenn PvP aktiv ist
local function UpdatePvP(b)
    local v, unit = b.v, b.unit
    if not GetDB().pvpShow then v.pvp:Hide() return end
    local tex
    local ffa = UnitIsPVPFreeForAll(unit)
    if not IsSecret(ffa) and ffa then
        tex = "Interface\\TargetingFrame\\UI-PVP-FFA"
    else
        local pvp = UnitIsPVP(unit)
        if not IsSecret(pvp) and pvp then
            local faction = UnitFactionGroup(unit)
            if IsSecret(faction) then
                tex = nil
            elseif faction == "Horde" then
                tex = "Interface\\TargetingFrame\\UI-PVP-Horde"
            elseif faction == "Alliance" then
                tex = "Interface\\TargetingFrame\\UI-PVP-Alliance"
            end
        end
    end
    if tex then
        v.pvp:SetTexture(tex)
        v.pvp:SetTexCoord(0, 0.62, 0, 0.62)
        v.pvp:Show()
    else
        v.pvp:Hide()
    end
end

local function UpdateLeader(b)
    local leader = GetDB().leaderShow and UnitIsGroupLeader(b.unit)
    b.v.leader:SetShown(not IsSecret(leader) and leader and true or false)
end

local function UpdateMark(b)
    local v = b.v
    local index = GetDB().markShow and GetRaidTargetIndex(b.unit)
    if IsSecret(index) or not index or index < 1 or index > 8 then v.mark:Hide() return end
    local i = index - 1
    local x, y = (i % 4) * 0.25, math.floor(i / 4) * 0.25
    v.mark:SetTexCoord(x, x + 0.25, y, y + 0.25)
    v.mark:Show()
end

-- Platzhalter im Verschiebe-Modus, solange es die Einheit nicht gibt (z. B. kein Ziel)
local function ShowPlaceholder(b)
    local v = b.v
    v.name:SetText(b.label)
    v.level:SetText("")
    v.hp:SetText("")
    v.pw:SetText("")
    v.status:Hide()
    v.health:SetMinMaxValues(0, 1)
    v.health:SetValue(1)
    v.health:SetStatusBarColor(0.35, 0.35, 0.4)
    v.healthBg:SetVertexColor(0.1, 0.1, 0.1)
    v.power:SetMinMaxValues(0, 1)
    v.power:SetValue(1)
    v.power:SetStatusBarColor(0, 0.45, 1)
    v.portrait:SetTexture(134400) -- Fragezeichen
    v.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    v.heal:SetValue(0) v.shield:SetValue(0) v.absorb:SetValue(0)
    -- Elite/Rar/Boss: Blizzards Symbol (wie an Blizzards Namensplaketten) an der oberen rechten Ecke
    v.classIcon = v.top:CreateTexture(nil, "OVERLAY", nil, 2)
    v.classIcon:SetSize(20, 20)
    v.classIcon:SetPoint("CENTER", c, "TOPRIGHT", -3, -3)
    for _, t in ipairs({ v.pvp, v.leader, v.mark, v.classIcon }) do t:Hide() end
end

function ns.UpdateAll(b)
    if not UnitExists(b.unit) then
        if not GetDB().locked then ShowPlaceholder(b) end
        return
    end
    UpdateName(b)
    UpdateColor(b)
    UpdateStatus(b)
    UpdateHealth(b)
    UpdatePower(b)
    UpdatePrediction(b)
    UpdatePortrait(b)
    UpdatePvP(b)
    UpdateCombat(b)
    UpdateLeader(b)
    UpdateMark(b)
    UpdateResting(b)
end

---------------------------------------------------------------------------
-- Anordnung eines Rahmens aus den Einstellungen
---------------------------------------------------------------------------
local function SetFont(fs, look, size, justify)
    fs:SetFont(look.font or STANDARD_TEXT_FONT, size, look.outline or "")
    if look.shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
    fs:SetJustifyH(justify)
end

---------------------------------------------------------------------------
-- Skin "Forever" (optional, nur Aussehen) – die Designsprache der Forever-Fenster auf den Einheitenrahmen:
--   * Rahmen wie die Forever-Tooltips: feine graue Kante, oben eine Goldlinie; innen trennen dunkle Fugen
--     Porträt, Lebens- und Energiebalken (statt eines durchgehend grauen Rands)
--   * Balken gedeckt mit leichtem Glanz (SetBarFill) und einer hauchfeinen Lichtkante oben
--   * Namensband: dunkles Band mit Verlauf und feiner Goldlinie darunter (wie die Titelleisten)
--   * Porträt unten leicht abgedunkelt, damit es in den Rahmen übergeht
--   * Elite/Boss: goldene Eckklammern an der oberen Außenecke, Rare: silberne
--   * Maus darüber: Kante leuchtet gold (wie bei den Knöpfen); Spielerrahmen im Kampf: Oberkante dezent rot
-- Funktionen, Texte und Farbwahl (Klasse, Reaktion) bleiben; ein Schalter in den Einstellungen (Optik) wechselt zurück.
---------------------------------------------------------------------------
local SKIN_INNER = { 0.025, 0.025, 0.035, 1 } -- Fugen zwischen den Teilen (fast schwarz)
local SKIN_COMBAT = { 0.85, 0.22, 0.18 }       -- Oberkante des Spielerrahmens im Kampf
local SKIN_RARE = { 0.78, 0.84, 0.95 }         -- Eckklammern bei seltenen Gegnern (Silber)

local function SkinLook(look)
    local s = {}
    for k, val in pairs(look) do s[k] = val end
    s.texture = WHITE
    s.borderSize = 1
    s.borderColor = SKIN_INNER
    s.outline = ""
    s.shadow = true
    return s
end

-- Farbe der Außenkante: Maus darüber = Gold; Spieler im Kampf = Oberkante rot; sonst grau mit Goldlinie oben
local function SkinEdgeColors(b)
    local sk = b.v.skin
    if not sk or not sk.shown then return end
    local C, a = UI.COLOR, UI.COLOR.accent
    if b.fuHover then
        for _, e in pairs(sk.edges) do e:SetColorTexture(a[1], a[2], a[3], 0.9) end
        return
    end
    for side, e in pairs(sk.edges) do
        if side ~= "top" then e:SetColorTexture(C.border[1], C.border[2], C.border[3], 1) end
    end
    if b.unit == "player" and sk.inCombat then
        sk.edges.top:SetColorTexture(SKIN_COMBAT[1], SKIN_COMBAT[2], SKIN_COMBAT[3], 0.9)
    else
        sk.edges.top:SetColorTexture(a[1], a[2], a[3], 0.65)
    end
end

-- Eckklammern (zwei kurze Linien an der oberen Außenecke) für Elite, Boss und Rare
function ns.SkinClassification(b, classification)
    local sk = b.v.skin
    if not sk then return end
    local color
    if sk.shown then
        if classification == "elite" or classification == "worldboss" or classification == "rareelite" then
            color = UI.COLOR.accent
        elseif classification == "rare" then
            color = SKIN_RARE
        end
    end
    for i, t in ipairs(sk.bracket) do
        if color then
            if i <= 2 then
                t:SetColorTexture(color[1], color[2], color[3], 1)
            else
                t:SetColorTexture(0, 0, 0, 0.6) -- feiner dunkler Schatten innen an der Klammer
            end
        end
        t:SetShown(color ~= nil)
    end
end

local function CreateSkinParts(b)
    local v = b.v
    local layer = CreateFrame("Frame", nil, v.content)
    layer:SetAllPoints(v.content)
    layer:SetFrameLevel(v.content:GetFrameLevel() + 4) -- über den Balken, unter Texten und Symbolen
    local function Tex(sub) return layer:CreateTexture(nil, "OVERLAY", nil, sub or 0) end
    local sk = { layer = layer, edges = {}, bracket = {} }
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do sk.edges[side] = Tex(2) end
    sk.band, sk.line = Tex(-2), Tex(-1)
    sk.shineHealth, sk.shinePower = Tex(-1), Tex(-1)
    sk.vignette = Tex(-2)
    for i = 1, 4 do sk.bracket[i] = Tex(3) end
    v.skin = sk
    -- Maus darüber: Kante gold
    b:HookScript("OnEnter", function(self) self.fuHover = true SkinEdgeColors(self) end)
    b:HookScript("OnLeave", function(self) self.fuHover = nil SkinEdgeColors(self) end)
    return sk
end

-- Kampfbeginn/-ende: Oberkante des Spielerrahmens
local function SkinCombat(inCombat)
    local b = ns.frames.player
    local sk = b and b.v.skin
    if not sk then return end
    sk.inCombat = inCombat
    SkinEdgeColors(b)
end
ns.On("PLAYER_REGEN_DISABLED", "Skin", function() SkinCombat(true) end)
ns.On("PLAYER_REGEN_ENABLED", "Skin", function() SkinCombat(false) end)

-- Zusatzflächen des Skins (einmalig angelegt, ohne Skin versteckt)
local function ApplySkinParts(b, enabled, stacked, size, f)
    local v = b.v
    local sk = v.skin
    if not enabled then
        if sk then
            sk.shown = false
            sk.layer:Hide()
        end
        return
    end
    sk = sk or CreateSkinParts(b)
    sk.shown = true
    sk.layer:Show()
    local c = v.content

    -- Außenkante (1 px rundherum, genau über dem dunklen Rand)
    local e = sk.edges
    e.top:ClearAllPoints() e.top:SetPoint("TOPLEFT", c) e.top:SetPoint("TOPRIGHT", c) e.top:SetHeight(1)
    e.bottom:ClearAllPoints() e.bottom:SetPoint("BOTTOMLEFT", c) e.bottom:SetPoint("BOTTOMRIGHT", c) e.bottom:SetHeight(1)
    e.left:ClearAllPoints() e.left:SetPoint("TOPLEFT", c) e.left:SetPoint("BOTTOMLEFT", c) e.left:SetWidth(1)
    e.right:ClearAllPoints() e.right:SetPoint("TOPRIGHT", c) e.right:SetPoint("BOTTOMRIGHT", c) e.right:SetWidth(1)
    sk.inCombat = b.unit == "player" and InCombatLockdown() or false
    SkinEdgeColors(b)

    -- Lichtkanten oben auf den Balken
    sk.shineHealth:ClearAllPoints()
    sk.shineHealth:SetPoint("TOPLEFT", v.health, "TOPLEFT")
    sk.shineHealth:SetPoint("TOPRIGHT", v.health, "TOPRIGHT")
    sk.shineHealth:SetHeight(1)
    sk.shineHealth:SetColorTexture(1, 1, 1, 0.12)
    sk.shineHealth:SetShown(not stacked) -- mit Namensband trägt dessen Goldlinie die Kante
    sk.shinePower:ClearAllPoints()
    sk.shinePower:SetPoint("TOPLEFT", v.power, "TOPLEFT")
    sk.shinePower:SetPoint("TOPRIGHT", v.power, "TOPRIGHT")
    sk.shinePower:SetHeight(1)
    sk.shinePower:SetColorTexture(1, 1, 1, 0.10)
    sk.shinePower:SetShown(f.powerHeight > 0)

    -- Namensband mit feiner Goldlinie darunter (nur wenn Name und LP in zwei Zeilen stehen)
    local a = UI.COLOR.accent
    if stacked then
        sk.band:ClearAllPoints()
        sk.band:SetPoint("TOPLEFT", v.health, "TOPLEFT", 0, 0)
        sk.band:SetPoint("TOPRIGHT", v.health, "TOPRIGHT", 0, 0)
        sk.band:SetHeight(size + 5)
        sk.band:SetColorTexture(1, 1, 1, 1)
        if sk.band.SetGradient and CreateColor then
            -- oben dunkler, nach unten auslaufend
            sk.band:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.22), CreateColor(0, 0, 0, 0.55))
        else
            sk.band:SetColorTexture(0, 0, 0, 0.4)
        end
        sk.band:Show()
        sk.line:ClearAllPoints()
        sk.line:SetPoint("TOPLEFT", sk.band, "BOTTOMLEFT", 0, 0)
        sk.line:SetPoint("TOPRIGHT", sk.band, "BOTTOMRIGHT", 0, 0)
        sk.line:SetHeight(1)
        sk.line:SetColorTexture(a[1], a[2], a[3], 0.4)
        sk.line:Show()
    else
        sk.band:Hide()
        sk.line:Hide()
    end

    -- Porträt: unten leicht abgedunkelt
    if f.portrait ~= "none" and v.portrait:IsShown() then
        sk.vignette:ClearAllPoints()
        sk.vignette:SetPoint("BOTTOMLEFT", v.portrait, "BOTTOMLEFT")
        sk.vignette:SetPoint("BOTTOMRIGHT", v.portrait, "BOTTOMRIGHT")
        sk.vignette:SetHeight(math.max(4, math.floor(v.portrait:GetHeight() * 0.45)))
        sk.vignette:SetColorTexture(1, 1, 1, 1)
        if sk.vignette.SetGradient and CreateColor then
            sk.vignette:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
            sk.vignette:Show()
        else
            sk.vignette:Hide()
        end
    else
        sk.vignette:Hide()
    end

    -- Eckklammern an der oberen Außenecke (Seite des Porträts; ohne Porträt rechts)
    local outerRight = f.portrait == "none" or f.portraitSide == "RIGHT"
    local corner = outerRight and "TOPRIGHT" or "TOPLEFT"
    local dx = outerRight and -1 or 1
    local len = math.max(6, math.floor(math.min(f.height, 40) * 0.3))
    local br = sk.bracket
    -- zwei Linien je Klammer, leicht nach außen versetzt (wie eine eingefasste Ecke), plus dunkler Schatten
    br[1]:ClearAllPoints() br[1]:SetPoint(corner, c, corner, -dx * 2, 2) br[1]:SetSize(len, 2)
    br[2]:ClearAllPoints() br[2]:SetPoint(corner, c, corner, -dx * 2, 2) br[2]:SetSize(2, len)
    br[3]:ClearAllPoints() br[3]:SetPoint(corner, c, corner, -dx * 2 + dx, 1) br[3]:SetSize(len - 1, 1)
    br[4]:ClearAllPoints() br[4]:SetPoint(corner, c, corner, -dx * 2 + dx, 1) br[4]:SetSize(1, len - 1)
    br[3]:SetDrawLayer("OVERLAY", 4) br[4]:SetDrawLayer("OVERLAY", 4)
    for i = 1, 4 do br[i]:Hide() end
    local cls = UnitExists(b.unit) and UnitClassification(b.unit) or nil
    ns.SkinClassification(b, (not IsSecret(cls)) and cls or nil)
end

function ns.Layout(b)
    local d, f, look = GetDB(), FrameDB(b.key), Look()
    local skinned = d.skin == "FOREVER"
    if skinned then look = SkinLook(look) end
    local v = b.v
    ns.OutOfCombat("pos-" .. b.key, function()
        b:SetSize(f.width, f.height)
        b:ClearAllPoints()
        b:SetPoint("CENTER", UIParent, "CENTER", f.x, f.y)
    end)

    local bs = look.borderSize or 1
    local bc = look.borderColor or { 0, 0, 0, 1 }
    v.content:SetBackdrop({ bgFile = WHITE })
    v.content:SetBackdropColor(bc[1], bc[2], bc[3], bc[4] or 1)

    -- Porträt (quadratisch, so hoch wie der Rahmen)
    local hasPortrait = f.portrait ~= "none"
    local ps = f.height - 2 * bs
    local left, right = bs, -bs
    v.portrait:ClearAllPoints()
    if hasPortrait then
        v.portrait:SetSize(ps, ps)
        if f.portraitSide == "RIGHT" then
            v.portrait:SetPoint("TOPRIGHT", v.content, "TOPRIGHT", -bs, -bs)
            right = -bs - ps - bs
        else
            v.portrait:SetPoint("TOPLEFT", v.content, "TOPLEFT", bs, -bs)
            left = bs + ps + bs
        end
        v.portrait:Show()
    else
        v.portrait:Hide()
    end

    -- Balken
    local tex = look.texture or WHITE
    for _, bar in ipairs({ v.health, v.power }) do bar:SetStatusBarTexture(tex) end
    v.healthBg:SetTexture(tex)
    v.powerBg:SetTexture(tex)
    local hc, sc, ac = look.healColor, look.shieldColor, look.healAbsorbColor
    if hc then v.heal:SetStatusBarColor(hc[1], hc[2], hc[3], hc[4] or 1) end
    if hc then
        v.hot:SetStatusBarColor(math.min(1, hc[1] + 0.5), math.min(1, hc[2] + 0.5), math.min(1, hc[3] + 0.5), 1)
        v.hotFill:SetStatusBarColor(math.min(1, hc[1] + 0.2), math.min(1, hc[2] + 0.2), math.min(1, hc[3] + 0.2), 0.4)
    end
    if sc then v.shield:SetStatusBarColor(sc[1], sc[2], sc[3], sc[4] or 1) end
    if ac then v.absorb:SetStatusBarColor(ac[1], ac[2], ac[3], ac[4] or 1) end

    v.health:ClearAllPoints()
    v.health:SetPoint("TOPLEFT", v.content, "TOPLEFT", left, -bs)
    v.health:SetPoint("TOPRIGHT", v.content, "TOPRIGHT", right, -bs)
    if f.powerHeight > 0 then
        v.power:ClearAllPoints()
        v.power:SetPoint("BOTTOMLEFT", v.content, "BOTTOMLEFT", left, bs)
        v.power:SetPoint("BOTTOMRIGHT", v.content, "BOTTOMRIGHT", right, bs)
        v.power:SetHeight(f.powerHeight)
        v.power:Show()
        v.health:SetPoint("BOTTOMLEFT", v.power, "TOPLEFT", 0, bs)
        v.health:SetPoint("BOTTOMRIGHT", v.power, "TOPRIGHT", 0, bs)
    else
        v.power:Hide()
        v.health:SetPoint("BOTTOMLEFT", v.content, "BOTTOMLEFT", left, bs)
        v.health:SetPoint("BOTTOMRIGHT", v.content, "BOTTOMRIGHT", right, bs)
    end

    -- Trennlinie (optional): oberste Zeile des Ressourcenbalkens
    v.sep:ClearAllPoints()
    if f.powerHeight > 0 and GetDB().powerSeparator ~= false then
        v.sep:SetPoint("TOPLEFT", v.power, "TOPLEFT", 0, 0)
        v.sep:SetPoint("TOPRIGHT", v.power, "TOPRIGHT", 0, 0)
        v.sep:SetHeight(1)
        v.sep:Show()
    else
        v.sep:Hide()
    end

    -- Texte. "stacked" (Standard): Stufe + Name oben, Lebenspunkte darunter – wie bei den
    -- Raidrahmen, damit lange Namen nichts ueberdecken. "inline": alles in einer Zeile.
    local size = f.fontSize
    -- zwei Zeilen nur, wenn der Lebensbalken hoch genug ist (sonst z. B. beim schmalen Begleiter-
    -- Rahmen: Name links, LP rechts in einer Zeile)
    local healthH = f.height - 2 * bs - ((f.powerHeight > 0) and (f.powerHeight + bs) or 0)
    local stacked = f.textLayout ~= "inline" and healthH >= 2 * size + 4
    SetFont(v.level, look, size, "LEFT")
    SetFont(v.name, look, size, "LEFT")
    SetFont(v.hp, look, size, stacked and "LEFT" or "RIGHT")
    SetFont(v.pw, look, math.max(7, size - 3), "RIGHT")
    SetFont(v.status, look, size, "CENTER")
    local anchor, rowY = stacked and "TOPLEFT" or "LEFT", stacked and -2 or 0
    v.level:ClearAllPoints()
    v.level:SetPoint(anchor, v.health, anchor, 4, rowY)
    v.name:ClearAllPoints()
    if f.levelShow then
        v.name:SetPoint(anchor, v.level, stacked and "TOPRIGHT" or "RIGHT", 4, 0)
    else
        v.name:SetPoint(anchor, v.health, anchor, 4, rowY)
    end
    if stacked then
        v.name:SetPoint("RIGHT", v.health, "RIGHT", -4, 0)
    else
        v.name:SetPoint("RIGHT", v.health, "RIGHT", f.hpFormat == "none" and -4 or -(size * 4), 0)
    end
    v.level:SetShown(f.levelShow)
    v.name:SetShown(f.nameShow)
    v.hp:ClearAllPoints()
    if stacked then
        v.hp:SetPoint("BOTTOMLEFT", v.health, "BOTTOMLEFT", 4, 2)
    else
        v.hp:SetPoint("RIGHT", v.health, "RIGHT", -4, 0)
    end
    v.pw:ClearAllPoints()
    v.pw:SetPoint("RIGHT", v.power, "RIGHT", -3, 0)
    v.pw:SetShown(f.powerText and f.powerHeight >= 7)
    v.status:ClearAllPoints()
    v.status:SetPoint("CENTER", v.health, "CENTER", 0, 0)

    -- Symbole: PvP an der Aussenecke auf der Porträt-Seite, Anführer und Markierung oben
    local outerRight = f.portraitSide == "RIGHT"
    v.pvp:ClearAllPoints()
    v.pvp:SetSize(math.floor(f.height * 0.6 + 0.5), math.floor(f.height * 0.6 + 0.5))
    if outerRight then
        v.pvp:SetPoint("CENTER", v.content, "TOPRIGHT", 2, -2)
    else
        v.pvp:SetPoint("CENTER", v.content, "TOPLEFT", -2, -2)
    end
    v.leader:ClearAllPoints()
    v.leader:SetSize(12, 12)
    v.leader:SetPoint("BOTTOMLEFT", v.health, "TOPLEFT", 2, -5)
    v.mark:ClearAllPoints()
    v.mark:SetSize(16, 16)
    v.mark:SetPoint("CENTER", v.content, "TOP", 0, 0)
    -- Ausruhen: obere Ecke gegenueber dem PvP-Symbol
    v.resting:ClearAllPoints()
    v.resting:SetSize(18, 18)
    if outerRight then
        v.resting:SetPoint("CENTER", v.content, "TOPLEFT", -2, -2)
    else
        v.resting:SetPoint("CENTER", v.content, "TOPRIGHT", 2, -2)
    end

    ApplySkinParts(b, skinned, stacked, size, f)

    -- Verschiebe-Hinweis
    v.mover:SetShown(not d.locked)
    v.moverText:SetShown(not d.locked)

    LayoutOverlays(v)
    LayoutAuras(b)
    ns.UpdateAll(b)
end

---------------------------------------------------------------------------
-- An/Aus, Sperren, Blizzard-Rahmen
---------------------------------------------------------------------------
-- Sichtbarkeit: gesperrt -> Blizzard blendet ein/aus (gibt es kein Ziel, kein Rahmen);
-- entsperrt -> immer sichtbar (Platzhalter), damit man alles verschieben kann
local function ApplyVisibility(b)
    ns.OutOfCombat("vis-" .. b.key, function()
        local f = FrameDB(b.key)
        UnregisterUnitWatch(b)
        if not f.enabled then
            b:Hide()
        elseif GetDB().locked then
            RegisterUnitWatch(b)
        else
            b:Show()
        end
    end)
end

-- Blizzard-Rahmen sicher ausblenden (Blizzards geschuetzter Sichtbarkeits-Treiber statt :Hide(),
-- sonst laufen Blizzards Skripte im Namen dieses Addons und z. B. das Rechtsklick-Menue wird gestoert)
local hiddenFrames = {}
local function HideBlizzardFrame(frame)
    if not frame or hiddenFrames[frame] then return end
    hiddenFrames[frame] = true
    frame:UnregisterAllEvents()
    if not (RegisterStateDriver and pcall(RegisterStateDriver, frame, "visibility", "hide")) then
        frame:Hide()
    end
end

local BLIZZARD = {
    hideBlizzPlayer = { "PlayerFrame" },
    hideBlizzTarget = { "TargetFrame" },
    hideBlizzFocus = { "FocusFrame" },
    hideBlizzPet = { "PetFrame" },
}

function ns.HideBlizzard()
    ns.OutOfCombat("blizzard", function()
        local d = GetDB()
        for key, names in pairs(BLIZZARD) do
            if d[key] then
                for _, name in ipairs(names) do HideBlizzardFrame(_G[name]) end
            end
        end
    end)
end

-- Alles neu aufbauen (nach Aenderungen in den Einstellungen oder an der ForeverFrames-Optik)
-- Hub: Einstellung "Spielernamen" geändert -> Namen neu
if UI.On then
    UI.On("NameStyleChanged", function()
        for _, info in ipairs(ns.UNITS) do
            local b = ns.frames[info.key]
            if b and b.unit and UnitExists(b.unit) then pcall(ns.UpdateAll, b) end
        end
    end)
    -- ForeverCast: Zauberleiste für Ziel/Fokus an-/abgedockt -> Platz unter den Rahmen neu verteilen
    UI.On("ForeverCastDock", function()
        local function Relayout()
            for _, key in ipairs({ "target", "focus" }) do
                local b = ns.frames[key]
                if b then pcall(LayoutAuras, b) end
            end
        end
        -- sofort, im Kampf erst danach (UI.AfterCombat: Schlüssel, Funktion, Addon)
        UI.AfterCombat("ForeverUnits:castDock", Relayout, "ForeverUnits")
    end)
end

function ns.ApplyAll()
    ns.currentLook = ns.Look()
    for _, info in ipairs(ns.UNITS) do
        local b = ns.frames[info.key]
        ApplyVisibility(b)
        local ok, err = pcall(ns.Layout, b)
        if not ok then ns.ReportError(T("Rahmen", "Frame") .. " " .. info.key, err) end
        pcall(ns.UpdateDotAnchor, b) -- auch wenn der Aufbau oben scheitert
    end
    local ok, err = pcall(ns.UpdateGrid)
    if not ok then ns.ReportError(T("Raster", "Grid"), err) end
end

-- ForeverFrames meldet sich hier, wenn sich dessen Optik aendert
_G.ForeverUnitsRefresh = function()
    if GetDB().syncLook then ns.ApplyAll() end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
for _, info in ipairs(ns.UNITS) do
    local b = CreateUnitFrame(info)
    -- beim Einblenden sofort den aktuellen Stand zeigen
    b:HookScript("OnShow", function(self)
        local ok, err = pcall(ns.UpdateAll, self)
        if not ok then ns.ReportError(T("Rahmen", "Frame"), err) end
        RefreshAuraUnit(self)
    end)
end

local function ForUnit(fn)
    return function(unit, ...)
        local b = unit and byUnit[unit]
        if b and b:IsVisible() then fn(b, ...) end
    end
end

-- auch unsichtbare Rahmen aktualisieren: Blizzard blendet z. B. den Zielrahmen erst
-- einen Moment nach dem Zielwechsel ein
local function Frame(key)
    local b = ns.frames[key]
    if b and FrameDB(key).enabled then return b end
end

local function Refresh(key)
    local b = Frame(key)
    if b then
        ns.UpdateAll(b)
        RefreshAuraUnit(b)
    end
end

ns.On("UNIT_HEALTH", T("Lebenspunkte", "Health"), ForUnit(function(b)
    UpdateStatus(b)
    UpdateHealth(b)
    UpdatePrediction(b)
end))
ns.On("UNIT_MAXHEALTH", T("Lebenspunkte", "Health"), ForUnit(function(b)
    UpdateHealth(b)
    UpdatePrediction(b)
end))
ns.On("UNIT_HEAL_PREDICTION", T("Heilvorhersage", "Heal prediction"), ForUnit(UpdatePrediction))
ns.On("UNIT_ABSORB_AMOUNT_CHANGED", T("Schilde", "Shields"), ForUnit(UpdatePrediction))
ns.On("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", T("Heilabsorption", "Heal absorbs"), ForUnit(UpdatePrediction))
ns.On("UNIT_AURA", T("HoT/DoT-Vorhersage", "HoT/DoT prediction"), ForUnit(UpdatePrediction))
if UI.OnOverTimeChange then UI.OnOverTimeChange(function() for _, b in pairs(ns.frames) do if b:IsVisible() then UpdatePrediction(b) end end end) end
-- Flächen schrumpfen mit der Restdauer: sekündlich nachziehen, solange eine sichtbar ist
C_Timer.NewTicker(1, function()
    for _, b in pairs(ns.frames) do if b:IsVisible() and b.v and b.v.overOn then pcall(UpdatePrediction, b) end end
end)
ns.On("UNIT_POWER_UPDATE", T("Energie", "Power"), ForUnit(UpdatePower))
ns.On("UNIT_MAXPOWER", T("Energie", "Power"), ForUnit(UpdatePower))
ns.On("UNIT_DISPLAYPOWER", T("Energie", "Power"), ForUnit(UpdatePower))
ns.On("UNIT_NAME_UPDATE", "Name", ForUnit(function(b) UpdateName(b) UpdateColor(b) end))
ns.On("UNIT_LEVEL", T("Stufe", "Level"), ForUnit(UpdateName))
ns.On("UNIT_CLASSIFICATION_CHANGED", T("Stufe", "Level"), ForUnit(UpdateName))
ns.On("UNIT_FACTION", "PvP", ForUnit(function(b) UpdatePvP(b) UpdateColor(b) end))
ns.On("PLAYER_FLAGS_CHANGED", "PvP", ForUnit(UpdatePvP))
ns.On("UNIT_FLAGS", "Status", ForUnit(function(b) UpdatePvP(b) UpdateCombat(b) UpdateStatus(b) UpdateColor(b) end))
ns.On("PLAYER_REGEN_DISABLED", "Kampf", function() local b = ns.frames.player if b then UpdateCombat(b) end end)
ns.On("PLAYER_REGEN_ENABLED", "Kampf", function() local b = ns.frames.player if b then UpdateCombat(b) end end)
ns.On("UNIT_CONNECTION", "Status", ForUnit(function(b) UpdateStatus(b) UpdateColor(b) UpdateHealth(b) end))
ns.On("UNIT_PORTRAIT_UPDATE", T("Porträt", "Portrait"), ForUnit(UpdatePortrait))
ns.On("UNIT_MODEL_CHANGED", T("Porträt", "Portrait"), ForUnit(UpdatePortrait))
ns.On("RAID_TARGET_UPDATE", T("Zielmarkierung", "Raid marker"), function()
    for _, b in pairs(ns.frames) do if b:IsVisible() then UpdateMark(b) end end
end)
ns.On("PARTY_LEADER_CHANGED", T("Gruppe", "Group"), function()
    for _, b in pairs(ns.frames) do if b:IsVisible() then UpdateLeader(b) end end
end)
ns.On("GROUP_ROSTER_UPDATE", T("Gruppe", "Group"), function()
    for _, b in pairs(ns.frames) do if b:IsVisible() then UpdateLeader(b) end end
end)

ns.On("PLAYER_TARGET_CHANGED", T("Ziel", "Target"), function()
    Refresh("target")
    Refresh("targettarget")
end)
ns.On("UNIT_TARGET", T("Ziel des Ziels", "Target of target"), function(unit)
    if unit == "target" then Refresh("targettarget") end
end)
ns.On("PLAYER_FOCUS_CHANGED", T("Fokus", "Focus"), function() Refresh("focus") end)
ns.On("PLAYER_UPDATE_RESTING", T("Ausruhen", "Resting"), function()
    local b = Frame("player")
    if b then UpdateResting(b) end
end)
ns.On("UNIT_PET", T("Begleiter", "Pet"), function(unit)
    if unit == "player" then C_Timer.After(0, function() pcall(Refresh, "pet") end) end
end)

-- "Ziel des Ziels" meldet keine Aenderungen: regelmaessig nachsehen (nur wenn sichtbar)
-- (gemeinsamer Takt aus ForeverCore: nur, solange es ein Ziel des Ziels gibt)
UI.Every(0.25, function()
    local b = Frame("targettarget")
    if b and b:IsVisible() then ns.UpdateAll(b) end
end, { addon = "ForeverUnits", name = T("Ziel des Ziels", "Target of target"), when = function() return UnitExists("targettarget") end })

ns.On("PLAYER_ENTERING_WORLD", T("Welt betreten", "Entering world"), function()
    ns.HideBlizzard()
    for key in pairs(ns.frames) do Refresh(key) end
end)

ns.On("PLAYER_LOGIN", "Start", function()
    ns.ApplyAll()
    ns.HideBlizzard()
end)
