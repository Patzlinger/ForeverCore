-- ForeverHelpers – Languages.lua: Sprachauswahl für "Suche nach Gruppe" > Durchsuchen (LFGBrowseFrame).
-- Das Spiel zeigt in der Gruppensuche nur Einträge in den gewählten Sprachen (Blizzards Sprachfilter,
-- C_LFGList.Get/SaveLanguageSearchFilter); ein eigenes Menü dafür hat das Fenster im Forever-Client nicht.
-- Unter dem Fenster sitzt ein kleiner Knopf "Sprachen: …"; ein Klick öffnet eine Liste mit Häkchen je Sprache.
-- Die Auswahl speichert das Spiel selbst (gilt für den ganzen Account). Mindestens eine Sprache bleibt immer an.
-- Nur lesen/speichern über die freie Schnittstelle – Blizzards Rahmen bleiben unberührt (Taint-Regel).
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR

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

-- neue Auswahl speichern und – wie Blizzards eigener Filter – gleich neu suchen (Klick = Tastendruck des Spielers)
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
    pcall(C_LFGList.SaveLanguageSearchFilter, filter)
    UpdateChecks()
    UpdateButton()
    if _G.LFGBrowse_DoSearch then pcall(_G.LFGBrowse_DoSearch) end
end

local function SetAll()
    local filter = {}
    for _, l in ipairs(Available()) do filter[l] = true end
    if not next(filter) then return end
    pcall(C_LFGList.SaveLanguageSearchFilter, filter)
    UpdateChecks()
    UpdateButton()
    if _G.LFGBrowse_DoSearch then pcall(_G.LFGBrowse_DoSearch) end
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
    local all = UI.Button(popup, T("Alle", "All"), 70, SetAll)
    all:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, y - 4)
    popup:SetSize(math.floor(widest + 24), -y + 36)
    -- schließt mit der Gruppensuche, mit Escape (über den Knopf) und beim nächsten Klick auf den Knopf
    popup:SetScript("OnShow", UpdateChecks)
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
        tip:AddLine(T("Die Gruppensuche zeigt nur Einträge in den gewählten Sprachen. Die Auswahl gilt für den ganzen Account.",
            "The group finder only shows listings in the selected languages. The choice applies to your whole account."),
            1, 1, 1, true)
        tip:Show()
    end)
    button:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    browse:HookScript("OnShow", UpdateButton)
    browse:HookScript("OnHide", function() if popup then popup:Hide() end end)
    UpdateButton()
end

local events = CreateFrame("Frame")
local function TryBuild()
    if button then return end
    if not (C_LFGList and C_LFGList.GetLanguageSearchFilter and C_LFGList.SaveLanguageSearchFilter) then
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
