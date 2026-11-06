-- ForeverSpellbook: kompaktes Zauberbuch (Prototyp)
--  * Reiter je Zauberbuch-Abschnitt (Allgemein, Klasse, Begleiter), Suche ueber alle Abschnitte
--  * Hinweis, wenn in den Aktionsleisten ein niedrigerer Rang liegt – mit "Ersetzen"-Knopf
--  * "Beim Lehrer": was noch kommt (wird beim Besuch des Klassenlehrers ausgelesen) und
--    noch nicht gelernte Zauber, falls das Zauberbuch sie mit "ab Stufe X" fuehrt
-- Zauber werden per Klick oder Ziehen in die Leiste gelegt, Umschalt-Klick fuegt den Link in den Chat ein.
local ADDON_NAME = ...
local UI = ForeverHub.UI -- gemeinsamer Stil aller Forever-Addons (ForeverHub.lua)
local T = UI.T

---------------------------------------------------------------------------
-- Einstellungen (wegen des Beta-Bugs bei jedem Zugriff pruefen)
---------------------------------------------------------------------------
local DEFAULTS = {
    replaceBlizzard = true,  -- Taste fuers Zauberbuch (P) oeffnet dieses Fenster
    allRanks = false,        -- alle Raenge zeigen (sonst nur den hoechsten)
    warnOutdated = true,     -- Hinweis auf niedrigere Raenge in den Aktionsleisten
    fadeMoving = true,       -- beim Bewegen durchsichtig
    fadeCombat = true,       -- im Kampf durchsichtig
    fadeAlpha = 45,          -- Sichtbarkeit dann (Prozent)
    minimapAngle = 220,
}
local db
local function GetDB()
    if type(_G.ForeverSpellbookDB) ~= "table" then _G.ForeverSpellbookDB = db or {} end
    db = _G.ForeverSpellbookDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end
local charDB
local function GetCharDB()
    if type(_G.ForeverSpellbookCharDB) ~= "table" then _G.ForeverSpellbookCharDB = charDB or {} end
    charDB = _G.ForeverSpellbookCharDB
    return charDB
end

-- besuchte Lehrer je Charakter: [NPC-Name] = { list, level, time, npc }
-- (bis 0.41b gab es nur einen Eintrag "trainer" = zuletzt besuchter Lehrer – wird uebernommen)
local function GetTrainers()
    local c = GetCharDB()
    if type(c.trainers) ~= "table" then c.trainers = {} end
    if type(c.trainer) == "table" then
        c.trainers[c.trainer.npc or "?"] = c.trainer
        c.trainer = nil
    end
    return c.trainers
end

local function Chat(text) UI.Chat("ForeverSpellbook", text) end
local issecret = issecretvalue or function() return false end

local function Money(copper)
    copper = math.max(0, math.floor(copper or 0))
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if f then
        local ok, s = pcall(f, copper)
        if ok and s then return s end
    end
    return tostring(copper) .. "c"
end

local function Level()
    local l = UnitLevel("player")
    return (type(l) == "number" and not issecret(l)) and l or 1
end

-- Rang als Zahl aus "Rang 3" / "Rank 3"
local function RankNumber(text)
    if type(text) ~= "string" or issecret(text) then return nil end
    return tonumber(text:match("(%d+)"))
end

local function SpellSubtext(id)
    return C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
end

---------------------------------------------------------------------------
-- Zauberbuch auslesen
---------------------------------------------------------------------------
local BANK_PLAYER = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local BANK_PET = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet or 1
local TYPE_FUTURE = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
local TYPE_FLYOUT = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout

local lines = {} -- { name, icon, spells = { entry, ... } }

local function ReadItem(slot, bank)
    local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if not item or not item.name or issecret(item.name) then return nil end
    local e = {
        slot = slot, bank = bank, id = item.spellID or item.actionID, name = item.name,
        icon = item.iconID, sub = item.subName, passive = item.isPassive,
        future = TYPE_FUTURE ~= nil and item.itemType == TYPE_FUTURE,
        flyout = TYPE_FLYOUT ~= nil and item.itemType == TYPE_FLYOUT,
    }
    if (not e.sub or e.sub == "") and e.id then e.sub = SpellSubtext(e.id) end
    e.rank = RankNumber(e.sub)
    if e.future and C_SpellBook.GetSpellBookItemLevelLearned then
        local ok, lvl = pcall(C_SpellBook.GetSpellBookItemLevelLearned, slot, bank)
        if ok and type(lvl) == "number" then e.learnLevel = lvl end
    end
    return e
end

local function Collect()
    wipe(lines)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if info and not info.shouldHide and (info.numSpellBookItems or 0) > 0 then
            local line = { name = info.name, icon = info.iconID, spells = {} }
            for s = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local e = ReadItem(s, BANK_PLAYER)
                if e then line.spells[#line.spells + 1] = e end
            end
            lines[#lines + 1] = line
        end
    end
    if C_SpellBook.HasPetSpells then
        -- der zweite Rueckgabewert ist ein interner Code in Grossbuchstaben ("PET", "DEMON"), kein Anzeigename
        local n = C_SpellBook.HasPetSpells()
        if n and n > 0 then
            local line = { name = T("Begleiter", "Pets"), icon = 132599, spells = {}, pet = true }
            for s = 1, n do
                local e = ReadItem(s, BANK_PET)
                if e then line.spells[#line.spells + 1] = e end
            end
            lines[#lines + 1] = line
        end
    end
end

-- hoechster gelernter Rang je Zaubername (fuer den Rang-Vergleich)
local function BestRanks()
    local best = {}
    for _, line in ipairs(lines) do
        for _, e in ipairs(line.spells) do
            if not e.future and not e.passive and e.rank then
                local b = best[e.name]
                if not b or e.rank > b.rank then best[e.name] = e end
            end
        end
    end
    return best
end

-- Nur den hoechsten Rang zeigen (es sei denn, "alle Raenge" ist an); noch nicht Gelerntes ans Ende
local function VisibleSpells(spells)
    local all = GetDB().allRanks
    local top = {}
    for _, e in ipairs(spells) do
        if not e.future then
            local cur = top[e.name]
            if not cur or (e.rank or 0) > (cur.rank or 0) then top[e.name] = e end
        end
    end
    local learned, future = {}, {}
    for _, e in ipairs(spells) do
        if e.future then
            future[#future + 1] = e
        elseif all or top[e.name] == e then
            learned[#learned + 1] = e
        end
    end
    table.sort(future, function(a, b)
        if (a.learnLevel or 0) ~= (b.learnLevel or 0) then return (a.learnLevel or 0) < (b.learnLevel or 0) end
        return (a.slot or 0) < (b.slot or 0)
    end)
    for _, e in ipairs(future) do learned[#learned + 1] = e end
    return learned
end

---------------------------------------------------------------------------
-- Aktionsleisten: liegt irgendwo ein niedrigerer Rang?
---------------------------------------------------------------------------
local function OutdatedSlots()
    local out = {}
    if InCombatLockdown() or not GetActionInfo then return out end
    local best = BestRanks()
    for slot = 1, 180 do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "spell" and id and not issecret(id) then
            local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            local b = name and best[name]
            if b and b.id ~= id then
                local r = RankNumber(SpellSubtext(id))
                if r and r < b.rank then
                    out[#out + 1] = { slot = slot, id = id, rank = r, best = b }
                end
            end
        end
    end
    return out
end

-- Im Kampf ist PickupSpellBookItem für Addons gesperrt (ADDON_ACTION_BLOCKED): dort den Zauber über seine ID aufnehmen
local lastCombatHint = 0
local function PickupEntry(e)
    -- Im Kampf sind PickupSpellBookItem UND PickupSpell/C_Spell.PickupSpell für Addons gesperrt
    -- (ADDON_ACTION_BLOCKED, auch mit pcall): Zauber lassen sich nur außerhalb des Kampfes aufnehmen.
    if InCombatLockdown() then
        if GetTime() - lastCombatHint > 3 then
            lastCombatHint = GetTime()
            Chat(T("Im Kampf nicht möglich – Zauber nach dem Kampf auf die Leiste ziehen (oder Blizzards Zauberbuch nutzen).",
                "Not possible in combat – drag spells to the bar after combat (or use Blizzard's spellbook)."))
        end
        return
    end
    if e.slot and C_SpellBook and C_SpellBook.PickupSpellBookItem then
        C_SpellBook.PickupSpellBookItem(e.slot, e.bank)
    elseif e.id and C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(e.id)
    end
end

-- veraltete Raenge in den Leisten durch den hoechsten ersetzen (nur ausserhalb des Kampfs)
local function ReplaceOutdated()
    if InCombatLockdown() then Chat(T("Im Kampf nicht möglich.", "Not possible in combat.")) return end
    local list, n = OutdatedSlots(), 0
    for _, o in ipairs(list) do
        ClearCursor()
        PickupEntry(o.best)
        local ok = pcall(PlaceAction, o.slot)
        ClearCursor()
        if ok then n = n + 1 end
    end
    Chat(string.format(T("%d Zauber in deinen Leisten auf den höchsten Rang gebracht.", "%d spells on your bars updated to the highest rank."), n))
end

---------------------------------------------------------------------------
-- Lehrer auslesen (beim Besuch): was gibt es, ab welcher Stufe, was kostet es
---------------------------------------------------------------------------
local scanning = false
local SERVICE_TYPES = { available = true, unavailable = true, used = true, header = true }

-- GetTrainerServiceInfo liefert in Forever die Werte in anderer Reihenfolge als in Retail (Status an 2. Stelle,
-- dann eine Symbol-Nummer, kein Rang): Werte nach Inhalt erkennen statt nach Position
local function ServiceInfo(i)
    local n = select("#", GetTrainerServiceInfo(i))
    local r = { GetTrainerServiceInfo(i) }
    local name, stype, sub, icon = r[1], nil, nil, nil
    for k = 2, n do
        local v = r[k]
        if type(v) == "string" and not issecret(v) and SERVICE_TYPES[v] then
            stype = stype or v
        elseif type(v) == "string" and not issecret(v) and v ~= "" then
            sub = sub or v
        elseif type(v) == "number" then
            icon = icon or v
        end
    end
    return name, stype, sub, icon
end

-- aeltere gespeicherte Eintraege (vor dem Fix): Status stand in "rank", die Symbol-Nummer in "category"
local function NormalizeService(s)
    if s.stype then return s end
    if SERVICE_TYPES[s.rank] then s.stype, s.rank = s.rank, nil end
    if not s.stype and SERVICE_TYPES[s.category] then s.stype = s.category end
    return s
end

local TrainerKind -- unten (braucht die Zauberbuch-Zeilen)

local function ScanTrainer()
    if scanning or not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end -- nur Klassenlehrer
    scanning = true
    -- Blizzards Filter kurz auf "alles zeigen", danach wiederherstellen
    local saved = {}
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
        for _, f in ipairs({ "available", "unavailable", "used" }) do
            saved[f] = GetTrainerServiceTypeFilter(f)
            pcall(SetTrainerServiceTypeFilter, f, 1)
        end
    end
    local list = {}
    for i = 1, (GetNumTrainerServices() or 0) do
        local name, stype, sub, icon = ServiceInfo(i)
        if type(name) == "string" and name ~= "" and stype ~= "header" then
            list[#list + 1] = {
                name = name, rank = sub, stype = stype,
                level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
                cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0,
                icon = (GetTrainerServiceIcon and GetTrainerServiceIcon(i)) or icon,
            }
        end
    end
    if SetTrainerServiceTypeFilter then
        -- (das Spiel meldet "aus" teils als 0 – in Lua ist 0 "wahr": darum ausdrücklich vergleichen, sonst stand der
        -- Filter nach jedem Auslesen wieder auf "alles zeigen")
        for f, v in pairs(saved) do pcall(SetTrainerServiceTypeFilter, f, (v == true or v == 1) and 1 or 0) end
    end
    scanning = false
    if #list > 0 then
        -- jeden Lehrer an seinem eigenen Platz merken. Der NPC-Name fehlt in Forever beim Besuch oft – deshalb haben
        -- Klassenlehrer und Portal-Lehrer feste Plaetze ("#class", "#portal"), weitere Lehrer je Name
        local npc = UnitName("npc")
        if type(npc) ~= "string" or issecret(npc) or npc == "" then npc = nil end
        local rec = { list = list, level = Level(), time = time(), npc = npc }
        local kind = TrainerKind(rec)
        rec.kind = kind
        local key = (kind == "class" and "#class") or (kind == "portal" and "#portal") or ("#other:" .. (npc or "?"))
        GetTrainers()[key] = rec
    end
end

-- Portale und Teleports der Magier lehrt ein eigener Portal-Lehrer: eigene Sektion
local function IsMage()
    local _, class = UnitClass("player")
    return class == "MAGE"
end
local function IsPortal(name)
    return type(name) == "string" and (name:find("^Portal") or name:find("^Teleport")) ~= nil
end

-- Art eines Lehrers aus seinem Angebot: "portal" (nur Portale/Teleports), "class" (lehrt Zauber aus dem
-- eigenen Zauberbuch, auch kuenftige Raenge) oder "other" (Tierausbilder, Waffenmeister, Reitlehrer …)
function TrainerKind(rec)
    local names = {}
    for _, line in ipairs(lines) do
        for _, e in ipairs(line.spells) do names[e.name] = true end
    end
    local portals, classHits, count = 0, 0, #(rec.list or {})
    for _, s in ipairs(rec.list or {}) do
        if IsPortal(s.name) then portals = portals + 1 end
        if names[s.name] then classHits = classHits + 1 end
    end
    if count > 0 and portals == count then return "portal" end
    if classHits > 0 then return "class" end
    return "other"
end

local function SortByLevel(list)
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
end

-- Daten fuer die Lehrer-Reiter:
--   main     = noch nicht Gelerntes vom Klassenlehrer (ohne Besuch: die "ab Stufe X"-Eintraege des Zauberbuchs)
--   groups   = je weiterer Lehrer ein eigener Reiter: Portale (Magier), Tierausbilder, Waffenmeister, Reitlehrer …
--              { key, title, label, icon, list, rec }
--   classRec = der zuletzt besuchte Klassenlehrer (fuer die Ueberschrift)
local function UpcomingList()
    local level = Level()
    local recs = {}
    for _, rec in pairs(GetTrainers()) do
        if type(rec) == "table" and type(rec.list) == "table" then
            for _, s in ipairs(rec.list) do NormalizeService(s) end
            recs[#recs + 1] = rec
        end
    end
    -- neueste Besuche zuerst; je Art (Klassenlehrer, Portale, jeder weitere Lehrer) gilt nur der neueste
    table.sort(recs, function(a, b) return (a.time or 0) > (b.time or 0) end)
    local buckets, order = {}, {}
    for _, rec in ipairs(recs) do
        local kind = rec.kind or TrainerKind(rec)
        local bucket = (kind == "class" or kind == "portal") and kind or ("other:" .. (rec.npc or "?"))
        if not buckets[bucket] then
            buckets[bucket] = { kind = kind, rec = rec }
            order[#order + 1] = bucket
        end
    end

    local mage = IsMage()
    local function Entry(s)
        return { name = s.name, sub = s.rank, icon = s.icon, level = s.level or 0, cost = s.cost or 0,
            now = (s.level or 0) <= level, trainer = true }
    end

    -- Schon gelernt? Gegen das echte Zauberbuch pruefen (der Stand beim Lehrerbesuch kann veraltet sein).
    -- Forever liefert beim Lehrer keinen Rang: Eintraege gleichen Namens sind nach Stufe die Raenge 1, 2, 3 …
    local knownRank = {}
    for _, line in ipairs(lines) do
        for _, e in ipairs(line.spells) do
            if not e.future then
                local r = e.rank or 1
                if r > (knownRank[e.name] or 0) then knownRank[e.name] = r end
            end
        end
    end
    local learnedSet = {}
    for _, rec in ipairs(recs) do
        local byName = {}
        for _, s in ipairs(rec.list) do
            if s.stype == "used" then learnedSet[s] = true end
            byName[s.name] = byName[s.name] or {}
            tinsert(byName[s.name], s)
        end
        for name, list in pairs(byName) do
            local known = knownRank[name]
            if known then
                table.sort(list, function(a, b) return (a.level or 0) < (b.level or 0) end)
                for i, s in ipairs(list) do
                    local r = RankNumber(s.rank) or i
                    if r <= known then learnedSet[s] = true end
                end
            end
        end
    end
    local function Open(s) return not learnedSet[s] end -- schon gelernt: nicht anzeigen

    local main, portal, groups = {}, {}, {}
    local classRec = buckets.class and buckets.class.rec
    if classRec then
        for _, s in ipairs(classRec.list) do
            if Open(s) then
                if mage and IsPortal(s.name) then portal[#portal + 1] = Entry(s) else main[#main + 1] = Entry(s) end
            end
        end
    else
        -- Klassenlehrer noch nie besucht: was das Zauberbuch selbst als "ab Stufe X" fuehrt
        for _, line in ipairs(lines) do
            for _, e in ipairs(line.spells) do
                if e.future and not (mage and IsPortal(e.name)) then
                    main[#main + 1] = { name = e.name, sub = e.sub, icon = e.icon, level = e.learnLevel or 0,
                        now = (e.learnLevel or 0) <= level, id = e.id }
                end
            end
        end
    end
    SortByLevel(main)

    local portalRec = buckets.portal and buckets.portal.rec
    if portalRec then
        local seen = {}
        for _, u in ipairs(portal) do seen[u.name] = true end
        for _, s in ipairs(portalRec.list) do
            if Open(s) and not seen[s.name] then seen[s.name] = true portal[#portal + 1] = Entry(s) end
        end
    end
    if portalRec or #portal > 0 then
        SortByLevel(portal)
        groups[#groups + 1] = { key = "trainer:portal", title = T("Portale und Teleports", "Portals and teleports"),
            label = T("Portale", "Portals"), icon = 135744, list = portal, rec = portalRec }
    end
    for _, bucket in ipairs(order) do
        local b = buckets[bucket]
        if b.kind == "other" then
            local list = {}
            for _, s in ipairs(b.rec.list) do if Open(s) then list[#list + 1] = Entry(s) end end
            SortByLevel(list)
            local name = b.rec.npc or T("Weiterer Lehrer", "Other trainer")
            groups[#groups + 1] = { key = "trainer:" .. bucket, title = string.format(T("Lehrer: %s", "Trainer: %s"), name),
                label = name, icon = (b.rec.list[1] and b.rec.list[1].icon) or 136243, list = list, rec = b.rec }
        end
    end
    return main, groups, classRec
end
---------------------------------------------------------------------------
-- WhatsTraining (falls installiert): dessen Daten ueber die offizielle Schnittstelle WT_API
---------------------------------------------------------------------------
local function WTInstalled() return type(_G.WT_API) == "table" end
local function WTData()
    local api = _G.WT_API
    if not (WTInstalled() and api.IsReady and api.GetSpells) then return nil end
    local okReady, ready = pcall(api.IsReady)
    if not (okReady and ready) then return nil end
    local ok, spells = pcall(api.GetSpells)
    if not ok or type(spells) ~= "table" then return nil end
    local S = api.Status or {}
    local groups = { now = {}, nextLevel = {}, later = {}, missing = {} }
    for _, s in ipairs(spells) do
        local st = s.status
        local bucket = ((st == S.AVAILABLE or st == S.WEAPON_AVAILABLE) and groups.now)
            or ((st == S.NEXTLEVEL or st == S.WEAPON_NEXTLEVEL) and groups.nextLevel)
            or ((st == S.NOTLEVEL or st == S.WEAPON_NOTLEVEL) and groups.later)
            or ((st == S.MISSINGREQS or st == S.MISSINGTALENT) and groups.missing)
        if bucket and s.name then
            bucket[#bucket + 1] = { name = s.name, sub = s.subText, icon = s.icon, level = s.level or 0, cost = s.cost or 0,
                link = s.link, id = type(s.id) == "number" and s.id or nil, trainer = true, wt = true,
                now = bucket == groups.now }
        end
    end
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            if a.level ~= b.level then return a.level < b.level end
            return a.name < b.name
        end)
    end
    return groups
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local W, H = 600, 470
local frame = UI.Window("ForeverSpellbookFrame", T("Zauberbuch", "Spellbook"), W, H)
local view = 1          -- Reiter-Nummer, "upcoming" = Beim Lehrer
local query = ""
local Refresh, ApplyBinding, SpellbookKeys, UpdateMicro -- weiter unten

-- Suche
local search = UI.EditBox(frame, 200, 22)
search:SetPoint("TOPLEFT", 154, -34)
local searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", 8, 0)
searchHint:SetText(T("Zauber suchen …", "Search spells …"))
search:SetScript("OnTextChanged", function(self)
    query = strtrim(self:GetText() or ""):lower()
    searchHint:SetShown(query == "" and not self:HasFocus())
    if Refresh then Refresh() end
end)
search:HookScript("OnEditFocusGained", function() searchHint:Hide() end)
search:HookScript("OnEditFocusLost", function() searchHint:SetShown(query == "") end)
search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

-- Optionen (kleines Menue)
local optBtn = UI.Button(frame, T("Optionen", "Options"), 90)
optBtn:SetPoint("TOPRIGHT", -12, -34)
if UI.AddArrow then UI.AddArrow(optBtn) end

-- Reiter links
local tabs = {}
local tabHolder = CreateFrame("Frame", nil, frame)
tabHolder:SetPoint("TOPLEFT", 10, -64)
tabHolder:SetPoint("BOTTOMLEFT", 10, 46) -- waechst mit der Fensterhoehe
tabHolder:SetWidth(134)

local function TabButton(i)
    local b = tabs[i]
    if b then return b end
    b = UI.Button(tabHolder, "", 134)
    b:SetHeight(24)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local fs = b:GetFontString()
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", -6, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    tabs[i] = b
    return b
end

-- Inhalt: zwei Spalten mit Bildlauf
local listBox = UI.Box(frame, 0.35)
listBox:SetPoint("TOPLEFT", 152, -64)
listBox:SetPoint("BOTTOMRIGHT", -10, 46)
local okScroll, scroll = pcall(CreateFrame, "ScrollFrame", nil, listBox, "UIPanelScrollFrameTemplate")
if not okScroll then scroll = CreateFrame("ScrollFrame", nil, listBox, "ScrollFrameTemplate") end
scroll:SetPoint("TOPLEFT", 6, -6)
scroll:SetPoint("BOTTOMRIGHT", -26, 6)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(400, 10)
scroll:SetScrollChild(content)

local ENTRY_W, ENTRY_H = 200, 40 -- Mindestbreite eines Eintrags; breiteres Fenster = mehr Spalten
local entries = {}
local sectionLabels = {}

local function EntryTooltip(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if e.link and GameTooltip.SetHyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, e.link) then
        -- Tooltip ueber den Link (WhatsTraining)
    elseif e.slot and GameTooltip.SetSpellBookItem then
        GameTooltip:SetSpellBookItem(e.slot, e.bank)
    elseif e.id and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(e.id)
    else
        GameTooltip:AddLine(e.name)
        if e.sub and e.sub ~= "" then GameTooltip:AddLine(e.sub, 0.7, 0.7, 0.7) end
    end
    if e.outdated then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(T("In deinen Leisten liegt noch Rang %d.", "Your bars still have rank %d."), e.outdated), 1, 0.4, 0.3)
    end
    if e.trainer then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(T("Beim Lehrer ab Stufe %d · %s", "At the trainer from level %d · %s"), e.level, Money(e.cost)), 1, 0.82, 0)
    end
    if not e.trainer and not e.future and not e.passive then
        GameTooltip:AddLine(T("Klick oder Ziehen: in die Leiste legen · Umschalt-Klick: Link", "Click or drag: put on a bar · Shift-click: link"), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function Entry(i)
    local b = entries[i]
    if b then return b end
    b = CreateFrame("Button", nil, content)
    b:SetSize(ENTRY_W, ENTRY_H)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetSize(36, 36)
    b.border:SetPoint("LEFT", 2, 0)
    b.border:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b.border, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b.border, "BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.warn = b:CreateTexture(nil, "OVERLAY")
    b.warn:SetSize(14, 14)
    b.warn:SetPoint("TOPRIGHT", b.border, "TOPRIGHT", 3, 3)
    b.warn:SetTexture("Interface\\Buttons\\UI-MicroStream-Yellow")
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("TOPLEFT", b.border, "TOPRIGHT", 8, -3)
    b.name:SetPoint("RIGHT", -4, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.sub:SetPoint("RIGHT", -4, 0)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetWordWrap(false)
    b:SetScript("OnEnter", EntryTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    local function Pick(self)
        local e = self.entry
        if not e or e.trainer or e.future or e.passive then return end
        PickupEntry(e)
    end
    b:SetScript("OnDragStart", Pick)
    b:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") and e.id and C_Spell and C_Spell.GetSpellLink then
            local link = C_Spell.GetSpellLink(e.id)
            if link then
                if ChatEdit_InsertLink then ChatEdit_InsertLink(link)
                elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link) end
            end
            return
        end
        Pick(self)
    end)
    entries[i] = b
    return b
end

local function Section(i)
    local fs = sectionLabels[i]
    if fs then return fs end
    fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetJustifyH("LEFT")
    sectionLabels[i] = fs
    return fs
end

-- Hinweisleiste unten: veraltete Raenge
local warnBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
warnBar:SetPoint("BOTTOMLEFT", 152, 10)
warnBar:SetPoint("BOTTOMRIGHT", -22, 10) -- Platz fuer den Groessen-Griff in der Ecke
warnBar:SetHeight(28)
UI.SetFlat(warnBar, UI.COLOR and UI.COLOR.panel or { 0.1, 0.1, 0.12, 0.95 })
warnBar.text = warnBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
warnBar.text:SetPoint("LEFT", 10, 0)
warnBar.text:SetPoint("RIGHT", -110, 0)
warnBar.text:SetJustifyH("LEFT")
warnBar.text:SetWordWrap(false)
local replaceBtn = UI.Button(warnBar, T("Ersetzen", "Replace"), 92, function()
    ReplaceOutdated()
    C_Timer.After(0.3, function() if Refresh then Refresh() end end)
end)
replaceBtn:SetPoint("RIGHT", -4, 0)
warnBar:SetScript("OnEnter", function(self)
    if not self.list or #self.list == 0 then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(T("Niedrigere Ränge in deinen Leisten", "Lower ranks on your bars"))
    for _, o in ipairs(self.list) do
        GameTooltip:AddDoubleLine(o.best.name, string.format(T("Rang %d » %d", "Rank %d » %d"), o.rank, o.best.rank), 1, 1, 1, 1, 0.82, 0)
    end
    GameTooltip:Show()
end)
warnBar:SetScript("OnLeave", GameTooltip_Hide)

-- Ansicht neu aufbauen
local outdatedBySpell = {}
function Refresh()
    if not frame:IsShown() then return end
    Collect()
    local d = GetDB()

    -- veraltete Raenge
    local outdated = d.warnOutdated and OutdatedSlots() or {}
    wipe(outdatedBySpell)
    for _, o in ipairs(outdated) do
        outdatedBySpell[o.best.name] = math.min(outdatedBySpell[o.best.name] or 99, o.rank)
    end
    warnBar.list = outdated
    if #outdated > 0 then
        warnBar.text:SetText("|cffffd100" .. string.format(T("%d Zauber in deinen Leisten haben einen niedrigeren Rang", "%d spells on your bars have a lower rank"), #outdated) .. "|r")
        replaceBtn:Show()
    else
        warnBar.text:SetText(T("Alle Zauber in deinen Leisten haben den höchsten Rang.", "All spells on your bars have the highest rank."))
        replaceBtn:Hide()
    end
    warnBar:SetShown(d.warnOutdated and true or false)

    -- Reiter
    local upcoming, trainerGroups, tr = UpcomingList()
    local nowCount, nowCost = 0, 0
    for _, u in ipairs(upcoming) do
        if u.now then nowCount = nowCount + 1 nowCost = nowCost + (u.cost or 0) end
    end
    local function Badge(n) return n > 0 and (" |cff33ff33(" .. n .. ")|r") or "" end
    local tabList = {}
    for i, line in ipairs(lines) do tabList[#tabList + 1] = { key = i, label = line.name, icon = line.icon } end
    tabList[#tabList + 1] = { key = "upcoming", label = T("Beim Lehrer", "Trainer") .. Badge(nowCount), icon = 136243, gap = true }
    -- je weiterer Lehrer ein eigener Reiter (Portale, Tierausbilder, Waffenmeister …)
    local groupByKey = {}
    for _, g in ipairs(trainerGroups) do
        local c = 0
        for _, u in ipairs(g.list) do if u.now then c = c + 1 end end
        groupByKey[g.key] = g
        tabList[#tabList + 1] = { key = g.key, label = g.label .. Badge(c), icon = g.icon, gap = true }
    end
    local wtGroups = WTData()
    if WTInstalled() then
        local c = wtGroups and #wtGroups.now or 0
        tabList[#tabList + 1] = { key = "wt", label = "What's Training" .. (c > 0 and (" |cff33ff33(" .. c .. ")|r") or ""), icon = 134939, gap = true }
    end
    -- Verweis ganz unten: öffnet Blizzards Makro-Fenster (kein eigener Inhalt, der Reiter bleibt, wie er ist)
    tabList[#tabList + 1] = { key = "macros", label = T("Makros", "Macros"), icon = "Interface\\Icons\\INV_Misc_Note_01",
        gap = true, link = function()
            if ShowMacroFrame then
                ShowMacroFrame()
            else
                if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_MacroUI") end
                if _G.MacroFrame then ShowUIPanel(_G.MacroFrame) end
            end
        end }
    if view ~= "upcoming" and view ~= "wt" and not lines[view] and not groupByKey[view] then view = 1 end
    if view == "wt" and not WTInstalled() then view = 1 end
    for _, b in ipairs(tabs) do b:Hide() end
    for i, tab in ipairs(tabList) do
        local b = TabButton(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -(i - 1) * 27 - (tab.gap and 10 or 0)) -- Lehrer-Reiter etwas abgesetzt
        b:SetText(tab.label)
        b.icon:SetTexture(tab.icon or 134400)
        b:SetEnabled(tab.link ~= nil or view ~= tab.key or query ~= "")
        b:SetScript("OnClick", function()
            if tab.link then
                if InCombatLockdown() then Chat(T("Im Kampf nicht möglich.", "Not possible in combat.")) return end
                tab.link()
                return
            end
            view = tab.key
            search:SetText("")
            search:ClearFocus()
            Refresh()
        end)
        b:Show()
    end

    -- Inhalt: so viele Spalten, wie in die aktuelle Fensterbreite passen
    for _, e in ipairs(entries) do e:Hide() e.entry = nil end
    for _, s in ipairs(sectionLabels) do s:Hide() end
    local listW = math.max(ENTRY_W, math.floor(scroll:GetWidth() or 0))
    local cols = math.max(1, math.floor((listW + 6) / (ENTRY_W + 6)))
    local entryW = math.floor((listW - (cols - 1) * 6) / cols)
    content:SetWidth(listW)
    local n, y, sec, col = 0, 0, 0, 0
    local function Place(e, label, sub, color)
        if col == cols then y = y - ENTRY_H - 2 col = 0 end
        n = n + 1
        local b = Entry(n)
        b:ClearAllPoints()
        b:SetWidth(entryW)
        b:SetPoint("TOPLEFT", col * (entryW + 6), y)
        col = col + 1
        b.entry = e
        b.icon:SetTexture(e.icon or 134400)
        b.icon:SetDesaturated(e.future or (e.trainer and not e.now) or false)
        b.name:SetText(label)
        b.sub:SetText(sub or "")
        if color then b.name:SetTextColor(color[1], color[2], color[3]) else b.name:SetTextColor(1, 1, 1) end
        b.warn:SetShown(e.outdated ~= nil)
        b:Show()
    end
    local function NewSection(text)
        if col > 0 then y = y - ENTRY_H - 2 col = 0 end -- angefangene Reihe abschliessen
        if n > 0 or sec > 0 then y = y - 8 end
        sec = sec + 1
        local fs = Section(sec)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 2, y)
        fs:SetWidth(listW - 4)
        fs:SetText(text)
        fs:Show()
        y = y - (fs:GetStringHeight() or 14) - 6
    end
    local function SpellLine(e)
        local sub = e.sub
        if e.passive then sub = (sub and sub ~= "" and (sub .. " · ") or "") .. T("Passiv", "Passive") end
        if e.future then sub = e.learnLevel and string.format(T("ab Stufe %d", "from level %d"), e.learnLevel) or T("noch nicht gelernt", "not learned yet") end
        e.outdated = outdatedBySpell[e.name]
        if e.outdated then sub = (sub or "") .. "  |cffff6644" .. T("Leiste veraltet", "bar outdated") .. "|r" end
        Place(e, e.name, sub, e.future and { 0.6, 0.6, 0.6 } or nil)
    end

    if query ~= "" then
        -- Suche ueber alle Abschnitte
        for _, line in ipairs(lines) do
            local hits = {}
            for _, e in ipairs(VisibleSpells(line.spells)) do
                if e.name:lower():find(query, 1, true) then hits[#hits + 1] = e end
            end
            if #hits > 0 then
                NewSection(line.name)
                for _, e in ipairs(hits) do SpellLine(e) end
            end
        end
        if n == 0 and sec == 0 then
            NewSection(T("Nichts gefunden.", "Nothing found."))
        end
    elseif view == "upcoming" then
        if tr then
            NewSection(string.format(T("Klassenlehrer – zuletzt besucht auf Stufe %d", "Class trainer – last visited at level %d"), tr.level or 0))
        elseif #upcoming > 0 then
            NewSection(T("Noch nicht gelernt (laut Zauberbuch)", "Not learned yet (from the spellbook)"))
        else
            NewSection(T("Besuche einmal deinen Klassenlehrer – dann steht hier, was noch kommt.", "Visit your class trainer once – then this shows what's coming."))
        end
        if nowCount > 0 then
            NewSection(string.format(T("Jetzt lernbar: %d · zusammen %s", "Learnable now: %d · total %s"), nowCount, Money(nowCost)))
            for _, u in ipairs(upcoming) do
                if u.now then Place(u, u.name, (u.sub and u.sub ~= "" and (u.sub .. " · ") or "") .. Money(u.cost), { 0.4, 1, 0.4 }) end
            end
        end
        local lastLevel
        for _, u in ipairs(upcoming) do
            if not u.now then
                if u.level ~= lastLevel then
                    lastLevel = u.level
                    NewSection(string.format(T("Stufe %d", "Level %d"), u.level))
                end
                local cost = u.trainer and Money(u.cost) or nil
                Place(u, u.name, (u.sub and u.sub ~= "" and u.sub or "") .. (cost and ("  ·  " .. cost) or ""), { 0.75, 0.75, 0.75 })
            end
        end
    elseif groupByKey[view] then
        -- weiterer Lehrer (eigener Reiter): Portale und Teleports, Tierausbilder, Waffenmeister …
        local g = groupByKey[view]
        if g.rec then
            NewSection(string.format(T("%s – zuletzt besucht auf Stufe %d", "%s – last visited at level %d"), g.title, g.rec.level or 0))
        else
            NewSection(g.title)
        end
        local nowN, nowSum = 0, 0
        for _, u in ipairs(g.list) do if u.now then nowN = nowN + 1 nowSum = nowSum + (u.cost or 0) end end
        if nowN > 0 then
            NewSection(string.format(T("Jetzt lernbar: %d · zusammen %s", "Learnable now: %d · total %s"), nowN, Money(nowSum)))
            for _, u in ipairs(g.list) do
                if u.now then Place(u, u.name, (u.sub and u.sub ~= "" and (u.sub .. " · ") or "") .. Money(u.cost), { 0.4, 1, 0.4 }) end
            end
        end
        local lastLevel
        for _, u in ipairs(g.list) do
            if not u.now then
                if u.level ~= lastLevel then
                    lastLevel = u.level
                    NewSection(string.format(T("Stufe %d", "Level %d"), u.level))
                end
                Place(u, u.name, (u.sub and u.sub ~= "" and (u.sub .. "  ·  ") or "") .. Money(u.cost), { 0.75, 0.75, 0.75 })
            end
        end
        if #g.list == 0 then
            NewSection(T("Hier gibt es gerade nichts Neues.", "Nothing new here right now."))
        end
    elseif view == "wt" then
        local function WTLine(u, color)
            local parts = {}
            if u.sub and u.sub ~= "" then parts[#parts + 1] = u.sub end
            if (u.cost or 0) > 0 then parts[#parts + 1] = Money(u.cost) end
            parts[#parts + 1] = string.format(T("Stufe %d", "Level %d"), u.level)
            Place(u, u.name, table.concat(parts, "  ·  "), color)
        end
        if not wtGroups then
            NewSection(T("What's Training lädt noch …", "What's Training is still loading …"))
        else
            local total = 0
            for _, u in ipairs(wtGroups.now) do total = total + (u.cost or 0) end
            if #wtGroups.now > 0 then
                NewSection(string.format(T("Jetzt lernbar: %d · zusammen %s", "Learnable now: %d · total %s"), #wtGroups.now, Money(total)))
                for _, u in ipairs(wtGroups.now) do WTLine(u, { 0.4, 1, 0.4 }) end
            end
            if #wtGroups.nextLevel > 0 then
                NewSection(T("Nächste Stufe", "Next level"))
                for _, u in ipairs(wtGroups.nextLevel) do WTLine(u, { 1, 0.82, 0 }) end
            end
            local lastLevel
            for _, u in ipairs(wtGroups.later) do
                if u.level ~= lastLevel then
                    lastLevel = u.level
                    NewSection(string.format(T("Stufe %d", "Level %d"), u.level))
                end
                WTLine(u, { 0.75, 0.75, 0.75 })
            end
            if #wtGroups.missing > 0 then
                NewSection(T("Voraussetzung fehlt (Talent oder früherer Rang)", "Missing requirement (talent or earlier rank)"))
                for _, u in ipairs(wtGroups.missing) do WTLine(u, { 0.55, 0.55, 0.55 }) end
            end
            if sec == 0 then NewSection(T("Laut What's Training gibt es gerade nichts Neues.", "According to What's Training there is nothing new right now.")) end
        end
    else
        local line = lines[view]
        if line then
            for _, e in ipairs(VisibleSpells(line.spells)) do SpellLine(e) end
        end
    end
    content:SetHeight(math.max(10, -y + (col > 0 and ENTRY_H or 0) + 4))
end

-- Fenstergroesse mit der Maus (Griff unten rechts): Inhalt ordnet sich beim Ziehen neu an.
-- Rechtsklick auf den Griff = Standardgroesse. Gespeichert im ForeverHub (ForeverHubDB.windows).
if UI.MakeResizable then
    UI.MakeResizable(frame, { mode = "size", minW = 520, minH = 380, maxW = 1400, maxH = 1000 })
end
local resizeQueued = false
frame:HookScript("OnSizeChanged", function()
    if resizeQueued then return end
    resizeQueued = true
    C_Timer.After(0.05, function()
        resizeQueued = false
        Refresh()
    end)
end)

-- Optionen: kleines Feld am Knopf (mit Regler fuer die Durchsichtigkeit)
local optPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
UI.Hud(optPanel, 0.97)
optPanel:SetSize(300, 214)
optPanel:SetPoint("TOPRIGHT", optBtn, "BOTTOMRIGHT", 0, -4)
optPanel:SetFrameLevel(frame:GetFrameLevel() + 30)
optPanel:EnableMouse(true)
optPanel:Hide()
local optControls = {}
local function OptCheck(y, label, key, after)
    local cb = UI.Check(optPanel, 10, y, label, function(checked)
        GetDB()[key] = checked
        if after then after() end
        Refresh()
    end)
    optControls[#optControls + 1] = function() cb:SetChecked(GetDB()[key] and true or false) end
end
OptCheck(-8, T("Alle Ränge zeigen", "Show all ranks"), "allRanks")
OptCheck(-32, T("Hinweis auf niedrigere Ränge in den Leisten", "Note lower ranks on your bars"), "warnOutdated")
OptCheck(-56, T("Blizzard-Zauberbuch ersetzen (Taste, Mini-Menü)", "Replace Blizzard spellbook (key, micro menu)"), "replaceBlizzard", function()
    if ApplyBinding then ApplyBinding() end
    if UpdateMicro then UpdateMicro() end
end)
OptCheck(-88, T("Beim Bewegen durchsichtig", "Transparent while moving"), "fadeMoving")
OptCheck(-112, T("Im Kampf durchsichtig", "Transparent in combat"), "fadeCombat")
local alphaSlider = UI.Slider(optPanel, 16, -144, T("Sichtbarkeit dann", "Visibility then"), 10, 100, 5, function(v)
    GetDB().fadeAlpha = v
end, { width = 170, unit = " %" })
optControls[#optControls + 1] = function() alphaSlider:Load(GetDB().fadeAlpha) end
optPanel:SetScript("OnShow", function() for _, load in ipairs(optControls) do load() end end)
optBtn:SetScript("OnClick", function() optPanel:SetShown(not optPanel:IsShown()) end)
frame:HookScript("OnHide", function() optPanel:Hide() end)

-- Durchsichtig beim Bewegen und/oder im Kampf (Maus ueber dem Fenster = voll sichtbar).
-- Bewegung kommt aus Blizzards Ereignissen statt aus GetUnitSpeed: die Geschwindigkeit ist im Kampf ein
-- gesperrter Wert ("secret"), den man nicht vergleichen darf.
local playerMoving = false
local moveEvents = CreateFrame("Frame")
moveEvents:RegisterEvent("PLAYER_STARTED_MOVING")
moveEvents:RegisterEvent("PLAYER_STOPPED_MOVING")
moveEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
moveEvents:SetScript("OnEvent", function(_, event)
    playerMoving = event == "PLAYER_STARTED_MOVING"
end)

local fadeElapsed = 0
frame:HookScript("OnUpdate", function(self, elapsed)
    fadeElapsed = fadeElapsed + elapsed
    if fadeElapsed < 0.05 then return end
    local step = fadeElapsed * 4
    fadeElapsed = 0
    local d = GetDB()
    local moving = d.fadeMoving and playerMoving
    local fighting = d.fadeCombat and InCombatLockdown()
    local target = ((moving or fighting) and not self:IsMouseOver()) and ((d.fadeAlpha or 45) / 100) or 1
    local a = self:GetAlpha()
    if math.abs(a - target) <= step then
        self:SetAlpha(target)
    else
        self:SetAlpha(a + (target > a and step or -step))
    end
end)
frame:HookScript("OnShow", function()
    frame:SetAlpha(1)
    search:SetText("")
    Refresh()
end)
frame:HookScript("OnHide", function() if UI.HideMenu then UI.HideMenu() end end)

local function Toggle()
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Taste des Blizzard-Zauberbuchs uebernehmen (Override-Bindung, nur ausserhalb des Kampfs)
---------------------------------------------------------------------------
local toggleBtn = CreateFrame("Button", "ForeverSpellbookToggle", UIParent)
toggleBtn:SetScript("OnClick", Toggle)
local bindOwner = CreateFrame("Frame")
-- alle Tastenbelegungen, die Blizzards Zauberbuch oeffnen (der Name der Belegung unterscheidet sich je Client)
function SpellbookKeys()
    local out = {}
    if not (GetNumBindings and GetBinding) then return out end
    for i = 1, GetNumBindings() do
        local command, _, key1, key2 = GetBinding(i)
        if type(command) == "string" and command:upper():find("SPELLBOOK") then
            if key1 then out[#out + 1] = { key = key1, command = command } end
            if key2 then out[#out + 1] = { key = key2, command = command } end
        end
    end
    return out
end

local bindPending, lastBindSig = false, nil
function ApplyBinding()
    if InCombatLockdown() then bindPending = true return end
    bindPending = false
    local keys = {}
    if GetDB().replaceBlizzard then
        for _, k in ipairs(SpellbookKeys()) do keys[#keys + 1] = k.key end
    end
    local sig = table.concat(keys, ",")
    if sig == lastBindSig then return end
    lastBindSig = sig
    ClearOverrideBindings(bindOwner)
    for _, key in ipairs(keys) do SetOverrideBindingClick(bindOwner, false, key, "ForeverSpellbookToggle") end
end

-- Zauberbuch-Knopf im Mini-Menue: ein eigener, unsichtbarer Knopf liegt darueber und oeffnet
-- dieses Fenster. Blizzards Knopf selbst wird nicht veraendert (kein "taint").
-- Welcher Knopf? Der eigene Zauberbuch-Knopf – oder Retails kombinierter Knopf, aber nur, wenn es
-- zusaetzlich einen eigenen Talente-Knopf gibt (sonst waeren die Talente nicht mehr erreichbar).
local function MicroButtons()
    if _G.SpellbookMicroButton then return { "SpellbookMicroButton" } end
    if _G.PlayerSpellsMicroButton and _G.TalentMicroButton then return { "PlayerSpellsMicroButton" } end
    return {}
end
local microOverlays = {}
function UpdateMicro()
    for _, name in ipairs(MicroButtons()) do
        local mb = _G[name]
        if mb then
            local o = microOverlays[name]
            if not o then
                o = CreateFrame("Button", nil, UIParent)
                o:SetAllPoints(mb)
                o:RegisterForClicks("AnyUp")
                o:SetScript("OnClick", function() frame:SetShown(not frame:IsShown()) end)
                local hl = o:CreateTexture(nil, "HIGHLIGHT")
                hl:SetTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
                hl:SetBlendMode("ADD")
                hl:SetAllPoints()
                o:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(T("Zauberbuch", "Spellbook"))
                    GameTooltip:AddLine("ForeverSpellbook", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                o:SetScript("OnLeave", GameTooltip_Hide)
                mb:HookScript("OnShow", UpdateMicro)
                mb:HookScript("OnHide", UpdateMicro)
                microOverlays[name] = o
            end
            o:SetFrameStrata(mb:GetFrameStrata())
            o:SetFrameLevel(mb:GetFrameLevel() + 10)
            o:SetShown(GetDB().replaceBlizzard and mb:IsVisible() and true or false)
        end
    end
end

---------------------------------------------------------------------------
-- Hinweis, wenn ein neuer Rang gelernt wurde, die Leiste aber noch den alten hat
---------------------------------------------------------------------------
local notified = {}
local function CheckNewRanks()
    if not GetDB().warnOutdated or InCombatLockdown() then return end
    Collect()
    for _, o in ipairs(OutdatedSlots()) do
        local key = o.best.name .. ":" .. o.best.rank
        if not notified[key] then
            notified[key] = true
            Chat(string.format(T("%s Rang %d gelernt – in deiner Leiste liegt noch Rang %d. Im Zauberbuch: \"Ersetzen\".",
                "%s rank %d learned – your bar still has rank %d. In the spellbook: \"Replace\"."), o.best.name, o.best.rank, o.rank))
        end
    end
end

---------------------------------------------------------------------------
-- Minimap-Knopf und Befehle
---------------------------------------------------------------------------
local mm = UI.MinimapButton({
    name = "ForeverSpellbookMinimapButton",
    icon = "Interface\\AddOns\\ForeverSpellbook\\Media\\ForeverSpellbook",
    title = "ForeverSpellbook",
    angle = function() return GetDB().minimapAngle end,
    setAngle = function(a) GetDB().minimapAngle = a end,
    onClick = function() Toggle() end,
    lines = function() return { T("Klick: Zauberbuch öffnen/schließen", "Click: open/close spellbook") } end,
})

SLASH_FOREVERSPELLBOOK1 = "/fsb"
SLASH_FOREVERSPELLBOOK2 = "/fspellbook"
SLASH_FOREVERSPELLBOOK3 = "/foreverspellbook"
SlashCmdList["FOREVERSPELLBOOK"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "replace" or msg == "ersetzen" then
        ReplaceOutdated()
    elseif msg == "status" then
        local parts = {}
        for _, k in ipairs(SpellbookKeys()) do
            local now = GetBindingAction and GetBindingAction(k.key, true) or "?"
            parts[#parts + 1] = k.key .. " (" .. k.command .. " » " .. tostring(now) .. ")"
        end
        Chat("Tasten: " .. (#parts > 0 and table.concat(parts, ", ") or "keine gefunden"))
        local mbs = {}
        for _, name in ipairs({ "SpellbookMicroButton", "PlayerSpellsMicroButton", "TalentMicroButton" }) do
            if _G[name] then mbs[#mbs + 1] = name .. (microOverlays[name] and microOverlays[name]:IsShown() and " (ersetzt)" or "") end
        end
        Chat("Mini-Menü: " .. (#mbs > 0 and table.concat(mbs, ", ") or "-") .. " · WhatsTraining: " .. tostring(_G.WT_API ~= nil))
    else
        Toggle()
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB", "ACTIONBAR_SLOT_CHANGED", "TRAINER_SHOW",
    "TRAINER_UPDATE", "PLAYER_LEVEL_UP" }) do
    pcall(events.RegisterEvent, events, e)
end
local pending = false
local function Soon(fn)
    if pending then return end
    pending = true
    C_Timer.After(0.4, function()
        pending = false
        local ok, err = pcall(fn)
        if not ok then
            local handler = geterrorhandler and geterrorhandler()
            if handler then pcall(handler, err) end
        end
    end)
end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        mm.UpdatePosition()
        ApplyBinding()
        UpdateMicro()
        C_Timer.After(2, function() if not InCombatLockdown() then ApplyBinding() end UpdateMicro() end)
        -- WhatsTraining meldet, wenn seine Daten bereit sind bzw. sich aendern
        local api = _G.WT_API
        if WTInstalled() and api.RegisterCallback and api.Event then
            local owner = {}
            for _, ev in ipairs({ api.Event.READY, api.Event.SPELLS_CHANGED, api.Event.LEVEL_CHANGED, api.Event.IGNORED_CHANGED }) do
                if ev then pcall(api.RegisterCallback, owner, ev, function() Soon(Refresh) end) end
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if bindPending then ApplyBinding() end
    elseif event == "UPDATE_BINDINGS" then
        -- eigene Override-Bindungen loesen das Ereignis ebenfalls aus: nur bei echten Aenderungen neu setzen
        if not InCombatLockdown() then C_Timer.After(0, function() if not InCombatLockdown() then ApplyBinding() end end) end
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        if not scanning then Soon(function() ScanTrainer() Refresh() end) end
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" then
        C_Timer.After(1, function() pcall(CheckNewRanks) end)
        Soon(Refresh)
    else
        Soon(Refresh)
    end
end)

-- Schnittstelle für andere Forever-Addons (UI.API, Hub v49): z. B. ForeverSkin bietet im Lehrerfenster an, nach dem
-- Lernen die Leisten auf den neuen Rang zu bringen
if UI.API then
    UI.API.ForeverSpellbook = {
        OutdatedCount = function()
            local ok, list = pcall(OutdatedSlots)
            return ok and #list or 0
        end,
        ReplaceOutdated = ReplaceOutdated,
        Toggle = function() Toggle() end, -- Zauberbuch öffnen/schließen (z. B. Knopf im Lehrerfenster)
    }
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zuruecksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = "ForeverSpellbook", sv = "ForeverSpellbookDB", defaults = DEFAULTS, version = 1 })
