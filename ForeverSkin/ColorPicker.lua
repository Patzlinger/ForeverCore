-- ForeverSkin – ColorPicker.lua: Farbauswahl (ColorPickerFrame – z. B. Chatfarben) im Forever-Stil
-- (docs/Fenster-Stil.md): flache Fläche, Titelleiste mit goldener Linie und dem Titel darin (Blizzards Schild weg),
-- unten eine dunklere Leiste mit "OK" (links) und "Abbrechen" (rechts) flach statt rot, das Hex-Feld flach.
-- Farbrad, Helligkeitsregler und Farbfelder bleiben Blizzards (sie sind die Auswahl selbst).
local _, ns = ...
local C = ns.C

local TITLE = 23
local FOOTER = 36

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

local function FlatButton(b)
    if done[b] then return end
    done[b] = true
    ns.SkinButton(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

local function SkinEdit(box)
    if done[box] then return end
    done[box] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    ns.HideTextures(box)
    ns.Flat(box, C.input, { -14, 0, 0, 0 }) -- (links Platz für das "#")
end

-- Knöpfe mit Text und Eingabefelder suchen (die Farbauswahl selbst hat keinen Text)
local buttons = {}
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("EditBox") then
                SkinEdit(child)
            elseif child:IsObjectType("Button") and child.GetText and (child:GetText() or "") ~= ""
                and (child:GetWidth() or 0) > 50 then
                FlatButton(child)
                buttons[child] = true
            elseif depth < 4 then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Titel mittig in die Titelleiste, die Knöpfe in die untere Leiste (OK links, Abbrechen rechts)
local function Place(f)
    local header = f.Header
    local title = header and (header.Text or header.text)
    if not title then
        for _, r in ipairs({ f:GetRegions() }) do
            if r:IsObjectType("FontString") and (r:GetText() or "") ~= "" then title = r break end
        end
    end
    if header and ns.CanMove(header) then
        header:ClearAllPoints()
        header:SetPoint("CENTER", f, "TOP", 0, -math.floor(TITLE / 2) - 1)
    elseif title then
        title:ClearAllPoints()
        title:SetPoint("CENTER", f, "TOP", 0, -math.floor(TITLE / 2) - 1)
    end
    local list = {}
    for b in pairs(buttons) do if b:IsShown() then list[#list + 1] = b end end
    table.sort(list, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    local y = math.floor(FOOTER / 2)
    for i, b in ipairs(list) do
        if ns.CanMove(b) then
            b:ClearAllPoints()
            if i == 1 then b:SetPoint("LEFT", f, "BOTTOMLEFT", 10, y) else b:SetPoint("RIGHT", f, "BOTTOMRIGHT", -10, y) end
        end
    end
end

local skinned
local function SkinColorPicker()
    local f = _G.ColorPickerFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    for _, key in ipairs({ "Border", "Header", "Footer" }) do
        local part = f[key]
        if type(part) == "table" and not Forbidden(part) then
            ns.HideTextures(part)
            if type(part.NineSlice) == "table" then ns.Hide(part.NineSlice) end
        end
    end
    if f.ClearBackdrop and f.GetBackdrop and f:GetBackdrop() then pcall(f.ClearBackdrop, f) end
    ns.ContentBox(f, FOOTER, TITLE + 8, true) -- (nur die untere Leiste)
    pcall(Scan, f, 1)
    pcall(Place, f)
    ns.Watch(f)
    f:HookScript("OnShow", function(self)
        pcall(Scan, self, 1)
        pcall(Place, self)
        C_Timer.After(0, function() pcall(Place, self) end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().colorpicker then return end
    if _G.ColorPickerFrame and not skinned then
        local ok, err = pcall(SkinColorPicker)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "colorpicker", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
