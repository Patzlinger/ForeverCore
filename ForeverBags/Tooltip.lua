local addonName, ns = ...

-- Tooltip.lua: im Gegenstands-Tooltip, wie viele davon jeder Charakter hat, z. B.
--   Main     20 (Taschen), 5 (Bank)
--   Twink    3 (Taschen)
-- Quelle: die gespeicherten Taschen/Banken (Data.lua); der eingeloggte Charakter zählt live.
-- Eingehängt über Blizzards TooltipDataProcessor (nur angehängt, nichts ersetzt).

local L = ns.L

local issecret = issecretvalue or function() return false end

-- Zählung je Charakter und Gegenstand: index[key][itemID] = { bags, bank }; neu gebaut, wenn sich Daten ändern
local index, indexVersion = nil, -1

local function ItemID(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function CountInto(counts, containers, field)
    for _, c in pairs(containers or {}) do
        if type(c) == "table" then
            for slot = 1, (c.size or 0) do
                local item = c[slot]
                local id = item and ItemID(item[1])
                if id then
                    local entry = counts[id] or { 0, 0 }
                    entry[field] = entry[field] + (item[2] or 1)
                    counts[id] = entry
                end
            end
        end
    end
end

local function Index()
    if index and indexVersion == (ns.dataVersion or 0) then return index end
    index = {}
    for _, entry in ipairs(ns.Characters()) do
        local counts = {}
        CountInto(counts, entry.data.bags, 1)
        CountInto(counts, entry.data.bank, 2)
        index[entry.key] = counts
    end
    indexVersion = ns.dataVersion or 0
    return index
end

local function Describe(bags, bank)
    local parts = {}
    if bags > 0 then parts[#parts + 1] = L("COUNT_BAGS", bags) end
    if bank > 0 then parts[#parts + 1] = L("COUNT_BANK", bank) end
    return table.concat(parts, ", ")
end

local function AddCounts(tooltip, itemID)
    if not itemID or issecret(itemID) or (ns.db and ns.db.tooltipCounts == false) then return end
    local all = Index()
    local me = ns.CharKey()
    local lines, total, chars = {}, 0, 0
    for _, entry in ipairs(ns.Characters()) do
        local bags, bank
        if entry.key == me and C_Item and C_Item.GetItemCount then
            -- live: Taschen ohne Bank, mit Bank (die Bank kennt das Spiel auch, wenn sie zu ist)
            bags = C_Item.GetItemCount(itemID, false) or 0
            bank = math.max(0, (C_Item.GetItemCount(itemID, true) or 0) - bags)
        else
            local c = all[entry.key] and all[entry.key][itemID]
            bags, bank = c and c[1] or 0, c and c[2] or 0
        end
        if bags + bank > 0 then
            lines[#lines + 1] = { ns.ColoredName(entry.data), Describe(bags, bank) }
            total = total + bags + bank
            chars = chars + 1
        end
    end
    if chars == 0 then return end
    tooltip:AddLine(" ")
    for _, line in ipairs(lines) do
        tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
    end
    if chars > 1 then
        tooltip:AddDoubleLine(L("COUNT_TOTAL"), total, 1, 0.82, 0, 1, 0.82, 0)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        local ok = pcall(AddCounts, tooltip, data and data.id)
        if not ok then return end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    -- ältere Clients
    local function OnItem(tooltip)
        local _, link = tooltip:GetItem()
        pcall(AddCounts, tooltip, ItemID(link))
    end
    GameTooltip:HookScript("OnTooltipSetItem", OnItem)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnItem) end
end
