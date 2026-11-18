-- ForeverCoreUI – Probe.lua: Messbefehl /fprobe. Prüft harmlose Abfragen einmal außerhalb und einmal im Kampf und
-- zeigt je Abfrage: ok / gesperrt (Wert ist ein "secret value") / Fehler. So steht fest, was im Kampf WIRKLICH geht,
-- statt es anzunehmen. Es wird nichts Geschütztes angefasst (keine Aktionsknöpfe, keine sicheren Rahmen).
-- Ablauf: /fprobe = jetzt messen (außerhalb) und für den nächsten Kampf vormerken; die Kampfmessung läuft 2 s nach
-- Kampfbeginn, der Vergleich erscheint nach dem Kampf im Chat. /fprobe zeigen = letzten Vergleich nochmal anzeigen.
-- Zum Entfernen: diese Datei und die Zeile "Probe.lua" in der .toc löschen.
local hub = _G.ForeverHub
if type(hub) ~= "table" or type(hub.UI) ~= "table" then return end
local UI = hub.UI
local T = UI.T or function(de) return de end

local isSecret = _G.issecretvalue or function() return false end

-- Jede Abfrage liefert (Wert) oder wirft; ein gesperrter Wert wird als "gesperrt" erkannt.
local PROBES = {
    { "Leben (player)",        function() return UnitHealth("player") end },
    { "Leben max (player)",    function() return UnitHealthMax("player") end },
    { "Leben (target)",        function() return UnitExists("target") and UnitHealth("target") or 0 end },
    { "Mana/Kraft (player)",   function() return UnitPower("player") end },
    { "GUID (player)",         function() return UnitGUID("player") end },
    { "Name (target)",         function() return UnitExists("target") and UnitName("target") or "-" end },
    { "Klasse (target)",       function() return UnitExists("target") and select(2, UnitClass("target")) or "-" end },
    { "Ist Spieler (target)",  function() return UnitExists("target") and UnitIsPlayer("target") or false end },
    { "Aura 1 (player)",       function() local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL") return a and a.name or "-" end },
    { "Aura-Dauer (player)",   function() local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL") return a and a.expirationTime or 0 end },
    { "Zauber lesen (Aura-ID)",function() local a = C_UnitAuras.GetAuraDataByIndex("player", 1, "HELPFUL") return a and a.spellId or 0 end },
    { "Abklingzeit (GCD)",     function() local c = C_Spell.GetSpellCooldown(61304) return c and c.duration or 0 end },
    { "Zauberinfo (Name)",     function() local i = C_Spell.GetSpellInfo(133) return i and i.name or "-" end },
    { "Zauberkosten",          function() return C_Spell.GetSpellPowerCost and #(C_Spell.GetSpellPowerCost(133) or {}) or 0 end },
    { "Wirkt gerade (player)", function() return UnitCastingInfo("player") or "-" end },
    { "Item-Info",             function() return C_Item.GetItemInfo(6948) or "-" end },
    { "Item im Slot",          function() return GetInventoryItemLink("player", 16) or "-" end },
    { "Tooltip-Daten Zauber",  function() local d = C_TooltipInfo and C_TooltipInfo.GetSpellByID(133) return d and d.type or "-" end },
    { "Geschwindigkeit",       function() return GetUnitSpeed("player") end },
    { "Kartenposition",        function() local m = C_Map.GetBestMapForUnit("player") return m or 0 end },
    { "Gruppe: Mitglieder",    function() return GetNumGroupMembers() end },
    { "Textur anlegen",        function() local f = CreateFrame("Frame") local t = f:CreateTexture() t:SetColorTexture(1, 1, 1) return "ok" end },
    { "Schrift anlegen",       function() local f = CreateFrame("Frame") local s = f:CreateFontString(nil, "OVERLAY", "GameFontNormal") s:SetText("x") return "ok" end },
    { "Rahmen anzeigen/verstecken", function() local f = CreateFrame("Frame") f:Show() f:Hide() return "ok" end },
    { "Rahmen verschieben",    function() local f = CreateFrame("Frame", nil, UIParent) f:SetPoint("CENTER") f:SetSize(10, 10) return "ok" end },
    { "StatusBar-Wert",        function() local b = CreateFrame("StatusBar") b:SetMinMaxValues(0, 100) b:SetValue(UnitHealth("player")) return "ok" end },
}

local function Run()
    local out = {}
    for _, p in ipairs(PROBES) do
        local ok, v = pcall(p[2])
        if not ok then out[p[1]] = "Fehler"
        elseif isSecret(v) then out[p[1]] = "gesperrt"
        else out[p[1]] = "ok" end
    end
    return out
end

local before, during, armed
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

local function Report()
    if not before or not during then
        print("|cffffd100ForeverProbe|r " .. T("Noch keine Kampfmessung. /fprobe eingeben und einen Kampf beginnen.", "No combat measurement yet. Type /fprobe, then enter combat."))
        return
    end
    print("|cffffd100ForeverProbe|r " .. T("Abfrage: außerhalb → im Kampf", "Query: outside → in combat"))
    local diff = 0
    for _, p in ipairs(PROBES) do
        local a, b = before[p[1]], during[p[1]]
        local color = (a == b) and "|cff80ff80" or "|cffff8080"
        if a ~= b then diff = diff + 1 end
        print(("  %s%s|r: %s → %s"):format(color, p[1], a, b))
    end
    print("|cffffd100ForeverProbe|r " .. T("Unterschiede im Kampf: ", "Differences in combat: ") .. diff)
    _G.ForeverHubDB = type(_G.ForeverHubDB) == "table" and _G.ForeverHubDB or {}
    _G.ForeverHubDB.probe = { before = before, during = during, date = date("%Y-%m-%d %H:%M") }
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" and armed then
        C_Timer.After(2, function()
            if InCombatLockdown() then during = Run() end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" and armed and during then
        armed = false
        Report()
    end
end)

SLASH_FOREVERPROBE1 = "/fprobe"
SlashCmdList["FOREVERPROBE"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "zeigen" or msg == "show" then Report() return end
    if InCombatLockdown() then
        during = Run()
        print("|cffffd100ForeverProbe|r " .. T("Kampfmessung gespeichert. Nach dem Kampf: /fprobe zeigen", "Combat measurement saved. After combat: /fprobe show"))
        armed = true
        return
    end
    before, during, armed = Run(), nil, true
    print("|cffffd100ForeverProbe|r " .. T("Messung außerhalb des Kampfes fertig. Beim nächsten Kampf wird nach 2 s erneut gemessen; der Vergleich erscheint nach dem Kampf.", "Out-of-combat measurement done. The next fight is measured after 2 s; the comparison is shown after combat."))
end
