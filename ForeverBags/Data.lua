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

-- Bank: Bankfach, Bank-Taschen (und Reagenzienbank, falls es sie gibt)
function ns.BankIDs()
    local bi = Enum and Enum.BagIndex or {}
    local list = { bi.Bank or -1 }
    local first = bi.BankBag_1 or ((NUM_BAG_SLOTS or 4) + 1)
    for i = 0, (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = first + i end
    if bi.Reagentbank then list[#list + 1] = bi.Reagentbank end
    return list
end

local function ReadContainers(ids)
    local out = {}
    for _, bag in ipairs(ids) do
        local size = C_Container.GetContainerNumSlots(bag) or 0
        if size > 0 then
            local entry = { size = size }
            for slot = 1, size do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.hyperlink then
                    entry[slot] = { info.hyperlink, info.stackCount or 1, info.iconFileID, info.quality }
                end
            end
            out[bag] = entry
        end
    end
    return out
end

function ns.SaveBags()
    local c = Me()
    c.bags = ReadContainers(ns.BagIDs())
    c.money = GetMoney()
    c.updated = time()
end

local bankOpen = false
function ns.SaveBank()
    if not bankOpen then return end
    local c = Me()
    c.bank = ReadContainers(ns.BankIDs())
    c.bankUpdated = time()
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
    "PLAYERBANKSLOTS_CHANGED", "PLAYER_LOGOUT" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.SaveBags()
    elseif event == "PLAYER_MONEY" then
        ns.SaveMoney()
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        C_Timer.After(0.5, ns.SaveBank)
    elseif event == "BANKFRAME_CLOSED" then
        -- nicht mehr speichern: nach dem Schließen ist die Bank evtl. schon nicht mehr lesbar (wäre dann leer)
        bankOpen = false
    elseif event == "PLAYER_LOGOUT" then
        ns.SaveBags()
    else
        QueueSave()
    end
end)
