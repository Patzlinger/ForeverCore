local addonName, ns = ...

-- ZoneLevels.lua: Stufenbereich der Gebiete auf der Weltkarte. Fährt man auf der Kontinent- oder Weltkarte über ein
-- Gebiet, zeigt Blizzard oben dessen Namen ("Wald von Elwynn") – dahinter steht jetzt der Stufenbereich "(1–10)",
-- gefärbt nach Schwierigkeit für den eigenen Charakter (wie Quests und Gegner).
-- Blizzards Namens-Anzeige bleibt unverändert: der Bereich ist ein eigener Text direkt dahinter.
-- Stufen: zuerst vom Spiel (C_Map.GetMapLevels), sonst aus der Tabelle unten (klassische Stufenbereiche; Karten-
-- Nummern der Classic-Karten und der heutigen Karten, je nachdem, welche der Forever-Client nutzt).
-- Abschaltbar: Menü » Anzeige » "Stufen der Gebiete auf der Weltkarte" (ns.db.zoneLevels).

local issecret = issecretvalue or function() return false end

-- [Karten-Nummer] = { von, bis } – Classic-Karten (1411 …) und heutige Karten (1 …)
local RANGES = {}
local function Add(ids, from, to)
    for _, id in ipairs(ids) do RANGES[id] = { from, to } end
end
Add({ 1411, 1 }, 1, 10)       -- Durotar
Add({ 1412, 7 }, 1, 10)       -- Mulgore
Add({ 1413, 10 }, 10, 25)     -- Brachland
Add({ 1416 }, 30, 40)         -- Alteracgebirge
Add({ 1417, 14 }, 30, 40)     -- Arathihochland
Add({ 1418, 15 }, 35, 45)     -- Ödland
Add({ 1419, 17 }, 45, 55)     -- Verwüstete Lande
Add({ 1420, 18 }, 1, 10)      -- Tirisfal
Add({ 1421, 21 }, 10, 20)     -- Silberwald
Add({ 1422, 22 }, 51, 58)     -- Westliche Pestländer
Add({ 1423, 23 }, 53, 60)     -- Östliche Pestländer
Add({ 1424, 25 }, 20, 30)     -- Vorgebirge des Hügellands
Add({ 1425, 26 }, 40, 50)     -- Hinterland
Add({ 1426, 27 }, 1, 10)      -- Dun Morogh
Add({ 1427, 32 }, 43, 50)     -- Sengende Schlucht
Add({ 1428, 36 }, 50, 58)     -- Brennende Steppe
Add({ 1429, 37 }, 1, 10)      -- Wald von Elwynn
Add({ 1430, 42 }, 55, 60)     -- Gebirgspass der Totenwinde
Add({ 1431, 47 }, 18, 30)     -- Dämmerwald
Add({ 1432, 48 }, 10, 20)     -- Loch Modan
Add({ 1433, 49 }, 15, 25)     -- Rotkammgebirge
Add({ 1434, 50, 210 }, 30, 45) -- Schlingendorntal
Add({ 1435, 51 }, 35, 45)     -- Sümpfe des Elends
Add({ 1436, 52 }, 10, 20)     -- Westfall
Add({ 1437, 56 }, 20, 30)     -- Sumpfland
Add({ 1438, 57 }, 1, 10)      -- Teldrassil
Add({ 1439, 62 }, 10, 20)     -- Dunkelküste
Add({ 1440, 63 }, 18, 30)     -- Eschental
Add({ 1441, 64 }, 25, 35)     -- Tausend Nadeln
Add({ 1442, 65 }, 15, 27)     -- Steinkrallengebirge
Add({ 1443, 66 }, 30, 40)     -- Desolace
Add({ 1444, 69 }, 40, 50)     -- Feralas
Add({ 1445, 70 }, 35, 45)     -- Düstermarschen
Add({ 1446, 71 }, 40, 50)     -- Tanaris
Add({ 1447, 76 }, 45, 55)     -- Azshara
Add({ 1448, 77 }, 48, 55)     -- Teufelswald
Add({ 1449, 78 }, 48, 55)     -- Krater von Un'Goro
Add({ 1451, 81 }, 55, 60)     -- Silithus
Add({ 1452, 83 }, 55, 60)     -- Winterquell

-- Stufen eines Gebiets: vom Spiel, sonst aus der Tabelle
local function Levels(mapID)
    if not mapID then return nil end
    if C_Map and C_Map.GetMapLevels then
        local ok, from, to = pcall(C_Map.GetMapLevels, mapID)
        if ok and type(from) == "number" and type(to) == "number" and not issecret(from) and from > 0 and to >= from then
            return from, to
        end
    end
    local r = RANGES[mapID]
    if r then return r[1], r[2] end
    return nil
end
ns.ZoneLevels = Levels

-- Blizzards Namens-Anzeige auf der Karte (Datenquelle mit .Label und darin .Name)
local function FindLabel(map)
    for provider in pairs(map.dataProviders or {}) do
        local label = type(provider) == "table" and provider.Label
        if type(label) == "table" and label.Name and label.Name.GetText then return label end
    end
end

local function Setup()
    local map = _G.WorldMapFrame
    if not map or ns.zoneLevelsReady then return end
    local label = FindLabel(map)
    if not label then return end
    ns.zoneLevelsReady = true
    local text = label:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(label.Name:GetFontObject() or "GameFontNormalLarge")
    text:SetPoint("LEFT", label.Name, "RIGHT", 6, 0)
    text:Hide()
    local elapsed = 0
    local watch = CreateFrame("Frame", nil, map)
    watch:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.05 then return end
        elapsed = 0
        local name = label.Name:GetText()
        if not (ns.db and ns.db.zoneLevels ~= false) or not label.Name:IsVisible() or not name or name == ""
            or issecret(name) then
            text:Hide()
            return
        end
        -- Gebiet unter dem Mauszeiger
        local container = map.ScrollContainer
        local mapID = map.GetMapID and map:GetMapID()
        local x, y
        if container and container.GetNormalizedCursorPosition then x, y = container:GetNormalizedCursorPosition() end
        local info = mapID and x and C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, x, y)
        -- (nur, wenn Blizzard gerade genau dieses Gebiet anzeigt – nicht etwa einen Dungeon-Namen)
        if not (info and info.mapID and info.name == name) then
            text:Hide()
            return
        end
        local from, to = Levels(info.mapID)
        if not from then
            text:Hide()
            return
        end
        local color = ns.QuestList and ns.QuestList.LevelColor and ns.QuestList.LevelColor(math.floor((from + to) / 2))
        if color then text:SetTextColor(color.r, color.g, color.b) else text:SetTextColor(1, 0.82, 0) end
        text:SetText(from == to and ("(" .. from .. ")") or ("(" .. from .. "–" .. to .. ")"))
        text:Show()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
    local ok, err = pcall(Setup)
    if not ok then geterrorhandler()(err) end
    -- (die Namens-Anzeige entsteht teils erst beim ersten Öffnen der Karte)
    local map = _G.WorldMapFrame
    if map and not ns.zoneLevelsHooked then
        ns.zoneLevelsHooked = true
        map:HookScript("OnShow", function() pcall(Setup) end)
    end
end)
