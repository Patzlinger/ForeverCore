local addonName, ns = ...
local L = ns.L

-- Vorlagen (fertige Anordnungen) sowie Export/Import aller Einstellungen als Text.
-- Export/Import umgeht den Beta-Bug, bei dem SavedVariables beim Login nicht geladen werden.

---------------------------------------------------------------------------
-- Vorlagen
---------------------------------------------------------------------------

ns.PRESETS = {
    { key = "STANDARD", textKey = "PRESET_STANDARD" },             -- Standard: drei Leisten unten (wie neues Profil)
    { key = "STANDARD_RIGHT", textKey = "PRESET_STANDARD_RIGHT" }, -- drei unten, zwei senkrecht rechts
    { key = "TWO_TWO", textKey = "PRESET_TWO_TWO" },               -- zwei Leisten unten, zwei senkrecht rechts
    { key = "SINGLE", textKey = "PRESET_SINGLE" },                 -- eine Leiste unten, eine senkrecht rechts
    { key = "COMPACT", textKey = "PRESET_COMPACT" },               -- kleiner, Menü/Taschen nur bei Maus darüber
}

local function Bars() return ns.db.bars end

-- Alle Leisten auf Standard zurücksetzen (Positionen werden neu berechnet)
local function ResetAllBars()
    for key in pairs(ns.defaults.bars) do
        ns.db.bars[key] = CopyTable(ns.defaults.bars[key])
    end
end

function ns.ApplyPreset(key)
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    ResetAllBars()
    local bars = Bars()
    if key == "STANDARD_RIGHT" then
        bars.bar4.enabled = true
        bars.bar5.enabled = true
    elseif key == "TWO_TWO" then
        bars.bar3.enabled = false
        bars.bar4.enabled = true
        bars.bar5.enabled = true
    elseif key == "SINGLE" then
        bars.bar2.enabled = false
        bars.bar3.enabled = false
        bars.bar4.enabled = true
    elseif key == "COMPACT" then
        -- etwas kleiner, Menü und Taschen erscheinen erst bei Maus darüber (im Kampf voll sichtbar)
        for _, barKey in ipairs({ "bar1", "bar2", "bar3", "prof" }) do bars[barKey].scale = 85 end
        for _, barKey in ipairs({ "pet", "stance" }) do bars[barKey].scale = 43 end
        for _, barKey in ipairs({ "micro", "bags" }) do
            bars[barKey].fadeMouseover = true
            bars[barKey].fadeAlpha = 0
            bars[barKey].fadeDelay = 1
        end
    end
    -- Positionen der Standard-Anordnung neu berechnen (Leisten 1-3 unten aneinander, Rest drumherum)
    for barKey, cfg in pairs(bars) do
        cfg.x, cfg.y = nil, nil
        ns.GetBarPosition(barKey)
    end
    ns.RequestLayout()
    ns.UpdateAllButtons()
    ns.Print(L("PRESET_DONE"))
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Alle Einstellungen und Positionen auf Standard (gespeicherte Profile bleiben erhalten; Blizzard-Einstellungen
-- wie Tastenbelegung oder "Beim Drücken auslösen" bleiben unverändert)
local KEEP_ON_RESET = { profiles = true, activeProfile = true }

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
-- Gespeicherte Profile: Kopie aller Einstellungen unter einem Namen (ohne Minimap-Symbol und die Profile selbst)
---------------------------------------------------------------------------

-- Es gibt immer ein aktives Profil. Die aktuellen Einstellungen gehören zu ihm: beim Wechseln und beim
-- Ausloggen werden sie in das aktive Profil geschrieben. "Default" gibt es immer (Anzeige: "Standard").
ns.DEFAULT_PROFILE = "Default"
local NOT_IN_PROFILE = { profiles = true, activeProfile = true, version = true,
                         showMinimapButton = true, minimapAngle = true }

local function Snapshot()
    local copy = {}
    for key, value in pairs(ns.db) do
        if not NOT_IN_PROFILE[key] then
            copy[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    return copy
end

-- Anzeigename (das Standardprofil heißt in jeder Sprache passend)
function ns.ProfileLabel(name)
    if name == ns.DEFAULT_PROFILE then return L("PROFILE_DEFAULT") end
    return name
end

-- Beim Start: Standardprofil anlegen, aktives Profil prüfen
function ns.InitProfiles()
    ns.db.profiles = ns.db.profiles or {}
    if not ns.db.profiles[ns.DEFAULT_PROFILE] then ns.db.profiles[ns.DEFAULT_PROFILE] = Snapshot() end
    if not ns.db.profiles[ns.db.activeProfile or ""] then ns.db.activeProfile = ns.DEFAULT_PROFILE end
end

function ns.GetActiveProfile()
    return ns.db.activeProfile or ns.DEFAULT_PROFILE
end

-- Aktuelle Einstellungen ins aktive Profil schreiben
function ns.SaveActiveProfile()
    if not ns.db then return end
    ns.db.profiles = ns.db.profiles or {}
    ns.db.profiles[ns.GetActiveProfile()] = Snapshot()
end

-- Standardprofil zuerst, dann alphabetisch
function ns.GetProfileNames()
    local names = {}
    for name in pairs(ns.db.profiles or {}) do
        if name ~= ns.DEFAULT_PROFILE then table.insert(names, name) end
    end
    table.sort(names)
    table.insert(names, 1, ns.DEFAULT_PROFILE)
    return names
end

-- Neues Profil aus den aktuellen Einstellungen; es wird das aktive Profil
function ns.SaveProfile(name)
    name = strtrim(name or "")
    if name == "" then return false end
    ns.SaveActiveProfile()
    ns.db.profiles[name] = Snapshot()
    ns.db.activeProfile = name
    ns.Print(L("PROFILE_SAVED", ns.ProfileLabel(name)))
    return true
end

-- Zu einem anderen Profil wechseln (die Einstellungen des bisherigen bleiben in dessen Profil)
function ns.LoadProfile(name)
    local profile = ns.db.profiles and ns.db.profiles[name]
    if not profile then return end
    if InCombatLockdown() then
        ns.Print(L("NOT_IN_COMBAT"))
        return
    end
    ns.SaveActiveProfile()
    for key, value in pairs(profile) do
        if not NOT_IN_PROFILE[key] then
            ns.db[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    -- Ältere Profile kennen neuere Einstellungen nicht: umrechnen und aus den Standardwerten ergänzen
    ns.MigrateBars(ns.db.bars)
    ns.FillDefaults(ns.db, ns.defaults)
    ns.db.activeProfile = name
    ns.RequestLayout()
    ns.UpdateAllButtons()
    ns.Print(L("PROFILE_LOADED", ns.ProfileLabel(name)))
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Das Standardprofil lässt sich nicht löschen; wird das aktive gelöscht, gilt danach das Standardprofil
function ns.DeleteProfile(name)
    if name == ns.DEFAULT_PROFILE then
        ns.Print(L("PROFILE_DEFAULT_KEEP"))
        return
    end
    if ns.db.profiles and ns.db.profiles[name] then
        if name == ns.GetActiveProfile() then
            ns.db.profiles[name] = nil
            ns.db.activeProfile = ns.DEFAULT_PROFILE
            -- Einstellungen des Standardprofils übernehmen (ohne die gelöschten zurückzuschreiben)
            local profile = ns.db.profiles[ns.DEFAULT_PROFILE]
            if profile and not InCombatLockdown() then
                for key, value in pairs(profile) do
                    if not NOT_IN_PROFILE[key] then
                        ns.db[key] = type(value) == "table" and CopyTable(value) or value
                    end
                end
                ns.FillDefaults(ns.db, ns.defaults)
                ns.RequestLayout()
                ns.UpdateAllButtons()
            end
        else
            ns.db.profiles[name] = nil
        end
        ns.Print(L("PROFILE_DELETED", name))
    end
end

---------------------------------------------------------------------------
-- Export/Import als Text: "FB1:" + Einträge "pfad=typ:wert" getrennt durch ";"
-- (z. B. "bars.bar1.x=n:640;bars.bar1.enabled=b:1;font=s:STANDARD")
---------------------------------------------------------------------------

local EXPORT_PREFIX = "FB1:"

local function Escape(text)
    return (tostring(text):gsub("%%", "%%25"):gsub(";", "%%3B"):gsub("=", "%%3D"):gsub("\n", "%%0A"))
end

-- Teil eines Pfades (z. B. Profilname): zusätzlich den Punkt, der die Teile trennt
local function EscapePart(text)
    return (Escape(text):gsub("%.", "%%2E"))
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
        local path = prefix and (prefix .. "." .. EscapePart(key)) or EscapePart(key)
        local kind = type(value)
        if kind == "table" then
            Flatten(value, path, out)
        elseif kind == "number" then
            table.insert(out, path .. "=n:" .. value)
        elseif kind == "boolean" then
            table.insert(out, path .. "=b:" .. (value and "1" or "0"))
        elseif kind == "string" then
            table.insert(out, path .. "=s:" .. Escape(value))
        end
    end
    return out
end

function ns.ExportSettings()
    ns.SaveActiveProfile() -- damit das aktive Profil im Text den aktuellen Stand hat
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
            for part in rawPath:gmatch("[^%.]+") do
                part = Unescape(part)
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
    ns.InitProfiles() -- Standardprofil sicherstellen, aktives Profil prüfen
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
