-- ForeverSkin – Extra.lua: Flugkarte und Beute-Fenster im Forever-Stil.
--  * Flugkarte (TaxiFrame): flaches Fenster mit Titelleiste; die Karte selbst (Flugpunkte, Routen) bleibt unverändert
--  * Beute (LootFrame): flaches Fenster, jeder Gegenstand ein flacher Knopf (Symbol und Qualitätsfarbe bleiben)
-- Wie überall: Blizzards Grafiken nur unsichtbar, eigene darunter, nichts in Blizzards Tabellen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end

---------------------------------------------------------------------------
-- Flugkarte
---------------------------------------------------------------------------
-- Karten-Texturen erkennen (bleiben sichtbar): Name oder Grafik mit "Map"/"Taxi"
local function MapTextures(frame, keep, depth)
    if not frame or not frame.GetRegions then return keep end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local name = (r:GetName() or ""):lower()
            local tex = r.GetTexture and r:GetTexture()
            local atlas = r.GetAtlas and r:GetAtlas()
            local path = (type(tex) == "string" and tex or "") .. (type(atlas) == "string" and atlas or "")
            path = path:lower()
            if name:find("map") or name:find("taxi") or path:find("taximap") or path:find("taxi") then keep[r] = true end
        end
    end
    if depth < 2 then
        for _, child in ipairs({ frame:GetChildren() }) do MapTextures(child, keep, depth + 1) end
    end
    return keep
end

local function SkinTaxi()
    local f = G("TaxiFrame")
    if not f then return end
    local keep = MapTextures(f, {}, 1)
    for _, key in ipairs({ "TaxiMap", "Map", "MapTexture" }) do
        if type(f[key]) == "table" and f[key].IsObjectType and f[key]:IsObjectType("Texture") then keep[f[key]] = true end
    end
    -- Die Karte ist eine der Grafiken des Fensters (am Namen nicht zu erkennen) – aber mit Abstand die größte. Beim
    -- ersten Öffnen (dann stimmen die Größen) bleibt darum nur die größte Grafik von Fenster und Innenfläche sichtbar,
    -- alle übrigen Rahmenteile werden unsichtbar. Flugrouten und Flugpunkte liegen auf eigenen Ebenen und bleiben.
    local inset = f.Inset or G("TaxiFrameInset")
    local cleaned = false
    local function KeepOnlyMap()
        if cleaned then return end
        local list, largest, area = {}, nil, 0
        for _, holder in ipairs({ f, inset }) do
            if holder and holder.GetRegions then
                for _, r in ipairs({ holder:GetRegions() }) do
                    if r:IsObjectType("Texture") and not ns.IsMine(holder, r) then
                        list[#list + 1] = r
                        local a = (r:GetWidth() or 0) * (r:GetHeight() or 0)
                        if a > area then largest, area = r, a end
                    end
                end
            end
        end
        if not largest or area < 10000 then return end -- Größen noch nicht bekannt: beim nächsten Öffnen
        cleaned = true
        for _, r in ipairs(list) do
            if r ~= largest and not keep[r] then r:SetAlpha(0) end
        end
    end
    -- nur Rahmen, Titel-Hintergrund und Porträt weg (light), den Rest erledigt KeepOnlyMap
    ns.SkinWindow(f, keep, true)
    f:HookScript("OnShow", function() C_Timer.After(0, function() pcall(KeepOnlyMap) end) end)
    if f:IsShown() then pcall(KeepOnlyMap) end
    ns.Watch(f)
end

---------------------------------------------------------------------------
-- Beute
---------------------------------------------------------------------------
local done = setmetatable({}, { __mode = "k" })

-- eine Beute-Zeile (Retail: Element der Liste, Classic: LootButton1-4): flacher Knopf, Symbol bleibt
local function SkinLootRow(row, name)
    if not row then return end
    local icon = row.Item or row.icon or row.Icon or (name and G(name .. "IconTexture"))
    local keep = {}
    if type(icon) == "table" and icon.IsObjectType and icon:IsObjectType("Texture") then keep[icon] = true end
    for _, key in ipairs({ "NameFrame", "QualityStripe", "HighlightNameFrame", "PushedNameFrame", "BorderFrame" }) do
        local t = row[key]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
    end
    if name then ns.Hide(G(name .. "NameFrame")) end
    if done[row] then return end
    done[row] = true
    if row:IsObjectType("Button") then
        ns.Hide(row:GetHighlightTexture())
        ns.Hide(row:GetPushedTexture())
    end
    ns.Flat(row, C.button, 1)
    ns.Hover(row)
end

local function SkinLootRows()
    local f = G("LootFrame")
    if not f then return end
    local box = f.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(function(e) SkinLootRow(e) end) end
    for i = 1, 4 do
        local b = G("LootButton" .. i)
        if b then SkinLootRow(b, "LootButton" .. i) end
    end
end

local function SkinLoot()
    local f = G("LootFrame")
    if not f then return end
    ns.SkinWindow(f)
    for _, n in ipairs({ "LootFramePortraitOverlay", "LootFramePortrait" }) do ns.Hide(G(n)) end
    ns.SkinArrowOnly(G("LootFrameUpButton"), "up")
    ns.SkinArrowOnly(G("LootFrameDownButton"), "down")
    if f.ScrollBar then ns.SkinScrollBar(f.ScrollBar) end
    ns.Watch(f)
    -- Zeilen baut Blizzard bei jeder Beute neu: solange das Fenster offen ist, in jedem Bild prüfen
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function() pcall(SkinLootRows) end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local db = ns.GetDB()
    for _, w in ipairs({ { "taxi", SkinTaxi }, { "loot", SkinLoot } }) do
        if db[w[1]] then
            local ok, err = pcall(w[2])
            if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", w[1], err) end
        end
    end
end)
