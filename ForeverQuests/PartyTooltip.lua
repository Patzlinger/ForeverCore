local addonName, ns = ...

-- PartyTooltip.lua: Im Tooltip von Gegnern und Objekten zeigen Questie bzw. das Spiel auch den Questfortschritt der
-- Gruppenmitglieder. Steht dort eine Quest, die man selbst gar nicht hat, wird sie grau und mit dem Hinweis
-- "nicht in deinem Questlog" markiert, damit man sie nicht mit den eigenen verwechselt.
-- Aufbau der Questzeilen im Tooltip: Questname (nicht eingerückt), darunter die Ziele mit drei Leerzeichen eingerückt.
-- Questie wird dabei nicht verändert: es werden nur die fertigen Tooltip-Zeilen umgefärbt.

local L = ns.L
local issecret = issecretvalue or function() return false end
local MARK_COLOR = "|cff8a8a8a"     -- fremde Quest: Name und Ziele grau
local NOTE_COLOR = "|cffff9933"     -- Hinweis dahinter: orange
local busy = false

-- Text ohne Farb-, Symbol- und Stufenangaben ("[12] Name" → "Name")
local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("^%[[^%]]*%]%s*", "")
    return text
end

-- Namen aller Quests im eigenen Questlog
local function OwnTitles()
    local titles = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return titles end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.title and not issecret(info.title) then
            table.insert(titles, info.title)
        end
    end
    return titles
end

local function IsOwn(titles, plain)
    for _, title in ipairs(titles) do
        -- (beginnt mit dem Namen: Questie hängt manchmal z. B. "(Abgeschlossen)" an)
        if plain == title or plain:sub(1, #title) == title then return true end
    end
    return false
end

-- Nur Tooltips von Gegnern/NPCs und Objekten (bei Gegenständen gibt es eingerückte Zeilen auch für Sets)
local function IsUnitOrObject(tip)
    if not (tip.GetPrimaryTooltipData and Enum and Enum.TooltipDataType) then return false end
    local ok, data = pcall(tip.GetPrimaryTooltipData, tip)
    if not ok or type(data) ~= "table" or issecret(data.type) then return false end
    local K = Enum.TooltipDataType
    return data.type == K.Unit or (K.Object ~= nil and data.type == K.Object)
end

local function MarkForeignQuests(tip)
    if busy or not IsUnitOrObject(tip) then return end
    local name = tip:GetName()
    local count = tip:NumLines()
    if not name or count < 2 then return end
    local titles
    local changed = false
    local inForeign = false
    for i = 1, count do
        local line = _G[name .. "TextLeft" .. i]
        local text = line and line:GetText()
        if not text or issecret(text) then
            inForeign = false
        elseif text:match("^   ") then
            -- Ziel einer Quest: bei fremden Quests grau (Farben im Text entfernen, sonst wirkt SetTextColor nicht)
            -- (Farbe erst nach der Einrückung, damit die Zeile beim nächsten Durchlauf noch als Ziel erkannt wird)
            local rest = text:sub(4)
            if inForeign and rest:sub(1, #MARK_COLOR) ~= MARK_COLOR then
                line:SetText("   " .. MARK_COLOR .. rest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r")
                changed = true
            end
        else
            inForeign = false
            local nextLine = _G[name .. "TextLeft" .. (i + 1)]
            local nextText = nextLine and nextLine:GetText()
            -- Questname = nicht eingerückte Zeile mit eingerückten Zielen darunter
            if i > 1 and nextText and not issecret(nextText) and nextText:match("^   ") then
                titles = titles or OwnTitles()
                local plain = Plain(text)
                if plain ~= "" and not IsOwn(titles, plain) then
                    inForeign = true
                    -- (schon markiert, z. B. beim erneuten Anzeigen desselben Tooltips)
                    if not text:find(L("TIP_PARTY_ONLY"), 1, true) then
                        line:SetText(MARK_COLOR .. Plain(text) .. "|r  " .. NOTE_COLOR .. "(" .. L("TIP_PARTY_ONLY") .. ")|r")
                        changed = true
                    end
                end
            end
        end
    end
    if changed then
        -- Breite an die längeren Zeilen anpassen
        busy = true
        tip:Show()
        busy = false
    end
end

-- Nach jedem Anzeigen prüfen: so ist es egal, ob Questie seine Zeilen vor oder nach uns einträgt
hooksecurefunc(GameTooltip, "Show", function(self) pcall(MarkForeignQuests, self) end)
