-- ForeverUnits – Combo.lua: Kombopunkte am Zielrahmen (Schurken, Druiden in Katzengestalt).
-- Drei Orte zur Wahl: "PORTRAIT" = senkrechte Spalte direkt neben dem Porträt (Standard), "BELOW" = Balken mit
-- 5 Strichen unter dem Rahmen, "ABOVE" = Punkte über dem Rahmen. Jeder Punkt ist ein kleiner Balken
-- (Bereich i-1 bis i), so zeigt er auch gesperrte Werte ("secret values") richtig an, ohne zu rechnen.
local ADDON_NAME, ns = ...
local T, GetDB, IsSecret = ns.T, ns.GetDB, ns.IsSecret
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAX_PIPS = 10
local GAP = 3   -- Abstand der Punkte: 1 px dunkler Rand je Punkt + 1 px Lücke
local GLOW = 3  -- so weit leuchtet ein gefüllter Punkt über seinen Rand hinaus

local combo -- { frame, pips = { {bar, bg, edge} } }

local _, playerClass = UnitClass("player")
local COMBO_POWER = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4

-- Farbe je Punkt: von hellem Gold (erster) zu leuchtendem Orangerot (letzter)
local function PipColor(i, count)
    local t = count > 1 and (i - 1) / (count - 1) or 1
    return 1, 0.92 - 0.52 * t, 0.35 - 0.2 * t
end

-- gesperrte Werte nicht prüfen oder vergleichen, nur weiterreichen
local function Points()
    local n
    if GetComboPoints then n = GetComboPoints("player", "target") else n = UnitPower("player", COMBO_POWER) end
    if IsSecret(n) then return n end
    return n or 0
end

local function MaxPoints()
    local m = UnitPowerMax and UnitPowerMax("player", COMBO_POWER)
    if IsSecret(m) or not m or m <= 0 then return 5 end
    return math.min(m, MAX_PIPS)
end

-- Kann die Klasse überhaupt Kombopunkte haben? (Druiden: nur in Katzengestalt bzw. sobald Punkte da sind)
local function ClassUsesCombo(n)
    if playerClass == "ROGUE" then return true end
    if playerClass == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID()
        if form == 1 then return true end -- Katzengestalt
        return IsSecret(n) or (n or 0) > 0
    end
    return false
end

local function Build(b)
    if combo then return combo end
    combo = { pips = {} }
    local f = CreateFrame("Frame", nil, b)
    f:SetFrameLevel(b.v.top:GetFrameLevel() + 2) -- über Namen und Lebensbalken
    combo.frame = f
    for i = 1, MAX_PIPS do
        -- Leuchten: gleicher Wert wie der Punkt, etwas größer, hinter ihm und additiv (nur gefüllt sichtbar)
        local glow = CreateFrame("StatusBar", nil, f)
        glow:SetFrameLevel(f:GetFrameLevel())
        glow:SetStatusBarTexture(WHITE)
        glow:GetStatusBarTexture():SetBlendMode("ADD")
        glow:SetMinMaxValues(i - 1, i)
        glow:SetValue(0)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetFrameLevel(f:GetFrameLevel() + 1)
        bar.glow = glow
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        local edge = bar:CreateTexture(nil, "BACKGROUND", nil, -1) -- 1 px dunkler Rand um den Punkt
        edge:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(0)
        combo.pips[i] = { bar = bar, bg = bg, edge = edge }
    end
    f:Hide()
    return combo
end

-- Platz, den die Kombopunkte unter bzw. über dem Rahmen brauchen (Auren und DoT-Leisten rücken dann weiter weg)
function ns.ComboSpace(b, where)
    local d = GetDB()
    if b.key ~= "target" or not d.comboShow then return 0 end
    if not (playerClass == "ROGUE" or playerClass == "DRUID") then return 0 end
    local point = d.comboPoint or "PORTRAIT"
    if point == "BELOW" and where == "BELOW" then return (d.comboSize or 8) + 3 end
    if point == "ABOVE" and where == "ABOVE" then return (d.comboSize or 8) + 4 + 10 end
    -- Spalte außen neben dem Porträt: DoT-Leisten auf derselben Seite rücken weiter weg
    local side = ns.FrameDB("target").portraitSide == "LEFT" and "LEFT" or "RIGHT"
    if point == "PORTRAIT" and where == side then return (d.comboSize or 8) + 3 end
    return 0
end

local function LayoutCombo(b)
    local d, fdb = GetDB(), ns.FrameDB("target")
    if not (d.comboShow and (playerClass == "ROGUE" or playerClass == "DRUID")) then
        if combo then combo.frame:Hide() end
        return
    end
    -- einmalig: neuer Standard 10 px (vorher 8) für alle, die die Größe nicht selbst geändert haben
    if not d.comboSizeV2 then
        if d.comboSize == 8 then d.comboSize = 10 end
        d.comboSizeV2 = true
    end
    local c = Build(b)
    local v = b.v
    local size = d.comboSize or 10
    local count = MaxPoints()
    local where = d.comboPoint or "PORTRAIT"
    local frame = c.frame
    frame:ClearAllPoints()
    local round = where == "ABOVE"
    local pipW, pipH, vertical
    if where == "BELOW" then
        -- Balken mit Strichen, so breit wie der Rahmen
        local w = fdb.width
        pipW, pipH = (w - (count - 1) * GAP) / count, size
        frame:SetSize(w, size)
        frame:SetPoint("TOPLEFT", v.content, "BOTTOMLEFT", 0, -3)
    elseif where == "ABOVE" then
        -- runde Punkte über dem Lebensbalken (über der Zielmarkierung)
        local dot = size + 2
        pipW, pipH = dot, dot
        frame:SetSize(count * dot + (count - 1) * (GAP + 1), dot)
        frame:SetPoint("BOTTOM", v.health, "TOP", 0, 10)
    else
        -- senkrechte Spalte außen neben dem Porträt, genau so hoch wie der Rahmen (samt 1-px-Rand der Punkte)
        vertical = true
        local h = fdb.height
        pipW, pipH = size, (h - 2 - (count - 1) * GAP) / count
        frame:SetSize(size + 2, h)
        -- außen am Rahmen auf der Seite des Porträts (beim Ziel: rechts neben dem Porträt)
        if fdb.portraitSide == "LEFT" then
            frame:SetPoint("RIGHT", v.content, "LEFT", -3, 0)
        else
            frame:SetPoint("LEFT", v.content, "RIGHT", 3, 0)
        end
    end
    for i, p in ipairs(c.pips) do
        local bar = p.bar
        bar:ClearAllPoints()
        if i <= count then
            bar:SetSize(pipW, pipH)
            if vertical then
                -- von unten nach oben füllen
                bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, 1 + (i - 1) * (pipH + GAP))
            elseif round then
                bar:SetPoint("LEFT", frame, "LEFT", (i - 1) * (pipW + GAP + 1), 0)
            else
                bar:SetPoint("LEFT", frame, "LEFT", (i - 1) * (pipW + GAP), 0)
            end
            bar:SetStatusBarTexture(round and ROUND or WHITE)
            local r, g, bl = PipColor(i, count)
            bar:SetStatusBarColor(r, g, bl)
            local glow = bar.glow
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -GLOW, GLOW)
            glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", GLOW, -GLOW)
            glow:SetStatusBarTexture(round and ROUND or WHITE)
            glow:GetStatusBarTexture():SetBlendMode("ADD")
            glow:SetStatusBarColor(r, g, bl, 0.35)
            glow:Show()
            p.bg:SetTexture(round and ROUND or WHITE)
            p.bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)
            p.edge:SetTexture(round and ROUND or WHITE)
            p.edge:SetVertexColor(0, 0, 0, 0.9)
            bar:Show()
        else
            bar:Hide()
            bar.glow:Hide()
        end
    end
    c.count = count
    ns.UpdateCombo()
end

function ns.UpdateCombo()
    if not combo then return end
    local d = GetDB()
    local frame = combo.frame
    local n = Points()
    -- entsperrt ohne Ziel: Platzhalter mit 3 Punkten, damit man die Lage sieht
    local preview = not d.locked and not UnitExists("target")
    if preview then n = 3 end
    local show = d.comboShow and (preview or (UnitExists("target") and ClassUsesCombo(n)))
    if show and not preview and not d.comboShowEmpty and not IsSecret(n) and n <= 0 then show = false end
    if show and not preview then
        local attackable = UnitCanAttack("player", "target")
        if not IsSecret(attackable) and not attackable and (IsSecret(n) or n <= 0) then show = false end
    end
    if not show then frame:Hide() return end
    for i = 1, (combo.count or 5) do
        local bar = combo.pips[i].bar
        bar:SetValue(n)
        bar.glow:SetValue(n)
    end
    frame:Show()
end

-- an den Aufbau des Zielrahmens anhängen
local layout = ns.Layout
ns.Layout = function(b)
    layout(b)
    if b.key == "target" then
        local ok, err = pcall(LayoutCombo, b)
        if not ok then ns.ReportError(T("Kombopunkte", "Combo points"), err) end
    end
end

local function OnPower(unit, powerType)
    if unit == "player" and (powerType == nil or powerType == "COMBO_POINTS") then ns.UpdateCombo() end
end
ns.On("UNIT_POWER_UPDATE", T("Kombopunkte", "Combo points"), OnPower)
ns.On("UNIT_POWER_FREQUENT", T("Kombopunkte", "Combo points"), OnPower)
ns.On("UNIT_MAXPOWER", T("Kombopunkte", "Combo points"), function(unit)
    local b = ns.frames.target
    if unit == "player" and b and combo and MaxPoints() ~= combo.count then LayoutCombo(b) end
end)
ns.On("PLAYER_COMBO_POINTS", T("Kombopunkte", "Combo points"), function() ns.UpdateCombo() end)
ns.On("PLAYER_TARGET_CHANGED", T("Kombopunkte", "Combo points"), function() ns.UpdateCombo() end)
ns.On("UPDATE_SHAPESHIFT_FORM", T("Kombopunkte", "Combo points"), function() ns.UpdateCombo() end)
