-- ForeverSkin – Communities.lua: Fenster "Gilde & Communitys" (CommunitiesFrame) im Forever-Stil
-- (docs/Fenster-Stil.md) – erster Schritt: Rahmen, Liste links, Innenrahmen, Laufleisten, Knöpfe oben rechts.
-- Die Bilder im Inhalt (z. B. der Drache auf der Gildenseite) bleiben: der Rahmen wird nur "leicht" umgestaltet,
-- an Innenflächen verschwinden nur Blizzards Rahmen (NineSlice). Blizzard lädt das Fenster erst beim ersten Öffnen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

-- Rand links so breit wie rechts: rechts = Abstand des Inhalts zur Fensterkante, links = Abstand der Liste zur Kante
-- unserer Fläche. Die Fläche (samt Titelleiste) reicht links entsprechend über Blizzards Fensterkante hinaus –
-- Blizzards Inhalt bleibt, wo er ist. Gemessen bei jedem Durchgang (die Aufteilung ändert sich z. B. beim Verkleinern)
local currentGrow
local function EvenMargins(f)
    local list = f.CommunitiesList
    if type(list) ~= "table" or Forbidden(list) or not (list:GetLeft() and f:GetLeft() and f:GetRight()) then return end
    local maxRight
    for _, child in ipairs({ f:GetChildren() }) do
        if child ~= list and not Forbidden(child) and child:IsShown() and child:GetRight()
            and (child:GetWidth() or 0) > 150 and (child:GetHeight() or 0) > 100 and child:GetRight() <= f:GetRight() + 1 then
            maxRight = math.max(maxRight or 0, child:GetRight())
        end
    end
    if not maxRight then return end
    local rightMargin = math.max(0, f:GetRight() - maxRight)
    local grow = math.floor(rightMargin - (list:GetLeft() - f:GetLeft()) + 0.5)
    if grow == currentGrow then return end
    currentGrow = grow
    local look = ns.Flat(f, C.background, { -grow, 0, 0, 0 })
    if look and look.head then
        look.head:ClearAllPoints()
        look.head:SetPoint("TOPLEFT", look.fill, "TOPLEFT", 1, -1)
        look.head:SetPoint("TOPRIGHT", look.fill, "TOPRIGHT", -1, -1)
    end
end

-- Porträt oben links (hier "PortraitOverlay" mit Gildenwappen, dazu das übliche PortraitContainer): unsichtbar
local function HidePortrait(f)
    for _, key in ipairs({ "PortraitOverlay", "PortraitContainer", "PortraitFrame", "Portrait" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
        end
    end
end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "communities/" .. what, err) end
end

-- Liste links (Gilde, Communitys, "Community beitreten"): blauer Hintergrund und Zierecken weg, flache Fläche
local function SkinList(list)
    if type(list) ~= "table" or Forbidden(list) then return end
    for _, key in ipairs({ "Bg", "Background", "FilligreeOverlay", "TopFiller", "BottomFiller" }) do ns.Hide(list[key]) end
    local inset = list.InsetFrame
    if type(inset) == "table" and not Forbidden(inset) then ns.SkinInset(inset) end
end

-- in allen Unterrahmen: Blizzards Innenrahmen (NineSlice) unsichtbar, Laufleisten gold – Bilder bleiben
local done = setmetatable({}, { __mode = "k" })
local textButtons = setmetatable({}, { __mode = "k" }) -- Text-Knöpfe, deren roten Grafiken laufend unsichtbar bleiben

-- Text-Knopf flach ("Mitglied einladen", "Entfernen", "Gruppeneinladung" …; Blizzard setzt das Rot teils neu)
local function FlatButton(b)
    if not textButtons[b] then
        textButtons[b] = true
        ns.SkinButton(b)
    end
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

local function IsDropdown(child)
    return (child.IsObjectType and child:IsObjectType("DropdownButton")) or type(child.SetupMenu) == "function"
        or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
end

-- Ältere Auswahlliste (UIDropDownMenuTemplate: Left/Middle/Right-Grafik und Pfeil-Knopf .Button) – flach wie unsere
local function SkinOldDropdown(dd)
    if done[dd] or Forbidden(dd) then return end
    done[dd] = true
    for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(dd[key]) end
    local name = dd:GetName()
    if name then for _, s in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(G(name .. s)) end end
    local button = dd.Button
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    local look = ns.Flat(dd, C.button)
    if look then
        look.fill:ClearAllPoints()
        look.fill:SetPoint("TOPLEFT", dd, "TOPLEFT", 18, -2)
        look.fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        local arrow = dd:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(10, 10)
        arrow:SetPoint("RIGHT", look.fill, "RIGHT", -8, 0)
        arrow:SetRotation(-math.pi / 2)
        arrow:SetVertexColor(0.8, 0.8, 0.82)
        look.mine[arrow] = true
    end
    ns.Hover(dd)
end
local function IsOldDropdown(child)
    return not child:IsObjectType("Button") and type(child.Button) == "table" and type(child.Text) == "table"
        and (type(child.Left) == "table" or type(child.Middle) == "table")
end

local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
            local isBar = type(child.Track) == "table" and (child.Track.Thumb or child.Back)
            if isBar then
                if not done[child] then
                    done[child] = true
                    ns.SkinScrollBar(child)
                end
            elseif child:IsObjectType("Button") and not child:IsObjectType("CheckButton") and type(child.Left) == "table"
                and type(child.Right) == "table" and child.GetText and (child:GetText() or "") ~= "" then
                FlatButton(child)
            elseif depth < 4 and not child:IsObjectType("Button") then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Kleine Fenster am Gildenfenster (Mitglied-Details: Rang, Notizen, Entfernen/Gruppeneinladung): flach und dunkel
-- mit goldener Linie oben, unser Schließen-Kreuz, Notizfelder als flache Kästen, Rang-Auswahl flach
local function SkinDialog(d)
    if type(d) ~= "table" or Forbidden(d) then return end
    if not done[d] then
        done[d] = true
        ns.HideTextures(d)
        for _, key in ipairs({ "Border", "NineSlice", "Bg", "Background" }) do
            local part = d[key]
            if type(part) == "table" then
                ns.Hide(part)
                if part.GetRegions then ns.HideTextures(part) end
            end
        end
        if d.ClearBackdrop and d.GetBackdrop and d:GetBackdrop() then pcall(d.ClearBackdrop, d) end
        ns.Flat(d, C.background)
        local line = d:CreateTexture(nil, "BORDER", nil, -6)
        line:SetTexture("Interface\\Buttons\\WHITE8x8")
        line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
        line:SetPoint("TOPLEFT", 1, -1)
        line:SetPoint("TOPRIGHT", -1, -1)
        ns.OnePixel(line, true)
        local close = ns.FindCloseButton(d)
        if close then ns.SkinClose(close) end
    end
    for _, child in ipairs({ d:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            if IsDropdown(child) then
                done[child] = true
                ns.SkinDropdown(child)
            elseif IsOldDropdown(child) then
                SkinOldDropdown(child) -- (Rang-Auswahl)
            elseif not child:IsObjectType("Button") and (type(child.NineSlice) == "table"
                or (child.GetBackdrop and child:GetBackdrop())) then
                -- Notizfeld (Kasten mit Blizzard-Rahmen)
                done[child] = true
                if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
                if child.ClearBackdrop then pcall(child.ClearBackdrop, child) end
                ns.HideTextures(child)
                ns.Flat(child, C.input)
            end
        end
    end
    Scan(d, 1)
end

local DIALOG_KEYS = { "GuildMemberDetailFrame" }

-- Verkleinern/Vergrößern oben rechts: nur feine Pfeile (ohne Blizzards roten Knopf)
local function SkinMaxMin(f)
    local mm = f.MaximizeMinimizeFrame
    if type(mm) ~= "table" or Forbidden(mm) then return end
    ns.HideTextures(mm)
    ns.SkinArrowOnly(mm.MaximizeButton, "up")
    ns.SkinArrowOnly(mm.MinimizeButton, "down")
end

-- Blizzard sperrt den Knopf (ausgegraut), solange es nichts zu verkleinern gibt (keine Gilde/Community) – unser feiner
-- Pfeil zeigte das nicht: dann ganz ausblenden, sonst sichtbar
local function MaxMinShown(f)
    local mm = f.MaximizeMinimizeFrame
    if type(mm) ~= "table" or Forbidden(mm) then return end
    local usable = false
    for _, b in ipairs({ mm.MaximizeButton or false, mm.MinimizeButton or false }) do
        if b and b:IsShown() and b:IsEnabled() then usable = true end
    end
    mm:SetAlpha(usable and 1 or 0)
end

local function SkinCommunities()
    local f = G("CommunitiesFrame")
    if not f or ns.communitiesSkinned or Forbidden(f) then return end
    ns.communitiesSkinned = true
    ns.SkinWindow(f, nil, true)
    ns.Hide(f.Bg)
    Step("margins", function() EvenMargins(f) end)
    Step("portrait", function() HidePortrait(f) end)
    Step("list", function() SkinList(f.CommunitiesList) end)
    Step("maxmin", function() SkinMaxMin(f); MaxMinShown(f) end)
    Step("scan", function() Scan(f, 1) end)
    ns.Watch(f)
    -- Blizzard baut Seiten beim Umschalten (Gilde, Chat, Mitglieder …) neu und blendet Rahmen beim Öffnen wieder
    -- ein: solange offen, ab und zu nachsehen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.3) then return end
        waited = 0
        if type(f.NineSlice) == "table" then ns.Hide(f.NineSlice) end
        pcall(HidePortrait, f)
        pcall(MaxMinShown, f)
        pcall(EvenMargins, f)
        pcall(SkinList, f.CommunitiesList)
        pcall(Scan, f, 1)
        for _, key in ipairs(DIALOG_KEYS) do
            if type(f[key]) == "table" and f[key]:IsShown() then pcall(SkinDialog, f[key]) end
        end
        -- rote Knöpfe flach halten
        for b in pairs(textButtons) do if b:IsVisible() then pcall(FlatButton, b) end end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.communitiesSkinned or not ns.GetDB().communities or not G("CommunitiesFrame") then return end
    Step("skin", SkinCommunities)
end)
