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
    flatHealth = true,    -- Lebensbalken flach in Klassen-/Reaktionsfarbe
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
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip" }
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
    local _, _, quality, level, _, _, _, _, equipLoc = GetItemInfo(info)
    if quality and d.colorBorder and d.skin and quality >= 2 then
        local r, g, b = GetItemQualityColor(quality)
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
UI.SetFlat(anchor, { 0.2, 0.5, 1, 0.25 })
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
-- Einstellungsfenster
---------------------------------------------------------------------------
local ToggleOptions
do
    local options = UI.SettingsPanel("ForeverTooltipOptions", T("ForeverTooltip – Einstellungen (Prototyp)",
        "ForeverTooltip – Settings (prototype)"), 360, 530,
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
    Check(-126, T("Lebensbalken flach in Klassenfarbe", "Flat health bar in class color"), "flatHealth")
    Check(-150, T("Rahmen rundum gold (sonst grau mit Goldlinie)", "Gold border all around (else grey with gold line)"), "goldEdge")

    UI.Header(options, 18, -172, T("Mehr Infos", "More info"), W)
    Check(-194, T("Gegenstandsstufe bei Ausrüstung", "Item level on gear"), "itemLevel")
    Check(-218, T("Ziel der Einheit („Ziel: …“)", "Target of the unit (\"Target: …\")"), "showTarget")
    Check(-242, T("Gegenstands- und Zauber-IDs", "Item and spell IDs"), "showIDs")

    UI.Header(options, 18, -284, T("Ort", "Position"), W)
    Check(-306, T("Am Mauszeiger statt am Ankerplatz", "At the mouse cursor instead of the anchor"), "atCursor")
    local scale = UI.Slider(options, 18, -338, T("Größe", "Size"), 70, 150, 5, Safe(T("Einstellungen", "Settings"), function(v)
        GetDB().scale = v / 100
        ApplyScale()
    end), { width = 200, unit = " %" })
    local alpha = UI.Slider(options, 18, -378, T("Deckkraft des Hintergrunds", "Background opacity"), 20, 100, 5,
        Safe(T("Einstellungen", "Settings"), function(v)
            GetDB().bgAlpha = v
            for tip in pairs(skinned) do ApplyLook(tip) end
        end), { width = 200, unit = " %" })
    local move = UI.Button(options, T("Verschieben", "Move"), 110, Safe("Move", function() SetLocked(false) end))
    move:SetPoint("TOPLEFT", 16, -420)
    local done = UI.Button(options, T("Fertig – sperren", "Done – lock"), 130, Safe("Lock", function() SetLocked(true) end))
    done:SetPoint("LEFT", move, "RIGHT", 6, 0)
    local reset = UI.Button(options, T("Position zurücksetzen", "Reset position"), 160, Safe("Reset", function()
        GetDB().pos = nil
        PlaceAnchor()
    end))
    reset:SetPoint("TOPLEFT", 16, -446)
    UI.Hint(options, 18, -476, W, T("Alle Forever-Rahmen auf einmal verschieben: /fmove. Prototyp – noch nicht im Release.",
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
    icon = "Interface\\Icons\\INV_Misc_Note_01",
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
