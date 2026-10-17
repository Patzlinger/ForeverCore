-- ForeverChat – Channels.lua: eigene Kanäle (Custom Channels) in einem festen Kanalfenster.
-- Direkt hinter den festen Reitern (General, Kampflog) steht ein eigener Kanal-Reiter mit dem gewählten Kanal
-- ("# Name"), dahinter der "+"-Knopf: dort wechselt man den Kanal, verlässt ihn oder springt in andere Chatfenster.
-- Das Kanalfenster ist ein normales Blizzard-Chatfenster (nur der gewählte Kanal läuft dort, oben rechts steht
-- "Kanal 5 · Name", die Eingabezeile schreibt automatisch in den Kanal). Sein Blizzard-Reiter ist unsichtbar,
-- unser Reiter ersetzt ihn: Linksklick zeigt das Fenster, Rechtsklick öffnet Blizzards normales Reiter-Menü
-- (Umbenennen, Schriftgröße, Einstellungen …) mit zusätzlich "Kanal verlassen" und "Wechseln zu …".
-- Blizzards Überlauf-Pfeil der Reiterleiste ist ausgeblendet – der "+"-Knopf listet auch alle Chatfenster.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local plus, chanTab
local SIZE_H, SIZE_W = 18, 20
local TAB_MAX_W = 120
local overflowWanted = false -- Blizzard würde gerade den Überlauf-Pfeil zeigen (nicht alle Reiter passen)
local reflowing = false

---------------------------------------------------------------------------
-- Eigene Kanäle finden
---------------------------------------------------------------------------
-- Eigener Kanal (vom Spieler erstellt/betreten)?
local function IsCustom(id, name)
    -- Die Typ-Angabe der API ist uneinheitlich, deshalb über Nummer und Namen: die ersten Nummern sind Zonenkanäle,
    -- Zonenkanäle heißen "Allgemein - Zone", "Dienste - Stadt" …, Gemeinschaftskanäle beginnen mit "Community:"
    name = tostring(name)
    return id > 4 and not name:find("^Community:") and not name:find(" %- ")
end

local function CustomChannels()
    local out = {}
    if not GetChannelList then return out end
    local list = { GetChannelList() }
    local i = 1
    while list[i] ~= nil do
        local id, name = list[i], list[i + 1]
        local step = type(list[i + 2]) == "boolean" and 3 or 2 -- (id, Name, deaktiviert) bzw. (id, Name)
        if type(id) == "number" and type(name) == "string" and IsCustom(id, name) then
            out[#out + 1] = { id = id, name = name }
        end
        i = i + step
    end
    return out
end

local function Joined(name)
    local id = name and GetChannelName and GetChannelName(name)
    if id and id > 0 then return id end
    return nil
end

---------------------------------------------------------------------------
-- Das Kanalfenster (Blizzard merkt sich Fenster, Name und Kanal selbst; wir nur, welches es ist)
---------------------------------------------------------------------------
local function DockFrames()
    local dock = _G.GENERAL_CHAT_DOCK
    local frames = dock and _G.FCFDock_GetChatFrames and _G.FCFDock_GetChatFrames(dock)
    return dock, frames or {}
end

local function TabOf(frame) return frame and _G[frame:GetName() .. "Tab"] end

-- das Kanalfenster, falls offen
local function ChannelWindow()
    local d = ns.GetDB()
    local frame = d.channelWindow and _G[d.channelWindow]
    if not frame then return nil end
    for _, f in ipairs(select(2, DockFrames())) do
        if f == frame then return frame end
    end
    return nil
end

-- Kanal des Fensters (nil = kein Kanalfenster oder Kanal nicht mehr betreten)
local function ChannelOfWindow(frame)
    if not frame or frame ~= ChannelWindow() then return nil end
    local name = ns.GetDB().channelActive
    local id = Joined(name)
    if not id then return nil end
    return { id = id, name = name }
end

local function Selected()
    local dock = _G.GENERAL_CHAT_DOCK
    return dock and _G.FCFDock_GetSelectedWindow and _G.FCFDock_GetSelectedWindow(dock)
end

---------------------------------------------------------------------------
-- Eingabezeile: im Kanalfenster schreibt sie in den Kanal, in anderen Fenstern wieder wie vorher
---------------------------------------------------------------------------
local function EditBoxFor(frame)
    local choose = _G.ChatFrameUtil and _G.ChatFrameUtil.ChooseBoxForSend
    return (choose and choose(frame)) or frame.editBox
end

local function ApplyEditTarget(frame)
    local edit = frame and EditBoxFor(frame)
    if not edit then return end
    local ch = ChannelOfWindow(frame)
    if ch then
        if not edit.fcChannelSticky then edit.fcPrevSticky = edit:GetAttribute("stickyType") end
        edit.fcChannelSticky = true
        edit:SetAttribute("stickyType", "CHANNEL")
        edit:SetAttribute("chatType", "CHANNEL")
        edit:SetAttribute("channelTarget", ch.id)
    elseif edit.fcChannelSticky then
        edit.fcChannelSticky = nil
        local prev = edit.fcPrevSticky or "SAY"
        edit:SetAttribute("stickyType", prev)
        edit:SetAttribute("chatType", prev)
    end
    if edit:IsShown() and edit.UpdateHeader then edit:UpdateHeader() end
end

---------------------------------------------------------------------------
-- Überschrift im Kanalfenster: "Kanal 5 · Name" oben rechts
---------------------------------------------------------------------------
local function UpdateHeading(frame)
    if not frame then return end
    local ch = ChannelOfWindow(frame)
    if not ch then
        if frame.fcChannelHead then frame.fcChannelHead:Hide() end
        return
    end
    local head = frame.fcChannelHead
    if not head then
        head = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        head:SetHeight(18)
        head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
        head:SetFrameLevel(frame:GetFrameLevel() + 5)
        head:EnableMouse(false)
        UI.SetFlat(head, { C.header[1], C.header[2], C.header[3], 0.85 })
        head:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.6)
        head.text = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head.text:SetPoint("CENTER", 0, 0)
        head.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        frame.fcChannelHead = head
    end
    head.text:SetText(T("Kanal ", "Channel ") .. ch.id .. " · " .. ch.name)
    head:SetWidth(head.text:GetStringWidth() + 14)
    head:Show()
end

---------------------------------------------------------------------------
-- Blizzards Reiter des Kanalfensters unsichtbar und schmal (unser Reiter ersetzt ihn)
---------------------------------------------------------------------------
local function HideBlizzardTab(tab, hidden)
    if not tab then return end
    tab.fcHiddenByChannel = hidden or nil
    if not tab.fcAlphaHooked then
        tab.fcAlphaHooked = true
        -- Blizzard blendet Reiter ständig ein und aus (SetAlpha) – solange er versteckt sein soll, bleibt er bei 0
        hooksecurefunc(tab, "SetAlpha", function(self, a)
            if self.fcHiddenByChannel and a and a > 0 then self:SetAlpha(0) end
        end)
    end
    if hidden then
        tab:SetAlpha(0)
        tab:EnableMouse(false)
        tab:SetWidth(1)
    else
        tab:EnableMouse(true)
        tab:SetAlpha(1)
        if _G.FCFTab_UpdateAlpha then
            local frame = _G["ChatFrame" .. tab:GetID()]
            if frame then pcall(_G.FCFTab_UpdateAlpha, frame) end
        end
    end
end

---------------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------------
local function SelectWindow(frame)
    local dock = _G.GENERAL_CHAT_DOCK
    if frame.isDocked and dock and _G.FCFDock_SelectWindow then
        _G.FCFDock_SelectWindow(dock, frame)
    elseif _G.FCF_CheckShowChatFrame then
        _G.FCF_CheckShowChatFrame(frame)
    end
end

local function OpenChat(channel, frame)
    local id = Joined(channel.name) or channel.id
    local open = (_G.ChatFrameUtil and _G.ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
    if open then open("/" .. id .. " ", frame) end
end

-- Kanal wählen: das Kanalfenster zeigt ab jetzt diesen Kanal (bei Bedarf wird es angelegt)
local function Switch(channel, keepClosed)
    local d = ns.GetDB()
    local frame = ChannelWindow()
    if not frame and _G.FCF_OpenNewWindow then
        frame = _G.FCF_OpenNewWindow(channel.name, true) -- true = ohne Standardnachrichten (nur der Kanal)
        if frame then d.channelWindow = frame:GetName() end
        d.channelActive = nil
    end
    if not frame then
        ns.Chat(T("Kein Chatfenster mehr frei (Blizzard erlaubt 10) – schreibe im aktuellen Fenster.",
            "No free chat window (Blizzard allows 10) – writing in the current one."))
        OpenChat(channel, Selected() or ns.MainChatFrame())
        return
    end
    if not d.channelActive or strupper(d.channelActive) ~= strupper(channel.name) then
        if frame.RemoveAllChannels then frame:RemoveAllChannels() end
        if frame.AddChannel then frame:AddChannel(channel.name) end
        if _G.FCF_SetWindowName then _G.FCF_SetWindowName(frame, channel.name) end
        frame:Clear()
        d.channelActive = channel.name
    end
    SelectWindow(frame)
    UpdateHeading(frame)
    ApplyEditTarget(frame)
    if not keepClosed then OpenChat(channel, frame) end
    if ns.UpdateChannelButton then ns.UpdateChannelButton() end
end

local function CloseChannelWindow()
    local d = ns.GetDB()
    local frame = ChannelWindow()
    d.channelWindow, d.channelActive = nil, nil
    if frame then
        if frame.fcChannelHead then frame.fcChannelHead:Hide() end
        HideBlizzardTab(TabOf(frame), false)
        ApplyEditTarget(frame)
        if _G.FCF_Close then _G.FCF_Close(frame) end
    end
end

-- Kanal verlassen; war er im Kanalfenster, zeigt es den nächsten eigenen Kanal (sonst geht es zu)
local function Leave(channel)
    local d = ns.GetDB()
    local active = d.channelActive and strupper(d.channelActive) == strupper(channel.name)
    if LeaveChannelByName then LeaveChannelByName(channel.name) end
    if active then
        local nextChannel
        for _, ch in ipairs(CustomChannels()) do
            if strupper(ch.name) ~= strupper(channel.name) then nextChannel = ch break end
        end
        if nextChannel then Switch(nextChannel, true) else CloseChannelWindow() end
    end
    C_Timer.After(0.3, function() if ns.UpdateChannelButton then ns.UpdateChannelButton() end end)
end

local function WindowName(frame)
    if frame == ChannelWindow() and ns.GetDB().channelActive then return "# " .. ns.GetDB().channelActive end
    local tab = TabOf(frame)
    local text = tab and tab.GetText and tab:GetText()
    if text and text ~= "" then return text end
    return frame:GetName()
end

---------------------------------------------------------------------------
-- Menüs
---------------------------------------------------------------------------
local function ShowMenu(owner)
    local channels = CustomChannels()
    local dock, frames = DockFrames()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local active = ns.GetDB().channelActive
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(T("Eigene Kanäle", "Custom channels"))
        for _, ch in ipairs(channels) do
            local entry = root:CreateRadio(ch.id .. ". " .. ch.name,
                function() return active and strupper(active) == strupper(ch.name) and ChannelWindow() ~= nil end,
                function() Switch(ch) end)
            entry:CreateButton(T("Anzeigen", "Show"), function() Switch(ch) end)
            entry:CreateButton(T("Kanal verlassen", "Leave channel"), function() Leave(ch) end)
        end
        if #channels == 0 then root:CreateTitle("|cff8a8a8a" .. T("keine eigenen Kanäle", "no custom channels") .. "|r") end
        root:CreateDivider()
        root:CreateButton(T("Kanäle verwalten …", "Manage channels …"), function()
            if ToggleChannelFrame then ToggleChannelFrame() end
        end)
        if #frames > 1 and dock then
            root:CreateDivider()
            root:CreateTitle(T("Chatfenster", "Chat windows"))
            local selected = Selected()
            for _, frame in ipairs(frames) do
                root:CreateRadio(WindowName(frame), function() return frame == selected end,
                    function() SelectWindow(frame) end)
            end
        end
    end)
end

-- Rechtsklick auf einen Reiter: Blizzards Menü um Kanal-Einträge ergänzen
local function ExtendTabMenu()
    if not (Menu and Menu.ModifyMenu) then return end
    Menu.ModifyMenu("MENU_FCF_TAB", function(owner, root)
        local frame = owner and owner.GetID and _G["ChatFrame" .. owner:GetID()]
        local ch = ChannelOfWindow(frame)
        if not ch then return end
        root:CreateDivider()
        root:CreateTitle(T("Kanal: ", "Channel: ") .. ch.name)
        root:CreateButton(T("Kanal verlassen", "Leave channel"), function() Leave(ch) end)
        for _, other in ipairs(CustomChannels()) do
            if strupper(other.name) ~= strupper(ch.name) then
                root:CreateButton(T("Wechseln zu ", "Switch to ") .. other.id .. ". " .. other.name, function() Switch(other) end)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Kanal-Reiter und "+"-Knopf
---------------------------------------------------------------------------
local function TabFont()
    local ref = _G.ChatFrame1Tab and _G.ChatFrame1Tab:GetFontString()
    local font, size, flags = ref and ref:GetFont()
    return font, size, flags
end

local function UpdateChanTabLook()
    if not chanTab then return end
    local selected = ChannelWindow() and Selected() == ChannelWindow() and not ns.imActive
    if selected then
        chanTab:SetBackdropColor(C.header[1], C.header[2], C.header[3], 0.95)
        chanTab:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.75)
        chanTab.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    else
        chanTab:SetBackdropColor(C.button[1], C.button[2], C.button[3], 0.85)
        chanTab:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        chanTab.text:SetTextColor(0.82, 0.82, 0.82)
    end
end

local function BuildChanTab()
    if chanTab then return chanTab end
    chanTab = CreateFrame("Button", "ForeverChatChannelTab", UIParent, "BackdropTemplate")
    chanTab:SetHeight(SIZE_H)
    chanTab:SetFrameStrata("MEDIUM")
    chanTab:SetFrameLevel(20)
    UI.SetFlat(chanTab, { C.button[1], C.button[2], C.button[3], 0.85 })
    chanTab.text = chanTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local font, size, flags = TabFont()
    -- Schrift wie Blizzards Reiter; liefert der Reiter keine Größe, bleibt die Standardschrift
    if type(font) == "string" and type(size) == "number" and size > 0 then
        pcall(chanTab.text.SetFont, chanTab.text, font, size, flags or "")
    end
    chanTab.text:SetPoint("LEFT", 7, 0)
    chanTab.text:SetPoint("RIGHT", -7, 0)
    chanTab.text:SetWordWrap(false)
    chanTab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    chanTab:SetScript("OnClick", function(self, button)
        local frame = ChannelWindow()
        if not frame then return end
        local tab = TabOf(frame)
        if button == "RightButton" then
            -- Blizzards Reiter-Menü des Kanalfensters (mit unseren Einträgen, siehe ExtendTabMenu)
            if tab and _G.FCF_Tab_OnClick then _G.FCF_Tab_OnClick(tab, "RightButton") end
            return
        end
        if tab and _G.FCF_Tab_OnClick then _G.FCF_Tab_OnClick(tab, "LeftButton") else SelectWindow(frame) end
        if ns.HideIM then ns.HideIM() end
        local ch = ChannelOfWindow(frame)
        if ch then ApplyEditTarget(frame) end
        UpdateChanTabLook()
    end)
    chanTab:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local ch = ChannelOfWindow(ChannelWindow())
        GameTooltip:AddLine(ch and (T("Kanal ", "Channel ") .. ch.id .. " · " .. ch.name) or T("Kanalfenster", "Channel window"))
        GameTooltip:AddLine(T("Linksklick: anzeigen · Rechtsklick: Fenster-Menü (Kanal verlassen …)",
            "Left-click: show · Right-click: window menu (leave channel …)"), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(T("Kanal wechseln: „+“-Knopf", "Switch channel: \"+\" button"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    chanTab:SetScript("OnLeave", function()
        UpdateChanTabLook()
        GameTooltip_Hide()
    end)
    chanTab:Hide()
    return chanTab
end

local function BuildButton()
    if plus then return plus end
    plus = CreateFrame("Button", "ForeverChatChannelButton", UIParent, "BackdropTemplate")
    plus:SetSize(SIZE_W, SIZE_H)
    plus:SetFrameStrata("MEDIUM")
    plus:SetFrameLevel(20)
    UI.SetFlat(plus, { C.button[1], C.button[2], C.button[3], 0.85 })
    plus.text = plus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plus.text:SetPoint("CENTER", 0, 1)
    plus.text:SetText("+")
    plus.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    plus:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    plus:SetScript("OnClick", function(self) ShowMenu(self) end)
    plus:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(T("Eigene Kanäle und Chatfenster", "Custom channels and chat windows"))
        for _, ch in ipairs(CustomChannels()) do GameTooltip:AddLine(ch.id .. ". " .. ch.name, 1, 1, 1) end
        GameTooltip:AddLine(T("Klick: Kanal wählen oder verlassen, Fenster wechseln", "Click: choose or leave a channel, switch windows"),
            0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip_Hide()
    end)
    plus:Hide()
    return plus
end

-- Reihenfolge: [General][Kampflog][# Kanal][+][weitere Reiter …] – Blizzards bewegliche Reiter rücken dahinter
local function Place()
    local d = ns.GetDB()
    local dock, frames = DockFrames()
    if not (dock and dock.scrollFrame) then return end
    local channels = CustomChannels()
    local window = ChannelWindow()
    -- Kanalfenster ohne gültigen Kanal (z. B. anderswo verlassen): nächsten Kanal zeigen
    if window and not ChannelOfWindow(window) and d.channelButton then
        if channels[1] then Switch(channels[1], true) return end
    end
    local on = d.channelButton and dock:IsVisible()
    local showTab = on and window ~= nil and ChannelOfWindow(window) ~= nil
    local showPlus = on and (#channels > 0 or overflowWanted or showTab)

    -- Blizzards Reiter des Kanalfensters verstecken (bzw. wieder zeigen, wenn die Funktion aus ist)
    if window then HideBlizzardTab(TabOf(window), showTab) end

    -- unsere Knöpfe kommen hinter "Kampflog" (ChatFrame2), sonst hinter "General" (ChatFrame1)
    local anchorIndex
    for i, frame in ipairs(frames) do
        local tab = TabOf(frame)
        if (frame == _G.ChatFrame1 or frame == _G.ChatFrame2) and tab and tab:IsShown() then anchorIndex = i end
    end
    local anchorTab = anchorIndex and TabOf(frames[anchorIndex])
    local anchor = anchorTab and (anchorTab.fcArea or anchorTab)
    if showTab then
        BuildChanTab()
        local ch = ChannelOfWindow(window)
        chanTab.text:SetText("# " .. ch.name)
        local w = (chanTab.text.GetUnboundedStringWidth and chanTab.text:GetUnboundedStringWidth())
            or chanTab.text:GetStringWidth()
        chanTab:SetWidth(math.min(TAB_MAX_W, w + 14))
        chanTab:ClearAllPoints()
        if anchor then chanTab:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else chanTab:SetPoint("LEFT", dock, "LEFT", 2, 0) end
        UpdateChanTabLook()
        chanTab:Show()
    elseif chanTab then
        chanTab:Hide()
    end
    if showPlus then
        BuildButton()
        plus:ClearAllPoints()
        if showTab then
            plus:SetPoint("LEFT", chanTab, "RIGHT", 3, 0)
        elseif anchor then
            plus:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
        else
            plus:SetPoint("LEFT", dock, "LEFT", 2, 0)
        end
        plus:SetAlpha(0.9)
        plus:Show()
    elseif plus then
        plus:Hide()
    end

    -- weitere Blizzard-Reiter (Flüstern, eigene Fenster …) rücken hinter unsere Knöpfe
    local last = (showPlus and plus) or (showTab and chanTab) or nil
    if last and anchorIndex then
        for i = anchorIndex + 1, #frames do
            local frame = frames[i]
            if frame ~= window then
                local tab = TabOf(frame)
                if tab then
                    tab:ClearAllPoints()
                    tab:SetPoint("LEFT", last, "RIGHT", 2, 0)
                end
                break
            end
        end
    end
end

function ns.UpdateChannelButton()
    Place()
    local window = ChannelWindow()
    if window then UpdateHeading(window) end
end

-- Blizzards Überlauf-Pfeil ganz weg: sobald er gezeigt würde, wieder verstecken (wir merken uns nur, dass er nötig wäre)
local function HideOverflow()
    local dock = _G.GENERAL_CHAT_DOCK
    local button = dock and dock.overflowButton
    if not button or button.fcHooked then return end
    button.fcHooked = true
    local hiding = false
    hooksecurefunc(button, "Show", function(self)
        overflowWanted = true
        hiding = true
        self:Hide()
        hiding = false
    end)
    hooksecurefunc(button, "Hide", function()
        if not hiding then overflowWanted = false end
    end)
    if button:IsShown() then button:Show() end -- löst den Haken oben aus
    if button.list then button.list:Hide() end
end

-- Stand der Vorversion (je Kanal ein eigenes Fenster) aufräumen: diese Fenster schließen
local function CleanupOldWindows()
    local d = ns.GetDB()
    if not d.channelWindows then return end
    for frameName, name in pairs(d.channelWindows) do
        local frame = _G[frameName]
        local tab = TabOf(frame)
        if frame and tab and tab:GetText() == name and frameName ~= d.channelWindow and _G.FCF_Close then
            pcall(_G.FCF_Close, frame)
        end
    end
    d.channelWindows = nil
end

function ns.SetupChannels()
    HideOverflow()
    ExtendTabMenu()
    if _G.FCFDock_UpdateTabs then hooksecurefunc("FCFDock_UpdateTabs", function() if not reflowing then Place() end end) end
    -- Fensterwechsel: Eingabezeile auf den Kanal stellen bzw. zurück, Kanal-Reiter einfärben
    if _G.FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function(_, frame)
            ApplyEditTarget(frame)
            UpdateHeading(frame)
            UpdateChanTabLook()
        end)
    end
    -- Kanalfenster von Hand geschlossen: vergessen, Blizzard-Reiter wieder normal (das Fenster wird später neu vergeben)
    if _G.FCF_Close then
        hooksecurefunc("FCF_Close", function(frame)
            local d = ns.GetDB()
            if frame and frame.GetName and d.channelWindow == frame:GetName() then
                d.channelWindow, d.channelActive = nil, nil
                if frame.fcChannelHead then frame.fcChannelHead:Hide() end
                HideBlizzardTab(TabOf(frame), false)
                C_Timer.After(0, ns.UpdateChannelButton)
            end
        end)
    end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "CHANNEL_LEFT",
        "CHANNEL_FLAGS_UPDATED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function() C_Timer.After(0.2, ns.UpdateChannelButton) end)
    C_Timer.NewTicker(2, Place) -- Sicherheitsnetz: Reiter ändern ihre Breite auch ohne Ereignis
    C_Timer.After(1, function()
        CleanupOldWindows()
        ns.UpdateChannelButton()
        local selected = Selected()
        if selected then ApplyEditTarget(selected) end
    end)
end
