-- ForeverSkin – Trainer.lua: Lehrerfenster im Forever-Stil, dazu unten der Knopf "Leisten aktualisieren (Anzahl)":
-- mit ForeverSpellbook – liegt in den Aktionsleisten noch ein alter Rang, ersetzt ein Klick ihn durch den neuen
-- (UI.API.ForeverSpellbook). ("Alle lernen" gab es kurz, auf Wunsch wieder entfernt.)
-- Blizzards Fenster lädt erst beim ersten Besuch (Blizzard_TrainerUI) – darum beim Laden dieses Addons umgestalten.
local _, ns = ...
local C, T = ns.C, ns.T

local function G(name) return _G[name] end

local replace

local function UpdateButtons()
    if not replace then return end
    local api = ns.UI.API and ns.UI.API.ForeverSpellbook
    local outdated = api and api.OutdatedCount and api.OutdatedCount() or 0
    replace:SetText(string.format(T("Leisten aktualisieren (%d)", "Update bars (%d)"), outdated))
    replace:SetWidth(math.max(130, replace:GetFontString():GetStringWidth() + 20))
    replace:SetShown(outdated > 0)
end
ns.UpdateTrainerButtons = UpdateButtons

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
    -- Filter ("Optionen"): flach wie die anderen Knöpfe, der Pfeil bleibt
    local filter = f.FilterDropdown or f.FilterDropDown
    if filter and filter.IsObjectType and filter:IsObjectType("Button") then
        local arrow = filter.Arrow
        ns.SkinButton(filter)
        if filter.NineSlice then ns.Hide(filter.NineSlice) end
        if filter.Background then ns.Hide(filter.Background) end
        if arrow and arrow.SetAlpha then arrow:SetAlpha(1) end
    end
    ns.SkinButton(f.TrainButton or G("ClassTrainerTrainButton"))
    ns.SkinButton(G("ClassTrainerCancelButton"))
    -- Laufleisten im Fenster suchen (Retail: Rahmen mit Track/Thumb, Classic: Slider) – gold wie im Gespräch
    local bars = {}
    local function FindBars(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if (type(child.Track) == "table" and (child.Track.Thumb or child.Back)) or
                (child:IsObjectType("Slider") and (child:GetName() or ""):find("ScrollBar")) then
                bars[#bars + 1] = child
            elseif depth < 3 then
                FindBars(child, depth + 1)
            end
        end
    end
    FindBars(f, 1)
    for _, bar in ipairs(bars) do ns.SkinScrollBar(bar) end
    ns.Watch(f)

    -- Knopf "Leisten aktualisieren" links neben "Ausbilden" (nur sichtbar, wenn alte Ränge in den Leisten liegen)
    local train = f.TrainButton or G("ClassTrainerTrainButton")
    replace = ns.UI.Button(f, "", 130, function()
        local api = ns.UI.API and ns.UI.API.ForeverSpellbook
        if api and api.ReplaceOutdated then pcall(api.ReplaceOutdated) end
        C_Timer.After(0.5, function() pcall(UpdateButtons) end)
    end)
    if train then
        replace:SetPoint("RIGHT", train, "LEFT", -6, 0)
    else
        replace:SetPoint("BOTTOMRIGHT", -100, 6)
    end
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
    -- Visitenkarte wie bei Gespräch und Händler; Liste rückt darunter (Innenfläche oben ab 84, darin Liste und ggf.
    -- die Fertigkeitsstufe – hängen sie an der Innenfläche, wandern sie mit)
    local inset = f.Inset or G("ClassTrainerFrameInset")
    -- unten über der Knopfleiste (30) enden – sonst lag der untere Pfeil der Laufleiste auf "Ausbilden"
    local function Place()
        if inset then ns.Fit(f, inset, 84, 34) end
        ns.Fit(f, f.skillStepButton, 88, nil, inset)
        ns.Fit(f, f.ScrollBox, 88, 38, inset)
        ns.Fit(f, G("ClassTrainerListScrollFrame"), 88, 38, inset)
        for _, bar in ipairs(bars) do ns.Fit(f, bar, 88, 38, f.ScrollBox or inset) end
    end
    local function Card()
        ns.NpcCard(f, "npc", T("Lehrer", "Trainer"), function() return T("Lehrer", "Trainer") end, filter and 130 or 14)
    end
    f:HookScript("OnShow", function()
        Card()
        Later()
        C_Timer.After(0, function() pcall(Place) end)
    end)
    if f:IsShown() then
        Card()
        C_Timer.After(0, function() pcall(Place) end)
    end
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
