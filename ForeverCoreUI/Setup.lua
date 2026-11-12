-- ForeverCore – Setup.lua: Einrichtungsassistent beim allerersten Start (statt der früheren Begrüßungsseite im Hub).
-- Vier kurze Schritte: 1. Sprache und Spielernamen, 2. welche Addons laufen sollen, 3. Allgemeines (Minimap-Knopf,
-- Einrasten, Blizzard-Fenster verschiebbar), 4. Fertig (Neu laden, falls nötig). Jede Wahl gilt sofort bzw. nach dem
-- Neuladen genau wie im Hub-Fenster – der Assistent nutzt dieselben Schalter (hub.setup in ForeverHub.lua).
-- Später jederzeit: /forever einrichtung (bzw. /forever setup).
local hub = _G.ForeverHub
local UI = hub and hub.UI
if not UI or not hub.setup or UI.ShowSetup then return end
local T, C, S = UI.T, UI.COLOR, hub.setup

local W, H = 600, 440
local PAD = 20
local STEPS = 4

local f, pages, step, stepText, back, nextBtn, langChanged, onDone

local function AnyPending()
    if langChanged then return true end
    for _, a in ipairs(S.Addons()) do
        if S.IsPending(a.name) then return true end
    end
    return false
end

local function Title(page, text)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", 0, 0)
    fs:SetText(text)
    return fs
end

local function Intro(page, text, y)
    local fs = UI.Hint(page, 0, y or -28, W - PAD * 2, text)
    fs:SetWordWrap(true)
    fs:SetTextColor(0.8, 0.8, 0.8)
    return fs
end

local function Tip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine(title)
        tip:AddLine(text, 1, 1, 1, true)
        tip:Show()
    end)
    frame:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
end

---------------------------------------------------------------------------
-- Schritt 1: Willkommen, Sprache, Spielernamen
---------------------------------------------------------------------------
local function BuildWelcome(page)
    Title(page, T("Willkommen bei Forever Core UI", "Welcome to Forever Core UI"))
    Intro(page, T("Ein paar kurze Fragen, dann ist alles eingerichtet. Du kannst alles später im Hub (/forever) ändern – diesen Assistenten startest du wieder mit /forever einrichtung.",
        "A few quick questions and you're set. You can change everything later in the hub (/forever) – run this assistant again with /forever setup."))
    local y = -96
    local loads = {}
    if UI.GERMAN_CLIENT then
        local LANGS = {
            { key = "AUTO", label = T("Automatisch (Client)", "Automatic (client)") },
            { key = "deDE", label = "Deutsch" },
            { key = "enUS", label = "English" },
        }
        local function Current() return S.GetDB().language or "AUTO" end
        local function LabelOf(key)
            for _, l in ipairs(LANGS) do if l.key == key then return l.label end end
            return key
        end
        local label = UI.Text(page, "field", T("Sprache", "Language"))
        label:SetPoint("TOPLEFT", 0, y - 4)
        local lang = UI.AddArrow(UI.Button(page, "", 200))
        lang:SetPoint("TOPLEFT", 150, y)
        lang:SetScript("OnClick", function(self)
            UI.ChoiceMenu(self, LANGS, Current, function(key)
                S.GetDB().language = key ~= "AUTO" and key or nil
                self:SetText(LabelOf(Current()))
                langChanged = true
            end)
        end)
        loads[#loads + 1] = function() lang:SetText(LabelOf(Current())) end
        local hint = UI.Hint(page, 150, y - 28, 380, T("Gilt nach dem Neuladen für alle Forever-Addons.",
            "Applies to all Forever addons after reloading."))
        hint:SetWordWrap(true)
        y = y - 70
    end

    local NAME_CHOICES = {
        { key = "first", label = T("Nur Vorname", "First name only") },
        { key = "initial", label = T("Vorname + Initiale", "First name + initial") },
        { key = "full", label = T("Voller Name", "Full name") },
    }
    local function NameLabel(key)
        for _, c in ipairs(NAME_CHOICES) do if c.key == key then return c.label end end
        return key
    end
    local label = UI.Text(page, "field", T("Spielernamen", "Player names"))
    label:SetPoint("TOPLEFT", 0, y - 4)
    local names = UI.AddArrow(UI.Button(page, "", 200))
    names:SetPoint("TOPLEFT", 150, y)
    names:SetScript("OnClick", function(self)
        UI.ChoiceMenu(self, NAME_CHOICES, UI.NameStyle, function(key)
            S.GetDB().nameStyle = key ~= "initial" and key or nil
            self:SetText(NameLabel(UI.NameStyle()))
            UI.Fire("NameStyleChanged")
        end)
    end)
    loads[#loads + 1] = function() names:SetText(NameLabel(UI.NameStyle())) end
    local hint = UI.Hint(page, 150, y - 28, 380, T("Wie Namen auf Einheiten- und Gruppenrahmen, Namensplaketten und Würfen erscheinen.",
        "How names appear on unit and group frames, nameplates and loot rolls."))
    hint:SetWordWrap(true)
    function page.Load() for _, fn in ipairs(loads) do fn() end end
end

---------------------------------------------------------------------------
-- Schritt 2: Addons an/aus
---------------------------------------------------------------------------
local function BuildAddons(page)
    Title(page, T("Welche Addons möchtest du nutzen?", "Which addons do you want to use?"))
    Intro(page, T("Haken = an. Du kannst erst einmal alle anlassen und später einzelne im Hub ausschalten. Änderungen gelten nach dem Neuladen.",
        "Checked = on. You can keep them all on for now and turn single ones off in the hub later. Changes apply after reloading."))
    local checks = {}
    local list = S.Addons()
    local colW, rowH, top = math.floor((W - PAD * 2) / 2), 26, -74
    local perCol = math.ceil(#list / 2)
    for i, a in ipairs(list) do
        local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
        local cb = UI.Check(page, nil, nil, "", function(checked) S.SetEnabled(a.name, checked) end)
        cb:SetPoint("TOPLEFT", col * colW, top - row * rowH)
        local icon = page:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", cb, "RIGHT", 8, 0)
        icon:SetTexture(a.icon or UI.LOGO)
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetText(a.name)
        local ok, _, _, notes = pcall(C_AddOns.GetAddOnInfo, a.name)
        if ok and notes and notes ~= "" then Tip(cb, a.name, notes) end
        cb.addon = a.name
        checks[#checks + 1] = cb
    end
    local y = top - perCol * rowH - 10
    local function SetAll(on)
        for _, cb in ipairs(checks) do
            S.SetEnabled(cb.addon, on)
            cb:SetChecked(on)
        end
    end
    local allOn = UI.Button(page, T("Alle an", "All on"), 90, function() SetAll(true) end)
    allOn:SetPoint("TOPLEFT", 0, y)
    local allOff = UI.Button(page, T("Alle aus", "All off"), 90, function() SetAll(false) end)
    allOff:SetPoint("LEFT", allOn, "RIGHT", 6, 0)
    function page.Load()
        for _, cb in ipairs(checks) do cb:SetChecked(S.IsEnabled(cb.addon)) end
    end
end

---------------------------------------------------------------------------
-- Schritt 3: Allgemeines
---------------------------------------------------------------------------
local function BuildGeneral(page)
    Title(page, T("Allgemeines", "General"))
    Intro(page, T("Die wichtigsten Grundeinstellungen – alle gelten sofort.", "The most important basics – all apply right away."))
    local mm = UI.Check(page, 0, -70, T("Minimap-Knopf anzeigen", "Show minimap button"), function(checked)
        S.GetDB().hideButton = not checked or nil
        S.ApplyMode()
    end)
    UI.Hint(page, 28, -92, W - PAD * 2 - 28, T("Ein Knopf an der Minimap öffnet den Hub mit allen Forever-Addons. Ohne Knopf: /forever.",
        "A minimap button opens the hub with all Forever addons. Without it: /forever.")):SetWordWrap(true)
    local snap = UI.Check(page, 0, -126, T("Einrasten beim Verschieben", "Snap while moving"), function(checked)
        UI.SetSnapEnabled(checked)
    end)
    UI.Hint(page, 28, -148, W - PAD * 2 - 28, T("Verschobene Rahmen rasten an anderen Rahmen, der Bildschirmmitte und dem Raster ein (Umschalt beim Ziehen = kurz nicht).",
        "Moved frames snap to other frames, the screen center and the grid (hold Shift while dragging to skip)."))
        :SetWordWrap(true)
    local blizz = UI.Check(page, 0, -182, T("Blizzard-Fenster verschiebbar", "Movable Blizzard windows"), function(checked)
        if UI.SetBlizzMove then UI.SetBlizzMove(checked) end
    end)
    UI.Hint(page, 28, -204, W - PAD * 2 - 28, T("Charakter, Händler, Post, Berufe, Talente … an einer freien Stelle ziehen; die Lage wird gemerkt.",
        "Drag the character, vendor, mail, professions, talents … windows at a free spot; the position is remembered."))
        :SetWordWrap(true)
    UI.Hint(page, 0, -250, W - PAD * 2, T("Rahmen der Addons (Leisten, Einheitenrahmen …) verschiebst du später mit /fmove.",
        "Move the addons' frames (bars, unit frames …) later with /fmove.")):SetWordWrap(true)
    function page.Load()
        mm:SetChecked(not S.GetDB().hideButton)
        snap:SetChecked(UI.SnapEnabled())
        blizz:SetChecked(not UI.BlizzMoveEnabled or UI.BlizzMoveEnabled())
    end
end

---------------------------------------------------------------------------
-- Schritt 4: Fertig
---------------------------------------------------------------------------
local function BuildDone(page)
    Title(page, T("Fertig!", "All set!"))
    local text = Intro(page, "")
    local lines = UI.Hint(page, 0, -110, W - PAD * 2, T("Gut zu wissen:", "Good to know:") .. "\n\n"
        .. T("• /forever – Hub: Addons an/aus, alle Einstellungen\n• /fmove – Rahmen verschieben\n• /forever leistung – Rechenzeit und Speicher der Addons\n• /forever einrichtung – dieser Assistent",
            "• /forever – hub: addons on/off, all settings\n• /fmove – move frames\n• /forever performance – CPU time and memory of the addons\n• /forever setup – this assistant"))
    lines:SetWordWrap(true)
    lines:SetSpacing(3)
    lines:SetTextColor(0.85, 0.85, 0.85)
    function page.Load()
        text:SetText(AnyPending()
            and T("Einige Änderungen gelten erst nach dem Neuladen – klick unten auf „Neu laden“.",
                "Some changes only apply after reloading – click \"Reload\" below.")
            or T("Alles ist eingerichtet. Viel Spaß!", "Everything is set up. Have fun!"))
    end
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local function Show(n)
    step = math.max(1, math.min(STEPS, n))
    for i, page in ipairs(pages) do
        page:SetShown(i == step)
        if i == step and page.Load then page.Load() end
    end
    stepText:SetText(string.format(T("Schritt %d von %d", "Step %d of %d"), step, STEPS))
    back:SetShown(step > 1)
    if step < STEPS then
        nextBtn:SetText(T("Weiter", "Next"))
    else
        nextBtn:SetText(AnyPending() and T("Neu laden", "Reload") or T("Fertig", "Done"))
    end
end

local function Build()
    f = UI.Window("ForeverSetupWindow", T("Einrichtung", "Setup"), W, H)
    f:SetPoint("CENTER", 0, 40)
    pages = {}
    for i, builder in ipairs({ BuildWelcome, BuildAddons, BuildGeneral, BuildDone }) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", PAD, -46)
        page:SetPoint("BOTTOMRIGHT", -PAD, 56)
        builder(page)
        pages[i] = page
    end
    -- Fußzeile: feine Linie, Schritt-Anzeige, Zurück / Weiter
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", PAD, 46)
    line:SetPoint("BOTTOMRIGHT", -PAD, 46)
    line:SetHeight(1)
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.4)
    stepText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stepText:SetPoint("BOTTOMLEFT", PAD, 18)
    nextBtn = UI.Button(f, "", 110, function()
        if step < STEPS then
            Show(step + 1)
        elseif AnyPending() then
            ReloadUI()
        else
            f:Hide()
        end
    end)
    nextBtn:SetPoint("BOTTOMRIGHT", -PAD, 12)
    nextBtn:GetFontString():SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    back = UI.Button(f, T("Zurück", "Back"), 110, function() Show(step - 1) end)
    back:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
    -- Schließen (auch mittendrin): danach ggf. die Frage nach anderen Addons (ForeverHub.lua, MaybeWelcome)
    f:HookScript("OnHide", function()
        local fn = onDone
        onDone = nil
        if fn then C_Timer.After(0.2, fn) end
    end)
end

-- done: wird einmal aufgerufen, sobald der Assistent geschlossen wird
function UI.ShowSetup(done)
    if InCombatLockdown() then
        UI.Chat("Forever", T("Die Einrichtung geht nach dem Kampf.", "Setup is available after combat."))
        return
    end
    if not f then Build() end
    onDone = done
    langChanged = false
    f:Show()
    if UI.BringToFront then UI.BringToFront(f) end
    Show(1)
end
