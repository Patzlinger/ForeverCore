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
local function SkinEdit(edit, inset)
    if not edit or Forbidden(edit) or slots[edit] then return end
    slots[edit] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(edit[key]) end
    local name = edit:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(G(name .. suffix)) end
    end
    ns.HideTextures(edit)
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

-- Mehr Luft unten: das Fenster wächst optisch um DOWN nach unten (eigene Fläche, die Reiter darunter rücken mit).
-- Unten eine Leiste mit feiner goldener Linie (FOOT über dem alten Fensterrand, wie beim Handel), darin feste Plätze
-- für die Knöpfe; Blizzards Innenfläche endet darüber.
local DOWN, FOOT = 14, 24
local function Grow(f)
    local look = ns.Flat(f, C.background, { 0, 0, 0, -DOWN })
    if look then
        local foot = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        foot:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
        foot:SetPoint("BOTTOMLEFT", look.fill, "BOTTOMLEFT", 1, 1)
        foot:SetPoint("BOTTOMRIGHT", look.fill, "BOTTOMRIGHT", -1, 1)
        foot:SetHeight(DOWN + FOOT)
        local line = f:CreateTexture(nil, "BORDER", nil, -6)
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
        line:SetPoint("BOTTOMLEFT", foot, "TOPLEFT")
        line:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
        line:SetHeight(1)
        ours[foot], ours[line] = true, true
    end
    -- die neue Fläche fängt die Maus ab (sonst klickt man ins Spiel durch)
    local grip = CreateFrame("Frame", nil, f)
    grip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, 0)
    grip:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, 0)
    grip:SetHeight(DOWN)
    grip:EnableMouse(true)
    ours[grip] = true
    -- Blizzards Innenfläche (Posteingang) endet über der Leiste – sie lag sonst darüber und die Linie lief
    -- durch die Knöpfe
    local inset = f.Inset or G(f:GetName() .. "Inset")
    if inset and not Forbidden(inset) then
        local points = {}
        for i = 1, inset:GetNumPoints() do
            local p, rel, rp, x, y = inset:GetPoint(i)
            -- untere Ankerpunkte: am Fenster, 6 px über der goldenen Linie der Leiste
            if type(p) == "string" and p:find("BOTTOM") then
                rel, rp, y = f, p, FOOT + 6
            end
            points[i] = { p, rel, rp, x or 0, y or 0 }
        end
        inset:ClearAllPoints()
        for _, pt in ipairs(points) do inset:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
    end
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
        if box and not Forbidden(box) then SkinEdit(box, { -4, 0, -2, 0 }) end
    end
    SkinButtons({ "SendMailMailButton", "SendMailCancelButton" })
    -- mehr Luft zwischen "Geld senden" und "Nachnahme" (die Kästchen klebten aneinander): das obere etwas hoch,
    -- das untere etwas tiefer – unten bleibt durch die tiefer gesetzten Knöpfe trotzdem Platz
    Shift(G("SendMailSendMoneyButton"), 0, 3)
    Shift(G("SendMailCODButton"), 0, -3)
end

-- Knöpfe unten in die neue Leiste (etwas tiefer), "Senden" mit Abstand neben "Abbrechen", Reiter unter das
-- gewachsene Fenster
local function PlaceBottom(f)
    -- feste Plätze in der unteren Leiste (mittig in deren Höhe): Zurück links, Weiter rechts, "Alle öffnen" mittig;
    -- beim Senden "Abbrechen" rechts, "Senden" 8 px links daneben
    local y = -DOWN + 5
    local function Put(name, point, x)
        local b = G(name)
        if not b or Forbidden(b) then return end
        b:ClearAllPoints()
        b:SetPoint(point, f, point, x, y)
    end
    Put("InboxPrevPageButton", "BOTTOMLEFT", 10)
    Put("InboxNextPageButton", "BOTTOMRIGHT", -10)
    Put("OpenAllMail", "BOTTOM", 0)
    Put("InboxFrameOpenAllButton", "BOTTOM", 0)
    Put("SendMailCancelButton", "BOTTOMRIGHT", -10)
    local send, cancel = G("SendMailMailButton"), G("SendMailCancelButton")
    if send and cancel and not Forbidden(send) and not Forbidden(cancel) then
        send:ClearAllPoints()
        send:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
    end
    Shift(G("MailFrameTab1"), 0, -DOWN - 2)
    local tab1, tab2 = G("MailFrameTab1"), G("MailFrameTab2")
    if tab1 and tab2 and not Forbidden(tab2) then
        tab2:ClearAllPoints()
        tab2:SetPoint("LEFT", tab1, "RIGHT", 8, 0)
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
    Step("grow", function() Grow(f) end)
    Step("inbox", SkinInbox)
    Step("send", SkinSend)
    Step("bottom", function() PlaceBottom(f) end)
    Step("bars", function() SkinBars(f, 1) end)
    ns.Watch(f)
    ns.Scaled(f) -- so groß wie Gespräch, Händler und Co.
    -- solange offen: Brieftext hell halten (Blizzard färbt beim Wechsel neu), Reiter-Beschriftung mittig
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function()
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
