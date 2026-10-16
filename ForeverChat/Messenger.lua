-- ForeverChat – Messenger.lua: Fluestern wie in einem Messenger.
-- Reiter "IM" in der obersten Zeile des Chats; darin je Gespraechspartner ein Unterreiter mit eigenem Verlauf
-- und eigenem Antwortfeld. Abschaltbar (dann laeuft Fluestern wie gewohnt im normalen Chat).
--
-- Sicherheit/taint:
--  * Gespraeche werden aus den Chat-Ereignissen gelesen – nur, wenn die Werte lesbar sind. Im Kampf gesperrte
--    Fluesternachrichten bleiben im normalen Chat (dort ueberspringt Blizzard auch unseren Filter).
--  * Gesendet wird ueber C_ChatInfo.SendChatMessage bzw. BNSendWhisper auf Tastendruck (Enter) – Blizzards
--    Eingabefeld, "Antworten" (/r) und dessen Absender-Merker fasst ForeverChat nicht an.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR
local WHITE = "Interface\\Buttons\\WHITE8x8"

local MAX_LINES = 150   -- Zeilen je Gespraech
local MAX_TABS = 8      -- so viele Gespraeche hoechstens als Unterreiter
local SUBTAB_H = 20

local convs = {}        -- [Schluessel] = { kind, target, bnID, name, guid, lines, unread }
local order = {}        -- Schluessel, neueste zuerst
local current           -- gewaehltes Gespraech
local panel, view, input, placeholder, emptyHint, imTab
local subTabs = {}
local hiddenChat        -- Chatfenster, das waehrend der Messenger-Ansicht unsichtbar ist
ns.imActive = false

local WHISPER_EVENTS = {
    CHAT_MSG_WHISPER = { incoming = true, kind = "W", color = "WHISPER" },
    CHAT_MSG_WHISPER_INFORM = { incoming = false, kind = "W", color = "WHISPER_INFORM" },
    CHAT_MSG_BN_WHISPER = { incoming = true, kind = "BN", color = "BN_WHISPER" },
    CHAT_MSG_BN_WHISPER_INFORM = { incoming = false, kind = "BN", color = "BN_WHISPER_INFORM" },
}
ns.WHISPER_EVENTS = WHISPER_EVENTS

---------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------
local function ShortName(name)
    if type(name) ~= "string" then return "?" end
    if Ambiguate then return Ambiguate(name, "none") end
    return name:match("^([^%-]+)") or name
end

local function ColorOf(chatType)
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]
    if info then return info.r, info.g, info.b end
    return 1, 0.5, 1
end

local function ClassName(name, guid)
    if guid and ns.CanRead(guid) and _G.GetPlayerInfoByGUID then
        local _, class = _G.GetPlayerInfoByGUID(guid)
        local color = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
        if color and color.WrapTextInColorCode then return color:WrapTextInColorCode(name) end
    end
    return "|cffffffff" .. name .. "|r"
end

local function TotalUnread()
    local n = 0
    for _, c in pairs(convs) do n = n + c.unread end
    return n
end

local function MoveToFront(key)
    for i, k in ipairs(order) do
        if k == key then table.remove(order, i) break end
    end
    table.insert(order, 1, key)
    while #order > MAX_TABS do
        convs[table.remove(order)] = nil -- aeltestes Gespraech faellt heraus
    end
end

---------------------------------------------------------------------------
-- Reiter "IM" in der Knopfleiste (Skin.lua setzt ihn links neben die Knoepfe)
---------------------------------------------------------------------------
local function UpdateIMTab()
    if not imTab then return end
    local n = TotalUnread()
    imTab:SetText(n > 0 and ("IM |cffffd100" .. n .. "|r") or "IM")
    imTab:SetWidth(math.max(34, imTab:GetFontString():GetStringWidth() + 16))
    local on = ns.imActive
    imTab:SetBackdropColor(on and C.header[1] or C.button[1], on and C.header[2] or C.button[2],
        on and C.header[3] or C.button[3], 0.95)
    if on or n > 0 then
        imTab:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], on and 0.75 or 0.45)
    else
        imTab:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end
    imTab:GetFontString():SetTextColor(on and C.accent[1] or 0.82, on and C.accent[2] or 0.82, on and C.accent[3] or 0.82)
    if ns.ApplyDockSpace then ns.ApplyDockSpace() end
end

function ns.CreateIMTab(parent)
    imTab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    imTab:SetHeight(18)
    UI.SetFlat(imTab, C.button)
    local fs = imTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    imTab:SetFontString(fs)
    local hl = imTab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.06)
    imTab:SetScript("OnClick", function() ns.ToggleIM() end)
    imTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(T("Instant Messaging", "Instant messaging"))
        GameTooltip:AddLine(T("Flüstergespräche, je Person ein eigener Reiter.", "Whisper conversations, one tab per person."), 1, 1, 1, true)
        GameTooltip:Show()
        parent:SetAlpha(1)
    end)
    imTab:SetScript("OnLeave", function() GameTooltip_Hide() parent:SetAlpha(0.55) end)
    UpdateIMTab()
    return imTab
end

---------------------------------------------------------------------------
-- Messenger-Fenster (liegt genau ueber dem Chatbereich)
---------------------------------------------------------------------------
local function Flat(frame, bg, edge)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local function ShowConversation(key)
    current = key
    local c = key and convs[key]
    view:Clear()
    if c then
        c.unread = 0
        for _, line in ipairs(c.lines) do view:AddMessage(line.text, line.r, line.g, line.b) end
        placeholder:SetText(string.format(T("Antwort an %s … (Enter sendet)", "Reply to %s … (Enter sends)"), c.name))
    end
    emptyHint:SetShown(c == nil)
    input:SetShown(c ~= nil)
    ns.UpdateIMTabs()
end

local function SubTab(i)
    if subTabs[i] then return subTabs[i] end
    local b = CreateFrame("Button", nil, panel, "BackdropTemplate")
    b:SetHeight(SUBTAB_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- Gespraech schliessen
            convs[self.key] = nil
            for k, key in ipairs(order) do if key == self.key then table.remove(order, k) break end end
            if current == self.key then current = order[1] end
            ShowConversation(current)
        else
            ShowConversation(self.key)
            input:SetFocus()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local c = convs[self.key]
        GameTooltip:AddLine(c and c.name or "")
        GameTooltip:AddLine(T("Klick: öffnen · Rechtsklick: schließen", "Click: open · Right-click: close"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    subTabs[i] = b
    return b
end

function ns.UpdateIMTabs()
    UpdateIMTab()
    if not panel then return end
    local width = panel:GetWidth()
    local x, shown = 0, 0
    for i, key in ipairs(order) do
        local c = convs[key]
        local b = SubTab(i)
        b.key = key
        b:SetText(c.unread > 0 and (c.name .. " |cffffd100" .. c.unread .. "|r") or c.name)
        local w = math.min(130, b:GetFontString():GetStringWidth() + 18)
        if x + w > width then b:Hide() else
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -2)
            b:SetWidth(w)
            local on = key == current
            Flat(b, on and { C.header[1], C.header[2], C.header[3], 0.95 } or { C.button[1], C.button[2], C.button[3], 0.85 },
                on and { C.accent[1], C.accent[2], C.accent[3], 0.75 } or C.border)
            b:GetFontString():SetTextColor(on and C.accent[1] or 0.82, on and C.accent[2] or 0.82, on and C.accent[3] or 0.82)
            b:Show()
            x = x + w + 3
            shown = shown + 1
        end
    end
    for i = #order + 1, #subTabs do subTabs[i]:Hide() end
end

local function SendText(text)
    local c = current and convs[current]
    if not c or not text or strtrim(text) == "" then return end
    local ok
    if c.kind == "BN" and c.bnID and _G.BNSendWhisper then
        ok = pcall(_G.BNSendWhisper, c.bnID, text)
    else
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
        ok = send and pcall(send, text, "WHISPER", nil, c.target)
    end
    if not ok then
        ns.Chat(T("Senden nicht möglich – bitte über den normalen Chat flüstern.", "Could not send – please whisper via the normal chat."))
    end
end

local function BuildPanel()
    if panel then return end
    local main = ns.MainChatFrame()
    local anchor = main.Background or main
    panel = CreateFrame("Frame", "ForeverChatMessenger", UIParent)
    panel:SetPoint("TOPLEFT", anchor, "TOPLEFT", 2, -2)
    panel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -2, 2)
    panel:SetFrameStrata("MEDIUM")
    panel:EnableMouse(true)
    panel:Hide()

    -- Verlauf
    view = CreateFrame("ScrollingMessageFrame", nil, panel)
    view:SetPoint("TOPLEFT", 2, -(SUBTAB_H + 6))
    view:SetPoint("BOTTOMRIGHT", -2, 30)
    local font, size, flags = main:GetFont()
    if font then view:SetFont(font, size, flags) else view:SetFontObject("ChatFontNormal") end
    view:SetJustifyH("LEFT")
    view:SetFading(false)
    view:SetMaxLines(MAX_LINES)
    view:SetHyperlinksEnabled(true)
    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        elseif delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    view:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if _G.SetItemRef then _G.SetItemRef(link, text, button, self) end
    end)

    emptyHint = UI.Hint(panel, nil, nil, 300, T("Noch keine Flüstergespräche. Sobald dir jemand flüstert (oder du jemandem), "
        .. "erscheint hier ein Reiter für die Person.",
        "No whisper conversations yet. As soon as someone whispers you (or you whisper someone), a tab for that person appears here."))
    emptyHint:SetPoint("CENTER", panel, "CENTER", 0, 0)
    emptyHint:SetJustifyH("CENTER")

    -- Antwortfeld (Forever-Stil, goldener Rand beim Tippen)
    input = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
    input:SetPoint("BOTTOMLEFT", 0, 2)
    input:SetPoint("BOTTOMRIGHT", 0, 2)
    input:SetHeight(24)
    Flat(input, { C.input[1], C.input[2], C.input[3], 0.92 }, C.border)
    input:SetFontObject("ChatFontNormal")
    input:SetTextInsets(8, 8, 0, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(255)
    placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 8, 0)
    local function UpdatePlaceholder(self) placeholder:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end
    input:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
        UpdatePlaceholder(self)
    end)
    input:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        UpdatePlaceholder(self)
    end)
    input:SetScript("OnTextChanged", UpdatePlaceholder)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function(self)
        SendText(self:GetText())
        self:SetText("")
    end)

    panel:SetScript("OnSizeChanged", function() ns.UpdateIMTabs() end)
end

---------------------------------------------------------------------------
-- Ein- und Ausblenden
---------------------------------------------------------------------------
function ns.ShowIM()
    if not ns.GetDB().messenger then return end
    BuildPanel()
    -- den gerade sichtbaren Chat unsichtbar machen (nur Alpha – Blizzard-Chat laeuft weiter)
    hiddenChat = ns.SelectedChatFrame()
    if hiddenChat then hiddenChat:SetAlpha(0) end
    ns.imActive = true
    panel:Show()
    if not current then current = order[1] end
    ShowConversation(current)
    ns.UpdateAllTabLooks()
end

function ns.HideIM()
    if not ns.imActive then return end
    ns.imActive = false
    if panel then panel:Hide() end
    if hiddenChat then hiddenChat:SetAlpha(1) end
    hiddenChat = nil
    ns.UpdateAllTabLooks()
    UpdateIMTab()
end

function ns.ToggleIM()
    if ns.imActive then ns.HideIM() else ns.ShowIM() end
end

---------------------------------------------------------------------------
-- Nachrichten einsammeln
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for event in pairs(WHISPER_EVENTS) do events:RegisterEvent(event) end
events:SetScript("OnEvent", ns.Safe(T("Messenger", "Messenger"), function(_, event, text, sender, ...)
    local db = ns.GetDB()
    if not db.messenger then return end
    if not ns.CanRead(text, sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    local info = WHISPER_EVENTS[event]
    local guid = select(10, ...)  -- arg12
    local bnID = select(11, ...)  -- arg13
    if info.kind == "BN" and not ns.CanRead(bnID) then return end

    local key = info.kind .. ":" .. (info.kind == "BN" and tostring(bnID) or sender:lower())
    local c = convs[key]
    if not c then
        c = { kind = info.kind, target = sender, bnID = bnID, name = ShortName(sender), lines = {}, unread = 0 }
        convs[key] = c
    end
    if info.incoming and guid and ns.CanRead(guid) then c.guid = guid end

    local who = info.incoming and ClassName(c.name, c.guid) or ("|cffffd100" .. T("Du", "You") .. "|r")
    local line = { text = "|cff8a8a8a" .. date("%H:%M") .. "|r " .. who .. ": " .. text }
    line.r, line.g, line.b = ColorOf(info.color)
    table.insert(c.lines, line)
    if #c.lines > MAX_LINES then table.remove(c.lines, 1) end
    MoveToFront(key)

    if ns.imActive and current == key then
        view:AddMessage(line.text, line.r, line.g, line.b)
    elseif info.incoming then
        c.unread = c.unread + 1
    end
    if not current then current = key end
    if info.incoming and not db.whispersInMain and SOUNDKIT then
        PlaySound(SOUNDKIT.TELL_MESSAGE or 3081) -- Blizzard spielt den Ton nur fuer Zeilen im Hauptchat
    end
    ns.UpdateIMTabs()
end))
