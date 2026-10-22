-- ForeverAlts – ProfessionTab.lua: eigener Reiter rechts am Berufe-Fenster, in der Reihe von Blizzards Berufs-Reitern.
-- Im Forever-Client heißen die Reiter "Professions1Tab", "Professions2Tab" … (am "ProfessionsFrame") und bestehen
-- aus der Grafik "common-sidetab", einer runden Maske für das Symbol und "common-sidetab-hover" (laut /fskin grafik).
-- Unser Reiter ist genauso gebaut, darin das Symbol von ForeverAlts, und steht unter dem letzten Reiter im selben
-- Abstand. Klick: Übersicht der Twinks (dort die Berufe und Rezepte jedes Charakters). Blizzards Reiter bleiben
-- unverändert.
local _, ns = ...
local T = ns.T

local ICON = "Interface\\AddOns\\ForeverAlts\\Media\\ForeverAlts"
local tab

-- sichtbare Blizzard-Reiter von oben nach unten
local function BlizzardTabs()
    local list = {}
    for i = 1, 12 do
        local t = _G["Professions" .. i .. "Tab"]
        if t and t ~= tab and t:IsShown() and t:GetTop() then list[#list + 1] = t end
    end
    table.sort(list, function(a, b) return a:GetTop() > b:GetTop() end)
    return list
end

local function Build(frame)
    tab = CreateFrame("Button", "ForeverAltsProfessionTab", frame)
    tab:SetSize(55, 59)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not bg:SetAtlas("common-sidetab") then bg:SetColorTexture(0.1, 0.1, 0.12, 0.9) end
    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(49, 49)
    icon:SetPoint("CENTER")
    icon:SetTexture(ICON)
    local mask = tab:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetAtlas("common-sidetab-mask")
    icon:AddMaskTexture(mask)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if not hl:SetAtlas("common-sidetab-hover") then hl:SetColorTexture(1, 1, 1, 0.15) end
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
end

local function Place(frame)
    local tabs = BlizzardTabs()
    local last = tabs[#tabs]
    if not last then
        tab:Hide()
        return
    end
    -- gleiche Größe, Ebene und gleicher Abstand wie zwischen Blizzards Reitern
    tab:SetSize(last:GetWidth(), last:GetHeight())
    tab:SetFrameStrata(last:GetFrameStrata())
    tab:SetFrameLevel(last:GetFrameLevel())
    local gap = 4
    if tabs[2] then gap = math.max(0, (tabs[1]:GetBottom() or 0) - (tabs[2]:GetTop() or 0)) end
    tab:ClearAllPoints()
    tab:SetPoint("TOP", last, "BOTTOM", 0, -gap)
    tab:Show()
end

local function Setup(frame)
    if tab or not frame then return end
    Build(frame)
    -- (Blizzards Reiter stehen erst nach dem Öffnen fest – kurz danach einreihen; beim Berufswechsel ebenso)
    local function Later() C_Timer.After(0.05, function() pcall(Place, frame) end) end
    frame:HookScript("OnShow", Later)
    for i = 1, 12 do
        local t = _G["Professions" .. i .. "Tab"]
        if t then
            t:HookScript("OnShow", Later)
            t:HookScript("OnHide", Later)
        end
    end
    if frame:IsShown() then Later() end
end

-- /falts reiter: wie weit ist der Reiter gekommen? (Fenster gefunden, Reiter angelegt, Blizzards Reiter, Lage)
function ns.CheckProfessionTab()
    local function Say(text) print("|cffffcc00ForeverAlts|r: " .. tostring(text)) end
    local frame = _G.ProfessionsFrame or _G.ProfessionsBookFrame
    Say("Berufe-Fenster: " .. (frame and ((frame:GetName() or "?") .. (frame:IsShown() and " (offen)" or " (zu)")) or "nicht gefunden"))
    Say("Reiter angelegt: " .. tostring(tab ~= nil))
    local names = {}
    for i = 1, 12 do
        local t = _G["Professions" .. i .. "Tab"]
        if t then names[#names + 1] = "Professions" .. i .. "Tab" .. (t:IsShown() and "" or " (versteckt)") end
    end
    Say("Blizzard-Reiter: " .. (#names > 0 and table.concat(names, ", ") or "keine gefunden"))
    if tab then
        local p, rel, rp, x, y = tab:GetPoint(1)
        Say(string.format("Unser Reiter: sichtbar=%s, Größe %dx%d, Ebene %s/%d, hängt an %s %s (%d, %d)",
            tostring(tab:IsVisible()), tab:GetWidth() or 0, tab:GetHeight() or 0, tab:GetFrameStrata(),
            tab:GetFrameLevel(), tostring(rel and rel.GetName and rel:GetName() or rel), tostring(rp), x or 0, y or 0))
    end
    -- gleich noch einmal einreihen (falls das Fenster offen ist)
    if frame and tab and frame:IsShown() then pcall(Place, frame) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if tab then return end
    local frame = _G.ProfessionsFrame or _G.ProfessionsBookFrame
    if frame and not (frame.IsForbidden and frame:IsForbidden()) then pcall(Setup, frame) end
end)
