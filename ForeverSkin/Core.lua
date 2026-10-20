-- ForeverSkin – Core.lua: Bausteine, um Blizzard-Fenster im Forever-Stil zu zeigen, und die Einstellungsseite.
-- Grundsatz (wie beim Spielmenü in ForeverCore): Blizzards Fenster, Knöpfe und Funktionen bleiben dieselben. Wir
-- machen nur Blizzards Grafiken unsichtbar (SetAlpha 0) und legen eigene flache Grafiken als zusätzliche Ebenen
-- (Texturen) darunter. Es wird nichts in Blizzards Tabellen geschrieben und nichts verschoben – darum gibt es auch
-- keine Blockier-Fehler, und Ausschalten = Addon aus (oder Haken in den Einstellungen) + /reload.
local ADDON_NAME, ns = ...
local UI = ForeverHub.UI
local T = UI.T
local C = UI.COLOR
ns.UI, ns.T, ns.C = UI, T, C

ns.DEFAULTS = {
    gossip = true,   -- NPC-Gespräch
    quest = true,    -- Quest-Dialog (Annehmen, Fortschritt, Abgeben)
    merchant = true, -- Händler
}

function ns.GetDB()
    if type(_G.ForeverSkinDB) ~= "table" then _G.ForeverSkinDB = {} end
    local db = _G.ForeverSkinDB
    for k, v in pairs(ns.DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

function ns.Safe(where, fn) return UI.Safe("ForeverSkin", where, fn) end

---------------------------------------------------------------------------
-- Bausteine
---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"
local looks = setmetatable({}, { __mode = "k" })  -- [Blizzard-Rahmen] = unsere Texturen (fill, edges)
local hovers = setmetatable({}, { __mode = "k" }) -- [Blizzard-Knopf] = Aussehen, das beim Überfahren gold wird

function ns.Hide(obj)
    if obj and obj.SetAlpha then obj:SetAlpha(0) end
end

-- alle Texturen eines Rahmens unsichtbar (nur die eigenen Ebenen, nicht die der Kinder); keep = Texturen, die bleiben
function ns.HideTextures(frame, keep)
    if not frame or not frame.GetRegions then return end
    local own = looks[frame]
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not (keep and keep[r]) and not (own and own.mine[r]) then r:SetAlpha(0) end
    end
end

-- flache Fläche mit feinem Rand als Texturen IM Rahmen (Ebene BACKGROUND/BORDER, also unter Blizzards Texten)
function ns.Flat(frame, fill, inset)
    if not frame or not frame.CreateTexture then return end
    local look = looks[frame]
    if not look then
        look = { mine = {} }
        look.fill = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        look.fill:SetTexture(WHITE)
        look.mine[look.fill] = true
        look.edges = {}
        for i = 1, 4 do
            local e = frame:CreateTexture(nil, "BORDER", nil, -8)
            e:SetTexture(WHITE)
            look.edges[i] = e
            look.mine[e] = true
        end
        looks[frame] = look
    end
    -- inset: Zahl (rundum nach innen) oder { links, oben, rechts, unten } (negativ = über den Rahmen hinaus)
    inset = inset or 0
    local l, t, r, b = inset, inset, inset, inset
    if type(inset) == "table" then l, t, r, b = inset[1], inset[2], inset[3], inset[4] end
    local f, e = look.fill, look.edges
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", l, -t)
    f:SetPoint("BOTTOMRIGHT", -r, b)
    f:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1)
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1 },
        { "TOPLEFT", "BOTTOMLEFT", nil }, { "TOPRIGHT", "BOTTOMRIGHT", nil } }) do
        e[i]:ClearAllPoints()
        e[i]:SetPoint(p[1], f, p[1])
        e[i]:SetPoint(p[2], f, p[2])
        if p[3] then e[i]:SetHeight(1) else e[i]:SetWidth(1) end
    end
    ns.EdgeColor(frame, C.border)
    return look
end

function ns.EdgeColor(frame, c, a)
    local look = looks[frame]
    if not look then return end
    for _, e in ipairs(look.edges) do e:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end
end

-- Fenster: dunkle Fläche, Titelleiste mit goldener Linie (wie alle Forever-Fenster); Blizzards Rahmen,
-- Hintergrund, Porträt und Titel-Grafik unsichtbar, der Titeltext bleibt
function ns.SkinWindow(frame)
    if not frame then return end
    ns.HideTextures(frame)
    for _, key in ipairs({ "NineSlice", "Bg", "Background", "PortraitContainer", "TopTileStreaks", "TitleBg",
        "Portrait", "portrait" }) do
        local obj = frame[key]
        if type(obj) == "table" then ns.Hide(obj) end
    end
    local name = frame:GetName()
    if name then
        for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TitleBg", "Bg", "BgTop" }) do ns.Hide(_G[name .. suffix]) end
    end
    if frame.TitleContainer then ns.HideTextures(frame.TitleContainer) end
    local look = ns.Flat(frame, C.background)
    if look and not look.head then
        look.head = frame:CreateTexture(nil, "BORDER", nil, -7)
        look.head:SetTexture(WHITE)
        look.head:SetVertexColor(C.header[1], C.header[2], C.header[3], 1)
        look.head:SetPoint("TOPLEFT", 1, -1)
        look.head:SetPoint("TOPRIGHT", -1, -1)
        look.head:SetHeight(23)
        look.line = frame:CreateTexture(nil, "BORDER", nil, -6)
        look.line:SetTexture(WHITE)
        look.line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
        look.line:SetPoint("TOPLEFT", look.head, "BOTTOMLEFT")
        look.line:SetPoint("TOPRIGHT", look.head, "BOTTOMRIGHT")
        look.line:SetHeight(1)
        look.mine[look.head], look.mine[look.line] = true, true
    end
    local inset = frame.Inset or (name and _G[name .. "Inset"])
    if inset then ns.SkinInset(inset) end
    -- weitere Innenflächen mit Blizzard-Rahmen (z. B. oben beim Händler) unsichtbar – sonst doppelte Kästen
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= inset and type(child.NineSlice) == "table" and not child:IsObjectType("Button") then
            ns.Hide(child.NineSlice)
            ns.HideTextures(child)
        end
    end
    ns.SkinClose(frame.CloseButton or (name and _G[name .. "CloseButton"]))
end

-- Gliederung wie bei Blizzard, aber flach: abgesetzter Kasten für den Inhalt (wie die Abschnitts-Kästen der
-- Menüs) und unten eine dunklere Leiste mit feiner goldener Linie für die Knöpfe. footer = Höhe der unteren Leiste.
function ns.ContentBox(frame, footer, top, noBox)
    local look = looks[frame]
    if not look or look.box then return end
    top = top or 32
    -- Blizzards Innenfläche (Inset) nicht zusätzlich zeigen – sonst liegen zwei Kästen übereinander
    local name = frame:GetName()
    local inset = frame.Inset or (name and _G[name .. "Inset"])
    local insetLook = inset and looks[inset]
    if insetLook then
        insetLook.fill:SetAlpha(0)
        for _, e in ipairs(insetLook.edges) do e:SetAlpha(0) end
    end
    local function Tex(layer, sub, c, a)
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(WHITE)
        t:SetVertexColor(c[1], c[2], c[3], a or 1)
        look.mine[t] = true
        return t
    end
    -- untere Leiste
    local foot = Tex("BACKGROUND", -7, C.header)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(footer)
    local footLine = Tex("BORDER", -6, C.accent, 0.35)
    footLine:SetPoint("BOTTOMLEFT", foot, "TOPLEFT")
    footLine:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    footLine:SetHeight(1)
    look.box = true
    if noBox then return end -- nur die untere Leiste (z. B. Händler: dort haben die Gegenstände eigene Kästen)
    -- Inhalt
    local box = Tex("BACKGROUND", -6, C.panel, C.panel[4])
    box:SetPoint("TOPLEFT", 8, -top)
    box:SetPoint("BOTTOMRIGHT", -8, footer + 8)
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1 },
        { "TOPLEFT", "BOTTOMLEFT", nil }, { "TOPRIGHT", "BOTTOMRIGHT", nil } }) do
        local e = Tex("BORDER", -5, C.border)
        e:SetPoint(p[1], box, p[1])
        e:SetPoint(p[2], box, p[2])
        if p[3] then e:SetHeight(1) else e:SetWidth(1) end
    end
    look.box = box
end

-- Porträt des NPCs klein und eckig mit goldenem Rand links in der Titelleiste (wie das Logo der Forever-Fenster)
function ns.Portrait(frame, unit)
    local look = looks[frame]
    if not look then return end
    if not look.portrait then
        local edge = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        edge:SetTexture(WHITE)
        edge:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
        edge:SetSize(21, 21)
        edge:SetPoint("TOPLEFT", 6, -2)
        local p = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        p:SetPoint("TOPLEFT", edge, "TOPLEFT", 1, -1)
        p:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
        p:SetTexCoord(0.12, 0.88, 0.12, 0.88) -- rundes Bild eckig zuschneiden
        look.portrait, look.portraitEdge = p, edge
        look.mine[p], look.mine[edge] = true, true
    end
    local shown = UnitExists(unit) and SetPortraitTexture ~= nil
    if shown then SetPortraitTexture(look.portrait, unit) end
    look.portrait:SetShown(shown)
    look.portraitEdge:SetShown(shown)
end

-- Textbereich unter die Visitenkarte: Blizzards Textbereich (und seine Laufleiste) beginnt je nach Fenster an einer
-- anderen Höhe. Liegt er höher als top (Abstand vom oberen Fensterrand), rückt er um den Unterschied nach unten.
-- Nur die oberen Ankerpunkte werden versetzt, ausgehend von Blizzards ursprünglicher Lage (nie mehrfach).
-- bottom (optional): ebenso unten – endet der Bereich tiefer als bottom über dem unteren Fensterrand, rücken seine
-- unteren Ankerpunkte nach oben (z. B. Laufleiste nicht bis in die Knopfleiste).
-- Hängt der Bereich an einem anderen Bereich, der selbst versetzt wird (skip), bleibt er, wie er ist – er wandert mit.
local original = setmetatable({}, { __mode = "k" }) -- [Bereich] = { Ankerpunkte, Abstände vom Fensterrand }
function ns.Fit(frame, region, top, bottom, skip)
    if not region or not region.GetNumPoints or not frame:GetTop() or not region:GetTop() then return end
    local o = original[region]
    if not o then
        o = { points = {}, top = frame:GetTop() - region:GetTop(), bottom = region:GetBottom() - frame:GetBottom() }
        for i = 1, region:GetNumPoints() do o.points[i] = { region:GetPoint(i) } end
        original[region] = o
    end
    for _, p in ipairs(o.points) do
        if skip and p[2] == skip then return end
    end
    local down = top and math.max(0, top - o.top) or 0
    local up = bottom and math.max(0, bottom - o.bottom) or 0
    if down == 0 and up == 0 then return end
    region:ClearAllPoints()
    for _, p in ipairs(o.points) do
        local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5] or 0
        if point:find("TOP") then y = y - down elseif point:find("BOTTOM") then y = y + up end
        region:SetPoint(point, rel, relPoint, x, y)
    end
end

-- Visitenkarte des NPCs über dem Inhalt (dort, wo Blizzard sein Porträt hat): großes rundes Porträt mit goldenem
-- Ring, daneben der Name groß in Gold, darunter sein Titel ("<Metzger>") und Stufe/Art. Blizzards Titel in der
-- Titelleiste wird dafür unsichtbar, dort steht klein, was für ein Fenster es ist (label).
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
function ns.NpcCard(frame, unit, label)
    local look = looks[frame]
    if not look then return end
    if not look.card then
        local card = {}
        local function Disk(size, sub, c)
            local t = frame:CreateTexture(nil, "ARTWORK", nil, sub)
            t:SetTexture(WHITE)
            t:SetVertexColor(c[1], c[2], c[3], 1)
            t:SetSize(size, size)
            t:SetPoint("CENTER", frame, "TOPLEFT", 36, -50)
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(t)
            t:AddMaskTexture(mask)
            look.mine[t] = true
            return t
        end
        card.ring = Disk(48, 1, C.accent)        -- goldener Ring
        card.gap = Disk(45, 2, C.background)     -- feine dunkle Fuge
        card.portrait = Disk(43, 3, { 1, 1, 1 }) -- Bild
        card.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        card.name:SetPoint("TOPLEFT", frame, "TOPLEFT", 68, -32)
        card.name:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
        card.name:SetJustifyH("LEFT")
        card.name:SetWordWrap(false)
        card.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
        card.sub:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
        card.sub:SetJustifyH("LEFT")
        card.sub:SetWordWrap(false)
        card.info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.info:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -2)
        card.info:SetJustifyH("LEFT")
        card.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.label:SetPoint("TOP", frame, "TOP", 0, -5)
        look.card = card
        -- Blizzards Titel (NPC-Name) nicht doppelt
        if frame.TitleContainer then ns.Hide(frame.TitleContainer) end
        local name = frame:GetName()
        if name then ns.Hide(_G[name .. "TitleText"]) end
    end
    local card = look.card
    card.label:SetText(label or "")
    local exists = UnitExists(unit)
    if exists and SetPortraitTexture then SetPortraitTexture(card.portrait, unit) end
    card.portrait:SetTexCoord(0, 1, 0, 1)
    for _, t in ipairs({ card.ring, card.gap, card.portrait }) do t:SetShown(exists) end
    card.name:SetText(exists and UnitName(unit) or "")
    -- Titel aus dem Tooltip (zweite Zeile in spitzen Klammern), sonst leer
    local sub = ""
    if exists and C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        local lines = ok and data and data.lines
        for i = 2, math.min(4, lines and #lines or 0) do
            local text = lines[i].leftText
            if type(text) == "string" and text:find("^<.+>$") then sub = text break end
        end
    end
    card.sub:SetText(sub)
    local info = ""
    if exists then
        local level = UnitLevel(unit)
        local kind = UnitCreatureType and UnitCreatureType(unit)
        if level and level > 0 then info = (LEVEL or "Level") .. " " .. level end
        if kind and kind ~= "" then info = info ~= "" and (info .. "  ·  " .. kind) or kind end
    end
    card.info:SetText(info)
    card.info:ClearAllPoints()
    if sub ~= "" then
        card.info:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -2)
    else
        card.info:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    end
    -- ohne NPC (z. B. Quest aus einem Gegenstand): nur der Titel in der Leiste
    if not exists then card.name:SetText("") card.info:SetText("") end
end

-- Innenfläche (Inset): etwas hellere Fläche statt Blizzards Rahmen
function ns.SkinInset(inset)
    if not inset then return end
    ns.HideTextures(inset)
    if inset.NineSlice then ns.Hide(inset.NineSlice) end
    if inset.Bg then ns.Hide(inset.Bg) end
    ns.Flat(inset, C.panel)
end

-- Schließen-Kreuz: zwei feine Linien wie im Hub, beim Überfahren gold
function ns.SkinClose(button)
    if not button or looks[button] then return end
    ns.HideTextures(button)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    local look = { mine = {}, lines = {} }
    for i, angle in ipairs({ 45, -45 }) do
        local line = button:CreateTexture(nil, "OVERLAY")
        line:SetSize(12, 2)
        line:SetPoint("CENTER")
        line:SetColorTexture(1, 1, 1, 1)
        line:SetRotation(math.rad(angle))
        line:SetVertexColor(0.75, 0.75, 0.78, 1)
        look.lines[i] = line
        look.mine[line] = true
    end
    look.edges = {}
    looks[button] = look
    hovers[button] = { close = true }
end

-- Knopf mit Text (z. B. "Annehmen", "Abschied"): flach wie die Hub-Knöpfe, beim Überfahren goldener Rand
function ns.SkinButton(button)
    if not button or hovers[button] then return end
    for _, key in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        ns.Hide(button[key])
    end
    ns.HideTextures(button)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    ns.Flat(button, C.button)
    local look = looks[button]
    look.hl = button:CreateTexture(nil, "BORDER", nil, -7)
    look.hl:SetTexture(WHITE)
    look.hl:SetVertexColor(1, 1, 1, 0.06)
    look.hl:SetPoint("TOPLEFT", 1, -1)
    look.hl:SetPoint("BOTTOMRIGHT", -1, 1)
    look.hl:Hide()
    look.mine[look.hl] = true
    hovers[button] = {}
end

-- Reiter (z. B. Händler/Rückkauf): flach, der gewählte mit goldenem Rand und goldener Schrift
function ns.SkinTab(tab, isSelected)
    if not tab or hovers[tab] then return end
    ns.SkinButton(tab)
    for _, key in ipairs({ "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight",
        "RightHighlight" }) do
        ns.Hide(tab[key])
    end
    hovers[tab].selected = isSelected
end

-- Überfahren und gewählte Reiter: keine Haken an Blizzards Knöpfen – solange ein Fenster offen ist, schaut ein
-- kleiner Rahmen selbst nach, wo die Maus ist (wie im Spielmenü)
local driver = CreateFrame("Frame")
driver:Hide()
local openWindows = {}
local function UpdateHover()
    for button, info in pairs(hovers) do
        local look = looks[button]
        if look and button:IsVisible() then
            local over = button:IsMouseOver() and (not button.IsEnabled or button:IsEnabled()) and true or false
            local selected = info.selected and info.selected(button) or false
            local state = (over and 1 or 0) + (selected and 2 or 0)
            if state ~= info.state then
                info.state = state
                if info.close then
                    local c = over and C.accent or { 0.75, 0.75, 0.78 }
                    for _, l in ipairs(look.lines) do l:SetVertexColor(c[1], c[2], c[3], 1) end
                else
                    ns.EdgeColor(button, (over or selected) and C.accent or C.border, (over or selected) and 0.9 or 1)
                    if look.hl then look.hl:SetShown(over) end
                    local fs = button.GetFontString and button:GetFontString()
                    if fs and info.selected then
                        local c = selected and C.accent or { 0.9, 0.9, 0.9 }
                        fs:SetTextColor(c[1], c[2], c[3])
                    end
                end
            end
        end
    end
end
local waited = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + elapsed
    if waited < 0.05 then return end -- 20-mal je Sekunde reicht für den Maus-Rand
    waited = 0
    pcall(UpdateHover)
end)

-- Fenster melden: solange es offen ist, läuft die Prüfung
function ns.Watch(frame)
    if not frame or openWindows[frame] ~= nil then return end
    openWindows[frame] = false
    frame:HookScript("OnShow", function()
        openWindows[frame] = true
        driver:Show()
    end)
    frame:HookScript("OnHide", function()
        openWindows[frame] = false
        for _, open in pairs(openWindows) do if open then return end end
        driver:Hide()
    end)
    if frame:IsShown() then openWindows[frame] = true driver:Show() end
end

-- dunkle Farbcodes im Text aufhellen (für Pergament gedacht: z. B. dunkelblaue Quest-Namen) – auf der dunklen
-- Fläche sonst kaum lesbar
function ns.LightenCodes(text)
    if type(text) ~= "string" or not text:find("|c") then return text end
    return (text:gsub("|c(%x%x)(%x%x)(%x%x)(%x%x)", function(a, r, g, b)
        local R, G, B = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
        if R + G + B >= 300 then return nil end
        -- gleiche Farbrichtung, aber hell
        local m = math.max(R, G, B, 1)
        local function L(v) return math.floor(150 + 105 * v / m) end
        return string.format("|c%s%02x%02x%02x", a, L(R), L(G), L(B))
    end))
end

---------------------------------------------------------------------------
-- Einstellungsseite und Befehl
---------------------------------------------------------------------------
local options
local checks = {}
local function Build()
    options = UI.SettingsPanel("ForeverSkinOptions", T("ForeverSkin – Einstellungen (Prototyp)", "ForeverSkin – Settings (prototype)"),
        460, 300, { key = "ForeverSkin", group = UI.SETTINGS_GROUPS.comfort, label = T("Fenster-Stil", "Window style") })
    local W = 420
    UI.Header(options, 18, -40, T("Fenster im Forever-Stil", "Windows in the Forever look"), W)
    local reload
    local function Check(y, label, key)
        local cb = UI.Check(options, 14, y, label, ns.Safe(T("Einstellungen", "Settings"), function(checked)
            ns.GetDB()[key] = checked
            reload:Show()
        end))
        checks[#checks + 1] = { cb = cb, key = key }
    end
    Check(-62, T("NPC-Gespräch", "NPC dialog"), "gossip")
    Check(-86, T("Quest-Dialog (Annehmen, Fortschritt, Abgeben)", "Quest dialog (accept, progress, turn in)"), "quest")
    Check(-110, T("Händler", "Vendor"), "merchant")
    UI.Hint(options, 22, -138, W - 12, T("Änderungen gelten nach dem Neuladen. Gefällt dir der Stil nicht, schalte " ..
        "ForeverSkin in der Addon-Liste aus – dann ist alles wieder wie vorher.",
        "Changes apply after reloading. If you don't like the look, turn ForeverSkin off in the addon list – " ..
        "everything is back as before."))
    reload = UI.Button(options, T("Neu laden", "Reload"), 120, function() ReloadUI() end)
    reload:SetPoint("BOTTOMLEFT", 14, 14)
    reload:Hide()
    options:HookScript("OnShow", function()
        local db = ns.GetDB()
        for _, c in ipairs(checks) do c.cb:SetChecked(db[c.key] and true or false) end
    end)
end

function ns.ToggleOptions()
    if not options then Build() end
    options:SetShown(not options:IsShown())
end

if UI.RegisterSettingsLink then
    UI.RegisterSettingsLink({ key = "ForeverSkin", group = UI.SETTINGS_GROUPS.comfort, label = T("Fenster-Stil", "Window style"),
        open = function() ns.ToggleOptions() end })
end

SLASH_FOREVERSKIN1 = "/fskin"
SlashCmdList["FOREVERSKIN"] = ns.Safe(T("Befehl", "Command"), function() ns.ToggleOptions() end)
