-- ForeverBuffs: unaufdringliche Erinnerung an fehlende Buffs, niedrige Raenge und Verbrauchsgueter.
-- Geprueft wird nur ausserhalb des Kampfs (dort sind alle Daten lesbar). Eine kleine Symbol-Leiste
-- erscheint nur, wenn etwas fehlt; Klick auf ein Buff-Symbol wirkt den Buff (hoechster Rang).
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
local T = UI.T

---------------------------------------------------------------------------
-- Einstellungen (wegen des Beta-Bugs bei jedem Zugriff pruefen)
---------------------------------------------------------------------------
local DEFAULTS = {
    locked = true,
    iconSize = 22,
    hideResting = true,     -- in Gasthaus/Hauptstadt keine Buff-Hinweise (Verbrauchsgueter bleiben: dort ist der Haendler)
    hideInCombat = false,   -- im Kampf ausblenden (sonst bleibt der Stand von vor dem Kampf sichtbar)
    ownBuffs = true,
    rankCheck = true,       -- niedrigerer Rang aktiv als bekannt?
    groupBuffs = true,      -- Gruppen-Buffs (fehlende bei anderen / bei mir)
    optionalBuffs = false,  -- z. B. Dornen, Schattenschutz
    food = true,
    drink = true,
    tierCheck = true,       -- besseres Essen/Trinken fuer die Stufe moeglich?
    weapon = nil,           -- Waffen-Verzauberung (Gift/Oel); nil = je nach Klasse
    ammo = true, ammoMin = 200,
    shards = true, shardMin = 2,
    custom = "",            -- eigene Liste: je Zeile "Name oder ID[:Anzahl]"
    minimapAngle = 60,
}

local db
local function GetDB()
    if type(_G.ForeverBuffsDB) ~= "table" then _G.ForeverBuffsDB = db or {} end
    db = _G.ForeverBuffsDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    local _, class = UnitClass("player")
    if db.weapon == nil then db.weapon = class == "ROGUE" or class == "SHAMAN" end
    -- einmalig: Schamanen bekommen die Waffen-Pruefung (Verzauberungen) dazu
    if not db.weaponV2 then
        if class == "SHAMAN" then db.weapon = true end
        db.weaponV2 = true
    end
    return db
end

local issecret = issecretvalue or function() return false end
local function IsSecret(v) return issecret(v) end
local function Chat(text) UI.Chat("ForeverBuffs", text) end

local _, myClass = UnitClass("player")
-- Kennt der Spieler den Zauber? (neue Schnittstelle bevorzugt, alte als Ersatz)
local function IsKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then return C_SpellBook.IsSpellInSpellBook(id) end
    local legacy = _G.IsPlayerSpell or _G.IsSpellKnown
    return legacy and legacy(id) or false
end
local function SpellName(id) return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or tostring(id) end
local function SpellIcon(id) return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or 134400 end

---------------------------------------------------------------------------
-- Buffs lesen (nur ausserhalb des Kampfs)
---------------------------------------------------------------------------
local function AuraIDs(unit)
    local ids = {}
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return ids end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or not aura then break end
        local id = aura.spellId
        if not IsSecret(id) and id then ids[id] = true end
    end
    return ids
end

-- hoechster bekannter Rang einer Reihe (Index und Zauber-ID)
local function BestKnown(line)
    for i = #line, 1, -1 do
        if IsKnown(line[i]) then return i, line[i] end
    end
end

-- Familie: was ist aktiv? -> Reihe, Rang-Index (nil = nicht aktiv; "also" = Gruppen-Variante)
local function ActiveIn(fam, ids)
    for li, line in ipairs(fam.lines) do
        for ri, id in ipairs(line) do
            if ids[id] then return li, ri end
        end
    end
    for _, id in ipairs(fam.also or {}) do
        if ids[id] then return "also" end
    end
end

-- bester bekannter Zauber der Familie (letzte bekannte Reihe gewinnt bei "supersede")
local function BestSpell(fam)
    local bestLine, bestId
    for li, line in ipairs(fam.lines) do
        local _, id = BestKnown(line)
        if id then
            if not bestId then bestLine, bestId = li, id end
            if fam.supersede and fam.supersede[bestLine] == li then bestLine, bestId = li, id end
        end
    end
    return bestId, bestLine
end

local function Enabled(fam)
    return not fam.optional or GetDB().optionalBuffs
end

-- alle Zauber-IDs einer Familie (jeder Rang, auch Gruppen-Variante) – fuer die Kampf-Anzeige
local function FamilyIDs(fam)
    local ids = {}
    for _, line in ipairs(fam.lines) do
        for _, id in ipairs(line) do ids[id] = true end
    end
    for _, id in ipairs(fam.also or {}) do ids[id] = true end
    return ids
end

-- Gruppe: Einheiten (inkl. mir) und vorhandene Klassen
local function GroupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if not UnitIsUnit(u, "player") then units[#units + 1] = u end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

---------------------------------------------------------------------------
-- Pruefung -> Liste von Hinweisen { icon, title, lines, color, spell, unit, count }
---------------------------------------------------------------------------
local RED, YELLOW, GREY = { 1, 0.25, 0.25 }, { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }

local function CheckBuffs(issues)
    local d = GetDB()
    local myIDs = AuraIDs("player")
    local units = GroupUnits()
    local inGroup = #units > 1

    -- Klassen in der Gruppe (fuer Buffs, die mir jemand geben koennte)
    local classes = {}
    for _, u in ipairs(units) do
        local _, c = UnitClass(u)
        if not IsSecret(c) and c and UnitIsConnected(u) then classes[c] = true end
    end

    for _, fam in ipairs(ns.BUFFS) do
        if Enabled(fam) then
            local mine = fam.class == myClass
            local spell = mine and BestSpell(fam)
            if mine and spell then
                -- eigene Buffs auf mir: fehlt er, oder ist ein niedrigerer Rang aktiv?
                if fam.self and d.ownBuffs then
                    local line, rank = ActiveIn(fam, myIDs)
                    if not line then
                        issues[#issues + 1] = { icon = SpellIcon(spell), color = RED, spell = spell, unit = "player",
                            watch = { unit = "player", ids = FamilyIDs(fam) }, title = SpellName(spell), lines = { T("Fehlt – Klick zum Wirken.", "Missing – click to cast.") } }
                    elseif d.rankCheck and line ~= "also" then
                        local bestRank, bestId = BestKnown(fam.lines[line])
                        local _, bestLine = BestSpell(fam)
                        local outdated = (bestRank and rank < bestRank)
                            or (fam.supersede and fam.supersede[line] == bestLine and bestLine ~= line)
                        if outdated then
                            local castId = (fam.supersede and fam.supersede[line] == bestLine) and spell or bestId
                            issues[#issues + 1] = { icon = SpellIcon(castId), color = YELLOW, spell = castId, unit = "player",
                                title = SpellName(castId), lines = { T("Ein niedrigerer Rang ist aktiv – Klick wirkt den höchsten.",
                                    "A lower rank is active – click to cast the highest.") } }
                        end
                    end
                end
                -- meine Gruppen-Buffs bei den anderen
                if fam.group and inGroup and d.groupBuffs then
                    local missing = {}
                    for i = 2, #units do
                        local u = units[i]
                        if UnitExists(u) and UnitIsConnected(u) and not UnitIsDeadOrGhost(u) and not ActiveIn(fam, AuraIDs(u)) then
                            missing[#missing + 1] = u
                        end
                    end
                    if #missing > 0 then
                        local names = {}
                        for _, u in ipairs(missing) do names[#names + 1] = UnitName(u) or u end
                        issues[#issues + 1] = { icon = SpellIcon(spell), color = RED, spell = spell, unit = missing[1],
                            count = #missing, title = SpellName(spell),
                            watch = #missing == 1 and { unit = missing[1], ids = FamilyIDs(fam) } or nil,
                            lines = { string.format(T("Fehlt bei %d: %s", "Missing on %d: %s"), #missing, table.concat(names, ", ")),
                                T("Klick wirkt ihn auf den Ersten.", "Click casts it on the first one.") } }
                    end
                end
            elseif fam.group and inGroup and d.groupBuffs and classes[fam.class] and not mine then
                -- Gruppen-Buff, den mir jemand geben koennte
                if not ActiveIn(fam, myIDs) then
                    local id = fam.lines[1][1]
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[fam.class]
                    local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[fam.class]) or fam.class
                    issues[#issues + 1] = { icon = SpellIcon(id), color = GREY, title = SpellName(id),
                        watch = { unit = "player", ids = FamilyIDs(fam) },
                        lines = { string.format(T("Fehlt dir – ein %s in der Gruppe kann ihn geben.", "You are missing it – a %s in your group can give it."),
                            cc and cc:WrapTextInColorCode(cname) or cname) } }
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Verbrauchsgueter in den Taschen
---------------------------------------------------------------------------
local function BagItems()
    local list = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return list end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local e = list[info.itemID]
                if not e then
                    e = { id = info.itemID, count = 0, icon = info.iconFileID, name = info.itemName }
                    list[info.itemID] = e
                end
                e.count = e.count + (info.stackCount or 1)
            end
        end
    end
    return list
end

-- Essen oder Trinken? (am Namen des Benutzen-Zaubers, in jeder Spielsprache)
local foodName, drinkName
local function ItemKind(id)
    foodName = foodName or SpellName(ns.FOOD_SPELL)
    drinkName = drinkName or SpellName(ns.DRINK_SPELL)
    local spellName = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)
    if not spellName then return nil end
    if spellName == drinkName then return "drink" end
    if spellName == foodName then return "food" end
end

local function MinLevel(id)
    if not (C_Item and C_Item.GetItemInfo) then return 0 end
    local _, _, _, _, minLevel = C_Item.GetItemInfo(id)
    return minLevel or 0
end

local function BestTier()
    local level = UnitLevel("player")
    if IsSecret(level) then return 1 end
    local best = 1
    for _, t in ipairs(ns.FOOD_TIERS) do
        if level >= t then best = t end
    end
    return best
end

-- Ist die Haupthand-Waffe verzaubert (Gift, Oel, Stein, Schamanen-Verzauberung)?
-- Drei Wege, einer genuegt: Blizzards Abfrage, ein Buff mit dem Namen der Verzauberung
-- (so legt dieser Client Schamanen-Verzauberungen an) oder der Waffen-Tooltip, in dem
-- voruebergehende Verzauberungen mit Restzeit stehen, z. B. "Windzorn 3 (30 Min.)".
local function WeaponEnchanted()
    if GetWeaponEnchantInfo then
        local hasMain = GetWeaponEnchantInfo()
        if IsSecret(hasMain) or hasMain then return true end
    end
    -- Buff am Spieler mit dem Namen einer Schamanen-Verzauberung
    if myClass == "SHAMAN" and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local names = {}
        for _, line in ipairs(ns.SHAMAN_IMBUES) do
            for _, id in ipairs(line) do
                local n = SpellName(id)
                if n then names[n] = true end
            end
        end
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            local name = aura.name
            if IsSecret(name) or (name and names[name]) then return true end
        end
    end
    -- Tooltip der Waffe: Zeile mit Restzeit in Klammern
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 16)
        if ok and data and data.lines then
            for _, l in ipairs(data.lines) do
                local text = l.leftText
                if text and not IsSecret(text) and text:find("%(%d+%s*%a") then return true end
            end
        end
    end
    return false
end

local function CheckConsumables(issues)
    local d = GetDB()
    local items = BagItems()
    local tier = BestTier()
    local usesMana = (UnitPowerMax("player", 0) or 0) > 0

    -- Essen / Trinken
    for _, kind in ipairs({ "food", "drink" }) do
        if d[kind] and (kind == "food" or usesMana) then
            local count, bestLevel, bestIcon = 0, -1, nil
            for id, e in pairs(items) do
                if ItemKind(id) == kind then
                    count = count + e.count
                    local lvl = MinLevel(id)
                    if lvl > bestLevel then bestLevel, bestIcon = lvl, e.icon end
                end
            end
            local label = kind == "food" and T("Essen", "Food") or T("Trinken", "Drink")
            local icon = kind == "food" and 133964 or 132794
            if count == 0 then
                issues[#issues + 1] = { icon = icon, color = RED, title = label,
                    lines = { T("Nichts dabei.", "None in your bags.") } }
            elseif d.tierCheck and bestLevel < tier then
                issues[#issues + 1] = { icon = bestIcon or icon, color = YELLOW, title = label,
                    lines = { string.format(T("Für deine Stufe gibt es Besseres (ab Stufe %d).", "Better is available for your level (from level %d)."), tier) } }
            end
        end
    end

    -- Klassen-Extras
    if d.weapon and GetInventoryItemID("player", 16) and not WeaponEnchanted() then
        do
            -- Schamane: beste bekannte Waffenverzauberung per Klick wirken
            local imbue
            if myClass == "SHAMAN" then
                for _, line in ipairs(ns.SHAMAN_IMBUES) do
                    local _, id = BestKnown(line)
                    if id then imbue = id break end
                end
            end
            if imbue then
                local ids = {}
                for _, line in ipairs(ns.SHAMAN_IMBUES) do
                    for _, id in ipairs(line) do ids[id] = true end
                end
                issues[#issues + 1] = { icon = SpellIcon(imbue), color = RED, spell = imbue, unit = "player",
                    watch = { unit = "player", ids = ids },
                    title = SpellName(imbue), lines = { T("Keine Waffenverzauberung aktiv – Klick zum Wirken.", "No weapon imbue active – click to cast.") } }
            else
                issues[#issues + 1] = { icon = GetInventoryItemTexture("player", 16) or 135966, color = RED,
                    title = T("Waffe", "Weapon"), lines = { T("Kein Gift/Öl/Stein auf der Waffe.", "No poison/oil/stone on your weapon.") } }
            end
        end
    end
    if myClass == "HUNTER" and d.ammo then
        local ammo = GetInventoryItemCount("player", 0) or 0
        if GetInventoryItemID("player", 0) == nil or ammo < d.ammoMin then
            issues[#issues + 1] = { icon = GetInventoryItemTexture("player", 0) or 132382, color = ammo == 0 and RED or YELLOW,
                count = ammo, title = T("Munition", "Ammo"),
                lines = { string.format(T("Nur noch %d.", "Only %d left."), ammo) } }
        end
    end
    if myClass == "WARLOCK" and d.shards then
        local n = items[ns.SOUL_SHARD] and items[ns.SOUL_SHARD].count or 0
        if n < d.shardMin then
            issues[#issues + 1] = { icon = 134075, color = n == 0 and RED or YELLOW, count = n,
                title = T("Seelensplitter", "Soul Shards"), lines = { string.format(T("Nur noch %d.", "Only %d left."), n) } }
        end
    end

    -- Eigene Liste: "Name oder ID[:Anzahl]" je Zeile (Namensteil genuegt)
    for line in (d.custom or ""):gmatch("[^\n,]+") do
        local entry, min = line:match("^%s*(.-)%s*:%s*(%d+)%s*$")
        entry = strtrim(entry or line)
        min = tonumber(min) or 1
        if entry ~= "" then
            local id = tonumber(entry)
            local count, icon = 0, nil
            for itemID, e in pairs(items) do
                local name = e.name or ""
                if (id and itemID == id) or (not id and name:lower():find(entry:lower(), 1, true)) then
                    count = count + e.count
                    icon = icon or e.icon
                end
            end
            if count < min then
                issues[#issues + 1] = { icon = icon or (id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400,
                    color = count == 0 and RED or YELLOW, count = count, title = entry,
                    lines = { string.format(T("%d von %d dabei.", "%d of %d in your bags."), count, min) } }
            end
        end
    end
end

---------------------------------------------------------------------------
-- Symbol-Leiste (sichere Knoepfe: Klick wirkt den Buff)
---------------------------------------------------------------------------
local MAX_ICONS = 12
-- Anker: bestimmt die Position der Leiste. Entsperrt sichtbar (blauer Rahmen) und ziehbar,
-- Rechtsklick darauf sperrt wieder. Die Leiste haengt links am Anker.
local anchor = CreateFrame("Frame", "ForeverBuffsAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(170, 30)
anchor:SetPoint("TOP", 0, -57)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:SetFrameStrata("DIALOG")
UI.Hud(anchor, 0.55)
anchor:SetBackdropBorderColor(0.3, 0.6, 1, 1)
anchor:RegisterForDrag("LeftButton")
anchor:Hide()
local anchorText = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
anchorText:SetPoint("BOTTOM", anchor, "TOP", 0, 3)
anchorText:SetText(T("ForeverBuffs – ziehen · Rechtsklick: sperren", "ForeverBuffs – drag · right-click: lock"))

local bar = CreateFrame("Frame", "ForeverBuffsBar", UIParent)
bar:SetSize(200, 24)
bar:SetPoint("LEFT", anchor, "LEFT", 4, 0)
bar:Hide()

local ToggleLock -- weiter unten
UI.AddMover(bar) -- andere Forever-Rahmen rasten an der Leiste ein
anchor:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    UI.BeginDrag(self) -- Einrasten an anderen Rahmen (Umschalt = aus, Schalter im Hub)
    self:StartMoving()
end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local dx, dy = UI.EndDrag()
    local point, _, relPoint, x, y = self:GetPoint()
    if dx ~= 0 or dy ~= 0 then
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        x, y = x + dx / s, y + dy / s
        self:ClearAllPoints()
        self:SetPoint(point, UIParent, relPoint, x, y)
    end
    GetDB().pos = { point, relPoint, x, y }
end)
anchor:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and ToggleLock then ToggleLock() end
end)

local buttons = {}
for i = 1, MAX_ICONS do
    local b = CreateFrame("Button", "ForeverBuffsButton" .. i, bar, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.border:SetColorTexture(1, 1, 1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", 1, -1)
    b:SetScript("OnEnter", function(self)
        local issue = self.issue
        if not issue then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(issue.title)
        for _, l in ipairs(issue.lines or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    buttons[i] = b
end

---------------------------------------------------------------------------
-- Im Kampf: Blizzard-Anzeige (AuraContainer) ueber jedem Buff-Symbol – wie bei den HoT-Symbolen
-- in ForeverFrames. Das Spiel zeichnet den Buff selbst darueber, sobald er da ist (gruener Rahmen
-- + Haken); faellt er wieder ab, ist das Warnsymbol wieder zu sehen. Das Addon muss dafuer keine
-- gesperrten Aura-Daten lesen.
---------------------------------------------------------------------------
local WATCH_KEY = "fb_watch"
local function WatchSupported()
    return AuraContainerSortDirection ~= nil and AuraContainerSortMethod ~= nil
end

-- Aussehen des vom Spiel gezeichneten Symbols
local function WatchInitializer(size)
    return function(f)
        f:SetSize(size, size)
        f:EnableMouse(false) -- Klicks gehen durch auf den Knopf darunter
        local border = f:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0.2, 1, 0.3, 1)
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f:SetIcon(icon)
        local check = f:CreateTexture(nil, "OVERLAY")
        check:SetSize(size * 0.7, size * 0.7)
        check:SetPoint("CENTER")
        check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    end
end

local function RetireWatch(c)
    if not c then return end
    pcall(c.ClearAuraGroups, c)
    c:Hide()
end

-- Container fuer einen Knopf: Einheit + Zauber-IDs des Buffs (alle Raenge), hoechstens 1 Symbol.
-- Aendert sich etwas, gibt es einen frischen Container (Filter nachtraeglich aendern ist unsicher).
-- Fluss-Layout wie in ForeverFrames: Richtung, Wachstum, Ankerpunkt und maximale Zeilenlaenge.
-- Ohne Zeilenlaenge passt kein Symbol hinein und das Spiel zeichnet nichts.
local function EnumValue(enumTable, ...)
    if not enumTable then return nil end
    for i = 1, select("#", ...) do
        local v = enumTable[(select(i, ...))]
        if v ~= nil then return v end
    end
end
local function ApplyWatchFlow(c, size)
    local axisEnum = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local dirEnum = AnchorUtil and AnchorUtil.FlowDirection
    if not (axisEnum and dirEnum and c.SetFlowLayoutAxis) then return false end
    local axis = EnumValue(axisEnum, "Horizontal", "HORIZONTAL", "X")
    local forward = EnumValue(dirEnum, "Up", "Right", "Forward", "FORWARD", "Positive")
    if axis == nil or forward == nil then return false end
    return pcall(function()
        c:SetFlowLayoutAxis(axis)
        c:SetFlowLayoutGrowthDirection(forward, forward)
        c:SetFlowLayoutAnchorPoint("TOPLEFT")
        c:SetFlowLayoutMaximumLineSize(size + 1)
    end)
end

local function SetWatch(b, watch, size)
    if not WatchSupported() then return end
    local sig
    if watch then
        local ids = {}
        for id in pairs(watch.ids) do ids[#ids + 1] = id end
        table.sort(ids)
        sig = size .. ":" .. watch.unit .. ":" .. table.concat(ids, ",")
    end
    local c = b.watchC
    if c and c.fbSig == sig then
        if c then c:Show() end
        return
    end
    RetireWatch(c)
    b.watchC = nil
    if not watch then return end

    local ok
    ok, c = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not (ok and c) then return end
    c:SetAllPoints(b)
    c:SetFrameLevel(b:GetFrameLevel() + 5)
    local added = pcall(c.AddAuraGroup, c, WATCH_KEY, "HELPFUL", {
        maxFrameCount = 1,
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        candidateFilters = { includeSpellIDs = watch.ids },
        initializeFrame = WatchInitializer(size),
    })
    if not added then c:Hide() return end
    local layout = { elementWidth = size, elementHeight = size, elementSpacing = 0, lineSpacing = 0, layoutIndex = 1 }
    if not ApplyWatchFlow(c, size) then
        -- aeltere Variante der Anzeige: Wachstum direkt im Layout
        layout.growthDirection = "RIGHT_UP"
        layout.wrapAfter = size + 1
    end
    pcall(c.SetAuraGroupLayout, c, WATCH_KEY, layout)
    pcall(c.SetUnit, c, watch.unit)
    c.fbSig = sig
    b.watchC = c
    c:Show()
end

local function Visible()
    local d = GetDB()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or (UnitOnTaxi and UnitOnTaxi("player")) then return false end
    return true
end

local testMode = false
local function TestIssues()
    return {
        { icon = SpellIcon(1243), color = RED, title = T("Beispiel: fehlender Buff", "Example: missing buff"), lines = { "" } },
        { icon = 133964, color = YELLOW, title = T("Beispiel: besseres Essen möglich", "Example: better food available"), lines = { "" } },
        { icon = 134830, color = RED, count = 0, title = T("Beispiel: eigene Liste", "Example: own list"), lines = { "" } },
    }
end

local function Render(issues)
    local d = GetDB()
    local size = d.iconSize
    for i, b in ipairs(buttons) do
        local issue = issues[i]
        b.issue = issue
        if issue then
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (size + 3), 0)
            b.icon:SetTexture(issue.icon)
            local c = issue.color or RED
            b.border:SetColorTexture(c[1], c[2], c[3], 0.9)
            b.count:SetText(issue.count and issue.count > 1 and issue.count or (issue.count == 0 and "0" or ""))
            if issue.spell then
                b:SetAttribute("type", "spell")
                b:SetAttribute("spell", issue.spell)
                b:SetAttribute("unit", issue.unit or "player")
            else
                b:SetAttribute("type", nil)
            end
            b:Show()
            SetWatch(b, issue.watch, size)
        else
            b:Hide()
            SetWatch(b, nil, size)
        end
    end
    bar:SetSize(math.max(1, #issues) * (size + 3), size)
end

local function Update()
    if InCombatLockdown() then return end -- Knoepfe sind geschuetzt; nach dem Kampf weiter
    local d = GetDB()
    if not Visible() and not testMode and d.locked then bar:Hide() return end
    local issues = {}
    if testMode then
        issues = TestIssues()
    else
        local ok, err = true, nil
        if not (d.hideResting and IsResting()) then ok, err = pcall(CheckBuffs, issues) end
        if ok then ok, err = pcall(CheckConsumables, issues) end
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then pcall(handler, err) end
        end
    end
    -- entsperrt: Beispiel-Symbole zeigen, damit man sieht, wo die Leiste erscheint
    if not d.locked and #issues == 0 then issues = TestIssues() end
    while #issues > MAX_ICONS do table.remove(issues) end
    Render(issues)
    bar:SetShown(#issues > 0)
    anchor:SetSize(math.max(170, #issues * (d.iconSize + 3) + 8), d.iconSize + 8)
    anchor:SetShown(not d.locked)
    anchor:EnableMouse(not d.locked)
end

-- Aenderungen sammeln, hoechstens 2x pro Sekunde pruefen
local dirty = true
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    if dirty then
        dirty = false
        Update()
    end
end)
C_Timer.NewTicker(10, function() dirty = true end) -- Buffs laufen ab, ohne dass sich etwas meldet

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UNIT_AURA", "BAG_UPDATE_DELAYED", "GROUP_ROSTER_UPDATE",
    "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Im Kampf darf die Leiste nicht umgebaut werden und Aura-Daten sind gesperrt:
        -- sie bleibt mit dem Stand von vor dem Kampf stehen (Klick zum Wirken geht weiter).
        -- Auf Wunsch ausblenden – das geht nur jetzt, noch vor der Kampfsperre.
        if GetDB().hideInCombat then bar:Hide() end
        return
    elseif event == "PLAYER_LOGIN" then
        local pos = GetDB().pos
        if pos then
            anchor:ClearAllPoints()
            anchor:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        end
    elseif event == "UNIT_AURA" and unit and not (unit == "player" or unit:find("^party") or unit:find("^raid")) then
        return
    end
    dirty = true
end)

---------------------------------------------------------------------------
-- Einstellungen
---------------------------------------------------------------------------
local options = UI.Window("ForeverBuffsOptions", T("ForeverBuffs – Einstellungen", "ForeverBuffs – Settings"), 620, 500)
local controls = {}
local function Refresh() dirty = true end

local function Check(p, x, y, label, key)
    local cb = UI.Check(p, x, y, label, function(checked)
        GetDB()[key] = checked
        Refresh()
    end)
    controls[#controls + 1] = function() cb:SetChecked(GetDB()[key] and true or false) end
    return cb
end
local function Slider(p, x, y, label, key, minV, maxV, step, opts)
    local s = UI.Slider(p, x, y, label, minV, maxV, step, function(v)
        GetDB()[key] = v
        Refresh()
    end, opts)
    controls[#controls + 1] = function() s:Load(GetDB()[key]) end
end

local L, R = 18, 318
UI.Header(options, L, -32, T("Buffs", "Buffs"), 280)
Check(options, L - 4, -54, T("Eigene Buffs", "Own buffs"), "ownBuffs")
Check(options, L - 4, -78, T("Höchsten Rang prüfen", "Check for highest rank"), "rankCheck")
Check(options, L - 4, -102, T("Gruppen-Buffs (bei anderen und bei mir)", "Group buffs (others and me)"), "groupBuffs")
Check(options, L - 4, -126, T("Auch Dornen / Schattenschutz", "Also Thorns / Shadow Protection"), "optionalBuffs")

UI.Header(options, L, -166, T("Essen und Trinken", "Food and drink"), 280)
Check(options, L - 4, -188, T("Essen dabei", "Carry food"), "food")
Check(options, L - 4, -212, T("Trinken dabei (Klassen mit Mana)", "Carry drink (mana users)"), "drink")
Check(options, L - 4, -236, T("Bestes für meine Stufe", "Best for my level"), "tierCheck")

UI.Header(options, L, -276, T("Klasse", "Class"), 280)
Check(options, L - 4, -298, T("Waffe: Gift/Öl/Stein bzw. Verzauberung (Schamane)", "Weapon: poison/oil/stone or imbue (shaman)"), "weapon")
Check(options, L - 4, -322, T("Munition (Jäger)", "Ammo (hunter)"), "ammo")
Slider(options, L + 2, -350, T("Munition ab", "Ammo below"), "ammoMin", 0, 1000, 50)
Check(options, L - 4, -392, T("Seelensplitter (Hexenmeister)", "Soul shards (warlock)"), "shards")
Slider(options, L + 2, -420, T("Splitter ab", "Shards below"), "shardMin", 0, 10, 1)

UI.Header(options, R, -32, T("Eigene Liste", "Own list"), 280)
UI.Hint(options, R + 4, -52, 280, T("Je Zeile: Name (oder Teil davon) oder Gegenstands-ID, optional mit Mindestanzahl. Beispiel:\nHeiltrank:3\nManatrank:2\nLeinenverband",
    "One per line: name (or part of it) or item ID, optionally with a minimum. Example:\nHealing Potion:3\nMana Potion:2\nLinen Bandage"))
local box = UI.Box(options, 0.5)
box:SetPoint("TOPLEFT", R + 4, -118)
box:SetSize(280, 120)
local edit = CreateFrame("EditBox", nil, box)
edit:SetMultiLine(true)
edit:SetAutoFocus(false)
edit:SetFontObject("ChatFontNormal")
edit:SetPoint("TOPLEFT", 6, -6)
edit:SetPoint("BOTTOMRIGHT", -6, 6)
edit:SetMaxLetters(800)
edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
edit:SetScript("OnEditFocusLost", function(self)
    GetDB().custom = self:GetText() or ""
    Refresh()
end)
box:EnableMouse(true)
box:SetScript("OnMouseDown", function() edit:SetFocus() end)
controls[#controls + 1] = function() edit:SetText(GetDB().custom or "") end

UI.Header(options, R, -258, T("Anzeige", "Display"), 280)
Check(options, R - 4, -280, T("Gasthaus/Hauptstadt: keine Buff-Hinweise", "Inns/capitals: no buff reminders"), "hideResting")
Check(options, R - 4, -304, T("Im Kampf ausblenden", "Hide in combat"), "hideInCombat")
Slider(options, R + 2, -332, T("Symbolgröße", "Icon size"), "iconSize", 14, 40, 1, { unit = " px" })
local lockCheck = Check(options, R - 4, -374, T("Leiste sperren (entsperrt: ziehen)", "Lock bar (unlocked: drag)"), "locked")
local testBtn = UI.Button(options, T("Beispiel zeigen", "Show example"), 130, function()
    testMode = not testMode
    Refresh()
end)
testBtn:SetPoint("TOPLEFT", R + 2, -406)
UI.Hint(options, R + 4, -436, 280, T("Die Leiste erscheint nur, wenn etwas fehlt. Kommt ein fehlender Buff im Kampf dazu, wird das Symbol grün mit Haken; nach dem Kampf wird neu geprüft.",
    "The bar only appears when something is missing. If a missing buff arrives in combat, its icon turns green with a check; everything is checked again after combat."))

options:SetScript("OnShow", function() for _, load in ipairs(controls) do load() end end)
options:SetScript("OnHide", function()
    if testMode then testMode = false Refresh() end
end)

local function ToggleOptions() options:SetShown(not options:IsShown()) end

-- Sperren/Entsperren (Optionen, Minimap-Rechtsklick, Rechtsklick auf den Anker, /fbuffs lock)
function ToggleLock()
    if InCombatLockdown() then Chat(T("Im Kampf nicht möglich.", "Not possible in combat.")) return end
    local d = GetDB()
    d.locked = not d.locked
    if lockCheck then lockCheck:SetChecked(d.locked) end
    dirty = true
    Update()
    Chat(d.locked and T("Leiste gesperrt.", "Bar locked.")
        or T("Leiste entsperrt – den blauen Anker ziehen, Rechtsklick sperrt wieder.", "Bar unlocked – drag the blue anchor, right-click locks it again."))
end

-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverBuffs", function() return GetDB().locked end, function(locked)
        GetDB().locked = locked
        if lockCheck then lockCheck:SetChecked(locked) end
        dirty = true
        Update()
    end)
end

---------------------------------------------------------------------------
-- Minimap-Knopf und Befehle
---------------------------------------------------------------------------
local mm = UI.MinimapButton({
    name = "ForeverBuffsMinimapButton",
    icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    title = "ForeverBuffs",
    angle = function() return GetDB().minimapAngle end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = function(_, button)
        if button == "RightButton" then ToggleLock() else ToggleOptions() end
    end,
    lines = function()
        return { T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Leiste sperren/entsperren", "Right-click: lock/unlock bar") }
    end,
})
events:HookScript("OnEvent", function(_, event) if event == "PLAYER_LOGIN" then mm.UpdatePosition() end end)

SLASH_FOREVERBUFFS1 = "/fbuffs"
SLASH_FOREVERBUFFS2 = "/foreverbuffs"
SlashCmdList["FOREVERBUFFS"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" or msg == "unlock" or msg == "move" then
        ToggleLock()
    elseif msg == "reset" then
        GetDB().pos = nil
        anchor:ClearAllPoints()
        anchor:SetPoint("TOP", 0, -57)
        Chat(T("Position zurückgesetzt.", "Position reset."))
    else
        ToggleOptions()
    end
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = "ForeverBuffs", sv = "ForeverBuffsDB", defaults = DEFAULTS, version = 1 })
