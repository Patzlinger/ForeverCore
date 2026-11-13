-- ForeverHelpers – Languages.lua: Sprachauswahl für "Suche nach Gruppe" > Durchsuchen (LFGBrowseFrame).
-- Blizzards Durchsuchen-Seite (Classic-Stil) gibt beim Suchen die Sprachauswahl NICHT mit – das Spiel liefert dann
-- nur Einträge in der Client-Sprache (im Spiel gemessen 2026-11-13: 8 statt 100 Treffer). Darum:
--   - Knopf "Sprachen: …" unter dem Fenster: Liste mit Häkchen je Sprache und "Alle Sprachen"; jede Änderung
--     sucht sofort neu.
--   - Über Blizzards Aktualisieren-Knopf liegt ein unsichtbarer eigener Knopf: ein Klick darauf sucht mit den
--     gewählten Sprachen (statt Blizzards Suche ohne Sprachen). Das Ergebnis zeigt Blizzards Liste wie gewohnt.
--       C_LFGList.Search(Kategorie, 0, 0, Sprachen, false, nil, Aktivitäten) – wie Blizzards LFGBrowse_DoSearch
--       (Blizzard_LFGVanilla_Browse.lua), nur mit Sprachen statt languageFilter = nil.
-- Das Spiel erlaubt Addons nur EINE Suche je Klick des Spielers (eine zweite direkt nach Blizzards Suche wurde
-- blockiert: ADDON_ACTION_BLOCKED, 2026-11-13). Darum keine Hooks auf Blizzards Suche, und nach einem
-- Kategorie-Wechsel (Blizzard sucht dann selbst, ohne Sprachen) einmal Aktualisieren.
-- Die Sprachauswahl speichert das Spiel selbst (Account). Blizzards Rahmen bleiben unberührt (Taint-Regel).
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

-- Aktivitäten wie Blizzard: die im Filter angehakten, sonst alle der Kategorie (nur lesen)
local function Activities(browse, category)
    local dropdown = browse.ActivityDropdown or browse.ActivityDropDown
    local selected = dropdown and dropdown.selectedValues
    if type(selected) == "table" and #selected > 0 then
        local copy = {}
        for i, id in ipairs(selected) do copy[i] = id end
        return copy
    end
    if type(_G.LFGUtil_GetFilteredActivities) == "function" then
        local ok, list = pcall(_G.LFGUtil_GetFilteredActivities, category)
        if ok and type(list) == "table" then return list end
    end
    return nil
end

-- Schutzfläche während unserer Suche: das Spiel verwirft die alten Treffer sofort, Blizzards Liste zeigt sie aber
-- bis zu den neuen Ergebnissen weiter (Blizzard leert sie nur bei der EIGENEN Suche). Fährt die Maus dann über
-- einen alten Eintrag, wirft Blizzards Tooltip einen Fehler (searchResultInfo nil, 2026-11-13). Eine unsichtbare,
-- mausfangende Fläche über dem Fenster verhindert das – bis die Ergebnisse da sind, höchstens 3 s. Blizzards
-- Liste selbst bleibt unberührt.
local shield
local function Shield(browse)
    if not shield then
        shield = CreateFrame("Frame", nil, browse)
        shield:SetAllPoints(browse)
        shield:SetFrameLevel(browse:GetFrameLevel() + 50)
        shield:EnableMouse(true)
        shield:Hide()
        for _, event in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED" }) do
            pcall(shield.RegisterEvent, shield, event)
        end
        shield:SetScript("OnEvent", function(self) self:Hide() end)
        browse:HookScript("OnHide", function() shield:Hide() end)
    end
    shield:Show()
    local token = {}
    shield.token = token
    C_Timer.After(3, function() if shield.token == token then shield:Hide() end end)
end

-- Suche mit den gewählten Sprachen in der oben eingestellten Kategorie. Nur aus einem eigenen Klick aufrufen.
local function Search()
    local browse = _G.LFGBrowseFrame
    if not (browse and browse:IsVisible()) then return end
    local dropdown = browse.CategoryDropdown or browse.CategoryDropDown
    local ok, category = false, nil
    if dropdown and dropdown.GetValue then ok, category = pcall(dropdown.GetValue, dropdown) end
    if not (ok and type(category) == "number" and category > 0) then
        UI.Chat("ForeverHelpers", T("Erst oben eine Kategorie wählen (z. B. Dungeons).", "Choose a category at the top first (e.g. Dungeons)."))
        return
    end
    local searched, err = pcall(C_LFGList.Search, category, 0, 0, Current(), false, nil, Activities(browse, category))
    if searched then
        pcall(Shield, browse)
    elseif UI.ReportError then
        UI.ReportError("ForeverHelpers", "Languages/Search", err)
    end
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

-- Unsichtbarer eigener Knopf genau über Blizzards Aktualisieren-Knopf: fängt den Klick ab und sucht MIT Sprachen
-- (Blizzards Knopf selbst bleibt unverändert – er bekommt den Klick nur nicht mehr). Sichtbar, solange er es ist.
local function CoverRefresh(browse)
    local refresh = browse.RefreshButton
    if type(refresh) ~= "table" or not refresh.GetObjectType or (refresh.IsForbidden and refresh:IsForbidden()) then return end
    local cover = CreateFrame("Button", nil, browse)
    cover:SetAllPoints(refresh)
    cover:SetFrameLevel(refresh:GetFrameLevel() + 5)
    cover:RegisterForClicks("LeftButtonUp")
    cover:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        Search()
    end)
    cover:SetScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(T("Aktualisieren", "Refresh"), 1, 0.82, 0)
        tip:AddLine(T("Sucht mit allen gewählten Sprachen (Knopf „Sprachen“ unter dem Fenster).",
            "Searches with all selected languages (\"Languages\" button below the window)."), 1, 1, 1, true)
        tip:Show()
    end)
    cover:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)
    cover:SetShown(refresh:IsShown())
    refresh:HookScript("OnShow", function() cover:Show() end)
    refresh:HookScript("OnHide", function() cover:Hide() end)
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
        tip:AddLine(T("Die Liste zeigt Einträge in allen gewählten Sprachen; jede Änderung sucht sofort neu. Nach einem Wechsel der Kategorie einmal auf Aktualisieren klicken. Die Auswahl gilt für den ganzen Account.",
            "The list shows listings in all selected languages; every change searches again right away. After changing the category, click Refresh once. The choice applies to your whole account."),
            1, 1, 1, true)
        tip:Show()
    end)
    button:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    browse:HookScript("OnShow", UpdateButton)
    browse:HookScript("OnHide", function() if popup then popup:Hide() end end)
    CoverRefresh(browse)
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
