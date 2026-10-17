local addonName, ns = ...
local L = ns.L

-- Aktionsleisten: ForeverBars nimmt die originalen Blizzard-Knöpfe und ordnet sie in eigenen Leisten an.
-- So erledigt das Spiel weiterhin Seitenwechsel, Abklingzeiten, Reichweite und Tastenbelegungen.
-- Wichtig: Aktionsknöpfe sind geschützt - Anordnung, Größe und Position nur außerhalb des Kampfes ändern.

local ACTION_SIZE = 36   -- Kantenlänge der Aktionsknöpfe
local SMALL_SIZE = 30    -- Taschenknöpfe (Begleiter/Haltung haben Aktionsgröße und werden über "Größe" verkleinert)
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
    -- Ausklappbar und gerade eingeklappt: nur der Rucksack (der Pfeil daneben klappt die Taschen aus)
    local onlyBackpack = cfg.collapsible and cfg.bagsCollapsed
    local list = {}
    for i, name in ipairs(def.bagButtons) do
        if _G[name] and (i == 1 or not onlyBackpack) then table.insert(list, _G[name]) end
    end
    if cfg.keyring and KeyRingButton and not onlyBackpack then table.insert(list, KeyRingButton) end
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
-- Positionen. Gespeichert wird, wo der Ankerpunkt der Leiste liegt (cfg.point, z. B. "CENTER" oder
-- "BOTTOMRIGHT"), gemessen von unten links. So bleibt z. B. die Haltungsleiste rechtsbündig, auch wenn
-- sich die Zahl ihrer Knöpfe ändert.
---------------------------------------------------------------------------

-- Lage eines Ankerpunkts relativ zur Mitte (-1 = links/unten, 1 = rechts/oben)
local function PointFactors(point)
    point = point or "CENTER"
    local fx = point:find("LEFT") and -1 or (point:find("RIGHT") and 1 or 0)
    local fy = point:find("TOP") and 1 or (point:find("BOTTOM") and -1 or 0)
    return fx, fy
end

-- Standard-Anordnung: drei Aktionsleisten unten mittig aneinander, darüber links die Begleiterleiste
-- (bündig zum ersten Knopf) und rechts die Haltungsleiste (bündig zum letzten Knopf), links daneben die
-- Berufeleiste, unten rechts Menü und Taschen übereinander, oben mittig Erfahrung und Ruf.
local EDGE = 4         -- Abstand zum Bildschirmrand
local STATUS_EDGE = 9  -- Abstand der untersten Erfahrungs-/Ruf-Leiste zum Bildschirmrand (etwas Luft unter der Leiste)
local STATUS_TOP_GAP = 7 -- zusätzlicher Abstand zwischen der obersten dieser Leisten und den Aktionsleisten
local BAR_GAP = 1.5    -- Abstand zwischen aneinanderliegenden Leisten (wie "Abstand" der Knöpfe)
local SIDE_GAP = 24    -- Abstand von Berufe-/Verpflegungsleiste zu den Aktionsleisten (Platz für den Einklapp-Pfeil)
local FRAME_SPACE = 4  -- Rand des Rahmens um eine Leiste (siehe UpdateBarFrame)
local PET_GAP = 8     -- kleiner Abstand der Begleiter-/Haltungsleiste zu den Aktionsleisten (Flächen berühren sich nicht)

-- Tatsächliche Größe einer Leiste. Aktionsleisten: "100 %" im Menü sind 105 % der Blizzard-Knopfgröße
-- (die Knöpfe sollten größer werden, ohne dass im Menü ein krummer Wert steht)
local ACTION_BASE_SCALE = 1.05
function ns.BarScale(key, cfg)
    local def = ns.GetBarDef and ns.GetBarDef(key)
    local base = def and def.kind == "action" and ACTION_BASE_SCALE or 1
    return math.max(0.3, (cfg.scale or 100) / 100) * base
end

local function DefaultPosition(key)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local bars = ns.db.bars
    local function Scale(barKey) return ns.BarScale(barKey, bars[barKey]) end
    local function HolderHeight(barKey, fallback)
        local holder = holders[barKey]
        if holder and holder:GetHeight() > 1 then return holder:GetHeight() * holder:GetScale() end
        return fallback
    end
    -- Zwischen aneinanderliegenden Leisten wie zwischen Knöpfen: Ränder übereinander, eine feine Linie
    local BAR_GAP = ns.ButtonGap({ spacing = BAR_GAP })
    local scale = Scale("bar1")
    local barWidth = (12 * ACTION_SIZE + 11 * ns.ButtonGap(bars.bar1)) * scale
    local barHeight = ACTION_SIZE * scale
    local left, right = width / 2 - barWidth / 2, width / 2 + barWidth / 2
    -- Erfahrungs- und Ruf-Leiste liegen ganz unten (Erfahrung unten, Ruf darüber, sonst ohne Lücke); die Aktionsleisten
    -- und alles daneben beginnen darüber. Bei Höchststufe (keine Erfahrung) und ausgeschalteten Leisten entfällt der Platz.
    local statusBase, statusCenter = EDGE, {}
    for _, key in ipairs({ "xp", "rep" }) do
        local cfg = bars[key]
        if cfg and cfg.enabled and not (key == "xp" and ns.AtMaxLevel and ns.AtMaxLevel()) then
            statusBase = STATUS_EDGE -- die unterste Leiste liegt nicht direkt am Bildschirmrand
            break
        end
    end
    for _, key in ipairs({ "xp", "rep" }) do
        local cfg = bars[key]
        if cfg then
            local h = ns.StatusHeight(key, cfg) * Scale(key)
            statusCenter[key] = statusBase + h / 2
            if cfg.enabled and not (key == "xp" and ns.AtMaxLevel and ns.AtMaxLevel()) then
                statusBase = statusBase + h + BAR_GAP
            end
        end
    end
    -- Luft zwischen der obersten Statusleiste (Ruf) und Aktionsleiste 1 – nur, wenn überhaupt eine Statusleiste da ist
    -- (früher "== STATUS_EDGE": das traf bei sichtbaren Leisten nie zu, die Luft fehlte)
    if statusBase > EDGE then statusBase = statusBase + STATUS_TOP_GAP end
    local function BarCenter(row) return statusBase + barHeight / 2 + row * (barHeight + BAR_GAP) end
    -- Aktionsleisten übereinander: 1, 2, 3, darüber 6, 7, 8. Begleiter- und Haltungsleiste sitzen immer über der
    -- obersten eingeschalteten davon (ApplyLayout rechnet das bei jeder Anordnung neu, solange man sie nicht selbst
    -- verschoben hat)
    local ROWS = { bar1 = 0, bar2 = 1, bar3 = 2, bar6 = 3, bar7 = 4, bar8 = 5 }
    local topRow = 0
    for key, row in pairs(ROWS) do
        if bars[key] and bars[key].enabled and row > topRow then topRow = row end
    end
    local stackTop = BarCenter(topRow) + barHeight / 2              -- Oberkante der obersten Aktionsleiste
    local smallRow = ACTION_SIZE * Scale("pet")                    -- Höhe der Begleiter-/Haltungsreihe
    local smallBottom = stackTop + PET_GAP                          -- Unterkante der Begleiter-/Haltungsreihe
    local aboveSmall = smallBottom + smallRow + PET_GAP             -- darüber: Fahrzeug verlassen
    local microHeight = HolderHeight("micro", 40)
    -- Mikromenü unter der Minimap angedockt: die Taschen sitzen allein unten rechts in der Ecke
    if bars.micro.dockMinimap and C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverMinimap") then
        microHeight = 1
    end
    local positions = {
        bar1 = { width / 2, BarCenter(0) }, bar2 = { width / 2, BarCenter(1) }, bar3 = { width / 2, BarCenter(2) },
        bar6 = { width / 2, BarCenter(3) }, bar7 = { width / 2, BarCenter(4) }, bar8 = { width / 2, BarCenter(5) },
        bar4 = { width - 30, height / 2 }, bar5 = { width - 30 - ACTION_SIZE - 8, height / 2 },
        pet = { left, smallBottom },     -- BOTTOMLEFT
        totem = { left, smallBottom },   -- BOTTOMLEFT, beim Schamanen statt der Begleiterleiste
        stance = { right, smallBottom }, -- BOTTOMRIGHT
        prof = { left - SIDE_GAP - FRAME_SPACE, statusBase + FRAME_SPACE }, -- BOTTOMRIGHT (Rahmen eingerechnet)
        food = { right + SIDE_GAP + FRAME_SPACE, statusBase + FRAME_SPACE }, -- BOTTOMLEFT, gespiegelt zur Berufeleiste
        xp = { width / 2, statusCenter.xp or (EDGE + 9) }, rep = { width / 2, statusCenter.rep or (EDGE + 30) },
        micro = { width - EDGE, EDGE },                        -- BOTTOMRIGHT
        bags = { width - EDGE, EDGE + microHeight - 1 },       -- BOTTOMRIGHT, direkt auf dem Mikromenü (Ränder übereinander)
        vehicle = { width / 2, aboveSmall + 20 }, queue = { width - 290, 120 },
    }
    local position = positions[key] or { width / 2, height / 2 }
    return position[1], position[2]
end

ns.DefaultPosition = DefaultPosition

-- Mitte einer Leiste setzen (Ziehen, "Zentrieren"); gespeichert wird der Ankerpunkt
function ns.SetBarCenter(key, centerX, centerY)
    local cfg = ns.db.bars[key]
    local holder = holders[key]
    local fx, fy = PointFactors(cfg.point)
    local halfWidth, halfHeight = 0, 0
    if holder then
        halfWidth = holder:GetWidth() * holder:GetScale() / 2
        halfHeight = holder:GetHeight() * holder:GetScale() / 2
    end
    if centerX then cfg.x = math.floor(centerX + fx * halfWidth + 0.5) end
    if centerY then cfg.y = math.floor(centerY + fy * halfHeight + 0.5) end
    cfg.moved = true -- vom Nutzer gesetzt: neue Standard-Anordnungen (Layout-Version) lassen die Leiste in Ruhe
end

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

ns.GetFontPath = GetFontPath
ns.SetTextFont = SetTextFont

-- Stile der Knöpfe, alle im flachen Forever-Design: Randfarbe, Randstärke, Abstand des Symbols zum Rand
-- und Hintergrund leerer Plätze
local COLOR = ns.Style.COLOR
ns.SKINS = {
    -- Forever: wie die Fenster der Forever-Addons – heller 1-px-Rand, darin ein schwarzer Ring, dunkle Fläche,
    -- beim Darüberfahren goldener Rand; Aktions-, Begleiter- und Haltungsleisten liegen auf einer dunklen Fläche
    -- (wie der Körper eines Forever-Fensters)
    { key = "FOREVER", textKey = "SKIN_FOREVER", border = { 0.34, 0.34, 0.40, 1 }, size = 1, inset = 2,
      inner = { 0, 0, 0, 0.9 }, hoverGold = true, barBackdrop = true,
      background = { 0.10, 0.10, 0.12, 0.92 } },
    { key = "FLAT", textKey = "SKIN_FLAT", border = COLOR.border, size = 1, inset = 1,
      background = { 0.06, 0.06, 0.08, 0.85 } },
    { key = "GOLD", textKey = "SKIN_GOLD", border = { COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.55 }, size = 1,
      inset = 1, background = { 0.06, 0.06, 0.08, 0.85 } },
    { key = "SHADOW", textKey = "SKIN_SHADOW", border = { 0, 0, 0, 1 }, size = 2, inset = 2,
      background = { 0, 0, 0, 0.6 } },
    { key = "GLASS", textKey = "SKIN_GLASS", border = { 1, 1, 1, 0.18 }, size = 1, inset = 1,
      background = { 0.20, 0.20, 0.25, 0.35 } },
}

local function GetSkin()
    for _, skin in ipairs(ns.SKINS) do
        if skin.key == ns.db.skin then return skin end
    end
    return ns.SKINS[1]
end

-- Platz zwischen zwei Knöpfen. "Abstand" meint den Abstand zwischen den Symbolen: die Ränder benachbarter
-- Knöpfe liegen übereinander (sonst wirken Rand + Lücke + Rand wie ein Balken). Bei Abstand 1 und 1-px-Rand
-- bleibt genau eine feine Linie.
function ns.ButtonGap(cfg)
    -- Es überlappen nur die äußeren Ränder (Stärke size); ein innerer Ring (Stil "Forever") bleibt je Knopf sichtbar
    local border = ns.db.showBorder and GetSkin().size or 0
    return (cfg.spacing or 1.5) - 2 * border
end

-- Breite der Aktionsleiste 1 in Bildschirmeinheiten: Erfahrungs- und Ruf-Leiste sind standardmäßig genauso breit
function ns.ActionBarWidth()
    local cfg = ns.db.bars.bar1
    local holder = holders.bar1
    -- tatsächliche Breite des Halters (nach dem Anordnen der Knöpfe), sonst aus den Einstellungen gerechnet
    if holder and cfg.enabled and holder:GetWidth() > ACTION_SIZE then
        return holder:GetWidth() * ns.BarScale("bar1", cfg)
    end
    local count = math.max(1, math.min(cfg.perRow or 12, cfg.buttons or 12))
    return (count * ACTION_SIZE + (count - 1) * ns.ButtonGap(cfg)) * ns.BarScale("bar1", cfg)
end

-- Hover-, Gedrückt- und Aktiv-Leuchten: Blizzards Grafiken sind für größere Knöpfe mit Rahmen gemacht und
-- sitzen auf den flachen Knöpfen versetzt. Darum flache Flächen genau über dem Symbol.
local function UpdateStateTextures(button, icon)
    local target = icon or button
    local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
    if highlight then
        highlight:SetColorTexture(1, 1, 1, math.max(0, math.min(100, ns.db.hoverAlpha or 15)) / 100)
        highlight:ClearAllPoints()
        highlight:SetAllPoints(target)
    end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed then
        pushed:SetColorTexture(0, 0, 0, 0.35)
        pushed:ClearAllPoints()
        pushed:SetAllPoints(target)
    end
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.25)
        checked:ClearAllPoints()
        checked:SetAllPoints(target)
    end
    -- Weitere Blizzard-Flächen (Aufblinken beim Angriff, neue Aktion, Hinweis aus dem Zauberbuch) ebenfalls aufs Symbol
    for _, region in ipairs({ button.Flash, button.NewActionTexture, button.SpellHighlightTexture }) do
        if region and region.SetAllPoints then
            region:ClearAllPoints()
            region:SetAllPoints(target)
        end
    end
end

-- Position der Tastenbelegung auf dem Knopf
local HOTKEY_POSITIONS = {
    TOPRIGHT = { "TOPRIGHT", -2, -3, "RIGHT" },
    TOPLEFT = { "TOPLEFT", 3, -3, "LEFT" },
    TOP = { "TOP", 0, -3, "CENTER" },
}

-- Lange Tastennamen kürzen, damit sie auf den Knopf passen (Blizzard kürzt nur teilweise, z. B. "Mausrad hoch")
local KEY_SHORT = {
    { "SHIFT%-", "S" }, { "Shift%-", "S" }, { "Umschalt%-", "S" }, { "UMSCHALT%-", "S" },
    { "STRG%-", "C" }, { "Strg%-", "C" }, { "CTRL%-", "C" }, { "Ctrl%-", "C" },
    { "ALT%-", "A" }, { "Alt%-", "A" }, { "META%-", "M" },
    { "Mausrad hoch", "MU" }, { "Mausrad runter", "MD" }, { "Mausrad unten", "MD" },
    { "Mouse Wheel Up", "MU" }, { "Mouse Wheel Down", "MD" },
    { "Mittlere Maustaste", "M3" }, { "Middle Mouse", "M3" },
    { "Maustaste (%d+)", "M%1" }, { "Mouse Button (%d+)", "M%1" },
    { "Ziffernblock ?", "N" }, { "Num Pad ?", "N" }, { "Numpad ?", "N" },
    { "Leertaste", "Spc" }, { "Spacebar", "Spc" }, { "Rücktaste", "BS" }, { "Backspace", "BS" },
    { "Einfg", "Ins" }, { "Entf", "Del" }, { "Bild auf", "PU" }, { "Bild ab", "PD" },
    { "Page Up", "PU" }, { "Page Down", "PD" }, { "Pos1", "Hm" },
}
function ns.ShortKey(text)
    if type(text) ~= "string" or text == "" then return text end
    for _, pair in ipairs(KEY_SHORT) do text = text:gsub(pair[1], pair[2]) end
    return text
end

local CAST_VFX_ALPHA = 0.4 -- Deckkraft von Blizzards Zauber-Rand auf den Knöpfen (siehe UpdateButtonLook)

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
        -- Blizzards Feld ist fest 32 x 10 groß: bei unserer Schrift wurden längere Tasten abgeschnitten oder
        -- gar nicht gezeigt. Darum so breit wie der Knopf und so hoch wie die Schrift.
        local width = button:GetWidth()
        if not width or width < 10 then width = ACTION_SIZE end
        hotkey:SetSize(width - 4, db.fontSize + 4)
        hotkey:SetWordWrap(false)
        local text = hotkey:GetText()
        if text == RANGE_INDICATOR then
            -- Knopf ohne Tastenbelegung: Blizzard zeigt hier den Reichweiten-Punkt "●" (rot = außer Reichweite).
            -- Viele Schriften haben das Zeichen nicht (es erschien ein leeres Kästchen) – dafür Arial Narrow
            local _, fontSize, flags = hotkey:GetFont()
            hotkey:SetFont("Fonts\\ARIALN.TTF", fontSize or db.fontSize, flags or "OUTLINE")
        elseif text and text ~= "" then
            local short = ns.ShortKey(text)
            if short ~= text then hotkey:SetText(short) end
        end
    end
    if macro then
        macro:SetAlpha(db.showMacroNames and 1 or 0)
        SetTextFont(macro, math.max(8, db.fontSize - 2))
    end
    if count then
        count:SetAlpha(db.showCounts and 1 or 0)
        SetTextFont(count, db.fontSize)
    end

    -- Zauber-Effekt auf dem Knopf (gelber Rand, der beim Zaubern umläuft), falls das Spiel ihn hat. Blizzards Rand
    -- ist für größere Knöpfe gemacht und wirkt auf den flachen Knöpfen dick: dezenter (halb durchsichtig)
    for _, effect in ipairs({ button.SpellCastAnimFrame, button.TargetReticleAnimFrame }) do
        if effect and effect.SetAlpha then effect:SetAlpha(db.castVFX and CAST_VFX_ALPHA or 0) end
    end
    if button.InterruptDisplay and button.InterruptDisplay.SetAlpha then
        button.InterruptDisplay:SetAlpha(db.castVFX and 1 or 0)
    end

    -- Stil: Rand, Hintergrund leerer Plätze, Abstand des Symbols zum Rand
    local skin = GetSkin()
    if button.fbBorder then
        button.fbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = skin.size })
        button.fbBorder:SetBackdropBorderColor(unpack(skin.border))
        button.fbBorder:SetShown(db.showBorder)
        -- Innerer Ring zwischen Rand und Symbol (Stil "Forever")
        if skin.inner and not button.fbInner then
            local inner = CreateFrame("Frame", nil, button.fbBorder, "BackdropTemplate")
            inner:SetPoint("TOPLEFT", skin.size, -skin.size)
            inner:SetPoint("BOTTOMRIGHT", -skin.size, skin.size)
            inner:EnableMouse(false)
            inner:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            button.fbInner = inner
        end
        if button.fbInner then
            button.fbInner:SetShown(skin.inner ~= nil and db.showBorder)
            if skin.inner then button.fbInner:SetBackdropBorderColor(unpack(skin.inner)) end
        end
    end
    if button.fbBackground then button.fbBackground:SetColorTexture(unpack(skin.background)) end
    -- Grüner "Ausgerüstet"-Rand, Zuschnitt des Symbols
    if button.Border then button.Border:SetAlpha(db.showEquipped and 1 or 0) end
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    if icon then
        local crop = math.max(0, math.min(30, db.iconZoom or 4)) / 100
        icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        local inset = db.showBorder and skin.inset or 0
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
    UpdateStateTextures(button, icon)

    -- Abklingzeit: auf die Symbolfläche legen (nur außerhalb des Kampfes, der Rahmen hängt am geschützten Knopf);
    -- Zahlen in der Schrift der Knopftexte (ob Zahlen erscheinen, regelt die Blizzard-Einstellung)
    local cooldown = button.cooldown or button.Cooldown or (name and _G[name .. "Cooldown"])
    if cooldown then
        if icon and not InCombatLockdown() then
            cooldown:ClearAllPoints()
            cooldown:SetAllPoints(icon)
        end
        local countdown = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
        if countdown then SetTextFont(countdown, db.fontSize + 2) end
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

    -- Symbol eckig zuschneiden (Abstand zum Rand setzt der Stil in UpdateButtonLook)
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    if icon and button.IconMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, button.IconMask) end

    if not button.fbBorder then
        -- Hintergrund für leere Plätze und dünner Rand (Farben je nach Stil)
        local background = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        background:SetAllPoints()
        button.fbBackground = background

        local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        border:SetAllPoints()
        border:SetFrameLevel(button:GetFrameLevel() + 1)
        border:EnableMouse(false)
        button.fbBorder = border

        -- Blizzard setzt seine Grafiken bei manchen Aktualisierungen neu: danach wieder ausblenden bzw. anpassen
        if button.UpdateButtonArt then
            hooksecurefunc(button, "UpdateButtonArt", function(self)
                HideRegion(self.NormalTexture)
                HideRegion(self.SlotArt)
                HideRegion(self.SlotBackground)
                UpdateStateTextures(self, self.icon or self.Icon)
            end)
        end
        if button.UpdateHotkeys then
            hooksecurefunc(button, "UpdateHotkeys", UpdateButtonLook)
        end
        -- Tooltip des Knopfes nach Einstellung wieder ausblenden (nie bzw. nicht im Kampf)
        button:HookScript("OnEnter", function(self)
            local mode = ns.db.buttonTooltip
            if mode == "NEVER" or (mode == "NOCOMBAT" and InCombatLockdown()) then
                GameTooltip:Hide()
            end
            -- Stil "Forever": goldener Rand beim Darüberfahren
            if GetSkin().hoverGold and self.fbBorder then
                self.fbBorder:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
            end
        end)
        button:HookScript("OnLeave", function(self)
            if self.fbBorder then self.fbBorder:SetBackdropBorderColor(unpack(GetSkin().border)) end
        end)
    end
    UpdateButtonLook(button)

    -- Leere Plätze zeigen oder verstecken (nur außerhalb des Kampfes erlaubt)
    if button.SetShowGrid and not InCombatLockdown() then
        pcall(button.SetShowGrid, button, ns.db.showGrid, GRID_REASON)
    end
end

-- Nach Änderung von Texten, Schrift, Rand oder Zoom alle Knöpfe aktualisieren (geht auch im Kampf)
---------------------------------------------------------------------------
-- Mikromenü im Forever-Stil: Blizzards Hintergrund-Grafiken unsichtbar, darunter eine flache dunkle Fläche
-- mit 1-px-Rand (Farben wie der gewählte Knopf-Stil), beim Darüberfahren goldener Rand.
-- Nur Alpha, eigene Flächen und HookScript – keine Blizzard-Funktion wird ersetzt (kein taint).
---------------------------------------------------------------------------

local function MicroButtons()
    local list = {}
    local function Collect(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsObjectType("Button") then
                table.insert(list, child)
            elseif child == MicroMenu then
                Collect(child)
            end
        end
    end
    local container = MicroMenuContainer or MicroMenu
    if container then Collect(container) end
    return list
end

local function StyleMicroButton(button)
    if not button.fbMicroBorder then
        local background = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        background:SetAllPoints()
        button.fbMicroBackground = background
        local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
        border:SetAllPoints()
        border:SetFrameLevel(button:GetFrameLevel() + 1)
        border:EnableMouse(false)
        button.fbMicroBorder = border
        button:HookScript("OnEnter", function(self)
            if ns.db.showBorder then
                self.fbMicroBorder:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
            end
        end)
        button:HookScript("OnLeave", function(self)
            self.fbMicroBorder:SetBackdropBorderColor(unpack(GetSkin().border))
        end)
    end
    HideRegion(button.Background)
    HideRegion(button.PushedBackground)
    -- Schwarz-weiß: alle Grafiken des Knopfes (Symbol, Porträt, Hervorhebung) entsättigen
    local grey = ns.db.bars.micro.microGrey and true or false
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") and region ~= button.fbMicroBackground and region.SetDesaturated then
            region:SetDesaturated(grey)
        end
    end
    for _, child in ipairs({ button:GetChildren() }) do
        if child ~= button.fbMicroBorder then
            for _, region in ipairs({ child:GetRegions() }) do
                if region:IsObjectType("Texture") and region.SetDesaturated then region:SetDesaturated(grey) end
            end
        end
    end
    local skin = GetSkin()
    button.fbMicroBackground:SetColorTexture(unpack(skin.background))
    button.fbMicroBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = skin.size })
    button.fbMicroBorder:SetBackdropBorderColor(unpack(skin.border))
    button.fbMicroBorder:SetShown(ns.db.showBorder)
end

function ns.StyleMicroMenu()
    for _, button in ipairs(MicroButtons()) do StyleMicroButton(button) end
end

---------------------------------------------------------------------------
-- Eigenes Mikromenü: flache quadratische Knöpfe wie die Knöpfe in ForeverQuests mit eigenen schlichten Symbolen
-- (Media\Micro\*.tga, weiß – gold gefärbt, beim Darüberfahren weiß und goldener Rand).
-- Unsere Knöpfe sind nur die Optik: Blizzards echte Menüknöpfe liegen unsichtbar (Deckkraft 0) genau darüber und
-- bekommen den Klick selbst. So öffnet das Spiel seine Fenster wie gewohnt (manche, z. B. das Spielmenü, öffnen nur,
-- wenn die Maus wirklich über dem Blizzard-Knopf ist), Blizzards Tooltips bleiben, und es entsteht kein taint.
-- Auch ForeverSpellbook greift so von selbst (sein Knopf liegt über dem Zauberbuch-Knopf).
---------------------------------------------------------------------------

local MICRO_HEIGHT = 19 -- quadratisch: so breit wie hoch
local MICRO_ICON = 13
local MICRO_MAX = 16
local MICRO_ICON_PATH = "Interface\\AddOns\\ForeverBars\\Media\\Micro\\"
local MICRO_ICON_HOVER = { 1, 1, 1 } -- beim Darüberfahren weiß (sonst Gold)
-- Symbol je Blizzard-Knopf (Dateiname in Media\Micro; unbekannte Knöpfe: "Generic")
local MICRO_ICONS = {
    CharacterMicroButton = "Character", ProfessionMicroButton = "Professions", PlayerSpellsMicroButton = "Spells",
    SpellbookMicroButton = "Spells", TalentMicroButton = "Talents", AchievementMicroButton = "Achievements",
    QuestLogMicroButton = "Quests", GuildMicroButton = "Guild", SocialsMicroButton = "Social", LFDMicroButton = "Group",
    LFGMicroButton = "Group", PVPMicroButton = "PvP", CollectionsMicroButton = "Collections", EJMicroButton = "Journal",
    WorldMapMicroButton = "Map", StoreMicroButton = "Compass", MainMenuMicroButton = "Menu", HelpMicroButton = "Help",
    HousingMicroButton = "Housing",
}

-- Blizzards Menüknöpfe in ihrer Reihenfolge. Die Liste wird einmal gemerkt, denn nach dem Umhängen liegen die
-- Knöpfe nicht mehr im Blizzard-Mikromenü.
local microNames
local function BlizzardMicroButtons()
    if not microNames then
        local found = {}
        for _, button in ipairs(MicroButtons()) do
            if button:GetName() then table.insert(found, button) end
        end
        table.sort(found, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)
        if #found > 0 then
            microNames = {}
            for _, button in ipairs(found) do table.insert(microNames, button:GetName()) end
        end
    end
    local list = {}
    for _, name in ipairs(microNames or {}) do
        local button = _G[name]
        if button and button:IsShown() then table.insert(list, button) end
    end
    return list
end

-- Alle Blizzard-Menüknöpfe, auch die gerade versteckten (z. B. Shop, wenn er nicht verfügbar ist)
local function AllBlizzardMicroButtons()
    BlizzardMicroButtons() -- Namen merken
    local list = {}
    for _, name in ipairs(microNames or {}) do
        if _G[name] then table.insert(list, _G[name]) end
    end
    return list
end

-- Sichtbarer Knopf (nur Optik, nimmt keine Maus an)
local function GetOwnMicroButton(index, holder)
    local name = "ForeverBarsMicroButton" .. index
    local button = _G[name]
    if button then return button end
    button = CreateFrame("Frame", name, holder, "BackdropTemplate")
    button:SetSize(MICRO_HEIGHT, MICRO_HEIGHT)
    button:EnableMouse(false)
    ns.Style.SetFlat(button, COLOR.button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(MICRO_ICON, MICRO_ICON)
    button.icon:SetPoint("CENTER")
    return button
end

-- Dünner Rand um jeden Menüknopf: Farbe wie der Rand der Aktionsknöpfe (Knopf-Stil), beim Darüberfahren gold
local MICRO_BORDER = { 0.42, 0.42, 0.48, 1 }
local function SetMicroHover(own, hovered)
    if hovered then
        own:SetBackdropColor(unpack(COLOR.buttonHover))
        own:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
    else
        own:SetBackdropColor(unpack(COLOR.button))
        own:SetBackdropBorderColor(unpack(MICRO_BORDER))
    end
    -- Blizzards Symbole sind farbig und bleiben so; die eigenen (weißen) Ersatz-Symbole gold, beim Darüberfahren weiß
    if own.fbBlizzardIcon then
        own.icon:SetVertexColor(1, 1, 1)
        own.icon:SetAlpha(hovered and 1 or 0.9)
    elseif hovered then
        own.icon:SetVertexColor(unpack(MICRO_ICON_HOVER))
    else
        own.icon:SetVertexColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3])
    end
end

-- Symbol des Blizzard-Knopfes übernehmen (seine Grafik "-Up" aus dem Atlas, im Seitenverhältnis des Originals,
-- so hoch wie unser Knopf ohne Rand). Ohne Atlas-Grafik: eigenes Ersatz-Symbol aus Media\Micro.
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local portraitButtons = {}
local portraitEvents
-- Charakter-Knopf: Blizzard zeigt dort kein Symbol, sondern das runde Porträt der Spielfigur (SetPortraitTexture)
local function SetMicroPortrait(own)
    if not own.fbPortraitMask then
        own.fbPortraitMask = own:CreateMaskTexture()
        own.fbPortraitMask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        own.fbPortraitMask:SetAllPoints(own.icon)
    end
    own.icon:SetTexCoord(0, 1, 0, 1)
    own.icon:SetSize(MICRO_HEIGHT - 4, MICRO_HEIGHT - 4)
    own.icon:AddMaskTexture(own.fbPortraitMask)
    SetPortraitTexture(own.icon, "player")
    own.fbBlizzardIcon = true
    own.fbPortrait = true
    portraitButtons[own] = true
    if not portraitEvents then
        -- wie Blizzards Knopf: Porträt bei Änderungen der Spielfigur neu zeichnen
        portraitEvents = CreateFrame("Frame")
        portraitEvents:RegisterEvent("PORTRAITS_UPDATED")
        portraitEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        portraitEvents:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player")
        portraitEvents:SetScript("OnEvent", function()
            for button in pairs(portraitButtons) do
                if button.fbPortrait then SetPortraitTexture(button.icon, "player") end
            end
        end)
    end
end

local function SetMicroIcon(own, blizzard)
    if blizzard == _G.CharacterMicroButton then
        SetMicroPortrait(own)
        return
    end
    -- anderer Knopf auf diesem Platz als zuvor: Porträt-Maske wieder entfernen
    if own.fbPortrait then
        own.fbPortrait = false
        if own.fbPortraitMask then own.icon:RemoveMaskTexture(own.fbPortraitMask) end
    end
    local normal = blizzard.GetNormalTexture and blizzard:GetNormalTexture()
    local atlas = normal and normal.GetAtlas and normal:GetAtlas()
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if info and info.width and info.height and info.height > 0 then
        own.icon:SetAtlas(atlas)
        local height = MICRO_HEIGHT - 2
        own.icon:SetSize(math.min(MICRO_HEIGHT - 2, height * info.width / info.height), height)
        own.fbBlizzardIcon = true
    else
        own.icon:SetTexture(MICRO_ICON_PATH .. (MICRO_ICONS[blizzard:GetName()] or "Generic"))
        own.icon:SetTexCoord(0, 1, 0, 1)
        own.icon:SetSize(MICRO_ICON, MICRO_ICON)
        own.fbBlizzardIcon = false
    end
end

-- Blizzard-Knopf unsichtbar über unseren Knopf legen und dort festhalten (Blizzards Mikromenü ordnet seine Knöpfe
-- sonst gelegentlich neu an). Nur mitgehört über hooksecurefunc/HookScript; die Menüknöpfe sind nicht geschützt.
local function OverlayBlizzardButton(blizzard, own, holder)
    blizzard.fbOwn = own
    blizzard.fbOverlayHolder = holder
    local function Place(self)
        if self.fbPlacing or not self.fbOwn or not self.fbOverlayHolder then return end
        if InCombatLockdown() and self:IsProtected() then return end
        self.fbPlacing = true
        if self:GetParent() ~= self.fbOverlayHolder then self:SetParent(self.fbOverlayHolder) end
        self:ClearAllPoints()
        self:SetAllPoints(self.fbOwn)
        self:SetFrameLevel(self.fbOwn:GetFrameLevel() + 5)
        if self:GetAlpha() ~= 0 then self:SetAlpha(0) end
        self.fbPlacing = false
    end
    if not blizzard.fbOverlayHooked then
        blizzard.fbOverlayHooked = true
        hooksecurefunc(blizzard, "SetPoint", Place)
        hooksecurefunc(blizzard, "SetParent", Place)
        hooksecurefunc(blizzard, "SetAlpha", function(self, alpha)
            if alpha ~= 0 and self.fbOwn and not self.fbPlacing then Place(self) end
        end)
        -- Darüberfahren: unsere Optik reagiert, Blizzards Tooltip bleibt
        blizzard:HookScript("OnEnter", function(self) if self.fbOwn then SetMicroHover(self.fbOwn, true) end end)
        blizzard:HookScript("OnLeave", function(self) if self.fbOwn then SetMicroHover(self.fbOwn, false) end end)
        -- Wechselt Blizzard die Grafik (z. B. Gilden-Wappen, Hinweis-Zustände), unser Symbol mitziehen
        if blizzard.SetNormalAtlas then
            hooksecurefunc(blizzard, "SetNormalAtlas", function(self)
                if self.fbOwn then
                    SetMicroIcon(self.fbOwn, self)
                    SetMicroHover(self.fbOwn, self:IsMouseOver())
                end
            end)
        end
    end
    Place(blizzard)
end

-- Eigene Knöpfe anordnen (nur außerhalb des Kampfes); "Knöpfe pro Reihe" bricht um, "Abstand" wie bei Leisten
local function LayoutOwnMicro(def, cfg, holder)
    local buttons = BlizzardMicroButtons() -- vor dem Umhängen merken (siehe oben)
    -- Blizzards Mikromenü bleibt sichtbar in unserem Halter, nur mit Deckkraft 0. Wichtig: Beim Umhängen eines Knopfes
    -- ordnet Blizzard das Mikromenü neu an und fragt dabei nach den Bildschirmpositionen der übrigen Knöpfe – liegt
    -- das Mikromenü im unsichtbaren Ablageort, gibt es keine Positionen (Fehler "compare two nil values").
    local blizzardMenu = FindFrame(def.frames)
    if blizzardMenu then
        blizzardMenu.fbHolder = holder
        if blizzardMenu:GetParent() ~= holder then blizzardMenu:SetParent(holder) end
        blizzardMenu.fbPositioning = true
        blizzardMenu:ClearAllPoints()
        blizzardMenu:SetPoint("CENTER", holder, "CENTER")
        blizzardMenu.fbPositioning = false
        blizzardMenu:SetAlpha(0)
    end
    -- Versteckte Blizzard-Knöpfe ebenfalls aus dem Mikromenü holen (unsichtbar im Halter). Ist das Mikromenü leer,
    -- bricht Blizzards Anordnung sauber ab. Zeigt Blizzard einen davon später, wird neu angeordnet.
    for _, blizzard in ipairs(AllBlizzardMicroButtons()) do
        if not blizzard:IsShown() then
            blizzard.fbOwn = nil
            if blizzard:GetParent() ~= holder then blizzard:SetParent(holder) end
            blizzard:SetAlpha(0)
            if not blizzard.fbShowHooked then
                blizzard.fbShowHooked = true
                hooksecurefunc(blizzard, "Show", function() ns.RequestLayout() end)
            end
        end
    end
    -- Abstand 0 = Knöpfe stoßen aneinander, ihre 1-px-Ränder liegen übereinander (eine feine Linie)
    local gap = math.max(0, cfg.spacing or 0) - 1
    local perRow = math.max(1, cfg.perRow or MICRO_MAX)
    local x, y, width, used = 0, 0, 0, 0
    for index, blizzard in ipairs(buttons) do
        if index > MICRO_MAX then break end
        local own = GetOwnMicroButton(index, holder)
        own:SetParent(holder)
        SetMicroIcon(own, blizzard)
        if (index - 1) % perRow == 0 and index > 1 then
            x, y = 0, y - MICRO_HEIGHT - gap
        end
        own:ClearAllPoints()
        own:SetPoint("TOPLEFT", holder, "TOPLEFT", x, y)
        own:Show()
        SetMicroHover(own, false)
        OverlayBlizzardButton(blizzard, own, holder)
        x = x + MICRO_HEIGHT + gap
        width = math.max(width, x - gap)
        used = index
    end
    for index = used + 1, MICRO_MAX do
        local own = _G["ForeverBarsMicroButton" .. index]
        if own then own:Hide() end
    end
    -- (früherer Neu-laden-Knopf am Ende: entfernt)
    if _G.ForeverBarsMicroReload then _G.ForeverBarsMicroReload:Hide() end
    holder:SetSize(math.max(1, width), math.max(MICRO_HEIGHT, -y + MICRO_HEIGHT))
end

-- Zu Blizzards Mikromenü zurück: eigene Knöpfe ausblenden. Blizzards Knöpfe kommen nach dem Neuladen zurück
-- (sie liegen bis dahin unsichtbar über den ausgeblendeten Knöpfen)
local function HideOwnMicro()
    local wasOwn = false
    for index = 1, MICRO_MAX do
        local own = _G["ForeverBarsMicroButton" .. index]
        if own then
            if own:IsShown() then wasOwn = true end
            own:Hide()
        end
    end
    if wasOwn then ns.Print(L("MICRO_RELOAD")) end
end

function ns.UpdateAllButtons()
    for _, def in ipairs(ns.BAR_DEFS) do
        for _, button in ipairs(GetAllButtons(def)) do
            if button.fbBorder then UpdateButtonLook(button) end
        end
    end
    ns.StyleMicroMenu()
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
-- Berufeleiste: eigene geschützte Knöpfe, belegt mit den Berufen des Charakters
-- (aktive Berufs-Fähigkeiten aus dem Zauberbuch, z. B. Schmelzen, Kräutersuche; sonst der Beruf selbst)
---------------------------------------------------------------------------

local PROF_COUNT = 12
local FOOD_COUNT = 18

-- Berufe- und Verpflegungsleiste: frei anordnen wie eine Aktionsleiste. Jede Leiste hat feste Plätze
-- (cfg.slots[Platz] = Zauber bzw. Gegenstand); Knopf i zeigt Platz i, darum gehören Tastenbelegungen immer zu
-- einem Platz. Neues wird automatisch auf freie Plätze eingetragen (Berufe: alle Berufs-Zauber, Verpflegung:
-- Essen, Getränke, Tränke, Elixiere, Fläschchen aus den Taschen). Shift + ziehen tauscht Plätze; daneben loslassen
-- entfernt (cfg.excluded – wird dann nicht wieder automatisch eingetragen). Hineinziehen: in die Berufeleiste nur
-- Berufs-Zauber, in die Verpflegungsleiste beliebige Gegenstände.
local SLOT_BARS = {
    prof = { prefix = "ForeverBarsProfButton", count = PROF_COUNT, cursorKind = "spell" },
    food = { prefix = "ForeverBarsFoodButton", count = FOOD_COUNT, cursorKind = "item" },
}

-- Zauber an einer Stelle im Zauberbuch (neue und alte Schnittstelle); nur aktive Zauber
local function SpellBookSpell(slot)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
        local info = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
        if info and info.spellID and not info.isPassive then return info.spellID, info.iconID end
    elseif GetSpellBookItemInfo then
        local kind, spellID = GetSpellBookItemInfo(slot, BOOKTYPE_SPELL or "spell")
        local passive = IsPassiveSpell and IsPassiveSpell(slot, BOOKTYPE_SPELL or "spell")
        if kind == "SPELL" and spellID and not passive then return spellID end
    end
end

local function SpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
    return GetSpellTexture and GetSpellTexture(spellID)
end

---------------------------------------------------------------------------
-- Berufe: alle aktiven Berufs-Zauber des Charakters (Hauptberufe, Archäologie, Angeln, Kochen, Erste Hilfe),
-- je Beruf zuerst das Berufsfenster, dann die Fertigkeiten (Entzaubern, Schmelzen …)
---------------------------------------------------------------------------

local FISHING_SLOT = 4 -- GetProfessions liefert Angeln an 4. Stelle

local function ProfessionSpells()
    local list = {}
    if not GetProfessions or not GetProfessionInfo then return list end
    local indices = { GetProfessions() }
    local seen = {}
    for i = 1, 6 do
        local index = indices[i]
        if index then
            local name, icon, _, _, numSpells, offset = GetProfessionInfo(index)
            local spells = {}
            for s = 1, numSpells or 0 do
                local spellID, spellIcon = SpellBookSpell((offset or 0) + s)
                if spellID and not seen[spellID] then
                    seen[spellID] = true
                    table.insert(spells, { spell = spellID, icon = spellIcon or SpellIcon(spellID) or icon })
                end
            end
            if i == FISHING_SLOT then
                -- Angeln: das Fenster trägt ein anderes Symbol als der Beruf (die Fertigkeit "Auswerfen" dasselbe)
                table.sort(spells, function(a, b) return (a.icon ~= icon) and (b.icon == icon) end)
            end
            -- Ohne eigene Fähigkeit im Zauberbuch: den Beruf über seinen Namen öffnen
            if #spells == 0 and name then spells = { { spell = name, icon = icon } } end
            for _, entry in ipairs(spells) do table.insert(list, entry) end
        end
    end
    return list
end

-- Berufs-Zauber zu einem Zauber (oder nil, wenn es kein Berufs-Zauber des Charakters ist)
local function ProfessionSpell(spell)
    for _, entry in ipairs(ProfessionSpells()) do
        if entry.spell == spell then return entry end
    end
end

---------------------------------------------------------------------------
-- Verpflegung: Verbrauchbares aus den Taschen
---------------------------------------------------------------------------

-- Gegenstandsart "Verbrauchbar" (0) und die Unterarten, die automatisch kommen:
-- 5 = Speis & Trank, 1 = Trank, 2 = Elixier, 3 = Fläschchen
local CONSUMABLE_CLASS = 0
local AUTO_SUBCLASSES = { [5] = 1, [3] = 2, [2] = 3, [1] = 4 } -- Reihenfolge beim automatischen Eintragen

local function ItemInfoInstant(itemID)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(itemID) end
    return GetItemInfoInstant and GetItemInfoInstant(itemID)
end

local function ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) end
    return GetItemCount and GetItemCount(itemID) or 0
end

local function ItemIcon(itemID)
    return select(5, ItemInfoInstant(itemID))
end

-- Alle Gegenstände in den Taschen (inBags) und die Verbrauchbaren für das automatische Eintragen (auto)
local function BagContents()
    local inBags, auto = {}, {}
    local numSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local itemAt = C_Container and C_Container.GetContainerItemID or GetContainerItemID
    if not numSlots or not itemAt then return inBags, auto end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, numSlots(bag) or 0 do
            local itemID = itemAt(bag, slot)
            if itemID and not inBags[itemID] then
                inBags[itemID] = true
                local _, _, _, _, _, classID, subclassID = ItemInfoInstant(itemID)
                local order = classID == CONSUMABLE_CLASS and AUTO_SUBCLASSES[subclassID]
                if order then
                    local level = 0
                    if C_Item and C_Item.GetItemInfo then
                        level = select(5, C_Item.GetItemInfo(itemID)) or 0 -- benötigte Stufe
                    end
                    table.insert(auto, { item = itemID, order = order, level = level })
                end
            end
        end
    end
    -- Erst Essen/Trinken, dann Fläschchen, Elixiere, Tränke; jeweils höchste Stufe zuerst
    table.sort(auto, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.level ~= b.level then return a.level > b.level end
        return a.item < b.item
    end)
    return inBags, auto
end

---------------------------------------------------------------------------
-- Plätze
---------------------------------------------------------------------------

local function SlotConfig(key)
    local cfg = ns.db.bars[key]
    cfg.slots = cfg.slots or {}         -- [Platz] = Zauber-ID/Name bzw. Gegenstands-ID
    cfg.slotsAuto = cfg.slotsAuto or {} -- [Platz] = true, wenn automatisch eingetragen (verschwindet mit dem Gegenstand)
    cfg.excluded = cfg.excluded or {}   -- herausgezogen: nicht wieder automatisch eintragen
    -- Ältere Stände: die frühere Liste der entfernten Knöpfe übernehmen, alte Reihenfolgen vergessen
    for _, oldKey in ipairs({ "foodExcluded", "profExcluded" }) do
        if type(cfg[oldKey]) == "table" then
            for value in pairs(cfg[oldKey]) do cfg.excluded[value] = true end
            cfg[oldKey] = nil
        end
    end
    cfg.foodOrder, cfg.profOrder = nil, nil
    return cfg
end

local function SlotCount(key, cfg)
    return math.max(1, math.min(SLOT_BARS[key].count, cfg.buttons or SLOT_BARS[key].count))
end

local function FindSlot(cfg, value)
    for slot, stored in pairs(cfg.slots) do
        if stored == value then return slot end
    end
end

local function FreeSlot(cfg, count)
    for slot = 1, count do
        if cfg.slots[slot] == nil then return slot end
    end
end

local function SetSlot(cfg, slot, value, auto)
    cfg.slots[slot] = value
    cfg.slotsAuto[slot] = (value ~= nil and auto) and true or nil
end

-- Automatisch auffüllen: Berufe – verlernte entfernen, neue auf freie Plätze; Verpflegung – automatisch
-- eingetragene, die nicht mehr in den Taschen sind, entfernen, neue Verbrauchbare auf freie Plätze
local function FillSlots(key)
    local cfg = SlotConfig(key)
    local count = SlotCount(key, cfg)
    if key == "prof" then
        local spells = ProfessionSpells()
        local known = {}
        for _, entry in ipairs(spells) do known[entry.spell] = true end
        for slot, value in pairs(cfg.slots) do
            if not known[value] then SetSlot(cfg, slot, nil) end
        end
        for _, entry in ipairs(spells) do
            if not cfg.excluded[entry.spell] and not FindSlot(cfg, entry.spell) then
                local slot = FreeSlot(cfg, count)
                if slot then SetSlot(cfg, slot, entry.spell, true) end
            end
        end
    else
        local inBags, auto = BagContents()
        for slot, value in pairs(cfg.slots) do
            if cfg.slotsAuto[slot] and not inBags[value] then SetSlot(cfg, slot, nil) end
        end
        for _, entry in ipairs(auto) do
            if not cfg.excluded[entry.item] and not FindSlot(cfg, entry.item) then
                local slot = FreeSlot(cfg, count)
                if slot then SetSlot(cfg, slot, entry.item, true) end
            end
        end
    end
    return cfg, count
end

-- Was liegt auf einem Platz? (Tabelle für den Knopf: spell oder item, icon)
local function SlotEntry(key, value)
    if value == nil then return nil end
    if key == "prof" then
        local entry = ProfessionSpell(value)
        return { spell = value, icon = entry and entry.icon or (type(value) == "number" and SpellIcon(value)) }
    end
    return { item = value, icon = ItemIcon(value) }
end

-- Darf das in die Leiste? Berufe: nur Berufs-Zauber; Verpflegung: jeder Gegenstand
local function Accepts(key, value)
    if key == "prof" then
        if ProfessionSpell(value) then return true end
        ns.Print(L("PROF_NOT_FITTING"))
        return false
    end
    return value ~= nil
end

-- Hineingezogen bzw. verschoben: auf den Zielplatz legen. Lag der Wert schon woanders, tauschen die Plätze;
-- war der Zielplatz belegt, wandert der bisherige Wert auf den ersten freien Platz (sonst gilt er als entfernt).
function ns.SlotPlace(key, value, target)
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    if not Accepts(key, value) then return end
    local cfg = SlotConfig(key)
    local count = SlotCount(key, cfg)
    target = math.max(1, math.min(count, target or FreeSlot(cfg, count) or count))
    cfg.excluded[value] = nil
    local from = FindSlot(cfg, value)
    local displaced = cfg.slots[target]
    if from == target then return end
    if from then
        -- Tauschen (beide gelten danach als selbst angeordnet)
        SetSlot(cfg, from, displaced, false)
    elseif displaced ~= nil then
        local free = FreeSlot(cfg, count)
        if free and free ~= target then
            SetSlot(cfg, free, displaced, cfg.slotsAuto[target])
        else
            cfg.excluded[displaced] = true
        end
    end
    SetSlot(cfg, target, value, false)
    ns.RequestLayout()
end

-- Herausgezogen: Platz leeren und nicht wieder automatisch eintragen
function ns.SlotRemove(key, slot)
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    local cfg = SlotConfig(key)
    local value = cfg.slots[slot]
    if value == nil then return end
    cfg.excluded[value] = true
    SetSlot(cfg, slot, nil)
    ns.RequestLayout()
end

-- Alles zurück auf automatisch: Plätze leeren, Entferntes wieder zulassen
function ns.SlotReset(key)
    local cfg = SlotConfig(key)
    wipe(cfg.slots)
    wipe(cfg.slotsAuto)
    wipe(cfg.excluded)
    ns.RequestLayout()
end
ns.FoodResetChoices = function() ns.SlotReset("food") end
ns.ProfResetChoices = function() ns.SlotReset("prof") end

---------------------------------------------------------------------------
-- Knöpfe
---------------------------------------------------------------------------

local function UpdateSlotButton(button)
    local entry = button.fbEntry
    if not entry then
        button.cooldown:Clear()
        if button.Count then button.Count:SetText("") end
        return
    end
    if entry.item then
        -- Gegenstand: Anzahl in den Taschen; ist keiner mehr da, grau (wie auf einer Aktionsleiste)
        local count = ItemCount(entry.item)
        button.Count:SetText(count)
        button.icon:SetDesaturated(count == 0)
        local getCooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown
        if getCooldown then
            -- Werte unverändert an die Abklingzeit-Anzeige weiterreichen (keine eigene Rechnung)
            local start, duration = getCooldown(entry.item)
            if start then pcall(button.cooldown.SetCooldown, button.cooldown, start, duration) end
        end
    elseif type(entry.spell) == "number" and C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(entry.spell)
        if info then pcall(button.cooldown.SetCooldown, button.cooldown, info.startTime, info.duration) end
    else
        button.cooldown:Clear()
    end
end

-- Leere Plätze zeigen: bei "Leere Plätze zeigen", beim Verschieben und solange etwas Passendes am Mauszeiger hängt
local slotDragActive = false
local function ShowEmptySlots(key)
    return ns.db.showGrid or slotDragActive or (GetCursorInfo() == SLOT_BARS[key].cursorKind)
end

-- Raster der Berufe-/Verpflegungsleiste: mindestens 2 (Berufe) bzw. 3 Reihen (Verpflegung); die Leiste wächst
-- nach der Seite (Spalte für Spalte, so behält jeder Knopf seinen Platz). Erst wenn "Knöpfe pro Reihe" voll ist,
-- kommt eine Reihe dazu.
local SLOT_MIN_ROWS = { prof = 2, food = 3 }
local function SlotRows(key, cfg, count)
    local perRow = math.max(1, cfg.perRow or count)
    return math.max(1, math.min(count, math.max(SLOT_MIN_ROWS[key] or 2, math.ceil(count / perRow))))
end
-- Spalte und Reihe (ab 0) eines Platzes
local function SlotCell(index, rows)
    return math.floor((index - 1) / rows), (index - 1) % rows
end

-- Wie viele Plätze die Leiste gerade zeigt: bis zum letzten belegten Platz (die Leiste wächst mit; "Anzahl
-- Knöpfe" ist die Höchstzahl), beim Hineinziehen/Verschieben ein freier Platz mehr. Mindestgröße, damit der
-- Titel über der Leiste Platz hat: Berufe 2×2, Verpflegung 3×3; aufgerundet auf volle Spalten.
local SLOT_MIN = { prof = 4, food = 9 } -- Berufe 2 x 2, Verbrauchbar 3 x 3
local slotShown = {}
local function ShownSlotCount(key, cfg, capacity)
    local last = 0
    for slot in pairs(cfg.slots) do
        if slot <= capacity and slot > last then last = slot end
    end
    if slotDragActive or GetCursorInfo() == SLOT_BARS[key].cursorKind then last = last + 1 end
    local count = math.max(SLOT_MIN[key] or 2, last)
    local rows = SlotRows(key, cfg, count)
    return math.max(1, math.min(capacity, math.ceil(count / rows) * rows))
end

-- Knöpfe belegen (nur außerhalb des Kampfes); Rückgabe: Anzahl gezeigter Plätze
function ns.AssignSlotButtons(key)
    local info = SLOT_BARS[key]
    local cfg, capacity = FillSlots(key)
    local count = ShownSlotCount(key, cfg, capacity)
    slotShown[key] = count
    local showEmpty = ShowEmptySlots(key)
    for i = 1, info.count do
        local button = _G[info.prefix .. i]
        if button then
            local entry = i <= count and SlotEntry(key, cfg.slots[i]) or nil
            button.fbEntry = entry
            button.fbSlotIndex = i
            if key == "prof" then
                button:SetAttribute("type", entry and "spell" or nil)
                button:SetAttribute("spell", entry and entry.spell or nil)
            else
                button:SetAttribute("type", entry and "item" or nil)
                button:SetAttribute("item", entry and ("item:" .. entry.item) or nil)
            end
            button.icon:SetTexture(entry and entry.icon or nil)
            button.icon:SetDesaturated(false)
            button:SetShown(i <= count and (entry ~= nil or showEmpty))
            UpdateSlotButton(button)
        end
    end
    return count
end

-- Leere Plätze ein-/ausblenden (z. B. Gegenstand am Mauszeiger), ohne neu anzuordnen
function ns.UpdateEmptySlots()
    if InCombatLockdown() then return end
    for key, info in pairs(SLOT_BARS) do
        local count = slotShown[key] or SlotCount(key, ns.db.bars[key])
        local showEmpty = ShowEmptySlots(key)
        for i = 1, math.min(count, info.count) do
            local button = _G[info.prefix .. i]
            if button and not button.fbEntry and button:GetParent() ~= hiddenParent then button:SetShown(showEmpty) end
        end
    end
end

function ns.UpdateProfessionCooldowns()
    for i = 1, PROF_COUNT do
        local button = _G["ForeverBarsProfButton" .. i]
        if button and button.fbEntry then UpdateSlotButton(button) end
    end
end

function ns.UpdateFoodButtons()
    for i = 1, FOOD_COUNT do
        local button = _G["ForeverBarsFoodButton" .. i]
        if button and button.fbEntry then UpdateSlotButton(button) end
    end
end

-- Taschen geändert: neu belegen, wenn sich die Verbrauchbaren geändert haben, sonst nur Anzahl und Abklingzeit
local bagSignature = ""
function ns.OnBagsChanged()
    local _, auto = BagContents()
    local ids = {}
    for _, entry in ipairs(auto) do table.insert(ids, entry.item) end
    local signature = table.concat(ids, ",")
    if signature ~= bagSignature then
        bagSignature = signature
        ns.RequestLayout() -- im Kampf erst danach (geschützte Knöpfe)
    end
    ns.UpdateFoodButtons()
end

-- Eigener geschützter Knopf (Berufe, Verpflegung): Symbol, Abklingzeit, Anzahl, Tastenbelegung, Tooltip
local function CreateOwnButton(name, showTooltip)
    local button = CreateFrame("Button", name, hiddenParent, "SecureActionButtonTemplate")
    button:SetSize(ACTION_SIZE, ACTION_SIZE)
    -- Beide Richtungen anmelden: welche auslöst, regelt die Blizzard-Einstellung "Beim Drücken auslösen"
    button:RegisterForClicks("AnyUp", "AnyDown")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    button:SetPushedTexture("Interface\\Buttons\\WHITE8x8")
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.Count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- Tastenbelegung (Text setzt UpdateOwnHotkeys; Schrift und Platz wie bei den Aktionsknöpfen)
    button.HotKey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    button.HotKey:SetPoint("TOPRIGHT", -2, -3)
    button:SetScript("OnEnter", function(self)
        local mode = ns.db.buttonTooltip
        if mode == "NEVER" or (mode == "NOCOMBAT" and InCombatLockdown()) or not self.fbEntry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        showTooltip(self.fbEntry)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    -- Shift-Klick wirkt nichts (sonst würde man beim Verschieben zaubern/essen); Shift-Ziehen verschiebt
    button:SetAttribute("shift-type1", "fbnone")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStop", function(self) ns.StopOwnDrag(self) end)
    return button
end

function ns.CreateProfessionButtons()
    for i = 1, PROF_COUNT do
        local name = "ForeverBarsProfButton" .. i
        if not _G[name] then
            local button = CreateOwnButton(name, function(entry)
                if type(entry.spell) == "number" then
                    GameTooltip:SetSpellByID(entry.spell)
                else
                    GameTooltip:SetText(entry.spell)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("PROF_TIP_MOVE"), 0.6, 0.6, 0.6)
                GameTooltip:AddLine(L("SLOT_TIP_MOVE"), 0.6, 0.6, 0.6)
            end)
            -- Shift + ziehen: verschieben/entfernen; normales Ziehen legt den Zauber auf eine Aktionsleiste
            button:SetScript("OnDragStart", function(self)
                local entry = self.fbEntry
                if not entry or InCombatLockdown() then return end
                if IsShiftKeyDown() then
                    ns.StartOwnDrag("prof", self)
                elseif C_Spell and C_Spell.PickupSpell then
                    C_Spell.PickupSpell(entry.spell)
                elseif PickupSpell then
                    PickupSpell(entry.spell)
                end
            end)
        end
    end
end

-- Tastenbelegung auf eigenen Knöpfen anzeigen (belegt über Blizzards Tastaturbelegung > AddOns)
function ns.UpdateOwnHotkeys()
    for i = 1, FOOD_COUNT do
        local button = _G["ForeverBarsFoodButton" .. i]
        if button then
            local key = GetBindingKey and GetBindingKey("CLICK ForeverBarsFoodButton" .. i .. ":LeftButton")
            button.HotKey:SetText(key and GetBindingText and ns.ShortKey(GetBindingText(key, true)) or "")
        end
    end
    if ns.UpdateMarkHotkeys then ns.UpdateMarkHotkeys() end
end

-- Hineinziehen: Fläche über einer Leiste, nur sichtbar, solange etwas Passendes am Mauszeiger hängt
-- (Verpflegung: Gegenstand, Berufe: Zauber). Sie fängt auch Klicks ab, damit dabei nichts benutzt wird.
-- Der Platz ergibt sich aus der Mausposition.
local catchers = {} -- [Leiste] = { frame, kind }
local catcherWatcher

-- Platz unter dem Mauszeiger (ab 1)
local function DropSlot(key)
    local holder = holders[key]
    if not holder or not holder:GetLeft() then return nil end
    local cfg = ns.db.bars[key]
    local scale = holder:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local step = ACTION_SIZE + ns.ButtonGap(cfg)
    local col = cfg.growX == "LEFT" and math.floor((holder:GetRight() - x) / step) or math.floor((x - holder:GetLeft()) / step)
    local row = cfg.growY == "UP" and math.floor((y - holder:GetBottom()) / step) or math.floor((holder:GetTop() - y) / step)
    -- Raster wie beim Anordnen (siehe SlotRows/SlotCell)
    local count = slotShown[key] or SlotCount(key, cfg)
    local rows = SlotRows(key, cfg, count)
    local columns = math.ceil(count / rows)
    col = math.max(0, math.min(columns - 1, col))
    row = math.max(0, math.min(rows - 1, row))
    return math.min(count, col * rows + row + 1)
end

local lastCursorKind
local function UpdateCatchers()
    local kind = GetCursorInfo()
    -- Zauber am Mauszeiger (bzw. wieder weg): Berufeleiste bekommt einen freien Platz dazu (bzw. wieder weg)
    if (kind == "spell") ~= (lastCursorKind == "spell") and not InCombatLockdown() then ns.RequestLayout() end
    lastCursorKind = kind
    for key, catcher in pairs(catchers) do
        local holder = holders[key]
        catcher.frame:SetShown(kind == catcher.kind and not InCombatLockdown() and holder ~= nil
            and holder:IsVisible() and ns.db.bars[key].enabled)
    end
    ns.UpdateEmptySlots()
end

local function CreateCatcher(key)
    local holder = holders[key]
    if catchers[key] or not holder then return end
    local kind = SLOT_BARS[key].cursorKind
    local frame = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", -2, 2)
    frame:SetPoint("BOTTOMRIGHT", 2, -2)
    frame:SetFrameLevel(holder:GetFrameLevel() + 20) -- über den Knöpfen
    frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.8)
    frame:EnableMouse(true)
    local function Drop()
        local cursorKind, a, _, d = GetCursorInfo()
        if cursorKind ~= kind then return end
        ClearCursor() -- Gegenstand bleibt in der Tasche, Zauber im Zauberbuch
        local value = cursorKind == "spell" and d or a
        if value then ns.SlotPlace(key, value, DropSlot(key)) end
    end
    frame:SetScript("OnReceiveDrag", Drop)
    frame:SetScript("OnMouseUp", Drop)
    frame:Hide()
    catchers[key] = { frame = frame, kind = kind }
    if not catcherWatcher then
        catcherWatcher = CreateFrame("Frame")
        catcherWatcher:RegisterEvent("CURSOR_CHANGED")
        catcherWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        catcherWatcher:SetScript("OnEvent", UpdateCatchers)
    end
end

-- Verschieben wie auf Aktionsleisten: Shift + ziehen nimmt den Knopf auf (ein Symbol folgt dem Mauszeiger).
-- Loslassen auf einem Platz der Leiste = dorthin (tauscht), loslassen daneben = entfernen.
local dragIcon, dragState

local function CursorOverHolder(key)
    local holder = holders[key]
    return holder ~= nil and holder:IsVisible() and holder:IsMouseOver(4, -4, -4, 4)
end

function ns.StartOwnDrag(key, button)
    if InCombatLockdown() or not button.fbEntry then return end
    dragState = { key = key, button = button, slot = button.fbSlotIndex,
                  value = button.fbEntry.spell or button.fbEntry.item }
    if not dragIcon then
        dragIcon = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        dragIcon:SetSize(30, 30)
        dragIcon:SetFrameStrata("TOOLTIP")
        ns.Style.SetFlat(dragIcon, COLOR.background, { COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1 })
        dragIcon.icon = dragIcon:CreateTexture(nil, "ARTWORK")
        dragIcon.icon:SetPoint("TOPLEFT", 1, -1)
        dragIcon.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        dragIcon:EnableMouse(false)
        dragIcon:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end)
    end
    dragIcon.icon:SetTexture(button.icon:GetTexture())
    dragIcon:Show()
    button:SetAlpha(0.35)
    slotDragActive = true
    ns.UpdateEmptySlots() -- leere Plätze als Ziel zeigen
    if key == "prof" then ns.RequestLayout() end -- Berufeleiste: ein freier Platz mehr zum Ablegen
end

function ns.StopOwnDrag(button)
    local state = dragState
    dragState = nil
    slotDragActive = false
    if dragIcon then dragIcon:Hide() end
    button:SetAlpha(1)
    if not state or state.button ~= button then
        ns.UpdateEmptySlots()
        ns.RequestLayout()
        return
    end
    if CursorOverHolder(state.key) then
        ns.SlotPlace(state.key, state.value, DropSlot(state.key))
    else
        ns.SlotRemove(state.key, state.slot)
    end
    ns.UpdateEmptySlots()
    ns.RequestLayout() -- den freien Platz vom Ziehen wieder entfernen
end

function ns.CreateFoodButtons()
    for i = 1, FOOD_COUNT do
        local name = "ForeverBarsFoodButton" .. i
        if not _G[name] then
            local button = CreateOwnButton(name, function(entry)
                GameTooltip:SetItemByID(entry.item)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L("SLOT_TIP_MOVE"), 0.6, 0.6, 0.6)
                GameTooltip:AddLine(L("FOOD_TIP_ADD"), 0.6, 0.6, 0.6)
            end)
            button:SetScript("OnDragStart", function(self)
                if IsShiftKeyDown() then ns.StartOwnDrag("food", self) end
            end)
        end
    end
    ns.UpdateOwnHotkeys()
end

---------------------------------------------------------------------------
-- Leuchten bei Procs: Blizzard entscheidet, welcher Knopf leuchtet (ShowAlert/HideAlert);
-- ForeverBars zeigt dazu wahlweise einen goldenen pulsierenden Rahmen im eigenen Stil
-- oder lässt Blizzards Leuchten stehen. Es wird nichts selbst berechnet.
---------------------------------------------------------------------------

-- Stile des Leuchtens (alle eigenen in Gold, der einzigen Akzentfarbe). "BLIZZARD" lässt Blizzards
-- Leuchten stehen; für den Testmodus gibt es davon eine eigene Nachbildung.
ns.GLOW_STYLES = {
    { value = "FOREVER", textKey = "GLOW_FOREVER" },   -- goldener Rahmen, pulsierend
    { value = "SOFT", textKey = "GLOW_SOFT" },         -- weicher goldener Schein um den Knopf
    { value = "PIXEL", textKey = "GLOW_PIXEL" },       -- feine goldene Linie, schnell blinkend
    { value = "CORNERS", textKey = "GLOW_CORNERS" },   -- goldene Ecken
    { value = "FLASH", textKey = "GLOW_FLASH" },       -- Symbol blitzt hell auf
    { value = "BLIZZARD", textKey = "GLOW_BLIZZARD" },
    { value = "OFF", textKey = "GLOW_OFF" },
}

local BLIZZARD_PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function GoldTexture(parent, layer)
    local texture = parent:CreateTexture(nil, layer or "OVERLAY")
    texture:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)
    return texture
end

local function GetGlow(button)
    if button.fbGlow then return button.fbGlow end
    local glow = CreateFrame("Frame", nil, button, "BackdropTemplate")
    glow:SetAllPoints()
    glow:SetFrameLevel(button:GetFrameLevel() + 5)
    glow:EnableMouse(false)
    local parts = {}

    -- Goldener Rahmen (2 px, etwas außerhalb) bzw. feine Linie (1 px, auf dem Rand)
    local frame = CreateFrame("Frame", nil, glow, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", -2, 2)
    frame:SetPoint("BOTTOMRIGHT", 2, -2)
    frame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    frame:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)
    parts.FOREVER = { frame }
    local pixel = CreateFrame("Frame", nil, glow, "BackdropTemplate")
    pixel:SetAllPoints()
    pixel:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    pixel:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)
    parts.PIXEL = { pixel }

    -- Weicher Schein: Blizzard-Knopfrand als heller Hof in Gold
    local soft = glow:CreateTexture(nil, "OVERLAY")
    soft:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    soft:SetBlendMode("ADD")
    soft:SetVertexColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 1)
    soft:SetPoint("CENTER")
    soft:SetSize(ACTION_SIZE * 1.8, ACTION_SIZE * 1.8)
    parts.SOFT = { soft }

    -- Ecken: je zwei kurze goldene Striche
    local corners = {}
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local fx, fy = PointFactors(corner)
        local across = GoldTexture(glow)
        across:SetSize(10, 2)
        across:SetPoint(corner, glow, corner, fx, fy)
        local down = GoldTexture(glow)
        down:SetSize(2, 10)
        down:SetPoint(corner, glow, corner, fx, fy)
        table.insert(corners, across)
        table.insert(corners, down)
    end
    parts.CORNERS = corners

    -- Aufblitzen: helle Fläche über dem Symbol
    local flash = glow:CreateTexture(nil, "OVERLAY")
    flash:SetColorTexture(1, 0.95, 0.7, 0.55)
    flash:SetBlendMode("ADD")
    flash:SetAllPoints(button.icon or button.Icon or glow)
    parts.FLASH = { flash }

    -- Nachbildung von Blizzards Leuchten (nur Testmodus): die Blizzard-Grafik, sonst ein ähnlicher Schein
    local blizzard = glow:CreateTexture(nil, "OVERLAY")
    blizzard:SetPoint("CENTER")
    blizzard:SetSize(ACTION_SIZE * 1.4, ACTION_SIZE * 1.4)
    local blizzardAnim = blizzard:CreateAnimationGroup()
    blizzardAnim:SetLooping("REPEAT")
    if HasAtlas(BLIZZARD_PROC_ATLAS) then
        blizzard:SetAtlas(BLIZZARD_PROC_ATLAS)
        local flip = blizzardAnim:CreateAnimation("FlipBook")
        flip:SetFlipBookRows(6)
        flip:SetFlipBookColumns(5)
        flip:SetFlipBookFrames(30)
        flip:SetDuration(1)
    else
        blizzard:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        blizzard:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
        blizzard:SetBlendMode("ADD")
        local fade = blizzardAnim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.4)
        fade:SetDuration(0.5)
        blizzardAnim:SetLooping("BOUNCE")
    end
    parts.BLIZZARD = { blizzard }
    glow.blizzardAnim = blizzardAnim

    -- Pulsieren für alle eigenen Stile (feine Linie und Aufblitzen etwas schneller)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    glow.fade = pulse:CreateAnimation("Alpha")
    glow.fade:SetFromAlpha(1)
    glow.fade:SetToAlpha(0.3)
    glow.fade:SetDuration(0.5)
    glow.pulse = pulse

    glow.parts = parts
    glow:Hide()
    button.fbGlow = glow
    return glow
end

-- style = einer der Stile oben oder nil (aus)
local function ShowGlow(button, style)
    local glow = GetGlow(button)
    glow.pulse:Stop()
    glow.blizzardAnim:Stop()
    for key, list in pairs(glow.parts) do
        for _, part in ipairs(list) do part:SetShown(key == style) end
    end
    if not style or not glow.parts[style] then
        glow:Hide()
        return
    end
    glow:Show()
    if style == "BLIZZARD" then
        glow.blizzardAnim:Play()
    else
        local fast = style == "PIXEL" or style == "FLASH"
        glow.fade:SetDuration(fast and 0.3 or 0.5)
        glow.fade:SetToAlpha(style == "FLASH" and 0 or 0.3)
        glow.pulse:Play()
    end
end

local function OnAlertShown(button)
    if not button or not button.fbBorder then return end -- nur Knöpfe in ForeverBars-Leisten
    button.fbAlertActive = true
    local style = ns.db.procGlow
    local alert = button.SpellActivationAlert or button.overlay
    if alert then alert:SetAlpha(style == "BLIZZARD" and 1 or 0) end
    -- Bei "Wie Blizzard" zeigt Blizzard selbst das Leuchten, bei "Aus" nichts
    ShowGlow(button, (style ~= "BLIZZARD" and style ~= "OFF") and style or nil)
end

local function OnAlertHidden(button)
    if not button then return end
    button.fbAlertActive = nil
    -- Im Testmodus leuchtet der Knopf weiter
    if button.fbGlow and not button.fbTestGlow then ShowGlow(button, nil) end
end

---------------------------------------------------------------------------
-- Testmodus: alle aktiven Leisten zeigen, auf einigen Knöpfen Proc-Leuchten und Beispiel-Abklingzeiten.
-- Nutzt eigene Anzeigen (eigener Abklingzeit-Rahmen, eigenes Leuchten) - Blizzards Knöpfe bleiben unberührt.
---------------------------------------------------------------------------

local TEST_COOLDOWN = 30 -- Sekunden der Beispiel-Abklingzeit
local testTicker

local function TestCooldown(button)
    if not button.fbTestCooldown then
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        local icon = button.icon or button.Icon
        if icon then cooldown:SetAllPoints(icon) else cooldown:SetAllPoints() end
        button.fbTestCooldown = cooldown
    end
    return button.fbTestCooldown
end

-- Alle Aktionsknöpfe in ForeverBars-Leisten, die gerade zu sehen sind
local function TestButtons()
    local list = {}
    for _, def in ipairs(ns.BAR_DEFS) do
        if def.kind == "action" and ns.db.bars[def.key].enabled then
            for _, button in ipairs(GetAllButtons(def)) do
                if button.fbBorder and button:GetParent() ~= hiddenParent then table.insert(list, button) end
            end
        end
    end
    return list
end

local function ApplyTestEffects(on)
    for i, button in ipairs(TestButtons()) do
        -- Jeder dritte Knopf leuchtet im gewählten Stil ("Wie Blizzard" als Nachbildung),
        -- jeder vierte (versetzt) zeigt eine Abklingzeit
        local style = ns.db.procGlow
        local glow = on and i % 3 == 1 and style ~= "OFF"
        button.fbTestGlow = glow or nil
        if glow then
            ShowGlow(button, style)
        elseif button.fbAlertActive and style ~= "BLIZZARD" and style ~= "OFF" then
            ShowGlow(button, style) -- echter Proc läuft gerade
        else
            ShowGlow(button, nil)
        end
        if on and i % 4 == 2 then
            TestCooldown(button):SetCooldown(GetTime(), TEST_COOLDOWN)
        elseif button.fbTestCooldown then
            button.fbTestCooldown:Clear()
        end
    end
end

function ns.SetTestMode(on)
    if on and InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    ns.testMode = on and true or false
    if testTicker then
        testTicker:Cancel()
        testTicker = nil
    end
    if ns.testMode then
        -- Abklingzeiten regelmäßig neu starten, solange der Testmodus läuft
        testTicker = C_Timer.NewTicker(TEST_COOLDOWN, function() ApplyTestEffects(true) end)
    end
    ns.RequestLayout() -- Sichtbarkeit (alle Leisten zeigen bzw. wieder wie eingestellt)
    -- Nach dem Anordnen, damit die Knöpfe schon in den Leisten liegen
    C_Timer.After(0.1, function() ApplyTestEffects(ns.testMode) end)
    ns.Print(L(ns.testMode and "TEST_ON" or "TEST_OFF"))
    if ns.testMode and ns.db.procGlow == "OFF" then ns.Print(L("TEST_GLOW_HINT")) end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Stil gewechselt: laufende Vorschau bzw. echtes Leuchten sofort im neuen Stil zeigen
function ns.RefreshGlows()
    if ns.testMode then ApplyTestEffects(true) end
    for _, button in ipairs(TestButtons()) do
        if button.fbAlertActive and not button.fbTestGlow then OnAlertShown(button) end
    end
end

local function HookProcGlow()
    local manager = ActionButtonSpellAlertManager
    if manager and manager.ShowAlert then
        hooksecurefunc(manager, "ShowAlert", function(_, button) OnAlertShown(button) end)
        if manager.HideAlert then
            hooksecurefunc(manager, "HideAlert", function(_, button) OnAlertHidden(button) end)
        end
    end
    -- Ältere Blizzard-Funktionen (falls es sie in Forever gibt)
    if ActionButton_ShowOverlayGlow then hooksecurefunc("ActionButton_ShowOverlayGlow", OnAlertShown) end
    if ActionButton_HideOverlayGlow then hooksecurefunc("ActionButton_HideOverlayGlow", OnAlertHidden) end
end

---------------------------------------------------------------------------
-- Rahmen um eine Leiste (wie die Fenster in ForeverQuests: dunkle Fläche, Kopfzeile mit Namen, goldene Linie)
---------------------------------------------------------------------------

local FRAME_PAD, FRAME_TITLE = 4, 18

local BACKDROP_PAD = 3 -- Stil "Forever": Fläche unter Aktions-, Begleiter- und Haltungsleisten

local function UpdateBarFrame(def, cfg, holder)
    local frame = holder.fbFrame
    local backdropOnly = not cfg.frame and GetSkin().barBackdrop
        and (def.kind == "action" or def.kind == "pet" or def.kind == "stance")
    if not cfg.frame and not backdropOnly then
        if frame then frame:Hide() end
        return
    end
    if not frame then
        frame = CreateFrame("Frame", nil, holder, "BackdropTemplate")
        frame:EnableMouse(false)
        ns.Style.SetFlat(frame, { COLOR.background[1], COLOR.background[2], COLOR.background[3], 0.85 })
        frame.header = frame:CreateTexture(nil, "BORDER")
        frame.header:SetColorTexture(unpack(COLOR.header))
        frame.header:SetPoint("TOPLEFT", 1, -1)
        frame.header:SetPoint("TOPRIGHT", -1, -1)
        frame.header:SetHeight(FRAME_TITLE)
        frame.line = frame:CreateTexture(nil, "ARTWORK")
        frame.line:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.6)
        frame.line:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT")
        frame.line:SetPoint("TOPRIGHT", frame.header, "BOTTOMRIGHT")
        frame.line:SetHeight(1)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.title:SetPoint("LEFT", frame.header, "LEFT", 6, 0)
        -- endet vor dem Zahnrad (Berufe/Verbrauchbar) und wird bei schmaler Leiste gekürzt statt überzulaufen
        frame.title:SetPoint("RIGHT", frame.header, "RIGHT", -20, 0)
        frame.title:SetJustifyH("LEFT")
        frame.title:SetWordWrap(false)
        holder.fbFrame = frame
    end
    -- Unter den Knöpfen (die Knöpfe liegen eine Ebene höher im Halter)
    frame:SetFrameLevel(holder:GetFrameLevel())
    if backdropOnly then
        -- nur die dunkle Fläche, ohne Kopfzeile und ohne Rand (übereinanderliegende Leisten verschmelzen so zu
        -- einer Fläche, statt dass sich ihre Ränder kreuzen), eng um die Knöpfe
        frame.header:Hide()
        frame.line:Hide()
        frame.title:Hide()
        frame:SetBackdropBorderColor(0, 0, 0, 0)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", holder, "TOPLEFT", -BACKDROP_PAD, BACKDROP_PAD)
        frame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", BACKDROP_PAD, -BACKDROP_PAD)
        frame:Show()
        return
    end
    frame:SetBackdropBorderColor(unpack(COLOR.border))
    local withTitle = cfg.frameTitle and true or false
    frame.header:SetShown(withTitle)
    frame.line:SetShown(withTitle)
    frame.title:SetShown(withTitle)
    -- Eigener Titel aus dem Menü, sonst der Standardtitel der Leiste (z. B. "Berufe") bzw. ihr Name
    local titleText = strtrim(cfg.frameTitleText or "")
    -- Verbrauchbar in Markierungs-Ansicht: Überschrift der Ansicht ("Zielmarkierungen"/"Bodenmarkierungen")
    local viewTitle = def.key == "food" and ns.FoodViewTitle and ns.FoodViewTitle(cfg)
    frame.title:SetText(viewTitle or (titleText ~= "" and titleText) or L(def.titleKey or def.textKey))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", holder, "TOPLEFT", -FRAME_PAD, FRAME_PAD + (withTitle and FRAME_TITLE + 1 or 0))
    frame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", FRAME_PAD, -FRAME_PAD)
    frame:Show()
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
    -- andere Forever-Rahmen (Tracker, Zauberleiste, Fenster ...) rasten an den Leisten ein
    local hub = _G.ForeverHub and _G.ForeverHub.UI
    if hub and hub.AddMover then hub.AddMover(holder) end
    return holder
end

-- Halter sofort beim Laden anlegen (nicht erst bei PLAYER_LOGIN): Blizzards Bearbeitungsmodus merkt sich im
-- Layout Anker wie "MainStatusTrackingBarContainer an ForeverBars_xp" und wendet das Layout schon beim Laden an.
-- Gibt es den Rahmen dann noch nicht, meldet Blizzard "Couldn't find region named 'ForeverBars_xp'".
for _, def in ipairs(ns.BAR_DEFS) do GetHolder(def) end

-- Taschenknöpfe festhalten: Blizzard ordnet die Taschen bei manchen Aktualisierungen selbst neu an (z. B. neue
-- Tasche, Bearbeitungsmodus) – dann landete der Rucksack an Blizzards unsichtbarer Taschenleiste und nur der Pfeil
-- blieb sichtbar. Verschiebt, versteckt oder hängt Blizzard einen unserer Taschenknöpfe um, setzen wir ihn
-- sofort zurück (nur mitgehört über hooksecurefunc; Taschenknöpfe sind nicht geschützt).
local function KeepBagButton(button)
    if button.fbBagHooked then return end
    button.fbBagHooked = true
    local function Back(self)
        local slot = self.fbSlot
        if self.fbPositioning or not slot then return end
        if InCombatLockdown() and self:IsProtected() then return end
        self.fbPositioning = true
        if self:GetParent() ~= slot[2] then self:SetParent(slot[2]) end
        self:ClearAllPoints()
        self:SetPoint(unpack(slot))
        if not self:IsShown() then self:Show() end
        self.fbPositioning = false
    end
    hooksecurefunc(button, "SetPoint", Back)
    hooksecurefunc(button, "SetParent", Back)
    hooksecurefunc(button, "Hide", Back)
end

-- Rucksack: Blizzards eigenes Symbol im flachen Forever-Knopf (Rand wie die Aktionsknöpfe, beim Darüberfahren
-- gold). Der Knopf bleibt Blizzards Knopf (Klick öffnet die Taschen, die Zahl der freien Plätze bleibt).
local function StyleBackpack(button)
    local icon = button.icon or button.Icon or _G[button:GetName() .. "IconTexture"]
    if icon then icon:SetAlpha(1) end
    if button.fbBackpackIcon then button.fbBackpackIcon:Hide() end -- früheres eigenes Symbol
    if not button.fbBackpackHooked then
        button.fbBackpackHooked = true
        button:HookScript("OnEnter", function(self)
            if self.fbBorder then self.fbBorder:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9) end
        end)
        button:HookScript("OnLeave", function(self)
            if self.fbBorder then self.fbBorder:SetBackdropBorderColor(unpack(GetSkin().border)) end
        end)
    end
end

-- Knöpfe in Reihen anordnen. Wachstumsrichtung: von links nach rechts bzw. rechts nach links,
-- von oben nach unten bzw. unten nach oben (der erste Knopf sitzt in der Ecke, von der aus es wächst).
local function LayoutButtons(def, cfg, holder)
    local buttons = GetButtons(def, cfg)
    local size = def.kind == "bags" and SMALL_SIZE or ACTION_SIZE
    local wanted = def.bagButtons and #buttons or (cfg.buttons or def.count)
    -- Haltungen: immer genau so viele Plätze, wie der Charakter hat; Berufe/Verpflegung: feste Plätze (frei belegbar)
    if def.kind == "stance" then
        wanted = math.max(1, GetNumShapeshiftForms and GetNumShapeshiftForms() or 0)
    elseif def.kind == "prof" or def.kind == "food" then
        wanted = ns.AssignSlotButtons(def.key)
    end
    local count = math.max(1, math.min(wanted, #buttons))
    local perRow = math.max(1, math.min(cfg.perRow or count, count))
    local rows = math.ceil(count / perRow)
    -- Platz (Spalte, Reihe) je Knopf, Reihe für Reihe
    local slots = {}
    if def.kind == "prof" or def.kind == "food" then
        -- Berufe/Verpflegung: Spalte für Spalte, mindestens 2 Reihen (siehe SlotRows)
        rows = SlotRows(def.key, cfg, count)
        perRow = math.ceil(count / rows)
        for i = 1, count do slots[i] = { SlotCell(i, rows) } end
    else
        for i = 1, count do slots[i] = { (i - 1) % perRow, math.floor((i - 1) / perRow) } end
    end
    local gap = ns.ButtonGap(cfg)
    local toLeft, toTop = cfg.growX == "LEFT", cfg.growY == "UP"
    local corner = (toTop and "BOTTOM" or "TOP") .. (toLeft and "RIGHT" or "LEFT")
    -- Verbrauchbar in Markierungs-Ansicht (Zahnrad): eigene Knöpfe ablegen, Markierungen ins 3x3-Raster
    if def.kind == "food" and ns.LayoutFoodMarks and ns.FoodView(cfg) ~= "items" then
        for _, button in ipairs(GetAllButtons(def)) do
            button.fbPositioning = true
            button:SetParent(hiddenParent)
            button.fbPositioning = false
        end
        ns.LayoutFoodMarks(cfg, holder, gap, corner, toLeft, toTop)
        return
    end
    if def.kind == "food" and ns.LayoutFoodMarks then ns.LayoutFoodMarks(cfg, holder, gap, corner, toLeft, toTop) end
    local shown = {}
    for i, button in ipairs(buttons) do
        if i <= count then
            shown[button] = true
            local column, row = slots[i][1], slots[i][2]
            local x = column * (size + gap) * (toLeft and -1 or 1)
            local y = row * (size + gap) * (toTop and 1 or -1)
            button.fbPositioning = true
            button:SetParent(holder)
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint(corner, holder, corner, x, y)
            button.fbPositioning = false
            -- Taschen: Platz merken und festhalten (siehe KeepBagButton)
            if def.kind == "bags" then
                button.fbSlot = { corner, holder, corner, x, y }
                if not button:IsShown() then button:Show() end
            end
            -- Ausklapp-Richtung von Zauber-Gruppen (z. B. Portale); nur Aktionsknöpfe
            if def.kind == "action" then
                button:SetAttribute("flyoutDirection", cfg.flyout or "UP")
                if button.UpdateFlyout then pcall(button.UpdateFlyout, button) end
            end
        end
        StyleButton(button)
        if def.kind == "bags" then
            KeepBagButton(button)
            if button == MainMenuBarBackpackButton then StyleBackpack(button) end
        end
    end
    -- Nicht genutzte Knöpfe (zu viele bzw. ausgeschlossene Taschen) ablegen
    for _, button in ipairs(GetAllButtons(def)) do
        if not shown[button] then
            button.fbSlot = nil
            button.fbPositioning = true
            button:SetParent(hiddenParent)
            button.fbPositioning = false
        end
    end
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
    -- Blizzards Status-Leisten (Erfahrung/Ruf) rufen self:GetParent():CheckForLayoutChange() auf – ihr
    -- Elternrahmen muss der StatusTrackingBarManager bleiben. Hängt man sie in den Halter um, landet dieser
    -- Aufruf in ForeverBars-Code und Blizzards Code läuft danach "getaintet" weiter (Fehler mit gesperrten
    -- Werten z. B. in den Gruppenrahmen beim Öffnen des Bearbeitungsmodus). Darum werden sie nur an den
    -- Halter angelegt, nicht umgehängt; Größe und Deckkraft bekommen sie direkt.
    local keepParent = frame.GetStatusTrackingManager ~= nil or def.keepParent
    frame.fbKeepParent = keepParent
    if keepParent then
        local manager = _G.StatusTrackingBarManager
        if frame:GetParent() == holder and manager then frame:SetParent(manager) end
        frame:SetScale(math.max(0.3, (cfg.scale or 100) / 100))
        frame:SetAlpha(cfg.enabled and (cfg.alpha or 100) / 100 or 0)
    elseif frame:GetParent() ~= holder then
        frame:SetParent(holder)
    end
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
            if not self.fbKeepParent and self:GetParent() ~= self.fbHolder then self:SetParent(self.fbHolder) end
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
    if def.key == "micro" then
        frame:SetAlpha(1) -- war bei den eigenen Knöpfen unsichtbar
        ns.StyleMicroMenu()
    end
    -- Totemleiste (Schamane): Blizzards Leiste bleibt, wie sie ist (Totem-Arten nebeneinander, Auswahl klappt
    -- nach oben auf); nur ihre Aktionsknöpfe bekommen den Forever-Look
    if def.key == "totem" then
        for i = 1, 12 do
            local button = _G["MultiCastActionButton" .. i]
            if button then StyleButton(button) end
        end
        for _, name in ipairs({ "MultiCastSummonSpellButton", "MultiCastRecallSpellButton" }) do
            if _G[name] then StyleButton(_G[name]) end
        end
    end
    -- Mindestgröße, damit der Halter auch dann Platz hat, wenn Blizzard das Element gerade ausblendet
    local minSize = def.minSize or 1
    holder:SetSize(math.max(minSize, frame:GetWidth()), math.max(minSize, frame:GetHeight()))
end

---------------------------------------------------------------------------
-- Feste Seite der Aktionsleisten. Eine "Seite" ist eine Belegung von 12 Knöpfen; nach dem Umhängen in die
-- eigenen Halter muss jede Leiste ihre Seite selbst setzen. Leiste 1 überlässt den Wechsel Blizzard
-- (Gestalten, Fahrzeuge, Seiten-Pfeile). Läuft über die geschützte Blizzard-Technik (Zustandstreiber).
---------------------------------------------------------------------------

-- Eigene Seite jeder Leiste (wie bei Blizzard): Leiste 1 = Seite 1, Leiste 2 = Seite 6 usw.
local HOME_PAGES = { bar1 = 1, bar2 = 6, bar3 = 5, bar4 = 3, bar5 = 4, bar6 = 13, bar7 = 14, bar8 = 15 }

-- nil = Blizzard regelt es (Leiste 1), sonst die feste Seite der Leiste
local function PagingDriver(def)
    if def.kind ~= "action" or def.key == "bar1" then return nil end
    return tostring(HOME_PAGES[def.key] or 1)
end

-- Seite einer Leiste einrichten (nur außerhalb des Kampfes)
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
    local driver = PagingDriver(def)
    if driver then
        RegisterStateDriver(holder, "page", driver)
        holder.fbPaging = true
    elseif holder.fbPaging then
        -- Zurück zum Blizzard-Seitenwechsel (Leiste 1, z. B. nach Profilen aus älteren Versionen)
        UnregisterStateDriver(holder, "page")
        holder.fbPaging = false
        holder:SetAttribute("actionpage", nil)
        for _, button in ipairs(buttons) do
            button:SetAttribute("actionpage", nil)
            if button.UpdateAction then button:UpdateAction() end
        end
    end
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

-- ignoreCollapse: das Einklappen regelt der geschützte Pfeil selbst (Attribut "fbcollapsed", Treiber "fbvis")
local function VisibilityDriver(def, cfg, ignoreCollapse)
    if not cfg.enabled then return "hide" end
    if ns.unlocked or ns.testMode then return "show" end
    -- Mit dem Pfeil eingeklappt (Berufe, Verpflegung)
    if not ignoreCollapse and (def.kind == "prof" or def.kind == "food") and cfg.collapseArrow and cfg.collapsed then
        return "hide"
    end
    -- Haltungsleiste ohne Haltungen, Auren oder Gestalten ausblenden
    if def.kind == "stance" and (GetNumShapeshiftForms and GetNumShapeshiftForms() or 0) == 0 then return "hide" end
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

-- Mikromenü unter der Minimap (nur mit ForeverMinimap): direkt unter der Karte bzw. unter ihrer Leiste, wenn die
-- unten liegt (wie der Tracker von ForeverQuests), so breit wie die Karte samt 1-px-Rahmen. Darunter hängt
-- ForeverQuests den Tracker. Rückgabe: { anchor, scale, x, y } (x/y = Mitte in UIParent-Koordinaten) oder nil.
local MICRO_DOCK_GAP = 4   -- Abstand unter der Karte (bzw. ihrer Leiste)
local MICRO_DOCK_SNAP = 30 -- so nah (Mitte zu Mitte) rastet das gezogene Mikromenü wieder unter der Karte ein
function ns.MicroDockTarget(holder)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverMinimap")) then return nil end
    local map = _G.Minimap
    if not (holder and map and map:IsShown() and map:GetBottom() and holder:GetWidth() > 1) then return nil end
    local anchor = map
    local bar = _G.ForeverMinimapBar
    if bar and bar:IsShown() and bar:GetBottom() and bar:GetBottom() < map:GetBottom() then anchor = bar end
    local uiScale = UIParent:GetEffectiveScale()
    -- Breite in Pixeln: Karte samt Rahmen (ohne die Knopfleiste daneben), mittig unter der Karte
    local anchorX = anchor:GetCenter() * anchor:GetEffectiveScale()
    local pixels, centerPx = (map:GetWidth() + 2) * map:GetEffectiveScale(), anchorX
    local scale = pixels / (holder:GetWidth() * uiScale)
    local ratio = anchor:GetEffectiveScale() / uiScale
    local centerY = anchor:GetBottom() * ratio - MICRO_DOCK_GAP - holder:GetHeight() * scale / 2
    -- shift: waagerechter Versatz zur Mitte des Ankers (in Einheiten des Halters)
    return { anchor = anchor, scale = scale, x = centerPx / uiScale, y = centerY,
             shift = (centerPx - anchorX) / (uiScale * scale) }
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
    -- Rahmen anderer Forever-Addons (und Bildschirmmitte/Raster): gemeinsamer Hub-Versatz, wo oben nichts einrastete.
    -- (Der Halter steht dafuer schon auf der Mausposition, siehe OnUpdate beim Ziehen.)
    local hub = _G.ForeverHub and _G.ForeverHub.UI
    if hub and hub.SnapOffset and (distanceX > SNAP_DISTANCE or distanceY > SNAP_DISTANCE) then
        local dx, dy = hub.SnapOffset()
        if distanceX > SNAP_DISTANCE then bestX = bestX + dx end
        if distanceY > SNAP_DISTANCE then bestY = bestY + dy end
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
            local hub = _G.ForeverHub and _G.ForeverHub.UI
            if hub and hub.BeginDrag then hub.BeginDrag(holders[self.key], { snap = ns.db.snap }) end
            -- Die Leiste selbst wandert mit (der Griff hängt an ihr), damit man sie beim Ziehen sieht;
            -- dabei rastet sie magnetisch ein (Shift gedrückt halten = frei schieben)
            self:SetScript("OnUpdate", function(frame)
                local holder = holders[frame.key]
                if not holder or InCombatLockdown() then return end
                local x, y = CursorPosition()
                x, y = x + frame.offsetX, y + frame.offsetY
                -- Mikromenü: nahe der Stelle unter der Minimap rastet es dort wieder ein (Shift = frei schieben)
                local dock = frame.key == "micro" and not IsShiftKeyDown() and ns.MicroDockTarget(holder)
                if dock and math.abs(x - dock.x) < MICRO_DOCK_SNAP and math.abs(y - dock.y) < MICRO_DOCK_SNAP then
                    frame.dock = true
                    holder:SetScale(dock.scale)
                    holder:ClearAllPoints()
                    holder:SetPoint("TOP", dock.anchor, "BOTTOM", dock.shift, -MICRO_DOCK_GAP / dock.scale)
                    return
                end
                frame.dock = false
                if frame.key == "micro" then holder:SetScale(math.max(0.3, (ns.db.bars.micro.scale or 100) / 100)) end
                -- erst frei an die Mausposition, damit der Hub die Kanten der Leiste dort misst
                local rawScale = holder:GetScale()
                holder:ClearAllPoints()
                holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / rawScale, y / rawScale)
                x, y = SnapPosition(frame.key, x, y)
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
            local hub = _G.ForeverHub and _G.ForeverHub.UI
            if hub and hub.EndDrag then hub.EndDrag() end
            -- Die (ggf. eingerastete) Position vom Ziehen übernehmen
            local x, y = self.dropX, self.dropY
            if not x or not y then
                local cursorX, cursorY = CursorPosition()
                x, y = cursorX + self.offsetX, cursorY + self.offsetY
            end
            self.dropX, self.dropY = nil, nil
            if self.key == "micro" then
                -- Unter der Minimap losgelassen: wieder angedockt; sonst frei an der neuen Stelle
                ns.db.bars.micro.dockMinimap = self.dock and true or false
            end
            -- x/y ist die Mitte; gespeichert wird der Ankerpunkt der Leiste
            if not (self.key == "micro" and self.dock) then ns.SetBarCenter(self.key, x, y) end
            self.dock = nil
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

-- Pfeil an der Taschenleiste zum Aus- und Einklappen der Taschen (eingeklappt bleibt der Rucksack sichtbar).
-- Er sitzt an dem Ende, in das die Taschen wachsen; im Kampf wird erst danach umgebaut.
function ns.UpdateBagToggle(def, cfg, holder)
    local toggle = holder.fbBagToggle
    if not cfg.collapsible then
        if toggle then toggle:Hide() end
        return
    end
    if not toggle then
        toggle = CreateFrame("Button", nil, holder, "BackdropTemplate")
        ns.Style.SetFlat(toggle, COLOR.button)
        toggle.arrow = toggle:CreateTexture(nil, "OVERLAY")
        toggle.arrow:SetSize(10, 10)
        toggle.arrow:SetPoint("CENTER")
        toggle.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        toggle:SetScript("OnClick", function()
            local barCfg = ns.db.bars[def.key]
            barCfg.bagsCollapsed = not barCfg.bagsCollapsed
            if InCombatLockdown() then ns.Print(L("COMBAT_QUEUED")) end
            ns.RequestLayout()
        end)
        toggle:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
            local tip = ns.Style.GetTooltip()
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:AddLine(L(ns.db.bars[def.key].bagsCollapsed and "BAGS_EXPAND" or "BAGS_COLLAPSE"))
            tip:Show()
        end)
        toggle:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(COLOR.border))
            ns.Style.GetTooltip():Hide()
        end)
        holder.fbBagToggle = toggle
    end
    -- Pfeil zeigt in die Richtung, in die sich die Taschen öffnen bzw. schließen
    local toLeft = cfg.growX == "LEFT"
    local expanding = cfg.bagsCollapsed
    toggle:ClearAllPoints()
    toggle:SetSize(12, SMALL_SIZE)
    if toLeft then
        toggle:SetPoint("RIGHT", holder, "LEFT", -2, 0)
    else
        toggle:SetPoint("LEFT", holder, "RIGHT", 2, 0)
    end
    local pointLeft = (toLeft and expanding) or (not toLeft and not expanding)
    toggle.arrow:SetRotation(pointLeft and math.pi or 0) -- die Grafik zeigt von sich aus nach rechts
    toggle:Show()
end

-- Einklapp-Pfeil an Berufe- und Verpflegungsleiste: sitzt auf der Innenseite (zu den Aktionsleisten hin), so hoch
-- wie die Leiste samt Rahmen. Ausgeklappt zeigt er nach innen ("einklappen"), eingeklappt nach außen. Eingeklappt
-- ist die Leiste ausgeblendet (über ihre Sichtbarkeits-Bedingung, im Kampf erst danach); der Pfeil bleibt stehen.
---------------------------------------------------------------------------
-- Zahnrad oben rechts in der Berufe- und Verbrauchbar-Leiste: kleines Auswahlmenü.
--   Berufe: "Leiste ausschalten".
--   Verbrauchbar: Ansicht wechseln – Verbrauchbares, Zielmarkierungen ("Einheit": aufs Ziel) oder
--   Bodenmarkierungen ("Boden") im selben 3x3-Raster (8 Symbole + Entfernen), dazu "Pings beschränken auf"
--   und "Leiste ausschalten" – wie in Blizzards Raid-Werkzeug. Die Überschrift wechselt mit der Ansicht.
-- Ziel- und Bodenmarkierungen setzt das Spiel nur über geschützte Knöpfe (SecureActionButton, type "raidtarget"
-- bzw. "worldmarker"); die klicken auch im Kampf, die Ansicht wechselt aber erst nach dem Kampf.
---------------------------------------------------------------------------
-- Reihenfolge wie bei Blizzard: Totenkopf, Kreuz, Quadrat, Mond, Dreieck, Diamant, Kreis, Stern.
-- raid = Index der Zielmarkierung (UI-RaidTargetingIcon_N), world = Nummer der Bodenmarkierung
local MARKERS = {
    { raid = 8, world = 8 }, { raid = 7, world = 4 }, { raid = 6, world = 1 }, { raid = 5, world = 7 },
    { raid = 4, world = 2 }, { raid = 3, world = 3 }, { raid = 2, world = 6 }, { raid = 1, world = 5 },
}
local MARK_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local GEAR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local MARK_SEP = 7 -- zusätzlicher Abstand vor der 4. Spalte (Bereitschaftscheck usw.) für die Trennlinie
local FOOD_VIEWS = { unit = true, ground = true } -- "Verbrauchbares" gibt es als Ansicht nicht mehr

local function PingChoices()
    local e = Enum and Enum.RestrictPingsTo
    if not (e and C_PartyInfo and C_PartyInfo.SetRestrictPings) then return nil end
    return {
        { value = e.None, text = L("PING_NONE") },
        { value = e.Lead, text = L("PING_LEAD") },
        { value = e.Assist, text = L("PING_ASSIST") },
        { value = e.TankHealer, text = L("PING_TANKHEALER") },
    }
end

-- Ansicht der (früheren Verbrauchbar-)Leiste: "unit" (Zielmarkierungen, Standard) oder "ground" (Bodenmarkierungen)
function ns.FoodView(cfg)
    local view = cfg and cfg.foodView
    return FOOD_VIEWS[view] and view or "unit"
end

-- Schnelltastenbelegung (Blizzards Modus "Tastenbelegung per Maus"): im Modus Knopf unter der Maus an Blizzards
-- Belegungs-Fenster melden (QuickKeybindFrame:SetSelected mit dem Befehl "CLICK <name>:LeftButton"); die gedrückte
-- Taste belegt Blizzard dann selbst. Solange der Modus läuft, lösen die Knöpfe nichts aus (Typ kurz entfernt) und
-- zeigen eine goldene Fläche. Der Modus geht nur außerhalb des Kampfes auf.
local quickButtons = {}
local function InQuickKeybind() return QuickKeybindFrame and QuickKeybindFrame:IsShown() end

local function QuickTooltip(button)
    local tip = ns.Style.GetTooltip()
    tip:SetOwner(button, "ANCHOR_TOP")
    tip:AddLine(_G["BINDING_NAME_" .. button.commandName] or button.commandName, 1, 0.82, 0)
    local key = GetBindingKey(button.commandName)
    tip:AddLine(key and GetBindingText(key) or (NOT_BOUND or "-"), 1, 1, 1)
    tip:AddLine(L("QUICKBIND_HINT"), 0.7, 0.7, 0.7, true)
    tip:Show()
end

local function SetQuickMode(on)
    for _, button in ipairs(quickButtons) do
        if not InCombatLockdown() then
            if on then
                button.fbQuickType = button.fbQuickType or button:GetAttribute("type")
                button:SetAttribute("type", nil)
            elseif button.fbQuickType then
                button:SetAttribute("type", button.fbQuickType)
                button.fbQuickType = nil
            end
        end
        button.fbQuickHighlight:SetShown(on)
    end
end

local function AddQuickKeybind(button)
    button.commandName = "CLICK " .. button:GetName() .. ":LeftButton"
    local highlight = button:CreateTexture(nil, "OVERLAY", nil, 7)
    highlight:SetAllPoints()
    highlight:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.22)
    highlight:Hide()
    button.fbQuickHighlight = highlight
    button:HookScript("OnEnter", function(self)
        if not InQuickKeybind() then return end
        QuickKeybindFrame:SetSelected(self.commandName, self)
        self.fbQuickHighlight:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.45)
        QuickTooltip(self)
    end)
    button:HookScript("OnLeave", function(self)
        if not InQuickKeybind() then return end
        QuickKeybindFrame:SetSelected(nil, nil)
        self.fbQuickHighlight:SetColorTexture(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.22)
        ns.Style.GetTooltip():Hide()
    end)
    -- weitere Maustasten (Taste 4/5 …) im Modus ebenfalls belegen (wie bei Blizzards Knöpfen)
    button:HookScript("OnClick", function(self, mouseButton, down)
        if InQuickKeybind() and mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" and down ~= false then
            QuickKeybindFrame:OnKeyDown(mouseButton)
            QuickTooltip(self)
        end
    end)
    quickButtons[#quickButtons + 1] = button
    if InQuickKeybind() then SetQuickMode(true) end
end

if EventRegistry and EventRegistry.RegisterCallback then
    local owner = {}
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function() SetQuickMode(true) end, owner)
    EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function() SetQuickMode(false) end, owner)
end

-- Geschützter Markierungs-Knopf im Forever-Look (Rand wie der Knopf-Stil, beim Darüberfahren gold).
-- name: fester Name für die Tastaturbelegung (Bindings.xml: "CLICK <name>:LeftButton")
local markButtonNames = {}
local function MarkButton(parent, size, name)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetSize(size, size)
    button:RegisterForClicks("AnyUp", "AnyDown")
    ns.Style.SetFlat(button, GetSkin().background or COLOR.button, GetSkin().border)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 5, -5)
    button.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    -- Tastenbelegung oben rechts (Text setzt ns.UpdateOwnHotkeys)
    button.HotKey = button:CreateFontString(nil, "OVERLAY")
    SetTextFont(button.HotKey, ns.db.fontSize)
    button.HotKey:SetPoint("TOPRIGHT", -2, -3)
    button.HotKey:SetJustifyH("RIGHT")
    if name then markButtonNames[#markButtonNames + 1] = name end
    button:HookScript("OnEnter", function(self)
        self:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
    end)
    button:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(GetSkin().border)) end)
    if name then AddQuickKeybind(button) end
    return button
end

-- Die beiden Sätze Markierungs-Knöpfe einer Leiste (einmalig, außerhalb des Kampfes angelegt)
local function GetMarkButtons(holder)
    if holder.fbMarks then return holder.fbMarks end
    local sets = { unit = {}, ground = {} }
    for i, m in ipairs(MARKERS) do
        local unitButton = MarkButton(holder, ACTION_SIZE, "ForeverBarsMarkTarget" .. m.raid)
        unitButton.icon:SetTexture(MARK_ICON .. m.raid)
        unitButton:SetAttribute("type", "raidtarget")
        unitButton:SetAttribute("unit", "target")
        unitButton:SetAttribute("marker", m.raid)
        unitButton:SetAttribute("action", "toggle") -- gleiche Markierung noch einmal = entfernen
        sets.unit[i] = unitButton
        local groundButton = MarkButton(holder, ACTION_SIZE, "ForeverBarsMarkWorld" .. m.raid)
        groundButton.icon:SetTexture(MARK_ICON .. m.raid)
        groundButton:SetAttribute("type", "worldmarker")
        groundButton:SetAttribute("marker", m.world)
        groundButton:SetAttribute("action", "toggle") -- an die Mausposition setzen bzw. wieder entfernen
        sets.ground[i] = groundButton
    end
    -- 9. Platz: Entfernen (Markierung vom Ziel bzw. alle Bodenmarkierungen)
    local clearUnit = MarkButton(holder, ACTION_SIZE, "ForeverBarsMarkTargetClear")
    clearUnit.icon:SetTexture(CLEAR_ICON)
    clearUnit:SetAttribute("type", "raidtarget")
    clearUnit:SetAttribute("unit", "target")
    clearUnit:SetAttribute("action", "clear")
    sets.unit[9] = clearUnit
    local clearGround = MarkButton(holder, ACTION_SIZE, "ForeverBarsMarkWorldClear")
    clearGround.icon:SetTexture(CLEAR_ICON)
    clearGround:SetAttribute("type", "worldmarker")
    clearGround:SetAttribute("action", "clear")
    sets.ground[9] = clearGround
    -- 4. Spalte (in beiden Ansichten): Bereitschaftscheck, Rollenabfrage, Countdown – über Blizzards Chatbefehle
    -- auf geschützten Knöpfen (die Funktionen selbst sind im Forever-Client geschützt)
    sets.extra = {}
    for i, e in ipairs({
        { macro = "/readycheck", icon = "Interface\\RaidFrame\\ReadyCheck-Ready", tip = "TIP_READYCHECK",
          name = "ForeverBarsReadyCheck" },
        { macro = "/rolepoll", icon = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", coords = { 0, 0.2617, 0.2617, 0.5234 },
          tip = "TIP_ROLEPOLL", name = "ForeverBarsRolePoll" },
        { macro = "/countdown 10", icon = "Interface\\Icons\\Spell_Holy_BorrowedTime", tip = "TIP_COUNTDOWN",
          name = "ForeverBarsCountdown" },
    }) do
        local b = MarkButton(holder, ACTION_SIZE, e.name)
        b.icon:SetTexture(e.icon)
        if e.coords then b.icon:SetTexCoord(unpack(e.coords)) end
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", e.macro)
        b:HookScript("OnEnter", function(self)
            local tip = ns.Style.GetTooltip()
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:AddLine(L(e.tip), 1, 1, 1)
            tip:Show()
        end)
        b:HookScript("OnLeave", function() ns.Style.GetTooltip():Hide() end)
        sets.extra[i] = b
    end
    holder.fbMarks = sets
    ns.UpdateOwnHotkeys()
    return sets
end

-- Tastenbelegung auf den Markierungs-Knöpfen anzeigen (aus ns.UpdateOwnHotkeys)
function ns.UpdateMarkHotkeys()
    for _, name in ipairs(markButtonNames) do
        local button = _G[name]
        if button and button.HotKey then
            local key = GetBindingKey and GetBindingKey("CLICK " .. name .. ":LeftButton")
            button.HotKey:SetText(key and GetBindingText and ns.ShortKey(GetBindingText(key, true)) or "")
            SetTextFont(button.HotKey, ns.db.fontSize)
            button.HotKey:SetAlpha(ns.db.showHotkeys == false and 0 or 1)
        end
    end
end

-- Verbrauchbar in Markierungs-Ansicht anordnen (aus LayoutButtons, nur außerhalb des Kampfes).
-- Rückgabe: true = erledigt (die Verbrauchbar-Knöpfe hat LayoutButtons dann schon abgelegt)
function ns.LayoutFoodMarks(cfg, holder, gap, corner, toLeft, toTop)
    local view = ns.FoodView(cfg)
    if view == "items" then
        if holder.fbMarks then
            for _, set in pairs(holder.fbMarks) do
                for _, button in ipairs(set) do button:Hide() end
            end
        end
        return false
    end
    local sets = GetMarkButtons(holder)
    local function Place(button, column, row)
        button:ClearAllPoints()
        button:SetPoint(corner, holder, corner, column * (ACTION_SIZE + gap) * (toLeft and -1 or 1),
            row * (ACTION_SIZE + gap) * (toTop and 1 or -1))
        button:SetBackdropBorderColor(unpack(GetSkin().border))
        button:Show()
    end
    for key, set in pairs(sets) do
        for i, button in ipairs(set) do
            if key == "extra" then
                Place(button, 3, i - 1) -- 4. Spalte, untereinander
                -- etwas Platz für die Trennlinie zwischen Markierungen und Abfragen
                local point, rel, relPoint, x, y = button:GetPoint(1)
                button:SetPoint(point, rel, relPoint, x + MARK_SEP * (toLeft and -1 or 1), y)
            elseif key == view then
                Place(button, (i - 1) % 3, math.floor((i - 1) / 3))
            else
                button:Hide()
            end
        end
    end
    -- Trennlinie: senkrecht, mittig im Abstand vor der 4. Spalte (Ziel- und Bodenmarkierungen gleich)
    if not holder.fbMarkLine then
        holder.fbMarkLine = holder:CreateTexture(nil, "ARTWORK")
        holder.fbMarkLine:SetWidth(1)
    end
    local line = holder.fbMarkLine
    line:SetColorTexture(1, 1, 1, 0.18)
    line:ClearAllPoints()
    local first, last = sets.extra[1], sets.extra[#sets.extra]
    local side = toLeft and "RIGHT" or "LEFT"
    local offset = (MARK_SEP + gap) / 2 * (toLeft and 1 or -1)
    line:SetPoint("TOP", first, "TOP" .. side, offset, 0)
    line:SetPoint("BOTTOM", last, "BOTTOM" .. side, offset, 0)
    line:Show()
    holder:SetSize(4 * ACTION_SIZE + 3 * gap + MARK_SEP, 3 * ACTION_SIZE + 2 * gap)
    return true
end

-- Überschrift der Verbrauchbar-Leiste je Ansicht (nil = normaler Titel)
function ns.FoodViewTitle(cfg)
    local view = ns.FoodView(cfg)
    if view == "unit" then return L("MARK_TITLE_UNIT") end
    if view == "ground" then return L("MARK_TITLE_GROUND") end
end

local function DisableBar(key)
    ns.db.bars[key].enabled = false
    ns.Print(L("BAR_DISABLED_HINT"))
    ns.RequestLayout()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

local function GearMenu(key, gear)
    local items = {}
    if key == "food" then
        local cfg = ns.db.bars.food
        table.insert(items, { title = L("GEAR_VIEW") })
        for _, v in ipairs({ { "unit", "MARK_TITLE_UNIT" }, { "ground", "MARK_TITLE_GROUND" } }) do
            table.insert(items, { radio = true, text = L(v[2]),
                checked = function() return ns.FoodView(cfg) == v[1] end,
                onClick = function()
                    cfg.foodView = v[1]
                    if InCombatLockdown() then ns.Print(L("COMBAT_QUEUED")) end
                    ns.RequestLayout()
                end })
        end
        local pings = PingChoices()
        if pings then
            table.insert(items, { divider = true })
            table.insert(items, { title = L("PING_RESTRICT") })
            for _, c in ipairs(pings) do
                table.insert(items, { radio = true, text = c.text,
                    checked = function() return C_PartyInfo.GetRestrictPings and C_PartyInfo.GetRestrictPings() == c.value end,
                    onClick = function() pcall(C_PartyInfo.SetRestrictPings, c.value) end })
            end
        end
        table.insert(items, { divider = true })
    end
    table.insert(items, { text = L("OPT_DISABLE_BAR"), onClick = function() DisableBar(key) end })
    ns.Style.ShowMenu(gear, items)
end

-- Zahnrad in der Ecke der Leiste (ausgeklappt sichtbar; eingeklappt ist die Leiste samt Zahnrad ausgeblendet)
function ns.UpdateBarGear(def, cfg, holder)
    local gear = holder.fbGear
    if not gear then
        gear = CreateFrame("Button", nil, holder, "BackdropTemplate")
        gear:SetSize(14, 14)
        gear.icon = gear:CreateTexture(nil, "ARTWORK")
        gear.icon:SetAllPoints()
        gear.icon:SetTexture(GEAR_ICON)
        gear.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        gear.icon:SetAlpha(0.8)
        gear:SetScript("OnClick", function(self) GearMenu(def.key, self) end)
        gear:SetScript("OnEnter", function(self)
            self.icon:SetAlpha(1)
            local tip = ns.Style.GetTooltip()
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:AddLine(L("GEAR_TIP"))
            tip:Show()
        end)
        gear:SetScript("OnLeave", function(self)
            self.icon:SetAlpha(0.8)
            ns.Style.GetTooltip():Hide()
        end)
        holder.fbGear = gear
    end
    -- in der Kopfzeile des Rahmens (falls an), sonst an der oberen rechten Ecke der Leiste
    local frame = cfg.frame and holder.fbFrame
    gear:ClearAllPoints()
    if frame and frame.header and frame.header:IsShown() then
        gear:SetPoint("RIGHT", frame.header, "RIGHT", -2, 0)
    elseif frame then
        gear:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    else
        gear:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, 2)
    end
    gear:SetFrameLevel(holder:GetFrameLevel() + 10)
    gear:SetShown(cfg.enabled)
end

local ARROW_WIDTH = 20
-- Symbol je Leiste im eingeklappten Pfeil-Knopf
local COLLAPSE_SYMBOLS = {
    prof = "Interface\\Icons\\Trade_BlackSmithing", -- Amboss: Berufe
}
function ns.UpdateCollapseArrow(def, cfg, holder)
    local arrow = holder.fbCollapseArrow
    if not cfg.enabled or not cfg.collapseArrow then
        if arrow then arrow:Hide() end
        return
    end
    if not arrow then
        -- Geschützter Knopf: klappt die Leiste auch im Kampf aus und ein (die Leiste selbst ist geschützt und darf
        -- im Kampf nur aus geschütztem Code gezeigt/versteckt werden). Den Zustand hält der Halter als Attribut
        -- "fbcollapsed", sein Sichtbarkeits-Treiber "fbvis" beachtet es (siehe ApplyLayout).
        arrow = CreateFrame("Button", nil, UIParent, "SecureHandlerClickTemplate, BackdropTemplate")
        -- mit zwei Vorlagen läuft nur das OnLoad der letzten: die geschützte Vorlage von Hand einrichten
        if not arrow.SetFrameRef and SecureHandler_OnLoad then SecureHandler_OnLoad(arrow) end
        arrow:SetFrameStrata("MEDIUM")
        ns.Style.SetFlat(arrow, COLOR.button)
        arrow.icon = arrow:CreateTexture(nil, "OVERLAY")
        arrow.icon:SetSize(12, 12)
        arrow.icon:SetPoint("CENTER")
        arrow.icon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetFrameRef("holder", holder)
        arrow:SetAttribute("_onclick", [[
            local h = self:GetFrameRef("holder")
            local collapsed = not h:GetAttribute("fbcollapsed")
            h:SetAttribute("fbcollapsed", collapsed)
            if h:GetAttribute("fbvisstate") ~= "hide" and not collapsed then h:Show() else h:Hide() end
        ]])
        -- danach (ungeschützt): Einstellung merken; außerhalb des Kampfes alles neu anordnen, im Kampf nur den
        -- Pfeil drehen und das Symbol zeigen/verstecken – Größe und Lage des Knopfs folgen nach dem Kampf
        arrow:HookScript("OnClick", function(self)
            local barCfg = ns.db.bars[def.key]
            barCfg.collapsed = holder:GetAttribute("fbcollapsed") and true or false
            if InCombatLockdown() then
                if self.fbRotate then self.fbRotate(barCfg.collapsed) end
                if self.label then self.label:SetShown(barCfg.collapsed) end
            end
            ns.RequestLayout()
            -- Tooltip nach dem Umbau neu schreiben (sonst stünde noch die alte Richtung da)
            C_Timer.After(0.05, function()
                local tip = ns.Style.GetTooltip()
                if tip:GetOwner() == self or self:IsMouseOver() then
                    tip:Hide()
                    if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
                end
            end)
        end)
        arrow:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(COLOR.accent[1], COLOR.accent[2], COLOR.accent[3], 0.9)
            local barCfg = ns.db.bars[def.key]
            local titleText = strtrim(barCfg.frameTitleText or "")
            -- Markierungs-Leiste: Name der zuletzt gewählten Ansicht ("Zielmarkierungen ausklappen")
            local viewTitle = def.key == "food" and ns.FoodViewTitle and ns.FoodViewTitle(barCfg)
            local name = viewTitle or (titleText ~= "" and titleText) or L(def.titleKey or def.textKey)
            local tip = ns.Style.GetTooltip()
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:AddLine(L(barCfg.collapsed and "BAR_EXPAND_NAME" or "BAR_COLLAPSE_NAME", name))
            tip:Show()
        end)
        arrow:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(COLOR.border))
            ns.Style.GetTooltip():Hide()
        end)
        holder.fbCollapseArrow = arrow
    end
    -- Seite des Pfeils: im Menü wählbar (arrowSide); "AUTO" = Innenseite, also die Seite zur Bildschirmmitte hin
    local side = cfg.arrowSide or "AUTO"
    if side == "AUTO" then
        local centerX = holder:GetCenter()
        local onLeftHalf = centerX and centerX * holder:GetEffectiveScale() < UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
        side = onLeftHalf and "RIGHT" or "LEFT"
    end
    local edge = (cfg.frame and holder.fbFrame) or holder
    local vertical = side == "RIGHT" or side == "LEFT"
    -- Die Grafik zeigt von sich aus nach rechts; ausgeklappt zeigt der Pfeil von der Leiste weg, eingeklappt zu ihr hin
    local ROTATION = { RIGHT = 0, LEFT = math.pi, TOP = math.pi / 2, BOTTOM = -math.pi / 2 }
    local OPPOSITE = { RIGHT = "LEFT", LEFT = "RIGHT", TOP = "BOTTOM", BOTTOM = "TOP" }
    arrow.icon:SetRotation(ROTATION[cfg.collapsed and OPPOSITE[side] or side])
    arrow.fbRotate = function(collapsed) arrow.icon:SetRotation(ROTATION[collapsed and OPPOSITE[side] or side]) end
    -- Symbol im Knopf (nur eingeklappt) zeigt, welche Leiste es ist; was der Klick tut, sagt der Tooltip.
    -- Pfeil links/rechts: Symbol unter dem Pfeil, Pfeil oben/unten: Symbol rechts daneben
    if not arrow.label then
        arrow.label = arrow:CreateTexture(nil, "OVERLAY")
        arrow.label:SetSize(16, 16)
    end
    -- Symbol: Berufe = Amboss; Markierungs-Leiste = Totenkopf (Zielmarkierungen) bzw. Stern (Bodenmarkierungen)
    if def.key == "food" then
        arrow.label:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (ns.FoodView(cfg) == "ground" and 1 or 8))
        arrow.label:SetTexCoord(0, 1, 0, 1)
    else
        arrow.label:SetTexture(COLLAPSE_SYMBOLS[def.key] or COLLAPSE_SYMBOLS.prof)
        arrow.label:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    local label = arrow.label
    label:ClearAllPoints()
    arrow.icon:ClearAllPoints()
    arrow:ClearAllPoints()
    arrow:SetScale(holder:GetScale())
    local offset = (side == "RIGHT" or side == "TOP") and 2 or -2
    local near, far = OPPOSITE[side], side
    if cfg.collapsed then
        -- Eingeklappt: Knopf etwas breiter, so hoch bzw. breit wie die Leiste, Pfeil und Symbol mittig
        if vertical then
            arrow.icon:SetPoint("BOTTOM", arrow, "CENTER", 0, 2)
            label:SetPoint("TOP", arrow, "CENTER", 0, -2)
            arrow:SetSize(ARROW_WIDTH + 4, math.max(edge:GetHeight(), 44))
            arrow:SetPoint(near, edge, far, offset, 0)
        else
            arrow.icon:SetPoint("RIGHT", arrow, "CENTER", -2, 0)
            label:SetPoint("LEFT", arrow, "CENTER", 2, 0)
            arrow:SetSize(math.max(edge:GetWidth(), 44), ARROW_WIDTH + 4)
            arrow:SetPoint(near, edge, far, 0, offset)
        end
        label:Show()
    else
        -- Ausgeklappt: schmaler Streifen über die ganze Seite der Leiste
        label:Hide()
        arrow.icon:SetPoint("CENTER")
        if vertical then
            arrow:SetWidth(ARROW_WIDTH)
            arrow:SetPoint("TOP" .. near, edge, "TOP" .. far, offset, 0)
            arrow:SetPoint("BOTTOM" .. near, edge, "BOTTOM" .. far, offset, 0)
        else
            arrow:SetHeight(ARROW_WIDTH)
            arrow:SetPoint(near .. "LEFT", edge, far .. "LEFT", 0, offset)
            arrow:SetPoint(near .. "RIGHT", edge, far .. "RIGHT", 0, offset)
        end
    end
    arrow:Show()
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
        if def.key == "micro" and cfg.microOwn then
            LayoutOwnMicro(def, cfg, holder) -- eigene Knöpfe statt Blizzards Mikromenü
        elseif def.key == "queue" and not cfg.enabled then
            -- Warteschlangen-Leiste aus: das Auge nicht in den (unsichtbaren) Halter haengen – sonst waere es gar
            -- nicht zu sehen. Es bleibt bei Blizzard bzw. ForeverMinimap (dort in der Leiste ueber der Karte).
            local eye = _G.QueueStatusButton
            if eye then eye.fbHolder = nil end -- frueheres "zurueck in den Halter" (Hook) abschalten
        elseif def.kind == "status" then
            ns.LayoutStatus(def, cfg, holder) -- Erfahrungs- und Ruf-Leiste (Status.lua)
        elseif def.kind == "container" or def.kind == "single" then
            if def.key == "micro" then HideOwnMicro() end
            LayoutContainer(def, cfg, holder)
        else
            LayoutButtons(def, cfg, holder)
        end
        local scale = ns.BarScale(def.key, cfg)
        holder:SetScale(scale)
        local x, y = cfg.x, cfg.y
        if not x or not y then x, y = ns.GetBarPosition(def.key) end
        -- Begleiter-, Haltungs- und Totemleiste: immer über der obersten eingeschalteten Aktionsleiste, solange man
        -- sie nicht selbst verschoben hat (cfg.moved) – auch nach dem Ein-/Ausschalten von Leisten
        if (def.key == "pet" or def.key == "stance" or def.key == "totem") and not cfg.moved then
            x, y = DefaultPosition(def.key)
            x, y = math.floor(x + 0.5), math.floor(y + 0.5)
            cfg.x, cfg.y = x, y
        end
        holder:ClearAllPoints()
        -- Am Chatfenster angeheftet (Häkchen; früher auch "unter dem Chat" – das gilt jetzt als "über dem Chat")
        -- Die Leiste soll genau auf der Ecke des sichtbaren Chat-Hintergrunds sitzen (er ist etwas größer als das
        -- Textfeld). An den Hintergrund selbst darf sie nicht geheftet werden (geschützte Leisten dürfen nur an
        -- Fenster, nicht an Texturen); deshalb am Chatfenster mit dem gemessenen Überstand des Hintergrunds.
        -- Mikromenü unter der Minimap angedockt (mit ForeverMinimap): so breit wie die Karte samt Rahmen
        local dock = def.key == "micro" and cfg.dockMinimap and ns.MicroDockTarget(holder)
        if dock then
            holder:SetScale(dock.scale)
            holder:SetPoint("TOP", dock.anchor, "BOTTOM", dock.shift, -MICRO_DOCK_GAP / dock.scale)
        else
            holder:SetPoint(cfg.point or "CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end
        if def.key == "micro" then ns.microDocked = dock and true or false end
        if def.kind == "bags" then ns.UpdateBagToggle(def, cfg, holder) end
        -- Deckkraft; beim Einblenden per Maus übernimmt das die Überblendung (siehe UpdateFading)
        if not cfg.fadeMouseover or ns.unlocked or ns.testMode then
            holder:SetAlpha((cfg.alpha or 100) / 100)
            holder.fbAlpha = nil
        end
        SetupPaging(def, cfg, holder)
        -- Abgesichert, damit eine fehlerhafte eigene Bedingung keinen Fehler auslöst
        local securedCollapse = (def.kind == "prof" or def.kind == "food") and cfg.enabled and cfg.collapseArrow
        if securedCollapse then
            -- Einklappbare Leiste: eigener Treiber "fbvis"; gezeigt wird nur, wenn er "show" sagt und die Leiste
            -- nicht eingeklappt ist – so kann der geschützte Pfeil auch im Kampf aus- und einklappen
            UnregisterStateDriver(holder, "visibility")
            holder:SetAttribute("fbcollapsed", (cfg.collapsed and not ns.unlocked and not ns.testMode) and true or false)
            holder:SetAttribute("_onstate-fbvis", [[
                self:SetAttribute("fbvisstate", newstate)
                if newstate ~= "hide" and not self:GetAttribute("fbcollapsed") then self:Show() else self:Hide() end
            ]])
            if not pcall(RegisterStateDriver, holder, "fbvis", VisibilityDriver(def, cfg, true)) then
                RegisterStateDriver(holder, "fbvis", "[petbattle] hide; show")
            end
            -- gleich anwenden (ändert sich nur das Einklappen, meldet der Treiber keinen neuen Zustand)
            local state = holder:GetAttribute("state-fbvis")
            if state then holder:SetAttribute("fbvisstate", state) end
            holder:SetShown(state ~= "hide" and not holder:GetAttribute("fbcollapsed"))
        else
            UnregisterStateDriver(holder, "fbvis")
            if not pcall(RegisterStateDriver, holder, "visibility", VisibilityDriver(def, cfg)) then
                RegisterStateDriver(holder, "visibility", "[petbattle] hide; show")
            end
        end
        UpdateBarFrame(def, cfg, holder)
        if def.kind == "prof" or def.kind == "food" then
            ns.UpdateCollapseArrow(def, cfg, holder)
            ns.UpdateBarGear(def, cfg, holder)
        end
        UpdateMover(def, holder)
    end
    -- Flächen zum Hineinziehen (einmalig anlegen, sobald die Halter da sind)
    -- (keine Fläche zum Hineinziehen bei der früheren Verbrauchbar-Leiste: sie zeigt nur noch Markierungen)
    CreateCatcher("prof")
    -- ForeverQuests hängt den Tracker unter das angedockte Mikromenü (siehe dort MinimapAnchor)
    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    if hubUI and hubUI.Fire then hubUI.Fire("ForeverBars.Layout") end
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

-- ForeverMinimap meldet Änderungen an Karte/Leiste (Größe, Leiste oben/unten): angedocktes Mikromenü neu setzen
do
    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    if hubUI and hubUI.On then
        hubUI.On("ForeverMinimap.Layout", function() if ns.db and ns.db.bars.micro.dockMinimap then ns.RequestLayout() end end)
    end
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
    local inCombat = InCombatLockdown()
    -- Allgemeine Einstellung: außerhalb des Kampfes alle Leisten abblenden (Maus darüber = voll sichtbar)
    local outOfCombatDim = ns.db.hideOutOfCombat and not inCombat
    for _, def in ipairs(ns.BAR_DEFS) do
        local cfg = ns.db.bars[def.key]
        local holder = holders[def.key]
        if holder and cfg.enabled and (cfg.fadeMouseover or ns.db.hideOutOfCombat) and not ns.unlocked
            and not ns.testMode then
            local full = (cfg.alpha or 100) / 100
            local mouseOver = holder:IsMouseOver()
                or (SpellFlyout and SpellFlyout:IsShown() and SpellFlyout:IsMouseOver())
            local over = mouseOver or (cfg.fadeInCombat and inCombat)
            if over then holder.fbLastOver = now end
            local visible = over or (now - (holder.fbLastOver or 0)) < (cfg.fadeDelay or 0)
            local target = full
            if cfg.fadeMouseover and not visible then target = math.min(full, (cfg.fadeAlpha or 0) / 100) end
            if outOfCombatDim and not mouseOver then
                target = math.min(target, math.max(0, math.min(100, ns.db.oocAlpha or 30)) / 100)
            end
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

-- Blizzard-Bearbeitungsmodus kann die Leisten nicht greifen (sie liegen in ForeverBars-Haltern).
-- Darum beim Öffnen die eigenen Griffe zeigen und beim Schließen wieder sperren – aber nur, wenn
-- der Bearbeitungsmodus sie entsperrt hat. Hooks/Callbacks lösen in Forever nicht aus, darum wird
-- nur nachgeschaut, ob der Rahmen sichtbar ist (liest nur, verändert nichts – kein taint).
local EDIT_MODE_INTERVAL = 0.2 -- Sekunden zwischen zwei Blicken
local editModeOpen = false

local function CheckEditMode()
    local frame = EditModeManagerFrame
    local open = frame and frame:IsShown() or false
    if open == editModeOpen then return end
    if InCombatLockdown() then return end -- im Kampf nichts umbauen, danach erneut prüfen
    editModeOpen = open
    if open then
        if ns.unlocked then return end
        ns.unlockedByEditMode = true
        ns.SetUnlocked(true)
        if ns.unlocked then ns.Print(L("EDITMODE_HINT")) end
    elseif ns.unlockedByEditMode then
        ns.unlockedByEditMode = nil
        if ns.unlocked then ns.SetUnlocked(false) end
    end
end

function ns.WatchEditMode()
    C_Timer.NewTicker(EDIT_MODE_INTERVAL, CheckEditMode)
end

---------------------------------------------------------------------------
-- Neue Ränge automatisch: Lernt man einen höheren Rang eines Zaubers, kommt er auf jeden Aktionsknopf, auf dem
-- ein niedrigerer Rang dieses Zaubers liegt (gleicher Platz). Nur beim Lernen und nur für diesen Zauber – absichtlich
-- niedrigere Ränge anderer Zauber bleiben. Rang-Erkennung wie in ForeverSpellbook (Zusatztext "Rang 3", höchster
-- gelernter Rang aus dem Zauberbuch). Nur außerhalb des Kampfes und nur mit leerem Mauszeiger.
---------------------------------------------------------------------------

local issecret = _G.issecretvalue or function() return false end
local pendingRanks = {}   -- [Zaubername] = true: wurde gerade gelernt
local rankUpQueued = false

local function RankNumber(text)
    if type(text) ~= "string" or issecret(text) then return nil end
    return tonumber(text:match("(%d+)"))
end

local function SpellSubtext(spellID)
    return C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
end

local function LearnedSpellName(spellID)
    local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if type(name) == "string" and not issecret(name) then return name end
end

-- Höchster gelernter Rang je Zaubername aus dem Zauberbuch: { slot, bank, id, rank }
local function BestRanks(names)
    local best = {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo) then return best end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and (info.numSpellBookItems or 0) > 0 then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
                local name = item and item.name
                if name and not issecret(name) and names[name] and not item.isPassive
                    and not (future and item.itemType == future) then
                    local id = item.spellID or item.actionID
                    local sub = item.subName
                    if (not sub or sub == "") and id then sub = SpellSubtext(id) end
                    local rank = RankNumber(sub)
                    if rank and (not best[name] or rank > best[name].rank) then
                        best[name] = { slot = slot, bank = bank, id = id, rank = rank }
                    end
                end
            end
        end
    end
    return best
end

local function UpgradeRanks()
    rankUpQueued = false
    if not ns.db.autoRankUp or not next(pendingRanks) then wipe(pendingRanks) return end
    -- Im Kampf oder mit etwas am Mauszeiger: später nochmal (nach dem Kampf bzw. in einer Sekunde)
    if InCombatLockdown() then return end
    if GetCursorInfo() then
        rankUpQueued = true
        C_Timer.After(1, UpgradeRanks)
        return
    end
    if not (GetActionInfo and PlaceAction and C_SpellBook and C_SpellBook.PickupSpellBookItem) then return end
    local best = BestRanks(pendingRanks)
    wipe(pendingRanks)
    local count = 0
    for slot = 1, 180 do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "spell" and id and not issecret(id) then
            local name = LearnedSpellName(id)
            local target = name and best[name]
            local rank = target and RankNumber(SpellSubtext(id))
            if target and target.id ~= id and rank and rank < target.rank then
                ClearCursor()
                C_SpellBook.PickupSpellBookItem(target.slot, target.bank)
                if pcall(PlaceAction, slot) then count = count + 1 end
                ClearCursor()
            end
        end
    end
    if count > 0 then ns.Print(L("RANK_UPGRADED", count)) end
end

-- Zauber gelernt: merken und kurz danach prüfen (das Zauberbuch ist dann schon aktualisiert)
function ns.OnSpellLearned(spellID)
    local name = LearnedSpellName(spellID)
    if not name or not ns.db.autoRankUp then return end
    pendingRanks[name] = true
    if not rankUpQueued then
        rankUpQueued = true
        C_Timer.After(0.5, UpgradeRanks)
    end
end

-- Nach dem Kampf nachholen, was währenddessen gelernt wurde
function ns.UpgradeRanksAfterCombat()
    if next(pendingRanks) and not rankUpQueued then UpgradeRanks() end
end

function ns.SetupBars()
    ns.ready = true
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if isLoaded and isLoaded("Blizzard_NewPlayerExperience") then
        DisableTutorials()
    elseif NPE_LoadUI then
        hooksecurefunc("NPE_LoadUI", DisableTutorials)
    end
    ns.CreateProfessionButtons()
    ns.CreateFoodButtons()
    HookProcGlow()
    ns.ApplyLayout()
    C_Timer.NewTicker(FADE_INTERVAL, UpdateFading)

    ns.WatchEditMode()

    local events = CreateFrame("Frame")
    -- Nach dem Kampf ausstehende Änderungen übernehmen; nach Ladebildschirmen und Bearbeitungsmodus neu anordnen;
    -- neue oder verlernte Berufe in die Berufeleiste übernehmen
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED",
        "UPDATE_SHAPESHIFT_FORMS", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
        "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN",
        "UPDATE_BINDINGS", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Kampf beginnt: Testmodus beenden (Leisten werden nach dem Kampf wieder wie eingestellt)
            if ns.testMode then ns.SetTestMode(false) end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if layoutPending then ns.ApplyLayout() end
            ns.UpgradeRanksAfterCombat()
        elseif event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
            ns.OnSpellLearned((...)) -- erster Wert: die Zauber-ID
            ns.RequestLayout() -- Berufeleiste: neuer Berufs-Zauber
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            ns.UpdateProfessionCooldowns()
        elseif event == "BAG_UPDATE_DELAYED" then
            ns.OnBagsChanged()
        elseif event == "BAG_UPDATE_COOLDOWN" then
            ns.UpdateFoodButtons()
        elseif event == "UPDATE_BINDINGS" then
            ns.UpdateOwnHotkeys()
        else
            ns.RequestLayout()
        end
    end)
end
