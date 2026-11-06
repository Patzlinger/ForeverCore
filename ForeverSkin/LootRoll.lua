-- ForeverSkin – LootRoll.lua: Würfelfenster bei Gruppenbeute (GroupLootFrame1–4: Bedarf / Gier / Passen) im
-- Forever-Stil (docs/Fenster-Stil.md): flache dunkle Fläche mit feinem Rand in der Farbe der Gegenstandsqualität,
-- Symbol mit feinem Rand, Namensfeld ohne Blizzards Kasten, die Zeitleiste flach und gold. Die Würfel-, Münz- und
-- Passen-Knöpfe bleiben Blizzards (sie sind die Auswahl). Das Ergebnis-Fenster der Würfe ist ForeverLoot
-- (ForeverHelpers). Nur Grafiken unsichtbar und eigene Flächen darunter – Klicks und Würfeln bleiben unberührt.
local _, ns = ...
local C = ns.C

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

-- Rand in der Farbe der Gegenstandsqualität (grün, blau, lila …); unbekannt = grau
local function QualityEdge(frame)
    local rollID = frame.rollID
    local quality
    if rollID and GetLootRollItemInfo then
        local ok, _, _, _, q = pcall(GetLootRollItemInfo, rollID)
        if ok then quality = q end
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        ns.EdgeColor(frame, { color.r, color.g, color.b }, 0.9)
    else
        ns.EdgeColor(frame, C.border, 1)
    end
end

local function SkinTimer(bar)
    if type(bar) ~= "table" or done[bar] or not bar.GetStatusBarTexture then return end
    done[bar] = true
    local fill = bar:GetStatusBarTexture()
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= fill then r:SetAlpha(0) end
    end
    ns.Flat(bar, C.input, -1)
    if fill then
        fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        bar:SetStatusBarColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
    end
end

local function SkinRoll(frame)
    if not frame or Forbidden(frame) then return end
    if not done[frame] then
        done[frame] = true
        ns.HideTextures(frame)
        for _, key in ipairs({ "Border", "NineSlice", "Background", "BG", "NameFrame", "Corner", "Decoration" }) do
            local part = frame[key]
            if type(part) == "table" then
                if part.IsObjectType and part:IsObjectType("Texture") then part:SetAlpha(0) else ns.HideTextures(part) end
            end
        end
        local name = frame:GetName()
        if name then
            for _, suffix in ipairs({ "SlotTexture", "NameFrame", "Decoration", "Corner", "Background" }) do
                local t = _G[name .. suffix]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
        end
        ns.Flat(frame, C.background)
        -- Symbol: feiner Rand dahinter (das Symbol selbst bleibt)
        local iconFrame = frame.IconFrame or (name and _G[name .. "IconFrame"])
        if type(iconFrame) == "table" and not Forbidden(iconFrame) then
            local icon = iconFrame.Icon or (iconFrame.GetName and iconFrame:GetName() and _G[iconFrame:GetName() .. "Icon"])
            ns.HideTextures(iconFrame, type(icon) == "table" and { [icon] = true } or nil)
            if type(iconFrame.Border) == "table" then iconFrame.Border:SetAlpha(0) end
            ns.Flat(iconFrame, C.input, -1)
        end
        SkinTimer(frame.Timer or (name and _G[name .. "Timer"]))
    end
    QualityEdge(frame)
end

local hooked = setmetatable({}, { __mode = "k" })
local function Setup()
    for i = 1, 8 do
        local f = _G["GroupLootFrame" .. i]
        if f and not hooked[f] and not Forbidden(f) then
            hooked[f] = true
            f:HookScript("OnShow", function(self)
                local ok, err = pcall(SkinRoll, self)
                if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "lootroll", err) end
            end)
            if f:IsShown() then pcall(SkinRoll, f) end
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("START_LOOT_ROLL")
events:SetScript("OnEvent", function()
    if not ns.GetDB().lootroll then return end
    Setup()
    -- (Blizzard füllt das Fenster beim Würfelstart: Qualitätsfarbe danach nachziehen)
    C_Timer.After(0, function()
        for i = 1, 8 do
            local f = _G["GroupLootFrame" .. i]
            if f and f:IsShown() and done[f] then pcall(QualityEdge, f) end
        end
    end)
end)
