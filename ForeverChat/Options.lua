-- ForeverChat – Options.lua: Einstellungsfenster und Minimap-Knopf (gemeinsamer Forever-Stil aus ForeverHub)
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T

-- Seite im zentralen Einstellungsfenster von Forever Core (verhält sich wie das bisherige eigene Fenster)
local options = UI.SettingsPanel("ForeverChatOptions", T("ForeverChat – Einstellungen", "ForeverChat – Settings"), 660, 780,
    { key = "ForeverChat", group = UI.SETTINGS_GROUPS.comfort, label = "Chat" })
local loaders = {} -- Funktionen, die beim Oeffnen die aktuellen Werte anzeigen

local function Changed()
    if ns.ApplySkin then ns.ApplySkin() end
end

local function Check(x, y, label, key, after)
    local cb = UI.Check(options, x, y, label, function(checked)
        ns.GetDB()[key] = checked
        if after then after(checked) else Changed() end
    end)
    loaders[#loaders + 1] = function() cb:SetChecked(ns.GetDB()[key] and true or false) end
    return cb
end

local function Slider(x, y, label, key, minV, maxV, step)
    local s = UI.Slider(options, x, y, label, minV, maxV, step, function(v)
        ns.GetDB()[key] = v
        Changed()
    end, { width = 200, unit = " %" })
    loaders[#loaders + 1] = function() s:Load(ns.GetDB()[key]) end
end

-- Auswahlliste: list = { { key, label } }, get()/set(key)
local function Choice(x, y, label, list, get, set, width)
    local fs = UI.Text(options, "label", label)
    fs:SetPoint("TOPLEFT", x, y - 4)
    local b = UI.AddArrow(UI.Button(options, "", width or 170))
    b:SetPoint("TOPLEFT", x, y - 20)
    local function LabelOf(key)
        for _, c in ipairs(list) do if c.key == key then return c.label end end
        return tostring(key)
    end
    b:SetScript("OnClick", function(self)
        UI.ChoiceMenu(self, list, get, function(key)
            set(key)
            self:SetText(LabelOf(get()))
        end)
    end)
    loaders[#loaders + 1] = function() b:SetText(LabelOf(get())) end
    return b
end

local L, R = 18, 340

---------------------------------------------------------------------------
-- linke Spalte
---------------------------------------------------------------------------
UI.Header(options, L, -34, T("Fenster", "Window"), 300)
Slider(L + 2, -58, T("Deckkraft der Fläche", "Window opacity"), "bgAlpha", 0, 100, 5)
Slider(L + 2, -100, T("Deckkraft des Rahmens", "Border opacity"), "borderAlpha", 0, 100, 5)
-- Textgroesse: Blizzards eigene Einstellung je Chatfenster (wird von Blizzard gespeichert, nur auf Wunsch geaendert)
local fontSlider = UI.Slider(options, L + 2, -142, T("Textgröße", "Text size"), 8, 24, 1, function(v)
    ns.SetFontSize(v)
end, { width = 200 })
loaders[#loaders + 1] = function() fontSlider:Load(ns.GetFontSize()) end
Check(L - 4, -184, T("Reiter im Forever-Stil", "Tabs in Forever style"), "styleTabs")
Check(L - 4, -208, T("Eingabefeld im Forever-Stil", "Input box in Forever style"), "styleEditBox")
Check(L + 16, -232, T("nur beim Schreiben", "only while typing"), "autoHideEditBox")
Check(L - 4, -256, T("Blizzard-Knöpfe neben dem Chat ausblenden", "Hide Blizzard buttons next to the chat"), "hideSideButtons")
Check(L - 4, -280, T("Knopfleiste in der Reiterzeile", "Button bar in the tab row"), "toolbar")
Check(L + 16, -304, T("mit „Vorlesen“", "with \"Text to speech\""), "ttsButton")
Check(L - 4, -328, T("„+“-Knopf für eigene Kanäle", "\"+\" button for custom channels"), "channelButton", function()
    if ns.UpdateChannelButton then ns.UpdateChannelButton() end
end)

UI.Header(options, L, -374, T("Position und Sperre", "Position and lock"), 300)
local lockCheck = UI.Check(options, L - 4, -396, T("Chatfenster sperren", "Lock chat windows"), function(checked)
    ns.SetLocked(checked)
end)
loaders[#loaders + 1] = function() lockCheck:SetChecked(ns.IsLocked()) end
-- Hauptchat ganz unten links, solange er im Bearbeitungsmodus nicht verschoben wurde (Skin.lua)
Check(L + 150, -396, T("Ganz unten links", "Bottom left corner"), "chatCorner", function() if ns.PlaceChatCorner then ns.PlaceChatCorner() end end)
local editBtn = UI.Button(options, T("Im Bearbeitungsmodus verschieben", "Move in Edit Mode"), 230, function()
    options:Hide()
    ns.OpenEditMode()
end)
editBtn:SetPoint("TOPLEFT", L, -424)
UI.Hint(options, L + 2, -452, 300, T("Den Hauptchat verwaltet Blizzards Bearbeitungsmodus (Position und Größe). "
    .. "Entsperrte Zusatzfenster lassen sich am Reiter ziehen.",
    "Blizzard's Edit Mode manages the main chat (position and size). Unlocked extra windows can be dragged by their tab."))

UI.Header(options, L, -514, T("Eingabe", "Input"), 300)
Check(L - 4, -536, T("Pfeiltasten blättern im Verlauf (ohne Alt)", "Arrow keys browse history (no Alt)"), "arrowHistory")
Check(L - 4, -560, T("Umschalt + Mausrad: ganz nach oben/unten", "Shift + mouse wheel: jump to top/bottom"), "shiftScroll")

UI.Header(options, L, -604, T("Instant Messaging", "Instant messaging"), 300)
Check(L - 4, -626, T("Reiter „IM“: je Person ein Unterreiter", "“IM” tab: one sub-tab per person"), "messenger", function(on)
    if not on and ns.HideIM then ns.HideIM() end
    Changed()
end)
Check(L + 16, -650, T("Flüstern zusätzlich im normalen Chat", "Also show whispers in the normal chat"), "whispersInMain")
UI.Hint(options, L + 2, -676, 300, T("Im IM-Reiter schreibt die Eingabezeile (Enter) an die gewählte Person. "
    .. "/r kennt Absender nur, wenn Flüstern auch im normalen Chat steht.",
    "In the IM tab the input line (Enter) writes to the selected person. /r only knows senders shown in the normal chat."))

---------------------------------------------------------------------------
-- rechte Spalte
---------------------------------------------------------------------------
UI.Header(options, R, -34, T("Spielernamen", "Player names"), 300)
Check(R - 4, -56, T("Klassenfarben", "Class colors"), "classColors")
Check(R - 4, -80, T("Stufe vor dem Namen (wenn bekannt)", "Level before the name (if known)"), "showLevel")
Check(R + 16, -104, T("nicht bei Höchststufe", "not at max level"), "hideMaxLevel")
UI.Hint(options, R + 2, -130, 300, T("Stufen kennt ForeverChat von Gruppe, Gilde, Freunden, /wer, Ziel und Mauszeiger.",
    "ForeverChat learns levels from group, guild, friends, /who, target and mouseover."))

UI.Header(options, R, -182, T("Nachrichten", "Messages"), 300)
Choice(R + 2, -202, T("Kanalnamen", "Channel names"), {
    { key = "FULL", label = T("Voll: [2. Handel - Stadt]", "Full: [2. Trade - City]") },
    { key = "SHORT", label = T("Kurz: [2. Handel]", "Short: [2. Trade]") },
    { key = "NUMBER", label = T("Nur Nummer: [2]", "Number only: [2]") },
}, function() return ns.GetDB().channelNames end, function(key) ns.GetDB().channelNames = key end, 220)
Check(R - 4, -254, T("Webadressen anklickbar (zum Kopieren)", "Clickable web addresses (to copy)"), "urls")
Check(R - 4, -278, T("Erwähnungen deines Namens hervorheben", "Highlight mentions of your name"), "mention")
Check(R + 16, -302, T("mit leisem Ton", "with a soft sound"), "mentionSound")

-- Zeitstempel: Blizzards eigene Einstellung (wirkt nach /reload; ForeverChat aendert sie nur auf Wunsch)
local STAMPS = {
    { key = "none", label = T("Keine", "None") },
    { key = "%H:%M ", label = "15:27" },
    { key = "%H:%M:%S ", label = "15:27:32" },
    { key = "%I:%M %p ", label = "03:27 PM" },
}
Choice(R + 2, -328, T("Zeitstempel (nach /reload)", "Timestamps (after /reload)"), STAMPS,
    function() return GetCVar and GetCVar("showTimestamps") or "none" end,
    function(key) if SetCVar then SetCVar("showTimestamps", key) end end, 220)

UI.Header(options, R, -396, T("Farben", "Colors"), 300)
UI.Hint(options, R + 2, -418, 300, T("Ändert Blizzards Chatfarben (vorher gesichert, jederzeit zurücksetzbar).",
    "Changes Blizzard's chat colors (saved first, can be restored anytime)."))
local soft = UI.Button(options, T("Dezente Farben übernehmen", "Apply soft colors"), 200, function() ns.ApplySoftColors() end)
soft:SetPoint("TOPLEFT", R, -448)
local restore = UI.Button(options, T("Vorherige Farben", "Previous colors"), 150, function() ns.RestoreColors() end)
restore:SetPoint("TOPLEFT", R, -476)

local hint = UI.Hint(options, nil, nil, 620, T("/fchat öffnet dieses Fenster · /fchat copy kopiert den Chat · Prototyp",
    "/fchat opens this window · /fchat copy copies the chat · prototype"))
hint:SetPoint("BOTTOMLEFT", 18, 16)

options:SetScript("OnShow", function()
    for _, load in ipairs(loaders) do load() end
end)

function ns.ToggleOptions() options:SetShown(not options:IsShown()) end
function ns.RefreshOptions()
    if options:IsShown() then for _, load in ipairs(loaders) do load() end end
end

---------------------------------------------------------------------------
-- Minimap-Knopf (gemeinsame Vorlage; ab zwei Forever-Addons im Sammelknopf)
---------------------------------------------------------------------------
function ns.SetupOptions()
    if ns.minimapButton then return end
    ns.minimapButton = UI.MinimapButton({
        name = "ForeverChatMinimapButton",
        icon = "Interface\\AddOns\\ForeverChat\\Media\\ForeverChat",
        title = "ForeverChat",
        angle = function() return ns.GetDB().minimapAngle end,
        setAngle = function(a) ns.GetDB().minimapAngle = a end,
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then ns.ShowCopyChat() else ns.ToggleOptions() end
        end,
        lines = function()
            return { T("Linksklick: Einstellungen", "Left-click: settings"),
                     T("Rechtsklick: Chat kopieren", "Right-click: copy chat") }
        end,
    })
end
