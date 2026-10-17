local addonName, ns = ...

-- GroupQuests.lua: "Der Gruppe vorschlagen" (Rechtsklick auf eine Quest im Tracker).
-- Wer eine Quest vorschlägt, teilt sie wie gewohnt mit der Gruppe (falls teilbar) und schickt allen
-- Gruppenmitgliedern mit ForeverQuests eine unsichtbare Addon-Nachricht. Bei jedem erscheint im Tracker der Reiter
-- "Gruppe" mit dieser Quest; jeder meldet seinen Fortschritt, sobald er sich ändert – so sieht jeder den Stand aller.
-- Nachrichten (Kennung "FQGRP"):
--   S|<questID>|<Titel>   vorgeschlagen
--   P|<questID>|<Stand>   eigener Stand: "-" = Quest nicht im Questlog, "+" = fertig, sonst "3/8,1/1" je Ziel
--   R|<questID>           aus der Gruppenliste genommen
-- Nur für diese Sitzung (verlässt man die Gruppe, ist die Liste leer).

local L = ns.L
local PREFIX = "FQGRP"
local issecret = issecretvalue or function() return false end

ns.groupQuests = {}   -- [questID] = { title, order, members = { [Name] = { state, class } } }
ns.trackerTab = "quests"
local order = 0
local lastSent = {}   -- [questID] = zuletzt gesendeter eigener Stand

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end

local function Channel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function Send(message)
    local channel = Channel()
    if channel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel)
    end
end

-- Name ohne Realm (Forever: "Vorname Nachname-Realm" -> "Vorname Nachname")
local function ShortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:match("^[^-]+")) or name
end

local function MyName() return ShortName(UnitName("player")) end

local function AddQuest(questID, title)
    if ns.groupQuests[questID] then return ns.groupQuests[questID] end
    order = order + 1
    local q = { title = title or C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID), order = order, members = {} }
    ns.groupQuests[questID] = q
    return q
end

-- Eigener Stand einer Quest als kurzer Text (siehe oben)
local function MyState(questID)
    if not C_QuestLog.GetLogIndexForQuestID(questID) then return "-" end
    if C_QuestLog.IsComplete(questID) then return "+" end
    local parts = {}
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
        parts[#parts + 1] = (objective.numFulfilled or 0) .. "/" .. (objective.numRequired or 0)
    end
    return #parts > 0 and table.concat(parts, ",") or "0"
end

local function SetMember(questID, name, state, class)
    local q = ns.groupQuests[questID]
    if not q or not name then return end
    q.members[name] = { state = state, class = class }
end

function ns.SendGroupProgress(questID)
    local state = MyState(questID)
    local _, class = UnitClass("player")
    SetMember(questID, MyName(), state, class)
    lastSent[questID] = state
    Send("P|" .. questID .. "|" .. state)
end

function ns.SuggestQuest(questID)
    if not IsInGroup() then return end
    local title = C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID)
    AddQuest(questID, title)
    -- auch auf Blizzards Weg teilen, damit die anderen die Quest annehmen können
    if C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID) then
        if QuestMapQuestOptions_ShareQuest then
            pcall(QuestMapQuestOptions_ShareQuest, questID)
        elseif QuestLogPushQuest then
            C_QuestLog.SetSelectedQuest(questID)
            QuestLogPushQuest()
        end
    end
    Send("S|" .. questID .. "|" .. title:sub(1, 200))
    ns.SendGroupProgress(questID)
    ns.trackerTab = "group"
    if ns.RequestUpdate then ns.RequestUpdate() end
end

function ns.RemoveGroupQuest(questID, broadcast)
    ns.groupQuests[questID] = nil
    lastSent[questID] = nil
    if broadcast then Send("R|" .. questID) end
    if not next(ns.groupQuests) then ns.trackerTab = "quests" end
    if ns.RequestUpdate then ns.RequestUpdate() end
end

function ns.HasGroupQuests() return next(ns.groupQuests) ~= nil end

-- Für die Anzeige: Quests in Vorschlags-Reihenfolge, je Quest die Teilnehmer (man selbst zuerst)
function ns.GroupQuestList()
    local list = {}
    for questID, q in pairs(ns.groupQuests) do list[#list + 1] = { questID = questID, data = q } end
    table.sort(list, function(a, b) return a.data.order < b.data.order end)
    local me = MyName()
    for _, entry in ipairs(list) do
        local members = {}
        for name, m in pairs(entry.data.members) do members[#members + 1] = { name = name, state = m.state, class = m.class } end
        table.sort(members, function(a, b)
            if a.name == me then return true end
            if b.name == me then return false end
            return a.name < b.name
        end)
        entry.members = members
    end
    return list
end

-- Stand als Anzeigetext: "fertig", "Quest fehlt" oder "3/8 · 1/1"
function ns.GroupStateText(state)
    if state == "+" then return "|cff33ff33" .. L("GQ_DONE") .. "|r" end
    if state == "-" then return "|cff8a8a8a" .. L("GQ_MISSING") .. "|r" end
    return (state or "?"):gsub(",", "  ·  ")
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("GROUP_ROSTER_UPDATE")

local progressQueued = false
local function QueueProgress()
    if progressQueued or not next(ns.groupQuests) then return end
    progressQueued = true
    C_Timer.After(1, function()
        progressQueued = false
        for questID in pairs(ns.groupQuests) do
            if MyState(questID) ~= lastSent[questID] then ns.SendGroupProgress(questID) end
        end
    end)
end

events:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
    if event == "QUEST_LOG_UPDATE" then
        QueueProgress()
        return
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not IsInGroup() then
            wipe(ns.groupQuests)
            wipe(lastSent)
            ns.trackerTab = "quests"
            if ns.RequestUpdate then ns.RequestUpdate() end
        end
        return
    end
    -- CHAT_MSG_ADDON
    if prefix ~= PREFIX or issecret(message) or issecret(sender) or type(message) ~= "string" then return end
    local name = ShortName(sender)
    if name == MyName() then return end -- eigene Nachricht kommt zurück
    local kind, id, rest = strsplit("|", message, 3)
    local questID = tonumber(id)
    if not questID then return end
    if kind == "S" then
        local isNew = ns.groupQuests[questID] == nil
        AddQuest(questID, rest)
        ns.SendGroupProgress(questID)
        ns.trackerTab = "group"
        if isNew then print(ns.ChatPrefix() .. ": " .. L("GQ_SUGGESTED", name, rest or ("Quest " .. questID))) end
    elseif kind == "P" then
        AddQuest(questID, nil)
        local _, class = UnitClass(name)
        SetMember(questID, name, rest, class)
        -- ein Nachzügler (Vorschlag verpasst) bekommt den eigenen Stand auch
        if lastSent[questID] == nil then ns.SendGroupProgress(questID) end
    elseif kind == "R" then
        ns.groupQuests[questID] = nil
        lastSent[questID] = nil
        if not next(ns.groupQuests) then ns.trackerTab = "quests" end
    end
    if ns.RequestUpdate then ns.RequestUpdate() end
end)
