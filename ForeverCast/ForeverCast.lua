-- ForeverCast: minimalistische Zauberleiste mit Ping, Lag und Spell-Queue-Fenster
local ADDON_NAME, ns = ...

local GCD_SPELL = 61304   -- interne Zauber-ID der globalen Abklingzeit
local FADE_TIME = 0.5     -- so lange blendet die Leiste nach dem Zauber aus
local BAR_WIDTH = 290

-- Farben je Look (Look.lua: Forever gedämpft, Clean kräftig wie früher); die Tabellen bleiben dieselben
local COLOR_CAST    = ns.COLORS.cast     -- normaler Zauber (gold)
local COLOR_CHANNEL = ns.COLORS.channel  -- kanalisierter Zauber (blau)
local COLOR_QUEUE   = ns.COLORS.queue    -- jetzt kann der naechste Zauber gedrueckt werden
local COLOR_FAIL    = ns.COLORS.fail     -- unterbrochen / fehlgeschlagen
local COLOR_IDLE    = ns.COLORS.idle     -- Platzhalter zum Verschieben
local COLOR_FLIGHT  = ns.COLORS.flight   -- Flugzeit (violett)

-- Kanalisierte Zauber und ihre Anzahl Ticks. Die Zauber-ID dient nur dazu, den
-- Namen in der Client-Sprache herauszufinden; erkannt wird dann am Namen (alle Raenge).
local CHANNEL_TICKS = {
    [5143]  = 5,   -- Arkane Geschosse
    [15407] = 3,   -- Gedankenschinden
    [689]   = 5,   -- Blutsauger
    [1120]  = 5,   -- Seelendieb
    [5138]  = 5,   -- Mana entziehen
    [755]   = 10,  -- Lebenslinie
    [10]    = 8,   -- Blizzard
    [5740]  = 4,   -- Feuerregen
    [16914] = 10,  -- Hurrikan
    [740]   = 5,   -- Gelassenheit
    [1510]  = 6,   -- Salve
    [12051] = 4,   -- Hervorrufung
    [746]   = 8,   -- Erste Hilfe (Verbaende)
}

-- Zauber, die zum Gasthaus zurueckbringen: Ruhestein, Astraler Rueckruf
local HEARTH_SPELLS = { [8690] = true, [556] = true }

---------------------------------------------------------------------------
-- Sprache: deutscher Client auf Deutsch, alle anderen auf Englisch
---------------------------------------------------------------------------
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
local T = UI.T

---------------------------------------------------------------------------
-- Einstellungen (SavedVariables)
---------------------------------------------------------------------------
local DEFAULTS = {
    locked = true, -- gesperrt starten; entsperren per Menue, Minimap-Rechtsklick oder /fmove
    showIcon = true,
    showLatency = true,
    showQueue = true,
    showGCD = false, -- standardmaessig aus, im Einstellungsfenster einschaltbar
    showTicks = true,
    showPushback = true,
    showFlight = true,
    showCraft = true,
    showExpect = true,
    showInstant = true,
    showMelee = true,
    showCombo = false,  -- Combopunkte zeigen ForeverUnits/ForeverPlates; hier nur auf Wunsch
    hideBlizzard = true,
    look = "forever",   -- "forever" (flach, Goldlinie) oder "clean" (bisheriger Look) – Look.lua
    -- Zauberleisten für Ziel und Fokus (Units.lua): standardmäßig aus; angedockt unter den ForeverUnits-Rahmen
    targetBar = false,
    focusBar = false,
    unitDock = true,
    unitHeight = 18,
    unitWidth = 220,    -- nur frei platziert (angedockt: so breit wie der Rahmen)
    showMirror = true,  -- Atem/Erschöpfung im Forever-Stil statt Blizzards Leisten (Mirror.lua)
    minimapAngle = 130,
    width = BAR_WIDTH,  -- Laenge der Leiste in Pixeln
    height = 24,        -- Hoehe der Leiste in Pixeln
    gridShow = true,    -- Raster beim Ziehen / bei offenen Einstellungen (nur entsperrt)
    gridSize = 32,
    snap = true,        -- an Rahmen, Bildschirmmitte und Raster einrasten
}

-- Wegen des Beta-Bugs wird ForeverCastDB bei jedem Zugriff neu geprueft;
-- fehlende Werte werden mit den Standardwerten aufgefuellt.
-- "__fresh" markiert eine selbst angelegte (also NICHT geladene) Tabelle – der Selbsttest
-- erkennt daran, ob die SavedVariables beim Login wirklich geladen wurden.
local db
local function GetDB()
    if type(_G.ForeverCastDB) ~= "table" then
        _G.ForeverCastDB = db or { __fresh = true }
    end
    db = _G.ForeverCastDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    db.flights = db.flights or {} -- gemerkte Flugzeiten: ["Start → Ziel"] = Sekunden
    -- einmalig: Combopunkte an der Leiste standardmäßig aus (zeigen ForeverUnits/ForeverPlates)
    if not db.comboOffV2 then
        db.showCombo = false
        db.comboOffV2 = true
    end
    return db
end
ns.GetDB = GetDB

---------------------------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------------------------
local function IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

local function Chat(text)
    UI.Chat("ForeverCast", text)
end

-- Fehlerschutz (gemeinsam im ForeverHub): ein Fehler in einem Teil legt nicht das ganze Addon lahm.
-- Jeder Fehler wird nur EINMAL pro Stelle im Chat gemeldet (und an BugSack weitergegeben).
local errorCount = 0
local function ReportError(where, err)
    errorCount = errorCount + 1
    UI.ReportError("ForeverCast", where, err)
end

local function Safe(where, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then ReportError(where, err) end
    end
end

local function GetCVarValue(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar(name)
end

local function SetCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then return C_CVar.SetCVar(name, value) end
    return SetCVar(name, value)
end

local function GetSpellNameByID(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function GetSpellNameAndIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, info.iconID end
    elseif GetSpellInfo then
        local n, _, tex = GetSpellInfo(spellID)
        return n, tex
    end
end

-- "1:24" fuer Flugzeiten
local function FormatClock(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function FormatNumber(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

-- Spell-Queue-Fenster in Sekunden (Spieleinstellung, Standard 400 ms)
local queueWindow = 0.4
local function RefreshQueueWindow()
    queueWindow = (tonumber(GetCVarValue("SpellQueueWindow")) or 400) / 1000
end

-- Ping zum Weltserver in Millisekunden
local function GetPing()
    local _, _, home, world = GetNetStats()
    return world or home or 0
end

-- Gemessene Verzoegerung zwischen "Taste gedrueckt" und "Zauber startet"
local sentTime, measuredLag

local function GetLag()
    if measuredLag and measuredLag < 1 then return measuredLag end
    return GetPing() / 1000
end

local function PingColor(ms)
    if ms < 100 then return "|cff33ff33" end
    if ms < 200 then return "|cffffff33" end
    return "|cffff3333"
end

-- Tick-Anzahl fuer einen kanalisierten Zauber (Namen werden bei Bedarf nachgeladen)
local ticksByName = {}
local function GetChannelTicks(name)
    if ticksByName[name] then return ticksByName[name] end
    for id, ticks in pairs(CHANNEL_TICKS) do
        local spellName = GetSpellNameByID(id)
        if spellName then ticksByName[spellName] = ticks end
    end
    return ticksByName[name]
end

-- Ruhestein & Co. erkennen (an der ID oder am Namen, z. B. bei Ruhestein-Spielzeugen)
local hearthNames
local function IsHearth(spellID, name)
    if not IsSecret(spellID) and spellID and HEARTH_SPELLS[spellID] then return true end
    if not hearthNames then
        hearthNames = {}
        for id in pairs(HEARTH_SPELLS) do
            local n = GetSpellNameByID(id)
            if n then hearthNames[n] = true end
        end
    end
    return name and hearthNames[name] or false
end

---------------------------------------------------------------------------
-- Erwartungswerte aus der Zauberbeschreibung
---------------------------------------------------------------------------
-- Wichtig: Hier wird NICHTS selbst berechnet. Blizzard schreibt den aktuellen
-- Schadens-/Heilbereich (inkl. Zauber-/Angriffskraft) in die Beschreibung;
-- das Addon liest diese Zahlen nur ab und zeigt sie an.
local SCHOOLS = {
    { 2, STRING_SCHOOL_HOLY }, { 3, STRING_SCHOOL_FIRE }, { 4, STRING_SCHOOL_NATURE },
    { 5, STRING_SCHOOL_FROST }, { 6, STRING_SCHOOL_SHADOW }, { 7, STRING_SCHOOL_ARCANE },
}
-- Woerter zwischen den Zahlen ("14 bis 22") in verschiedenen Client-Sprachen
local RANGE_WORDS = { "bis", "to", "a", "à", "до" }
local expectCache = {}   -- [spellID] = { low, high, overTime, heal, crit } – fuer den Kampf
local loadRequested = {} -- [spellID] = true: Beschreibung wurde schon einmal angefordert

local function ParseNumber(s)
    return tonumber((s:gsub("[%.,%s]", ""))) -- "1.234" -> 1234
end

local function FindRange(desc)
    local a, b = desc:match("(%d[%d%.,]*)%s*%-%s*(%d[%d%.,]*)")
    if not a then a, b = desc:match("(%d[%d%.,]*)%s*–%s*(%d[%d%.,]*)") end
    if not a then
        for _, word in ipairs(RANGE_WORDS) do
            a, b = desc:match("(%d[%d%.,]*)%s+" .. word .. "%s+(%d[%d%.,]*)")
            if a then break end
        end
    end
    if not a then return nil end
    local low, high = ParseNumber(a), ParseNumber(b)
    if low and high and high >= low then return low, high end
end

-- Schaden/Heilung ueber Zeit (DoT/HoT): "120 Schattenschaden über 18 Sek."
-- oder "im Verlauf von 18 Sek. 120 Schattenschaden". Liefert Menge und Sekunden.
local function FindOverTime(desc)
    local amount, seconds = desc:match("im Verlauf von (%d+[%.,]?%d*) Sek%.?%s*(%d[%d%.,]*)")
    if amount then
        amount, seconds = seconds, amount -- hier steht die Dauer zuerst
    else
        local pos = desc:find("über%s+%d") or desc:find("over%s+%d")
        if not pos then return nil end
        seconds = desc:match("über%s+(%d+[%.,]?%d*)", pos) or desc:match("over%s+(%d+[%.,]?%d*)", pos)
        for n in desc:sub(1, pos - 1):gmatch("(%d[%d%.,]*)") do amount = n end -- letzte Zahl davor
    end
    amount = amount and ParseNumber(amount)
    seconds = seconds and tonumber((seconds:gsub(",", ".")))
    if amount and amount > 0 and seconds and seconds > 0 then return amount, seconds end
end

-- Finishing-Moves (z. B. Ausweiden): eine Zeile pro Combopunkt
-- "1 Punkt: 6-10 Schaden  2 Punkte: 12-16 Schaden ..." bzw. "1 point: 179 damage ..."
local COMBO_WORDS = { "[Pp]unkte?", "[Pp]oints?" }

-- Steht hinter der Zahl eine Zeiteinheit? ("9 Sek.", "9 sec", "1 Min.")
-- Liefert den Faktor in Sekunden (1 oder 60), sonst nil.
local function TimeUnitAt(text, pos)
    local rest = text:sub(pos, pos + 8)
    if rest:match("^%s*[Ss]ek") or rest:match("^%s*[Ss]ec") or rest:match("^%s*s[%s%.,;]") or rest:match("^%s*s$") then
        return 1
    end
    if rest:match("^%s*[Mm]in") then return 60 end
end

-- Welches Wort steht hinter der Zahl? ("80 Rüstung" -> "Rüstung"); nil, wenn keins
local function UnitWordAt(text, pos)
    return text:match("^%s*([^%s%d%.,:;%(%)]+)", pos)
end

-- Ordnet das Wort hinter den Zahlen einer Art zu
local function ClassifyUnit(word)
    if not word then return "damage" end -- "1 Punkt: 6-10" ohne Wort: wie bisher Schaden
    local l = word:lower()
    if l:find("schaden") or l:find("damage") then return "damage" end
    if l:find("heil") or l:find("heal") or l:find("gesundheit") or l:find("health") then return "heal" end
    return "other" -- z. B. "Rüstung" bei Rüstung schwächen
end

-- Liefert die Tabelle [Punkte] = { low, high }, die Art der Werte
-- ("damage", "heal", "duration" oder "other") und bei "other" das Wort dahinter.
-- Beispiele: Ausweiden "1 Punkt: 6-10 Schaden", Zerhaeckseln "1 Punkt: 9 Sek.",
-- Rüstung schwächen "1 Punkt: 80 Rüstung"
local function FindComboRanges(desc)
    local text = (desc:gsub("–", "-"))
    local result, count = {}, 0
    local kind, unitWord

    -- Art einmalig anhand der ersten Zeile festlegen
    local function Classify(pos)
        if kind then return end
        if TimeUnitAt(text, pos) then
            kind = "duration"
        else
            unitWord = UnitWordAt(text, pos)
            kind = ClassifyUnit(unitWord)
        end
    end

    for _, word in ipairs(COMBO_WORDS) do
        for cp, a, b, pos in text:gmatch("(%d)%s*" .. word .. "%s*:%s*(%d[%d%.,]*)%s*%-%s*(%d[%d%.,]*)()") do
            local low, high = ParseNumber(a), ParseNumber(b)
            if low and high then
                Classify(pos)
                local factor = TimeUnitAt(text, pos)
                if factor then low, high = low * factor, high * factor end
                result[tonumber(cp)] = { low = low, high = high }
                count = count + 1
            end
        end
        if count == 0 then -- Variante mit nur einer Zahl pro Punkt
            for cp, a, pos in text:gmatch("(%d)%s*" .. word .. "%s*:%s*(%d[%d%.,]*)()") do
                -- "9,5 Sek." / "9.5 sec": Komma/Punkt als Dezimalzeichen bei Zeiten
                local factor = TimeUnitAt(text, pos)
                local n = factor and tonumber((a:gsub(",", "."):gsub("%.$", ""))) or ParseNumber(a)
                if n then
                    Classify(pos)
                    if factor then n = n * factor end
                    result[tonumber(cp)] = { low = n, high = n }
                    count = count + 1
                end
            end
        end
        if count > 0 then break end
    end
    -- erst ab zwei Zeilen ist es sicher eine Punkte-Tabelle
    if count >= 2 then return result, kind, unitWord end
end

-- Aktuelle Combopunkte (Retail: am Spieler, Classic: am Ziel)
local function GetCurrentCombo()
    local cp
    if UnitPower and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        cp = UnitPower("player", Enum.PowerType.ComboPoints)
    end
    if IsSecret(cp) then return nil end
    if (not cp or cp == 0) and GetComboPoints then
        local alt = GetComboPoints("player", "target")
        if not IsSecret(alt) and alt and alt > 0 then cp = alt end
    end
    return cp
end

-- Einzelne Zahl: "verursacht 45 körperlichen Schaden", "heilt das Ziel um 50"
local function FindSingle(desc, lower)
    if lower:find("absorb") then return nil end -- Schilde: "absorbiert 50 Schaden" ist kein Schaden
    local n
    if lower:find("heilt") or lower:find("heal") then
        n = desc:match("[Hh]eilt[^%d%.]-(%d[%d%.,]*)") or desc:match("[Hh]eals?[^%d%.]-(%d[%d%.,]*)")
            or desc:match("(%d[%d%.,]*)%s+[^%d%.]-[Gg]esundheit") or desc:match("(%d[%d%.,]*)%s+[^%d%.]-health")
    end
    if not n then
        -- Zahl, danach (ohne Satzende) "Schaden"/"damage" – aber nicht "150 % Waffenschaden"
        for num, mid in desc:gmatch("(%d[%d%.,]*)%s+([^%d%.]-)[Ss]chaden") do
            if mid:sub(1, 1) ~= "%" then n = num break end
        end
    end
    n = n or desc:match("(%d[%d%.,]*)%s+[^%d%.]-damage")
    n = n and ParseNumber(n)
    if n and n > 0 then return n end
end

-- Waffenschaden: "Waffenschaden plus 10", "zusätzlich zum normalen Waffenschaden 10 Schaden",
-- "10 damage in addition to your normal weapon damage" oder "150 % Waffenschaden".
local WEAPON_PLUS_PATTERNS = {
    "[Ww]affenschaden plus (%d[%d%.,]*)",
    "[Ww]affenschaden zuzüglich (%d[%d%.,]*)",
    "[Ww]affenschaden %+%s*(%d[%d%.,]*)",
    "zusätzlich zu[mr]?[^%d%.]-[Ww]affenschaden%s+(%d[%d%.,]*)",
    "(%d[%d%.,]*)%s+[^%d%.]-zusätzlich zu[mr]?[^%d%.]-[Ww]affenschaden",
    "[Ww]eapon damage plus (%d[%d%.,]*)",
    "[Ww]eapon damage %+%s*(%d[%d%.,]*)",
    "(%d[%d%.,]*)%s+[^%d%.]-in addition to[^%d%.]-weapon damage",
}

local function FindWeapon(desc)
    for _, pattern in ipairs(WEAPON_PLUS_PATTERNS) do
        local plus = desc:match(pattern)
        if plus then return { weaponPlus = ParseNumber(plus) } end
    end
    local pct = desc:match("(%d+)%s*%%%s*[^%d%.]-[Ww]affenschaden") or desc:match("(%d+)%%%s*[^%d%.]-weapon damage")
    if pct then return { weaponPct = tonumber(pct) } end
end

-- Waffenschaden so, wie ihn das Charakterfenster anzeigt (inkl. Angriffskraft).
-- Im Kampf koennen die Werte gesperrt sein – dann gibt es hier nichts.
local function GetWeaponDamage(ranged)
    local minD, maxD
    if ranged and UnitRangedDamage then
        local _, a, b = UnitRangedDamage("player")
        minD, maxD = a, b
    elseif UnitDamage then
        minD, maxD = UnitDamage("player")
    end
    if IsSecret(minD, maxD) or not minD or not maxD or maxD <= 0 then return nil end
    return minD, maxD
end

-- Physische Faehigkeit? Dann gilt die Nahkampf- bzw. Fernkampf-Krit-Chance
local function IsPhysical(lower)
    return lower:find("waffe") or lower:find("weapon") or lower:find("körperlich") or lower:find("physical")
end

local function IsRanged(lower)
    return lower:find("distanz") or lower:find("fernkampf") or lower:find("ranged")
        or lower:find("schuss") or lower:find("shot")
end

local function GetCrit(desc)
    local lower = desc:lower()
    if IsPhysical(lower) then
        local c
        if IsRanged(lower) and GetRangedCritChance then
            c = GetRangedCritChance()
        elseif GetCritChance then
            c = GetCritChance()
        end
        if not IsSecret(c) and c then return c end
        return nil
    end
    if not GetSpellCritChance then return nil end
    -- Zauberschule an ihrem Namen in der Beschreibung erkennen ("Feuerschaden")
    local school, bestPos
    for _, s in ipairs(SCHOOLS) do
        local p = s[2] and desc:find(s[2], 1, true)
        if p and (not bestPos or p < bestPos) then bestPos, school = p, s[1] end
    end
    if school then
        local c = GetSpellCritChance(school)
        return not IsSecret(c) and c or nil
    end
    local best -- Schule unbekannt: hoechste Zauber-Krit-Chance nehmen
    for i = 2, 7 do
        local c = GetSpellCritChance(i)
        if not IsSecret(c) and c and (not best or c > best) then best = c end
    end
    return best
end

local function ReadDescription(spellID)
    if C_Spell and C_Spell.GetSpellDescription then return C_Spell.GetSpellDescription(spellID) end
    if GetSpellDescription then return GetSpellDescription(spellID) end
end

local function GetExpectation(spellID)
    if not spellID or IsSecret(spellID) then return nil end
    local cached = expectCache[spellID]
    if InCombatLockdown() then return cached end -- im Kampf: zuletzt gelesene Werte

    local desc = ReadDescription(spellID)
    if IsSecret(desc) or type(desc) ~= "string" or desc == "" then
        -- Beschreibung noch nicht geladen: EINMAL pro Zauber anfordern.
        -- Wichtig: vorher merken, denn das Spiel kann die "geladen"-Meldung sofort
        -- schicken – sonst entsteht eine Endlosschleife (z. B. Automatischer Angriff
        -- hat gar keine Beschreibung).
        if not loadRequested[spellID] and C_Spell and C_Spell.RequestLoadSpellData then
            loadRequested[spellID] = true
            C_Spell.RequestLoadSpellData(spellID)
        end
        return cached
    end

    -- Reihenfolge: Bereich "14 bis 22" → ueber Zeit (DoT/HoT) → Waffenschaden → einzelne Zahl
    local lower = desc:lower()
    local entry
    local byCombo, comboKind, comboUnit = FindComboRanges(desc)
    local low, high = FindRange(desc)
    if byCombo then
        local first = byCombo[1] or select(2, next(byCombo))
        entry = {
            low = first.low, high = first.high, byCombo = byCombo,
            duration = comboKind == "duration",
            otherUnit = comboKind == "other" and comboUnit or nil, -- z. B. "Rüstung"
        }
    elseif low then
        entry = { low = low, high = high }
    else
        local amount, overTime = FindOverTime(desc)
        if amount then
            entry = { low = amount, high = amount, overTime = overTime }
        else
            entry = FindWeapon(desc)
            if entry then
                -- Waffenschaden (Charakterfenster) + Bonus aus dem Tooltip zusammenzaehlen
                local wMin, wMax = GetWeaponDamage(IsRanged(lower))
                if wMin then
                    if entry.weaponPlus then
                        entry.low = math.floor(wMin + entry.weaponPlus)
                        entry.high = math.ceil(wMax + entry.weaponPlus)
                    elseif entry.weaponPct then
                        entry.low = math.floor(wMin * entry.weaponPct / 100)
                        entry.high = math.ceil(wMax * entry.weaponPct / 100)
                    end
                elseif cached and cached.low then
                    entry.low, entry.high = cached.low, cached.high -- Waffenwerte gerade nicht lesbar
                end
            else
                local single = FindSingle(desc, lower)
                if single then entry = { low = single, high = single } end
            end
        end
    end
    if not entry then
        expectCache[spellID] = nil
        return nil
    end
    entry.heal = (lower:find("heilt") or lower:find("heilung") or lower:find("heal")) and true or false
    entry.physical = (IsPhysical(lower) or byCombo) and true or false -- Nahkampf/Waffe/Finishing-Move
    entry.crit = GetCrit(desc)
    expectCache[spellID] = entry
    return entry
end

-- "≈ 14–22 Schaden · 8.5 % Krit" bzw. "≈ 120 Schaden über 18 s · 8.5 % Krit"
local function FormatExpectation(expect)
    local color = expect.heal and "|cff66ff66" or "|cffffaa55"
    local kind = expect.heal and T("Heilung", "healing") or T("Schaden", "damage")
    local text
    if expect.duration then
        -- Dauer statt Schaden (z. B. Zerhaeckseln, Nierenhieb): neutral, ohne Krit
        local function Secs(v) return (string.format("%.1f", v):gsub("%.0$", "")) end
        local value = expect.low == expect.high and Secs(expect.low) or (Secs(expect.low) .. "–" .. Secs(expect.high))
        text = string.format("|cffccccff≈ %s s %s|r", value, T("Dauer", "duration"))
        if expect.comboText then text = text .. "  (" .. expect.comboText .. ")" end
        return text
    elseif expect.otherUnit then
        -- Weder Schaden noch Dauer (z. B. "80 Rüstung"): neutral mit dem Originalwort, ohne Krit
        local value = expect.low == expect.high and FormatNumber(expect.low)
            or (FormatNumber(expect.low) .. "–" .. FormatNumber(expect.high))
        text = string.format("|cffccccff≈ %s %s|r", value, expect.otherUnit)
        if expect.comboText then text = text .. "  (" .. expect.comboText .. ")" end
        return text
    elseif not expect.low and expect.weaponPlus then
        -- Waffenschaden war nicht lesbar: als Text anzeigen
        text = string.format("%s≈ %s + %s %s|r", color, T("Waffe", "weapon"), FormatNumber(expect.weaponPlus), kind)
    elseif not expect.low and expect.weaponPct then
        text = string.format("%s≈ %d %% %s|r", color, expect.weaponPct, T("Waffenschaden", "weapon damage"))
    elseif expect.low == expect.high and not expect.overTime then
        text = string.format("%s≈ %s %s|r", color, FormatNumber(expect.low), kind)
    elseif expect.overTime then
        text = string.format("%s≈ %s %s %s %s s|r", color, FormatNumber(expect.low), kind, T("über", "over"),
            (string.format("%.1f", expect.overTime):gsub("%.0$", "")))
    else
        text = string.format("%s≈ %s–%s %s|r", color, FormatNumber(expect.low),
            FormatNumber(expect.high), kind)
    end
    if expect.comboText then
        text = text .. "  (" .. expect.comboText .. ")"
    end
    if expect.crit then
        text = text .. string.format("  ·  %.1f %% %s", expect.crit, T("Krit", "crit"))
    end
    return text
end

-- Bei Finishing-Moves den Wert fuer die tatsaechlich verbrauchten Combopunkte waehlen
local function ForCombo(expect, combo)
    if not expect.byCombo then return expect end
    local shown = {
        heal = expect.heal, crit = expect.crit, duration = expect.duration,
        physical = expect.physical, otherUnit = expect.otherUnit,
    }
    local r = combo and expect.byCombo[combo]
    if r then
        shown.low, shown.high = r.low, r.high
        shown.comboText = string.format(combo == 1 and T("%d Punkt", "%d point") or T("%d Punkte", "%d points"), combo)
    else
        -- Punkte unbekannt: ganze Spanne von wenig bis viele Punkte zeigen
        local minCP, maxCP
        for cp in pairs(expect.byCombo) do
            if not minCP or cp < minCP then minCP = cp end
            if not maxCP or cp > maxCP then maxCP = cp end
        end
        shown.low, shown.high = expect.byCombo[minCP].low, expect.byCombo[maxCP].high
        shown.comboText = string.format(T("%d–%d Punkte", "%d–%d points"), minCP, maxCP)
    end
    return shown
end

---------------------------------------------------------------------------
-- Zauberleiste
---------------------------------------------------------------------------
-- Unsichtbarer Halter: traegt Zauberleiste und GCD-Balken, wird verschoben
local anchor = CreateFrame("Frame", "ForeverCastAnchor", UIParent)
anchor:SetSize(BAR_WIDTH, 28)
anchor:SetPoint("CENTER", 32, -336)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)

-- Rahmen im gewählten Look (Look.lua: Forever = flach mit Goldlinie, Clean = bronzener Tooltip-Rand wie früher)
local castFrame = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
castFrame:SetPoint("TOPLEFT")
castFrame:SetPoint("TOPRIGHT")
castFrame:SetHeight(20)
castFrame:Hide()

local bar = CreateFrame("StatusBar", nil, castFrame)
ns.StyleBox(castFrame, bar)
ns.StyleBar(bar)
bar:SetMinMaxValues(0, 1)

-- Bereich am Ende: hier kann der naechste Zauber schon gedrueckt werden
local queueZone = bar:CreateTexture(nil, "OVERLAY", nil, 1)
queueZone:SetColorTexture(0.2, 1, 0.2, 0.3)
queueZone:Hide()

-- Feiner senkrechter Strich am Beginn des Queue-Fensters (weicher Uebergang statt harter Kante)
local queueMarker = bar:CreateTexture(nil, "OVERLAY", nil, 5)
queueMarker:SetColorTexture(1, 1, 1, 0.75)
queueMarker:SetWidth(2)
queueMarker:SetPoint("TOPRIGHT", queueZone, "TOPLEFT", 1, 0)
queueMarker:SetPoint("BOTTOMRIGHT", queueZone, "BOTTOMLEFT", 1, 0)
queueMarker:Hide()

-- Bereich am Ende: so viel "frisst" die Verbindung (Lag)
local lagZone = bar:CreateTexture(nil, "OVERLAY", nil, 2)
lagZone:SetColorTexture(1, 0.1, 0.1, 0.5)
lagZone:Hide()

local spark = bar:CreateTexture(nil, "OVERLAY", nil, 3)
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetSize(12, 26)
spark:Hide()

-- Feine Striche fuer die Ticks kanalisierter Zauber
local tickMarks = {}
local function HideTicks()
    for _, t in ipairs(tickMarks) do t:Hide() end
end

local function ShowTicks(count)
    HideTicks()
    local width = bar:GetWidth()
    if not count or count < 2 or width <= 0 then return end
    for i = 1, count - 1 do
        local t = tickMarks[i]
        if not t then
            t = bar:CreateTexture(nil, "OVERLAY", nil, 4)
            t:SetColorTexture(1, 1, 1, 0.6)
            t:SetWidth(1)
            tickMarks[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOP", bar, "TOPLEFT", width * i / count, 0)
        t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", width * i / count, 0)
        t:Show()
    end
end

local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
nameText:SetPoint("LEFT", 4, 0)
nameText:SetJustifyH("LEFT")
nameText:SetWordWrap(false)

local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timeText:SetPoint("RIGHT", -4, 0)
timeText:SetJustifyH("RIGHT")
nameText:SetPoint("RIGHT", timeText, "LEFT", -4, 0)

-- Zaubersymbol links, mit dem gleichen dezenten Rahmen
local iconFrame = CreateFrame("Frame", nil, castFrame, "BackdropTemplate")
iconFrame:SetSize(20, 20)
iconFrame:SetPoint("RIGHT", castFrame, "LEFT", -3, 0)

local icon = iconFrame:CreateTexture(nil, "ARTWORK")
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- Rand des Symbols abschneiden
ns.StyleBox(iconFrame, icon)

local pingText = castFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pingText:SetPoint("LEFT", castFrame, "RIGHT", 5, 0)
ns.Text(pingText, 10)

-- Kleine Zeile ueber der Leiste: "≈ 14–22 Schaden · 8.5 % Krit"
local expectText = castFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
expectText:SetPoint("BOTTOMLEFT", castFrame, "TOPLEFT", 2, 2)
expectText:SetJustifyH("LEFT")
ns.Text(expectText, 11) -- etwas groesser als die Texte in der Leiste: besser lesbar

-- Duenner GCD-Balken unter der Zauberleiste (auch bei Spontanzaubern sichtbar)
local gcdBar = CreateFrame("StatusBar", nil, anchor)
gcdBar:SetPoint("TOPLEFT", castFrame, "BOTTOMLEFT", 3, -2)
gcdBar:SetPoint("TOPRIGHT", castFrame, "BOTTOMRIGHT", -3, -2)
gcdBar:SetHeight(4)
ns.StyleBar(gcdBar)
gcdBar:SetMinMaxValues(0, 1)
gcdBar:Hide()

-- Combopunkte: kleine Felder rechts unter dem GCD-Balken (nur wenn Punkte vorhanden)
local COMBO_SIZE, COMBO_GAP = 8, 3
local comboRow = CreateFrame("Frame", nil, anchor)
comboRow:SetPoint("TOPRIGHT", castFrame, "BOTTOMRIGHT", -3, -8)
comboRow:SetSize(1, COMBO_SIZE)
comboRow:Hide()
local comboDots = {}

local function GetComboDot(i)
    local d = comboDots[i]
    if d then return d end
    d = CreateFrame("Frame", nil, comboRow)
    d:SetSize(COMBO_SIZE, COMBO_SIZE)
    d.border = d:CreateTexture(nil, "BACKGROUND")
    d.border:SetAllPoints()
    d.border:SetColorTexture(0, 0, 0, 0.9) -- feiner dunkler Rand
    d.fill = d:CreateTexture(nil, "ARTWORK")
    d.fill:SetPoint("TOPLEFT", 1, -1)
    d.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    comboDots[i] = d
    return d
end

local gcdBg = gcdBar:CreateTexture(nil, "BACKGROUND")
gcdBg:SetAllPoints()
gcdBg:SetColorTexture(0, 0, 0, 0.6)

local function SetBarColor(c)
    bar:SetStatusBarColor(c[1], c[2], c[3])
end

-- Laenge und Hoehe aus den Einstellungen uebernehmen
local function ApplySize()
    local o = GetDB()
    anchor:SetSize(o.width, o.height + 8) -- inkl. GCD-Balken
    castFrame:SetHeight(o.height)
    iconFrame:SetSize(o.height, o.height)
    spark:SetSize(math.max(8, o.height * 0.6), o.height * 1.4)
    local size = o.height >= 26 and 12 or 10
    ns.Text(nameText, size)
    ns.Text(timeText, size)
end

---------------------------------------------------------------------------
-- Zauber-Zustand und "Aufwecken" der Bild-fuer-Bild-Aktualisierung
---------------------------------------------------------------------------
-- mode: nil (nichts), "cast", "channel", "flight", "fade" (ausblenden)
local state = {}
local gcdStart, gcdEnd
local craft         -- Herstellungs-Zaehler: { total = Anzahl, done = fertig }
local pendingFlight -- Flug gebucht, aber noch nicht abgehoben
local flight        -- laufender Flug
local popupOrder = {} -- sichtbare Spontanzauber-Einblendungen (neueste zuerst)

-- Die Bild-fuer-Bild-Aktualisierung laeuft nur, solange etwas angezeigt wird.
-- Im Leerlauf schlaeft sie und kostet keine Leistung.
local OnUpdate -- weiter unten
local updaterAwake = false

local function Wake()
    if not updaterAwake then
        updaterAwake = true
        anchor:SetScript("OnUpdate", OnUpdate)
    end
end

local function Sleep()
    updaterAwake = false
    anchor:SetScript("OnUpdate", nil)
end

local function HideZones()
    queueZone:Hide()
    queueMarker:Hide()
    lagZone:Hide()
    HideTicks()
end

-- Platzhalter, solange die Leiste entsperrt ist (zum Verschieben)
local function ShowPlaceholder()
    state.mode = nil
    HideZones()
    spark:Hide()
    SetBarColor(COLOR_IDLE)
    bar:SetValue(1)
    nameText:SetText(T("ForeverCast – ziehen zum Verschieben", "ForeverCast – drag to move"))
    timeText:SetText("")
    pingText:SetText("")
    expectText:SetText("")
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    castFrame:SetAlpha(1)
    castFrame:Show()
end

local function HideOrPlaceholder()
    if GetDB().locked then
        state.mode = nil
        castFrame:Hide()
    else
        ShowPlaceholder()
    end
end

-- Lag- und Queue-Bereich passend zur Zauberdauer einzeichnen
local function LayoutZones(isChannel, total)
    local o = GetDB()
    local width = bar:GetWidth()
    HideZones()
    if total <= 0 or width <= 0 then return end

    if o.showQueue then
        -- Queue-Fenster am Ende des Zaubers: beim Wirken rechts, beim Kanalisieren
        -- (Balken laeuft von rechts nach links) liegt das Ende links
        local side, inner, innerOther = "RIGHT", "LEFT", "RIGHT"
        if isChannel then side, inner, innerOther = "LEFT", "RIGHT", "LEFT" end
        queueZone:ClearAllPoints()
        queueZone:SetPoint("TOP" .. side)
        queueZone:SetPoint("BOTTOM" .. side)
        queueZone:SetWidth(math.max(1, math.min(1, queueWindow / total) * width))
        queueZone:Show()
        -- Strich an der Innenkante der Zone; nur, wenn das Queue-Fenster kuerzer als der ganze Zauber ist
        local dx = isChannel and -1 or 1
        queueMarker:ClearAllPoints()
        queueMarker:SetPoint("TOP" .. innerOther, queueZone, "TOP" .. inner, dx, 0)
        queueMarker:SetPoint("BOTTOM" .. innerOther, queueZone, "BOTTOM" .. inner, dx, 0)
        queueMarker:SetShown(queueWindow < total)
    end

    if o.showLatency then
        lagZone:ClearAllPoints()
        -- Kanalisieren laeuft von rechts nach links, dort liegt das Ende links
        local side = isChannel and "LEFT" or "RIGHT"
        lagZone:SetPoint("TOP" .. side)
        lagZone:SetPoint("BOTTOM" .. side)
        lagZone:SetWidth(math.max(1, math.min(1, GetLag() / total) * width))
        lagZone:Show()
    end
end

local testToken = 0 -- jeder echte Zauber bricht einen laufenden Test-Durchlauf ab

-- fake = Testdaten { name, texture, duration, ticks, expect, tradeSkill } oder nil fuer echte Zauber
local function StartCast(isChannel, fake)
    local name, texture, startMS, endMS, castID, isTradeSkill, spellID
    if fake then
        name, texture, isTradeSkill = fake.name, fake.texture, fake.tradeSkill
        startMS = GetTime() * 1000
        endMS = startMS + fake.duration * 1000
    elseif isChannel then
        local n, _, tex, s, e, _, _, sid = UnitChannelInfo("player")
        name, texture, startMS, endMS, spellID = n, tex, s, e, sid
    else
        local n, _, tex, s, e, trade, id, _, sid = UnitCastingInfo("player")
        name, texture, startMS, endMS, isTradeSkill, castID, spellID = n, tex, s, e, trade, id, sid
    end

    local secret = IsSecret(name, startMS, endMS)
    if not secret and not name then return end
    if not fake then testToken = testToken + 1 end

    local o = GetDB()
    state.mode = isChannel and "channel" or "cast"
    state.secret = secret
    state.test = fake ~= nil
    state.failed = nil
    state.pushback, state.pushbackUntil = nil, nil
    state.castID = (not IsSecret(castID)) and castID or nil
    state.isTradeSkill = (not IsSecret(isTradeSkill)) and isTradeSkill or false

    icon:SetTexture(texture) -- SetText/SetTexture vertragen auch "secret"-Werte
    SetBarColor(isChannel and COLOR_CHANNEL or COLOR_CAST)

    if o.showLatency then
        local ms = GetPing()
        pingText:SetText(PingColor(ms) .. ms .. " ms|r")
    else
        pingText:SetText("")
    end

    -- Erwartungswerte aus der Zauberbeschreibung (nur Anzeige, keine eigene Rechnung)
    local expect
    if o.showExpect and not state.isTradeSkill then
        expect = fake and fake.expect or (not fake and GetExpectation(spellID))
        if expect and expect.physical and not o.showMelee then expect = nil end
    end
    expectText:SetText(expect and FormatExpectation(expect) or "")

    if secret then
        -- Zeiten sind geheim: Blizzard-Timer den Balken fuellen lassen, ohne Extras
        nameText:SetText(name)
        HideZones()
        spark:Hide()
        timeText:SetText("")
        local duration = isChannel and UnitChannelDuration and UnitChannelDuration("player")
            or (not isChannel and UnitCastingDuration and UnitCastingDuration("player"))
        if duration and bar.SetTimerDuration then
            pcall(bar.SetTimerDuration, bar, duration)
        else
            bar:SetValue(1)
        end
    else
        -- Falls vorher ein Blizzard-Timer den Balken gesteuert hat, diesen loesen
        if bar.ClearTimerDuration then pcall(bar.ClearTimerDuration, bar) end
        state.startT = startMS / 1000
        state.endT = endMS / 1000
        local total = state.endT - state.startT
        LayoutZones(isChannel, total)
        spark:Show()

        if o.showCraft and state.isTradeSkill and craft and craft.total > 1 then
            -- Herstellen mehrerer Gegenstaende: "Leinenstoff 3/20 (~38 s)"
            local left = (craft.total - craft.done) * total
            nameText:SetText(string.format("%s %d/%d (~%s)", name, craft.done + 1, craft.total,
                left >= 60 and FormatClock(left) or string.format("%d s", left + 0.5)))
        elseif not fake and IsHearth(spellID, name) and GetBindLocation and GetBindLocation() then
            -- Ruhestein: Ziel dazuschreiben ("Ruhestein » Goldhain"; "→" kennt die WoW-Schrift nicht)
            nameText:SetText(name .. " » " .. GetBindLocation())
        else
            -- "Opening - No Text" / "Öffnen - Kein Text": was geoeffnet wird, steht im Tooltip
            local lower = name:lower()
            local isOpening = lower:find("no text", 1, true) or lower:find("kein text", 1, true)
                or lower:find("opening", 1, true) or lower:find("öffnen", 1, true)
            if not fake and isOpening then
                local clean = name:gsub("%s*%-%s*[Nn]o [Tt]ext$", ""):gsub("%s*%-%s*[Kk]ein [Tt]ext$", "")
                nameText:SetText(state.openTarget and (clean .. ": " .. state.openTarget) or clean)
            else
                nameText:SetText(name)
            end
        end

        if isChannel and o.showTicks then
            ShowTicks(fake and fake.ticks or GetChannelTicks(name))
        end
    end

    castFrame:SetAlpha(1)
    castFrame:Show()
    Wake()
end

-- by = GUID dessen, der unterbrochen hat (UNIT_SPELLCAST_INTERRUPTED) – "Unterbrochen von Name"
local function FinishCast(kind, by)
    if kind == "done" then
        if state.mode ~= "cast" and state.mode ~= "channel" and state.mode ~= "flight" then return end
        if not state.secret and state.mode == "cast" then bar:SetValue(1) end
    else
        -- Unterbrochen/fehlgeschlagen: auch kurz nach STOP noch anzeigen (Reihenfolge der Events schwankt)
        local justEnded = state.mode == "fade" and GetTime() - state.fadeStart < 0.3 and not state.failed
        if state.mode ~= "cast" and state.mode ~= "channel" and not justEnded then return end
        state.failed = true
        if state.isTradeSkill then craft = nil end -- Herstellen wurde abgebrochen
        HideZones()
        SetBarColor(COLOR_FAIL)
        bar:SetValue(1)
        nameText:SetText(kind == "interrupted" and ns.InterruptedText(by) or T("Fehlgeschlagen", "Failed"))
        timeText:SetText("")
        expectText:SetText("")
    end
    spark:Hide()
    HideTicks()
    if state.mode ~= "fade" then
        state.mode = "fade"
        -- Unterbrochen/fehlgeschlagen: erst kurz stehen lassen (lesbar), dann ausblenden
        state.fadeStart = GetTime() + (kind ~= "done" and 0.5 or 0)
    end
    Wake()
end

-- Zauber wurde verzoegert (Rueckstoss) oder Kanalisieren verkuerzt: Unterschied kurz anzeigen
local function OnCastUpdated(isChannel)
    local oldEnd = (state.mode == "cast" or state.mode == "channel") and not state.secret and state.endT
    StartCast(isChannel)
    if oldEnd and state.endT and not state.secret and GetDB().showPushback then
        local delta = state.endT - oldEnd
        if math.abs(delta) > 0.05 then
            state.pushback = delta
            state.pushbackUntil = GetTime() + 1.5
        end
    end
end

---------------------------------------------------------------------------
-- Spontanzauber/DoTs: kleine Einblendungen unter der Zauberleiste
---------------------------------------------------------------------------
-- Nur wenn die Beschreibung eine Zahl liefert (sonst wuerden Reittiere, Buffs usw. aufpoppen).
local POPUP_HOLD = 2.5  -- so lange voll sichtbar
local POPUP_FADE = 0.5  -- danach ausblenden
local POPUP_MAX = 3     -- hoechstens so viele gleichzeitig (neueste oben)

local popups = {}

for i = 1, POPUP_MAX do
    local f = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    ns.StyleBox(f)
    f:SetHeight(20)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(14, 14)
    f.icon:SetPoint("LEFT", 4, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.Text(f.text, 10)
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
    f:Hide()
    popups[i] = f
end

local function LayoutPopups()
    for i, f in ipairs(popupOrder) do
        f:ClearAllPoints()
        -- unter der Leiste (unterhalb des GCD-Balkens), buendig am linken Rand
        -- sind Combopunkte sichtbar, rutschen die Einblendungen etwas tiefer
        local top = comboRow:IsShown() and -20 or -10
        f:SetPoint("TOPLEFT", castFrame, "BOTTOMLEFT", 0, top - (i - 1) * 22)
    end
end

local function ShowPopup(name, iconID, expect)
    -- Freie Einblendung nehmen, sonst die aelteste wiederverwenden
    local f
    for _, p in ipairs(popups) do
        if not p:IsShown() then f = p break end
    end
    if not f then f = table.remove(popupOrder) end

    f.icon:SetTexture(iconID)
    f.text:SetText(name .. "   " .. FormatExpectation(expect))
    -- mindestens so breit wie die Zauberleiste, damit es sauber untereinander steht
    f:SetWidth(math.max(castFrame:GetWidth(), f.text:GetStringWidth() + 30))
    f.shownAt = GetTime()
    f:SetAlpha(1)
    f:Show()
    table.insert(popupOrder, 1, f)
    LayoutPopups()
    Wake()
end

local function ShowInstant(spellID, combo)
    -- Laeuft doch ein Zauber mit Zauberzeit/Kanalisieren? Dann zeigt das die Leiste selbst.
    if state.mode == "cast" or state.mode == "channel" then return end
    local expect = GetExpectation(spellID)
    if not expect then return end
    if expect.physical and not GetDB().showMelee then return end -- Nahkampf ausgeschaltet
    local name, iconID = GetSpellNameAndIcon(spellID)
    if not name then return end
    ShowPopup(name, iconID, ForCombo(expect, combo))
end

local function UpdatePopups(now)
    local changed = false
    for i = #popupOrder, 1, -1 do
        local f = popupOrder[i]
        local age = now - f.shownAt
        if age > POPUP_HOLD + POPUP_FADE then
            f:Hide()
            table.remove(popupOrder, i)
            changed = true
        elseif age > POPUP_HOLD then
            f:SetAlpha(1 - (age - POPUP_HOLD) / POPUP_FADE)
        end
    end
    if changed then LayoutPopups() end
end

---------------------------------------------------------------------------
-- Zauberbuch vorab einlesen (nur ausserhalb des Kampfs), damit die Werte
-- auch beim ersten Zauber im Kampf schon bekannt sind
---------------------------------------------------------------------------
local function ForEachSpellbookSpell(fn)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID and not item.isPassive then fn(item.spellID) end
                end
            end
        end
    elseif GetNumSpellTabs then -- aeltere Zauberbuch-Funktionen
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local _, id = GetSpellBookItemInfo(i, "spell")
                if id then fn(id) end
            end
        end
    end
end

local precachePending = false
local function PrecacheSpells()
    if precachePending then return end
    precachePending = true
    C_Timer.After(1, Safe("Zauberbuch", function() -- mehrere Ausloeser kurz hintereinander zusammenfassen
        precachePending = false
        if InCombatLockdown() then return end
        ForEachSpellbookSpell(GetExpectation)
    end))
end

-- /fcast debug: zeigt im Chat, was beim Spontanzauber gelesen wurde
local debugMode = false
local function DebugSpell(spellID)
    if IsSecret(spellID) then
        Chat(T("Debug: Zauber-ID ist im Kampf gesperrt (secret).", "Debug: spell ID is locked in combat (secret)."))
        return
    end
    local name = GetSpellNameAndIcon(spellID) or "?"
    local desc = ReadDescription(spellID)
    local expect = GetExpectation(spellID)
    Chat(string.format(T("Debug: %s (ID %s), Kampf: %s, Werte: %s", "Debug: %s (ID %s), combat: %s, values: %s"),
        name, tostring(spellID), InCombatLockdown() and T("ja", "yes") or T("nein", "no"),
        expect and FormatExpectation(expect) or T("keine", "none")))
    if IsSecret(desc) then
        Chat(T("Debug: Beschreibung ist gesperrt (secret).", "Debug: description is locked (secret)."))
    elseif desc then
        Chat(T("Debug: Beschreibung: ", "Debug: description: ") .. desc)
    end
end

---------------------------------------------------------------------------
-- Combopunkte an der Leiste
---------------------------------------------------------------------------
local COLOR_COMBO      = { 1, 0.8, 0.1 }   -- gesammelt (gold)
local COLOR_COMBO_FULL = { 1, 0.3, 0.15 }  -- alle voll (rot)

local function UpdateCombo()
    local maxCP = 5
    if UnitPowerMax and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        local m = UnitPowerMax("player", Enum.PowerType.ComboPoints)
        if not IsSecret(m) and m and m > 0 then maxCP = m end
    end
    local cp = GetCurrentCombo()
    local wasShown = comboRow:IsShown()
    if not GetDB().showCombo or not cp or cp <= 0 then
        comboRow:Hide()
    else
        for i = 1, maxCP do
            local d = GetComboDot(i)
            d:ClearAllPoints()
            d:SetPoint("RIGHT", comboRow, "RIGHT", -(maxCP - i) * (COMBO_SIZE + COMBO_GAP), 0)
            if i <= cp then
                local c = cp >= maxCP and COLOR_COMBO_FULL or COLOR_COMBO
                d.fill:SetColorTexture(c[1], c[2], c[3], 1)
            else
                d.fill:SetColorTexture(0.25, 0.25, 0.25, 0.8) -- leer
            end
            d:Show()
        end
        for i = maxCP + 1, #comboDots do comboDots[i]:Hide() end
        comboRow:SetWidth(maxCP * (COMBO_SIZE + COMBO_GAP))
        comboRow:Show()
    end
    if wasShown ~= comboRow:IsShown() then LayoutPopups() end
end

---------------------------------------------------------------------------
-- GCD: mehrere Wege, falls Blizzards GCD-Zauber auf diesem Client nicht klappt
---------------------------------------------------------------------------
-- Automatischer Schuss/Angriff loesen bei jedem Schuss/Schlag aus, sind aber kein GCD
local GCD_IGNORE = { [75] = true, [5019] = true, [3018] = true, [2764] = true, [6603] = true }
local gcdTimerMode = false -- true: Blizzard-Timer fuellt den Balken (Werte gesperrt)
local gcdMethod            -- fuer den Selbsttest: wie wurde der GCD zuletzt erkannt?
local learnedGCD           -- zuletzt echt gemessene GCD-Dauer (beruecksichtigt Tempo-Boni)

-- Liefert die Abklingzeit-Infos, falls lesbar; zweiter Wert = "vorhanden, aber gesperrt"
local function ReadCooldown(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil, false end
    local info = C_Spell.GetSpellCooldown(spellID)
    if not info then return nil, false end
    if IsSecret(info.startTime, info.duration) then return nil, true end
    return info, false
end

local function SetGCD(start, duration, method, timerMode)
    gcdStart, gcdEnd = start, start + duration
    gcdMethod = method
    gcdTimerMode = timerMode
    if not timerMode and gcdBar.ClearTimerDuration then pcall(gcdBar.ClearTimerDuration, gcdBar) end
    Wake()
end

local function EstimateGCD()
    if learnedGCD then return learnedGCD end
    local powerType = UnitPowerType and UnitPowerType("player")
    if not IsSecret(powerType) and Enum and Enum.PowerType and powerType == Enum.PowerType.Energy then
        return 1.0 -- Energie-Klassen (Schurke, Druide in Katzengestalt)
    end
    return 1.5
end

-- spellID: gerade erfolgreich gewirkter Zauber (nil bei SPELL_UPDATE_COOLDOWN)
local function UpdateGCD(spellID)
    -- 1) Blizzards interner GCD-Zauber
    local info, gcdLocked = ReadCooldown(GCD_SPELL)
    if info and info.duration and info.duration > 0 and info.duration <= 2 then
        learnedGCD = info.duration
        SetGCD(info.startTime, info.duration, "gcd", false)
        return
    end
    if not spellID or IsSecret(spellID) or GCD_IGNORE[spellID] then return end

    -- 2) Abklingzeit des gerade gewirkten Zaubers (die IST meist der GCD)
    local own = ReadCooldown(spellID)
    if own and own.duration then
        if own.duration > 0 and own.duration <= 2 then
            learnedGCD = own.duration
            SetGCD(own.startTime, own.duration, "spell", false)
            return
        end
        if own.duration == 0 then return end -- Zauber ohne GCD
    end

    -- 3) Werte gesperrt: Blizzards Timer fuellt den Balken (Laenge nur fuers Ausblenden geschaetzt)
    if gcdLocked and C_Spell.GetSpellCooldownDuration and gcdBar.SetTimerDuration then
        local durationObj = C_Spell.GetSpellCooldownDuration(GCD_SPELL)
        if durationObj and pcall(gcdBar.SetTimerDuration, gcdBar, durationObj) then
            SetGCD(GetTime(), EstimateGCD(), "timer", true)
            return
        end
    end

    -- 4) Letzte Rettung: geschaetzte GCD-Laenge
    SetGCD(GetTime(), EstimateGCD(), "estimate", false)
end

---------------------------------------------------------------------------
-- Herstellungs-Zaehler: merkt sich, wie oft "Herstellen" gedrueckt wurde
---------------------------------------------------------------------------
local function OnCraftStarted(count)
    count = tonumber(count) or 1
    craft = count > 1 and { total = count, done = 0 } or nil
end

if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", Safe("Herstellen", function(_, count) OnCraftStarted(count) end))
end
if DoTradeSkill then -- aeltere Berufe-Oberflaeche
    hooksecurefunc("DoTradeSkill", Safe("Herstellen", function(_, count) OnCraftStarted(count) end))
end

---------------------------------------------------------------------------
-- Flugzeit-Timer: Flugzeiten werden beim ersten Flug gemerkt
---------------------------------------------------------------------------
local function FlightKey(from, to)
    return (from or "?") .. " → " .. (to or "?")
end

if TakeTaxiNode then
    hooksecurefunc("TakeTaxiNode", Safe("Flugmeister", function(index)
        local from
        for i = 1, NumTaxiNodes() do
            if TaxiNodeGetType(i) == "CURRENT" then from = TaxiNodeName(i) end
        end
        local to = TaxiNodeName(index)
        -- Ortsnamen enthalten oft ", Region" – fuer die Anzeige reicht der erste Teil
        pendingFlight = { from = from, to = to, short = to and to:match("^([^,]+)") or to, t = GetTime() }
        Wake()
    end))
end

local function ShowFlightBar()
    state.mode = "flight"
    state.secret = false
    state.test = false
    HideZones()
    spark:Show()
    SetBarColor(COLOR_FLIGHT)
    icon:SetTexture("Interface\\Icons\\Ability_Mount_Wyvern_01")
    nameText:SetText("» " .. (flight.short or T("Flug", "Flight")))
    pingText:SetText("")
    expectText:SetText("")
    castFrame:SetAlpha(1)
    castFrame:Show()
    Wake()
end

local function StartFlight(now)
    flight = pendingFlight
    pendingFlight = nil
    flight.start = now
    flight.known = GetDB().flights[FlightKey(flight.from, flight.to)]
    if GetDB().showFlight then ShowFlightBar() end
end

local function EndFlight(now)
    local duration = now - flight.start
    -- Nur vollstaendige echte Fluege merken (nicht Testfluege, nicht nach /reload mitten im Flug)
    if not flight.test and duration > 5 then
        local key = FlightKey(flight.from, flight.to)
        local seconds = math.floor(duration + 0.5)
        GetDB().flights[key] = seconds
    end
    flight = nil
    if state.mode == "flight" then FinishCast("done") end
end

local function UpdateFlight(now)
    if pendingFlight then
        if UnitOnTaxi("player") then
            StartFlight(now)
        elseif now - pendingFlight.t > 10 then
            pendingFlight = nil -- Flug kam nicht zustande
        end
    elseif flight then
        local elapsed = now - flight.start
        local landed = flight.test and elapsed >= flight.known or (not flight.test and not UnitOnTaxi("player"))
        if landed then
            EndFlight(now)
        elseif state.mode == "flight" then
            if flight.known then
                local progress = math.min(1, elapsed / flight.known)
                bar:SetValue(progress)
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", bar, "LEFT", progress * bar:GetWidth(), 0)
                timeText:SetText(FormatClock(flight.known - elapsed))
            else
                -- Erster Flug auf dieser Strecke: Zeit hochzaehlen und danach merken
                bar:SetValue(1)
                spark:Hide()
                timeText:SetText(FormatClock(elapsed) .. T(" (wird gemerkt)", " (learning)"))
            end
        end
    end
end

---------------------------------------------------------------------------
-- Bild-fuer-Bild-Aktualisierung: Balken, Zeit, Queue-Farbe, Ausblenden, GCD, Flug
---------------------------------------------------------------------------
OnUpdate = Safe("Anzeige", function()
    local now = GetTime()
    local o = GetDB()

    if (state.mode == "cast" or state.mode == "channel") and not state.secret then
        local total = state.endT - state.startT
        local remaining = math.max(0, state.endT - now)
        local elapsed = math.min(total, math.max(0, now - state.startT))
        local progress = total > 0 and (state.mode == "channel" and remaining or elapsed) / total or 1
        bar:SetValue(progress)
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", bar, "LEFT", progress * bar:GetWidth(), 0)

        local text = string.format("%.1f / %.1f", state.mode == "channel" and remaining or elapsed, total)
        if state.pushbackUntil and now < state.pushbackUntil then
            -- Rueckstoss: "+0.5 s" in Rot (beim Kanalisieren wird es kuerzer: "-0.5 s")
            text = text .. string.format("  |cffff4444%+.1f s|r", state.pushback)
        end
        timeText:SetText(text)

        do
            -- Im Queue-Fenster sanft (ca. 0,15 s) nach Gruen ueberblenden
            -- (Wirken: von Gold, Kanalisieren: von Blau)
            local base = state.mode == "channel" and COLOR_CHANNEL or COLOR_CAST
            local blend = 0
            if o.showQueue and remaining <= queueWindow then
                blend = math.min(1, (queueWindow - remaining) / 0.15)
            end
            bar:SetStatusBarColor(
                base[1] + (COLOR_QUEUE[1] - base[1]) * blend,
                base[2] + (COLOR_QUEUE[2] - base[2]) * blend,
                base[3] + (COLOR_QUEUE[3] - base[3]) * blend)
        end
        if state.test and now >= state.endT then
            FinishCast("done")
        end
    elseif state.mode == "fade" then
        local alpha = 1 - (now - state.fadeStart) / FADE_TIME
        if alpha <= 0 then
            state.failed = nil
            HideOrPlaceholder()
        else
            castFrame:SetAlpha(math.min(1, alpha))
        end
    end

    if pendingFlight or flight then
        UpdateFlight(now)
    end

    if #popupOrder > 0 then
        UpdatePopups(now)
    end

    -- GCD-Balken: gruen, sobald der naechste Zauber in die Warteschlange darf
    local gcdActive = o.showGCD and gcdEnd and now < gcdEnd
    if gcdActive then
        local total = gcdEnd - gcdStart
        if not gcdTimerMode then -- im Timer-Modus fuellt Blizzard den Balken selbst
            gcdBar:SetValue(total > 0 and (now - gcdStart) / total or 1)
        end
        if o.showQueue and gcdEnd - now <= queueWindow then
            gcdBar:SetStatusBarColor(COLOR_QUEUE[1], COLOR_QUEUE[2], COLOR_QUEUE[3])
        else
            gcdBar:SetStatusBarColor(0.8, 0.8, 0.8)
        end
        gcdBar:Show()
    else
        gcdBar:Hide()
    end

    -- Nichts mehr zu tun? Dann schlafen legen, bis wieder etwas passiert.
    if not state.mode and not pendingFlight and not flight and #popupOrder == 0 and not gcdActive then
        Sleep()
    end
end)

---------------------------------------------------------------------------
-- Verschieben
---------------------------------------------------------------------------
-- Raster (aus ForeverHub.lua): nur entsperrt, und nur beim Ziehen oder bei offenen Einstellungen
-- (ein Dauer-Raster waere stoerend, solange man nur kurz entsperrt)
-- Nach aussen nur diese drei (200-Variablen-Grenze); castFrame.fcOnMoved setzt das Einstellungsfenster
local RestorePosition, UpdateGrid, SetPosition
do
local castDragging = false
function UpdateGrid()
    local o = GetDB()
    local opts = _G.ForeverCastOptions
    local want = o.gridShow and not o.locked and (castDragging or (opts and opts:IsShown()))
    UI.Grid("ForeverCast", want and o.gridSize or nil)
end

castFrame:RegisterForDrag("LeftButton")
UI.AddMover(castFrame) -- andere Forever-Rahmen rasten an der Leiste ein
castFrame:SetScript("OnDragStart", function()
    local o = GetDB()
    if o.locked then return end
    anchor:StartMoving()
    castDragging = true
    UpdateGrid()
    -- Einrasten: gemeinsamer Schalter in der Übersicht (Umschalt = frei), Raster beim Ziehen
    UI.BeginDrag(anchor, { edges = castFrame, grid = o.gridShow and o.gridSize or nil })
end)

-- Position als Versatz der Mitte zur Bildschirmmitte speichern (so stehen X/Y in den Einstellungen)
function SetPosition(x, y)
    GetDB().pos = { "CENTER", "CENTER", UI.Round(x), UI.Round(y) }
    RestorePosition()
    if castFrame.fcOnMoved then castFrame.fcOnMoved() end
end

castFrame:SetScript("OnDragStop", function()
    anchor:StopMovingOrSizing()
    local dx, dy = UI.EndDrag()
    castDragging = false
    UpdateGrid()
    local x, y = UI.CenterOffset(anchor)
    SetPosition(x + dx, y + dy)
end)
end -- Ende Block "Verschieben"

function RestorePosition()
    local pos = GetDB().pos
    anchor:ClearAllPoints()
    if pos then
        anchor:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        anchor:SetPoint("CENTER", 32, -336)
    end
end

---------------------------------------------------------------------------
-- Blizzard-Zauberleiste ausblenden
---------------------------------------------------------------------------
-- Bewusst nur Events abmelden und verstecken: Methoden wie SetUnit wuerden die
-- Blizzard-Leiste "verunreinigen" und koennen das Blockier-Fenster ausloesen.
local blizzPending = false
local blizzHidden = false

-- Im Bearbeitungsmodus zeigt Blizzard die Leiste als Vorschau an – ganz ohne Ereignisse. Deshalb zusaetzlich
-- unsichtbar halten (UI.HideBlizzard aus dem ForeverHub: Alpha 0, gegen Zuruecksetzen abgesichert, kein taint).
-- Ihr Auswahl-Rahmen im Bearbeitungsmodus wird nicht anklickbar, damit man die unsichtbare Leiste dort nicht
-- aus Versehen erwischt. Geht auch im Kampf (die Leiste ist nicht geschuetzt).
local function KeepBlizzardInvisible(f)
    UI.HideBlizzard(f, { when = function() return GetDB().hideBlizzard end, children = false,
        noMouse = { f.Selection } })
end

local function ApplyBlizzardBar()
    local f = PlayerCastingBarFrame or CastingBarFrame
    if f and GetDB().hideBlizzard then KeepBlizzardInvisible(f) end
    if not GetDB().hideBlizzard or blizzHidden then return end
    if not f then return end
    if InCombatLockdown() then
        blizzPending = true -- im Kampf nichts an Blizzard-Fenstern aendern
        return
    end
    -- Laeuft gerade ein Zauber, warten: ohne Ereignisse wuerde die Leiste sonst stehen bleiben
    if f:IsShown() then
        C_Timer.After(1, ApplyBlizzardBar)
        return
    end
    blizzPending = false
    -- Nur die Ereignisse abmelden, NICHT :Hide() aufrufen: Hide() startet Blizzards eigene
    -- Ausblende-Skripte im Namen dieses Addons ("taint"). Das verschmutzt den Bearbeitungsmodus
    -- und das Rechtsklick-Menue (z. B. Raid-Symbole setzen wird dann blockiert).
    -- Ohne Ereignisse zeigt sich die (ohnehin versteckte) Leiste einfach nie wieder.
    f:UnregisterAllEvents()
    blizzHidden = true
end

---------------------------------------------------------------------------
-- Test-Durchlauf: spielt alle Funktionen nacheinander ab
---------------------------------------------------------------------------
local function RunTestSequence()
    testToken = testToken + 1
    local token = testToken
    local steps = {
        { 0, function()
            StartCast(false, { name = T("Testzauber", "Test spell"), duration = 2.5,
                texture = "Interface\\Icons\\Spell_Fire_FireBolt02",
                expect = { low = 120, high = 140, crit = 12.5 } })
        end },
        { 3.2, function()
            StartCast(true, { name = T("Testkanal (5 Ticks)", "Test channel (5 ticks)"), duration = 3,
                texture = "Interface\\Icons\\Spell_Shadow_SiphonMana", ticks = 5,
                expect = { low = 300, high = 300, overTime = 3, crit = 8 } })
        end },
        { 6.8, function()
            StartCast(false, { name = T("Testzauber (wird unterbrochen)", "Test spell (interrupted)"),
                duration = 2, texture = "Interface\\Icons\\Spell_Frost_FrostBolt02" })
        end },
        { 7.8, function() FinishCast("interrupted") end },
        { 8.8, function()
            ShowPopup(T("Test-DoT", "Test DoT"), "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
                { low = 120, high = 120, overTime = 18, crit = 9.2 })
            ShowPopup(T("Test-Spontanzauber", "Test instant"), "Interface\\Icons\\Spell_Fire_Fireball",
                { low = 55, high = 67, crit = 8.5 })
            if ns.TestMirror then ns.TestMirror() end -- Atem-Leiste (Mirror.lua)
        end },
        { 10, function()
            pendingFlight = nil
            flight = { short = T("Testflug", "Test flight"), start = GetTime(), known = 4, test = true }
            if GetDB().showFlight then ShowFlightBar() else Wake() end
        end },
        { 14.8, function()
            craft = { total = 5, done = 2 }
            StartCast(false, { name = T("Leinenverband", "Linen Bandage"), duration = 1.5, tradeSkill = true,
                texture = "Interface\\Icons\\INV_Misc_Bandage_15" })
        end },
        { 16.6, function()
            craft = nil
            Chat(T("Test-Durchlauf beendet.", "Test run finished."))
        end },
    }
    Chat(T("Test-Durchlauf startet (ca. 17 Sekunden) …", "Test run starting (about 17 seconds) …"))
    for _, step in ipairs(steps) do
        C_Timer.After(step[1], Safe("Test", function()
            if token == testToken then step[2]() end -- ein echter Zauber bricht den Test ab
        end))
    end
end

---------------------------------------------------------------------------
-- Selbsttest (/fcast status): was ist auf diesem Client verfuegbar oder gesperrt?
---------------------------------------------------------------------------
local savedVarsLoaded -- wird bei ADDON_LOADED gesetzt

local function StatusLine(label, status, detail)
    local colors = { ok = "|cff33ff33", warn = "|cffffcc00", bad = "|cffff4444" }
    local words = {
        ok = T("OK", "OK"), warn = T("eingeschränkt", "limited"), bad = T("fehlt/gesperrt", "missing/locked"),
    }
    Chat(string.format("%s[%s]|r %s%s", colors[status], words[status], label, detail and ("  – " .. detail) or ""))
end

local function RunStatus()
    local inCombat = InCombatLockdown()
    Chat(T("|cffffb300— Selbsttest —|r", "|cffffb300— Self-test —|r") ..
        (inCombat and T(" (im Kampf: manche Werte sind dann gesperrt)", " (in combat: some values are locked)") or ""))

    StatusLine(T("Gespeicherte Einstellungen geladen", "Saved settings loaded"),
        savedVarsLoaded and "ok" or "warn",
        not savedVarsLoaded and T("nein – Beta-Bug? Standardwerte aktiv", "no – beta bug? using defaults") or nil)

    StatusLine(T("Zauberzeiten (UnitCastingInfo)", "Cast times (UnitCastingInfo)"),
        UnitCastingInfo and "ok" or "bad")

    StatusLine(T("Ersatz bei gesperrten Zeiten (Timer-Balken)", "Fallback for locked times (timer bar)"),
        bar.SetTimerDuration and "ok" or "warn",
        not bar.SetTimerDuration and T("fehlt – bei gesperrten Zeiten bleibt der Balken stehen",
            "missing – bar stays static if times are locked") or nil)

    -- Zauberbeschreibung testweise am ersten Zauber im Zauberbuch lesen
    local testID
    pcall(ForEachSpellbookSpell, function(id) testID = testID or id end)
    if not (C_Spell and C_Spell.GetSpellDescription) and not GetSpellDescription then
        StatusLine(T("Zauberbeschreibungen", "Spell descriptions"), "bad")
    elseif not testID then
        StatusLine(T("Zauberbeschreibungen", "Spell descriptions"), "warn", T("Zauberbuch nicht lesbar", "spellbook not readable"))
    else
        local desc = ReadDescription(testID)
        local cachedCount = 0
        for _ in pairs(expectCache) do cachedCount = cachedCount + 1 end
        StatusLine(T("Zauberbeschreibungen", "Spell descriptions"), IsSecret(desc) and "warn" or "ok",
            string.format(T("%d Zauber mit Schadens-/Heilwerten bekannt%s", "%d spells with damage/heal values known%s"),
                cachedCount, IsSecret(desc) and T(", gerade gesperrt", ", currently locked") or ""))
    end

    local crit = GetSpellCritChance and GetSpellCritChance(2)
    StatusLine(T("Zauber-Krit-Chance", "Spell crit chance"),
        not GetSpellCritChance and "bad" or (IsSecret(crit) and "warn" or "ok"))

    local methods = {
        gcd = { "ok", T("Blizzard-GCD", "Blizzard GCD") },
        spell = { "ok", T("über die Abklingzeit des Zaubers", "via the spell's cooldown") },
        timer = { "warn", T("Blizzard-Timer (Werte gesperrt)", "Blizzard timer (values locked)") },
        estimate = { "warn", string.format(T("geschätzt (%.1f s)", "estimated (%.1f s)"), EstimateGCD()) },
    }
    local m = gcdMethod and methods[gcdMethod]
    if m then
        StatusLine(T("Globale Abklingzeit (GCD)", "Global cooldown (GCD)"), m[1], m[2])
    else
        StatusLine(T("Globale Abklingzeit (GCD)", "Global cooldown (GCD)"),
            (C_Spell and C_Spell.GetSpellCooldown) and "warn" or "bad",
            T("noch nicht erkannt – erst einen Zauber wirken, dann erneut testen",
                "not detected yet – cast a spell, then test again"))
    end

    local cp = GetCurrentCombo()
    StatusLine(T("Combopunkte", "Combo points"), cp ~= nil and "ok" or "warn",
        cp ~= nil and tostring(cp) or T("nicht lesbar", "not readable"))

    StatusLine(T("Ping / Lag", "Ping / lag"), GetNetStats and "ok" or "bad",
        string.format("%d ms%s", GetPing(), measuredLag and string.format(T(", gemessen %d ms", ", measured %d ms"),
            measuredLag * 1000 + 0.5) or ""))

    StatusLine(T("Flugmeister-Funktionen", "Flight master functions"),
        (TakeTaxiNode and UnitOnTaxi and TaxiNodeName) and "ok" or "bad")

    local flightCount = 0
    for _ in pairs(GetDB().flights) do flightCount = flightCount + 1 end
    StatusLine(T("Gemerkte Flugzeiten", "Remembered flight times"), "ok",
        string.format(T("%d Strecken bekannt", "%d routes known"), flightCount))

    StatusLine(T("Herstellungs-Zähler", "Crafting counter"),
        ((C_TradeSkillUI and C_TradeSkillUI.CraftRecipe) or DoTradeSkill) and "ok" or "bad")

    StatusLine(T("Fehler seit dem Login", "Errors since login"), errorCount == 0 and "ok" or "warn",
        tostring(errorCount))
end

---------------------------------------------------------------------------
-- Einstellungsfenster (gleicher Stil wie die anderen Forever-Addons)
---------------------------------------------------------------------------
-- Nach aussen gebraucht werden nur diese drei; der Rest bleibt im do-Block (200-Variablen-Grenze)
local ApplySettings, ToggleOptions, ToggleLock
do
-- Seite im zentralen Einstellungsfenster von Forever Core (verhält sich wie das bisherige eigene Fenster)
local options = UI.SettingsPanel("ForeverCastOptions", T("ForeverCast – Einstellungen", "ForeverCast – Settings"), 600, 700,
    { key = "ForeverCast", group = UI.SETTINGS_GROUPS.frames, label = T("Zauberleiste", "Cast bar") })
local L, R, COL = 16, 306, 276 -- linke / rechte Spalte, Breite der Ueberschriften

local function MakeButton(parent, text, width, onClick)
    return UI.Button(parent, text, width, Safe("Einstellungen", onClick))
end

-- Haekchen in Abschnitten: { Schluessel, Beschriftung }
local checkboxes = {}
local function Section(x, y, title, list)
    UI.Header(options, x + 2, y, title, COL)
    for i, opt in ipairs(list) do
        local key = opt[1]
        checkboxes[key] = UI.Check(options, x - 2, y - 22 - (i - 1) * 24, opt[2], Safe("Einstellungen", function(checked)
            GetDB()[key] = checked
            if key == "hideBlizzard" and not checked then
                -- wieder sichtbar (z. B. im Bearbeitungsmodus); Zauber zeigt sie erst nach /reload wieder an
                local f = PlayerCastingBarFrame or CastingBarFrame
                if f then UI.ShowBlizzard(f) end
                if blizzHidden then
                    Chat(T("Die Blizzard-Zauberleiste kommt nach /reload zurück.", "The Blizzard cast bar returns after /reload."))
                end
            end
            ApplySettings()
        end))
    end
end

Section(L, -32, T("Leiste", "Bar"), {
    { "locked",       T("Leiste sperren (nicht verschiebbar)", "Lock bar (not movable)") },
    { "showIcon",     T("Zaubersymbol anzeigen", "Show spell icon") },
    { "hideBlizzard", T("Blizzard-Zauberleiste ausblenden", "Hide Blizzard cast bar") },
})
Section(L, -146, T("Zauber", "Spells"), {
    { "showLatency",  T("Ping und Lag-Bereich (rot) anzeigen", "Show ping and lag zone (red)") },
    { "showQueue",    T("Spell-Queue-Fenster (grün) anzeigen", "Show spell queue window (green)") },
    { "showGCD",      T("GCD-Balken unter der Leiste anzeigen", "Show GCD bar below") },
    { "showTicks",    T("Ticks bei kanalisierten Zaubern", "Show ticks on channeled spells") },
    { "showPushback", T("Rückstoß anzeigen (+0.5 s)", "Show pushback (+0.5 s)") },
    { "showCombo",    T("Combopunkte an der Leiste anzeigen", "Show combo points at the bar") },
})
Section(R, -32, T("Zusatz-Infos", "Extras"), {
    { "showExpect",   T("Schaden/Heilung + Krit aus Tooltip", "Damage/healing + crit from tooltip") },
    { "showInstant",  T("Spontanzauber/DoTs kurz anzeigen", "Briefly show instants/DoTs") },
    { "showMelee",    T("Nahkampf-/Waffenangriffe mit Schaden", "Melee/weapon attacks with damage") },
    { "showFlight",   T("Flugzeit-Timer beim Fliegen", "Flight timer") },
    { "showCraft",    T("Herstellungs-Zähler (3/20)", "Crafting counter (3/20)") },
})

-- Groesse der Leiste
UI.Header(options, R + 2, -190, T("Größe", "Size"), COL)
local widthSlider = UI.Slider(options, R + 2, -214, T("Länge", "Length"), 120, 500, 10, Safe("Einstellungen", function(value)
    GetDB().width = value
    ApplySize()
end), { width = 170, unit = " px" })
local heightSlider = UI.Slider(options, R + 2, -254, T("Höhe", "Height"), 12, 40, 2, Safe("Einstellungen", function(value)
    GetDB().height = value
    ApplySize()
end), { width = 170, unit = " px" })

-- Spell-Queue-Fenster einstellen (Spieleinstellung "SpellQueueWindow")
UI.Header(options, L + 2, -334, T("Spell-Queue-Fenster", "Spell queue window"), 568)
local queueLabel = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
queueLabel:SetPoint("TOPLEFT", L + 2, -360)

local function UpdateQueueLabel()
    queueLabel:SetText(string.format(T("Spell-Queue-Fenster: %d ms", "Spell queue window: %d ms"), queueWindow * 1000 + 0.5))
end

local function ChangeQueueWindow(delta)
    if InCombatLockdown() then
        Chat(T("Das Spell-Queue-Fenster kann nicht im Kampf geändert werden.", "The spell queue window cannot be changed in combat."))
        return
    end
    local ms = math.floor(queueWindow * 1000 + 0.5) + delta
    ms = math.max(0, math.min(400, ms))
    SetCVarValue("SpellQueueWindow", tostring(ms))
    RefreshQueueWindow()
    UpdateQueueLabel()
end

local minusBtn = MakeButton(options, "–", 20, function() ChangeQueueWindow(-50) end)
minusBtn:SetPoint("TOPLEFT", L + 210, -356)
local plusBtn = MakeButton(options, "+", 20, function() ChangeQueueWindow(50) end)
plusBtn:SetPoint("LEFT", minusBtn, "RIGHT", 2, 0)

local queueHint = UI.Hint(options, L + 2, -384, 560, T("So früh vor Zauberende darfst du den nächsten Zauber drücken. " ..
    "Faustregel: Ping + ca. 100 ms. Standard von WoW: 400 ms.",
    "How early before the cast ends you may press the next spell. " ..
    "Rule of thumb: ping + about 100 ms. WoW default: 400 ms."))

local pingInfo = UI.Text(options, "label")
pingInfo:SetPoint("TOPLEFT", queueHint, "BOTTOMLEFT", 0, -8)

local function UpdatePingInfo()
    local _, _, home, world = GetNetStats()
    local lag = measuredLag and string.format(T("   ·   gemessener Lag: %d ms", "   ·   measured lag: %d ms"),
        measuredLag * 1000 + 0.5) or ""
    pingInfo:SetText(string.format(T("Ping: %d ms (Welt) / %d ms (Heimat)%s", "Ping: %d ms (world) / %d ms (home)%s"),
        world or 0, home or 0, lag))
end

-- Position: X/Y (Mitte der Leiste ab Bildschirmmitte), Raster und Einrasten
UI.Header(options, L + 2, -456, T("Position (X/Y ab Bildschirmmitte)", "Position (X/Y from screen center)"), COL)
local function PosGet(i)
    return function() return select(i, UI.CenterOffset(anchor)) end
end
local function PosSet(i)
    return Safe("Einstellungen", function(v)
        local x, y = UI.CenterOffset(anchor)
        if i == 1 then x = v else y = v end
        SetPosition(x, y)
    end)
end
local posX = UI.Number(options, L + 4, -480, "X", PosGet(1), PosSet(1))
local posY = UI.Number(options, L + 150, -480, "Y", PosGet(2), PosSet(2))
castFrame.fcOnMoved = function()
    if options:IsShown() then posX:Load() posY:Load() end
end
-- Look (Look.lua): Forever (Standard) oder Clean (bisheriger Look); Einrasten gilt über den Schalter der Übersicht
UI.Header(options, R + 2, -456, T("Look", "Look"), COL)
local lookBtn = UI.AddArrow(UI.Button(options, "", 220))
lookBtn:SetPoint("TOPLEFT", R + 2, -480)
-- (Hilfen als Felder statt eigener Variablen: die Datei ist nahe an Luas Grenze von 200 lokalen Variablen)
function lookBtn.Load()
    local mode = ns.LookMode()
    for _, l in ipairs(ns.LOOKS) do if l.key == mode then lookBtn:SetText(l.label) return end end
end
lookBtn:SetScript("OnClick", Safe("Einstellungen", function(self)
    UI.ChoiceMenu(self, ns.LOOKS, ns.LookMode, function(key)
        GetDB().look = key
        lookBtn.Load()
        ns.Restyle()
    end)
end))

-- Ziel & Fokus (Units.lua) und Atem/Erschöpfung (Mirror.lua)
Section(L, -540, T("Zauberleisten für Ziel und Fokus", "Cast bars for target and focus"), {
    { "targetBar", T("Zauberleiste des Ziels", "Target cast bar") },
    { "focusBar",  T("Zauberleiste des Fokus", "Focus cast bar") },
    { "unitDock",  T("Unter den Rahmen von ForeverUnits", "Below the ForeverUnits frames") },
})
UI.Hint(options, L + 2, -640, COL - 10, T("Nicht angedockt (oder ohne ForeverUnits): frei verschiebbar, wenn die Leiste entsperrt ist.",
    "Not docked (or without ForeverUnits): movable while the bar is unlocked.")):SetWordWrap(true)
Section(R, -540, T("Atem und Erschöpfung", "Breath and fatigue"), {
    { "showMirror", T("Im Forever-Stil über der Zauberleiste", "In Forever style above the cast bar") },
})
local unitHeightSlider = UI.Slider(options, R + 2, -600, T("Höhe Ziel/Fokus-Leisten", "Height of target/focus bars"), 12, 30, 2,
    Safe("Einstellungen", function(value)
        GetDB().unitHeight = value
        if ns.ApplyUnits then ns.ApplyUnits() end
    end), { width = 170, unit = " px" })

local testBtn = MakeButton(options, T("Test", "Test"), 70, RunTestSequence)
testBtn:SetPoint("BOTTOMLEFT", 16, 14)

local statusBtn = MakeButton(options, T("Selbsttest", "Self-test"), 90, RunStatus)
statusBtn:SetPoint("LEFT", testBtn, "RIGHT", 6, 0)

local resetPosBtn = MakeButton(options, T("Position & Größe zurück", "Reset position & size"), 150, function()
    local o = GetDB()
    o.pos = nil
    o.width, o.height = DEFAULTS.width, DEFAULTS.height
    widthSlider:Load(o.width)
    heightSlider:Load(o.height)
    RestorePosition()
    ApplySize()
    castFrame.fcOnMoved()
end)
resetPosBtn:SetPoint("BOTTOMRIGHT", -16, 14)

local pingTicker
options:SetScript("OnShow", Safe("Einstellungen", function()
    RefreshQueueWindow()
    UpdateQueueLabel()
    UpdatePingInfo()
    for key, cb in pairs(checkboxes) do
        cb:SetChecked(GetDB()[key])
    end
    widthSlider:Load(GetDB().width)
    heightSlider:Load(GetDB().height)
    unitHeightSlider:Load(GetDB().unitHeight)
    lookBtn.Load()
    posX:Load()
    posY:Load()
    UpdateGrid()
    pingTicker = C_Timer.NewTicker(1, Safe("Einstellungen", UpdatePingInfo))
end))
options:SetScript("OnHide", function()
    if pingTicker then pingTicker:Cancel() end
    UpdateGrid()
end)

ApplySettings = function()
    local o = GetDB()
    ApplySize()
    iconFrame:SetShown(o.showIcon)
    castFrame:EnableMouse(not o.locked) -- gesperrt: Klicks gehen durch die Leiste durch
    if not state.mode then HideOrPlaceholder() end
    for key, cb in pairs(checkboxes) do
        cb:SetChecked(o[key])
    end
    UpdateCombo()
    ApplyBlizzardBar()
    UpdateGrid()
    if ns.ApplyUnits then ns.ApplyUnits() end   -- Ziel/Fokus (Units.lua)
    if ns.ApplyMirror then ns.ApplyMirror() end -- Atem/Erschöpfung (Mirror.lua)
end
ns.OnRestyle = function() ApplySettings() end
ns.IsLocked = function() return GetDB().locked end

function ToggleOptions()
    options:SetShown(not options:IsShown())
end

function ToggleLock()
    local o = GetDB()
    o.locked = not o.locked
    ApplySettings()
    Chat(o.locked and T("Leiste gesperrt.", "Bar locked.") or T("Leiste entsperrt – zum Verschieben ziehen.", "Bar unlocked – drag to move."))
end

-- gemeinsamer Verschiebe-Modus (/fmove, Sammelknopf)
if UI.RegisterMovable then
    UI.RegisterMovable("ForeverCast", function() return GetDB().locked end, function(locked)
        GetDB().locked = locked
        ApplySettings()
    end)
end
end -- Ende Block "Einstellungsfenster"

---------------------------------------------------------------------------
-- Minimap-Button
---------------------------------------------------------------------------
local UpdateMinimapPosition -- nach aussen gebraucht
do
local mmButton = UI.MinimapButton({
    name = "ForeverCastMinimapButton",
    icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    title = "ForeverCast",
    angle = function() return GetDB().minimapAngle end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = Safe("Minimap", function(_, button)
        if button == "RightButton" then ToggleLock() else ToggleOptions() end
    end),
    lines = function()
        return {
            T("Linksklick: Einstellungen", "Left-click: settings"),
            T("Rechtsklick: Leiste sperren/entsperren", "Right-click: lock/unlock bar"),
        }
    end,
})
UpdateMinimapPosition = mmButton.UpdatePosition
end -- Ende Block "Minimap-Button"

---------------------------------------------------------------------------
-- Events (jedes Event einzeln abgesichert)
---------------------------------------------------------------------------
-- Passt eine Fehl-/Abbruchmeldung zum aktuellen Zauber?
local function IsCurrentCast(castGUID)
    if state.castID and not IsSecret(castGUID) and castGUID then
        return castGUID == state.castID
    end
    return state.mode == "cast" -- ohne vergleichbare ID nur waehrend eines laufenden Zaubers
end

local function MeasureLag()
    if sentTime then
        local lag = GetTime() - sentTime
        if lag < 2 then measuredLag = lag end
        sentTime = nil
    end
end

local H = {} -- Event-Name -> Funktion

H.ADDON_LOADED = function(name)
    if name ~= ADDON_NAME then return end
    -- Selbst angelegte Tabelle (__fresh) = SavedVariables wurden NICHT geladen
    savedVarsLoaded = type(_G.ForeverCastDB) == "table" and not _G.ForeverCastDB.__fresh
    GetDB().__fresh = nil
    RestorePosition()
    UpdateMinimapPosition()
    RefreshQueueWindow()
    ApplySettings()
end

H.PLAYER_ENTERING_WORLD = function()
    RestorePosition()
    UpdateMinimapPosition()
    RefreshQueueWindow()
    ApplySettings()
    PrecacheSpells()
end

H.PLAYER_REGEN_ENABLED = function()
    if blizzPending then ApplyBlizzardBar() end
    PrecacheSpells() -- nach dem Kampf Werte auffrischen
end

H.SPELLS_CHANGED = PrecacheSpells
H.PLAYER_EQUIPMENT_CHANGED = PrecacheSpells
-- Waffenschaden/Angriffskraft geaendert (Buffs, Waffenwechsel): Werte auffrischen
-- (PrecacheSpells liest nur ausserhalb des Kampfs)
H.UNIT_DAMAGE = PrecacheSpells
H.UNIT_ATTACK_POWER = PrecacheSpells
H.UNIT_RANGEDDAMAGE = PrecacheSpells
H.UNIT_RANGED_ATTACK_POWER = PrecacheSpells
H.CVAR_UPDATE = RefreshQueueWindow
H.SPELL_UPDATE_COOLDOWN = function() UpdateGCD() end

-- Combopunkte: aendern sich am Spieler (Retail) bzw. am Ziel (Classic)
H.UNIT_POWER_UPDATE = function(_, powerType)
    if not IsSecret(powerType) and powerType == "COMBO_POINTS" then UpdateCombo() end
end
H.UNIT_POWER_FREQUENT = H.UNIT_POWER_UPDATE
H.UNIT_MAXPOWER = function() UpdateCombo() end
H.PLAYER_TARGET_CHANGED = function() UpdateCombo() end

H.SPELL_DATA_LOAD_RESULT = function(spellID, success)
    if success and not InCombatLockdown() and not IsSecret(spellID) then GetExpectation(spellID) end
end


-- Combopunkte beim Druecken der Taste merken – beim Aufpoppen sind sie schon verbraucht
local comboAtSend

H.UNIT_SPELLCAST_SENT = function(_, target)
    sentTime = GetTime()
    comboAtSend = GetCurrentCombo()

    -- Was wird geoeffnet? Name des Objekts unter der Maus (Tooltip-Zeile 1) merken,
    -- dazu ein Quest-Fortschritt aus dem Tooltip ("Kiste (Vorräte: 2/5)").
    state.openTarget = nil
    if GameTooltip and GameTooltip:IsShown() and _G.GameTooltipTextLeft1 then
        local title = _G.GameTooltipTextLeft1:GetText()
        if not IsSecret(title) and title and title ~= "" then
            local text = title
            for i = 2, math.min(GameTooltip:NumLines() or 0, 8) do
                local line = _G["GameTooltipTextLeft" .. i]
                local s = line and line:GetText()
                if not IsSecret(s) and s and s:find("%d+%s*/%s*%d+") then
                    text = text .. " (" .. strtrim((s:gsub("^%s*%-%s*", ""))) .. ")"
                    break
                end
            end
            state.openTarget = text
        end
    end
    if not state.openTarget and not IsSecret(target) and target and target ~= "" then
        state.openTarget = target
    end
end

H.UNIT_SPELLCAST_START = function()
    MeasureLag()
    StartCast(false)
end

H.UNIT_SPELLCAST_DELAYED = function() OnCastUpdated(false) end

H.UNIT_SPELLCAST_CHANNEL_START = function()
    MeasureLag()
    StartCast(true)
end

H.UNIT_SPELLCAST_CHANNEL_UPDATE = function() OnCastUpdated(true) end

H.UNIT_SPELLCAST_STOP = function()
    if state.mode == "cast" and not state.test then FinishCast("done") end
end

H.UNIT_SPELLCAST_CHANNEL_STOP = function()
    if state.mode == "channel" and not state.test then FinishCast("done") end
end

H.UNIT_SPELLCAST_INTERRUPTED = function(_, castGUID, _, by)
    if state.test then return end
    if state.mode == "channel" or IsCurrentCast(castGUID) then FinishCast("interrupted", by) end
end

H.UNIT_SPELLCAST_FAILED = function(_, castGUID)
    if state.test then return end
    if state.mode ~= "channel" and IsCurrentCast(castGUID) then FinishCast("failed") end
end

H.UNIT_SPELLCAST_SUCCEEDED = function(_, _, spellID)
    UpdateGCD(spellID)
    -- Ein Gegenstand fertig hergestellt: Zaehler weiter
    if craft and state.isTradeSkill and not state.test then
        craft.done = craft.done + 1
        if craft.done >= craft.total then craft = nil end
    end
    -- Spontanzauber? Kurz warten, ob doch ein Zauber/Kanalisieren laeuft
    -- (bei Zaubern mit Zauberzeit kommt diese Meldung waehrend die Leiste noch laeuft).
    local o = GetDB()
    local isInstant = state.mode ~= "cast" and state.mode ~= "channel"
    if debugMode and isInstant then DebugSpell(spellID) end
    if o.showInstant and o.showExpect and not IsSecret(spellID) and spellID and isInstant then
        local combo = comboAtSend
        comboAtSend = nil
        C_Timer.After(0.05, Safe("Spontanzauber", function() ShowInstant(spellID, combo) end))
    end
end

local events = CreateFrame("Frame")
local UNIT_EVENTS = {
    UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_SUCCEEDED = true, UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_DAMAGE = true, UNIT_ATTACK_POWER = true, UNIT_RANGEDDAMAGE = true, UNIT_RANGED_ATTACK_POWER = true,
    UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true,
}
for event in pairs(H) do
    -- Abgesichert: gibt es ein Event auf diesem Client nicht, wird es einfach uebersprungen
    if UNIT_EVENTS[event] then
        pcall(events.RegisterUnitEvent, events, event, "player")
    else
        pcall(events.RegisterEvent, events, event)
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    local handler = H[event]
    if not handler then return end
    local ok, err = pcall(handler, ...)
    if not ok then ReportError(event, err) end
end)

---------------------------------------------------------------------------
-- Slash-Befehl
---------------------------------------------------------------------------
SLASH_FOREVERCAST1 = "/fcast"
SLASH_FOREVERCAST2 = "/forevercast"
SlashCmdList["FOREVERCAST"] = Safe("Befehl", function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "lock" then
        ToggleLock()
    elseif msg == "test" then
        RunTestSequence()
    elseif msg == "status" then
        RunStatus()
    elseif msg == "debug" then
        debugMode = not debugMode
        Chat(debugMode and T("Debug an: Spontanzauber werden im Chat analysiert.", "Debug on: instants are analysed in chat.")
            or T("Debug aus.", "Debug off."))
    else
        ToggleOptions()
    end
end)

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = "ForeverCast", sv = "ForeverCastDB", defaults = DEFAULTS, version = 1 })
