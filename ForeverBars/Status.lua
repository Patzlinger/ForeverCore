local addonName, ns = ...

-- Erfahrungs- und Ruf-Leiste (früher das Addon ForeverXP, seit 0.44b Teil von ForeverBars).
-- Beide sind Leisten wie die Aktionsleisten: verschiebbar, einrastend, mit Sichtbarkeit/Ausblenden und Profilen.
-- Der Halter (Bars.lua) bestimmt Lage und Größe; hier steckt der Inhalt: Füllung, Striche, Texte an den Enden
-- (Ruhe = kurze Fassung, Maus darüber = ausführlich) und ein Tooltip mit allen Einzelheiten.
-- Blizzards eigene Erfahrungs- und Rufleiste wird unsichtbar gemacht, solange die jeweilige eigene Leiste an ist.

local UI = ForeverHub.UI
local T = UI.T
local Style = ns.Style
local COLOR = Style.COLOR

local WINDOW = 30 * 60      -- pro Stunde wird über die letzten 30 Minuten gemittelt
local MIN_SPAN = 5 * 60     -- direkt nach dem Login mindestens durch 5 Minuten teilen
local REFRESH = 5           -- Anzeige alle 5 Sekunden auffrischen
local AVERAGE_OF = 5        -- Kills/Quests bis Level-Up: Schnitt der letzten 5
local HISTORY_SIZE = 10     -- so viele vergangene Level merken
local MATCH_WINDOW = 1.5    -- Sekunden, in denen XP und Kill-/Quest-Meldung zusammengehören
local FLAT = "Interface\\Buttons\\WHITE8x8"
local INSET = 2                                  -- 1 px Rand + 1 px dunkle Fuge, Füllung liegt innen
-- Stil wie die Forever-Fenster: dunkle Fläche, feiner grauer Rand, goldene Linie oben
local EDGE = { 0.22, 0.22, 0.26, 1 }
local TOP_LINE = { 1, 0.82, 0, 0.55 }
local TEXT_COLOR = { 0.92, 0.92, 0.90 }
-- Füllfarben: gleiche Farbfamilie wie Blizzard, aber gedeckter; Unterschied über Helligkeit und Deckkraft
-- statt über knallige Farben. Jede Füllung bekommt einen leichten Glanz (oben heller, unten dunkler).
local XP_COLOR = { 0.50, 0.36, 0.74, 1.00 }      -- aktuelle Erfahrung: weiches Violett
local RESTED_COLOR = { 0.36, 0.56, 0.86, 0.42 }  -- Erholung: helles Blau, durchscheinend
local QUEST_COLOR = { 0.86, 0.72, 0.34, 0.58 }   -- fertige Quests: Gold, durchscheinend

-- Standardhöhen (px); die Breite ist standardmäßig die der Aktionsleiste 1
ns.STATUS_HEIGHT = { xp = 16, rep = 12 }

local widgets = {}          -- [xp|rep] = Inhalt der Leiste

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

local function IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

local function AtMaxLevel()
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    if IsPlayerAtEffectiveMaxLevel then return IsPlayerAtEffectiveMaxLevel() end
    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    return maxLevel ~= nil and UnitLevel("player") >= maxLevel
end
ns.AtMaxLevel = AtMaxLevel

local function Join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v then out[#out + 1] = v end
    end
    return table.concat(out, "  ·  ")
end

local function Cfg(key) return ns.db and ns.db.bars and ns.db.bars[key] end

-- Spielzeit pro Level liegt pro Charakter (Name der Variable wie im früheren Addon ForeverXP, damit der Verlauf bleibt)
local function CharDB()
    if type(_G.ForeverXPCharDB) ~= "table" then _G.ForeverXPCharDB = {} end
    local c = _G.ForeverXPCharDB
    c.history = c.history or {}
    return c
end

---------------------------------------------------------------------------
-- XP-Verlauf: XP/Stunde und Herkunft (Quest / Mob / Sonstiges)
---------------------------------------------------------------------------
local gains = {}            -- { t = Zeitpunkt, xp = Menge, source = Herkunft }
local sessionStart = GetTime()
local sessionXP = 0
local sourceXP = { quest = 0, mob = 0, other = 0 }
local recentKills, recentQuests = {}, {}
local lastXP, lastMax, lastLevel
local lastGain, pendingSource

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

-- Kill- oder Quest-Meldung kam an: dem passenden XP-Gewinn zuordnen (Reihenfolge der Ereignisse ist nicht garantiert)
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
    while gains[1] and now - gains[1].t > WINDOW do table.remove(gains, 1) end
    local sum = 0
    for _, g in ipairs(gains) do sum = sum + g.xp end
    if sum == 0 then return 0 end
    local span = math.max(MIN_SPAN, math.min(WINDOW, now - sessionStart))
    return sum / span * 3600
end

function ns.ResetXPRate()
    wipe(gains)
    wipe(recentKills)
    wipe(recentQuests)
    sessionStart = GetTime()
    sessionXP = 0
    sourceXP.quest, sourceXP.mob, sourceXP.other = 0, 0, 0
    lastGain, pendingSource = nil, nil
    if ns.UpdateStatus then ns.UpdateStatus() end
end

-- Erkennt Kill-Meldungen wie "Kobold stirbt, Ihr bekommt 45 Erfahrung." (Muster aus dem Text des Spiels gebaut)
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
    local c = CharDB()
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
    local c = CharDB()
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
local notifiedLevel -- für welches Level der "reicht fürs Level-Up"-Hinweis schon kam

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

local function NotifyQuestsEnough()
    if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE) end
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(T("Deine fertigen Quests reichen fürs Level-Up!",
            "Your completed quests are enough for a level-up!"), 1, 0.82, 0)
    end
    ns.Print(T("Deine fertigen Quests reichen fürs Level-Up – ab zum Questgeber!",
        "Your completed quests are enough for a level-up – off to the quest giver!"))
end

---------------------------------------------------------------------------
-- Beobachteter Ruf lesen (normale Fraktionen, Ruhm, Freundschaften, Paragon)
---------------------------------------------------------------------------
local FALLBACK_COLORS = {
    [1] = { 0.80, 0.13, 0.13 }, [2] = { 0.80, 0.30, 0.22 }, [3] = { 0.75, 0.27, 0.00 }, [4] = { 0.90, 0.70, 0.00 },
    [5] = { 0.00, 0.60, 0.10 }, [6] = { 0.00, 0.60, 0.10 }, [7] = { 0.00, 0.60, 0.10 }, [8] = { 0.00, 0.60, 0.10 },
}

local function StandingLabel(reaction)
    if not reaction then return "" end
    local key = "FACTION_STANDING_LABEL" .. reaction
    if GetText then
        local text = GetText(key, UnitSex("player"))
        if text and text ~= "" then return text end
    end
    return _G[key] or ""
end

-- Farben dezent: ein Stück zum Grau hin und etwas dunkler (Blizzards Rangfarben sind sehr grell)
local function Mute(r, g, b)
    local grey = (r + g + b) / 3
    local function M(v) return (v + (grey - v) * 0.35) * 0.85 end
    return M(r), M(g), M(b)
end

local function StandingColor(reaction)
    local c = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[reaction] or FALLBACK_COLORS[reaction] or FALLBACK_COLORS[5]
    return Mute(c.r or c[1], c.g or c[2], c.b or c[3])
end

-- liefert { id, name, label, nextLabel, r, g, b, value, max, total, maxed, reward, atWar } oder nil
local function ReadFaction()
    local id, name, reaction, lo, hi, cur, atWar
    local C = C_Reputation
    local data = C and C.GetWatchedFactionData and C.GetWatchedFactionData()
    if data and data.factionID and data.factionID > 0 then
        id, name, reaction = data.factionID, data.name, data.reaction
        lo, hi, cur, atWar = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding, data.atWarWith
    elseif GetWatchedFactionInfo then
        local n, r, mn, mx, v, fid = GetWatchedFactionInfo()
        if n and n ~= "" then id, name, reaction, lo, hi, cur = fid or n, n, r, mn, mx, v end
    end
    if not name then return nil end

    local f = { id = id, name = name, atWar = atWar }
    f.r, f.g, f.b = StandingColor(reaction)

    -- Ruhm (große Fraktionen)
    if C and C.IsMajorFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionData and C.IsMajorFaction(id) then
        local mf = C_MajorFactions.GetMajorFactionData(id)
        if mf then
            f.label = string.format(T("Ruhm %d", "Renown %d"), mf.renownLevel or 0)
            f.nextLabel = string.format(T("Ruhm %d", "Renown %d"), (mf.renownLevel or 0) + 1)
            f.max = math.max(1, mf.renownLevelThreshold or 1)
            f.value = math.min(f.max, mf.renownReputationEarned or 0)
            f.total = (mf.renownLevel or 0) * f.max + f.value
            f.r, f.g, f.b = Mute(0.00, 0.55, 0.95)
            return f
        end
    end

    -- Freundschaft (z. B. Nomi, Tillers)
    local fr = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(id)
    if fr and fr.friendshipFactionID and fr.friendshipFactionID > 0 then
        local flo, fhi, fcur = fr.reactionThreshold or 0, fr.nextThreshold, fr.standing or 0
        f.label = fr.reaction or ""
        f.r, f.g, f.b = StandingColor(5)
        f.total = fcur
        if fhi and fhi > flo then
            f.max, f.value = fhi - flo, math.max(0, math.min(fhi - flo, fcur - flo))
        else
            f.max, f.value, f.maxed = 1, 1, true
        end
        return f
    end

    f.label = StandingLabel(reaction)
    f.nextLabel = StandingLabel(reaction and reaction + 1)
    f.total = cur

    -- Paragon: nach dem höchsten Rang läuft der Ruf weiter bis zur nächsten Belohnung
    if C and C.IsFactionParagon and C.IsFactionParagon(id) and C.GetFactionParagonInfo then
        local value, threshold, _, hasReward = C.GetFactionParagonInfo(id)
        if value and threshold and threshold > 0 then
            f.label = T("Paragon", "Paragon")
            f.nextLabel = nil
            f.max = threshold
            f.value = hasReward and threshold or (value % threshold)
            f.reward = hasReward and true or nil
            f.total = value
            f.r, f.g, f.b = Mute(0.00, 0.50, 0.90)
            return f
        end
    end

    if lo and hi and cur and hi > lo and (reaction or 0) < 8 then
        f.max = hi - lo
        f.value = math.max(0, math.min(f.max, cur - lo))
    else
        f.max, f.value, f.maxed, f.nextLabel = 1, 1, true, nil
    end
    return f
end

-- Ruf-Verlauf: Gewinn in dieser Sitzung und Ruf pro Stunde (nur für den beobachteten Ruf)
local lastTotal, repGains, sessionRep, firstSeen = {}, {}, {}, {}
local faction -- aktuell beobachteter Ruf (ReadFaction)

local function TrackRep(f)
    if not (f and f.total) then return end
    local now = GetTime()
    firstSeen[f.id] = firstSeen[f.id] or now
    local last = lastTotal[f.id]
    if last and f.total > last then
        local delta = f.total - last
        repGains[#repGains + 1] = { t = now, v = delta, id = f.id }
        sessionRep[f.id] = (sessionRep[f.id] or 0) + delta
    end
    lastTotal[f.id] = f.total
end

local function RepRate(f)
    local now = GetTime()
    while repGains[1] and now - repGains[1].t > WINDOW do table.remove(repGains, 1) end
    local sum = 0
    for _, g in ipairs(repGains) do
        if g.id == f.id then sum = sum + g.v end
    end
    if sum == 0 then return 0 end
    local span = math.max(MIN_SPAN, math.min(WINDOW, now - (firstSeen[f.id] or now)))
    return sum / span * 3600
end

---------------------------------------------------------------------------
-- Inhalt der Leiste (im Halter von Bars.lua): flacher Forever-Look, Füllung, Zehntel-Striche, drei Textzonen
---------------------------------------------------------------------------
-- Schrift wie in den Forever-Fenstern: Friz Quadrata ohne Umriss, mit weichem Schatten
local function BarFont(fs)
    fs:SetFontObject("GameFontHighlightSmall")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetTextColor(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3])
    fs:SetWordWrap(false)
end

-- Füllfarbe mit leichtem Glanz: senkrechter Verlauf von etwas dunkler (unten) nach etwas heller (oben)
local function SetFill(s, r, g, b, a)
    local tex = s:GetStatusBarTexture()
    if not tex then return end
    local lo, hi = 0.78, 1.18
    local function clamp(v) return math.min(1, v) end
    if tex.SetGradient and CreateColor then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("VERTICAL", CreateColor(r * lo, g * lo, b * lo, a), CreateColor(clamp(r * hi), clamp(g * hi), clamp(b * hi), a))
    else
        s:SetStatusBarColor(r, g, b, a)
    end
end
ns.SetStatusFill = SetFill

local function Layer(w, color, level)
    local s = CreateFrame("StatusBar", nil, w.root)
    s:SetAllPoints(w.inner)
    s:SetStatusBarTexture(FLAT)
    SetFill(s, color[1], color[2], color[3], color[4])
    s:SetFrameLevel(w.root:GetFrameLevel() + level)
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    return s
end

-- feine helle Endmarke (wo Erholung bzw. Quest-XP enden), damit die Bereiche auch bei gedeckten Farben klar bleiben
local function Mark(w, r, g, b)
    local t = w.tickLayer:CreateTexture(nil, "OVERLAY", nil, 2)
    t:SetColorTexture(r, g, b, 0.9)
    t:SetWidth(1)
    t:Hide()
    return t
end

local function PlaceMark(w, mark, fraction)
    local width = w.inner:GetWidth() or 0
    if not fraction or fraction <= 0 or fraction >= 0.999 or width <= 0 then mark:Hide() return end
    mark:ClearAllPoints()
    mark:SetPoint("TOP", w.tickLayer, "TOPLEFT", width * fraction, 0)
    mark:SetPoint("BOTTOM", w.tickLayer, "BOTTOMLEFT", width * fraction, 0)
    mark:Show()
end

local Tooltip -- weiter unten

local function Build(key, holder)
    local w = { key = key, textParts = {}, hovered = false }
    local root = CreateFrame("Frame", nil, holder, "BackdropTemplate")
    root:SetAllPoints(holder)
    -- scharfer 1-px-Rand wie die Forever-Fenster (statt des weichen Tooltip-Rands) und goldene Linie oben
    root:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    root:SetBackdropColor(0.05, 0.05, 0.065, 0.92)
    root:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
    root:EnableMouse(true)
    w.root = root
    w.topLine = root:CreateTexture(nil, "BORDER")
    w.topLine:SetPoint("TOPLEFT", 1, -1)
    w.topLine:SetPoint("TOPRIGHT", -1, -1)
    w.topLine:SetHeight(1)
    w.topLine:SetColorTexture(TOP_LINE[1], TOP_LINE[2], TOP_LINE[3], TOP_LINE[4])
    w.inner = CreateFrame("Frame", nil, root)
    w.inner:SetPoint("TOPLEFT", INSET, -INSET - 1)
    w.inner:SetPoint("BOTTOMRIGHT", -INSET, INSET)
    -- leerer Teil der Leiste etwas heller als der Rahmen, damit Striche und Kante sichtbar bleiben
    w.track = root:CreateTexture(nil, "ARTWORK")
    w.track:SetAllPoints(w.inner)
    w.track:SetColorTexture(0.10, 0.10, 0.12, 0.9)

    if key == "xp" then
        w.rested = Layer(w, RESTED_COLOR, 1) -- Erholung
        w.quest = Layer(w, QUEST_COLOR, 2)   -- fertige Quests
        w.fill = Layer(w, XP_COLOR, 3)       -- aktuelle XP
    else
        w.fill = Layer(w, { 0.30, 0.50, 0.30, 1 }, 3) -- Ruf (Farbe des Rangs, siehe RenderRep)
    end

    -- Zehntel-Striche über der Füllung, Texte noch darüber
    local tickLayer = CreateFrame("Frame", nil, root)
    tickLayer:SetAllPoints(w.inner)
    tickLayer:SetFrameLevel(root:GetFrameLevel() + 5)
    w.tickLayer = tickLayer
    -- Glanzkante: feine helle Linie oben auf der Leiste
    w.shine = tickLayer:CreateTexture(nil, "OVERLAY", nil, -1)
    w.shine:SetPoint("TOPLEFT")
    w.shine:SetPoint("TOPRIGHT")
    w.shine:SetHeight(1)
    w.shine:SetColorTexture(1, 1, 1, 0.10)
    -- Striche "eingraviert": dunkle Linie mit hellem Saum daneben – klar sichtbar, ohne hart zu wirken
    w.ticks, w.tickLights = {}, {}
    for i = 1, 9 do
        local t = tickLayer:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.55)
        t:SetWidth(1)
        w.ticks[i] = t
        local l = tickLayer:CreateTexture(nil, "OVERLAY")
        l:SetColorTexture(1, 1, 1, 0.07)
        l:SetWidth(1)
        w.tickLights[i] = l
    end
    if key == "xp" then
        w.restedMark = Mark(w, 0.62, 0.78, 1)   -- Ende der Erholung
        w.questMark = Mark(w, 1, 0.86, 0.45)    -- Ende der Quest-XP
    end
    local top = CreateFrame("Frame", nil, root)
    top:SetAllPoints(w.inner)
    top:SetFrameLevel(root:GetFrameLevel() + 7)
    w.center = top:CreateFontString(nil, "OVERLAY")
    BarFont(w.center)
    w.center:SetPoint("CENTER", 0, 0)
    w.left = top:CreateFontString(nil, "OVERLAY")
    BarFont(w.left)
    w.left:SetPoint("LEFT", 6, 0)
    w.left:SetJustifyH("LEFT")
    w.right = top:CreateFontString(nil, "OVERLAY")
    BarFont(w.right)
    w.right:SetPoint("RIGHT", -6, 0)
    w.right:SetJustifyH("RIGHT")

    root:SetScript("OnEnter", function()
        w.hovered = true
        ns.FitStatusTexts(w)
        Tooltip(w)
    end)
    root:SetScript("OnLeave", function()
        w.hovered = false
        ns.FitStatusTexts(w)
        local tip = Style.GetTooltip()
        if tip:GetOwner() == root then tip:Hide() end
    end)
    root:SetScript("OnSizeChanged", function() ns.ApplyStatusLook(w) end)
    root:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if ns.ShowBarOptions then ns.ShowBarOptions(key) end
        elseif button == "LeftButton" and key == "rep" and ToggleCharacter then
            pcall(ToggleCharacter, "ReputationFrame") -- Rufübersicht
        end
    end)
    widgets[key] = w
    return w
end

local function PlaceTicks(w)
    local cfg = Cfg(w.key)
    local width = w.inner:GetWidth()
    local show = cfg and cfg.barTicks and width and width > 0
    for i, t in ipairs(w.ticks) do
        local l = w.tickLights[i]
        t:ClearAllPoints()
        l:ClearAllPoints()
        if show then
            local x = math.floor(width * i / 10 + 0.5)
            t:SetPoint("TOPLEFT", w.tickLayer, "TOPLEFT", x, -1)
            t:SetPoint("BOTTOMLEFT", w.tickLayer, "BOTTOMLEFT", x, 1)
            l:SetPoint("TOPLEFT", t, "TOPRIGHT", 0, 0)
            l:SetPoint("BOTTOMLEFT", t, "BOTTOMRIGHT", 0, 0)
        end
        t:SetShown(show and true or false)
        l:SetShown(show and true or false)
    end
end

-- Texte in drei gleich breiten Zonen, je Zone von lang nach kurz: genommen wird die erste Fassung, die hineinpasst
-- (nichts wird abgeschnitten). Ruhe = kurze Fassungen, Maus darüber = ausführliche.
local function Pick(fs, variants, width)
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

function ns.FitStatusTexts(w)
    local cfg = Cfg(w.key)
    local avail = w.inner:GetWidth() or 0
    if not cfg or avail <= 0 then return end
    if (w.inner:GetHeight() or 0) < 6 then
        w.left:Hide() w.center:Hide() w.right:Hide()
        return
    end
    local zone = avail / 3
    local mode = w.hovered and "hover" or "rest"
    local function V(zoneKey) local z = w.textParts[zoneKey] return z and z[mode] end
    Pick(w.center, V("center"), zone - 8)
    if cfg.barTexts then
        Pick(w.left, V("left"), zone - 12)
        Pick(w.right, V("right"), zone - 12)
    else
        w.left:Hide()
        w.right:Hide()
    end
end

function ns.ApplyStatusLook(w)
    PlaceTicks(w)
    -- etwas kleiner als die Knopfschrift (höchstens 10), ohne Umriss – wie in den Forever-Fenstern
    local innerH = (w.inner:GetHeight() or 12)
    local size = math.max(7, math.min(10, math.floor(innerH + 1)))
    local font = (GameFontHighlightSmall and GameFontHighlightSmall:GetFont()) or STANDARD_TEXT_FONT
    for _, fs in ipairs({ w.center, w.left, w.right }) do
        if not (font and fs:SetFont(font, size, "")) then ns.SetTextFont(fs, size) end
    end
    ns.FitStatusTexts(w)
end

---------------------------------------------------------------------------
-- Erfahrungsleiste: Werte und Texte
---------------------------------------------------------------------------
local xpStats = {}

local function RenderXP(w)
    if AtMaxLevel() then
        w.root:Hide()
        return
    end
    local xp, maxXP, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if IsSecret(xp, maxXP, level) then return end
    if not maxXP or maxXP <= 0 then return end
    w.root:Show()

    local missing = maxXP - xp
    local rested = GetXPExhaustion() or 0
    local rate = GetRate()
    local avgKill, avgQuest = Average(recentKills), Average(recentQuests)
    xpStats.missing = missing
    xpStats.rate = rate
    xpStats.eta = rate > 0 and FormatTime(missing / rate * 3600) or "–"
    xpStats.kills = avgKill and math.ceil(missing / avgKill)
    -- noch keine Kills gezählt: grobe Schätzung für Mobs der eigenen Stufe (Classic-Formel 45 + 5 x Stufe)
    xpStats.killsGuess = not avgKill and math.ceil(missing / (45 + 5 * level)) or nil
    xpStats.quests = avgQuest and math.ceil(missing / avgQuest)

    for _, s in ipairs({ w.rested, w.quest, w.fill }) do s:SetMinMaxValues(0, maxXP) end
    w.fill:SetValue(xp)
    w.quest:SetValue(math.min(maxXP, xp + questXP))
    w.rested:SetValue(math.min(maxXP, xp + rested))
    PlaceMark(w, w.restedMark, rested > 0 and (xp + rested) / maxXP or nil)
    PlaceMark(w, w.questMark, questXP > 0 and (xp + questXP) / maxXP or nil)

    -- Hinweis, sobald die fertigen Quests fürs Level-Up reichen (einmal pro Level)
    local enough = questXP > 0 and questXP >= missing
    if enough and notifiedLevel ~= level then
        notifiedLevel = level
        NotifyQuestsEnough()
    end

    local pctText = string.format("%.1f %%", xp / maxXP * 100)
    local xpText = string.format("%s / %s", Num(xp), Num(maxXP))
    local mobs = xpStats.kills and string.format(T("≈ %s Mobs", "≈ %s mobs"), Num(xpStats.kills))
        or xpStats.killsGuess and string.format(T("~%s Mobs", "~%s mobs"), Num(xpStats.killsGuess)) or nil
    local quests = xpStats.quests and string.format(T("≈ %s Quests", "≈ %s quests"), Num(xpStats.quests)) or nil
    local eta = rate > 0 and (T("Level-Up in ", "Level-up in ") .. xpStats.eta) or nil
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
    local levelText = "Level " .. level
    local rateText = rate > 0 and (Num(rate) .. " XP/h") or nil
    w.textParts.left = {
        rest = { Join(levelText, rateText), levelText },
        hover = { Join(levelText, mobs, quests), Join(levelText, mobs), levelText },
    }
    w.textParts.center = {
        rest = { xpText .. "  (" .. pctText .. ")", xpText, pctText },
        hover = { Join(xpText .. "  (" .. pctText .. ")", T("noch ", "left ") .. Num(missing)), xpText, pctText },
    }
    -- rechts: Erholung und fertige Quests (auch in Ruhe), dazu die Zeit bis zum Level-Up
    local restedShort = rested > 0 and ("|cff7f9fd6" .. T("Erholt ", "Rested ") .. Num(rested) .. "|r") or nil
    w.textParts.right = {
        rest = { Join(restedShort, questShort, eta), Join(restedShort, questShort), Join(questShort, eta), questShort,
            restedShort, eta },
        hover = { Join(restedShort, questLong, eta), Join(restedShort, questShort, eta), Join(questShort, eta),
            Join(restedShort, questShort), questShort or eta },
    }
    ns.FitStatusTexts(w)
end

---------------------------------------------------------------------------
-- Ruf-Leiste: Werte und Texte
---------------------------------------------------------------------------
local function Hex(f, text)
    return string.format("|cff%02x%02x%02x%s|r", f.r * 255, f.g * 255, f.b * 255, text)
end

local function RenderRep(w)
    local f = faction
    if not f then
        w.root:Hide()
        return
    end
    w.root:Show()
    w.fill:SetMinMaxValues(0, f.max)
    w.fill:SetValue(f.value)
    -- Farbe des Rangs, etwas gedeckter (ein Viertel Richtung Grau) und mit Glanz
    local gray = (f.r + f.g + f.b) / 3
    SetFill(w.fill, f.r * 0.75 + gray * 0.25, f.g * 0.75 + gray * 0.25, f.b * 0.75 + gray * 0.25, 1)

    local remaining = f.max - f.value
    local pct = f.value / f.max * 100
    local gain = sessionRep[f.id] or 0
    local rate = RepRate(f)
    local eta = (not f.maxed and rate > 0 and f.nextLabel)
        and (T("Nächster Rang in ", "Next rank in ") .. FormatTime(remaining / rate * 3600)) or nil
    local labelColored = f.label ~= "" and Hex(f, f.label) or nil
    local nextText = f.nextLabel and f.nextLabel ~= "" and ("→ " .. f.nextLabel) or nil

    w.textParts.left = {
        rest = { Join(f.name, labelColored), f.name, labelColored },
        hover = { Join(f.name, labelColored, nextText), Join(f.name, labelColored), f.name },
    }
    if f.maxed then
        local full = T("Maximal erreicht", "Maxed out")
        w.textParts.center = { rest = { full, T("Maximal", "Maxed") }, hover = { full, T("Maximal", "Maxed") } }
    else
        local numbers = string.format("%s / %s", Num(f.value), Num(f.max))
        local pctText = string.format("%.1f %%", pct)
        w.textParts.center = {
            rest = { numbers .. "  (" .. pctText .. ")", numbers, pctText },
            hover = { numbers .. "  (" .. pctText .. ")  ·  " .. T("noch ", "left ") .. Num(remaining),
                numbers .. "  (" .. pctText .. ")", numbers, pctText },
        }
    end
    local gainText = gain > 0 and ("|cff66ff66+" .. Num(gain) .. "|r " .. T("Ruf", "rep")) or nil
    local rateText = rate > 0 and (Num(rate) .. T(" Ruf/h", " rep/h")) or nil
    local remainText = (not f.maxed and f.nextLabel) and (Num(remaining) .. T(" bis ", " to ") .. f.nextLabel) or nil
    local rewardText = f.reward and ("|cffffd100" .. T("Belohnung bereit!", "Reward ready!") .. "|r") or nil
    w.textParts.right = {
        rest = { rewardText, Join(gainText, rateText), gainText, remainText },
        hover = { Join(rewardText, gainText, rateText, eta), Join(gainText, rateText, eta), Join(gainText, eta), gainText or remainText },
    }
    ns.FitStatusTexts(w)
end

---------------------------------------------------------------------------
-- Tooltip (Maus darüber): alle Einzelheiten
---------------------------------------------------------------------------
local WHITE = { 1, 1, 1 }
local function Row(tip, label, value, color)
    color = color or WHITE
    tip:AddDoubleLine(label, value, 1, 0.82, 0, color[1], color[2], color[3])
end

local function XPTooltip(tip)
    tip:AddLine(T("Erfahrung", "Experience"), 1, 0.82, 0)
    if questXP > 0 then
        Row(tip, string.format(T("Fertige Quests (%d):", "Completed quests (%d):"), questCount), "+" .. Num(questXP) .. " XP", { 1, 0.82, 0 })
    end
    if xpStats.missing then
        Row(tip, T("Noch bis Level-Up:", "Left until level-up:"), Num(xpStats.missing) .. " XP")
        Row(tip, T("XP pro Stunde:", "XP per hour:"), xpStats.rate > 0 and Num(xpStats.rate) or "–")
        Row(tip, T("Level-Up in:", "Level-up in:"), xpStats.eta)
        if xpStats.kills then Row(tip, T("Kills bis Level-Up:", "Kills until level-up:"), "≈ " .. Num(xpStats.kills)) end
        if xpStats.quests then Row(tip, T("Quests bis Level-Up:", "Quests until level-up:"), "≈ " .. Num(xpStats.quests)) end
    end
    Row(tip, T("Erholt:", "Rested:"), Num(GetXPExhaustion() or 0) .. " XP", { 0.4, 0.6, 1 })

    -- Woher kamen die XP in dieser Sitzung?
    tip:AddLine(" ")
    Row(tip, T("XP diese Sitzung:", "XP this session:"), Num(sessionXP))
    Row(tip, T("Sitzungsdauer:", "Session length:"), FormatTime(GetTime() - sessionStart))
    if sessionXP > 0 then
        local function Share(v) return string.format("%s (%d %%)", Num(v), v / sessionXP * 100 + 0.5) end
        Row(tip, T("   aus Quests:", "   from quests:"), Share(sourceXP.quest))
        Row(tip, T("   aus Kills:", "   from kills:"), Share(sourceXP.mob))
        Row(tip, T("   Sonstiges:", "   other:"), Share(sourceXP.other))
    end

    -- Spielzeit pro Level
    local c = CharDB()
    if c.current then
        tip:AddLine(" ")
        local prefix = c.current.complete and "" or T("mind. ", "at least ")
        Row(tip, T("Zeit auf diesem Level:", "Time on this level:"), prefix .. FormatTime(c.current.seconds))
        for i = 1, math.min(5, #c.history) do
            local h = c.history[i]
            local text = (h.complete and "" or T("mind. ", "at least ")) .. FormatTime(h.seconds)
            Row(tip, string.format("   Level %d – %d:", h.level, h.level + 1), text, h.complete and WHITE or { 0.6, 0.6, 0.6 })
        end
    end

    tip:AddLine(" ")
    tip:AddLine(T("XP/h = Durchschnitt der letzten 30 Minuten", "XP/h = average of the last 30 minutes"), 0.7, 0.7, 0.7)
    tip:AddLine(T("Kills/Quests = Schnitt der letzten 5", "Kills/quests = average of the last 5"), 0.7, 0.7, 0.7)
    tip:AddLine(T("Gold = fertige Quests, Blau = Erholungsbonus", "Gold = completed quests, blue = rested bonus"), 0.7, 0.7, 0.7)
end

local function RepTooltip(tip)
    local f = faction
    if not f then return end
    tip:AddLine(f.name, 1, 0.82, 0)
    Row(tip, T("Stand:", "Standing:"), f.label ~= "" and f.label or "–", { f.r, f.g, f.b })
    if f.maxed then
        Row(tip, T("Fortschritt:", "Progress:"), T("Maximal erreicht", "Maxed out"))
    else
        Row(tip, T("Fortschritt:", "Progress:"), string.format("%s / %s (%.1f %%)", Num(f.value), Num(f.max), f.value / f.max * 100))
        if f.nextLabel and f.nextLabel ~= "" then
            Row(tip, string.format(T("Noch bis %s:", "Left until %s:"), f.nextLabel), Num(f.max - f.value))
        else
            Row(tip, T("Noch bis zur Belohnung:", "Left until the reward:"), Num(f.max - f.value))
        end
    end
    if f.reward then Row(tip, T("Belohnung:", "Reward:"), T("bereit zum Abholen!", "ready to collect!"), { 1, 0.82, 0 }) end
    if f.atWar then Row(tip, T("Im Krieg:", "At war:"), T("ja", "yes"), { 1, 0.3, 0.3 }) end
    local gain = sessionRep[f.id] or 0
    local rate = RepRate(f)
    tip:AddLine(" ")
    Row(tip, T("Ruf diese Sitzung:", "Reputation this session:"), "+" .. Num(gain), { 0.4, 1, 0.4 })
    Row(tip, T("Ruf pro Stunde:", "Reputation per hour:"), rate > 0 and Num(rate) or "–")
    if not f.maxed and rate > 0 then
        Row(tip, T("Nächster Rang in:", "Next rank in:"), FormatTime((f.max - f.value) / rate * 3600))
    end
    tip:AddLine(" ")
    tip:AddLine(T("Linksklick: Rufübersicht · Rechtsklick: Einstellungen", "Left-click: reputation panel · right-click: settings"), 0.7, 0.7, 0.7)
    tip:AddLine(T("Anderen Ruf zeigen: in der Rufübersicht „Als Erfahrungsleiste anzeigen“", "Other faction: tick \"Show as Experience Bar\" in the reputation panel"), 0.7, 0.7, 0.7)
end

Tooltip = function(w)
    if ns.unlocked then return end
    local tip = Style.GetTooltip()
    -- dort, wo auch sonst Tooltips erscheinen (unten rechts); sonst über/unter der Leiste
    if not (GameTooltip_SetDefaultAnchor and pcall(GameTooltip_SetDefaultAnchor, tip, w.root)) then
        local _, y = w.root:GetCenter()
        tip:SetOwner(w.root, (y and y > UIParent:GetHeight() / 2) and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
    end
    if w.key == "xp" then XPTooltip(tip) else RepTooltip(tip) end
    tip:Show()
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------
local function Render(w)
    if w.key == "xp" then RenderXP(w) else RenderRep(w) end
end

function ns.UpdateStatus()
    if not ns.db then return end
    faction = ReadFaction()
    TrackRep(faction)
    for _, w in pairs(widgets) do Render(w) end
end

---------------------------------------------------------------------------
-- Blizzards eigene Leisten unsichtbar machen (nur Durchsichtigkeit, nie :Hide(), kein "taint"-Risiko)
-- Blizzard verteilt Erfahrung, Ruf usw. auf zwei Behälter; jeder merkt sich in shownBarIndex, was er gerade zeigt.
-- Unsichtbar wird nur der Behälter mit der Erfahrung (wenn die Erfahrungsleiste an ist) bzw. dem Ruf (Ruf-Leiste an).
---------------------------------------------------------------------------
local CONTAINERS = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }
local OLD_BARS = { "MainMenuExpBar", "ReputationWatchBar" } -- ältere Spielstände

local function Shows(c, kind)
    local enum = _G.StatusTrackingBarInfo and _G.StatusTrackingBarInfo.BarsEnum
    if not (enum and enum[kind] and c.shownBarIndex ~= nil) then
        -- unbekannter Aufbau: Hauptleiste = Erfahrung, zweite Leiste = Ruf
        if kind == "Experience" then return c == _G.MainStatusTrackingBarContainer end
        return c == _G.SecondaryStatusTrackingBarContainer
    end
    return c.shownBarIndex == enum[kind]
end

local function ShouldHide(c)
    if not (ns.db and ns.db.hideStatusBlizzard) then return false end
    local xp, rep = Cfg("xp"), Cfg("rep")
    return (xp and xp.enabled and Shows(c, "Experience")) or (rep and rep.enabled and Shows(c, "Reputation")) or false
end

-- Mehrfach nachsetzen: Blizzard baut die Leisten erst kurz nach dem Anmelden auf (und setzt sie im Bearbeitungsmodus neu)
local blizzPending = false
local function ScheduleBlizzard(delay)
    C_Timer.After(delay or 0, function()
        blizzPending = false
        if ns.db and not InCombatLockdown() then ns.UpdateBlizzardStatus() end
    end)
end

function ns.UpdateBlizzardStatus()
    if not (ns.db and UI.HideBlizzard) then return end
    local any = false
    -- Sind beide eigenen Leisten an, verschwindet die ganze Verwaltung samt allen Unterrahmen (kein Warten darauf,
    -- welcher Behälter gerade was zeigt); die Verwaltung meldet sich bei jedem Neuaufbau und wird dann gleich wieder versteckt
    local xpCfg, repCfg = Cfg("xp"), Cfg("rep")
    local manager = _G.StatusTrackingBarManager
    if manager and ns.db.hideStatusBlizzard and xpCfg and repCfg and xpCfg.enabled and repCfg.enabled then
        UI.HideBlizzard(manager, { when = function()
            return ns.db.hideStatusBlizzard and xpCfg.enabled and repCfg.enabled
        end })
        if not manager.fbStatusHooked then
            manager.fbStatusHooked = true
            for _, method in ipairs({ "UpdateBarsShown", "LayoutBars", "Layout", "SetBarsShown", "OnShow" }) do
                if manager[method] then
                    hooksecurefunc(manager, method, function()
                        if not blizzPending then
                            blizzPending = true
                            ScheduleBlizzard(0)
                        end
                    end)
                end
            end
            manager:HookScript("OnShow", function() ScheduleBlizzard(0) end)
        end
        for _, name in ipairs(CONTAINERS) do UI.ShowBlizzard(_G[name]) end -- einzeln nichts mehr zu tun (alles unter der Verwaltung)
        return
    elseif manager then
        UI.ShowBlizzard(manager)
    end
    for _, name in ipairs(CONTAINERS) do
        local c = _G[name]
        if c then
            any = true
            if ShouldHide(c) then
                UI.HideBlizzard(c, { when = function() return ShouldHide(c) end })
            else
                UI.ShowBlizzard(c)
            end
            -- Tauscht Blizzard die Leisten zwischen den Behältern (z. B. Ruf beobachten), neu verteilen
            if not c.fbStatusHooked and c.ApplyPendingBarToShow then
                c.fbStatusHooked = true
                hooksecurefunc(c, "ApplyPendingBarToShow", function() C_Timer.After(0, ns.UpdateBlizzardStatus) end)
            end
        end
    end
    if not any then
        -- ältere Spielstände: eine Leiste für Erfahrung bzw. Ruf
        local xp, rep = Cfg("xp"), Cfg("rep")
        for i, name in ipairs(OLD_BARS) do
            local f = _G[name]
            local on = (i == 1 and xp and xp.enabled) or (i == 2 and rep and rep.enabled)
            if f then
                if ns.db.hideStatusBlizzard and on then
                    UI.HideBlizzard(f, { when = function() return ns.db.hideStatusBlizzard end })
                else
                    UI.ShowBlizzard(f)
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Einbindung in die Leisten (Bars.lua: ApplyLayout / Standardposition)
---------------------------------------------------------------------------
function ns.StatusHeight(key, cfg)
    return math.max(8, cfg and cfg.height or ns.STATUS_HEIGHT[key] or 16)
end

function ns.StatusWidth(cfg)
    return math.max(100, cfg and cfg.width or ns.ActionBarWidth())
end

function ns.LayoutStatus(def, cfg, holder)
    local w = widgets[def.key] or Build(def.key, holder)
    holder:SetSize(ns.StatusWidth(cfg), ns.StatusHeight(def.key, cfg))
    w.root:ClearAllPoints()
    w.root:SetAllPoints(holder)
    ns.ApplyStatusLook(w)
    Render(w)
    ns.UpdateBlizzardStatus()
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "QUEST_LOG_UPDATE",
    "QUEST_TURNED_IN", "CHAT_MSG_COMBAT_XP_GAIN", "UPDATE_FACTION", "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "PLAYER_REGEN_ENABLED", "EDIT_MODE_LAYOUTS_UPDATED" }) do
    pcall(events.RegisterEvent, events, e)
end
events:SetScript("OnEvent", function(_, event, arg1)
    if not ns.db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Blizzards Leisten entstehen erst kurz nach dem Anmelden: ein paar Mal nachsetzen
        for _, delay in ipairs({ 0.5, 2, 5, 10 }) do ScheduleBlizzard(delay) end
    end
    if event == "UPDATE_FACTION" or event == "EDIT_MODE_LAYOUTS_UPDATED" or event == "PLAYER_REGEN_ENABLED" then
        if not InCombatLockdown() then ns.UpdateBlizzardStatus() end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- In Instanzen kann der Text im Kampf geheim sein; dann zählt es als "Sonstiges"
        if killPattern and type(arg1) == "string" and not IsSecret(arg1) and arg1:match(killPattern) then
            NoteSource("mob")
        end
        return
    elseif event == "QUEST_TURNED_IN" then
        NoteSource("quest")
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        TickLevelTime()
        TrackXP()
        UpdateQuestXP()
    elseif event == "PLAYER_LEVEL_UP" then
        OnLevelUp(arg1)
        if not InCombatLockdown() then ns.UpdateBlizzardStatus() end
    elseif event == "PLAYER_XP_UPDATE" then
        TrackXP()
    elseif event == "QUEST_LOG_UPDATE" then
        UpdateQuestXP()
    end
    ns.UpdateStatus()
end)

-- zeitabhängige Werte (pro Stunde, Zeit bis Level-Up) laufen ohne Ereignis weiter
C_Timer.NewTicker(REFRESH, function()
    if not ns.db then return end
    TickLevelTime()
    ns.UpdateStatus()
end)

-- Blizzards Leisten zur Sicherheit selten nachprüfen (sonst über Ereignisse, siehe oben)
C_Timer.NewTicker(30, function()
    if ns.ready and not InCombatLockdown() then ns.UpdateBlizzardStatus() end
end)

-- /fxp: wie früher das Addon ForeverXP (ohne Zusatz öffnet sich das Menü bei der Erfahrungsleiste)
SLASH_FOREVERXP1 = "/fxp"
SLASH_FOREVERXP2 = "/foreverxp"
SlashCmdList.FOREVERXP = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "reset" then
        ns.ResetXPRate()
        ns.Print(T("XP/h und Sitzungswerte zurückgesetzt.", "XP/h and session values reset."))
    elseif ns.ShowBarOptions then
        ns.ShowBarOptions((msg == "rep" or msg == "ruf") and "rep" or "xp")
    end
end
