-- ForeverMinimap (Prototyp): Blizzards Minimap im Forever-Core-UI-Stil – rund oder eckig, schlichter Rahmen,
-- schmale Leiste mit Zone, Uhr und Koordinaten, Knoepfe nur bei Bedarf.
-- Core.lua: Einstellungen, Start, Chatbefehl
--
-- Grundsatz: Die Blizzard-Minimap bleibt die Minimap (Pings, Verfolgung, Zoom, Bearbeitungsmodus fuer Position und
-- Groesse funktionieren unveraendert). ForeverMinimap
--   * aendert nur die Form (SetMaskTexture – das macht Blizzard selbst genauso) und legt eigene Flaechen daneben,
--   * blendet Blizzards Knoepfe nur optisch aus (Alpha 0 per UI.HideBlizzard, nie Hide/SetParent/SetScript),
--   * ersetzt keine Blizzard-Funktionen; eigene Knoepfe rufen Blizzards Funktionen auf (Kalender, Uhr, Verfolgung).
local ADDON_NAME, ns = ...

local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua in ForeverCore)
ns.UI = UI
local T = UI.T
ns.T = T

---------------------------------------------------------------------------
-- Einstellungen (SavedVariables, Profile verwaltet ForeverCore)
---------------------------------------------------------------------------
ns.DEFAULTS = {
    -- Form und Rahmen
    shape = "SQUARE",        -- "SQUARE" (eckig) oder "ROUND" (rund)
    border = true,           -- feiner Rahmen um Minimap und Leiste
    mapScale = 113,          -- Kartengroesse in % von Blizzards Minimap (198 px); Position/Gesamtgroesse: Bearbeitungsmodus
    -- Leiste
    bar = true,              -- Leiste mit Zonenname
    barPosition = "TOP",     -- "TOP" (ueber der Minimap) oder "BOTTOM" (darunter)
    clock = true,            -- Uhr in der Leiste
    clockSource = "LOCAL",   -- "LOCAL" (Ortszeit des Rechners) oder "SERVER" (Serverzeit)
    clock24 = true,          -- 24 Stunden (aus: 12 Stunden mit AM/PM)
    restInfo = true,         -- im Ruhegebiet (Stadt, Gasthaus) dezentes "zZ" hinter dem Namen
    durability = true,       -- Amboss-Symbol in der Leiste, wenn ein Ausruestungsteil unter 30 % faellt
    queueDock = true,        -- Warteschlangen-Auge unten rechts in der Karte (solange ForeverBars es nicht selbst fuehrt)
    coords = true,           -- Koordinaten (nur draussen; in Instanzen gibt es keine)
    difficulty = true,       -- in Instanzen: Schwierigkeit (z. B. "Heroisch")
    barClickMap = true,      -- Klick auf den Zonennamen oeffnet die Weltkarte
    -- Knoepfe (ab Version 2: senkrechte Knopfleiste neben der Karte)
    strip = "LEFT",          -- Knopfleiste "LEFT"/"RIGHT" neben der Minimap oder "OFF" (Knoepfe am Rand bleiben, wo sie sind)
    stripMouseover = false,  -- an: Knopfleiste nur, solange die Maus ueber Minimap/Leisten ist; Standard: immer sichtbar
    stripAlpha = 50,         -- Deckkraft der Flaeche hinter den Knoepfen in % (Knoepfe selbst bleiben voll sichtbar)
    toolsInBar = true,       -- eigene Knoepfe (Post, Verfolgung, Kalender, Einstellungen) oben in der Leiste statt seitlich
    squareForeign = true,    -- Minimap-Knoepfe anderer Addons im gleichen eckigen Look wie die eigenen
    hideBlizzard = true,     -- Blizzards Kopfzeile, Rahmen und Knoepfe ausblenden (Ersatz: Leiste und eigene Knoepfe)
    -- Komfort
    rightClickTracking = true, -- Rechtsklick auf die Minimap: Verfolgung (Kraeuter, Erze, Personen …)
    autoZoom = true,         -- nach 10 Sekunden wieder auf die Grundstufe zoomen
    cityZoom = true,         -- in Staedten und Gasthaeusern (Ruhegebiet) naeher heran
    cityZoomLevel = 2,       -- Zoomstufe dort (0 = ganz weit, 5 = ganz nah)
    pingNames = true,        -- beim Pingen kurz zeigen, wer gepingt hat
    auraBesideMap = true,    -- Blizzards Buff-/Debuff-Leiste neben die Minimap (solange im Bearbeitungsmodus nicht verschoben)
    minimapAngle = 190,
    locked = true,           -- Karte im Verschiebe-Modus (/fmove) verschiebbar, wenn entsperrt
    pos = nil,               -- gemerkte Lage { links, oben } (nil = Blizzards Lage)
}

local function FillDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil and value ~= nil then
            target[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
end

function ns.GetDB()
    if type(_G.ForeverMinimapDB) ~= "table" then _G.ForeverMinimapDB = {} end
    FillDefaults(_G.ForeverMinimapDB, ns.DEFAULTS)
    return _G.ForeverMinimapDB
end

function ns.Chat(text) UI.Chat(ADDON_NAME, text) end
function ns.Safe(where, fn) return UI.Safe(ADDON_NAME, where, fn) end

-- Gesperrte Werte (Kampf, "secret values") nie anfassen
local canaccessvalue = _G.canaccessvalue
function ns.CanRead(...)
    if not canaccessvalue then return true end
    return canaccessvalue(...)
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", ns.Safe(T("Start", "Start"), function()
    ns.GetDB()
    if ns.SetupMap then ns.SetupMap() end
    if ns.SetupOptions then ns.SetupOptions() end
    if ns.SetupMove then ns.SetupMove() end
end))

---------------------------------------------------------------------------
-- Verschieben (Verschiebe-Modus /fmove): Solange entsperrt, liegt ein Griff über der Karte (gelber Rahmen und
-- Rechtsklick = Einstellungen kommen vom Hub). Gezogen wird Blizzards MinimapCluster; die Lage merkt sich ForeverMinimap
-- (ForeverMinimapDB.pos) und stellt sie nach Blizzards Anordnen (Bearbeitungsmodus, Anmelden) wieder her.
-- /fmm resetpos vergisst sie (danach /reload: es gilt wieder Blizzards Lage).
---------------------------------------------------------------------------
function ns.SetupMove()
    local mc, map = _G.MinimapCluster, _G.Minimap
    if not (mc and map and UI.RegisterMovable) then return end
    local handle = CreateFrame("Frame", "ForeverMinimapMoveHandle", UIParent)
    handle:SetFrameStrata("FULLSCREEN")
    handle:SetAllPoints(map)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:Hide()
    if UI.AddMover then UI.AddMover(handle, ADDON_NAME) end

    local function Apply()
        local d = ns.GetDB()
        if not d.pos or ns.moving or ns.placing or InCombatLockdown() then return end
        ns.placing = true
        mc:ClearAllPoints()
        mc:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.pos[1], d.pos[2])
        ns.placing = false
        if UI.Fire then UI.Fire("ForeverMinimap.Layout") end
    end
    -- Blizzard ordnet die Karte neu (Bearbeitungsmodus, Anmelden): unsere Lage wieder setzen
    hooksecurefunc(mc, "SetPoint", function()
        if not ns.placing and not ns.moving and ns.GetDB().pos then C_Timer.After(0, Apply) end
    end)
    C_Timer.After(1, Apply)
    C_Timer.After(4, Apply)

    handle:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        ns.moving = true
        mc:SetMovable(true)
        mc:StartMoving()
        if UI.BeginDrag then UI.BeginDrag(handle, { snap = false }) end
    end)
    handle:SetScript("OnDragStop", function()
        if not ns.moving then return end
        mc:StopMovingOrSizing()
        pcall(mc.SetUserPlaced, mc, false) -- Lage merkt sich ForeverMinimap, nicht Blizzards Layout-Datei
        if UI.EndDrag then UI.EndDrag() end
        ns.moving = false
        local left, top = mc:GetLeft(), mc:GetTop()
        if left and top then ns.GetDB().pos = { math.floor(left + 0.5), math.floor(top + 0.5) } end
        if UI.Fire then UI.Fire("ForeverMinimap.Layout") end
    end)

    local function Show() handle:SetShown(not ns.GetDB().locked and not InCombatLockdown()) end
    UI.RegisterMovable(ADDON_NAME, function() return ns.GetDB().locked end, function(locked)
        ns.GetDB().locked = locked and true or false
        Show()
    end)
    local combat = CreateFrame("Frame")
    combat:RegisterEvent("PLAYER_REGEN_DISABLED")
    combat:SetScript("OnEvent", function() ns.GetDB().locked = true handle:Hide() end)
    function ns.ResetMovePos()
        ns.GetDB().pos = nil
        ns.Chat(T("Lage vergessen – /reload, dann gilt wieder Blizzards Lage.", "Position forgotten – /reload, then Blizzard's position applies again."))
    end
end

---------------------------------------------------------------------------
-- Chatbefehl
---------------------------------------------------------------------------
SLASH_FOREVERMINIMAP1 = "/fmm"
SLASH_FOREVERMINIMAP2 = "/foreverminimap"
SlashCmdList["FOREVERMINIMAP"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "square" or msg == "eckig" then
        ns.GetDB().shape = "SQUARE"
        if ns.ApplyAll then ns.ApplyAll() end
    elseif msg == "resetpos" then
        if ns.ResetMovePos then ns.ResetMovePos() end
    elseif msg == "round" or msg == "rund" then
        ns.GetDB().shape = "ROUND"
        if ns.ApplyAll then ns.ApplyAll() end
    else
        if ns.ToggleOptions then ns.ToggleOptions() end
    end
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = ADDON_NAME, sv = "ForeverMinimapDB", defaults = ns.DEFAULTS, version = 4,
    -- Version 2: statt "buttons" (Leiste/links/rechts) eine senkrechte Knopfleiste
    -- Version 3: Knopfleiste standardmaessig immer sichtbar (vorher nur bei Maus ueber der Minimap)
    -- Version 4: eigene Knoepfe (Post, Verfolgung, Kalender, Einstellungen) standardmaessig oben in der Leiste –
    --            einmalig auch fuer bestehende Profile (Version 2 hatte sie seitlich gestellt)
    migrate = function(data, from)
        if from < 2 then
            data.strip = data.buttons == "RIGHT" and "RIGHT" or "LEFT"
            data.stripMouseover = data.buttonsMouseover ~= false
            data.buttons, data.buttonsMouseover, data.edgeMouseover = nil, nil, nil
        end
        if from < 3 then
            data.stripMouseover = false
        end
        if from < 4 then
            data.toolsInBar = true
        end
    end })
