local addonName, ns = ...

-- GroupQuests.lua: Quests gemeinsam machen ("Der Gruppe vorschlagen", Rechtsklick auf eine Quest im Tracker).
-- Wer eine Quest vorschlägt, teilt sie wie gewohnt mit der Gruppe (falls teilbar) und schickt allen Gruppenmitgliedern
-- mit ForeverQuests eine unsichtbare Addon-Nachricht. Bei ihnen fragt ein kleines Fenster neben dem Tracker, ob sie
-- mitmachen möchten. Wer mitmacht, hat die Quest ganz oben im Tracker angeheftet ("Gemeinsam") – mit dem Stand aller,
-- die mitmachen. Jeder meldet seinen Fortschritt, sobald er sich ändert.
-- Nachrichten (Kennung "FQGRP"):
--   S|<questID>|<Titel>   vorgeschlagen (Absender macht selbst mit)
--   A|<questID>           macht mit
--   D|<questID>           macht nicht mit
--   P|<questID>|<Stand>   eigener Stand: "-" = Quest nicht im Questlog, "+" = fertig, sonst "3/8,1/1" je Ziel
--   L|<questID>           macht nicht mehr mit (früher "R": wird genauso behandelt)
-- Nur für diese Sitzung (verlässt man die Gruppe, ist alles leer).

local L = ns.L
local PREFIX = "FQGRP"
local INVITE_TIMEOUT = 60 -- Sekunden, dann verschwindet die Anfrage (gilt als "keine Antwort")
local issecret = issecretvalue or function() return false end

ns.groupQuests = {}   -- [questID] = { title, order, members = { [Name] = { state, class } } } – nur Quests, bei denen ich mitmache
ns.trackerTab = "quests" -- (alter Reiter "Gruppe" entfällt; gemeinsame Quests stehen oben in der normalen Liste)
local order = 0
local lastSent = {}   -- [questID] = zuletzt gesendeter eigener Stand
local invites = {}    -- offene Anfragen: { questID, title, from }

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

-- Einheitlicher Name: nur der Vorname. In Forever kommen Namen verschieden an – UnitName("player") liefert
-- "Vorname", Addon-Nachrichten "Vorname Nachname-Realm". Ohne Angleichen stand man selbst doppelt in der Liste
-- (einmal als "Du", einmal mit vollem Namen). Der Vorname passt auch zu UnitClass(name) bei Gruppenmitgliedern.
local function ShortName(name)
    if not name or issecret(name) then return nil end
    if Ambiguate then name = Ambiguate(name, "short") end
    return name:match("^[^%s%-]+") or name
end

local function MyName() return ShortName(UnitName("player")) end

local function Print(text) print(ns.ChatPrefix() .. ": " .. text) end

local function QuestTitle(questID, fallback)
    return (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or fallback or ("Quest " .. questID)
end

local function ClassOf(name)
    local _, class = UnitClass(name)
    if issecret(class) then return nil end
    return class
end

local function AddQuest(questID, title)
    if ns.groupQuests[questID] then return ns.groupQuests[questID] end
    order = order + 1
    local q = { title = QuestTitle(questID, title), order = order, members = {} }
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
    local m = q.members[name] or {}
    m.state = state or m.state
    m.class = class or m.class
    q.members[name] = m
end

function ns.SendGroupProgress(questID)
    if not ns.groupQuests[questID] then return end
    local state = MyState(questID)
    SetMember(questID, MyName(), state, select(2, UnitClass("player")))
    lastSent[questID] = state
    Send("P|" .. questID .. "|" .. state)
end

local function Refresh()
    if ns.RequestUpdate then ns.RequestUpdate() end
end

---------------------------------------------------------------------------
-- Anfrage-Fenster neben dem Tracker (unaufdringlich: klein, ohne Ton, verschwindet nach einer Minute von selbst)
---------------------------------------------------------------------------
local dialog
local ShowNextInvite

local function RemoveInvite(questID)
    for i = #invites, 1, -1 do
        if invites[i].questID == questID then table.remove(invites, i) end
    end
end

local function PlaceDialog()
    local tracker = _G.ForeverQuestsTracker
    dialog:ClearAllPoints()
    if tracker and tracker:IsShown() and tracker:GetLeft() then
        -- auf der Seite des Trackers, die zur Bildschirmmitte zeigt
        local center = tracker:GetCenter() * tracker:GetEffectiveScale()
        local onRight = center > (UIParent:GetWidth() * UIParent:GetEffectiveScale()) / 2
        if onRight then
            dialog:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -8, 0)
        else
            dialog:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 8, 0)
        end
    else
        dialog:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -260)
    end
end

local function Answer(accept)
    local invite = dialog and dialog.invite
    if not invite then return end
    dialog.invite = nil
    dialog:Hide()
    RemoveInvite(invite.questID)
    if accept then
        AddQuest(invite.questID, invite.title)
        Send("A|" .. invite.questID)
        ns.SendGroupProgress(invite.questID)
        Refresh()
    else
        Send("D|" .. invite.questID)
    end
    C_Timer.After(0.3, ShowNextInvite)
end

local function BuildDialog()
    if dialog then return dialog end
    local Style, C = ns.Style, ns.Style.COLOR
    dialog = CreateFrame("Frame", "ForeverQuestsGroupInvite", UIParent, "BackdropTemplate")
    dialog:SetSize(230, 112)
    dialog:SetFrameStrata("HIGH")
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    Style.SetFlat(dialog, C.background)
    local accent = dialog:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)
    accent:SetHeight(1)
    accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)

    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dialog.title:SetPoint("TOPLEFT", 10, -9)
    dialog.title:SetText(L("GQ_INVITE_TITLE"))
    dialog.from = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dialog.from:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -5)
    dialog.from:SetPoint("RIGHT", -10, 0)
    dialog.from:SetJustifyH("LEFT")
    dialog.quest = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.quest:SetPoint("TOPLEFT", dialog.from, "BOTTOMLEFT", 0, -3)
    dialog.quest:SetPoint("RIGHT", -10, 0)
    dialog.quest:SetJustifyH("LEFT")
    dialog.quest:SetTextColor(1, 1, 1)
    dialog.hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dialog.hint:SetPoint("TOPLEFT", dialog.quest, "BOTTOMLEFT", 0, -2)
    dialog.hint:SetPoint("RIGHT", -10, 0)
    dialog.hint:SetJustifyH("LEFT")

    dialog.yes = Style.CreateButton(dialog, L("GQ_ACCEPT"), 100, 20, function() Answer(true) end)
    dialog.yes:SetPoint("BOTTOMLEFT", 10, 8)
    dialog.yes:GetFontString():SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    dialog.no = Style.CreateButton(dialog, L("GQ_DECLINE"), 100, 20, function() Answer(false) end)
    dialog.no:SetPoint("BOTTOMRIGHT", -10, 8)

    -- schmaler Zeitbalken unten: so lange bleibt die Anfrage stehen
    dialog.timer = dialog:CreateTexture(nil, "ARTWORK")
    dialog.timer:SetPoint("BOTTOMLEFT", 1, 1)
    dialog.timer:SetHeight(2)
    dialog.timer:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5)
    dialog:SetScript("OnUpdate", function(self)
        if not self.invite then return end
        local left = self.invite.expires - GetTime()
        if left <= 0 then
            -- keine Antwort: einfach schließen, nichts senden
            RemoveInvite(self.invite.questID)
            self.invite = nil
            self:Hide()
            C_Timer.After(0.3, ShowNextInvite)
            return
        end
        self.timer:SetWidth(math.max(1, (self:GetWidth() - 2) * left / INVITE_TIMEOUT))
    end)
    dialog:Hide()
    return dialog
end

ShowNextInvite = function()
    if dialog and dialog.invite then return end
    local invite = invites[1]
    if not invite then return end
    if ns.groupQuests[invite.questID] then -- inzwischen schon dabei
        RemoveInvite(invite.questID)
        return ShowNextInvite()
    end
    BuildDialog()
    invite.expires = GetTime() + INVITE_TIMEOUT
    dialog.invite = invite
    dialog.from:SetText(L("GQ_INVITE_FROM", invite.from))
    dialog.quest:SetText(QuestTitle(invite.questID, invite.title))
    local inLog = C_QuestLog.GetLogIndexForQuestID(invite.questID) ~= nil
    dialog.hint:SetText(inLog and "" or L("GQ_INVITE_MISSING"))
    dialog:SetHeight(inLog and 100 or 112)
    PlaceDialog()
    dialog:Show()
end

---------------------------------------------------------------------------
-- Vorschlagen, Verlassen, Anzeige
---------------------------------------------------------------------------
function ns.SuggestQuest(questID)
    if not IsInGroup() then return end
    local title = QuestTitle(questID)
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
    Print(L("GQ_SENT", title))
    Refresh()
end

-- selbst nicht mehr mitmachen (die anderen nehmen mich aus ihrer Liste)
function ns.RemoveGroupQuest(questID, broadcast)
    ns.groupQuests[questID] = nil
    lastSent[questID] = nil
    if broadcast ~= false then Send("L|" .. questID) end
    Refresh()
end

function ns.HasGroupQuests() return next(ns.groupQuests) ~= nil end
function ns.IsGroupQuest(questID) return ns.groupQuests[questID] ~= nil end

-- Für die Anzeige: Quests in Vorschlags-Reihenfolge, je Quest die Teilnehmer (man selbst zuerst)
function ns.GroupQuestList()
    local list = {}
    for questID, q in pairs(ns.groupQuests) do list[#list + 1] = { questID = questID, data = q } end
    table.sort(list, function(a, b) return a.data.order < b.data.order end)
    local me = MyName()
    for _, entry in ipairs(list) do
        local members = {}
        for name, m in pairs(entry.data.members) do
            members[#members + 1] = { name = name, state = m.state, class = m.class, me = name == me }
        end
        table.sort(members, function(a, b)
            if a.me ~= b.me then return a.me end
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
    if not state then return "|cff8a8a8a…|r" end
    return (state:gsub(",", "  ·  "))
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
            wipe(invites)
            if dialog then dialog.invite = nil dialog:Hide() end
            Refresh()
        end
        return
    end
    -- CHAT_MSG_ADDON
    if prefix ~= PREFIX or issecret(message) or issecret(sender) or type(message) ~= "string" then return end
    local name = ShortName(sender)
    if not name or name == MyName() then return end -- eigene Nachricht kommt zurück
    local kind, id, rest = strsplit("|", message, 3)
    local questID = tonumber(id)
    if not questID then return end
    local q = ns.groupQuests[questID]
    if kind == "S" then
        if q then
            -- mache schon mit (z. B. beide gleichzeitig vorgeschlagen): Vorschlagenden aufnehmen
            SetMember(questID, name, nil, ClassOf(name))
            ns.SendGroupProgress(questID)
        else
            RemoveInvite(questID)
            invites[#invites + 1] = { questID = questID, title = rest, from = name }
            ShowNextInvite()
        end
    elseif kind == "A" then
        if q then
            SetMember(questID, name, nil, ClassOf(name))
            ns.SendGroupProgress(questID) -- der Neue bekommt meinen Stand
            Print(L("GQ_JOINED", name, q.title))
        end
    elseif kind == "D" then
        if q then Print(L("GQ_DECLINED", name, q.title)) end
    elseif kind == "P" then
        -- nur von Mitmachenden (wer nur gefragt wurde, sendet keinen Stand)
        if q then SetMember(questID, name, rest, ClassOf(name)) end
    elseif kind == "L" or kind == "R" then
        if q then q.members[name] = nil end
        -- zog jemand seinen Vorschlag zurück, verschwindet auch die offene Anfrage
        for _, invite in ipairs(invites) do
            if invite.questID == questID and invite.from == name then RemoveInvite(questID) break end
        end
        if dialog and dialog.invite and dialog.invite.questID == questID and dialog.invite.from == name then
            dialog.invite = nil
            dialog:Hide()
            C_Timer.After(0.3, ShowNextInvite)
        end
    end
    Refresh()
end)
