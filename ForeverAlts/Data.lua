-- ForeverAlts – Data.lua: merkt sich zu JEDEM Charakter, der einmal eingeloggt war, das Wichtigste – Stufe, Erfahrung,
-- Erholung, Gold, Ort, Berufe und Quests im Log (mit Fortschritt und Dungeon). Kontoweit in ForeverAltsData (eigene
-- SavedVariable, NICHT über die Profil-Verwaltung: Charakter-Daten sind keine Einstellungen, CLAUDE.md Abschnitt 9).
-- Gelesen wird nur außerhalb des Kampfes (keine gesperrten Werte) und gebündelt, nie in jedem Bild.
--
-- Aufbau: ForeverAltsData.chars["Name-Realm"] = {
--     name, realm, class, race, faction, level, maxLevel, xp, xpMax, rested, resting, money, zone, subZone,
--     ilvl, updated (Zeit), profs = { { name, rank, max, icon } }, gear = { [Platz] = { link, icon, quality } },
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
    showHidden = false,   -- ausgeblendete Charaktere trotzdem (blass) zeigen, um sie wieder einzublenden
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

-- Ausblenden statt Löschen: die Daten bleiben, der Charakter erscheint nur nicht mehr in der Übersicht
-- (und nicht in den Hinweisen anderer Addons). Unten im Fenster "Ausgeblendete zeigen" holt ihn zurück.
function ns.SetHidden(key, hidden)
    local c = Data().chars[key]
    if c and key ~= ns.CharKey() then c.hidden = hidden and true or nil end
end

function ns.HiddenCount()
    local n = 0
    for _, c in pairs(Data().chars) do if type(c) == "table" and c.hidden then n = n + 1 end end
    return n
end

local function Me()
    local chars, key = Data().chars, ns.CharKey()
    if type(chars[key]) ~= "table" then chars[key] = {} end
    return chars[key]
end

-- Klassenfarbiger Name (voller Name "Vorname Nachname", wenn bekannt)
function ns.ColoredName(c)
    local color = c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    local name = c and (c.fullName or c.name) or "?"
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
            and (not db.sameFaction or c.faction == myFaction) and (db.showHidden or not c.hidden))) then
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
        if sortKey == "zone" then return (c.zone or ""):lower() end
        if sortKey == "played" then return ns.PlayedNow(entry) or -1 end
        if sortKey == "honor" then return c.honor or c.honorKills or -1 end
        if sortKey == "mail" then return (c.mail and (c.mail.new and 1000 or 0) + (c.mail.count or 0)) or -1 end
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

-- Ehre: Classic (Ehrenpunkte, Rang, ehrenhafte Siege) bzw. Retail (Ehre als Währung) – was der Client hat
local function ReadHonor(c)
    local ok, value = pcall(function()
        if GetHonorCurrency then return GetHonorCurrency() end
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local id = Constants and Constants.CurrencyConsts and Constants.CurrencyConsts.HONOR_CURRENCY_ID or 1792
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            return info and info.quantity
        end
    end)
    c.honor = ok and Plain(value) or c.honor
    if UnitPVPRank and GetPVPRankInfo then
        local okRank, rankName = pcall(function()
            local rank = UnitPVPRank("player")
            return rank and rank > 0 and GetPVPRankInfo(rank) or nil
        end)
        c.pvpRank = okRank and rankName or nil
    end
    if GetPVPLifetimeStats then
        local okKills, kills = pcall(GetPVPLifetimeStats)
        c.honorKills = okKills and Plain(kills) or c.honorKills
    end
end

-- Post: beim Login/Ändern nur "neue Post ja/nein"; am Briefkasten Anzahl und früheste Ablaufzeit
local function ReadMail(c, atMailbox)
    c.mail = c.mail or {}
    c.mail.new = HasNewMail and HasNewMail() and true or nil
    if atMailbox and GetInboxNumItems then
        local count = GetInboxNumItems() or 0
        local soonest
        for i = 1, count do
            local okHeader, daysLeft = pcall(function() return select(7, GetInboxHeaderInfo(i)) end)
            daysLeft = okHeader and tonumber(daysLeft)
            if daysLeft and (not soonest or daysLeft < soonest) then soonest = daysLeft end
        end
        c.mail.count = count
        c.mail.expires = soonest and (time() + soonest * 86400) or nil
        c.mail.checked = time()
    end
end

-- Gespielte Zeit: das Spiel liefert sie nur auf Anfrage (TIME_PLAYED_MSG) und schreibt sie dann in den Chat. Für unsere
-- eigene Anfrage (einmal je Login) melden wir die Chatfenster kurz vom Ereignis ab – ein eigenes /played zeigt sie
-- weiter ganz normal. (Keine Blizzard-Funktion wird überschrieben.)
local playedMuted = {}
local function MutePlayedChat(mute)
    if mute then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local frame = _G["ChatFrame" .. i]
            if frame and frame.IsEventRegistered and frame:IsEventRegistered("TIME_PLAYED_MSG") then
                frame:UnregisterEvent("TIME_PLAYED_MSG")
                playedMuted[#playedMuted + 1] = frame
            end
        end
    else
        for _, frame in ipairs(playedMuted) do frame:RegisterEvent("TIME_PLAYED_MSG") end
        wipe(playedMuted)
    end
end

function ns.RequestPlayed()
    if not RequestTimePlayed or ns.playedRequested then return end
    ns.playedRequested = true
    MutePlayedChat(true)
    RequestTimePlayed()
    C_Timer.After(5, function() MutePlayedChat(false) end) -- Sicherheit, falls keine Antwort kommt
end

-- gespielte Zeit eines Charakters jetzt (beim eingeloggten: seit der Abfrage weitergezählt)
function ns.PlayedNow(entry)
    local c = entry.data
    if not c.playedTotal then return nil end
    local extra = (entry.me and c.playedAt) and math.max(0, time() - c.playedAt) or 0
    return c.playedTotal + extra, c.playedLevel and (c.playedLevel + extra) or nil
end

-- Voller Name: UnitName("player") liefert in Forever nur den Vornamen, Addon-Nachrichten kommen aber mit
-- "Vorname Nachname-Realm" an. Darum schickt ForeverAlts sich beim Login einmal unsichtbar selbst eine Nachricht.
local NAME_PREFIX = "FALTS"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, NAME_PREFIX) end

-- an sich selbst geht nicht überall (Flüstern braucht evtl. schon den vollen Namen) – darum zusätzlich an Gilde
-- bzw. Gruppe: dort kommt die eigene Nachricht mit dem eigenen vollen Namen als Absender zurück
function ns.RequestFullName()
    if Me().fullName or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, NAME_PREFIX, "N", "WHISPER", UnitName("player"))
    if IsInGuild and IsInGuild() then pcall(C_ChatInfo.SendAddonMessage, NAME_PREFIX, "N", "GUILD") end
    if IsInGroup() then pcall(C_ChatInfo.SendAddonMessage, NAME_PREFIX, "N", IsInRaid() and "RAID" or "PARTY") end
end

-- Weitere Quelle: eigene Chatnachrichten (Sagen, Gilde, Gruppe …) tragen den vollen Namen als Absender; erkannt an
-- der eigenen Kennung (GUID), nicht am Namen
local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_INSTANCE_CHAT" }

local function StoreFullName(sender)
    if type(sender) ~= "string" or issecret(sender) then return end
    local full = sender:match("^(.-)%-[^%-]+$") or sender -- "-Realm" ab
    local first = UnitName("player")
    if first and full:sub(1, #first) == first then
        Me().fullName = full ~= first and full or nil
        if ns.RefreshWindow then ns.RefreshWindow() end
    end
end

-- Weitere Quellen ohne Chat: Name samt Rang/Titel aus dem Spiel (UnitPVPName) und die Überschrift des
-- Charakterfensters. Der Titel wird herausgenommen; übrig bleibt "Vorname Nachname" (zwei Wörter ab dem Vornamen).
local function NameFromText(text)
    if type(text) ~= "string" or issecret(text) then return end
    local first = UnitName("player")
    if not first or issecret(first) then return end
    local start = text:find(first, 1, true)
    if not start then return end
    local surname = text:sub(start + #first):match("^ ([^%s%-<,]+)")
    if not surname then return end
    -- kein Titelwort erwischen (z. B. "Hexeron der Entdecker")
    local title = Me().title
    if title and title:find(surname, 1, true) then return end
    Me().fullName = first .. " " .. surname
    if ns.RefreshWindow then ns.RefreshWindow() end
end

function ns.TryNameFromTexts()
    if Me().fullName then return end
    if UnitPVPName then NameFromText(UnitPVPName("player")) end
    if Me().fullName then return end
    local frame = _G.CharacterFrame
    local titleText = _G.CharacterFrameTitleText
        or (frame and frame.TitleContainer and frame.TitleContainer.TitleText)
    if titleText and titleText.GetText then NameFromText(titleText:GetText()) end
end

-- Charakterfenster geöffnet: dessen Überschrift lesen (nur lesen, nichts am Fenster ändern)
local nameWatcher = CreateFrame("Frame")
nameWatcher:RegisterEvent("PLAYER_LOGIN")
nameWatcher:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(3, function() pcall(ns.TryNameFromTexts) end)
    local frame = _G.CharacterFrame
    if frame and frame.HookScript then
        frame:HookScript("OnShow", function() C_Timer.After(0.2, function() pcall(ns.TryNameFromTexts) end) end)
    end
end)

-- Titel (z. B. PvP-Rang oder Erfolgstitel), ohne den Platzhalter für den Namen
local function ReadTitle(c)
    local ok, title = pcall(function()
        local id = GetCurrentTitle and GetCurrentTitle()
        return id and id > 0 and GetTitleName and GetTitleName(id) or nil
    end)
    title = ok and type(title) == "string" and strtrim((title:gsub("%%s", ""))) or nil
    c.title = (title and title ~= "") and title or nil
end

-- Ausrüstung (für die Charakterübersicht anderer Charaktere): je Platz Link, Symbol und Qualität – alles gleich beim
-- Lesen gemerkt, damit die Übersicht später ohne nachgeladene Gegenstandsdaten auskommt
local GEAR_SLOTS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
local function ReadGear(c)
    local gear = {}
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and not issecret(link) then
            gear[slot] = { link = link, icon = GetInventoryItemTexture("player", slot),
                quality = GetInventoryItemQuality and GetInventoryItemQuality("player", slot) or nil }
        end
    end
    c.gear = gear
    if GetAverageItemLevel then
        local ok, _, equipped = pcall(GetAverageItemLevel)
        if ok and equipped then c.ilvl = math.floor(equipped + 0.5) end
    end
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
    if not what or what == "honor" then ReadHonor(c) end
    if not what or what == "title" then ReadTitle(c) end
    if not what or what == "mail" or what == "mailbox" then ReadMail(c, what == "mailbox") end
    if not what or what == "quests" then c.quests, c.questCount = ReadQuests() end
    if not what or what == "gear" then ReadGear(c) end
    if ns.RefreshGear then ns.RefreshGear() end
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
                local q = not entry.me and not entry.data.hidden and entry.data.quests and entry.data.quests[questID]
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
    PLAYER_PVP_RANK_CHANGED = "honor", HONOR_CURRENCY_UPDATE = "honor", PLAYER_PVP_KILLS_CHANGED = "honor",
    CURRENCY_DISPLAY_UPDATE = "honor",
    UPDATE_PENDING_MAIL = "mail", MAIL_INBOX_UPDATE = "mailbox", MAIL_SHOW = "mailbox",
    KNOWN_TITLES_UPDATE = "title", PLAYER_TITLE_CHANGED = "title",
    PLAYER_EQUIPMENT_CHANGED = "gear",
}
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("TIME_PLAYED_MSG")
for event in pairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("UNIT_NAME_UPDATE")
for _, event in ipairs(CHAT_EVENTS) do pcall(events.RegisterEvent, events, event) end
local isChatEvent = {}
for _, event in ipairs(CHAT_EVENTS) do isChatEvent[event] = true end
events:SetScript("OnEvent", ns.Safe("Ereignis", function(_, event, total, level, _, sender, ...)
    if isChatEvent[event] then
        -- Chat: 2. Wert = Absender, 12. Wert = GUID des Absenders
        if Me().fullName then return end
        local guid = select(8, ...)
        if not issecret(guid) and not issecret(level) and guid and guid == UnitGUID("player") then StoreFullName(level) end
        return
    elseif event == "CHAT_MSG_ADDON" then
        if not issecret(total) and total == NAME_PREFIX then StoreFullName(sender) end
        return
    elseif event == "UNIT_NAME_UPDATE" then
        if total == "player" then Queue("title") end
        return
    end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(5, ns.RequestFullName)
        C_Timer.After(30, ns.RequestFullName) -- Gilde/Gruppe sind beim Login evtl. noch nicht bekannt
        -- Berufe, Quests und Dungeondaten (ForeverQuests baut sie aus Questie) sind erst nach ein paar Sekunden da
        C_Timer.After(3, function() Queue() end)
        C_Timer.After(15, function() Queue("quests") end)
        C_Timer.After(8, ns.RequestPlayed)
    elseif event == "TIME_PLAYED_MSG" then
        local c = Me()
        c.playedTotal, c.playedLevel, c.playedAt = tonumber(total), tonumber(level), time()
        C_Timer.After(0, function() MutePlayedChat(false) end)
        if ns.RefreshWindow then ns.RefreshWindow() end
    elseif event == "PLAYER_LOGOUT" then
        -- nur Zeit, Ort und Erholungs-Zustand (für die Schätzung der Erholung bis zum nächsten Login)
        local c = Me()
        c.updated = time()
        c.resting = IsResting() and true or nil
    else
        Queue(EVENTS[event])
    end
end))
