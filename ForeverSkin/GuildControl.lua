-- ForeverSkin – GuildControl.lua: Gildenverwaltung (GuildControlUI – Gildenränge, Rechte, Bankfächer) im Forever-Stil
-- (docs/Fenster-Stil.md): flache dunkle Fläche mit goldener Linie oben, unser Schließen-Kreuz, die Innenfläche als
-- flacher Kasten; Auswahllisten ("Optionen", Rang), Namensfelder, Text-Knöpfe ("Neuer Rang"), Häkchen und Laufleisten
-- flach; die Pfeile zum Verschieben der Ränge als feine Pfeile (gesperrt = blass). Die Löschen-Symbole bleiben.
-- Die Seiten wechseln über "Optionen" – darum wird solange das Fenster offen ist nachgesehen. Blizzard lädt das
-- Fenster erst beim ersten Öffnen (Blizzard_GuildControlUI). Teile werden nach Art gesucht.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })
local arrows = setmetatable({}, { __mode = "k" }) -- [Knopf] = true: feiner Pfeil, gesperrt blass
local textButtons = setmetatable({}, { __mode = "k" })

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

local function SkinEdit(box)
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    local name = box:GetName()
    if name then for _, s in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(G(name .. s)) end end
    ns.HideTextures(box)
    ns.Flat(box, C.input, { -4, 0, 0, 0 })
end

local function SkinOldDropdown(dd)
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
    if dd.Text and dd.Text.SetTextColor then dd.Text:SetTextColor(0.95, 0.95, 0.95) end
end

-- Pfeil-Knöpfe (Rang hoch/runter): am Schlüssel bzw. Namen erkannt
local function ArrowDir(frame, child)
    local key = ((ns.KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
    if key:find("up") then return "up" end
    if key:find("down") then return "down" end
end

local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            if type(child.NineSlice) == "table" and not child:IsObjectType("Button") then
                ns.Hide(child.NineSlice)
                ns.Flat(child, C.panel)
            end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("Slider") and (child:GetName() or ""):find("ScrollBar") then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("DropdownButton") or type(child.SetupMenu) == "function" then
                done[child] = true
                ns.SkinDropdown(child)
            elseif not child:IsObjectType("Button") and type(child.Button) == "table" and type(child.Text) == "table"
                and (type(child.Left) == "table" or type(child.Middle) == "table") then
                done[child] = true
                SkinOldDropdown(child)
            elseif child:IsObjectType("EditBox") then
                done[child] = true
                SkinEdit(child)
            elseif child:IsObjectType("CheckButton") then
                if (child:GetWidth() or 0) <= 32 then
                    done[child] = true
                    ns.SkinCheck(child)
                end
            elseif child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                local dir = ArrowDir(frame, child)
                if type(text) == "string" and text ~= "" and (child:GetWidth() or 0) >= 60 then
                    FlatButton(child)
                    done[child] = true
                elseif dir and (child:GetWidth() or 0) <= 32 then
                    done[child] = true
                    ns.SkinArrowOnly(child, dir)
                    arrows[child] = true
                end
            elseif depth < 5 then
                -- (Rang-Zeilen u. a. sind Rahmen mit Knöpfen darin – sie werden nicht gemerkt und jedes Mal durchsucht)
                Scan(child, depth + 1)
            end
        end
    end
end

local skinned
local function SkinGuildControl()
    local f = G("GuildControlUI")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.HideTextures(f)
    for _, key in ipairs({ "NineSlice", "Border", "Bg", "Background" }) do
        local part = f[key]
        if type(part) == "table" then
            ns.Hide(part)
            if part.GetRegions then ns.HideTextures(part) end
        end
    end
    if f.ClearBackdrop and f.GetBackdrop and f:GetBackdrop() then pcall(f.ClearBackdrop, f) end
    ns.Flat(f, C.background)
    local line = f:CreateTexture(nil, "BORDER", nil, -6)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", -1, -1)
    ns.OnePixel(line, true)
    local close = ns.FindCloseButton(f)
    if close then ns.SkinClose(close) end
    pcall(Scan, f, 1)
    ns.Watch(f)
    -- Seiten (Ränge, Rechte, Bankfächer) und Rang-Zeilen entstehen beim Umschalten: solange offen nachsehen;
    -- gesperrte Pfeile blass, rote Knöpfe flach halten
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.3) then return end
        waited = 0
        pcall(Scan, f, 1)
        for b in pairs(arrows) do
            if b:IsVisible() then b:SetAlpha((b.IsEnabled and not b:IsEnabled()) and 0.3 or 1) end
        end
        for b in pairs(textButtons) do if b:IsVisible() then pcall(FlatButton, b) end end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().communities then return end
    if G("GuildControlUI") and not skinned then
        local ok, err = pcall(SkinGuildControl)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "guildcontrol", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
