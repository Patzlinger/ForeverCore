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

-- Inhalt in den Kasten (unter die Visitenkarte, über die Knopfleiste): alle Inhalts-Flächen direkt am Fenster
-- (Begrüßung, Kaufen-Seite, Laufbereich) – nicht Titel, Rahmen, Knöpfe; dazu die Laufleisten
local SKIP_KEYS = { TitleContainer = true, PortraitContainer = true, NineSlice = true, Inset = true }
local function Place(f, top)
    top = top or CARD
    local skip = {}
    for key in pairs(SKIP_KEYS) do if type(f[key]) == "table" then skip[f[key]] = true end end
    for _, child in ipairs({ f:GetChildren() }) do
        if not Forbidden(child) and not skip[child] and child:IsShown() and not child:IsObjectType("Button") then
            ns.Fit(f, child, top + 8, FOOTER + 14)
        end
    end
    local function Bars(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) and child:IsShown() then
                if child:IsObjectType("Slider") or type(child.Track) == "table" then
                    ns.Fit(f, child, top + 8, FOOTER + 14)
                elseif depth < 3 then
                    Bars(child, depth + 1)
                end
            end
        end
    end
    Bars(f, 1)
end

-- Blizzards Titel (NPC-Name oben in der Leiste) weg – der Name steht in unserer Visitenkarte; in der Leiste nur
-- unsere Beschriftung
local function HideTitle(f)
    local name = f:GetName()
    if name then
        for _, suffix in ipairs({ "NpcNameText", "TitleText", "NpcName" }) do ns.Hide(_G[name .. suffix]) end
    end
    if f.TitleContainer then ns.Hide(f.TitleContainer) end
    if f.TitleText then ns.Hide(f.TitleText) end
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
        HideTitle(f)
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

-- Gildenurkunde (PetitionFrame – Satzung benutzen, Unterschriften sammeln): gleich gebaut wie der Registrator, aber
-- ohne NPC-Visitenkarte; Gildenname, Gildenmeister, Mitglieder als Überschriften gold, Namen hell, Knöpfe flach
local PETITION_TOP = 31 -- Kasten direkt unter der Titelleiste
local petitionSkinned
local function SkinPetition()
    local f = _G.PetitionFrame
    if not f or petitionSkinned or Forbidden(f) then return end
    petitionSkinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    ns.ContentBox(f, FOOTER, PETITION_TOP)
    pcall(Scan, f, 1)
    ns.Watch(f)
    ns.Scaled(f)
    f:HookScript("OnShow", function(self)
        pcall(Scan, self, 1)
        C_Timer.After(0, function()
            pcall(Scan, self, 1) -- (Blizzard füllt Namen und Unterschriften beim Öffnen)
            pcall(Place, self, PETITION_TOP)
        end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PETITION_SHOW")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().registrar then return end
    if _G.GuildRegistrarFrame and not skinned then
        local ok, err = pcall(SkinRegistrar)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "registrar", err) end
    end
    if _G.PetitionFrame and not petitionSkinned then
        local ok, err = pcall(SkinPetition)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "petition", err) end
    end
    if skinned and petitionSkinned then self:UnregisterAllEvents() end
end)
