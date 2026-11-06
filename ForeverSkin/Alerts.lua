-- ForeverSkin – Alerts.lua: Beute-Meldungen am unteren Bildschirmrand ("Ihr habt erhalten: …", besserer Gegenstand,
-- erhaltenes Gold) im Forever-Stil (docs/Fenster-Stil.md): flache dunkle Fläche mit goldener Linie oben und feinem
-- Rand in der Qualitätsfarbe des Gegenstands; Symbol mit feinem Rand, Blizzards Rahmen, Leuchten und Glanz weg.
-- Die Meldungen kommen aus Blizzards Meldungssystem (Vorlagen, immer wieder verwendet) – darum hängen wir uns an deren
-- Einrichtung (…_SetUp) an und gestalten jede Meldung beim ersten Mal um; die Qualitätsfarbe bei jeder Meldung neu.
-- Nur Grafiken unsichtbar und eigene Flächen darunter.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local SETUPS = { "LootWonAlertFrame_SetUp", "LootUpgradeAlertFrame_SetUp", "MoneyWonAlertFrame_SetUp" }

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

-- Symbole, die bleiben sollen (Gegenstand, Münze): direkt am Fenster oder im Gegenstands-Unterrahmen
local function IconsOf(frame)
    local keep = {}
    for _, obj in ipairs({ frame, frame.lootItem or false }) do
        if obj then
            for _, key in ipairs({ "Icon", "icon", "MoneyIcon" }) do
                if type(obj[key]) == "table" and obj[key].IsObjectType then keep[obj[key]] = true end
            end
        end
    end
    return keep
end

local function Skin(frame)
    if not frame or Forbidden(frame) then return end
    if not done[frame] then
        done[frame] = true
        local keep = IconsOf(frame)
        ns.HideTextures(frame, keep)
        -- Leuchten/Glanz (eigene Unterrahmen oder Grafiken) und der Gegenstands-Unterrahmen ohne Rahmen
        for _, key in ipairs({ "glow", "shine", "Glow", "Shine", "IconBorder", "BGAtlas", "Background", "SpecRing" }) do
            local part = frame[key]
            if type(part) == "table" and part.SetAlpha then part:SetAlpha(0) end
        end
        local item = frame.lootItem
        if type(item) == "table" and not Forbidden(item) then
            ns.HideTextures(item, keep)
            if type(item.IconBorder) == "table" then item.IconBorder:SetAlpha(0) end
            ns.Flat(item, C.input, -1)
        end
        ns.Flat(frame, C.background, 6)
        local line = frame:CreateTexture(nil, "BORDER", nil, -6)
        line:SetTexture(WHITE)
        line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
        line:SetPoint("TOPLEFT", 7, -6)
        line:SetPoint("TOPRIGHT", -7, -6)
        ns.OnePixel(line, true)
    end
    -- Blizzard blendet Leuchten/Glanz bei jeder Meldung neu ein
    for _, key in ipairs({ "glow", "shine", "Glow", "Shine" }) do
        local part = frame[key]
        if type(part) == "table" and part.SetAlpha then part:SetAlpha(0) end
    end
end

local function QualityEdge(frame, itemLink)
    local quality
    if type(itemLink) == "string" and C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemLink)
        if ok then quality = q end
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then ns.EdgeColor(frame, { color.r, color.g, color.b }, 0.9) else ns.EdgeColor(frame, C.border, 1) end
end

local hooked = false
local function Setup()
    if hooked then return end
    local any = false
    for _, fn in ipairs(SETUPS) do
        if type(_G[fn]) == "function" then
            any = true
            hooksecurefunc(fn, function(frame, itemLink)
                local ok, err = pcall(function()
                    Skin(frame)
                    QualityEdge(frame, itemLink)
                end)
                if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "alerts", err) end
            end)
        end
    end
    hooked = any
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().alerts then return end
    Setup()
    if hooked then self:UnregisterAllEvents() end
end)
