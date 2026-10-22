-- ForeverSkin – ChatConfig.lua: Fenster "Chat-Einstellungen" (ChatConfigFrame) im Forever-Stil (docs/Fenster-Stil.md).
-- Fenster flach mit Titelleiste (ohne "Dein Gold"), Blizzards Kästen (Kategorien links, Einstellungsbereiche) als
-- flache Flächen mit feinem Rand; Häkchen, Regler, Auswahllisten, Text-Knöpfe und Reiter flach, Laufleisten gold. Die
-- Farbfelder (Chatfarben) bleiben. Blizzard legt Teile erst beim Umschalten der Kategorie an – darum im Takt.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "chatconfig/" .. what, err) end
end

local function KeyOf(parent, child)
    for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
end

-- Farbfeld (Chatfarbe): bleibt wie es ist – erkannt am Namen oder an Blizzards Farbfeld-Grafik
local function IsSwatch(frame, key)
    if key:find("swatch") or key:find("color") then return true end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local tex = r:GetTexture()
            if type(tex) == "string" and tex:lower():find("swatch") then return true end
        end
    end
    return false
end

local done = setmetatable({}, { __mode = "k" })
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] then
            local key = ((KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
            local text = child.GetText and child:GetText()
            local hasText = type(text) == "string" and text ~= ""
            local isDropdown = child:IsObjectType("DropdownButton")
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if IsSwatch(child, key) then
                done[child] = true -- (Farbfeld bleibt)
            elseif type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("Slider") then
                done[child] = true
                if key:find("scroll") then ns.SkinScrollBar(child) else ns.SkinSlider(child) end
            elseif child:IsObjectType("CheckButton") then
                done[child] = true
                ns.SkinCheck(child)
            elseif isDropdown then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("EditBox") then
                done[child] = true
                for _, k in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(child[k]) end
                ns.HideTextures(child)
                ns.Flat(child, C.input, { -4, 0, -2, 0 })
            elseif child:IsObjectType("Button") then
                if hasText then
                    done[child] = true
                    ns.SkinButton(child) -- ("Standard", "Okay", Kategorien, Reiter …)
                    ns.CenterText(child)
                end
            else
                -- Kasten mit Blizzard-Rahmen (Backdrop/NineSlice): flache Fläche mit feinem Rand. Kleine Rahmen
                -- (Zeilen) nur ohne Rahmen
                local w, h = child:GetWidth() or 0, child:GetHeight() or 0
                if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
                local hadBackdrop = child.GetBackdrop and child:GetBackdrop() ~= nil
                if hadBackdrop or type(child.NineSlice) == "table" then
                    ns.HideTextures(child)
                    if w > 60 and h > 40 then ns.Flat(child, C.panel) end
                end
                if depth < 6 then Scan(child, depth + 1) end
            end
        end
    end
end

-- Kopf ("Chat-Einstellungen"): Blizzards Kopfgrafik weg, Titel mittig in unserer Titelleiste
local function SkinHeader(f)
    local header = f.Header or G("ChatConfigFrameHeader")
    if type(header) ~= "table" or Forbidden(header) then return end
    ns.HideTextures(header)
    local title = header.Text or G("ChatConfigFrameHeaderText")
    if title and title.ClearAllPoints then
        title:ClearAllPoints()
        title:SetPoint("CENTER", f, "TOP", 0, -12)
        title:SetParent(f)
        title:SetDrawLayer("OVERLAY", 7)
    end
end

local function SkinChatConfig()
    local f = G("ChatConfigFrame")
    if not f or ns.chatConfigSkinned or Forbidden(f) then return end
    ns.chatConfigSkinned = true
    ns.SkinWindow(f)
    Step("header", function() SkinHeader(f) end)
    Step("scan", function() Scan(f, 1) end)
    ns.Watch(f)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        if type(f.NineSlice) == "table" then ns.Hide(f.NineSlice) end
        pcall(Scan, f, 1)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.chatConfigSkinned or not ns.GetDB().chatConfig or not G("ChatConfigFrame") then return end
    Step("skin", SkinChatConfig)
end)
