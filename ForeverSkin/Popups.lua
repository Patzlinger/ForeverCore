-- ForeverSkin – Popups.lua: Blizzards Rückfrage-Fenster ("Sollen alle Talente verlernt werden?", Einladungen,
-- Löschen …) flach und dunkel mit goldener Linie oben (wie die Forever-Tooltips), Knöpfe flach.
-- Diese Fenster lösen oft geschützte Aktionen aus (z. B. Talente verlernen): darum besonders zurückhaltend – nur
-- Grafiken unsichtbar (SetAlpha) und eigene Texturen darunter, NICHTS in die Tabellen der Fenster schreiben,
-- keine Skripte ersetzen, nichts verschieben.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local done = setmetatable({}, { __mode = "k" })

-- nur die Antwort-Knöpfe 1–4 (Retail: im ButtonContainer, Classic: StaticPopup1Button1 …) – NICHT die Münzen
-- eines Betrags (die sind auch Knöpfe mit Text, z. B. "1" mit Silber-Symbol)
local function Buttons(frame)
    local list, name = {}, frame:GetName()
    local box = frame.ButtonContainer
    for i = 1, 4 do
        local b = (box and box["Button" .. i]) or frame["button" .. i] or (name and _G[name .. "Button" .. i])
        if b then list[#list + 1] = b end
    end
    local extra = frame.extraButton or (name and _G[name .. "ExtraButton"])
    if extra then list[#list + 1] = extra end
    return list
end

local function SkinPopup(frame)
    if not frame then return end
    -- Knöpfe bei jedem Anzeigen prüfen (Blizzard legt sie teils erst später an; ns.SkinButton gestaltet jeden nur einmal)
    for _, b in ipairs(Buttons(frame)) do ns.SkinButton(b) end
    if done[frame] then return end
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

-- Prüfbefehl /fskin maus: welches Fenster liegt unter der Maus (Name, Eltern-Kette, geschützt?) – im Chat. Dient
-- dazu, Blizzard-Fenster zu finden, die anders heißen als erwartet (z. B. die Rückfrage "Handel abschließen?").
function ns.DumpMouse()
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local frame = foci and foci[1]
    if not frame then
        ns.UI.Chat("ForeverSkin", ns.T("Unter der Maus liegt kein Fenster.", "No frame under the mouse."))
        return
    end
    local depth = 0
    while frame and depth < 8 do
        local forbidden = frame.IsForbidden and frame:IsForbidden()
        local name = forbidden and "(geschützt)" or (frame.GetName and frame:GetName()) or "-"
        local kind = (not forbidden and frame.GetObjectType) and frame:GetObjectType() or "?"
        ns.UI.Chat("ForeverSkin", string.rep("  ", depth) .. name .. " [" .. kind .. "]")
        if forbidden then break end
        frame = frame.GetParent and frame:GetParent()
        depth = depth + 1
    end
end

-- Beim Login gibt es im Forever-Client nicht immer schon alle Rückfrage-Fenster (sie entstehen beim ersten
-- Anzeigen, z. B. "Handel abschließen?") – darum zusätzlich nach jedem Anzeigen nachsehen (nur angehängt, Blizzards
-- Funktion bleibt unverändert)
local hooked = false
function ns.SkinPopups()
    for i = 1, 10 do
        local frame = _G["StaticPopup" .. i]
        if frame then SkinPopup(frame) end
    end
    if not hooked and type(_G.StaticPopup_Show) == "function" then
        hooked = true
        hooksecurefunc("StaticPopup_Show", function() pcall(ns.SkinPopups) end)
    end
end
