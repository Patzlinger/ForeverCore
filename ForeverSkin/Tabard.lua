-- ForeverSkin – Tabard.lua: Wappenrock-Gestaltung (Gildenwappenrock) im Forever-Stil, nach docs/Fenster-Stil.md.
--  * Größe wie das Gesprächsfenster, Titelleiste mit eigenem Kontostand links ("Dein Gold"), Blizzards doppelte
--    Gold-Anzeige unten ausgeblendet
--  * Visitenkarte des NPCs oben (wie Händler/Lehrer), Blizzards Begrüßungstext mittig darunter
--  * Innenfläche mit dem Modell; die fünf Gestaltungs-Zeilen (Symbol, Symbolfarbe, Rand, Randfarbe, Hintergrund)
--    als graue Balken mit flachen Pfeilen, unten rechts im Modell
--  * untere Leiste: Kosten links, "Annehmen" und "Abbrechen" rechts
-- Wie überall: Blizzards Grafiken nur unsichtbar, eigene darunter, nichts in Blizzards Tabellen; gesperrte Teile
-- bleiben, wie sie sind.
local _, ns = ...
local C, T = ns.C, ns.T

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local FOOTER = 40
local ROWS = 5

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "tabard/" .. what, err) end
end

-- Ankerpunkt nur neu setzen, wenn er abweicht
local function Anchor(obj, point, rel, relPoint, x, y)
    if not obj or Forbidden(obj) then return end
    local p, r, rp, ox, oy = obj:GetPoint(1)
    if obj:GetNumPoints() == 1 and p == point and r == rel and rp == relPoint
        and math.abs((ox or 0) - x) < 0.5 and math.abs((oy or 0) - y) < 0.5 then return end
    obj:ClearAllPoints()
    obj:SetPoint(point, rel, relPoint, x, y)
end

-- Text-Knöpfe: flach; zusätzlich ein eigener Kasten dahinter (Blizzard setzt seine roten Grafiken teils neu)
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

local function HideBlizzardButtonArt()
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

-- eine Gestaltungs-Zeile: grauer Balken, Pfeile links/rechts flach
local function SkinRow(i)
    local row = G("TabardFrameCustomization" .. i)
    if not row or Forbidden(row) then return end
    ns.HideTextures(row)
    local name = row:GetName()
    for _, suffix in ipairs({ "Left", "Middle", "Right", "Background" }) do ns.Hide(G(name .. suffix)) end
    ns.Flat(row, C.button)
    ns.SkinArrowButton(G(name .. "LeftButton"), true)
    ns.SkinArrowButton(G(name .. "RightButton"), false)
end

local balance
local function Place(f)
    -- Größe wie das Gesprächsfenster
    local gossip = G("GossipFrame")
    local w, h = gossip and gossip:GetWidth() or 384, gossip and gossip:GetHeight() or 512
    if math.abs(f:GetWidth() - w) > 0.5 then f:SetWidth(w) end
    if math.abs(f:GetHeight() - h) > 0.5 then f:SetHeight(h) end
    -- Kontostand links in der Titelleiste; Blizzards Gold-Anzeige unten (doppelt) unsichtbar
    if not balance then
        balance = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        balance:SetPoint("LEFT", f, "TOPLEFT", 10, -12)
    end
    if ns.Money and GetMoney then balance:SetText(T("Dein Gold: ", "Your gold: ") .. ns.Money(GetMoney())) end
    for _, n in ipairs({ "TabardFrameMoneyFrame", "TabardFrameMoneyInset", "TabardFrameMoneyBg" }) do
        local obj = G(n)
        if obj and not Forbidden(obj) and obj:GetAlpha() > 0 then obj:SetAlpha(0) end
    end
    -- Begrüßungstext mittig unter der Visitenkarte; der Inhalt beginnt darunter
    local top = -87
    local greet = G("TabardFrameGreetingText")
    if greet and not Forbidden(greet) then
        Anchor(greet, "TOP", f, "TOP", 0, -84)
        greet:SetWidth(w - 28)
        greet:SetJustifyH("CENTER")
        greet:SetTextColor(0.85, 0.85, 0.85)
        top = -84 - (greet:GetStringHeight() or 0) - 8
    end
    -- Innenfläche und Modell darin
    local inset = f.Inset or G("TabardFrameInset")
    local insetY
    if inset and not Forbidden(inset) then insetY = select(5, inset:GetPoint(1)) end
    if inset and not Forbidden(inset) and not (inset:GetNumPoints() == 2 and math.abs((insetY or 0) - top) < 0.5) then
        inset:ClearAllPoints()
        inset:SetPoint("TOPLEFT", f, "TOPLEFT", 6, top)
        inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, FOOTER + 4)
    end
    local model = G("TabardModel")
    if model and not Forbidden(model) and inset then
        local p1, r1 = model:GetPoint(1)
        if not (model:GetNumPoints() == 2 and p1 == "TOPLEFT" and r1 == inset) then
            model:ClearAllPoints()
            model:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
            model:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
        end
    end
    -- Gestaltungs-Zeilen unten rechts in der Innenfläche, 4 Abstand untereinander (die erste oben)
    local first = G("TabardFrameCustomization1")
    if first and inset then
        local rowH = first:GetHeight() or 22
        Anchor(first, "BOTTOMRIGHT", inset, "BOTTOMRIGHT", -10, 10 + (ROWS - 1) * (rowH + 4))
        for i = 2, ROWS do
            Anchor(G("TabardFrameCustomization" .. i), "TOP", G("TabardFrameCustomization" .. (i - 1)), "BOTTOM", 0, -4)
        end
    end
    -- untere Leiste: Kosten links, "Abbrechen" rechts, "Annehmen" 8 daneben (alles auf halber Höhe)
    local y = FOOTER / 2
    Anchor(G("TabardFrameCostFrame"), "LEFT", f, "BOTTOMLEFT", 10, y)
    local cancel, accept = G("TabardFrameCancelButton"), G("TabardFrameAcceptButton")
    Anchor(cancel, "RIGHT", f, "BOTTOMRIGHT", -10, y)
    if cancel then Anchor(accept, "RIGHT", cancel, "LEFT", -8, 0) end
end

local function SkinTabard()
    local f = G("TabardFrame")
    if not f or ns.tabardSkinned then return end
    ns.tabardSkinned = true
    ns.SkinWindow(f)
    ns.ContentBox(f, FOOTER, nil, true)
    Step("card", function()
        ns.NpcCard(f, "npc", T("Wappenrock", "Tabard"), function() return T("Wappenrock-Gestaltung", "Tabard design") end, 130)
    end)
    -- Hintergründe von Modell und Kosten weg (die Innenfläche ist die Fläche)
    Step("art", function()
        for _, n in ipairs({ "TabardModel", "TabardFrameCostFrame", "TabardFrameCostMoneyFrame" }) do
            local obj = G(n)
            if obj and not Forbidden(obj) then ns.HideTextures(obj) end
        end
        for _, n in ipairs({ "TabardFrameBackground", "TabardFrameCostFrameBackground" }) do ns.Hide(G(n)) end
    end)
    Step("rows", function() for i = 1, ROWS do SkinRow(i) end end)
    Step("buttons", function()
        SkinTextButton(G("TabardFrameAcceptButton"))
        SkinTextButton(G("TabardFrameCancelButton"))
        for _, n in ipairs({ "TabardCharacterModelRotateLeftButton", "TabardCharacterModelRotateRightButton" }) do
            local b = G(n)
            if b and not Forbidden(b) then ns.SkinIconButton(b) end
        end
    end)
    Step("place", function() Place(f) end)
    ns.Watch(f)
    ns.Scaled(f)
    f:HookScript("OnShow", function()
        Step("card", function()
            ns.NpcCard(f, "npc", T("Wappenrock", "Tabard"), function() return T("Wappenrock-Gestaltung", "Tabard design") end, 130)
        end)
        C_Timer.After(0, function() Step("place", function() Place(f) end) end)
    end)
    -- solange offen: Plätze prüfen (Blizzard hängt teils neu auf), Blizzards Knopf-Grafiken unsichtbar halten
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        pcall(HideBlizzardButtonArt)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        pcall(Place, f)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("OPEN_TABARD_FRAME")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Blizzard_TabardUI" then return end
    if not ns.GetDB().tabard or not G("TabardFrame") then return end
    -- (beim Öffnen-Ereignis ist das Fenster evtl. erst im Aufbau)
    C_Timer.After(0, function() Step("skin", SkinTabard) end)
end)
