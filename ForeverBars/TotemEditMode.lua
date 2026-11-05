-- ForeverBars – TotemEditMode.lua: Totemleiste (Schamane) vor Blizzards Neuordnung der unteren Leisten schützen.
-- Ursache (aufgezeichnet 2026-11-05): Beim Kampfbeginn blendet Blizzard die Begleiterleiste aus; danach ordnet der
-- Bearbeitungsmodus alle unteren Leisten neu (EditModeManager:UpdateBottomActionBarPositions) und setzt dabei die
-- Totemleiste über die Hauptleiste – mitten in der Kampfsperre, ForeverBars darf sie dann nicht zurückholen.
-- Blizzard ordnet aber nur Leisten neu, die im Layout des Bearbeitungsmodus noch "auf dem Standardplatz" stehen.
-- Darum trägt ForeverBars die Totemleiste einmal (außerhalb des Kampfes) über Blizzards Schnittstelle C_EditMode als
-- "vom Spieler verschoben" ein und speichert das Layout. Blizzards Vorlagen ("Modern"/"Klassisch") lassen sich nicht
-- ändern: dann entsteht eine Kopie namens "Forever", die aktiv geschaltet wird (sieht sonst genauso aus).
-- Es wird nichts in Blizzards Tabellen geschrieben – nur die Daten aus C_EditMode.GetLayouts geändert und gespeichert.
local _, ns = ...
local L = ns.L

local LAYOUT_NAME = "Forever"

local function PresetLayouts()
    local manager = _G.EditModePresetLayoutManager
    if manager and manager.GetCopyOfPresetLayouts then
        local ok, presets = pcall(manager.GetCopyOfPresetLayouts, manager)
        if ok and type(presets) == "table" then return presets end
    end
    return {}
end

local function FindTotemEntry(layout, system)
    for _, s in ipairs(layout and layout.systems or {}) do
        if s.system == system then return s end
    end
end

local function Fix()
    if InCombatLockdown() then return end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and Enum and Enum.EditModeSystem) then return end
    local system = Enum.EditModeSystem.TotemActionBar
    if not system then return end
    local _, class = UnitClass("player")
    if class ~= "SHAMAN" then return end
    local cfg = ns.db and ns.db.bars and ns.db.bars.totem
    if not (cfg and cfg.enabled) then return end

    local info = C_EditMode.GetLayouts()
    if type(info) ~= "table" or type(info.layouts) ~= "table" then return end
    local presets = PresetLayouts()
    local numPresets = #presets
    local active = tonumber(info.activeLayout) or 1

    local layout, switchTo, created
    if active > numPresets then
        layout = info.layouts[active - numPresets]
    else
        -- Vorlage aktiv: vorhandene Kopie "Forever" nehmen, sonst eine anlegen
        for i, l in ipairs(info.layouts) do
            if l.layoutName == LAYOUT_NAME then layout, switchTo = l, i + numPresets end
        end
        if not layout then
            local source = presets[active]
            if type(source) ~= "table" then return end
            layout = CopyTable(source)
            layout.layoutName = LAYOUT_NAME
            layout.layoutType = (Enum.EditModeLayoutType and Enum.EditModeLayoutType.Account) or layout.layoutType
            table.insert(info.layouts, layout)
            switchTo, created = #info.layouts + numPresets, true
        end
    end
    local entry = FindTotemEntry(layout, system)
    if not entry then return end
    if entry.isInDefaultPosition == false and not switchTo then return end -- schon eingerichtet

    entry.isInDefaultPosition = false
    -- (die genaue Stelle ist egal: ForeverBars hält die Leiste in ihrem eigenen Halter)
    entry.anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 200 }
    if switchTo then info.activeLayout = switchTo end
    C_EditMode.SaveLayouts(info)
    if switchTo and C_EditMode.SetActiveLayout then pcall(C_EditMode.SetActiveLayout, switchTo) end
    ns.Print(created and L("TOTEM_EDITMODE_NEW") or L("TOTEM_EDITMODE_FIXED"))
    -- Leiste wieder in den Halter (Blizzard wendet das gespeicherte Layout an)
    C_Timer.After(1, function()
        if ns.ApplyLayout and not InCombatLockdown() then pcall(ns.ApplyLayout) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents() -- (einmal je Sitzung reicht)
    -- etwas warten, bis der Bearbeitungsmodus sein Layout geladen hat
    C_Timer.After(4, function()
        if InCombatLockdown() then
            local hub = _G.ForeverHub and _G.ForeverHub.UI
            if hub and hub.AfterCombat then hub.AfterCombat("ForeverBars:totemEditMode", Fix, "ForeverBars") end
            return
        end
        local ok, err = pcall(Fix)
        if not ok then
            local hub = _G.ForeverHub and _G.ForeverHub.UI
            if hub and hub.ReportError then hub.ReportError("ForeverBars", "totemEditMode", err) end
        end
    end)
end)
