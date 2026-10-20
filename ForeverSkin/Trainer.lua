-- ForeverSkin – Trainer.lua: Lehrerfenster im Forever-Stil, dazu zwei Knöpfe unten:
--  * "Alle lernen (Preis)": lernt nacheinander alles, was gerade verfügbar ist und bezahlbar
--  * "Leisten aktualisieren (Anzahl)": mit ForeverSpellbook – liegt in den Aktionsleisten noch ein alter Rang,
--    ersetzt ein Klick ihn durch den neuen (UI.API.ForeverSpellbook)
-- Blizzards Fenster lädt erst beim ersten Besuch (Blizzard_TrainerUI) – darum beim Laden dieses Addons umgestalten.
local _, ns = ...
local C, T = ns.C, ns.T

local function G(name) return _G[name] end

---------------------------------------------------------------------------
-- Was gibt es zu lernen? (GetTrainerServiceInfo liefert in Forever die Werte in anderer Reihenfolge als in Retail –
-- wie in ForeverSpellbook nach Inhalt erkennen statt nach Position)
---------------------------------------------------------------------------
local function ServiceType(i)
    local values = { GetTrainerServiceInfo(i) }
    for k = 2, select("#", GetTrainerServiceInfo(i)) do
        local v = values[k]
        if v == "available" or v == "unavailable" or v == "used" or v == "header" then return v end
    end
end

-- verfügbare und bezahlbare Lernangebote: Liste der Nummern und Gesamtpreis
local function Learnable()
    local list, total = {}, 0
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return list, 0 end
    local money = GetMoney()
    for i = 1, GetNumTrainerServices() or 0 do
        if ServiceType(i) == "available" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            if total + cost <= money then
                list[#list + 1] = i
                total = total + cost
            end
        end
    end
    return list, total
end

local function Money(copper)
    if GetMoneyString then return GetMoneyString(copper, true) end
    return GetCoinTextureString and GetCoinTextureString(copper) or tostring(copper)
end

local learnAll, replace
local learning = false

local function UpdateButtons()
    if not learnAll then return end
    local list, total = Learnable()
    learnAll:SetText(#list > 0 and string.format(T("Alle lernen (%s)", "Learn all (%s)"), Money(total))
        or T("Alle lernen", "Learn all"))
    learnAll:SetWidth(math.max(110, learnAll:GetFontString():GetStringWidth() + 20))
    learnAll:SetEnabled(#list > 0 and not learning and not InCombatLockdown())
    local api = ns.UI.API and ns.UI.API.ForeverSpellbook
    local outdated = api and api.OutdatedCount and api.OutdatedCount() or 0
    replace:SetText(string.format(T("Leisten aktualisieren (%d)", "Update bars (%d)"), outdated))
    replace:SetWidth(math.max(130, replace:GetFontString():GetStringWidth() + 20))
    replace:SetShown(outdated > 0)
end
ns.UpdateTrainerButtons = UpdateButtons

-- nacheinander lernen: immer das erste verfügbare bezahlbare Angebot, kurz warten (Liste baut sich neu), weiter
local function LearnNext(count)
    if InCombatLockdown() or not (G("ClassTrainerFrame") and G("ClassTrainerFrame"):IsShown()) then
        learning = false
        UpdateButtons()
        return
    end
    local list = Learnable()
    local index = list[1]
    if not index or count > 60 then
        learning = false
        if count > 0 then
            ns.UI.Chat("ForeverSkin", string.format(T("%d Fähigkeiten gelernt.", "%d abilities learned."), count))
        end
        C_Timer.After(1, function() pcall(UpdateButtons) end) -- Zauberbuch und Leisten sind dann aktuell
        return
    end
    pcall(BuyTrainerService, index)
    C_Timer.After(0.4, function() LearnNext(count + 1) end)
end

---------------------------------------------------------------------------
-- Aussehen
---------------------------------------------------------------------------
local skinnedRows = setmetatable({}, { __mode = "k" })
local function SkinRow(row)
    if not row or skinnedRows[row] then return end
    skinnedRows[row] = true
    local keep = {}
    for _, key in ipairs({ "icon", "Icon" }) do
        if type(row[key]) == "table" then keep[row[key]] = true end
    end
    ns.HideTextures(row, keep)
    ns.Flat(row, C.panel, 1)
    ns.Hover(row, function(b) return b.selectedTex and b.selectedTex:IsShown() end)
end

local function SkinRows()
    local f = G("ClassTrainerFrame")
    local box = f and f.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(SkinRow) end
    for i = 1, 20 do -- Classic: feste Zeilen
        local row = G("ClassTrainerSkill" .. i)
        if not row then break end
        SkinRow(row)
    end
end

local function SkinTrainer()
    local f = G("ClassTrainerFrame")
    if not f or ns.trainerSkinned then return end
    ns.trainerSkinned = true
    ns.SkinWindow(f)
    ns.ContentBox(f, 30, nil, true) -- untere Leiste (Geld, Knöpfe); die Zeilen haben eigene Kästen
    for _, key in ipairs({ "BottomInset", "skillStepButton" }) do
        local obj = f[key]
        if type(obj) == "table" then
            if obj.NineSlice then ns.Hide(obj.NineSlice) end
            ns.HideTextures(obj, { [obj.icon or false] = true })
        end
    end
    if type(f.skillStepButton) == "table" then ns.Flat(f.skillStepButton, C.panel, 1) end
    ns.SkinButton(f.TrainButton or G("ClassTrainerTrainButton"))
    ns.SkinButton(G("ClassTrainerCancelButton"))
    ns.SkinScrollBar(f.ScrollBar or G("ClassTrainerListScrollFrameScrollBar"))
    ns.Watch(f)

    -- Knöpfe "Alle lernen" und "Leisten aktualisieren" links neben "Ausbilden"
    local train = f.TrainButton or G("ClassTrainerTrainButton")
    learnAll = ns.UI.Button(f, T("Alle lernen", "Learn all"), 110, function()
        if learning or InCombatLockdown() then return end
        learning = true
        UpdateButtons()
        LearnNext(0)
    end)
    replace = ns.UI.Button(f, "", 130, function()
        local api = ns.UI.API and ns.UI.API.ForeverSpellbook
        if api and api.ReplaceOutdated then pcall(api.ReplaceOutdated) end
        C_Timer.After(0.5, function() pcall(UpdateButtons) end)
    end)
    if train then
        learnAll:SetPoint("RIGHT", train, "LEFT", -6, 0)
    else
        learnAll:SetPoint("BOTTOMRIGHT", -100, 6)
    end
    replace:SetPoint("BOTTOMRIGHT", learnAll, "TOPRIGHT", 0, 6)
    learnAll:SetFrameLevel(f:GetFrameLevel() + 20)
    replace:SetFrameLevel(f:GetFrameLevel() + 20)
    replace:SetScript("OnEnter", function(self)
        local tip = ns.UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine(T("Leisten aktualisieren", "Update bars"))
        tip:AddLine(T("In deinen Aktionsleisten liegen noch alte Ränge. Ein Klick ersetzt sie durch den höchsten gelernten Rang (ForeverSpellbook).",
            "Your action bars still hold old ranks. One click replaces them with the highest learned rank (ForeverSpellbook)."), 1, 1, 1, true)
        tip:Show()
    end)
    replace:SetScript("OnLeave", function() ns.UI.GetTooltip():Hide() end)

    local function Later()
        C_Timer.After(0, function()
            pcall(SkinRows)
            pcall(UpdateButtons)
        end)
    end
    if type(_G.ClassTrainerFrame_Update) == "function" then hooksecurefunc("ClassTrainerFrame_Update", Later) end
    f:HookScript("OnShow", function()
        ns.Portrait(f, "npc")
        Later()
    end)
    Later()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRAINER_UPDATE")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "TRAINER_UPDATE" or event == "PLAYER_MONEY" then
        if ns.trainerSkinned then C_Timer.After(0, function() pcall(SkinRows) pcall(UpdateButtons) end) end
        return
    end
    if event == "ADDON_LOADED" and addon ~= "Blizzard_TrainerUI" then return end
    if not ns.GetDB().trainer or not G("ClassTrainerFrame") then return end
    local ok, err = pcall(SkinTrainer)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "trainer", err) end
end)
