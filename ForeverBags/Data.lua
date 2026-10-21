local addonName, ns = ...

-- Data.lua: Taschen, Bank und Gold JEDES Charakters, der einmal eingeloggt war – kontoweit gespeichert in
-- ForeverBagsData (eigene SavedVariable, NICHT über die Profil-Verwaltung: das sind Charakter-Daten, keine
-- Einstellungen, siehe CLAUDE.md Abschnitt 9). So sieht man auf jedem Charakter, was die anderen dabeihaben.
--
-- Aufbau: ForeverBagsData.chars["Name-Realm"] = {
--     name, realm, class, faction, money, updated (Zeit), bankUpdated,
--     bags = { [Tasche] = { size = n, [Platz] = { link, count, icon, quality } } },
--     bank = { … wie bags … },   -- erst nach dem ersten Besuch der Bank vorhanden
-- }

local function DB()
    if type(ForeverBagsData) ~= "table" then ForeverBagsData = {} end
    if type(ForeverBagsData.chars) ~= "table" then ForeverBagsData.chars = {} end
    return ForeverBagsData
end

function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Daten des eingeloggten Charakters (wird angelegt)
local function Me()
    local chars = DB().chars
    local key = ns.CharKey()
    local c = chars[key]
    if type(c) ~= "table" then c = {} chars[key] = c end
    c.name = UnitName("player")
    c.realm = GetRealmName()
    local _, class = UnitClass("player")
    c.class = class
    c.faction = UnitFactionGroup("player")
    return c
end

-- Taschen-Nummern: Rucksack, Taschen, Reagenzientasche
function ns.BagIDs()
    local list = { 0, 1, 2, 3, 4 }
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagent then list[#list + 1] = reagent end
    return list
end

-- Bank: neuere Blizzard-Bank mit Bankfächern (CharacterBankTab_1 …) – genau die GEKAUFTEN Fächer, wie Blizzards
-- Bankfenster (C_Bank.FetchPurchasedBankTabData); nicht gekaufte Fächer melden trotzdem eine Größe. Achtung: in diesem
-- Client ist -1 der Schlüsselbund, nicht das Bankfach – es kommt nur dazu, wenn es Enum.BagIndex.Bank gibt.
-- Sonst die klassische Bank (Bankfach -1, Bank-Taschen) und Reagenzienbank. Leere Nummern stören nicht.
function ns.BankIDs()
    local bi = Enum and Enum.BagIndex or {}
    local list = {}
    if bi.CharacterBankTab_1 then
        local tabs
        if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
            local ok, data = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
            if ok and type(data) == "table" then tabs = data end
        end
        if tabs then
            -- zusätzlich nach der gemeldeten ANZAHL gekaufter Fächer begrenzen (der Forever-Client lieferte zeitweise
            -- auch nicht gekaufte Fächer mit)
            local bought
            if C_Bank.FetchNumPurchasedBankTabs then
                local ok, n = pcall(C_Bank.FetchNumPurchasedBankTabs, Enum.BankType.Character)
                if ok and type(n) == "number" then bought = n end
            end
            for _, tab in ipairs(tabs) do
                if type(tab) == "table" and tab.ID and (not bought or #list < bought) then list[#list + 1] = tab.ID end
            end
        else
            -- ohne Abfrage: nur das erste Fach (das hat jeder)
            list[#list + 1] = bi.CharacterBankTab_1
        end
        if bi.Bank then list[#list + 1] = bi.Bank end
        if bi.Reagentbank then list[#list + 1] = bi.Reagentbank end
        return list
    end
    list[#list + 1] = bi.Bank or -1
    do
        -- nur die GEKAUFTEN Bank-Taschenplätze (GetNumBankSlots); nicht gekaufte melden im Forever-Client teils eine Größe
        local first = bi.BankBag_1 or ((NUM_BAG_SLOTS or 4) + 1)
        local count = NUM_BANKBAGSLOTS or 7
        if GetNumBankSlots then
            local ok, n = pcall(GetNumBankSlots)
            if ok and type(n) == "number" then count = math.min(count, n) end
        end
        for i = 0, count - 1 do list[#list + 1] = first + i end
    end
    if bi.Reagentbank then list[#list + 1] = bi.Reagentbank end
    return list
end

-- Inhalt lesen; Rückgabe: Tabelle, Anzahl Plätze. Fehlt der Link noch (Gegenstand noch nicht geladen), reicht die
-- Gegenstands-Nummer – der Tooltip holt sich den Rest später selbst.
local function ReadContainers(ids)
    local out, slots = {}, 0
    for _, bag in ipairs(ids) do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        if size > 0 then
            local entry = { size = size }
            for slot = 1, size do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local link = info and (info.hyperlink or (info.itemID and ("item:" .. info.itemID)))
                if link then
                    entry[slot] = { link, info.stackCount or 1, info.iconFileID, info.quality }
                end
            end
            out[bag] = entry
            slots = slots + size
        end
    end
    return out, slots
end

-- Nie mit einem leeren Stand überschreiben: beim Ein- und Ausloggen liefert das Spiel kurz gar keine Taschen
function ns.SaveBags()
    local data, slots = ReadContainers(ns.BagIDs())
    local c = Me()
    c.money = GetMoney()
    if slots == 0 then return end
    c.bags = data
    c.updated = time()
    ns.dataVersion = (ns.dataVersion or 0) + 1 -- Tooltip-Zählung neu aufbauen (Tooltip.lua)
end

local bankOpen = false
function ns.SaveBank()
    if not bankOpen then return end
    local data, slots = ReadContainers(ns.BankIDs())
    if slots == 0 then return end
    local c = Me()
    c.bank = data
    c.bankUpdated = time()
    ns.dataVersion = (ns.dataVersion or 0) + 1
end

function ns.SaveMoney()
    Me().money = GetMoney()
end

-- Alle gespeicherten Charaktere (eigener zuerst, dann nach Name), nur derselbe Realm-Name zuerst
function ns.Characters()
    local list = {}
    for key, c in pairs(DB().chars) do
        if type(c) == "table" then list[#list + 1] = { key = key, data = c } end
    end
    local me = ns.CharKey()
    table.sort(list, function(a, b)
        if a.key == me then return true end
        if b.key == me then return false end
        return a.key < b.key
    end)
    return list
end

function ns.CharacterData(key)
    return DB().chars[key]
end

-- Farbiger Name eines gespeicherten Charakters (Klassenfarbe)
function ns.ColoredName(c)
    local color = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local name = c.name or "?"
    if color then return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name) end
    return name
end

function ns.ForgetCharacter(key)
    if key ~= ns.CharKey() then DB().chars[key] = nil end
end

---------------------------------------------------------------------------
-- Ereignisse: Taschen bei jeder Änderung (gesammelt), Bank solange sie offen ist
---------------------------------------------------------------------------
local queued = false
local function QueueSave()
    if queued then return end
    queued = true
    C_Timer.After(1, function()
        queued = false
        ns.SaveBags()
        ns.SaveBank()
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED", "BAG_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
-- (kein Speichern beim Ausloggen: dann sind die Taschen evtl. schon leer – gespeichert wird bei jeder Änderung)
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- die Taschen sind beim Login oft noch nicht geladen: ein paar Sekunden später lesen (zweimal zur Sicherheit)
        C_Timer.After(3, ns.SaveBags)
        C_Timer.After(10, ns.SaveBags)
    elseif event == "PLAYER_MONEY" then
        ns.SaveMoney()
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        C_Timer.After(0.5, ns.SaveBank)
        C_Timer.After(2, ns.SaveBank) -- Bankfächer laden manchmal etwas später
    elseif event == "BANKFRAME_CLOSED" then
        -- nicht mehr speichern: nach dem Schließen ist die Bank evtl. schon nicht mehr lesbar (wäre dann leer)
        bankOpen = false
    else
        QueueSave()
    end
end)
