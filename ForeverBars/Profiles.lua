local addonName, ns = ...
local L = ns.L

-- "Alles zurücksetzen" sowie die Anbindung an die gemeinsame Profil-Verwaltung von ForeverCore.

-- Alle Einstellungen und Positionen auf Standard (gespeicherte Profile bleiben erhalten; Blizzard-Einstellungen
-- wie Tastenbelegung oder "Beim Drücken auslösen" bleiben unverändert)
local KEEP_ON_RESET = {} -- (frueher: eigene Profile; die verwaltet jetzt ForeverCore)

function ns.ResetAllSettings()
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    for key, value in pairs(ns.defaults) do
        if not KEEP_ON_RESET[key] then
            ns.db[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    -- Positionen neu berechnen (Standard-Anordnung)
    for barKey in pairs(ns.db.bars) do ns.GetBarPosition(barKey) end
    ns.RequestLayout()
    ns.UpdateAllButtons()
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    ns.Print(L("RESET_ALL_DONE"))
    if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- Profile: verwaltet ForeverCore fuer alle Forever-Addons gleich (UI.RegisterSettings in Core.lua).
-- Neu gegenueber frueher: jeder Charakter nutzt das gemeinsame Profil oder ein eigenes; Wechseln gilt nach
-- dem Neuladen. Die Funktionen hier behalten ihre Namen, damit das Menue (Options.lua) unveraendert bleibt.
---------------------------------------------------------------------------
local UI = ForeverHub.UI
ns.DEFAULT_PROFILE = UI.DEFAULT_PROFILE

-- Anzeigename (das Standardprofil heißt in jeder Sprache passend)
function ns.ProfileLabel(name)
    if name == ns.DEFAULT_PROFILE then return L("PROFILE_DEFAULT") end
    return name
end

function ns.InitProfiles() end      -- erledigt ForeverCore beim Laden
function ns.SaveActiveProfile() end -- die Einstellungen stehen immer im aktiven Profil

function ns.GetActiveProfile()
    return UI.CurrentProfile(addonName) or ns.DEFAULT_PROFILE
end

-- Standardprofil zuerst, dann alphabetisch
function ns.GetProfileNames()
    return UI.ProfileNames(addonName)
end

function ns.HasProfile(name)
    for _, n in ipairs(UI.ProfileNames(addonName)) do
        if n == name then return true end
    end
    return false
end

-- Neues Profil aus den aktuellen Einstellungen; gilt sofort für diesen Charakter
function ns.SaveProfile(name)
    name = strtrim(name or "")
    if name == "" then return false end
    if not UI.NewProfile(addonName, name) then return false end
    ns.Print(L("PROFILE_SAVED", ns.ProfileLabel(name)))
    return true
end

-- Profil für diesen Charakter wählen; gilt nach dem Neuladen (Knopf im Profil-Fenster von ForeverCore)
function ns.LoadProfile(name)
    if not ns.HasProfile(name) then return end
    UI.UseProfile(addonName, name)
    if UI.ProfilePending(addonName) then
        ns.Print(L("PROFILE_RELOAD", ns.ProfileLabel(name)))
        UI.ShowProfiles()
    end
end

-- Das Standardprofil lässt sich nicht löschen
function ns.DeleteProfile(name)
    if name == ns.DEFAULT_PROFILE then
        ns.Print(L("PROFILE_DEFAULT_KEEP"))
        return
    end
    if UI.DeleteProfile(addonName, name) then
        ns.Print(L("PROFILE_DELETED", name))
        if UI.ProfilePending(addonName) then UI.ShowProfiles() end
    end
end

-- Export/Import: gemeinsames Fenster von ForeverCore (ein Text für alle gewählten Forever-Addons)
function ns.ShowTransferWindow(mode)
    UI.ShowTransfer(mode)
end