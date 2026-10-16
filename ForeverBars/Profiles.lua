local addonName, ns = ...
local L = ns.L

-- Vorlagen (fertige Anordnungen) sowie Export/Import aller Einstellungen als Text.
-- Export/Import umgeht den Beta-Bug, bei dem SavedVariables beim Login nicht geladen werden.

---------------------------------------------------------------------------
-- Vorlagen
---------------------------------------------------------------------------

ns.PRESETS = {
    { key = "STANDARD", textKey = "PRESET_STANDARD" }, -- Standard: drei Leisten unten, zwei senkrecht rechts
    { key = "THREE_BOTTOM", textKey = "PRESET_THREE_BOTTOM" }, -- drei Leisten unten, keine rechts
    { key = "TWO_TWO", textKey = "PRESET_TWO_TWO" },   -- zwei Leisten unten, zwei senkrecht rechts
    { key = "SINGLE", textKey = "PRESET_SINGLE" },     -- eine Leiste unten, eine senkrecht rechts
    { key = "COMPACT", textKey = "PRESET_COMPACT" },   -- kleiner, Zusatzleisten nur bei Maus darüber
}

local function Bars() return ns.db.bars end

-- Alle Leisten auf Standard zurücksetzen (Positionen werden neu berechnet)
local function ResetAllBars()
    for key in pairs(ns.defaults.bars) do
        ns.db.bars[key] = CopyTable(ns.defaults.bars[key])
    end
end

-- Leiste im Raster über Leiste 1 einsetzen (Reihe 0 = unterste)
local function Stack(key, row)
    local x, y = ns.DefaultPosition("bar1")
    local step = 36 + 8
    Bars()[key].x = math.floor(x + 0.5)
    Bars()[key].y = math.floor(y + row * step + 0.5)
end

function ns.ApplyPreset(key)
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    ResetAllBars()
    local bars = Bars()
    if key == "THREE_BOTTOM" then
        bars.bar4.enabled = false
        bars.bar5.enabled = false
    elseif key == "TWO_TWO" then
        bars.bar3.enabled = false
    elseif key == "SINGLE" then
        bars.bar2.enabled = false
        bars.bar3.enabled = false
        bars.bar5.enabled = false
    elseif key == "COMPACT" then
        -- etwas kleiner, Zusatzleisten und Menü/Taschen erscheinen erst bei Maus darüber (im Kampf voll sichtbar)
        for _, barKey in ipairs({ "bar1", "bar2", "bar3", "bar4", "bar5", "pet", "stance" }) do
            bars[barKey].scale = 85
        end
        for _, barKey in ipairs({ "bar4", "bar5", "micro", "bags" }) do
            bars[barKey].fadeMouseover = true
            bars[barKey].fadeAlpha = 0
            bars[barKey].fadeDelay = 1
        end
    end
    -- Positionen: Leisten 1-3 gestapelt, Rest an den Standardplätzen
    for barKey, cfg in pairs(bars) do
        cfg.x, cfg.y = nil, nil
        ns.GetBarPosition(barKey)
    end
    Stack("bar1", 0)
    Stack("bar2", 1)
    Stack("bar3", 2)
    ns.RequestLayout()
    ns.UpdateAllButtons()
    ns.Print(L("PRESET_DONE"))
    if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- Export/Import als Text: "FB1:" + Einträge "pfad=typ:wert" getrennt durch ";"
-- (z. B. "bars.bar1.x=n:640;bars.bar1.enabled=b:1;font=s:STANDARD")
---------------------------------------------------------------------------

local EXPORT_PREFIX = "FB1:"

local function Escape(text)
    return (tostring(text):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D"):gsub("\n", "%%0A"))
end

local function Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Einstellungen in eine flache Liste "pfad=wert" zerlegen (sortiert, damit der Text immer gleich aussieht)
local function Flatten(tbl, prefix, out)
    local keys = {}
    for key in pairs(tbl) do table.insert(keys, key) end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        local value = tbl[key]
        local path = prefix and (prefix .. "." .. tostring(key)) or tostring(key)
        local kind = type(value)
        if kind == "table" then
            Flatten(value, path, out)
        elseif kind == "number" then
            table.insert(out, Escape(path) .. "=n:" .. value)
        elseif kind == "boolean" then
            table.insert(out, Escape(path) .. "=b:" .. (value and "1" or "0"))
        elseif kind == "string" then
            table.insert(out, Escape(path) .. "=s:" .. Escape(value))
        end
    end
    return out
end

function ns.ExportSettings()
    return EXPORT_PREFIX .. table.concat(Flatten(ns.db, nil, {}), ";")
end

-- Text wieder einlesen. Es werden nur Einstellungen übernommen, die ForeverBars kennt
-- (der Text wird nicht als Programmcode ausgeführt). Rückgabe: Anzahl übernommener Werte oder nil.
function ns.ImportSettings(text)
    text = strtrim(text or "")
    if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return nil end
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return nil
    end
    local count = 0
    for entry in text:sub(#EXPORT_PREFIX + 1):gmatch("[^;]+") do
        local rawPath, kind, rawValue = entry:match("^(.-)=([nbs]):(.*)$")
        if rawPath then
            local value
            if kind == "n" then
                value = tonumber(rawValue)
            elseif kind == "b" then
                value = rawValue == "1"
            else
                value = Unescape(rawValue)
            end
            -- Pfad auflösen; der erste Teil muss eine bekannte Einstellung sein
            local parts = {}
            for part in Unescape(rawPath):gmatch("[^%.]+") do
                table.insert(parts, tonumber(part) or part)
            end
            if value ~= nil and #parts > 0 and ns.defaults[parts[1]] ~= nil then
                local target = ns.db
                for i = 1, #parts - 1 do
                    if type(target[parts[i]]) ~= "table" then target[parts[i]] = {} end
                    target = target[parts[i]]
                end
                target[parts[#parts]] = value
                count = count + 1
            end
        end
    end
    ns.RequestLayout()
    ns.UpdateAllButtons()
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    if ns.RefreshOptions then ns.RefreshOptions() end
    return count
end

---------------------------------------------------------------------------
-- Fenster für Export/Import (Text markieren und mit Strg+C kopieren bzw. mit Strg+V einfügen)
---------------------------------------------------------------------------

local textWindow

local function CreateTextWindow()
    textWindow = ns.Style.CreateWindow("ForeverBarsTransfer", 560, 300, L("TRANSFER_TITLE"))
    textWindow:SetFrameStrata("FULLSCREEN_DIALOG")

    textWindow.hint = textWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textWindow.hint:SetPoint("TOPLEFT", 16, -50)
    textWindow.hint:SetPoint("RIGHT", -16, 0)
    textWindow.hint:SetJustifyH("LEFT")

    -- Textfeld mit Bildlauf
    local panel = ns.Style.CreatePanel(textWindow)
    panel:SetPoint("TOPLEFT", 12, -72)
    panel:SetPoint("BOTTOMRIGHT", -12, 50)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetWidth(510)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, box:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function() box:SetFocus() end)
    textWindow.box = box

    textWindow.applyButton = ns.Style.CreateButton(textWindow, L("BTN_IMPORT_APPLY"), 150, 26, function()
        local count = ns.ImportSettings(box:GetText())
        if count then
            ns.Print(L("IMPORT_DONE", count))
            textWindow:Hide()
        else
            ns.Print(L("IMPORT_INVALID"))
        end
    end)
    textWindow.applyButton:SetPoint("BOTTOMLEFT", 12, 12)
    ns.Style.CreateButton(textWindow, L("BTN_CLOSE"), 150, 26, function() textWindow:Hide() end)
        :SetPoint("BOTTOMRIGHT", -12, 12)
    textWindow:Hide()
end

-- mode = "export" (Text anzeigen und markieren) oder "import" (leeres Feld zum Einfügen)
function ns.ShowTransferWindow(mode)
    if not textWindow then CreateTextWindow() end
    textWindow:Show()
    if mode == "export" then
        textWindow.hint:SetText(L("EXPORT_HINT"))
        textWindow.applyButton:Hide()
        textWindow.box:SetText(ns.ExportSettings())
        textWindow.box:SetFocus()
        textWindow.box:HighlightText()
    else
        textWindow.hint:SetText(L("IMPORT_HINT"))
        textWindow.applyButton:Show()
        textWindow.box:SetText("")
        textWindow.box:SetFocus()
    end
end
