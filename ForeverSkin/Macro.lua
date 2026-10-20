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

-- Platz mit Symbol (Makro, Symbol-Auswahl): Fach weg, dunkles Feld, Symbol bleibt; gewählt (angehakt) = gold
local function SkinSlot(button)
    if not button or slots[button] then return end
    slots[button] = true
    local name = button.GetName and button:GetName()
    local icon = button.Icon or button.icon or (name and G(name .. "Icon"))
    local keep = {}
    if type(icon) == "table" and icon.IsObjectType and icon:IsObjectType("Texture") then keep[icon] = true end
    ns.HideTextures(button, keep)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    ns.Flat(button, { 0.04, 0.04, 0.05, 1 })
    if type(icon) == "table" and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
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
    local watch = CreateFrame("Frame", nil, popup)
    watch:SetScript("OnUpdate", function() pcall(SkinGrid, popup.IconSelector) end)
end

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
            ns.Refit(tab, { 0, math.max(0, (tab:GetHeight() or 30) - 24), 0, 2 })
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
        ns.Flat(textBg, C.input)
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
    end
    -- Classic: feste Plätze
    for i = 1, 36 do
        local b = G("MacroButton" .. i)
        if not b then break end
        SkinSlot(b)
    end
    ns.Watch(f)
    -- Plätze baut Blizzard beim Blättern/Reiter-Wechsel neu: solange offen, sichtbare Plätze prüfen; Text der Reiter
    -- mittig; die Symbol-Auswahl gestalten, sobald es sie gibt
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function()
        pcall(SkinGrid, selector)
        for i = 1, 2 do
            local tab = G("MacroFrameTab" .. i)
            if tab then pcall(ns.CenterText, tab) end
        end
        local popup = G("MacroPopupFrame")
        if popup then pcall(SkinPopup, popup) end
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
