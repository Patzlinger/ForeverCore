-- ForeverSkin – Talents.lua: Talentfenster (im Forever-Client "PlayerSpellsFrame") – erst einmal nur Rahmen und die
-- Reiter "Primär"/"Sekundär" im Forever-Stil (docs/Fenster-Stil.md). Der Inhalt (Talentbäume samt Hintergrund) bleibt
-- unangetastet: der Rahmen wird darum nur "leicht" umgestaltet (Blizzards Rahmen, Titel-Hintergrund und Porträt weg,
-- unsere Titelleiste mit goldener Linie dazu). Die Reiter stecken namenlos tief im Fenster – sie werden über ihre
-- Beschriftung gefunden. Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "talents/" .. what, err) end
end

-- Reiter "Primär"/"Sekundär" (Primary/Secondary) über die Beschriftung finden
local tabs = setmetatable({}, { __mode = "k" })
local function IsSpecTabText(text)
    if type(text) ~= "string" then return false end
    local s = text:lower()
    return s:find("prim") or s:find("sekund") or s:find("second")
end

-- gewählt = wirklich ausgewählter Reiter (nicht "gesperrt": Sekundär ist ohne zweite Talentverteilung deaktiviert)
local function Selected(b)
    if type(b.isSelected) == "boolean" then return b.isSelected end
    if b.IsSelected then
        local ok, sel = pcall(b.IsSelected, b)
        if ok and type(sel) == "boolean" then return sel end
    end
    if b.GetChecked then return b:GetChecked() and true or false end
    return b.selected == true
end

-- Auswahlliste (der kleine Pfeil-Knopf neben der Suche): flach mit feinem Pfeil – bei schmalen Knöpfen ohne Text der
-- Pfeil mittig. Das aufgeklappte Menü macht ns.SkinOpenMenu flach (im Takt unten)
local dropdowns = setmetatable({}, { __mode = "k" })
local function FindDropdowns(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            -- (beim Betrachten anderer Spieler ein kleiner Pfeil-Knopf ohne Text: am Menü-Aufbau erkennen)
            local isDropdown = (child.IsObjectType and child:IsObjectType("DropdownButton"))
                or (type(child.SetupMenu) == "function" and not child:IsObjectType("CheckButton"))
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if isDropdown and not dropdowns[child] then
                dropdowns[child] = true
                ns.SkinDropdown(child)
                if child:GetWidth() < 40 then
                    for _, r in ipairs({ child:GetRegions() }) do
                        if ns.IsMine(child, r) and math.abs(r:GetWidth() - 10) < 0.5 and math.abs(r:GetHeight() - 10) < 0.5 then
                            r:ClearAllPoints()
                            r:SetPoint("CENTER")
                        end
                    end
                end
            elseif depth < 5 then
                FindDropdowns(child, depth + 1)
            end
        end
    end
end

-- Text-Knöpfe (z. B. "Änderungen anwenden" unten): flach wie überall. Nur Knöpfe mit Beschriftung in Knopfgröße –
-- die Talent-Symbole haben keinen Text und bleiben unberührt
local buttons = setmetatable({}, { __mode = "k" })
local function FindButtons(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not tabs[child] and not dropdowns[child] then
            if child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                if not buttons[child] and type(text) == "string" and text ~= "" and child:GetHeight() <= 32
                    and child:GetWidth() >= 60 then
                    buttons[child] = true
                    ns.SkinButton(child)
                end
            elseif depth < 5 then
                FindButtons(child, depth + 1)
            end
        end
    end
end

-- Knopf "Zauberbuch" links neben dem Suchfeld (wie beim Lehrer: ForeverSpellbook, sonst Blizzards Zauberbuch)
local function FindSearchBox(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("EditBox") then return child end
            if depth < 5 then
                local found = FindSearchBox(child, depth + 1)
                if found then return found end
            end
        end
    end
end

-- Talente eines anderen Spielers ansehen (Betrachten)? Dann fehlt Blizzards Reiterleiste, das Suchfeld sitzt links –
-- der Knopf "Zauberbuch" (für das eigene Zauberbuch) wird dann ausgeblendet
local function Inspecting(f)
    for _, obj in ipairs({ f, f.TalentsFrame or false }) do
        if obj and type(obj.IsInspecting) == "function" then
            local ok, yes = pcall(obj.IsInspecting, obj)
            if ok then return yes and true or false end
        end
    end
    return false
end
local book
local function UpdateSpellbookButton(f)
    if book then book:SetShown(not Inspecting(f)) end
end

local function AddSpellbookButton(f)
    book = ns.UI.Button(f, ns.T("Zauberbuch", "Spellbook"), 100, function()
        local api = ns.UI.API and ns.UI.API.ForeverSpellbook
        if api and api.Toggle then
            pcall(api.Toggle)
        elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBookFrame then
            pcall(PlayerSpellsUtil.ToggleSpellBookFrame)
        end
    end)
    book:SetHeight(22)
    local search = FindSearchBox(f, 1)
    if search then
        -- im selben Rahmen und auf der Ebene des Suchfelds: sonst lag ein unsichtbarer Teil des Talentfensters
        -- (sehr hohe Ebenen) darüber und fing den Klick ab
        local holder = search:GetParent() or f
        book:SetParent(holder)
        book:SetPoint("RIGHT", search, "LEFT", -12, 0)
        book:SetFrameLevel(search:GetFrameLevel() + 2)
    else
        book:SetPoint("TOPRIGHT", f, "TOPRIGHT", -260, -32)
        book:SetFrameLevel(f:GetFrameLevel() + 500)
    end
    UpdateSpellbookButton(f)
    f:HookScript("OnShow", function() pcall(UpdateSpellbookButton, f) end)
end

-- Reiter kleiner (Schrift bleibt gleich groß): Höhe 24, Breite nach Text; danach die Leiste neu anordnen lassen
local TAB_HEIGHT, TAB_PAD, TAB_MIN = 24, 28, 80
local function SizeTabs()
    local bars = {}
    for tab in pairs(tabs) do
        local fs = tab.GetFontString and tab:GetFontString()
        local w = math.max(TAB_MIN, math.floor((fs and fs:GetStringWidth() or 0) + TAB_PAD + 0.5))
        if math.abs(tab:GetWidth() - w) > 0.5 or math.abs(tab:GetHeight() - TAB_HEIGHT) > 0.5 then
            tab:SetSize(w, TAB_HEIGHT)
            local bar = tab:GetParent()
            if bar then bars[bar] = true end
        end
    end
    for bar in pairs(bars) do
        if bar.Layout and not Forbidden(bar) then pcall(bar.Layout, bar) end
    end
end

-- Luft unter den Reitern: die Reiterleiste (Elternrahmen der Reiter) etwas nach oben
local LIFT = 6
local lifted = {} -- [Leiste] = ursprünglicher y-Versatz
local function LiftTabs(f)
    for tab in pairs(tabs) do
        local bar = tab:GetParent()
        if bar and bar ~= f and not Forbidden(bar) and bar:GetNumPoints() == 1 then
            local point, rel, relPoint, x, y = bar:GetPoint(1)
            if lifted[bar] == nil then lifted[bar] = y end
            if y ~= lifted[bar] + LIFT then bar:SetPoint(point, rel, relPoint, x, lifted[bar] + LIFT) end
        end
    end
end

local function FindTabs(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("Button") or child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                if not tabs[child] and IsSpecTabText(text) then
                    tabs[child] = true
                    ns.SkinTab(child, Selected)
                end
            elseif depth < 5 then
                FindTabs(child, depth + 1)
            end
        end
    end
end

-- Blizzards Metallrahmen (NineSlice, samt braunem Balken und goldenen Ecken) und das Porträt: Blizzard blendet sie
-- beim Öffnen wieder ein – darum jedes Teil einzeln unsichtbar, bei offenem Fenster immer wieder
local function HideFrameArt(f)
    -- Blizzards Fensterhintergrund (liegt über unserer flachen Fläche)
    ns.Hide(f.Bg)
    for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
        end
    end
    -- Blizzards großes Talent-Hintergrundbild (liegt unter den Bäumen, sichtbar nur oben bei den Reitern) und die
    -- Partikel-Animation darüber: weg, dort zeigt sich unsere flache Fläche
    local talents = f.TalentsFrame
    if type(talents) == "table" and not Forbidden(talents) then
        for key, obj in pairs(talents) do
            if type(key) == "string" and type(obj) == "table" and (key == "Background" or key:find("Particles"))
                and obj.IsObjectType and obj:IsObjectType("Texture") then
                obj:SetAlpha(0)
            end
        end
    end
end

local function SkinTalents()
    local f = G("PlayerSpellsFrame")
    if not f or ns.talentsSkinned or Forbidden(f) then return end
    ns.talentsSkinned = true
    -- nur der Rahmen ("leicht": Blizzards Hintergrund mit den Talentbäumen bleibt)
    ns.SkinWindow(f, nil, true)
    Step("frame", function() HideFrameArt(f) end)
    Step("tabs", function() FindTabs(f, 1); SizeTabs(); LiftTabs(f) end)
    Step("dropdowns", function() FindDropdowns(f, 1) end)
    Step("buttons", function() FindButtons(f, 1) end)
    Step("spellbook", function() AddSpellbookButton(f) end)
    ns.Watch(f)
    -- Reiter entstehen teils erst beim Öffnen/Umschalten: solange offen, ab und zu nachsehen; Text mittig
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.2) then return end
        waited = 0
        pcall(HideFrameArt, f)
        pcall(FindTabs, f, 1)
        pcall(SizeTabs)
        pcall(FindDropdowns, f, 1)
        pcall(FindButtons, f, 1)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end -- aufgeklapptes Menü ("Passive ausblenden" …) flach
        pcall(LiftTabs, f)
        pcall(UpdateSpellbookButton, f)
        for t in pairs(tabs) do pcall(ns.CenterText, t) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.talentsSkinned or not ns.GetDB().talents or not G("PlayerSpellsFrame") then return end
    Step("skin", SkinTalents)
end)
