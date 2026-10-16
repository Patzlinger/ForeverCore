local addonName, ns = ...

-- Anbindung an ForeverHub (gemeinsame Datei aller Forever-Addons, siehe Shared/ForeverHub.lua im Repository).
-- Sammelknopf an der Minimap und Hub-Fenster (/forever) finden das Addon über seinen Minimap-Knopf
-- "ForeverBarsMinimapButton"; hier meldet es sich nur für den gemeinsamen Verschiebe-Modus (/fmove) an.
-- (SetUnlocked prüft selbst Kampf und Bartender4 und aktualisiert das Menü.)
local hub = _G.ForeverHub
local UI = hub and hub.UI
if UI and UI.RegisterMovable then
    UI.RegisterMovable(addonName, function() return not ns.unlocked end, function(locked)
        if ns.SetUnlocked then ns.SetUnlocked(not locked) end
    end)
end
