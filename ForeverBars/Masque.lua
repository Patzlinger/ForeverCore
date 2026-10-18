local addonName, ns = ...

-- Masque-Unterstützung (optional): Ist das Addon Masque installiert, melden sich alle Knöpfe von ForeverBars dort in
-- der Gruppe "Forever Core › ForeverBars" an. Solange Masque diese Gruppe gestaltet, überlässt ForeverBars ihm Rand,
-- Hintergrund, Symbol-Zuschnitt und Leuchten (Texte wie Tastenbelegung bleiben bei uns). Schaltet man die Gruppe in
-- Masque aus, gilt sofort wieder der eigene Forever-Stil. Ohne Masque ändert sich nichts.

local MSQ = _G.LibStub and _G.LibStub("Masque", true)
local group
if MSQ and MSQ.Group then
    local ok, g = pcall(MSQ.Group, MSQ, "Forever Core", "ForeverBars")
    if ok then group = g end
end

-- gestaltet Masque gerade unsere Knöpfe?
function ns.MasqueActive()
    if not group then return false end
    local db = group.db
    return not (db and db.Disabled)
end

-- Knopf bei Masque anmelden (einmalig je Knopf)
function ns.MasqueAdd(button)
    if not group or button.fbMasque then return end
    button.fbMasque = true
    pcall(group.AddButton, group, button)
end

-- Masque-Einstellung der Gruppe geändert (Stil gewählt, Gruppe aus/an): eigenes Aussehen neu anwenden
if group and group.RegisterCallback then
    pcall(group.RegisterCallback, group, function()
        if ns.UpdateAllButtons then pcall(ns.UpdateAllButtons) end
    end)
end
