local addonName, ns = ...

---------------------------------------------------------------------------
-- Automatisch annehmen/abgeben: kleines Feld im Forever-Stil, das immer rechts am Quest-Dialog (und am
-- Gesprächsfenster eines NPCs) andockt. Zwei Schalter:
--   "Quests annehmen" – angebotene Quests sofort annehmen (graue Quests nicht)
--   "Quests abgeben"  – fertige Quests abgeben; bei mehreren Belohnungen wählt man selbst, Quests, die Gold
--                       kosten, gibt man ebenfalls selbst ab
-- Shift gedrückt halten, wenn man den NPC anspricht: diesmal nichts automatisch.
-- Gespeichert in ns.db.autoAccept / ns.db.autoTurnIn (Standard: aus).
---------------------------------------------------------------------------

local L = ns.L
local WIDTH = 250
local panel

local function Paused() return IsShiftKeyDown() end
local function AcceptOn() return ns.db and ns.db.autoAccept and not Paused() end
local function TurnInOn() return ns.db and ns.db.autoTurnIn and not Paused() end

local function Build()
    local Style = ns.Style
    local C = Style.COLOR
    panel = CreateFrame("Frame", "ForeverQuestsAutoQuest", UIParent, "BackdropTemplate")
    panel:SetSize(WIDTH, 82)
    panel:SetFrameStrata("HIGH")
    Style.SetFlat(panel, C.background)
    panel:EnableMouse(true)
    panel:Hide()
    local head = panel:CreateTexture(nil, "BORDER")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(23)
    head:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", head, "LEFT", 10, 0)
    title:SetText(L("AUTO_TITLE"))
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("RIGHT", head, "RIGHT", -10, 0)
    hint:SetText(L("AUTO_SHIFT"))

    local function Toggle(key, label, tip, y)
        local check = Style.CreateCheckbox(panel, label)
        check:SetPoint("TOPLEFT", 12, y)
        check:SetScript("OnClick", function(self) ns.db[key] = self:GetChecked() and true or false end)
        check:HookScript("OnEnter", function(self)
            local tooltip = Style.GetTooltip()
            tooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltip:AddLine(label, 1, 0.82, 0)
            tooltip:AddLine(tip, 1, 1, 1, true)
            tooltip:Show()
        end)
        check:HookScript("OnLeave", function() Style.GetTooltip():Hide() end)
        check.key = key
        return check
    end
    panel.accept = Toggle("autoAccept", L("AUTO_ACCEPT"), L("AUTO_ACCEPT_TIP"), -34)
    panel.turnIn = Toggle("autoTurnIn", L("AUTO_TURNIN"), L("AUTO_TURNIN_TIP"), -58)
end

-- Feld rechts an das offene Fenster hängen (Quest-Dialog hat Vorrang vor dem Gesprächsfenster)
local function Dock()
    local frame
    for _, name in ipairs({ "QuestFrame", "GossipFrame" }) do
        local f = _G[name]
        if f and f:IsShown() then frame = f break end
    end
    if not frame then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build() end
    panel.accept:SetChecked(ns.db.autoAccept == true)
    panel.turnIn:SetChecked(ns.db.autoTurnIn == true)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    panel:Show()
end
ns.AutoQuestPanel = function() return panel and panel:IsShown() and panel or nil end

-- Gesprächsfenster: fertige Quests abgeben, neue annehmen (immer nur eine pro Schritt; danach öffnet das Spiel
-- das Fenster erneut und es geht mit der nächsten weiter)
local function OnGossip()
    if not C_GossipInfo then return end
    if TurnInOn() and C_GossipInfo.GetActiveQuests then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if quest.isComplete and quest.questID then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end
    if AcceptOn() and C_GossipInfo.GetAvailableQuests then
        for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if not quest.isTrivial and quest.questID then
                C_GossipInfo.SelectAvailableQuest(quest.questID)
                return
            end
        end
    end
end

-- Begrüßung mit Questliste (NPCs ohne Gespräch, mehrere Quests)
local function OnGreeting()
    if TurnInOn() and GetNumActiveQuests then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if AcceptOn() and GetNumAvailableQuests then
        for i = 1, GetNumAvailableQuests() do
            local isTrivial = GetAvailableQuestInfo and select(1, GetAvailableQuestInfo(i))
            if not isTrivial then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

local function OnComplete()
    if not TurnInOn() then return end
    -- Abgabe kostet Gold: selbst entscheiden
    if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices > 1 then return end -- Belohnung selbst wählen
    GetQuestReward(choices == 1 and 1 or nil)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "QUEST_FINISHED",
    "GOSSIP_SHOW", "GOSSIP_CLOSED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_DETAIL" then
        -- (Quests, die das Spiel selbst annimmt, nicht noch einmal)
        if AcceptOn() and not (QuestGetAutoAccept and QuestGetAutoAccept()) then
            AcceptQuest()
        end
    elseif event == "QUEST_PROGRESS" then
        if TurnInOn() and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        OnComplete()
    elseif event == "QUEST_GREETING" then
        OnGreeting()
    elseif event == "GOSSIP_SHOW" then
        OnGossip()
    end
    -- einen Augenblick später andocken: dann sind die Fenster offen bzw. schon wieder zu
    C_Timer.After(0, function()
        local ok, err = pcall(Dock)
        if not ok then geterrorhandler()(err) end
    end)
end)

-- Fenster zu (auch per Esc) = Feld weg bzw. an das andere noch offene Fenster
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    for _, name in ipairs({ "QuestFrame", "GossipFrame" }) do
        local f = _G[name]
        if f then
            f:HookScript("OnShow", function() C_Timer.After(0, Dock) end)
            f:HookScript("OnHide", function() C_Timer.After(0, Dock) end)
        end
    end
end)
