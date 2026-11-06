-- ForeverSkin – QuickKeybind.lua: Schnelltastenbelegung (QuickKeybindFrame – Esc » Tastaturbelegung »
-- Schnelltastenbelegung) im Forever-Stil (docs/Fenster-Stil.md): flache Fläche, Titelleiste mit goldener Linie und dem
-- Titel darin (Blizzards Schild und durchscheinender Rahmen weg), Hinweistexte hell, das Häkchen "Charakterspezifische
-- Tastenbelegung" flach, unten eine dunklere Leiste mit den Knöpfen flach (Standard links, Okay/Abbrechen rechts).
-- Die Hervorhebung der Aktionsknöpfe beim Belegen bleibt Blizzards. Teile werden nach Art gesucht.
local _, ns = ...
local C = ns.C

local TITLE = 23
local FOOTER = 36
local GAP = 6

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })
local buttons = {}

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

local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("CheckButton") then
                if not done[child] and (child:GetWidth() or 0) <= 32 then
                    done[child] = true
                    ns.SkinCheck(child)
                end
            elseif child:IsObjectType("Button") and child.GetText and (child:GetText() or "") ~= ""
                and (child:GetWidth() or 0) > 50 then
                FlatButton(child)
                buttons[child] = true
            elseif depth < 3 then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Titel in die Titelleiste; Knöpfe unten: der linke ("Standard") links, die übrigen rechts nebeneinander
local function Place(f)
    local header = f.Header
    if header and ns.CanMove(header) then
        header:ClearAllPoints()
        header:SetPoint("CENTER", f, "TOP", 0, -math.floor(TITLE / 2) - 1)
    end
    local list = {}
    for b in pairs(buttons) do if b:IsShown() then list[#list + 1] = b end end
    table.sort(list, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    local y = math.floor(FOOTER / 2)
    local right
    for i = #list, 1, -1 do
        local b = list[i]
        if ns.CanMove(b) then
            b:ClearAllPoints()
            if i == 1 and #list > 1 then
                b:SetPoint("LEFT", f, "BOTTOMLEFT", 10, y)
            elseif right then
                b:SetPoint("RIGHT", right, "LEFT", -GAP, 0)
                right = b
            else
                b:SetPoint("RIGHT", f, "BOTTOMRIGHT", -10, y)
                right = b
            end
        end
    end
end

local skinned
local function SkinQuickKeybind()
    local f = _G.QuickKeybindFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    for _, key in ipairs({ "BG", "Border", "Header", "NineSlice" }) do
        local part = f[key]
        if type(part) == "table" and not Forbidden(part) then
            ns.HideTextures(part)
            if type(part.NineSlice) == "table" then ns.Hide(part.NineSlice) end
            if part.IsObjectType and part:IsObjectType("Texture") then ns.Hide(part) end
        end
    end
    ns.ContentBox(f, FOOTER, TITLE + 8, true) -- (nur die untere Leiste)
    -- Hinweistexte hell (Blizzard: gelb/grau auf durchscheinendem Grund)
    for _, key in ipairs({ "InstructionText", "CancelDescriptionText" }) do
        local fs = f[key]
        if fs and fs.SetTextColor then fs:SetTextColor(0.85, 0.85, 0.85) end
    end
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
    if not ns.GetDB().quickkeybind then return end
    if _G.QuickKeybindFrame and not skinned then
        local ok, err = pcall(SkinQuickKeybind)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "quickkeybind", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
