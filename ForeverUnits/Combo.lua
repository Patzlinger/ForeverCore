-- ForeverUnits – Combo.lua: Kombopunkte am Zielrahmen (Schurken, Druiden in Katzengestalt).
-- Drei Orte zur Wahl: "PORTRAIT" = senkrechte Spalte direkt neben dem Porträt (Standard), "BELOW" = Balken mit
-- 5 Strichen unter dem Rahmen, "ABOVE" = Punkte über dem Rahmen. Jeder Punkt ist ein kleiner Balken
-- (Bereich i-1 bis i), so zeigt er auch gesperrte Werte ("secret values") richtig an, ohne zu rechnen.
local ADDON_NAME, ns = ...
local T, GetDB, IsSecret = ns.T, ns.GetDB, ns.IsSecret
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAX_PIPS = 10
local GAP = 2

local combo -- { frame, pips = { {bar, bg, edge} } }

local _, playerClass = UnitClass("player")
local COMBO_POWER = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4

-- Farbe je Punkt: von Gold (erster) zu Orangerot (letzter)
local function PipColor(i, count)
    local t = count > 1 and (i - 1) / (count - 1) or 1
    return 1, 0.82 - 0.5 * t, 0.2 - 0.1 * t
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
        local bar = CreateFrame("StatusBar", nil, f)
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
    if b.key ~= "target" or not d.comboShow or d.comboPoint ~= where then return 0 end
    if not (playerClass == "ROGUE" or playerClass == "DRUID") then return 0 end
    if where == "BELOW" then return (d.comboSize or 8) + 3 end
    if where == "ABOVE" then return (d.comboSize or 8) + 4 + 10 end
    return 0
end

local function LayoutCombo(b)
    local d, fdb = GetDB(), ns.FrameDB("target")
    if not (d.comboShow and (playerClass == "ROGUE" or playerClass == "DRUID")) then
        if combo then combo.frame:Hide() end
        return
    end
    local c = Build(b)
    local v = b.v
    local size = d.comboSize or 8
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
        -- senkrechte Spalte direkt neben dem Porträt (auf der Seite des Lebensbalkens); ohne Porträt an der Außenkante
        vertical = true
        local h = fdb.height - 4
        pipW, pipH = size, (h - (count - 1) * GAP) / count
        frame:SetSize(size, h)
        local hasPortrait = fdb.portrait ~= "none"
        local inset = size + 6 -- so weit rücken die Texte auf dieser Seite des Lebensbalkens ein
        if fdb.portraitSide == "RIGHT" then
            if hasPortrait then
                frame:SetPoint("RIGHT", v.portrait, "LEFT", -3, 0)
                -- Name (zweizeilig) bzw. Lebenspunkte (einzeilig) enden vor der Spalte
                if v.name:GetNumPoints() > 0 then
                    local stacked = fdb.textLayout ~= "inline"
                    if stacked then
                        v.name:SetPoint("RIGHT", v.health, "RIGHT", -inset, 0)
                    else
                        v.hp:ClearAllPoints()
                        v.hp:SetPoint("RIGHT", v.health, "RIGHT", -inset, 0)
                    end
                end
            else
                frame:SetPoint("LEFT", v.content, "RIGHT", 3, 0)
            end
        else
            if hasPortrait then
                frame:SetPoint("LEFT", v.portrait, "RIGHT", 3, 0)
                -- Stufe/Name und Lebenspunkte beginnen hinter der Spalte
                for _, fs in ipairs({ v.level, v.name, v.hp }) do
                    local point, rel, relPoint, x, y = fs:GetPoint(1)
                    if point and rel == v.health and x and x < inset then
                        fs:SetPoint(point, rel, relPoint, inset, y)
                    end
                end
            else
                frame:SetPoint("RIGHT", v.content, "LEFT", -3, 0)
            end
        end
    end
    for i, p in ipairs(c.pips) do
        local bar = p.bar
        bar:ClearAllPoints()
        if i <= count then
            bar:SetSize(pipW, pipH)
            if vertical then
                -- von unten nach oben füllen
                bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, (i - 1) * (pipH + GAP))
            elseif round then
                bar:SetPoint("LEFT", frame, "LEFT", (i - 1) * (pipW + GAP + 1), 0)
            else
                bar:SetPoint("LEFT", frame, "LEFT", (i - 1) * (pipW + GAP), 0)
            end
            bar:SetStatusBarTexture(round and ROUND or WHITE)
            bar:SetStatusBarColor(PipColor(i, count))
            p.bg:SetTexture(round and ROUND or WHITE)
            p.bg:SetVertexColor(0.08, 0.08, 0.08, 0.85)
            p.edge:SetTexture(round and ROUND or WHITE)
            p.edge:SetVertexColor(0, 0, 0, 0.9)
            bar:Show()
        else
            bar:Hide()
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
    for i = 1, (combo.count or 5) do combo.pips[i].bar:SetValue(n) end
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
