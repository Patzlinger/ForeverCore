-- ForeverAlts – Flights.lua (PROTOTYP): merkt sich, welche Flugpunkte jeder Charakter kennt, und zeigt sie im
-- Fenster "Flugpunkte" (Suchfeld + Liste je Flugpunkt: welcher Charakter ihn hat). Gelesen wird nur, wenn man beim
-- Flugmeister die Flugkarte öffnet (nur dann liefert das Spiel die Liste). Gespeichert pro Charakter in
-- ForeverAltsData.chars[Schlüssel].flights = { ["Flugpunkt-Name"] = true (bekannt) / false (noch nicht entdeckt) }.
-- Entfernen: diese Datei + die .toc-Zeile + den Knopf in Window.lua + den Zweig "flug" in Options.lua.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T

local issecret = issecretvalue or function() return false end

-- Alle Flugpunkte der geöffneten Flugkarte lesen: { name = bekannt? }
local function ReadNodes()
    local out, n = {}, 0
    if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then -- klassische Flugkarte
        for i = 1, NumTaxiNodes() do
            local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
            if name and not issecret(name) and not issecret(kind) then
                -- bekannt = CURRENT (hier) oder REACHABLE; DISTANT/NONE = nicht entdeckt (der erste Versuch zählte
                -- DISTANT mit: alle Punkte waren "ja"). Auszählung der Typen für /falts flug dump:
                out[name] = (kind == "CURRENT" or kind == "REACHABLE")
                ns.flightTally = ns.flightTally or {}
                ns.flightTally[tostring(kind)] = (ns.flightTally[tostring(kind)] or 0) + 1
                n = n + 1
            end
        end
    elseif C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then -- neuere Form (Karten-Nummer der Flugkarte)
        local mapID = GetTaxiMapID and GetTaxiMapID()
        local nodes = mapID and C_TaxiMap.GetAllTaxiNodes(mapID)
        for _, node in ipairs(nodes or {}) do
            if node.name and not issecret(node.name) then
                out[node.name] = not (Enum and Enum.FlightPathState and node.state == Enum.FlightPathState.Unreachable)
                n = n + 1
            end
        end
    end
    return out, n
end

local function Store()
    local c = ns.CharacterData(ns.CharKey())
    if not c then return end
    ns.flightTally = {}
    local nodes, n = ReadNodes()
    if n == 0 then return end
    if c.flightsV ~= 2 then c.flights, c.flightsV = {}, 2 end -- Daten des ersten Versuchs (alles "ja") verwerfen
    c.flights = c.flights or {}
    for name, known in pairs(nodes) do
        if known then
            c.flights[name] = true
        elseif c.flights[name] == nil then
            c.flights[name] = false -- bekannt bleibt bekannt
        end
    end
    c.flightsAt = time()
    if ns.RefreshFlights then ns.RefreshFlights() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("TAXIMAP_OPENED")
pcall(events.RegisterEvent, events, "NEW_TAXI_NODE") -- neuer Flugpunkt entdeckt: Karte kurz danach neu lesen
events:SetScript("OnEvent", ns.Safe("Flugpunkte", function(_, event)
    if event == "NEW_TAXI_NODE" then
        C_Timer.After(1, ns.Safe("Flugpunkte", Store))
    else
        Store()
    end
end))

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local window, search, text
local ROWS_MAX = 40

local function Matches(name, filter)
    return filter == "" or name:lower():find(filter, 1, true) ~= nil
end

function ns.RefreshFlights()
    if not (window and window:IsShown()) then return end
    local filter = strtrim(search:GetText() or ""):lower()
    local chars, all = {}, {}
    for _, entry in ipairs(ns.Characters()) do
        if not entry.data.hidden then
            chars[#chars + 1] = entry
            for name in pairs(entry.data.flights or {}) do all[name] = true end
        end
    end
    if #chars == 0 or next(all) == nil then
        text:SetText(T("Noch keine Flugpunkte gespeichert.\nÖffne bei einem Flugmeister die Flugkarte – jeder Charakter muss das einmal tun.",
            "No flight points saved yet.\nOpen the flight map at a flight master – every character has to do this once."))
        return
    end
    local names = {}
    for name in pairs(all) do
        if Matches(name, filter) then names[#names + 1] = name end
    end
    table.sort(names)
    local lines = {}
    for i = 1, math.min(#names, ROWS_MAX) do
        local name = names[i]
        local parts = {}
        for _, entry in ipairs(chars) do
            local state = entry.data.flights and entry.data.flights[name]
            local who = ns.ColoredName(entry.data) or entry.data.name or "?"
            if state then
                parts[#parts + 1] = who .. " |cff40ff40" .. T("ja", "yes") .. "|r"
            elseif state == false then
                parts[#parts + 1] = who .. " |cffff6060" .. T("nein", "no") .. "|r"
            else
                parts[#parts + 1] = who .. " |cff888888?|r" -- Karte dieses Charakters noch nie gesehen
            end
        end
        lines[#lines + 1] = "|cffffd100" .. name .. "|r\n    " .. table.concat(parts, "   ")
    end
    if #names == 0 then lines[1] = T("Kein Flugpunkt mit diesem Namen.", "No flight point with that name.") end
    if #names > ROWS_MAX then
        lines[#lines + 1] = "… " .. (#names - ROWS_MAX) .. T(" weitere – Suche eingrenzen", " more – narrow the search")
    end
    text:SetText(table.concat(lines, "\n"))
end

function ns.ToggleFlights(filter)
    if not window then
        window = UI.Window("ForeverAltsFlights", T("Flugpunkte", "Flight points"), 460, 460)
        local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 16, -34)
        hint:SetText(T("Suche (Teil des Namens):", "Search (part of the name):"))
        search = UI.EditBox(window, 200, 22)
        search:SetPoint("TOPLEFT", 16, -52)
        search:SetScript("OnTextChanged", ns.Safe("Flugpunkte", ns.RefreshFlights))
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local scroll = CreateFrame("ScrollFrame", nil, window)
        scroll:SetPoint("TOPLEFT", 16, -84)
        scroll:SetPoint("BOTTOMRIGHT", -16, 36)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(420, 1)
        scroll:SetScrollChild(content)
        text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT")
        text:SetWidth(420)
        text:SetJustifyH("LEFT")
        text:SetSpacing(3)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = math.max(0, text:GetStringHeight() - self:GetHeight())
            self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * 40)))
        end)
        local note = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("BOTTOMLEFT", 16, 14)
        note:SetText(T("Prototyp – wird beim Öffnen der Flugkarte aktualisiert",
            "Prototype – updated when the flight map is opened"))
        window:HookScript("OnShow", ns.Safe("Flugpunkte", ns.RefreshFlights))
    end
    if filter and filter ~= "" then
        search:SetText(filter)
        window:Show()
    else
        window:SetShown(not window:IsShown())
    end
    ns.RefreshFlights()
end
