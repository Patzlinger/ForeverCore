-- ForeverXP: minimalistische XP-Anzeige (mit Ruf-Leiste, siehe Reputation.lua)
local ADDON_NAME, ns = ...
ns.xp = {} -- Schnittstelle fuer Reputation.lua (am Ende dieser Datei gefuellt)
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
local T = UI.T

local WINDOW = 30 * 60    -- XP/Stunde wird ueber die letzten 30 Minuten gemittelt
local MIN_SPAN = 5 * 60   -- direkt nach dem Login mindestens durch 5 Minuten teilen
local REFRESH = 5         -- Anzeige alle 5 Sekunden aktualisieren
local COMBAT_ALPHA = 0.3  -- Sichtbarkeit im Kampf (0 = unsichtbar, 1 = voll sichtbar)
local AVERAGE_OF = 5      -- Kills/Quests bis Level-Up: Schnitt der letzten 5
local HISTORY_SIZE = 10   -- so viele vergangene Level merken

---------------------------------------------------------------------------
-- Gespeicherte Daten
---------------------------------------------------------------------------
-- ForeverXPDB     (account-weit): Position, Sperre, Ein/Aus, Kompakt-Modus
-- ForeverXPCharDB (pro Charakter): Spielzeit pro Level
-- Wegen des Beta-Bugs wird bei jedem Zugriff neu geprueft, ob die Daten da sind.
local DEFAULTS = {
    style = "bar",         -- "bar": Querbalken im Blizzard-Stil (Details bei Mouse-over) | "box": Kasten mit Zeilen
    locked = true,
    combatFade = false,    -- im Kampf durchsichtig (standardmaessig aus: Anzeige bleibt voll sichtbar)
    barAuto = false,       -- an Blizzards Platz, Laenge automatisch (aus = eigene Position und Groesse); folgt barPlace
    barPlace = "TOP",      -- "BLIZZARD" (an Blizzards Platz), "TOP" (oben mittig), "BOTTOM" (unten mittig), "FREE" (frei)
    barWidth = 1192,       -- eigene Breite (px)
    barHeight = 18,        -- eigene Hoehe inkl. Rand (px)
    barHeightScale = 85,   -- an Blizzards Platz: Hoehe in % von Blizzards Leiste
    barTexts = true,       -- Infos an den Enden (Stufe, Mobs, Quests, Tempo, Level-Up)
    barTicks = true,       -- Zehntel-Striche wie bei Blizzard
    hideBlizzard = true,   -- Blizzards Erfahrungs- und Rufleiste unsichtbar machen (Ruf nur mit eigener Ruf-Leiste)
    repShow = true,        -- Ruf-Leiste (beobachteter Ruf) neben dem Balken, siehe Reputation.lua
    repHeightScale = 70,   -- Hoehe der Ruf-Leiste in % der Erfahrungsleiste
    texture = "blizzard",  -- Balken-Textur
    font = "friz",         -- Schrift
    fontSize = 11,
    fontOutline = "",      -- "" | "OUTLINE" | "THICKOUTLINE" (Schatten gibt es immer)
    gridShow = true, gridSize = 32, snap = true,
}

---------------------------------------------------------------------------
-- Texturen und Schriften (wie in den anderen Forever-Addons; weitere ueber LibSharedMedia)
---------------------------------------------------------------------------
local TEXTURES = {
    { key = "blizzard", label = "Blizzard",               path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "raid",     label = T("Raid (Blizzard)", "Raid (Blizzard)"), path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "flat",     label = T("Flach", "Flat"),       path = "Interface\\Buttons\\WHITE8x8" },
    { key = "gradient", label = T("Verlauf", "Gradient"), path = "Interface\\Buttons\\GreyscaleRamp64" },
    { key = "tooltip",  label = T("Weich (Tooltip)", "Soft (tooltip)"), path = "Interface\\Tooltips\\UI-Tooltip-Background" },
}
local FONTS = {
    { key = "friz",   label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn", label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "2002",   label = "2002",          path = "Fonts\\2002.TTF" },
    { key = "2002b",  label = T("2002 Fett", "2002 Bold"), path = "Fonts\\2002B.TTF" },
}
local OUTLINES = {
    { key = "",             label = T("Ohne (mit Schatten)", "None (with shadow)") },
    { key = "OUTLINE",      label = T("Umriss", "Outline") },
    { key = "THICKOUTLINE", label = T("Dicker Umriss", "Thick outline") },
}
local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function WithSharedMedia(list, mediaType)
    local out, seen = {}, {}
    for _, e in ipairs(list) do out[#out + 1] = e seen[e.label] = true end
    local lsm = SharedMedia()
    if lsm then
        for _, name in ipairs(lsm:List(mediaType)) do
            if not seen[name] then out[#out + 1] = { key = "lsm:" .. name, label = name } end
        end
    end
    return out
end
local function MediaPath(key, list, mediaType)
    if type(key) == "string" and key:sub(1, 4) == "lsm:" then
        local lsm = SharedMedia()
        local path = lsm and lsm:Fetch(mediaType, key:sub(5), true)
        if path then return path end
    end
    for _, e in ipairs(list) do
        if e.key == key then return e.path end
    end
    return list[1].path
end

local db
local function GetDB()
    if type(_G.ForeverXPDB) ~= "table" then
        _G.ForeverXPDB = db or {}
    end
    db = _G.ForeverXPDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local function IsBar() return GetDB().style ~= "box" end

local charDB
local function GetCharDB()
    if type(_G.ForeverXPCharDB) ~= "table" then
        _G.ForeverXPCharDB = charDB or {}
    end
    charDB = _G.ForeverXPCharDB
    charDB.history = charDB.history or {}
    return charDB
end

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
local function Num(n)
    n = math.floor(n + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function FormatTime(sec)
    sec = math.floor(sec)
    if sec < 60 then return T("< 1 Min", "< 1 min") end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format(T("%d Std %d Min", "%d h %d min"), h, m) end
    return string.format(T("%d Min", "%d min"), m)
end

local function AtMaxLevel()
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    if IsPlayerAtEffectiveMaxLevel then return IsPlayerAtEffectiveMaxLevel() end
    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    return maxLevel ~= nil and UnitLevel("player") >= maxLevel
end

local function IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

local function Chat(text)
    UI.Chat("ForeverXP", text)
end

---------------------------------------------------------------------------
-- XP-Verlauf: XP/Stunde und Herkunft (Quest / Mob / Sonstiges)
---------------------------------------------------------------------------
local gains = {}          -- { t = Zeitpunkt, xp = Menge, source = Herkunft }
local sessionStart = GetTime()
local sessionXP = 0
local sourceXP = { quest = 0, mob = 0, other = 0 }
local recentKills, recentQuests = {}, {}
local lastXP, lastMax, lastLevel
local lastGain, pendingSource
local MATCH_WINDOW = 1.5  -- Sekunden, in denen XP und Kill-/Quest-Meldung zusammengehoeren

local function PushRecent(list, amount)
    list[#list + 1] = amount
    if #list > AVERAGE_OF then table.remove(list, 1) end
end

local function Average(list)
    if #list == 0 then return nil end
    local sum = 0
    for _, v in ipairs(list) do sum = sum + v end
    return sum / #list
end

local function AssignSource(gain, source)
    sourceXP[gain.source] = sourceXP[gain.source] - gain.xp
    gain.source = source
    sourceXP[source] = sourceXP[source] + gain.xp
    if source == "mob" then
        PushRecent(recentKills, gain.xp)
    elseif source == "quest" then
        PushRecent(recentQuests, gain.xp)
    end
end

-- Kill- oder Quest-Meldung kam an: dem passenden XP-Gewinn zuordnen.
-- Die Reihenfolge der Events ist nicht garantiert, daher geht es in beide Richtungen.
local function NoteSource(source)
    local now = GetTime()
    if lastGain and lastGain.source == "other" and now - lastGain.t < MATCH_WINDOW then
        AssignSource(lastGain, source)
        lastGain = nil
    else
        pendingSource = { source = source, t = now }
    end
end

local function TrackXP()
    local xp, maxXP, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if IsSecret(xp, maxXP, level) then return end
    if lastXP then
        local delta
        if level > lastLevel then
            delta = (lastMax - lastXP) + xp -- Rest des alten Levels + neues Level
        else
            delta = xp - lastXP
        end
        if delta > 0 then
            local now = GetTime()
            local gain = { t = now, xp = delta, source = "other" }
            gains[#gains + 1] = gain
            sessionXP = sessionXP + delta
            sourceXP.other = sourceXP.other + delta
            lastGain = gain
            if pendingSource and now - pendingSource.t < MATCH_WINDOW then
                AssignSource(gain, pendingSource.source)
                lastGain = nil
            end
            pendingSource = nil
        end
    end
    lastXP, lastMax, lastLevel = xp, maxXP, level
end

local function GetRate()
    local now = GetTime()
    while gains[1] and now - gains[1].t > WINDOW do
        table.remove(gains, 1)
    end
    local sum = 0
    for _, g in ipairs(gains) do sum = sum + g.xp end
    if sum == 0 then return 0 end
    local span = math.max(MIN_SPAN, math.min(WINDOW, now - sessionStart))
    return sum / span * 3600
end

local function ResetRate()
    wipe(gains)
    wipe(recentKills)
    wipe(recentQuests)
    sessionStart = GetTime()
    sessionXP = 0
    sourceXP.quest, sourceXP.mob, sourceXP.other = 0, 0, 0
    lastGain, pendingSource = nil, nil
end

-- Erkennt Kill-Meldungen wie "Kobold stirbt, Ihr bekommt 45 Erfahrung."
-- Das Muster wird aus dem Text des Spiels gebaut, passt also zur Client-Sprache.
local killPattern
do
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON
    local prefix = fmt and fmt:match("^(.-)%%%d?%$?d")
    if prefix and (prefix:find("%%s") or prefix:find("%%%d%$s")) then
        prefix = prefix:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
        prefix = prefix:gsub("%%%%%d%%%$s", ".+"):gsub("%%%%s", ".+")
        killPattern = "^" .. prefix
    end
end

---------------------------------------------------------------------------
-- Spielzeit pro Level (pro Charakter gespeichert)
---------------------------------------------------------------------------
local lastTick = GetTime()

local function TickLevelTime()
    local now = GetTime()
    local elapsed = now - lastTick
    lastTick = now
    local level = UnitLevel("player")
    if IsSecret(level) then return end
    local c = GetCharDB()
    -- Neues Level ohne mitgezaehlten Level-Up (z. B. Daten fehlen): Zeit ist unvollstaendig
    if not c.current or level > c.current.level then
        c.current = { level = level, seconds = 0, complete = false }
    end
    if c.current.level == level then
        c.current.seconds = c.current.seconds + elapsed
    end
end

local function OnLevelUp(newLevel)
    -- Zeit direkt dem alten Level gutschreiben (UnitLevel kann hier schon das neue Level liefern)
    local now = GetTime()
    local c = GetCharDB()
    local cur = c.current
    if cur and cur.level == newLevel - 1 then
        cur.seconds = cur.seconds + (now - lastTick)
        table.insert(c.history, 1, { level = cur.level, seconds = cur.seconds, complete = cur.complete })
        while #c.history > HISTORY_SIZE do table.remove(c.history) end
    end
    lastTick = now
    c.current = { level = newLevel, seconds = 0, complete = true }
end

---------------------------------------------------------------------------
-- XP aus fertigen Quests im Questlog
---------------------------------------------------------------------------
local questXP, questCount = 0, 0

local function UpdateQuestXP()
    local total, count = 0, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 then
            local ready = C_QuestLog.IsComplete(id)
                or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id))
            if ready then
                local xp = GetQuestLogRewardXP(id) or 0
                if xp > 0 then
                    total = total + xp
                    count = count + 1
                end
            end
        end
    end
    questXP, questCount = total, count
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------
-- Anzeige-Look wie alle Forever-Anzeigen (dunkel, schlanker Rand); die Titelleiste ist
-- ein eigenes Teil, damit sie getrennt ein- und ausgeblendet werden kann.
local frame = CreateFrame("Frame", "ForeverXPFrame", UIParent, "BackdropTemplate")
frame:SetSize(320, 70)
frame:SetPoint("TOP", 0, -120)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
UI.Hud(frame)

-- Titelleiste: sitzt oben auf dem Fenster, nur bei Mouse-over sichtbar
local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
titleBar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, -1)
titleBar:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -1)
titleBar:SetHeight(22)
UI.Hud(titleBar, 0.95)
titleBar:SetBackdropColor(0.1, 0.1, 0.13, 0.95)
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetAlpha(0)

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("LEFT", 8, 0)
titleText:SetText("ForeverXP")

-- Das X oben rechts blendet die Anzeige aus (merkt sich das auch)
local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
closeBtn:SetSize(18, 18)
closeBtn:SetPoint("RIGHT", 0, 0)
closeBtn:SetScript("OnClick", function()
    GetDB().hidden = true
    frame:Hide()
end)

local line1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
line1:SetPoint("TOPLEFT", 14, -10)
line1:SetPoint("TOPRIGHT", -14, -10)
line1:SetJustifyH("LEFT")

-- Rahmen um den Balken (gleicher Innenrahmen wie in allen Forever-Fenstern)
local barFrame = UI.Box(frame, 0.6)
barFrame:SetPoint("TOPLEFT", 10, -26)
barFrame:SetPoint("TOPRIGHT", -10, -26)
barFrame:SetHeight(18)

-- Balken: unten Erholung (blau), darueber fertige Quests (gold), oben aktuelle XP (lila)
local function MakeBar(r, g, b, a, level)
    local bar = CreateFrame("StatusBar", nil, barFrame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(r, g, b, a)
    bar:SetFrameLevel(barFrame:GetFrameLevel() + level)
    return bar
end

local restedBar = MakeBar(0.2, 0.5, 1, 0.45, 1)
local questBar = MakeBar(1, 0.8, 0.1, 0.7, 2)
local xpBar = MakeBar(0.6, 0.2, 0.9, 1, 3)

-- Detailzeilen unter dem Balken (werden je nach Inhalt ein-/ausgeblendet)
local function MakeLine(r, g, b)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

local lineInfo = MakeLine()               -- Noch / XP/h / Level-Up
local lineEstimate = MakeLine(0.8, 0.8, 1) -- Kills / Quests bis Level-Up
local lineQuests = MakeLine(1, 0.82, 0)    -- fertige Quests im Log

local function LayoutLines(lines)
    local y = -52
    for _, fs in ipairs({ lineInfo, lineEstimate, lineQuests }) do
        fs:Hide()
    end
    for _, fs in ipairs(lines) do
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 14, y)
        fs:SetPoint("TOPRIGHT", -14, y)
        fs:Show()
        y = y - 14
    end
    frame:SetHeight(#lines > 0 and (56 + 14 * #lines) or 54)
end

---------------------------------------------------------------------------
-- Querbalken im Blizzard-Stil: schmal, Zehntel-Striche, gleiche Farben wie der Kasten.
-- Maus drueber: XP-Zahl auf dem Balken (wie bei Blizzard) und der Kasten mit allen Infos.
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "ForeverXPBar", UIParent, "BackdropTemplate")
bar:SetSize(1024, 12)
bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4)
bar:SetMovable(true)
bar:SetClampedToScreen(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetFrameStrata("MEDIUM")
bar:SetFrameLevel(20)
-- abgerundeter Rand wie bei Blizzard (Tooltip-Rahmen), dezent golden eingefaerbt; Fuellung innen
local GOLD_EDGE = { 0.85, 0.7, 0.35, 0.9 }
bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
bar:SetBackdropColor(0.04, 0.04, 0.05, 1) -- deckend wie Blizzards Leiste
bar:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], GOLD_EDGE[4])
local INSET = 3
local inner = CreateFrame("Frame", nil, bar) -- Bereich innerhalb des Rands
inner:SetPoint("TOPLEFT", INSET, -INSET)
inner:SetPoint("BOTTOMRIGHT", -INSET, INSET)
bar:Hide()
if UI.AddMover then UI.AddMover(bar) end

local function MakeLongBar(r, g, b, a, level)
    local s = CreateFrame("StatusBar", nil, bar)
    s:SetAllPoints(inner)
    s:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    s:SetStatusBarColor(r, g, b, a)
    s:SetFrameLevel(bar:GetFrameLevel() + level)
    return s
end
local barRested = MakeLongBar(0.2, 0.5, 1, 0.6, 1)
local barQuest = MakeLongBar(1, 0.8, 0.1, 0.8, 2)
local barXP = MakeLongBar(0.6, 0.2, 0.9, 1, 3)

-- Zehntel-Striche ueber der Fuellung, Texte noch darueber (Striche schneiden nicht in die Schrift)
local tickLayer = CreateFrame("Frame", nil, bar)
tickLayer:SetAllPoints(inner)
tickLayer:SetFrameLevel(bar:GetFrameLevel() + 5)
local barTop = CreateFrame("Frame", nil, bar)
barTop:SetAllPoints(inner)
barTop:SetFrameLevel(bar:GetFrameLevel() + 7)
local ticks = {}
for i = 1, 9 do
    local t = tickLayer:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0, 0, 0, 0.75)
    t:SetWidth(1)
    ticks[i] = t
end

local function BarFont(fs)
    local font = _G.TextStatusBarText or _G.NumberFontNormalSmall
    if font then fs:SetFontObject(font) else fs:SetFontObject("GameFontHighlightSmall") end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetWordWrap(false)
end
local barCenter = barTop:CreateFontString(nil, "OVERLAY")
BarFont(barCenter)
barCenter:SetPoint("CENTER", 0, 0)
local barLeft = barTop:CreateFontString(nil, "OVERLAY")
BarFont(barLeft)
barLeft:SetPoint("LEFT", 6, 0)
barLeft:SetJustifyH("LEFT")
local barRight = barTop:CreateFontString(nil, "OVERLAY")
BarFont(barRight)
barRight:SetPoint("RIGHT", -6, 0)
barRight:SetJustifyH("RIGHT")
local barLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
barLabel:SetPoint("BOTTOM", bar, "TOP", 0, 3)
barLabel:SetText(T("ForeverXP – ziehen", "ForeverXP – drag"))
barLabel:Hide()

-- Blizzards Erfahrungsleiste: bleibt an ihrem Platz (sonst ruecken die Aktionsleisten nach),
-- wird nur unsichtbar – unser Balken legt sich genau darueber. Je nach Spielversion heisst sie anders.
local BLIZZ_BARS = { "MainMenuExpBar", "MainStatusTrackingBarContainer", "StatusTrackingBarManager" }
local blizzBar -- die gefundene Blizzard-Leiste, ueber der unser Balken liegt
local function Overlaying()
    return blizzBar ~= nil and IsBar() and GetDB().barPlace == "BLIZZARD"
end

-- Striche passend zur tatsaechlichen Breite (die Breite kann von Blizzards Leiste kommen)
local function PlaceTicks()
    local w = inner:GetWidth()
    local show = GetDB().barTicks and w and w > 0
    for i, t in ipairs(ticks) do
        t:ClearAllPoints()
        if show then
            t:SetPoint("TOP", tickLayer, "TOPLEFT", w * i / 10, 0)
            t:SetPoint("BOTTOM", tickLayer, "BOTTOMLEFT", w * i / 10, 0)
        end
        t:SetShown(show and true or false)
    end
end
local ApplyLook -- weiter unten
bar:SetScript("OnSizeChanged", function()
    PlaceTicks()
    if ApplyLook then ApplyLook() end
end)

-- Position: an Blizzards Platz, oben mittig, unten mittig – oder frei (Mitte relativ zur Bildschirmmitte)
local function RestoreBarPosition()
    local d = GetDB()
    local pos = d.barPos
    bar:ClearAllPoints()
    if Overlaying() then
        bar:SetPoint("CENTER", blizzBar, "CENTER", 0, 0)
    elseif d.barPlace == "TOP" then
        bar:SetPoint("TOP", UIParent, "TOP", 0, -6)
    elseif d.barPlace == "BOTTOM" then
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4)
    elseif pos then
        bar:SetPoint("CENTER", UIParent, "CENTER", pos[1], pos[2])
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4)
    end
end

-- Textur und Schrift aus den Einstellungen (Balken und Kasten). Die Schrift wird bei flachem
-- Balken automatisch kleiner, damit sie nicht ueber den Rand hinausragt.
-- Texte in drei gleich breiten Zonen (links, Mitte, rechts). Je Zone mehrere Fassungen von lang
-- nach kurz: genommen wird die erste, die hineinpasst – sonst bleibt die Zone leer (nichts wird abgeschnitten).
-- Ruhezustand = kurze Fassungen, Maus drueber = ausfuehrliche.
local barTextParts = {} -- je Zone: { rest = { ... }, hover = { ... } }
local barHovered = false
local function PickText(fs, variants, width)
    for _, v in ipairs(variants or {}) do
        if v and v ~= "" then
            fs:SetText(v)
            if fs:GetStringWidth() <= width then
                fs:Show()
                return
            end
        end
    end
    fs:SetText("")
    fs:Hide()
end
local function FitTexts()
    local d = GetDB()
    local avail = inner:GetWidth() or 0
    if avail <= 0 then return end
    local zone = avail / 3
    if (inner:GetHeight() or 0) < 6 then
        barLeft:Hide() barCenter:Hide() barRight:Hide()
        return
    end
    local mode = barHovered and "hover" or "rest"
    local function V(key) local z = barTextParts[key] return z and z[mode] end
    PickText(barCenter, V("center"), zone - 8)
    if d.barTexts then
        PickText(barLeft, V("left"), zone - 12)
        PickText(barRight, V("right"), zone - 12)
    else
        barLeft:Hide()
        barRight:Hide()
    end
end

function ApplyLook()
    local d = GetDB()
    local tex = MediaPath(d.texture, TEXTURES, "statusbar")
    for _, s in ipairs({ barRested, barQuest, barXP, restedBar, questBar, xpBar }) do s:SetStatusBarTexture(tex) end
    local font = MediaPath(d.font, FONTS, "font")
    local innerH = (bar:GetHeight() or 16) - 2 * INSET
    local size = math.max(7, math.min(d.fontSize, math.floor(innerH + 4)))
    for _, fs in ipairs({ barCenter, barLeft, barRight }) do
        fs:SetFont(font, size, d.fontOutline or "")
    end
    -- Kasten: gleiche Schrift, Groessen wie frueher (Kopfzeile etwas groesser)
    line1:SetFont(font, d.fontSize + 1, d.fontOutline or "")
    for _, fs in ipairs({ lineInfo, lineEstimate, lineQuests }) do fs:SetFont(font, math.max(8, d.fontSize - 1), d.fontOutline or "") end
    FitTexts()
end

-- Groesse, Texte und Verschiebe-Optik aus den Einstellungen
local function LayoutBar()
    local d = GetDB()
    if Overlaying() then
        -- volle Laenge wie Blizzards Leiste; Hoehe: Anteil davon plus Rand (bei 2 Leisten: eigene Hoehe)
        local h = blizzBar:GetHeight() or 0
        local s = blizzBar:GetEffectiveScale() / bar:GetEffectiveScale()
        local height = (h > 8 and h <= 20) and ((h * s + 4) * (d.barHeightScale or 85) / 100) or d.barHeight
        bar:SetSize(math.max(100, blizzBar:GetWidth() * s), math.max(8, math.floor(height + 0.5)))
    else
        local w = math.max(100, math.min(d.barWidth, math.floor(UIParent:GetWidth())))
        bar:SetSize(w, d.barHeight)
    end
    bar:SetFrameStrata(Overlaying() and "HIGH" or "MEDIUM")
    PlaceTicks()
    ApplyLook()
    if d.locked then
        bar:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], GOLD_EDGE[4])
    else
        bar:SetBackdropBorderColor(0.3, 0.6, 1, 1)
    end
    barLabel:SetShown(not d.locked and IsBar())
end

local OnBarMoved -- Einstellungsfenster: X/Y nachziehen
local function SetBarPosition(x, y)
    local d = GetDB()
    if d.barPlace == "BLIZZARD" then
        -- vom Blizzard-Platz geloest: bisherige Groesse als eigene Groesse uebernehmen
        d.barWidth = math.floor(bar:GetWidth() + 0.5)
        d.barHeight = math.floor(bar:GetHeight() + 0.5)
    end
    -- selbst gezogen bzw. X/Y eingegeben: ab jetzt frei
    d.barPlace, d.barAuto = "FREE", false
    d.barPos = { UI.Round(x), UI.Round(y) }
    RestoreBarPosition()
    LayoutBar()
    if OnBarMoved then OnBarMoved() end
end

-- Kasten als Info-Fenster ueber (bzw. unter) dem Balken
local function AnchorPanel()
    frame:ClearAllPoints()
    local _, y = bar:GetCenter()
    if y and y < UIParent:GetHeight() / 2 then
        frame:SetPoint("BOTTOM", bar, "TOP", 0, 6)
    else
        frame:SetPoint("TOP", bar, "BOTTOM", 0, -6)
    end
end

-- Blizzards Leiste unsichtbar machen (nur Durchsichtigkeit – kein Ausblenden, kein "taint"-Risiko
-- wie bei :Hide()). Erfasst werden ALLE bekannten Rahmen (Retail- und Classic-Variante) samt ihren
-- Unterrahmen (die eigentliche Leiste darin kann die Durchsichtigkeit des Rahmens ignorieren).
-- Setzt Blizzard sie wieder sichtbar, wird das gleich zurueckgenommen (UI.HideBlizzard aus dem ForeverHub;
-- ein erneuter Aufruf sammelt spaeter dazugekommene Unterrahmen ein, z. B. wenn man einen Ruf beobachtet).
local function WantHidden() return IsBar() and GetDB().hideBlizzard end

-- Retail/Forever: Blizzard verteilt Erfahrung, Ruf usw. auf zwei Behaelter (Main/Secondary), jeder merkt sich in
-- shownBarIndex, welche Leiste er gerade zeigt. Unsichtbar wird nur der Behaelter mit der Erfahrung – frueher wurde
-- die ganze Verwaltung (StatusTrackingBarManager) samt Rufleiste unsichtbar, dann zeigte ein beobachteter Ruf nichts.
local XP_CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local function ShowsExperience(c)
    local enum = _G.StatusTrackingBarInfo and _G.StatusTrackingBarInfo.BarsEnum
    if not (enum and enum.Experience and c.shownBarIndex ~= nil) then
        return c == _G.MainStatusTrackingBarContainer -- unbekannter Aufbau: wie bisher die Hauptleiste
    end
    return c.shownBarIndex == enum.Experience
end

-- Zeigt der Behaelter gerade den beobachteten Ruf? (den ersetzt die eigene Ruf-Leiste, siehe Reputation.lua)
local function ShowsReputation(c)
    local enum = _G.StatusTrackingBarInfo and _G.StatusTrackingBarInfo.BarsEnum
    if not (enum and enum.Reputation and c.shownBarIndex ~= nil) then
        return c == _G.SecondaryStatusTrackingBarContainer -- unbekannter Aufbau: die zweite Leiste
    end
    return c.shownBarIndex == enum.Reputation
end

-- Unsichtbar machen: den Behaelter mit der Erfahrung (Balken-Modus) und den mit dem Ruf (solange die Ruf-Leiste laeuft)
local function ShouldHide(c)
    local d = GetDB()
    if not d.hideBlizzard then return false end
    return (IsBar() and ShowsExperience(c)) or (ns.repWanted == true and ShowsReputation(c))
end

local HideBlizzardBar
local function HideSplitContainers()
    local target
    for _, name in ipairs(XP_CONTAINERS) do
        local c = _G[name]
        if ShouldHide(c) then
            UI.HideBlizzard(c, { when = function() return ShouldHide(c) end })
        else
            UI.ShowBlizzard(c)
        end
        if ShowsExperience(c) then target = c end
        -- Tauscht Blizzard die Leisten zwischen den Behaeltern (z. B. Ruf beobachten), neu verteilen
        if not c.fxpHooked and c.ApplyPendingBarToShow then
            c.fxpHooked = true
            hooksecurefunc(c, "ApplyPendingBarToShow", function() C_Timer.After(0, HideBlizzardBar) end)
            c:HookScript("OnSizeChanged", function(self) if self == blizzBar and Overlaying() then LayoutBar() end end)
        end
    end
    -- Ziel fuer unseren Balken: der Behaelter mit der Erfahrung (ohne Erfahrung, z. B. Hoechststufe: Hauptleiste)
    blizzBar = target or _G.MainStatusTrackingBarContainer
end

HideBlizzardBar = function()
    if _G.StatusTrackingBarManager and _G.MainStatusTrackingBarContainer and _G.SecondaryStatusTrackingBarContainer then
        HideSplitContainers()
        RestoreBarPosition()
        LayoutBar()
        return
    end
    for _, name in ipairs(BLIZZ_BARS) do
        local f = _G[name]
        if f then
            if WantHidden() then
                UI.HideBlizzard(f, { when = WantHidden })
            else
                UI.ShowBlizzard(f)
            end
            -- Ziel fuer unseren Balken: die erste sichtbare, breite Leiste
            if not blizzBar and f:IsVisible() and (f:GetWidth() or 0) > 100 then
                blizzBar = f
                -- Blizzards Leiste aendert ihre Groesse (z. B. Bearbeitungsmodus): Balken nachziehen
                f:HookScript("OnSizeChanged", function() if Overlaying() then LayoutBar() end end)
            end
        end
    end
    RestoreBarPosition()
    LayoutBar()
end

-- Diagnose: welche Blizzard-Leisten gibt es, und sind sie unsichtbar?
local function BlizzStatus()
    local out = {}
    for _, name in ipairs(BLIZZ_BARS) do
        local f = _G[name]
        if f then
            out[#out + 1] = string.format("%s: shown=%s alpha=%.2f w=%.0f%s", name, tostring(f:IsVisible()),
                f.GetEffectiveAlpha and f:GetEffectiveAlpha() or f:GetAlpha(), f:GetWidth() or 0, f == blizzBar and " <<" or "")
        else
            out[#out + 1] = name .. ": -"
        end
    end
    local n = 0
    for _, name in ipairs(BLIZZ_BARS) do
        local f = _G[name]
        if f and f.fcHideParts then n = n + #f.fcHideParts end
    end
    out[#out + 1] = "parts=" .. n
    return table.concat(out, " | ")
end
-- Aktuelle Werte, damit der Tooltip sie auch im Kompakt-Modus zeigen kann
local stats = {}
local notifiedLevel -- fuer welches Level der "reicht fuers Level-Up"-Hinweis schon kam

local function NotifyQuestsEnough()
    if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
    end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(T("Deine fertigen Quests reichen fürs Level-Up!",
            "Your completed quests are enough for a level-up!"), 1, 0.82, 0)
    end
    Chat(T("Deine fertigen Quests reichen fürs Level-Up – ab zum Questgeber!",
        "Your completed quests are enough for a level-up – off to the quest giver!"))
end

-- Balken-Modus: der Kasten erscheint nur, solange die Maus am Balken oder am Kasten ist
local panelHover = false
local function ApplyShown()
    local d = GetDB()
    if d.hidden then
        frame:Hide()
        bar:Hide()
    elseif IsBar() then
        bar:Show()
        titleBar:Hide()
        frame:Hide()
    else
        bar:Hide()
        titleBar:Show()
        frame:Show()
    end
end

local function UpdateDisplay()
    if AtMaxLevel() then
        frame:Hide()
        bar:Hide()
        return
    end
    local xp, maxXP, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if IsSecret(xp, maxXP, level) then return end
    if not maxXP or maxXP <= 0 then return end
    ApplyShown()

    local missing = maxXP - xp
    local rested = GetXPExhaustion() or 0
    local rate = GetRate()
    local avgKill, avgQuest = Average(recentKills), Average(recentQuests)

    stats.missing = missing
    stats.rate = rate
    stats.eta = rate > 0 and FormatTime(missing / rate * 3600) or "–"
    stats.kills = avgKill and math.ceil(missing / avgKill)
    -- noch keine Kills gezaehlt: grobe Schaetzung fuer Mobs der eigenen Stufe (Classic-Formel 45 + 5 x Stufe)
    stats.killsGuess = not avgKill and math.ceil(missing / (45 + 5 * level)) or nil
    stats.quests = avgQuest and math.ceil(missing / avgQuest)

    line1:SetText(string.format(T("Level %d   %s / %s XP (%.1f %%)", "Level %d   %s / %s XP (%.1f %%)"),
        level, Num(xp), Num(maxXP), xp / maxXP * 100))

    for _, bar in ipairs({ restedBar, questBar, xpBar }) do
        bar:SetMinMaxValues(0, maxXP)
    end
    xpBar:SetValue(xp)
    questBar:SetValue(math.min(maxXP, xp + questXP))
    restedBar:SetValue(math.min(maxXP, xp + rested))

    -- Hinweis, sobald die fertigen Quests fuers Level-Up reichen (einmal pro Level)
    local enough = questXP > 0 and questXP >= missing
    if enough and notifiedLevel ~= level then
        notifiedLevel = level
        NotifyQuestsEnough()
    end

    -- Querbalken: gleiche Werte, kurze Infos an den Enden, XP-Zahl (bei Mouse-over) in der Mitte
    for _, s in ipairs({ barRested, barQuest, barXP }) do s:SetMinMaxValues(0, maxXP) end
    barXP:SetValue(xp)
    barQuest:SetValue(math.min(maxXP, xp + questXP))
    barRested:SetValue(math.min(maxXP, xp + rested))
    -- wie die Zeilen im Kasten: links Stufe/Prozent/Schaetzung, Mitte XP, rechts Tempo und Level-Up
    -- Texte auf dem Balken: je Zone eine dezente (Ruhe) und eine ausfuehrliche Fassung (Maus drueber),
    -- jeweils von lang nach kurz – FitTexts nimmt die erste, die in die Zone passt
    local pct = xp / maxXP * 100
    local pctText = string.format("%.1f %%", pct)
    local xpText = string.format("%s / %s", Num(xp), Num(maxXP))
    local restedText = rested > 0 and ("|cff66a3ff" .. T("erholt ", "rested ") .. Num(rested) .. "|r") or nil
    local mobs = stats.kills and string.format(T("≈ %s Mobs", "≈ %s mobs"), Num(stats.kills))
        or stats.killsGuess and string.format(T("~%s Mobs", "~%s mobs"), Num(stats.killsGuess)) or nil
    local quests = stats.quests and string.format(T("≈ %s Quests", "≈ %s quests"), Num(stats.quests)) or nil
    local eta = rate > 0 and (T("Level-Up in ", "Level-up in ") .. stats.eta) or nil
    local questLong, questShort
    if questXP > 0 then
        if enough then
            questLong = "|cffffd100" .. string.format(T("%d fertige Quests reichen fürs Level-Up!", "%d completed quests are enough to level up!"), questCount) .. "|r"
            questShort = "|cffffd100" .. T("Quests reichen fürs Level-Up!", "Quests: enough to level!") .. "|r"
        else
            questLong = "|cffffd100" .. string.format(T("%d fertige Quests bringen +%s XP", "%d completed quests give +%s XP"), questCount, Num(questXP)) .. "|r"
            questShort = "|cffffd100+" .. Num(questXP) .. T(" XP aus Quests", " XP from quests") .. "|r"
        end
    end
    local function Join(...)
        local out = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if v then out[#out + 1] = v end
        end
        return table.concat(out, "  ·  ")
    end
    local levelText = "Level " .. level
    local rateText = rate > 0 and (Num(rate) .. " XP/h") or nil
    barTextParts.left = {
        rest = { Join(levelText, rateText), levelText },
        hover = { Join(levelText, mobs, quests), Join(levelText, mobs), levelText },
    }
    barTextParts.center = {
        rest = { xpText .. "  (" .. pctText .. ")", xpText, pctText },
        hover = { Join(xpText .. "  (" .. pctText .. ")", T("noch ", "left ") .. Num(missing), restedText),
            Join(xpText .. "  (" .. pctText .. ")", T("noch ", "left ") .. Num(missing)), xpText, pctText },
    }
    barTextParts.right = {
        -- in Ruhe: reichen die Quests, ist das wichtiger als die Zeit
        rest = { Join(eta, questShort), questShort, eta },
        hover = { Join(rate > 0 and (Num(rate) .. " XP/h") or nil, eta, questLong), Join(eta, questShort), questShort or eta },
    }
    FitTexts()

    if GetDB().compact and not IsBar() then
        LayoutLines({})
        return
    end

    local lines = { lineInfo }
    lineInfo:SetText(string.format(T("Noch %s   ·   %s XP/h   ·   Level-Up: %s", "%s left   ·   %s XP/h   ·   Level-up: %s"),
        Num(missing), rate > 0 and Num(rate) or "–", stats.eta))

    if stats.kills or stats.killsGuess or stats.quests then
        local parts = {}
        if stats.kills then parts[#parts + 1] = string.format(T("≈ %s Mobs", "≈ %s mobs"), Num(stats.kills))
        elseif stats.killsGuess then parts[#parts + 1] = string.format(T("~%s Mobs (geschätzt)", "~%s mobs (estimate)"), Num(stats.killsGuess)) end
        if stats.quests then parts[#parts + 1] = "≈ " .. Num(stats.quests) .. " Quests" end
        lineEstimate:SetText(T("Bis Level-Up: ", "Until level-up: ") .. table.concat(parts, T("   oder   ", "   or   ")))
        lines[#lines + 1] = lineEstimate
    end

    if questXP > 0 then
        local suffix = enough and T("  – reicht fürs Level-Up!", "  – enough for a level-up!") or ""
        lineQuests:SetText(string.format(T("%d fertige Quests bringen +%s XP%s", "%d completed quests give +%s XP%s"),
            questCount, Num(questXP), suffix))
        lines[#lines + 1] = lineQuests
    end

    LayoutLines(lines)
end

-- Tooltip mit allen Details
local WHITE = { 1, 1, 1 }
local function AddRow(label, value, color)
    color = color or WHITE
    GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, color[1], color[2], color[3])
end

-- das grosse Info-Fenster (Tooltip) – am Kasten und am Balken
local function ShowDetails(owner, anchor)
    if anchor == "DEFAULT" and GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, owner) -- dort, wo auch sonst Tooltips erscheinen
    else
        GameTooltip:SetOwner(owner, anchor == "DEFAULT" and "ANCHOR_TOP" or anchor)
    end
    GameTooltip:AddLine("ForeverXP")
    if questXP > 0 then
        AddRow(string.format(T("Fertige Quests (%d):", "Completed quests (%d):"), questCount), "+" .. Num(questXP) .. " XP", { 1, 0.82, 0 })
    end

    if stats.missing then
        AddRow(T("Noch bis Level-Up:", "Left until level-up:"), Num(stats.missing) .. " XP")
        AddRow(T("XP pro Stunde:", "XP per hour:"), stats.rate > 0 and Num(stats.rate) or "–")
        AddRow(T("Level-Up in:", "Level-up in:"), stats.eta)
        if stats.kills then AddRow(T("Kills bis Level-Up:", "Kills until level-up:"), "≈ " .. Num(stats.kills)) end
        if stats.quests then AddRow(T("Quests bis Level-Up:", "Quests until level-up:"), "≈ " .. Num(stats.quests)) end
    end
    AddRow(T("Erholt:", "Rested:"), Num(GetXPExhaustion() or 0) .. " XP", { 0.4, 0.6, 1 })

    -- Woher kamen die XP in dieser Sitzung?
    GameTooltip:AddLine(" ")
    AddRow(T("XP diese Sitzung:", "XP this session:"), Num(sessionXP))
    AddRow(T("Sitzungsdauer:", "Session length:"), FormatTime(GetTime() - sessionStart))
    if sessionXP > 0 then
        local function Share(v) return string.format("%s (%d %%)", Num(v), v / sessionXP * 100 + 0.5) end
        AddRow(T("   aus Quests:", "   from quests:"), Share(sourceXP.quest))
        AddRow(T("   aus Kills:", "   from kills:"), Share(sourceXP.mob))
        AddRow(T("   Sonstiges:", "   other:"), Share(sourceXP.other))
    end

    -- Spielzeit pro Level
    local c = GetCharDB()
    if c.current then
        GameTooltip:AddLine(" ")
        local prefix = c.current.complete and "" or T("mind. ", "at least ")
        AddRow(T("Zeit auf diesem Level:", "Time on this level:"), prefix .. FormatTime(c.current.seconds))
        for i = 1, math.min(5, #c.history) do
            local h = c.history[i]
            local text = (h.complete and "" or T("mind. ", "at least ")) .. FormatTime(h.seconds)
            AddRow(string.format("   Level %d – %d:", h.level, h.level + 1), text,
                h.complete and WHITE or { 0.6, 0.6, 0.6 })
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(T("XP/h = Durchschnitt der letzten 30 Minuten", "XP/h = average of the last 30 minutes"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(T("Kills/Quests = Schnitt der letzten 5", "Kills/quests = average of the last 5"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(T("Gold = fertige Quests, Blau = Erholungsbonus", "Gold = completed quests, blue = rested bonus"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end
frame:SetScript("OnEnter", function(self) ShowDetails(self, IsBar() and "ANCHOR_RIGHT" or "ANCHOR_BOTTOM") end)
frame:SetScript("OnLeave", GameTooltip_Hide)

-- Verschieben und Position merken
frame:SetScript("OnDragStart", function(self)
    if not GetDB().locked and not IsBar() then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    GetDB().pos = { point, relPoint, x, y }
end)

-- Auch an der Titelleiste kann man das Fenster ziehen
titleBar:SetScript("OnDragStart", function()
    if not GetDB().locked and not IsBar() then frame:StartMoving() end
end)
titleBar:SetScript("OnDragStop", function()
    frame:GetScript("OnDragStop")(frame)
end)

local function RestorePosition()
    if IsBar() then return end -- im Balken-Modus haengt der Kasten am Balken
    local pos = GetDB().pos
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        frame:SetPoint("TOP", 0, -120)
    end
end

---------------------------------------------------------------------------
-- Funktionen fuer Buttons und Slash-Befehl
---------------------------------------------------------------------------
local lockBtn, compactBtn -- werden unten erzeugt

local function UpdateIcons()
    if lockBtn then
        lockBtn:SetNormalTexture(GetDB().locked and "Interface\\Buttons\\LockButton-Locked-Up"
            or "Interface\\Buttons\\LockButton-Unlocked-Up")
    end
    if compactBtn then
        compactBtn:SetNormalTexture(GetDB().compact and "Interface\\Buttons\\UI-PlusButton-Up"
            or "Interface\\Buttons\\UI-MinusButton-Up")
    end
    LayoutBar()
end

local function ToggleLock()
    local d = GetDB()
    d.locked = not d.locked
    UpdateIcons()
    Chat(d.locked and T("Anzeige gesperrt.", "Display locked.")
        or T("Anzeige entsperrt – zum Verschieben ziehen.", "Display unlocked – drag to move."))
end

-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverXP", function() return GetDB().locked end, function(locked)
        GetDB().locked = locked
        UpdateIcons()
    end)
end

local function ToggleCompact()
    local d = GetDB()
    d.compact = not d.compact
    UpdateIcons()
    UpdateDisplay()
end

local function DoReset()
    ResetRate()
    UpdateDisplay()
    Chat(T("XP/h und Sitzungswerte zurückgesetzt.", "XP/h and session values reset."))
end

local function ToggleShown()
    local d = GetDB()
    d.hidden = not d.hidden
    ApplyShown()
    UpdateDisplay()
end

-- Kleine Symbol-Buttons fuer die Titelleiste
local function MakeIconButton(texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, titleBar)
    b:SetSize(16, 16)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(type(tooltip) == "function" and tooltip() or tooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

-- In der Titelleiste von rechts nach links: X, Reset, Schloss, Kompakt
local resetBtn = MakeIconButton("Interface\\Buttons\\UI-RefreshButton", T("XP/h zurücksetzen", "Reset XP/h"), DoReset)
resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)

lockBtn = MakeIconButton("Interface\\Buttons\\LockButton-Unlocked-Up", function()
    return GetDB().locked and T("Anzeige entsperren", "Unlock display") or T("Anzeige sperren", "Lock display")
end, ToggleLock)
lockBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)

compactBtn = MakeIconButton("Interface\\Buttons\\UI-MinusButton-Up", function()
    return GetDB().compact and T("Details einblenden", "Show details") or T("Kompakt-Modus (nur Balken)", "Compact mode (bar only)")
end, ToggleCompact)
compactBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)

---------------------------------------------------------------------------
-- Titelleiste nur bei Mouse-over (sanft ein- und ausblenden)
---------------------------------------------------------------------------
-- Geprueft wird die Mausposition selbst – so flackert nichts, wenn die Maus
-- vom Fenster auf die Titelleiste oder einen Button wechselt.
local TITLE_FADE_SPEED = 5 -- ca. 0,2 s fuer den Uebergang
local hideDelay = 0        -- kurze Gnadenfrist, bevor die Leiste verschwindet

frame:HookScript("OnUpdate", function(_, elapsed)
    local hovered = frame:IsMouseOver() or titleBar:IsMouseOver()
    if hovered then
        hideDelay = 0.4
    else
        hideDelay = math.max(0, hideDelay - elapsed)
    end
    local target = hideDelay > 0 and 1 or 0
    local alpha = titleBar:GetAlpha()
    if alpha ~= target then
        local step = elapsed * TITLE_FADE_SPEED
        if math.abs(target - alpha) <= step then
            titleBar:SetAlpha(target)
        else
            titleBar:SetAlpha(alpha + (target > alpha and step or -step))
        end
    end
end)

---------------------------------------------------------------------------
-- Im Kampf transparent (sanft ein- und ausblenden) – Kasten und Balken gemeinsam
---------------------------------------------------------------------------
local targetAlpha = 1
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
    local current = frame:GetAlpha()
    local step = elapsed * 3 -- etwa eine Drittelsekunde fuer den Uebergang
    local nextAlpha
    if math.abs(current - targetAlpha) <= step then
        nextAlpha = targetAlpha
        self:Hide()
    else
        nextAlpha = current + (targetAlpha > current and step or -step)
    end
    frame:SetAlpha(nextAlpha)
    bar:SetAlpha(nextAlpha)
end)

local function FadeTo(alpha)
    targetAlpha = alpha
    fader:Show()
end

local function UpdateCombatAlpha()
    FadeTo((GetDB().combatFade and InCombatLockdown() and not panelHover) and COMBAT_ALPHA or 1)
end

-- Maus drueber: auch im Kampf kurz voll sichtbar
frame:HookScript("OnEnter", function() FadeTo(1) end)
frame:HookScript("OnLeave", UpdateCombatAlpha)

---------------------------------------------------------------------------
-- Balken: Mouse-over (Kasten aufklappen), Verschieben, Rechtsklick = Einstellungen
---------------------------------------------------------------------------
local ToggleOptions -- weiter unten
local barDragging = false

local function UpdateXPGrid()
    if not UI.Grid then return end
    local d = GetDB()
    local opts = _G.ForeverXPOptions
    local want = IsBar() and d.gridShow and not d.locked and (barDragging or (opts and opts:IsShown()))
    UI.Grid("ForeverXP", want and d.gridSize or nil)
end

local hoverDelay = 0
bar:SetScript("OnUpdate", function(_, elapsed)
    local over = bar:IsMouseOver() or (frame:IsShown() and frame:IsMouseOver())
    if over then
        hoverDelay = 0.3
    else
        hoverDelay = math.max(0, hoverDelay - elapsed)
    end
    local want = bar:IsMouseOver() and not barDragging
    if want ~= panelHover then
        panelHover = want
        barHovered = want
        FitTexts()
        if want then
            ShowDetails(bar, "DEFAULT")
            FadeTo(1)
        else
            if GameTooltip:GetOwner() == bar then GameTooltip:Hide() end
            UpdateCombatAlpha()
        end
    end
end)
bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and ToggleOptions then ToggleOptions() end
end)
bar:SetScript("OnDragStart", function(self)
    local d = GetDB()
    if d.locked or InCombatLockdown() then return end
    self:StartMoving()
    barDragging = true
    UpdateXPGrid()
    if UI.BeginDrag then UI.BeginDrag(self, { snap = d.snap, grid = d.gridShow and d.gridSize or nil }) end
end)
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local dx, dy = 0, 0
    if UI.EndDrag then dx, dy = UI.EndDrag() end
    barDragging = false
    UpdateXPGrid()
    local x, y = UI.CenterOffset(self)
    SetBarPosition(x + dx, y + dy)
end)

---------------------------------------------------------------------------
-- Einstellungsfenster (Aufbau wie in den anderen Forever-Addons: zwei Spalten mit Abschnitten)
---------------------------------------------------------------------------
do
local options = UI.Window("ForeverXPOptions", T("ForeverXP – Einstellungen", "ForeverXP – Settings"), 660, 600)
local controls = {}
local L, R = 18, 346

local function Refresh()
    RestoreBarPosition()
    LayoutBar()
    HideBlizzardBar()
    UpdateDisplay()
    UpdateXPGrid()
    if ns.RepRefresh then ns.RepRefresh() end
end

local function Check(x, y, label, get, set)
    local cb = UI.Check(options, x, y, label, function(checked)
        set(checked)
        Refresh()
    end)
    controls[#controls + 1] = function() cb:SetChecked(get() and true or false) end
    return cb
end
local function KeyCheck(x, y, label, key)
    return Check(x, y, label, function() return GetDB()[key] end, function(v) GetDB()[key] = v end)
end
local function Slider(x, y, label, key, minV, maxV, step, opts)
    local s = UI.Slider(options, x, y, label, minV, maxV, step, function(v)
        GetDB()[key] = v
        Refresh()
    end, opts)
    controls[#controls + 1] = function() s:Load(GetDB()[key]) end
end
-- Auswahlliste: Beschriftung links, Knopf mit Pfeil rechts (wie ForeverUnits/ForeverFrames)
local function Choice(x, y, label, choices, key, after)
    local fs = UI.Text(options, "label", label)
    fs:SetPoint("TOPLEFT", x, y - 4)
    local b = UI.Button(options, "", 170)
    b:SetPoint("TOPLEFT", x + 110, y)
    if UI.AddArrow then UI.AddArrow(b) end
    local function List() return type(choices) == "function" and choices() or choices end
    local function Load()
        local cur, text = GetDB()[key], nil
        for _, c in ipairs(List()) do if c.key == cur then text = c.label end end
        b:SetText(text or tostring(cur or ""))
    end
    local function Pick(k)
        GetDB()[key] = k
        Load()
        if after then after() end
        Refresh()
    end
    b:SetScript("OnClick", function(self)
        local list = List()
        if UI.ChoiceMenu and UI.ChoiceMenu(self, list, function() return GetDB()[key] end, Pick) then return end
        local cur, nextKey = GetDB()[key], list[1].key
        for i, c in ipairs(list) do if c.key == cur then nextKey = (list[i + 1] or list[1]).key end end
        Pick(nextKey)
    end)
    controls[#controls + 1] = Load
end

---------------------------------------------------------------- linke Spalte
UI.Header(options, L, -36, T("Darstellung", "Style"), 312)
Choice(L, -58, T("Anzeige", "Display"), {
    { key = "bar", label = T("Balken (Blizzard-Stil)", "Bar (Blizzard style)") },
    { key = "box", label = T("Kasten (wie früher)", "Box (classic)") },
}, "style", function()
    RestorePosition()
    panelHover = false
    ApplyShown()
end)
Check(L - 4, -88, T("Anzeige einblenden", "Show display"), function() return not GetDB().hidden end,
    function(v) GetDB().hidden = not v ApplyShown() end)
Check(L - 4, -112, T("Gesperrt (entsperrt: ziehen zum Verschieben)", "Locked (unlocked: drag to move)"),
    function() return GetDB().locked end, function(v) GetDB().locked = v UpdateIcons() end)
KeyCheck(L - 4, -136, T("Im Kampf durchsichtig", "Transparent in combat"), "combatFade")

UI.Header(options, L, -176, T("Balken", "Bar"), 312)
Choice(L, -194, T("Position", "Position"), {
    { key = "BLIZZARD", label = T("An Blizzards Platz", "At Blizzard's spot") },
    { key = "TOP", label = T("Oben mittig", "Top center") },
    { key = "BOTTOM", label = T("Unten mittig", "Bottom center") },
    { key = "FREE", label = T("Frei verschiebbar", "Free to move") },
}, "barPlace", function()
    local d = GetDB()
    d.barAuto = d.barPlace == "BLIZZARD"
    if OnBarMoved then OnBarMoved() end
end)
Slider(L + 2, -228, T("Höhe an Blizzards Platz", "Height at Blizzard's spot"), "barHeightScale", 50, 150, 1, { width = 190, unit = " %" })
Slider(L + 2, -268, T("Eigene Breite", "Own width"), "barWidth", 100, 2560, 10, { width = 190, unit = " px" })
Slider(L + 2, -308, T("Eigene Höhe", "Own height"), "barHeight", 8, 48, 1, { width = 190, unit = " px" })
KeyCheck(L - 4, -348, T("Infos an den Enden", "Info at the ends"), "barTexts")
KeyCheck(L - 4, -372, T("Zehntel-Striche", "Tenth markers"), "barTicks")
KeyCheck(L - 4, -396, T("Blizzards Erfahrungs- und Rufleiste ersetzen", "Replace Blizzard's XP and reputation bar"), "hideBlizzard")
UI.Hint(options, L + 2, -420, 300, T("An Blizzards Platz passt sich die Länge an. Oben, unten und frei gelten eigene Breite und Höhe. Ziehen (entsperrt) stellt auf \"Frei\".",
    "At Blizzard's spot the length adapts. Top, bottom and free use your own width and height. Dragging (unlocked) switches to \"Free\"."))

UI.Header(options, L, -466, T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)"), 312)
local function PosGet(i) return function() return select(i, UI.CenterOffset(bar)) end end
local function PosSet(i)
    return function(v)
        local x, y = UI.CenterOffset(bar)
        if i == 1 then x = v else y = v end
        SetBarPosition(x, y)
    end
end
local posX = UI.Number and UI.Number(options, L + 2, -490, "X", PosGet(1), PosSet(1))
local posY = UI.Number and UI.Number(options, L + 150, -490, "Y", PosGet(2), PosSet(2))
OnBarMoved = function()
    if options:IsShown() then
        for _, load in ipairs(controls) do load() end
        if posX then posX:Load() posY:Load() end
    end
end
KeyCheck(L - 4, -520, T("Raster beim Ziehen und hier", "Grid while dragging and here"), "gridShow")
KeyCheck(L - 4, -544, T("Einrasten (Umschalt = aus)", "Snap (Shift = off)"), "snap")

---------------------------------------------------------------- rechte Spalte
UI.Header(options, R, -36, T("Schrift und Textur", "Font and texture"), 296)
Choice(R, -58, T("Textur", "Texture"), function() return WithSharedMedia(TEXTURES, "statusbar") end, "texture")
Choice(R, -88, T("Schrift", "Font"), function() return WithSharedMedia(FONTS, "font") end, "font")
Choice(R, -118, T("Schriftrand", "Font outline"), OUTLINES, "fontOutline")
Slider(R + 2, -150, T("Schriftgröße", "Font size"), "fontSize", 7, 20, 1, { width = 170 })
UI.Hint(options, R + 2, -190, 290, T("Ist der Balken flacher als die Schrift, wird sie dort automatisch kleiner. Was nicht mehr passt, wird ausgeblendet statt abgeschnitten.",
    "If the bar is lower than the font, the font gets smaller there automatically. What no longer fits is hidden instead of cut off."))

UI.Header(options, R, -248, T("Kasten", "Box"), 296)
Check(R - 4, -270, T("Kompakt (nur Balken, Details im Tooltip)", "Compact (bar only, details in tooltip)"),
    function() return GetDB().compact end, function(v) GetDB().compact = v UpdateIcons() end)
UI.Hint(options, R + 2, -296, 290, T("Im Kasten stehen die Infos wie früher in Zeilen.", "The box shows the info in lines, as before."))

UI.Header(options, R, -336, T("Werkzeuge", "Tools"), 296)
local resetPos = UI.Button(options, T("Position zurücksetzen", "Reset position"), 160, function()
    local d = GetDB()
    d.barPos, d.barAuto, d.barPlace = nil, false, "TOP"
    Refresh()
    if OnBarMoved then OnBarMoved() end
end)
resetPos:SetPoint("TOPLEFT", R, -360)
local resetRate = UI.Button(options, T("XP/h zurücksetzen", "Reset XP/h"), 120, function() DoReset() end)
resetRate:SetPoint("LEFT", resetPos, "RIGHT", 6, 0)

options:SetScript("OnShow", function()
    for _, load in ipairs(controls) do load() end
    if posX then posX:Load() posY:Load() end
    UpdateXPGrid()
end)
options:SetScript("OnHide", UpdateXPGrid)

function ToggleOptions() options:SetShown(not options:IsShown()) end

-- fuer Reputation.lua: eigener Abschnitt "Ruf-Leiste" im selben Fenster
ns.optionsApi = { frame = options, R = R, KeyCheck = KeyCheck, Slider = Slider }
end -- Ende Block "Einstellungsfenster"

-- Schnittstelle fuer Reputation.lua (die Ruf-Leiste haengt am Balken und teilt Look, Schrift und Texturen)
ns.xp.bar = bar
ns.xp.GetDB = GetDB
ns.xp.IsBar = IsBar
ns.xp.MediaPath = MediaPath
ns.xp.TEXTURES = TEXTURES
ns.xp.FONTS = FONTS
ns.xp.GOLD_EDGE = GOLD_EDGE
ns.xp.INSET = INSET
ns.xp.Num = Num
ns.xp.FormatTime = FormatTime
ns.xp.IsSecret = IsSecret
ns.xp.BarFont = BarFont
ns.xp.HideBlizzardBar = function() HideBlizzardBar() end
ns.xp.ToggleOptions = function() ToggleOptions() end
ns.xp.Chat = Chat

---------------------------------------------------------------------------
-- Minimap-Button
---------------------------------------------------------------------------
local mmButton = UI.MinimapButton({
    name = "ForeverXPMinimapButton",
    icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
    title = "ForeverXP",
    angle = function() return GetDB().minimapAngle or 160 end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = function(_, button)
        if button == "RightButton" then ToggleLock() else ToggleOptions() end
    end,
    lines = function()
        return {
            T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Anzeige sperren/entsperren", "Right-click: lock/unlock display"),
        }
    end,
})
local UpdateMinimapPosition = mmButton.UpdatePosition

---------------------------------------------------------------------------
-- Events, Timer & Slash-Befehl
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED") -- Kampf beginnt
events:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Kampf endet
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
-- Blizzard-Leiste neu einsammeln, wenn sie sich aendern kann (Ruf beobachten, Bearbeitungsmodus)
pcall(events.RegisterEvent, events, "UPDATE_FACTION")
pcall(events.RegisterEvent, events, "EDIT_MODE_LAYOUTS_UPDATED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "UPDATE_FACTION" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        if not InCombatLockdown() then HideBlizzardBar() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        if GetDB().combatFade and not panelHover then FadeTo(COMBAT_ALPHA) end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        FadeTo(1)
        HideBlizzardBar() -- falls im Kampf eingeloggt
        return
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        LayoutBar()
        return
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- In Instanzen kann der Text im Kampf geheim sein; dann zaehlt es als "Sonstiges"
        if killPattern and type(arg1) == "string" and not IsSecret(arg1) and arg1:match(killPattern) then
            NoteSource("mob")
        end
        return
    elseif event == "QUEST_TURNED_IN" then
        NoteSource("quest")
        return
    elseif event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        RestorePosition()
        RestoreBarPosition()
        UpdateIcons()
        UpdateMinimapPosition()
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        RestorePosition()
        RestoreBarPosition()
        UpdateIcons()
        UpdateMinimapPosition()
        HideBlizzardBar()
        UpdateCombatAlpha() -- z. B. nach /reload mitten im Kampf
        TickLevelTime()
        TrackXP()
        UpdateQuestXP()
    elseif event == "PLAYER_LEVEL_UP" then
        OnLevelUp(arg1)
        if not InCombatLockdown() then HideBlizzardBar() end
    elseif event == "PLAYER_XP_UPDATE" then
        TrackXP()
    elseif event == "QUEST_LOG_UPDATE" then
        UpdateQuestXP()
    end
    UpdateDisplay()
end)

-- Zeitabhaengige Werte (XP/Stunde, Zeit bis Level-Up) laufen ohne Ereignis weiter
C_Timer.NewTicker(REFRESH, function()
    TickLevelTime()
    UpdateDisplay()
end)
-- Blizzard-Leiste zur Sicherheit selten nachpruefen (sonst ueber Ereignisse, siehe oben; vorher alle 5 s)
C_Timer.NewTicker(30, function()
    if not InCombatLockdown() then HideBlizzardBar() end
end)

SLASH_FOREVERXP1 = "/fxp"
SLASH_FOREVERXP2 = "/foreverxp"
SlashCmdList["FOREVERXP"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        DoReset()
    elseif msg == "lock" then
        ToggleLock()
    elseif msg == "kompakt" or msg == "compact" then
        ToggleCompact()
    elseif msg == "show" or msg == "hide" then
        ToggleShown()
    elseif msg == "rep" or msg == "ruf" then
        GetDB().repShow = not GetDB().repShow
        if ns.RepRefresh then ns.RepRefresh() end
        HideBlizzardBar()
        Chat(GetDB().repShow and T("Ruf-Leiste an.", "Reputation bar on.") or T("Ruf-Leiste aus.", "Reputation bar off."))
    elseif msg == "status" then
        -- Hilfe bei der Fehlersuche: wo ist der Balken?
        local d = GetDB()
        local x, y = UI.CenterOffset(bar)
        Chat(string.format("style=%s hidden=%s shown=%s visible=%s pos=%.0f/%.0f size=%.0fx%.0f alpha=%.2f blizz=%s",
            tostring(d.style), tostring(d.hidden), tostring(bar:IsShown()), tostring(bar:IsVisible()), x, y,
            bar:GetWidth(), bar:GetHeight(), bar:GetAlpha(), blizzBar and (blizzBar:GetName() or "?") or "-"))
        Chat(BlizzStatus())
    elseif msg == "bar" or msg == "balken" or msg == "box" or msg == "kasten" then
        GetDB().style = (msg == "box" or msg == "kasten") and "box" or "bar"
        RestorePosition()
        panelHover = false
        LayoutBar()
        HideBlizzardBar()
        UpdateDisplay()
    else
        ToggleOptions()
    end
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = "ForeverXP", sv = "ForeverXPDB", defaults = DEFAULTS, version = 2,
    -- Version 2: statt "An Blizzards Platz" ja/nein eine Auswahl (Blizzard, oben, unten, frei)
    migrate = function(data, from)
        if from < 2 and data.barPlace == nil then
            data.barPlace = (data.barAuto == false) and "FREE" or "BLIZZARD"
        end
    end })
