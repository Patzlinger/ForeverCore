-- ForeverHelpers – Languages.lua: Sprachauswahl für "Suche nach Gruppe" > Durchsuchen (LFGBrowseFrame).
-- Blizzards Durchsuchen-Seite (Classic-Stil) gibt beim Suchen die Sprachauswahl NICHT mit – das Spiel liefert dann
-- nur Einträge in der Client-Sprache (im Spiel gemessen 2026-11-13: 8 statt 100 Treffer). Darum:
--   - Knopf "Sprachen: …" unter dem Fenster: Liste mit Häkchen je Sprache und "Alle Sprachen"; jede Änderung
--     sucht sofort neu.
--   - Die Liste aktualisiert sich selbst mit den gewählten Sprachen: beim Öffnen von "Durchsuchen" und jedes Mal,
--     wenn Blizzard sucht (Aktualisieren, Kategorie …) – direkt danach im selben Klick eine eigene Suche, deren
--     Ergebnis Blizzards Liste wie gewohnt zeigt:
--       C_LFGList.Search(Kategorie, 0, 0, Sprachen, false)   (Reihenfolge laut Fehlermeldung des Spiels;
--       false = nur die eigene Fraktion)
-- Das Spiel lässt Addons nur auf einen Klick/Tastendruck des Spielers suchen – darum nur in solchen Momenten.
-- Die Sprachauswahl speichert das Spiel selbst (Account). Blizzards Rahmen bleiben unberührt: nur Hooks (Taint-Regel).
local UI = ForeverHub.UI
local T = UI.T

-- Namen der Sprachen in beiden Sprachen (Blizzards Texte dafür sind je Client verschieden benannt)
local NAMES = {
    deDE = { "Deutsch", "German" }, enUS = { "Englisch", "English" }, frFR = { "Französisch", "French" },
    esES = { "Spanisch", "Spanish" }, ruRU = { "Russisch", "Russian" }, ptBR = { "Portugiesisch", "Portuguese" },
    itIT = { "Italienisch", "Italian" }, koKR = { "Koreanisch", "Korean" }, zhCN = { "Chinesisch", "Chinese" },
    zhTW = { "Chinesisch (trad.)", "Chinese (trad.)" },
}
local function Name(lang)
    local n = NAMES[lang]
    return n and T(n[1], n[2]) or lang
end
local function Short(lang) return lang:sub(1, 2):upper() end

local function Available()
    local ok, list = pcall(C_LFGList.GetAvailableLanguageSearchFilter)
    return ok and type(list) == "table" and list or {}
end
local function Current()
    local ok, f = pcall(C_LFGList.GetLanguageSearchFilter)
    return ok and type(f) == "table" and f or {}
end

-- Suche mit den gewählten Sprachen in der oben eingestellten Kategorie. quiet = ohne Hinweis, wenn noch keine
-- Kategorie gewählt ist (beim Öffnen und nach Blizzards Suche)
local lastSearch
local function Search(quiet)
    local now = GetTime()
    if lastSearch == now then return end -- (mehrere Anlässe im selben Klick: nur einmal suchen)
    local browse = _G.LFGBrowseFrame
    if not (browse and browse:IsVisible()) then return end
    local dropdown = browse.CategoryDropdown or browse.CategoryDropDown
    local ok, category = false, nil
    if dropdown and dropdown.GetValue then ok, category = pcall(dropdown.GetValue, dropdown) end
    if not (ok and type(category) == "number" and category > 0) then
        if not quiet then
            UI.Chat("ForeverHelpers", T("Erst oben eine Kategorie wählen (z. B. Dungeons).", "Choose a category at the top first (e.g. Dungeons)."))
        end
        return
    end
    lastSearch = now
    local searched, err = pcall(C_LFGList.Search, category, 0, 0, Current(), false)
    if not searched and UI.ReportError then UI.ReportError("ForeverHelpers", "Languages/Search", err) end
end

local button, popup, checks = nil, nil, {}

local function UpdateButton()
    if not button then return end
    local on = {}
    local cur = Current()
    for _, lang in ipairs(Available()) do
        if cur[lang] then on[#on + 1] = Short(lang) end
    end
    local text
    if #on == 0 or #on == #Available() then text = T("alle", "all") else text = table.concat(on, ", ") end
    button:SetText(T("Sprachen: ", "Languages: ") .. text)
    button:SetWidth(math.max(110, math.floor((button:GetFontString():GetStringWidth() or 80) + 20)))
end

local function UpdateChecks()
    local cur = Current()
    for lang, cb in pairs(checks) do cb:SetChecked(cur[lang] and true or false) end
end

local function Apply(filter)
    pcall(C_LFGList.SaveLanguageSearchFilter, filter)
    UpdateChecks()
    UpdateButton()
    Search()
end

-- neue Auswahl speichern und gleich neu suchen (Klick = Eingabe des Spielers)
local function Save(lang, value)
    local cur = Current()
    local filter = {}
    for _, l in ipairs(Available()) do filter[l] = cur[l] and true or nil end
    filter[lang] = value or nil
    if not next(filter) then -- mindestens eine Sprache an lassen
        UI.Chat("ForeverHelpers", T("Mindestens eine Sprache muss gewählt bleiben.", "At least one language must stay selected."))
        UpdateChecks()
        return
    end
    Apply(filter)
end

local function SetAll()
    local filter = {}
    for _, l in ipairs(Available()) do filter[l] = true end
    if next(filter) then Apply(filter) end
end

local function BuildPopup()
    popup = UI.Box(button)
    popup:SetFrameStrata("DIALOG")
    popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    popup:EnableMouse(true)
    popup:Hide()
    local title = UI.Text(popup, "field", T("In diesen Sprachen suchen", "Search in these languages"))
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -8)
    local y, widest = -30, title:GetStringWidth() or 150
    for _, lang in ipairs(Available()) do
        local cb = UI.Check(popup, 6, y, Name(lang), function(checked) Save(lang, checked) end)
        checks[lang] = cb
        widest = math.max(widest, 30 + (cb.label:GetStringWidth() or 80))
        y = y - 24
    end
    local all = UI.Button(popup, T("Alle Sprachen", "All languages"), 110, SetAll)
    all:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, y - 4)
    popup:SetSize(math.floor(math.max(widest, 120) + 24), -y + 36)
    popup:SetScript("OnShow", UpdateChecks)
end

-- Blizzards Suche abfangen (nur nachgeschaltet): direkt danach mit den gewählten Sprachen erneut suchen
local function HookBlizzardSearch(browse)
    local function After() Search(true) end
    if type(_G.LFGBrowse_DoSearch) == "function" then hooksecurefunc("LFGBrowse_DoSearch", After) end
    if type(browse.DoSearch) == "function" then hooksecurefunc(browse, "DoSearch", After) end
    -- Aktualisieren-Knopf (Symbol ohne Text), Name/Schlüssel enthält "refresh" bzw. "search"
    local function Find(frame, depth)
        for key, child in pairs(frame) do
            if type(key) == "string" and type(child) == "table" and child.IsObjectType and child.HookScript
                and not (child.IsForbidden and child:IsForbidden()) and child:IsObjectType("Button") then
                local k = key:lower()
                if k:find("refresh") or k:find("search") then child:HookScript("OnClick", After) end
            end
        end
        if depth < 2 then
            for _, child in ipairs({ frame:GetChildren() }) do
                if not (child.IsForbidden and child:IsForbidden()) then Find(child, depth + 1) end
            end
        end
    end
    Find(browse, 1)
    -- beim Öffnen der Seite (Klick auf den Reiter bzw. das Auge) gleich mit den gewählten Sprachen suchen
    browse:HookScript("OnShow", After)
end

local function Build(browse)
    local parent = _G.LFGParentFrame or browse
    button = UI.Button(browse, "", 120, function()
        if not popup then BuildPopup() end
        popup:SetShown(not popup:IsShown())
    end)
    -- unter dem Fenster links (im Fenster ist kein Platz frei; Blizzards Rahmen bleiben unberührt)
    button:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    button:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_BOTTOM")
        tip:SetText(T("Sprachen der Gruppensuche", "Group finder languages"), 1, 0.82, 0)
        tip:AddLine(T("Die Gruppensuche zeigt Einträge in allen gewählten Sprachen und aktualisiert sich bei jeder Änderung selbst. Die Auswahl gilt für den ganzen Account.",
            "The group finder shows listings in all selected languages and refreshes itself on every change. The choice applies to your whole account."),
            1, 1, 1, true)
        tip:Show()
    end)
    button:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    browse:HookScript("OnShow", UpdateButton)
    browse:HookScript("OnHide", function() if popup then popup:Hide() end end)
    HookBlizzardSearch(browse)
    UpdateButton()
end

local events = CreateFrame("Frame")
local function TryBuild()
    if button then return end
    if not (C_LFGList and C_LFGList.GetLanguageSearchFilter and C_LFGList.SaveLanguageSearchFilter and C_LFGList.Search) then
        events:UnregisterAllEvents() -- (gibt es in diesem Client nicht)
        return
    end
    local browse = _G.LFGBrowseFrame
    if type(browse) ~= "table" or not browse.GetObjectType or (browse.IsForbidden and browse:IsForbidden()) then return end
    local ok, err = pcall(Build, browse)
    if not ok and UI.ReportError then UI.ReportError("ForeverHelpers", "Languages", err) end
    events:UnregisterAllEvents()
end
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED") -- (falls Blizzard die Gruppensuche erst bei Bedarf lädt)
events:SetScript("OnEvent", TryBuild)
