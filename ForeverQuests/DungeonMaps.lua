local addonName, ns = ...

-- DungeonMaps.lua: Blizzards eigene Dungeonkarten. Der Spiel-Client bringt für viele Dungeons fertige Karten (mit
-- Ebenen) mit, zeigt sie aber nur im Dungeon. Hier: die Karte eines Dungeons über seinen Namen finden und die
-- Weltkarte darauf umschalten (Knopf "Karte" im Dungeonfenster). Ebenen wählt man dann wie gewohnt in Blizzards
-- Auswahl oben links. Keine eigenen Kartenbilder – nur, was der Client selbst kennt.
-- Prüfbefehl: /fq karten (wie viele Dungeonkarten der Client kennt, mit den ersten Namen).

local index -- [vereinfachter Name] = Karten-ID (einmal beim ersten Bedarf aufgebaut)
local count = 0
local MAX_MAP_ID = 3000 -- so weit werden Karten-IDs durchsucht (Classic- und heutige Karten liegen darunter)

local function Simple(name)
    if type(name) ~= "string" then return nil end
    name = name:lower():gsub("^die ", ""):gsub("^der ", ""):gsub("^das ", ""):gsub("^the ", "")
    return (name:gsub("[%s%p]", ""))
end

local function BuildIndex()
    if index then return end
    index = {}
    if not (C_Map and C_Map.GetMapInfo) then return end
    local dungeonType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
    for id = 1, MAX_MAP_ID do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if ok and info and info.mapType == dungeonType and info.name and info.name ~= "" then
            local key = Simple(info.name)
            -- (bei mehreren Ebenen zählt die erste gefundene – die Auswahl oben links wechselt die Ebene)
            if key and not index[key] then
                index[key] = id
                count = count + 1
            end
        end
    end
end

-- Karten-ID zu einem Dungeon aus dem Dungeonfenster (über den Namen, auch den englischen)
function ns.DungeonMapID(dungeon)
    if not dungeon then return nil end
    BuildIndex()
    for _, name in ipairs({ dungeon.name, dungeon.nameEN }) do
        local key = Simple(name)
        if key and index[key] then return index[key] end
    end
    return nil
end

-- Weltkarte auf die Dungeonkarte umschalten
function ns.OpenDungeonMap(dungeon)
    local mapID = ns.DungeonMapID(dungeon)
    if not mapID then
        print(ns.ChatPrefix() .. ": " .. ns.L("NO_DUNGEON_MAP"))
        return
    end
    if InCombatLockdown() then
        print(ns.ChatPrefix() .. ": " .. ns.L("MAP_AFTER_COMBAT"))
        return
    end
    if type(_G.OpenWorldMap) == "function" then
        pcall(_G.OpenWorldMap, mapID)
    else
        local map = _G.WorldMapFrame
        if map then
            if not map:IsShown() then ShowUIPanel(map) end
            map:SetMapID(mapID)
        end
    end
end

-- /fq karten: was kennt der Client?
function ns.ListDungeonMaps()
    BuildIndex()
    local prefix = ns.ChatPrefix() .. ": "
    print(prefix .. string.format(ns.L("DUNGEON_MAPS_FOUND"), count))
    local names = {}
    for _, id in pairs(index) do
        local info = C_Map.GetMapInfo(id)
        if info and #names < 12 then names[#names + 1] = info.name .. " (" .. id .. ")" end
    end
    table.sort(names)
    if #names > 0 then print(prefix .. table.concat(names, ", ")) end
end
