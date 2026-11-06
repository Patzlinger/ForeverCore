-- ForeverSkin – Dialogs.lua: kleine Gruppen-/PvP-Dialoge im Stil der Rückfrage-Fenster (Popups.lua): flach und dunkel
-- mit goldener Linie oben, Text-Knöpfe flach, Schließen-Kreuz wie bei uns. Betroffen: Rollenabfrage (RolePollPopup),
-- Einladung über die Gruppensuche (LFGInvitePopup), PvP-Bereitschaft "Schlachtfeld betreten" (PVPReadyDialog),
-- Gildeneinladung (GuildInviteFrame – das Gildenwappen bleibt).
-- Sie zeigen sich nur bei echter Abfrage/Einladung (ohne Gruppe nicht zu öffnen) – darum beim ersten Anzeigen.
-- Wie bei den Rückfrage-Fenstern besonders zurückhaltend: die Knöpfe lösen teils geschützte Aktionen aus (Rolle
-- setzen, Schlachtfeld betreten) – nur Grafiken unsichtbar und eigene Flächen darunter, nichts in Blizzards
-- Tabellen, keine Skripte ersetzt, nichts verschoben. Rollen-Symbole und Häkchen bleiben Blizzards.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local NAMES = { "RolePollPopup", "LFGInvitePopup", "PVPReadyDialog", "GuildInviteFrame" }

-- Gildenwappen (Gildeneinladung) bleibt: Grafiken, deren Name bzw. Schlüssel nach Wappen klingt
local KEEP_WORDS = { "tabard", "emblem", "crest", "banner" }
local function KeepArt(frame)
    local keep = {}
    local function Check(r, key)
        local s = ((r.GetName and r:GetName() or "") .. "|" .. (key or "")):lower()
        for _, w in ipairs(KEEP_WORDS) do
            if s:find(w, 1, true) then keep[r] = true return end
        end
    end
    for k, v in pairs(frame) do
        if type(k) == "string" and type(v) == "table" and v.IsObjectType and v:IsObjectType("Texture") then Check(v, k) end
    end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not keep[r] then Check(r, nil) end
    end
    return keep
end

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

-- Text-Knöpfe ("Annehmen", "Ablehnen", "Betreten" …): Knöpfe mit Text in Knopfgröße, nicht die Rollen-Symbole
local function Buttons(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                if type(text) == "string" and text ~= "" and (child:GetWidth() or 0) >= 60 and (child:GetHeight() or 0) <= 32 then
                    ns.SkinButton(child)
                end
            elseif depth < 3 then
                Buttons(child, depth + 1)
            end
        end
    end
end

local function Skin(frame)
    if not frame or Forbidden(frame) then return end
    pcall(Buttons, frame, 1) -- (bei jedem Anzeigen: Blizzard legt Knöpfe teils erst später an)
    if done[frame] then return end
    done[frame] = true
    ns.HideTextures(frame, KeepArt(frame))
    for _, key in ipairs({ "Border", "NineSlice", "BG", "Bg", "Background" }) do
        if type(frame[key]) == "table" then ns.Hide(frame[key]) end
    end
    if frame.ClearBackdrop and frame.GetBackdrop and frame:GetBackdrop() then pcall(frame.ClearBackdrop, frame) end
    ns.Flat(frame, C.background)
    local line = frame:CreateTexture(nil, "BORDER", nil, -6)
    line:SetTexture(WHITE)
    line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    line:SetPoint("TOPLEFT", 1, -1)
    line:SetPoint("TOPRIGHT", -1, -1)
    ns.OnePixel(line, true)
    local close = ns.FindCloseButton(frame)
    if close then ns.SkinClose(close) end
    ns.Watch(frame)
end

local hooked = setmetatable({}, { __mode = "k" })
local function Setup()
    for _, name in ipairs(NAMES) do
        local f = _G[name]
        if f and not hooked[f] and not Forbidden(f) then
            hooked[f] = true
            f:HookScript("OnShow", function(self)
                local ok, err = pcall(Skin, self)
                if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "dialogs/" .. name, err) end
            end)
            if f:IsShown() then pcall(Skin, f) end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().dialogs then return end
    Setup()
end)
