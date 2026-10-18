-- ForeverAlts – Data.lua: merkt sich zu JEDEM Charakter, der einmal eingeloggt war, das Wichtigste – Stufe, Erfahrung,
-- Erholung, Gold, Ort, Berufe und Quests im Log (mit Fortschritt und Dungeon). Kontoweit in ForeverAltsData (eigene
-- SavedVariable, NICHT über die Profil-Verwaltung: Charakter-Daten sind keine Einstellungen, CLAUDE.md Abschnitt 9).
-- Gelesen wird nur außerhalb des Kampfes (keine gesperrten Werte) und gebündelt, nie in jedem Bild.
--
-- Aufbau: ForeverAltsData.chars["Name-Realm"] = {
--     name, realm, class, race, faction, level, maxLevel, xp, xpMax, rested, resting, money, zone, subZone,
--     ilvl, updated (Zeit), profs = { { name, rank, max, icon } },
--     questCount, quests = { [questID] = { title, level, complete, done, total, dungeon, raid } },
-- }
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI
local T = UI.T
ns.UI, ns.T = UI, T

---------------------------------------------------------------------------
-- Einstellungen (Profil-Verwaltung des Hubs)
---------------------------------------------------------------------------
ns.DEFAULTS = {
    minimapAngle = 250,
    sameRealm = false,   -- nur Charaktere dieses Realms zeigen
    sameFaction = false, -- nur Charaktere der eigenen Fraktion zeigen
    questInfo = true,    -- Twinks in Quest-Tooltips und im Hinweis "Dungeon betreten" (ForeverQuests)
    sortKey = "level",   -- Sortierung der Liste: level, name, money, rested, updated
    sortDesc = true,
    hiddenColumns = {},  -- ausgeblendete Spalten der Übersicht ([Schlüssel] = true)
    recipeTooltip = true, -- im Gegenstands-Tooltip zeigen, welcher Charakter ihn herstellen kann
}

function ns.GetDB()
    if type(_G.ForeverAltsDB) ~= "table" then _G.ForeverAltsDB = {} end
    local db = _G.ForeverAltsDB
    for k, v in pairs(ns.DEFAULTS) do
        if db[k] == nil then db[k] = type(v) == "table" and CopyTable(v) or v end
    end
    return db
end

function ns.Safe(where, fn) return UI.Safe("ForeverAlts", where, fn) end
function ns.Chat(text) UI.Chat("ForeverAlts", text) end

local issecret = issecretvalue or function() return false end
local function Plain(value) -- gesperrter Wert = nicht verwendbar
    if issecret(value) then return nil end
    return value
end

---------------------------------------------------------------------------
-- Gespeicherte Charaktere
---------------------------------------------------------------------------
local function Data()
    if type(_G.ForeverAltsData) ~= "table" then _G.ForeverAltsData = {} end
    if type(_G.ForeverAltsData.chars) ~= "table" then _G.ForeverAltsData.chars = {} end
    return _G.ForeverAltsData
end

-- gleicher Schlüssel wie ForeverBags ("Name-Realm"), damit die Taschen eines Twinks gefunden werden
function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

function ns.CharacterData(key) return Data().chars[key] end

function ns.ForgetCharacter(key)
    if key ~= ns.CharKey() then Data().chars[key] = nil end
end

local function Me()
    local chars, key = Data().chars, ns.CharKey()
    if type(chars[key]) ~= "table" then chars[key] = {} end
    return chars[key]
end

-- Klassenfarbiger Name
function ns.ColoredName(c)
    local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local name = c and c.name or "?"
    if color then return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name) end
    return name
end

-- Alle Charaktere nach den Einstellungen gefiltert (der eingeloggte immer dabei) und sortiert
function ns.Characters()
    local db, me = ns.GetDB(), ns.CharKey()
    local myRealm, myFaction = GetRealmName(), UnitFactionGroup("player")
    local list = {}
    for key, c in pairs(Data().chars) do
        if type(c) == "table" and (key == me or ((not db.sameRealm or c.realm == myRealm)
            and (not db.sameFaction or c.faction == myFaction))) then
            list[#list + 1] = { key = key, data = c, me = key == me }
        end
    end
    local sortKey, desc = db.sortKey, db.sortDesc
    local function Value(entry)
        local c = entry.data
        if sortKey == "name" then return (c.name or ""):lower() end
        if sortKey == "money" then return c.money or 0 end
        if sortKey == "rested" then return ns.RestedPercent(entry) or -1 end
        if sortKey == "updated" then return entry.me and math.huge or (c.updated or 0) end
        return (c.level or 0) + (c.xpMax and c.xpMax > 0 and (c.xp or 0) / c.xpMax or 0)
    end
    table.sort(list, function(a, b)
        local va, vb = Value(a), Value(b)
        if va == vb then return a.key < b.key end
        if desc then return va > vb end
        return va < vb
    end)
    return list
end

---------------------------------------------------------------------------
-- Erholung: beim eingeloggten Charakter aus dem Spiel, bei den anderen geschätzt seit dem letzten Login
-- (Blizzard-Regel: 5 % einer Stufe je 8 Stunden im Gasthaus/in der Hauptstadt, sonst ein Viertel davon; höchstens 150 %)
---------------------------------------------------------------------------
function ns.RestedPercent(entry)
    local c = entry.data
    if not c.xpMax or c.xpMax <= 0 or (c.maxLevel and c.level and c.level >= c.maxLevel) then return nil end
    local rested = c.rested or 0
    local estimated = false
    if not entry.me and c.updated then
        local hours = math.max(0, time() - c.updated) / 3600
        local gain = hours / 8 * 0.05 * c.xpMax * (c.resting and 1 or 0.25)
        if gain > 0 then rested, estimated = rested + gain, true end
    end
    rested = math.min(rested, c.xpMax * 1.5)
    return math.floor(rested / c.xpMax * 100 + 0.5), estimated
end

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------
local function ReadProfessions()
    local list = {}
    if GetProfessions and GetProfessionInfo then
        local ok, a, b, c, d, e = pcall(GetProfessions)
        if ok then
            for _, index in pairs({ a, b, c, d, e }) do
                local okInfo, name, icon, rank, maxRank = pcall(GetProfessionInfo, index)
                if okInfo and name then list[#list + 1] = { name = name, icon = icon, rank = rank, max = maxRank } end
            end
        end
    end
    -- Rückfall (klassische Fertigkeiten-Liste): Berufe lassen sich verlernen, Nebenberufe stehen unter eigener Überschrift
    if #list == 0 and GetNumSkillLines and GetSkillLineInfo then
        local header
        for i = 1, GetNumSkillLines() or 0 do
            local name, isHeader, _, rank, _, _, maxRank, isAbandonable = GetSkillLineInfo(i)
            if isHeader then
                header = name
            elseif name and (isAbandonable or (header and (header == _G.SECONDARY_SKILLS
                or header:find("Sekund") or header:find("Secondary")))) then
                list[#list + 1] = { name = name, rank = rank, max = maxRank }
            end
        end
    end
    return list
end

local function QuestProgress(questID)
    local done, total = 0, 0
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        local need = tonumber(Plain(objective.numRequired)) or 0
        if need <= 0 then need = 1 end
        local have = tonumber(Plain(objective.numFulfilled)) or 0
        if objective.finished then have = need end
        done, total = done + math.min(have, need), total + need
    end
    return done, total
end

local function ReadQuests()
    local quests, count = {}, 0
    local questsAPI = UI.API and UI.API.ForeverQuests
    for i = 1, (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or 0) do
        local info = C_QuestLog.GetInfo(i)
        local questID = info and not info.isHeader and not info.isHidden and info.questID
        if questID and questID > 0 then
            count = count + 1
            local q = { title = info.title, level = info.level }
            q.complete = C_QuestLog.IsComplete(questID) and true or nil
            local okProgress, done, total = pcall(QuestProgress, questID)
            if okProgress and total > 0 then q.done, q.total = done, total end
            if questsAPI and questsAPI.DungeonOfQuest then
                local ok, dungeon, raid = pcall(questsAPI.DungeonOfQuest, questID)
                if ok and dungeon then q.dungeon, q.raid = dungeon, raid or nil end
            end
            quests[questID] = q
        end
    end
    return quests, count
end

-- Alles des eingeloggten Charakters neu lesen (what = nil: alles; "money"/"xp"/"quests"/"profs": nur das)
function ns.Update(what)
    if InCombatLockdown() then
        UI.AfterCombat("ForeverAlts:update", function() ns.Update() end, "ForeverAlts")
        return
    end
    local c = Me()
    c.name, c.realm = UnitName("player"), GetRealmName()
    local _, class = UnitClass("player")
    c.class = class
    c.race = UnitRace("player")
    c.faction = UnitFactionGroup("player")
    c.updated = time()
    if not what or what == "xp" then
        c.level = Plain(UnitLevel("player"))
        c.maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or c.maxLevel
        c.xp, c.xpMax = Plain(UnitXP("player")), Plain(UnitXPMax("player"))
        c.rested = Plain(GetXPExhaustion and GetXPExhaustion()) or 0
        c.resting = IsResting() and true or nil
    end
    if not what or what == "money" then c.money = Plain(GetMoney()) or c.money end
    if not what or what == "zone" then
        c.zone, c.subZone = GetRealZoneText(), GetSubZoneText()
        c.resting = IsResting() and true or nil
    end
    if not what or what == "profs" then c.profs = ReadProfessions() end
    if not what or what == "quests" then c.quests, c.questCount = ReadQuests() end
    if not what and GetAverageItemLevel then
        local ok, _, equipped = pcall(GetAverageItemLevel)
        if ok and equipped then c.ilvl = math.floor(equipped + 0.5) end
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

---------------------------------------------------------------------------
-- Schnittstelle für andere Forever-Addons (über den Hub, UI.API.ForeverAlts)
---------------------------------------------------------------------------
if UI.API then
    UI.API.ForeverAlts = {
        Characters = function() return ns.Characters() end,
        -- andere eigene Charaktere, die die Quest im Log haben: { name, coloredName, key, complete, done, total }
        CharsWithQuest = function(questID)
            local out = {}
            if not questID or not ns.GetDB().questInfo then return out end
            for _, entry in ipairs(ns.Characters()) do
                local q = not entry.me and entry.data.quests and entry.data.quests[questID]
                if q then
                    out[#out + 1] = { key = entry.key, name = entry.data.name, coloredName = ns.ColoredName(entry.data),
                        complete = q.complete, done = q.done, total = q.total }
                end
            end
            return out
        end,
        Toggle = function() if ns.ToggleWindow then ns.ToggleWindow() end end,
    }
end

---------------------------------------------------------------------------
-- Ereignisse: gebündelt (mehrere kurz hintereinander = ein Lesen)
---------------------------------------------------------------------------
local pending, scheduled = {}, false
local function Queue(what)
    pending[what or "all"] = true
    if scheduled then return end
    scheduled = true
    C_Timer.After(1, ns.Safe("Update", function()
        scheduled = false
        local parts = pending
        pending = {}
        if parts.all then ns.Update() return end
        for part in pairs(parts) do ns.Update(part) end
    end))
end

local EVENTS = {
    PLAYER_LEVEL_UP = "xp", PLAYER_XP_UPDATE = "xp", UPDATE_EXHAUSTION = "xp", PLAYER_UPDATE_RESTING = "xp",
    PLAYER_MONEY = "money", ZONE_CHANGED_NEW_AREA = "zone", ZONE_CHANGED = "zone",
    SKILL_LINES_CHANGED = "profs", QUEST_LOG_UPDATE = "quests", QUEST_TURNED_IN = "quests",
}
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
for event in pairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", ns.Safe("Ereignis", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Berufe, Quests und Dungeondaten (ForeverQuests baut sie aus Questie) sind erst nach ein paar Sekunden da
        C_Timer.After(3, function() Queue() end)
        C_Timer.After(15, function() Queue("quests") end)
    elseif event == "PLAYER_LOGOUT" then
        -- nur Zeit, Ort und Erholungs-Zustand (für die Schätzung der Erholung bis zum nächsten Login)
        local c = Me()
        c.updated = time()
        c.resting = IsResting() and true or nil
    else
        Queue(EVENTS[event])
    end
end))
