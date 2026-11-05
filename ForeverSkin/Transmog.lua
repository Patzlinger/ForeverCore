-- ForeverSkin – Transmog.lua: Blizzards neues Transmogrifizier-Fenster (TransmogFrame) im Forever-Stil
-- (docs/Fenster-Stil.md), erster Entwurf nach dem Aufbau aus /fskin aufbau TransmogFrame:
--  * Rahmen flach mit Titelleiste und goldener Linie, unser Schließen-Kreuz (Metallrahmen, Porträt, Streifen weg)
--  * links (OutfitCollection): flache Fläche statt Blizzards Verlauf, feine Trennlinien, Laufleiste gold, Knöpfe
--    "Outfitplatz kaufen" (Symbol bleibt) und "Kleidung speichern" flach, Geldfeld flach
--  * Mitte (CharacterPreview): Blizzards Hintergrundbild und Verläufe weg (das Modell bleibt), Häkchen flach,
--    Ausrüstungsplätze mit feinem Rand statt Blizzards Rahmen (gewählt = gold; Haken/Warnzeichen bleiben)
--  * rechts (WardrobeCollection): Reiter flach (gewählt gold), Inhalt in einem flachen Kasten, Suche, Auswahllisten
--    und Text-Knöpfe flach, Blizzards Trennlinie als feine goldene Linie
-- Die Vorschau-Kacheln mit den Modellen bleiben vorerst Blizzards. Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "transmog/" .. what, err) end
end

local done = setmetatable({}, { __mode = "k" })

local function Tex(parent, layer, sub, c, a)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    return t
end

local function HideTex(obj)
    if type(obj) == "table" and obj.SetAlpha then obj:SetAlpha(0) end
end

-- Knopf mit Text flach; keepKey = Symbol, das bleiben soll (z. B. das Plus bei "Outfitplatz kaufen")
local function FlatButton(b, keepKey)
    if not b or done[b] or Forbidden(b) then return end
    done[b] = true
    local keep = keepKey and type(b[keepKey]) == "table" and { [b[keepKey]] = true } or nil
    ns.HideTextures(b, keep)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = b[get] and b[get](b)
        if t and not (keep and keep[t]) then HideTex(t) end
    end
    ns.SkinButton(b)
end

-- Ausrüstungsplatz: Blizzards Rahmen weg, feiner Rand um das Symbol; gewählt (Blizzards "SelectedFrame") = gold
local function SlotSelected(b) return type(b.SelectedFrame) == "table" and b.SelectedFrame:IsShown() end
local function SkinSlot(b)
    if not b or done[b] or Forbidden(b) then return end
    done[b] = true
    HideTex(b.Border)
    HideTex(b.GetHighlightTexture and b:GetHighlightTexture())
    if type(b.SelectedFrame) == "table" then ns.HideTextures(b.SelectedFrame) end
    local w = b:GetWidth() or 58
    ns.Flat(b, C.input, math.max(4, math.floor((w - 46) / 2)))
    ns.Hover(b, SlotSelected)
end

-- Reiter (Gegenstände, Sets, Benutzerdefinierte Sets, Situationen)
local function TabSelected(t)
    if type(t.isSelected) == "boolean" then return t.isSelected end
    return type(t.SelectedHighlight) == "table" and t.SelectedHighlight:IsShown()
end

local function IsDropdown(child)
    return (child.IsObjectType and child:IsObjectType("DropdownButton")) or type(child.SetupMenu) == "function"
        or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
end

-- Inhalt rechts (Seiten der Reiter): Suche, Auswahllisten, Text-Knöpfe, Häkchen, Laufleisten; Trennlinie gold
local function ScanContent(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            if child:IsObjectType("EditBox") and (type(child.searchIcon) == "table" or type(child.SearchIcon) == "table"
                or (child:GetName() or ""):find("Search") or ns.KeyOf(frame, child) == "SearchBox") then
                done[child] = true
                ns.SkinSearchBox(child, { -4, 0, 0, 0 })
            elseif type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif IsDropdown(child) then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("CheckButton") and (child:GetWidth() or 0) <= 32 then
                done[child] = true
                ns.SkinCheck(child)
            elseif child:IsObjectType("Button") and child.GetText and (child:GetText() or "") ~= ""
                and (child:GetWidth() or 0) >= 80 and (child:GetHeight() or 0) <= 36 then
                FlatButton(child)
            elseif not child:IsObjectType("Button") and depth < 3 then
                ScanContent(child, depth + 1)
            end
        end
    end
end

local function GoldDivider(region)
    if type(region) ~= "table" or done[region] or not region.GetParent then return end
    done[region] = true
    region:SetAlpha(0)
    local line = Tex(region:GetParent(), "OVERLAY", 1, C.accent, 0.5)
    line:SetPoint("LEFT", region, "LEFT")
    line:SetPoint("RIGHT", region, "RIGHT")
    ns.OnePixel(line, true)
end

local function SkinLeft(col)
    if type(col) ~= "table" or Forbidden(col) then return end
    for _, key in ipairs({ "Background", "GradientTop", "GradientBottom", "DividerBar" }) do HideTex(col[key]) end
    if not done[col] then
        done[col] = true
        ns.Flat(col, C.panel)
        -- feine Linie zur Mitte
        local edge = Tex(col, "BORDER", 1, C.border)
        edge:SetPoint("TOPRIGHT", 0, 0)
        edge:SetPoint("BOTTOMRIGHT", 0, 0)
        ns.OnePixel(edge, false)
    end
    local spell = col.ShowEquippedGearSpellFrame
    if type(spell) == "table" and type(spell.Button) == "table" and not done[spell.Button] then
        local b = spell.Button
        done[b] = true
        HideTex(b.Border)
        HideTex(b.GetHighlightTexture and b:GetHighlightTexture())
        ns.Flat(b, C.input, 3)
        ns.Hover(b)
    end
    local list = col.OutfitList
    if type(list) == "table" then
        GoldDivider(list.DividerTop)
        GoldDivider(list.DividerBottom)
        if list.ScrollBar and not done[list.ScrollBar] then
            done[list.ScrollBar] = true
            ns.SkinScrollBar(list.ScrollBar)
        end
    end
    FlatButton(col.PurchaseOutfitButton, "Icon")
    FlatButton(col.SaveOutfitButton)
    local money = col.MoneyFrame
    if type(money) == "table" and not done[money] then
        done[money] = true
        HideTex(money.Background)
        ns.Flat(money, C.input)
    end
end

local function SkinMiddle(mid)
    if type(mid) ~= "table" or Forbidden(mid) then return end
    HideTex(mid.Background)
    if type(mid.Gradients) == "table" then ns.HideTextures(mid.Gradients) end
    local toggles = mid.ToggleOptions
    if type(toggles) == "table" then
        for _, opt in ipairs({ toggles:GetChildren() }) do
            local cb = opt.Checkbox
            if type(cb) == "table" and not done[cb] then
                done[cb] = true
                ns.SkinCheck(cb)
            end
        end
    end
    for _, key in ipairs({ "LeftSlots", "RightSlots", "BottomSlots" }) do
        local holder = mid[key]
        if type(holder) == "table" then
            for _, b in ipairs({ holder:GetChildren() }) do
                if b:IsObjectType("Button") then SkinSlot(b) end
            end
        end
    end
    local clear = mid.ClearAllPendingButton
    if type(clear) == "table" and not done[clear] then
        done[clear] = true
        HideTex(clear.NormalTexture)
        HideTex(clear.HighlightTexture)
        ns.Flat(clear, C.button, 4)
        ns.Hover(clear)
    end
end

local function SkinRight(right)
    if type(right) ~= "table" or Forbidden(right) then return end
    HideTex(right.Background)
    local tabs = right.tabSystem
    if type(tabs) == "table" then
        for _, t in ipairs({ tabs:GetChildren() }) do
            if t:IsObjectType("Button") and not done[t] then
                done[t] = true
                ns.SkinTab(t, TabSelected)
                if type(t.SelectedHighlight) == "table" then ns.HideTextures(t.SelectedHighlight) end
            end
            if done[t] then pcall(ns.CenterText, t) end
        end
    end
    local content = right.TabContent
    if type(content) == "table" then
        HideTex(content.Background)
        HideTex(content.Border)
        if not done[content] then
            done[content] = true
            ns.Flat(content, C.panel)
        end
        local items = content.ItemsFrame
        if type(items) == "table" then GoldDivider(items.Divider) end
        ScanContent(content, 1)
    end
end

local skinned
local function SkinTransmog()
    local f = _G.TransmogFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.SkinWindow(f)
    HideTex(f.TopTileStreaks)
    if type(f.HelpPlateButton) == "table" then f.HelpPlateButton:SetAlpha(0) end -- (Hilfe-Knopf: vom Nutzer gestrichen)
    Step("left", function() SkinLeft(f.OutfitCollection) end)
    Step("middle", function() SkinMiddle(f.CharacterPreview) end)
    Step("right", function() SkinRight(f.WardrobeCollection) end)
    ns.Watch(f)
    -- Blizzard baut Seiten beim Reiterwechsel und zeigt Hintergründe teils neu: solange offen, nachsehen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.3) then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(SkinLeft, f.OutfitCollection)
        pcall(SkinMiddle, f.CharacterPreview)
        pcall(SkinRight, f.WardrobeCollection)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().wardrobe then return end
    if _G.TransmogFrame and not skinned then Step("skin", SkinTransmog) end
    if skinned then self:UnregisterAllEvents() end
end)
