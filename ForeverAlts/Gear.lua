-- ForeverAlts – Gear.lua: Charakterübersicht – die Ausrüstung eines (auch ausgeloggten) Charakters, angeordnet wie im
-- Charakterfenster: links Kopf bis Handgelenke, rechts Hände bis Schmuck, unten die Waffen. Gezeigt wird der Stand vom
-- letzten Login dieses Charakters (Data.lua, c.gear). Maus darüber: Gegenstands-Tooltip; Shift-Klick: im Chat
-- verlinken; Strg-Klick: anprobieren. Öffnet über den Knopf in der Zeile der Twink-Übersicht oder Klick auf die Zeile.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local SLOT = 38   -- Kantenlänge eines Platzes
local GAP = 5     -- Abstand zwischen den Plätzen
local PAD = 14
local TOP = 40    -- unter der Titelleiste
local MIDDLE = 176 -- Breite der Mitte (Name, Stufe, Gegenstandsstufe)

-- Plätze wie im Charakterfenster (Platznummer, Name für das leere Feld)
local LEFT = { { 1, "HeadSlot" }, { 2, "NeckSlot" }, { 3, "ShoulderSlot" }, { 15, "BackSlot" }, { 5, "ChestSlot" },
    { 4, "ShirtSlot" }, { 19, "TabardSlot" }, { 9, "WristSlot" } }
local RIGHT = { { 10, "HandsSlot" }, { 6, "WaistSlot" }, { 7, "LegsSlot" }, { 8, "FeetSlot" }, { 11, "Finger0Slot" },
    { 12, "Finger1Slot" }, { 13, "Trinket0Slot" }, { 14, "Trinket1Slot" } }
local BOTTOM = { { 16, "MainHandSlot" }, { 17, "SecondaryHandSlot" }, { 18, "RangedSlot" } }

local window, info, stamp, slots
local shownKey

-- Bild des leeren Platzes aus dem Spiel (nur der Pfad, nichts wird ausgelesen)
local function EmptyTexture(slotName)
    if not GetInventorySlotInfo then return nil end
    local ok, _, texture = pcall(GetInventorySlotInfo, slotName)
    return ok and texture or nil
end

local function QualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return C.accent[1], C.accent[2], C.accent[3]
end

local function CreateSlot(parent, slotID, slotName)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SLOT, SLOT)
    UI.SetFlat(b, C.input or C.button)
    b.slotID, b.empty = slotID, EmptyTexture(slotName)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-Klick verlinkt im Chat, Strg-Klick probiert an (Blizzards übliche Klicks für Gegenstände)
    b:SetScript("OnClick", function(self)
        if self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
    end)
    return b
end

local function Fill(b, item)
    b.link = item and item.link or nil
    if item then
        b.icon:SetTexture(item.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.link)))
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(1)
        local r, g, bl = QualityColor(item.quality)
        b:SetBackdropBorderColor(r, g, bl, 0.9)
    else
        b.icon:SetTexture(b.empty)
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(0.35)
        local border = C.border or { 0.3, 0.3, 0.3 }
        b:SetBackdropBorderColor(border[1], border[2], border[3], 0.6)
    end
end

local function Build()
    local width = PAD * 2 + SLOT * 2 + MIDDLE
    local height = TOP + #LEFT * (SLOT + GAP) - GAP + GAP * 3 + SLOT + 36
    window = UI.Window("ForeverAltsGearWindow", T("Charakterübersicht", "Character overview"), width, height)
    slots = {}
    for i, s in ipairs(LEFT) do
        local b = CreateSlot(window, s[1], s[2])
        b:SetPoint("TOPLEFT", PAD, -TOP - (i - 1) * (SLOT + GAP))
        slots[#slots + 1] = b
    end
    for i, s in ipairs(RIGHT) do
        local b = CreateSlot(window, s[1], s[2])
        b:SetPoint("TOPRIGHT", -PAD, -TOP - (i - 1) * (SLOT + GAP))
        slots[#slots + 1] = b
    end
    local bottomY = -TOP - #LEFT * (SLOT + GAP) - GAP * 2
    local bottomWidth = #BOTTOM * SLOT + (#BOTTOM - 1) * GAP
    for i, s in ipairs(BOTTOM) do
        local b = CreateSlot(window, s[1], s[2])
        b:SetPoint("TOPLEFT", window, "TOP", -bottomWidth / 2 + (i - 1) * (SLOT + GAP), bottomY)
        slots[#slots + 1] = b
    end

    -- Mitte: Name, Titel, Stufe/Volk/Klasse, Gegenstandsstufe
    info = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOP", window, "TOP", 0, -TOP - 6)
    info:SetWidth(MIDDLE - 12)
    info:SetJustifyH("CENTER")
    info:SetSpacing(4)
    -- unten: Stand der Daten
    stamp = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stamp:SetPoint("BOTTOM", 0, 12)
    stamp:SetTextColor(0.55, 0.55, 0.55)

    window:SetScript("OnHide", function() shownKey = nil end)
end

local function Ago(timestamp)
    if not timestamp then return "?" end
    local s = math.max(0, time() - timestamp)
    if s < 120 then return T("gerade eben", "just now") end
    if s < 7200 then return string.format(T("vor %d Min.", "%d min ago"), math.floor(s / 60)) end
    if s < 172800 then return string.format(T("vor %d Std.", "%d h ago"), math.floor(s / 3600)) end
    return string.format(T("vor %d Tagen", "%d days ago"), math.floor(s / 86400))
end

function ns.RefreshGear()
    if not window or not window:IsShown() or not shownKey then return end
    local c = ns.CharacterData(shownKey)
    if not c then window:Hide() return end
    local gear = c.gear or {}
    for _, b in ipairs(slots) do Fill(b, gear[b.slotID]) end
    local className = c.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class] or c.class or ""
    local lines = { ns.ColoredName(c) }
    if c.title then lines[#lines + 1] = "|cffd8c27a" .. c.title .. "|r" end
    lines[#lines + 1] = "|cffbbbbbb" .. string.format(T("Stufe %s %s %s", "Level %s %s %s"), c.level or "?", c.race or "",
        className) .. "|r"
    if c.ilvl then
        lines[#lines + 1] = string.format("|cff%02x%02x%02x%s|r", C.accent[1] * 255, C.accent[2] * 255, C.accent[3] * 255,
            string.format(T("Gegenstandsstufe %d", "Item level %d"), c.ilvl))
    end
    if c.realm then lines[#lines + 1] = "|cff6a6a6a" .. c.realm .. "|r" end
    info:SetText(table.concat(lines, "\n"))
    if not c.gear then
        stamp:SetText(T("Noch keine Ausrüstung bekannt – einmal mit diesem Charakter einloggen.",
            "No gear known yet – log in with this character once."))
    elseif shownKey == ns.CharKey() then
        stamp:SetText(T("Stand: jetzt", "As of: now"))
    else
        stamp:SetText(T("Stand: ", "As of: ") .. Ago(c.updated))
    end
end

-- Übersicht eines Charakters zeigen; derselbe Charakter nochmal = schließen. Neben dem Fenster "anchor" (falls offen).
function ns.ShowGear(key, anchor)
    if not key then return end
    if not window then Build() end
    if window:IsShown() and shownKey == key then
        window:Hide()
        return
    end
    shownKey = key
    if anchor and anchor:IsShown() and not window:IsShown() then
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    end
    window:Show()
    if UI.BringToFront then UI.BringToFront(window) end
    ns.RefreshGear()
end

function ns.IsGearShown(key) return window and window:IsShown() and shownKey == key end
