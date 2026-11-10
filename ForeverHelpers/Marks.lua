-- ForeverMarks (Prototyp, Modul von ForeverHelpers): Markierungs-Rad.
-- /fmarks (oder eine Taste) öffnet ein Rad mit den 8 Markierungen an der Maus. Wie beim Ping-Rad zählt die RICHTUNG:
-- die Maus zeigt in ein Tortenstück, dieses leuchtet auf (Zeiger + großes Symbol), ein Linksklick setzt es.
--   Modus "Ziel":  Markierung auf die Einheit, über der die Maus beim Öffnen stand (sonst auf das aktuelle Ziel)
--   Modus "Boden": Bodenmarkierung an der Mausposition beim Klick (das Rad also dort öffnen, wo sie hin soll)
-- Klick in die Mitte = Modus umschalten, Knopf unten = Markierung(en) entfernen. Taste: /fmarks key ALT-X (key aus = keine).
-- Prototyp-Grenzen: Öffnen und Moduswechsel nur außerhalb des Kampfs (die Markierungs-Aktion ist ein geschützter Knopf).
-- Reihenfolge und Zuordnung Ziel-/Bodenmarkierung wie die unsichtbaren Markierungs-Knöpfe in ForeverBars.
local UI = ForeverHub.UI
local T = UI.T
local function Chat(text) UI.Chat("ForeverMarks", text) end

local MARKERS = { -- im Uhrzeigersinn ab oben: raid = Zielmarkierung 1–8, world = Bodenmarkierung
    { raid = 8, world = 8 }, { raid = 7, world = 4 }, { raid = 6, world = 1 }, { raid = 5, world = 7 },
    { raid = 4, world = 2 }, { raid = 3, world = 3 }, { raid = 2, world = 6 }, { raid = 1, world = 5 },
}
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RING, ICON_SIZE, ICON_BIG = 70, 34, 44
local INNER, OUTER = 24, 120 -- Mitte (Moduswechsel) bis Außenrand der Tortenstücke
local CLOSE_DIST = 190
local GOLD = { 1, 0.82, 0 }

local function DB()
    if type(_G.ForeverHelpersDB) ~= "table" then _G.ForeverHelpersDB = {} end
    local db = _G.ForeverHelpersDB
    if type(db.marks) ~= "table" then db.marks = {} end
    return db.marks
end

---------------------------------------------------------------------------
-- Rad (Anzeige)
---------------------------------------------------------------------------
local wheel = CreateFrame("Frame", "ForeverMarksWheel", UIParent)
wheel:SetSize(2 * OUTER, 2 * OUTER)
wheel:SetFrameStrata("DIALOG")
wheel:SetClampedToScreen(true)
wheel:Hide()
tinsert(UISpecialFrames, "ForeverMarksWheel") -- Esc schließt

local mode = "unit" -- "unit" | "ground"
local unitToken = "target"
local hoverIndex -- Tortenstück unter der Mausrichtung (1–8) oder nil (Mitte / außerhalb)
local slots = {}

local function Skin(f, size)
    f:SetSize(size, size)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
    f:SetBackdropColor(0.06, 0.06, 0.07, 0.92)
end

-- Ring-Hintergrund (rund wirkt das Rad dadurch geordneter)
local disc = wheel:CreateTexture(nil, "BACKGROUND")
disc:SetSize(2 * (RING + 30), 2 * (RING + 30))
disc:SetPoint("CENTER")
disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
disc:SetVertexColor(0, 0, 0, 0.45)

-- Zeiger: kurzer Strich vom Zentrum in Richtung des gewählten Tortenstücks
local pointer = wheel:CreateTexture(nil, "ARTWORK")
pointer:SetTexture(WHITE)
pointer:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
pointer:Hide()

local function SlotAngle(i) return math.rad(90 - (i - 1) * 45) end

local function RefreshSlot(s)
    local r, g, b = 0.3, 0.3, 0.3
    local size = ICON_SIZE
    if s.flash then r, g, b = 0.2, 1, 0.3 size = ICON_BIG
    elseif s.hover then r, g, b = 1, 1, 1 size = ICON_BIG
    elseif s.active then r, g, b = GOLD[1], GOLD[2], GOLD[3] end
    s:SetBackdropBorderColor(r, g, b, 1)
    s:SetSize(size, size)
    s:SetFrameLevel(wheel:GetFrameLevel() + (s.hover and 5 or 2))
end

for i, m in ipairs(MARKERS) do
    local s = CreateFrame("Frame", nil, wheel, "BackdropTemplate")
    Skin(s, ICON_SIZE)
    s:EnableMouse(false) -- Klicks gehen an die Fläche darunter
    local a = SlotAngle(i)
    s:SetPoint("CENTER", wheel, "CENTER", RING * math.cos(a), RING * math.sin(a))
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 3, -3)
    s.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    s.icon:SetTexture(ICON .. m.raid)
    s.marker = m
    slots[i] = s
end

-- Mitte: zeigt den Modus (Klick = umschalten)
local center = CreateFrame("Frame", nil, wheel, "BackdropTemplate")
Skin(center, 2 * INNER)
center:SetPoint("CENTER")
center:EnableMouse(false)
center:SetFrameLevel(wheel:GetFrameLevel() + 1)
center.text = center:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
center.text:SetPoint("CENTER")

-- Beschriftung unter dem Rad
local label = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

---------------------------------------------------------------------------
-- Welche Markierung steht gerade? (für die goldene Umrandung)
---------------------------------------------------------------------------
local function MarkActive(m)
    if mode == "unit" then
        local ok, idx = pcall(GetRaidTargetIndex, unitToken)
        return ok and idx == m.raid
    end
    if IsRaidMarkerActive then
        local ok, on = pcall(IsRaidMarkerActive, m.world)
        return ok and on and true or false
    end
    return false
end

local function RefreshAll()
    for _, s in ipairs(slots) do
        s.active = MarkActive(s.marker)
        RefreshSlot(s)
    end
end

local function UpdateLabel()
    local name = UnitName(unitToken)
    local head
    if mode == "unit" then
        head = string.format(T("Ziel: %s", "Unit: %s"), name or T("(keins)", "(none)"))
    else
        head = T("Boden: an der Mausposition", "Ground: at the mouse position")
    end
    if hoverIndex then
        local raid = MARKERS[hoverIndex].raid
        head = head .. "\n|cffffd100" .. (_G["RAID_TARGET_" .. raid] or ("#" .. raid)) .. "|r"
    end
    label:SetText(head)
end

local function SetMode(newMode)
    mode = newMode
    center.text:SetText(mode == "unit" and T("Ziel", "Unit") or T("Boden", "Ground"))
    if mode == "unit" then center.text:SetTextColor(1, 1, 1) else center.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    RefreshAll()
    UpdateLabel()
end

---------------------------------------------------------------------------
-- Auswahl: Tortenstück aus der Mausrichtung
---------------------------------------------------------------------------
local function CursorOffset()
    local x, y = GetCursorPosition()
    local s = wheel:GetEffectiveScale()
    local cx, cy = wheel:GetCenter()
    if not cx then return 0, 0 end
    return x / s - cx, y / s - cy
end

-- 1 = oben, im Uhrzeigersinn; nil = Mitte
local function SectorAt(dx, dy)
    if math.sqrt(dx * dx + dy * dy) < INNER then return nil end
    local deg = math.deg(math.atan2(dy, dx))
    return math.floor(((90 - deg) % 360 + 22.5) / 45) % 8 + 1
end

local function SetHover(i)
    if i == hoverIndex then return end
    hoverIndex = i
    for idx, s in ipairs(slots) do
        s.hover = idx == i or nil
        RefreshSlot(s)
    end
    if i then
        local a = SlotAngle(i)
        local mid = (INNER + 6 + ICON_BIG / 2 + 4) -- Strich zwischen Mitte und Symbol
        local len = RING - ICON_BIG / 2 - INNER - 8
        pointer:ClearAllPoints()
        pointer:SetSize(math.max(len, 6), 4)
        pointer:SetPoint("CENTER", wheel, "CENTER", (INNER + 4 + len / 2) * math.cos(a), (INNER + 4 + len / 2) * math.sin(a))
        pointer:SetRotation(a)
        pointer:Show()
    else
        pointer:Hide()
    end
    UpdateLabel()
end

-- Klick-Fläche: ein geschützter Knopf über dem ganzen Rad. Vor dem Klick (PreClick) wird eingestellt, was er tut –
-- je nach Richtung der Maus. In der Mitte tut er nichts (dort wird nur der Modus umgeschaltet).
local catcher = CreateFrame("Button", "ForeverMarksCatcher", wheel, "SecureActionButtonTemplate")
catcher:SetAllPoints(wheel)
catcher:SetFrameLevel(wheel:GetFrameLevel() + 1)
-- Auf- UND Abwärts: je nach Spiel-Einstellung "bei Tastendruck auslösen" reagiert der geschützte Knopf nur auf eine
-- der beiden Hälften
catcher:RegisterForClicks("AnyUp", "AnyDown")

local function Configure(sector)
    if InCombatLockdown() then return end
    if not sector then
        catcher:SetAttribute("type", nil)
        return
    end
    local m = MARKERS[sector]
    if mode == "unit" then
        catcher:SetAttribute("type", "raidtarget")
        catcher:SetAttribute("unit", unitToken)
        catcher:SetAttribute("marker", m.raid)
    else
        catcher:SetAttribute("type", "worldmarker")
        catcher:SetAttribute("marker", m.world)
    end
    catcher:SetAttribute("action", "toggle") -- gleiche Markierung noch einmal = entfernen
end

catcher:SetScript("PreClick", function() Configure(SectorAt(CursorOffset())) end)

-- einmal je Klick (OnMouseUp kommt genau einmal): Rückmeldung und Schließen
catcher:SetScript("OnMouseUp", function(_, button)
    if button ~= "LeftButton" then return end
    local sector = SectorAt(CursorOffset())
    if not sector then -- Mitte: Modus wechseln
        if not InCombatLockdown() then
            SetMode(mode == "unit" and "ground" or "unit")
            DB().mode = mode
        end
        return
    end
    local s = slots[sector]
    s.flash = true
    RefreshSlot(s)
    label:SetText(string.format(T("|cff33ff4dGesetzt:|r %s", "|cff33ff4dSent:|r %s"),
        _G["RAID_TARGET_" .. s.marker.raid] or ("#" .. s.marker.raid)))
    C_Timer.After(0.4, function()
        s.flash = nil
        wheel:Hide()
    end)
end)

-- Rechtsklick auf die Fläche schließt
catcher:HookScript("OnClick", function(_, button, down)
    if button == "RightButton" and not down then wheel:Hide() end
end)

-- Unten: Markierung(en) entfernen
local clear = CreateFrame("Button", "ForeverMarksClear", wheel, "SecureActionButtonTemplate,BackdropTemplate")
Skin(clear, 24)
clear:SetPoint("TOP", wheel, "BOTTOM", 0, 2)
clear:RegisterForClicks("AnyUp", "AnyDown")
clear.icon = clear:CreateTexture(nil, "ARTWORK")
clear.icon:SetPoint("TOPLEFT", 3, -3)
clear.icon:SetPoint("BOTTOMRIGHT", -3, 3)
clear.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
clear:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
clear:HookScript("OnEnter", function(self)
    self:SetBackdropBorderColor(1, 1, 1, 1)
    SetHover(nil)
    label:SetText(T("Entfernen", "Clear"))
end)
clear:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) UpdateLabel() end)
clear:HookScript("OnMouseUp", function(self)
    self:SetBackdropBorderColor(0.2, 1, 0.3, 1)
    label:SetText(T("|cff33ff4dEntfernt.|r", "|cff33ff4dCleared.|r"))
    C_Timer.After(0.4, function() wheel:Hide() end)
end)

label:SetPoint("TOP", clear, "BOTTOM", 0, -4)

---------------------------------------------------------------------------
-- Einheit unter der Maus beim Öffnen finden (Token zu GUID)
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function Guid(token)
    local ok, g = pcall(UnitGUID, token)
    if ok and g and not issecret(g) then return g end
end

local function TokenFor(guid)
    local list = { "target", "focus", "player", "pet", "targettarget" }
    for i = 1, 4 do list[#list + 1] = "party" .. i; list[#list + 1] = "party" .. i .. "target" end
    for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
    for _, t in ipairs(list) do
        if Guid(t) == guid then return t end
    end
end

local function Open()
    if InCombatLockdown() then
        Chat(T("Im Kampf nicht möglich (Prototyp).", "Not possible in combat (prototype)."))
        return
    end
    unitToken = "target"
    local g = UnitExists("mouseover") and Guid("mouseover")
    if g then unitToken = TokenFor(g) or "target" end
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    hoverIndex = nil
    pointer:Hide()
    for _, slot in ipairs(slots) do slot.hover, slot.flash = nil, nil end
    SetMode(DB().mode == "ground" and "ground" or "unit")
    wheel:Show()
end

-- Richtung der Maus verfolgen; schließt, wenn die Maus weit vom Rad wegwandert
wheel:SetScript("OnUpdate", function(self)
    local dx, dy = CursorOffset()
    if math.sqrt(dx * dx + dy * dy) > CLOSE_DIST then self:Hide() return end
    if dy < -(OUTER + 4) then return end -- Knopf "Entfernen" unten: Hervorhebung bleibt aus
    SetHover(SectorAt(dx, dy))
end)

---------------------------------------------------------------------------
-- Taste und Befehl
---------------------------------------------------------------------------
local opener = CreateFrame("Button", "ForeverMarksOpen", UIParent)
opener:SetScript("OnClick", function()
    if wheel:IsShown() then wheel:Hide() else Open() end
end)

local boundKey
local function ApplyKey()
    if InCombatLockdown() then return false end
    if boundKey then ClearOverrideBindings(opener) boundKey = nil end
    local key = DB().key
    if key and key ~= "" then
        if SetOverrideBindingClick(opener, false, key, "ForeverMarksOpen") ~= false then boundKey = key end
    end
    return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function() ApplyKey() end)

SLASH_FOREVERMARKS1 = "/fmarks"
SlashCmdList["FOREVERMARKS"] = function(msg)
    msg = strtrim(msg or "")
    local key = msg:match("^key%s+(.+)$")
    if key then
        key = key:upper()
        DB().key = (key == "AUS" or key == "OFF") and nil or key
        if ApplyKey() then
            Chat(DB().key and string.format(T("Taste: %s", "Key: %s"), DB().key) or T("Taste entfernt.", "Key removed."))
        else
            Chat(T("Im Kampf nicht möglich – nach dem Kampf wird die Taste gesetzt.", "Not possible in combat – the key is set after combat."))
        end
    elseif msg == "" then
        if wheel:IsShown() then wheel:Hide() else Open() end
    else
        Chat(T("/fmarks – Rad öffnen · /fmarks key ALT-X – Taste festlegen · /fmarks key aus", "/fmarks – open wheel · /fmarks key ALT-X – set key · /fmarks key off"))
    end
end
