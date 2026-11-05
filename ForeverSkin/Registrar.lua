-- ForeverSkin – Registrar.lua: Gildenregistrator (GuildRegistrarFrame – "Verfügbare Dienste", Satzung kaufen) im
-- Forever-Stil wie das NPC-Gespräch (Windows.lua): flache Fläche, Titelleiste mit goldener Linie, Visitenkarte des NPCs
-- (runder Rahmen, Name), Inhalt in unserem Kasten statt Pergament, unten eine Knopfleiste. Texte hell, Überschriften
-- gold; "Kaufen"/"Abbrechen" flach, das Namensfeld flach, die Laufleiste gold. Die Auswahl-Zeilen ("Eine
-- Gildensatzung erwerben") bleiben Text-Zeilen wie im Gespräch. Teile werden nach Art gesucht.
local _, ns = ...
local C = ns.C

local TEXT = { 0.9, 0.9, 0.9 }
local CARD = 87   -- Kasten beginnt unter der Visitenkarte (wie beim NPC-Gespräch)
local FOOTER = 30

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

local function FlatButton(b)
    ns.SkinButton(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

-- Schrift hell (Pergament-Schrift ist dunkel), Überschriften gold; dunkle Farbcodes im Text aufhellen
local function Lighten(fs)
    local name = (fs:GetName() or ""):lower()
    local heading = name:find("available") or name:find("title") or name:find("header")
    local r, g, b = fs:GetTextColor()
    if heading then
        fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    elseif r and (r + g + b) < 1.6 then
        fs:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    end
    local text = fs:GetText()
    local light = ns.LightenCodes(text)
    if light ~= text then fs:SetText(light) end
end

-- Auswahl-Zeile (Knopf mit Symbol links, ohne Knopf-Grafik): nur der Text hell
local function IsOptionLine(b)
    local name = b:GetName() or ""
    return name:find("GuildRegistrarButton%d") ~= nil or (b:GetWidth() or 0) > 200
end

local function Scan(frame, depth)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("FontString") then Lighten(r) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.Track) == "table" or (child:IsObjectType("Slider") and (child:GetName() or ""):find("ScrollBar")) then
                if not done[child] then done[child] = true ns.SkinScrollBar(child) end
            elseif child:IsObjectType("EditBox") then
                if not done[child] then
                    done[child] = true
                    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(child[key]) end
                    ns.HideTextures(child)
                    ns.Flat(child, C.input, { -4, 0, 0, 0 })
                end
            elseif child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                if IsOptionLine(child) then
                    local fs = child.GetFontString and child:GetFontString()
                    if fs then Lighten(fs) end
                elseif type(text) == "string" and text ~= "" and not done[child] and not (child:GetName() or ""):lower():find("money") then
                    done[child] = true
                    FlatButton(child)
                end
            else
                -- Pergament und Rahmen-Bilder der Unterflächen weg (Texte bleiben)
                if not (child:GetName() or ""):lower():find("money") then ns.HideTextures(child) end
                if depth < 4 then Scan(child, depth + 1) end
            end
        end
    end
end

-- Text samt Laufleiste in den Kasten (unter die Visitenkarte, über die Knopfleiste)
local function Place(f)
    local function Walk(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) and child:IsShown() then
                if child:IsObjectType("ScrollFrame") then
                    ns.Fit(f, child, CARD + 8, FOOTER + 14)
                    local bar = child.ScrollBar or (child:GetName() and _G[child:GetName() .. "ScrollBar"])
                    if bar then ns.Fit(f, bar, CARD + 8, FOOTER + 14, child) end
                elseif depth < 2 then
                    Walk(child, depth + 1)
                end
            end
        end
    end
    Walk(f, 1)
end

local skinned
local function SkinRegistrar()
    local f = _G.GuildRegistrarFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    ns.ContentBox(f, FOOTER, CARD)
    pcall(Scan, f, 1)
    ns.Watch(f)
    ns.Scaled(f)
    local function Card()
        ns.NpcCard(f, "npc", ns.T("Gilde", "Guild"), function() return ns.T("Gildenregistrator", "Guild registrar") end)
    end
    f:HookScript("OnShow", function(self)
        pcall(Card)
        pcall(Scan, self, 1)
        C_Timer.After(0, function()
            pcall(Scan, self, 1)
            pcall(Place, self)
        end)
    end)
    -- Wechsel zwischen "Verfügbare Dienste" und "Satzung kaufen": die Unterflächen zeigen sich neu
    for _, child in ipairs({ f:GetChildren() }) do
        if not Forbidden(child) and not child:IsObjectType("Button") then
            child:HookScript("OnShow", function()
                C_Timer.After(0, function()
                    pcall(Scan, f, 1)
                    pcall(Place, f)
                end)
            end)
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().registrar then return end
    if _G.GuildRegistrarFrame and not skinned then
        local ok, err = pcall(SkinRegistrar)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "registrar", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
