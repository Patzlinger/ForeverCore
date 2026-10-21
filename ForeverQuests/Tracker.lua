local addonName, ns = ...

local tracker, title, scrollFrame, content, overlay, filterButton, headerBar
local menuButton, dungeonButton, unlockHint
local updatePending = false

-- Zeichenziel ("Ansicht"): der Tracker oder der Questlog an der Weltkarte (QuestLog.lua). Beide benutzen dieselben
-- Zeilen, Fenster, Tooltips und Menüs; jede Ansicht hat ihre eigenen Zeilen und eingeklappten Gebiete.
-- Felder: content (Rahmen, in den gezeichnet wird), lines, boxes, prefix (Namen der Zeilen), collapsed,
-- anchor (Tooltip-Seite), expanded (eigener Auf-/Zuklapp-Stand; nur Questlog), watchToggle (Häkchen "verfolgen")
local trackerView = { lines = {}, boxes = {}, prefix = "ForeverQuestsTracker", anchor = "ANCHOR_LEFT" }
local view = trackerView
local lines = trackerView.lines

-- Aufgeklappt-Zustand je Quest, per Pfeil gesetzt (true/false).
-- Fehlt ein Eintrag, gilt die Menü-Einstellung bzw. das automatische Aufklappen.
ns.expanded = {}
-- Zeitpunkt, zu dem eine Quest wegen Fortschritt automatisch aufgeklappt wurde
ns.autoExpandedAt = {}
-- Letzter bekannter Fortschritt je Quest, um Änderungen zu erkennen
local progressSnapshots = {}

-- Beste Belohnungs-Seltenheit je Quest (wird nur gespeichert, wenn alle Daten geladen waren)
local rewardQualityCache = {}
local waitingForItemData = false

local ARROW_TEXTURE = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local ICON_SIZE = 12
local REWARD_ICON_ATLAS = "VignetteLoot"
local REWARD_ICON_TEXTURE = "Interface\\Icons\\INV_Box_02"
local REWARD_ICON_SIZE = 14
local QUEST_ITEM_SIZE = 20 -- Questgegenstand (anklickbar, darum etwas größer als die Truhe)
local BOX_GAP = 8     -- Abstand zwischen den Fenstern der Gebiete
local BOX_PADDING = 6 -- Innenabstand in den Fenstern

-- Feste Farben der Überschriften (Klassenquests bekommen die Klassenfarbe)
local HEADER_COLORS = {
    zone = { 1.00, 0.82, 0.00 },       -- Gebiete und alles andere: Gelb
    pinned = { 1.00, 0.20, 0.20 },     -- Angeheftet: Rot
    reputation = { 0.25, 0.55, 1.00 }, -- Ruf: Blau
}

---------------------------------------------------------------------------
-- Blizzard-Questtracker ausblenden
---------------------------------------------------------------------------

-- Je nach Client-Version heißt der Blizzard-Tracker unterschiedlich
local BLIZZARD_TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame" }
local hookedFrames = {}
local blizzardUpdatePending = false

-- Schwierigkeitsfarbe nach den klassischen Erfahrungsregeln (gemeinsam im ForeverHub, wie bei Gegnern in
-- ForeverUnits); Blizzards GetQuestDifficultyColor faerbt im Forever-Client zu frueh grau
local function LevelColor()
    local hub = _G.ForeverHub and _G.ForeverHub.UI
    return (hub and hub.LevelColor) or _G.GetQuestDifficultyColor
end

-- Nach dem Kampf erneut versuchen: über die gemeinsame Warteschlange im ForeverHub
-- (ohne Hub wie bisher über PLAYER_REGEN_ENABLED, siehe unten)
local function RetryAfterCombat()
    local UI = _G.ForeverHub and _G.ForeverHub.UI
    if UI and UI.AfterCombat then
        UI.AfterCombat("ForeverQuests:blizzardTracker", function() ns.UpdateBlizzardTracker() end, addonName)
    else
        blizzardUpdatePending = true
    end
end

-- Unsichtbar machen (Deckkraft 0) geht auch im Kampf: Blizzard zeigt den Tracker z. B. beim Aufsammeln von
-- Questgegenständen neu an – im Kampf darf er nicht versteckt werden, bliebe also bis Kampfende sichtbar.
-- Der Hub hält die Deckkraft auf 0, solange "Blizzard-Questtracker ausblenden" an ist.
local function HoldInvisible(frame)
    local UI = _G.ForeverHub and _G.ForeverHub.UI
    if not (UI and UI.HideBlizzard) then return end
    if ns.db.hideBlizzard then
        UI.HideBlizzard(frame, { children = false, when = function() return ns.db.hideBlizzard end })
    elseif UI.ShowBlizzard then
        UI.ShowBlizzard(frame)
    end
end

function ns.UpdateBlizzardTracker()
    for _, name in ipairs(BLIZZARD_TRACKERS) do
        if _G[name] then HoldInvisible(_G[name]) end
    end
    -- Im Kampf darf der Blizzard-Tracker nicht verändert werden (Questgegenstand-Knöpfe sind geschützt)
    if InCombatLockdown() then
        RetryAfterCombat()
        return
    end
    blizzardUpdatePending = false

    for _, name in ipairs(BLIZZARD_TRACKERS) do
        local frame = _G[name]
        if frame then
            if not hookedFrames[frame] then
                hookedFrames[frame] = true
                frame:HookScript("OnShow", function(self)
                    if not ns.db.hideBlizzard then return end
                    if InCombatLockdown() then
                        RetryAfterCombat()
                    else
                        self:Hide()
                    end
                end)
            end
            if ns.db.hideBlizzard then
                frame:Hide()
            else
                frame:Show()
            end
        end
    end
end

---------------------------------------------------------------------------
-- Farben und Schrift
---------------------------------------------------------------------------

local fonts = {}

-- Eigene Schrift-Objekte für Überschriften, Questnamen und Fortschritt
function ns.UpdateFonts()
    local db = ns.db
    if not fonts.header then
        fonts.header = CreateFont("ForeverQuestsFontHeader")
        fonts.quest = CreateFont("ForeverQuestsFontQuest")
        fonts.objective = CreateFont("ForeverQuestsFontObjective")
    end

    local path = STANDARD_TEXT_FONT
    for _, font in ipairs(ns.FONTS) do
        if font.key == db.font then
            path = font.path
        end
    end
    local flags = db.fontOutline and "OUTLINE" or ""
    local sizes = {
        header = db.fontSize + 1,
        quest = db.fontSize,
        objective = math.max(6, db.fontSize - 1),
    }
    for key, size in pairs(sizes) do
        local fontObject = fonts[key]
        -- Falls die Schriftdatei fehlt, auf die Standardschrift zurückfallen
        if not fontObject:SetFont(path, size, flags) then
            fontObject:SetFont(STANDARD_TEXT_FONT, size, flags)
        end
        fontObject:SetShadowColor(0, 0, 0, 1)
        fontObject:SetShadowOffset(1, -1)
    end
end

---------------------------------------------------------------------------
-- Questtyp erkennen (Klasse / Ruf)
---------------------------------------------------------------------------

-- Klassenname (z. B. "Kriegerin") -> interner Klassenname (z. B. "WARRIOR")
local classFiles
local function GetClassFileForHeader(header)
    if not classFiles then
        classFiles = {}
        for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
            if names then
                for classFile, name in pairs(names) do
                    classFiles[name] = classFile
                end
            end
        end
    end
    return header and classFiles[header]
end

local factionNames = {}
local function BuildFactionNames()
    wipe(factionNames)
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() do
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data and data.name then
                factionNames[data.name] = true
            end
        end
    end
end

local function IsReputationHeader(header)
    return header == REPUTATION or header == "Reputation" or factionNames[header] == true
end

-- Berufe: Namen werden vom Spiel in der eingestellten Sprache geholt
local PROFESSION_SKILL_LINES = { 171, 164, 333, 202, 182, 773, 755, 165, 186, 393, 197, 185, 129, 356, 794 }
local professionNames
local function IsProfessionHeader(header)
    if not header then return false end
    if not professionNames then
        professionNames = {}
        if TRADE_SKILLS then
            professionNames[TRADE_SKILLS] = true -- "Berufe"
        end
        if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
            for _, skillLine in ipairs(PROFESSION_SKILL_LINES) do
                local name = C_TradeSkillUI.GetTradeSkillDisplayName(skillLine)
                if name and name ~= "" then
                    professionNames[name] = true
                end
            end
        end
    end
    return professionNames[header] == true
end

-- Blizzard-Kennzeichnung einer Quest (Dungeon, Schlachtzug, Gruppe, PvP …)
local QUEST_TAG = Enum and Enum.QuestTag or {}
local TAG_GROUP = QUEST_TAG.Group or 1
local TAG_PVP = QUEST_TAG.PvP or 41
local TAG_RAID = QUEST_TAG.Raid or 62
local TAG_DUNGEON = QUEST_TAG.Dungeon or 81
local TAG_HEROIC = QUEST_TAG.Heroic or 85
local TAG_RAID10 = QUEST_TAG.Raid10 or 88
local TAG_RAID25 = QUEST_TAG.Raid25 or 89

local function GetQuestTag(questID)
    if not C_QuestLog.GetQuestTagInfo then return nil end
    return C_QuestLog.GetQuestTagInfo(questID)
end

-- Liefert die Typ-Kennzeichnungen einer Quest, z. B. "[Klasse]" oder "[Ruf] [Gruppe]"
local function GetQuestTypeText(questID, header)
    local tags = {}
    if header then
        if GetClassFileForHeader(header) then
            table.insert(tags, ns.L("TAG_CLASS"))
        elseif IsReputationHeader(header) then
            table.insert(tags, ns.L("TAG_REPUTATION"))
        elseif IsProfessionHeader(header) then
            table.insert(tags, ns.L("TAG_PROFESSION"))
        end
    end
    if C_QuestLog.GetQuestTagInfo then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo and tagInfo.tagName and tagInfo.tagName ~= "" then
            table.insert(tags, "[" .. tagInfo.tagName .. "]")
        end
    end
    return table.concat(tags, " ")
end

-- Farbe einer Überschrift: Angeheftet rot, Ruf blau, Klasse in Klassenfarbe, alles andere gelb
local function GetHeaderColor(group)
    if group.pinned then
        return unpack(HEADER_COLORS.pinned)
    end
    local header = group.header
    if not header then
        return unpack(HEADER_COLORS.zone)
    end
    local classFile = GetClassFileForHeader(header)
    if classFile then
        local color = (C_ClassColor and C_ClassColor.GetClassColor(classFile))
            or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
        if color then
            return color.r, color.g, color.b
        end
    end
    if IsReputationHeader(header) then
        return unpack(HEADER_COLORS.reputation)
    end
    return unpack(HEADER_COLORS.zone)
end

---------------------------------------------------------------------------
-- Belohnungen
---------------------------------------------------------------------------

-- Höchste Seltenheit unter den Gegenstandsbelohnungen einer Quest (-1 = keine Gegenstände)
local function GetBestRewardQuality(questID)
    local cached = rewardQualityCache[questID]
    if cached then return cached end

    local best, complete = -1, true
    local function Check(name, quality, itemID)
        if not name or quality == nil or quality < 0 then
            -- Gegenstandsdaten noch nicht geladen: anfordern und später erneut prüfen
            complete = false
            if itemID and C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemID)
            end
        elseif quality > best then
            best = quality
        end
    end

    -- Die Auswahl-Belohnungen werden für die "ausgewählte" Quest abgefragt;
    -- danach wird die vorherige Auswahl wiederhergestellt
    local previous = C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(questID)
    for i = 1, GetNumQuestLogRewards(questID) do
        local name, _, _, quality, _, itemID = GetQuestLogRewardInfo(i, questID)
        Check(name, quality, itemID)
    end
    for i = 1, GetNumQuestLogChoices(questID) do
        local name, _, _, quality, _, itemID = GetQuestLogChoiceInfo(i)
        Check(name, quality, itemID)
    end
    C_QuestLog.SetSelectedQuest(previous or 0)

    if complete then
        rewardQualityCache[questID] = best
    else
        waitingForItemData = true
    end
    return best
end

---------------------------------------------------------------------------
-- Auf-/Zuklappen
---------------------------------------------------------------------------

function ns.IsExpanded(questID)
    local value = ns.expanded[questID]
    if value ~= nil then
        return value
    end
    if ns.autoExpandedAt[questID] then
        return true
    end
    return not ns.db.hideObjectives
end

-- Merkt sich den Fortschritt einer Quest und klappt sie auf, wenn er sich geändert hat
local function CheckProgress(questID, objectives, isComplete)
    local parts = { isComplete and "1" or "0" }
    for _, objective in ipairs(objectives) do
        table.insert(parts, (objective.numFulfilled or 0) .. (objective.finished and "f" or ""))
    end
    local snapshot = table.concat(parts, ",")
    local previous = progressSnapshots[questID]
    progressSnapshots[questID] = snapshot
    if previous and previous ~= snapshot then
        -- Von Hand aufgeklappte Quests bleiben offen, alle anderen klappen automatisch auf
        if ns.expanded[questID] ~= true then
            ns.expanded[questID] = nil
            ns.autoExpandedAt[questID] = GetTime()
        end
    end
end

-- Läuft regelmäßig: klappt Quests wieder ein, die seit der im Menü eingestellten Zeit keinen Fortschritt hatten
local function CheckAutoCollapse()
    local now, changed = GetTime(), false
    local seconds = (ns.db.autoCollapseMinutes or 5) * 60
    for questID, expandedAt in pairs(ns.autoExpandedAt) do
        if now - expandedAt >= seconds then
            ns.autoExpandedAt[questID] = nil
            changed = true
        end
    end
    if changed then
        ns.RequestUpdate()
    end
end

---------------------------------------------------------------------------
-- Rechtsklick-Menü einer Quest
---------------------------------------------------------------------------

local function AbandonQuest(questID)
    if QuestMapQuestOptions_AbandonQuest then
        -- Blizzard-Funktion, inklusive Sicherheitsabfrage
        QuestMapQuestOptions_AbandonQuest(questID)
    else
        C_QuestLog.SetSelectedQuest(questID)
        C_QuestLog.SetAbandonQuest()
        StaticPopup_Show("ABANDON_QUEST", C_QuestLog.GetTitleForQuestID(questID) or "")
    end
end

-- Quest teilen (Blizzards Weg). Das Spiel sperrt das für Addons im Kampf (ADDON_ACTION_BLOCKED "QuestLogPushQuest")
-- – dann nach dem Kampf teilen und das im Chat sagen. Alle Teilen-Knöpfe (Tracker, Questlog, Dungeonfenster,
-- "Zusammen") laufen hierüber.
local function ShareQuest(questID)
    if not questID then return end
    if InCombatLockdown() then
        local hub = _G.ForeverHub and _G.ForeverHub.UI
        if hub and hub.AfterCombat then
            hub.AfterCombat("ForeverQuests:share" .. questID, function() ShareQuest(questID) end, addonName)
            print(ns.ChatPrefix() .. ": " .. ns.L("SHARE_AFTER_COMBAT"))
        end
        return
    end
    if QuestMapQuestOptions_ShareQuest then
        QuestMapQuestOptions_ShareQuest(questID)
    else
        C_QuestLog.SetSelectedQuest(questID)
        QuestLogPushQuest()
    end
end
ns.PushQuest = ShareQuest

local function TogglePinned(questID)
    if ns.db.pinned[questID] then
        ns.db.pinned[questID] = nil
    else
        ns.db.pinned[questID] = true
    end
    ns.UpdateTracker()
end

-- Rechtsklick-Menü im eigenen flachen Stil (siehe Style.ShowMenu), an der Mausposition
-- inLog = Menü aus dem Questlog an der Karte (nur dort gibt es den Wowhead-Link)
local function OpenQuestMenu(owner, questID, inLog)
    if inLog == nil then inLog = owner and owner.view and owner.view.watchToggle or false end
    local items = {
        { title = C_QuestLog.GetTitleForQuestID(questID) or "Quest" },
        {
            -- Questdetails auf der Karte (geht im Kampf nicht)
            text = ns.L("MENU_DETAILS"),
            disabled = InCombatLockdown() or not QuestMapFrame_OpenToQuestDetails,
            onClick = function() QuestMapFrame_OpenToQuestDetails(questID) end,
        },
        {
            text = ns.L(ns.db.pinned[questID] and "MENU_UNPIN" or "MENU_PIN"),
            onClick = function() TogglePinned(questID) end,
        },
        {
            -- Teilen geht nur in einer Gruppe und nur bei teilbaren Quests
            text = ns.L("MENU_SHARE"),
            disabled = not (IsInGroup() and C_QuestLog.IsPushableQuest(questID)),
            onClick = function() ShareQuest(questID) end,
        },
        (ns.IsGroupQuest and ns.IsGroupQuest(questID)) and {
            -- schon gemeinsam (Fenster "Gemeinsam" oben): beenden
            text = ns.L("GQ_LEAVE"),
            onClick = function() ns.RemoveGroupQuest(questID, true) end,
        } or {
            -- Der Gruppe vorschlagen: wer mitmacht, hat sie oben unter "Gemeinsam" samt Fortschritt aller
            text = ns.L("MENU_SUGGEST"),
            disabled = not IsInGroup(),
            onClick = function() if ns.SuggestQuest then ns.SuggestQuest(questID) end end,
        },
    }
    if C_QuestLog.GetQuestWatchType(questID) then
        table.insert(items, {
            text = ns.L("MENU_UNTRACK"),
            onClick = function() C_QuestLog.RemoveQuestWatch(questID) end,
        })
    end
    -- Questie-Befehle (Fokus, Abgabe auf der Karte, Wegpunkt, Wowhead), nur wenn Questie läuft
    if ns.AddQuestieMenuItems then ns.AddQuestieMenuItems(items, questID, inLog) end
    table.insert(items, { divider = true })
    table.insert(items, {
        text = ns.L("MENU_ABANDON"),
        color = { 1, 0.3, 0.3 },
        onClick = function() AbandonQuest(questID) end,
    })
    ns.Style.ShowMenu(owner, items, { atCursor = true })
end

---------------------------------------------------------------------------
-- Zeilen und Rahmen im Tracker
---------------------------------------------------------------------------

-- Eingeklappte Gebiete (nur für diese Sitzung): [Schlüssel] = true
ns.collapsedGroups = {}
trackerView.collapsed = ns.collapsedGroups

-- Ansicht neu zeichnen (der Tracker zeichnet den offenen Questlog gleich mit)
local function Redraw(v)
    if v and v ~= trackerView then
        if ns.UpdateQuestLog then ns.UpdateQuestLog() end
    else
        ns.UpdateTracker()
    end
end

local function ToggleGroup(v, groupKey)
    v = v or trackerView
    v.collapsed[groupKey] = not v.collapsed[groupKey] or nil
    Redraw(v)
end

-- Aufgeklappt in dieser Ansicht? (Questlog: eigener Stand, Standard aufgeklappt)
local function IsExpandedIn(v, questID)
    if v and v.expanded then
        local value = v.expanded[questID]
        if value == nil then return v.expandedDefault == true end
        return value
    end
    return ns.IsExpanded(questID)
end

-- Tooltip-Seite je Ansicht (Tracker: links, Questlog: rechts); owner ist die Zeile oder ein Symbol darauf
local function AnchorOf(owner)
    local v = owner and (owner.view or (owner.GetParent and owner:GetParent() and owner:GetParent().view))
    return (v and v.anchor) or "ANCHOR_LEFT"
end

---------------------------------------------------------------------------
-- Tooltip einer Quest im Tracker: Beschreibung, Ziele und Belohnungen
---------------------------------------------------------------------------

local TOOLTIP_DESCRIPTION_LENGTH = 300 -- längere Beschreibungen werden gekürzt

local function QualityHex(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and color.hex or "|cffffffff"
end

local function RewardText(name, texture, count, quality)
    local text = (texture and ("|T" .. texture .. ":14:14:0:0|t ") or "") .. QualityHex(quality) .. name .. "|r"
    if count and count > 1 then text = text .. " |cffaaaaaax" .. count .. "|r" end
    return text
end

-- Belohnungen einer Quest in den Tooltip schreiben: feste Gegenstände, Auswahl, Geld, Erfahrung.
-- Gibt true zurück, wenn es Belohnungen gab.
local function AddRewardLines(tooltip, questID)
    -- Die Auswahl-Belohnungen gelten für die "ausgewählte" Quest; danach Auswahl zurücksetzen
    local previous = C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(questID)
    local rewardLines, choiceLines = {}, {}
    for i = 1, GetNumQuestLogRewards(questID) do
        local name, texture, count, quality = GetQuestLogRewardInfo(i, questID)
        if name then table.insert(rewardLines, RewardText(name, texture, count, quality)) end
    end
    for i = 1, GetNumQuestLogChoices(questID) do
        local name, texture, count, quality = GetQuestLogChoiceInfo(i)
        if name then table.insert(choiceLines, RewardText(name, texture, count, quality)) end
    end
    C_QuestLog.SetSelectedQuest(previous or 0)
    local money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID) or 0
    local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID) or 0
    if #rewardLines == 0 and #choiceLines == 0 and money == 0 and xp == 0 then return false end

    tooltip:AddLine(" ")
    tooltip:AddLine(ns.L("TIP_REWARDS"), 1, 0.82, 0)
    for _, line in ipairs(rewardLines) do tooltip:AddLine(line) end
    if #choiceLines > 0 then
        tooltip:AddLine(ns.L("TIP_CHOICES"), 0.75, 0.75, 0.75)
        for _, line in ipairs(choiceLines) do tooltip:AddLine("  " .. line) end
    end
    if money > 0 then
        tooltip:AddLine(GetMoneyString and GetMoneyString(money) or GetCoinTextureString(money), 1, 1, 1)
    end
    if xp > 0 then
        tooltip:AddLine(ns.L("TIP_XP", BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp), 0.6, 0.6, 1)
    end
    return true
end

-- Tooltip der Beutetruhe: nur Questname und Belohnungen
local function ShowRewardTooltip(owner, questID)
    local tooltip = ns.Style.GetTooltip()
    tooltip:SetOwner(owner, AnchorOf(owner))
    tooltip:AddLine(C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID), 1, 0.82, 0)
    AddRewardLines(tooltip, questID)
    tooltip:AddLine(" ")
    tooltip:AddLine(ns.L("TIP_REWARD_CHEST"), 0.5, 0.5, 0.5, true)
    tooltip:Show()
end

-- Mit ForeverAlts: welche deiner anderen Charaktere die Quest auch haben (mit Fortschritt) bzw. schon erledigt haben.
-- Die Daten liefert ForeverAlts über die gemeinsame Schnittstelle des Hubs (fehlt das Addon, passiert nichts).
function ns.AddAltLines(tooltip, questID)
    local HUB = _G.ForeverHub and _G.ForeverHub.UI
    local alts = HUB and HUB.API and HUB.API.ForeverAlts
    if not (alts and alts.CharsWithQuest and questID) then return end
    local ok, list = pcall(alts.CharsWithQuest, questID)
    if not ok or type(list) ~= "table" or #list == 0 then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(ns.L("TIP_ALTS"), 1, 0.82, 0)
    for _, alt in ipairs(list) do
        local state
        if alt.complete then
            state = "|cff00ff00" .. ns.L("READY_TO_TURN_IN") .. "|r"
        elseif alt.total and alt.total > 0 then
            state = alt.done .. "/" .. alt.total
        else
            state = ns.L("DETAIL_IN_LOG")
        end
        tooltip:AddDoubleLine(alt.coloredName or alt.name or "?", state, 1, 1, 1, 0.8, 0.8, 0.8)
    end
end

local function ShowQuestTooltip(owner, questID, noHint)
    local tooltip = ns.Style.GetTooltip()
    tooltip:SetOwner(owner, AnchorOf(owner))
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    local info = logIndex and C_QuestLog.GetInfo(logIndex)

    -- Titel in Schwierigkeitsfarbe mit Level
    local r, g, b = 1, 0.82, 0
    if info and info.level and LevelColor() then
        local color = LevelColor()(info.level)
        r, g, b = color.r, color.g, color.b
    end
    local questTitle = C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID)
    if info and info.level and info.level > 0 then questTitle = questTitle .. " (" .. info.level .. ")" end
    tooltip:AddLine(questTitle, r, g, b)

    -- Beschreibung und Kurzziel stehen bei der "ausgewählten" Quest; danach Auswahl zurücksetzen
    local previous = C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(questID)
    local description, objectiveText
    if GetQuestLogQuestText then
        description, objectiveText = GetQuestLogQuestText(logIndex)
    end
    if objectiveText and objectiveText ~= "" then
        tooltip:AddLine(objectiveText, 1, 1, 1, true)
    end
    if description and description ~= "" then
        if #description > TOOLTIP_DESCRIPTION_LENGTH then
            -- Am Ende kein halbes Umlaut-Zeichen stehen lassen
            description = description:sub(1, TOOLTIP_DESCRIPTION_LENGTH):gsub("[\192-\255][\128-\191]*$", "") .. "…"
        end
        tooltip:AddLine(" ")
        tooltip:AddLine(description, 0.7, 0.7, 0.7, true)
    end

    -- Ziele mit Fortschritt
    local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
    if C_QuestLog.IsComplete(questID) then
        tooltip:AddLine(" ")
        tooltip:AddLine(ns.L("READY_TO_TURN_IN"), 0, 1, 0)
    elseif #objectives > 0 then
        tooltip:AddLine(" ")
        for _, objective in ipairs(objectives) do
            if objective.text and objective.text ~= "" then
                local shade = objective.finished and 0.5 or 1
                tooltip:AddLine("- " .. objective.text, shade, shade, shade, true)
            end
        end
    end

    C_QuestLog.SetSelectedQuest(previous or 0)

    AddRewardLines(tooltip, questID)
    ns.AddAltLines(tooltip, questID)
    -- Klick-Hinweise nur, wo man klicken kann (nicht z. B. in der Questreihe der Detailansicht)
    if not noHint then
        tooltip:AddLine(" ")
        tooltip:AddLine(ns.L("TIP_QUEST_HINT"), 0.5, 0.5, 0.5, true)
    end
    tooltip:Show()
end

local function OnLineEnter(self)
    if self.questID then
        -- Im Menü abschaltbar
        if ns.db.showQuestTooltip then ShowQuestTooltip(self, self.questID) end
    elseif self.groupKey then
        ns.Style.GetTooltip():SetOwner(self, AnchorOf(self))
        ns.Style.GetTooltip():AddLine(ns.L("TIP_GROUP_TOGGLE"), 1, 1, 1)
        ns.Style.GetTooltip():Show()
    end
end

local function OnLineClick(self, button)
    -- Klick auf die Titelleiste eines Gebiets (oder "Gemeinsam"): ein-/ausklappen
    if self.groupKey then
        if button == "LeftButton" then ToggleGroup(self.view, self.groupKey) end
        return
    end
    local questID = self.questID
    -- gemeinsame Quest, die man selbst (noch) nicht im Questlog hat: Rechtsklick beendet das gemeinsame Machen
    if not questID and self.groupQuestID then
        local groupQuestID = self.groupQuestID
        if button == "RightButton" then
            ns.Style.ShowMenu(self, {
                { title = (ns.groupQuests[groupQuestID] or {}).title or "Quest" },
                { text = ns.L("GQ_LEAVE"), onClick = function() ns.RemoveGroupQuest(groupQuestID, true) end },
            }, { atCursor = true })
        end
        return
    end
    if not questID then return end
    -- Shift-Klick auf das Symbol des Questgegenstands: Gegenstand im Chat verlinken
    local item = self.questItem
    if item and item:IsShown() and item.link and item:IsMouseOver(3, -3, -3, 3) and IsModifiedClick() then
        HandleModifiedItemClick(item.link)
        return
    end
    if button == "RightButton" then
        OpenQuestMenu(self, questID)
    elseif IsShiftKeyDown() then
        -- Shift + Linksklick: Quest nicht mehr verfolgen
        if C_QuestLog.GetQuestWatchType(questID) then
            C_QuestLog.RemoveQuestWatch(questID)
        end
    else
        -- Linksklick auf den Namen: Quest im Questlog öffnen (auf-/zuklappen nur noch über den Pfeil).
        -- Im Kampf öffnet Blizzard das Questlog nicht.
        if InCombatLockdown() then return end
        if QuestMapFrame_OpenToQuestDetails then
            QuestMapFrame_OpenToQuestDetails(questID)
        elseif ToggleQuestLog then
            C_QuestLog.SetSelectedQuest(questID)
            ToggleQuestLog()
        end
    end
end

local function OnArrowClick(self)
    local line = self:GetParent()
    local v = line.view
    if line.groupKey then
        ToggleGroup(v, line.groupKey)
        return
    end
    local questID = line.questID
    if not questID then return end
    if v and v.expanded then
        -- Questlog: eigener Stand, der Tracker bleibt unverändert
        v.expanded[questID] = not IsExpandedIn(v, questID)
        Redraw(v)
        return
    end
    ns.expanded[questID] = not ns.IsExpanded(questID)
    ns.autoExpandedAt[questID] = nil
    ns.UpdateTracker()
end

-- Häkchen "verfolgen" (nur im Questlog): Quest in den Tracker aufnehmen bzw. herausnehmen
local function OnWatchClick(self)
    local questID = self:GetParent().questID
    if not questID then return end
    if C_QuestLog.GetQuestWatchType(questID) then
        C_QuestLog.RemoveQuestWatch(questID)
    elseif C_QuestLog.AddQuestWatch then
        C_QuestLog.AddQuestWatch(questID)
    end
    ns.RequestUpdate()
end

-- Tooltip des Questgegenstands (item = das Symbol mit .link und .logIndex)
local function ShowQuestItemTooltip(owner, item)
    local tip = ns.Style.GetTooltip()
    tip:SetOwner(owner, AnchorOf(owner))
    -- 1. Spielfunktion für Questgegenstände, 2. Gegenstand über die ID, 3. Link; jeweils abgesichert
    local shown = false
    if item.logIndex and tip.SetQuestLogSpecialItem then
        shown = pcall(tip.SetQuestLogSpecialItem, tip, item.logIndex) and tip:NumLines() > 0
    end
    local itemID = item.link and tonumber(item.link:match("item:(%d+)"))
    if not shown and itemID and tip.SetItemByID then
        shown = pcall(tip.SetItemByID, tip, itemID) and tip:NumLines() > 0
    end
    if not shown and item.link and tip.SetHyperlink then
        shown = pcall(tip.SetHyperlink, tip, item.link) and tip:NumLines() > 0
    end
    if not shown then
        -- Notlösung: wenigstens der Name aus dem Link
        tip:AddLine(item.link and item.link:match("%[(.-)%]") or "?", 1, 1, 1)
    end
    tip:AddLine(ns.L("TIP_QUEST_ITEM"), 0.6, 0.8, 1, true)
    tip:Show()
end

-- Liegt die Maus gerade auf diesem Symbol? (rein nach Position, mit etwas Rand)
local function IsOverIcon(icon)
    return icon and icon:IsShown() and icon:IsMouseOver(3, -3, -3, 3)
end

-- Solange die Maus über einer Questzeile ist: prüfen, ob sie auf Gegenstand oder Truhe liegt,
-- und den passenden Tooltip zeigen. (Die kleinen Symbole bekommen die Maus nicht immer selbst.)
local function OnLineUpdate(self)
    local mode = "line"
    if IsOverIcon(self.questItem) then
        mode = "item"
    elseif IsOverIcon(self.rewardIcon) then
        mode = "chest"
    end
    if mode == self.hoverMode then return end
    self.hoverMode = mode
    if mode == "item" then
        ShowQuestItemTooltip(self, self.questItem)
    elseif mode == "chest" and self.questID then
        ShowRewardTooltip(self, self.questID)
    else
        ns.Style.GetTooltip():Hide()
        OnLineEnter(self)
    end
end

-- /fq maus: zeigt, welches Fenster die Maus gerade bekommt und wie es um die Questgegenstand-Symbole steht
-- (zur Fehlersuche: Maus auf das Symbol legen, dann den Befehl mit Enter abschicken)
function ns.DebugMouse()
    local prefix = ns.ChatPrefix() .. ": "
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local names = {}
    for _, frame in ipairs(foci or {}) do
        table.insert(names, (frame.GetName and frame:GetName()) or tostring(frame))
    end
    print(prefix .. "Maus auf: " .. (#names > 0 and table.concat(names, ", ") or "nichts"))
    local found = false
    for index, line in ipairs(lines) do
        local item = line.questItem
        if line:IsShown() and item and item:IsShown() then
            found = true
            print(prefix .. string.format("Zeile %d: Symbol sichtbar, Maus drauf: %s, Zeile Maus drauf: %s, Zeile Maus an: %s, Ebenen Zeile/Symbol: %d/%d, Link: %s",
                index, tostring(item:IsMouseOver(3, -3, -3, 3)), tostring(line:IsMouseOver()),
                tostring(line:IsMouseEnabled()), line:GetFrameLevel(), item:GetFrameLevel(), tostring(item.link)))
        end
    end
    if not found then print(prefix .. "Kein Questgegenstand-Symbol im Tracker sichtbar.") end
end

-- Tooltip nur ausblenden, wenn er zu diesem Element gehört. Sonst würde z. B. die Questzeile beim
-- Wechsel der Maus auf ihr Symbol (Questgegenstand, Truhe, Auge) dessen gerade gezeigten Tooltip schließen.
local function HideOwnTooltip(self)
    local tip = ns.Style.GetTooltip()
    if tip:GetOwner() == self then tip:Hide() end
end

---------------------------------------------------------------------------
-- Questgegenstände benutzen
---------------------------------------------------------------------------
-- Gegenstände benutzen geht nur über geschützte Blizzard-Knöpfe (SecureActionButtonTemplate). Diese liegen
-- unsichtbar über dem Symbol der Zeile; das Symbol zeichnet weiter Bild, Abklingzeit und Rückmeldung.
-- Geschützte Knöpfe darf man im Kampf nicht verschieben, zeigen oder verstecken: darum werden sie nur außerhalb
-- des Kampfes nachgeführt (alle 0,1 s), im Kampf bleiben sie, wo sie zuletzt waren.
local QuestItemButtons = {}
do
    local slots = setmetatable({}, { __mode = "k" }) -- alle Gegenstand-Symbole der Zeilen
    local pool = {}
    local driver = CreateFrame("Frame")

    local function NewButton(index)
        local b = CreateFrame("Button", "ForeverQuestsItemButton" .. index, UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "item")
        -- Shift-Klick verlinkt nur im Chat (siehe PostClick), statt den Gegenstand zu benutzen
        b:SetAttribute("shift-type1", "forever_link")
        b:SetAttribute("shift-type2", "forever_link")
        b:Hide()
        b:SetScript("OnEnter", function(self)
            if self.slot then
                self.slot.hover:Show()
                ShowQuestItemTooltip(self, self.slot)
            end
        end)
        b:SetScript("OnLeave", function(self)
            if self.slot then self.slot.hover:Hide() end
            HideOwnTooltip(self)
        end)
        -- gedrückt = kurz dunkler
        b:SetScript("OnMouseDown", function(self) if self.slot then self.slot.press:Show() end end)
        b:SetScript("OnMouseUp", function(self) if self.slot then self.slot.press:Hide() end end)
        b:SetScript("PostClick", function(self, _, down)
            local slot = self.slot
            -- (Klicks kommen beim Drücken und Loslassen; nur einmal reagieren, wie die Aktionsleisten)
            if not slot or down ~= GetCVarBool("ActionButtonUseKeyDown") then return end
            if slot.link and IsModifiedClick("CHATLINK") then
                HandleModifiedItemClick(slot.link)
                return
            end
            -- benutzt: kurzes goldenes Aufleuchten
            slot.glow:Stop()
            slot.glow:Play()
        end)
        return b
    end

    -- Liegt das Symbol im sichtbaren Bereich der Liste? (Zeilen außerhalb sind nur abgeschnitten, nicht versteckt)
    local function InView(slot)
        local clip = slot.clip
        if clip == nil then
            clip = false
            local parent = slot:GetParent()
            while parent do
                if parent:GetObjectType() == "ScrollFrame" then clip = parent break end
                parent = parent:GetParent()
            end
            slot.clip = clip
        end
        if not clip then return true end
        local x, y = slot:GetCenter()
        local left, bottom, width, height = clip:GetRect()
        if not (x and left) then return false end
        local s = slot:GetEffectiveScale() / clip:GetEffectiveScale()
        x, y = x * s, y * s
        return x >= left and x <= left + width and y >= bottom and y <= bottom + height
    end

    function QuestItemButtons.Sync()
        if InCombatLockdown() then return end
        local used = 0
        local uiScale = UIParent:GetEffectiveScale()
        for slot in pairs(slots) do
            local itemID = slot.link and tonumber(slot.link:match("item:(%d+)"))
            local left, bottom, width, height = slot:GetRect()
            if itemID and left and slot:IsVisible() and slot:GetEffectiveAlpha() > 0.05 and InView(slot) then
                used = used + 1
                local b = pool[used] or NewButton(used)
                pool[used] = b
                local s = slot:GetEffectiveScale() / uiScale
                local key = string.format("%.1f:%.1f:%.1f:%.1f", left * s, bottom * s, width * s, height * s)
                if b.key ~= key then
                    b.key = key
                    b:ClearAllPoints()
                    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * s, bottom * s)
                    b:SetSize(width * s, height * s)
                end
                b:SetFrameStrata(slot:GetFrameStrata())
                b:SetFrameLevel(slot:GetFrameLevel() + 5)
                if b.itemID ~= itemID then
                    b.itemID = itemID
                    b:SetAttribute("item", "item:" .. itemID)
                end
                if b.slot ~= slot then
                    if b.slot then b.slot.hover:Hide() end
                    b.slot = slot
                end
                b:Show()
            end
        end
        for i = used + 1, #pool do
            local b = pool[i]
            if b.slot then b.slot.hover:Hide() end
            b.slot = nil
            b:Hide()
        end
    end

    -- Abklingzeit der Questgegenstände (auch im Kampf, das Symbol ist kein geschützter Knopf)
    function QuestItemButtons.UpdateCooldown(slot)
        if not (slot:IsShown() and slot.logIndex and GetQuestLogSpecialItemCooldown) then
            slot.cooldown:Clear()
            return
        end
        local ok, start, duration, enable = pcall(GetQuestLogSpecialItemCooldown, slot.logIndex)
        if ok and start and CooldownFrame_Set then
            pcall(CooldownFrame_Set, slot.cooldown, start, duration, enable)
        end
    end

    function QuestItemButtons.Register(slot)
        slots[slot] = true
    end

    local elapsed = 0
    driver:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 0.1 then return end
        elapsed = 0
        QuestItemButtons.Sync()
    end)
    driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
    driver:SetScript("OnEvent", function()
        for slot in pairs(slots) do QuestItemButtons.UpdateCooldown(slot) end
    end)
end

local function GetLine(index)
    local line = view.lines[index]
    if not line then
        local prefix = view.prefix
        line = CreateFrame("Button", prefix .. "Line" .. index, view.content)
        line.view = view
        line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        line:SetScript("OnClick", OnLineClick)
        -- Beim Darüberfahren: Tooltip der Zeile; solange die Maus drauf ist, wird auf die Symbole geachtet
        line:SetScript("OnEnter", function(self)
            self.hoverMode = nil
            self:SetScript("OnUpdate", OnLineUpdate)
            OnLineUpdate(self)
            -- Questlog: Quest auf der Karte hervorheben
            if self.questID and self.view.onHover then self.view.onHover(self.questID) end
        end)
        line:SetScript("OnLeave", function(self)
            self:SetScript("OnUpdate", nil)
            self.hoverMode = nil
            HideOwnTooltip(self)
            if self.view.onHover then self.view.onHover(nil) end
        end)

        -- Kleine Beutetruhe rechts für Quests mit guten Belohnungen.
        -- Bevorzugt die Schatztruhe von der Karte; falls es die nicht gibt, ein Kisten-Symbol.
        -- Als kleiner Knopf, damit die Truhe beim Darüberfahren die Belohnungen zeigt
        local chest = CreateFrame("Button", prefix .. "Chest" .. index, line)
        chest:SetSize(REWARD_ICON_SIZE, REWARD_ICON_SIZE)
        chest:SetPoint("TOPRIGHT", line, "TOPRIGHT", 0, 0)
        chest:SetHitRectInsets(-3, -3, -3, -3)
        chest.icon = chest:CreateTexture(nil, "OVERLAY")
        chest.icon:SetAllPoints()
        if not chest.icon:SetAtlas(REWARD_ICON_ATLAS) then
            chest.icon:SetTexture(REWARD_ICON_TEXTURE)
            chest.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Symbolrand abschneiden
        end
        chest:SetScript("OnEnter", function(self)
            local questID = self:GetParent().questID
            if questID then ShowRewardTooltip(self, questID) end
        end)
        chest:SetScript("OnLeave", HideOwnTooltip)
        -- Klick auf die Truhe wirkt wie ein Klick auf die Questzeile (Details, Menü …)
        chest:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        chest:SetScript("OnClick", function(self, button) OnLineClick(self:GetParent(), button) end)
        line.rewardIcon = chest

        line.text = line:CreateFontString(nil, "OVERLAY")
        line.text:SetPoint("TOPLEFT")
        line.text:SetJustifyH("LEFT")
        line.text:SetWordWrap(true)

        -- Hover-Effekt: Zeile beim Darüberfahren leicht hell hinterlegen (inkl. Pfeil links).
        -- Zeigt sich nur bei anklickbaren Zeilen (Quests und Gebiets-Titelleisten).
        local highlight = line:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", -(ICON_SIZE + 5), 1)
        highlight:SetPoint("BOTTOMRIGHT", 3, -1)
        highlight:SetColorTexture(1, 1, 1, 0.07)
        line.highlight = highlight

        -- Questgegenstand: Symbol rechts. Benutzt wird er über einen unsichtbaren geschützten Knopf darüber
        -- (siehe QuestItemButtons); dieses Symbol zeichnet Bild, Rand, Abklingzeit und die Rückmeldung.
        -- Mit Namen, damit es im Blizzard-Werkzeug /fstack erkennbar ist
        local item = CreateFrame("Button", prefix .. "Item" .. index, line)
        item:SetSize(QUEST_ITEM_SIZE, QUEST_ITEM_SIZE)
        local border = item:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0, 0, 0, 0.9)
        item.icon = item:CreateTexture(nil, "ARTWORK")
        item.icon:SetPoint("TOPLEFT", 1, -1)
        item.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        item.cooldown = CreateFrame("Cooldown", nil, item, "CooldownFrameTemplate")
        item.cooldown:SetPoint("TOPLEFT", 1, -1)
        item.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
        item.cooldown:SetHideCountdownNumbers(true)
        -- Rückmeldung wie beim Händler: Maus drauf = heller, gedrückt = kurz dunkler, benutzt = goldenes Aufleuchten
        local itemAccent = ns.Style.COLOR.accent
        item.hover = item:CreateTexture(nil, "OVERLAY", nil, 5)
        item.hover:SetPoint("TOPLEFT", 1, -1)
        item.hover:SetPoint("BOTTOMRIGHT", -1, 1)
        item.hover:SetColorTexture(1, 1, 1, 0.15)
        item.hover:Hide()
        item.press = item:CreateTexture(nil, "OVERLAY", nil, 6)
        item.press:SetPoint("TOPLEFT", 1, -1)
        item.press:SetPoint("BOTTOMRIGHT", -1, 1)
        item.press:SetColorTexture(0, 0, 0, 0.3)
        item.press:Hide()
        local glow = item:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetAllPoints()
        glow:SetColorTexture(itemAccent[1], itemAccent[2], itemAccent[3], 1)
        glow:SetAlpha(0)
        item.glow = glow:CreateAnimationGroup()
        local fade = item.glow:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.45)
        fade:SetToAlpha(0)
        fade:SetDuration(0.5)
        fade:SetSmoothing("OUT")
        item.glow:SetScript("OnFinished", function() glow:SetAlpha(0) end)
        item:SetScript("OnHide", function(self)
            self.hover:Hide()
            self.press:Hide()
        end)
        QuestItemButtons.Register(item)
        item:SetScript("OnEnter", function(self) ShowQuestItemTooltip(self, self) end)
        item:SetScript("OnLeave", HideOwnTooltip)
        -- Shift-Klick: Gegenstand im Chat verlinken
        item:SetScript("OnClick", function(self)
            if self.link and IsModifiedClick() then HandleModifiedItemClick(self.link) end
        end)
        item:Hide()
        line.questItem = item

        -- Kleiner Pfeil links neben dem Questnamen
        local arrow = CreateFrame("Button", nil, line)
        arrow:SetSize(ICON_SIZE, ICON_SIZE)
        arrow:SetPoint("TOPRIGHT", line, "TOPLEFT", -3, 0)
        arrow.icon = arrow:CreateTexture(nil, "ARTWORK")
        arrow.icon:SetAllPoints()
        arrow.icon:SetTexture(ARROW_TEXTURE)
        arrow:SetScript("OnClick", OnArrowClick)
        arrow:SetScript("OnEnter", function(self) self.icon:SetVertexColor(1, 1, 0.5) end)
        arrow:SetScript("OnLeave", function(self) self.icon:SetVertexColor(1, 1, 1) end)
        line.arrow = arrow

        -- Häkchen "verfolgen" links vor dem Pfeil (nur im Questlog): hohl = nicht verfolgt, gold = im Tracker
        local watch = CreateFrame("Button", nil, line, "BackdropTemplate")
        watch:SetSize(ICON_SIZE - 1, ICON_SIZE - 1)
        watch:SetPoint("TOPRIGHT", line, "TOPLEFT", -(ICON_SIZE + 6), 0)
        watch:SetHitRectInsets(-3, -3, -3, -3)
        ns.Style.SetFlat(watch, ns.Style.COLOR.input)
        watch.fill = watch:CreateTexture(nil, "ARTWORK")
        watch.fill:SetPoint("TOPLEFT", 2, -2)
        watch.fill:SetPoint("BOTTOMRIGHT", -2, 2)
        local accent = ns.Style.COLOR.accent
        watch.fill:SetColorTexture(accent[1], accent[2], accent[3], 1)
        watch:SetScript("OnClick", OnWatchClick)
        watch:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
            local tip = ns.Style.GetTooltip()
            tip:SetOwner(self, AnchorOf(self))
            tip:AddLine(ns.L(self.fill:IsShown() and "TIP_WATCH_OFF" or "TIP_WATCH_ON"), 1, 1, 1)
            tip:Show()
        end)
        watch:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(ns.Style.COLOR.border))
            HideOwnTooltip(self)
        end)
        watch:Hide()
        line.watch = watch

        -- Nur bei Titelleisten: Auge der Gruppensuche direkt hinter dem Namen (wenn das Gebiet ein Dungeon ist)
        -- und danach ein Zusatztext (Anzahl der Quests)
        local eye = CreateFrame("Button", nil, line)
        eye:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
        -- Klickfläche rundherum etwas größer als das Symbol, damit es sich leicht treffen lässt
        eye:SetHitRectInsets(-8, -8, -6, -6) -- links/rechts 8, oben/unten 6 Pixel über das Symbol hinaus
        eye.icon = eye:CreateTexture(nil, "ARTWORK")
        eye.icon:SetAllPoints()
        if ns.SetEyeTexture then ns.SetEyeTexture(eye.icon) end
        eye:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        eye:SetScript("OnClick", function(self)
            if self.dungeon and ns.OpenInGroupFinder then ns.OpenInGroupFinder(self.dungeon) end
        end)
        eye:SetScript("OnEnter", function(self)
            ns.Style.GetTooltip():SetOwner(self, "ANCHOR_LEFT")
            ns.Style.GetTooltip():AddLine(ns.L("TIP_LFG"), 1, 1, 1)
            ns.Style.GetTooltip():Show()
        end)
        eye:SetScript("OnLeave", HideOwnTooltip)
        eye:Hide()
        line.eye = eye
        line.suffix = line:CreateFontString(nil, "OVERLAY")

        view.lines[index] = line
    end
    -- Zeilen liegen über den Rahmen
    line:SetFrameLevel(view.content:GetFrameLevel() + 5)
    return line
end

-- Fügt eine Zeile ein und gibt die neue Y-Position (Abstand von oben) zurück.
-- opts (optional):
--   questID   = Quest dieser Zeile (macht sie anklickbar)
--   groupKey  = Titelleiste eines Gebiets (Klick klappt das Gebiet ein/aus)
--   arrow     = nil: kein Pfeil, true: aufgeklappt (nach unten), false: eingeklappt (nach rechts)
--   reward    = Seltenheit der besten Belohnung, wenn eine Truhe angezeigt werden soll, sonst nil
--   questItem = { link = Gegenstandslink, icon = Symbol } für den Questgegenstand, sonst nil
--   watch     = nil: kein Häkchen, true/false: Häkchen "verfolgen" an/aus (Questlog)
local function AddLine(index, y, x, width, text, fontObject, r, g, b, opts)
    opts = opts or {}
    local line = GetLine(index)
    width = math.max(1, width)
    -- Mit Truhe und/oder Questgegenstand bleibt rechts etwas Platz frei
    local iconCount = (opts.reward and 1 or 0) + (opts.questItem and 1 or 0)
    local iconsWidth = (opts.reward and REWARD_ICON_SIZE + 4 or 0) + (opts.questItem and QUEST_ITEM_SIZE + 4 or 0)
    local textWidth = math.max(1, width - iconsWidth - (iconCount > 0 and 2 or 0))
    line.text:SetFontObject(fontObject)
    line.text:SetTextColor(r, g, b)
    line.text:SetWidth(textWidth)
    line.text:SetText(text)
    local height = line.text:GetStringHeight() + 2
    if iconCount > 0 then
        height = math.max(height, opts.questItem and QUEST_ITEM_SIZE or REWARD_ICON_SIZE)
    end

    -- Hervorhebung nur bis vor die Symbole rechts (Truhe, Questgegenstand)
    line.highlight:ClearAllPoints()
    line.highlight:SetPoint("TOPLEFT", line, "TOPLEFT", -(ICON_SIZE + 5), 1)
    line.highlight:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT",
        iconCount > 0 and -(iconsWidth + 2) or 3, -1)

    -- Questgegenstand: ganz rechts bzw. links neben der Truhe
    if opts.questItem then
        local item = line.questItem
        item.link = opts.questItem.link
        item.logIndex = opts.questItem.logIndex
        item.icon:SetTexture(opts.questItem.icon or 134400)
        item:ClearAllPoints()
        item:SetPoint("TOPRIGHT", line, "TOPRIGHT", opts.reward and -(REWARD_ICON_SIZE + 4) or 0, 0)
        item:SetFrameLevel(line:GetFrameLevel() + 2)
        item:Show()
        QuestItemButtons.UpdateCooldown(item)
    else
        line.questItem:Hide()
    end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", view.content, "TOPLEFT", x, -y)
    line:SetSize(width, height)
    if opts.watch == nil then
        line.watch:Hide()
    else
        line.watch.fill:SetShown(opts.watch)
        line.watch:SetFrameLevel(line:GetFrameLevel() + 2)
        line.watch:Show()
    end
    line.questID = opts.questID
    line.groupKey = opts.groupKey
    line.groupQuestID = nil -- (Reiter "Gruppe" setzt das nach AddLine)
    line:EnableMouse(opts.questID ~= nil or opts.groupKey ~= nil)

    if opts.arrow == nil then
        line.arrow:Hide()
    else
        line.arrow.icon:SetRotation(opts.arrow and -math.pi / 2 or 0)
        line.arrow:Show()
    end

    line.rewardIcon:SetShown(opts.reward ~= nil)
    line.rewardIcon:SetFrameLevel(line:GetFrameLevel() + 2)

    -- Auge (Dungeon) und Zusatztext direkt hinter dem Text der ersten Zeile
    local textEnd = math.min(line.text:GetStringWidth(), textWidth)
    if opts.eyeDungeon then
        line.eye.dungeon = opts.eyeDungeon
        line.eye:ClearAllPoints()
        line.eye:SetPoint("TOPLEFT", line.text, "TOPLEFT", textEnd + 3, 3)
        -- Über allen Zeilen und Rahmen, damit keine andere Zeile die Maus abfängt
        line.eye:SetFrameLevel(line:GetFrameLevel() + 10)
        line.eye:Show()
        textEnd = textEnd + 3 + line.eye:GetWidth()
    else
        line.eye:Hide()
    end
    if opts.suffix then
        line.suffix:SetFontObject(fontObject)
        line.suffix:SetText(opts.suffix)
        line.suffix:ClearAllPoints()
        line.suffix:SetPoint("TOPLEFT", line.text, "TOPLEFT", textEnd + 4, 0)
        line.suffix:Show()
    else
        line.suffix:Hide()
    end

    line:Show()
    return y + height
end

-- Eigenes kleines "Fenster" je Gebiet/Kategorie im Stil des Dungeonfensters:
-- dunkles Feld mit grauem Rand, oben eine Titelleiste mit farbiger Linie darunter.
-- Die Hintergrund-Transparenz kommt aus dem Menü.
local function GetBox(index, alpha)
    local box = view.boxes[index]
    if not box then
        box = CreateFrame("Frame", nil, view.content, "BackdropTemplate")
        box:SetBackdrop(ns.Style.BACKDROP)
        box.header = box:CreateTexture(nil, "ARTWORK", nil, -1)
        box.header:SetPoint("TOPLEFT", 1, -1)
        box.header:SetPoint("TOPRIGHT", -1, -1)
        box.accent = box:CreateTexture(nil, "ARTWORK", nil, 1)
        box.accent:SetHeight(1)
        box.accent:SetPoint("TOPLEFT", box.header, "BOTTOMLEFT")
        box.accent:SetPoint("TOPRIGHT", box.header, "BOTTOMRIGHT")
        view.boxes[index] = box
    end
    local color = ns.Style.COLOR
    box:SetBackdropColor(color.panel[1], color.panel[2], color.panel[3], alpha)
    box:SetBackdropBorderColor(color.border[1], color.border[2], color.border[3], math.max(alpha, 0.3))
    box.header:SetColorTexture(color.header[1], color.header[2], color.header[3], math.max(alpha, 0.15))
    box:SetFrameLevel(view.content:GetFrameLevel() + 1)
    for _, sep in ipairs(box.separators or {}) do sep:Hide() end -- Trennlinien (nur im Fenster "Gemeinsam")
    return box
end

---------------------------------------------------------------------------
-- Tracker-Inhalt aufbauen
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Filter
---------------------------------------------------------------------------

local function HasTag(questID, ...)
    local tagInfo = GetQuestTag(questID)
    if not tagInfo then return false end
    for i = 1, select("#", ...) do
        if tagInfo.tagID == select(i, ...) then
            return true
        end
    end
    return false
end

-- Jeder Filter prüft eine Quest (info = Questlog-Eintrag, header = Gebiet/Kategorie).
-- Im Filter-Menü steht jede Gruppe mit Häkchen: an = Quests dieser Art werden gezeigt, aus = ausgeblendet.
-- Ganz oben "Alles": an, solange nichts ausgeblendet ist; Klick darauf zeigt wieder alles.
ns.FILTERS = {
    -- Aktuelles Gebiet: die Quest hat Ziele oder ihre Abgabe auf der Karte, auf der man gerade steht.
    -- (Nicht nach der Überschrift im Questlog: dort stehen Quests oft unter dem Gebiet, in dem man sie bekommt –
    -- eine in Orgrimmar angenommene Quest fürs Brachland stünde sonst unter "Orgrimmar".)
    -- Nur wenn das Spiel das nicht beantworten kann: Vergleich mit der Überschrift wie bisher.
    { key = "ZONE", textKey = "FILTER_ZONE", test = function(info, header)
        if C_QuestLog.IsOnMap then
            local ok, onMap = pcall(C_QuestLog.IsOnMap, info.questID)
            if ok then return onMap and true or false end
        end
        if info.isOnMap ~= nil then return info.isOnMap end
        return header ~= nil and (header == GetRealZoneText() or header == GetZoneText())
    end },
    { key = "DUNGEON", textKey = "FILTER_DUNGEON", test = function(info)
        return HasTag(info.questID, TAG_DUNGEON, TAG_HEROIC)
    end },
    { key = "RAID", textKey = "FILTER_RAID", test = function(info)
        return HasTag(info.questID, TAG_RAID, TAG_RAID10, TAG_RAID25)
    end },
    { key = "GROUP", textKey = "FILTER_GROUP", test = function(info)
        local tagInfo = GetQuestTag(info.questID)
        return (tagInfo and (tagInfo.tagID == TAG_GROUP or tagInfo.isElite))
            or (info.suggestedGroup or 0) > 1
    end },
    { key = "PVP", textKey = "FILTER_PVP", test = function(info)
        return HasTag(info.questID, TAG_PVP)
    end },
    { key = "CLASS", textKey = "FILTER_CLASS", test = function(info, header)
        return GetClassFileForHeader(header) ~= nil
    end },
    { key = "PROFESSION", textKey = "FILTER_PROFESSION", test = function(info, header)
        return IsProfessionHeader(header)
    end },
    { key = "REPUTATION", textKey = "FILTER_REPUTATION", test = function(info, header)
        return header ~= nil and IsReputationHeader(header)
    end },
    { key = "COMPLETE", textKey = "FILTER_COMPLETE", test = function(info)
        return C_QuestLog.IsComplete(info.questID)
    end },
    { key = "REWARD", textKey = "FILTER_REWARD", test = function(info)
        return GetBestRewardQuality(info.questID) >= math.max(2, ns.db.rewardHighlight)
    end },
    { key = "PINNED", textKey = "FILTER_PINNED", test = function(info)
        return ns.db.pinned[info.questID] == true
    end },
}

-- Name der Instanz, in der der Spieler gerade ist (nil = keine Instanz)
local function GetCurrentInstanceName()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType == "none" then
        return nil
    end
    return (GetInstanceInfo())
end

-- Wird automatisch benutzt, wenn man eine Instanz betritt (Option im Menü)
local INSTANCE_FILTER = {
    key = "INSTANCE",
    textKey = "FILTER_INSTANCE",
    test = function(info, header)
        -- Quest steht unter der Instanz als Überschrift oder hat Ziele auf der aktuellen Karte
        if info.isOnMap then return true end
        return header ~= nil and (header == GetCurrentInstanceName() or header == GetRealZoneText())
    end,
}

-- Ausgeblendete Gruppen: dbKey "hiddenFilters" (Tracker) oder "logHiddenFilters" (Questlog); [Schlüssel] = true
local function FilterTable(dbKey)
    dbKey = dbKey or "hiddenFilters"
    if type(ns.db[dbKey]) ~= "table" then ns.db[dbKey] = {} end
    return ns.db[dbKey]
end

-- Filter-Auswahl als Liste und Art:
--   "DEFAULT" = alles sichtbar (Liste leer)
--   "CUSTOM"  = einzelne Gruppen ausgeblendet (Liste = ausgeblendete Gruppen)
--   "ONLY"    = "Alles" ausgeschaltet (NONE gesetzt): nur angehakte Gruppen (Liste = angehakte Gruppen, evtl. leer)
local function GetSelectedFilters(dbKey)
    local hidden = FilterTable(dbKey)
    local list = {}
    if hidden.NONE then
        for _, filter in ipairs(ns.FILTERS) do
            if not hidden[filter.key] then table.insert(list, filter) end
        end
        return list, "ONLY"
    end
    for _, filter in ipairs(ns.FILTERS) do
        if hidden[filter.key] then table.insert(list, filter) end
    end
    return list, #list > 0 and "CUSTOM" or "DEFAULT"
end

-- Aktive Filter und Art: "INSTANCE" (automatisch im Dungeon: nur die Quests der Instanz) oder wie oben
local function GetActiveFilters()
    if ns.db.instanceFilter and GetCurrentInstanceName() then
        return { INSTANCE_FILTER }, "INSTANCE"
    end
    return GetSelectedFilters()
end

-- Im Dungeon bzw. bei "Alles" aus: Quest wird gezeigt, wenn sie zu einer der Gruppen gehört.
-- Sonst: Quest wird ausgeblendet, sobald sie zu einer ausgeblendeten Gruppe gehört ("Dungeon" aus = Dungeonquests weg)
local function PassesFilters(filters, info, header, mode)
    if mode == "ONLY" and #filters == 0 then return false end -- "Alles" aus und nichts angehakt: nichts
    if #filters == 0 then return true end
    if mode == "INSTANCE" or mode == "ONLY" then
        for _, filter in ipairs(filters) do
            if filter.test(info, header) then return true end
        end
        return false
    end
    for _, filter in ipairs(filters) do
        if filter.test(info, header) then return false end
    end
    return true
end

-- Text für den Tooltip des Filter-Knopfs: "Alles", "Instanz" oder "Ausgeblendet: Dungeon, Gruppe"
local function GetActiveFilterText()
    local filters, mode = GetActiveFilters()
    if mode == "DEFAULT" then return ns.L("FILTER_EVERYTHING") end
    local names = {}
    for _, filter in ipairs(filters) do
        table.insert(names, ns.L(filter.textKey))
    end
    if mode == "INSTANCE" then return table.concat(names, ", ") end
    if mode == "ONLY" then
        return #names > 0 and ns.L("FILTER_ONLY", table.concat(names, ", ")) or ns.L("FILTER_NOTHING")
    end
    return ns.L("FILTER_HIDDEN", table.concat(names, ", "))
end

-- "Alles" schaltet um: alles sichtbar -> alles aus (dann einzelne Gruppen wieder anhaken), sonst -> alles sichtbar.
-- Jeder andere Eintrag blendet seine Gruppe ein bzw. aus.
local function ToggleFilter(key, dbKey, redraw)
    local hidden = FilterTable(dbKey)
    if key == "EVERYTHING" then
        if next(hidden) == nil then
            hidden.NONE = true
            for _, filter in ipairs(ns.FILTERS) do hidden[filter.key] = true end
        else
            wipe(hidden)
        end
    else
        hidden[key] = not hidden[key] or nil
        -- alle Gruppen wieder angehakt: zurück zu "Alles"
        local anyHidden = false
        for _, filter in ipairs(ns.FILTERS) do
            if hidden[filter.key] then anyHidden = true end
        end
        if not anyHidden then wipe(hidden) end
    end
    if redraw then redraw() else ns.UpdateTracker() end
end

-- Filter-Liste im eigenen flachen Stil (siehe Style.ShowMenu); bleibt beim Anhaken offen.
-- Ohne Angaben: Filter des Trackers; dbKey/redraw: eigene Auswahl (Questlog, ohne Instanz-Filter)
local function OpenFilterMenu(owner, dbKey, redraw)
    local hidden = FilterTable(dbKey)
    local items = {
        { title = ns.L("FILTER_TITLE") },
        {
            checkbox = true,
            text = ns.L("FILTER_EVERYTHING"),
            checked = function() return next(hidden) == nil end,
            onClick = function() ToggleFilter("EVERYTHING", dbKey, redraw) end,
        },
        { divider = true },
    }
    for _, filter in ipairs(ns.FILTERS) do
        table.insert(items, {
            checkbox = true,
            text = ns.L(filter.textKey),
            checked = function() return not hidden[filter.key] end,
            onClick = function() ToggleFilter(filter.key, dbKey, redraw) end,
        })
    end
    if dbKey then
        ns.Style.ShowMenu(owner, items)
        return
    end
    table.insert(items, { divider = true })
    table.insert(items, {
        checkbox = true,
        text = ns.L("FILTER_INSTANCE_TOGGLE"),
        checked = function() return ns.db.instanceFilter end,
        onClick = function()
            ns.db.instanceFilter = not ns.db.instanceFilter
            ns.UpdateTracker()
            if ns.RefreshOptions then ns.RefreshOptions() end
        end,
    })
    ns.Style.ShowMenu(owner, items)
end

---------------------------------------------------------------------------
-- Quests sammeln
---------------------------------------------------------------------------

-- Passt die Quest zum Suchtext? (Name, Gebiet oder Questziel; ohne Groß-/Kleinschreibung)
local function MatchesSearch(search, info, header)
    if not search or search == "" then return true end
    local function Has(text) return text and text:lower():find(search, 1, true) ~= nil end
    if Has(info.title) or Has(header) then return true end
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
        if Has(objective.text) then return true end
    end
    return false
end

-- Sammelt die anzuzeigenden Quests, gruppiert nach Gebiet (Überschrift im Questlog).
-- Angeheftete Quests kommen in einen eigenen Rahmen ganz oben.
-- opts (Questlog): all = alle Quests, immer nach Gebieten; filterKey = eigene Filterauswahl; search = Suchtext
local function CollectGroups(opts)
    local db = ns.db
    local groups = {}
    local pinnedGroup = { header = ns.L("PINNED"), pinned = true, quests = {} }
    local currentHeader
    local filters, filterMode, useTrackedOnly, showZones, search
    if opts then
        filters, filterMode = GetSelectedFilters(opts.filterKey)
        useTrackedOnly, showZones = false, true
        search = opts.search and opts.search:lower() or nil
    else
        filters, filterMode = GetActiveFilters()
        -- Im Dungeon (Instanz-Filter) wird das ganze Questlog durchsucht, nicht nur verfolgte Quests
        useTrackedOnly = db.onlyTracked and filterMode ~= "INSTANCE"
        showZones = db.showZones
    end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                currentHeader = info.title
            elseif not info.isHidden and info.questID and info.questID > 0
                and not (ns.IsGroupQuest and ns.IsGroupQuest(info.questID)) -- steht schon oben unter "Gemeinsam"
                and PassesFilters(filters, info, currentHeader, filterMode)
                and MatchesSearch(search, info, currentHeader) then
                info.zoneHeader = currentHeader
                if db.pinned[info.questID] then
                    -- Angeheftete Quests werden immer angezeigt, auch wenn sie nicht verfolgt werden
                    table.insert(pinnedGroup.quests, info)
                elseif not useTrackedOnly or C_QuestLog.GetQuestWatchType(info.questID) ~= nil then
                    local group = groups[#groups]
                    -- Ohne Gebietsanzeige landen alle Quests in einem einzigen Rahmen
                    if not group or (showZones and group.header ~= currentHeader) then
                        group = { header = currentHeader, quests = {} }
                        table.insert(groups, group)
                    end
                    table.insert(group.quests, info)
                end
            end
        end
    end
    if #pinnedGroup.quests > 0 then
        table.insert(groups, 1, pinnedGroup)
    end
    return groups
end

-- Gemeinsame Quests (GroupQuests.lua) ganz oben in EINEM Fenster mit goldener Titelleiste ("Gemeinsam · 2"):
-- je Quest die Questzeile wie in der normalen Liste, darunter je Questziel der Stand aller, die mitmachen
-- ("Du 3/8   Anna 5/8"); zwischen den Quests eine feine Linie. Rechtsklick auf eine Quest: nicht mehr gemeinsam.
-- Rückgabe: y, index, Anzahl Fenster (0 oder 1)
local function MemberName(member)
    local text = member.me and ns.L("YOU") or member.name
    local color = member.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
    if color then
        return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
    end
    return text
end

-- feine Trennlinie im Fenster (eigene kleine Sammlung je Fenster, beim nächsten Aufbau wieder versteckt)
local function Separator(box, n, top, width)
    box.separators = box.separators or {}
    local line = box.separators[n]
    if not line then
        line = box:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        box.separators[n] = line
    end
    local accent = ns.Style.COLOR.accent
    line:SetColorTexture(accent[1], accent[2], accent[3], 0.18)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -top)
    line:SetWidth(math.max(1, width - 20))
    line:Show()
end

local function RenderGroupQuest(entry, y, index, nameX, nameWidth, objectiveX, objectiveWidth)
    local questID = entry.questID
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    -- Questgegenstand wie in der normalen Liste
    local questItem
    if logIndex and GetQuestLogSpecialItemInfo then
        local itemLink, itemIcon, _, showWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
        if itemLink and (not C_QuestLog.IsComplete(questID) or showWhenComplete) then
            questItem = { link = itemLink, icon = itemIcon, logIndex = logIndex }
        end
    end
    -- Questzeile: Name in Schwierigkeitsfarbe mit Stufe, Questtyp, "(Fertig)", Truhe, Questgegenstand und Quest-ID;
    -- Maus darüber = Quest-Tooltip, Klick = Questlog, Rechtsklick = Menü (mit "Nicht mehr gemeinsam machen")
    local info = logIndex and C_QuestLog.GetInfo(logIndex)
    local isComplete = logIndex and C_QuestLog.IsComplete(questID)
    local r, g, b = 1, 1, 1
    if info and info.level and LevelColor() then
        local color = LevelColor()(info.level)
        r, g, b = color.r, color.g, color.b
    end
    local name = (info and info.title) or entry.data.title
    if info and info.level and info.level > 0 then name = name .. " (" .. info.level .. ")" end
    if logIndex and ns.db.showQuestType then
        local typeText = GetQuestTypeText(questID, nil)
        if typeText ~= "" then name = name .. " |cff88ccff" .. typeText .. "|r" end
    end
    if isComplete then name = name .. " |cff00ff00" .. ns.L("COMPLETE_TAG") .. "|r" end
    local rewardQuality
    if logIndex and ns.db.rewardHighlight > 0 then
        local quality = GetBestRewardQuality(questID)
        if quality >= ns.db.rewardHighlight then rewardQuality = quality end
    end
    -- Quest-ID (zum Nachschlagen/Abgleichen), nur mit Einstellung "Quest-IDs anzeigen"
    if ns.db.showQuestIDs then name = name .. "  |cff6a6a6a#" .. questID .. "|r" end
    index = index + 1
    y = AddLine(index, y, nameX, nameWidth, name, fonts.quest, r, g, b, {
        questID = logIndex and questID or nil,
        reward = rewardQuality,
        questItem = questItem,
    })
    -- auch ohne eigene Quest im Questlog per Rechtsklick beendbar
    view.lines[index].groupQuestID = questID
    view.lines[index]:EnableMouse(true)
    if logIndex then CheckProgress(questID, C_QuestLog.GetQuestObjectives(questID) or {}, isComplete) end
    if isComplete then
        index = index + 1
        y = AddLine(index, y, objectiveX, objectiveWidth, "- " .. ns.L("READY_TO_TURN_IN"), fonts.objective, 0, 1, 0)
    end
    -- Stand je Teilnehmer in Einzelteile zerlegen ("3/8,1/1" -> { "3/8", "1/1" })
    for _, member in ipairs(entry.members) do
        member.parts = {}
        if member.state and member.state ~= "+" and member.state ~= "-" then
            for part in member.state:gmatch("[^,]+") do member.parts[#member.parts + 1] = part end
        end
    end
    local objectives = logIndex and C_QuestLog.GetQuestObjectives(questID) or {}
    if #objectives > 0 then
        for i, objective in ipairs(objectives) do
            -- Zielname ohne den eigenen Zähler am Ende ("Wolf getötet: 3/8" -> "Wolf getötet")
            local label = (objective.text or ""):gsub("[:：]?%s*%d+%s*/%s*%d+%s*$", "")
            if label == "" then label = ns.L("GQ_OBJECTIVE", i) end
            index = index + 1
            y = AddLine(index, y + 2, objectiveX, objectiveWidth, "- " .. label, fonts.objective, 0.85, 0.85, 0.85)
            local parts = {}
            for _, member in ipairs(entry.members) do
                local value
                if member.state == "+" then
                    value = "|cff33ff33" .. ns.L("GQ_DONE") .. "|r"
                elseif member.state == "-" then
                    value = "|cff8a8a8a" .. ns.L("GQ_MISSING") .. "|r"
                else
                    local part = member.parts[i]
                    local have, need -- (nicht "part and part:match(...)": das liefert nur den ersten Wert)
                    if part then have, need = part:match("^(%d+)/(%d+)$") end
                    if have and tonumber(have) >= tonumber(need) then
                        value = "|cff33ff33" .. part .. "|r"
                    else
                        value = part or "|cff8a8a8a…|r"
                    end
                end
                parts[#parts + 1] = MemberName(member) .. " " .. value
            end
            index = index + 1
            y = AddLine(index, y + 1, objectiveX + 8, objectiveWidth - 8, table.concat(parts, "   "),
                fonts.objective, 0.9, 0.9, 0.9)
        end
    else
        -- Quest nicht (mehr) im eigenen Questlog: je Teilnehmer eine Zeile mit seinem Stand
        for _, member in ipairs(entry.members) do
            index = index + 1
            y = AddLine(index, y + 2, objectiveX, objectiveWidth,
                MemberName(member) .. ":  " .. ns.GroupStateText(member.state), fonts.objective, 0.9, 0.9, 0.9)
        end
    end
    return y, index
end

local function RenderGroupView(y, index, alpha, contentWidth, nameX, nameWidth, objectiveX, objectiveWidth, padding)
    local list = ns.GroupQuestList()
    if #list == 0 then return y, index, 0 end
    local boxTop = y
    local box = GetBox(1, alpha)
    local accent = ns.Style.COLOR.accent
    local groupKey = "#GQ"
    local collapsed = view.collapsed[groupKey] == true
    -- Titelleiste: "Gemeinsam" mit Anzahl der gemeinsamen Quests (Klick klappt ein/aus)
    index = index + 1
    y = AddLine(index, y + 5, nameX, nameWidth, ns.L("GQ_TAG"), fonts.header, accent[1], accent[2], accent[3], {
        groupKey = groupKey,
        arrow = not collapsed,
        suffix = "|cff8a8a8a" .. #list .. "|r",
    })
    y = y + 4
    box.header:SetHeight(math.max(1, y - boxTop - 1))
    box.header:Show()
    box.accent:SetColorTexture(accent[1], accent[2], accent[3], 0.7)
    box.accent:Show()
    y = y + 3
    if not collapsed then
        for n, entry in ipairs(list) do
            if n > 1 then
                -- feine Trennung zwischen den Quests
                y = y + 4
                Separator(box, n - 1, y - boxTop, contentWidth)
                y = y + 4
            else
                y = y + 2
            end
            y, index = RenderGroupQuest(entry, y, index, nameX, nameWidth, objectiveX, objectiveWidth)
        end
    end
    y = y + padding
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", view.content, "TOPLEFT", 0, -boxTop)
    box:SetSize(contentWidth, y - boxTop)
    box:Show()
    y = y + BOX_GAP
    return y, index, 1
end

-- Reiterzeile über der Liste ("Quests" | "Gruppe"), nur solange es vorgeschlagene Quests gibt
local tabRow, questsTab, groupTab
local function UpdateTabs()
    if not tabRow then return end
    -- (früher Reiter "Quests | Gruppe"; gemeinsame Quests stehen jetzt oben in der Liste – Reiterzeile bleibt aus)
    local show = false
    ns.trackerTab = "quests"
    tabRow:SetShown(show)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", 6, show and -54 or -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 6)
    local accent = ns.Style.COLOR.accent
    for tab, key in pairs({ [questsTab] = "quests", [groupTab] = "group" }) do
        local active = ns.trackerTab == key
        tab:GetFontString():SetTextColor(active and accent[1] or 0.9, active and accent[2] or 0.9, active and accent[3] or 0.9)
    end
end

-- Zeichnet die Quest-Fenster (Gemeinsam, Angeheftet, Gebiete) in eine Ansicht.
-- v = Ansicht, groups = Ergebnis von CollectGroups, contentWidth = Breite, alpha = Deckkraft der Fenster,
-- emptyText = Text, wenn nichts da ist (Funktion). Rückgabe: Anzahl der Quests, Höhe des Inhalts
local function RenderQuestList(v, groups, contentWidth, alpha, emptyText)
    view = v
    local db = ns.db
    local isTracker = v == trackerView
    local showZones = (not isTracker) or db.showZones
    v.content:SetWidth(contentWidth)

    local padding = BOX_PADDING
    local innerX = padding + 2
    local innerWidth = contentWidth - 2 * innerX
    -- Platz links für den Pfeil (im Questlog zusätzlich für das Häkchen "verfolgen")
    local iconSpace = ICON_SIZE + 4 + (v.watchToggle and (ICON_SIZE + 3) or 0)
    local nameX = innerX + iconSpace
    local nameWidth = innerWidth - iconSpace
    local objectiveX = nameX + 8
    local objectiveWidth = nameWidth - 8

    -- gemeinsame Quests (mit der Gruppe) stehen ganz oben, danach die normale Liste
    local y, index, count = 0, 0, 0
    local groupBoxes = 0
    if ns.HasGroupQuests and ns.HasGroupQuests() then
        y, index, groupBoxes = RenderGroupView(y, index, alpha, contentWidth, nameX, nameWidth, objectiveX,
            objectiveWidth, padding)
        count = groupBoxes
    end
    local boxesUsed = groupBoxes + #groups

    for groupIndex, group in ipairs(groups) do
        local boxTop = y
        local hr, hg, hb = GetHeaderColor(group)
        local box = GetBox(groupBoxes + groupIndex, alpha)

        -- Titelleiste des Fensters (Gebiet, Klasse, Ruf oder "Angeheftet") mit Anzahl der Quests.
        -- Klick darauf oder auf den Pfeil klappt das Gebiet ein bzw. aus.
        local collapsed = false
        if showZones or group.pinned then
            local groupKey = group.pinned and "#PINNED" or (group.header or "#OTHER")
            collapsed = v.collapsed[groupKey] == true
            index = index + 1
            -- Ist das Gebiet ein Dungeon aus den Dungeon-Daten, steht das Auge der Gruppensuche dahinter
            local eyeDungeon = not group.pinned and ns.FindDungeonForHeader and ns.FindDungeonForHeader(group.header) or nil
            y = AddLine(index, y + 5, nameX, nameWidth, group.header or ns.L("OTHER"), fonts.header, hr, hg, hb, {
                groupKey = groupKey,
                arrow = not collapsed,
                eyeDungeon = eyeDungeon,
                suffix = "|cff8a8a8a" .. #group.quests .. "|r",
            })
            y = y + 4
            box.header:SetHeight(math.max(1, y - boxTop - 1))
            box.header:Show()
            -- Linie unter der Titelleiste in der Farbe der Kategorie
            box.accent:SetColorTexture(hr, hg, hb, 0.7)
            box.accent:Show()
            y = y + 3
        else
            box.header:Hide()
            box.accent:Hide()
            y = y + padding
        end

        for _, info in ipairs(group.quests) do
            local questID = info.questID
            count = count + 1

            local isComplete = C_QuestLog.IsComplete(questID)
            local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
            -- automatisches Aufklappen bei Fortschritt gilt nur im Tracker
            if isTracker then CheckProgress(questID, objectives, isComplete) end

            -- Eingeklapptes Gebiet: Quests werden mitgezählt, aber nicht angezeigt
            if not collapsed then

            -- Questname, eingefärbt nach Schwierigkeit, mit Level dahinter
            local r, g, b = 1, 1, 1
            if info.level and LevelColor() then
                local color = LevelColor()(info.level)
                r, g, b = color.r, color.g, color.b
            end
            local name = info.title or ("Quest " .. questID)
            if info.level and info.level > 0 then
                name = name .. " (" .. info.level .. ")"
            end
            if db.showQuestType then
                local typeText = GetQuestTypeText(questID, info.zoneHeader)
                if typeText ~= "" then
                    name = name .. " |cff88ccff" .. typeText .. "|r"
                end
            end
            if isComplete then
                name = name .. " |cff00ff00" .. ns.L("COMPLETE_TAG") .. "|r"
            end

            -- Truhe anzeigen, wenn die beste Belohnung selten genug ist
            local rewardQuality = nil
            if db.rewardHighlight > 0 then
                local quality = GetBestRewardQuality(questID)
                if quality >= db.rewardHighlight then
                    rewardQuality = quality
                end
            end

            -- Questgegenstand (benutzbarer Gegenstand zur Quest), falls es einen gibt
            local questItem = nil
            local logIndex = GetQuestLogSpecialItemInfo and C_QuestLog.GetLogIndexForQuestID(questID)
            if logIndex then
                local itemLink, itemIcon, _, showWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
                if itemLink and (not isComplete or showWhenComplete) then
                    questItem = { link = itemLink, icon = itemIcon, logIndex = logIndex }
                end
            end

            -- Welche Fortschrittszeilen gibt es?
            local details = {}
            if isComplete then
                table.insert(details, { text = "- " .. ns.L("READY_TO_TURN_IN"), r = 0, g = 1, b = 0 })
            else
                for _, objective in ipairs(objectives) do
                    if objective.text and objective.text ~= "" then
                        local shade = objective.finished and 0.5 or 0.85
                        table.insert(details, { text = "- " .. objective.text, r = shade, g = shade, b = shade })
                    end
                end
            end

            local arrowState = nil
            local expanded = false
            if #details > 0 then
                expanded = IsExpandedIn(v, questID)
                arrowState = expanded
            end

            index = index + 1
            y = AddLine(index, y + 2, nameX, nameWidth, name, fonts.quest, r, g, b, {
                questID = questID,
                arrow = arrowState,
                reward = rewardQuality,
                questItem = questItem,
                -- Questlog: true = verfolgt (gold), false = leeres Kästchen; Tracker: nil = kein Kästchen
                watch = v.watchToggle and (C_QuestLog.GetQuestWatchType(questID) ~= nil),
            })

            if expanded then
                for _, detail in ipairs(details) do
                    index = index + 1
                    y = AddLine(index, y, objectiveX, objectiveWidth, detail.text, fonts.objective,
                        detail.r, detail.g, detail.b)
                end
            end
            end -- if not collapsed
        end

        y = y + padding
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", v.content, "TOPLEFT", 0, -boxTop)
        box:SetSize(contentWidth, y - boxTop)
        box:Show()
        y = y + (v.boxGap or BOX_GAP) -- Questlog: etwas mehr Luft zwischen den Kategorien
    end

    if count == 0 then
        index = index + 1
        y = AddLine(index, y, 0, contentWidth, emptyText(), fonts.objective, 0.6, 0.6, 0.6)
    end

    -- Übrige Zeilen und Rahmen aus vorherigen Durchläufen verstecken
    for i = index + 1, #v.lines do
        v.lines[i]:Hide()
    end
    for i = boxesUsed + 1, #v.boxes do
        v.boxes[i]:Hide()
    end
    v.content:SetHeight(math.max(1, y))
    view = trackerView
    return count, y
end

function ns.UpdateTracker()
    updatePending = false
    if not tracker then return end
    local db = ns.db
    UpdateTabs()

    ns.UpdateFonts()
    BuildFactionNames()
    local alpha = 1 - db.backgroundTransparency / 100

    -- Filter-Knopf grün bei gewähltem Filter, orange beim automatischen Instanz-Filter
    local _, filterMode = GetActiveFilters()
    local filterActive = filterMode ~= "DEFAULT"
    if filterMode == "INSTANCE" then
        filterButton:SetText("|cffff9900" .. ns.L("BTN_FILTER") .. "|r")
    elseif filterActive then
        filterButton:SetText("|cff00ff00" .. ns.L("BTN_FILTER") .. "|r")
    else
        filterButton:SetText(ns.L("BTN_FILTER"))
    end

    local count, y = RenderQuestList(trackerView, CollectGroups(), math.max(1, tracker:GetWidth() - 12), alpha,
        function()
            if filterMode == "INSTANCE" then return ns.L("EMPTY_INSTANCE") end
            if filterActive then return ns.L("EMPTY_FILTER") end
            if db.onlyTracked then return ns.L("EMPTY_TRACKED") end
            return ns.L("EMPTY_LOG")
        end)

    title:SetText(ns.L("TRACKER_TITLE") .. "  |cff8a8a8a" .. count .. "|r")
    if title.button then title.button:SetWidth(math.max(40, title:GetStringWidth() + 8)) end
    -- Titelleiste folgt der eingestellten Hintergrund-Transparenz
    local headerColor = ns.Style.COLOR.header
    headerBar:SetBackdropColor(headerColor[1], headerColor[2], headerColor[3], math.max(alpha, 0.15))

    -- Scrollposition begrenzen, falls die Liste kürzer geworden ist
    local maxScroll = math.max(0, y - scrollFrame:GetHeight())
    if scrollFrame:GetVerticalScroll() > maxScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    end

    -- offener Questlog an der Weltkarte zeigt dieselben Quests: gleich mit aktualisieren
    if ns.UpdateQuestLog then ns.UpdateQuestLog() end
end

-- Bausteine für den Questlog an der Weltkarte (QuestLog.lua)
ns.QuestList = {
    -- neue Ansicht in einem Inhaltsrahmen (content) anlegen
    NewView = function(content, prefix)
        -- Questlog: Quests standardmäßig aufgeklappt (expandedDefault), etwas mehr Abstand zwischen den Kategorien
        return { content = content, lines = {}, boxes = {}, prefix = prefix, collapsed = {}, expanded = {},
            expandedDefault = true, boxGap = 14, anchor = "ANCHOR_RIGHT", watchToggle = true }
    end,
    Render = function(v, opts, contentWidth, emptyText)
        ns.UpdateFonts()
        BuildFactionNames()
        return RenderQuestList(v, CollectGroups(opts), contentWidth, 1, emptyText)
    end,
    OpenFilterMenu = OpenFilterMenu,
    HasFilters = function(dbKey) return select(2, GetSelectedFilters(dbKey)) ~= "DEFAULT" end,
    -- für die Detailansicht im Questlog: dieselben Befehle wie im Rechtsklick-Menü
    OpenMenu = function(owner, questID) OpenQuestMenu(owner, questID, true) end,
    Abandon = AbandonQuest,
    Share = ShareQuest,
    TogglePinned = TogglePinned,
    LevelColor = function(level)
        local fn = LevelColor()
        return fn and level and fn(level) or nil
    end,
    QuestTypeText = GetQuestTypeText,
    ShowQuestTooltip = ShowQuestTooltip,
    Fonts = function() ns.UpdateFonts() return fonts end,
}

-- Mehrere Ereignisse kurz hintereinander werden zu einer Aktualisierung zusammengefasst
function ns.RequestUpdate()
    if updatePending or not tracker then return end
    updatePending = true
    C_Timer.After(0.1, ns.UpdateTracker)
end

---------------------------------------------------------------------------
-- Position, Größe, Entsperren, Ein-/Ausblenden
---------------------------------------------------------------------------

-- Tracker zeigen oder verstecken (per Rechtsklick auf den Minimap-Button oder im Kampf)
function ns.UpdateVisibility()
    if not tracker then return end
    local db = ns.db
    local hiddenByCombat = db.hideInCombat and ns.inCombat
    tracker:SetShown(not db.trackerHidden and not hiddenByCombat)
end

-- Standard mit ForeverMinimap: direkt unter der Minimap, die Fenster genau so breit wie die Karte samt Rahmen
-- (Tracker = Kartenbreite + 2 px Rahmen + 2 x 6 px Einzug der Fenster). Zieht man den Tracker selbst woanders hin,
-- gilt wieder die eigene Position; "Position zuruecksetzen" haengt ihn wieder unter die Minimap.
-- ForeverMinimap meldet Aenderungen (Kartengroesse, Leiste oben/unten, Groesse im Bearbeitungsmodus) ueber den Hub
do
    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    if hubUI and hubUI.On then
        hubUI.On("ForeverMinimap.Layout", function() if ns.ApplyLayout then ns.ApplyLayout() end end)
        -- ForeverBars: Mikromenü unter der Karte angedockt bzw. gelöst
        hubUI.On("ForeverBars.Layout", function() if ns.ApplyLayout then ns.ApplyLayout() end end)
    end
end

-- Mikromenü von ForeverBars, wenn es unter der Minimap angedockt ist (dann kommt der Tracker darunter)
local function DockedMicroMenu()
    local bars = _G.ForeverBarsDB and _G.ForeverBarsDB.bars
    local micro = _G.ForeverBars_micro
    if not (bars and bars.micro and bars.micro.enabled and bars.micro.dockMinimap) then return nil end
    if not (micro and micro:IsShown() and micro:GetBottom()) then return nil end
    return micro
end

do
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_LOGIN")
    watcher:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        local manager = _G.EditModeManagerFrame
        if manager and manager.HookScript then
            manager:HookScript("OnHide", function()
                for _, delay in ipairs({ 0.2, 1, 2.5 }) do
                    C_Timer.After(delay, function() if ns.ApplyLayout then ns.ApplyLayout() end end)
                end
            end)
        end
        -- Breite hängt an Karte und Knopfleiste von ForeverMinimap: ändern die sich (Größe, ein-/ausgeblendet –
        -- z. B. erst ein paar Sekunden nach dem Bearbeitungsmodus), sofort nachziehen statt einen Zwischenstand
        -- zu behalten (sonst war die Breite nach jedem Bearbeitungsmodus eine andere)
        local queued = false
        local function Reapply()
            if queued then return end
            queued = true
            C_Timer.After(0.1, function()
                queued = false
                if ns.ApplyLayout then ns.ApplyLayout() end
            end)
        end
        local hooked = {}
        local function HookFrames()
            for _, name in ipairs({ "Minimap", "ForeverMinimapStrip", "ForeverMinimapBar" }) do
                local frame = _G[name]
                if frame and frame.HookScript and not hooked[frame] then
                    hooked[frame] = true
                    frame:HookScript("OnSizeChanged", Reapply)
                    frame:HookScript("OnShow", Reapply)
                    frame:HookScript("OnHide", Reapply)
                end
            end
        end
        HookFrames()
        C_Timer.After(3, HookFrames) -- falls ForeverMinimap seine Leisten erst nach uns baut
    end)
end

local function MinimapAnchor()
    if not ns.db.followMinimap then return nil end
    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ForeverMinimap")) then return nil end
    local map = _G.Minimap
    if not (map and map:IsShown() and map:GetBottom()) then return nil end
    -- liegt die Leiste der Minimap unten, kommt der Tracker unter die Leiste
    local bar = _G.ForeverMinimapBar
    if bar and bar:IsShown() and bar:GetBottom() and bar:GetBottom() < map:GetBottom() then return bar, map end
    return map, map
end

-- Bearbeitungsmodus offen: Karte, Mikromenü usw. sind nur vorübergehend verstellt – der Tracker bleibt, wo er ist,
-- und wird nach dem Schließen mehrfach sauber neu gesetzt (Blizzard und die anderen Forever-Addons brauchen kurz)
local function EditModeOpen()
    return _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown() or false
end

-- Lage von Karte, Knopfleiste und Mikromenü als Kennung: ändert sie sich, ohne dass ein Ereignis kam (z. B. wenn die
-- Knopfleiste nach dem Bearbeitungsmodus noch ein paar Sekunden nachrückt), setzt die Nachkontrolle unten den
-- Tracker neu – sonst behielt er einen Zwischenstand und sprang in der Breite
function ns.LayoutSignature()
    local map = _G.Minimap
    if not (map and map:GetLeft()) then return nil end
    local left, right = map:GetLeft(), map:GetRight()
    if _G.ForeverMinimap_GetSpan then left, right = _G.ForeverMinimap_GetSpan() end
    local micro = DockedMicroMenu()
    return string.format("%d:%d:%d:%d", math.floor((left or 0) + 0.5), math.floor((right or 0) + 0.5),
        math.floor(map:GetBottom() + 0.5), micro and math.floor(micro:GetBottom() + 0.5) or 0)
end

do
    local hubUI = _G.ForeverHub and _G.ForeverHub.UI
    if hubUI and hubUI.Every then
        hubUI.Every(1, function()
            if EditModeOpen() then return end
            local signature = ns.LayoutSignature()
            if signature and signature ~= ns.layoutSignature then ns.ApplyLayout() end
        end, { addon = "ForeverQuests", name = "TrackerLayout",
            when = function() return tracker ~= nil and tracker:IsShown() and ns.db and ns.db.followMinimap end })
    end
end

function ns.ApplyLayout()
    if not tracker then return end
    if EditModeOpen() then return end
    ns.layoutSignature = ns.LayoutSignature()
    local db = ns.db
    local anchor, map = MinimapAnchor()
    if anchor then
        local k = map:GetEffectiveScale() / tracker:GetEffectiveScale()
        tracker:ClearAllPoints()
        local offset = -8 / k
        -- Angedocktes Mikromenü von ForeverBars: der Tracker kommt 4 px darunter. Er hängt trotzdem an der Karte
        -- (nicht am Menü – das ist ein geschützter Rahmen; daran gehängt dürfte der Tracker im Kampf nicht mehr
        -- ein-/ausgeblendet werden), der Abstand wird aus der Lage des Menüs berechnet
        local micro = DockedMicroMenu()
        if micro then
            local trackerScale = tracker:GetEffectiveScale()
            offset = (micro:GetBottom() * micro:GetEffectiveScale() - anchor:GetBottom() * anchor:GetEffectiveScale())
                / trackerScale - 4 / k
        end
        -- Breite: Karte samt Rahmen und ausgeklappter Knopfleiste (ForeverMinimap_GetSpan); die Fenster im Tracker
        -- sind je 6 px eingerückt, darum + 12. Ohne die Angabe: nur die Karte.
        local trackerScale = tracker:GetEffectiveScale()
        local width, shift = (map:GetWidth() + 2) * k + 12, 0
        local left, right = nil, nil
        if _G.ForeverMinimap_GetSpan then left, right = _G.ForeverMinimap_GetSpan() end
        if left and right and anchor:GetCenter() then
            width = (right - left) / trackerScale + 12
            shift = ((left + right) / 2 - anchor:GetCenter() * anchor:GetEffectiveScale()) / trackerScale
        end
        tracker:SetPoint("TOP", anchor, "BOTTOM", shift, offset)
        tracker:SetSize(math.floor(width + 0.5), db.height)
        ns.UpdateVisibility()
        ns.RequestUpdate()
        return
    end
    if db.x == nil or db.y == nil then
        db.x = math.floor(UIParent:GetWidth() - db.width - 40)
        db.y = math.floor(UIParent:GetHeight() - 220)
    end
    tracker:ClearAllPoints()
    tracker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.x, db.y)
    tracker:SetSize(db.width, db.height)
    ns.UpdateVisibility()
    ns.RequestUpdate()
end

function ns.ToggleTracker()
    ns.db.trackerHidden = not ns.db.trackerHidden
    ns.UpdateVisibility()
end

-- Nach Ziehen/Größenänderung mit der Maus die neuen Werte übernehmen
local function SaveFromFrame()
    tracker:StopMovingOrSizing()
    local db = ns.db
    db.followMinimap = false -- selbst verschoben/vergroessert: ab jetzt eigene Position
    db.x = math.floor(tracker:GetLeft() + 0.5)
    db.y = math.floor(tracker:GetTop() + 0.5)
    db.width = math.floor(tracker:GetWidth() + 0.5)
    db.height = math.floor(tracker:GetHeight() + 0.5)
    ns.ApplyLayout()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.SetUnlocked(unlocked)
    ns.unlocked = unlocked
    if overlay then
        overlay:SetShown(unlocked)
    end
end

function ns.ResetPosition()
    local db = ns.db
    db.x, db.y = nil, nil
    db.followMinimap = true -- wieder unter die Minimap (wenn ForeverMinimap aktiv ist)
    db.width = ns.defaults.width
    db.height = ns.defaults.height
    ns.ApplyLayout()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Beim Umschalten der Grundeinstellung gilt sie wieder für alle Quests
function ns.ResetExpanded()
    wipe(ns.expanded)
    wipe(ns.autoExpandedAt)
end

-- Nach einem Sprachwechsel: feste Beschriftungen des Trackers neu setzen
function ns.UpdateTrackerTexts()
    if not tracker then return end
    dungeonButton:SetText(ns.L("BTN_DUNGEONS"))
    unlockHint:SetText(ns.L("UNLOCK_HINT"))
    ns.UpdateTracker() -- setzt auch Titel, Filter-Knopf und alle Zeilen
end

---------------------------------------------------------------------------
-- Tracker-Fenster erstellen
---------------------------------------------------------------------------

function ns.CreateTracker()
    if tracker then return end

    tracker = CreateFrame("Frame", "ForeverQuestsTracker", UIParent)
    do -- andere Forever-Rahmen rasten am Tracker ein
        local hub = _G.ForeverHub and _G.ForeverHub.UI
        if hub and hub.AddMover then hub.AddMover(tracker) end
    end
    -- Über den Aktionsleisten (z. B. Bartender4), damit deren - auch leere/unsichtbare - Knöpfe
    -- nicht die Maus über dem Tracker abfangen. Menüs, Dungeonfenster und Tooltips liegen noch höher.
    tracker:SetFrameStrata("HIGH")
    tracker:SetMovable(true)
    tracker:SetResizable(true)
    tracker:SetResizeBounds(200, 100, 800, 1200)
    tracker:SetClampedToScreen(true)
    tracker:SetScript("OnSizeChanged", ns.RequestUpdate)

    local Style = ns.Style

    -- Titelleiste mit goldener Linie, wie beim Dungeon-Fenster
    -- links/rechts 6 px eingerückt wie der Scrollbereich darunter: Leiste und Gebiets-Fenster sind genau gleich
    -- breit und bleiben es bei jeder Größenänderung (beide hängen am Tracker)
    headerBar = CreateFrame("Frame", nil, tracker, "BackdropTemplate")
    headerBar:SetPoint("TOPLEFT", 6, 0)
    headerBar:SetPoint("TOPRIGHT", -6, 0)
    headerBar:SetHeight(26)
    headerBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    headerBar:SetBackdropColor(unpack(Style.COLOR.header))
    local accentLine = headerBar:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("BOTTOMLEFT")
    accentLine:SetPoint("BOTTOMRIGHT")
    accentLine:SetHeight(1)
    accentLine:SetColorTexture(Style.COLOR.accent[1], Style.COLOR.accent[2], Style.COLOR.accent[3], 0.6)

    -- Knöpfe rechts in der Titelleiste: Dungeons, Filter, Menü
    -- Texte kommen aus Locales.lua; Tooltips werden erst beim Anzeigen übersetzt
    dungeonButton = Style.CreateButton(headerBar, ns.L("BTN_DUNGEONS"), 62, 18,
        function() ns.ToggleDungeons() end, function(tooltip) tooltip:AddLine(ns.L("TIP_DUNGEONS")) end)
    dungeonButton:SetPoint("RIGHT", -4, 0)

    filterButton = Style.CreateButton(headerBar, ns.L("BTN_FILTER"), 42, 18, function(self) OpenFilterMenu(self) end, function(tooltip)
        tooltip:AddLine(ns.L("FILTER_TITLE"))
        tooltip:AddLine(ns.L("TIP_FILTER_ACTIVE", GetActiveFilterText()), 1, 1, 1, true)
    end)
    filterButton:SetPoint("RIGHT", dungeonButton, "LEFT", -4, 0)

    -- Menü: quadratischer Knopf mit Zahnrad (wie der Einstellungs-Knopf von ForeverMinimap)
    menuButton = Style.CreateButton(headerBar, "", 18, 18,
        function() ns.ToggleOptions() end, function(tooltip)
            tooltip:AddLine(ns.L("BTN_MENU"))
            tooltip:AddLine(ns.L("TIP_MENU"), 1, 1, 1, true)
        end)
    menuButton:SetPoint("RIGHT", filterButton, "LEFT", -4, 0)
    local gear = menuButton:CreateTexture(nil, "ARTWORK")
    gear:SetPoint("TOPLEFT", 2, -2)
    gear:SetPoint("BOTTOMRIGHT", -2, 2)
    gear:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    gear:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    title = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 8, 0)
    title:SetPoint("RIGHT", menuButton, "LEFT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(1, 1, 1)

    -- Klick auf den Schriftzug "Quests": Questlog öffnen/schließen (Fläche so breit wie der Text, siehe UpdateTracker)
    local titleButton = CreateFrame("Button", nil, headerBar)
    titleButton:SetPoint("LEFT", title, "LEFT", -4, 0)
    titleButton:SetHeight(18)
    titleButton:SetWidth(60)
    titleButton:RegisterForClicks("LeftButtonUp")
    titleButton:SetScript("OnClick", function()
        if InCombatLockdown() then return end -- im Kampf öffnet Blizzard das Questlog nicht
        if ToggleQuestLog then ToggleQuestLog() elseif ToggleWorldMap then ToggleWorldMap() end
    end)
    titleButton:SetScript("OnEnter", function(self)
        title:SetTextColor(1, 0.82, 0)
        local tooltip = ns.Style.GetTooltip()
        tooltip:SetOwner(self, "ANCHOR_TOP")
        tooltip:AddLine(ns.L("TIP_OPEN_QUESTLOG"))
        tooltip:Show()
    end)
    titleButton:SetScript("OnLeave", function()
        title:SetTextColor(1, 1, 1)
        ns.Style.GetTooltip():Hide()
    end)
    title.button = titleButton

    -- Scrollbereich: Inhalt, der nicht in die Höhe passt, ist per Mausrad erreichbar
    scrollFrame = CreateFrame("ScrollFrame", nil, tracker)
    scrollFrame:SetPoint("TOPLEFT", 6, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -6, 6)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local newScroll = self:GetVerticalScroll() - delta * 30
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, newScroll)))
    end)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    trackerView.content = content

    -- Reiter "Quests" | "Gruppe" unter der Titelleiste (nur bei vorgeschlagenen Quests, siehe GroupQuests.lua)
    tabRow = CreateFrame("Frame", nil, tracker)
    tabRow:SetPoint("TOPLEFT", 6, -30)
    tabRow:SetPoint("TOPRIGHT", -6, -30)
    tabRow:SetHeight(20)
    questsTab = Style.CreateButton(tabRow, ns.L("TAB_QUESTS"), 80, 18, function()
        ns.trackerTab = "quests"
        ns.UpdateTracker()
    end)
    questsTab:SetPoint("LEFT", 0, 0)
    groupTab = Style.CreateButton(tabRow, ns.L("TAB_GROUP"), 80, 18, function()
        ns.trackerTab = "group"
        ns.UpdateTracker()
    end)
    groupTab:SetPoint("LEFT", questsTab, "RIGHT", 4, 0)
    tabRow:Hide()

    -- Überlagerung im entsperrten Zustand: zum Verschieben und Größe ändern
    overlay = CreateFrame("Frame", nil, tracker, "BackdropTemplate")
    overlay:SetAllPoints()
    overlay:SetFrameLevel(tracker:GetFrameLevel() + 20)
    -- Entsperrt: goldener Rahmen und leicht getönter Hintergrund
    Style.SetFlat(overlay, { 0.10, 0.10, 0.12, 0.75 },
        { Style.COLOR.accent[1], Style.COLOR.accent[2], Style.COLOR.accent[3], 1 })
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetScript("OnDragStart", function()
        local hub = _G.ForeverHub and _G.ForeverHub.UI
        if hub and hub.BeginDrag then hub.BeginDrag(tracker) end -- Einrasten an anderen Rahmen (Umschalt = aus)
        tracker:StartMoving()
    end)
    overlay:SetScript("OnDragStop", function()
        tracker:StopMovingOrSizing()
        local hub = _G.ForeverHub and _G.ForeverHub.UI
        local dx, dy = 0, 0
        if hub and hub.EndDrag then dx, dy = hub.EndDrag() end
        local left, top = tracker:GetLeft(), tracker:GetTop()
        if (dx ~= 0 or dy ~= 0) and left and top then
            local s = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
            tracker:ClearAllPoints()
            tracker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + dx / s, top + dy / s)
        end
        SaveFromFrame()
    end)

    unlockHint = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    unlockHint:SetPoint("CENTER")
    unlockHint:SetText(ns.L("UNLOCK_HINT"))

    local grip = CreateFrame("Button", nil, overlay)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() tracker:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", SaveFromFrame)

    overlay:Hide()

    ns.inCombat = UnitAffectingCombat("player")

    -- Ereignisse, bei denen sich die Questliste oder die Sichtbarkeit ändern kann
    local events = {
        "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
        "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GET_ITEM_INFO_RECEIVED",
    }
    for _, event in ipairs(events) do
        tracker:RegisterEvent(event)
    end
    tracker:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Kampfbeginn
            ns.inCombat = true
            ns.UpdateVisibility()
            -- Gegenstand-Knöpfe ein letztes Mal nachführen (geht hier noch, die Kampfsperre greift erst danach),
            -- damit sie z. B. bei "im Kampf ausblenden" mit dem Tracker verschwinden
            QuestItemButtons.Sync()
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Kampfende
            ns.inCombat = false
            ns.UpdateVisibility()
            if blizzardUpdatePending then
                ns.UpdateBlizzardTracker()
            end
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            -- Nur reagieren, wenn wir auf Daten für Questbelohnungen warten
            if not waitingForItemData then return end
            waitingForItemData = false
        elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
            -- Abgegebene oder abgebrochene Quests vergessen
            local questID = ...
            if questID then
                ns.db.pinned[questID] = nil
                ns.expanded[questID] = nil
                ns.autoExpandedAt[questID] = nil
                progressSnapshots[questID] = nil
                rewardQualityCache[questID] = nil
            end
        end
        ns.RequestUpdate()
    end)

    -- (gemeinsamer Takt aus ForeverCore)
    local hub = _G.ForeverHub and _G.ForeverHub.UI
    if hub and hub.Every then
        hub.Every(10, CheckAutoCollapse, { addon = "ForeverQuests", name = "Auto collapse" })
    else
        C_Timer.NewTicker(10, CheckAutoCollapse)
    end

    ns.ApplyLayout()
end
