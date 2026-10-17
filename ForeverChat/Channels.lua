-- ForeverChat – Channels.lua: "+"-Knopf neben den Reitern (General, Kampflog …) für eigene Kanäle.
-- Er erscheint, sobald man in einem eigenen Kanal (Custom Channel) ist, und zeigt ein Menü: Kanal wählen (die
-- Eingabezeile schreibt dann dorthin, der Kanal wird im gewählten Chatfenster angezeigt) oder Kanal verlassen.
-- Zusätzlich listet das Menü alle Chatfenster der Reiterleiste zum Umschalten (falls Blizzards Überlauf-Pfeil
-- Reiter versteckt). Nur Aussehen und eigene Knöpfe – Blizzards Reiter bleiben, wie sie sind.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local plus
local SIZE_H, SIZE_W = 18, 20

---------------------------------------------------------------------------
-- Eigene Kanäle finden
---------------------------------------------------------------------------
-- Eigener Kanal (vom Spieler erstellt/betreten)? Blizzard unterscheidet Zonen-, Gemeinschafts- und eigene Kanäle.
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
-- Aktionen
---------------------------------------------------------------------------
-- Gewähltes Chatfenster der Reiterleiste (sonst der Hauptchat)
local function TargetFrame()
    local dock = _G.GENERAL_CHAT_DOCK
    local selected = dock and _G.FCFDock_GetSelectedWindow and _G.FCFDock_GetSelectedWindow(dock)
    return selected or ns.MainChatFrame()
end

local function Switch(channel)
    local frame = TargetFrame()
    if not frame then return end
    -- im gewählten Fenster anzeigen, falls der Kanal dort noch fehlt
    local present = false
    for _, name in pairs(frame.channelList or {}) do
        if strupper(name) == strupper(channel.name) then present = true break end
    end
    if not present and frame.AddChannel then frame:AddChannel(channel.name) end
    -- Eingabezeile öffnen und auf den Kanal stellen ("/5 " wählt den Kanal wie von Hand)
    local id = (GetChannelName and GetChannelName(channel.name)) or channel.id
    local open = (_G.ChatFrameUtil and _G.ChatFrameUtil.OpenChat) or _G.ChatFrame_OpenChat
    if open then open("/" .. id .. " ", frame) end
end

local function Leave(channel)
    if LeaveChannelByName then
        LeaveChannelByName(channel.name)
        C_Timer.After(0.3, function() if ns.UpdateChannelButton then ns.UpdateChannelButton() end end)
    end
end

local function DockFrames()
    local dock = _G.GENERAL_CHAT_DOCK
    local frames = dock and _G.FCFDock_GetChatFrames and _G.FCFDock_GetChatFrames(dock)
    return dock, frames or {}
end

local function WindowName(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    local text = tab and tab.GetText and tab:GetText()
    if text and text ~= "" then return text end
    return frame:GetName()
end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------
local function ShowMenu(owner)
    local channels = CustomChannels()
    local dock, frames = DockFrames()
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(T("Eigene Kanäle", "Custom channels"))
            for _, ch in ipairs(channels) do
                local entry = root:CreateButton(ch.id .. ". " .. ch.name, function() Switch(ch) end)
                entry:CreateButton(T("Dorthin wechseln", "Switch to it"), function() Switch(ch) end)
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
                        function() if _G.FCFDock_SelectWindow then _G.FCFDock_SelectWindow(dock, frame) end end)
                end
            end
        end)
    elseif UI.ChoiceMenu then
        -- Rückfall ohne Menü-System: nur wechseln
        local list = {}
        for _, ch in ipairs(channels) do list[#list + 1] = { key = ch, label = ch.id .. ". " .. ch.name } end
        if #list > 0 then UI.ChoiceMenu(owner, list, function() return nil end, Switch) end
    end
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
        GameTooltip:AddLine(T("Eigene Kanäle", "Custom channels"))
        for _, ch in ipairs(CustomChannels()) do GameTooltip:AddLine(ch.id .. ". " .. ch.name, 1, 1, 1) end
        GameTooltip:AddLine(T("Klick: Kanal wählen oder verlassen", "Click: choose or leave a channel"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
        GameTooltip_Hide()
    end)
    plus:Hide()
    return plus
end

-- direkt rechts neben den letzten sichtbaren Reiter setzen; ist die Leiste voll, links vom Überlauf-Pfeil
local function Place()
    local d = ns.GetDB()
    local main = ns.MainChatFrame()
    local channels = CustomChannels()
    if not (d.channelButton and #channels > 0 and main and main:IsShown()) then
        if plus then plus:Hide() end
        return
    end
    BuildButton()
    local dock, frames = DockFrames()
    local lastTab, lastRight
    for _, frame in ipairs(frames) do
        local tab = _G[frame:GetName() .. "Tab"]
        if tab and tab:IsShown() and tab:GetRight() then
            local r = tab:GetRight()
            if not lastRight or r > lastRight then lastTab, lastRight = tab, r end
        end
    end
    plus:ClearAllPoints()
    local overflow = dock and dock.overflowButton
    if overflow and overflow:IsShown() then
        plus:SetPoint("RIGHT", overflow, "LEFT", -3, 0)
    elseif lastTab then
        local area = lastTab.fcArea or lastTab
        plus:SetPoint("LEFT", area, "RIGHT", 4, 0)
    else
        plus:SetPoint("LEFT", dock or main, "LEFT", 4, 0)
    end
    plus:SetAlpha(0.9)
    plus:Show()
end

function ns.UpdateChannelButton() Place() end

function ns.SetupChannels()
    -- Blizzards Überlauf-Liste (Pfeil, wenn nicht alle Reiter passen) soll über unseren Knöpfen liegen
    local dock = _G.GENERAL_CHAT_DOCK
    if dock and dock.overflowButton and dock.overflowButton.list then dock.overflowButton.list:SetFrameStrata("DIALOG") end
    if _G.FCFDock_UpdateTabs then hooksecurefunc("FCFDock_UpdateTabs", function() Place() end) end
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "CHANNEL_LEFT",
        "CHANNEL_FLAGS_UPDATED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function() C_Timer.After(0.2, Place) end)
    C_Timer.NewTicker(2, Place) -- Sicherheitsnetz: Reiter ändern ihre Breite auch ohne Ereignis
    C_Timer.After(1, Place)
end
