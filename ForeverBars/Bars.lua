local addonName, ns = ...
local L = ns.L

-- Aktionsleisten: ForeverBars nimmt die originalen Blizzard-Knöpfe und ordnet sie in eigenen Leisten an.
-- So erledigt das Spiel weiterhin Seitenwechsel, Abklingzeiten, Reichweite und Tastenbelegungen.
-- Wichtig: Aktionsknöpfe sind geschützt - Anordnung, Größe und Position nur außerhalb des Kampfes ändern.

local ACTION_SIZE = 36   -- Kantenlänge der Aktionsknöpfe
local SMALL_SIZE = 30    -- Begleiter- und Haltungsknöpfe
local GRID_REASON = 2048 -- eigene Kennung für "leere Plätze zeigen"
local MOVER_COLOR = { 1, 0.82, 0 }

local holders = {}   -- [Leiste] = Halter-Fenster, in dem die Knöpfe liegen
local movers = {}    -- [Leiste] = Griff zum Verschieben (nur entsperrt sichtbar)
local layoutPending, layoutQueued = false, false

-- Unsichtbarer Ablageort für ausgeblendete Blizzard-Leisten und nicht genutzte Knöpfe
local hiddenParent = CreateFrame("Frame", "ForeverBarsHidden", UIParent)
hiddenParent:Hide()

local function GetDef(key)
    for _, def in ipairs(ns.BAR_DEFS) do
        if def.key == key then return def end
    end
end
ns.GetBarDef = GetDef

local function FindFrame(names)
    for _, name in ipairs(names or {}) do
        if _G[name] then return _G[name] end
    end
end

-- Alle Knöpfe einer Leiste (bei Taschen: alle vorhandenen Taschenknöpfe inkl. Schlüsselbund)
local function GetAllButtons(def)
    local list = {}
    if def.buttons then
        for i = 1, def.count do
            local button = _G[def.buttons .. i]
            if button then table.insert(list, button) end
        end
    elseif def.bagButtons then
        for _, name in ipairs(def.bagButtons) do
            if _G[name] then table.insert(list, _G[name]) end
        end
        if KeyRingButton then table.insert(list, KeyRingButton) end
    end
    return list
end

-- Die Knöpfe, die gerade angezeigt werden sollen (bei Taschen: "nur Rucksack" und "Schlüsselbund" beachten)
local function GetButtons(def, cfg)
    if not def.bagButtons then return GetAllButtons(def) end
    cfg = cfg or ns.db.bars[def.key]
    local list = {}
    for i, name in ipairs(def.bagButtons) do
        if _G[name] and (i == 1 or not cfg.onlyBackpack) then table.insert(list, _G[name]) end
    end
    if cfg.keyring and KeyRingButton then table.insert(list, KeyRingButton) end
    return list
end

-- Höchstzahl der Knöpfe einer Leiste (für das Menü)
function ns.GetMaxButtons(key)
    local def = GetDef(key)
    if not def then return 0 end
    if def.bagButtons then return #GetButtons(def) end
    return def.count or 0
end

-- Gibt es den Schlüsselbund in diesem Spiel?
function ns.HasKeyring()
    return KeyRingButton ~= nil
end

---------------------------------------------------------------------------
-- Standardpositionen (Mitte der Leiste, gemessen von unten links)
---------------------------------------------------------------------------

local function DefaultPosition(key)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local step = ACTION_SIZE + 8
    local base = 46 -- unterste Aktionsleiste; darunter Erfahrungs- und Rufleiste
    local positions = {
        bar1 = { width / 2, base }, bar2 = { width / 2, base + step }, bar3 = { width / 2, base + step * 2 },
        bar6 = { width / 2, base + step * 3 }, bar7 = { width / 2, base + step * 4 }, bar8 = { width / 2, base + step * 5 },
        bar4 = { width - 30, height / 2 }, bar5 = { width - 30 - step, height / 2 },
        pet = { width / 2 - 140, base + step * 3 }, stance = { width / 2 + 140, base + step * 3 },
        micro = { width - 170, 22 }, bags = { width - 110, 62 }, vehicle = { width / 2 - 300, base + 20 },
        xp = { width / 2, 8 }, rep = { width / 2, 20 }, queue = { width - 290, 120 },
    }
    local position = positions[key] or { width / 2, height / 2 }
    return position[1], position[2]
end

ns.DefaultPosition = DefaultPosition

function ns.GetBarPosition(key)
    local cfg = ns.db.bars[key]
    if not cfg.x or not cfg.y then
        cfg.x, cfg.y = DefaultPosition(key)
        cfg.x, cfg.y = math.floor(cfg.x + 0.5), math.floor(cfg.y + 0.5)
    end
    return cfg.x, cfg.y
end

---------------------------------------------------------------------------
-- Aussehen der Knöpfe im Forever-Stil: flach, dünner Rand, eckiges Symbol
---------------------------------------------------------------------------

local function HideRegion(region)
    if region and region.SetAlpha then region:SetAlpha(0) end
end

local function GetFontPath()
    for _, font in ipairs(ns.FONTS) do
        if font.key == ns.db.font then return font.path end
    end
    return STANDARD_TEXT_FONT
end

-- Schrift setzen; fehlt die Schriftdatei, auf die Standardschrift zurückfallen
local function SetTextFont(text, size)
    local flags = ns.db.fontOutline ~= "NONE" and ns.db.fontOutline or ""
    if not text:SetFont(GetFontPath(), size, flags) then
        text:SetFont(STANDARD_TEXT_FONT, size, flags)
    end
end

-- Position der Tastenbelegung auf dem Knopf
local HOTKEY_POSITIONS = {
    TOPRIGHT = { "TOPRIGHT", -2, -3, "RIGHT" },
    TOPLEFT = { "TOPLEFT", 3, -3, "LEFT" },
    TOP = { "TOP", 0, -3, "CENTER" },
}

-- Texte (Tastenbelegung, Makroname, Anzahl), Schrift, Rand und Symbol-Zuschnitt eines Knopfes
local function UpdateButtonLook(button)
    local name = button:GetName()
    local db = ns.db
    local hotkey = button.HotKey or (name and _G[name .. "HotKey"])
    local macro = button.Name or (name and _G[name .. "Name"])
    local count = button.Count or (name and _G[name .. "Count"])
    if hotkey then
        hotkey:SetAlpha(db.showHotkeys and 1 or 0)
        SetTextFont(hotkey, db.fontSize)
        local position = HOTKEY_POSITIONS[db.hotkeyPosition] or HOTKEY_POSITIONS.TOPRIGHT
        hotkey:ClearAllPoints()
        hotkey:SetPoint(position[1], button, position[1], position[2], position[3])
        hotkey:SetJustifyH(position[4])
    end
    if macro then
        macro:SetAlpha(db.showMacroNames and 1 or 0)
        SetTextFont(macro, math.max(8, db.fontSize - 2))
    end
    if count then
        count:SetAlpha(db.showCounts and 1 or 0)
        SetTextFont(count, db.fontSize)
    end

    -- Zauber-Effekt auf dem Knopf (kleine Zauberleiste beim Zaubern), falls das Spiel ihn hat
    for _, effect in ipairs({ button.SpellCastAnimFrame, button.InterruptDisplay }) do
        if effect and effect.SetAlpha then effect:SetAlpha(db.castVFX and 1 or 0) end
    end

    -- Rand, grüner "Ausgerüstet"-Rand, Zuschnitt des Symbols
    if button.fbBorder then button.fbBorder:SetShown(db.showBorder) end
    if button.Border then button.Border:SetAlpha(db.showEquipped and 1 or 0) end
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    if icon then
        local crop = math.max(0, math.min(30, db.iconZoom or 8)) / 100
        icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
    end
end

local function StyleButton(button)
    local name = button:GetName()
    -- Blizzard-Rahmen und Hintergrund-Grafiken ausblenden
    HideRegion(button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture()))
    HideRegion(button.SlotArt)
    HideRegion(button.SlotBackground)
    HideRegion(button.FloatingBG)
    HideRegion(button.RightDivider)
    HideRegion(button.BottomDivider)
    HideRegion(name and _G[name .. "FloatingBG"])

    -- Symbol eckig und randlos zuschneiden
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    if icon then
        if button.IconMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
    end

    if not button.fbBorder then
        -- Dunkler Hintergrund für leere Plätze und dünner grauer Rand wie in ForeverQuests
        local background = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        background:SetAllPoints()
        background:SetColorTexture(0.06, 0.06, 0.08, 0.85)
        button.fbBackground = background

        local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        border:SetAllPoints()
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        border:SetBackdropBorderColor(unpack(ns.Style.COLOR.border))
        border:SetFrameLevel(button:GetFrameLevel() + 1)
        border:EnableMouse(false)
        button.fbBorder = border

        -- Blizzard setzt seine Grafiken bei manchen Aktualisierungen neu: danach wieder ausblenden
        if button.UpdateButtonArt then
            hooksecurefunc(button, "UpdateButtonArt", function(self)
                HideRegion(self.NormalTexture)
                HideRegion(self.SlotArt)
                HideRegion(self.SlotBackground)
            end)
        end
        if button.UpdateHotkeys then
            hooksecurefunc(button, "UpdateHotkeys", UpdateButtonLook)
        end
        -- Tooltip des Knopfes nach Einstellung wieder ausblenden (nie bzw. nicht im Kampf)
        button:HookScript("OnEnter", function()
            local mode = ns.db.buttonTooltip
            if mode == "NEVER" or (mode == "NOCOMBAT" and InCombatLockdown()) then
                GameTooltip:Hide()
            end
        end)
    end
    UpdateButtonLook(button)

    -- Leere Plätze zeigen oder verstecken (nur außerhalb des Kampfes erlaubt)
    if button.SetShowGrid and not InCombatLockdown() then
        pcall(button.SetShowGrid, button, ns.db.showGrid, GRID_REASON)
    end
end

-- Nach Änderung von Texten, Schrift, Rand oder Zoom alle Knöpfe aktualisieren (geht auch im Kampf)
function ns.UpdateAllButtons()
    for _, def in ipairs(ns.BAR_DEFS) do
        for _, button in ipairs(GetAllButtons(def)) do
            if button.fbBorder then UpdateButtonLook(button) end
        end
    end
end
ns.UpdateAllButtonTexts = ns.UpdateAllButtons

---------------------------------------------------------------------------
-- Blizzard-Leisten ausblenden (ihre Knöpfe liegen dann in den eigenen Leisten)
---------------------------------------------------------------------------

local function HideBlizzardBars(def)
    for _, name in ipairs(def.blizzard or {}) do
        local frame = _G[name]
        if frame and not frame.fbHidden then
            frame.fbHidden = true
            frame:SetParent(hiddenParent)
            -- Ordnet Blizzard die Knöpfe neu an (z. B. Bearbeitungsmodus, neue Tasche), danach wieder eigene Anordnung
            for _, method in ipairs({ "UpdateGridLayout", "Layout" }) do
                if frame[method] then
                    hooksecurefunc(frame, method, function() ns.RequestLayout() end)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Anordnung
---------------------------------------------------------------------------

local function GetHolder(def)
    local holder = holders[def.key]
    if holder then return holder end
    -- Geschützter Halter, damit die Sichtbarkeit (z. B. nur im Kampf) auch im Kampf umschalten kann
    holder = CreateFrame("Frame", "ForeverBars_" .. def.key, UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(ACTION_SIZE, ACTION_SIZE)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder.def = def
    holders[def.key] = holder
    return holder
end

-- Knöpfe in Reihen anordnen. Wachstumsrichtung: von links nach rechts bzw. rechts nach links,
-- von oben nach unten bzw. unten nach oben (der erste Knopf sitzt in der Ecke, von der aus es wächst).
local function LayoutButtons(def, cfg, holder)
    local buttons = GetButtons(def, cfg)
    local size = def.kind == "action" and ACTION_SIZE or SMALL_SIZE
    local wanted = def.bagButtons and #buttons or (cfg.buttons or def.count)
    local count = math.max(1, math.min(wanted, #buttons))
    local perRow = math.max(1, math.min(cfg.perRow or count, count))
    local gap = cfg.spacing or 4
    local toLeft, toTop = cfg.growX == "LEFT", cfg.growY == "UP"
    local corner = (toTop and "BOTTOM" or "TOP") .. (toLeft and "RIGHT" or "LEFT")
    local shown = {}
    for i, button in ipairs(buttons) do
        if i <= count then
            shown[button] = true
            button:SetParent(holder)
            button:SetSize(size, size)
            button:ClearAllPoints()
            local column, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            button:SetPoint(corner, holder, corner,
                column * (size + gap) * (toLeft and -1 or 1), row * (size + gap) * (toTop and 1 or -1))
            -- Ausklapp-Richtung von Zauber-Gruppen (z. B. Portale); nur Aktionsknöpfe
            if def.kind == "action" then
                button:SetAttribute("flyoutDirection", cfg.flyout or "UP")
                if button.UpdateFlyout then pcall(button.UpdateFlyout, button) end
            end
        end
        StyleButton(button)
    end
    -- Nicht genutzte Knöpfe (zu viele bzw. ausgeschlossene Taschen) ablegen
    for _, button in ipairs(GetAllButtons(def)) do
        if not shown[button] then button:SetParent(hiddenParent) end
    end
    local rows = math.ceil(count / perRow)
    holder:SetSize(math.max(1, perRow * size + (perRow - 1) * gap), math.max(1, rows * size + (rows - 1) * gap))
end

-- Ganze Blizzard-Leiste (Menü, Taschen) bzw. einzelner Knopf (Fahrzeug verlassen) in den Halter setzen
local function LayoutContainer(def, cfg, holder)
    local frame = FindFrame(def.frames)
    if not frame then
        holder:SetSize(1, 1)
        return
    end
    frame.fbHolder = holder
    if frame:GetParent() ~= holder then frame:SetParent(holder) end
    frame.fbPositioning = true
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", holder, "CENTER")
    frame.fbPositioning = false
    if not frame.fbHooked then
        frame.fbHooked = true
        -- Verschiebt Blizzard die Leiste (z. B. Bearbeitungsmodus), zurück in den Halter
        local function BackToHolder(self)
            if self.fbPositioning or not self.fbHolder or InCombatLockdown() then return end
            self.fbPositioning = true
            if self:GetParent() ~= self.fbHolder then self:SetParent(self.fbHolder) end
            self:ClearAllPoints()
            self:SetPoint("CENTER", self.fbHolder, "CENTER")
            self.fbPositioning = false
        end
        hooksecurefunc(frame, "SetPoint", BackToHolder)
        -- Eigene Positionier-Funktionen von Blizzard (z. B. beim Warteschlangen-Auge)
        for _, method in ipairs(def.hookMethods or {}) do
            if frame[method] then hooksecurefunc(frame, method, BackToHolder) end
        end
    end
    -- Mindestgröße, damit der Halter auch dann Platz hat, wenn Blizzard das Element gerade ausblendet
    local minSize = def.minSize or 1
    holder:SetSize(math.max(minSize, frame:GetWidth()), math.max(minSize, frame:GetHeight()))
end

-- Sichtbarkeit als Blizzard-Bedingung (wird vom Spiel auch im Kampf umgeschaltet)
---------------------------------------------------------------------------
-- Seitenwechsel (nur Aktionsleisten). Eine "Seite" ist eine andere Belegung derselben 12 Knöpfe.
-- Läuft über die geschützte Blizzard-Technik (Zustandstreiber), damit er auch im Kampf funktioniert.
---------------------------------------------------------------------------

-- Eigene Seite jeder Leiste (wie bei Blizzard): Leiste 1 = Seite 1, Leiste 2 = Seite 6 usw.
local HOME_PAGES = { bar1 = 1, bar2 = 6, bar3 = 5, bar4 = 3, bar5 = 4, bar6 = 13, bar7 = 14, bar8 = 15 }
ns.HOME_PAGES = HOME_PAGES
local MODIFIERS = { { key = "pageCtrl", mod = "ctrl" }, { key = "pageAlt", mod = "alt" }, { key = "pageShift", mod = "shift" } }

-- Leiste 1 ohne eigene Einstellungen: Blizzard regelt den Seitenwechsel selbst (Gestalten, Seiten-Pfeile)
local function IsDefaultPaging(cfg)
    if cfg.usePagingCustom and strtrim(cfg.pagingCustom or "") ~= "" then return false end
    for _, modifier in ipairs(MODIFIERS) do
        if (tonumber(cfg[modifier.key]) or 0) > 0 then return false end
    end
    for _, value in pairs(cfg.stancePages or {}) do
        if value ~= "BLIZZARD" then return false end
    end
    return true
end

-- Makro-Bedingung für den Seitenwechsel, z. B. "[mod:shift] 2; [stance:1] 7; 1" (nil = Blizzard regelt es)
local function PagingDriver(def, cfg)
    if def.kind ~= "action" then return nil end
    if def.key == "bar1" and IsDefaultPaging(cfg) then return nil end
    local home = HOME_PAGES[def.key] or 1
    local custom = cfg.usePagingCustom and strtrim(cfg.pagingCustom or "")
    if custom and custom ~= "" then return custom end
    local parts = {}
    if def.key == "bar1" then
        -- Fahrzeug, Blizzard-Fahrzeugleiste, Gedankenkontrolle und Sonderleisten wie bei Blizzard
        table.insert(parts, ("[overridebar] %d"):format(GetOverrideBarIndex and GetOverrideBarIndex() or 14))
        table.insert(parts, ("[vehicleui] %d"):format(GetVehicleBarIndex and GetVehicleBarIndex() or 12))
        table.insert(parts, ("[possessbar] %d"):format(GetVehicleBarIndex and GetVehicleBarIndex() or 12))
        table.insert(parts, ("[shapeshift] %d"):format(GetTempShapeshiftBarIndex and GetTempShapeshiftBarIndex() or 13))
    end
    for _, modifier in ipairs(MODIFIERS) do
        local page = tonumber(cfg[modifier.key]) or 0
        if page > 0 then table.insert(parts, ("[mod:%s] %d"):format(modifier.mod, page)) end
    end
    local blizzardStances = false
    local forms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, forms do
        local value = cfg.stancePages and cfg.stancePages[i]
        if value == nil then value = def.key == "bar1" and "BLIZZARD" or 0 end
        if value == "BLIZZARD" then
            blizzardStances = true
        elseif (tonumber(value) or 0) > 0 then
            table.insert(parts, ("[stance:%d] %d"):format(i, value))
        end
    end
    if def.key == "bar1" then
        -- Blizzard-Seiten für Gestalten (Bär, Katze, Verstohlenheit …) und die Seiten-Pfeile
        if blizzardStances or forms == 0 then
            for n = 5, 1, -1 do table.insert(parts, ("[bonusbar:%d] %d"):format(n, 6 + n)) end
        end
        for n = 6, 2, -1 do table.insert(parts, ("[bar:%d] %d"):format(n, n)) end
    end
    table.insert(parts, tostring(home))
    return table.concat(parts, "; ")
end

-- Seitenwechsel einer Leiste einrichten (nur außerhalb des Kampfes)
local function SetupPaging(def, cfg, holder)
    if def.kind ~= "action" then return end
    local buttons = GetAllButtons(def)
    if not holder.fbPagingSetup then
        holder.fbPagingSetup = true
        for i, button in ipairs(buttons) do holder:SetFrameRef("button" .. i, button) end
        holder:SetAttribute("buttonCount", #buttons)
        -- Funktion, mit der Blizzard-Knöpfe ihre Belegung neu lesen
        local first = buttons[1]
        holder:SetAttribute("updateMethod", first and (first.UpdateAction and "UpdateAction" or (first.Update and "Update")) or nil)
        -- Läuft geschützt, auch im Kampf: neue Seite an alle Knöpfe geben und sie neu zeichnen lassen
        holder:SetAttribute("_onstate-page", [[
            local page = tonumber(newstate) or 1
            self:SetAttribute("actionpage", page)
            local method = self:GetAttribute("updateMethod")
            for i = 1, self:GetAttribute("buttonCount") or 0 do
                local button = self:GetFrameRef("button" .. i)
                if button then
                    button:SetAttribute("actionpage", page)
                    if method then button:CallMethod(method) end
                end
            end
        ]])
    end
    local driver = PagingDriver(def, cfg)
    if driver then
        -- Abgesichert: bei fehlerhafter eigener Bedingung die eigene Seite der Leiste
        if not pcall(RegisterStateDriver, holder, "page", driver) then
            RegisterStateDriver(holder, "page", tostring(HOME_PAGES[def.key] or 1))
        end
        holder.fbPaging = true
    elseif holder.fbPaging then
        -- Zurück zum Blizzard-Seitenwechsel (nur Leiste 1)
        UnregisterStateDriver(holder, "page")
        holder.fbPaging = false
        holder:SetAttribute("actionpage", nil)
        for _, button in ipairs(buttons) do
            button:SetAttribute("actionpage", nil)
            if button.UpdateAction then button:UpdateAction() end
        end
    end
end

-- Namen der Gestalten/Haltungen des Charakters (für das Menü)
function ns.GetStanceNames()
    local names = {}
    local forms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, forms do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        local name = spellID and (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
            or (GetSpellInfo and GetSpellInfo(spellID)))
        names[i] = name or ns.L("STANCE_N", i)
    end
    return names
end

-- Ausblend-Bedingungen (Häkchen im Menü) -> Makro-Bedingung
local HIDE_CONDITIONS = {
    { key = "hideVehicle", condition = "[vehicleui]" },
    { key = "hideOverride", condition = "[overridebar]" },
    { key = "hidePossess", condition = "[possessbar]" },
    { key = "hidePet", condition = "[pet]" },
    { key = "hideNoPet", condition = "[nopet]" },
    { key = "hideStance", condition = "[stance]" },
}

local function VisibilityDriver(def, cfg)
    if not cfg.enabled then return "hide" end
    if ns.unlocked then return "show" end
    -- Eigene Bedingung ersetzt alle anderen Einstellungen
    local custom = cfg.useCustom and strtrim(cfg.custom or "")
    if custom and custom ~= "" then return custom end
    local parts = { "[petbattle] hide" }
    for _, entry in ipairs(HIDE_CONDITIONS) do
        if cfg[entry.key] then table.insert(parts, entry.condition .. " hide") end
    end
    if cfg.visibility == "COMBAT" then
        table.insert(parts, "[combat] show")
        table.insert(parts, "hide")
    elseif cfg.visibility == "NOCOMBAT" then
        table.insert(parts, "[combat] hide")
        table.insert(parts, "show")
    else
        table.insert(parts, "show")
    end
    return table.concat(parts, "; ")
end

---------------------------------------------------------------------------
-- Magnetisches Einrasten beim Ziehen: an Kanten und Mitten der anderen Leisten und an der Bildschirmmitte
---------------------------------------------------------------------------

local SNAP_DISTANCE = 10 -- so nah (in Pixeln) muss man kommen, damit es einrastet
local SNAP_GAP = 2       -- Abstand, wenn Leisten aneinander einrasten

-- Rand eines Halters in Bildschirm-Koordinaten (wie UIParent)
local function HolderRect(holder)
    local left, right, top, bottom = holder:GetLeft(), holder:GetRight(), holder:GetTop(), holder:GetBottom()
    if not left then return nil end
    local ratio = holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * ratio, right * ratio, top * ratio, bottom * ratio
end

-- x/y = gewünschte Mitte der gezogenen Leiste; Rückgabe: ggf. eingerastete Mitte
local function SnapPosition(key, x, y)
    if not ns.db.snap or IsShiftKeyDown() then return x, y end
    local holder = holders[key]
    if not holder then return x, y end
    local ratio = holder:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local halfWidth, halfHeight = holder:GetWidth() * ratio / 2, holder:GetHeight() * ratio / 2
    local bestX, distanceX = x, SNAP_DISTANCE + 1
    local bestY, distanceY = y, SNAP_DISTANCE + 1
    local function TryX(candidate)
        local distance = math.abs(candidate - x)
        if distance < distanceX then bestX, distanceX = candidate, distance end
    end
    local function TryY(candidate)
        local distance = math.abs(candidate - y)
        if distance < distanceY then bestY, distanceY = candidate, distance end
    end
    -- Bildschirmmitte
    TryX(UIParent:GetWidth() / 2)
    TryY(UIParent:GetHeight() / 2)
    for otherKey, other in pairs(holders) do
        if otherKey ~= key and other:IsVisible() and ns.db.bars[otherKey].enabled then
            local left, right, top, bottom = HolderRect(other)
            if left then
                -- waagerecht: daneben (links/rechts), bündig (linke/rechte Kante), mittig
                TryX(right + SNAP_GAP + halfWidth)
                TryX(left - SNAP_GAP - halfWidth)
                TryX(left + halfWidth)
                TryX(right - halfWidth)
                TryX((left + right) / 2)
                -- senkrecht: darüber/darunter, bündig (obere/untere Kante), mittig
                TryY(top + SNAP_GAP + halfHeight)
                TryY(bottom - SNAP_GAP - halfHeight)
                TryY(top - halfHeight)
                TryY(bottom + halfHeight)
                TryY((top + bottom) / 2)
            end
        end
    end
    return bestX, bestY
end

local function UpdateMover(def, holder)
    local mover = movers[def.key]
    if not ns.unlocked or not ns.db.bars[def.key].enabled then
        if mover then mover:Hide() end
        return
    end
    if not mover then
        mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        -- Über dem Menüfenster, damit es die Griffe nicht verdeckt
        mover:SetFrameStrata("FULLSCREEN")
        ns.Style.SetFlat(mover, { 0.10, 0.10, 0.12, 0.55 }, { MOVER_COLOR[1], MOVER_COLOR[2], MOVER_COLOR[3], 1 })
        mover.text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mover.text:SetPoint("CENTER")
        mover:EnableMouse(true)
        -- Hinweis beim Darüberfahren
        mover:SetScript("OnEnter", function(self)
            if self.isMoving then return end
            local tip = ns.Style.GetTooltip()
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:AddLine(self.text:GetText(), 1, 0.82, 0)
            tip:AddLine(L("TIP_MOVER"), 1, 1, 1, true)
            tip:Show()
        end)
        mover:SetScript("OnLeave", function(self)
            local tip = ns.Style.GetTooltip()
            if tip:GetOwner() == self then tip:Hide() end
        end)
        -- Eigenes Ziehen: Maustaste gedrückt halten, der Griff folgt dem Mauszeiger.
        -- (Ohne StartMoving, das bei Leisten mit geschützten Knöpfen nicht zuverlässig klappt.)
        local function CursorPosition()
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            return x / scale, y / scale
        end
        mover:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or InCombatLockdown() then return end
            ns.Style.GetTooltip():Hide()
            -- Abstand zwischen Mauszeiger und Mitte des Griffs merken, damit er nicht springt
            local centerX, centerY = self:GetCenter()
            if not centerX or not centerY then centerX, centerY = ns.GetBarPosition(self.key) end
            local cursorX, cursorY = CursorPosition()
            self.offsetX, self.offsetY = centerX - cursorX, centerY - cursorY
            self.isMoving = true
            -- Die Leiste selbst wandert mit (der Griff hängt an ihr), damit man sie beim Ziehen sieht;
            -- dabei rastet sie magnetisch ein (Shift gedrückt halten = frei schieben)
            self:SetScript("OnUpdate", function(frame)
                local holder = holders[frame.key]
                if not holder or InCombatLockdown() then return end
                local x, y = CursorPosition()
                x, y = SnapPosition(frame.key, x + frame.offsetX, y + frame.offsetY)
                frame.dropX, frame.dropY = x, y
                local scale = holder:GetScale()
                holder:ClearAllPoints()
                holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
            end)
        end)
        mover:SetScript("OnMouseUp", function(self, button)
            -- Rechtsklick: Einstellungen dieser Leiste im Menü öffnen
            if button == "RightButton" and not self.isMoving then
                if ns.ShowBarOptions then ns.ShowBarOptions(self.key) end
                return
            end
            if button ~= "LeftButton" or not self.isMoving then return end
            self:SetScript("OnUpdate", nil)
            self.isMoving = false
            -- Die (ggf. eingerastete) Position vom Ziehen übernehmen
            local x, y = self.dropX, self.dropY
            if not x or not y then
                local cursorX, cursorY = CursorPosition()
                x, y = cursorX + self.offsetX, cursorY + self.offsetY
            end
            self.dropX, self.dropY = nil, nil
            local cfg = ns.db.bars[self.key]
            cfg.x = math.floor(x + 0.5)
            cfg.y = math.floor(y + 0.5)
            ns.RequestLayout()
            if ns.RefreshOptions then ns.RefreshOptions() end
        end)
        movers[def.key] = mover
    end
    mover.key = def.key
    mover.text:SetText(L(def.textKey))
    -- Wird der Griff gerade gezogen, nicht zurücksetzen (sonst springt er beim Ziehen zurück)
    if mover.isMoving then return end
    mover:ClearAllPoints()
    mover:SetAllPoints(holder)
    -- Mindestgröße, damit auch leere Leisten (z. B. Haltung ohne Gestalten) greifbar bleiben
    if holder:GetWidth() < 20 or holder:GetHeight() < 20 then
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", holder, "CENTER")
        mover:SetSize(math.max(holder:GetWidth() * holder:GetScale(), 80), math.max(holder:GetHeight() * holder:GetScale(), 20))
    end
    mover:Show()
end

function ns.ApplyLayout()
    layoutPending = false
    if ns.disabledByBartender then return end
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    for _, def in ipairs(ns.BAR_DEFS) do
        local cfg = ns.db.bars[def.key]
        local holder = GetHolder(def)
        HideBlizzardBars(def)
        if def.kind == "container" or def.kind == "single" then
            LayoutContainer(def, cfg, holder)
        else
            LayoutButtons(def, cfg, holder)
        end
        local scale = math.max(0.3, (cfg.scale or 100) / 100)
        holder:SetScale(scale)
        local x, y = ns.GetBarPosition(def.key)
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        -- Deckkraft; beim Einblenden per Maus übernimmt das die Überblendung (siehe UpdateFading)
        if not cfg.fadeMouseover or ns.unlocked then
            holder:SetAlpha((cfg.alpha or 100) / 100)
            holder.fbAlpha = nil
        end
        SetupPaging(def, cfg, holder)
        -- Abgesichert, damit eine fehlerhafte eigene Bedingung keinen Fehler auslöst
        if not pcall(RegisterStateDriver, holder, "visibility", VisibilityDriver(def, cfg)) then
            RegisterStateDriver(holder, "visibility", "[petbattle] hide; show")
        end
        UpdateMover(def, holder)
    end
end

-- Mehrere Änderungen kurz hintereinander werden zusammengefasst; im Kampf erst danach
function ns.RequestLayout()
    if not ns.ready then return end
    if InCombatLockdown() then
        layoutPending = true
        return
    end
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        ns.ApplyLayout()
    end)
end

---------------------------------------------------------------------------
-- Entsperren, Tastenbelegung, Mausover
---------------------------------------------------------------------------

function ns.SetUnlocked(unlocked)
    if ns.disabledByBartender then
        ns.Print(L("BARTENDER_ACTIVE"))
        return
    end
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    ns.unlocked = unlocked and true or false
    ns.ApplyLayout()
    ns.Print(L(ns.unlocked and "UNLOCKED" or "LOCKED"))
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Blizzard-Schnelltastenbelegung: Maus auf einen Knopf legen und Taste drücken
function ns.OpenKeybindMode()
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    if ns.HideOptions then ns.HideOptions() end
    if QuickKeybindFrame then
        if ShowUIPanel then ShowUIPanel(QuickKeybindFrame) else QuickKeybindFrame:Show() end
    else
        ns.Print(L("KEYBIND_UNAVAILABLE"))
    end
end

-- Einblenden bei Maus darüber: Leiste sanft auf die Rest-Deckkraft ausblenden, bis die Maus darüber ist;
-- nach dem Wegziehen erst nach der eingestellten Verzögerung. Im Kampf auf Wunsch immer voll sichtbar.
-- (Knöpfe bleiben auch ausgeblendet benutzbar; Deckkraft darf das Addon auch im Kampf ändern.)
local FADE_INTERVAL = 0.05 -- Sekunden zwischen zwei Schritten
local FADE_SPEED = 4       -- Deckkraft-Änderung pro Sekunde (ganze Überblendung ca. 0,25 s)

local function UpdateFading()
    local now = GetTime()
    for _, def in ipairs(ns.BAR_DEFS) do
        local cfg = ns.db.bars[def.key]
        local holder = holders[def.key]
        if holder and cfg.enabled and cfg.fadeMouseover and not ns.unlocked then
            local full = (cfg.alpha or 100) / 100
            local over = holder:IsMouseOver()
                or (SpellFlyout and SpellFlyout:IsShown() and SpellFlyout:IsMouseOver())
                or (cfg.fadeInCombat and InCombatLockdown())
            if over then holder.fbLastOver = now end
            local visible = over or (now - (holder.fbLastOver or 0)) < (cfg.fadeDelay or 0)
            local target = visible and full or math.min(full, (cfg.fadeAlpha or 0) / 100)
            local current = holder.fbAlpha or target
            local step = FADE_SPEED * FADE_INTERVAL
            if current < target then
                current = math.min(target, current + step)
            elseif current > target then
                current = math.max(target, current - step)
            end
            holder.fbAlpha = current
            holder:SetAlpha(current)
        end
    end
end

---------------------------------------------------------------------------
-- Start und Ereignisse
---------------------------------------------------------------------------

-- Blizzard-Einsteiger-Hilfe für Aktionsleisten abschalten: Sie sucht die Original-Leisten und wirft sonst
-- Fehler, wenn deren Knöpfe in ForeverBars liegen (so macht es auch Bartender4)
local function DisableTutorials()
    local tutorials = Tutorials
    if not tutorials then return end
    for _, name in ipairs({ "AddSpellToActionBar", "AddClassSpellToActionBar", "Intro_CombatTactics" }) do
        local tutorial = tutorials[name]
        if tutorial and tutorial.Disable then pcall(tutorial.Disable, tutorial) end
    end
    -- Ohne das Ziehen-Tutorial neue Zauber trotzdem automatisch auf die Leiste legen
    local watcher = tutorials.AutoPushSpellWatcher
    if watcher and watcher.Complete then pcall(watcher.Complete, watcher) end
end

function ns.SetupBars()
    ns.ready = true
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if isLoaded and isLoaded("Blizzard_NewPlayerExperience") then
        DisableTutorials()
    elseif NPE_LoadUI then
        hooksecurefunc("NPE_LoadUI", DisableTutorials)
    end
    ns.ApplyLayout()
    C_Timer.NewTicker(FADE_INTERVAL, UpdateFading)

    -- Blizzard-Bearbeitungsmodus kann die Leisten nicht greifen (sie liegen in ForeverBars-Haltern).
    -- Darum beim Öffnen die eigenen Griffe zeigen und beim Schließen wieder sperren – aber nur, wenn
    -- der Bearbeitungsmodus sie entsperrt hat. HookScript verändert den Blizzard-Rahmen nicht (kein taint).
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function()
            if ns.unlocked or InCombatLockdown() then return end
            ns.unlockedByEditMode = true
            ns.SetUnlocked(true)
            ns.Print(L("EDITMODE_HINT"))
        end)
        EditModeManagerFrame:HookScript("OnHide", function()
            if not ns.unlockedByEditMode then return end
            ns.unlockedByEditMode = nil
            if ns.unlocked and not InCombatLockdown() then ns.SetUnlocked(false) end
        end)
    end

    local events = CreateFrame("Frame")
    -- Nach dem Kampf ausstehende Änderungen übernehmen; nach Ladebildschirmen und Bearbeitungsmodus neu anordnen
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED",
        "UPDATE_SHAPESHIFT_FORMS", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if layoutPending then ns.ApplyLayout() end
        else
            ns.RequestLayout()
        end
    end)
end
