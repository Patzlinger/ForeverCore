local addonName, ns = ...

-- Options.lua: kleines Einstellungsfenster (Bausteine aus dem Hub: UI.Window, UI.Header, UI.Check, UI.Slider).
-- Jede Änderung wirkt sofort.

local L = ns.L
local UI = ForeverHub.UI

local options
local controls = {} -- Bedienelemente mit :Refresh()

local function Changed()
    if ns.LayoutBags then ns.LayoutBags() end
end

local function Check(parent, x, y, label, key, after)
    local cb = UI.Check(parent, x, y, label, function(checked)
        ns.db[key] = checked
        if after then after(checked) end
        Changed()
    end)
    cb.Refresh = function() cb:SetChecked(ns.db[key] and true or false) end
    controls[#controls + 1] = cb
    return cb
end

local function Slider(parent, x, y, label, key, minV, maxV, step, opts)
    local s = UI.Slider(parent, x, y, label, minV, maxV, step, function(value)
        ns.db[key] = value
        Changed()
    end, opts)
    s.Refresh = function() s:Load(ns.db[key]) end
    controls[#controls + 1] = s
    return s
end

local function CreateOptions()
    local W, H = 380, 360
    options = UI.Window("ForeverBagsOptions", L("OPT_TITLE"), W, H)
    local x = 16

    UI.Header(options, x, -40, L("SEC_GENERAL"), W - 32)
    Check(options, x, -62, L("OPT_REPLACE"), "replaceBlizzard")
    UI.Hint(options, x + 28, -86, W - 60, L("OPT_REPLACE_HINT"))
    Check(options, x, -118, L("OPT_BAGBAR"), "showBagBar")

    UI.Header(options, x, -156, L("SEC_LOOK"), W - 32)
    Slider(options, x + 4, -180, L("OPT_COLUMNS"), "columns", 4, 24, 1, { width = 200 })
    Slider(options, x + 4, -222, L("OPT_SPACING"), "spacing", 0, 8, 1, { width = 200, unit = " px" })
    Check(options, x, -262, L("OPT_QUALITY"), "qualityBorder")
    Check(options, x, -286, L("OPT_NEW"), "highlightNew")

    -- Fußleiste: links Position zurücksetzen, rechts Schließen (unten rechts bleibt Platz für den Größen-Griff)
    local reset = UI.Button(options, L("BTN_RESET_POS"), 150, function() ns.ResetPosition() end)
    reset:SetPoint("BOTTOMLEFT", 12, 12)
    local close = UI.Button(options, L("BTN_CLOSE"), 110, function() options:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -28, 12)

    -- HookScript statt SetScript: der Hub hängt eigene Dinge an OnShow (Abschnitts-Kästen, Fenster-Stapel)
    options:HookScript("OnShow", function() ns.RefreshOptions() end)
end

function ns.RefreshOptions()
    if not options or not options:IsShown() then return end
    for _, c in ipairs(controls) do c.Refresh() end
end

function ns.ToggleOptions()
    if not options then CreateOptions() end
    options:SetShown(not options:IsShown())
end
