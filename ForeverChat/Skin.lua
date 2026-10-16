-- ForeverChat – Skin.lua: Aussehen im Forever-Core-Stil.
-- Nur optisch: Blizzards Grafiken werden unsichtbar (UI.HideBlizzard = Alpha 0, kein Hide/SetParent ->
-- kein taint), unsere Flaechen liegen daneben bzw. als zusaetzliche Grafiken auf den Reitern.
-- Position und Groesse des Hauptchats verwaltet Blizzards Bearbeitungsmodus (ChatFrame1 ist dort ein
-- eigenes Element) – ForeverChat verschiebt ihn deshalb nicht selbst.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR
local WHITE = "Interface\\Buttons\\WHITE8x8"

local skinned = {}  -- [Chatfenster] = true
local backdrops = {} -- [Chatfenster] = Flaeche
function ns.GetBackdrop(frame) return backdrops[frame] end

---------------------------------------------------------------------------
-- Flache Rahmen aus Texturen (fuer Blizzard-Knoepfe/Eingabefelder, an die wir keine Kind-Rahmen haengen)
---------------------------------------------------------------------------
local function FlatTextures(owner, anchor, layer)
    local t = {}
    t.bg = owner:CreateTexture(nil, layer or "BACKGROUND", nil, -7)
    t.bg:SetTexture(WHITE)
    t.bg:SetAllPoints(anchor)
    t.edges = {}
    for i = 1, 4 do
        local e = owner:CreateTexture(nil, "BORDER", nil, 7)
        e:SetTexture(WHITE)
        t.edges[i] = e
    end
    local e = t.edges
    e[1]:SetPoint("TOPLEFT", anchor, "TOPLEFT") e[1]:SetPoint("TOPRIGHT", anchor, "TOPRIGHT") e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT") e[2]:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT") e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", anchor, "TOPLEFT") e[3]:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT") e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", anchor, "TOPRIGHT") e[4]:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT") e[4]:SetWidth(1)
    function t:SetColors(bg, edge)
        self.bg:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
        for _, x in ipairs(self.edges) do x:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1) end
    end
    function t:SetShown(shown)
        self.bg:SetShown(shown)
        for _, x in ipairs(self.edges) do x:SetShown(shown) end
    end
    return t
end

-- goldener Rand beim Ueberfahren (Highlight-Ebene, wie die Forever-Knoepfe)
local function HoverEdges(button, anchor)
    local a = C.accent
    local list = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
        local t = button:CreateTexture(nil, "HIGHLIGHT")
        t:SetColorTexture(a[1], a[2], a[3], 0.9)
        t:SetPoint(side[1], anchor, side[1])
        t:SetPoint(side[2], anchor, side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
        list[#list + 1] = t
    end
    return list
end

---------------------------------------------------------------------------
-- Flaeche hinter dem Chat (einstellbar durchsichtig)
---------------------------------------------------------------------------
local TAB_ROOM = 28 -- Platz fuer die Reiterzeile ueber dem Chat

local function UpdateBackdrop(frame)
    local bd = backdrops[frame]
    if not bd then return end
    local db = ns.GetDB()
    bd:SetBackdropColor(C.background[1], C.background[2], C.background[3], (db.bgAlpha or 20) / 100)
    bd:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], (db.borderAlpha or 50) / 100)
    bd.line:SetAlpha((db.borderAlpha or 50) / 100)
    bd:SetShown(frame:IsShown())
end

local function CreateBackdrop(frame)
    local bd = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    bd:SetFrameStrata("BACKGROUND")
    bd:EnableMouse(false)
    bd:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local anchor = frame.Background or frame
    bd:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, TAB_ROOM)
    bd:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
    -- feine goldene Linie unter der Reiterzeile
    bd.line = bd:CreateTexture(nil, "ARTWORK")
    bd.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
    bd.line:SetHeight(1)
    bd.line:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 1)
    bd.line:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 1)
    backdrops[frame] = bd
    frame:HookScript("OnShow", function() UpdateBackdrop(frame) end)
    frame:HookScript("OnHide", function() bd:Hide() end)
    UpdateBackdrop(frame)
    return bd
end

---------------------------------------------------------------------------
-- Reiter im ForeverQuests-Stil: flache Flaeche, feiner Rand, aktiv = gold
---------------------------------------------------------------------------
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
                  "HighlightLeft", "HighlightMiddle", "HighlightRight" }

local function UpdateTabLook(tab, selected)
    if not tab or not tab.fcFlat then return end
    local styled = ns.GetDB().styleTabs
    tab.fcFlat:SetShown(styled)
    for _, h in ipairs(tab.fcHover) do h:SetShown(styled) end
    if not styled then return end
    if selected == nil then
        local frame = _G["ChatFrame" .. tab:GetID()]
        selected = frame and frame:IsShown()
    end
    if ns.imActive then selected = false end -- der Messenger-Reiter ist gerade der aktive
    local fs = tab:GetFontString()
    if selected then
        tab.fcFlat:SetColors({ C.header[1], C.header[2], C.header[3], 0.95 }, { C.accent[1], C.accent[2], C.accent[3], 0.75 })
        if fs then fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
    else
        tab.fcFlat:SetColors({ C.button[1], C.button[2], C.button[3], 0.85 }, C.border)
        if fs then fs:SetTextColor(0.82, 0.82, 0.82) end
    end
    -- Neue-Nachricht-Leuchten in Gold
    if tab.glow then tab.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3]) end
end
ns.UpdateTabLook = UpdateTabLook

-- Blizzard-Grafiken des Reiters unsichtbar (bleiben vorhanden, nur Alpha 0) bzw. zurueck
local function ApplyTabArt(tab)
    local styled = ns.GetDB().styleTabs
    for _, key in ipairs(TAB_ART) do
        local tex = tab[key]
        if tex then
            if styled then UI.HideBlizzard(tex, { children = false }) else UI.ShowBlizzard(tex) end
        end
    end
end

local function SkinTab(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    if not tab or tab.fcFlat then return end
    -- eigene Flaeche um den Text des Reiters
    local area = CreateFrame("Frame", nil, tab)
    area:EnableMouse(false)
    local fs = tab:GetFontString()
    area:SetPoint("LEFT", tab, "LEFT", 2, 0)
    area:SetPoint("RIGHT", tab, "RIGHT", -2, 0)
    if fs then
        area:SetPoint("TOP", fs, "TOP", 0, 5)
        area:SetPoint("BOTTOM", fs, "BOTTOM", 0, -5)
    else
        area:SetPoint("TOP", tab, "TOP", 0, -8)
        area:SetPoint("BOTTOM", tab, "BOTTOM", 0, 2)
    end
    tab.fcFlat = FlatTextures(tab, area, "BACKGROUND")
    tab.fcHover = HoverEdges(tab, area)
    UpdateTabLook(tab)
end

---------------------------------------------------------------------------
-- Eingabefeld: flach, goldener Rand beim Tippen
---------------------------------------------------------------------------
local EDIT_ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function UpdateEditLook(edit)
    if not edit or not edit.fcFlat then return end
    local styled = ns.GetDB().styleEditBox
    edit.fcFlat:SetShown(styled)
    if not styled then return end
    local focus = edit:HasFocus()
    edit.fcFlat:SetColors({ C.input[1], C.input[2], C.input[3], 0.92 },
        focus and { C.accent[1], C.accent[2], C.accent[3], 0.85 } or C.border)
end

local function ApplyEditArt(edit)
    local styled = ns.GetDB().styleEditBox
    for _, key in ipairs(EDIT_ART) do
        local tex = _G[edit:GetName() .. key]
        if tex then
            if styled then UI.HideBlizzard(tex, { children = false }) else UI.ShowBlizzard(tex) end
        end
    end
end

-- Eingabezeile nur zeigen, wenn darin geschrieben wird oder die Maus darueber ist (Einstellung autoHideEditBox).
-- Blizzards Chat-Stil bleibt unveraendert; die Zeile ist nur unsichtbar (Alpha 0) und bleibt anklickbar.
-- Waehrend der Messenger-Ansicht ist sie ganz unsichtbar und nicht anklickbar (dort schreibt das IM-Feld).
local function EditShouldHide(edit)
    if ns.imActive then return true end
    if not ns.GetDB().autoHideEditBox then return false end
    return not (edit:HasFocus() or edit:IsMouseOver())
end

function ns.UpdateEditVisibility(edit)
    if not edit then return end
    if EditShouldHide(edit) then
        UI.HideBlizzard(edit, { children = false, when = function() return EditShouldHide(edit) end,
            noMouse = ns.imActive and { edit } or {} })
        if not ns.imActive then edit:EnableMouse(true) end -- Mausover soll sie wieder zeigen
    else
        UI.ShowBlizzard(edit)
    end
end

function ns.UpdateAllEditVisibility()
    ns.ForEachChatFrame(function(frame)
        ns.UpdateEditVisibility(frame.editBox or _G[frame:GetName() .. "EditBox"])
    end)
end

local function SkinEditBox(frame)
    local edit = frame.editBox or _G[frame:GetName() .. "EditBox"]
    if not edit or edit.fcFlat then return end
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnEditFocusGained", "OnEditFocusLost" }) do
        edit:HookScript(script, function(self) ns.UpdateEditVisibility(self) end)
    end
    local area = CreateFrame("Frame", nil, edit)
    area:EnableMouse(false)
    -- Hoehe vom Eingabefeld, Breite genau wie der Rahmen des Chatfensters (buendig links und rechts)
    local bd = backdrops[frame]
    area:SetPoint("TOP", edit, "TOP", 0, -4)
    area:SetPoint("BOTTOM", edit, "BOTTOM", 0, 4)
    area:SetPoint("LEFT", bd or edit, "LEFT", bd and 0 or 4, 0)
    area:SetPoint("RIGHT", bd or edit, "RIGHT", bd and 0 or -4, 0)
    edit.fcFlat = FlatTextures(edit, area, "BACKGROUND")
    edit:HookScript("OnEditFocusGained", UpdateEditLook)
    edit:HookScript("OnEditFocusLost", UpdateEditLook)
    UpdateEditLook(edit)
end

---------------------------------------------------------------------------
-- Eingabe: Pfeiltasten fuer den Verlauf, Umschalt + Mausrad
---------------------------------------------------------------------------
local function ApplyInput(frame)
    local edit = frame.editBox or _G[frame:GetName() .. "EditBox"]
    if edit and edit.SetAltArrowKeyMode then
        edit:SetAltArrowKeyMode(not ns.GetDB().arrowHistory)
    end
    if not frame.fcWheel then
        frame.fcWheel = true
        frame:HookScript("OnMouseWheel", function(self, delta)
            if not ns.GetDB().shiftScroll or not IsShiftKeyDown() then return end
            if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
        end)
    end
end

---------------------------------------------------------------------------
-- Blizzards Knopfleiste neben dem Chat (ausblendbar; Ersatz: eigene Knopfleiste)
---------------------------------------------------------------------------
local SIDE_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
                       "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }

local function SideParts(frame)
    local bf = frame.buttonFrame or _G[frame:GetName() .. "ButtonFrame"]
    local list = {}
    if bf then
        for _, c in ipairs({ bf:GetChildren() }) do list[#list + 1] = c end
    end
    if frame == ns.MainChatFrame() then
        for _, name in ipairs(SIDE_BUTTONS) do
            if _G[name] then list[#list + 1] = _G[name] end
        end
    end
    return bf, list
end

local function ApplySideButtons(frame)
    local bf, list = SideParts(frame)
    if not bf then return end
    if ns.GetDB().hideSideButtons then
        UI.HideBlizzard(bf, { noMouse = list })
        for _, b in ipairs(list) do UI.HideBlizzard(b, { noMouse = { b } }) end
    else
        UI.ShowBlizzard(bf)
        for _, b in ipairs(list) do UI.ShowBlizzard(b) end
    end
end

---------------------------------------------------------------------------
-- Eigene Knopfleiste in der obersten Zeile des Chatfensters (rechts neben den Reitern).
-- Blizzards Reiterleiste (GENERAL_CHAT_DOCK) bekommt rechts entsprechend weniger Platz – Blizzard verteilt
-- die Reiter dann selbst auf die verbleibende Breite (bei vielen Reitern wie gewohnt mit Ueberlauf-Pfeil).
---------------------------------------------------------------------------
local TOOL_SIZE, TOOL_GAP = 18, 3
local toolbar
local function ToolButton(parent, icon, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(TOOL_SIZE, TOOL_SIZE)
    UI.SetFlat(b, { C.button[1], C.button[2], C.button[3], 0.85 })
    HoverEdges(b, b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.icon:SetTexture(icon)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tip)
        GameTooltip:Show()
        toolbar:SetAlpha(1)
    end)
    b:SetScript("OnLeave", function() GameTooltip_Hide() toolbar:SetAlpha(0.55) end)
    return b
end

local function BuildToolbar()
    local main = ns.MainChatFrame()
    local bd = backdrops[main]
    if not bd or toolbar then return end
    toolbar = CreateFrame("Frame", "ForeverChatToolbar", UIParent)
    toolbar:SetHeight(TOOL_SIZE)
    -- senkrecht mittig in der Reiterzeile, rechts buendig im Rahmen
    toolbar:SetPoint("RIGHT", bd, "TOPRIGHT", -4, -(TAB_ROOM / 2) - 1)
    toolbar:SetFrameStrata("MEDIUM") -- wie die Reiter
    toolbar:SetAlpha(0.55)
    local buttons = {
        { "Interface\\Buttons\\LockButton-Locked-Up", T("Chat entsperren / sperren", "Unlock / lock chat"),
            function() ns.ToggleChatLock() end, "lock" },
        { "Interface\\Buttons\\UI-OptionsButton", T("ForeverChat-Einstellungen", "ForeverChat settings"),
            function() ns.ToggleOptions() end },
        { "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", T("Chat kopieren", "Copy chat"),
            function() ns.ShowCopyChat() end },
        { "Interface\\GossipFrame\\GossipGossipIcon", T("Kanäle", "Channels"),
            function() if ToggleChannelFrame then ToggleChannelFrame() end end },
        { "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up", T("Zum Ende springen", "Jump to the end"),
            function() ns.SelectedChatFrame():ScrollToBottom() end },
    }
    local prev
    toolbar.iconWidth = 0
    for _, def in ipairs(buttons) do
        local b = ToolButton(toolbar, def[1], def[2], def[3])
        if def[4] == "lock" then
            toolbar.lockButton = b
            b.icon:SetPoint("TOPLEFT", 1, -1) -- Schloss-Symbol etwas groesser
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        end
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -TOOL_GAP, 0) else b:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0) end
        prev = b
        toolbar.iconWidth = toolbar.iconWidth + TOOL_SIZE + (toolbar.iconWidth > 0 and TOOL_GAP or 0)
    end
    toolbar.lastIcon = prev
    -- Reiter "IM" (Messenger) links neben den Knoepfen
    if ns.CreateIMTab then
        toolbar.imTab = ns.CreateIMTab(toolbar)
        toolbar.imTab:SetPoint("RIGHT", prev, "LEFT", -6, 0)
    end
end

-- Breite der Knopfleiste (mit IM-Reiter, falls der Messenger an ist)
local function ToolbarWidth()
    if not toolbar or not toolbar:IsShown() then return 0 end
    local w = toolbar.iconWidth
    if toolbar.imTab and toolbar.imTab:IsShown() then w = w + 6 + toolbar.imTab:GetWidth() end
    return w
end

-- Blizzards Reiterleiste rechts um die Knopfleiste kuerzen
local function ApplyDockSpace()
    local dock = _G.GENERAL_CHAT_DOCK
    local primary = dock and (dock.primary or ns.MainChatFrame())
    if not (dock and primary and primary.Background) then return end
    local space = ToolbarWidth()
    if space > 0 then space = space + 10 end
    dock:SetPoint("BOTTOMRIGHT", primary.Background, "TOPRIGHT", -space, 0)
    if _G.FCFDock_SetDirty then _G.FCFDock_SetDirty(dock) end
end
ns.ApplyDockSpace = ApplyDockSpace

local function ApplyToolbar()
    BuildToolbar()
    if not toolbar then return end
    toolbar:SetShown(ns.GetDB().toolbar and true or false)
    if toolbar.imTab then toolbar.imTab:SetShown(ns.GetDB().messenger and true or false) end
    toolbar:SetWidth(math.max(1, ToolbarWidth()))
    ApplyDockSpace()
    if ns.UpdateLockButton then ns.UpdateLockButton() end
end

-- Schloss-Symbol: zu = gesperrt, offen = entsperrt (offen leuchtet gold)
function ns.UpdateLockButton()
    local b = toolbar and toolbar.lockButton
    if not b then return end
    local locked = ns.IsLocked()
    b.icon:SetTexture(locked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
    if locked then
        b:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    else
        b:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    end
end

---------------------------------------------------------------------------
-- Alles anwenden
---------------------------------------------------------------------------
local function SkinFrame(frame)
    if not skinned[frame] then
        skinned[frame] = true
        CreateBackdrop(frame)
        -- Blizzards Hintergrund unsichtbar (unsere Flaeche ersetzt ihn); FCF_SetWindowAlpha setzt ihn
        -- immer wieder – die Absicherung in UI.HideBlizzard nimmt das zurueck
        for _, key in ipairs(_G.CHAT_FRAME_TEXTURES or {}) do
            local tex = _G[frame:GetName() .. key]
            if tex then UI.HideBlizzard(tex, { children = false }) end
        end
        SkinTab(frame)
        SkinEditBox(frame)
    end
    UpdateBackdrop(frame)
    ApplyInput(frame)
    ApplySideButtons(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    if tab then
        ApplyTabArt(tab)
        UpdateTabLook(tab)
    end
    local edit = frame.editBox or _G[frame:GetName() .. "EditBox"]
    if edit then
        ApplyEditArt(edit)
        UpdateEditLook(edit)
        ns.UpdateEditVisibility(edit)
    end
end

function ns.ApplySkin()
    ns.ForEachChatFrame(SkinFrame)
    ApplyToolbar()
    local imInput = _G.ForeverChatMessengerInput
    if imInput and imInput.UpdateAlpha then imInput:UpdateAlpha() end
end

function ns.SetupSkin()
    ns.ApplySkin()
    -- Auswahl/Farben der Reiter: nach Blizzards eigener Aktualisierung unseren Stil setzen
    if _G.FCFTab_UpdateColors then
        hooksecurefunc("FCFTab_UpdateColors", function(tab, selected) UpdateTabLook(tab, selected) end)
    end
    -- neue Fenster (z. B. Fluestern in eigenem Reiter)
    for _, fn in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow" }) do
        if _G[fn] then hooksecurefunc(fn, function() C_Timer.After(0, ns.ApplySkin) end) end
    end
    -- Blizzard setzt die Reiterleiste beim Wechsel des Hauptfensters neu: Platz fuer die Knopfleiste erneut lassen
    if _G.FCFDock_SetPrimary then hooksecurefunc("FCFDock_SetPrimary", function() ApplyDockSpace() end) end
    -- Klick auf einen Blizzard-Reiter beendet die Messenger-Ansicht
    if _G.FCF_Tab_OnClick then
        hooksecurefunc("FCF_Tab_OnClick", function(_, button)
            if button ~= "RightButton" and ns.HideIM then ns.HideIM() end
        end)
    end
end

-- Textgroesse aller Chatfenster (Blizzards eigene Einstellung, FCF_SetChatWindowFontSize speichert sie)
function ns.GetFontSize()
    local _, size = ns.MainChatFrame():GetFont()
    return math.floor((size or 14) + 0.5)
end

function ns.SetFontSize(size)
    if not _G.FCF_SetChatWindowFontSize then return end
    ns.ForEachChatFrame(function(frame) _G.FCF_SetChatWindowFontSize(nil, frame, size) end)
    if ns.UpdateIMFont then ns.UpdateIMFont() end
end

-- alle Reiter neu einfaerben (z. B. wenn der Messenger auf- oder zugeht)
function ns.UpdateAllTabLooks()
    ns.ForEachChatFrame(function(frame)
        local tab = _G[frame:GetName() .. "Tab"]
        if tab then UpdateTabLook(tab) end
    end)
end

---------------------------------------------------------------------------
-- Sperren: Blizzards Sperre aller Chatfenster (verhindert Ziehen/Groesse aendern von Zusatzfenstern).
-- Den Hauptchat verschiebt man im Bearbeitungsmodus. Blizzard speichert die Sperre selbst – deshalb wird
-- sie nur auf Wunsch des Spielers (Menue, Minimap-Rechtsklick, /fmove) geaendert, nie automatisch.
---------------------------------------------------------------------------
function ns.IsLocked()
    local main = ns.MainChatFrame()
    if main and main.isLocked ~= nil then return main.isLocked and true or false end
    return ns.GetDB().locked and true or false
end

function ns.ApplyLock()
    if not _G.FCF_SetLocked then return end
    local locked = ns.GetDB().locked and true or false
    ns.ForEachChatFrame(function(frame)
        if frame.isLocked ~= locked then _G.FCF_SetLocked(frame, locked) end
    end)
end

local hintShown = false
function ns.SetLocked(locked, silent)
    ns.GetDB().locked = locked and true or false
    ns.ApplyLock()
    if not locked and not hintShown and not silent then
        hintShown = true
        ns.Chat(T("Chatfenster entsperrt. Den Hauptchat verschiebst du im Bearbeitungsmodus (Esc » Bearbeitungsmodus).",
            "Chat windows unlocked. Move the main chat in Edit Mode (Esc » Edit Mode)."))
    end
    if ns.UpdateLockButton then ns.UpdateLockButton() end
    if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Bearbeitungsmodus oeffnen (nur ausserhalb des Kampfes). Rueckgabe: true = geoeffnet
function ns.OpenEditMode()
    if InCombatLockdown() then
        ns.Chat(T("Im Kampf nicht möglich.", "Not possible in combat."))
        return false
    end
    if _G.EditModeManagerFrame and ShowUIPanel then
        ShowUIPanel(_G.EditModeManagerFrame)
        return true
    end
    return false
end

-- Schloss in der Knopfleiste: entsperren oeffnet den Bearbeitungsmodus (Blizzard laesst den Hauptchat nur dort
-- verschieben); schliesst man den Bearbeitungsmodus, wird wieder gesperrt. Hooks/Callbacks des
-- Bearbeitungsmodus loesen in Forever nicht aus – deshalb wird kurz nachgesehen, ob er noch offen ist.
local editWatch
local function WatchEditMode()
    if editWatch then editWatch:Cancel() end
    editWatch = C_Timer.NewTicker(0.25, function()
        local open = _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown()
        if not open then
            editWatch:Cancel()
            editWatch = nil
            if not ns.IsLocked() then ns.SetLocked(true, true) end
        end
    end)
end

function ns.ToggleChatLock()
    if not ns.IsLocked() then
        ns.SetLocked(true, true)
        if _G.EditModeManagerFrame and _G.EditModeManagerFrame:IsShown() and HideUIPanel and not InCombatLockdown() then
            HideUIPanel(_G.EditModeManagerFrame)
        end
        return
    end
    ns.SetLocked(false, true)
    if ns.OpenEditMode() then
        ns.Chat(T("Chat entsperrt: im Bearbeitungsmodus den Chat ziehen. Bearbeitungsmodus schließen = wieder gesperrt.",
            "Chat unlocked: drag the chat in Edit Mode. Closing Edit Mode locks it again."))
        WatchEditMode()
    else
        ns.Chat(T("Zusatzfenster entsperrt. Den Hauptchat verschiebst du nach dem Kampf im Bearbeitungsmodus.",
            "Extra windows unlocked. Move the main chat in Edit Mode after combat."))
    end
end

-- Gemeinsamer Verschiebe-Modus (/fmove): sperrt/entsperrt die Chatfenster mit
if UI.RegisterMovable then
    UI.RegisterMovable(ADDON_NAME, function() return ns.IsLocked() end, function(locked) ns.SetLocked(locked) end)
end

-- Dezente Farben fuer die Chat-Arten (nur auf Knopfdruck; aendert Blizzards Chatfarben, vorher gesichert)
ns.SOFT_COLORS = {
    SAY = { 0.92, 0.92, 0.90 }, YELL = { 0.95, 0.45, 0.42 }, EMOTE = { 0.93, 0.62, 0.38 },
    TEXT_EMOTE = { 0.93, 0.62, 0.38 }, PARTY = { 0.56, 0.74, 0.98 }, PARTY_LEADER = { 0.46, 0.66, 0.98 },
    RAID = { 0.98, 0.64, 0.32 }, RAID_LEADER = { 0.98, 0.52, 0.22 }, RAID_WARNING = { 0.98, 0.36, 0.22 },
    INSTANCE_CHAT = { 0.98, 0.64, 0.32 }, INSTANCE_CHAT_LEADER = { 0.98, 0.52, 0.22 },
    GUILD = { 0.47, 0.84, 0.50 }, OFFICER = { 0.36, 0.70, 0.40 },
    WHISPER = { 0.93, 0.58, 0.93 }, WHISPER_INFORM = { 0.80, 0.50, 0.80 },
    BN_WHISPER = { 0.42, 0.80, 0.95 }, BN_WHISPER_INFORM = { 0.34, 0.68, 0.82 },
    CHANNEL1 = { 0.88, 0.78, 0.62 }, CHANNEL2 = { 0.86, 0.72, 0.56 }, CHANNEL3 = { 0.80, 0.74, 0.62 },
    CHANNEL4 = { 0.76, 0.76, 0.66 }, CHANNEL5 = { 0.72, 0.78, 0.70 },
}

function ns.ApplySoftColors()
    if not _G.ChangeChatColor or not _G.ChatTypeInfo then return end
    local db = ns.GetDB()
    if not db.savedColors then
        db.savedColors = {}
        for key in pairs(ns.SOFT_COLORS) do
            local info = _G.ChatTypeInfo[key]
            if info then db.savedColors[key] = { info.r, info.g, info.b } end
        end
    end
    for key, c in pairs(ns.SOFT_COLORS) do
        if _G.ChatTypeInfo[key] then _G.ChangeChatColor(key, c[1], c[2], c[3]) end
    end
    ns.Chat(T("Dezente Chatfarben übernommen.", "Soft chat colors applied."))
end

function ns.RestoreColors()
    local db = ns.GetDB()
    if not db.savedColors or not _G.ChangeChatColor then
        ns.Chat(T("Keine gesicherten Farben vorhanden.", "No saved colors."))
        return
    end
    for key, c in pairs(db.savedColors) do _G.ChangeChatColor(key, c[1], c[2], c[3]) end
    db.savedColors = nil
    ns.Chat(T("Vorherige Chatfarben wiederhergestellt.", "Previous chat colors restored."))
end
