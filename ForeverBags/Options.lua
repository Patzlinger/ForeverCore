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

-- Farbfeld: Klick öffnet Blizzards Farbwahl (Abbrechen stellt die alte Farbe wieder her)
local function ColorSwatch(parent, x, y, label, key)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    b:SetPoint("TOPLEFT", x + 4, y - 3)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", b, "RIGHT", 8, 0)
    text:SetText(label)
    b.Refresh = function()
        local c = ns.db[key]
        b:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    local function Store(r, g, bl)
        ns.db[key] = { r, g, bl }
        b.Refresh()
        Changed()
    end
    b:SetScript("OnClick", function()
        local c = ns.db[key]
        local old = { c[1], c[2], c[3] }
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], hasOpacity = false,
            swatchFunc = function() Store(ColorPickerFrame:GetColorRGB()) end,
            cancelFunc = function() Store(old[1], old[2], old[3]) end,
        })
    end)
    controls[#controls + 1] = b
    return b
end

local function CreateOptions()
    local W, H = 680, 380
    options = UI.Window("ForeverBagsOptions", L("OPT_TITLE"), W, H)
    local x, x2, colW = 16, 352, 316

    -- linke Spalte: Allgemein, Fenster
    UI.Header(options, x, -40, L("SEC_GENERAL"), colW)
    Check(options, x, -62, L("OPT_REPLACE"), "replaceBlizzard")
    UI.Hint(options, x + 28, -86, colW - 32, L("OPT_REPLACE_HINT"))
    Check(options, x, -122, L("OPT_OPEN_CURSOR"), "openAtCursor")
    UI.Hint(options, x + 28, -146, colW - 32, L("OPT_OPEN_CURSOR_HINT"))
    Check(options, x, -172, L("OPT_COUNTS"), "tooltipCounts")

    UI.Header(options, x, -212, L("SEC_WINDOWS"), colW)
    Check(options, x, -234, L("OPT_REPLACE_BANK"), "replaceBank")
    Check(options, x, -258, L("OPT_REPLACE_GUILD"), "replaceGuildBank")
    local bankColumns = UI.Slider(options, x + 4, -290, L("OPT_BANK_COLUMNS"), 6, 24, 1, function(value)
        ns.db.bankColumns = value
        if ns.LayoutBank then ns.LayoutBank() end
    end, { width = 200 })
    bankColumns.Refresh = function() bankColumns:Load(ns.db.bankColumns) end
    controls[#controls + 1] = bankColumns

    -- rechte Spalte: Aussehen
    UI.Header(options, x2, -40, L("SEC_LOOK"), colW)
    Slider(options, x2 + 4, -64, L("OPT_COLUMNS"), "columns", 4, 24, 1, { width = 200 })
    Slider(options, x2 + 4, -106, L("OPT_SPACING"), "spacing", 0, 8, 1, { width = 200, unit = " px" })
    Check(options, x2, -146, L("OPT_BAGBAR"), "showBagBar")
    Check(options, x2, -170, L("OPT_QUALITY"), "qualityBorder")
    Check(options, x2, -194, L("OPT_NEW"), "highlightNew")
    ColorSwatch(options, x2, -218, L("OPT_REAGENT_COLOR"), "reagentColor")

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
