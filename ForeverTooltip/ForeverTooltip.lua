-- ForeverTooltip (Prototyp): Blizzards Tooltip im Stil der Forever-Fenster – dunkle Fläche, feiner grauer Rand,
-- goldene Linie oben (wie der Tooltip von ForeverQuests). Rahmenfarbe nach Gegenstandsqualität bzw. Klasse/Reaktion,
-- ein paar Zusatzinfos (Gegenstandsstufe, Ziel des Spielers, IDs) und ein eigener, verschiebbarer Ankerplatz
-- (entsperren über /fmove, /ftip lock oder Minimap-Rechtsklick). Nur Aussehen und Ort: Blizzards Tooltip bleibt
-- derselbe (eigene Flächen liegen hinter dem Text, Blizzards Rahmen wird nur unsichtbar, Inhalte nur angehängt).
local ADDON_NAME = ...
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR
local WHITE = "Interface\\Buttons\\WHITE8x8"

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------
local DEFAULTS = {
    skin = true,          -- Forever-Stil
    colorBorder = true,   -- Rahmen in Qualitäts- bzw. Klassen-/Reaktionsfarbe
    goldEdge = true,      -- Test: Rahmen rundum im Gold der Oberkante (aus = grau mit Goldlinie oben)
    classNames = true,    -- Spielernamen in Klassenfarbe
    itemLevel = true,     -- Gegenstandsstufe bei Ausrüstung
    showTarget = true,    -- "Ziel: …" bei Einheiten
    showIDs = false,      -- Gegenstands-/Zauber-ID
    statPerPoint = true,  -- Charakterfenster: bei Stärke, Beweglichkeit … zeigen, was 1 Punkt bringt
    flatHealth = true,    -- Lebensbalken flach in Klassen-/Reaktionsfarbe (falls er angezeigt wird)
    showHealthBar = false, -- Lebensbalken unter dem Tooltip (Standard: aus, unnötig)
    atCursor = true,      -- am Mauszeiger statt am Ankerplatz (Standard)
    scale = 1,
    bgAlpha = 75,         -- Deckkraft der Tooltip-Fläche in Prozent (etwas durchsichtig)
    locked = true,
    pos = nil,            -- Ankerplatz { x, y } (BOTTOMRIGHT, von unten rechts); nil = Standard
    minimapAngle = 300,
}

local db
local function GetDB()
    if type(_G.ForeverTooltipDB) ~= "table" then _G.ForeverTooltipDB = db or {} end
    db = _G.ForeverTooltipDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    -- einmalig: neuer Standard "am Mauszeiger" (vorher Ankerplatz)
    if not db.atCursorV2 then
        db.atCursor = true
        db.atCursorV2 = true
    end
    return db
end

local issecret = issecretvalue or function() return false end
local function IsSecret(...)
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return true end
    end
    return false
end

local function Safe(where, fn) return UI.Safe("ForeverTooltip", where, fn) end
local function Chat(text) UI.Chat("ForeverTooltip", text) end

---------------------------------------------------------------------------
-- Stil: eigene Fläche und Kanten hinter dem Text, Blizzards Rahmen (NineSlice) unsichtbar
---------------------------------------------------------------------------
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip",
    "SettingsTooltip" } -- (Tooltip im Optionen-Fenster von Blizzard)
local skinned = {}

local function SetEdgeColor(tip, r, g, b, a, topToo)
    local s = tip.ftSkin
    if not s then return end
    for i = 2, 4 do s.edges[i]:SetVertexColor(r, g, b, a) end
    if topToo then
        s.edges[1]:SetVertexColor(r, g, b, math.min(1, a + 0.1))
    else
        s.edges[1]:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
    end
end

local function ResetColors(tip)
    if GetDB().goldEdge then
        -- rundum dieselbe Farbe wie die Goldlinie oben
        local s = tip.ftSkin
        if not s then return end
        for i = 1, 4 do s.edges[i]:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7) end
        return
    end
    SetEdgeColor(tip, C.border[1], C.border[2], C.border[3], 1, false)
end

local function ApplyLook(tip)
    local s = tip.ftSkin
    if not s then return end
    local on = GetDB().skin
    -- Deckkraft der Fläche (Regler im Menü); Text und Rand bleiben voll sichtbar
    s.bg:SetColorTexture(C.background[1], C.background[2], C.background[3], (GetDB().bgAlpha or 75) / 100)
    s.bg:SetShown(on)
    for _, e in ipairs(s.edges) do e:SetShown(on) end
    if tip.NineSlice then tip.NineSlice:SetAlpha(on and 0 or 1) end
end

local function Skin(tip)
    if not tip or skinned[tip] then return end
    skinned[tip] = true
    local s = { edges = {} }
    s.bg = tip:CreateTexture(nil, "BACKGROUND", nil, -8)
    s.bg:SetAllPoints()
    s.bg:SetColorTexture(C.background[1], C.background[2], C.background[3], 0.94)
    local sides = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }
    for i, side in ipairs(sides) do
        local e = tip:CreateTexture(nil, "BACKGROUND", nil, -7)
        e:SetTexture(WHITE)
        e:SetPoint(side[1])
        e:SetPoint(side[2])
        if side[3] then e:SetHeight(1) else e:SetWidth(1) end
        s.edges[i] = e
    end
    tip.ftSkin = s
    ResetColors(tip)
    -- Blizzard setzt seinen Rahmen bei jedem Anzeigen neu: danach wieder unsichtbar
    tip:HookScript("OnShow", function(self) ApplyLook(self) end)
    if tip.HookScript then
        pcall(tip.HookScript, tip, "OnTooltipCleared", function(self) ResetColors(self) end)
    end
    ApplyLook(tip)
end

local function SkinAll()
    for _, name in ipairs(TOOLTIPS) do Skin(_G[name]) end
end

-- Lebensbalken unter dem Tooltip: flach statt Blizzards Grafik
local function StyleHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or bar.ftStyled then return end
    bar.ftStyled = true
    bar.ftBlizzTexture = bar:GetStatusBarTexture() and bar:GetStatusBarTexture():GetTexture()
    bar.ftBg = bar:CreateTexture(nil, "BACKGROUND")
    bar.ftBg:SetAllPoints()
    bar.ftBg:SetColorTexture(0, 0, 0, 0.6)
end

local function ApplyHealthBar()
    local bar = _G.GameTooltipStatusBar
    if not bar or not bar.ftStyled then return end
    local on = GetDB().flatHealth and GetDB().skin
    if on then
        bar:SetStatusBarTexture(WHITE)
        bar:SetHeight(5)
    elseif bar.ftBlizzTexture then
        bar:SetStatusBarTexture(bar.ftBlizzTexture)
    end
    bar.ftBg:SetShown(on and true or false)
    -- Lebensbalken unter dem Tooltip standardmäßig weg (unnötig, das Leben zeigen Rahmen und Plaketten):
    -- nur unsichtbar (Alpha 0, gegen Zurücksetzen abgesichert), kein Hide an Blizzards Rahmen
    if GetDB().showHealthBar then
        if UI.ShowBlizzard then UI.ShowBlizzard(bar) end
    elseif UI.HideBlizzard then
        UI.HideBlizzard(bar, { when = function() return not GetDB().showHealthBar end })
    end
end

---------------------------------------------------------------------------
-- Inhalte: Farben und Zusatzzeilen
---------------------------------------------------------------------------
local function ClassRGB(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
end

local function ReactionRGB(unit)
    local reaction = UnitReaction(unit, "player")
    if IsSecret(reaction) or not reaction then return end
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
end

-- Mischzeilen wie "Gefährte von 兔肥 猛斤": enthält eine Zeile chinesische/koreanische Zeichen, nimmt das Spiel für
-- die ganze Zeile eine asiatische Schrift – der fehlen ä, ö, ü (Kästchen). Darum solche Zeilen teilen: der Text vor
-- dem ersten asiatischen Zeichen links, der Rest (meist ein Name) rechts – jede Hälfte bekommt ihre eigene Schrift.
local ASIAN = "[\227-\237][\128-\191][\128-\191]" -- UTF-8 von U+3000 bis U+D7FF (CJK, Kana, Hangul)
local LATIN = "[\195\197][\128-\191]"             -- UTF-8 von ä, ö, ü, ß, é … (U+00C0 bis U+017F)
local function SplitMixedLines(tip)
    local name = tip:GetName()
    if not name then return end
    for i = 1, tip:NumLines() do
        local left, right = _G[name .. "TextLeft" .. i], _G[name .. "TextRight" .. i]
        local text = left and left:GetText()
        if text and not IsSecret(text) and right and not (right:IsShown() and (right:GetText() or "") ~= "")
            and text:find(LATIN) then
            local at = text:find(ASIAN)
            if at and at > 1 then
                local head, rest = strtrim(text:sub(1, at - 1)), text:sub(at)
                if head:find(LATIN) then
                    left:SetText(head)
                    right:SetText(rest)
                    right:SetTextColor(left:GetTextColor())
                    right:Show()
                end
            end
        end
    end
end

local function OnUnit(tip)
    if not skinned[tip] then return end
    local d = GetDB()
    local _, unit = tip:GetUnit()
    if not unit or IsSecret(unit) then return end
    pcall(SplitMixedLines, tip)
    local r, g, b
    local isPlayer = UnitIsPlayer(unit)
    if not IsSecret(isPlayer) and isPlayer then
        local _, class = UnitClass(unit)
        if not IsSecret(class) then r, g, b = ClassRGB(class) end
        -- Name (erste Zeile) in Klassenfarbe
        if r and d.classNames then
            local first = _G[tip:GetName() .. "TextLeft1"]
            if first then first:SetTextColor(r, g, b) end
        end
    else
        r, g, b = ReactionRGB(unit)
    end
    if r and d.colorBorder and d.skin then SetEdgeColor(tip, r, g, b, 0.85, true) end
    if r and d.flatHealth and d.skin and tip == GameTooltip and _G.GameTooltipStatusBar then
        _G.GameTooltipStatusBar:SetStatusBarColor(r, g, b)
    end
    -- Ziel der Einheit
    if d.showTarget then
        local target = unit .. "target"
        if UnitExists(target) then
            local name = UnitName(target)
            if name and not IsSecret(name) then
                local tr, tg, tb = 1, 1, 1
                if UnitIsUnit(target, "player") then
                    name, tr, tg, tb = T(">> DU <<", ">> YOU <<"), 1, 0.3, 0.3
                elseif UnitIsPlayer(target) then
                    local _, tclass = UnitClass(target)
                    if not IsSecret(tclass) then tr, tg, tb = ClassRGB(tclass) end
                    tr, tg, tb = tr or 1, tg or 1, tb or 1
                end
                tip:AddDoubleLine(T("Ziel:", "Target:"), name, 0.6, 0.6, 0.6, tr, tg, tb)
            end
        end
    end
    tip:Show() -- Größe an die neue Zeile anpassen
end

local function OnItem(tip, itemID)
    if not skinned[tip] then return end
    local d = GetDB()
    local _, link = tip:GetItem()
    if IsSecret(link) then return end
    local info = link or itemID
    if not info then return end
    -- (im Forever-Client gibt es nur noch C_Item.GetItemInfo – die alte GetItemInfo fehlt)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return end
    local _, _, quality, level, _, _, _, _, equipLoc = getInfo(info)
    local qualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
    if quality and qualityColor and d.colorBorder and d.skin and quality >= 2 then
        local r, g, b = qualityColor(quality)
        SetEdgeColor(tip, r, g, b, 0.85, true)
    end
    local added = false
    if d.itemLevel and level and level > 1 and equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
        and equipLoc ~= "INVTYPE_BAG" then
        tip:AddLine(T("Gegenstandsstufe ", "Item level ") .. level, 1, 0.82, 0)
        added = true
    end
    if d.showIDs then
        local id = itemID or (link and tonumber(link:match("item:(%d+)")))
        if id then
            tip:AddLine("ID " .. id, 0.5, 0.5, 0.5)
            added = true
        end
    end
    if added then tip:Show() end
end

local function OnSpell(tip, spellID)
    if not skinned[tip] or not GetDB().showIDs or not spellID or IsSecret(spellID) then return end
    tip:AddLine(T("Zauber-ID ", "Spell ID ") .. spellID, 0.5, 0.5, 0.5)
    tip:Show()
end

local function HookContent()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        local K = Enum.TooltipDataType
        TooltipDataProcessor.AddTooltipPostCall(K.Unit, function(tip) pcall(OnUnit, tip) end)
        TooltipDataProcessor.AddTooltipPostCall(K.Item, function(tip, data) pcall(OnItem, tip, data and data.id) end)
        if K.Spell then
            TooltipDataProcessor.AddTooltipPostCall(K.Spell, function(tip, data) pcall(OnSpell, tip, data and data.id) end)
        end
    else
        for _, name in ipairs(TOOLTIPS) do
            local tip = _G[name]
            if tip then
                pcall(tip.HookScript, tip, "OnTooltipSetUnit", function(self) pcall(OnUnit, self) end)
                pcall(tip.HookScript, tip, "OnTooltipSetItem", function(self) pcall(OnItem, self) end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Ort: eigener Ankerplatz (verschiebbar wie alle Forever-Rahmen) oder am Mauszeiger
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "ForeverTooltipAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(180, 64)
anchor:SetFrameStrata("DIALOG")
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
anchor:RegisterForDrag("LeftButton")
UI.SetFlat(anchor, { 1, 0.82, 0, 0.18 })
anchor:SetBackdropBorderColor(1, 0.82, 0, 1)
anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
anchor.text:SetPoint("CENTER")
anchor.text:SetText(T("Tooltip\nziehen zum Verschieben", "Tooltip\ndrag to move"))
anchor:Hide()

local function PlaceAnchor()
    local d = GetDB()
    anchor:ClearAllPoints()
    if d.pos then
        anchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", d.pos[1], d.pos[2])
    else
        anchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -6, 216) -- Standard: rechts über dem Details-Fenster
    end
end

-- Tooltip wächst vom Ankerplatz weg zur Bildschirmmitte hin
local function AnchorCorner()
    local x, y = anchor:GetCenter()
    if not x then return "BOTTOMRIGHT" end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local v = (y > h / 2) and "TOP" or "BOTTOM"
    local hz = (x > w / 2) and "RIGHT" or "LEFT"
    return v .. hz
end

local function SetLocked(locked)
    local d = GetDB()
    d.locked = locked and true or false
    anchor:SetShown(not d.locked)
    anchor:EnableMouse(not d.locked)
end

UI.AddMover(anchor)
anchor:SetScript("OnDragStart", function(self)
    if GetDB().locked then return end
    UI.BeginDrag(self)
    self:StartMoving()
end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local dx, dy = UI.EndDrag()
    local right, bottom = self:GetRight(), self:GetBottom()
    if right and bottom then
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        right, bottom = right * s + dx, bottom * s + dy
        GetDB().pos = { right - UIParent:GetWidth(), bottom }
    end
    PlaceAnchor()
end)

local function HookAnchor()
    if not GameTooltip_SetDefaultAnchor then return end
    -- gilt für jeden Tooltip, der Blizzards Standardplatz benutzt – auch die eigenen Tooltips der Forever-Addons
    -- (z. B. Erfahrungs-/Rufleiste von ForeverBars), damit alle an derselben Stelle erscheinen
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip, parent)
        if not (tip and tip.SetOwner and tip.ClearAllPoints) then return end
        local d = GetDB()
        if d.atCursor then
            tip:SetOwner(parent or UIParent, "ANCHOR_CURSOR_RIGHT", 16, -8)
        else
            local corner = AnchorCorner()
            tip:ClearAllPoints()
            tip:SetPoint(corner, anchor, corner, 0, 0)
        end
    end)
end

local function ApplyScale()
    local s = GetDB().scale or 1
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
        if _G[name] then _G[name]:SetScale(s) end
    end
end

local function ApplyAll()
    for tip in pairs(skinned) do ApplyLook(tip) end
    ApplyHealthBar()
    ApplyScale()
    PlaceAnchor()
end

---------------------------------------------------------------------------
-- Werte pro Punkt (Charakterfenster): unter Blizzards Tooltip von Stärke, Beweglichkeit, Ausdauer, Intelligenz und
-- Willenskraft steht, was EIN Punkt bringt (z. B. "1 Stärke = 2 Angriffskraft", "20 Beweglichkeit = 1 % krit.").
-- Die Werte kommen aus denselben Spielfunktionen, die Blizzards Tooltip nutzt (GetAttackPowerForStat usw.) – sie
-- gelten also für Klasse und Stufe des Charakters. Nur außerhalb des Kampfes (keine Kampfberechnungen), nur angehängt.
---------------------------------------------------------------------------
do
    local STR, AGI, STA, INT, SPI = LE_UNIT_STAT_STRENGTH or 1, LE_UNIT_STAT_AGILITY or 2, LE_UNIT_STAT_STAMINA or 3,
        LE_UNIT_STAT_INTELLECT or 4, LE_UNIT_STAT_SPIRIT or 5
    local statOf = setmetatable({}, { __mode = "k" })  -- [Blizzards Wert-Zeile] = Wert-Nummer
    local hooked = setmetatable({}, { __mode = "k" })
    local BLOCKERS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
    local NO_MANA = { WARRIOR = true, ROGUE = true }

    local function Num(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        if ok and type(v) == "number" and not issecret(v) then return v end
    end
    -- Zuwachs je Punkt (über 100 Punkte gemessen, damit Rundungen des Spiels nicht stören)
    local function Slope(fn, stat, base)
        local a, b = Num(fn, stat, base + 100), Num(fn, stat, base)
        if a and b then return (a - b) / 100 end
    end
    local function Fmt(v)
        local s
        if math.abs(v - math.floor(v + 0.5)) < 0.005 then
            s = tostring(math.floor(v + 0.5))
        else
            s = (string.format("%.2f", v):gsub("0+$", ""))
        end
        return (s:gsub("%.", T(",", ".")))
    end
    -- "1 Stärke = 2 Angriffskraft" bzw. bei kleinen Werten umgekehrt "20 Stärke = 1 Blockwert"
    local function PerPoint(lines, statName, perPoint, what, suffix, note)
        if not perPoint or perPoint <= 0 then return end
        suffix, note = suffix or "", note and ("|cff8a8a8a" .. note .. "|r") or ""
        if perPoint >= 0.995 then
            lines[#lines + 1] = "1 " .. statName .. " = " .. Fmt(perPoint) .. suffix .. " " .. what .. note
        else
            lines[#lines + 1] = Fmt(1 / perPoint) .. " " .. statName .. " = 1" .. suffix .. " " .. what .. note
        end
    end

    -------------------------------------------------------------------------
    -- Nachmessen beim Ausrüstungswechsel: Wie viel kommt von einem Punkt auf dem Gegenstand tatsächlich an (Talente/Buffs
    -- mit Prozent-Bonus), und wie viel Leben/Mana bringt ein Punkt Ausdauer/Intelligenz wirklich? Vorher-Stand beim
    -- Wechsel, Nachher-Stand kurz danach; Unterschied der Gegenstandswerte (C_Item.GetItemStats) gegen den Unterschied
    -- beim Charakter. Je Charakter gespeichert (ForeverTooltipCharDB, keine Einstellung). Nur außerhalb des Kampfes.
    -------------------------------------------------------------------------
    local ITEM_KEYS = { [STR] = "ITEM_MOD_STRENGTH_SHORT", [AGI] = "ITEM_MOD_AGILITY_SHORT",
        [STA] = "ITEM_MOD_STAMINA_SHORT", [INT] = "ITEM_MOD_INTELLECT_SHORT", [SPI] = "ITEM_MOD_SPIRIT_SHORT" }
    local MIN_DELTA = 4 -- kleinere Unterschiede sind wegen der Rundung zu ungenau
    local function CharDB()
        if type(_G.ForeverTooltipCharDB) ~= "table" then _G.ForeverTooltipCharDB = {} end
        local d = _G.ForeverTooltipCharDB
        d.ratio = d.ratio or {}
        return d
    end
    local function ItemStats(link)
        local out = {}
        if not link then return out end
        local get = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
        local ok, stats = pcall(get, link)
        if ok and type(stats) == "table" then
            for s, key in pairs(ITEM_KEYS) do out[s] = tonumber(stats[key]) or 0 end
        end
        return out
    end
    local function Snapshot()
        local snap = { hp = Num(UnitHealthMax, "player"), mana = Num(UnitPowerMax, "player", 0) }
        for s in pairs(ITEM_KEYS) do
            local ok, _, eff = pcall(UnitStat, "player", s)
            snap[s] = (ok and type(eff) == "number" and not issecret(eff)) and eff or nil
        end
        return snap
    end
    local links = {}
    local function RememberLinks()
        for slot = 1, 19 do links[slot] = GetInventoryItemLink("player", slot) end
    end
    local function Measure(before, oldItem, newItem)
        if InCombatLockdown() then return end
        local after, d = Snapshot(), CharDB()
        for s in pairs(ITEM_KEYS) do
            local itemDelta = (newItem[s] or 0) - (oldItem[s] or 0)
            local effDelta = before[s] and after[s] and (after[s] - before[s])
            if effDelta and math.abs(itemDelta) >= MIN_DELTA then
                local ratio = effDelta / itemDelta
                -- nur Plausibles merken (sonst ist z. B. gleichzeitig ein Buff ausgelaufen)
                if ratio >= 0.95 and ratio <= 1.6 then d.ratio[s] = ratio end
            end
            if effDelta and math.abs(effDelta) >= MIN_DELTA then
                if s == STA and before.hp and after.hp then
                    local per = (after.hp - before.hp) / effDelta
                    if per >= 5 and per <= 40 then d.hpPerSta = per end
                elseif s == INT and before.mana and after.mana and before.mana > 0 then
                    local per = (after.mana - before.mana) / effDelta
                    if per >= 5 and per <= 40 then d.manaPerInt = per end
                end
            end
        end
    end
    local measure = CreateFrame("Frame")
    measure:RegisterEvent("PLAYER_LOGIN")
    measure:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    measure:SetScript("OnEvent", function(_, event, slot)
        if event == "PLAYER_LOGIN" then RememberLinks() return end
        if type(slot) ~= "number" then return end
        local oldLink, newLink = links[slot], GetInventoryItemLink("player", slot)
        links[slot] = newLink
        if InCombatLockdown() or not GetDB().statPerPoint then return end
        local before, oldItem, newItem = Snapshot(), ItemStats(oldLink), ItemStats(newLink)
        C_Timer.After(1, function() pcall(Measure, before, oldItem, newItem) end)
    end)

    -- Grundwert mit Talenten/Buffs: aus der Messung, sonst die Spielregel
    local function Ratio(stat) return CharDB().ratio[stat] end

    local function AddLines(frame)
        if not GetDB().statPerPoint or InCombatLockdown() then return end
        local stat = statOf[frame]
        if not stat or GameTooltip:GetOwner() ~= frame then return end
        local ok, _, eff = pcall(UnitStat, "player", stat)
        if not ok or type(eff) ~= "number" or issecret(eff) then return end
        local _, class = UnitClass("player")
        local name = _G["SPELL_STAT" .. stat .. "_NAME"] or "?"
        local lines = {}
        if stat == STR then
            PerPoint(lines, name, Slope(GetAttackPowerForStat, STR, eff), T("Angriffskraft", "attack power"))
            if BLOCKERS[class] and BLOCK_VALUE_PER_STRENGTH then
                PerPoint(lines, name, 1 / BLOCK_VALUE_PER_STRENGTH, T("Blockwert", "block value"))
            end
        elseif stat == AGI then
            local ap = Slope(GetAttackPowerForStat, AGI, eff)
            PerPoint(lines, name, ap, T("Angriffskraft", "attack power"))
            local rap = Slope(GetRangedAttackPowerForStat, AGI, eff)
            if rap and rap > 0 and rap ~= ap then PerPoint(lines, name, rap, T("Distanzangriffskraft", "ranged attack power")) end
            local crit = Slope(GetCritChanceFromStat, AGI, eff)
            PerPoint(lines, name, crit and crit * 100, T("kritische Trefferchance", "critical strike chance"), " %")
            if ARMOR_PER_AGILITY then PerPoint(lines, name, ARMOR_PER_AGILITY, T("Rüstung", "armor")) end
        elseif stat == STA then
            -- gemessen (mit Talenten auf maximales Leben), sonst die Spielregel
            local measured = CharDB().hpPerSta
            PerPoint(lines, name, measured or Num(UnitHPPerStamina, "player"), T("Gesundheit", "health"),
                nil, measured and T(" (gemessen)", " (measured)"))
        elseif stat == INT then
            if not NO_MANA[class] then
                local measured = CharDB().manaPerInt
                PerPoint(lines, name, measured or MANA_PER_INTELLECT, T("Mana", "mana"), nil,
                    measured and T(" (gemessen)", " (measured)"))
            end
            local crit = Slope(GetSpellCritChanceFromStat, INT, eff)
            PerPoint(lines, name, crit and crit * 100, T("kritische Zaubertrefferchance", "spell critical strike chance"), " %")
        elseif stat == SPI and eff > 0 then
            -- Regeneration aus Willenskraft: Gesamtwert des Spiels durch die Punkte (wie Blizzard: je 5 Sek.)
            local health = Num(GetHealthRegenFromSpirit)
            if health then PerPoint(lines, name, health * 5 * 0.75 / eff, T("Gesundheit je 5 Sek.", "health per 5 sec.")) end
            local mana = not NO_MANA[class] and Num(GetManaRegenFromSpirit)
            if mana then PerPoint(lines, name, mana * 5 / eff, T("Mana je 5 Sek.", "mana per 5 sec.")) end
        end
        if #lines == 0 then return end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("Pro Punkt", "Per point"), C.accent[1], C.accent[2], C.accent[3])
        for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9) end
        -- Talente/Buffs mit Prozent-Bonus: 1 Punkt auf einem Gegenstand zählt als mehr als 1 Punkt
        local ratio = Ratio(stat)
        if ratio and ratio > 1.005 then
            GameTooltip:AddLine(string.format(T("Von Ausrüstung: 1 %s zählt als %s (+%d %% aus Talenten/Buffs, gemessen)",
                "From gear: 1 %s counts as %s (+%d %% from talents/buffs, measured)"), name, Fmt(ratio),
                math.floor((ratio - 1) * 100 + 0.5)), 0.4, 0.8, 0.4, true)
        elseif not ratio then
            GameTooltip:AddLine(T("Bonus aus Talenten/Buffs wird beim nächsten Ausrüstungswechsel gemessen.",
                "Bonus from talents/buffs is measured on your next gear change."), 0.55, 0.55, 0.55, true)
        end
        GameTooltip:Show()
    end

    -- Blizzard füllt den Tooltip jeder Wert-Zeile über PaperDollFrame_SetStatTooltip2(Zeile, Name, Nummer, Wert, Einheit):
    -- dabei merken wir uns die Zeile (eigene Tabelle) und hängen uns einmal an ihr OnEnter an
    local function Hook()
        if type(PaperDollFrame_SetStatTooltip2) ~= "function" then return false end
        hooksecurefunc("PaperDollFrame_SetStatTooltip2", function(frame, _, statIndex, _, unit)
            if not frame or type(statIndex) ~= "number" or (unit and unit ~= "player") then return end
            statOf[frame] = statIndex
            if not hooked[frame] and frame.HookScript then
                hooked[frame] = true
                frame:HookScript("OnEnter", function(self) pcall(AddLines, self) end)
            end
        end)
        return true
    end
    if not Hook() then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("ADDON_LOADED")
        wait:RegisterEvent("PLAYER_LOGIN")
        wait:SetScript("OnEvent", function(self)
            if Hook() then self:UnregisterAllEvents() end
        end)
    end

    -------------------------------------------------------------------------
    -- Gegenstands-Tooltip: was die Werte des Gegenstands DIR bringen ("Ausdauer +10: +100 Gesundheit") und beim
    -- Ansehen eines nicht angelegten Gegenstands der Unterschied zum angelegten am selben Platz. Gleiche Rechnung wie
    -- oben (Spielfunktionen, gemessener Talent-/Buff-Bonus). Nur außerhalb des Kampfes, nur angehängt.
    -------------------------------------------------------------------------
    local ORDER = { STR, AGI, STA, INT, SPI }
    local SLOTS = { INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
        INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
        INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
        INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
        INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
        INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 } }

    local function Signed(v, suffix)
        return (v >= 0 and "+" or "-") .. Fmt(math.abs(v)) .. (suffix or "")
    end
    -- Wirkung von "amount" Punkten eines Werts (auf einem Gegenstand) für den Charakter: { "+100 Gesundheit", … }
    local function Effects(stat, amount)
        local ok, _, eff = pcall(UnitStat, "player", stat)
        if not ok or type(eff) ~= "number" or issecret(eff) then return {} end
        local _, class = UnitClass("player")
        local n = amount * (Ratio(stat) or 1)
        local out = {}
        local function Add(perPoint, label, suffix)
            if perPoint and perPoint > 0 then
                local v = perPoint * n
                -- ganze Werte runden, Prozente auf zwei Stellen
                if not suffix then v = (v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)) end
                if v ~= 0 then out[#out + 1] = Signed(v, suffix) .. " " .. label end
            end
        end
        if stat == STR then
            Add(Slope(GetAttackPowerForStat, STR, eff), T("Angriffskraft", "attack power"))
            if BLOCKERS[class] and BLOCK_VALUE_PER_STRENGTH then Add(1 / BLOCK_VALUE_PER_STRENGTH, T("Blockwert", "block value")) end
        elseif stat == AGI then
            local ap = Slope(GetAttackPowerForStat, AGI, eff)
            Add(ap, T("Angriffskraft", "attack power"))
            local rap = Slope(GetRangedAttackPowerForStat, AGI, eff)
            if rap and rap ~= ap then Add(rap, T("Distanzangriffskraft", "ranged attack power")) end
            local crit = Slope(GetCritChanceFromStat, AGI, eff)
            Add(crit and crit * 100, T("Krit.", "crit"), " %")
            Add(ARMOR_PER_AGILITY, T("Rüstung", "armor"))
        elseif stat == STA then
            Add(CharDB().hpPerSta or Num(UnitHPPerStamina, "player"), T("Gesundheit", "health"))
        elseif stat == INT then
            if not NO_MANA[class] then Add(CharDB().manaPerInt or MANA_PER_INTELLECT, T("Mana", "mana")) end
            local crit = Slope(GetSpellCritChanceFromStat, INT, eff)
            Add(crit and crit * 100, T("Zauberkrit.", "spell crit"), " %")
        elseif stat == SPI and eff > 0 then
            local health = Num(GetHealthRegenFromSpirit)
            if health then Add(health * 5 * 0.75 / eff, T("Gesundheit/5 Sek.", "health/5 sec.")) end
            local mana = not NO_MANA[class] and Num(GetManaRegenFromSpirit)
            if mana then Add(mana * 5 / eff, T("Mana/5 Sek.", "mana/5 sec.")) end
        end
        return out
    end

    local function StatName(stat) return _G["SPELL_STAT" .. stat .. "_NAME"] or "?" end
    local function Sum(stats)
        local s = 0
        for _, v in pairs(stats) do s = s + v end
        return s
    end
    -- angelegter Gegenstand am selben Platz (bei Ringen/Schmuck/Einhand: der mit den schwächeren Werten)
    local function EquippedFor(equipLoc)
        local slots = SLOTS[equipLoc]
        if not slots then return nil end
        local best, bestSum
        for _, slot in ipairs(slots) do
            local link = GetInventoryItemLink("player", slot)
            local stats = ItemStats(link)
            local sum = link and Sum(stats) or -1
            if not bestSum or sum < bestSum then best, bestSum = { link = link, stats = stats }, sum end
        end
        return best
    end

    local function OnItemTip(tip)
        if not GetDB().statPerPoint or InCombatLockdown() or not tip.GetItem then return end
        local _, link = tip:GetItem()
        if not link or issecret(link) then return end
        local stats = ItemStats(link)
        local lines = {}
        for _, s in ipairs(ORDER) do
            if (stats[s] or 0) ~= 0 then
                local effects = Effects(s, stats[s])
                if #effects > 0 then
                    lines[#lines + 1] = StatName(s) .. " " .. Signed(stats[s]) .. ":  " .. table.concat(effects, "  ·  ")
                end
            end
        end
        -- Vergleich nur im Haupt-Tooltip (die Vergleichs-Tooltips zeigen ja den angelegten Gegenstand)
        local compare = {}
        if tip == GameTooltip or tip == _G.ItemRefTooltip then
            local okInfo, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
            local equipped = okInfo and equipLoc and EquippedFor(equipLoc)
            if equipped and equipped.link ~= link then
                for _, s in ipairs(ORDER) do
                    local delta = (stats[s] or 0) - (equipped.stats[s] or 0)
                    if delta ~= 0 then
                        local effects = Effects(s, delta)
                        local color = delta > 0 and "|cff55dd55" or "|cffee5555"
                        compare[#compare + 1] = color .. StatName(s) .. " " .. Signed(delta) .. "|r" ..
                            (#effects > 0 and (":  " .. table.concat(effects, "  ·  ")) or "")
                    end
                end
            end
        end
        if #lines == 0 and #compare == 0 then return end
        if #lines > 0 then
            tip:AddLine(" ")
            tip:AddLine(T("Für dich", "For you"), C.accent[1], C.accent[2], C.accent[3])
            for _, line in ipairs(lines) do tip:AddLine(line, 0.9, 0.9, 0.9, true) end
        end
        if #compare > 0 then
            tip:AddLine(" ")
            tip:AddLine(T("Gegenüber angelegt", "Compared to equipped"), C.accent[1], C.accent[2], C.accent[3])
            for _, line in ipairs(compare) do tip:AddLine(line, 0.9, 0.9, 0.9, true) end
        end
        tip:Show()
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip) pcall(OnItemTip, tip) end)
    end
end

---------------------------------------------------------------------------
-- Einstellungsfenster
---------------------------------------------------------------------------
local ToggleOptions
do
    local options = UI.SettingsPanel("ForeverTooltipOptions", T("ForeverTooltip – Einstellungen",
        "ForeverTooltip – Settings"), 360, 554,
        { key = "ForeverTooltip", group = UI.SETTINGS_GROUPS.comfort, label = "Tooltip" })
    local W = 326
    local checks = {}
    local function Check(y, label, key)
        local cb = UI.Check(options, 14, y, label, Safe(T("Einstellungen", "Settings"), function(checked)
            GetDB()[key] = checked
            ApplyAll()
        end))
        checks[#checks + 1] = { cb = cb, key = key }
        return cb
    end

    UI.Header(options, 18, -32, T("Aussehen", "Look"), W)
    Check(-54, T("Forever-Stil (dunkel, feiner Rand, Goldlinie)", "Forever style (dark, fine border, gold line)"), "skin")
    Check(-78, T("Rahmen in Qualitäts-/Klassenfarbe", "Border in quality/class color"), "colorBorder")
    Check(-102, T("Spielernamen in Klassenfarbe", "Player names in class color"), "classNames")
    Check(-126, T("Lebensbalken unter dem Tooltip", "Health bar below the tooltip"), "showHealthBar")
    Check(-150, T("Rahmen rundum gold (sonst grau mit Goldlinie)", "Gold border all around (else grey with gold line)"), "goldEdge")

    UI.Header(options, 18, -172, T("Mehr Infos", "More info"), W)
    Check(-194, T("Gegenstandsstufe bei Ausrüstung", "Item level on gear"), "itemLevel")
    Check(-218, T("Ziel der Einheit („Ziel: …“)", "Target of the unit (\"Target: …\")"), "showTarget")
    Check(-242, T("Gegenstands- und Zauber-IDs", "Item and spell IDs"), "showIDs")
    Check(-266, T("Werte umrechnen (Charakter, Gegenstände)", "Convert stats (character, items)"), "statPerPoint")

    UI.Header(options, 18, -308, T("Ort", "Position"), W)
    Check(-330, T("Am Mauszeiger statt am Ankerplatz", "At the mouse cursor instead of the anchor"), "atCursor")
    local scale = UI.Slider(options, 18, -362, T("Größe", "Size"), 70, 150, 5, Safe(T("Einstellungen", "Settings"), function(v)
        GetDB().scale = v / 100
        ApplyScale()
    end), { width = 200, unit = " %" })
    local alpha = UI.Slider(options, 18, -402, T("Deckkraft des Hintergrunds", "Background opacity"), 20, 100, 5,
        Safe(T("Einstellungen", "Settings"), function(v)
            GetDB().bgAlpha = v
            for tip in pairs(skinned) do ApplyLook(tip) end
        end), { width = 200, unit = " %" })
    local move = UI.Button(options, T("Verschieben", "Move"), 110, Safe("Move", function() SetLocked(false) end))
    move:SetPoint("TOPLEFT", 16, -444)
    local done = UI.Button(options, T("Fertig – sperren", "Done – lock"), 130, Safe("Lock", function() SetLocked(true) end))
    done:SetPoint("LEFT", move, "RIGHT", 6, 0)
    local reset = UI.Button(options, T("Position zurücksetzen", "Reset position"), 160, Safe("Reset", function()
        GetDB().pos = nil
        PlaceAnchor()
    end))
    reset:SetPoint("TOPLEFT", 16, -470)
    UI.Hint(options, 18, -500, W, T("Alle Forever-Rahmen auf einmal verschieben: /fmove. Prototyp – noch nicht im Release.",
        "Move all Forever frames at once: /fmove. Prototype – not in the release yet."))

    options:SetScript("OnShow", function()
        local d = GetDB()
        for _, c in ipairs(checks) do c.cb:SetChecked(d[c.key] and true or false) end
        scale:Load(math.floor((d.scale or 1) * 100 + 0.5))
        alpha:Load(d.bgAlpha or 75)
    end)

    function ToggleOptions() options:SetShown(not options:IsShown()) end
end

---------------------------------------------------------------------------
-- Anmeldung im Hub, Minimap-Knopf, Befehl
---------------------------------------------------------------------------
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverTooltip", function() return GetDB().locked end, SetLocked)
end

UI.MinimapButton({
    name = "ForeverTooltipMinimapButton",
    icon = "Interface\\AddOns\\ForeverTooltip\\Media\\ForeverTooltip",
    title = "ForeverTooltip",
    angle = function() return GetDB().minimapAngle end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = Safe("Minimap", function(_, button)
        if button == "RightButton" then SetLocked(not GetDB().locked) else ToggleOptions() end
    end),
    lines = function()
        return {
            T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Ankerplatz verschieben/sperren", "Right-click: move/lock the anchor"),
        }
    end,
})

SLASH_FOREVERTOOLTIP1 = "/ftip"
SLASH_FOREVERTOOLTIP2 = "/forevertooltip"
SlashCmdList["FOREVERTOOLTIP"] = Safe("Befehl", function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" then
        SetLocked(not GetDB().locked)
    elseif msg == "reset" then
        GetDB().pos = nil
        PlaceAnchor()
        Chat(T("Position zurückgesetzt.", "Position reset."))
    else
        ToggleOptions()
    end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", Safe("Start", function()
    SkinAll()
    StyleHealthBar()
    HookContent()
    HookAnchor()
    SetLocked(true) -- immer gesperrt starten
    ApplyAll()
end))

UI.RegisterSettings({ addon = "ForeverTooltip", sv = "ForeverTooltipDB", defaults = DEFAULTS, version = 1 })
