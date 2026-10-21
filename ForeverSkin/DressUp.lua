-- ForeverSkin – DressUp.lua: Anprobe-Fenster im Forever-Stil (nach docs/Fenster-Stil.md, auf Wunsch OHNE Titelleiste).
--  * flache dunkle Fläche mit feinem Rand, oben nur der Titel "Anprobe" in Gold, Schließen-Kreuz flach
--  * kleines rundes Porträt mit goldenem Ring oben links (wo Blizzard sein Porträt hat)
--  * alles Bedienbare bleibt: Set-Auswahl, Speichern, Details-Knopf, Modell (samt Hintergrundbild), Liste rechts,
--    Knöpfe unten – nur flach gestaltet; unten eine feine goldene Linie über den Knöpfen
-- Wie überall: Blizzards Grafiken nur unsichtbar, eigene darunter, nichts in Blizzards Tabellen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FOOTER = 28

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "dressup/" .. what, err) end
end

-- Text-Knöpfe flach, mit eigenem Kasten dahinter (Blizzard setzt seine roten Grafiken teils neu)
local buttons = {}
local function SkinTextButton(b)
    if not b or Forbidden(b) or buttons[b] then return end
    ns.SkinButton(b)
    local box = CreateFrame("Frame", nil, b:GetParent())
    box:SetAllPoints(b)
    box:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    ns.Flat(box, C.button)
    buttons[b] = box
end
local function KeepButtonsFlat()
    for b, box in pairs(buttons) do
        ns.HideTextures(b)
        for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(b[key]) end
        box:SetShown(b:IsShown())
        local over = b:IsMouseOver() and b:IsEnabled()
        if box.over ~= over then
            box.over = over
            ns.EdgeColor(box, over and C.accent or C.border, 1)
        end
    end
end

-- kleines rundes Porträt (wie Blizzards), Ring gold
local portrait
local function Portrait(f)
    if not portrait then
        portrait = {}
        local function Disk(size, sub, c)
            local t = f:CreateTexture(nil, "OVERLAY", nil, sub)
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:SetSize(size, size)
            t:SetPoint("CENTER", f, "TOPLEFT", 20, -20)
            local mask = f:CreateMaskTexture()
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(t)
            t:AddMaskTexture(mask)
            return t
        end
        portrait.ring = Disk(52, 1, C.accent)
        portrait.gap = Disk(49, 2, C.background)
        portrait.image = Disk(47, 3, { 1, 1, 1 })
    end
    if SetPortraitTexture then SetPortraitTexture(portrait.image, "player") end
end

local function SkinDressUp()
    local f = G("DressUpFrame")
    if not f or ns.dressUpSkinned or Forbidden(f) then return end
    ns.dressUpSkinned = true
    -- Rahmen: Blizzards Rahmen, Hintergrund, Titel-Grafik und Porträt weg; flache Fläche mit feinem Rand
    Step("frame", function()
        -- (das Hintergrundbild hinter dem Modell gehört zum Fenster und bleibt)
        local keep = {}
        for _, t in ipairs({ f.ModelBackground or false, G("DressUpBackgroundTopLeft") or false,
            G("DressUpBackgroundTopRight") or false, G("DressUpBackgroundBotLeft") or false,
            G("DressUpBackgroundBotRight") or false }) do
            if t then keep[t] = true end
        end
        ns.HideTextures(f, keep)
        for _, key in ipairs({ "NineSlice", "Bg", "Background", "TopTileStreaks", "TitleBg", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TitleBg", "Bg" }) do ns.Hide(G("DressUpFrame" .. suffix)) end
        if f.TitleContainer then ns.HideTextures(f.TitleContainer) end
        ns.Flat(f, C.background)
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or G("DressUpFrameTitleText")
        if title then title:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
        ns.SkinClose(f.CloseButton or G("DressUpFrameCloseButton"))
        -- Innenfläche um das Modell: nur Blizzards Rahmen weg (das Hintergrundbild des Modells bleibt)
        local inset = f.Inset or G("DressUpFrameInset")
        if inset and not Forbidden(inset) and inset.NineSlice then ns.Hide(inset.NineSlice) end
    end)
    Step("portrait", function() Portrait(f) end)
    -- untere Leiste: feine goldene Linie über den Knöpfen (wie in den übrigen Fenstern)
    Step("footer", function() ns.ContentBox(f, FOOTER, nil, true) end)
    -- oben: Set-Auswahl, Speichern, Details-Knopf
    Step("top", function()
        local dropdown = f.OutfitDropdown or f.OutfitDropDown or G("DressUpFrameOutfitDropdown")
        if dropdown and not Forbidden(dropdown) then ns.SkinDropdown(dropdown) end
        SkinTextButton(dropdown and (dropdown.SaveButton or G("DressUpFrameOutfitDropdownSaveButton")) or f.SaveButton)
        SkinTextButton(f.SaveButton)
        for _, key in ipairs({ "ToggleOutfitDetailsButton", "MaximizeMinimizeFrame" }) do
            local b = f[key]
            if type(b) == "table" and not Forbidden(b) and b.IsObjectType and b:IsObjectType("Button") then
                ns.SkinIconButton(b)
            end
        end
    end)
    -- unten: Set verlinken, Zurücksetzen, Schließen
    Step("bottom", function()
        for _, b in ipairs({ f.LinkButton or false, f.ResetButton or G("DressUpFrameResetButton") or false,
            f.CancelButton or G("DressUpFrameCancelButton") or false }) do
            if b then SkinTextButton(b) end
        end
    end)
    -- rechts: Liste der Teile – Rahmen und Verzierung weg, flache Fläche (Einträge mit Symbolen bleiben)
    Step("details", function()
        local panel = f.OutfitDetailsPanel
        if panel and not Forbidden(panel) then
            ns.HideTextures(panel)
            if panel.NineSlice then ns.Hide(panel.NineSlice) end
            for _, key in ipairs({ "BorderFrame", "Border", "TopBorder", "Background" }) do
                local obj = panel[key]
                if type(obj) == "table" and obj.SetAlpha then
                    if obj.GetRegions then ns.HideTextures(obj) else obj:SetAlpha(0) end
                end
            end
            ns.Flat(panel, C.background)
            if panel.ScrollBar then ns.SkinScrollBar(panel.ScrollBar) end
        end
    end)
    ns.Watch(f)
    f:HookScript("OnShow", function() Step("portrait", function() Portrait(f) end) end)
    -- solange offen: Blizzards Knopf-Grafiken unsichtbar halten, aufgeklappte Auswahlliste flach
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function()
        pcall(KeepButtonsFlat)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().dressup or not G("DressUpFrame") or ns.dressUpSkinned then return end
    Step("skin", SkinDressUp)
end)
