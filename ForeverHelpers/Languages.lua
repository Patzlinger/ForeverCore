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
-- das Addon die Anzeige selbst. Gelesen wird genau das, was Blizzards Liste für die Rollen-Symbole nutzt
-- (Blizzard_LFGVanilla_Browse.lua):
--   einzelner Spieler: C_LFGList.GetSearchResultPlayerInfo(id, 1).lfgRoles.tank/.healer/.dps -> bietet die Rolle an
-- Gruppen bleiben immer drin (gewünscht: der Filter gilt nur für einzelne Spieler). Spieler ohne Rollenangabe
-- fliegen bei aktivem Filter raus.
-- Auswahl in ForeverHelpersDB.lfg.roles.
--
-- !! VERSUCH ENTGEGEN DER TAINT-REGEL (CLAUDE.md, Abschnitt 3), ausdrücklich gewünscht von flowfy (2026-11-13):
--    Unpassende Spieler werden aus Blizzards Ergebnisliste ENTFERNT (hooksecurefunc auf LFGBrowseFrame:UpdateResults,
--    danach Elemente aus Blizzards DataProvider der ScrollBox löschen). Das schreibt in eine Tabelle, die Blizzard-Code
--    liest – mögliche Folge: ADDON_ACTION_BLOCKED beim Einladen/Anschreiben/Bewerben aus der Gruppensuche.
--    Rückweg (Abdunkeln statt Entfernen, regelkonform): git-Markierung "backup/gruppensuche-abdunkeln" (8f52d8e).
--    Nur im Entwicklungsstand: Datei steht in release/exclude-from-release.txt.
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
-- big = Rollen-Symbole der Gruppensuche (LFGBROWSE_GROUPDATA_ATLASES)
local ROLES = {
    { key = "tank", de = "Tank", en = "Tank", big = "groupfinder-icon-role-large-tank" },
    { key = "healer", de = "Heiler", en = "Healer", big = "groupfinder-icon-role-large-heal" },
    { key = "dps", de = "Schaden", en = "Damage", big = "groupfinder-icon-role-large-dps" },
}
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

-- "Gruppen anzeigen" (Häkchen über der Liste): aus = alle Gruppen raus (ForeverHelpersDB.lfg.hideGroups)
local function GroupsHidden()
    local db = _G.ForeverHelpersDB
    return type(db) == "table" and type(db.lfg) == "table" and db.lfg.hideGroups == true
end

-- bleibt der Eintrag in der Liste? (true auch, wenn nichts zu lesen ist)
local function Matches(id)
    local okInfo, info = pcall(C_LFGList.GetSearchResultInfo, id)
    if not (okInfo and type(info) == "table") then return true end
    -- Gruppen: nur das Häkchen "Gruppen anzeigen" zählt; der Rollenfilter gilt nur für einzelne Spieler
    if info.numMembers ~= 1 then return not GroupsHidden() end
    if not RolesActive() then return true end
    local wanted = RoleDB()
    local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, id, 1)
    if not (ok and type(member) == "table") then return true end
    local roles = member.lfgRoles
    -- keine Rolle angegeben (Blizzard zeigt dann kein "Rollen:"): bei aktivem Filter raus – gezeigt werden nur
    -- Spieler, die die Rolle selbst angegeben haben (Wunsch von flowfy, 2026-11-13)
    if type(roles) ~= "table" or not (roles.tank or roles.healer or roles.dps) then return false end
    for _, r in ipairs(ROLES) do
        if wanted[r.key] and roles[r.key] then return true end
    end
    return false
end

-- Nach jedem Neuaufbau von Blizzards Liste (UpdateResults) die unpassenden Spieler aus deren DataProvider
-- entfernen (siehe Warnung oben). In Forever ist das eine BAUM-Liste (Überschriften "Spieler"/"Gruppen", darunter
-- Knoten mit GetData() = { resultID = … }); im klassischen Client eine flache Liste mit { resultID = … }.
-- Erst sammeln, dann entfernen (beim Durchlaufen darf der Baum nicht verändert werden).
local function FilterList(browse)
    if not RolesActive() and not GroupsHidden() then return end
    local box = browse.ScrollBox
    local provider = box and box.GetDataProvider and box:GetDataProvider()
    if not (provider and provider.Remove) then return end
    local drop, headers = {}, {}
    local function Check(item)
        local data = item
        if type(item) == "table" and item.GetData then data = item:GetData() end
        local id = type(data) == "table" and data.resultID
        if type(id) == "number" then
            if not Matches(id) then drop[#drop + 1] = item end
        elseif type(item) == "table" and item.GetNodes then
            headers[#headers + 1] = item -- Überschrift ("Spieler"/"Gruppen"): danach prüfen, ob sie leer ist
        end
    end
    if provider.GetRootNode and provider.ForEach then
        -- Baum: alle Knoten, auch die unter zugeklappten Überschriften (false = IncludeCollapsed)
        provider:ForEach(Check, false)
    elseif provider.Enumerate then
        for _, element in provider:Enumerate() do Check(element) end
    end
    for _, item in ipairs(drop) do provider:Remove(item) end
    -- leer gewordene Überschriften mit entfernen (z. B. "Gruppen" bei ausgeblendeten Gruppen)
    for _, header in ipairs(headers) do
        local nodes = header:GetNodes()
        if type(nodes) == "table" and #nodes == 0 and header.parent then provider:Remove(header) end
    end
end

-- Auswahl geändert: Blizzards Liste aus den vorhandenen Ergebnissen neu aufbauen lassen (keine neue Suche – die
-- darf nur auf Klick); danach filtert der Hook. "Alle Rollen" bringt so alle Einträge zurück.
local function Rebuild(browse)
    if not (browse and browse:IsVisible()) then return end
    if browse.UpdateResultList then
        pcall(browse.UpdateResultList, browse)
    elseif browse.UpdateResults then
        pcall(browse.UpdateResults, browse)
    end
end

---------------------------------------------------------------------------
-- Bedienung: Flaggen-Knopf oben (Sprachen, Menü), runde Rollen-Knöpfe unten
---------------------------------------------------------------------------
-- Flaggen: eigene Grafiken (tools/make-flag-art.ps1), 64x32, die Flagge füllt links 48x32
local FLAGS = "Interface\\AddOns\\ForeverHelpers\\Media\\Flags\\"
local HAS_FLAG = { deDE = true, enUS = true, frFR = true, esES = true, ruRU = true, ptBR = true }
local function FlagTag(lang, h)
    if not HAS_FLAG[lang] then return "" end
    return "|T" .. FLAGS .. lang .. ":" .. h .. ":" .. math.floor(h * 1.5 + 0.5) .. ":0:0:64:32:0:48:0:32|t"
end
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local langButton
local roleButtons = {}

-- Flaggen-Knopf: Flagge der ersten gewählten Sprache, bei mehreren "+N" daneben; alle gewählt = "Alle"
local function UpdateLangButton()
    if not langButton then return end
    local on, all = {}, Available()
    local cur = Current()
    for _, lang in ipairs(all) do
        if cur[lang] then on[#on + 1] = lang end
    end
    local b = langButton
    if #on == 0 or #on == #all then
        b.flag:Hide()
        b.count:ClearAllPoints()
        b.count:SetPoint("CENTER")
        b.count:SetText(T("Alle", "All"))
    else
        local first = on[1]
        if HAS_FLAG[first] then
            b.flag:SetTexture(FLAGS .. first)
            b.flag:SetTexCoord(0, 0.75, 0, 1)
            b.flag:Show()
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.flag, "RIGHT", 1, 0)
            b.count:SetText(#on > 1 and ("+" .. (#on - 1)) or "")
        else
            b.flag:Hide()
            b.count:ClearAllPoints()
            b.count:SetPoint("CENTER")
            b.count:SetText(Short(first) .. (#on > 1 and ("+" .. (#on - 1)) or ""))
        end
    end
end

-- runde Rollen-Knöpfe: an = farbiges Symbol mit goldenem Ring, aus = blass mit grauem Ring
local function UpdateRoleButtons()
    local C = UI.COLOR
    for _, b in ipairs(roleButtons) do
        local on = RoleDB()[b.role.key] and true or false
        b.icon:SetDesaturated(not on)
        b.icon:SetAlpha(on and 1 or 0.45)
        local c = on and C.accent or C.border
        b.ring:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

local function UpdateLabel()
    UpdateLangButton()
    UpdateRoleButtons()
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

-- Menü wie Blizzards Kategorie-Auswahl (Blizzard_Menu): Überschrift, je Sprache Häkchen mit Flagge, "Alle Sprachen".
-- Bleibt beim Anhaken offen (mehrere Sprachen nacheinander).
local function MenuGenerator(_, root)
    root:CreateTitle(T("In diesen Sprachen suchen", "Search in these languages"))
    for _, lang in ipairs(Available()) do
        root:CreateCheckbox(FlagTag(lang, 12) .. "  " .. Name(lang),
            function() return Current()[lang] and true or false end,
            function() Toggle(lang) end)
    end
    root:CreateDivider()
    root:CreateButton(T("Alle Sprachen", "All languages"), function() SetAll() end)
end

local function ToggleRole(key)
    RoleDB()[key] = (not RoleDB()[key]) or nil
    UpdateLabel()
    Rebuild(_G.LFGBrowseFrame)
end

-- Platz unten in der Leiste: zwischen dem linken und rechten Text-Knopf ("Nachricht senden" / "Gruppeneinladung")
local function FooterButtons(browse)
    local bottom = browse:GetBottom()
    if not bottom then return nil end
    local found = {}
    local function Scan(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not (child.IsForbidden and child:IsForbidden()) and child ~= langButton then
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

-- Rollen-Knöpfe mittig in die Lücke unten (zwischen "Nachricht senden" und "Gruppeneinladung")
local ROLE_SIZE, ROLE_GAP = 26, 10
local placed = false
local holder
local function Place(browse)
    if placed or not holder then return end
    local left, right = FooterButtons(browse)
    holder:ClearAllPoints()
    if left and right then
        placed = true
        -- Mitte der Lücke: zwischen rechter Kante des linken und linker Kante des rechten Knopfs
        local spacer = holder.spacer or CreateFrame("Frame", nil, browse)
        holder.spacer = spacer
        spacer:ClearAllPoints()
        spacer:SetPoint("LEFT", left, "RIGHT", 0, 0)
        spacer:SetPoint("RIGHT", right, "LEFT", 0, 0)
        spacer:SetHeight(1)
        holder:SetPoint("CENTER", spacer, "CENTER", 0, 0)
    else
        -- (Knöpfe noch nicht gefunden: vorerst unten mittig; beim nächsten Öffnen erneut versuchen)
        holder:SetPoint("BOTTOM", browse, "BOTTOM", 0, 8)
    end
end

-- runder Knopf: dunkle Scheibe, Ring (Farbe nach Zustand), Rollen-Symbol darin
local function RoleButton(parent, role)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ROLE_SIZE, ROLE_SIZE)
    b.role = role
    local function Disk(size, layer, sub)
        local t = b:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(WHITE)
        t:SetSize(size, size)
        t:SetPoint("CENTER")
        local mask = b:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(t)
        t:AddMaskTexture(mask)
        return t
    end
    b.ring = Disk(ROLE_SIZE, "BACKGROUND", 1)
    local bg = UI.COLOR.background
    b.disk = Disk(ROLE_SIZE - 3, "BACKGROUND", 2)
    b.disk:SetVertexColor(bg[1], bg[2], bg[3], 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ROLE_SIZE - 6, ROLE_SIZE - 6)
    b.icon:SetPoint("CENTER")
    b.icon:SetAtlas(role.big)
    -- Maus darüber: Ring heller gold
    b.hover = Disk(ROLE_SIZE, "HIGHLIGHT", 1)
    local a = UI.COLOR.accent
    b.hover:SetVertexColor(a[1], a[2], a[3], 0.5)
    b:SetScript("OnClick", function(self)
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        ToggleRole(self.role.key)
    end)
    -- (ohne Tooltip – auf Wunsch)
    return b
end

-- Flaggen-Knopf oben rechts neben Aktualisieren: öffnet das Sprach-Menü
local function BuildLangButton(browse)
    -- (schmal und dicht am Aktualisieren-Knopf, etwas tiefer: ragte vorher rechts aus dem Fenster, 2026-11-13)
    langButton = UI.Button(browse, "", 32)
    langButton:SetHeight(20)
    local refresh = browse.RefreshButton
    if refresh then
        langButton:SetPoint("LEFT", refresh, "RIGHT", 2, -3)
    else
        langButton:SetPoint("TOPRIGHT", browse, "TOPRIGHT", -12, -12)
    end
    langButton.flag = langButton:CreateTexture(nil, "ARTWORK")
    langButton.flag:SetSize(18, 12)
    langButton.flag:SetPoint("LEFT", langButton, "LEFT", 3, 0)
    langButton.count = langButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    langButton:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, MenuGenerator) end
    end)
    -- (ohne Tooltip – auf Wunsch)
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
        tip:AddLine(T("Sucht mit allen gewählten Sprachen (Flaggen-Knopf rechts daneben).",
            "Searches with all selected languages (flag button to the right)."), 1, 1, 1, true)
        tip:Show()
    end)
    cover:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)
    cover:SetShown(refresh:IsShown())
    refresh:HookScript("OnShow", function() cover:Show() end)
    refresh:HookScript("OnHide", function() cover:Hide() end)
end

local function Build(browse)
    BuildLangButton(browse)
    holder = CreateFrame("Frame", nil, browse)
    holder:SetSize(#ROLES * ROLE_SIZE + (#ROLES - 1) * ROLE_GAP, ROLE_SIZE)
    for i, role in ipairs(ROLES) do
        local b = RoleButton(holder, role)
        b:SetPoint("LEFT", holder, "LEFT", (i - 1) * (ROLE_SIZE + ROLE_GAP), 0)
        roleButtons[i] = b
    end
    -- Häkchen "Gruppen anzeigen" in der freien Fläche über der Liste (unter der Kategorie-Auswahl)
    local groups = UI.Check(browse, nil, nil, T("Gruppen anzeigen", "Show groups"), function(checked)
        if type(_G.ForeverHelpersDB) ~= "table" then _G.ForeverHelpersDB = {} end
        local db = _G.ForeverHelpersDB
        if type(db.lfg) ~= "table" then db.lfg = {} end
        db.lfg.hideGroups = (not checked) or nil
        Rebuild(browse)
    end)
    local category = browse.CategoryDropdown or browse.CategoryDropDown
    if category then
        groups:SetPoint("TOPLEFT", category, "BOTTOMLEFT", 2, -10)
    else
        groups:SetPoint("TOPLEFT", browse, "TOPLEFT", 16, -48)
    end
    groups:SetChecked(not GroupsHidden())
    browse:HookScript("OnShow", function() groups:SetChecked(not GroupsHidden()) end)
    -- nach jedem Neuaufbau der Liste filtern (siehe Warnung oben)
    if type(browse.UpdateResults) == "function" then
        local reported = false
        hooksecurefunc(browse, "UpdateResults", function(self)
            local ok, err = pcall(FilterList, self)
            if not ok and not reported then
                reported = true
                if UI.ReportError then UI.ReportError("ForeverHelpers", "Languages/Roles", err) end
            end
        end)
    end
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
    if langButton then return end
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
