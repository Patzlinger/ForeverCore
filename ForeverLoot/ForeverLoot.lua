-- ForeverLoot: kleines Fenster bei Wuerfel-Drops – wer hat Bedarf, Gier oder Passen gewaehlt,
-- welche Zahl wurde gewuerfelt, wer hat gewonnen. Ist nichts los, bleibt das Fenster unsichtbar.
local ADDON_NAME = ...
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
-- Sprache: deutscher Client auf Deutsch, alle anderen auf Englisch
local T = UI.T

---------------------------------------------------------------------------
-- Einstellungen (SavedVariables)
---------------------------------------------------------------------------
local DEFAULTS = {
    locked = true, -- gesperrt starten; entsperren per Menue, Minimap-Rechtsklick oder /fmove
    scale = 1,
    keep = 5,       -- so viele Sekunden nach dem Ergebnis bleibt ein Wurf sichtbar (danach ausblenden)
    maxRows = 5,    -- mehr Spieler: Liste startet eingeklappt
    minimapAngle = 250,
}

-- Wegen des Beta-Bugs wird ForeverLootDB bei jedem Zugriff neu geprueft
local db
local function GetDB()
    if type(_G.ForeverLootDB) ~= "table" then
        _G.ForeverLootDB = db or {}
    end
    db = _G.ForeverLootDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    -- alter Standard (45 s) -> neuer Standard (5 s), einmalig
    if not db.keepV2 then
        if db.keep == 45 then db.keep = DEFAULTS.keep end
        db.keepV2 = true
    end
    return db
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function IsSecret(...)
    for i = 1, select("#", ...) do
        if issecret((select(i, ...))) then return true end
    end
    return false
end

local function Chat(text)
    UI.Chat("ForeverLoot", text)
end

-- Fehlerschutz (gemeinsam im ForeverHub): Fehler einmal pro Stelle melden, Addon laeuft weiter
local function Safe(where, fn)
    return UI.Safe("ForeverLoot", where, fn)
end

local function ShortName(name)
    if not name or IsSecret(name) then return nil end
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:gsub("%-.*$", ""))
end

local function ClassColor(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

local function ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Gruppe zum Zeitpunkt des Drops: Name -> Klasse (Reihenfolge wie in der Gruppe)
local function Roster()
    local list = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            name = ShortName(name)
            if name then list[#list + 1] = { name = name, class = class } end
        end
    else
        for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
            if UnitExists(unit) then
                local name = ShortName((UnitName(unit)))
                local _, class = UnitClass(unit)
                if name then list[#list + 1] = { name = name, class = class } end
            end
        end
    end
    return list
end

local function PlayerName()
    return ShortName((UnitName("player")))
end

---------------------------------------------------------------------------
-- Daten: ein Eintrag pro gewuerfeltem Gegenstand
---------------------------------------------------------------------------
local CHOICE = {
    need       = { order = 1, label = T("Bedarf", "Need"),     icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    greed      = { order = 2, label = T("Gier", "Greed"),      icon = "Interface\\Buttons\\UI-GroupLoot-Coin-Up" },
    disenchant = { order = 3, label = T("Entzaubern", "Disenchant"), icon = "Interface\\Buttons\\UI-GroupLoot-DE-Up" },
    pass       = { order = 4, label = T("Passen", "Pass"),     icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
}

local items = {}   -- Liste der aktiven Eintraege
local Refresh      -- weiter unten
local UpdateMinimapPosition -- weiter unten (Minimap-Button)

local function NewItem(info)
    local item = {
        rollID = info.rollID,
        link = info.link,
        itemID = ItemIDFromLink(info.link),
        name = info.name,
        icon = info.icon,
        quality = info.quality,
        start = GetTime(),
        duration = info.duration,
        players = {},   -- Name -> { name, class, choice, roll }
        order = {},     -- Namen in Gruppen-Reihenfolge
        test = info.test,
    }
    for _, p in ipairs(info.roster or Roster()) do
        if not item.players[p.name] then
            item.players[p.name] = { name = p.name, class = p.class }
            item.order[#item.order + 1] = p.name
        end
    end
    item.collapsed = #item.order > GetDB().maxRows
    items[#items + 1] = item
    return item
end

-- Forever fuehrt Vor- und Nachnamen ein: Der Chat meldet z. B. "Hexeron Soulbane", die Gruppen-
-- liste evtl. nur "Hexeron". Beides ist dieselbe Person (ein Name steht vorne im anderen + Leerzeichen).
local function SameName(a, b)
    if a == b then return true end
    if #a > #b then a, b = b, a end
    return b:sub(1, #a) == a and b:sub(#a + 1, #a + 1) == " "
end

local function FindPlayer(item, name)
    local p = item.players[name]
    if p then return p end
    for key, q in pairs(item.players) do
        if SameName(key, name) then return q end
    end
end

-- Spieler holen oder anlegen; angezeigt wird immer der laengste (= volle) bekannte Name
local function GetPlayer(item, name)
    local p = FindPlayer(item, name)
    if not p then
        p = { name = name }
        item.players[name] = p
        item.order[#item.order + 1] = name
    elseif #name > #(p.display or p.name) then
        p.display = name
    end
    return p
end

local function DisplayName(p) return p and (p.display or p.name) or "?" end

-- passenden (noch offenen) Eintrag fuer eine Chat-Nachricht finden;
-- filter waehlt bei gleichen Gegenstaenden den, bei dem der Spieler noch nichts gewaehlt hat
local function FindOpenItem(link, filter)
    local id = ItemIDFromLink(link)
    for _, item in ipairs(items) do
        if not item.finished and not item.test and ((id and item.itemID == id) or item.link == link) then
            if not filter or filter(item) then return item end
        end
    end
end

local function ItemFromChat(link, filter)
    local item = FindOpenItem(link, filter) or FindOpenItem(link)
    if item then return item end
    -- Drop, auf den wir selbst nicht wuerfeln (kein START_LOOT_ROLL): aus dem Chat anlegen
    -- (nicht "a and f()" schreiben: dann liefert Lua nur den ersten Rueckgabewert)
    local name, quality, icon
    if C_Item and C_Item.GetItemInfo then
        local n, _, q, _, _, _, _, _, _, tex = C_Item.GetItemInfo(link)
        name, quality, icon = n, q, tex
    end
    if not icon and C_Item and C_Item.GetItemIconByID then
        local id = ItemIDFromLink(link)
        icon = id and C_Item.GetItemIconByID(id)
    end
    return NewItem({ link = link, name = name or link, icon = icon, quality = quality })
end

---------------------------------------------------------------------------
-- Loot-Chat lesen (Blizzards eigene Sprachvorlagen -> passt in jeder Spielsprache)
---------------------------------------------------------------------------
-- "%s hat Bedarf ausgewählt für: %s" -> Lua-Muster + Art jedes Platzhalters.
-- Neuere Clients setzen vor die Meldung einen Verweis auf die Loot-Historie
-- ("|HlootHistory:%d|h[Loot]|h: ..."). Dessen Nummer wird markiert und spaeter uebersprungen.
local function Compile(fmt)
    if type(fmt) ~= "string" then return nil end
    local pattern, slots, i, n = "^", {}, 1, 0
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local pos, kind = fmt:match("^%%(%d)%$([sd])", i)
            local len = 4
            if not pos then
                kind = fmt:match("^%%([sd])", i)
                len = 2
                if kind then n = n + 1 pos = n end
            end
            if kind then
                local history = fmt:sub(1, i - 1):find("lootHistory:$") ~= nil
                slots[#slots + 1] = { pos = tonumber(pos), kind = kind, history = history }
                pattern = pattern .. (kind == "d" and "(%-?%d+)" or "(.-)")
                i = i + len
            else
                pattern = pattern .. "%%"
                i = i + (fmt:sub(i + 1, i + 1) == "%" and 2 or 1)
            end
        else
            if c:find("[%^%$%(%)%.%[%]%*%+%-%?]") then c = "%" .. c end
            pattern = pattern .. c
            i = i + 1
        end
    end
    return { pattern = pattern .. "$", slots = slots }
end

-- Teile einer Meldung nach Inhalt zuordnen (nicht nach fester Position):
-- Gegenstand = Text mit Gegenstands-Link, Wurf = Zahl, Spieler = uebriger Text
local function Parse(compiled, msg)
    local caps = { msg:match(compiled.pattern) }
    if #caps == 0 then return nil end
    local byPos = {}
    for k, slot in ipairs(compiled.slots) do
        byPos[#byPos + 1] = { pos = slot.pos, slot = slot, value = caps[k] }
    end
    table.sort(byPos, function(a, b) return a.pos < b.pos end)
    local result = {}
    for _, a in ipairs(byPos) do
        local value = a.value
        if not a.slot.history and value then
            if a.slot.kind == "d" then
                result.roll = result.roll or tonumber(value)
            elseif value:find("|Hitem") then
                result.link = result.link or value
            elseif not result.player then
                -- Spielername evtl. als Link: |Hplayer:Name-Realm|h[Name]|h
                result.player = value:match("|Hplayer:([^:|]+)") or value
            end
        end
    end
    if not result.link then return nil end -- ohne Gegenstand ist es keine Wuerfel-Meldung
    return result
end

-- Welche Vorlage bedeutet was? (Zahlen = Position des Platzhalters)
local MESSAGES = {
    -- Gewinner mit Wurf (Spam-Filter von Blizzard)
    { g = "LOOT_ROLL_YOU_WON_NO_SPAM_NEED",  won = true, self = true, choice = "need", roll = 1, item = 2 },
    { g = "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", won = true, self = true, choice = "greed", roll = 1, item = 2 },
    { g = "LOOT_ROLL_YOU_WON_NO_SPAM_DE",    won = true, self = true, choice = "disenchant", roll = 1, item = 2 },
    { g = "LOOT_ROLL_WON_NO_SPAM_NEED",      won = true, choice = "need", player = 1, roll = 2, item = 3 },
    { g = "LOOT_ROLL_WON_NO_SPAM_GREED",     won = true, choice = "greed", player = 1, roll = 2, item = 3 },
    { g = "LOOT_ROLL_WON_NO_SPAM_DE",        won = true, choice = "disenchant", player = 1, roll = 2, item = 3 },
    -- Wuerfe
    { g = "LOOT_ROLL_ROLLED_NEED",  rolled = "need", roll = 1, item = 2, player = 3 },
    { g = "LOOT_ROLL_ROLLED_GREED", rolled = "greed", roll = 1, item = 2, player = 3 },
    { g = "LOOT_ROLL_ROLLED_DE",    rolled = "disenchant", roll = 1, item = 2, player = 3 },
    -- Auswahl (eigene)
    { g = "LOOT_ROLL_NEED_SELF",        choice = "need", self = true, item = 1 },
    { g = "LOOT_ROLL_GREED_SELF",       choice = "greed", self = true, item = 1 },
    { g = "LOOT_ROLL_DISENCHANT_SELF",  choice = "disenchant", self = true, item = 1 },
    { g = "LOOT_ROLL_PASSED_SELF_AUTO", choice = "pass", self = true, item = 1 },
    { g = "LOOT_ROLL_PASSED_SELF",      choice = "pass", self = true, item = 1 },
    -- Auswahl (andere)
    { g = "LOOT_ROLL_NEED",              choice = "need", player = 1, item = 2 },
    { g = "LOOT_ROLL_GREED",             choice = "greed", player = 1, item = 2 },
    { g = "LOOT_ROLL_DISENCHANT",        choice = "disenchant", player = 1, item = 2 },
    { g = "LOOT_ROLL_PASSED_AUTO",       choice = "pass", player = 1, item = 2 },
    { g = "LOOT_ROLL_PASSED_AUTO_FEMALE", choice = "pass", player = 1, item = 2 },
    { g = "LOOT_ROLL_PASSED",            choice = "pass", player = 1, item = 2 },
    -- Ergebnis
    { g = "LOOT_ROLL_YOU_WON",    won = true, self = true, item = 1 },
    { g = "LOOT_ROLL_WON",        won = true, player = 1, item = 2 },
    { g = "LOOT_ROLL_ALL_PASSED", allPassed = true, item = 1 },
}
for _, m in ipairs(MESSAGES) do m.compiled = Compile(_G[m.g]) end

local function Finish(item)
    item.finished = true
    item.finishTime = GetTime()
end

local function HandleMessage(m, args)
    local link = args.link
    if not link then return end
    local name = m.self and PlayerName() or ShortName(args.player)
    if name and (name == YOU or name == UNIT_YOU) then name = PlayerName() end
    local roll = args.roll

    if m.allPassed then
        local item = ItemFromChat(link)
        Finish(item)
        item.allPassed = true
    elseif m.won then
        local item = ItemFromChat(link)
        if name then
            local p = GetPlayer(item, name)
            if m.choice and not p.choice then p.choice = m.choice end
            if roll then p.roll = roll end
            item.winner = p.name
        end
        Finish(item)
    elseif m.rolled then
        if not name then return end
        local item = ItemFromChat(link, function(it)
            local p = FindPlayer(it, name)
            return not p or not p.roll
        end)
        local p = GetPlayer(item, name)
        p.choice = p.choice or m.rolled
        p.roll = roll
    elseif m.choice then
        if not name then return end
        local item = ItemFromChat(link, function(it)
            local p = FindPlayer(it, name)
            return not p or not p.choice
        end)
        GetPlayer(item, name).choice = m.choice
    end
    Refresh()
end

local function OnLootMessage(msg)
    if not msg or IsSecret(msg) or not msg:find("|Hitem") then return end
    for _, m in ipairs(MESSAGES) do
        if m.compiled then
            local args = Parse(m.compiled, msg)
            if args then
                HandleMessage(m, args)
                return
            end
        end
    end
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local WIDTH = 280
local ROW_H = 15
local WHITE = "Interface\\Buttons\\WHITE8x8"

local frame = CreateFrame("Frame", "ForeverLootFrame", UIParent, "BackdropTemplate")
frame:SetSize(WIDTH, 60)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
UI.Hud(frame)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 8, -6)
title:SetText("ForeverLoot")

-- Hinweis im Verschiebe-Modus (solange kein Wurf laeuft)
frame.placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.placeholder:SetPoint("TOPLEFT", 10, -24)
frame.placeholder:SetPoint("RIGHT", -10, 0)
frame.placeholder:SetJustifyH("LEFT")
frame.placeholder:SetText(T("Zum Verschieben ziehen.\nDanach in den Einstellungen \"Sperren\" wählen.",
    "Drag to move.\nThen choose \"Lock\" in the settings."))
frame.placeholder:Hide()

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
close:SetSize(18, 18)
close:SetPoint("TOPRIGHT", 1, 1)

local function SavePosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        GetDB().pos = { math.floor(left + 0.5), math.floor(top - UIParent:GetTop() + 0.5) }
    end
end

local function RestorePosition()
    local p = GetDB().pos
    frame:ClearAllPoints()
    if p then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2])
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 320, -200)
    end
    frame:SetScale(GetDB().scale)
end

frame:SetScript("OnDragStart", function(self)
    if not GetDB().locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
    RestorePosition()
end)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("ForeverLoot")
    GameTooltip:AddLine(GetDB().locked and T("Gesperrt – /floot lock zum Entsperren", "Locked – /floot lock to unlock")
        or T("Ziehen: verschieben", "Drag: move"), 1, 1, 1)
    GameTooltip:AddLine(T("/floot test – Testmodus", "/floot test – test mode"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", GameTooltip_Hide)

-- Ein Block pro Gegenstand; Bloecke und Zeilen werden wiederverwendet
local blocks = {}

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 0.82, 0, 0.18)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetJustifyH("LEFT")
    r.roll = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.roll:SetPoint("RIGHT", -6, 0)
    r.roll:SetWidth(30)
    r.roll:SetJustifyH("RIGHT")
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("RIGHT", r.roll, "LEFT", -4, 0)
    r.choice = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.choice:SetPoint("RIGHT", r.icon, "LEFT", -4, 0)
    return r
end

local function NewBlock()
    local b = CreateFrame("Frame", nil, frame)
    b:SetWidth(WIDTH - 12)

    b.iconBtn = CreateFrame("Button", nil, b)
    b.iconBtn:SetSize(26, 26)
    b.iconBtn:SetPoint("TOPLEFT", 0, 0)
    b.icon = b.iconBtn:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.iconBtn:SetScript("OnEnter", function(self)
        local item = self:GetParent().item
        if item and item.link and item.link:find("|H") then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink(item.link)
            GameTooltip:Show()
        end
    end)
    b.iconBtn:SetScript("OnLeave", GameTooltip_Hide)

    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOPLEFT", b.iconBtn, "TOPRIGHT", 6, -1)
    b.name:SetPoint("RIGHT", b, "RIGHT", -22, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)

    b.timer = CreateFrame("StatusBar", nil, b)
    b.timer:SetPoint("BOTTOMLEFT", b.iconBtn, "BOTTOMRIGHT", 6, 1)
    b.timer:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.timer:SetHeight(4)
    b.timer:SetStatusBarTexture(WHITE)
    b.timer:SetStatusBarColor(1, 0.82, 0)
    b.timer:SetMinMaxValues(0, 1)
    local tbg = b.timer:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetColorTexture(0, 0, 0, 0.6)

    b.summary = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.summary:SetPoint("TOPLEFT", b.iconBtn, "BOTTOMLEFT", 0, -3)
    b.summary:SetPoint("RIGHT", b, "RIGHT", -22, 0)
    b.summary:SetJustifyH("LEFT")

    b.toggle = UI.Button and UI.Button(b, "", 20) or CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    b.toggle:SetSize(20, 16)
    b.toggle:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -30)
    b.toggle:SetScript("OnClick", function(self)
        local item = self:GetParent().item
        if item then
            item.collapsed = not item.collapsed
            Refresh()
        end
    end)

    b.remove = CreateFrame("Button", nil, b, "UIPanelCloseButtonNoScripts")
    b.remove:SetSize(16, 16)
    b.remove:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 2)
    b.remove:SetScript("OnClick", function(self)
        local item = self:GetParent().item
        for i, it in ipairs(items) do
            if it == item then table.remove(items, i) break end
        end
        Refresh()
    end)

    b.rows = {}
    return b
end

local function SortedPlayers(item)
    local list = {}
    for i, name in ipairs(item.order) do
        local p = item.players[name]
        p.index = i
        list[#list + 1] = p
    end
    table.sort(list, function(a, b)
        if (a.name == item.winner) ~= (b.name == item.winner) then return a.name == item.winner end
        local ao = a.choice and CHOICE[a.choice].order or 9
        local bo = b.choice and CHOICE[b.choice].order or 9
        if ao ~= bo then return ao < bo end
        if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
        return a.index < b.index
    end)
    return list
end

local function Summary(item)
    local counts, open = { need = 0, greed = 0, disenchant = 0, pass = 0 }, 0
    for _, p in pairs(item.players) do
        if p.choice then counts[p.choice] = counts[p.choice] + 1 else open = open + 1 end
    end
    local parts = {}
    for _, key in ipairs({ "need", "greed", "disenchant", "pass" }) do
        if counts[key] > 0 then
            parts[#parts + 1] = string.format("|T%s:12:12|t %d", CHOICE[key].icon, counts[key])
        end
    end
    if open > 0 and not item.finished then
        parts[#parts + 1] = string.format(T("|cff999999%d offen|r", "|cff999999%d open|r"), open)
    end
    local text = table.concat(parts, "   ")
    if item.allPassed then
        text = T("|cff999999Alle haben gepasst|r", "|cff999999Everyone passed|r")
    elseif item.winner then
        local p = item.players[item.winner]
        local r, g, bl = ClassColor(p and p.class)
        text = string.format(T("Gewinner: |cff%02x%02x%02x%s|r%s", "Winner: |cff%02x%02x%02x%s|r%s"),
            r * 255, g * 255, bl * 255, DisplayName(p), (p and p.roll) and (" (" .. p.roll .. ")") or "") .. "   " .. text
    end
    return text
end

local function LayoutBlock(b, item)
    b.item = item
    b.icon:SetTexture(item.icon or 134400) -- Fragezeichen, wenn unbekannt
    local quality = item.quality
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    b.name:SetText(item.name or item.link or "?")
    if c then b.name:SetTextColor(c.r, c.g, c.b) else b.name:SetTextColor(1, 1, 1) end
    b.timer:SetShown(not item.finished and item.duration ~= nil)
    b.summary:SetText(Summary(item))

    local players = SortedPlayers(item)
    local many = #players > GetDB().maxRows
    b.toggle:SetShown(many)
    b.toggle:SetText(item.collapsed and "+" or "–")

    local shown = (item.collapsed and many) and 0 or #players
    local y = -46
    for i = 1, shown do
        local r = b.rows[i] or NewRow(b)
        b.rows[i] = r
        local p = players[i]
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", b, "TOPLEFT", 0, y)
        r:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, y)
        r.name:SetText(DisplayName(p))
        r.name:SetTextColor(ClassColor(p.class))
        r.bg:SetShown(p.name == item.winner)
        if p.choice then
            r.icon:SetTexture(CHOICE[p.choice].icon)
            r.icon:Show()
            r.choice:SetText(CHOICE[p.choice].label)
        else
            r.icon:Hide()
            r.choice:SetText(item.finished and "" or T("wählt …", "choosing …"))
        end
        r.roll:SetText(p.roll and tostring(p.roll) or "")
        r:Show()
        y = y - ROW_H
    end
    for i = shown + 1, #b.rows do b.rows[i]:Hide() end
    b:SetHeight(-y + 2)
    return -y + 2
end

function Refresh()
    -- fertige Eintraege nach einer Weile entfernen
    local now = GetTime()
    for i = #items, 1, -1 do
        local it = items[i]
        if it.finished and now - it.finishTime > GetDB().keep then
            table.remove(items, i)
        elseif not it.finished and it.duration and now - it.start > it.duration + 15 then
            Finish(it) -- kein Ergebnis im Chat angekommen: Zeit ist um
        end
    end

    if #items == 0 then
        for _, b in ipairs(blocks) do b:Hide() end
        if frame.moving then
            -- Verschiebe-Modus: leeres Fenster mit Hinweis zeigen
            frame.placeholder:Show()
            frame:SetHeight(64)
            frame:Show()
        else
            frame:Hide()
        end
        return
    end
    frame.placeholder:Hide()

    local y = -22
    for i, item in ipairs(items) do
        local b = blocks[i] or NewBlock()
        blocks[i] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, y)
        local h = LayoutBlock(b, item)
        b:Show()
        y = y - h - 8
    end
    for i = #items + 1, #blocks do blocks[i]:Hide() end
    frame:SetHeight(-y + 2)
    frame:Show()
end

close:SetScript("OnClick", function()
    wipe(items)
    Refresh()
end)

-- Restzeit-Balken und Aufraeumen
local elapsedSince = 0
frame:SetScript("OnUpdate", Safe("Anzeige", function(_, elapsed)
    local now = GetTime()
    for _, b in ipairs(blocks) do
        local item = b:IsShown() and b.item
        if item and not item.finished and item.duration then
            local left
            if item.rollID and GetLootRollTimeLeft and not item.test then
                local ms = GetLootRollTimeLeft(item.rollID)
                if not IsSecret(ms) and ms then left = ms / 1000 end
            end
            left = left or math.max(0, item.duration - (now - item.start))
            b.timer:SetValue(math.max(0, math.min(1, left / item.duration)))
        end
    end
    elapsedSince = elapsedSince + elapsed
    if elapsedSince > 1 then
        elapsedSince = 0
        Refresh()
    end
end))

---------------------------------------------------------------------------
-- Testmodus
---------------------------------------------------------------------------
local TEST_NAMES = { "Thorgar", "Elyndra", "Pyrothas", "Maelwen", "Brannoc", "Sylvara", "Grimnar", "Tuluk",
    "Morvex", "Kiraya", "Aldric", "Fenja", "Jorund", "Lysara", "Okran", "Rhea", "Sigrun", "Talvar", "Ulla", "Varek" }
local TEST_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "WARLOCK", "SHAMAN" }

local function RunTest(count)
    count = math.max(2, math.min(40, count or 5))
    local roster = {}
    roster[1] = { name = PlayerName() or "Ich", class = select(2, UnitClass("player")) }
    for i = 2, count do
        local base = TEST_NAMES[(i - 2) % #TEST_NAMES + 1]
        roster[i] = { name = i > #TEST_NAMES + 1 and (base .. (i - 1)) or base, class = TEST_CLASSES[(i - 1) % #TEST_CLASSES + 1] }
    end
    local testItems = {
        NewItem({ test = true, name = T("Klinge des Testens", "Blade of Testing"), icon = 135274, quality = 3, duration = 20, roster = roster }),
        NewItem({ test = true, name = T("Robe der Probe", "Robe of Trials"), icon = 132656, quality = 2, duration = 20, roster = roster }),
    }
    Refresh()

    -- nach und nach waehlen die Spieler, dann wird gewuerfelt
    for n, item in ipairs(testItems) do
        for i, p in ipairs(roster) do
            C_Timer.After(0.4 + i * (8 / count) + n * 0.3, Safe("Testmodus", function()
                local r = (i * 37 + n * 11) % 10
                local choice = (r < 3 and "need") or (r < 7 and "greed") or "pass"
                local player = item.players[p.name]
                if not player then return end
                player.choice = choice
                Refresh()
            end))
        end
        C_Timer.After(10 + n, Safe("Testmodus", function()
            local best, bestRoll, bestOrder
            for _, p in pairs(item.players) do
                if p.choice == "need" or p.choice == "greed" then
                    p.roll = math.random(1, 100)
                    local o = CHOICE[p.choice].order
                    if not best or o < bestOrder or (o == bestOrder and p.roll > bestRoll) then
                        best, bestRoll, bestOrder = p.name, p.roll, o
                    end
                end
            end
            if best then item.winner = best else item.allPassed = true end
            Finish(item)
            Refresh()
        end))
    end
    Chat(string.format(T("Testmodus: 2 Gegenstände mit %d Spielern. Fenster zum Verschieben ziehen.",
        "Test mode: 2 items with %d players. Drag the window to move it."), count))
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
local H = {}

H.ADDON_LOADED = function(name)
    if name ~= ADDON_NAME then return end
    RestorePosition()
end

H.PLAYER_LOGIN = function()
    RestorePosition()
    UpdateMinimapPosition()
    -- noch nicht gesperrt (z. B. erster Start): Fenster gleich zeigen, damit man es platzieren kann
    frame.moving = not GetDB().locked
    Refresh()
end

-- Wir duerfen selbst wuerfeln: Gegenstand mit Restzeit anlegen
H.START_LOOT_ROLL = function(rollID, rollTime)
    if IsSecret(rollID) then return end
    local icon, name, _, quality = GetLootRollItemInfo(rollID)
    local link = GetLootRollItemLink(rollID)
    -- schon ueber den Chat angelegt?
    local existing = link and FindOpenItem(link, function(it) return not it.rollID end)
    if existing then
        existing.rollID, existing.duration, existing.start = rollID, (rollTime or 60000) / 1000, GetTime()
        existing.icon, existing.quality = existing.icon or icon, existing.quality or quality
    else
        NewItem({ rollID = rollID, link = link, name = name, icon = icon, quality = quality,
            duration = (rollTime or 60000) / 1000 })
    end
    Refresh()
end

H.CHAT_MSG_LOOT = OnLootMessage

for event in pairs(H) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, ...)
    local handler = H[event]
    if handler then Safe(event, handler)(...) end
end)

---------------------------------------------------------------------------
-- Sperren / Verschieben
---------------------------------------------------------------------------
-- Entsperrt: Fenster bleibt (auch ohne Wurf) sichtbar und laesst sich ziehen
local function SetLocked(locked)
    local o = GetDB()
    o.locked = locked
    frame.moving = not locked
    Refresh()
end

---------------------------------------------------------------------------
-- Einstellungsfenster
---------------------------------------------------------------------------
local ToggleOptions
do
    local options = UI.Window("ForeverLootOptions", T("ForeverLoot – Einstellungen", "ForeverLoot – Settings"), 340, 400)
    local W = 308 -- Breite der Ueberschriften

    local function Button(text, width, onClick)
        return UI.Button(options, text, width, Safe(T("Einstellungen", "Settings"), onClick))
    end

    -- Position: verschieben und sperren
    UI.Header(options, 18, -32, T("Position", "Position"), W)

    local lock = UI.Check(options, 14, -54, T("Fenster sperren", "Lock window"),
        Safe(T("Einstellungen", "Settings"), function(checked) SetLocked(checked) end))

    local moveBtn = Button(T("Verschieben", "Move"), 110, function()
        SetLocked(false)
        lock:SetChecked(false)
    end)
    moveBtn:SetPoint("TOPLEFT", 16, -82)
    local doneBtn = Button(T("Fertig – sperren", "Done – lock"), 130, function()
        SetLocked(true)
        lock:SetChecked(true)
    end)
    doneBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)
    local resetBtn = Button(T("Position zurücksetzen", "Reset position"), 160, function()
        local o = GetDB()
        o.pos = nil
        RestorePosition()
    end)
    resetBtn:SetPoint("TOPLEFT", 16, -108)

    -- Anzeige: Schieberegler mit – / +
    UI.Header(options, 18, -144, T("Anzeige", "Display"), W)
    local sliders = {}
    local function Slider(label, key, minV, maxV, step, y, toValue, fromValue, unit)
        local s = UI.Slider(options, 18, y, label, minV, maxV, step, Safe(T("Einstellungen", "Settings"), function(value)
            GetDB()[key] = toValue(value)
            RestorePosition()
            Refresh()
        end), { width = 200, unit = unit })
        s.ffLoad = function() s:Load(fromValue(GetDB()[key])) end
        sliders[#sliders + 1] = s
    end

    local function Same(v) return v end
    Slider(T("Größe", "Size"), "scale", 50, 200, 5, -168,
        function(v) return v / 100 end, function(v) return math.floor(v * 100 + 0.5) end, " %")
    Slider(T("Nach dem Ergebnis ausblenden nach", "Hide after result"), "keep", 1, 60, 1, -208, Same, Same, " s")
    Slider(T("Liste einklappen ab mehr als", "Collapse list above"), "maxRows", 1, 40, 1, -248, Same, Same,
        T(" Spielern", " players"))

    -- Test und Liste
    UI.Header(options, 18, -294, T("Testmodus", "Test mode"), W)
    local test5 = Button(T("Test: 5 Spieler", "Test: 5 players"), 140, function() RunTest(5) end)
    test5:SetPoint("TOPLEFT", 16, -318)
    local test20 = Button(T("Test: 20 Spieler", "Test: 20 players"), 140, function() RunTest(20) end)
    test20:SetPoint("LEFT", test5, "RIGHT", 6, 0)
    local clear = Button(T("Liste leeren", "Clear list"), 140, function()
        wipe(items)
        Refresh()
    end)
    clear:SetPoint("TOPLEFT", 16, -344)

    options:SetScript("OnShow", function()
        lock:SetChecked(GetDB().locked)
        for _, s in ipairs(sliders) do s.ffLoad() end
    end)

    function ToggleOptions()
        options:SetShown(not options:IsShown())
    end
end

---------------------------------------------------------------------------
-- Minimap-Button (wird bei mehreren Forever-Addons im Sammelknopf gebuendelt)
---------------------------------------------------------------------------
-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverLoot", function() return GetDB().locked end, SetLocked)
end

do
    local mm = UI.MinimapButton({
        name = "ForeverLootMinimapButton",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        title = "ForeverLoot",
        angle = function() return GetDB().minimapAngle end,
        setAngle = function(a) GetDB().minimapAngle = a end,
        onClick = Safe("Minimap", function(_, button)
            if button == "RightButton" then
                local locked = not GetDB().locked
                SetLocked(locked)
                Chat(locked and T("Fenster gesperrt.", "Window locked.")
                    or T("Fenster entsperrt – zum Verschieben ziehen.", "Window unlocked – drag to move."))
            else
                ToggleOptions()
            end
        end),
        lines = function()
            return {
                T("Linksklick: Einstellungen", "Left-click: settings"),
                GetDB().locked and T("Rechtsklick: Fenster entsperren/verschieben", "Right-click: unlock/move window")
                    or T("Rechtsklick: Fenster sperren", "Right-click: lock window"),
            }
        end,
    })
    UpdateMinimapPosition = mm.UpdatePosition
end

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------
SLASH_FOREVERLOOT1 = "/floot"
SLASH_FOREVERLOOT2 = "/foreverloot"
SlashCmdList["FOREVERLOOT"] = Safe("Befehl", function(msg)
    msg = strtrim(msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.*)$")
    local o = GetDB()
    if cmd == "test" then
        RunTest(tonumber(arg))
    elseif cmd == "" or cmd == "config" or cmd == "optionen" then
        ToggleOptions()
    elseif cmd == "lock" then
        SetLocked(not o.locked)
        Chat(o.locked and T("Fenster gesperrt.", "Window locked.") or T("Fenster entsperrt – zum Verschieben ziehen.", "Window unlocked – drag to move."))
    elseif cmd == "reset" then
        o.pos, o.scale = nil, 1
        RestorePosition()
        Chat(T("Position zurückgesetzt.", "Position reset."))
    elseif cmd == "clear" then
        wipe(items)
        Refresh()
    elseif cmd == "status" then
        -- Selbsttest: welche Chat-Vorlagen des Spiels wurden gefunden?
        local found, missing = 0, {}
        for _, m in ipairs(MESSAGES) do
            if m.compiled then found = found + 1 else missing[#missing + 1] = m.g end
        end
        Chat(string.format(T("Chat-Vorlagen erkannt: %d von %d", "Chat templates found: %d of %d"), found, #MESSAGES))
        if #missing > 0 then
            Chat(T("Fehlend (normal, wenn es sie in diesem Client nicht gibt): ", "Missing (normal if this client lacks them): ")
                .. table.concat(missing, ", "))
        end
        Chat(string.format(T("Aktive Einträge: %d", "Active entries: %d"), #items))
    elseif cmd == "scale" and tonumber(arg) then
        o.scale = math.max(0.5, math.min(2, tonumber(arg) / 100))
        RestorePosition()
        Chat(string.format(T("Größe: %d %%", "Scale: %d %%"), o.scale * 100 + 0.5))
    elseif cmd == "keep" and tonumber(arg) then
        o.keep = math.max(1, math.min(600, tonumber(arg)))
        Chat(string.format(T("Fertige Würfe bleiben %d s sichtbar.", "Finished rolls stay visible for %d s."), o.keep))
    elseif cmd == "rows" and tonumber(arg) then
        o.maxRows = math.max(1, math.min(40, tonumber(arg)))
        Chat(string.format(T("Ab %d Spielern startet die Liste eingeklappt.", "Lists with more than %d players start collapsed."), o.maxRows))
    else
        Chat(T("Befehle (oder einfach /floot für die Einstellungen):", "Commands (or just /floot for the settings):"))
        Chat(T("  /floot test [Anzahl] – Testmodus (z. B. /floot test 20)", "  /floot test [count] – test mode (e.g. /floot test 20)"))
        Chat(T("  /floot lock – Fenster sperren/entsperren", "  /floot lock – lock/unlock window"))
        Chat(T("  /floot scale 120 – Größe in Prozent", "  /floot scale 120 – size in percent"))
        Chat(T("  /floot keep 5 – Sekunden nach dem Ergebnis bis zum Ausblenden", "  /floot keep 5 – seconds after the result until it hides"))
        Chat(T("  /floot rows 5 – ab so vielen Spielern eingeklappt", "  /floot rows 5 – collapse lists above this many players"))
        Chat(T("  /floot reset – Position zurücksetzen,  /floot clear – Liste leeren", "  /floot reset – reset position,  /floot clear – clear list"))
        Chat(T("  /floot status – Selbsttest", "  /floot status – self-test"))
    end
end)
