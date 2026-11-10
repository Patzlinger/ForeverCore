-- ForeverMarks (Prototyp, Modul von ForeverHelpers): Markierungs-Rad.
-- Ein Tastendruck (oder /fmarks) öffnet ein Rad mit den 8 Markierungen an der Maus; Klick auf ein Feld setzt sie.
--   Modus "Ziel":  Markierung auf die Einheit, über der die Maus beim Öffnen stand (sonst auf das aktuelle Ziel)
--   Modus "Boden": Bodenmarkierung dort, wo das Feld auf dem Bildschirm liegt (also dort öffnen, wo sie hin soll)
-- Mitte = Modus umschalten, unten = Markierung(en) entfernen. Taste festlegen: /fmarks key ALT-X (/fmarks key aus = keine).
-- Prototyp-Grenzen: Öffnen und Moduswechsel nur außerhalb des Kampfs (die Markierungs-Knöpfe sind geschützt).
-- Reihenfolge und Zuordnung Ziel-/Bodenmarkierung wie die unsichtbaren Markierungs-Knöpfe in ForeverBars.
local _, root = ...
local UI = ForeverHub.UI
local T = UI.T
local function Chat(text) UI.Chat("ForeverMarks", text) end

local MARKERS = { -- im Uhrzeigersinn ab oben: raid = Zielmarkierung 1–8, world = Bodenmarkierung
    { raid = 8, world = 8 }, { raid = 7, world = 4 }, { raid = 6, world = 1 }, { raid = 5, world = 7 },
    { raid = 4, world = 2 }, { raid = 3, world = 3 }, { raid = 2, world = 6 }, { raid = 1, world = 5 },
}
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RADIUS, BTN, CLOSE_DIST = 66, 32, 130
local GOLD = { 1, 0.82, 0 }

local function DB()
    if type(_G.ForeverHelpersDB) ~= "table" then _G.ForeverHelpersDB = {} end
    local db = _G.ForeverHelpersDB
    if type(db.marks) ~= "table" then db.marks = {} end
    return db.marks
end

---------------------------------------------------------------------------
-- Rad
---------------------------------------------------------------------------
local wheel = CreateFrame("Frame", "ForeverMarksWheel", UIParent)
wheel:SetSize(2 * (RADIUS + BTN), 2 * (RADIUS + BTN) + 40)
wheel:SetFrameStrata("DIALOG")
wheel:SetClampedToScreen(true)
wheel:Hide()
tinsert(UISpecialFrames, "ForeverMarksWheel") -- Esc schließt

local mode = "unit" -- "unit" | "ground"
local unitToken = "target"
local buttons = {}

local function Skin(b)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b:SetBackdropColor(0.06, 0.06, 0.07, 0.92)
    b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    b:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) end)
    b:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end)
end

local function NewButton(size)
    local b = CreateFrame("Button", nil, wheel, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(size, size)
    b:RegisterForClicks("LeftButtonUp")
    Skin(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b:HookScript("PostClick", function() C_Timer.After(0.05, function() wheel:Hide() end) end)
    return b
end

-- Beschriftung in der Mitte (Modus und Ziel)
local label = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("TOP", wheel, "BOTTOM", 0, 14)

-- Mitte: Modus umschalten (insecure, nur außerhalb des Kampfs wirksam)
local center = CreateFrame("Button", nil, wheel, "BackdropTemplate")
center:SetSize(44, 44)
center:SetPoint("CENTER", wheel, "CENTER", 0, 20)
Skin(center)
center.text = center:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
center.text:SetPoint("CENTER")

local function Apply()
    if InCombatLockdown() then return end
    for _, b in ipairs(buttons) do
        if b.marker then
            if mode == "unit" then
                b:SetAttribute("type", "raidtarget")
                b:SetAttribute("unit", unitToken)
                b:SetAttribute("marker", b.marker.raid)
            else
                b:SetAttribute("type", "worldmarker")
                b:SetAttribute("marker", b.marker.world)
            end
            b:SetAttribute("action", "toggle")
        elseif b.isClear then
            b:SetAttribute("type", mode == "unit" and "raidtarget" or "worldmarker")
            b:SetAttribute("unit", unitToken)
            b:SetAttribute("action", "clear")
        end
    end
    local name = UnitName(unitToken)
    if mode == "unit" then
        center.text:SetText(T("Ziel", "Unit"))
        label:SetText(string.format(T("Ziel: %s", "Unit: %s"), name or T("(keins)", "(none)")))
    else
        center.text:SetText(T("Boden", "Ground"))
        label:SetText(T("Boden: an der Stelle des Feldes", "Ground: at the spot of the slot"))
    end
    center.text:SetTextColor(mode == "unit" and 1 or GOLD[1], mode == "unit" and 1 or GOLD[2], mode == "unit" and 1 or GOLD[3])
end

center:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    mode = mode == "unit" and "ground" or "unit"
    DB().mode = mode
    Apply()
end)

for i, m in ipairs(MARKERS) do
    local b = NewButton(BTN)
    local angle = math.rad(90 - (i - 1) * 45) -- 1 = oben, im Uhrzeigersinn
    b:SetPoint("CENTER", wheel, "CENTER", RADIUS * math.cos(angle), RADIUS * math.sin(angle) + 20)
    b.icon:SetTexture(ICON .. m.raid)
    b.marker = m
    buttons[#buttons + 1] = b
end

local clear = NewButton(22)
clear:SetPoint("TOP", wheel, "BOTTOM", 0, -2)
clear.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
clear.isClear = true
buttons[#buttons + 1] = clear
label:ClearAllPoints()
label:SetPoint("TOP", clear, "BOTTOM", 0, -3)

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
    mode = DB().mode == "ground" and "ground" or "unit"
    Apply()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s - 20)
    wheel:Show()
end

-- schließt, wenn die Maus weit vom Rad wegwandert
wheel:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local s = self:GetEffectiveScale()
    local cx, cy = self:GetCenter()
    if cx and math.sqrt((x / s - cx) ^ 2 + (y / s - cy - 20) ^ 2) > CLOSE_DIST then self:Hide() end
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
