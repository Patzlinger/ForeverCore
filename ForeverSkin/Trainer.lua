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
-- Blizzard macht bei manchen Zeilen (z. B. noch nicht lernbar) seine Grafiken beim Aktualisieren wieder sichtbar:
-- darum bei JEDEM Durchgang ausblenden; Fläche und Maus-Rand nur einmal anlegen
local function SkinRow(row)
    if not row then return end
    local keep = {}
    for _, key in ipairs({ "icon", "Icon" }) do
        if type(row[key]) == "table" then keep[row[key]] = true end
    end
    ns.HideTextures(row, keep)
    -- auch auf Unterflächen der Zeile (dort liegen bei manchen Zeilen Blizzards braune Flächen) – nicht bei
    -- Knöpfen (Symbol) und Geld (Münzen)
    for _, child in ipairs({ row:GetChildren() }) do
        local n = child:GetName() or ""
        if not child:IsObjectType("Button") and not n:find("Money") and not child.GetMoney and child ~= row.money then
            ns.HideTextures(child, keep)
        end
    end
    if skinnedRows[row] then return end
    skinnedRows[row] = true
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
    ns.ContentBox(f, FOOTER, nil, true)
    for _, key in ipairs({ "BottomInset", "skillStepButton" }) do
        local obj = f[key]
        if type(obj) == "table" then
            if obj.NineSlice then ns.Hide(obj.NineSlice) end
            ns.HideTextures(obj, { [obj.icon or false] = true })
        end
    end
    -- (Fertigkeitsstufe "Kochlehrling" o. Ä. über der Liste: gestaltet wie eine Zeile, siehe Place)
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
    -- Größe wie das Gesprächsfenster; Liste fest zwischen Visitenkarte (bzw. Fertigkeitsstufe) und unterer Leiste.
    -- (Früher relativ zu Blizzards Lage verschoben – Blizzard hängt die Liste aber je nach Lehrer anders auf, dann
    -- blieb unten Platz frei oder es überlappte oben.) Nach jedem Aktualisieren erneut, weil Blizzard neu aufhängt.
    function ns.TrainerSize()
        local gossip = G("GossipFrame")
        local w = gossip and gossip:GetWidth() or 384
        local h = gossip and gossip:GetHeight() or 512
        if math.abs(f:GetWidth() - w) > 0.5 then f:SetWidth(w) end
        if math.abs(f:GetHeight() - h) > 0.5 then f:SetHeight(h) end
    end
    function Place()
        ns.TrainerSize()
        -- Berufslehrer: kein Zauberbuch-Knopf (der Fertigkeitsbalken steht dort)
        local tradeskill = IsTradeskillTrainer and IsTradeskillTrainer() and true or false
        book:SetShown(not tradeskill)
        local TOP, BOTTOM, LEFT, RIGHT = -87, FOOTER + 6, 10, -30 -- (7 px unter dem Porträt, wie darüber)
        if inset then
            inset:ClearAllPoints()
            inset:SetPoint("TOPLEFT", f, "TOPLEFT", 6, TOP + 4)
            inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, BOTTOM - 4)
        end
        local step = f.skillStepButton
        local stepShown = type(step) == "table" and step:IsShown()
        local list = f.ScrollBox or G("ClassTrainerListScrollFrame")
        if stepShown then
            step:ClearAllPoints()
            step:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, TOP)
            step:SetPoint("RIGHT", f, "RIGHT", RIGHT, 0)
            -- so hoch wie die Zeilen der Liste und wie sie gestaltet (Maus-Rand, Auswahl); über Innenfläche und
            -- Liste, damit sie Klicks bekommt
            local rowH
            if list and list.ForEachFrame then
                list:ForEachFrame(function(row) rowH = rowH or (row:GetHeight() > 10 and row:GetHeight()) or nil end)
            end
            if rowH and math.abs(step:GetHeight() - rowH) > 0.5 then step:SetHeight(rowH) end
            local level = math.max(inset and inset:GetFrameLevel() or 0, list and list:GetFrameLevel() or 0) + 2
            if step:GetFrameLevel() < level then step:SetFrameLevel(level) end
            if step.EnableMouse then step:EnableMouse(true) end
            SkinRow(step)
        end
        if list then
            list:ClearAllPoints()
            if stepShown then
                list:SetPoint("TOPLEFT", step, "BOTTOMLEFT", 0, -4)
            else
                list:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, TOP)
            end
            list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", RIGHT, BOTTOM)
        end
        for _, bar in ipairs(bars) do
            if list then
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, -2)
                bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 8, 2)
            end
        end
        -- Berufslehrer: Fertigkeitsbalken ("20/75") lag auf dem Namen der Visitenkarte – rechts oben an die Stelle
        -- des Zauberbuch-Knopfs
        local skill = f.statusBar or f.StatusBar or G("ClassTrainerStatusBar")
        if skill and skill.ClearAllPoints then
            skill:ClearAllPoints()
            skill:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, tradeskill and -36 or -60)
            skill:SetWidth(130)
        end
    end
    local function Card()
        ns.NpcCard(f, "npc", T("Lehrer", "Trainer"), function() return T("Lehrer", "Trainer") end, 130)
    end
    ns.Scaled(f)
    -- solange offen: fünfmal je Sekunde die sichtbaren Zeilen prüfen (neue Zeilen beim Scrollen, wieder sichtbare
    -- Blizzard-Grafiken) – eigener kleiner Rahmen, läuft nur mit dem Fenster
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.2) then return end
        waited = 0
        pcall(SkinRows)
        -- Blizzard setzt die Größe (v. a. beim Klassenlehrer) teils nachträglich zurück: wieder wie das Gespräch
        if ns.TrainerSize then pcall(ns.TrainerSize) end
    end)
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
