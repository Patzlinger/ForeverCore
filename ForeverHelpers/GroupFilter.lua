-- ForeverHelpers – GroupFilter.lua: Rollenfilter für "Suche nach Gruppe" > Durchsuchen (LFGBrowseFrame).
-- Unter dem Fenster sitzt eine kleine Leiste mit drei Knöpfen (Tank, Heiler, Schaden). Ist mindestens eine Rolle
-- gewählt, werden alle Einträge ABGEDUNKELT, die nicht passen:
--   einzelner Spieler -> passt, wenn er eine der gewählten Rollen anbietet
--   Gruppe            -> passt, wenn ihr eine der gewählten Rollen noch fehlt
-- Lässt sich die Rolle eines Eintrags nicht ermitteln, bleibt er hell (lieber zu viel zeigen als etwas verstecken).
-- Bewusst nur Abdunkeln (SetAlpha) statt Entfernen: Blizzards Ergebnisliste und ihre Tabellen bleiben unberührt
-- (Taint-Regel: nichts in Tabellen legen, die Blizzard-Code liest). Die Auswahl gilt nur für die laufende Sitzung.
-- Prüfbefehl: /flfg check (zeigt, was das Spiel zu den sichtbaren Einträgen liefert).
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR
local function Chat(text) UI.Chat("ForeverHelpers", text) end

local ROLES = {
    { key = "TANK", de = "Tank", en = "Tank", atlas = "UI-LFG-RoleIcon-Tank", coords = { 0, 19 / 64, 22 / 64, 41 / 64 } },
    { key = "HEALER", de = "Heiler", en = "Healer", atlas = "UI-LFG-RoleIcon-Healer", coords = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 } },
    { key = "DAMAGER", de = "Schaden", en = "Damage", atlas = "UI-LFG-RoleIcon-DPS", coords = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 } },
}
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local DIM = 0.3      -- Deckkraft unpassender Einträge
local selected = {}  -- [Rolle] = true
local cache = {}     -- [Ergebnis-ID] = passt (true/false); geleert bei neuer Suche und neuer Auswahl
local dimmed = setmetatable({}, { __mode = "k" }) -- [Eintrag] = true (von uns abgedunkelt)

---------------------------------------------------------------------------
-- Daten eines Eintrags (nur lesen, alles abgesichert – der Aufbau der Rückgaben ist je Client verschieden)
---------------------------------------------------------------------------
local function Pack(ok, ...)
    if ok then return select("#", ...), { ... } end
    return 0
end
local function Call(name, ...)
    local fn = C_LFGList and C_LFGList[name]
    if type(fn) ~= "function" then return 0 end
    return Pack(pcall(fn, ...))
end

-- Rollen in einer Rückgabe finden: Texte "TANK"/"HEALER"/"DAMAGER" oder Felder wie tank = true, soloRoleHealer = true
local function Scan(value, found, depth)
    if type(value) == "string" then
        local s = value:upper()
        if s == "TANK" then found.TANK = true
        elseif s == "HEALER" then found.HEALER = true
        elseif s == "DAMAGER" or s == "DPS" then found.DAMAGER = true end
    elseif type(value) == "table" then
        for k, v in pairs(value) do
            if v == true and type(k) == "string" then
                local key = k:lower()
                if key:find("tank") then found.TANK = true
                elseif key:find("heal") then found.HEALER = true
                elseif key:find("dps") or key:find("damage") then found.DAMAGER = true end
            elseif depth < 2 and (type(v) == "string" or type(v) == "table") then
                Scan(v, found, depth + 1)
            end
        end
    end
end

local function Counts(id)
    local n, values = Call("GetSearchResultMemberCounts", id)
    if n > 0 and type(values[1]) == "table" then return values[1] end
end

-- Rollen, die ein einzelner Spieler anbietet (nil = unbekannt)
local function Offered(id)
    local found = {}
    for _, name in ipairs({ "GetSearchResultLeaderInfo", "GetSearchResultPlayerInfo", "GetSearchResultMemberInfo" }) do
        local n, values = Call(name, id, 1)
        for i = 1, n do Scan(values[i], found, 1) end
    end
    if not next(found) then
        local counts = Counts(id)
        if counts then
            for _, role in ipairs(ROLES) do
                if type(counts[role.key]) == "number" and counts[role.key] > 0 then found[role.key] = true end
            end
        end
    end
    return next(found) and found or nil
end

local function MaxPlayers(info)
    local activityID = info.activityID or (type(info.activityIDs) == "table" and info.activityIDs[1])
    if not activityID then return nil end
    local n, values = Call("GetActivityInfoTable", activityID)
    local activity = n > 0 and values[1]
    return type(activity) == "table" and activity.maxNumPlayers or nil
end

-- Rollen, die einer Gruppe noch fehlen (nil = unbekannt)
local function Needed(id, info)
    local counts = Counts(id)
    if not counts then return nil end
    if type(counts.TANK_REMAINING) == "number" then
        return {
            TANK = counts.TANK_REMAINING > 0,
            HEALER = (counts.HEALER_REMAINING or 0) > 0,
            DAMAGER = (counts.DAMAGER_REMAINING or 0) > 0,
        }
    end
    -- ohne "REMAINING": nur bei 5er-Gruppen eindeutig (1 Tank, 1 Heiler, 3 Schaden) und wenn alle eine Rolle haben
    if MaxPlayers(info) ~= 5 or (counts.NOROLE or 0) > 0 then return nil end
    return {
        TANK = (counts.TANK or 0) < 1,
        HEALER = (counts.HEALER or 0) < 1,
        DAMAGER = (counts.DAMAGER or 0) < 3,
    }
end

local function Matches(id)
    local n, values = Call("GetSearchResultInfo", id)
    local info = n > 0 and values[1]
    if type(info) ~= "table" then return true end
    local roles
    if info.numMembers == 1 then roles = Offered(id) else roles = Needed(id, info) end
    if not roles then return true end
    for role in pairs(selected) do
        if roles[role] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Einträge der Liste
---------------------------------------------------------------------------
local function Forbidden(frame) return frame.IsForbidden and frame:IsForbidden() end

local lists -- Listen (ScrollBox) der Seite, einmal gesucht
local function FindLists(frame, depth, out)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child.GetScrollTarget then out[#out + 1] = child
            elseif depth < 3 then FindLists(child, depth + 1, out) end
        end
    end
    return out
end

local function ResultID(entry)
    local id = entry.resultID
    if type(id) ~= "number" and entry.GetElementData then
        local ok, data = pcall(entry.GetElementData, entry)
        if ok and type(data) == "table" then id = data.resultID or data.id
        elseif ok and type(data) == "number" then id = data end
    end
    return type(id) == "number" and id or nil
end

local function ForEachEntry(browse, fn)
    if not lists or #lists == 0 then lists = FindLists(browse, 1, {}) end
    for _, list in ipairs(lists) do
        local target = list:GetScrollTarget()
        if target then
            for _, entry in ipairs({ target:GetChildren() }) do
                if not Forbidden(entry) and entry:IsShown() then fn(entry) end
            end
        end
    end
end

local function Apply(browse)
    local active = next(selected) ~= nil
    ForEachEntry(browse, function(entry)
        local match = true
        local id = active and ResultID(entry)
        if id then
            if cache[id] == nil then
                local ok, result = pcall(Matches, id)
                cache[id] = (not ok) or result
            end
            match = cache[id]
        end
        if match then
            if dimmed[entry] then
                dimmed[entry] = nil
                entry:SetAlpha(1)
            end
        else
            dimmed[entry] = true
            entry:SetAlpha(DIM)
        end
    end)
end

---------------------------------------------------------------------------
-- Leiste unter dem Fenster
---------------------------------------------------------------------------
local bar
local function Refresh()
    if not bar then return end
    for _, b in ipairs(bar.buttons) do
        if selected[b.role] then
            b:SetBackdropColor(C.header[1], C.header[2], C.header[3], 1)
            b:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        else
            b:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
            b:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        end
    end
    bar.hint:SetShown(next(selected) ~= nil)
    if not next(selected) then -- Filter aus: alles, was wir abgedunkelt haben, sofort wieder hell
        for entry in pairs(dimmed) do entry:SetAlpha(1) end
        wipe(dimmed)
    end
    wipe(cache)
    bar.waited = 1 -- sofort anwenden
end

local function Build(browse)
    local parent = _G.LFGParentFrame or browse
    bar = UI.Box(browse)
    bar:SetHeight(30)
    bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    bar:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
    bar:EnableMouse(true) -- (Klicks neben den Knöpfen nicht in die Spielwelt durchlassen)
    local label = UI.Text(bar, "field", T("Rolle:", "Role:"))
    label:SetPoint("LEFT", bar, "LEFT", 10, 0)
    bar.buttons = {}
    local prev = label
    for _, role in ipairs(ROLES) do
        local b = UI.Button(bar, T(role.de, role.en), 80, function(self)
            selected[self.role] = (not selected[self.role]) or nil
            Refresh()
        end)
        b.role = role.key
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", b, "LEFT", 6, 0)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(role.atlas) then
            icon:SetAtlas(role.atlas)
        else
            icon:SetTexture(ROLE_TEXTURE)
            icon:SetTexCoord(role.coords[1], role.coords[2], role.coords[3], role.coords[4])
        end
        local text = b:GetFontString()
        if text then
            text:ClearAllPoints()
            text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            b:SetWidth(math.max(60, math.floor(6 + 14 + 4 + (text:GetStringWidth() or 40) + 10)))
        end
        b:SetPoint("LEFT", prev, "RIGHT", prev == label and 8 or 6, 0)
        b:HookScript("OnEnter", function(self)
            local tip = UI.GetTooltip()
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:SetText(T(role.de, role.en), 1, 0.82, 0)
            tip:AddLine(T("Zeigt Spieler, die diese Rolle anbieten, und Gruppen, denen sie noch fehlt. Alles andere wird abgedunkelt. Noch einmal klicken = aus.",
                "Shows players who offer this role and groups that still need it. Everything else is dimmed. Click again = off."),
                1, 1, 1, true)
            tip:Show()
        end)
        b:HookScript("OnLeave", function() UI.GetTooltip():Hide() end)
        bar.buttons[#bar.buttons + 1] = b
        prev = b
    end
    bar.hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.hint:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    bar.hint:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    bar.hint:SetJustifyH("LEFT")
    bar.hint:SetWordWrap(false)
    bar.hint:SetText(T("Unpassende Einträge sind abgedunkelt", "Entries that don't match are dimmed"))
    -- neue Suchergebnisse: neu bewerten
    for _, event in ipairs({ "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED" }) do
        pcall(bar.RegisterEvent, bar, event)
    end
    bar:SetScript("OnEvent", function() wipe(cache) end)
    -- läuft nur, solange die Seite "Durchsuchen" offen ist (die Leiste gehört zu ihr); Blizzard füllt die Einträge
    -- beim Blättern neu – darum im Takt statt einmalig
    bar.waited = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        self.waited = self.waited + elapsed
        if self.waited < 0.15 then return end
        self.waited = 0
        if not next(selected) and not next(dimmed) then return end
        local ok, err = pcall(Apply, browse)
        if not ok and not self.reported then
            self.reported = true
            if UI.ReportError then UI.ReportError("ForeverHelpers", "GroupFilter", err) end
        end
    end)
    Refresh()
end

local events = CreateFrame("Frame")
local function TryBuild()
    if bar then return end
    local browse = _G.LFGBrowseFrame
    if type(browse) ~= "table" or not browse.GetObjectType or Forbidden(browse) then return end
    if InCombatLockdown() then
        if UI.AfterCombat then UI.AfterCombat("ForeverHelpers:GroupFilter", TryBuild, "ForeverHelpers") end
        return
    end
    local ok, err = pcall(Build, browse)
    if not ok and UI.ReportError then UI.ReportError("ForeverHelpers", "GroupFilter/Build", err) end
    events:UnregisterAllEvents()
end
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED") -- (falls Blizzard die Gruppensuche erst bei Bedarf lädt)
events:SetScript("OnEvent", TryBuild)

---------------------------------------------------------------------------
-- /flfg: Hilfe · /flfg aus · /flfg check (Prüfbefehl: was liefert das Spiel zu den sichtbaren Einträgen?)
---------------------------------------------------------------------------
local function Describe(value)
    if type(value) ~= "table" then return tostring(value) end
    local parts = {}
    for k, v in pairs(value) do
        parts[#parts + 1] = tostring(k) .. "=" .. (type(v) == "table" and "{…}" or tostring(v))
        if #parts >= 14 then parts[#parts + 1] = "…" break end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function Check()
    local browse = _G.LFGBrowseFrame
    if not (browse and browse:IsVisible()) then
        Chat(T("Erst „Suche nach Gruppe“ > Durchsuchen öffnen und suchen, dann /flfg check.",
            "Open \"Looking for Group\" > Browse and search first, then /flfg check."))
        return
    end
    local count = 0
    ForEachEntry(browse, function(entry)
        if count >= 4 then return end
        count = count + 1
        local id = ResultID(entry)
        Chat(string.format("#%d ID %s", count, tostring(id)))
        if not id then return end
        for _, name in ipairs({ "GetSearchResultInfo", "GetSearchResultMemberCounts", "GetSearchResultLeaderInfo",
            "GetSearchResultPlayerInfo", "GetSearchResultMemberInfo" }) do
            local n, values = Call(name, id, 1)
            local out = {}
            for i = 1, math.min(n, 8) do out[i] = Describe(values[i]) end
            Chat("  " .. name .. ": " .. (n > 0 and table.concat(out, " | ") or "–"))
        end
        local n, values = Call("GetSearchResultInfo", id)
        local info = n > 0 and values[1]
        local roles = type(info) == "table" and (info.numMembers == 1 and Offered(id) or Needed(id, info)) or nil
        Chat("  " .. T("erkannt: ", "detected: ") .. (roles and Describe(roles) or T("unbekannt (bleibt hell)", "unknown (stays bright)")))
    end)
    if count == 0 then Chat(T("Keine sichtbaren Einträge gefunden.", "No visible entries found.")) end
end

SLASH_FOREVERLFG1 = "/flfg"
SLASH_FOREVERLFG2 = "/foreverlfg"
SlashCmdList["FOREVERLFG"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "check" then
        local ok, err = pcall(Check)
        if not ok then Chat(tostring(err)) end
    elseif msg == "aus" or msg == "off" then
        wipe(selected)
        Refresh()
        Chat(T("Rollenfilter aus.", "Role filter off."))
    else
        Chat(T("Rollenfilter: Knöpfe unter dem Fenster „Suche nach Gruppe“ > Durchsuchen. /flfg aus · /flfg check",
            "Role filter: buttons below the \"Looking for Group\" > Browse window. /flfg off · /flfg check"))
    end
end
