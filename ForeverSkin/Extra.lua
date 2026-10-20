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
            -- (auch nicht die per Name erkannten: Rahmenteile heißen ebenfalls "TaxiFrame…")
            if r ~= largest then r:SetAlpha(0) end
        end
    end
    -- nur Rahmen, Titel-Hintergrund und Porträt weg (light), dazu gezielt (laut /fskin taxi in Forever): alle
    -- Rahmenteile "UI-Frame-…" (Kanten, Ecken, Titel) und Blizzards Stein-Hintergrund (Datei 374155, größer als die
    -- Karte – darum lag "größte Grafik = Karte" falsch). Die Karte selbst (z. B. 7961420) und die Routen bleiben.
    local BACKGROUNDS = { [374155] = true }
    local function HideFrameParts()
        for _, holder in ipairs({ f, inset }) do
            if holder and holder.GetRegions then
                for _, r in ipairs({ holder:GetRegions() }) do
                    if r:IsObjectType("Texture") and not ns.IsMine(holder, r) then
                        local atlas = r.GetAtlas and r:GetAtlas()
                        local tex = r.GetTexture and r:GetTexture()
                        if (type(atlas) == "string" and atlas:find("UI%-Frame")) or BACKGROUNDS[tex]
                            or (type(tex) == "string" and tex:find("UI%-Frame")) then
                            r:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end
    ns.SkinWindow(f, keep, true)
    HideFrameParts()
    f:HookScript("OnShow", function() pcall(HideFrameParts) end)
    ns.KeepOnlyMap = KeepOnlyMap -- (alter Versuch, nicht mehr benutzt)
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
    ns.Flat(row, C.button, 1) -- (kein Aufhellen beim Überfahren – nur der Rand in Seltenheitsfarbe, siehe LootHover)
end

-- Beute-Platz einer Zeile (Retail: Element, Classic: LootButton.slot)
local function Slot(row)
    if row.GetSlotIndex then
        local ok, slot = pcall(row.GetSlotIndex, row)
        if ok and slot then return slot end
    end
    return row.slotIndex or row.slot or (row.GetID and row:GetID())
end

-- Maus über einer Zeile: Rand in der Seltenheitsfarbe des Gegenstands, sonst grau (nichts hellt auf)
local overState = setmetatable({}, { __mode = "k" }) -- (eigene Tabelle: nichts in Blizzards Zeilen schreiben)
local function LootHover(row)
    if not done[row] then return end
    local over = row:IsMouseOver() and true or false
    if over == overState[row] then return end
    overState[row] = over
    local c = C.border
    if over then
        local slot = Slot(row)
        local quality = slot and GetLootSlotInfo and select(5, GetLootSlotInfo(slot))
        if type(quality) == "number" and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            c = { r, g, b }
        else
            c = C.accent
        end
    end
    ns.EdgeColor(row, c, 1)
end

local function SkinLootRows()
    local f = G("LootFrame")
    if not f then return end
    local box = f.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(function(e) SkinLootRow(e) LootHover(e) end) end
    for i = 1, 4 do
        local b = G("LootButton" .. i)
        if b then
            SkinLootRow(b, "LootButton" .. i)
            LootHover(b)
        end
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

-- Prüfbefehl /fskin taxi: welche Grafiken hat die Flugkarte (Name, Datei/Atlas, Größe, Sichtbarkeit) – im Chat
function ns.DumpTaxi()
    local f = G("TaxiFrame")
    if not (f and f:IsShown()) then
        ns.UI.Chat("ForeverSkin", ns.T("Erst die Flugkarte öffnen, dann /fskin taxi.", "Open the flight map first, then /fskin taxi."))
        return
    end
    local n = 0
    local function Dump(holder, label, depth)
        for _, r in ipairs({ holder:GetRegions() }) do
            if r:IsObjectType("Texture") and n < 40 then
                n = n + 1
                local tex = r.GetTexture and r:GetTexture()
                local atlas = r.GetAtlas and r:GetAtlas()
                local layer = r:GetDrawLayer()
                ns.UI.Chat("ForeverSkin", string.format("%s %s | %s | %dx%d | %s | a=%.1f%s", label, r:GetName() or "-",
                    tostring(atlas or tex), r:GetWidth() or 0, r:GetHeight() or 0, tostring(layer), r:GetAlpha() or 0,
                    ns.IsMine(holder, r) and " (FS)" or ""))
            end
        end
        if depth < 2 then
            for i, child in ipairs({ holder:GetChildren() }) do
                if not child:IsObjectType("Button") then
                    Dump(child, label .. ">" .. (child:GetName() or ("#" .. i)), depth + 1)
                end
            end
        end
    end
    Dump(f, "TaxiFrame", 1)
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
