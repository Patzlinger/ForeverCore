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
    for _, bar in ipairs({ v.heal, v.shield, v.absorb }) do
        bar:ClearAllPoints()
        bar:SetSize(w, h)
    end
    v.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    v.shield:SetPoint("TOPLEFT", v.heal:GetStatusBarTexture(), "TOPRIGHT")
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
    ns.AddMover(b)
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
    v.leader = v.top:CreateTexture(nil, "OVERLAY")
    v.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    v.mark = v.top:CreateTexture(nil, "OVERLAY")
    v.mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    for _, t in ipairs({ v.pvp, v.leader, v.mark }) do t:Hide() end
    v.resting = v.top:CreateTexture(nil, "OVERLAY")
    v.resting:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    v.resting:SetTexCoord(0, 0.5, 0, 0.421875)
    v.resting:Hide()

    -- Verschiebe-Hinweis (nur entsperrt)
    v.mover = v.top:CreateTexture(nil, "OVERLAY")
    v.mover:SetAllPoints(c)
    v.mover:SetColorTexture(0.2, 0.5, 1, 0.25)
    v.moverText = v.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    v.moverText:SetPoint("BOTTOM", c, "TOP", 0, 2)
    v.moverText:SetText(info.label)
    v.mover:Hide()
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
    ns.AddMover(a)
    dotAnchors[b.key] = a
    return a
end

local function LayoutAuras(b)
    local f = FrameDB(b.key)
    local supported = AurasSupported()
    local dotsOn = supported and f.dotBars and (b.key == "target" or b.key == "focus")
    -- Kombopunkte als Balken unter dem Rahmen (Combo.lua): Auren und DoT-Leisten rücken darunter
    local y = -3 - (ns.ComboSpace and ns.ComboSpace(b, "BELOW") or 0)
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

local function UpdateColor(b)
    local v, look = b.v, Look()
    if IsOffline(b.unit) then
        v.health:SetStatusBarColor(0.4, 0.4, 0.4)
        v.healthBg:SetVertexColor(0.15, 0.15, 0.15)
        return
    end
    local r, g, bl = BarColor(b.unit)
    v.health:SetStatusBarColor(r, g, bl)
    if look.lossColorMode == "custom" then
        local c = look.lossColor
        v.healthBg:SetVertexColor(c[1], c[2], c[3])
    else
        v.healthBg:SetVertexColor(r * 0.22, g * 0.22, bl * 0.22)
    end
end

local CLASSIFICATION = { elite = "+", rareelite = "R+", rare = "R", worldboss = "B" }

local function UpdateName(b)
    local v, f, unit = b.v, FrameDB(b.key), b.unit
    local name = UnitName(unit)
    v.name:SetText(name)
    if not f.levelShow then v.level:SetText("") return end
    local level = UnitLevel(unit)
    if IsSecret(level) then v.level:SetText(level) v.level:SetTextColor(1, 0.82, 0) return end
    local text = (level and level > 0) and tostring(level) or "??"
    local cls = UnitClassification(unit)
    if not IsSecret(cls) and CLASSIFICATION[cls] then text = text .. CLASSIFICATION[cls] end
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
        v.heal:SetValue(0) v.shield:SetValue(0) v.absorb:SetValue(0)
        return
    end
    UnitGetDetailedHealPrediction(unit, "player", c)
    local max = UnitHealthMax(unit)
    if not IsSecret(max) and (not max or max <= 0) then max = 1 end
    v.heal:SetMinMaxValues(0, max)
    if look.healPrediction ~= false then v.heal:SetValue((c:GetIncomingHeals())) else v.heal:SetValue(0) end
    v.shield:SetMinMaxValues(0, max)
    if look.shields ~= false then v.shield:SetValue((c:GetDamageAbsorbs())) else v.shield:SetValue(0) end
    v.absorb:SetMinMaxValues(0, max)
    if look.healAbsorbs ~= false then v.absorb:SetValue((c:GetHealAbsorbs())) else v.absorb:SetValue(0) end
end

local function UpdatePower(b)
    local v, f, unit = b.v, FrameDB(b.key), b.unit
    if f.powerHeight <= 0 then return end
    local pType, pToken = UnitPowerType(unit)
    local c = PowerBarColor and not IsSecret(pType, pToken) and (PowerBarColor[pToken] or PowerBarColor[pType])
    local r, g, bl = 0, 0.45, 1
    if c then r, g, bl = c.r, c.g, c.b end
    v.power:SetStatusBarColor(r, g, bl)
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
    for _, t in ipairs({ v.pvp, v.leader, v.mark }) do t:Hide() end
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

-- Skin "Forever" (optional, nur Aussehen): der Stil der Forever-Fenster – schlanker grauer Rand, flache Balken,
-- Schrift mit Schatten statt Umriss, dunkles Namensband mit feiner Goldlinie und Goldkante oben. Farben (Klasse,
-- Reaktion), Texte und Funktionen bleiben unberührt; ein Schalter in den Einstellungen (Optik) wechselt zurück.
local function SkinLook(look)
    local C = UI.COLOR
    local s = {}
    for k, val in pairs(look) do s[k] = val end
    s.texture = WHITE
    s.borderSize = 1
    s.borderColor = { C.border[1], C.border[2], C.border[3], 1 }
    s.outline = ""
    s.shadow = true
    return s
end

-- Zusatzflächen des Skins (einmalig angelegt, ohne Skin versteckt)
local function ApplySkinParts(b, enabled, stacked, size)
    local v = b.v
    local sk = v.skin
    if not enabled then
        if sk then
            sk.top:Hide() sk.band:Hide() sk.line:Hide()
        end
        return
    end
    if not sk then
        sk = {
            top = v.top:CreateTexture(nil, "BORDER"),
            band = v.top:CreateTexture(nil, "BORDER"),
            line = v.top:CreateTexture(nil, "BORDER"),
        }
        v.skin = sk
    end
    local a = UI.COLOR.accent
    -- Goldkante oben (wie die Linie unter der Titelleiste der Fenster)
    sk.top:ClearAllPoints()
    sk.top:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, 0)
    sk.top:SetPoint("TOPRIGHT", v.content, "TOPRIGHT", 0, 0)
    sk.top:SetHeight(1)
    sk.top:SetColorTexture(a[1], a[2], a[3], 0.55)
    sk.top:Show()
    -- Namensband mit feiner Linie darunter (nur wenn Name und LP in zwei Zeilen stehen)
    if stacked then
        sk.band:ClearAllPoints()
        sk.band:SetPoint("TOPLEFT", v.health, "TOPLEFT", 0, 0)
        sk.band:SetPoint("TOPRIGHT", v.health, "TOPRIGHT", 0, 0)
        sk.band:SetHeight(size + 5)
        sk.band:SetColorTexture(0, 0, 0, 0.38)
        sk.band:Show()
        sk.line:ClearAllPoints()
        sk.line:SetPoint("TOPLEFT", sk.band, "BOTTOMLEFT", 0, 0)
        sk.line:SetPoint("TOPRIGHT", sk.band, "BOTTOMRIGHT", 0, 0)
        sk.line:SetHeight(1)
        sk.line:SetColorTexture(a[1], a[2], a[3], 0.35)
        sk.line:Show()
    else
        sk.band:Hide()
        sk.line:Hide()
    end
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

    ApplySkinParts(b, skinned, stacked, size)

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
ns.On("UNIT_POWER_UPDATE", T("Energie", "Power"), ForUnit(UpdatePower))
ns.On("UNIT_MAXPOWER", T("Energie", "Power"), ForUnit(UpdatePower))
ns.On("UNIT_DISPLAYPOWER", T("Energie", "Power"), ForUnit(UpdatePower))
ns.On("UNIT_NAME_UPDATE", "Name", ForUnit(function(b) UpdateName(b) UpdateColor(b) end))
ns.On("UNIT_LEVEL", T("Stufe", "Level"), ForUnit(UpdateName))
ns.On("UNIT_CLASSIFICATION_CHANGED", T("Stufe", "Level"), ForUnit(UpdateName))
ns.On("UNIT_FACTION", "PvP", ForUnit(function(b) UpdatePvP(b) UpdateColor(b) end))
ns.On("PLAYER_FLAGS_CHANGED", "PvP", ForUnit(UpdatePvP))
ns.On("UNIT_FLAGS", "Status", ForUnit(function(b) UpdatePvP(b) UpdateStatus(b) UpdateColor(b) end))
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
C_Timer.NewTicker(0.25, Safe(T("Ziel des Ziels", "Target of target"), function()
    local b = Frame("targettarget")
    if b and b:IsVisible() and UnitExists("targettarget") then ns.UpdateAll(b) end
end))

ns.On("PLAYER_ENTERING_WORLD", T("Welt betreten", "Entering world"), function()
    ns.HideBlizzard()
    for key in pairs(ns.frames) do Refresh(key) end
end)

ns.On("PLAYER_LOGIN", "Start", function()
    ns.ApplyAll()
    ns.HideBlizzard()
end)
