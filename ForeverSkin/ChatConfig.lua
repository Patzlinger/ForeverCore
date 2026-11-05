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

local KeyOf = ns.KeyOf -- (gemeinsam in Core.lua)

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

-- Blizzards Backdrop (Rahmen samt Hintergrund) ganz entfernen und entfernt halten: Blizzard legt ihn beim Öffnen neu
-- an (darum vorher nur unsichtbar gemacht und doch wieder da). Sperre gegen Schleifen beim eigenen Entfernen
local cleared = setmetatable({}, { __mode = "k" })
local function NoBackdrop(frame)
    if not frame.ClearBackdrop and not frame.SetBackdrop then return end
    local function Clear()
        if cleared[frame] == "busy" then return end
        cleared[frame] = "busy"
        if frame.ClearBackdrop then pcall(frame.ClearBackdrop, frame) else pcall(frame.SetBackdrop, frame, nil) end
        cleared[frame] = true
    end
    Clear()
    if not cleared.hooked then cleared.hooked = {} end
    if not cleared.hooked[frame] then
        cleared.hooked[frame] = true
        for _, method in ipairs({ "SetBackdrop", "ApplyBackdrop" }) do
            if type(frame[method]) == "function" then hooksecurefunc(frame, method, Clear) end
        end
    end
end

-- Zierrahmen am Fenster ("Border" u. Ä.: Unter-Rahmen nur aus Grafiken, ohne Maus, fast so groß wie das Fenster) –
-- weg; der alte goldbraune Rahmen hatte weder Backdrop noch NineSlice
local function HideBorders(f)
    if type(f.Border) == "table" and f.Border.GetRegions and not Forbidden(f.Border) then
        ns.HideTextures(f.Border)
        ns.Hide(f.Border)
    end
    local fw, fh = f:GetWidth() or 0, f:GetHeight() or 0
    for _, child in ipairs({ f:GetChildren() }) do
        if not Forbidden(child) and not child:IsMouseEnabled() and #{ child:GetChildren() } == 0
            and (child:GetWidth() or 0) >= fw * 0.9 and (child:GetHeight() or 0) >= fh * 0.9 then
            ns.HideTextures(child)
        end
    end
end

-- Knöpfe unten ("Chat: Standard", "Fenster zurücksetzen", "OK"): BUTTON_IN nach innen, BUTTON_UP höher; hängt ein
-- Knopf rechts an einem anderen, bekommt er BUTTON_GAP Luft dazu – einmal je Knopf
local BUTTON_IN, BUTTON_UP, BUTTON_GAP = 6, -4, 4 -- (BUTTON_UP negativ = tiefer: unter der goldenen Linie)
local nudged = setmetatable({}, { __mode = "k" })
local function NudgeBottom(f, b)
    if nudged[b] or b:GetNumPoints() ~= 1 or not (b:GetCenter() and f:GetCenter()) then return end
    nudged[b] = true
    local p, rel, rp, x, y = b:GetPoint(1)
    if rel and rel ~= f and rel.IsObjectType and rel:IsObjectType("Button") then
        b:SetPoint(p, rel, rp, (x or 0) + BUTTON_GAP, y or 0) -- (wandert mit dem Knopf davor mit)
    else
        local inward = b:GetCenter() < f:GetCenter() and BUTTON_IN or -BUTTON_IN
        b:SetPoint(p, rel, rp, (x or 0) + inward, (y or 0) + BUTTON_UP)
    end
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
                    -- Kategorien links ("Chat", "Channels", "Anderes") liegen dicht übereinander: Fläche oben und
                    -- unten je 1 schmaler – so entsteht Luft dazwischen
                    if key:find("category") then ns.Flat(child, C.button, { 4, 2, 4, 2 }) end
                    ns.CenterText(child)
                end
                -- Knöpfe ganz unten am Fenster: nach innen und höher
                local f = G("ChatConfigFrame")
                if f and child:GetBottom() and f:GetBottom() and child:GetBottom() - f:GetBottom() < 30 then
                    NudgeBottom(f, child)
                end
            else
                -- Kasten mit Blizzard-Rahmen (Backdrop/NineSlice): flache Fläche mit feinem Rand. Kleine Rahmen
                -- (Zeilen) nur ohne Rahmen
                local w, h = child:GetWidth() or 0, child:GetHeight() or 0
                if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
                local hadBackdrop = child.GetBackdrop and child:GetBackdrop() ~= nil
                if hadBackdrop or type(child.NineSlice) == "table" then
                    NoBackdrop(child)
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
    Step("backdrop", function() NoBackdrop(f) end)
    ns.SkinWindow(f)
    Step("header", function() SkinHeader(f) end)
    Step("borders", function() HideBorders(f) end)
    Step("scan", function() Scan(f, 1) end)
    ns.ContentBox(f, 32, nil, true) -- (Fußleiste mit goldener Linie hinter den Knöpfen unten)
    ns.Watch(f)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        if type(f.NineSlice) == "table" then ns.Hide(f.NineSlice) end
        pcall(NoBackdrop, f)
        pcall(HideBorders, f)
        pcall(ns.HideTextures, f) -- (unsere eigenen Flächen bleiben – HideTextures lässt sie aus)
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
