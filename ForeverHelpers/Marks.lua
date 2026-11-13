-- ForeverMarks (Prototyp, Modul von ForeverHelpers): Markierungs-Rad wie das Blizzard-Ping-Rad.
-- Taste HALTEN (Standard ALT-X, ändern: /fmarks key ALT-Y) = Rad erscheint an der Maus. Mit der Maus in Richtung eines
-- Symbols zeigen (Symbol wird groß), Taste LOSLASSEN = auswählen. Loslassen in der Mitte = abbrechen.
--   Innen:  die 8 Markierungen. Steht die Maus beim Öffnen über einer Einheit -> Markierung auf diese Einheit,
--           sonst -> Bodenmarkierung an der Mausposition (automatisch, ohne Umschalten). Gleiche noch einmal = entfernen.
--   Außen:  die 4 Blizzard-Pings (Angreifen, Achtung, Unterwegs, Hilfe) – über /ping.
-- Da die Auswahl nur die RICHTUNG braucht, genügt ein kleiner Mausschwenk – die Bodenmarkierung liegt dann fast
-- genau dort, wo das Rad geöffnet wurde. Das Rad fängt keine Mausklicks: die Maus bleibt über der Spielwelt.
-- Prototyp-Grenze: nur außerhalb des Kampfs (die Aktion ist ein geschützter Knopf, dessen Einstellung im Kampf gesperrt ist).
-- Reihenfolge und Zuordnung Ziel-/Bodenmarkierung wie die unsichtbaren Markierungs-Knöpfe in ForeverBars.
local UI = ForeverHub.UI
local T = UI.T
local function Chat(text) UI.Chat("ForeverMarks", text) end
local issecret = issecretvalue or function() return false end -- gesperrte Werte dürfen nicht verglichen werden

local MARKERS = { -- im Uhrzeigersinn ab oben: raid = Zielmarkierung 1–8, world = Bodenmarkierung
    { raid = 8, world = 8 }, { raid = 7, world = 4 }, { raid = 6, world = 1 }, { raid = 5, world = 7 },
    { raid = 4, world = 2 }, { raid = 3, world = 3 }, { raid = 2, world = 6 }, { raid = 1, world = 5 },
}
-- Blizzards Pings (im Uhrzeigersinn ab oben). cmd als Zahl (Enum.PingSubjectType): "/ping attack" versteht nur der
-- englische Client, sonst kommt der Standard-Ping „Herschauen“. Zahlen gehen in jeder Sprache (so macht es auch OPie).
local PINGS = {
    { cmd = "1",  atlas = "Ping_Wheel_Icon_Attack",  icon = "Interface\\Icons\\Ability_Warrior_Charge",
      de = "Angreifen", en = "Attack" },
    { cmd = "2", atlas = "Ping_Wheel_Icon_Warning", icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
      de = "Achtung", en = "Warning" },
    { cmd = "3", atlas = "Ping_Wheel_Icon_OnMyWay", icon = "Interface\\Icons\\Ability_Rogue_Sprint",
      de = "Unterwegs", en = "On my way" },
    { cmd = "4",  atlas = "Ping_Wheel_Icon_Assist",  icon = "Interface\\Icons\\Ability_Warrior_RallyingCry",
      de = "Hilfe", en = "Assist" },
}
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MARK_R, MARK_SIZE, MARK_BIG = 58, 40, 56 -- Ring der Markierungen: Radius, Größe, Größe wenn gewählt
local PING_R, PING_SIZE, PING_BIG = 124, 38, 52
local DEAD, SPLIT = 10, 92 -- unter DEAD = Mitte (Abbruch); ab SPLIT = Pings
local GOLD = { 1, 0.82, 0 }

local function DB()
    if type(_G.ForeverHelpersDB) ~= "table" then _G.ForeverHelpersDB = {} end
    local db = _G.ForeverHelpersDB
    if type(db.marks) ~= "table" then db.marks = {} end
    return db.marks
end

---------------------------------------------------------------------------
-- Rad (nur Anzeige, ohne Maus)
---------------------------------------------------------------------------
local wheel = CreateFrame("Frame", "ForeverMarksWheel", UIParent)
wheel:SetSize(2 * (PING_R + PING_BIG), 2 * (PING_R + PING_BIG))
wheel:SetFrameStrata("HIGH")
wheel:EnableMouse(false)
wheel:Hide()
tinsert(UISpecialFrames, "ForeverMarksWheel") -- Esc schließt

local originX, originY = 0, 0 -- Mausposition beim Öffnen (UI-Einheiten)
local groundMode = true
local unitToken
local hover -- { kind = "mark"|"ping", index = n } oder nil

-- zarter runder Hintergrund hinter den Symbolen (kein Rahmen)
local disc = wheel:CreateTexture(nil, "BACKGROUND")
disc:SetSize(2 * (MARK_R + MARK_SIZE / 2 + 8), 2 * (MARK_R + MARK_SIZE / 2 + 8))
disc:SetPoint("CENTER")
disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
disc:SetVertexColor(0, 0, 0, 0.22)

local dot = wheel:CreateTexture(nil, "ARTWORK")
dot:SetSize(6, 6)
dot:SetPoint("CENTER")
dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
dot:SetVertexColor(1, 1, 1, 0.7)

local pointer = wheel:CreateTexture(nil, "ARTWORK")
pointer:SetTexture(WHITE)
pointer:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
pointer:Hide()

local label = wheel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetPoint("TOP", wheel, "CENTER", 0, -(PING_R + PING_BIG / 2 + 8))
label:SetShadowOffset(1, -1)

local function Angle(i, n) return math.rad(90 - (i - 1) * (360 / n)) end

-- Symbole: nur Texturen
local marks, pings = {}, {}
for i, m in ipairs(MARKERS) do
    local t = wheel:CreateTexture(nil, "ARTWORK")
    t:SetTexture(ICON .. m.raid)
    t:SetSize(MARK_SIZE, MARK_SIZE)
    local a = Angle(i, 8)
    t:SetPoint("CENTER", wheel, "CENTER", MARK_R * math.cos(a), MARK_R * math.sin(a))
    t:SetAlpha(0.8)
    t.angle, t.marker = a, m
    -- kleiner goldener Punkt darunter = diese Markierung steht gerade (auf dem Ziel bzw. am Boden)
    t.mark = wheel:CreateTexture(nil, "OVERLAY")
    t.mark:SetSize(6, 6)
    t.mark:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    t.mark:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    t.mark:SetPoint("TOP", t, "BOTTOM", 0, -1)
    t.mark:Hide()
    marks[i] = t
end
for i, p in ipairs(PINGS) do
    local t = wheel:CreateTexture(nil, "ARTWORK")
    local info = p.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(p.atlas)
    if info then t:SetAtlas(p.atlas) else
        t:SetTexture(p.icon)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    t:SetSize(PING_SIZE, PING_SIZE)
    local a = Angle(i, 4)
    t:SetPoint("CENTER", wheel, "CENTER", PING_R * math.cos(a), PING_R * math.sin(a))
    t:SetAlpha(0.7)
    t.angle, t.ping = a, p
    pings[i] = t
end

---------------------------------------------------------------------------
-- Auswahl aus der Mausrichtung
---------------------------------------------------------------------------
local function CursorOffset()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s - originX, y / s - originY
end

-- liefert kind ("mark"/"ping"/nil) und Index
local function Select(dx, dy)
    local d = math.sqrt(dx * dx + dy * dy)
    if d < DEAD then return nil end
    local deg = (90 - math.deg(math.atan2(dy, dx))) % 360 -- 0 = oben, im Uhrzeigersinn
    if d >= SPLIT then return "ping", math.floor((deg + 45) / 90) % 4 + 1 end
    return "mark", math.floor((deg + 22.5) / 45) % 8 + 1
end

local function Marker(kind, index)
    if kind == "mark" then return marks[index] elseif kind == "ping" then return pings[index] end
end

local function SetHover(kind, index)
    if hover and hover.kind == kind and hover.index == index then return end
    -- alte Auswahl zurück
    if hover then
        local old = Marker(hover.kind, hover.index)
        if old then
            old:SetSize(hover.kind == "mark" and MARK_SIZE or PING_SIZE, hover.kind == "mark" and MARK_SIZE or PING_SIZE)
            old:SetAlpha(hover.kind == "mark" and 0.8 or 0.7)
        end
    end
    hover = kind and { kind = kind, index = index } or nil
    local cur = kind and Marker(kind, index)
    if cur then
        local big = kind == "mark" and MARK_BIG or PING_BIG
        cur:SetSize(big, big)
        cur:SetAlpha(1)
        -- Zeiger vom Rand der Mitte bis kurz vor das Symbol
        local a = cur.angle
        local r = kind == "mark" and MARK_R or PING_R
        local from, to = DEAD + 2, r - big / 2 - 2
        local len = math.max(to - from, 4)
        pointer:ClearAllPoints()
        pointer:SetSize(len, 3)
        pointer:SetPoint("CENTER", wheel, "CENTER", (from + len / 2) * math.cos(a), (from + len / 2) * math.sin(a))
        pointer:SetRotation(a)
        pointer:Show()
        if kind == "mark" then
            local name = _G["RAID_TARGET_" .. cur.marker.raid] or ("#" .. cur.marker.raid)
            label:SetText(name .. "\n|cffaaaaaa" .. (groundMode and T("Boden", "Ground") or (UnitName(unitToken) or T("Ziel", "Unit"))) .. "|r")
        else
            label:SetText(T(cur.ping.de, cur.ping.en) .. "\n|cffaaaaaaPing|r")
        end
    else
        pointer:Hide()
        label:SetText("")
    end
end

local function RefreshActive()
    for _, t in ipairs(marks) do
        local on = false
        if groundMode then
            if IsRaidMarkerActive then
                local ok, v = pcall(IsRaidMarkerActive, t.marker.world)
                on = ok and not issecret(v) and v and true or false
            end
        elseif unitToken then
            local ok, idx = pcall(GetRaidTargetIndex, unitToken)
            on = ok and not issecret(idx) and idx == t.marker.raid
        end
        t.mark:SetShown(on)
    end
end

---------------------------------------------------------------------------
-- Einheit unter der Maus beim Öffnen finden (Token zu GUID)
---------------------------------------------------------------------------
local function Guid(token)
    local ok, g = pcall(UnitGUID, token)
    if ok and g and not issecret(g) then return g end
end

-- Token einer Einheit, die auch NACH dem Öffnen noch gilt (mouseover ändert sich, sobald die Maus weiterwandert).
-- Erst über die GUID; bei Spielern hält das Spiel die GUID oft geheim (gegnerische Spieler wurden darum nicht
-- gefunden, 2026-11-13) – dann über UnitIsUnit("mouseover", token), soweit dessen Antwort lesbar ist.
local function TokenFor(guid)
    local list = { "target", "focus", "player", "pet", "targettarget" }
    for i = 1, 4 do list[#list + 1] = "party" .. i; list[#list + 1] = "party" .. i .. "target" end
    for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
    if guid then
        for _, t in ipairs(list) do
            if Guid(t) == guid then return t end
        end
    end
    for _, t in ipairs(list) do
        local ok, same = pcall(UnitIsUnit, "mouseover", t)
        if ok and not issecret(same) and same then return t end
    end
end

local function Open()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    originX, originY = x / s, y / s
    -- automatisch: Einheit unter der Maus -> Ziel-Markierung, sonst Boden
    unitToken = nil
    local ok, exists = pcall(UnitExists, "mouseover")
    if ok and not issecret(exists) and exists then unitToken = TokenFor(Guid("mouseover")) end
    groundMode = unitToken == nil
    wheel:ClearAllPoints()
    wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", originX, originY)
    SetHover(nil)
    RefreshActive()
    label:SetText("")
    wheel:Show()
end

wheel:SetScript("OnUpdate", function()
    local kind, index = Select(CursorOffset())
    SetHover(kind, index)
end)

---------------------------------------------------------------------------
-- Auslöser: geschützter Knopf an der Taste. Beim Drücken (down) Rad öffnen, beim Loslassen (up) einstellen, was er tut.
---------------------------------------------------------------------------
local catcher = CreateFrame("Button", "ForeverMarksCatcher", UIParent, "SecureActionButtonTemplate")
catcher:RegisterForClicks("AnyUp", "AnyDown")
catcher:SetAttribute("useOnKeyDown", false) -- ausführen beim Loslassen, nicht beim Drücken

local function Configure(kind, index)
    if InCombatLockdown() then return end
    if kind == "mark" then
        local m = MARKERS[index]
        if groundMode then
            -- Über das Makro "/wm [@cursor] N" statt type "worldmarker": Letzteres schaltet nur den Zielkreis ein und
            -- wartet auf einen Mausklick – beim Rad (Taste loslassen = wählen) passierte dann scheinbar nichts.
            -- [@cursor] setzt sofort an die Mausposition; liegt die Markierung schon, nimmt "/cwm N" sie wieder weg.
            local active = false
            if IsRaidMarkerActive then
                local ok, v = pcall(IsRaidMarkerActive, m.world)
                active = ok and not issecret(v) and v and true or false
            end
            catcher:SetAttribute("type", "macro")
            catcher:SetAttribute("macrotext", active and ("/cwm " .. m.world) or ("/wm [@cursor] " .. m.world))
        else
            catcher:SetAttribute("type", "raidtarget")
            catcher:SetAttribute("unit", unitToken)
            catcher:SetAttribute("marker", m.raid)
        end
        catcher:SetAttribute("action", "toggle")
    elseif kind == "ping" then
        catcher:SetAttribute("type", "macro")
        catcher:SetAttribute("macrotext", "/ping " .. PINGS[index].cmd)
    else
        catcher:SetAttribute("type", nil)
    end
end

catcher:SetScript("PreClick", function(_, _, down)
    if InCombatLockdown() then
        if down then Chat(T("Im Kampf nicht möglich (Prototyp).", "Not possible in combat (prototype).")) end
        return
    end
    if down then
        Configure(nil)
        if not wheel:IsShown() then Open() end
    else
        local kind, index
        if wheel:IsShown() then kind, index = Select(CursorOffset()) end
        Configure(kind, index)
    end
end)

catcher:SetScript("PostClick", function(_, _, down)
    if not down then wheel:Hide() end
end)

-- Kampf beginnt, während das Rad offen ist: schließen
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")

local boundKey
local function ApplyKey()
    if InCombatLockdown() then return false end
    if boundKey then ClearOverrideBindings(catcher) boundKey = nil end
    local m = DB()
    if m.key == nil and not m.keyOff then m.key = "ALT-X" end -- Standardtaste, bis man etwas anderes festlegt
    if m.key and m.key ~= "" then
        if SetOverrideBindingClick(catcher, false, m.key, "ForeverMarksCatcher") ~= false then boundKey = m.key end
    end
    return true
end

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then wheel:Hide() return end
    ApplyKey()
end)

SLASH_FOREVERMARKS1 = "/fmarks"
SlashCmdList["FOREVERMARKS"] = function(msg)
    msg = strtrim(msg or "")
    local key = msg:match("^key%s+(.+)$")
    if key then
        key = key:upper()
        local m = DB()
        if key == "AUS" or key == "OFF" then m.key, m.keyOff = nil, true else m.key, m.keyOff = key, nil end
        if ApplyKey() then
            Chat(m.key and string.format(T("Taste: %s (halten = Rad, loslassen = wählen)", "Key: %s (hold = wheel, release = choose)"), m.key)
                or T("Taste entfernt.", "Key removed."))
        else
            Chat(T("Im Kampf nicht möglich – nach dem Kampf wird die Taste gesetzt.", "Not possible in combat – the key is set after combat."))
        end
    else
        Chat(string.format(T("Taste halten = Rad, loslassen = wählen. Aktuelle Taste: %s. Ändern: /fmarks key ALT-Y · /fmarks key aus",
            "Hold key = wheel, release = choose. Current key: %s. Change: /fmarks key ALT-Y · /fmarks key off"), DB().key or "–"))
    end
end
