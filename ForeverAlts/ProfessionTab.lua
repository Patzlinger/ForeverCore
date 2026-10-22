-- ForeverAlts – ProfessionTab.lua: eigener Reiter rechts am Berufe-Fenster, in der Reihe von Blizzards Berufs-Reitern.
-- Gleiche Größe und gleicher Rahmen wie Blizzards Reiter darüber (übernommen vom letzten Reiter), darin das Symbol
-- von ForeverAlts. Klick: Übersicht der Twinks (dort die Berufe und Rezepte jedes Charakters).
-- Blizzards Reiter bleiben unverändert – unser Reiter hängt sich nur darunter. Im Forever-Client heißt das
-- Berufe-Fenster "ProfessionsFrame" (sonst "ProfessionsBookFrame").
local _, ns = ...
local T = ns.T

local ICON = "Interface\\AddOns\\ForeverAlts\\Media\\ForeverAlts"
local tab

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

-- Blizzards Berufs-Reiter: kleine Knöpfe mit Symbol rechts außen am Fenster, von oben nach unten
local function BlizzardTabs(frame)
    local list = {}
    local right = frame:GetRight()
    if not right then return list end
    local function Look(parent, depth)
        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= tab and not Forbidden(child) and child:IsShown() then
                local left, w, h = child:GetLeft(), child:GetWidth() or 0, child:GetHeight() or 0
                -- (im Forever-Client sind die Reiter einfache Rahmen ohne Namen, keine Knöpfe – laut /fskin maus)
                if left and left >= right - 12 and w >= 24 and w <= 60 and h >= 24 and h <= 60 then
                    list[#list + 1] = child
                elseif depth < 2 and not child:IsObjectType("Button") then
                    Look(child, depth + 1)
                end
            end
        end
    end
    Look(frame, 1)
    -- (hängen die Reiter nicht am Fenster, sondern direkt am Bildschirm: dort suchen, ohne tiefer zu gehen)
    if #list == 0 then Look(UIParent, 2) end
    table.sort(list, function(a, b) return (a:GetTop() or 0) > (b:GetTop() or 0) end)
    -- nur die zusammenhängende Reihe von oben (der Hilfe-Knopf "?" steht weit darunter)
    local row = {}
    for i, b in ipairs(list) do
        if i == 1 or ((row[#row]:GetBottom() or 0) - (b:GetTop() or 0)) < 30 then row[#row + 1] = b else break end
    end
    return row
end

local function Place(frame)
    local tabs = BlizzardTabs(frame)
    local last = tabs[#tabs]
    if not last then
        tab:Hide()
        return
    end
    if not tab.styled then
        tab.styled = true
        tab:SetSize(last:GetWidth(), last:GetHeight())
        -- Rahmen wie Blizzards Reiter: dessen Grafiken außer dem Symbol übernehmen (Datei bzw. Atlas, Lage). Das Symbol
        -- liegt in der Ebene ARTWORK (bzw. unter einem bekannten Schlüssel) – das bleibt weg, sonst schiene es durch
        for _, r in ipairs({ last:GetRegions() }) do
            if r:IsObjectType("Texture") and r:IsShown() and r:GetAlpha() > 0 then
                local atlas = r.GetAtlas and r:GetAtlas()
                local file = r:GetTexture()
                local isIcon = r == last.icon or r == last.Icon or r == last.IconTexture
                    or r == (last.GetNormalTexture and last:GetNormalTexture()) or r:GetDrawLayer() == "ARTWORK"
                if not isIcon and (atlas or file) then
                    local t = tab:CreateTexture(nil, r:GetDrawLayer())
                    if atlas and atlas ~= "" then t:SetAtlas(atlas) else t:SetTexture(file) end
                    t:SetAllPoints(tab)
                    local l, rr, tt, b = r:GetTexCoord()
                    if l then t:SetTexCoord(l, rr, tt, b) end
                    t:SetAlpha(r:GetAlpha())
                end
            end
        end
        local icon = tab:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", -3, 3)
        icon:SetTexture(ICON)
        tab.icon = icon
        local hl = tab:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(icon)
        hl:SetColorTexture(1, 1, 1, 0.15)
    end
    tab:ClearAllPoints()
    tab:SetPoint("TOP", last, "BOTTOM", 0, -((tabs[2] and ((tabs[1]:GetBottom() or 0) - (tabs[2]:GetTop() or 0))) or 4))
    tab:Show()
end

local function Setup(frame)
    if tab or not frame then return end
    tab = CreateFrame("Button", "ForeverAltsProfessionTab", frame)
    tab:SetFrameLevel(frame:GetFrameLevel() + 5)
    tab:SetScript("OnClick", function()
        if ns.ToggleWindow then ns.ToggleWindow() end
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ForeverAlts", 1, 0.82, 0)
        GameTooltip:AddLine(T("Twinks: Berufe und Rezepte aller Charaktere", "Alts: professions and recipes of all characters"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab:Hide()
    -- (Blizzards Reiter stehen erst nach dem Öffnen fest – kurz danach einreihen)
    frame:HookScript("OnShow", function() C_Timer.After(0.05, function() pcall(Place, frame) end) end)
    if frame:IsShown() then C_Timer.After(0.05, function() pcall(Place, frame) end) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if tab then return end
    local frame = _G.ProfessionsFrame or _G.ProfessionsBookFrame
    if frame and not Forbidden(frame) then pcall(Setup, frame) end
end)
