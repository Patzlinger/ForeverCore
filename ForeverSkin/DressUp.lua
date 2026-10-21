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
local FOOTER = 36
local LINE_UP = 20 -- so weit über Blizzards altem Fensterrand liegt die goldene Linie (2–3 px unter dem Modellbild)
local GROW = FOOTER - LINE_UP -- so weit wächst das Fenster nach unten

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

-- Fläche des Fensters samt Leiste unten (Blizzards alter Rand + GROW). Blizzard baut das Fenster beim Auf-/Zuklappen
-- der Liste um – darum bei jedem Öffnen, Aufklappen und jeder Größenänderung neu setzen und sichtbar halten.
local back
local function ApplyBack(f)
    local look = ns.Flat(f, C.background, { 0, 0, 0, -GROW })
    if not look then return end
    if not back then
        back = {}
        back.foot = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        back.foot:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
        back.line = f:CreateTexture(nil, "BORDER", nil, -6)
        back.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
        back.line:SetHeight(1)
        -- die neue Fläche fängt die Maus ab (sonst klickt man ins Spiel durch)
        back.grip = CreateFrame("Frame", nil, f)
        back.grip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
        back.grip:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
        back.grip:SetHeight(GROW)
        back.grip:EnableMouse(true)
    end
    back.foot:ClearAllPoints()
    back.foot:SetPoint("BOTTOMLEFT", look.fill, "BOTTOMLEFT", 1, 1)
    back.foot:SetPoint("BOTTOMRIGHT", look.fill, "BOTTOMRIGHT", -1, 1)
    back.foot:SetHeight(FOOTER - 1)
    back.line:ClearAllPoints()
    back.line:SetPoint("BOTTOMLEFT", back.foot, "TOPLEFT")
    back.line:SetPoint("BOTTOMRIGHT", back.foot, "TOPRIGHT")
    for _, t in ipairs({ look.fill, back.foot, back.line }) do
        t:SetAlpha(1)
        t:Show()
    end
    for _, e in ipairs(look.edges or {}) do
        e:SetAlpha(1)
        e:Show()
    end
end

-- alle Text-Knöpfe und Auswahlfelder im Fenster finden (unabhängig von Blizzards Namen)
local function FindControls(frame, depth, found)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            local isDropdown = (child.IsObjectType and child:IsObjectType("DropdownButton"))
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if isDropdown then
                found.dropdowns[#found.dropdowns + 1] = child
                -- (im Auswahlfeld kann ein Knopf stecken, z. B. "Speichern")
                if depth < 3 then FindControls(child, depth + 1, found) end
            elseif child:IsObjectType("Button") then
                local label = child.GetText and child:GetText()
                if type(label) == "string" and label ~= "" then found.buttons[#found.buttons + 1] = child end
            elseif depth < 3 then
                FindControls(child, depth + 1, found)
            end
        end
    end
    return found
end

-- Liste der Teile rechts: Blizzards verzierter Rahmen weg, flache Fläche – die Einträge (in der Laufliste) bleiben
local function SkinDetailsPanel(panel)
    if not panel or Forbidden(panel) then return end
    -- Rahmen-Teile mehrere Ebenen tief (die Verzierung oben liegt verschachtelt) – nicht in der Liste selbst und
    -- nicht in Knöpfen (dort sind die Symbole der Teile)
    local function Strip(frame, depth)
        ns.HideTextures(frame)
        if frame.NineSlice then ns.Hide(frame.NineSlice) end
        if depth >= 4 then return end
        for _, child in ipairs({ frame:GetChildren() }) do
            local isList = child.ScrollTarget or child.ForEachFrame or child:IsObjectType("ScrollFrame")
            if not Forbidden(child) and not isList and not child:IsObjectType("Button") then Strip(child, depth + 1) end
        end
    end
    Strip(panel, 1)
    -- (keine eigene Fläche auf der Liste selbst – die liegt als eigener Rahmen dahinter, siehe PlacePanel; sonst
    -- überdeckte sie dessen Durchsichtigkeit)
    if panel.ScrollBar then ns.SkinScrollBar(panel.ScrollBar) end
end

-- Liste rechts: immer 4 rechts neben dem Hauptfenster (Blizzard ließ sie für seinen Zier-Rahmen über den Rand ragen
-- und hängt sie beim Aufklappen neu an), Oberkante wie bei Blizzard; dazu eine eigene deckende Fläche als Rahmen
-- direkt dahinter (unabhängig davon, was Blizzard in der Liste zeichnet)
local panelTop = setmetatable({}, { __mode = "k" })  -- [Liste] = Abstand der Oberkante zur Oberkante des Fensters
local panelBack = setmetatable({}, { __mode = "k" }) -- [Liste] = eigene Fläche dahinter
local function PlacePanel(f, panel)
    if not panel or Forbidden(panel) or not panel:IsShown() then return end
    if not panelTop[panel] and panel:GetTop() and f:GetTop() then panelTop[panel] = panel:GetTop() - f:GetTop() end
    local y = panelTop[panel] or 0
    local p, rel, rp, x, oy = panel:GetPoint(1)
    if not (panel:GetNumPoints() == 1 and p == "TOPLEFT" and rel == f and rp == "TOPRIGHT"
        and math.abs((x or 0) - 4) < 0.5 and math.abs((oy or 0) - y) < 0.5) then
        -- (Größe behalten: hing die Liste mit zwei Ecken, hätte sie sonst keine eigene Größe mehr)
        local w, h = panel:GetWidth(), panel:GetHeight()
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, y)
        if w and h and w > 0 and h > 0 then panel:SetSize(w, h) end
    end
    local b = panelBack[panel]
    if not b then
        b = CreateFrame("Frame", nil, f)
        b:SetAllPoints(panel)
        b:SetFrameStrata(panel:GetFrameStrata())
        b:SetFrameLevel(math.max(0, panel:GetFrameLevel() - 1))
        -- 20 % durchsichtig, Rand 3 px statt 1 (auf Wunsch)
        local look = ns.Flat(b, { C.background[1], C.background[2], C.background[3], 0.8 })
        for i, e in ipairs(look and look.edges or {}) do
            local horizontal = i <= 2 -- (oben, unten; 3 und 4 sind links, rechts)
            if PixelUtil and PixelUtil.SetHeight then
                if horizontal then PixelUtil.SetHeight(e, 3, 3) else PixelUtil.SetWidth(e, 3, 3) end
            elseif horizontal then
                e:SetHeight(3)
            else
                e:SetWidth(3)
            end
        end
        panelBack[panel] = b
        panel:HookScript("OnShow", function() b:Show() end)
        panel:HookScript("OnHide", function() b:Hide() end)
    end
    b:SetShown(panel:IsShown())
end
-- die Liste ist ein namenloser Unterrahmen der Anprobe (laut /fskin maus 312 × 473), rechts vom Modell. Darum außer
-- Blizzards bekanntem Namen jeden großen Unterrahmen, der weit rechts liegt (nicht Modell/Innenfläche/Knöpfe)
local function SkinDetails(f)
    SkinDetailsPanel(f.OutfitDetailsPanel)
    if f.OutfitDetailsPanel then PlacePanel(f, f.OutfitDetailsPanel) end
    local inset = f.Inset or G("DressUpFrameInset")
    local fl, fw = f:GetLeft(), f:GetWidth()
    for _, child in ipairs({ f:GetChildren() }) do
        if not Forbidden(child) and child ~= inset and child ~= f.ModelScene and not child:IsObjectType("Button") then
            local left, w, h = child:GetLeft(), child:GetWidth() or 0, child:GetHeight() or 0
            if left and fl and fw and left > fl + fw * 0.7 and w > 150 and h > 250 then
                SkinDetailsPanel(child)
                PlacePanel(f, child)
            end
        end
    end
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
        -- (flache Fläche samt der Leiste darunter: siehe "footer")
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or G("DressUpFrameTitleText")
        if title then title:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
        ns.SkinClose(f.CloseButton or G("DressUpFrameCloseButton"))
        -- Innenfläche um das Modell: nur Blizzards Rahmen weg (das Hintergrundbild des Modells bleibt)
        local inset = f.Inset or G("DressUpFrameInset")
        if inset and not Forbidden(inset) and inset.NineSlice then ns.Hide(inset.NineSlice) end
    end)
    Step("portrait", function() Portrait(f) end)
    -- untere Leiste UNTER Blizzards altem Fensterrand: das Fenster wächst optisch um FOOTER nach unten, die feine
    -- goldene Linie liegt genau am alten Rand – so endet das Hintergrundbild des Modells darüber
    Step("footer", function() ApplyBack(f) end)
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
    -- unten: Set verlinken, Zurücksetzen, Schließen – flach, mittig in der Leiste, 10 vom Rand, 8 auseinander;
    -- die Innenfläche (Modell) endet darüber
    Step("bottom", function()
        local link = f.LinkButton
        local reset = f.ResetButton or G("DressUpFrameResetButton")
        local cancel = f.CancelButton or G("DressUpFrameCancelButton")
        for _, b in ipairs({ link or false, reset or false, cancel or false }) do
            if b then SkinTextButton(b) end
        end
        -- (die Leiste reicht von −GROW bis LINE_UP über Blizzards altem Fensterrand, siehe "footer": Knöpfe mittig darin)
        local y = -GROW + FOOTER / 2
        local function Put(b, point, rel, relPoint, x, yy)
            if not b or Forbidden(b) then return end
            b:ClearAllPoints()
            b:SetPoint(point, rel, relPoint, x, yy)
        end
        Put(link, "LEFT", f, "BOTTOMLEFT", 10, y)
        Put(cancel, "RIGHT", f, "BOTTOMRIGHT", -10, y)
        if cancel then Put(reset, "RIGHT", cancel, "LEFT", -8, 0) end
    end)
    -- alle übrigen Text-Knöpfe und Auswahlfelder (Blizzard benennt sie je nach Fassung anders)
    Step("controls", function()
        local found = FindControls(f, 1, { buttons = {}, dropdowns = {} })
        for _, b in ipairs(found.buttons) do SkinTextButton(b) end
        for _, d in ipairs(found.dropdowns) do ns.SkinDropdown(d) end
    end)
    -- rechts: Liste der Teile – Rahmen und Verzierung weg, flache Fläche (Einträge mit Symbolen bleiben)
    Step("details", function() SkinDetails(f) end)
    ns.Watch(f)
    f:HookScript("OnSizeChanged", function() C_Timer.After(0, function() Step("footer", function() ApplyBack(f) end) end) end)
    f:HookScript("OnShow", function()
        Step("portrait", function() Portrait(f) end)
        C_Timer.After(0, function() Step("footer", function() ApplyBack(f) end) end)
        -- (die Liste rechts entsteht teils erst beim ersten Aufklappen)
        C_Timer.After(0, function() Step("details", function() SkinDetails(f) end) end)
    end)
    local details = f.ToggleOutfitDetailsButton
    if type(details) == "table" and details.HookScript and not Forbidden(details) then
        details:HookScript("OnClick", function()
            C_Timer.After(0, function()
                Step("details", function() SkinDetails(f) end)
                Step("footer", function() ApplyBack(f) end)
            end)
        end)
    end
    -- solange offen: Blizzards Knopf-Grafiken unsichtbar halten, aufgeklappte Auswahlliste flach
    -- und alle 0,3 s die Liste rechts prüfen (Lage, Fläche – Blizzard hängt sie beim Aufklappen neu an)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        pcall(KeepButtonsFlat)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
        waited = waited + elapsed
        if waited >= 0.3 then
            waited = 0
            pcall(SkinDetails, f)
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().dressup or not G("DressUpFrame") or ns.dressUpSkinned then return end
    Step("skin", SkinDressUp)
end)
