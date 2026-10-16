local addonName, ns = ...

-- Anbindung an ForeverHub (gemeinsame Datei aller Forever-Addons, siehe Shared/ForeverHub.lua im Repository).
-- Sammelknopf an der Minimap und Hub-Fenster (/forever) finden das Addon über seinen Minimap-Knopf
-- "ForeverQuestsMinimapButton". Hier: gemeinsamer Verschiebe-Modus (/fmove) und gemeinsame Sprachwahl.
local hub = _G.ForeverHub
local UI = hub and hub.UI
if not UI then return end

if UI.RegisterMovable then
    UI.RegisterMovable(addonName, function() return not ns.unlocked end, function(locked)
        if ns.SetUnlocked then ns.SetUnlocked(not locked) end
        if ns.RefreshOptions then ns.RefreshOptions() end
    end)
end

-- Sprache: gilt für alle Forever-Addons (ForeverHubDB.language). Die Auswahl im ForeverQuests-Menü
-- bleibt und schreibt in die gemeinsame Einstellung; ForeverQuests selbst wechselt sofort, die anderen
-- Forever-Addons nach /reload.
if UI.GetLanguage then
    ns.GetLanguage = UI.GetLanguage

    local function HubDB()
        if type(_G.ForeverHubDB) ~= "table" then _G.ForeverHubDB = {} end
        return _G.ForeverHubDB
    end

    -- Menü-Auswahl an die gemeinsame Einstellung angleichen (vor dem ersten Öffnen des Menüs)
    local sync = CreateFrame("Frame")
    sync:RegisterEvent("PLAYER_LOGIN")
    sync:SetScript("OnEvent", function()
        if ns.db then ns.db.language = HubDB().language or "AUTO" end
    end)

    local changed = ns.OnLanguageChanged
    ns.OnLanguageChanged = function(...)
        local language = ns.db and ns.db.language
        HubDB().language = (language == "deDE" or language == "enUS") and language or nil
        if changed then return changed(...) end
    end
end
