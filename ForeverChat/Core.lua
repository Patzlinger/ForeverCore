-- ForeverChat (Prototyp): Blizzards Chat im Forever-Core-Stil, mit Klassenfarben, Stufen, Links und Komfort.
-- Core.lua: Einstellungen, Hilfsfunktionen, Stufen-Speicher, Start, Chatbefehl
--
-- Grundsatz: Der Blizzard-Chat bleibt der Chat (Fluestern, Kanaele, Links, Bearbeitungsmodus, Communities
-- funktionieren unveraendert). ForeverChat
--   * aendert Texte nur ueber Blizzards offizielle Filter (ChatFrameUtil.AddSenderNameFilter /
--     AddMessageEventFilter) – die werden bei gesperrten Texten im Kampf automatisch uebersprungen,
--   * ersetzt KEINE Blizzard-Funktionen (AddMessage laeuft im Forever-Client ueber einen sicheren Pfad),
--   * aendert Blizzard-Rahmen nur optisch (Alpha 0 per UI.HideBlizzard, eigene Flaechen daneben).
local ADDON_NAME, ns = ...

local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
ns.UI = UI
local T = UI.T
ns.T = T

---------------------------------------------------------------------------
-- Einstellungen (SavedVariables)
---------------------------------------------------------------------------
ns.DEFAULTS = {
    -- Aussehen
    bgAlpha = 20,            -- Durchsichtigkeit der Chat-Flaeche in % Deckkraft (standardmaessig sehr durchsichtig)
    borderAlpha = 50,        -- Rand der Flaeche in %
    styleTabs = true,        -- Reiter im Forever-Stil
    styleEditBox = true,     -- Eingabefeld im Forever-Stil
    autoHideEditBox = true,  -- Eingabezeile nur beim Schreiben bzw. mit der Maus darueber zeigen
    hideSideButtons = true,  -- Blizzards Knopfleiste neben dem Chat ausblenden (Ersatz: eigene Knopfleiste)
    toolbar = true,          -- eigene kleine Knopfleiste ueber dem Chat
    -- Namen
    classColors = true,      -- Spielernamen in Klassenfarbe
    showLevel = true,        -- Stufe vor dem Namen, sofern bekannt
    hideMaxLevel = false,    -- Stufe bei Hoechststufe weglassen
    -- Nachrichten
    channelNames = "SHORT",  -- "FULL" = "2. Handel - Stadt", "SHORT" = "2. Handel", "NUMBER" = "2"
    urls = true,             -- Webadressen klickbar (Fenster zum Kopieren)
    mention = true,          -- eigenen Namen in fremden Nachrichten hervorheben
    mentionSound = false,    -- dazu ein leiser Ton
    -- Instant Messaging (Messenger.lua)
    messenger = true,        -- Reiter "IM": Fluestern je Person in eigenem Unterreiter
    whispersInMain = false,  -- Fluestern zusaetzlich im normalen Chat zeigen
    -- Eingabe
    arrowHistory = true,     -- Pfeiltasten blaettern im Verlauf (ohne Alt)
    shiftScroll = true,      -- Umschalt + Mausrad = ganz nach oben/unten
    -- Fenster
    locked = true,           -- Chatfenster gesperrt (Groesse/Ziehen von Zusatzfenstern)
    minimapAngle = 160,
    savedColors = nil,       -- Blizzard-Farben vor "Dezente Farben" (zum Zuruecksetzen)
}

local function FillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil and value ~= nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
end

function ns.GetDB()
    if type(_G.ForeverChatDB) ~= "table" then _G.ForeverChatDB = {} end
    FillDefaults(_G.ForeverChatDB, ns.DEFAULTS)
    return _G.ForeverChatDB
end

function ns.Chat(text) UI.Chat(ADDON_NAME, text) end

-- Fehlerschutz (gemeinsam im ForeverHub)
function ns.Safe(where, fn) return UI.Safe(ADDON_NAME, where, fn) end

-- Gesperrte Werte (Kampf, "secret values") nie anfassen: nur weiterreichen
local canaccessvalue = _G.canaccessvalue
function ns.CanRead(...)
    if not canaccessvalue then return true end
    return canaccessvalue(...)
end

-- Alle Chatfenster (auch spaeter geoeffnete Fluester-Fenster)
function ns.ForEachChatFrame(fn)
    for _, name in ipairs(_G.CHAT_FRAMES or {}) do
        local frame = _G[name]
        if frame then fn(frame, name) end
    end
end

function ns.MainChatFrame()
    return _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
end

-- Gerade gewaehltes Chatfenster (Reiter)
function ns.SelectedChatFrame()
    if _G.FCFDock_GetSelectedWindow and _G.GENERAL_CHAT_DOCK then
        local f = _G.FCFDock_GetSelectedWindow(_G.GENERAL_CHAT_DOCK)
        if f then return f end
    end
    return _G.SELECTED_CHAT_FRAME or ns.MainChatFrame()
end

---------------------------------------------------------------------------
-- Stufen-Speicher: Stufen bekannter Spieler (Gruppe, Gilde, Freunde, /wer, Ziel, Maus, Namensplaketten).
-- Forever-Namen koennen "Vorname Nachname" sein, die Gruppenliste kennt evtl. nur den Vornamen –
-- deshalb wird auch unter dem ersten Wort gespeichert und notfalls darueber gesucht.
---------------------------------------------------------------------------
local levels = {}

local function NameKeys(name)
    if type(name) ~= "string" or name == "" or not ns.CanRead(name) then return end
    local full = name:lower()
    local short = full:match("^([^%-]+)") or full      -- ohne Realm
    local first = short:match("^(%S+)") or short        -- erstes Wort
    return full, short, first
end

function ns.RememberLevel(name, level)
    if not ns.CanRead(level) or type(level) ~= "number" or level <= 0 then return end
    local full, short, first = NameKeys(name)
    if not full then return end
    levels[full], levels[short] = level, level
    if first ~= short and not levels[first] then levels[first] = level end
end

local function RememberUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local name, realm = UnitName(unit)
    if not ns.CanRead(name, realm) or not name then return end
    local level = UnitLevel(unit)
    if realm and realm ~= "" then ns.RememberLevel(name .. "-" .. realm, level) end
    ns.RememberLevel(name, level)
end

function ns.LevelOf(name, guid)
    -- 1. Spieler ist gerade als Einheit greifbar (Gruppe, Ziel, Namensplakette …)
    if guid and ns.CanRead(guid) and _G.UnitTokenFromGUID then
        local unit = _G.UnitTokenFromGUID(guid)
        if unit then
            local level = UnitLevel(unit)
            if ns.CanRead(level) and type(level) == "number" and level > 0 then return level end
        end
    end
    -- 2. gemerkt
    local full, short, first = NameKeys(name)
    if not full then return end
    return levels[full] or levels[short] or levels[first]
end

function ns.MaxLevel()
    if _G.GetMaxLevelForPlayerExpansion then return _G.GetMaxLevelForPlayerExpansion() end
    if _G.GetMaxPlayerLevel then return _G.GetMaxPlayerLevel() end
    return _G.MAX_PLAYER_LEVEL or 999
end

local function ScanGroup()
    RememberUnit("player")
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() do RememberUnit(prefix .. i) end
end

local function ScanGuild()
    if not IsInGuild() or not _G.GetNumGuildMembers then return end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level = GetGuildRosterInfo(i)
        ns.RememberLevel(name, level)
    end
end

local function ScanFriends()
    local FL = C_FriendList
    if not (FL and FL.GetNumFriends and FL.GetFriendInfoByIndex) then return end
    for i = 1, FL.GetNumFriends() do
        local info = FL.GetFriendInfoByIndex(i)
        if info and info.connected then ns.RememberLevel(info.name, info.level) end
    end
end

local function ScanWho()
    local FL = C_FriendList
    if not (FL and FL.GetNumWhoResults and FL.GetWhoInfo) then return end
    for i = 1, FL.GetNumWhoResults() do
        local info = FL.GetWhoInfo(i)
        if info then ns.RememberLevel(info.fullName, info.level) end
    end
end

---------------------------------------------------------------------------
-- Start und Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
    "UNIT_LEVEL", "PLAYER_LEVEL_UP", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "WHO_LIST_UPDATE",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", ns.Safe(T("Ereignis", "Event"), function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then ns.GetDB() end
    elseif event == "PLAYER_LOGIN" then
        ns.GetDB()
        if ns.SetupMessages then ns.SetupMessages() end
        if ns.SetupSkin then ns.SetupSkin() end
        if ns.SetupOptions then ns.SetupOptions() end
        ScanGroup()
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_LEVEL_UP" then
        ScanGroup()
    elseif event == "UNIT_LEVEL" then
        if arg1 then RememberUnit(arg1) end
    elseif event == "GUILD_ROSTER_UPDATE" then
        ScanGuild()
    elseif event == "FRIENDLIST_UPDATE" then
        ScanFriends()
    elseif event == "WHO_LIST_UPDATE" then
        ScanWho()
    elseif event == "PLAYER_TARGET_CHANGED" then
        RememberUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        RememberUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if arg1 then RememberUnit(arg1) end
    end
end))

---------------------------------------------------------------------------
-- Chatbefehl
---------------------------------------------------------------------------
SLASH_FOREVERCHAT1 = "/fchat"
SLASH_FOREVERCHAT2 = "/foreverchat"
SlashCmdList["FOREVERCHAT"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "copy" or msg == "kopieren" then
        if ns.ShowCopyChat then ns.ShowCopyChat() end
    elseif msg == "lock" or msg == "move" then
        if ns.SetLocked then ns.SetLocked(not ns.GetDB().locked) end
    else
        if ns.ToggleOptions then ns.ToggleOptions() end
    end
end
