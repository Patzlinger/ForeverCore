-- ForeverHelpers – Languages.lua: Sprachauswahl für "Suche nach Gruppe" > Durchsuchen (LFGBrowseFrame).
-- Blizzards Durchsuchen-Seite (Classic-Stil) gibt beim Suchen die Sprachauswahl NICHT mit – das Spiel liefert dann
-- nur Einträge in der Client-Sprache (im Spiel gemessen 2026-11-13: 8 statt 100 Treffer). Darum:
--   - Auswahlfeld "Sprachen: …" unten in der Leiste zwischen "Nachricht senden" und "Gruppeneinladung" – wie die
--     Kategorie-Auswahl oben (Blizzards Menü, Häkchen je Sprache, "Alle Sprachen"; ForeverSkin gestaltet es mit).
--     Speichert nur – wirksam wird die Auswahl beim nächsten Klick auf Aktualisieren.
--   - Über Blizzards Aktualisieren-Knopf liegt ein unsichtbarer eigener Knopf: ein Klick darauf sucht mit den
--     gewählten Sprachen (statt Blizzards Suche ohne Sprachen). Das Ergebnis zeigt Blizzards Liste wie gewohnt.
--       C_LFGList.Search(Kategorie, 0, 0, Sprachen, false, nil, Aktivitäten) – wie Blizzards LFGBrowse_DoSearch
--       (Blizzard_LFGVanilla_Browse.lua), nur mit Sprachen statt languageFilter = nil.
-- Das Spiel erlaubt Addons nur EINE Suche je Klick des Spielers (eine zweite direkt nach Blizzards Suche wurde
-- blockiert: ADDON_ACTION_BLOCKED, 2026-11-13). Darum keine Hooks auf Blizzards Suche, und nach einem
-- Kategorie-Wechsel (Blizzard sucht dann selbst, ohne Sprachen) einmal Aktualisieren.
-- Die Sprachauswahl speichert das Spiel selbst (Account). Blizzards Rahmen bleiben unberührt (Taint-Regel).
--
-- Rollenfilter (Auswahlfeld "Rolle" rechts daneben): Forever nimmt den erweiterten Filter der Suche (needsTank …)
-- zwar an, wertet ihn aber NICHT aus (im Spiel gemessen 2026-11-13: 17 ohne, 20 mit Heiler-Filter). Darum filtert
-- das Addon die Anzeige selbst und dunkelt unpassende Einträge ab (nur SetAlpha auf Blizzards Zeilen, die Liste
-- selbst bleibt unberührt). Gelesen wird genau das, was Blizzards Liste für die Rollen-Symbole nutzt
-- (Blizzard_LFGVanilla_Browse.lua):
--   einzelner Spieler: C_LFGList.GetSearchResultPlayerInfo(id, 1).lfgRoles.tank/.healer/.dps -> bietet die Rolle an
-- Gruppen bleiben immer hell (gewünscht: der Filter gilt nur für einzelne Spieler). Unbekanntes bleibt hell. Wirkt sofort (keine neue Suche nötig); Auswahl in ForeverHelpersDB.lfg.roles.
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

---------------------------------------------------------------------------
-- Rollenfilter (nur Anzeige)
---------------------------------------------------------------------------
local ROLES = {
    { key = "tank", de = "Tank", en = "Tank" },
    { key = "healer", de = "Heiler", en = "Healer" },
    { key = "dps", de = "Schaden", en = "Damage" },
}
local DIM = 0.25 -- Deckkraft unpassender Einträge

local function RoleDB()
    if type(_G.ForeverHelpersDB) ~= "table" then _G.ForeverHelpersDB = {} end
    local db = _G.ForeverHelpersDB
    if type(db.lfg) ~= "table" then db.lfg = {} end
    if type(db.lfg.roles) ~= "table" then db.lfg.roles = {} end
    return db.lfg.roles
end

local function RolesActive()
    for _, r in ipairs(ROLES) do if RoleDB()[r.key] then return true end end
    return false
end

-- passt der Eintrag zur Rollenauswahl? (true = hell lassen; auch, wenn nichts zu lesen ist)
local function Matches(id)
    local okInfo, info = pcall(C_LFGList.GetSearchResultInfo, id)
    if not (okInfo and type(info) == "table") then return true end
    -- Gruppen bleiben außen vor (immer hell) – der Filter gilt nur für einzelne Spieler (Wunsch von flowfy, 2026-11-13)
    if info.numMembers ~= 1 then return true end
    local wanted = RoleDB()
    local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, id, 1)
    local roles = ok and type(member) == "table" and member.lfgRoles
    if type(roles) ~= "table" or not (roles.tank or roles.healer or roles.dps) then return true end
    for _, r in ipairs(ROLES) do
        if wanted[r.key] and roles[r.key] then return true end
    end
    return false
end

-- alle sichtbaren Zeilen der Liste abdunkeln bzw. wieder hell (Blizzard verwendet Zeilen beim Blättern wieder –
-- darum im Takt, solange die Seite offen ist und ein Filter gilt bzw. noch etwas abgedunkelt ist)
local dimmed = setmetatable({}, { __mode = "k" })
local function ApplyRoles(browse)
    local box = browse.ScrollBox
    if not (box and box.ForEachFrame) then return end
    local active = RolesActive()
    box:ForEachFrame(function(entry)
        local id = entry.resultID
        local match = not active or type(id) ~= "number" or Matches(id)
        if match then
            if dimmed[entry] then
                dimmed[entry] = nil
                entry:SetAlpha(1)
            end
        elseif not dimmed[entry] or entry:GetAlpha() > DIM + 0.01 then
            dimmed[entry] = true
            entry:SetAlpha(DIM)
        end
    end)
end

---------------------------------------------------------------------------
-- Auswahlfelder
---------------------------------------------------------------------------
local dropdown, roleDropdown

local function Label()
    local on, all = {}, Available()
    local cur = Current()
    for _, lang in ipairs(all) do
        if cur[lang] then on[#on + 1] = Short(lang) end
    end
    local text
    if #on == 0 or #on == #all then text = T("alle", "all") else text = table.concat(on, ", ") end
    return T("Sprache: ", "Language: ") .. text
end

local function RoleLabel()
    local on = {}
    for _, r in ipairs(ROLES) do
        if RoleDB()[r.key] then on[#on + 1] = T(r.de, r.en) end
    end
    if #on == 0 or #on == #ROLES then return T("Rolle: alle", "Role: all") end
    return T("Rolle: ", "Role: ") .. table.concat(on, ", ")
end

local function SetLabel(dd, text)
    if not dd then return end
    if dd.OverrideText then pcall(dd.OverrideText, dd, text)
    elseif dd.SetText then pcall(dd.SetText, dd, text) end
end

local function UpdateLabel()
    SetLabel(dropdown, Label())
    SetLabel(roleDropdown, RoleLabel())
end

-- Auswahl nur speichern – gesucht wird erst beim Klick auf Aktualisieren (auf Wunsch, 2026-11-13)
local function Save(filter)
    if not next(filter) then -- mindestens eine Sprache an lassen
        UI.Chat("ForeverHelpers", T("Mindestens eine Sprache muss gewählt bleiben.", "At least one language must stay selected."))
        return
    end
    pcall(C_LFGList.SaveLanguageSearchFilter, filter)
    UpdateLabel()
end

local function Toggle(lang)
    local cur = Current()
    local filter = {}
    for _, l in ipairs(Available()) do filter[l] = cur[l] and true or nil end
    filter[lang] = (not cur[lang]) or nil
    Save(filter)
end

local function SetAll()
    local filter = {}
    for _, l in ipairs(Available()) do filter[l] = true end
    Save(filter)
end

-- Menü wie Blizzards Kategorie-Auswahl (Blizzard_Menu): Überschrift, ein Häkchen je Sprache, "Alle Sprachen".
-- Bleibt beim Anhaken offen (mehrere Sprachen nacheinander).
local function MenuGenerator(_, root)
    root:CreateTitle(T("In diesen Sprachen suchen", "Search in these languages"))
    for _, lang in ipairs(Available()) do
        root:CreateCheckbox(Name(lang),
            function() return Current()[lang] and true or false end,
            function() Toggle(lang) end)
    end
    root:CreateDivider()
    root:CreateButton(T("Alle Sprachen", "All languages"), function() SetAll() end)
end

-- Rollen-Menü: ein Häkchen je Rolle, "Alle Rollen" = Filter aus. Wirkt sofort auf die Anzeige.
local function RoleMenuGenerator(_, root)
    root:CreateTitle(T("Spieler mit dieser Rolle", "Players with this role"))
    for _, r in ipairs(ROLES) do
        root:CreateCheckbox(T(r.de, r.en),
            function() return RoleDB()[r.key] and true or false end,
            function()
                RoleDB()[r.key] = (not RoleDB()[r.key]) or nil
                UpdateLabel()
                if _G.LFGBrowseFrame then pcall(ApplyRoles, _G.LFGBrowseFrame) end
            end)
    end
    root:CreateDivider()
    root:CreateButton(T("Alle Rollen", "All roles"), function()
        for _, r in ipairs(ROLES) do RoleDB()[r.key] = nil end
        UpdateLabel()
        if _G.LFGBrowseFrame then pcall(ApplyRoles, _G.LFGBrowseFrame) end
    end)
end

-- Platz unten in der Leiste: zwischen dem linken und rechten Text-Knopf ("Nachricht senden" / "Gruppeneinladung")
local function FooterButtons(browse)
    local bottom = browse:GetBottom()
    if not bottom then return nil end
    local found = {}
    local function Scan(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not (child.IsForbidden and child:IsForbidden()) and child ~= dropdown and child ~= roleDropdown then
                if child:IsObjectType("Button") then
                    local text = child.GetText and child:GetText()
                    if type(text) == "string" and text ~= "" and child:IsShown() and child:GetBottom()
                        and child:GetBottom() - bottom < 50 and child:GetLeft() then
                        found[#found + 1] = child
                    end
                elseif depth < 2 then
                    Scan(child, depth + 1)
                end
            end
        end
    end
    Scan(browse, 1)
    if #found < 2 then return nil end
    table.sort(found, function(a, b) return a:GetLeft() < b:GetLeft() end)
    return found[1], found[#found]
end

-- Beide Felder teilen sich die Lücke: Sprache links, Rolle rechts (je halbe Breite, 6 px Luft dazwischen)
local placed = false
local gap
local function Place(browse)
    if placed or not dropdown then return end
    local left, right = FooterButtons(browse)
    gap = gap or CreateFrame("Frame", nil, browse)
    gap:ClearAllPoints()
    local height = 22
    if left and right then
        placed = true
        gap:SetPoint("LEFT", left, "RIGHT", 8, 0)
        gap:SetPoint("RIGHT", right, "LEFT", -8, 0)
        height = math.floor((left:GetHeight() or 22) + 0.5)
    else
        -- (Knöpfe noch nicht gefunden: vorerst unten mittig; beim nächsten Öffnen erneut versuchen)
        gap:SetPoint("BOTTOM", browse, "BOTTOM", 0, 6)
        gap:SetWidth(240)
    end
    gap:SetHeight(height)
    dropdown:ClearAllPoints()
    dropdown:SetPoint("TOPLEFT", gap, "TOPLEFT")
    dropdown:SetPoint("BOTTOMRIGHT", gap, "BOTTOM", -3, 0)
    if roleDropdown then
        roleDropdown:ClearAllPoints()
        roleDropdown:SetPoint("TOPLEFT", gap, "TOP", 3, 0)
        roleDropdown:SetPoint("BOTTOMRIGHT", gap, "BOTTOMRIGHT")
    end
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
        tip:AddLine(T("Sucht mit allen gewählten Sprachen (Auswahl „Sprachen“ unten im Fenster).",
            "Searches with all selected languages (\"Languages\" selection at the bottom of the window)."), 1, 1, 1, true)
        tip:Show()
    end)
    cover:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)
    cover:SetShown(refresh:IsShown())
    refresh:HookScript("OnShow", function() cover:Show() end)
    refresh:HookScript("OnHide", function() cover:Hide() end)
end

local function Build(browse)
    dropdown = CreateFrame("DropdownButton", nil, browse, "WowStyle1DropdownTemplate")
    dropdown:SetupMenu(MenuGenerator)
    dropdown:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:SetText(T("Sprachen der Gruppensuche", "Group finder languages"), 1, 0.82, 0)
        tip:AddLine(T("Sprachen wählen, dann oben auf Aktualisieren klicken: Die Liste zeigt dann Einträge in allen gewählten Sprachen. Die Auswahl gilt für den ganzen Account.",
            "Choose the languages, then click Refresh at the top: the list then shows listings in all selected languages. The choice applies to your whole account."),
            1, 1, 1, true)
        tip:Show()
    end)
    dropdown:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    roleDropdown = CreateFrame("DropdownButton", nil, browse, "WowStyle1DropdownTemplate")
    roleDropdown:SetupMenu(RoleMenuGenerator)
    roleDropdown:HookScript("OnEnter", function(self)
        local tip = UI.GetTooltip()
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:SetText(T("Nach Rolle filtern", "Filter by role"), 1, 0.82, 0)
        tip:AddLine(T("Einzelne Spieler bleiben hell, wenn sie eine gewählte Rolle anbieten; die übrigen Spieler werden abgedunkelt. Gruppen bleiben immer sichtbar.",
            "Single players stay bright if they offer a selected role; other players are dimmed. Groups always stay visible."),
            1, 1, 1, true)
        tip:Show()
    end)
    roleDropdown:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
    -- Rollenfilter im Takt anwenden (nur solange die Seite offen ist, die Uhr hängt an ihr)
    local ticker = CreateFrame("Frame", nil, browse)
    local waited = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        if not RolesActive() and not next(dimmed) then return end
        local ok, err = pcall(ApplyRoles, browse)
        if not ok and not self.reported then
            self.reported = true
            if UI.ReportError then UI.ReportError("ForeverHelpers", "Languages/Roles", err) end
        end
    end)
    Place(browse)
    UpdateLabel()
    -- Knöpfe stehen erst nach dem ersten Öffnen fest: dann einreihen
    browse:HookScript("OnShow", function()
        C_Timer.After(0, function()
            pcall(Place, browse)
            UpdateLabel()
        end)
    end)
    CoverRefresh(browse)
end

local events = CreateFrame("Frame")
local function TryBuild()
    if dropdown then return end
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
