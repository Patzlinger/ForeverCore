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
    ns.OnePixel(line, true)
    for _, b in ipairs(Buttons(frame)) do ns.SkinButton(b) end
    ns.Watch(frame)
end

-- Prüfbefehl /fskin maus: welches Fenster liegt unter der Maus (Name, Eltern-Kette, geschützt?) – im Chat. Dient
-- dazu, Blizzard-Fenster zu finden, die anders heißen als erwartet (z. B. die Rückfrage "Handel abschließen?").
function ns.DumpMouse()
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local frame = foci and foci[1]
    if not frame then
        -- nichts, das Mausklicks annimmt (z. B. Zier-Rahmen): alle sichtbaren Fenster unter dem Mauszeiger suchen und
        -- die kleinsten zeigen (je mit Name und Eltern-Kette)
        local hits = {}
        -- (manche Fenster liefern gesperrte Werte – die werden übersprungen)
        local secret = issecretvalue or function() return false end
        local function Yes(obj, method)
            local ok, v = pcall(obj[method], obj)
            return ok and not secret(v) and v == true
        end
        if EnumerateFrames then
            local f = EnumerateFrames()
            while f do
                local forbidden = f.IsForbidden and f:IsForbidden()
                if not forbidden and f ~= UIParent and f ~= WorldFrame and f.IsMouseOver
                    and Yes(f, "IsVisible") and Yes(f, "IsMouseOver") then
                    local okW, w = pcall(f.GetWidth, f)
                    local okH, h = pcall(f.GetHeight, f)
                    if okW and okH and not secret(w) and not secret(h) then
                        hits[#hits + 1] = { frame = f, area = (w or 0) * (h or 0) }
                    end
                end
                f = EnumerateFrames(f)
            end
        end
        if #hits == 0 then
            ns.UI.Chat("ForeverSkin", ns.T("Unter der Maus liegt kein Fenster.", "No frame under the mouse."))
            return
        end
        table.sort(hits, function(a, b) return a.area < b.area end)
        ns.UI.Chat("ForeverSkin", ns.T("Kein klickbares Fenster – sichtbare Fenster unter der Maus (kleinste zuerst):",
            "No clickable frame – visible frames under the mouse (smallest first):"))
        for i = 1, math.min(6, #hits) do
            local h = hits[i].frame
            local chain, p, d = {}, h, 0
            while p and d < 4 do
                chain[#chain + 1] = (p.GetName and p:GetName()) or "-"
                p = p.GetParent and p:GetParent()
                d = d + 1
            end
            ns.UI.Chat("ForeverSkin", i .. ". " .. table.concat(chain, " < ") ..
                string.format(" [%dx%d]", h:GetWidth() or 0, h:GetHeight() or 0))
        end
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

-- Prüfbefehl /fskin grafik: alle sichtbaren Grafiken unter dem Mauszeiger (kleinste zuerst) – je mit Rahmen,
-- Schlüssel, Datei/Atlas, Ebene und Größe. Damit lassen sich Blizzard-Grafiken gezielt finden, statt zu raten.
function ns.DumpTextures()
    local secret = issecretvalue or function() return false end
    local function Safe(obj, method, ...)
        local ok, a, b = pcall(obj[method], obj, ...)
        if not ok or secret(a) then return nil end
        return a, b
    end
    local function KeyOf(parent, child)
        if not parent then return nil end
        for k, v in pairs(parent) do
            if v == child and type(k) == "string" then return k end
        end
    end
    local hits = {}
    if EnumerateFrames then
        local f = EnumerateFrames()
        while f do
            local forbidden = f.IsForbidden and f:IsForbidden()
            if not forbidden and f ~= UIParent and f ~= WorldFrame and Safe(f, "IsVisible") then
                for _, r in ipairs({ f:GetRegions() }) do
                    if r:IsObjectType("Texture") and Safe(r, "IsVisible") and (Safe(r, "GetAlpha") or 0) > 0
                        and Safe(r, "IsMouseOver") then
                        local w, h = Safe(r, "GetWidth") or 0, Safe(r, "GetHeight") or 0
                        hits[#hits + 1] = { r = r, frame = f, area = w * h, w = w, h = h }
                    end
                end
            end
            f = EnumerateFrames(f)
        end
    end
    if #hits == 0 then
        ns.UI.Chat("ForeverSkin", ns.T("Keine Grafik unter der Maus.", "No texture under the mouse."))
        return
    end
    table.sort(hits, function(a, b) return a.area < b.area end)
    for i = 1, math.min(12, #hits) do
        local h = hits[i]
        local r, f = h.r, h.frame
        local atlas = r.GetAtlas and Safe(r, "GetAtlas")
        local file = Safe(r, "GetTexture")
        local layer = Safe(r, "GetDrawLayer")
        local chain, p, d = {}, f, 0
        while p and d < 3 do
            chain[#chain + 1] = (p.GetName and p:GetName()) or (KeyOf(p.GetParent and p:GetParent(), p)) or "-"
            p = p.GetParent and p:GetParent()
            d = d + 1
        end
        ns.UI.Chat("ForeverSkin", string.format("%d. %s | Schlüssel %s | %s | %s | %dx%d | in %s", i,
            r:GetName() or "-", KeyOf(f, r) or "-", tostring(atlas and atlas ~= "" and atlas or file), tostring(layer),
            h.w, h.h, table.concat(chain, " < ")))
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
