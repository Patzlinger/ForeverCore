-- ForeverSkin – FriendsFriends.lua: Fenster "Freunde von …" (FriendsFriendsFrame – Rechtsklick auf einen
-- Battle.net-Freund » Freunde anzeigen) im Forever-Stil (docs/Fenster-Stil.md): flache Fläche, dunkle Titelleiste mit
-- goldener Linie und dem Titel darin, unser Schließen-Kreuz; Auswahlliste flach, die Liste als flacher Kasten, unten
-- eine dunklere Leiste mit "Anfrage senden" (links) und "Schließen" (rechts, ohne Blizzards Rot).
-- Teile werden am Aufbau erkannt (Titel = oberster Text, Knöpfe = Knöpfe mit Text unten).
local _, ns = ...
local C = ns.C

local TITLE = 23
local FOOTER = 36

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

local function IsDropdown(child)
    return (child.IsObjectType and child:IsObjectType("DropdownButton")) or type(child.SetupMenu) == "function"
        or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
end

-- Text-Knopf flach (auch Blizzards roter "Schließen"-Knopf: dessen Grafiken setzt Blizzard teils neu)
local function FlatButton(b)
    ns.SkinButton(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

local function Scan(frame, depth, close)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= close and not Forbidden(child) and not done[child] then
            -- Kasten um die Liste (Blizzard: Rahmen als NineSlice bzw. Backdrop): flache, dunkle Fläche
            if not child:IsObjectType("Button") and (type(child.NineSlice) == "table" or child.SetBackdrop) then
                if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
                if child.SetBackdrop and child.GetBackdrop and child:GetBackdrop() then pcall(child.ClearBackdrop, child) end
                ns.HideTextures(child)
                ns.Flat(child, C.input)
            end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif IsDropdown(child) then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("Button") and not child:IsObjectType("CheckButton") and child.GetText
                and (child:GetText() or "") ~= "" and (child:GetWidth() or 0) > 60 then
                done[child] = true
                FlatButton(child)
            elseif not child:IsObjectType("Button") and depth < 4 then
                Scan(child, depth + 1, close)
            end
        end
    end
end

-- Titel mittig in die Titelleiste, die beiden Knöpfe in die untere Leiste (links / rechts, mittig in der Höhe)
local function Place(f)
    local top, bottom = f:GetTop(), f:GetBottom()
    if not top or not bottom then return end
    local title, titleTop
    local buttons = {}
    local function Walk(frame, depth)
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("FontString") and r:IsShown() and (r:GetText() or "") ~= "" then
                local t = r:GetTop()
                if t and top - t < 40 and (not titleTop or t > titleTop) then title, titleTop = r, t end
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) then
                local b = child:GetBottom()
                if child:IsObjectType("Button") and child.GetText and (child:GetText() or "") ~= ""
                    and (child:GetWidth() or 0) > 60 and b and b - bottom < 45 then
                    buttons[#buttons + 1] = child
                elseif depth < 3 then
                    Walk(child, depth + 1)
                end
            end
        end
    end
    Walk(f, 1)
    if title then
        title:ClearAllPoints()
        title:SetPoint("CENTER", f, "TOP", 0, -math.floor(TITLE / 2) - 1)
    end
    table.sort(buttons, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    local y = math.floor(FOOTER / 2)
    for i, b in ipairs(buttons) do
        if ns.CanMove(b) then
            b:ClearAllPoints()
            if i == 1 then
                b:SetPoint("LEFT", f, "BOTTOMLEFT", 10, y)
            else
                b:SetPoint("RIGHT", f, "BOTTOMRIGHT", -10, y)
            end
        end
    end
end

local skinned
local function SkinFriendsFriends()
    local f = _G.FriendsFriendsFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    for _, key in ipairs({ "Border", "Header" }) do
        local part = f[key]
        if type(part) == "table" and not Forbidden(part) then
            ns.HideTextures(part)
            if type(part.NineSlice) == "table" then ns.Hide(part.NineSlice) end
        end
    end
    ns.ContentBox(f, FOOTER, TITLE + 8, true) -- (nur die untere Leiste: die Liste hat ihren eigenen Kasten)
    local close = ns.FindCloseButton(f)
    pcall(Scan, f, 1, close)
    pcall(Place, f)
    ns.Watch(f)
    f:HookScript("OnShow", function(self)
        pcall(Scan, self, 1, close)
        pcall(Place, self)
        C_Timer.After(0, function() pcall(Place, self) end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().social then return end
    if _G.FriendsFriendsFrame and not skinned then
        local ok, err = pcall(SkinFriendsFriends)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "friendsfriends", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
