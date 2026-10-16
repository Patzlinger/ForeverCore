-- ForeverFrames: Debuff- und Buff-Anzeige
-- Im Kampf sind Aura-Daten oft "geheim". Deshalb:
--  * Auren werden ueber ihre Instanz-ID und Blizzards Filter gefunden
--    ("HARMFUL|RAID" = von mir bannbar, "HELPFUL|PLAYER|RAID_IN_COMBAT" = meine HoTs),
--  * Symbol, Stapel und Ablaufzeit werden nur durchgereicht (das erlaubt Blizzard),
--  * die Farbe je Debuff-Typ liefert Blizzard ueber eine Farbkurve – ohne dass wir den Typ vergleichen.
local ADDON_NAME, ns = ...
local T, IsSecret, GetDB, Safe = ns.T, ns.IsSecret, ns.GetDB, ns.Safe

local WHITE = "Interface\\Buttons\\WHITE8x8"
ns.MAX_AURA_ICONS = 6

-- Debuff-Typen: Einstellungs-Schluessel, Symbol und Nummer fuer Blizzards Farbkurve
ns.DEBUFF_TYPES = {
    { name = "Magic",   id = 1,  key = "colorMagic",   atlas = "RaidFrame-Icon-DebuffMagic",   label = T("Magie", "Magic") },
    { name = "Curse",   id = 2,  key = "colorCurse",   atlas = "RaidFrame-Icon-DebuffCurse",   label = T("Fluch", "Curse") },
    { name = "Disease", id = 3,  key = "colorDisease", atlas = "RaidFrame-Icon-DebuffDisease", label = T("Krankheit", "Disease") },
    { name = "Poison",  id = 4,  key = "colorPoison",  atlas = "RaidFrame-Icon-DebuffPoison",  label = T("Gift", "Poison") },
    { name = "Bleed",   id = 11, key = "colorBleed",   atlas = "RaidFrame-Icon-DebuffBleed",   label = T("Blutung", "Bleed") },
}
local TYPE_BY_NAME = {}
for _, t in ipairs(ns.DEBUFF_TYPES) do TYPE_BY_NAME[t.name] = t end

---------------------------------------------------------------------------
-- Farbkurven (werden neu gebaut, wenn sich eine Farbe aendert)
---------------------------------------------------------------------------
local curves = {}  -- icon = Typfarbe (ohne Typ: "ohne"-Farbe), border = Typfarbe (ohne Typ: unsichtbar), sym[name] = nur dieser Typ sichtbar
local curveSignature

local function ColorKeySignature()
    local parts = {}
    for _, t in ipairs(ns.DEBUFF_TYPES) do
        local r, g, b = ns.Color(t.key)
        parts[#parts + 1] = string.format("%.3f%.3f%.3f", r, g, b)
    end
    local r, g, b = ns.Color("colorNone")
    parts[#parts + 1] = string.format("%.3f%.3f%.3f", r, g, b)
    return table.concat(parts)
end

local function NewCurve()
    local c = C_CurveUtil.CreateColorCurve()
    if Enum and Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
    return c
end

local function BuildCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return end
    local sig = ColorKeySignature()
    if sig == curveSignature then return end
    curveSignature = sig

    local nr, ng, nb = ns.Color("colorNone")
    curves.icon, curves.border, curves.sym = NewCurve(), NewCurve(), {}
    curves.icon:AddPoint(0, CreateColor(nr, ng, nb, 1))
    curves.border:AddPoint(0, CreateColor(0, 0, 0, 0))
    for _, t in ipairs(ns.DEBUFF_TYPES) do
        curves.sym[t.name] = NewCurve()
        curves.sym[t.name]:AddPoint(0, CreateColor(1, 1, 1, 0))
    end
    -- Luecken (z. B. 5–10) bekommen "ohne Typ"
    local points = {}
    for _, t in ipairs(ns.DEBUFF_TYPES) do points[#points + 1] = t end
    table.sort(points, function(a, b) return a.id < b.id end)
    for i, t in ipairs(points) do
        local r, g, b = ns.Color(t.key)
        curves.icon:AddPoint(t.id, CreateColor(r, g, b, 1))
        curves.border:AddPoint(t.id, CreateColor(r, g, b, 1))
        for _, s in ipairs(ns.DEBUFF_TYPES) do
            curves.sym[s.name]:AddPoint(t.id, CreateColor(1, 1, 1, s.name == t.name and 1 or 0))
        end
        local nextID = points[i + 1] and points[i + 1].id or 99
        if nextID > t.id + 1 then
            curves.icon:AddPoint(t.id + 1, CreateColor(nr, ng, nb, 1))
            curves.border:AddPoint(t.id + 1, CreateColor(0, 0, 0, 0))
            for _, s in ipairs(ns.DEBUFF_TYPES) do
                curves.sym[s.name]:AddPoint(t.id + 1, CreateColor(1, 1, 1, 0))
            end
        end
    end
end

-- Farbe eines Debuff-Typs aus den Einstellungen; ohne Typ: "ohne"-Farbe bzw. unsichtbar
local function TypeColor(typeName, invisibleIfNone)
    local t = typeName and TYPE_BY_NAME[typeName]
    if t then
        local r, g, b = ns.Color(t.key)
        return r, g, b, 1
    end
    if invisibleIfNone then return 0, 0, 0, 0 end
    local r, g, b = ns.Color("colorNone")
    return r, g, b, 1
end

-- Im Kampf kann Blizzard den ganzen Aura-Datensatz sperren. Er wird trotzdem benutzt:
-- Felder werden geschuetzt gelesen, die (gesperrten) Werte nur an Blizzard-Funktionen
-- weitergereicht (Symbol, Stapel, Ablaufzeit). Kein Vergleich, kein Wahr/Falsch-Test damit.
local function GetAura(unit, id)
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
    if ok then return aura end
end

local function HasAura(aura)
    return IsSecret(aura) or aura ~= nil
end

local function Field(aura, key)
    if IsSecret(aura) then
        local ok, value = pcall(function() return aura[key] end)
        if ok then return value end
        return nil
    end
    if aura == nil then return nil end
    return aura[key]
end

-- Textur in der Farbe des Debuff-Typs einfaerben (auch wenn der Typ geheim ist)
local function ColorByType(tex, unit, id, aura, curve, invisibleIfNone)
    local typeName = Field(aura, "dispelName")
    if not IsSecret(aura) and not IsSecret(typeName) then
        tex:SetVertexColor(TypeColor(typeName, invisibleIfNone))
        return
    end
    local ok = curve and C_UnitAuras.GetAuraDispelTypeColor and pcall(function()
        tex:SetVertexColor(C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve):GetRGBA())
    end)
    if not ok then tex:SetVertexColor(TypeColor(nil, invisibleIfNone)) end
end

---------------------------------------------------------------------------
-- Aura-Listen
---------------------------------------------------------------------------
-- Aura-Nummern einer Einheit (nur ausserhalb des Kampfs – im Kampf sperrt Forever alle Abfragen;
-- dort zeichnet die Blizzard-Anzeige). Gesperrt/fehlgeschlagen: nil, true
local function GetIDs(unit, filter)
    if C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs then
        local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
        if ok and type(ids) == "table" and not IsSecret(ids) then return ids end
    end
    -- Ersatzweg: der Reihe nach abfragen
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil, true end
    local ids = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok then
            if i == 1 then return nil, true end
            break
        end
        if not HasAura(aura) then break end
        local id = Field(aura, "auraInstanceID")
        if IsSecret(id) or id ~= nil then ids[#ids + 1] = id end
    end
    return ids
end

local function IsDispellable(unit, id)
    if not (C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then return false end
    local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, id, "HARMFUL|RAID")
    if ok and not IsSecret(filtered) then return not filtered end
    return false
end


---------------------------------------------------------------------------
-- Eigene Buff-Liste (pro Klasse): Namen und/oder Zauber-IDs, durch Komma oder Zeile getrennt
---------------------------------------------------------------------------
local customCache = { text = nil, names = {}, ids = {} }

function ns.GetCustomBuffText()
    local db = GetDB()
    local _, class = UnitClass("player")
    if type(db.buffCustom) ~= "table" then db.buffCustom = {} end
    return db.buffCustom[class or "ALL"] or ""
end

function ns.SetCustomBuffText(text)
    local db = GetDB()
    local _, class = UnitClass("player")
    if type(db.buffCustom) ~= "table" then db.buffCustom = {} end
    db.buffCustom[class or "ALL"] = text
end

local function CustomList()
    local text = ns.GetCustomBuffText()
    if text ~= customCache.text then
        customCache.text = text
        wipe(customCache.names)
        wipe(customCache.ids)
        for entry in text:gmatch("[^,\n]+") do
            entry = strtrim(entry)
            local id = tonumber(entry)
            if id then
                customCache.ids[id] = true
            elseif entry ~= "" then
                customCache.names[entry:lower()] = true
            end
        end
    end
    return customCache
end

-- Eingebaute Standardliste: gaengige eigene HoTs/Schutz-Buffs je Klasse.
-- Blizzards Raid-Filter kennt viele Classic-Zauber (z. B. Erneuerung) nicht, deshalb diese Liste.
-- Es zaehlt der Name (aus der ID gelesen) – so passen alle Raenge und jede Spielsprache.
local CLASS_BUFFS = {
    PRIEST  = { 139, 17, 6346 },            -- Erneuerung, Machtwort: Schild, Furchtschutz
    DRUID   = { 774, 8936, 33763, 2893 },   -- Verjuengung, Nachwachsen, Blühendes Leben, Vergiftung aufheben
    PALADIN = { 1022, 1044, 6940 },         -- Segen des Schutzes, der Freiheit, der Opferung
    SHAMAN  = { 29203, 16177, 974 },        -- Heilende Wege, Seelenstaerke der Ahnen, Erdschild
    WARLOCK = { 20707 },                    -- Seelenstein-Auferstehung
    HUNTER  = { 136, 34477 },               -- Tier heilen, Irrefuehrung
    MAGE    = {},
    WARRIOR = {},
    ROGUE   = {},
}

-- Alle Raenge der gaengigen HoTs/Schutz-Buffs je Klasse (Classic-IDs). Gebraucht fuer die
-- Blizzard-Anzeige, die nur Zauber-IDs kennt: Fremde Zauber (z. B. Verjuengung beim Hexenmeister)
-- stehen nicht im eigenen Zauberbuch, deshalb hier fest eingetragen.
local CLASS_BUFF_RANKS = {
    PRIEST  = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315,         -- Erneuerung
                17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901,             -- Machtwort: Schild
                6346 },                                                                 -- Furchtschutz
    DRUID   = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299,      -- Verjuengung
                8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858,                   -- Nachwachsen
                33763, 2893 },                                                          -- Bluehendes Leben, Vergiftung aufheben
    PALADIN = { 1022, 5599, 10278, 1044, 6940, 20729 },                                 -- Schutz, Freiheit, Opferung
    SHAMAN  = { 29203, 16177, 16236, 16237, 974 },                                      -- Heilende Wege, Ahnen, Erdschild
    WARLOCK = { 20707, 20762, 20763, 20764, 20765 },                                    -- Seelenstein-Auferstehung
    HUNTER  = { 34477 },                                                                -- Irrefuehrung
}

-- alle Klassen zusammen (fuer "HoTs anderer Spieler zeigen")
local allClassList
local function AllClassBuffList()
    if not allClassList or not next(allClassList.names) then
        allClassList = { names = {}, ids = {} }
        for _, list in pairs(CLASS_BUFF_RANKS) do
            for _, id in ipairs(list) do
                allClassList.ids[id] = true
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                if not IsSecret(name) and name then allClassList.names[name:lower()] = true end
            end
        end
    end
    return allClassList
end

local classBuffList
local function ClassBuffList()
    -- neu bauen, solange noch kein Name gelesen werden konnte (Daten evtl. noch nicht geladen)
    if not classBuffList or (#classBuffList.labels == 0 and classBuffList.expected > 0) then
        local _, class = UnitClass("player")
        local idList = CLASS_BUFFS[class] or {}
        classBuffList = { names = {}, ids = {}, labels = {}, expected = #idList }
        for _, id in ipairs(idList) do
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if not IsSecret(name) and name then
                if not classBuffList.names[name:lower()] then
                    classBuffList.labels[#classBuffList.labels + 1] = name
                end
                classBuffList.names[name:lower()] = true
            end
        end
    end
    return classBuffList
end

-- fuer die Einstellungen: "Erneuerung, Machtwort: Schild, ..."
function ns.GetClassBuffLabels()
    local labels = ClassBuffList().labels
    if #labels == 0 then return T("(keine für deine Klasse)", "(none for your class)") end
    return table.concat(labels, ", ")
end

local function MatchesCustom(aura, list)
    if not HasAura(aura) or IsSecret(aura) then return false end
    local sid, name = Field(aura, "spellId"), Field(aura, "name")
    if not IsSecret(sid) and sid and list.ids[sid] then return true end
    if not IsSecret(name) and name and list.names[name:lower()] then return true end
    return false
end

---------------------------------------------------------------------------
-- Sichtbarer Teil
---------------------------------------------------------------------------
local function NewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(16, 16)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetAllPoints()
    f.border:SetTexture(WHITE)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f.icon)
    f.cd:SetReverse(true)
    f.cd:SetDrawEdge(false)
    -- Restzeit: Blizzard zeichnet Scheibe und Zahl selbst (klappt auch mit gesperrten Zeiten)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(false) end
    -- im Kampf kann die Liste nicht neu abgefragt werden: abgelaufene Symbole selbst entfernen
    f.cd:SetScript("OnCooldownDone", function()
        if InCombatLockdown() then
            f:Hide()
            f.ffAuraID = nil
        end
    end)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f.cd:GetFrameLevel() + 2)
    f.count = top:CreateFontString(nil, "OVERLAY")
    f.count:SetFont("Fonts\\ARIALN.TTF", 10, "OUTLINE")
    f.count:SetPoint("BOTTOMRIGHT", 2, -1)
    f:Hide()
    return f
end

---------------------------------------------------------------------------
-- Blizzard-Anzeige ("AuraContainer"): das Spiel zeichnet die Auren selbst – auch im Kampf.
-- Das Addon legt nur vorher fest: Einheit, Filter, Anzahl, Groesse, Anordnung.
-- (Vorbild: KallyeRaidFrames. Neuer Rahmentyp, deshalb jeder Aufruf abgesichert.)
---------------------------------------------------------------------------
local engine = {}

function engine.Supported()
    return AuraContainerSortDirection ~= nil and AuraContainerSortMethod ~= nil
end

local function CreateContainer(parent)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if ok and c then return c end
    ok, c = pcall(CreateFrame, "AuraContainer", nil, parent)
    if ok then return c end
end

-- Wachstumsrichtung -> Blizzards Fluss-Layout
local FLOW = {
    RIGHT = { axis = "HORIZONTAL", h = "FORWARD", v = "FORWARD" },
    LEFT  = { axis = "HORIZONTAL", h = "BACKWARD", v = "FORWARD" },
    UP    = { axis = "VERTICAL", h = "FORWARD", v = "FORWARD" },
    DOWN  = { axis = "VERTICAL", h = "FORWARD", v = "BACKWARD" },
}

local function EnumValue(enumTable, ...)
    if not enumTable then return nil end
    for i = 1, select("#", ...) do
        local v = enumTable[(select(i, ...))]
        if v ~= nil then return v end
    end
end

local function ApplyFlow(container, growth, point, lineSize)
    local flow = FLOW[growth] or FLOW.RIGHT
    local axisEnum = AnchorUtil and AnchorUtil.FlowLayoutAxis
    local dirEnum = AnchorUtil and AnchorUtil.FlowDirection
    if not (axisEnum and dirEnum and container.SetFlowLayoutAxis) then return false end
    local axis = flow.axis == "VERTICAL" and EnumValue(axisEnum, "Vertical", "VERTICAL", "Y")
        or EnumValue(axisEnum, "Horizontal", "HORIZONTAL", "X")
    local forward = EnumValue(dirEnum, "Up", "Right", "Forward", "FORWARD", "Positive")
    local backward = EnumValue(dirEnum, "Down", "Left", "Backward", "BACKWARD", "Negative")
    if axis == nil or forward == nil or backward == nil then return false end
    return pcall(function()
        container:SetFlowLayoutAxis(axis)
        container:SetFlowLayoutGrowthDirection(flow.h == "BACKWARD" and backward or forward,
            flow.v == "BACKWARD" and backward or forward)
        container:SetFlowLayoutAnchorPoint(point)
        container:SetFlowLayoutMaximumLineSize(math.max(1, lineSize))
    end)
end

-- Symbol-Aussehen beim Anlegen (gilt nur fuer neu erzeugte Symbole – deshalb bei Aenderung neuer Container)
local function MakeInitializer(size, showCooldown)
    local db = GetDB()
    local swipe, numbers, numberSize = db.auraTimerSwipe, db.auraTimerNumbers, db.auraTimerSize
    local tooltip = db.auraTooltip
    return function(button)
        button:SetSize(size, size)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 1)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)
        if showCooldown then
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:EnableMouse(false)
            cd:SetReverse(true)
            cd:SetDrawEdge(false)
            cd:SetDrawSwipe(swipe)
            cd:SetHideCountdownNumbers(not numbers)
            local text = cd.GetCountdownFontString and cd:GetCountdownFontString()
            if text then text:SetFont("Fonts\\ARIALN.TTF", numberSize, "OUTLINE") end
            button:SetDurationCooldown(cd)
        end
        -- Klicks gehen immer durch auf den Rahmen (Klick-Zauber!).
        -- Mit Tooltip: nur das Drueberfahren wird erkannt, Klicks bleiben durchlaessig.
        if tooltip and button.SetMouseClickEnabled and button.SetMouseMotionEnabled then
            button:EnableMouse(true)
            button:SetMouseClickEnabled(false)
            button:SetMouseMotionEnabled(true)
        else
            button:EnableMouse(false)
        end
    end
end

-- Kennung fuer das Aussehen: aendert sie sich, braucht es einen frischen Container
local function LookSignature(size, showCooldown)
    local db = GetDB()
    return table.concat({ size, tostring(showCooldown), tostring(db.auraTimerSwipe),
        tostring(db.auraTimerNumbers), db.auraTimerSize, tostring(db.auraTooltip) }, ":")
end

local function GroupLayout(container, key, prefix, num, layoutIndex)
    local db = GetDB()
    local size = db[prefix .. "Size"]
    local layout = {
        elementWidth = size, elementHeight = size,
        elementSpacing = 1, lineSpacing = 1, layoutIndex = layoutIndex or 1,
    }
    if not ApplyFlow(container, db[prefix .. "Grow"], db[prefix .. "Point"], num * (size + 1)) then
        local grow = db[prefix .. "Grow"]
        layout.growthDirection = (grow == "LEFT" and "LEFT_UP") or (grow == "UP" and "UP_RIGHT")
            or (grow == "DOWN" and "DOWN_RIGHT") or "RIGHT_UP"
        layout.wrapAfter = num * (size + 1)
    end
    pcall(container.SetAuraGroupLayout, container, key, layout)
end

local function RetireContainer(c)
    if not c then return end
    pcall(c.ClearAuraGroups, c)
    c:Hide()
end

-- Container fuer eine Aura-Art (Buffs/Debuffs) bereitstellen und an die Einstellungen anpassen.
-- groups = { { key, filter, candidates, max }, ... }
-- Die Gruppen werden EINMAL angelegt; Filter, Zauber-Auswahl und Anzahl danach nur umgestellt
-- (Loeschen und Neuanlegen vertraegt der Container nicht). Abgeschaltet: Filter "" und Anzahl 0.
local function EnsureGroups(v, kind, groups, prefix, showCooldown)
    local db = GetDB()
    local size = db[prefix .. "Size"]
    local num = math.min(db[prefix .. "Num"], ns.MAX_AURA_ICONS)
    v.engineC = v.engineC or {}
    local c = v.engineC[kind]
    local sig = LookSignature(size, showCooldown) .. ":" .. #groups

    if not c or c.ffSig ~= sig then
        RetireContainer(c)
        c = CreateContainer(v.auraLayer)
        if not c then return nil end
        for _, g in ipairs(groups) do
            local ok, err = pcall(c.AddAuraGroup, c, g.key, g.filter, {
                maxFrameCount = g.max,
                sortMethod = AuraContainerSortMethod.Default,
                sortDirection = AuraContainerSortDirection.Normal,
                candidateFilters = g.candidates,
                initializeFrame = MakeInitializer(size, showCooldown),
            })
            if not ok then
                ns.ReportError("AuraContainer " .. g.key, err)
                c:Hide()
                return nil
            end
        end
        c.ffSig, c.ffUnit = sig, nil
        v.engineC[kind] = c
    end
    for i, g in ipairs(groups) do
        pcall(c.SetAuraGroupFilterString, c, g.key, g.filter)
        if c.SetAuraGroupCandidateFilters then pcall(c.SetAuraGroupCandidateFilters, c, g.key, g.candidates) end
        pcall(c.SetAuraGroupMaxFrameCount, c, g.key, g.max)
        GroupLayout(c, g.key, prefix, num, i)
    end
    return c
end

local function DebuffEngineFilter()
    return GetDB().debuffMode == "dispellable" and "HARMFUL|RAID" or "HARMFUL"
end

-- Zauber-IDs fuer die Blizzard-Anzeige: eingetragene IDs + alle Raenge aus dem Zauberbuch,
-- deren Name auf der Liste steht (in Classic hat jeder Rang eine eigene ID)
local spellIDCache = {}
local function SpellIDSet(names, ids)
    local out = {}
    for id in pairs(ids or {}) do out[id] = true end
    if next(names or {}) and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    local name = item and item.name
                    if item and item.spellID and name and not IsSecret(name) and names[name:lower()] then
                        out[item.spellID] = true
                    end
                end
            end
        end
    end
    return out
end

local function ClassBaseIDs()
    local _, class = UnitClass("player")
    local ids = {}
    for _, id in ipairs(CLASS_BUFFS[class] or {}) do ids[id] = true end
    for _, id in ipairs(CLASS_BUFF_RANKS[class] or {}) do ids[id] = true end
    return ids
end

-- Welche Buffs soll die Blizzard-Anzeige zeigen? (passend zu "Anzeigen" im Reiter Buffs)
local function BuffEngineGroups(num)
    local db = GetDB()
    local mode = db.buffMode
    local include = {}
    local function merge(set) for id in pairs(set) do include[id] = true end end
    if mode == "hots" or mode == "both" then
        merge(SpellIDSet(ClassBuffList().names, ClassBaseIDs()))
    end
    if mode == "custom" or mode == "both" then
        local custom = CustomList()
        merge(SpellIDSet(custom.names, custom.ids))
    end
    -- HoTs/Schutz-Buffs anderer Spieler (alle Klassen) dazunehmen
    local groupHots = db.buffOthers and (mode == "hots" or mode == "both")
    if groupHots then merge(AllClassBuffList().ids) end
    -- eigene Liste ohne "nur meine" oder HoTs anderer: Buffs von allen, nicht nur von mir
    local othersToo = groupHots or ((mode == "custom" or mode == "both") and not db.buffCustomMine)
    -- leere Liste = Gruppe aus (eine leere Auswahl wuerde Blizzard als "alles zeigen" lesen)
    local any = next(include) ~= nil
    local groups = {
        { key = "ff_buffs", filter = any and (othersToo and "HELPFUL" or "HELPFUL|PLAYER") or "",
          candidates = any and { includeSpellIDs = include } or nil, max = any and num or 0 },
    }
    -- optional: weitere kurze eigene Buffs (z. B. andere HoTs), lange/dauerhafte bleiben draussen
    local short = db.buffEngineShort and mode ~= "custom"
    groups[2] = { key = "ff_buffs_short", filter = short and "HELPFUL|PLAYER" or "",
        candidates = short and { maxDuration = 120, excludeSpellIDs = any and include or nil } or nil,
        max = short and num or 0 }
    return groups
end
ns.BuffEngineGroups = BuffEngineGroups

local function SetContainerUnit(c, unit)
    if c and unit and c.ffUnit ~= unit then
        if pcall(c.SetUnit, c, unit) then c.ffUnit = unit end
    end
end

-- Container eines Buttons an die Einstellungen anpassen (Aussehen, Filter, Position)
function engine.Layout(b)
    local v, db = b.ff, GetDB()
    local use = db.auraEngine and engine.Supported() and not b.ffFake
    v.engine = nil
    if not use then
        for _, c in pairs(v.engineC or {}) do c:Hide() end
        return
    end

    local debuffNum = math.min(db.debuffNum, ns.MAX_AURA_ICONS)
    local buffNum = math.min(db.buffNum, ns.MAX_AURA_ICONS)
    -- Buff-Auswahl einmal pro Aufbau berechnen (Zauberbuch-Suche), nicht fuer jeden Rahmen
    local now = GetTime()
    if not spellIDCache.groups or spellIDCache.stamp ~= now then
        spellIDCache.groups = BuffEngineGroups(buffNum)
        spellIDCache.stamp = now
    end
    local specs = {
        { kind = "debuff", prefix = "debuff", on = db.debuffMode ~= "off", cd = db.debuffCooldown,
          groups = { { key = "ff_debuffs", filter = DebuffEngineFilter(), max = debuffNum } } },
        { kind = "buff", prefix = "buff", on = db.buffMode ~= "off", cd = db.buffCooldown,
          groups = spellIDCache.groups },
    }
    local any = false
    for _, s in ipairs(specs) do
        local existing = v.engineC and v.engineC[s.kind]
        if s.on then
            local c = EnsureGroups(v, s.kind, s.groups, s.prefix, s.cd)
            if c then
                local point = db[s.prefix .. "Point"]
                c:ClearAllPoints()
                c:SetPoint(point, v.top, point, db[s.prefix .. "X"], db[s.prefix .. "Y"])
                c.ffUnit = nil -- Einheit neu setzen: Blizzard sortiert mit den neuen Filtern neu ein
                SetContainerUnit(c, b.ffUnit)
                c:Show()
                any = true
            end
        elseif existing then
            existing:Hide()
        end
    end
    -- nur wenn mind. ein Container laeuft, schweigt das alte System
    v.engine = any or (db.debuffMode == "off" and db.buffMode == "off") or nil
end
-- neue Einheit am Rahmen: Container mitziehen (auch im Kampf)
function engine.SetUnit(b)
    local v = b.ff
    if not v.engine or not b.ffUnit then return end
    for _, c in pairs(v.engineC or {}) do SetContainerUnit(c, b.ffUnit) end
end
ns.auraEngine = engine

function ns.CreateAuraVisuals(b)
    local v = b.ff
    v.auraLayer = CreateFrame("Frame", nil, v.top)
    v.auraLayer:SetAllPoints(v.top)
    v.auraLayer:SetFrameLevel(v.top:GetFrameLevel() + 1)
    v.debuffs, v.buffs = {}, {}
    for i = 1, ns.MAX_AURA_ICONS do
        v.debuffs[i] = NewIcon(v.auraLayer)
        v.buffs[i] = NewIcon(v.auraLayer)
    end

    -- Typ-Symbole: eins pro Typ uebereinander; sichtbar ist nur das passende
    v.dispelSym = {}
    for _, t in ipairs(ns.DEBUFF_TYPES) do
        local tex = v.auraLayer:CreateTexture(nil, "OVERLAY")
        tex:SetAtlas(t.atlas)
        tex:Hide()
        v.dispelSym[t.name] = tex
    end

    -- Rahmen um den ganzen Button in Typfarbe (4 Kanten)
    v.dispelBorder = CreateFrame("Frame", nil, v.top)
    v.dispelBorder:SetAllPoints(v.content)
    v.dispelBorder:SetFrameLevel(v.top:GetFrameLevel() + 1)
    v.dispelEdges = {}
    for i = 1, 4 do
        local e = v.dispelBorder:CreateTexture(nil, "OVERLAY")
        e:SetTexture(WHITE)
        v.dispelEdges[i] = e
    end
    v.dispelBorder:Hide()
end

local GROW = {
    RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 },
}

local function PlaceRow(v, icons, prefix)
    local db = GetDB()
    local size, point = db[prefix .. "Size"], db[prefix .. "Point"]
    local dir = GROW[db[prefix .. "Grow"]] or GROW.RIGHT
    local step = size + 1
    for i, f in ipairs(icons) do
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint(point, v.top, point, db[prefix .. "X"] + dir[1] * step * (i - 1), db[prefix .. "Y"] + dir[2] * step * (i - 1))
        f.count:SetFont("Fonts\\ARIALN.TTF", math.max(8, math.floor(size * 0.6)), "OUTLINE")
        -- Restzeit-Anzeige: Scheibe und/oder Zahl
        f.cd:SetDrawSwipe(db.auraTimerSwipe)
        if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(not db.auraTimerNumbers) end
        local timerText = f.cd.GetCountdownFontString and f.cd:GetCountdownFontString()
        if timerText then
            timerText:SetFont("Fonts\\ARIALN.TTF", db.auraTimerSize, "OUTLINE")
            timerText:ClearAllPoints()
            timerText:SetPoint("CENTER", f, "CENTER", 0, 0)
        end
    end
end

function ns.LayoutAuras(b)
    local v, db = b.ff, GetDB()
    if not v.debuffs then return end
    BuildCurves()
    engine.Layout(b) -- Blizzard-Anzeige (falls verfuegbar und eingeschaltet)
    PlaceRow(v, v.debuffs, "debuff")
    PlaceRow(v, v.buffs, "buff")

    for _, tex in pairs(v.dispelSym) do
        tex:ClearAllPoints()
        tex:SetPoint(db.dispelPoint, v.top, db.dispelPoint, db.dispelX, db.dispelY)
        tex:SetSize(db.dispelSize, db.dispelSize)
    end

    local s = db.dispelBorderSize
    local e = v.dispelEdges
    for i = 1, 4 do e[i]:ClearAllPoints() end
    e[1]:SetPoint("TOPLEFT") e[1]:SetPoint("TOPRIGHT") e[1]:SetHeight(s)
    e[2]:SetPoint("BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT") e[2]:SetHeight(s)
    e[3]:SetPoint("TOPLEFT") e[3]:SetPoint("BOTTOMLEFT") e[3]:SetWidth(s)
    e[4]:SetPoint("TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT") e[4]:SetWidth(s)
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------
local function HideFrom(icons, first)
    for i = first, #icons do icons[i]:Hide() end
end

-- Ein Symbol fuellen; alles wird nur an Blizzard-Funktionen durchgereicht.
-- Jeder Schritt ist einzeln abgesichert: scheitert z. B. die Ablaufzeit, bleibt das Symbol trotzdem.
local function Step(_, fn)
    return (pcall(fn))
end

local function FillIcon(f, unit, id, aura, isDebuff, showCooldown)
    if not Step(T("Symbol", "icon"), function() f.icon:SetTexture(Field(aura, "icon")) end) then
        f.icon:SetTexture(134400) -- Fragezeichen
    end

    local countDone = C_UnitAuras.GetAuraApplicationDisplayCount and pcall(function()
        f.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, id, 2))
    end)
    if not countDone then
        local stacks = Field(aura, "applications")
        if not IsSecret(stacks) and (stacks or 0) > 1 then
            f.count:SetText(stacks)
        else
            f.count:SetText("")
        end
    end
    f.ffAuraID = (not IsSecret(id)) and id or nil -- zum Wiederfinden, wenn die Aura entfernt wird

    -- Ablaufzeit: erst Blizzards Dauer-Objekt, sonst aus den Aura-Daten selbst
    -- (im Kampf ist die Abfrage gesperrt, die mitgelieferten Daten evtl. nicht)
    local cdDone = not showCooldown
    if showCooldown and C_UnitAuras.GetAuraDuration and f.cd.SetCooldownFromDurationObject then
        cdDone = pcall(function() f.cd:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, id)) end)
    end
    if not cdDone then
        local duration, expiration = Field(aura, "duration"), Field(aura, "expirationTime")
        if not Step(T("Ablaufzeit", "duration"), function()
            if IsSecret(duration, expiration) then
                f.cd:SetCooldownFromExpirationTime(expiration, duration)
            elseif (duration or 0) > 0 and expiration then
                f.cd:SetCooldown(expiration - duration, duration)
            else
                f.cd:Clear()
            end
        end) then
            pcall(f.cd.Clear, f.cd)
        end
    elseif not showCooldown then
        f.cd:Clear()
    end

    if not Step(T("Randfarbe", "border color"), function()
        if isDebuff and GetDB().debuffTypeBorder then
            ColorByType(f.border, unit, id, aura, curves.icon, false)
        else
            f.border:SetVertexColor(0, 0, 0, 1)
        end
    end) then
        f.border:SetVertexColor(0, 0, 0, 1)
    end
    f:Show()
end

-- Kurve fuer gesperrte Buffs: sichtbar (1), solange die Restzeit zwischen 0 und 2 Minuten liegt,
-- sonst unsichtbar (0). Blizzard wertet sie aus – das Addon vergleicht nichts.
local shortCurve
local function ShortBuffCurve()
    if shortCurve == nil then
        shortCurve = false
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            local c = C_CurveUtil.CreateCurve()
            if Enum and Enum.LuaCurveType and c.SetType then c:SetType(Enum.LuaCurveType.Step) end
            c:AddPoint(0, 0)
            c:AddPoint(0.05, 1)
            c:AddPoint(120, 1)
            c:AddPoint(120.05, 0)
            shortCurve = c
        end
    end
    return shortCurve
end

-- unknown = Buff im Kampf, dessen Name gesperrt ist: nur sichtbar, wenn er kurz laeuft (wie ein HoT)
local function ShowIcon(f, unit, id, isDebuff, showCooldown, unknown)
    local aura = GetAura(unit, id)
    if not HasAura(aura) then return false end
    local ok, err = pcall(FillIcon, f, unit, id, aura, isDebuff, showCooldown)
    if not ok then
        f:Hide()
        ns.ReportError(T("Aura-Symbol", "Aura icon"), err)
        return false
    end
    f:SetAlpha(1)
    if unknown then
        local curve = ShortBuffCurve()
        local shown = curve and C_UnitAuras.GetAuraDuration and pcall(function()
            f:SetAlpha(C_UnitAuras.GetAuraDuration(unit, id):EvaluateRemainingDuration(curve))
        end)
        if not shown then f:SetAlpha(1) end
    end
    return true
end

local function HideDispel(v)
    for _, tex in pairs(v.dispelSym) do tex:Hide() end
    v.dispelBorder:Hide()
end

-- Typ-Symbol und Rahmen fuer einen bannbaren Debuff
local function ShowDispel(v, unit, id)
    local db = GetDB()
    if not (IsSecret(id) or id) or (not db.dispelShow and not db.dispelBorder) then HideDispel(v) return end
    local aura = GetAura(unit, id)
    local typeName = Field(aura, "dispelName")
    if not IsSecret(aura) and not IsSecret(typeName) then
        local t = typeName and TYPE_BY_NAME[typeName]
        for name, tex in pairs(v.dispelSym) do
            tex:SetVertexColor(1, 1, 1, 1)
            tex:SetShown(db.dispelShow and t ~= nil and name == typeName)
        end
        if db.dispelBorder and t then
            local r, g, b = TypeColor(typeName)
            for _, e in ipairs(v.dispelEdges) do e:SetVertexColor(r, g, b, 1) end
            v.dispelBorder:Show()
        else
            v.dispelBorder:Hide()
        end
        return
    end
    -- Typ geheim: Blizzard faerbt per Kurve, unpassende Symbole bleiben durchsichtig
    local ok = pcall(function()
        for name, tex in pairs(v.dispelSym) do
            if db.dispelShow then
                tex:SetVertexColor(C_UnitAuras.GetAuraDispelTypeColor(unit, id, curves.sym[name]):GetRGBA())
                tex:Show()
            else
                tex:Hide()
            end
        end
        if db.dispelBorder then
            local c = C_UnitAuras.GetAuraDispelTypeColor(unit, id, curves.border)
            for _, e in ipairs(v.dispelEdges) do e:SetVertexColor(c:GetRGBA()) end
            v.dispelBorder:Show()
        else
            v.dispelBorder:Hide()
        end
    end)
    if not ok then HideDispel(v) end
end

local function UpdateDebuffs(b)
    local v, db, unit = b.ff, GetDB(), b.ffUnit
    if db.debuffMode == "off" and not db.dispelShow and not db.dispelBorder then
        HideFrom(v.debuffs, 1)
        HideDispel(v)
        return
    end
    local ids, blocked = GetIDs(unit, "HARMFUL")
    if blocked then return nil, nil, true end
    ids = ids or {}
    local dispellable, others = {}, {}
    for _, id in ipairs(ids) do
        if IsDispellable(unit, id) then
            dispellable[#dispellable + 1] = id
        else
            others[#others + 1] = id
        end
    end

    -- Symbole: bannbare zuerst
    local n = 0
    if db.debuffMode ~= "off" and not v.engine then
        local max = math.min(db.debuffNum, ns.MAX_AURA_ICONS)
        local lists = db.debuffMode == "dispellable" and { dispellable } or { dispellable, others }
        for _, list in ipairs(lists) do
            for _, id in ipairs(list) do
                if n >= max then break end
                if ShowIcon(v.debuffs[n + 1], unit, id, true, db.debuffCooldown) then n = n + 1 end
            end
        end
    end
    HideFrom(v.debuffs, n + 1)

    -- Typ-Symbol und Rahmen: erster von mir bannbarer Debuff (oder auf Wunsch der erste mit Typ)
    -- (ueber die Laenge der Liste gewaehlt: die Nummern selbst koennen gesperrt sein)
    local target
    if #dispellable > 0 then
        target = dispellable[1]
    elseif not db.dispelOnlyMine and #ids > 0 then
        target = ids[1]
    end
    ShowDispel(v, unit, target)
    return #ids, n
end

-- Entscheidung pro Aura merken (ihre Nummer bleibt bis zum Ablauf gleich): true = zeigen,
-- false = nicht zeigen. So bleibt ein vor dem Kampf erkannter Buff auch im Kampf erkannt,
-- wenn Blizzard seinen Namen sperrt.
local buffDecision, decisionCount = {}, 0

local function Remember(id, decision)
    if IsSecret(id) then return end -- gesperrte Nummer: kann nicht gemerkt werden
    if buffDecision[id] == nil then
        decisionCount = decisionCount + 1
        if decisionCount > 3000 then wipe(buffDecision) decisionCount = 0 end
    end
    buffDecision[id] = decision
end

local function Readable(aura)
    return HasAura(aura) and not IsSecret(aura) and not IsSecret(Field(aura, "name")) and not IsSecret(Field(aura, "spellId"))
end

local function ShortReadable(aura)
    local d = Field(aura, "duration")
    return not IsSecret(d) and d ~= nil and d > 0 and d <= 120
end

local function UpdateBuffs(b)
    local v, db, unit = b.ff, GetDB(), b.ffUnit
    local mode = db.buffMode
    if mode == "off" or v.engine then HideFrom(v.buffs, 1) return end -- Blizzard-Anzeige zeichnet selbst

    local useClass = mode == "hots" or mode == "both"
    local custom = CustomList()
    local useCustom = (mode == "custom" or mode == "both") and (next(custom.ids) or next(custom.names)) and true or false
    local classList = ClassBuffList()

    local known, unknown, seen = {}, {}, {}
    local function add(list, id)
        if IsSecret(id) then list[#list + 1] = id return end
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end

    -- eigene Buffs; im Kampf gesperrt -> vorhandene Symbole stehen lassen
    local mineIDs, blocked = GetIDs(unit, "HELPFUL|PLAYER")
    if blocked then return nil, nil, true end

    -- Blizzard-Filter fuer Raidrahmen
    local raidIDs = useClass and GetIDs(unit, "HELPFUL|PLAYER|RAID_IN_COMBAT") or nil
    for _, id in ipairs(raidIDs or {}) do add(known, id) end

    -- eigene Buffs: Klassenliste / eigene Liste / kurze Laufzeit
    for _, id in ipairs(mineIDs or {}) do
        if IsSecret(id) or not seen[id] then
            local aura = GetAura(unit, id)
            local decision
            if not IsSecret(id) then decision = buffDecision[id] end
            if Readable(aura) then
                decision = (useClass and next(classList.names) ~= nil and MatchesCustom(aura, classList))
                    or (useCustom and MatchesCustom(aura, custom))
                    or (useClass and not raidIDs and ShortReadable(aura))
                    or false
                Remember(id, decision)
            end
            if decision then
                add(known, id)
            elseif decision == nil and useClass then
                -- Name gesperrt und vorher nicht gesehen (im Kampf gewirkt): kurze Buffs zeigen
                add(unknown, id)
            end
        end
    end

    -- Buffs von anderen: eigene Liste (ohne "nur meine") und/oder HoTs aller Klassen
    local otherCustom = useCustom and not db.buffCustomMine
    local otherHots = useClass and db.buffOthers
    if otherCustom or otherHots then
        local allClass = otherHots and AllClassBuffList()
        for _, id in ipairs(GetIDs(unit, "HELPFUL") or {}) do
            if IsSecret(id) or not seen[id] then
                local aura = GetAura(unit, id)
                if Readable(aura) and ((otherCustom and MatchesCustom(aura, custom))
                    or (otherHots and MatchesCustom(aura, allClass))) then
                    add(known, id)
                end
            end
        end
    end

    -- bekannte zuerst, dann die gesperrten (unsichtbare stehen so am Ende und reissen keine Luecken)
    local n, max = 0, math.min(db.buffNum, ns.MAX_AURA_ICONS)
    for pass, list in ipairs({ known, unknown }) do
        for _, id in ipairs(list) do
            if n >= max then break end
            if ShowIcon(v.buffs[n + 1], unit, id, false, db.buffCooldown, pass == 2) then n = n + 1 end
        end
    end
    HideFrom(v.buffs, n + 1)
    return #known + #unknown, n
end

-- Auren aktualisieren. Im Kampf sind alle Abfragen gesperrt: dann gar nicht erst versuchen –
-- die Blizzard-Anzeige zeichnet selbst, Typ-Symbol/Rahmen bleiben bis Kampfende stehen.
function ns.UpdateAuras(b)
    if not b.ff.debuffs or not b.ffUnit then return end
    engine.SetUnit(b)
    if InCombatLockdown() then return end
    local ok, err = pcall(UpdateDebuffs, b)
    if ok then ok, err = pcall(UpdateBuffs, b) end
    if not ok then ns.ReportError(T("Auren", "Auras"), err) end
end

-- nach dem Kampf alle Auren neu aufbauen (sonst erst bei der naechsten Aura-Aenderung)
ns.On("PLAYER_REGEN_ENABLED", T("Auren", "Auras"), function()
    if ns.ForEachShown then ns.ForEachShown(ns.UpdateAuras) end
end)

---------------------------------------------------------------------------
-- Testmodus: Beispiel-Auren
---------------------------------------------------------------------------
local FAKE_DEBUFFS = {
    { icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", type = "Magic" },
    { icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounges", type = "Curse" },
    { icon = "Interface\\Icons\\Spell_Nature_NullifyDisease", type = "Disease" },
    { icon = "Interface\\Icons\\Ability_Creature_Poison_02", type = "Poison" },
    { icon = "Interface\\Icons\\Ability_Gouge" },
}
local FAKE_BUFFS = {
    "Interface\\Icons\\Spell_Holy_Renew",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
    "Interface\\Icons\\Spell_Nature_ResistNature",
}

function ns.UpdateFakeAuras(b)
    local v, db, i = b.ff, GetDB(), b.ffIndex or 1
    if not v.debuffs then return end
    local n = 0
    local debuff = (i % 3 == 0) and FAKE_DEBUFFS[(i / 3 - 1) % #FAKE_DEBUFFS + 1] or nil
    if debuff and db.debuffMode ~= "off" and (db.debuffMode == "all" or debuff.type) then
        local f = v.debuffs[1]
        f.icon:SetTexture(debuff.icon)
        f.count:SetText(i % 2 == 0 and "2" or "")
        if db.debuffCooldown then f.cd:SetCooldown(GetTime() - (i % 7) * 2, 18) else f.cd:Clear() end
        if db.debuffTypeBorder then
            f.border:SetVertexColor(TypeColor(debuff.type))
        else
            f.border:SetVertexColor(0, 0, 0, 1)
        end
        f:Show()
        n = 1
    end
    HideFrom(v.debuffs, n + 1)

    local typeName = debuff and debuff.type
    for name, tex in pairs(v.dispelSym) do
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetShown(db.dispelShow and name == typeName)
    end
    if db.dispelBorder and typeName then
        local r, g, bl = TypeColor(typeName)
        for _, e in ipairs(v.dispelEdges) do e:SetVertexColor(r, g, bl, 1) end
        v.dispelBorder:Show()
    else
        v.dispelBorder:Hide()
    end

    local m = 0
    if db.buffMode ~= "off" then
        local count = math.min((i % 4 == 1) and 2 or (i % 4 == 2 and 1 or 0), db.buffNum)
        for k = 1, count do
            local f = v.buffs[k]
            f.icon:SetTexture(FAKE_BUFFS[(i + k) % #FAKE_BUFFS + 1])
            f.count:SetText("")
            if db.buffCooldown then f.cd:SetCooldown(GetTime() - ((i + k) % 5) * 2, 12 + k * 3) else f.cd:Clear() end
            f.border:SetVertexColor(0, 0, 0, 1)
            f:Show()
            m = k
        end
    end
    HideFrom(v.buffs, m + 1)
end
