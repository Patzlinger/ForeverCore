-- ForeverFrames: Klick-Zauber (Maustaste + Modifikator -> Zauber/Makro/Aktion auf den Rahmen)
-- Technik: Blizzards sichere Button-Attribute ("shift-type1" = "spell", "shift-spell1" = "Blitzheilung").
-- Die Header kopieren diese Attribute automatisch auf jeden neuen Button ("_initialAttribute-...").
local ADDON_NAME, ns = ...
local T, GetDB = ns.T, ns.GetDB

ns.MOUSE_BUTTONS = {
    { key = 1, label = T("Linksklick", "Left click") },
    { key = 2, label = T("Rechtsklick", "Right click") },
    { key = 3, label = T("Mittlere Taste", "Middle button") },
    { key = 4, label = T("Maustaste 4", "Mouse button 4") },
    { key = 5, label = T("Maustaste 5", "Mouse button 5") },
}

-- Reihenfolge wie bei Blizzard: alt- vor ctrl- vor shift-
ns.MODIFIERS = {
    { key = "",           label = T("ohne Taste", "no modifier") },
    { key = "shift-",     label = "Shift" },
    { key = "ctrl-",      label = T("Strg", "Ctrl") },
    { key = "alt-",       label = "Alt" },
    { key = "ctrl-shift-", label = T("Strg+Shift", "Ctrl+Shift") },
    { key = "alt-shift-", label = "Alt+Shift" },
    { key = "alt-ctrl-",  label = T("Alt+Strg", "Alt+Ctrl") },
}

ns.ACTIONS = {
    { key = "target", label = T("Als Ziel wählen", "Target"),       type = "target" },
    { key = "menu",   label = T("Menü öffnen", "Open menu"),         type = "togglemenu" },
    { key = "spell",  label = T("Zauber wirken", "Cast spell"),      type = "spell" },
    { key = "macro",  label = T("Makro-Text", "Macro text"),         type = "macro" },
    { key = "focus",  label = T("Als Fokus setzen", "Set focus"),    type = "focus" },
    { key = "assist", label = T("Assistieren", "Assist"),            type = "assist" },
}

local function ActionType(action)
    for _, a in ipairs(ns.ACTIONS) do
        if a.key == action then return a.type end
    end
end

-- Belegungen der aktuellen Klasse (jede Klasse hat eigene Zauber)
function ns.GetBindings()
    local db = GetDB()
    local _, class = UnitClass("player")
    class = class or "ALL"
    if type(db.clicks) ~= "table" then db.clicks = {} end
    if type(db.clicks[class]) ~= "table" then
        db.clicks[class] = {
            { button = 1, mod = "", action = "target", value = "" },
            { button = 2, mod = "", action = "menu", value = "" },
        }
    end
    return db.clicks[class]
end

-- Belegungen -> sichere Attribute
local function BuildAttributes()
    local attrs = {}
    for _, bd in ipairs(ns.GetBindings()) do
        local kind = ActionType(bd.action)
        local suffix = tostring(bd.button or 1)
        local mod = bd.mod or ""
        local value = bd.value and strtrim(bd.value) or ""
        if kind == "spell" then
            if value ~= "" then
                attrs[mod .. "type" .. suffix] = "spell"
                attrs[mod .. "spell" .. suffix] = value
            end
        elseif kind == "macro" then
            if value ~= "" then
                attrs[mod .. "type" .. suffix] = "macro"
                attrs[mod .. "macrotext" .. suffix] = value
            end
        elseif kind then
            attrs[mod .. "type" .. suffix] = kind
        end
    end
    return attrs
end

local currentAttrs = {}

local function ApplyToButton(b)
    for _, k in ipairs(b.ffClickKeys or {}) do
        b:SetAttribute(k, nil)
    end
    local keys = {}
    for k, v in pairs(currentAttrs) do
        b:SetAttribute(k, v)
        tinsert(keys, k)
    end
    b.ffClickKeys = keys
end

function ns.ApplyClicksToButton(b)
    ns.OutOfCombat("klickzauber-" .. b:GetName(), function() ApplyToButton(b) end)
end

-- Belegungen auf alle Header und Buttons uebertragen (im Kampf: nach dem Kampf)
function ns.ApplyClicks()
    currentAttrs = BuildAttributes()
    local queued = not ns.OutOfCombat("klickzauber", function()
        for _, h in ipairs(ns.headers) do
            h:SetAttribute("_ignore", "attributeChanges") -- nicht bei jedem Attribut neu sortieren
            local names = {}
            for k, v in pairs(currentAttrs) do
                h:SetAttribute("_initialAttribute-" .. k, v)
                tinsert(names, k)
            end
            h:SetAttribute("_initialAttributeNames", table.concat(names, ","))
            h:SetAttribute("_ignore", nil)
        end
        for _, b in ipairs(ns.buttons) do ApplyToButton(b) end
        for _, p in ipairs(ns.petButtons or {}) do ApplyToButton(p) end -- Begleiter
    end)
    if queued then
        ns.Chat(T("Klick-Zauber werden nach dem Kampf übernommen.", "Click casting will be applied after combat."))
    end
end

-- Alle aktiven (nicht passiven) Zauber aus dem Zauberbuch, alphabetisch
function ns.GetSpellbookSpells()
    local list, seen = {}, {}
    local function add(name, icon)
        if name and not seen[name] then
            seen[name] = true
            tinsert(list, { name = name, icon = icon })
        end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID and not item.isPassive then
                        add(item.name, item.iconID)
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
