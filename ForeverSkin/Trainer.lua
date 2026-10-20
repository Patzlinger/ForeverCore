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
    -- untere Leiste zweizeilig: oben Haken "Nicht verfügbare ausblenden" und "Leisten aktualisieren", unten Geld und
    -- "Ausbilden"; die Zeilen haben eigene Kästen
    -- FOOTER = Höhe der unteren Leiste, EXTRA = so viel höher endet die Liste unten (mit Luft über der Leiste),
    -- MORE = so viel länger wird die Liste (mehr Zeilen sichtbar)
    local FOOTER = 54
    local EXTRA -- unten so viel höher enden, dass die Liste 6 px über der unteren Leiste aufhört (je Lehrer ermittelt)
    ns.ContentBox(f, FOOTER, nil, true)
    for _, key in ipairs({ "BottomInset", "skillStepButton" }) do
        local obj = f[key]
        if type(obj) == "table" then
            if obj.NineSlice then ns.Hide(obj.NineSlice) end
            ns.HideTextures(obj, { [obj.icon or false] = true })
        end
    end
    if type(f.skillStepButton) == "table" then ns.Flat(f.skillStepButton, C.panel, 1) end
    -- Blizzards Filter ("Optionen") unsichtbar und nicht anklickbar – statt dessen oben "Zauberbuch" und unten der
    -- Haken "Nicht verfügbare ausblenden" (dieselbe Einstellung wie im Filter)
    local filter = f.FilterDropdown or f.FilterDropDown or G("ClassTrainerFrameFilterDropDown")
    if filter then
        filter:SetAlpha(0)
        if filter.EnableMouse then filter:EnableMouse(false) end
        local fb = filter.Button or (filter:GetName() and G(filter:GetName() .. "Button"))
        if fb and fb.EnableMouse then fb:EnableMouse(false) end
    end
    local book = ns.UI.Button(f, T("Zauberbuch", "Spellbook"), 110, function()
        local api = ns.UI.API and ns.UI.API.ForeverSpellbook
        if api and api.Toggle then
            pcall(api.Toggle)
        elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
            pcall(PlayerSpellsUtil.ToggleSpellBookFrame)
        elseif ToggleSpellBook then
            pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
        end
    end)
    book:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -32)
    book:SetFrameLevel(f:GetFrameLevel() + 20)
    -- (das Spiel meldet an/aus je nach Version als true/false oder 1/0 – 0 ist in Lua "wahr")
    local function UnavailableShown()
        local v = GetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter("unavailable")
        return v == true or v == 1
    end
    local hideCheck = ns.UI.Check(f, nil, nil, T("Nicht verfügbare ausblenden", "Hide unavailable"), function(checked)
        if not SetTrainerServiceTypeFilter then return end
        local ok = pcall(SetTrainerServiceTypeFilter, "unavailable", checked and 0 or 1)
        if not ok or UnavailableShown() == checked then
            pcall(SetTrainerServiceTypeFilter, "unavailable", not checked) -- andere Schreibweise (true/false)
        end
        if type(_G.ClassTrainerFrame_Update) == "function" then pcall(_G.ClassTrainerFrame_Update) end
    end)
    hideCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 34)
    hideCheck:SetFrameLevel(f:GetFrameLevel() + 20)
    local function LoadCheck()
        hideCheck:SetChecked(not UnavailableShown())
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

    -- Knopf "Leisten aktualisieren" oben rechts in der unteren Leiste (nur sichtbar, wenn alte Ränge in den Leisten
    -- liegen)
    replace = ns.UI.Button(f, "", 130, function()
        local api = ns.UI.API and ns.UI.API.ForeverSpellbook
        if api and api.ReplaceOutdated then pcall(api.ReplaceOutdated) end
        C_Timer.After(0.5, function() pcall(UpdateButtons) end)
    end)
    replace:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 30)
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

    local Place -- (unten)
    local function Later()
        C_Timer.After(0, function()
            pcall(SkinRows)
            pcall(UpdateButtons)
            -- Blizzard hängt die Liste bei jedem Aktualisieren neu auf (unter die Fertigkeitsstufe, falls sichtbar)
            if Place and f:IsShown() then pcall(Place) end
        end)
    end
    if type(_G.ClassTrainerFrame_Update) == "function" then hooksecurefunc("ClassTrainerFrame_Update", Later) end
    -- Visitenkarte wie bei Gespräch und Händler; Liste rückt darunter (Innenfläche oben ab 84, darin Liste und ggf.
    -- die Fertigkeitsstufe – hängen sie an der Innenfläche, wandern sie mit)
    local inset = f.Inset or G("ClassTrainerFrameInset")
    -- Das Fenster wird um den Platz der Visitenkarte und der zweiten Leistenzeile höher (wie beim Händler): die
    -- Liste behält ihre Höhe (vorher wurde sie gestaucht und lief über die Knöpfe). Oben rückt sie um "down" nach
    -- unten, unten endet sie EXTRA höher über dem Rand – hängt etwas an der Innenfläche/Liste, wandert es mit.
    local baseHeight
    function Place()
        baseHeight = baseHeight or f:GetHeight()
        -- Berufslehrer: kein Zauberbuch-Knopf (der Fertigkeitsbalken steht dort)
        local tradeskill = IsTradeskillTrainer and IsTradeskillTrainer() and true or false
        book:SetShown(not tradeskill)
        -- bei JEDEM Lehrer neu: Blizzards Liste endet beim Berufslehrer höher als beim Klassenlehrer. EXTRA = so viel
        -- höher bzw. (negativ) tiefer endet sie, damit sie 6 px über der unteren Leiste aufhört – kein leerer Rest
        local _, listBottom = ns.Original(f, f.ScrollBox or G("ClassTrainerListScrollFrame") or inset)
        EXTRA = (FOOTER + 6) - (listBottom or (FOOTER + 6))
        local down = 0
        local function Move(region, top, skip)
            local _, bottom = ns.Original(f, region)
            if not bottom then return end
            local d = ns.Fit(f, region, top, bottom + EXTRA, skip, true) or 0
            down = math.max(down, d)
        end
        if inset then Move(inset, 84) end
        ns.Fit(f, f.skillStepButton, 88, nil, inset) -- (feste Höhe: nur verschieben)
        Move(f.ScrollBox, 88, inset)
        Move(G("ClassTrainerListScrollFrame"), 88, inset)
        for _, bar in ipairs(bars) do Move(bar, 88, f.ScrollBox or inset) end
        -- Berufslehrer: Fertigkeitsbalken ("20/75") lag auf dem Namen der Visitenkarte – rechts oben an die Stelle
        -- des Zauberbuch-Knopfs
        local skill = f.statusBar or f.StatusBar or G("ClassTrainerStatusBar")
        if skill and skill.ClearAllPoints then
            skill:ClearAllPoints()
            skill:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, tradeskill and -36 or -60)
            skill:SetWidth(130)
        end
        local want = baseHeight + down + EXTRA
        if math.abs(f:GetHeight() - want) > 0.5 then f:SetHeight(want) end
    end
    local function Card()
        ns.NpcCard(f, "npc", T("Lehrer", "Trainer"), function() return T("Lehrer", "Trainer") end, 130)
    end
    ns.Scaled(f)
    f:HookScript("OnShow", function()
        Card()
        LoadCheck()
        Later()
        C_Timer.After(0, function() pcall(Place) end)
    end)
    if f:IsShown() then
        Card()
        LoadCheck()
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
