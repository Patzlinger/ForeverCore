-- ForeverSkin – Extra.lua: Flugkarte, Beute- und Handelsfenster im Forever-Stil.
--  * Flugkarte (TaxiFrame): flaches Fenster mit Titelleiste; die Karte selbst (Flugpunkte, Routen) bleibt unverändert
--  * Beute (LootFrame): flaches Fenster, jeder Gegenstand ein flacher Knopf (Symbol und Qualitätsfarbe bleiben)
-- Wie überall: Blizzards Grafiken nur unsichtbar, eigene darunter, nichts in Blizzards Tabellen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end

---------------------------------------------------------------------------
-- Flugkarte
---------------------------------------------------------------------------
-- Karten-Texturen erkennen (bleiben sichtbar): Name oder Grafik mit "Map"/"Taxi"
local function MapTextures(frame, keep, depth)
    if not frame or not frame.GetRegions then return keep end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local name = (r:GetName() or ""):lower()
            local tex = r.GetTexture and r:GetTexture()
            local atlas = r.GetAtlas and r:GetAtlas()
            local path = (type(tex) == "string" and tex or "") .. (type(atlas) == "string" and atlas or "")
            path = path:lower()
            if name:find("map") or name:find("taxi") or path:find("taximap") or path:find("taxi") then keep[r] = true end
        end
    end
    if depth < 2 then
        for _, child in ipairs({ frame:GetChildren() }) do MapTextures(child, keep, depth + 1) end
    end
    return keep
end

local function SkinTaxi()
    local f = G("TaxiFrame")
    if not f then return end
    local keep = MapTextures(f, {}, 1)
    for _, key in ipairs({ "TaxiMap", "Map", "MapTexture" }) do
        if type(f[key]) == "table" and f[key].IsObjectType and f[key]:IsObjectType("Texture") then keep[f[key]] = true end
    end
    -- Die Karte ist eine der Grafiken des Fensters (am Namen nicht zu erkennen) – aber mit Abstand die größte. Beim
    -- ersten Öffnen (dann stimmen die Größen) bleibt darum nur die größte Grafik von Fenster und Innenfläche sichtbar,
    -- alle übrigen Rahmenteile werden unsichtbar. Flugrouten und Flugpunkte liegen auf eigenen Ebenen und bleiben.
    local inset = f.Inset or G("TaxiFrameInset")
    local cleaned = false
    local function KeepOnlyMap()
        if cleaned then return end
        local list, largest, area = {}, nil, 0
        for _, holder in ipairs({ f, inset }) do
            if holder and holder.GetRegions then
                for _, r in ipairs({ holder:GetRegions() }) do
                    if r:IsObjectType("Texture") and not ns.IsMine(holder, r) then
                        list[#list + 1] = r
                        local a = (r:GetWidth() or 0) * (r:GetHeight() or 0)
                        if a > area then largest, area = r, a end
                    end
                end
            end
        end
        if not largest or area < 10000 then return end -- Größen noch nicht bekannt: beim nächsten Öffnen
        cleaned = true
        for _, r in ipairs(list) do
            -- (auch nicht die per Name erkannten: Rahmenteile heißen ebenfalls "TaxiFrame…")
            if r ~= largest then r:SetAlpha(0) end
        end
    end
    -- nur Rahmen, Titel-Hintergrund und Porträt weg (light), dazu gezielt (laut /fskin taxi in Forever): alle
    -- Rahmenteile "UI-Frame-…" (Kanten, Ecken, Titel) und Blizzards Stein-Hintergrund (Datei 374155, größer als die
    -- Karte – darum lag "größte Grafik = Karte" falsch). Die Karte selbst (z. B. 7961420) und die Routen bleiben.
    local BACKGROUNDS = { [374155] = true }
    local function HideFrameParts()
        for _, holder in ipairs({ f, inset }) do
            if holder and holder.GetRegions then
                for _, r in ipairs({ holder:GetRegions() }) do
                    if r:IsObjectType("Texture") and not ns.IsMine(holder, r) then
                        local atlas = r.GetAtlas and r:GetAtlas()
                        local tex = r.GetTexture and r:GetTexture()
                        if (type(atlas) == "string" and atlas:find("UI%-Frame")) or BACKGROUNDS[tex]
                            or (type(tex) == "string" and tex:find("UI%-Frame")) then
                            r:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end
    ns.SkinWindow(f, keep, true)
    HideFrameParts()
    f:HookScript("OnShow", function() pcall(HideFrameParts) end)
    ns.KeepOnlyMap = KeepOnlyMap -- (alter Versuch, nicht mehr benutzt)
    ns.Watch(f)
end

---------------------------------------------------------------------------
-- Beute
---------------------------------------------------------------------------
local done = setmetatable({}, { __mode = "k" })

-- eine Beute-Zeile (Retail: Element der Liste, Classic: LootButton1-4): flacher Knopf, Symbol bleibt
local function SkinLootRow(row, name)
    if not row then return end
    local icon = row.Item or row.icon or row.Icon or (name and G(name .. "IconTexture"))
    local keep = {}
    if type(icon) == "table" and icon.IsObjectType and icon:IsObjectType("Texture") then keep[icon] = true end
    for _, key in ipairs({ "NameFrame", "QualityStripe", "HighlightNameFrame", "PushedNameFrame", "BorderFrame" }) do
        local t = row[key]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
    end
    if name then ns.Hide(G(name .. "NameFrame")) end
    if done[row] then return end
    done[row] = true
    if row:IsObjectType("Button") then
        ns.Hide(row:GetHighlightTexture())
        ns.Hide(row:GetPushedTexture())
    end
    ns.Flat(row, C.button, 1) -- (kein Aufhellen beim Überfahren – nur der Rand in Seltenheitsfarbe, siehe LootHover)
end

-- Beute-Platz einer Zeile (Retail: Element, Classic: LootButton.slot)
local function Slot(row)
    if row.GetSlotIndex then
        local ok, slot = pcall(row.GetSlotIndex, row)
        if ok and slot then return slot end
    end
    return row.slotIndex or row.slot or (row.GetID and row:GetID())
end

-- Maus über einer Zeile: Rand in der Seltenheitsfarbe des Gegenstands, sonst grau (nichts hellt auf)
local overState = setmetatable({}, { __mode = "k" }) -- (eigene Tabelle: nichts in Blizzards Zeilen schreiben)
local function LootHover(row)
    if not done[row] then return end
    local over = row:IsMouseOver() and true or false
    if over == overState[row] then return end
    overState[row] = over
    local c = C.border
    if over then
        local slot = Slot(row)
        local quality = slot and GetLootSlotInfo and select(5, GetLootSlotInfo(slot))
        if type(quality) == "number" and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            c = { r, g, b }
        else
            c = C.accent
        end
    end
    ns.EdgeColor(row, c, 1)
end

local function SkinLootRows()
    local f = G("LootFrame")
    if not f then return end
    local box = f.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(function(e) SkinLootRow(e) LootHover(e) end) end
    for i = 1, 4 do
        local b = G("LootButton" .. i)
        if b then
            SkinLootRow(b, "LootButton" .. i)
            LootHover(b)
        end
    end
end

local function SkinLoot()
    local f = G("LootFrame")
    if not f then return end
    ns.SkinWindow(f)
    for _, n in ipairs({ "LootFramePortraitOverlay", "LootFramePortrait" }) do ns.Hide(G(n)) end
    ns.SkinArrowOnly(G("LootFrameUpButton"), "up")
    ns.SkinArrowOnly(G("LootFrameDownButton"), "down")
    if f.ScrollBar then ns.SkinScrollBar(f.ScrollBar) end
    ns.Watch(f)
    -- Zeilen baut Blizzard bei jeder Beute neu: solange das Fenster offen ist, in jedem Bild prüfen
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function() pcall(SkinLootRows) end)
end

---------------------------------------------------------------------------
-- Handel
---------------------------------------------------------------------------
-- Flaches Fenster; deine und die Gegenstände des anderen in flachen Kästen. Gegenstands-Plätze: flach mit Rand in
-- Seltenheitsfarbe (Maus drauf = gold). Hat der andere (bzw. du) "Handeln" gedrückt, wird der Rand seines
-- Kastens grün (statt Blizzards grünem Leuchten). Geld-Eingabe und Knöpfe flach.
local GREEN = { 0.30, 0.85, 0.30 }
local slotState = setmetatable({}, { __mode = "k" }) -- [Platz] = zuletzt gesetzte Randfarbe (als Text)

local function SkinTradeSlot(button)
    if not button or slotState[button] ~= nil then return end
    local icon = button.icon or button.Icon or (button:GetName() and _G[button:GetName() .. "IconTexture"])
    local keep = {}
    if icon then keep[icon] = true end
    ns.HideTextures(button, keep)
    if button.IconBorder then ns.Hide(button.IconBorder) end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    if icon and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    ns.Flat(button, C.button)
    slotState[button] = ""
end

-- Randfarbe eines Platzes: Maus drauf = gold, sonst Seltenheit (ab "selten"), sonst grau
local function TradeSlotEdge(button, link)
    if not button or slotState[button] == nil then return end
    local c, key = C.border, "border"
    if button:IsMouseOver() then
        c, key = C.accent, "accent"
    elseif link then
        local quality = select(3, GetItemInfo(link))
        if type(quality) == "number" and quality >= 2 and GetItemQualityColor then
            local r, g, b = GetItemQualityColor(quality)
            c, key = { r, g, b }, "q" .. quality
        end
    end
    if slotState[button] == key then return end
    slotState[button] = key
    ns.EdgeColor(button, c, 1)
end

-- Blizzards Handels-Grafiken im ganzen Fenster unsichtbar (auch in Unter-Rahmen wie dem Porträt des anderen):
-- alles mit "Portrait", "TradeFrame", Platz-Hintergrund oder Namensfeld im Namen, Schlüssel oder in der Datei.
-- Münz-Symbole, Gegenstands-Symbole und unsere eigenen Flächen bleiben.
local tradeOurs = setmetatable({}, { __mode = "k" }) -- eigene Texturen (Visitenkarten), bleiben sichtbar
local ART = { "portrait", "tradeframe", "slot%-background", "questitemnameframe", "nameframe", "ui%-frame", "recipient" }
local function IsTradeArt(holder, r)
    local name = (r:GetName() or ""):lower()
    local atlas = r.GetAtlas and r:GetAtlas()
    local tex = r.GetTexture and r:GetTexture()
    local text = name .. "|" .. (type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")
    -- Schlüssel im Rahmen (z. B. holder.portrait) – nur lesen
    for k, v in pairs(holder) do
        if v == r and type(k) == "string" then text = text .. "|" .. k end
    end
    text = text:lower()
    if text:find("coin") or text:find("money") or text:find("icon") then return false end
    for _, p in ipairs(ART) do
        if text:find(p) then return true end
    end
    return false
end

-- Geschützte Blizzard-Rahmen (z. B. für Kauf-/Bezahlfunktionen) dürfen Addons nicht einmal ansehen: überspringen
local function Forbidden(obj)
    return obj and obj.IsForbidden and obj:IsForbidden()
end

local function HideTradeArt(frame, depth)
    if not frame or Forbidden(frame) or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) and not tradeOurs[r] and IsTradeArt(frame, r) then
            r:SetAlpha(0)
        end
    end
    if depth < 3 then
        for _, child in ipairs({ frame:GetChildren() }) do HideTradeArt(child, depth + 1) end
    end
end

-- Visitenkarte je Spalte wie bei den Dialogen: rundes Porträt mit goldenem Ring, daneben der Name (Klassenfarbe),
-- darunter Gilde und Stufe/Klasse. Blizzards Namen in der Titelleiste werden dafür unsichtbar.
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local cards = {}
local function TradeCard(f, column, unit)
    local card = cards[unit]
    if not card then
        card = {}
        -- Streifen zwischen Titelleiste und Geldfeld der Spalte: die Karte sitzt darin mittig (gleich viel Luft
        -- zur goldenen Linie oben wie zum Kasten unten)
        local band = CreateFrame("Frame", nil, f)
        band:SetPoint("TOP", f, "TOP", 0, -24)
        band:SetPoint("BOTTOMLEFT", column, "TOPLEFT", 0, 0)
        band:SetPoint("BOTTOMRIGHT", column, "TOPRIGHT", 0, 0)
        card.band = band
        local function Disk(size, sub, c)
            local t = f:CreateTexture(nil, "ARTWORK", nil, sub)
            t:SetTexture(WHITE)
            t:SetVertexColor(c[1], c[2], c[3], 1)
            t:SetSize(size, size)
            t:SetPoint("CENTER", band, "LEFT", 22, 0)
            local mask = f:CreateMaskTexture()
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(t)
            t:AddMaskTexture(mask)
            tradeOurs[t] = true
            return t
        end
        card.ring = Disk(40, 1, C.accent)
        card.gap = Disk(37, 2, C.background)
        card.portrait = Disk(35, 3, { 1, 1, 1 })
        card.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        card.name:SetPoint("LEFT", band, "LEFT", 48, 0)
        card.name:SetPoint("TOP", band, "CENTER", 0, 17)
        card.name:SetPoint("RIGHT", column, "RIGHT", -2, 0)
        card.name:SetJustifyH("LEFT")
        card.name:SetWordWrap(false)
        card.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
        card.sub:SetPoint("RIGHT", column, "RIGHT", -2, 0)
        card.sub:SetJustifyH("LEFT")
        card.sub:SetWordWrap(false)
        card.info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.info:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -2)
        card.info:SetPoint("RIGHT", column, "RIGHT", -2, 0)
        card.info:SetJustifyH("LEFT")
        card.info:SetWordWrap(false)
        cards[unit] = card
    end
    local exists = UnitExists(unit)
    if exists and SetPortraitTexture then SetPortraitTexture(card.portrait, unit) end
    for _, t in ipairs({ card.ring, card.gap, card.portrait }) do t:SetShown(exists) end
    local r, g, b = C.accent[1], C.accent[2], C.accent[3]
    local _, class = UnitClass(unit)
    local color = exists and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then r, g, b = color.r, color.g, color.b end
    card.name:SetText(exists and (UnitName(unit) or "") or "")
    card.name:SetTextColor(r, g, b)
    local guild = exists and GetGuildInfo and GetGuildInfo(unit)
    card.sub:SetText(guild and ("<" .. guild .. ">") or "")
    card.sub:SetTextColor(0.85, 0.85, 0.85)
    local info = ""
    if exists then
        local level = UnitLevel(unit)
        local className = UnitClass(unit)
        if level and level > 0 then info = (LEVEL or "Level") .. " " .. level end
        if className then info = info .. (info ~= "" and " " or "") .. className end
    end
    card.info:SetText(info)
    card.info:ClearAllPoints()
    card.info:SetPoint("RIGHT", column, "RIGHT", -2, 0)
    if guild then
        card.info:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -2)
    else
        card.info:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    end
end

local function UpdateTradeCards()
    for _, n in ipairs({ "TradeFramePlayerNameText", "TradeFrameRecipientNameText" }) do ns.Hide(G(n)) end
    local left, right = G("TradePlayerInputMoneyInset"), G("TradeRecipientMoneyInset")
    if left then TradeCard(G("TradeFrame"), left, "player") end
    if right then TradeCard(G("TradeFrame"), right, "NPC") end
end

-- Mehr Platz oben für die Visitenkarten: Fenster um SHIFT höher, alles, was oben am Fenster hängt, rückt um
-- SHIFT nach unten (einmalig; unten Hängendes wie die Knöpfe bleibt)
local SHIFT = 34
local function MakeRoom(f)
    local function Shift(obj)
        if obj == f.CloseButton or tradeOurs[obj] or Forbidden(obj) or not obj.GetNumPoints then return end
        local points, changed = {}, false
        for i = 1, obj:GetNumPoints() do
            local p, rel, rp, x, y = obj:GetPoint(i)
            if rel == f and type(rp) == "string" and rp:find("TOP") then
                y = (y or 0) - SHIFT
                changed = true
            end
            points[i] = { p, rel, rp, x or 0, y or 0 }
        end
        if not changed then return end
        obj:ClearAllPoints()
        for _, pt in ipairs(points) do obj:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
    end
    for _, child in ipairs({ f:GetChildren() }) do Shift(child) end
    for _, r in ipairs({ f:GetRegions() }) do
        if not ns.IsMine(f, r) and r:IsObjectType("FontString") then Shift(r) end
    end
    f:SetHeight(f:GetHeight() + SHIFT)
end

-- eigener flacher Kasten hinter einem Blizzard-Knopf (als Geschwister-Rahmen darunter – unabhängig davon, was
-- Blizzard mit den Grafiken des Knopfs macht); Maus drauf = goldener Rand
local buttonBoxes = {}
local function ButtonBox(f, b)
    local box = CreateFrame("Frame", nil, f)
    box:SetAllPoints(b)
    box:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    tradeOurs[box] = true
    ns.Flat(box, C.button)
    buttonBoxes[b] = box
end

-- Blizzards Grafiken eines Rahmens samt Unter-Rahmen unsichtbar (keep = Texturen, die bleiben)
local function HideDeep(frame, keep, depth)
    if not frame or Forbidden(frame) or not frame.GetRegions then return end
    ns.HideTextures(frame, keep)
    if depth < 2 then
        for _, child in ipairs({ frame:GetChildren() }) do HideDeep(child, keep, depth + 1) end
    end
end

-- Text-Knöpfe des Fensters (Handeln, Abbrechen …), unabhängig vom Namen
local tradeButtons = {}
local function FindTradeButtons(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if Forbidden(child) then
            -- (nicht anfassen)
        elseif child:IsObjectType("Button") then
            local label = child.GetText and child:GetText()
            if type(label) == "string" and label ~= "" and child ~= frame.CloseButton then
                tradeButtons[#tradeButtons + 1] = child
            end
        elseif depth < 2 then
            FindTradeButtons(child, depth + 1)
        end
    end
end

-- Geld-Eingabe: flache Eingabefelder wie in den Forever-Menüs, das Münz-Symbol bleibt rechts darin.
-- Im Forever-Client sind diese Felder geschützt (für Addons gesperrt) – dann greift das nicht.
local moneyBoxes, coinKeep = {}, {}
local function SkinMoneyBox(box)
    for _, r in ipairs({ box:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r.GetTexture and r:GetTexture()
            local path = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
            if path:find("coin") or path:find("money") or path:find("gold") or path:find("silver") or path:find("copper") then
                coinKeep[r] = true
            end
        end
    end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(box[key]) end
    HideDeep(box, coinKeep, 1)
    ns.Flat(box, C.input or C.button, { -4, 0, -2, 0 })
    moneyBoxes[#moneyBoxes + 1] = box
end

local function SkinTrade()
    local f = G("TradeFrame")
    if not f then return end
    local function Step(what, fn)
        local ok, err = pcall(fn)
        if not ok then
            if ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "trade/" .. what, err)
            else geterrorhandler()(err) end
        end
    end
    ns.SkinWindow(f)
    ns.ContentBox(f, 32, nil, true) -- untere Leiste mit goldener Linie für die Knöpfe
    -- eigener Titel ("Handel"); Namen und Porträts stehen als Visitenkarten über den Spalten
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -6)
    title:SetText(TRADE or ns.T("Handel", "Trade"))
    -- Knöpfe zuerst (hängen von nichts anderem ab)
    Step("buttons", function()
        FindTradeButtons(f, 1)
        for _, b in ipairs(tradeButtons) do
            ns.SkinButton(b)
            ButtonBox(f, b)
        end
    end)
    Step("room", function() MakeRoom(f) end)
    ns.Scaled(f) -- so groß wie Gespräch, Händler und Co.
    Step("art", function() HideTradeArt(f, 1) end)
    Step("cards", UpdateTradeCards)
    f:HookScript("OnShow", function()
        Step("art", function() HideTradeArt(f, 1) end)
        Step("cards", UpdateTradeCards)
    end)
    -- Kästen: deine Gegenstände, die des anderen, "wird nicht gehandelt" und die Geldfelder
    local boxes = {}
    Step("boxes", function()
        for _, n in ipairs({ "TradePlayerItemsInset", "TradeRecipientItemsInset", "TradePlayerEnchantInset",
            "TradeRecipientEnchantInset", "TradePlayerInputMoneyInset", "TradeRecipientMoneyInset" }) do
            local inset = G(n)
            if inset then
                ns.SkinInset(inset)
                boxes[n] = inset
            end
        end
    end)
    -- Blizzards grünes Leuchten nur weg, wenn es den Kasten gibt, dessen Rand stattdessen grün wird
    local highlights = {
        { "TradeHighlightPlayer", "TradePlayerItemsInset" }, { "TradeHighlightPlayerEnchant", "TradePlayerEnchantInset" },
        { "TradeHighlightRecipient", "TradeRecipientItemsInset" },
        { "TradeHighlightRecipientEnchant", "TradeRecipientEnchantInset" },
    }
    Step("highlight", function()
        for _, h in ipairs(highlights) do
            local frame = G(h[1])
            if frame and boxes[h[2]] then HideDeep(frame, nil, 1) end
        end
    end)
    -- Gegenstands-Plätze (7 je Seite; der 7. ist "wird nicht gehandelt")
    Step("slots", function()
        for i = 1, (MAX_TRADE_ITEMS or 7) do
            for _, side in ipairs({ "TradePlayerItem", "TradeRecipientItem" }) do
                local row = G(side .. i)
                if row then
                    ns.Hide(G(side .. i .. "NameFrame"))
                    ns.Hide(G(side .. i .. "SlotTexture")) -- Blizzards Platz-Hintergrund (goldener Rahmen um den Platz)
                    if row.NameFrame then ns.Hide(row.NameFrame) end
                    if row.SlotTexture then ns.Hide(row.SlotTexture) end
                    SkinTradeSlot(G(side .. i .. "ItemButton") or row.ItemButton)
                end
            end
        end
    end)
    Step("money", function()
        for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
            local box = G("TradePlayerInputMoneyFrame" .. coin)
            -- (in Forever sind die Gold-Eingabefelder geschützt – dann bleiben sie, wie Blizzard sie zeichnet)
            if box and not Forbidden(box) then SkinMoneyBox(box) end
        end
    end)
    ns.Watch(f)
    -- Solange das Fenster offen ist: Seltenheitsfarben, "hat Handeln gedrückt" (grüner Rand) – und Blizzards
    -- Knopf- und Eingabe-Grafiken erneut unsichtbar (Blizzard setzt sie bei Zustandswechseln teils neu)
    local accepted = setmetatable({}, { __mode = "k" })
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function()
        for i = 1, (MAX_TRADE_ITEMS or 7) do
            TradeSlotEdge(G("TradePlayerItem" .. i .. "ItemButton"), GetTradePlayerItemLink and GetTradePlayerItemLink(i))
            TradeSlotEdge(G("TradeRecipientItem" .. i .. "ItemButton"), GetTradeTargetItemLink and GetTradeTargetItemLink(i))
        end
        for _, h in ipairs(highlights) do
            local frame, box = G(h[1]), boxes[h[2]]
            if frame and box then
                local on = frame:IsShown() and true or false
                if accepted[box] ~= on then
                    accepted[box] = on
                    ns.EdgeColor(box, on and GREEN or C.border, 1)
                end
            end
        end
        for _, b in ipairs(tradeButtons) do
            HideDeep(b, nil, 1)
            for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(b[key]) end
            local box = buttonBoxes[b]
            if box then
                box:SetShown(b:IsShown())
                local over = b:IsMouseOver() and b:IsEnabled()
                if box.over ~= over then
                    box.over = over
                    ns.EdgeColor(box, over and C.accent or C.border, 1)
                end
            end
        end
        for _, box in ipairs(moneyBoxes) do HideDeep(box, coinKeep, 1) end
    end)
end

-- Prüfbefehl /fskin taxi: welche Grafiken hat die Flugkarte (Name, Datei/Atlas, Größe, Sichtbarkeit) – im Chat
function ns.DumpTaxi()
    local f = G("TaxiFrame")
    if not (f and f:IsShown()) then
        ns.UI.Chat("ForeverSkin", ns.T("Erst die Flugkarte öffnen, dann /fskin taxi.", "Open the flight map first, then /fskin taxi."))
        return
    end
    local n = 0
    local function Dump(holder, label, depth)
        for _, r in ipairs({ holder:GetRegions() }) do
            if r:IsObjectType("Texture") and n < 40 then
                n = n + 1
                local tex = r.GetTexture and r:GetTexture()
                local atlas = r.GetAtlas and r:GetAtlas()
                local layer = r:GetDrawLayer()
                ns.UI.Chat("ForeverSkin", string.format("%s %s | %s | %dx%d | %s | a=%.1f%s", label, r:GetName() or "-",
                    tostring(atlas or tex), r:GetWidth() or 0, r:GetHeight() or 0, tostring(layer), r:GetAlpha() or 0,
                    ns.IsMine(holder, r) and " (FS)" or ""))
            end
        end
        if depth < 2 then
            for i, child in ipairs({ holder:GetChildren() }) do
                if not child:IsObjectType("Button") then
                    Dump(child, label .. ">" .. (child:GetName() or ("#" .. i)), depth + 1)
                end
            end
        end
    end
    Dump(f, "TaxiFrame", 1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local db = ns.GetDB()
    for _, w in ipairs({ { "taxi", SkinTaxi }, { "loot", SkinLoot }, { "trade", SkinTrade } }) do
        if db[w[1]] then
            local ok, err = pcall(w[2])
            if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", w[1], err) end
        end
    end
end)
