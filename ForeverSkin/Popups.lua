-- ForeverSkin – Popups.lua: Blizzards Rückfrage-Fenster ("Sollen alle Talente verlernt werden?", Einladungen,
-- Löschen …) flach und dunkel mit goldener Linie oben (wie die Forever-Tooltips), Knöpfe flach.
-- Diese Fenster lösen oft geschützte Aktionen aus (z. B. Talente verlernen): darum besonders zurückhaltend – nur
-- Grafiken unsichtbar (SetAlpha) und eigene Texturen darunter, NICHTS in die Tabellen der Fenster schreiben,
-- keine Skripte ersetzen, nichts verschieben.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local done = setmetatable({}, { __mode = "k" })

-- Knöpfe eines Fensters (Retail: in einem ButtonContainer, Classic: direkt), nur echte Text-Knöpfe
local function Buttons(frame, list, depth)
    list = list or {}
    depth = depth or 1
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
            local fs = child.GetFontString and child:GetFontString()
            if fs and child ~= frame.CloseButton then list[#list + 1] = child end
        elseif depth < 2 and not child:IsObjectType("EditBox") then
            Buttons(child, list, depth + 1)
        end
    end
    return list
end

local function SkinPopup(frame)
    if not frame or done[frame] then return end
    done[frame] = true
    ns.HideTextures(frame)
    if type(frame.Border) == "table" then ns.Hide(frame.Border) end
    if type(frame.NineSlice) == "table" then ns.Hide(frame.NineSlice) end
    if type(frame.BG) == "table" then ns.Hide(frame.BG) end
    ns.Flat(frame, C.background)
    -- goldene Linie oben wie bei den Forever-Tooltips
    local line = frame:CreateTexture(nil, "BORDER", nil, -6)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", -1, -1)
    line:SetHeight(1)
    for _, b in ipairs(Buttons(frame)) do ns.SkinButton(b) end
    ns.Watch(frame)
end

function ns.SkinPopups()
    for i = 1, 4 do SkinPopup(_G["StaticPopup" .. i]) end
end
