-- ForeverSkin – Windows.lua: die Fenster des Prototyps – NPC-Gespräch, Quest-Dialog und Händler.
-- Namen aus Retail und Classic: was es im Forever-Client nicht gibt, wird übersprungen.
local ADDON_NAME, ns = ...
local C = ns.C

local TEXT = { 0.9, 0.9, 0.9 }  -- Fließtext (statt Blizzards dunkler Pergament-Schrift)
local TITLE = C.accent           -- Überschriften gold

local function G(name) return _G[name] end

local function Color(fs, c)
    if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
end

-- Schriften in einem Rahmen (nur dessen eigene) hell; dunkle Farbcodes im Text aufhellen
local function LightenFontStrings(frame, c)
    if not frame or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("FontString") then
            Color(r, c or TEXT)
            local text = r:GetText()
            local light = ns.LightenCodes(text)
            if light ~= text then r:SetText(light) end
        end
    end
end

-- Hintergründe einer Fläche und ihrer direkten Unterflächen (z. B. Pergament der Quest-Seiten) unsichtbar;
-- Knöpfe und Bildlaufleisten bleiben
local function HidePanel(panel)
    if not panel then return end
    ns.HideTextures(panel)
    for _, child in ipairs({ panel:GetChildren() }) do
        local name = child:GetName() or ""
        if not child:IsObjectType("Button") and not child:IsObjectType("Slider") and not child:IsObjectType("EditBox")
            and not name:find("ScrollBar") and child ~= panel.ScrollBar then
            ns.HideTextures(child)
        end
    end
end

-- Gegenstands-Feld (Belohnung, benötigte Gegenstände): Namensfeld weg, flache Fläche dahinter
local function SkinItem(button)
    if not button then return end
    ns.Hide(button.NameFrame)
    local name = button:GetName()
    if name then ns.Hide(_G[name .. "NameFrame"]) end
    ns.Flat(button, C.panel) -- (Flat merkt sich selbst, ob die Fläche schon da ist – nichts in Blizzards Tabellen)
    Color(button.Name or (name and _G[name .. "Name"]), TEXT)
end

---------------------------------------------------------------------------
-- NPC-Gespräch
---------------------------------------------------------------------------
local function GossipText()
    local f = G("GossipFrame")
    if not f then return end
    local panel = f.GreetingPanel or G("GossipFrameGreetingPanel")
    local box = panel and panel.ScrollBox
    if box and box.ForEachFrame then
        box:ForEachFrame(function(element)
            LightenFontStrings(element)
            local fs = element.GetFontString and element:GetFontString()
            if fs then
                Color(fs, TEXT)
                local text = fs:GetText()
                local light = ns.LightenCodes(text)
                if light ~= text then fs:SetText(light) end
            end
        end)
    end
    -- Classic: feste Knöpfe und Begrüßungstext
    Color(G("GossipGreetingText"), TEXT)
    for i = 1, 32 do
        local b = G("GossipTitleButton" .. i)
        if not b then break end
        local fs = b:GetFontString()
        if fs then
            Color(fs, TEXT)
            local text = fs:GetText()
            local light = ns.LightenCodes(text)
            if light ~= text then fs:SetText(light) end
        end
    end
end

local function SkinGossip()
    local f = G("GossipFrame")
    if not f then return end
    ns.SkinWindow(f)
    local panel = f.GreetingPanel or G("GossipFrameGreetingPanel")
    HidePanel(panel)
    if panel and panel.ScrollBox then ns.HideTextures(panel.ScrollBox) end
    ns.ContentBox(f, 30, 87)
    ns.SkinButton((panel and panel.GoodbyeButton) or G("GossipFrameGreetingGoodbyeButton"))
    ns.Watch(f)
    ns.Scaled(f)
    local function Later() C_Timer.After(0, function() pcall(GossipText) end) end
    if type(f.Update) == "function" then hooksecurefunc(f, "Update", Later) end
    -- Text samt Laufleiste in den Kasten: oben unter die Visitenkarte (Kasten ab 80, Text 8 darunter), unten über
    -- die Knopfleiste (Kasten endet 38 über dem Rand)
    local function Place()
        if not panel then return end
        ns.Fit(f, panel.ScrollBox, 95, 44)
        ns.Fit(f, panel.ScrollBar, 95, 44, panel.ScrollBox)
        ns.Fit(f, G("GossipGreetingScrollFrame"), 95, 44)
    end
    if panel then ns.SkinScrollBar(panel.ScrollBar) end
    ns.SkinScrollBar(G("GossipGreetingScrollFrameScrollBar"))
    f:HookScript("OnShow", function()
        ns.NpcCard(f, "npc", ns.T("Gespräch", "Conversation"), ns.GossipRole)
        Later()
        C_Timer.After(0, function()
            pcall(Place)
            pcall(ns.NpcCard, f, "npc", ns.T("Gespräch", "Conversation"), ns.GossipRole) -- Optionen sind jetzt da
        end)
    end)
end

---------------------------------------------------------------------------
-- Quest-Dialog
---------------------------------------------------------------------------
local QUEST_PANELS = { "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel",
    "QuestFrameGreetingPanel", "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame",
    "QuestGreetingScrollFrame" }
local QUEST_BUTTONS = { "QuestFrameAcceptButton", "QuestFrameDeclineButton", "QuestFrameCompleteButton",
    "QuestFrameGoodbyeButton", "QuestFrameCompleteQuestButton", "QuestFrameGreetingGoodbyeButton",
    "QuestFrameCancelButton" }
local QUEST_TITLES = { "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader",
    "QuestProgressTitleText", "CurrentQuestsText", "AvailableQuestsText", "QuestProgressRequiredItemsText" }
local QUEST_TEXTS = { "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoRewardText", "QuestInfoGroupSize",
    "QuestInfoSpellObjectiveLearnLabel", "QuestInfoRequiredMoneyText", "QuestInfoTimerText", "QuestProgressText",
    "QuestProgressRequiredMoneyText", "GreetingText", "QuestGreetingText", "QuestInfoXPFrameReceiveText" }

local function QuestText()
    for _, n in ipairs(QUEST_TITLES) do Color(G(n), TITLE) end
    for _, n in ipairs(QUEST_TEXTS) do Color(G(n), TEXT) end
    for i = 1, 12 do
        local o = G("QuestInfoObjective" .. i)
        if not o then break end
        Color(o, TEXT)
    end
    local rewards = G("QuestInfoRewardsFrame")
    if rewards then
        Color(rewards.Header, TITLE)
        Color(rewards.ItemChooseText, TEXT)
        Color(rewards.ItemReceiveText, TEXT)
        Color(rewards.PlayerTitleText, TEXT)
        Color(rewards.QuestSessionBonusReward, TEXT)
        if rewards.XPFrame then Color(rewards.XPFrame.ReceiveText, TEXT) end
        for _, b in ipairs(rewards.RewardButtons or {}) do SkinItem(b) end
    end
    for i = 1, 12 do
        local b = G("QuestInfoRewardsFrameQuestInfoItem" .. i) or G("QuestInfoItem" .. i)
        if b then SkinItem(b) end
        local p = G("QuestProgressItem" .. i)
        if p then SkinItem(p) end
    end
    -- Begrüßung mit mehreren Quests: Titel-Knöpfe (dunkle Farbcodes aufhellen)
    local greet = G("QuestFrameGreetingPanel")
    if greet and greet.titleButtonPool and greet.titleButtonPool.EnumerateActive then
        for b in greet.titleButtonPool:EnumerateActive() do
            local fs = b.GetFontString and b:GetFontString()
            if fs then
                Color(fs, TEXT)
                local text = fs:GetText()
                local light = ns.LightenCodes(text)
                if light ~= text then fs:SetText(light) end
            end
        end
    end
    for i = 1, 32 do
        local b = G("QuestTitleButton" .. i)
        if not b then break end
        local fs = b:GetFontString()
        if fs then
            local text = fs:GetText()
            local light = ns.LightenCodes(text)
            if light ~= text then fs:SetText(light) end
        end
    end
end

local function SkinQuest()
    local f = G("QuestFrame")
    if not f then return end
    ns.SkinWindow(f)
    for _, n in ipairs(QUEST_PANELS) do HidePanel(G(n)) end
    for _, n in ipairs(QUEST_BUTTONS) do ns.SkinButton(G(n)) end
    ns.ContentBox(f, 30, 87)
    local function Place()
        for _, n in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame",
            "QuestGreetingScrollFrame" }) do
            local s = G(n)
            if s and s:IsShown() then
                ns.Fit(f, s, 95, 44)
                local bar = s.ScrollBar or G(n .. "ScrollBar")
                if bar then
                    ns.Fit(f, bar, 95, 44, s)
                    ns.SkinScrollBar(bar)
                end
            end
        end
    end
    f:HookScript("OnShow", function()
        ns.NpcCard(f, "questnpc", ns.T("Quest", "Quest"), function() return ns.T("Questgeber", "Quest giver") end)
        C_Timer.After(0, function() pcall(Place) end)
    end)
    for _, n in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel" }) do
        local p = G(n)
        if p then p:HookScript("OnShow", function() C_Timer.After(0, function() pcall(Place) end) end) end
    end
    ns.Watch(f)
    ns.Scaled(f)
    local function Later() C_Timer.After(0, function() pcall(QuestText) end) end
    -- Blizzard färbt die Texte je nach Hintergrund ("Pergament" = dunkel): danach wieder hell
    for _, fn in ipairs({ "QuestFrame_SetTitleTextColor", "QuestFrame_SetTextColor" }) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function(fs)
                if fs and fs.SetTextColor then
                    local c = fn == "QuestFrame_SetTitleTextColor" and TITLE or TEXT
                    fs:SetTextColor(c[1], c[2], c[3])
                end
            end)
        end
    end
    for _, fn in ipairs({ "QuestInfo_Display", "QuestFrameProgressItems_Update", "QuestFrameGreetingPanel_OnShow" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, Later) end
    end
    f:HookScript("OnShow", Later)
    for _, n in ipairs({ "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel" }) do
        local p = G(n)
        if p then p:HookScript("OnShow", Later) end
    end
end

---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local db = ns.GetDB()
    for _, w in ipairs({ { "gossip", SkinGossip }, { "quest", SkinQuest },
        { "merchant", function() if ns.SetupMerchant then ns.SetupMerchant() end end }, -- (Merchant.lua)
        { "popup", function() if ns.SkinPopups then ns.SkinPopups() end end } }) do
        if db[w[1]] then
            local ok, err = pcall(w[2])
            if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", w[1], err) end
        end
    end
end)
