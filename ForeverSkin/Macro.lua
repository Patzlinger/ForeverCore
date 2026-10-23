-- ForeverSkin – Macro.lua: Makro-Fenster und Symbol-Auswahl im Forever-Stil.
-- Blizzard lädt das Fenster erst beim ersten Öffnen (Blizzard_MacroUI) – darum beim Laden dieses Addons umgestalten.
--  * Fenster flach mit Titelleiste, Reiter "Allgemein/Charakterspezifisch" flach (gewählter gold)
--  * Makro-Plätze als flache dunkle Felder mit Symbol (Überfahren/gewählt: goldener Rand)
--  * gewähltes Makro (großes Symbol, Name), Textfeld als flache Eingabefläche, goldene Laufleisten, flache Knöpfe
--  * Symbol-Auswahl (beim Erstellen/Ändern) ebenso
-- Wie überall: Blizzards Grafiken nur unsichtbar, eigene darunter, nichts in Blizzards Tabellen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local slots = setmetatable({}, { __mode = "k" })

-- Platz mit Symbol (Makro, Symbol-Auswahl): nur Blizzards Fach-Grafiken weg (NICHT alle Grafiken – sonst verschwand
-- das Symbol, das hier nicht unter einem festen Namen liegt), flaches Feld etwas größer als der Knopf (Blizzards
-- Raster hat große Lücken), Knopf-Farbe; gewählt (angehakt) bzw. Überfahren = goldener Rand
local SLOT_PARTS = { "SlotBackground", "Background", "Border", "SelectedTexture", "BackgroundTexture" }
local function SkinSlot(button)
    if not button or slots[button] then return end
    slots[button] = true
    local name = button.GetName and button:GetName()
    for _, key in ipairs(SLOT_PARTS) do
        local t = button[key]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
    end
    if name then
        for _, suffix in ipairs({ "SlotBackground", "Background" }) do ns.Hide(G(name .. suffix)) end
    end
    -- die "normale" Grafik des Knopfs ist hier oft das SYMBOL – sie bleibt; nur gedrückt/hell/angehakt weg
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    for _, get in ipairs({ "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    -- Fach-Grafiken: Hintergrund-Ebene (das graue Fach-Muster) und alles, was als Datei/Atlas "Slot" heißt
    for _, r in ipairs({ button:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= normal and not ns.IsMine(button, r) then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r.GetTexture and r:GetTexture()
            local s = ((type(atlas) == "string" and atlas or "") .. (type(tex) == "string" and tex or "")):lower()
            if r:GetDrawLayer() == "BACKGROUND" or s:find("slot") then r:SetAlpha(0) end
        end
    end
    ns.Flat(button, C.button, -1) -- (nur 1 px größer als der Knopf: Luft zwischen den Feldern)
    ns.Hover(button, function(b) return b.GetChecked and b:GetChecked() end)
end

local function SkinGrid(selector)
    local box = selector and selector.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(SkinSlot) end
end

-- Symbol-Auswahl (MacroPopupFrame, IconSelectorPopupFrameTemplate)
local function SkinPopup(popup)
    if not popup or slots[popup] then return end
    slots[popup] = true
    local border = popup.BorderBox
    ns.HideTextures(popup)
    if border then
        ns.HideTextures(border)
        for _, child in ipairs({ border:GetChildren() }) do
            if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
        end
        ns.SkinButton(border.OkayButton)
        ns.SkinButton(border.CancelButton)
        -- Flächen 2 px kleiner als Blizzards Knöpfe: etwas Luft zwischen den Knöpfen und zum Rand
        -- volle Knopfgröße (Beschriftung passt), stattdessen OK mit 10 px Abstand links neben Abbrechen
        if border.OkayButton and border.CancelButton then
            border.OkayButton:ClearAllPoints()
            border.OkayButton:SetPoint("RIGHT", border.CancelButton, "LEFT", -10, 0)
        end
        local edit = border.IconSelectorEditBox
        if edit then
            ns.HideTextures(edit)
            ns.Flat(edit, C.input, { -4, 2, 0, 2 })
        end
        if border.IconTypeDropdown then ns.SkinDropdown(border.IconTypeDropdown) end
        if border.SelectedIconArea and border.SelectedIconArea.SelectedIconButton then
            SkinSlot(border.SelectedIconArea.SelectedIconButton)
        end
    end
    if popup.NineSlice then ns.Hide(popup.NineSlice) end
    ns.Flat(popup, C.background)
    if popup.IconSelector and popup.IconSelector.ScrollBar then ns.SkinScrollBar(popup.IconSelector.ScrollBar) end
    ns.Watch(popup)
    ns.Scaled(popup, 0.85) -- kleiner als die übrigen Fenster (die Symbol-Auswahl ist sehr groß)
    local watch = CreateFrame("Frame", nil, popup)
    watch:SetScript("OnUpdate", function()
        pcall(SkinGrid, popup.IconSelector)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end -- aufgeklappte Auswahlliste ("Alle Symbole")
    end)
end
-- für andere Symbol-Auswahlen derselben Vorlage (z. B. Ausrüstungssets im Charakterfenster: GearManagerPopupFrame)
ns.SkinIconPopup = SkinPopup

local function SkinMacro()
    local f = G("MacroFrame")
    if not f or ns.macroSkinned then return end
    ns.macroSkinned = true
    ns.SkinWindow(f)
    -- Reiter oben (Allgemein / Charakterspezifisch)
    for i = 1, 2 do
        local tab = G("MacroFrameTab" .. i)
        if tab then
            ns.SkinTab(tab, function(t)
                return (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) == t:GetID())
                    or (t.IsEnabled and not t:IsEnabled())
            end)
            ns.Refit(tab, { 0, math.max(0, (tab:GetHeight() or 30) - 24), 0, 6 }) -- (volle Breite, 6 px Luft zum Kasten darunter)
        end
    end
    -- gewähltes Makro: Hintergrund weg, großes Symbol als Platz, Name hell
    ns.Hide(G("MacroFrameSelectedMacroBackground"))
    SkinSlot(G("MacroFrameSelectedMacroButton"))
    -- Textfeld: flache dunkle Eingabefläche (Blizzards Rahmen weg)
    local textBg = G("MacroFrameTextBackground")
    if textBg then
        if textBg.NineSlice then ns.Hide(textBg.NineSlice) end
        ns.HideTextures(textBg)
        ns.Flat(textBg, C.input, { 4, 4, 4, 8 }) -- (Luft zum Rand, zur Schrift darüber und zu den Knöpfen darunter)
    end
    for _, n in ipairs({ "MacroFrameScrollFrame", "MacroButtonScrollFrame" }) do
        local s = G(n)
        local bar = s and (s.ScrollBar or G(n .. "ScrollBar"))
        if bar then ns.SkinScrollBar(bar) end
    end
    local selector = f.MacroSelector
    if selector and selector.ScrollBar then ns.SkinScrollBar(selector.ScrollBar) end
    if selector then
        ns.HideTextures(selector)
        if selector.NineSlice then ns.Hide(selector.NineSlice) end
    end
    for _, n in ipairs({ "MacroEditButton", "MacroDeleteButton", "MacroNewButton", "MacroExitButton", "MacroSaveButton",
        "MacroCancelButton" }) do
        ns.SkinButton(G(n))
        ns.Refit(G(n), { 0, 6, 0, 0 }) -- (volle Breite, damit die Beschriftung passt; oben Luft zum Textfeld)
    end
    -- Classic: feste Plätze
    for i = 1, 36 do
        local b = G("MacroButton" .. i)
        if not b then break end
        SkinSlot(b)
    end
    -- Abstände durch Verschieben statt durch kleinere Flächen (sonst passte die Beschriftung nicht mehr):
    -- zweiter Reiter 10 px neben dem ersten; unten Löschen links, Verlassen rechts (je 10 px vom Rand), Neu 10 px daneben
    local tab1, tab2 = G("MacroFrameTab1"), G("MacroFrameTab2")
    if tab1 and tab2 then
        tab2:ClearAllPoints()
        tab2:SetPoint("LEFT", tab1, "RIGHT", 10, 0)
    end
    local del, new, exit = G("MacroDeleteButton"), G("MacroNewButton"), G("MacroExitButton")
    if exit then
        exit:ClearAllPoints()
        exit:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 6)
    end
    if new and exit then
        new:ClearAllPoints()
        new:SetPoint("RIGHT", exit, "LEFT", -10, 0)
    end
    if del then
        del:ClearAllPoints()
        del:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 6)
    end
    ns.Watch(f)
    ns.Scaled(f, 1.05) -- als Ganzes größer wie Gespräch, Händler, Lehrer (Regler "Größe"), und 5 % mehr
    -- Plätze baut Blizzard beim Blättern/Reiter-Wechsel neu: solange offen, sichtbare Plätze prüfen; Text der Reiter
    -- mittig; die Symbol-Auswahl gestalten, sobald es sie gibt
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function()
        pcall(SkinGrid, selector)
        for i = 1, 2 do
            local tab = G("MacroFrameTab" .. i)
            if tab then pcall(ns.CenterText, tab) end
        end
        -- Beschriftung mittig in die (oben gekürzte) Fläche der Knöpfe
        for _, n in ipairs({ "MacroEditButton", "MacroDeleteButton", "MacroNewButton", "MacroExitButton", "MacroSaveButton",
            "MacroCancelButton" }) do
            local b = G(n)
            if b then pcall(ns.CenterText, b) end
        end
        local popup = G("MacroPopupFrame")
        if popup then pcall(SkinPopup, popup) end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end -- aufgeklappte Auswahllisten flach
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Blizzard_MacroUI" then return end
    if not ns.GetDB().macro or not G("MacroFrame") then return end
    local ok, err = pcall(SkinMacro)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "macro", err) end
end)
