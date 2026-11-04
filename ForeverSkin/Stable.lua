-- ForeverSkin – Stable.lua: Stall (PetStableFrame, nur Jäger beim Stallmeister) im Forever-Stil
-- (docs/Fenster-Stil.md). Der Forever-Client nutzt den klassischen Stall (laut /fskin maus), nicht Blizzards neuen
-- StableFrame: links fünf aktive Plätze, in der Mitte das Modell mit Name/Stufe/Art, unten zehn Stallplätze je Seite.
--  * Rahmen flach mit Titelleiste (links "Dein Gold": Stallplätze kosten Gold), Innenflächen flach statt Blizzards
--    Steinbildern
--  * alle Plätze wie Taschenplätze in ForeverBags (dunkles Feld, feiner Rand, Maus darauf bzw. gewählt = gold)
--  * Blätter-Pfeile ohne Kasten-Grafik, ausgegraut blasser
-- Nichts hier ist geschützt; Blizzards Grafiken werden nur unsichtbar, nichts in Blizzards Tabellen geschrieben.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local SLOT = { 0.06, 0.06, 0.08, 0.85 } -- Platz-Farbe wie in ForeverBags

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "stable/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" })

-- Platz (aktiv oder im Stall): Blizzards Fach-Grafik, Rahmen und Leucht-Grafiken weg, Symbol 1 px eingerückt
-- gewählt: in der Vanilla-Fassung ein Häkchen-Knopf (GetChecked), sonst Blizzards "Checked"-Grafik
local function Checked(button)
    if button.GetChecked then return button:GetChecked() and true or false end
    return type(button.Checked) == "table" and button.Checked:IsShown()
end
local function SkinSlot(button)
    if not button or done[button] or Forbidden(button) then return end
    done[button] = true
    local name = button:GetName()
    local icon = button.icon or (name and G(name .. "IconTexture"))
    for _, key in ipairs({ "Background", "Checked", "Border" }) do ns.Hide(button[key]) end
    if name then ns.Hide(G(name .. "Background")) end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    ns.Flat(button, SLOT)
    if icon and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    ns.Hover(button, Checked)
end

-- Symbol des gewählten Begleiters (oben über dem Modell): ebenso als Platz – Fläche und feiner Rand dahinter
local function SkinSelectedIcon()
    local icon, info = G("PetStableSelectedPetIcon"), G("PetStablePetInfo")
    if not icon or not info or done[icon] then return end
    done[icon] = true
    ns.Hide(G("PetStableIconBorder"))
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local function Tex(layer, sub, c)
        local t = info:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(WHITE)
        t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        return t
    end
    local fill = Tex("BACKGROUND", -8, SLOT)
    fill:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local e = Tex("BORDER", -8, C.border)
        e:SetPoint(p[1], fill, p[1])
        e:SetPoint(p[2], fill, p[2])
        ns.OnePixel(e, p[3])
    end
end

-- Kontostand unten: doppelt zum "Dein Gold" in der Titelleiste – unsichtbar samt seiner Leiste. Nur Rahmen mit
-- "Money" im Namen, nicht die Kosten ("Kosten: 5 Silber" gehört zum Stallplatz-Kauf)
local function HideMoneyBar(f)
    for _, child in ipairs({ f:GetChildren() }) do
        if not Forbidden(child) then
            local name = (child:GetName() or ""):lower()
            if name:find("money") and not name:find("cost") and child:GetAlpha() > 0 then child:SetAlpha(0) end
        end
    end
    for _, key in ipairs({ "MoneyInset", "MoneyBg", "MoneyFrame" }) do
        local obj = f[key]
        if type(obj) == "table" and obj.SetAlpha and obj:GetAlpha() > 0 then obj:SetAlpha(0) end
    end
end

-- braune Zierleisten über und unter dem Modell: alle langen, dünnen Grafiken (breiter als 150, höchstens 14 hoch),
-- die nicht von uns stammen, unsichtbar – in allen Unter-Rahmen
local function HideStrips(frame, depth)
    if not frame or Forbidden(frame) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) and r:GetAlpha() > 0 then
            local w, h = r:GetWidth() or 0, r:GetHeight() or 0
            if w > 150 and h > 1.5 and h <= 14 then r:SetAlpha(0) end
        end
    end
    if depth < 4 then
        for _, child in ipairs({ frame:GetChildren() }) do HideStrips(child, depth + 1) end
    end
end

-- Text-Knöpfe ("Kaufen" für einen Stallplatz …): flach halten – Blizzard setzt die roten Knopf-Grafiken teils neu.
-- Gesucht wird jeder Knopf mit Text im Fenster (der Name weicht in der Forever-Fassung ab); Plätze und das
-- Schließen-Kreuz haben keinen Text
local function FlatButton(b)
    ns.SkinButton(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "Center", "LeftSeparator", "RightSeparator" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end
local function TextButtons(frame, depth)
    if not frame or Forbidden(frame) then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            local label = child:IsObjectType("Button") and not child:IsObjectType("CheckButton") and child.GetText
                and child:GetText()
            if type(label) == "string" and label ~= "" then
                FlatButton(child)
            elseif depth < 3 then
                TextButtons(child, depth + 1)
            end
        end
    end
end
local function PurchaseButton()
    local f = G("PetStableFrame")
    if f then TextButtons(f, 1) end
end

-- Blätter-Pfeile: Blizzard setzt ihre Grafiken beim An-/Ausgrauen neu – immer wieder unsichtbar (unser Pfeil bleibt)
local function PageArrows()
    for _, n in ipairs({ "PetStablePrevPageButton", "PetStableNextPageButton" }) do
        local b = G(n)
        if b and not Forbidden(b) then
            ns.HideTextures(b)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                if b[get] then ns.Hide(b[get](b)) end
            end
            if type(b.icon) == "table" then ns.Hide(b.icon) end
            b:SetAlpha(b:IsEnabled() and 1 or 0.45)
        end
    end
end

local skinned
local function SkinStable()
    local f = G("PetStableFrame")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.SkinWindow(f) -- (macht auch Blizzards Bild hinter dem Modell unsichtbar)
    Step("insets", function()
        for _, inset in ipairs({ f.LeftInset or G("PetStableLeftInset"), f.BottomInset or G("PetStableBottomInset") }) do
            if inset and not Forbidden(inset) then ns.SkinInset(inset) end
        end
    end)
    Step("money", function() HideMoneyBar(f) end)
    Step("strips", function() HideStrips(f, 1) end)
    Step("purchase", PurchaseButton)
    Step("slots", function()
        SkinSlot(G("PetStableCurrentPet")) -- (Vanilla-Fassung: ein aktueller Begleiter)
        for i = 1, (NUM_PET_ACTIVE_SLOTS or 5) do SkinSlot(G("PetStableActivePet" .. i)) end
        for i = 1, (NUM_PET_STABLE_SLOTS or 10) do SkinSlot(G("PetStableStabledPet" .. i)) end
    end)
    Step("icon", SkinSelectedIcon)
    Step("arrows", function()
        ns.SkinArrowButton(G("PetStablePrevPageButton"), true)
        ns.SkinArrowButton(G("PetStableNextPageButton"), false)
        PageArrows()
    end)
    ns.Watch(f)
    -- solange offen: Pfeile und Rahmen nachhalten (Blizzard setzt sie beim Blättern und Öffnen teils neu)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(PageArrows)
        pcall(HideMoneyBar, f)
        pcall(HideStrips, f, 1)
        pcall(PurchaseButton)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if skinned or not ns.GetDB().stable or not G("PetStableFrame") then return end
    Step("skin", SkinStable)
end)
