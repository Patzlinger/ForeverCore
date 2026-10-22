-- ForeverSkin – GroupFinder.lua: Fenster "Suche nach Gruppe" (im Forever-Client LFGParentFrame) im Forever-Stil
-- (docs/Fenster-Stil.md). Auf Wunsch bleiben Hintergrund und die Grafiken der Knöpfe (Rollen, Kategorien, "Zurück",
-- "Selbst anmelden") unverändert – nur Rahmen und Titelleiste werden flach, das Auge (Porträt) sitzt klein links in
-- der Titelleiste. Beim Öffnen erscheint rechts daneben das Dungeonfenster von ForeverQuests (Schnittstelle
-- UI.API.ForeverQuests.ShowDocked/HideDocked); es schließt sich mit, wenn es erst dadurch aufging.
local _, ns = ...

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "groupfinder/" .. what, err) end
end

-- Blizzards Rahmen und das runde Porträt: Blizzard blendet sie teils wieder ein – darum jedes Teil einzeln, immer wieder
local function HideFrameArt(f)
    for _, key in ipairs({ "NineSlice", "PortraitContainer", "PortraitFrame" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
        end
    end
    local name = f:GetName()
    if name then
        for _, suffix in ipairs({ "Portrait", "PortraitFrame", "PortraitTexture" }) do ns.Hide(G(name .. suffix)) end
    end
    ns.Hide(f.portrait)
    ns.Hide(f.Portrait)
end

-- das Auge klein links in der Titelleiste (erstes Bild der Augen-Animation, wie im Quest-Tracker)
local function AddEye(f)
    local eye = f:CreateTexture(nil, "OVERLAY")
    eye:SetSize(18, 18)
    eye:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    if eye:SetTexture("Interface\\LFGFrame\\LFG-Eye") ~= false then
        eye:SetTexCoord(0, 0.125, 0, 0.25)
    else
        eye:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
        eye:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Dungeonfenster von ForeverQuests rechts daneben (nur, wenn ForeverQuests geladen ist)
local function Quests() return ns.UI.API and ns.UI.API.ForeverQuests end
local function DockDungeons(f)
    local api = Quests()
    if api and api.ShowDocked then pcall(api.ShowDocked, f) end
end
local function UndockDungeons()
    local api = Quests()
    if api and api.HideDocked then pcall(api.HideDocked) end
end

local function SkinGroupFinder()
    local f = G("LFGParentFrame")
    if not f or ns.groupFinderSkinned or Forbidden(f) then return end
    ns.groupFinderSkinned = true
    -- "leicht": Hintergrund und Knopf-Grafiken bleiben (auf Wunsch)
    ns.SkinWindow(f, nil, true)
    Step("frame", function() HideFrameArt(f) end)
    Step("eye", function() AddEye(f) end)
    ns.Watch(f)
    f:HookScript("OnShow", function() DockDungeons(f) end)
    f:HookScript("OnHide", UndockDungeons)
    if f:IsShown() then DockDungeons(f) end
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        pcall(HideFrameArt, f)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.groupFinderSkinned or not ns.GetDB().groupFinder or not G("LFGParentFrame") then return end
    Step("skin", SkinGroupFinder)
end)
