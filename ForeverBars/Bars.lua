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
local BAR_GAP = 1      -- Abstand zwischen aneinanderliegenden Leisten
local SIDE_GAP = 6     -- Abstand der Berufeleiste zu den Aktionsleisten
local FRAME_SPACE = 4  -- Rand des Rahmens um eine Leiste (siehe UpdateBarFrame)

local function DefaultPosition(key)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local bars = ns.db.bars
    local function Scale(barKey) return math.max(0.3, (bars[barKey].scale or 100) / 100) end
    local function HolderHeight(barKey, fallback)
        local holder = holders[barKey]
        if holder and holder:GetHeight() > 1 then return holder:GetHeight() * holder:GetScale() end
        return fallback
    end
    local scale = Scale("bar1")
    local barWidth = (12 * ACTION_SIZE + 11 * (bars.bar1.spacing or 1)) * scale
    local barHeight = ACTION_SIZE * scale
    local left, right = width / 2 - barWidth / 2, width / 2 + barWidth / 2
    local function BarCenter(row) return EDGE + barHeight / 2 + row * (barHeight + BAR_GAP) end
    local stackTop = EDGE + 3 * barHeight + 2 * BAR_GAP           -- Oberkante der drei Aktionsleisten
    local smallRow = ACTION_SIZE * Scale("pet")                    -- Höhe der Begleiter-/Haltungsreihe
    local aboveSmall = stackTop + BAR_GAP + smallRow + BAR_GAP    -- darüber beginnen Leisten 6-8
    local microHeight = HolderHeight("micro", 40)
    local xpHeight = HolderHeight("xp", 12)
    local positions = {
        bar1 = { width / 2, BarCenter(0) }, bar2 = { width / 2, BarCenter(1) }, bar3 = { width / 2, BarCenter(2) },
        bar6 = { width / 2, aboveSmall + barHeight / 2 },
        bar7 = { width / 2, aboveSmall + barHeight * 1.5 + BAR_GAP },
        bar8 = { width / 2, aboveSmall + barHeight * 2.5 + BAR_GAP * 2 },
        bar4 = { width - 30, height / 2 }, bar5 = { width - 30 - ACTION_SIZE - 8, height / 2 },
        pet = { left, stackTop + BAR_GAP },     -- BOTTOMLEFT
        stance = { right, stackTop + BAR_GAP }, -- BOTTOMRIGHT
        prof = { left - SIDE_GAP - FRAME_SPACE, EDGE + FRAME_SPACE }, -- BOTTOMRIGHT (Rahmen eingerechnet)
        food = { right + SIDE_GAP + FRAME_SPACE, EDGE + FRAME_SPACE }, -- BOTTOMLEFT, gespiegelt zur Berufeleiste
        micro = { width - EDGE, EDGE },                        -- BOTTOMRIGHT
        bags = { width - EDGE, EDGE + microHeight + 2 },       -- BOTTOMRIGHT
        xp = { width / 2, height - EDGE },                     -- TOP
        rep = { width / 2, height - EDGE - xpHeight - 2 },     -- TOP
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

-- Stile der Knöpfe, alle im flachen Forever-Design: Randfarbe, Randstärke, Abstand des Symbols zum Rand
-- und Hintergrund leerer Plätze
local COLOR = ns.Style.COLOR
ns.SKINS = {
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

    -- Stil: Rand, Hintergrund leerer Plätze, Abstand des Symbols zum Rand
    local skin = GetSkin()
    if button.fbBorder then
        button.fbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = skin.size })
        button.fbBorder:SetBackdropBorderColor(unpack(skin.border))
        button.fbBorder:SetShown(db.showBorder)
    end
    if button.fbBackground then button.fbBackground:SetColorTexture(unpack(skin.background)) end
    -- Grüner "Ausgerüstet"-Rand, Zuschnitt des Symbols
    if button.Border then button.Border:SetAlpha(db.showEquipped and 1 or 0) end
    local icon = button.icon or button.Icon or (name and _G[name .. "Icon"])
    if icon then
        local crop = math.max(0, math.min(30, db.iconZoom or 8)) / 100
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
-- Berufeleiste: eigene geschützte Knöpfe, belegt mit den Berufen des Charakters
-- (aktive Berufs-Fähigkeiten aus dem Zauberbuch, z. B. Schmelzen, Kräutersuche; sonst der Beruf selbst)
---------------------------------------------------------------------------

local PROF_COUNT = 12
local profSpells = {} -- [i] = { spell = Zauber-ID oder Name, icon = Symbol, row = 1 Beruf / 2 Fertigkeit }

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

-- Liste der Berufs-Knöpfe neu ermitteln (Hauptberufe, Archäologie, Angeln, Kochen, Erste Hilfe).
-- Je Beruf eine Spalte: oben das Berufsfenster, darunter seine Fertigkeit (Entzaubern, Schmelzen …);
-- hat ein Beruf mehrere Fertigkeiten, bekommen die weiteren eigene Spalten (oben frei).
-- Jeder Eintrag bekommt col (Spalte ab 0) und row (1 = Fenster, 2 = Fertigkeit).
local FISHING_SLOT = 4 -- GetProfessions liefert Angeln an 4. Stelle
local function CollectProfessionSpells()
    wipe(profSpells)
    if not GetProfessions or not GetProfessionInfo then return end
    local indices = { GetProfessions() }
    local seen = {}
    local column = 0
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
            local window, skills = nil, {}
            if i == FISHING_SLOT then
                -- Angeln: die Fertigkeit (Auswerfen) trägt das Symbol des Berufs, das Fenster ein anderes
                for _, entry in ipairs(spells) do
                    if not window and entry.icon ~= icon then window = entry else table.insert(skills, entry) end
                end
            else
                -- Sonst öffnet die erste Fähigkeit das Berufsfenster, die weiteren sind Fertigkeiten
                window = table.remove(spells, 1)
                skills = spells
            end
            -- Ohne eigene Fähigkeit im Zauberbuch: den Beruf über seinen Namen öffnen
            if not window and #skills == 0 and name then window = { spell = name, icon = icon } end
            if window then
                window.col, window.row = column, 1
                table.insert(profSpells, window)
            end
            for k, entry in ipairs(skills) do
                entry.col, entry.row = column + k - 1, 2
                table.insert(profSpells, entry)
            end
            column = column + math.max(1, #skills)
        end
    end
end

local function UpdateProfessionCooldown(button)
    local entry = button.fbEntry
    if not entry or type(entry.spell) ~= "number" or not C_Spell or not C_Spell.GetSpellCooldown then
        button.cooldown:Clear()
        return
    end
    -- Werte unverändert an die Abklingzeit-Anzeige weiterreichen (keine eigene Rechnung)
    local info = C_Spell.GetSpellCooldown(entry.spell)
    if info then pcall(button.cooldown.SetCooldown, button.cooldown, info.startTime, info.duration) end
end

function ns.CreateProfessionButtons()
    for i = 1, PROF_COUNT do
        local name = "ForeverBarsProfButton" .. i
        if not _G[name] then
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
            button:SetScript("OnEnter", function(self)
                local mode = ns.db.buttonTooltip
                if mode == "NEVER" or (mode == "NOCOMBAT" and InCombatLockdown()) or not self.fbEntry then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if type(self.fbEntry.spell) == "number" then
                    GameTooltip:SetSpellByID(self.fbEntry.spell)
                else
                    GameTooltip:SetText(self.fbEntry.spell)
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function(self)
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
            end)
        end
    end
end

-- Knöpfe belegen (nur außerhalb des Kampfes); Rückgabe: Anzahl belegter Knöpfe
local function AssignProfessionButtons()
    CollectProfessionSpells()
    for i = 1, PROF_COUNT do
        local button = _G["ForeverBarsProfButton" .. i]
        local entry = profSpells[i]
        if button then
            button.fbEntry = entry
            button:SetAttribute("type", entry and "spell" or nil)
            button:SetAttribute("spell", entry and entry.spell or nil)
            button.icon:SetTexture(entry and entry.icon or nil)
            button:SetShown(entry ~= nil)
            UpdateProfessionCooldown(button)
        end
    end
    return #profSpells
end

function ns.UpdateProfessionCooldowns()
    for i = 1, PROF_COUNT do
        local button = _G["ForeverBarsProfButton" .. i]
        if button and button.fbEntry then UpdateProfessionCooldown(button) end
    end
end

---------------------------------------------------------------------------
-- Verpflegungsleiste: eigene geschützte Knöpfe mit dem Essen und Trinken aus den Taschen
-- (Gegenstandsart "Verbrauchbar", Unterart "Speis & Trank"), höchste Stufe zuerst
---------------------------------------------------------------------------

local FOOD_COUNT = 18
-- Gegenstandsart "Verbrauchbar" (0) und ihre Unterarten: 5 = Speis & Trank, 1 = Trank, 2 = Elixier, 3 = Fläschchen
local CONSUMABLE_CLASS = 0
local FOOD_SUBCLASS = 5
local FLASK_SUBCLASSES = { [1] = true, [2] = true, [3] = true }
local foodItems = {}                   -- [i] = { item = Gegenstands-ID, icon = Symbol, row, col }
local foodSignature = ""               -- welche Gegenstände gerade belegt sind (für Änderungen)

local function ItemInfoInstant(itemID)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(itemID) end
    return GetItemInfoInstant and GetItemInfoInstant(itemID)
end

local function ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) end
    return GetItemCount and GetItemCount(itemID) or 0
end

-- Getränk oder Essen? Der Zauber eines Getränks heißt wie Blizzards "Trinken" (Zauber 430, in jeder Sprache
-- passend übersetzt). Rückfall: im Tooltip steht Mana, aber keine Gesundheit.
local DRINK_SPELL = 430
local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and (GetSpellInfo(spellID))
end

local drinkCache = {} -- [Gegenstand] = true/false (nur sichere Ergebnisse)

local function IsDrink(itemID)
    if drinkCache[itemID] ~= nil then return drinkCache[itemID] end
    local getItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
    local spellName = getItemSpell and getItemSpell(itemID)
    local drinkName = SpellName(DRINK_SPELL)
    if spellName and drinkName then
        drinkCache[itemID] = spellName == drinkName
        return drinkCache[itemID]
    end
    if C_TooltipInfo and C_TooltipInfo.GetItemByID and MANA and HEALTH then
        local data = C_TooltipInfo.GetItemByID(itemID)
        local mana, health = false, false
        for _, line in ipairs(data and data.lines or {}) do
            local text = line.leftText or ""
            if text:find(MANA, 1, true) then mana = true end
            if text:find(HEALTH, 1, true) then health = true end
        end
        return mana and not health
    end
    return false
end

-- Taschen durchsuchen. Jeder Eintrag bekommt row (1 = Essen, 2 = Getränk, 3 = Fläschchen/Elixier/Trank) und
-- col (Platz in der Reihe, höchste benötigte Stufe zuerst). perRow (optional) = höchstens so viele je Reihe.
-- Rückgabe: Liste (nach Reihen) und "Fingerabdruck"
local foodLimit -- zuletzt verwendete Grenze je Reihe (damit der Vergleich bei Taschenänderungen passt)
local function CollectFood(perRow)
    local groups, seen = { {}, {}, {} }, {}
    local numSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local itemAt = C_Container and C_Container.GetContainerItemID or GetContainerItemID
    if not numSlots or not itemAt then return {}, "" end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, numSlots(bag) or 0 do
            local itemID = itemAt(bag, slot)
            if itemID and not seen[itemID] then
                seen[itemID] = true
                local _, _, _, _, icon, classID, subclassID = ItemInfoInstant(itemID)
                local row
                if classID == CONSUMABLE_CLASS and subclassID == FOOD_SUBCLASS then
                    row = IsDrink(itemID) and 2 or 1
                elseif classID == CONSUMABLE_CLASS and FLASK_SUBCLASSES[subclassID] then
                    row = 3
                end
                if row then
                    local level = 0
                    if C_Item and C_Item.GetItemInfo then
                        level = select(5, C_Item.GetItemInfo(itemID)) or 0 -- benötigte Stufe
                    end
                    table.insert(groups[row], { item = itemID, icon = icon, level = level, row = row })
                end
            end
        end
    end
    local list, ids = {}, {}
    for _, group in ipairs(groups) do
        table.sort(group, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            return a.item < b.item
        end)
        for col, entry in ipairs(group) do
            if perRow and col > perRow then break end
            entry.col = col - 1
            table.insert(list, entry)
            table.insert(ids, entry.item .. ":" .. entry.row)
        end
    end
    return list, table.concat(ids, ",")
end

local function UpdateFoodButton(button)
    local entry = button.fbEntry
    if not entry then return end
    button.Count:SetText(ItemCount(entry.item))
    -- Abklingzeit unverändert an die Anzeige weiterreichen (keine eigene Rechnung)
    local getCooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    if getCooldown then
        local start, duration = getCooldown(entry.item)
        if start then pcall(button.cooldown.SetCooldown, button.cooldown, start, duration) end
    end
end

-- Eigener geschützter Knopf (Berufe, Verpflegung): Symbol, Abklingzeit, Anzahl, Tooltip
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
    return button
end

function ns.CreateFoodButtons()
    for i = 1, FOOD_COUNT do
        local name = "ForeverBarsFoodButton" .. i
        if not _G[name] then
            CreateOwnButton(name, function(entry) GameTooltip:SetItemByID(entry.item) end)
        end
    end
end

-- Knöpfe belegen (nur außerhalb des Kampfes); Rückgabe: Anzahl belegter Knöpfe
local function AssignFoodButtons(perRow)
    foodLimit = perRow
    foodItems, foodSignature = CollectFood(perRow)
    for i = 1, FOOD_COUNT do
        local button = _G["ForeverBarsFoodButton" .. i]
        local entry = foodItems[i]
        if button then
            button.fbEntry = entry
            button:SetAttribute("type", entry and "item" or nil)
            button:SetAttribute("item", entry and ("item:" .. entry.item) or nil)
            button.icon:SetTexture(entry and entry.icon or nil)
            button.Count:SetText("")
            button:SetShown(entry ~= nil)
            if entry then UpdateFoodButton(button) else button.cooldown:Clear() end
        end
    end
    return #foodItems
end

-- Taschen geändert: neu belegen, wenn sich die Auswahl geändert hat, sonst nur Anzahl und Abklingzeit
function ns.OnBagsChanged()
    local _, signature = CollectFood(foodLimit)
    if signature ~= foodSignature then
        ns.RequestLayout() -- im Kampf erst danach (geschützte Knöpfe)
    end
    ns.UpdateFoodButtons()
end

function ns.UpdateFoodButtons()
    for i = 1, FOOD_COUNT do
        local button = _G["ForeverBarsFoodButton" .. i]
        if button and button.fbEntry then UpdateFoodButton(button) end
    end
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

local function UpdateBarFrame(def, cfg, holder)
    local frame = holder.fbFrame
    if not cfg.frame then
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
        holder.fbFrame = frame
    end
    -- Unter den Knöpfen (die Knöpfe liegen eine Ebene höher im Halter)
    frame:SetFrameLevel(holder:GetFrameLevel())
    local withTitle = cfg.frameTitle and true or false
    frame.header:SetShown(withTitle)
    frame.line:SetShown(withTitle)
    frame.title:SetShown(withTitle)
    -- Eigener Titel aus dem Menü, sonst der Standardtitel der Leiste (z. B. "Berufe") bzw. ihr Name
    local titleText = strtrim(cfg.frameTitleText or "")
    frame.title:SetText(titleText ~= "" and titleText or L(def.titleKey or def.textKey))
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
    return holder
end

-- Knöpfe in Reihen anordnen. Wachstumsrichtung: von links nach rechts bzw. rechts nach links,
-- von oben nach unten bzw. unten nach oben (der erste Knopf sitzt in der Ecke, von der aus es wächst).
local function LayoutButtons(def, cfg, holder)
    local buttons = GetButtons(def, cfg)
    local size = def.kind == "bags" and SMALL_SIZE or ACTION_SIZE
    local wanted = def.bagButtons and #buttons or (cfg.buttons or def.count)
    -- Haltungen: immer genau so viele Plätze, wie der Charakter hat; Berufe: höchstens so viele
    if def.kind == "stance" then
        wanted = math.max(1, GetNumShapeshiftForms and GetNumShapeshiftForms() or 0)
    elseif def.kind == "prof" then
        wanted = math.min(wanted, math.max(1, AssignProfessionButtons()))
    elseif def.kind == "food" then
        -- In Reihen getrennt: je Reihe höchstens "Knöpfe pro Reihe"
        wanted = math.min(wanted, math.max(1, AssignFoodButtons(cfg.profRows and math.max(1, cfg.perRow or 4) or nil)))
    end
    local count = math.max(1, math.min(wanted, #buttons))
    local perRow = math.max(1, math.min(cfg.perRow or count, count))
    local rows = math.ceil(count / perRow)
    -- Platz (Spalte, Reihe) je Knopf; wahlweise nach Reihen getrennt: Berufeleiste Fenster oben, Fertigkeit
    -- darunter; Verpflegungsleiste Essen, Getränke, Fläschchen/Tränke. Leere Reihen fallen weg.
    local slots = {}
    if (def.kind == "prof" or def.kind == "food") and cfg.profRows then
        local entries = def.kind == "prof" and profSpells or foodItems
        local used, maxColumn = {}, 0
        for i = 1, count do
            local entry = entries[i]
            if entry then
                used[entry.row or 1] = true
                maxColumn = math.max(maxColumn, entry.col or 0)
            end
        end
        -- Genutzte Reihen der Reihe nach durchnummerieren (0 = oberste). Verpflegung: festes Raster
        -- (immer 3 Reihen, "Knöpfe pro Reihe" breit), damit die Leiste gleich groß bleibt
        local fixed = def.kind == "food"
        local rowIndex, nextRow = {}, 0
        for row = 1, 3 do
            if used[row] or fixed then
                rowIndex[row] = nextRow
                nextRow = nextRow + 1
            end
        end
        for i = 1, count do
            local entry = entries[i]
            slots[i] = { entry and entry.col or (i - 1), entry and rowIndex[entry.row or 1] or 0 }
        end
        perRow = fixed and math.max(1, cfg.perRow or 4) or (maxColumn + 1)
        rows = math.max(1, nextRow)
    else
        for i = 1, count do slots[i] = { (i - 1) % perRow, math.floor((i - 1) / perRow) } end
    end
    local gap = cfg.spacing or 1
    local toLeft, toTop = cfg.growX == "LEFT", cfg.growY == "UP"
    local corner = (toTop and "BOTTOM" or "TOP") .. (toLeft and "RIGHT" or "LEFT")
    local shown = {}
    for i, button in ipairs(buttons) do
        if i <= count then
            shown[button] = true
            button:SetParent(holder)
            button:SetSize(size, size)
            button:ClearAllPoints()
            local column, row = slots[i][1], slots[i][2]
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
    -- Blizzards Status-Leisten (Erfahrung/Ruf) rufen bei jeder Aktualisierung
    -- self:GetParent():CheckForLayoutChange() auf – gemeint ist der StatusTrackingBarManager, ihr
    -- eigentlicher Elternrahmen. Der Halter reicht den Aufruf an den echten Manager weiter; ohne das gibt
    -- es Lua-Fehler (z. B. beim Öffnen/Schließen des Bearbeitungsmodus, Blizzard-Code Zeile 228).
    if frame.GetStatusTrackingManager and not holder.CheckForLayoutChange then
        holder.CheckForLayoutChange = function()
            local manager = _G.StatusTrackingBarManager
            if manager and manager ~= holder and manager.CheckForLayoutChange then
                pcall(manager.CheckForLayoutChange, manager)
            end
        end
    end
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

local function VisibilityDriver(def, cfg)
    if not cfg.enabled then return "hide" end
    if ns.unlocked or ns.testMode then return "show" end
    -- Haltungsleiste ohne Haltungen, Auren oder Gestalten ausblenden
    if def.kind == "stance" and (GetNumShapeshiftForms and GetNumShapeshiftForms() or 0) == 0 then return "hide" end
    -- Eigene Bedingung ersetzt alle anderen Einstellungen
    local custom = cfg.useCustom and strtrim(cfg.custom or "")
    if custom and custom ~= "" then return custom end
    local parts = { "[petbattle] hide" }
    for _, entry in ipairs(HIDE_CONDITIONS) do
        if cfg[entry.key] then table.insert(parts, entry.condition .. " hide") end
    end
    -- Allgemeine Einstellung: alle Leisten nur im Kampf zeigen
    if ns.db.hideOutOfCombat then table.insert(parts, "[nocombat] hide") end
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
            -- x/y ist die Mitte; gespeichert wird der Ankerpunkt der Leiste
            ns.SetBarCenter(self.key, x, y)
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
        holder:SetPoint(cfg.point or "CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        -- Deckkraft; beim Einblenden per Maus übernimmt das die Überblendung (siehe UpdateFading)
        if not cfg.fadeMouseover or ns.unlocked or ns.testMode then
            holder:SetAlpha((cfg.alpha or 100) / 100)
            holder.fbAlpha = nil
        end
        SetupPaging(def, cfg, holder)
        -- Abgesichert, damit eine fehlerhafte eigene Bedingung keinen Fehler auslöst
        if not pcall(RegisterStateDriver, holder, "visibility", VisibilityDriver(def, cfg)) then
            RegisterStateDriver(holder, "visibility", "[petbattle] hide; show")
        end
        UpdateBarFrame(def, cfg, holder)
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
        if holder and cfg.enabled and cfg.fadeMouseover and not ns.unlocked and not ns.testMode then
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

function ns.SetupBars()
    ns.ready = true
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
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
        "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN" }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Kampf beginnt: Testmodus beenden (Leisten werden nach dem Kampf wieder wie eingestellt)
            if ns.testMode then ns.SetTestMode(false) end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if layoutPending then ns.ApplyLayout() end
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            ns.UpdateProfessionCooldowns()
        elseif event == "BAG_UPDATE_DELAYED" then
            ns.OnBagsChanged()
        elseif event == "BAG_UPDATE_COOLDOWN" then
            ns.UpdateFoodButtons()
        else
            ns.RequestLayout()
        end
    end)
end
