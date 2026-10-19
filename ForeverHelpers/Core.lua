-- ForeverHelpers: die kleinen Helfer von Forever Core in einem Addon – Würfel-Fenster (ForeverLoot), Buff-Erinnerung
-- (ForeverBuffs) und Händler (ForeverVendor). Jedes Modul bleibt für sich (eigene Einstellungen ForeverLootDB/
-- ForeverBuffsDB/ForeverVendorDB, eigene Befehle /floot /fbuffs /fvendor, eigene Anmeldung bei /fmove), nur Ordner,
-- Minimap-Knopf und Einstellungsfenster sind gemeinsam: die Einstellungen liegen im gemeinsamen Fenster von
-- Forever Core unter "Helfer".
local ADDON_NAME, root = ...
local UI = ForeverHub.UI
local T = UI.T

---------------------------------------------------------------------------
-- Alte Einzel-Addons (bis 0.44b): laufen sie noch, setzt das jeweilige Modul diesmal aus (sonst doppelt) – und sie
-- werden für das nächste Laden ausgeschaltet. Die Einstellungen gehen nicht verloren (gleiche Namen).
---------------------------------------------------------------------------
root.skip = {}
local OLD = { "ForeverLoot", "ForeverBuffs", "ForeverVendor" }
local oldActive = {}
if C_AddOns and C_AddOns.GetAddOnInfo then
    for _, name in ipairs(OLD) do
        local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, name)
        if ok and reason ~= "MISSING" then
            local okState, state = pcall(C_AddOns.GetAddOnEnableState, name, UnitGUID("player"))
            if okState and type(state) == "number" and state > 0 then
                root.skip[name] = true
                oldActive[#oldActive + 1] = name
                pcall(C_AddOns.DisableAddOn, name)
            end
        end
    end
    if #oldActive > 0 and C_AddOns.SaveAddOns then pcall(C_AddOns.SaveAddOns) end
end
if #oldActive > 0 then
    C_Timer.After(8, function()
        UI.Chat("ForeverHelpers", string.format(T("Die alten Ordner %s sind jetzt Teil von ForeverHelpers und wurden ausgeschaltet – bitte löschen. Nach dem nächsten Neuladen läuft alles über ForeverHelpers (Einstellungen bleiben).",
            "The old folders %s are now part of ForeverHelpers and were turned off – please delete them. After the next reload everything runs through ForeverHelpers (settings are kept)."),
            table.concat(oldActive, ", ")))
    end)
end

---------------------------------------------------------------------------
-- Gemeinsamer Minimap-Knopf: Linksklick = Einstellungen (Helfer), Rechtsklick = alle drei entsperren/sperren.
-- Die Module melden ihre bisherigen Knopf-Angaben mit root.ModuleButton(o) hier an.
---------------------------------------------------------------------------
local modules = {}
function root.ModuleButton(o)
    modules[#modules + 1] = o
    return { UpdatePosition = function() end }
end

local DB_DEFAULT_ANGLE = 250
local function HelperDB()
    if type(_G.ForeverHelpersDB) ~= "table" then _G.ForeverHelpersDB = {} end
    return _G.ForeverHelpersDB
end

local function FirstPage()
    return "ForeverHelpers.loot"
end

local button = UI.MinimapButton({
    name = "ForeverHelpersMinimapButton",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    title = "ForeverHelpers",
    angle = function() return HelperDB().minimapAngle or DB_DEFAULT_ANGLE end,
    setAngle = function(a) HelperDB().minimapAngle = a end,
    onClick = function(self, mouse)
        if mouse == "RightButton" then
            -- jedes Modul schaltet sein eigenes Sperren um (Würfel-Fenster, Buff-Symbole, Händler-Symbol)
            for _, o in ipairs(modules) do
                if o.onClick then pcall(o.onClick, self, "RightButton") end
            end
        else
            UI.ToggleSettings(FirstPage())
        end
    end,
    lines = function()
        return {
            T("Würfel-Fenster, Buff-Erinnerung, Händler", "Loot rolls, buff reminder, vendor"),
            T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Anzeigen entsperren/sperren", "Right-click: unlock/lock displays"),
        }
    end,
})
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() button.UpdatePosition() end)

SLASH_FOREVERHELPERS1 = "/fhelp"
SLASH_FOREVERHELPERS2 = "/foreverhelpers"
SlashCmdList["FOREVERHELPERS"] = function() UI.ToggleSettings(FirstPage()) end
