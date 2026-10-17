-- ForeverXP – Reputation.lua: Ruf-Leiste
-- Eine zweite, schmalere Leiste im selben Stil wie der Erfahrungsbalken, die den beobachteten Ruf zeigt.
-- Sie hängt am Erfahrungsbalken (darunter, wenn der oben steht, sonst darüber; ohne Erfahrungsbalken, z. B. auf
-- Höchststufe, nimmt sie dessen Platz ein), teilt Textur, Schrift und Breite und ersetzt Blizzards Rufleiste.
local ADDON_NAME, ns = ...
local X = ns.xp
if not X then return end
local UI = ForeverHub.UI
local T = UI.T

local bar, GetDB, Num, FormatTime = X.bar, X.GetDB, X.Num, X.FormatTime
local INSET, GOLD_EDGE = X.INSET, X.GOLD_EDGE
local GAP = 2                 -- Abstand zum Erfahrungsbalken
local WINDOW = 30 * 60        -- Ruf pro Stunde wird über die letzten 30 Minuten gemittelt
local MIN_SPAN = 5 * 60       -- direkt nach dem Login mindestens durch 5 Minuten teilen
local REFRESH = 5

---------------------------------------------------------------------------
-- Beobachteten Ruf lesen (normale Fraktionen, Ruhm, Freundschaften, Paragon)
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

local function StandingColor(reaction)
    local c = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[reaction] or FALLBACK_COLORS[reaction] or FALLBACK_COLORS[5]
    return c.r or c[1], c.g or c[2], c.b or c[3]
end

-- liefert { id, name, label, nextLabel, r, g, b, value, max, total, maxed, reward, atWar } oder nil
local function Read()
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
            f.r, f.g, f.b = 0.00, 0.55, 0.95
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
            f.r, f.g, f.b = 0.00, 0.50, 0.90
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

---------------------------------------------------------------------------
-- Verlauf: Ruf pro Stunde und Gewinn in dieser Sitzung (nur für den beobachteten Ruf)
---------------------------------------------------------------------------
local lastTotal, gains, sessionGain, firstSeen = {}, {}, {}, {}

local function Track(f)
    if not (f and f.total) then return end
    local now = GetTime()
    firstSeen[f.id] = firstSeen[f.id] or now
    local last = lastTotal[f.id]
    if last and f.total > last then
        local delta = f.total - last
        gains[#gains + 1] = { t = now, v = delta, id = f.id }
        sessionGain[f.id] = (sessionGain[f.id] or 0) + delta
    end
    lastTotal[f.id] = f.total
end

local function Rate(f)
    local now = GetTime()
    while gains[1] and now - gains[1].t > WINDOW do table.remove(gains, 1) end
    local sum = 0
    for _, g in ipairs(gains) do
        if g.id == f.id then sum = sum + g.v end
    end
    if sum == 0 then return 0 end
    local span = math.max(MIN_SPAN, math.min(WINDOW, now - (firstSeen[f.id] or now)))
    return sum / span * 3600
end

---------------------------------------------------------------------------
-- Die Leiste (Aufbau wie der Erfahrungsbalken)
---------------------------------------------------------------------------
local rep = CreateFrame("Frame", "ForeverXPRepBar", UIParent, "BackdropTemplate")
rep:SetSize(1024, 12)
rep:SetFrameStrata("MEDIUM")
rep:SetFrameLevel(20)
rep:SetClampedToScreen(true)
rep:EnableMouse(true)
rep:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
rep:SetBackdropColor(0.04, 0.04, 0.05, 1)
rep:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], GOLD_EDGE[4])
rep:Hide()
if UI.AddMover then UI.AddMover(rep) end -- andere Forever-Rahmen rasten an der Leiste ein
ns.repBar = rep

local inner = CreateFrame("Frame", nil, rep)
inner:SetPoint("TOPLEFT", INSET, -INSET)
inner:SetPoint("BOTTOMRIGHT", -INSET, INSET)

local fill = CreateFrame("StatusBar", nil, rep)
fill:SetAllPoints(inner)
fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
fill:SetFrameLevel(rep:GetFrameLevel() + 3)
fill:SetMinMaxValues(0, 1)

local tickLayer = CreateFrame("Frame", nil, rep)
tickLayer:SetAllPoints(inner)
tickLayer:SetFrameLevel(rep:GetFrameLevel() + 5)
local ticks = {}
for i = 1, 9 do
    local t = tickLayer:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(0, 0, 0, 0.75)
    t:SetWidth(1)
    ticks[i] = t
end

local top = CreateFrame("Frame", nil, rep)
top:SetAllPoints(inner)
top:SetFrameLevel(rep:GetFrameLevel() + 7)
local center = top:CreateFontString(nil, "OVERLAY")
X.BarFont(center)
center:SetPoint("CENTER", 0, 0)
local left = top:CreateFontString(nil, "OVERLAY")
X.BarFont(left)
left:SetPoint("LEFT", 6, 0)
left:SetJustifyH("LEFT")
local right = top:CreateFontString(nil, "OVERLAY")
X.BarFont(right)
right:SetPoint("RIGHT", -6, 0)
right:SetJustifyH("RIGHT")

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

-- Texte in drei Zonen, je Zone von lang nach kurz: die erste Fassung, die hineinpasst (nichts wird abgeschnitten)
local textParts = {}
local hovered = false
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

local function FitTexts()
    local d = GetDB()
    local avail = inner:GetWidth() or 0
    if avail <= 0 then return end
    if (inner:GetHeight() or 0) < 6 then
        left:Hide() center:Hide() right:Hide()
        return
    end
    local zone = avail / 3
    local mode = hovered and "hover" or "rest"
    local function V(key) local z = textParts[key] return z and z[mode] end
    Pick(center, V("center"), zone - 8)
    if d.barTexts then
        Pick(left, V("left"), zone - 12)
        Pick(right, V("right"), zone - 12)
    else
        left:Hide()
        right:Hide()
    end
end

local function ApplyLook()
    local d = GetDB()
    fill:SetStatusBarTexture(X.MediaPath(d.texture, X.TEXTURES, "statusbar"))
    local font = X.MediaPath(d.font, X.FONTS, "font")
    local innerH = (rep:GetHeight() or 12) - 2 * INSET
    local size = math.max(7, math.min(d.fontSize, math.floor(innerH + 4)))
    for _, fs in ipairs({ center, left, right }) do fs:SetFont(font, size, d.fontOutline or "") end
    FitTexts()
end

---------------------------------------------------------------------------
-- Lage und Größe: gleiche Breite wie der Erfahrungsbalken, direkt daneben
---------------------------------------------------------------------------
local state = { f = nil, wanted = false }

local function Relayout()
    local d = GetDB()
    rep:SetFrameStrata(bar:GetFrameStrata())
    local width = math.max(100, bar:GetWidth() or 100)
    local height = math.max(8, math.floor((bar:GetHeight() or 16) * (d.repHeightScale or 70) / 100 + 0.5))
    rep:SetSize(width, height)
    rep:ClearAllPoints()
    -- steht der Erfahrungsbalken oben auf dem Bildschirm, kommt die Ruf-Leiste darunter, sonst darüber
    local _, y = bar:GetCenter()
    local upper
    if y then upper = y > UIParent:GetHeight() / 2 else upper = d.barPlace == "TOP" end
    if bar:IsShown() then
        if upper then rep:SetPoint("TOP", bar, "BOTTOM", 0, -GAP) else rep:SetPoint("BOTTOM", bar, "TOP", 0, GAP) end
    else
        -- kein Erfahrungsbalken (Höchststufe, ausgeblendet): die Ruf-Leiste nimmt seinen Platz ein
        if upper then rep:SetPoint("TOP", bar, "TOP", 0, 0) else rep:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0) end
    end
    if d.locked then
        rep:SetBackdropBorderColor(GOLD_EDGE[1], GOLD_EDGE[2], GOLD_EDGE[3], GOLD_EDGE[4])
    else
        rep:SetBackdropBorderColor(0.3, 0.6, 1, 1)
    end
    PlaceTicks()
    ApplyLook()
end

---------------------------------------------------------------------------
-- Werte und Texte
---------------------------------------------------------------------------
local function Join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v then out[#out + 1] = v end
    end
    return table.concat(out, "  ·  ")
end

local function Hex(f, text)
    return string.format("|cff%02x%02x%02x%s|r", f.r * 255, f.g * 255, f.b * 255, text)
end

local function Render()
    local f = state.f
    if not f then return end
    fill:SetMinMaxValues(0, f.max)
    fill:SetValue(f.value)
    fill:SetStatusBarColor(f.r, f.g, f.b, 1)

    local remaining = f.max - f.value
    local pct = f.value / f.max * 100
    local gain = sessionGain[f.id] or 0
    local rate = Rate(f)
    local eta = (not f.maxed and rate > 0 and f.nextLabel) and (T("Nächster Rang in ", "Next rank in ") .. FormatTime(remaining / rate * 3600)) or nil
    local labelColored = f.label ~= "" and Hex(f, f.label) or nil
    local nextText = f.nextLabel and f.nextLabel ~= "" and (T("→ ", "→ ") .. f.nextLabel) or nil

    textParts.left = {
        rest = { Join(f.name, labelColored), f.name, labelColored },
        hover = { Join(f.name, labelColored, nextText), Join(f.name, labelColored), f.name },
    }
    if f.maxed then
        local full = T("Maximal erreicht", "Maxed out")
        textParts.center = { rest = { full, T("Maximal", "Maxed")}, hover = { full, T("Maximal", "Maxed") } }
    else
        local numbers = string.format("%s / %s", Num(f.value), Num(f.max))
        local pctText = string.format("%.1f %%", pct)
        textParts.center = {
            rest = { numbers .. "  (" .. pctText .. ")", numbers, pctText },
            hover = { numbers .. "  (" .. pctText .. ")  ·  " .. T("noch ", "left ") .. Num(remaining),
                numbers .. "  (" .. pctText .. ")", numbers, pctText },
        }
    end
    local gainText = gain > 0 and ("|cff66ff66+" .. Num(gain) .. "|r " .. T("Ruf", "rep")) or nil
    local rateText = rate > 0 and (Num(rate) .. T(" Ruf/h", " rep/h")) or nil
    local remainText = (not f.maxed and f.nextLabel) and (Num(remaining) .. T(" bis ", " to ") .. f.nextLabel) or nil
    local rewardText = f.reward and ("|cffffd100" .. T("Belohnung bereit!", "Reward ready!") .. "|r") or nil
    textParts.right = {
        rest = { rewardText, Join(gainText, rateText), gainText, remainText },
        hover = { Join(rewardText, gainText, rateText, eta), Join(gainText, rateText, eta), Join(gainText, eta), gainText or remainText },
    }
    FitTexts()
end

---------------------------------------------------------------------------
-- Sichtbarkeit und Aktualisierung
---------------------------------------------------------------------------
local function Update()
    local d = GetDB()
    local f = Read()
    state.f = f
    Track(f)
    local wanted = d.repShow ~= false and f ~= nil
    local changed = (wanted ~= state.wanted)
    state.wanted = wanted
    ns.repWanted = wanted -- Blizzards Rufleiste darf nur verschwinden, solange diese Leiste da ist
    local show = wanted and not d.hidden
    if show then
        Relayout()
        Render()
        rep:Show()
    else
        rep:Hide()
    end
    if changed and not InCombatLockdown() then X.HideBlizzardBar() end
end

function ns.RepRefresh()
    Update()
end

-- Lage nachziehen, wenn der Erfahrungsbalken sich ändert
bar:HookScript("OnShow", function() if rep:IsShown() then Relayout() end end)
bar:HookScript("OnHide", function() if rep:IsShown() then Relayout() end end)
bar:HookScript("OnSizeChanged", function() if rep:IsShown() then Relayout() end end)
hooksecurefunc(bar, "SetPoint", function() if rep:IsShown() then Relayout() end end)
-- Durchsichtigkeit (Kampf-Ausblendung) gemeinsam mit dem Balken
hooksecurefunc(bar, "SetAlpha", function(_, alpha) rep:SetAlpha(alpha) end)
rep:SetScript("OnSizeChanged", function() PlaceTicks() ApplyLook() end)

---------------------------------------------------------------------------
-- Tooltip (Maus drüber) und Klicks
---------------------------------------------------------------------------
local function Row(label, value, r, g, b)
    GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, r or 1, g or 1, b or 1)
end

rep:SetScript("OnEnter", function(self)
    hovered = true
    FitTexts()
    local f = state.f
    if not f then return end
    local _, y = self:GetCenter()
    GameTooltip:SetOwner(self, (y and y > UIParent:GetHeight() / 2) and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
    GameTooltip:AddLine(f.name)
    Row(T("Stand:", "Standing:"), f.label ~= "" and f.label or "–", f.r, f.g, f.b)
    if f.maxed then
        Row(T("Fortschritt:", "Progress:"), T("Maximal erreicht", "Maxed out"))
    else
        Row(T("Fortschritt:", "Progress:"), string.format("%s / %s (%.1f %%)", Num(f.value), Num(f.max), f.value / f.max * 100))
        if f.nextLabel and f.nextLabel ~= "" then
            Row(string.format(T("Noch bis %s:", "Left until %s:"), f.nextLabel), Num(f.max - f.value))
        else
            Row(T("Noch bis zur Belohnung:", "Left until the reward:"), Num(f.max - f.value))
        end
    end
    if f.reward then Row(T("Belohnung:", "Reward:"), T("bereit zum Abholen!", "ready to collect!"), 1, 0.82, 0) end
    if f.atWar then Row(T("Im Krieg:", "At war:"), T("ja", "yes"), 1, 0.3, 0.3) end
    local gain = sessionGain[f.id] or 0
    local rate = Rate(f)
    GameTooltip:AddLine(" ")
    Row(T("Ruf diese Sitzung:", "Reputation this session:"), "+" .. Num(gain), 0.4, 1, 0.4)
    Row(T("Ruf pro Stunde:", "Reputation per hour:"), rate > 0 and Num(rate) or "–")
    if not f.maxed and rate > 0 then
        Row(T("Nächster Rang in:", "Next rank in:"), FormatTime((f.max - f.value) / rate * 3600))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(T("Linksklick: Rufübersicht · Rechtsklick: Einstellungen", "Left-click: reputation panel · right-click: settings"), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(T("Anderen Ruf zeigen: in der Rufübersicht „Als Erfahrungsleiste anzeigen“", "Other faction: tick \"Show as Experience Bar\" in the reputation panel"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
rep:SetScript("OnLeave", function(self)
    hovered = false
    FitTexts()
    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end)
rep:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
        X.ToggleOptions()
    elseif button == "LeftButton" and ToggleCharacter then
        pcall(ToggleCharacter, "ReputationFrame")
    end
end)

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_FACTION")
pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_FACTION_CHANGE")
pcall(events.RegisterEvent, events, "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function() Update() end)
C_Timer.NewTicker(REFRESH, function() Update() end)

-- Einstellungen: eigener Abschnitt im ForeverXP-Fenster
local api = ns.optionsApi
if api then
    UI.Header(api.frame, api.R, -402, T("Ruf-Leiste", "Reputation bar"), 296)
    api.KeyCheck(api.R - 4, -424, T("Ruf-Leiste zeigen (beobachteter Ruf)", "Show reputation bar (watched faction)"), "repShow")
    api.Slider(api.R + 2, -450, T("Höhe (% des Balkens)", "Height (% of the bar)"), "repHeightScale", 40, 100, 1, { width = 170, unit = " %" })
    UI.Hint(api.frame, api.R + 2, -496, 290, T("Zeigt den Ruf, den du in der Rufübersicht beobachtest. Sie sitzt unter dem Balken (steht er unten: darüber) und teilt Breite, Schrift und Textur.",
        "Shows the faction you watch in the reputation panel. It sits below the bar (above it if the bar is at the bottom) and shares width, font and texture."))
end
