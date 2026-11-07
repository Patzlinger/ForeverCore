-- ForeverSkin – PvPMatch.lua: Punktetafel im Schlachtfeld (PVPMatchScoreboard) und Ergebnis danach (PVPMatchResults)
-- im Forever-Stil (docs/Fenster-Stil.md): flache Fläche, Titelleiste mit goldener Linie, unser Schließen-Kreuz;
-- Innenrahmen weg, Laufleiste gold, Reiter unten (Alle / Allianz / Horde) flach und direkt am Fenster (gewählt gold),
-- Text-Knöpfe ("Schlachtfeld verlassen") flach. Die farbigen Zeilen der Spieler (rot/blau je Fraktion) und die
-- Spaltenköpfe bleiben Blizzards – sie zeigen, wer zu wem gehört. Teile werden nach Art gesucht.
local _, ns = ...
local C = ns.C

local GAP = 8 -- Abstand zwischen den Reitern

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })
local tabsOf = setmetatable({}, { __mode = "k" })     -- [Fenster] = { Reiter … }
local textButtons = setmetatable({}, { __mode = "k" })

local function TabSelected(tab)
    if type(tab.isSelected) == "boolean" then return tab.isSelected end
    return tab.IsEnabled and not tab:IsEnabled()
end

local function FlatButton(b)
    if not textButtons[b] then
        textButtons[b] = true
        ns.SkinButton(b)
    end
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

local function Scan(f, frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            if type(child.NineSlice) == "table" and not child:IsObjectType("Button") then ns.Hide(child.NineSlice) end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
                local text = child.GetText and child:GetText()
                local key = ((ns.KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
                if type(text) == "string" and text ~= "" then
                    if key:find("tab") or type(child.SetTabSelected) == "function" then
                        done[child] = true
                        ns.SkinTab(child, TabSelected)
                        tabsOf[f] = tabsOf[f] or {}
                        table.insert(tabsOf[f], child)
                    elseif type(child.Left) == "table" or (child:GetWidth() or 0) >= 100 then
                        FlatButton(child)
                        done[child] = true
                    end
                end
            elseif depth < 4 then
                Scan(f, child, depth + 1)
            end
        end
    end
end

-- Reiter direkt am Fenster (unten links, GAP Abstand), Text mittig – wie beim Auktionshaus
local function PlaceTabs(f)
    local list = tabsOf[f]
    if not list then return end
    table.sort(list, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
    local prev
    for _, tab in ipairs(list) do
        if tab:IsShown() and ns.CanMove(tab) then
            ns.HideTextures(tab)
            if prev then ns.Anchor(tab, "LEFT", prev, "RIGHT", GAP, 0) else ns.Anchor(tab, "TOPLEFT", f, "BOTTOMLEFT", 6, 1) end
            pcall(ns.CenterText, tab)
            prev = tab
        end
    end
end

local skinned = setmetatable({}, { __mode = "k" })
local function SkinMatch(f)
    if not f or skinned[f] or Forbidden(f) then return end
    skinned[f] = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    for _, key in ipairs({ "Border", "BorderFrame", "Background", "Bg" }) do
        local part = f[key]
        if type(part) == "table" then
            if part.IsObjectType and part:IsObjectType("Texture") then part:SetAlpha(0)
            else ns.HideTextures(part) if type(part.NineSlice) == "table" then ns.Hide(part.NineSlice) end end
        end
    end
    pcall(Scan, f, f, 1)
    pcall(PlaceTabs, f)
    ns.Watch(f)
    -- Zeilen und Reiter entstehen bzw. wechseln während des Schlachtfelds: solange offen nachsehen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < ns.Tick(0.5) then return end
        waited = 0
        if type(f.NineSlice) == "table" then ns.Hide(f.NineSlice) end
        pcall(Scan, f, f, 1)
        pcall(PlaceTabs, f)
        for b in pairs(textButtons) do if b:IsVisible() then pcall(FlatButton, b) end end
    end)
end

local NAMES = { "PVPMatchScoreboard", "PVPMatchResults" }
local hooked = setmetatable({}, { __mode = "k" })
local function Setup()
    for _, name in ipairs(NAMES) do
        local f = _G[name]
        if f and not hooked[f] and not Forbidden(f) then
            hooked[f] = true
            f:HookScript("OnShow", function(self)
                local ok, err = pcall(SkinMatch, self)
                if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "pvpmatch/" .. name, err) end
            end)
            if f:IsShown() then pcall(SkinMatch, f) end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().pvpmatch then return end
    Setup()
end)
