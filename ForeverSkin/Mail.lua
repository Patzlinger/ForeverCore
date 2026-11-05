-- ForeverSkin – Mail.lua: Briefkasten im Forever-Stil.
--  * Postfenster (Posteingang / Senden) flach mit Titelleiste, Reiter flach (gewählter gold)
--  * Posteingang: jede Nachricht ein flacher Kasten, das Symbol wie ein Taschenplatz in ForeverBags (dunkle Fläche,
--    feiner Rand, Maus drauf = gold, Blizzards Seltenheitsrand bleibt); Blättern-Pfeile und Knöpfe flach
--  * Senden: Empfänger/Betreff als flache Eingabefelder, Brieftext hell auf dunkel (statt Pergament),
--    Anhänge wie Taschenplätze, "Geld schicken"/"Nachnahme" als flache Kästchen, Knöpfe flach
--  * Geöffnete Nachricht: eigenes Fenster ebenso, Brieftext hell, Anhänge wie Taschenplätze
-- Wie überall: Blizzards Grafiken nur unsichtbar, eigene darunter, nichts in Blizzards Tabellen. Geschützte
-- (für Addons gesperrte) Teile – z. B. die Geld-Eingabe – bleiben, wie Blizzard sie zeichnet.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local slots = setmetatable({}, { __mode = "k" })  -- [Platz] = { edge }
local ours = setmetatable({}, { __mode = "k" })   -- eigene Texturen/Rahmen (bleiben sichtbar)

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "mail/" .. what, err) end
end

-- Platz mit Gegenstand (Nachrichten-Symbol, Anhang): wie ein Taschenplatz in ForeverBags. Das Symbol ist hier oft
-- die "normale" Grafik des Knopfs – sie bleibt; weg sind nur Fach-Hintergrund, Gedrückt- und Hell-Grafik.
local function BagSlot(button)
    if not button or slots[button] or Forbidden(button) then return end
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    local name = button:GetName()
    local icon = button.icon or button.Icon or (name and (G(name .. "IconTexture") or G(name .. "Icon")))
    for _, get in ipairs({ "GetPushedTexture", "GetHighlightTexture" }) do
        if button[get] then ns.Hide(button[get](button)) end
    end
    for _, r in ipairs({ button:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= normal and r ~= icon and r ~= button.IconBorder and not ours[r] then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r.GetTexture and r:GetTexture()
            local s = ((type(atlas) == "string" and atlas or "") .. (type(tex) == "string" and tex or "")):lower()
            if r:GetDrawLayer() == "BACKGROUND" or s:find("slot") then r:SetAlpha(0) end
        end
    end
    -- Gibt es ein eigenes Symbol UND eine "normale" Grafik, lagen beide (zugeschnitten und eingerückt) übereinander:
    -- ein zweiter, falscher Rahmen um das Symbol (Anhänge in Briefen). Dann nur das Symbol zeigen.
    if normal and icon and normal ~= icon then ns.Hide(normal) normal = nil end
    -- Seltenheitsrand genau auf die Platzgröße
    local border = button.IconBorder
    if border and border.ClearAllPoints and not Forbidden(border) then
        border:ClearAllPoints()
        border:SetAllPoints(button)
    end
    for _, t in ipairs({ normal or false, icon or false }) do
        if t and t.SetTexCoord then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", 1, -1)
            t:SetPoint("BOTTOMRIGHT", -1, 1)
            t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    ours[bg] = true
    local edge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetFrameLevel(button:GetFrameLevel() + 2)
    edge:EnableMouse(false)
    edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    edge:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    ours[edge] = true
    slots[button] = { edge = edge }
    button:HookScript("OnEnter", function(self)
        local s = slots[self]
        if s then s.edge:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9) end
    end)
    button:HookScript("OnLeave", function(self)
        local s = slots[self]
        if s then s.edge:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end
    end)
end

-- Eingabefeld (Empfänger, Betreff …): Blizzards Rahmen weg, flache dunkle Fläche
local function SkinEdit(edit, inset, money)
    if not edit or Forbidden(edit) or slots[edit] then return end
    slots[edit] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(edit[key]) end
    local name = edit:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(G(name .. suffix)) end
    end
    -- Münz-Symbole der Geldfelder (Gold, Silber, Kupfer) bleiben sichtbar
    local keep = {}
    for _, r in ipairs({ edit:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r.GetTexture and r:GetTexture()
            local s = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
            -- (Geldfeld: auch jede kleine Grafik in Münzgröße, falls das Spiel die Münze nur als Datei-Nummer meldet)
            if s:find("coin") or s:find("money") or s:find("gold") or s:find("silver") or s:find("copper")
                or (money and (r:GetWidth() or 99) <= 20) then
                keep[r] = true
                r:SetAlpha(1)
            end
        end
    end
    ns.HideTextures(edit, keep)
    ns.Flat(edit, C.input or C.button, inset or { -4, 1, 0, 1 })
end

-- Pergament und Briefpapier-Grafiken eines Rahmens samt Unter-Rahmen weg (Knöpfe/Plätze ausgenommen)
local function HideDeep(frame, depth)
    if not frame or Forbidden(frame) or not frame.GetRegions then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ours[r] and not ns.IsMine(frame, r) then r:SetAlpha(0) end
    end
    if depth < 3 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if not child:IsObjectType("Button") and not child:IsObjectType("EditBox") and not ours[child] then
                HideDeep(child, depth + 1)
            end
        end
    end
end

-- Laufleisten in einem Rahmen suchen und gold gestalten (wie beim Lehrer)
local function SkinBars(frame, depth)
    if not frame or Forbidden(frame) then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if (type(child.Track) == "table" and (child.Track.Thumb or child.Back)) or
                (child:IsObjectType("Slider") and (child:GetName() or ""):find("ScrollBar")) then
                ns.SkinScrollBar(child)
            elseif depth < 4 then
                SkinBars(child, depth + 1)
            end
        end
    end
end

-- Brieftext hell (Blizzard färbt ihn dunkelbraun für das Pergament)
local function LightText(obj)
    if not obj or Forbidden(obj) or not obj.SetTextColor then return end
    if obj:IsObjectType("SimpleHTML") then
        for _, tag in ipairs({ "P", "H1", "H2", "H3" }) do pcall(obj.SetTextColor, obj, tag, 0.92, 0.92, 0.92) end
    else
        pcall(obj.SetTextColor, obj, 0.92, 0.92, 0.92)
    end
end

local function SkinButtons(list)
    for _, n in ipairs(list) do
        local b = G(n)
        if b and not Forbidden(b) then ns.SkinButton(b) end
    end
end

-- Element um dx/dy verschieben (alle Ankerpunkte, einmalig)
local shifted = setmetatable({}, { __mode = "k" })
local function Shift(obj, dx, dy)
    if not obj or Forbidden(obj) or shifted[obj] or not obj.GetNumPoints then return end
    shifted[obj] = true
    local points = {}
    for i = 1, obj:GetNumPoints() do
        local p, rel, rp, x, y = obj:GetPoint(i)
        points[i] = { p, rel, rp, (x or 0) + dx, (y or 0) + dy }
    end
    obj:ClearAllPoints()
    for _, pt in ipairs(points) do obj:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

-- Aufbau wie Händler und Lehrer: oben eine Visitenkarte (rundes Bild mit goldenem Ring, daneben Titel groß in Gold,
-- darunter die Anzahl der Nachrichten), darunter ab TOP die Liste in der Innenfläche, unten eine feste Leiste
-- (FOOTER hoch, feine goldene Linie) mit den Knöpfen. Blizzard hängt Teile beim Aktualisieren neu auf – darum
-- werden die Plätze immer wieder geprüft (Place).
local TOP, FOOTER = -87, 40
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAIL_ICON = "Interface\\Icons\\INV_Letter_15"
local card
local function Card(f)
    if card then return card end
    card = {}
    local function Disk(size, sub, c)
        local t = f:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetColorTexture(c[1], c[2], c[3], 1)
        t:SetSize(size, size)
        t:SetPoint("CENTER", f, "TOPLEFT", 36, -56) -- (wie die Visitenkarte von Händler und Lehrer)
        local mask = f:CreateMaskTexture()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(t)
        t:AddMaskTexture(mask)
        ours[t] = true
        return t
    end
    card.ring = Disk(48, 1, C.accent)
    card.gap = Disk(45, 2, C.background)
    card.icon = Disk(43, 3, { 1, 1, 1 })
    card.icon:SetTexture(MAIL_ICON)
    card.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.name:SetPoint("TOPLEFT", f, "TOPLEFT", 68, -37)
    card.name:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    card.name:SetJustifyH("LEFT")
    card.name:SetText(ns.T("Briefkasten", "Mailbox"))
    card.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.sub:SetJustifyH("LEFT")
    card.sub:SetTextColor(0.85, 0.85, 0.85)
    card.info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.info:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -2)
    card.info:SetJustifyH("LEFT")
    return card
end

local function UpdateCard(f)
    local c = Card(f)
    local shown, total = 0, 0
    if GetInboxNumItems then shown, total = GetInboxNumItems() end
    total = math.max(total or 0, shown or 0)
    c.sub:SetText(total == 1 and ns.T("1 Nachricht", "1 message") or string.format(ns.T("%d Nachrichten", "%d messages"), total))
    local page = G("InboxFrame") and G("InboxFrame").pageNum
    local pages = math.max(1, math.ceil(total / (INBOXITEMS_TO_DISPLAY or 7)))
    c.info:SetText(type(page) == "number" and pages > 1 and string.format(ns.T("Seite %d von %d", "Page %d of %d"), page, pages) or "")
end

-- Ankerpunkt nur neu setzen, wenn er nicht schon so ist (sonst würde das Fenster ständig neu berechnet)
local Anchor = ns.Anchor

local function Place(f)
    -- Größe wie das Gesprächsfenster (wie Händler und Lehrer) – Blizzards Postfenster ist kleiner, dann reichten
    -- die Nachrichten bis in die untere Leiste
    local gossip = G("GossipFrame")
    local w, h = gossip and gossip:GetWidth() or 384, gossip and gossip:GetHeight() or 512
    if math.abs(f:GetWidth() - w) > 0.5 then f:SetWidth(w) end
    if math.abs(f:GetHeight() - h) > 0.5 then f:SetHeight(h) end
    -- (eigener Kontostand links in der Titelleiste: ns.HeaderGold über ns.SkinWindow)
    -- Blizzards Gold-Anzeige unten beim Senden: doppelt zum Kontostand oben – unsichtbar (nur Grafik/Text, sie
    -- bleibt sonst, wie sie ist)
    for _, n in ipairs({ "SendMailMoneyFrame", "SendMailMoneyInset", "SendMailMoneyBg" }) do
        local obj = G(n)
        if obj and not Forbidden(obj) and obj:GetAlpha() > 0 then obj:SetAlpha(0) end
    end
    -- Brieftext-Feld bis kurz über die Anhänge (das Fenster ist höher als Blizzards, sonst blieb ein leerer Streifen)
    local scroll, attach = G("SendMailScrollFrame"), G("SendMailAttachment1")
    if scroll and attach and not Forbidden(scroll) and scroll:IsVisible() and scroll:GetTop() and attach:GetTop() then
        local s = attach:GetEffectiveScale() / scroll:GetEffectiveScale()
        local h = scroll:GetTop() - attach:GetTop() * s - 14
        if h > 40 and math.abs(scroll:GetHeight() - h) > 0.5 then scroll:SetHeight(h) end
    end
    local inbox = G("InboxFrame")
    local inInbox = inbox and inbox:IsShown()
    -- Visitenkarte nur im Posteingang (beim Senden stehen dort Empfänger und Betreff)
    local c = Card(f)
    for _, t in ipairs({ c.ring, c.gap, c.icon, c.name, c.sub, c.info }) do t:SetShown(inInbox and true or false) end
    if inInbox then UpdateCard(f) end
    -- Innenfläche zwischen Visitenkarte und unterer Leiste
    local inset = f.Inset or G("MailFrameInset")
    if inset and not Forbidden(inset) then
        local p1, r1, _, x1, y1 = inset:GetPoint(1)
        local p2, r2, _, x2, y2 = inset:GetPoint(2)
        if not (inset:GetNumPoints() == 2 and p1 == "TOPLEFT" and r1 == f and x1 == 6 and y1 == TOP + 4
            and p2 == "BOTTOMRIGHT" and r2 == f and x2 == -6 and y2 == FOOTER + 4) then
            inset:ClearAllPoints()
            inset:SetPoint("TOPLEFT", f, "TOPLEFT", 6, TOP + 4)
            inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, FOOTER + 4)
        end
    end
    -- erste Nachricht 7 px unter der Oberkante der Innenfläche (die übrigen hängt Blizzard darunter)
    local first = G("MailItem1")
    if first then
        local button = G("MailItem1Button") or first.Button
        -- (Abstand Zeile ↔ Symbol bleibt, wie Blizzard ihn hat: nur die Zeile wird gesetzt)
        local dx = 0
        if button and button:GetLeft() and first:GetLeft() then dx = button:GetLeft() - first:GetLeft() end
        Anchor(first, "TOPLEFT", f, "TOPLEFT", 14 - dx, TOP - 6)
    end
    -- Blätter-Pfeile: Blizzard setzt ihre Grafiken beim Blättern bzw. An-/Ausgrauen neu – immer wieder unsichtbar
    -- (unsere flache Fläche und unser Pfeil bleiben); ausgegraut etwas blasser
    for _, n in ipairs({ "InboxPrevPageButton", "InboxNextPageButton" }) do
        local b = G(n)
        if b and not Forbidden(b) then
            ns.HideTextures(b)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
                if b[get] then ns.Hide(b[get](b)) end
            end
            for _, child in ipairs({ b:GetChildren() }) do
                if not Forbidden(child) and not ours[child] then ns.HideTextures(child) end
            end
            b:SetAlpha(b:IsEnabled() and 1 or 0.45)
        end
    end
    -- untere Leiste: Knöpfe mittig in ihrer Höhe, 10 px vom Rand
    local y = FOOTER / 2
    Anchor(G("InboxPrevPageButton"), "LEFT", f, "BOTTOMLEFT", 10, y)
    Anchor(G("InboxNextPageButton"), "RIGHT", f, "BOTTOMRIGHT", -10, y)
    Anchor(G("OpenAllMail"), "CENTER", f, "BOTTOM", 0, y)
    Anchor(G("InboxFrameOpenAllButton"), "CENTER", f, "BOTTOM", 0, y)
    local send, cancel = G("SendMailMailButton"), G("SendMailCancelButton")
    Anchor(cancel, "RIGHT", f, "BOTTOMRIGHT", -10, y)
    if cancel then Anchor(send, "RIGHT", cancel, "LEFT", -8, 0) end
    -- zweiter Reiter mit Abstand neben dem ersten
    local tab1 = G("MailFrameTab1")
    if tab1 then Anchor(G("MailFrameTab2"), "LEFT", tab1, "RIGHT", 8, 0) end
end

-- grauer Balken je Nachricht mit dem Symbol darin (1 px Luft rundum, wie im Handelsfenster)
local rowBoxes = {}
local function RowBox(row, button)
    if not (row and button) or rowBoxes[row] then return end
    local parent = row:GetParent() or row
    local box = CreateFrame("Frame", nil, parent)
    box:SetFrameLevel(math.max(0, row:GetFrameLevel() - 1))
    box:SetPoint("TOP", button, "TOP", 0, 1)
    box:SetPoint("BOTTOM", button, "BOTTOM", 0, -1)
    box:SetPoint("LEFT", button, "LEFT", -1, 0)
    box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    ns.Flat(box, C.button)
    ours[box] = true
    -- dunkles Feld für das Symbol, auch ohne Nachricht (wie die Plätze im Handelsfenster); liegt unter Blizzards
    -- Symbol-Knopf, darum genau so groß wie dieser
    local well = CreateFrame("Frame", nil, box, "BackdropTemplate")
    well:SetAllPoints(button)
    well:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    well:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
    well:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    well:EnableMouse(false)
    ours[well] = true
    rowBoxes[row] = box
end

---------------------------------------------------------------------------
-- Postfenster (Posteingang und Senden)
---------------------------------------------------------------------------
local function SkinInbox()
    local inbox = G("InboxFrame")
    if inbox then HideDeep(inbox, 1) end
    for i = 1, (INBOXITEMS_TO_DISPLAY or 7) do
        local row = G("MailItem" .. i)
        if row and not Forbidden(row) then
            ns.HideTextures(row)
            local button = G("MailItem" .. i .. "Button") or row.Button
            BagSlot(button)
            RowBox(row, button)
        end
    end
    ns.SkinArrowButton(G("InboxPrevPageButton"), true)
    ns.SkinArrowButton(G("InboxNextPageButton"), false)
    SkinButtons({ "OpenAllMail", "InboxFrameOpenAllButton" })
end

local function SkinSend()
    local send = G("SendMailFrame")
    if send then HideDeep(send, 1) end
    SkinEdit(G("SendMailNameEditBox"))
    SkinEdit(G("SendMailSubjectEditBox"))
    -- Brieftext: flache Fläche hinter dem Textbereich, Schrift hell
    local scroll = G("SendMailScrollFrame")
    if scroll and not Forbidden(scroll) then
        HideDeep(scroll, 1)
        ns.Flat(scroll, C.input or C.button, { -4, -4, -4, -4 })
    end
    LightText(G("SendMailBodyEditBox"))
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do BagSlot(G("SendMailAttachment" .. i)) end
    for _, n in ipairs({ "SendMailSendMoneyButton", "SendMailCODButton" }) do
        local cb = G(n)
        if cb and not Forbidden(cb) and ns.SkinCheck then ns.SkinCheck(cb) end
    end
    -- Geld-Eingabe: nur, wenn das Spiel sie nicht sperrt
    for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
        local box = G("SendMailMoney" .. coin)
        if box and not Forbidden(box) then SkinEdit(box, { -4, 0, -2, 0 }, true) end
    end
    SkinButtons({ "SendMailMailButton", "SendMailCancelButton" })
    -- mehr Luft zwischen "Geld senden" und "Nachnahme" (die Kästchen klebten aneinander): das obere etwas hoch,
    -- das untere etwas tiefer – unten bleibt durch die tiefer gesetzten Knöpfe trotzdem Platz
    Shift(G("SendMailSendMoneyButton"), 0, 3)
    Shift(G("SendMailCODButton"), 0, -3)
    -- die ganze Geld-Zeile ("Zu sendende Menge", Geldfelder, "Geld senden"/"Nachnahme") 14 px höher: sie lag sonst
    -- auf der goldenen Linie der unteren Leiste. Nur, was nicht an einem anderen Teil dieser Zeile hängt (das
    -- wandert ohnehin mit).
    local group, members = {}, {}
    for _, n in ipairs({ "SendMailMoneyText", "SendMailMoney", "SendMailSendMoneyButton", "SendMailCODButton" }) do
        local obj = G(n)
        if obj and not Forbidden(obj) then
            group[#group + 1] = obj
            members[obj] = true
        end
    end
    for _, obj in ipairs(group) do
        local _, rel = obj:GetPoint(1)
        if not members[rel] then
            local points = {}
            for i = 1, obj:GetNumPoints() do
                local p, r, rp, x, y = obj:GetPoint(i)
                points[i] = { p, r, rp, x or 0, (y or 0) + 14 }
            end
            obj:ClearAllPoints()
            for _, pt in ipairs(points) do obj:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
        end
    end
end

local function SkinMail()
    local f = G("MailFrame")
    if not f or ns.mailSkinned then return end
    ns.mailSkinned = true
    ns.SkinWindow(f)
    for i = 1, 2 do
        local tab = G("MailFrameTab" .. i)
        if tab and not Forbidden(tab) then
            ns.SkinTab(tab, function(t)
                return PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) == t:GetID()
            end)
        end
    end
    ns.ContentBox(f, FOOTER, nil, true) -- untere Leiste mit feiner goldener Linie (wie beim Lehrer)
    Step("inbox", SkinInbox)
    Step("send", SkinSend)
    Step("bars", function() SkinBars(f, 1) end)
    Step("place", function() Place(f) end)
    ns.Watch(f)
    ns.Scaled(f) -- so groß wie Gespräch, Händler und Co.
    -- Blizzard hängt beim Blättern/Reiterwechsel teils neu auf: danach und beim Öffnen wieder an die festen Plätze
    if type(_G.InboxFrame_Update) == "function" then
        hooksecurefunc("InboxFrame_Update", function() C_Timer.After(0, function() pcall(Place, f) end) end)
    end
    f:HookScript("OnShow", function() C_Timer.After(0, function() pcall(Place, f) end) end)
    local events = CreateFrame("Frame", nil, f)
    events:RegisterEvent("MAIL_INBOX_UPDATE")
    events:SetScript("OnEvent", function() if f:IsShown() then pcall(Place, f) end end)
    -- solange offen: Brieftext hell halten (Blizzard färbt beim Wechsel neu), Reiter-Beschriftung mittig, Plätze
    -- prüfen (fünfmal je Sekunde)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited >= 0.2 then
            waited = 0
            pcall(Place, f)
        end
        pcall(LightText, G("SendMailBodyEditBox"))
        -- Balken nur bei sichtbaren Nachrichten-Zeilen
        for row, box in pairs(rowBoxes) do box:SetShown(row:IsVisible()) end
        for i = 1, 2 do
            local tab = G("MailFrameTab" .. i)
            if tab then pcall(ns.CenterText, tab) end
        end
    end)
end

---------------------------------------------------------------------------
-- Geöffnete Nachricht
---------------------------------------------------------------------------
local function SkinOpenMail()
    local f = G("OpenMailFrame")
    if not f or ns.openMailSkinned then return end
    ns.openMailSkinned = true
    ns.SkinWindow(f)
    local scroll = G("OpenMailScrollFrame")
    if scroll and not Forbidden(scroll) then
        HideDeep(scroll, 1)
        ns.Flat(scroll, C.input or C.button, { -4, -4, -4, -4 })
    end
    for _, n in ipairs({ "OpenMailBodyText", "OpenMailInvoiceItemLabel", "OpenMailArithmeticLine" }) do LightText(G(n)) end
    for i = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do BagSlot(G("OpenMailAttachmentButton" .. i)) end
    BagSlot(G("OpenMailMoneyButton"))
    BagSlot(G("OpenMailLetterButton"))
    SkinButtons({ "OpenMailReplyButton", "OpenMailDeleteButton", "OpenMailCancelButton", "OpenMailReportSpamButton" })
    Step("bars", function() SkinBars(f, 1) end)
    ns.Watch(f)
    ns.Scaled(f)
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function() pcall(LightText, G("OpenMailBodyText")) end)
end

local function Run()
    if not ns.GetDB().mail then return end
    if G("MailFrame") then Step("mail", SkinMail) end
    if G("OpenMailFrame") then Step("open", SkinOpenMail) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MAIL_SHOW")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Blizzard_MailFrame" and addon ~= "Blizzard_MailUI" then return end
    Run()
end)
