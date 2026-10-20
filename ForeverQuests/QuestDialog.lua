local addonName, ns = ...

---------------------------------------------------------------------------
-- Questreihe am Quest-Dialog: bietet ein NPC eine Quest an (oder man gibt sie ab), steht rechts neben Blizzards
-- Quest-Fenster ein kleines Feld im Forever-Stil mit der ganzen Questreihe aus Questies Datenbank – wie in der
-- Detailansicht des Questlogs: erledigt = grün mit Haken, diese Quest = gold, im Questlog = blau, sonst grau.
-- Maus über einer Zeile: Stufe und Ziele; Rechtsklick: Wowhead-Link. Nur mit Questie und wenn es eine Reihe gibt.
-- Blizzards Fenster bleibt unberührt (das Feld hängt nur daneben). Abschaltbar: ns.db.dialogChain = false.
---------------------------------------------------------------------------

local WIDTH = 250
local ROW_GAP = 2
local panel

local function Build()
    local Style = ns.Style
    local C = Style.COLOR
    panel = CreateFrame("Frame", "ForeverQuestsDialogChain", UIParent, "BackdropTemplate")
    panel:SetWidth(WIDTH)
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
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("LEFT", head, "LEFT", 10, 0)
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.count:SetPoint("LEFT", panel.title, "RIGHT", 8, 0)
    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.hint:SetPoint("BOTTOMLEFT", 10, 8)
    panel.hint:SetPoint("BOTTOMRIGHT", -10, 8)
    panel.hint:SetJustifyH("LEFT")
    panel.rows = {}
end

local function Row(i)
    local row = panel.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel)
    row:RegisterForClicks("RightButtonUp")
    row.view = { anchor = "ANCHOR_RIGHT" } -- Tooltip-Seite für den Tracker-Tooltip
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", 2, -1)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(true)
    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        -- derselbe Tooltip wie bei der Questreihe im Questlog: Ziele, Questgeber/Abgabe und alle Belohnungen
        if ns.ChainTooltip then
            ns.ChainTooltip(self)
            local tip = ns.Style.GetTooltip()
            if tip:IsShown() then
                tip:AddLine(" ")
                tip:AddLine(ns.L("TIP_RIGHTCLICK_WOWHEAD"), 0.5, 0.5, 0.5)
                tip:Show()
            end
            return
        end
        local tip = ns.Style.GetTooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:AddLine(e.name or ("Quest #" .. e.questID), 1, 0.82, 0)
        if e.level and e.level > 0 then
            tip:AddLine((LEVEL or "Level") .. " " .. e.level
                .. ((e.requiredLevel and e.requiredLevel > 0) and ("  ·  " .. ns.L("TIP_MIN_LEVEL_SHORT", e.requiredLevel)) or ""),
                0.8, 0.8, 0.8)
        end
        if type(e.objectives) == "table" then
            for _, o in ipairs(e.objectives) do
                if type(o) == "string" and o ~= "" then tip:AddLine(o, 1, 1, 1, true) end
            end
        end
        if ns.ShowQuestieWowhead then tip:AddLine(ns.L("TIP_RIGHTCLICK_WOWHEAD"), 0.5, 0.5, 0.5) end
        tip:Show()
    end)
    row:SetScript("OnLeave", function() ns.Style.GetTooltip():Hide() end)
    row:SetScript("OnClick", function(self)
        if self.entry and ns.ShowQuestieWowhead then ns.ShowQuestieWowhead(self.entry.questID) end
    end)
    panel.rows[i] = row
    return row
end

local function Refresh()
    local frame = _G.QuestFrame
    local questID = GetQuestID and GetQuestID()
    if not frame or not frame:IsShown() or not questID or questID == 0 or (ns.db and ns.db.dialogChain == false) then
        if panel then panel:Hide() end
        return
    end
    local chain = ns.GetQuestChain and ns.GetQuestChain(questID)
    if not chain then
        if panel then panel:Hide() end
        return
    end
    if not panel then Build() end
    local C = ns.Style.COLOR
    local position = 0
    for i, e in ipairs(chain) do if e.questID == questID then position = i end end
    panel.title:SetText(ns.L("DETAIL_CHAIN"))
    panel.count:SetText(position > 0 and (position .. " / " .. #chain) or #chain)
    local y = 32
    for i, e in ipairs(chain) do
        local row = Row(i)
        local label = (e.name or ("Quest #" .. e.questID))
            .. ((e.level and e.level > 0) and (" (" .. e.level .. ")") or "")
        local done = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(e.questID)
        local inLog = C_QuestLog.GetLogIndexForQuestID(e.questID) ~= nil
        local text, r, g, b = i .. ". " .. label, 0.6, 0.6, 0.6
        if e.questID == questID then
            r, g, b = C.accent[1], C.accent[2], C.accent[3]
            row.text:SetFontObject("GameFontNormal")
        else
            row.text:SetFontObject("GameFontHighlightSmall")
            if done then
                text, r, g, b = text .. "  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t", 0.45, 0.85, 0.45
            elseif inLog then
                text, r, g, b = text .. "  |cff88ccff" .. ns.L("DETAIL_IN_LOG") .. "|r", 0.85, 0.85, 0.85
            end
        end
        if ns.db and ns.db.showQuestIDs then text = text .. "  |cff6a6a6a#" .. e.questID .. "|r" end
        row.entry, row.done, row.inLog = e, done, inLog
        row.text:SetWidth(WIDTH - 24)
        row.text:SetText(text)
        row.text:SetTextColor(r, g, b)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -y)
        row:SetSize(WIDTH - 20, row.text:GetStringHeight() + 2)
        row:Show()
        y = y + row:GetHeight() + ROW_GAP
    end
    for i = #chain + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.hint:SetText(ns.ShowQuestieWowhead and ns.L("TIP_RIGHTCLICK_WOWHEAD") or "")
    panel:SetHeight(y + 26)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
    panel:Show()
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_GREETING" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if event == "QUEST_FINISHED" or event == "QUEST_GREETING" then
        if panel then panel:Hide() end
        return
    end
    -- einen Augenblick später: dann ist das Fenster offen und die Quest-ID gesetzt
    C_Timer.After(0, function()
        local ok, err = pcall(Refresh)
        if not ok then geterrorhandler()(err) end
    end)
end)

-- Fenster zu (auch per Esc) = Feld weg
local hooked = false
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if _G.QuestFrame and not hooked then
        hooked = true
        _G.QuestFrame:HookScript("OnHide", function() if panel then panel:Hide() end end)
    end
end)
