-- ForeverChat – Channels.lua: "+"-Knopf neben den Reitern (General, Kampflog …) für eigene Kanäle.
-- Kanal wählen öffnet (oder zeigt) ein eigenes Chatfenster als Reiter mit dem Kanalnamen: nur dieser Kanal läuft
-- dort, oben rechts steht gut sichtbar "Kanal 5 · Name", und die Eingabezeile schreibt automatisch in den Kanal.
-- Der Reiter hat Blizzards normales Rechtsklick-Menü (Umbenennen, Schriftgröße, Schließen …) plus "Kanal verlassen".
-- Blizzards Überlauf-Pfeil der Reiterleiste ist ausgeblendet – der "+"-Knopf listet auch alle Chatfenster.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local plus
local SIZE_H, SIZE_W = 18, 20
local overflowWanted = false -- Blizzard würde gerade den Überlauf-Pfeil zeigen (nicht alle Reiter passen)

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

---------------------------------------------------------------------------
-- Kanalfenster: welches Chatfenster gehört zu welchem Kanal (gespeichert, Blizzard merkt sich die Fenster selbst)
---------------------------------------------------------------------------
local function WindowMap()
    local d = ns.GetDB()
    d.channelWindows = d.channelWindows or {}
    return d.channelWindows
end

local function DockFrames()
    local dock = _G.GENERAL_CHAT_DOCK
    local frames = dock and _G.FCFDock_GetChatFrames and _G.FCFDock_GetChatFrames(dock)
    return dock, frames or {}
end

local function IsOpenWindow(frame)
    if not frame then return false end
    local tab = _G[frame:GetName() .. "Tab"]
    return tab and tab:IsShown() or frame:IsShown()
end

-- Kanal des Fensters (nil = kein Kanalfenster oder Kanal nicht mehr betreten)
local function ChannelOfWindow(frame)
    if not frame then return nil end
    local name = WindowMap()[frame:GetName()]
    if not name then return nil end
    local id = GetChannelName and GetChannelName(name)
    if not id or id == 0 then return nil end
    return { id = id, name = name }
end

local function WindowOfChannel(channel)
    for frameName, name in pairs(WindowMap()) do
        local frame = _G[frameName]
        if strupper(name) == strupper(channel.name) and IsOpenWindow(frame) then return frame end
    end
    return nil
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

local function UpdateAllWindows()
    local _, frames = DockFrames()
    for _, frame in ipairs(frames) do UpdateHeading(frame) end
    for frameName in pairs(WindowMap()) do
        local frame = _G[frameName]
        if frame then UpdateHeading(frame) end
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
    local id = (GetChannelName and GetChannelName(channel.name)) or channel.id
    local open = (_G.ChatFrameUtil and _G.ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
    if open then open("/" .. id .. " ", frame) end
end

-- Kanal wählen: eigenes Fenster zeigen (bei Bedarf anlegen) und die Eingabezeile darauf stellen
local function Switch(channel)
    local frame = WindowOfChannel(channel)
    if not frame and _G.FCF_OpenNewWindow then
        frame = _G.FCF_OpenNewWindow(channel.name, true) -- true = ohne Standardnachrichten (nur dieser Kanal)
        if frame then
            if frame.AddChannel then frame:AddChannel(channel.name) end
            WindowMap()[frame:GetName()] = channel.name
        end
    end
    if not frame then
        -- kein Fenster mehr frei (Blizzard erlaubt nur 10): im gewählten Fenster schreiben
        frame = (_G.GENERAL_CHAT_DOCK and _G.FCFDock_GetSelectedWindow(_G.GENERAL_CHAT_DOCK)) or ns.MainChatFrame()
        ns.Chat(T("Kein Chatfenster mehr frei – schreibe im aktuellen Fenster.", "No free chat window – writing in the current one."))
    end
    SelectWindow(frame)
    UpdateHeading(frame)
    ApplyEditTarget(frame)
    OpenChat(channel, frame)
    C_Timer.After(0.1, function() if ns.UpdateChannelButton then ns.UpdateChannelButton() end end)
end

local function Leave(channel)
    local frame = WindowOfChannel(channel)
    if LeaveChannelByName then LeaveChannelByName(channel.name) end
    if frame then
        WindowMap()[frame:GetName()] = nil
        if frame.fcChannelHead then frame.fcChannelHead:Hide() end
        ApplyEditTarget(frame)
        if _G.FCF_Close then _G.FCF_Close(frame) end
    end
    C_Timer.After(0.3, function() if ns.UpdateChannelButton then ns.UpdateChannelButton() end end)
end

local function WindowName(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    local text = tab and tab.GetText and tab:GetText()
    if text and text ~= "" then return text end
    return frame:GetName()
end

---------------------------------------------------------------------------
-- Menü des "+"-Knopfs
---------------------------------------------------------------------------
local function ShowMenu(owner)
    local channels = CustomChannels()
    local dock, frames = DockFrames()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(T("Eigene Kanäle", "Custom channels"))
        for _, ch in ipairs(channels) do
            local entry = root:CreateButton(ch.id .. ". " .. ch.name, function() Switch(ch) end)
            entry:CreateButton(T("Fenster öffnen", "Open window"), function() Switch(ch) end)
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
            local selected = _G.FCFDock_GetSelectedWindow and _G.FCFDock_GetSelectedWindow(dock)
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
        local channels = CustomChannels()
        if not ch and #channels == 0 then return end
        root:CreateDivider()
        root:CreateTitle(T("Eigene Kanäle", "Custom channels"))
        if ch then
            root:CreateButton(T("Kanal verlassen", "Leave channel") .. " (" .. ch.name .. ")", function() Leave(ch) end)
        end
        for _, other in ipairs(channels) do
            if not ch or strupper(other.name) ~= strupper(ch.name) then
                root:CreateButton(T("Öffnen: ", "Open: ") .. other.id .. ". " .. other.name, function() Switch(other) end)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Der Knopf
---------------------------------------------------------------------------
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
        GameTooltip:AddLine(T("Klick: Kanal öffnen oder verlassen, Fenster wechseln", "Click: open or leave a channel, switch windows"),
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

-- Rechts neben den letzten Reiter; passen nicht alle Reiter, an den rechten Rand der Reiterleiste (wo Blizzards Pfeil säße)
local function Place()
    local d = ns.GetDB()
    local dock, frames = DockFrames()
    local channels = CustomChannels()
    if not (d.channelButton and (#channels > 0 or overflowWanted) and dock and dock:IsVisible()) then
        if plus then plus:Hide() end
        return
    end
    BuildButton()
    local lastTab, lastRight
    for _, frame in ipairs(frames) do
        local tab = _G[frame:GetName() .. "Tab"]
        if tab and tab:IsShown() and tab:GetRight() then
            local r = tab:GetRight()
            if not lastRight or r > lastRight then lastTab, lastRight = tab, r end
        end
    end
    plus:ClearAllPoints()
    local area = lastTab and (lastTab.fcArea or lastTab)
    if overflowWanted then
        local dy = 0
        local _, ay = area and area:GetCenter()
        local _, cy = dock:GetCenter()
        if ay and cy then dy = ay - cy end
        plus:SetPoint("RIGHT", dock, "RIGHT", -2, dy)
    elseif area then
        plus:SetPoint("LEFT", area, "RIGHT", 4, 0)
    else
        plus:SetPoint("LEFT", dock, "LEFT", 4, 0)
    end
    plus:SetAlpha(0.9)
    plus:Show()
end

function ns.UpdateChannelButton()
    Place()
    UpdateAllWindows()
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

function ns.SetupChannels()
    HideOverflow()
    ExtendTabMenu()
    if _G.FCFDock_UpdateTabs then hooksecurefunc("FCFDock_UpdateTabs", function() Place() end) end
    -- Fensterwechsel: Eingabezeile auf den Kanal stellen bzw. zurück, Überschrift aktualisieren
    if _G.FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function(_, frame)
            ApplyEditTarget(frame)
            UpdateHeading(frame)
            Place()
        end)
    end
    -- von Hand geschlossene Kanalfenster vergessen
    if _G.FCF_Close then
        hooksecurefunc("FCF_Close", function(frame)
            if frame and frame.GetName then WindowMap()[frame:GetName()] = nil end
            if frame and frame.fcChannelHead then frame.fcChannelHead:Hide() end
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
        ns.UpdateChannelButton()
        local dock = _G.GENERAL_CHAT_DOCK
        local selected = dock and _G.FCFDock_GetSelectedWindow and _G.FCFDock_GetSelectedWindow(dock)
        if selected then ApplyEditTarget(selected) end
    end)
end
