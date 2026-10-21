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
    -- Pfeile ohne eigenen Kasten (grau, Maus drauf = gold)
    ns.SkinArrowOnly(G(name .. "LeftButton"), "left")
    ns.SkinArrowOnly(G(name .. "RightButton"), "right")
end

-- Kasten nur so breit wie die längste Beschriftung (+ Luft), mittig in der Zeile; Pfeile AUSSERHALB davon, 3 neben
-- dem Kasten, senkrecht mittig. Breite für alle Zeilen gleich (bündig untereinander).
local boxInsets = {} -- [Zeile] = zuletzt gesetzter Einzug
local function RowText(row)
    local text = G(row:GetName() .. "Text") or row.Text
    if not text then
        for _, r in ipairs({ row:GetRegions() }) do
            if r:IsObjectType("FontString") then text = r break end
        end
    end
    return text
end
local function FitRows()
    local widest = 0
    for i = 1, ROWS do
        local row = G("TabardFrameCustomization" .. i)
        local text = row and not Forbidden(row) and RowText(row)
        if text then widest = math.max(widest, text:GetStringWidth() or 0) end
    end
    local boxW = math.floor(widest + 28)
    for i = 1, ROWS do
        local row = G("TabardFrameCustomization" .. i)
        if row and not Forbidden(row) and row:GetWidth() and row:GetWidth() > boxW then
            local inset = math.floor((row:GetWidth() - boxW) / 2)
            if boxInsets[row] ~= inset then
                boxInsets[row] = inset
                ns.Flat(row, C.button, { inset, 0, inset, 0 })
            end
            local name = row:GetName()
            Anchor(G(name .. "LeftButton"), "RIGHT", row, "CENTER", -boxW / 2 - 3, 0)
            Anchor(G(name .. "RightButton"), "LEFT", row, "CENTER", boxW / 2 + 3, 0)
        end
    end
end

-- Beschriftung ("Symbol", "Rand" …) genau mittig im Balken
local function CenterRowText(i)
    local row = G("TabardFrameCustomization" .. i)
    if not row or Forbidden(row) then return end
    local text = G(row:GetName() .. "Text") or row.Text
    if not text then
        for _, r in ipairs({ row:GetRegions() }) do
            if r:IsObjectType("FontString") then text = r break end
        end
    end
    if text then
        Anchor(text, "CENTER", row, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
    end
end

local function Place(f)
    -- Größe wie das Gesprächsfenster
    local gossip = G("GossipFrame")
    local w, h = gossip and gossip:GetWidth() or 384, gossip and gossip:GetHeight() or 512
    if math.abs(f:GetWidth() - w) > 0.5 then f:SetWidth(w) end
    if math.abs(f:GetHeight() - h) > 0.5 then f:SetHeight(h) end
    -- Kontostand links in der Titelleiste (ns.HeaderGold über ns.SkinWindow); Blizzards Gold-Anzeige unten
    -- (doppelt) unsichtbar
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
        Anchor(first, "BOTTOMRIGHT", inset, "BOTTOMRIGHT", -10, 14 + (ROWS - 1) * (rowH + 4))
        for i = 2, ROWS do
            Anchor(G("TabardFrameCustomization" .. i), "TOP", G("TabardFrameCustomization" .. (i - 1)), "BOTTOM", 0, -4)
        end
        for i = 1, ROWS do CenterRowText(i) end
        FitRows()
    end
    -- Dreh-Knöpfe unten links in der Innenfläche (mit Luft zur goldenen Linie)
    if inset then Anchor(G("TabardCharacterModelRotateLeftButton"), "BOTTOMLEFT", inset, "BOTTOMLEFT", 10, 14) end
    -- untere Leiste: Kosten links, "Abbrechen" rechts, "Annehmen" 8 daneben (alles auf halber Höhe).
    -- Blizzards Kosten-Feld ist breit und schreibt rechtsbündig: darum Beschriftung ("Kosten:") und Betrag einzeln
    -- setzen – Beschriftung 10 vom linken Rand, der Betrag 4 dahinter (Blizzard passt dessen Breite selbst an)
    local y = FOOTER / 2
    local cost = G("TabardFrameCostFrame")
    if cost and not Forbidden(cost) then
        -- Beschriftung über ihren Text suchen ("Kosten:"), im Kosten-Feld, dessen Unter-Rahmen und im Fenster
        local label
        local wanted = _G.COSTS_LABEL
        local function Find(frame)
            if label or not frame or Forbidden(frame) or not frame.GetRegions then return end
            for _, r in ipairs({ frame:GetRegions() }) do
                if r:IsObjectType("FontString") then
                    local s = r:GetText()
                    if type(s) == "string" and (s == wanted or s:find("^Kosten") or s:find("^Cost")) then
                        label = r
                        return
                    end
                end
            end
        end
        Find(cost)
        for _, child in ipairs({ cost:GetChildren() }) do Find(child) end
        Find(f)
        local money = G("TabardFrameCostMoneyFrame")
        if label then
            Anchor(label, "LEFT", f, "BOTTOMLEFT", 10, y)
            if money then Anchor(money, "LEFT", label, "RIGHT", 4, 0) end
        else
            Anchor(cost, "LEFT", f, "BOTTOMLEFT", 10, y)
        end
    end
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
    -- Blizzards Rahmen um die Gestaltungs-Zeilen (dunkler Kasten dahinter) und sein NPC-Name oben (lag über dem
    -- Namen der Visitenkarte) unsichtbar
    Step("rowFrame", function()
        local first = G("TabardFrameCustomization1")
        local holder = first and first:GetParent()
        if holder and holder ~= f and not Forbidden(holder) then
            ns.HideTextures(holder)
            if holder.NineSlice then ns.Hide(holder.NineSlice) end
        end
        -- (Rahmen nur ohne Grafiken – NICHT ganz unsichtbar, darin liegen die Zeilen)
        for _, n in ipairs({ "TabardFrameCustomizationFrame", "TabardFrameCustomizationBorder" }) do
            local obj = G(n)
            if obj and not Forbidden(obj) then
                if obj.GetRegions then ns.HideTextures(obj) end
                if obj.NineSlice then ns.Hide(obj.NineSlice) end
            end
        end
        local nameText = G("TabardFrameNameText")
        if nameText and not Forbidden(nameText) then nameText:SetAlpha(0) end
    end)
    Step("buttons", function()
        SkinTextButton(G("TabardFrameAcceptButton"))
        SkinTextButton(G("TabardFrameCancelButton"))
        -- (Dreh-Knöpfe bleiben ohne eigenen Kasten – nur Blizzards Pfeil-Symbole, auf Wunsch)
    end)
    Step("place", function() Place(f) end)
    ns.Watch(f)
    ns.Scaled(f, 1.05) -- wie die übrigen Fenster (Regler "Größe") und 5 % mehr (das Modell braucht Platz)
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
