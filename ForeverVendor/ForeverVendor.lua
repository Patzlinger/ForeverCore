-- ForeverVendor: Haendler-Helfer. Beim Oeffnen eines Haendlers (Umschalt gedrueckt = diesmal nicht):
--  1. graue Gegenstaende verkaufen, 2. reparieren (wahlweise zuerst aus der Gildenkasse),
--  3. nachkaufen: Nachkauf-Liste (Klassen-Reagenzien + eigene Eintraege), bestes Essen/Trinken
--     fuer die Stufe, Munition (Jaeger). Mit Obergrenze pro Besuch und Gold-Ruecklage.
-- Im Alltag nur ein kleines Symbol: Klick klappt die Uebersicht auf, Rechtsklick oeffnet die Einstellungen.
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
local T = UI.T

---------------------------------------------------------------------------
-- Einstellungen (wegen des Beta-Bugs bei jedem Zugriff pruefen)
---------------------------------------------------------------------------
local GOLD = 10000 -- Kupfer pro Gold
local DEFAULTS = {
    enabled = false,         -- Automatik beim Haendler (standardmaessig aus: erst einschalten, dann passiert etwas)
    sellGrey = true,
    repair = true,
    guildRepair = false,     -- zuerst aus der Gildenkasse
    restock = true,
    askBuy = false,          -- an: nicht automatisch kaufen, nur per Knopf im Fenster am Haendler
    summary = true,          -- Zusammenfassung im Chat
    maxSpend = 1,            -- hoechstens so viel Gold pro Haendlerbesuch
    reserve = 0,             -- nie unter diesen Goldbetrag kaufen
    food = true, foodCount = 20,
    drink = true, drinkCount = 20,
    ammo = true, ammoCount = 1000,
    useBuffsList = false,    -- eigene Liste aus ForeverBuffs mitkaufen
    showIcon = false,        -- verschiebbares Symbol auf dem Bildschirm (optional; Fenster am Haendler + Minimap reichen)
    locked = true,
    iconSize = 22,
    gridShow = true, gridSize = 32, snap = true,
    minimapAngle = 100,
}

local _, myClass = UnitClass("player")

local function CopyEntry(e)
    return { id = e.id, name = e.name, count = e.count, minLevel = e.minLevel, group = e.group, auto = e.auto }
end

local function ClassList()
    local list = {}
    for _, e in ipairs(ns.CLASS_REAGENTS[myClass] or {}) do
        local c = CopyEntry(e)
        c.auto = true
        list[#list + 1] = c
    end
    return list
end

local db
local function GetDB()
    if type(_G.ForeverVendorDB) ~= "table" then _G.ForeverVendorDB = db or {} end
    db = _G.ForeverVendorDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    if type(db.list) ~= "table" then db.list = ClassList() end -- Nachkauf-Liste, vorbelegt nach Klasse
    return db
end

local function Chat(text) UI.Chat("ForeverVendor", text) end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
local function Money(copper)
    copper = math.max(0, math.floor(copper or 0))
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if f then
        local ok, s = pcall(f, copper)
        if ok and s then return s end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    return (g > 0 and (g .. "g ") or "") .. ((g > 0 or s > 0) and (s .. "s ") or "") .. c .. "c"
end

local function SpellName(id) return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) end

local function ItemInfo(id)
    if not (C_Item and C_Item.GetItemInfo) then return end
    return C_Item.GetItemInfo(id)
end

local function MinLevel(id)
    local _, _, _, _, minLevel = ItemInfo(id)
    return minLevel or 0
end

local function SellPrice(id)
    return select(11, ItemInfo(id)) or 0
end

local function ItemName(e)
    if e.id then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)
        if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, e.id) end
        return name or (T("Gegenstand ", "Item ") .. e.id)
    end
    return e.name or "?"
end

local function ItemIcon(e)
    if e.id and C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(e.id) or 134400 end
    return e.icon or 134400
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

-- Munitionsart passend zur Fernkampfwaffe: 2 = Pfeile (Bogen, Armbrust), 3 = Kugeln (Schusswaffe)
local function AmmoType()
    local id = GetInventoryItemID("player", 18)
    if not (id and C_Item and C_Item.GetItemInfoInstant) then return end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    if classID ~= 2 then return end
    if subID == 2 or subID == 18 then return 2 end
    if subID == 3 then return 3 end
end

local function IsAmmo(id, ammoType)
    if not (ammoType and C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    return classID == 6 and subID == ammoType
end

local function UsesMana() return (UnitPowerMax("player", 0) or 0) > 0 end

local function Level()
    local l = UnitLevel("player")
    return type(l) == "number" and l or 1
end

-- Taschen: alle belegten Plaetze
local function BagItems()
    local list = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return list end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                list[#list + 1] = { bag = bag, slot = slot, id = info.itemID, count = info.stackCount or 1,
                    quality = info.quality, noValue = info.hasNoValue, locked = info.isLocked,
                    name = info.itemName or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)) }
            end
        end
    end
    return list
end

local function NameMatches(name, key)
    return name and key and key ~= "" and name:lower():find(key:lower(), 1, true) ~= nil
end

---------------------------------------------------------------------------
-- Nachkauf-Liste: welche Eintraege gelten gerade?
---------------------------------------------------------------------------
-- Eintraege aus ForeverBuffs ("Name oder ID[:Anzahl]" je Zeile)
local function BuffsEntries()
    local out = {}
    local b = _G.ForeverBuffsDB
    if not (GetDB().useBuffsList and type(b) == "table" and type(b.custom) == "string") then return out end
    for line in b.custom:gmatch("[^\n,]+") do
        local entry, min = line:match("^%s*(.-)%s*:%s*(%d+)%s*$")
        entry = strtrim(entry or line)
        if entry ~= "" then
            local id = tonumber(entry)
            out[#out + 1] = { id = id, name = not id and entry or nil, count = tonumber(min) or 1, fromBuffs = true }
        end
    end
    return out
end

-- gilt der Eintrag fuer die aktuelle Stufe? (Gruppen: nur der hoechste erlaubte)
local function ActiveEntries()
    local level, d = Level(), GetDB()
    local best = {}
    for _, e in ipairs(d.list) do
        if e.group and (e.minLevel or 0) <= level then
            local cur = best[e.group]
            if not cur or (e.minLevel or 0) > (cur.minLevel or 0) then best[e.group] = e end
        end
    end
    local out = {}
    for _, e in ipairs(d.list) do
        if (e.count or 0) > 0 and (e.minLevel or 0) <= level and (not e.group or best[e.group] == e) then
            out[#out + 1] = e
        end
    end
    for _, e in ipairs(BuffsEntries()) do out[#out + 1] = e end
    return out
end

local function IsActive(e)
    for _, a in ipairs(ActiveEntries()) do if a == e then return true end end
    return false
end

local function EntryMatches(e, id, name)
    if e.id then return id == e.id end
    return NameMatches(name, e.name)
end

-- Anzahl in den Taschen. minLevel: nur Gegenstaende ab dieser Stufe zaehlen (Essen/Trinken/Munition)
local function CountWhere(test, bags)
    local n = 0
    for _, it in ipairs(bags or BagItems()) do
        if test(it.id, it.name) then n = n + it.count end
    end
    return n
end

local function CountEntry(e, bags)
    return CountWhere(function(id, name) return EntryMatches(e, id, name) end, bags)
end

---------------------------------------------------------------------------
-- Beim Haendler
---------------------------------------------------------------------------
local merchantOpen = false
local lastVisit -- Text der letzten Zusammenfassung

local function MerchantItems()
    local out = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local info
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            info = C_MerchantFrame.GetItemInfo(i)
        elseif GetMerchantItemInfo then
            local name, tex, price, qty, avail, purchasable, usable, ext = GetMerchantItemInfo(i)
            info = { name = name, texture = tex, price = price, stackCount = qty, numAvailable = avail,
                isPurchasable = purchasable, isUsable = usable, hasExtendedCost = ext }
        end
        if id and info and info.name and (info.price or 0) > 0 and not info.hasExtendedCost and info.isPurchasable ~= false then
            out[#out + 1] = { index = i, id = id, name = info.name, price = info.price,
                per = math.max(1, info.stackCount or 1), avail = info.numAvailable or -1,
                usable = info.isUsable ~= false, minLevel = MinLevel(id) }
        end
    end
    return out
end

-- bester passender Haendler-Gegenstand: benutzbar, hoechste Stufe, bei Gleichstand der teurere
local function BestMatch(items, test)
    local level, best = Level(), nil
    for _, m in ipairs(items) do
        if m.usable and m.minLevel <= level and test(m) then
            if not best or m.minLevel > best.minLevel
                or (m.minLevel == best.minLevel and m.price / m.per > best.price / best.per) then
                best = m
            end
        end
    end
    return best
end

-- Was soll gekauft werden? -> { { item, want, label }, ... } in dieser Reihenfolge (Wichtiges zuerst)
local function Plan(items, bags)
    local d, plan = GetDB(), {}
    for _, e in ipairs(ActiveEntries()) do
        local m = BestMatch(items, function(x) return EntryMatches(e, x.id, x.name) end)
        if m then
            local want = e.count - CountEntry(e, bags)
            if want > 0 then plan[#plan + 1] = { item = m, want = want } end
        end
    end
    for _, kind in ipairs({ "drink", "food" }) do
        if d[kind] and (kind == "food" or UsesMana()) then
            local m = BestMatch(items, function(x) return ItemKind(x.id) == kind end)
            if m then
                -- nur Essen/Trinken mitzaehlen, das mindestens so gut ist wie das beim Haendler
                local have = CountWhere(function(id) return ItemKind(id) == kind and MinLevel(id) >= m.minLevel end, bags)
                local want = d[kind .. "Count"] - have
                if want > 0 then plan[#plan + 1] = { item = m, want = want } end
            end
        end
    end
    if myClass == "HUNTER" and d.ammo then
        local ammoType = AmmoType()
        local m = ammoType and BestMatch(items, function(x) return IsAmmo(x.id, ammoType) end)
        if m then
            local have = CountWhere(function(id) return IsAmmo(id, ammoType) and MinLevel(id) >= m.minLevel end, bags)
            local want = d.ammoCount - have
            if want > 0 then plan[#plan + 1] = { item = m, want = want } end
        end
    end
    return plan
end

-- Was wird gekauft? (Grenzen schon beachtet) -> Liste { item, bundles, units, cost }, Gesamtpreis
local function Purchases(result)
    local d = GetDB()
    local plan = Plan(MerchantItems(), BagItems())
    local budget = math.floor((d.maxSpend or 0) * GOLD)
    local reserve = math.floor((d.reserve or 0) * GOLD)
    local spent, list = 0, {}
    for _, p in ipairs(plan) do
        local m = p.item
        local units = p.want
        if m.avail and m.avail >= 0 then units = math.min(units, m.avail * m.per) end
        local bundles = math.ceil(units / m.per)
        local money = GetMoney() - spent
        local afford = math.floor(math.min(budget - spent, money - reserve) / m.price)
        if afford < bundles then result.capped = true end
        bundles = math.max(0, math.min(bundles, afford))
        if bundles > 0 then
            list[#list + 1] = { item = m, bundles = bundles, units = bundles * m.per, cost = bundles * m.price }
            spent = spent + bundles * m.price
        end
    end
    return list, spent
end

local function BuyList(list, result)
    local spent = 0
    for _, b in ipairs(list) do
        local m = b.item
        if m.per > 1 then
            -- Gegenstaende im Buendel (z. B. 200 Pfeile): Buendel einzeln kaufen
            for _ = 1, math.min(b.bundles, 50) do BuyMerchantItem(m.index) end
        else
            local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(m.index)) or 20
            local left = b.bundles
            while left > 0 do
                local n = math.min(left, math.max(1, maxStack))
                BuyMerchantItem(m.index, n)
                left = left - n
            end
        end
        spent = spent + b.cost
        result.bought[#result.bought + 1] = string.format("%d× %s", b.units, m.name)
    end
    result.spent = spent
end

local function ListText(list)
    local parts = {}
    for _, b in ipairs(list) do parts[#parts + 1] = string.format("%d× %s", b.units, b.item.name) end
    return table.concat(parts, ", ")
end
local function SellJunk(result)
    local total, n = 0, 0
    local queue = {}
    for _, it in ipairs(BagItems()) do
        if it.quality == 0 and not it.noValue and not it.locked then
            local price = SellPrice(it.id)
            if price > 0 then
                total = total + price * it.count
                n = n + 1
                queue[#queue + 1] = it
            end
        end
    end
    if n == 0 then return end
    result.sold, result.soldValue = n, total
    -- Blizzards eigenes "Plunder verkaufen" (falls vorhanden), sonst einzeln mit kleiner Pause
    if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems and pcall(C_MerchantFrame.SellAllJunkItems) then return end
    for i, it in ipairs(queue) do
        C_Timer.After(i * 0.15, function()
            if merchantOpen and C_Container.UseContainerItem then C_Container.UseContainerItem(it.bag, it.slot) end
        end)
    end
end

local function Repair(result, then_)
    local d = GetDB()
    if not (d.repair and CanMerchantRepair and CanMerchantRepair()) then return then_() end
    local cost, can = GetRepairAllCost()
    if not can or (cost or 0) <= 0 then return then_() end
    if d.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
        RepairAllItems(true)
        -- Gildenkasse reicht evtl. nicht (Tageslimit): danach selbst zahlen
        C_Timer.After(0.4, function()
            local rest, still = GetRepairAllCost()
            if still and (rest or 0) > 0 and GetMoney() >= rest then
                RepairAllItems()
                result.repaired = rest
            end
            result.guild = true
            then_()
        end)
        return
    end
    if GetMoney() >= cost then
        RepairAllItems()
        result.repaired = cost
    else
        result.repairFailed = cost
    end
    then_()
end

local UpdateIcon -- weiter unten

local function Report(result)
    local parts = {}
    if result.sold then
        parts[#parts + 1] = string.format(T("Verkauft: %d× Graues (%s)", "Sold: %d× junk (%s)"), result.sold, Money(result.soldValue))
    end
    if result.repaired then
        parts[#parts + 1] = string.format(T("Repariert: %s", "Repaired: %s"), Money(result.repaired))
    elseif result.guild then
        parts[#parts + 1] = T("Repariert (Gildenkasse)", "Repaired (guild bank)")
    elseif result.repairFailed then
        parts[#parts + 1] = string.format(T("Reparatur: zu wenig Gold (%s)", "Repair: not enough gold (%s)"), Money(result.repairFailed))
    end
    if #result.bought > 0 then
        parts[#parts + 1] = string.format(T("Gekauft: %s (%s)", "Bought: %s (%s)"), table.concat(result.bought, ", "), Money(result.spent))
    end
    if result.capped then
        parts[#parts + 1] = T("Grenze erreicht – Rest nicht gekauft", "Limit reached – rest not bought")
    end
    if #parts == 0 then return end
    lastVisit = table.concat(parts, " · ")
    if GetDB().summary then Chat(lastVisit) end
end

local UpdateMerchantPanel -- weiter unten (Fenster am Haendler)

local function OnMerchant()
    local d = GetDB()
    -- Gegenstandsdaten des Haendlers anfordern (beim ersten Besuch evtl. noch nicht geladen)
    if C_Item and C_Item.RequestLoadItemDataByID and GetMerchantItemID then
        for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
            local id = GetMerchantItemID(i)
            if id then pcall(C_Item.RequestLoadItemDataByID, id) end
        end
    end
    if not d.enabled then return end
    if IsShiftKeyDown() then
        Chat(T("Umschalt gedrückt – diesmal nichts automatisch.", "Shift held – nothing automatic this time."))
        return
    end
    local result = { bought = {} }
    if d.sellGrey then SellJunk(result) end
    -- kurz warten: Verkauf bringt Gold, Haendlerliste ist dann sicher geladen
    C_Timer.After(0.3, function()
        if not merchantOpen then return end
        Repair(result, function()
            -- automatisch kaufen nur, wenn "Nachkaufen" an ist und nicht gefragt werden soll;
            -- sonst zeigt das Fenster am Haendler die Einkaufsliste mit "Kaufen"-Knopf
            if merchantOpen and d.restock and not d.askBuy then
                local ok, list = pcall(Purchases, result)
                if ok and list and #list > 0 then
                    BuyList(list, result)
                elseif ok then
                    -- Haendlerdaten evtl. noch nicht geladen: einmal etwas spaeter nochmal versuchen
                    C_Timer.After(1.5, function()
                        if not merchantOpen then return end
                        local r = { bought = {} }
                        local ok2, list2 = pcall(Purchases, r)
                        if ok2 and list2 and #list2 > 0 then
                            BuyList(list2, r)
                            C_Timer.After(0.6, function()
                                Report(r)
                                UpdateIcon()
                                UpdateMerchantPanel()
                            end)
                        end
                    end)
                elseif not ok then
                    local handler = geterrorhandler and geterrorhandler()
                    if handler then pcall(handler, list) end
                end
            end
            C_Timer.After(0.6, function()
                Report(result)
                if UpdateIcon then UpdateIcon() end
                if UpdateMerchantPanel then UpdateMerchantPanel() end
            end)
        end)
    end)
end

---------------------------------------------------------------------------
-- Fenster am Haendler: Erinnerung, was automatisch passiert, und die Einkaufsliste mit "Kaufen"
---------------------------------------------------------------------------
local mpanel = CreateFrame("Frame", "ForeverVendorMerchantPanel", UIParent, "BackdropTemplate")
UI.Hud(mpanel, 0.95)
mpanel:SetWidth(240)
mpanel:SetFrameStrata("HIGH")
mpanel:EnableMouse(true)
mpanel:Hide()
mpanel.title = mpanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mpanel.title:SetPoint("TOPLEFT", 10, -8)
mpanel.title:SetText("ForeverVendor")
mpanel.logo = mpanel:CreateTexture(nil, "OVERLAY")
mpanel.logo:SetTexture(UI.LOGO)
mpanel.logo:SetSize(14, 14)
mpanel.logo:SetPoint("TOPRIGHT", -8, -8)
mpanel.status = mpanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mpanel.status:SetPoint("TOPLEFT", 10, -28)
mpanel.status:SetWidth(220)
mpanel.status:SetJustifyH("LEFT")
mpanel.rows = {}
mpanel.info = UI.Hint(mpanel, 10, 0, 220, "")

local mpList = {} -- aktuelle Einkaufsliste
local autoToggle = UI.Button(mpanel, "", 108, function()
    local d = GetDB()
    d.enabled = not d.enabled
    UpdateIcon()
    UpdateMerchantPanel()
end)
local buyBtn = UI.Button(mpanel, T("Kaufen", "Buy"), 108, function()
    if not merchantOpen or #mpList == 0 then return end
    local r = { bought = {} }
    BuyList(mpList, r)
    C_Timer.After(0.6, function()
        Report(r)
        UpdateIcon()
        UpdateMerchantPanel()
    end)
end)
local optBtn = UI.Button(mpanel, T("Einstellungen", "Settings"), 220, function()
    local o = _G.ForeverVendorOptions
    if o then o:SetShown(not o:IsShown()) end
end)

local function OnOff(v) return v and ("|cff33ff33" .. T("an", "on") .. "|r") or ("|cff999999" .. T("aus", "off") .. "|r") end

function UpdateMerchantPanel()
    if not merchantOpen then mpanel:Hide() return end
    local d = GetDB()
    -- Erinnerung: was passiert automatisch?
    local restockMode = not d.restock and OnOff(false)
        or d.askBuy and ("|cffffd100" .. T("auf Knopfdruck", "on click") .. "|r") or OnOff(true)
    mpanel.status:SetText(string.format(T("Automatik: %s\nGraues verkaufen: %s · Reparieren: %s\nNachkaufen: %s",
        "Auto: %s\nSell junk: %s · Repair: %s\nRestock: %s"),
        OnOff(d.enabled), OnOff(d.sellGrey), OnOff(d.repair), restockMode))
    autoToggle:SetText(d.enabled and T("Automatik aus", "Auto off") or T("Automatik an", "Auto on"))

    -- Einkaufsliste (mit Grenzen pro Besuch und Ruecklage)
    local probe = { bought = {} }
    local ok, list, total = pcall(Purchases, probe)
    if not ok then list, total = {}, 0 end
    mpList = list
    for _, r in ipairs(mpanel.rows) do r:Hide() end
    local y = -28 - (mpanel.status:GetStringHeight() or 36) - 10
    local header = mpanel.rows[1] or mpanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mpanel.rows[1] = header
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 10, y)
    header:SetText(T("Einkaufsliste", "Shopping list"))
    header:Show()
    y = y - 16
    local shown = 0
    for i, b in ipairs(list) do
        if i > 8 then break end
        local r = mpanel.rows[i + 1]
        if not r then
            r = mpanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r:SetJustifyH("LEFT")
            r:SetWidth(220)
            r:SetWordWrap(false)
            mpanel.rows[i + 1] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 12, y)
        r:SetText(string.format("%d× %s  |cffbbbbbb%s|r", b.units, b.item.name, Money(b.cost)))
        r:Show()
        y = y - 14
        shown = shown + 1
    end
    local info
    if shown == 0 then
        info = T("Nichts nachzukaufen.", "Nothing to restock.")
    else
        info = string.format(T("Zusammen: %s", "Total: %s"), Money(total))
        if probe.capped then
            info = info .. "\n" .. string.format(T("Grenze: höchstens %g Gold pro Besuch", "Limit: at most %g gold per visit"), d.maxSpend or 0)
        end
    end
    if lastVisit then info = info .. "\n\n" .. T("Gerade: ", "Just now: ") .. lastVisit end
    mpanel.info:ClearAllPoints()
    mpanel.info:SetPoint("TOPLEFT", 10, y - 4)
    mpanel.info:SetText(info)
    y = y - 4 - (mpanel.info:GetStringHeight() or 12) - 10

    buyBtn:SetEnabled(shown > 0)
    autoToggle:ClearAllPoints()
    autoToggle:SetPoint("TOPLEFT", 10, y)
    buyBtn:ClearAllPoints()
    buyBtn:SetPoint("LEFT", autoToggle, "RIGHT", 4, 0)
    optBtn:ClearAllPoints()
    optBtn:SetPoint("TOPLEFT", autoToggle, "BOTTOMLEFT", 0, -4)
    mpanel:SetHeight(-y + 22 + 26 + 8)

    -- rechts neben dem Haendlerfenster (falls es das gibt)
    mpanel:ClearAllPoints()
    local mf = _G.MerchantFrame
    if mf and mf:IsShown() then
        mpanel:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, 0)
    else
        mpanel:SetPoint("LEFT", UIParent, "LEFT", 380, 80)
    end
    mpanel:Show()
end

---------------------------------------------------------------------------
-- Uebersicht (auch ohne Haendler): was fehlt gerade?
---------------------------------------------------------------------------
-- { { label, have, want }, ... }
local function Status()
    local d, out, bags = GetDB(), {}, BagItems()
    for _, e in ipairs(ActiveEntries()) do
        out[#out + 1] = { label = ItemName(e), have = CountEntry(e, bags), want = e.count, icon = ItemIcon(e) }
    end
    if d.drink and UsesMana() then
        out[#out + 1] = { label = T("Trinken", "Drink"), have = CountWhere(function(id) return ItemKind(id) == "drink" end, bags),
            want = d.drinkCount, icon = 132794 }
    end
    if d.food then
        out[#out + 1] = { label = T("Essen", "Food"), have = CountWhere(function(id) return ItemKind(id) == "food" end, bags),
            want = d.foodCount, icon = 133964 }
    end
    if myClass == "HUNTER" and d.ammo then
        local ammoType = AmmoType()
        if ammoType then
            out[#out + 1] = { label = T("Munition", "Ammo"), have = CountWhere(function(id) return IsAmmo(id, ammoType) end, bags),
                want = d.ammoCount, icon = GetInventoryItemTexture("player", 0) or 132382 }
        end
    end
    return out
end

local function AnyMissing(status)
    for _, s in ipairs(status or Status()) do
        if s.want > 0 and s.have < s.want then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Kleines Symbol (Anker) + ausklappbare Uebersicht
---------------------------------------------------------------------------
local icon = CreateFrame("Button", "ForeverVendorIcon", UIParent, "BackdropTemplate")
icon:SetSize(22, 22)
icon:SetPoint("CENTER", UIParent, "CENTER", 480, -300)
icon:SetMovable(true)
icon:SetClampedToScreen(true)
icon:SetFrameStrata("MEDIUM")
icon:RegisterForClicks("AnyUp")
icon:RegisterForDrag("LeftButton")
icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
icon:SetBackdropColor(0, 0, 0, 0.6)
icon:SetBackdropBorderColor(0, 0, 0, 1)
icon.tex = icon:CreateTexture(nil, "ARTWORK")
icon.tex:SetPoint("TOPLEFT", 1, -1)
icon.tex:SetPoint("BOTTOMRIGHT", -1, 1)
icon.tex:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
-- roter Punkt: beim naechsten Haendler wird etwas nachgekauft
icon.dot = icon:CreateTexture(nil, "OVERLAY")
icon.dot:SetSize(7, 7)
icon.dot:SetPoint("TOPRIGHT", 2, 2)
icon.dot:SetColorTexture(1, 0.25, 0.2, 1)
icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
icon.label:SetPoint("BOTTOM", icon, "TOP", 0, 3)
icon.label:SetText(T("ForeverVendor – ziehen", "ForeverVendor – drag"))
UI.AddMover(icon)

local panel = CreateFrame("Frame", "ForeverVendorPanel", UIParent, "BackdropTemplate")
UI.Hud(panel, 0.92)
panel:SetFrameStrata("DIALOG")
panel:SetClampedToScreen(true)
panel:SetWidth(230)
panel:Hide()
tinsert(UISpecialFrames, "ForeverVendorPanel") -- Escape schliesst
panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 8, -7)
panel.title:SetText("ForeverVendor")
panel.state = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.state:SetPoint("TOPRIGHT", -8, -9)
panel.rows = {}
panel.last = UI.Hint(panel, 8, 0, 214, "")

local ToggleOptions, ToggleLock -- weiter unten
local autoBtn = UI.Button(panel, "", 104, function()
    local d = GetDB()
    d.enabled = not d.enabled
    UpdateIcon()
end)
local optBtn = UI.Button(panel, T("Einstellungen", "Settings"), 104, function()
    panel:Hide()
    ToggleOptions()
end)

local function FillPanel()
    local d = GetDB()
    panel.state:SetText(d.enabled and ("|cff33ff33" .. T("Automatik an", "Auto on") .. "|r")
        or ("|cff999999" .. T("Automatik aus", "Auto off") .. "|r"))
    autoBtn:SetText(d.enabled and T("Automatik aus", "Turn auto off") or T("Automatik an", "Turn auto on"))
    local status = Status()
    for _, r in ipairs(panel.rows) do r:Hide() end
    local y = -28
    if #status == 0 then
        local r = panel.rows[1] or panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        panel.rows[1] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, y)
        r:SetText(T("Nichts zum Nachkaufen eingestellt.", "Nothing set up to restock."))
        r:Show()
        y = y - 16
    end
    for i, s in ipairs(status) do
        local r = panel.rows[i]
        if not r then
            r = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r:SetJustifyH("LEFT")
            r:SetWidth(212)
            r:SetWordWrap(false)
            panel.rows[i] = r
        end
        local color = s.have >= s.want and "|cff88ff88" or "|cffff6666"
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 10, y)
        r:SetText(string.format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s  %s%d/%d|r", tostring(s.icon or 134400), s.label, color, s.have, s.want))
        r:Show()
        y = y - 16
    end
    panel.last:ClearAllPoints()
    panel.last:SetPoint("TOPLEFT", 8, y - 6)
    panel.last:SetText(lastVisit and (T("Letzter Händler: ", "Last merchant: ") .. lastVisit)
        or T("Klick: auf/zu · Rechtsklick: Einstellungen · Umschalt-Klick: Automatik an/aus",
            "Click: open/close · Right-click: settings · Shift-click: auto on/off"))
    local lastH = panel.last:GetStringHeight() or 12
    y = y - 6 - lastH - 8
    autoBtn:ClearAllPoints()
    autoBtn:SetPoint("TOPLEFT", 8, y)
    optBtn:ClearAllPoints()
    optBtn:SetPoint("LEFT", autoBtn, "RIGHT", 6, 0)
    panel:SetHeight(-y + 30)
end

local function TogglePanel()
    if panel:IsShown() then panel:Hide() return end
    FillPanel()
    panel:ClearAllPoints()
    -- je nach Lage des Symbols nach oben/unten und links/rechts aufklappen
    local x, y = icon:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local v = (y and y > h / 2) and "TOP" or "BOTTOM"
    local hz = (x and x > w / 2) and "RIGHT" or "LEFT"
    local other = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
    panel:SetPoint(v .. hz, icon, other[v] .. hz, 0, v == "TOP" and -4 or 4)
    panel:Show()
end

-- Position: Mitte des Symbols relativ zur Bildschirmmitte
local function RestorePosition()
    local pos = GetDB().pos
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", UIParent, "CENTER", pos and pos[1] or 480, pos and pos[2] or -300)
end

local OnMoved -- Einstellungsfenster: X/Y nachziehen
local function SetPosition(x, y)
    GetDB().pos = { UI.Round(x), UI.Round(y) }
    RestorePosition()
    if OnMoved then OnMoved() end
end

-- Raster nur entsperrt und nur beim Ziehen oder bei offenen Einstellungen
local dragging = false
local function UpdateGrid()
    local d = GetDB()
    local opts = _G.ForeverVendorOptions
    local want = d.gridShow and not d.locked and (dragging or (opts and opts:IsShown()))
    UI.Grid("ForeverVendor", want and d.gridSize or nil)
end

function UpdateIcon()
    local d = GetDB()
    icon:SetSize(d.iconSize, d.iconSize)
    icon:SetShown(d.showIcon and true or false) -- optional; ausgeschaltet auch beim Entsperren nicht zeigen
    icon.tex:SetDesaturated(not d.enabled)
    icon:SetAlpha((icon:IsMouseOver() or not d.locked) and 1 or 0.75)
    icon:SetBackdropBorderColor(d.locked and 0 or 0.3, d.locked and 0 or 0.6, d.locked and 0 or 1, 1)
    icon.label:SetShown(not d.locked)
    icon.dot:SetShown(d.enabled and d.restock and AnyMissing())
    if panel:IsShown() then FillPanel() end
end

icon:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        panel:Hide()
        ToggleOptions()
    elseif IsShiftKeyDown() then
        local d = GetDB()
        d.enabled = not d.enabled
        Chat(d.enabled and T("Automatik an.", "Auto on.") or T("Automatik aus.", "Auto off."))
        UpdateIcon()
    else
        TogglePanel()
    end
end)
icon:SetScript("OnDragStart", function(self)
    local d = GetDB()
    if d.locked or InCombatLockdown() then return end
    panel:Hide()
    self:StartMoving()
    dragging = true
    UpdateGrid()
    UI.BeginDrag(self, { snap = d.snap, grid = d.gridShow and d.gridSize or nil })
end)
icon:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local dx, dy = UI.EndDrag()
    dragging = false
    UpdateGrid()
    local x, y = UI.CenterOffset(self)
    SetPosition(x + dx, y + dy)
end)
icon:SetScript("OnEnter", function(self)
    UpdateIcon()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ForeverVendor")
    local d = GetDB()
    GameTooltip:AddLine(d.enabled and T("Automatik beim Händler: an", "Auto at merchants: on")
        or T("Automatik beim Händler: aus", "Auto at merchants: off"), 1, 1, 1)
    if self.dot:IsShown() then
        GameTooltip:AddLine(T("Beim nächsten Händler wird nachgekauft.", "Will restock at the next merchant."), 1, 0.4, 0.4)
    end
    GameTooltip:AddLine(T("Klick: Übersicht · Rechtsklick: Einstellungen", "Click: overview · Right-click: settings"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(T("Umschalt-Klick: Automatik an/aus", "Shift-click: auto on/off"), 0.7, 0.7, 0.7)
    if not d.locked then GameTooltip:AddLine(T("Entsperrt: ziehen zum Verschieben", "Unlocked: drag to move"), 0.4, 0.7, 1) end
    GameTooltip:Show()
end)
icon:SetScript("OnLeave", function()
    GameTooltip:Hide()
    UpdateIcon()
end)

---------------------------------------------------------------------------
-- Einstellungsfenster
---------------------------------------------------------------------------
local RefreshList
do
-- 720 breit: die deutschen Beschriftungen links sind laenger und brauchen ~370 px bis zur rechten Spalte
local options = UI.Window("ForeverVendorOptions", T("ForeverVendor – Einstellungen", "ForeverVendor – Settings"), 720, 690)
local controls = {}
local function Changed() UpdateIcon() end

local function Check(x, y, label, key)
    local cb = UI.Check(options, x, y, label, function(checked)
        GetDB()[key] = checked
        Changed()
        UpdateGrid()
    end)
    controls[#controls + 1] = function() cb:SetChecked(GetDB()[key] and true or false) end
    return cb
end
local function Slider(x, y, label, key, minV, maxV, step, opts)
    local s = UI.Slider(options, x, y, label, minV, maxV, step, function(v)
        GetDB()[key] = v
        Changed()
    end, opts)
    controls[#controls + 1] = function() s:Load(GetDB()[key]) end
end
local goldFormat = { width = 150, format = function(v) return string.format(T("%g Gold", "%g gold"), v) end }

local L, R = 18, 398
local LW = R - L - 30 -- Breite der linken Abschnitte
-- linke Spalte: Verhalten
UI.Header(options, L, -32, T("Beim Händler", "At the merchant"), LW)
Check(L - 4, -54, T("Automatisch (Umschalt beim Öffnen = diesmal nicht)", "Automatic (Shift when opening = skip once)"), "enabled")
Check(L - 4, -78, T("Graue Gegenstände verkaufen", "Sell grey items"), "sellGrey")
Check(L - 4, -102, T("Reparieren", "Repair"), "repair")
Check(L + 16, -126, T("zuerst aus der Gildenkasse", "use guild bank first"), "guildRepair")
Check(L - 4, -150, T("Nachkaufen (Liste, Essen, Trinken, Munition)", "Restock (list, food, drink, ammo)"), "restock")
Check(L + 16, -174, T("nicht automatisch – nur per Knopf am Händler", "not automatic – only via button at the merchant"), "askBuy")
Check(L - 4, -198, T("Zusammenfassung im Chat", "Summary in chat"), "summary")

UI.Header(options, L, -240, T("Grenzen beim Nachkaufen", "Restock limits"), LW)
Slider(L + 2, -264, T("Höchstens pro Händlerbesuch", "At most per merchant visit"), "maxSpend", 0, 20, 0.5, goldFormat)
Slider(L + 2, -304, T("Gold-Rücklage (nie darunter)", "Gold reserve (never below)"), "reserve", 0, 100, 1, goldFormat)

UI.Header(options, L, -362, T("Essen und Trinken (bestes für deine Stufe)", "Food and drink (best for your level)"), LW)
Check(L - 4, -384, T("Essen", "Food"), "food")
Slider(L + 120, -384, T("Menge", "Amount"), "foodCount", 0, 80, 5, { width = 100 })
Check(L - 4, -426, T("Trinken", "Drink"), "drink")
Slider(L + 120, -426, T("Menge", "Amount"), "drinkCount", 0, 80, 5, { width = 100 })

UI.Header(options, L, -486, T("Munition (Jäger)", "Ammo (hunter)"), LW)
Check(L - 4, -508, T("Passend zur Waffe nachkaufen", "Restock to match your weapon"), "ammo")
Slider(L + 2, -538, T("Menge", "Amount"), "ammoCount", 200, 3000, 200, { width = 150 })

UI.Header(options, L, -598, T("Anzeige", "Display"), LW)
Check(L - 4, -620, T("Verschiebbares Symbol anzeigen (optional)", "Show movable icon (optional)"), "showIcon")
local lockCheck = Check(L - 4, -644, T("Symbol sperren (entsperrt: ziehen)", "Lock icon (unlocked: drag)"), "locked")

-- rechte Spalte: Nachkauf-Liste
UI.Header(options, R, -32, T("Nachkauf-Liste", "Restock list"), 300)
local listBox = UI.Box(options, 0.35)
listBox:SetPoint("TOPLEFT", R - 2, -56)
listBox:SetSize(296, 236)
local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, listBox, "UIPanelScrollFrameTemplate")
if not okScroll then scroll = CreateFrame("ScrollFrame", nil, listBox, "ScrollFrameTemplate") end
scroll:SetPoint("TOPLEFT", 4, -4)
scroll:SetPoint("BOTTOMRIGHT", -26, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(266, 10)
scroll:SetScrollChild(content)

local ROW_H = 26
local rows = {}
local function RemoveEntry(e)
    local list = GetDB().list
    for i, x in ipairs(list) do
        if x == e then table.remove(list, i) break end
    end
    RefreshList()
    UpdateIcon()
end

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, content)
    r:SetSize(266, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:EnableMouse(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.name:SetWidth(102)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.num = UI.Number(r, 122, -2, "", function() return r.entry and r.entry.count or 0 end, function(v)
        if r.entry then
            r.entry.count = math.max(0, math.floor(v))
            UpdateIcon()
        end
    end)
    r.del = UI.Button(r, "×", 22, function() if r.entry then RemoveEntry(r.entry) end end)
    r.del:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if e.id and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(e.id)
        else
            GameTooltip:AddLine(ItemName(e))
            GameTooltip:AddLine(T("Passt auf jeden Gegenstand, dessen Name das enthält.", "Matches any item whose name contains this."), 1, 1, 1, true)
        end
        if e.minLevel and e.minLevel > 0 then
            GameTooltip:AddLine(string.format(T("Gekauft ab Stufe %d.", "Bought from level %d."), e.minLevel), 0.7, 0.7, 0.7)
        end
        if e.group then
            GameTooltip:AddLine(T("Aus dieser Gruppe nur die Sorte für deine Stufe.", "From this group only the kind for your level."), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local emptyHint = UI.Hint(content, 6, -8, 250, T("Noch leer – unten Gegenstände hinzufügen.", "Empty – add items below."))

function RefreshList()
    local list = GetDB().list
    for _, r in ipairs(rows) do r:Hide() r.entry = nil end
    for i, e in ipairs(list) do
        local r = Row(i)
        r.entry = e
        r.icon:SetTexture(ItemIcon(e))
        local name = ItemName(e)
        if e.minLevel and e.minLevel > Level() then
            name = "|cff888888" .. name .. "|r"
        elseif not IsActive(e) then
            name = "|cff888888" .. name .. "|r"
        end
        r.name:SetText(name)
        r.num:Load()
        r:Show()
    end
    emptyHint:SetShown(#list == 0)
    content:SetHeight(math.max(10, #list * ROW_H))
end

-- Hinzufuegen: Name, ID, Gegenstands-Link; mehrere je Zeile oder mit Komma; Anzahl mit ":"
local function AddEntry(id, name, count)
    local list = GetDB().list
    for _, e in ipairs(list) do
        if (id and e.id == id) or (not id and e.name and name and e.name:lower() == name:lower()) then
            e.count = count or e.count
            return
        end
    end
    list[#list + 1] = { id = id, name = (not id) and name or nil, count = count or 5 }
end

local function AddFromText(text)
    local n = 0
    for token in (text or ""):gmatch("[^\n,;]+") do
        local id = tonumber(token:match("|Hitem:(%d+)"))
        local count
        if id then
            count = tonumber(token:match("|h|r%s*:%s*(%d+)") or token:match("%]|h%s*:%s*(%d+)"))
            AddEntry(id, nil, count)
            n = n + 1
        else
            local entry, c = token:match("^%s*(.-)%s*:%s*(%d+)%s*$")
            entry = strtrim(entry or token)
            count = tonumber(c)
            if entry ~= "" then
                if tonumber(entry) then AddEntry(tonumber(entry), nil, count) else AddEntry(nil, entry, count) end
                n = n + 1
            end
        end
    end
    return n
end

local addBox = UI.Box(options, 0.5)
addBox:SetPoint("TOPLEFT", R - 2, -300)
addBox:SetSize(258, 46)
local addEdit = CreateFrame("EditBox", nil, addBox)
addEdit:SetMultiLine(true)
addEdit:SetAutoFocus(false)
addEdit:SetFontObject("ChatFontNormal")
addEdit:SetPoint("TOPLEFT", 6, -5)
addEdit:SetPoint("BOTTOMRIGHT", -6, 5)
addEdit:SetMaxLetters(1000)
addEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
addBox:EnableMouse(true)
addBox:SetScript("OnMouseDown", function() addEdit:SetFocus() end)

local function AddNow()
    local kind, id = GetCursorInfo()
    local n = 0
    if kind == "item" and id then
        AddEntry(id, nil, nil)
        ClearCursor()
        n = 1
    else
        n = AddFromText(addEdit:GetText())
        addEdit:SetText("")
        addEdit:ClearFocus()
    end
    if n > 0 then
        RefreshList()
        UpdateIcon()
        C_Timer.After(0, function() scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end)
    end
end
local plus = UI.Button(options, "+", 34, AddNow)
plus:SetHeight(46)
plus:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
-- Gegenstand aus der Tasche auf "+" oder ins Feld ziehen
for _, f in ipairs({ plus, addBox, addEdit }) do
    f:SetScript("OnReceiveDrag", AddNow)
end
plus:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(T("Hinzufügen", "Add"))
    GameTooltip:AddLine(T("Fügt die Einträge aus dem Feld hinzu – oder einen Gegenstand, den du hierher ziehst.",
        "Adds the entries from the field – or an item you drag here."), 1, 1, 1, true)
    GameTooltip:Show()
end)
plus:SetScript("OnLeave", GameTooltip_Hide)
addEdit:SetScript("OnEnterPressed", function(self)
    if IsShiftKeyDown() then self:Insert("\n") else AddNow() end
end)

-- Umschalt-Klick auf einen Gegenstand fuegt dessen Link ins Feld ein (wie in den Chat)
local lastLink, lastLinkTime
local function InsertLink(link)
    if not (addEdit:HasFocus() and type(link) == "string") then return end
    local now = GetTime()
    if link == lastLink and lastLinkTime == now then return end -- nicht doppelt (zwei Haken)
    lastLink, lastLinkTime = link, now
    addEdit:Insert(link)
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLink) end

UI.Hint(options, R + 2, -352, 296, T("Name (oder Teil davon), Gegenstands-ID oder Link (Umschalt-Klick auf einen Gegenstand). " ..
    "Mehrere je Zeile oder mit Komma, Menge mit Doppelpunkt: Heiltrank:5. Oder einen Gegenstand auf + ziehen. " ..
    "Grau = gilt erst ab höherer Stufe.",
    "Name (or part of it), item ID or link (shift-click an item). One per line or comma-separated, amount after a colon: " ..
    "Healing Potion:5. Or drag an item onto +. Grey = only applies at a higher level."))

Check(R - 4, -420, T("Auch die eigene Liste aus ForeverBuffs nachkaufen", "Also restock the own list from ForeverBuffs"), "useBuffsList")
local resetList = UI.Button(options, T("Klassen-Vorschläge wiederherstellen", "Restore class suggestions"), 240, function()
    for _, e in ipairs(ClassList()) do
        local found = false
        for _, x in ipairs(GetDB().list) do if x.id == e.id then found = true end end
        if not found then table.insert(GetDB().list, e) end
    end
    RefreshList()
    UpdateIcon()
end)
resetList:SetPoint("TOPLEFT", R + 2, -450)

UI.Header(options, R, -500, T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)"), 300)
local function PosGet(i) return function() return select(i, UI.CenterOffset(icon)) end end
local function PosSet(i)
    return function(v)
        local x, y = UI.CenterOffset(icon)
        if i == 1 then x = v else y = v end
        SetPosition(x, y)
    end
end
local posX = UI.Number(options, R + 2, -524, "X", PosGet(1), PosSet(1))
local posY = UI.Number(options, R + 148, -524, "Y", PosGet(2), PosSet(2))
Check(R - 4, -554, T("Raster beim Ziehen und hier", "Grid while dragging and here"), "gridShow")
Check(R - 4, -578, T("Einrasten (Umschalt = aus)", "Snap (Shift = off)"), "snap")
OnMoved = function()
    if options:IsShown() then posX:Load() posY:Load() end
end

options:SetScript("OnShow", function()
    for _, load in ipairs(controls) do load() end
    posX:Load()
    posY:Load()
    RefreshList()
    UpdateGrid()
end)
options:SetScript("OnHide", function() UpdateGrid() end)

-- Gegenstandsnamen kommen evtl. erst spaeter vom Server
local pendingRefresh = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function()
    if not options:IsShown() or pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0.3, function()
        pendingRefresh = false
        if options:IsShown() then RefreshList() end
    end)
end)

function ToggleOptions() options:SetShown(not options:IsShown()) end

function ToggleLock(silent)
    if InCombatLockdown() then Chat(T("Im Kampf nicht möglich.", "Not possible in combat.")) return end
    local d = GetDB()
    if not d.showIcon then
        if not silent then
            Chat(T("Das verschiebbare Symbol ist aus – einschalten unter Einstellungen » Anzeige.",
                "The movable icon is off – turn it on under Settings » Display."))
        end
        return
    end
    d.locked = not d.locked
    lockCheck:SetChecked(d.locked)
    UpdateIcon()
    UpdateGrid()
    if not silent then
        Chat(d.locked and T("Symbol gesperrt.", "Icon locked.")
            or T("Symbol entsperrt – zum Verschieben ziehen.", "Icon unlocked – drag to move."))
    end
end

-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverVendor", function() return GetDB().locked or not GetDB().showIcon end, function(locked)
        if not GetDB().showIcon then return end -- ohne Symbol gibt es nichts zu verschieben
        if GetDB().locked ~= locked then ToggleLock(true) end
    end)
end
end -- Ende Block "Einstellungsfenster"

---------------------------------------------------------------------------
-- Minimap-Knopf und Befehle
---------------------------------------------------------------------------
local mm = UI.MinimapButton({
    name = "ForeverVendorMinimapButton",
    icon = "Interface\\Icons\\INV_Misc_Bag_08",
    title = "ForeverVendor",
    angle = function() return GetDB().minimapAngle end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = function(_, button)
        if button == "RightButton" then ToggleLock() else ToggleOptions() end
    end,
    lines = function()
        return { T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Symbol sperren/entsperren", "Right-click: lock/unlock icon") }
    end,
})

SLASH_FOREVERVENDOR1 = "/fvendor"
SLASH_FOREVERVENDOR2 = "/forevervendor"
SlashCmdList["FOREVERVENDOR"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" or msg == "unlock" or msg == "move" then
        ToggleLock()
    elseif msg == "auto" then
        local d = GetDB()
        d.enabled = not d.enabled
        Chat(d.enabled and T("Automatik an.", "Auto on.") or T("Automatik aus.", "Auto off."))
        UpdateIcon()
    elseif msg == "reset" then
        GetDB().pos = nil
        RestorePosition()
        Chat(T("Position zurückgesetzt.", "Position reset."))
    else
        ToggleOptions()
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED",
    "PLAYER_LEVEL_UP", "UNIT_INVENTORY_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
end
local iconPending = false
local function SoonUpdateIcon()
    if iconPending then return end
    iconPending = true
    C_Timer.After(0.5, function()
        iconPending = false
        local ok, err = pcall(UpdateIcon)
        if ok and merchantOpen then ok, err = pcall(UpdateMerchantPanel) end
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then pcall(handler, err) end
        end
    end)
end
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        RestorePosition()
        mm.UpdatePosition()
        SoonUpdateIcon()
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        -- Fenster am Haendler (auch bei ausgeschalteter Automatik); Haendlerliste kurz nachladen lassen
        C_Timer.After(0.35, function() if merchantOpen then pcall(UpdateMerchantPanel) end end)
        local ok, err = pcall(OnMerchant)
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then pcall(handler, err) end
        end
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        mpanel:Hide()
        SoonUpdateIcon()
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then SoonUpdateIcon() end
    else
        SoonUpdateIcon()
    end
end)

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = "ForeverVendor", sv = "ForeverVendorDB", defaults = DEFAULTS, version = 1 })
