-- ForeverChat – Messages.lua: Namen und Nachrichten ueber Blizzards OFFIZIELLE Filter veraendern.
-- ChatFrameUtil.AddSenderNameFilter / AddMessageEventFilter laufen im Forever-Client abgesichert: sind die
-- Werte gesperrt (Kampf in Instanzen), ueberspringt Blizzard unsere Filter von selbst – die Nachricht kommt
-- dann einfach unveraendert. Wir ersetzen keine Blizzard-Funktion.
local ADDON_NAME, ns = ...
local T = ns.T

local LEVEL_COLOR = "|cff8a8a8a"   -- dezentes Grau fuer die Stufe
local URL_COLOR = "|cff7fb4ff"     -- dezentes Blau fuer Webadressen
local MENTION_MARK = "|cffffd100»|r " -- goldener Pfeil vor Nachrichten, die dich erwaehnen

---------------------------------------------------------------------------
-- Absendername: Klassenfarbe und Stufe (steht in der Chatzeile innerhalb der eckigen Klammern)
---------------------------------------------------------------------------
local function SenderFilter(event, decorated, text, senderName, languageName, channelName, playerName2,
                            specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, senderGUID)
    if type(decorated) ~= "string" then return nil end
    local db = ns.GetDB()
    local out = decorated

    -- Klassenfarbe selbst setzen (statt Blizzards Einstellung "chatClassColorOverride" zu aendern);
    -- ist der Name schon eingefaerbt (Blizzard-Einstellung, Discord), bleibt es dabei
    if db.classColors and senderGUID and _G.GetPlayerInfoByGUID and not out:find("|c", 1, true) then
        local _, class = _G.GetPlayerInfoByGUID(senderGUID)
        local color = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
        if color and color.WrapTextInColorCode then out = color:WrapTextInColorCode(out) end
    end

    if db.showLevel then
        local level = ns.LevelOf(senderName, senderGUID)
        if level and not (db.hideMaxLevel and level >= ns.MaxLevel()) then
            out = LEVEL_COLOR .. level .. "|r " .. out
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Webadressen: als Addon-Link einfaerben; Klick oeffnet ein Feld zum Kopieren (Copy.lua).
-- Blizzard meldet Klicks auf "addon:"-Links ueber EventRegistry "SetItemRef" (ohne eigenen Link-Typ).
---------------------------------------------------------------------------
ns.urls = {}
local URL_KEEP = 200
local urlCount = 0

local function StoreUrl(url)
    urlCount = urlCount + 1
    ns.urls[urlCount] = url
    ns.urls[urlCount - URL_KEEP] = nil
    return urlCount
end

local function LinkUrl(url)
    local id = StoreUrl(url)
    return URL_COLOR .. "|Haddon:" .. ADDON_NAME .. ":url:" .. id .. "|h[" .. url:gsub("|", "||") .. "]|h|r"
end

local URL_PATTERNS = {
    "%f[%w]https?://[^%s|]+",
    "%f[%w]www%.[%w%-]+%.[^%s|]+",
}

local function ReplaceUrls(msg)
    -- Nachrichten mit Links (Gegenstaende, Erfolge …) nicht anfassen, damit kein Link zerbricht
    if msg:find("|H", 1, true) then return msg, false end
    local changed = false
    for _, pattern in ipairs(URL_PATTERNS) do
        local new, n = msg:gsub(pattern, LinkUrl)
        if n > 0 then msg, changed = new, true end
    end
    return msg, changed
end

---------------------------------------------------------------------------
-- Erwaehnung: dein Name in einer fremden Nachricht
---------------------------------------------------------------------------
local myNames
local function MyNames()
    if myNames then return myNames end
    local name = UnitName("player")
    if not name or not ns.CanRead(name) then return {} end
    myNames = { name:lower() }
    local first = name:match("^(%S+)%s")
    if first then myNames[2] = first:lower() end -- Forever: auch der Vorname allein
    return myNames
end

local lastSound = 0
local function MentionsMe(msg, author)
    local me = UnitName("player")
    if type(author) == "string" and me and Ambiguate and Ambiguate(author, "none") == me then return false end
    local lower = msg:lower()
    for _, n in ipairs(MyNames()) do
        if #n >= 3 and lower:find("%f[%w]" .. n:gsub("%p", "%%%0") .. "%f[%W]") then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Nachrichtenfilter
---------------------------------------------------------------------------
local function ShortChannel(name, mode)
    if type(name) ~= "string" or name == "" or mode == "FULL" then return name end
    if mode == "NUMBER" then return name:match("^(%d+)%.") or name end
    return (name:gsub("%s%-%s.*$", "")) -- "2. Handel - Stadt" -> "2. Handel"
end

local MENTION_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true, CHAT_MSG_CHANNEL = true,
}

local function MessageFilter(chatFrame, event, msg, ...)
    if type(msg) ~= "string" then return false end
    local db = ns.GetDB()
    -- Messenger an und "auch im Hauptchat" aus: Fluestern nur im IM-Reiter zeigen. Dieser Filter laeuft (wie das
    -- Einsammeln im Messenger) nur bei lesbaren Werten – gesperrte Fluesternachrichten bleiben im Hauptchat.
    if db.messenger and not db.whispersInMain and ns.WHISPER_EVENTS and ns.WHISPER_EVENTS[event] then
        return true
    end
    local changed = false
    local n = select("#", ...)
    local args = { ... } -- arg2 … arg14 (Absender, Sprache, Kanal, …)

    if db.urls then
        local new, did = ReplaceUrls(msg)
        if did then msg, changed = new, true end
    end

    if db.mention and MENTION_EVENTS[event] and MentionsMe(msg, args[1]) then
        msg, changed = MENTION_MARK .. msg, true
        if db.mentionSound and GetTime() - lastSound > 2 and SOUNDKIT then
            lastSound = GetTime()
            PlaySound(SOUNDKIT.TELL_MESSAGE or 3081, "Master")
        end
    end

    if event == "CHAT_MSG_CHANNEL" and db.channelNames ~= "FULL" then
        local short = ShortChannel(args[3], db.channelNames)
        if short ~= args[3] then args[3], changed = short, true end
    end

    if not changed then return false end -- nichts geaendert: Blizzard nimmt die Originalwerte
    return false, msg, unpack(args, 1, n)
end

local FILTER_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

---------------------------------------------------------------------------
-- Einrichten
---------------------------------------------------------------------------
function ns.SetupMessages()
    local CFU = _G.ChatFrameUtil
    if CFU and CFU.AddSenderNameFilter then
        CFU.AddSenderNameFilter(SenderFilter)
    end
    if CFU and CFU.AddMessageEventFilter then
        for _, event in ipairs(FILTER_EVENTS) do CFU.AddMessageEventFilter(event, MessageFilter) end
    elseif _G.ChatFrame_AddMessageEventFilter then
        for _, event in ipairs(FILTER_EVENTS) do _G.ChatFrame_AddMessageEventFilter(event, MessageFilter) end
    end

    -- Klick auf einen unserer Links (Webadresse)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link)
            if type(link) ~= "string" then return end
            local id = link:match("^addon:" .. ADDON_NAME .. ":url:(%d+)")
            local url = id and ns.urls[tonumber(id)]
            if url and ns.ShowCopyText then
                ns.ShowCopyText(T("Webadresse kopieren", "Copy web address"), url, true)
            end
        end, ns)
    end
end
