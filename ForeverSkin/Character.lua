-- ForeverSkin – Character.lua: Charakterfenster (CharacterFrame: Ausrüstung, Ruf, Währungen) im Forever-Stil
-- (docs/Fenster-Stil.md). Auf Wunsch wie die Anprobe: OHNE Titelleiste und ohne "Dein Gold", dafür das kleine runde
-- Porträt mit goldenem Ring; Blizzards Hintergrundgrafiken (Bild hinter dem Modell, Hintergründe der Innenflächen)
-- bleiben, nur Rahmen, Titel-Grafik und Porträt-Ring weg. Dazu unsere Bausteine: Ausrüstungsplätze wie Taschenplätze,
-- flache Reiter, goldene Laufleisten, flache Häkchen/Auswahllisten/Text-Knöpfe. Die Einträge von Ruf und Währungen
-- bleiben Blizzards.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TITLE_UP = 10            -- Titelleiste so viel höher als Blizzards Fensterrand (siehe Raise)
local PORTRAIT_X, PORTRAIT_Y = 12, TITLE_UP - 12 -- Mitte des Porträts: auf der oberen linken Ecke (leicht innen)
-- goldener Rand der Ausrüstungsplätze (Dicke) und Luft zwischen Rand und Symbol – in der Luft zeigt sich die
-- Seltenheitsfarbe (Blizzards IconBorder wird genau dorthin gesetzt)
local SLOT_EDGE, SLOT_GAP = 1, 1

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "character/" .. what, err) end
end

-- kleines rundes Porträt oben links (wie bei der Anprobe), Ring gold
-- (auf eigenem Rahmen ÜBER den Hintergründen links/rechts – die sind eigene Rahmen und verdeckten sonst das Porträt)
local portrait
local function Portrait(f)
    if not portrait then
        portrait = {}
        local holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel(f:GetFrameLevel() + 110) -- (über dem Rand)
        holder:EnableMouse(false)
        portrait.holder = holder
        local function Disk(size, sub, c)
            local t = holder:CreateTexture(nil, "OVERLAY", nil, sub)
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:SetSize(size, size)
            -- (auf der oberen linken Ecke unserer Fläche, die TITLE_UP über Blizzards Rand reicht – ragt leicht hinaus)
            t:SetPoint("CENTER", f, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
            local mask = holder:CreateMaskTexture()
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

-- Rahmen: nur Blizzards Rahmen, Titel-Grafik, Streifen und Porträt weg – Hintergründe bleiben; flache Fläche darunter
local function HideFrameArt(f)
    for _, key in ipairs({ "NineSlice", "PortraitContainer", "TopTileStreaks", "TitleBg" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            if obj.GetRegions then ns.HideTextures(obj) end
        end
    end
    for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TitleBg" }) do ns.Hide(G("CharacterFrame" .. suffix)) end
    if f.TitleContainer then ns.HideTextures(f.TitleContainer) end
    -- Streifen hinter "Stufe …, Klasse" (TopBackgroundStrip der Seiten) und Steinstreifen hinter den 4 Reitern der
    -- rechten Spalte (laut /fskin grafik) – weg, auf Wunsch; die großen Hintergründe dahinter bleiben
    for _, page in ipairs({ "PaperDollFrame", "ReputationFrame", "TokenFrame" }) do
        local host = G(page) and G(page).TopBackgroundStripHost
        if type(host) == "table" and not Forbidden(host) then
            ns.Hide(host.TopBackgroundStrip)
            ns.HideTextures(host)
        end
    end
    ns.Hide(G("CharacterFrameRightPaneHostStoneBg"))
    -- Hintergrundbilder der beiden Seiten ("UI-Character-Info-General-BG" links, "…-Stat-BG" rechts): durch unsere
    -- flache Innenfläche ersetzt (auf Wunsch); das Bild hinter dem Modell gehört zur Modellansicht und bleibt
    for _, hostName in ipairs({ "CharacterFrameLeftPaneHost", "CharacterFrameRightPaneHost" }) do
        local host = G(hostName)
        if host and not Forbidden(host) then
            ns.HideTextures(host)
            ns.Flat(host, C.panel)
        end
    end
    -- Trennlinie zwischen linker und rechter Seite ("common-framedivider", samt Verzierung unten): gold
    local right = G("CharacterFrameRightPaneHost")
    if right and not Forbidden(right) then
        for _, child in ipairs({ right:GetChildren() }) do
            if not Forbidden(child) then
                for _, r in ipairs({ child:GetRegions() }) do
                    local atlas = r:IsObjectType("Texture") and r.GetAtlas and r:GetAtlas()
                    if type(atlas) == "string" and atlas:find("framedivider") then
                        r:SetDesaturated(true)
                        r:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
                    end
                end
            end
        end
    end
    -- Innenflächen: nur ihr Rahmen weg (ihr Hintergrund bleibt)
    for _, key in ipairs({ "Inset", "InsetRight", "InsetLeft" }) do
        local inset = f[key] or G("CharacterFrame" .. key)
        if type(inset) == "table" and inset.NineSlice and not Forbidden(inset) then ns.Hide(inset.NineSlice) end
    end
end

-- Ausrüstungsplatz wie ein Taschenplatz (ForeverBags): dunkler Platz, feiner Rand, beim Überfahren gold; Blizzards
-- Rahmen-Grafiken weg, Symbol eckig mit 1 px Rand, Seltenheitsrahmen (IconBorder) bleibt
local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs",
    "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local slotDone = setmetatable({}, { __mode = "k" })
local function SkinSlot(b)
    if not b or slotDone[b] or Forbidden(b) then return end
    slotDone[b] = true
    local name = b:GetName()
    local icon = b.icon or b.Icon or (name and G(name .. "IconTexture"))
    local keep = {}
    if icon then keep[icon] = true end
    if b.IconBorder then keep[b.IconBorder] = true end
    for _, key in ipairs({ "IconOverlay", "IconOverlay2", "Count", "searchOverlay", "ItemContextOverlay" }) do
        if type(b[key]) == "table" then keep[b[key]] = true end
    end
    ns.HideTextures(b, keep)
    ns.Hide(b.GetNormalTexture and b:GetNormalTexture())
    ns.Hide(name and G(name .. "Frame"))
    -- Blizzards Verzierung um den Platz ("UI-Character-Info-GearSlot" im Unter-Rahmen BorderFrame): weg – unser
    -- goldener Rand ersetzt sie (auf Wunsch)
    local deco = b.BorderFrame
    if type(deco) == "table" and deco.GetRegions and not Forbidden(deco) then ns.HideTextures(deco) end
    -- Symbol innerhalb von Rand + Luft
    local inset = SLOT_EDGE + SLOT_GAP
    if icon and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    -- Seltenheitsrahmen direkt innerhalb des goldenen Randes: füllt die Luft um das Symbol mit der Seltenheitsfarbe
    if b.IconBorder and b.IconBorder.ClearAllPoints then
        b.IconBorder:ClearAllPoints()
        b.IconBorder:SetPoint("TOPLEFT", SLOT_EDGE, -SLOT_EDGE)
        b.IconBorder:SetPoint("BOTTOMRIGHT", -SLOT_EDGE, SLOT_EDGE)
    end
    -- dunkle Fläche; der feine Rand von ns.Flat weg – stattdessen ein eigener goldener Rand SLOT_EDGE dick (auf Wunsch,
    -- ersetzt Blizzards Verzierung); dauerhaft gold, Blizzards Hervorhebung beim Überfahren bleibt
    local look = ns.Flat(b, { 0.06, 0.06, 0.08, 0.85 })
    if look then
        for _, e in ipairs(look.edges or {}) do e:SetAlpha(0) end
    end
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local e = b:CreateTexture(nil, "OVERLAY", nil, 6)
        -- (gedämpftes Gold – auf Wunsch weniger grell: dunkler und etwas durchscheinend)
        e:SetColorTexture(C.accent[1] * 0.7, C.accent[2] * 0.7, C.accent[3] * 0.7, 0.6)
        e:SetPoint(p[1], b, p[1])
        e:SetPoint(p[2], b, p[2])
        if p[3] then e:SetHeight(SLOT_EDGE) else e:SetWidth(SLOT_EDGE) end
    end
end

-- Reiter unten ("Charakter", "Ruf", "Währung"): flach, der gewählte gold (PanelTemplates sperren den gewählten)
local function TabSelected(tab)
    if type(tab.isSelected) == "boolean" then return tab.isSelected end
    return tab.IsEnabled and not tab:IsEnabled()
end

-- übrige Bedienelemente: Laufleisten gold, Häkchen/Auswahllisten flach, Text-Knöpfe flach – aber nur echte Knöpfe
-- (mit Blizzards Knopf-Teilen Left/Middle/Right), nicht die Einträge der Ruf-/Währungsliste
local done = setmetatable({}, { __mode = "k" })
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] and not slotDone[child] then
            local isDropdown = child:IsObjectType("DropdownButton")
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("CheckButton") and (child:GetWidth() or 0) <= 32 then
                done[child] = true
                ns.SkinCheck(child)
            elseif isDropdown then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                if type(text) == "string" and text ~= "" and type(child.Left) == "table" and type(child.Right) == "table" then
                    done[child] = true
                    ns.SkinButton(child)
                end
            elseif depth < 5 then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Titelleiste (Name + Schließen) TITLE_UP höher: unsere Fläche reicht oben so weit über Blizzards Fensterrand
-- hinaus, Name und Kreuz rücken mit – Blizzards Inhalt bleibt, wo er ist (wie beim Handelsfenster)
local raised = setmetatable({}, { __mode = "k" })
local function Raise(obj)
    if not obj or raised[obj] or not obj.GetNumPoints or obj:GetNumPoints() == 0 then return end
    raised[obj] = true
    local points = {}
    for i = 1, obj:GetNumPoints() do
        local p, rel, rp, x, y = obj:GetPoint(i)
        points[i] = { p, rel, rp, x or 0, (y or 0) + TITLE_UP }
    end
    obj:ClearAllPoints()
    for _, pt in ipairs(points) do obj:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

-- feine goldene Trennlinien: unter "Stufe …, Klasse" (Unterkante des früheren Streifens der Ausrüstungsseite) und
-- rechts unter den 4 Reitern (Unterkante des früheren Steinstreifens) – wie die Linie unter der Titelleiste
local function SubLines()
    local function Line(parent, anchor)
        -- (auf eigenem Unter-Rahmen: das Ausblenden der Grafiken von parent im Takt trifft ihn nicht)
        local holder = CreateFrame("Frame", nil, parent)
        holder:SetAllPoints(parent)
        holder:EnableMouse(false)
        local line = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
        line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    end
    local paper = G("PaperDollFrame")
    local host = paper and paper.TopBackgroundStripHost
    if type(host) == "table" and not Forbidden(host) then Line(host, host.TopBackgroundStrip or host) end
    local right, stone = G("CharacterFrameRightPaneHost"), G("CharacterFrameRightPaneHostStoneBg")
    if right and stone and not Forbidden(right) then Line(right, stone) end
end

local function SkinCharacter()
    local f = G("CharacterFrame")
    if not f or ns.characterSkinned or Forbidden(f) then return end
    ns.characterSkinned = true
    Step("frame", function()
        HideFrameArt(f)
        ns.Flat(f, C.background, { 0, -TITLE_UP, 0, 0 })
        -- feiner Rand ums ganze Fenster auf eigenem Rahmen ÜBER den Hintergründen links/rechts (die verdeckten ihn),
        -- unter dem Porträt; ohne Füllung, ohne Maus
        local border = CreateFrame("Frame", nil, f)
        border:SetAllPoints(f)
        border:SetFrameLevel(f:GetFrameLevel() + 100) -- (der linke Hintergrund liegt hoch und verdeckte den Rand)
        border:EnableMouse(false)
        ns.Flat(border, { 0, 0, 0, 0 }, { 0, -TITLE_UP, 0, 0 })
        -- goldene Trennlinie unter der Titelleiste: an der Oberkante der Hintergründe (linke Seite), sonst 23 unter
        -- Blizzards Rand
        local line = border:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        line:SetHeight(1)
        local function PlaceLine()
            local pane = G("CharacterFrameLeftPaneHost")
            local y = -23
            if pane and pane:GetTop() and f:GetTop() then y = math.floor(pane:GetTop() - f:GetTop() + 0.5) end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, y)
            line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, y)
        end
        PlaceLine()
        f:HookScript("OnShow", function() C_Timer.After(0, PlaceLine) end)
        f:HookScript("OnSizeChanged", function() C_Timer.After(0, PlaceLine) end)
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or G("CharacterFrameTitleText")
        if title then title:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
        Raise(f.TitleContainer or title)
        local close = f.CloseButton or G("CharacterFrameCloseButton")
        ns.SkinClose(close)
        Raise(close)
    end)
    Step("portrait", function() Portrait(f) end)
    Step("lines", SubLines)
    Step("slots", function()
        for _, s in ipairs(SLOTS) do SkinSlot(G("Character" .. s .. "Slot")) end
    end)
    Step("tabs", function()
        for i = 1, 6 do
            local tab = G("CharacterFrameTab" .. i)
            if tab and not Forbidden(tab) then ns.SkinTab(tab, TabSelected) end
        end
    end)
    Step("scan", function() Scan(f, 1) end)
    ns.Watch(f)
    f:HookScript("OnShow", function() Step("portrait", function() Portrait(f) end) end)
    -- Blizzard blendet Rahmen beim Öffnen/Umschalten wieder ein und baut Seiten erst beim ersten Zeigen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        pcall(HideFrameArt, f)
        pcall(Scan, f, 1)
        for i = 1, 6 do
            local tab = G("CharacterFrameTab" .. i)
            if tab and tab:IsShown() then pcall(ns.CenterText, tab) end
        end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.characterSkinned or not ns.GetDB().character or not G("CharacterFrame") then return end
    Step("skin", SkinCharacter)
end)
