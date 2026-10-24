-- ForeverAlts – Options.lua: Seite im zentralen Einstellungsfenster, Minimap-Knopf und Chatbefehl
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T

local options
local checks = {}

local function Build()
    options = UI.SettingsPanel("ForeverAltsOptions", T("ForeverAlts – Einstellungen", "ForeverAlts – Settings"), 460, 350,
        { key = "ForeverAlts", group = UI.SETTINGS_GROUPS.comfort, label = T("Twink-Übersicht", "Alts") })
    local W = 420
    local function Check(y, label, key)
        local cb = UI.Check(options, 14, y, label, ns.Safe(T("Einstellungen", "Settings"), function(checked)
            ns.GetDB()[key] = checked
            ns.RefreshWindow()
        end))
        checks[#checks + 1] = { cb = cb, key = key }
    end

    UI.Header(options, 18, -40, T("Liste", "List"), W)
    Check(-62, T("Nur Charaktere dieses Realms", "Only characters of this realm"), "sameRealm")
    Check(-86, T("Nur Charaktere meiner Fraktion", "Only characters of my faction"), "sameFaction")
    UI.Hint(options, 22, -114, W - 12, T("Ein Charakter erscheint, sobald er einmal eingeloggt war. Erholung bei anderen " ..
        "Charakteren ist geschätzt (≈) – seit ihrem letzten Login.",
        "A character shows up once it has logged in. Rested XP of other characters is estimated (≈) since their last login."))

    UI.Header(options, 18, -178, T("Mit anderen Forever-Addons", "With other Forever addons"), W)
    Check(-200, T("Twinks bei Quests zeigen (ForeverQuests)", "Show alts on quests (ForeverQuests)"), "questInfo")
    Check(-224, T("\"Herstellbar von\" im Gegenstands-Tooltip", "\"Can be made by\" in item tooltips"), "recipeTooltip")
    UI.Hint(options, 22, -252, W - 12, T("Im Quest-Tooltip und im Hinweis \"Dungeon betreten\": welche Twinks die Quest " ..
        "auch haben. Taschen und Bank der Twinks: Rechtsklick in der Übersicht (ForeverBags).",
        "In the quest tooltip and the \"Entering dungeon\" hint: which alts have the quest too. Bags and bank of your " ..
        "alts: right-click in the overview (ForeverBags)."))

    local open = UI.Button(options, T("Übersicht öffnen", "Open overview"), 150, function() ns.ToggleWindow() end)
    open:SetPoint("BOTTOMLEFT", 14, 14)

    options:HookScript("OnShow", function()
        local db = ns.GetDB()
        for _, c in ipairs(checks) do c.cb:SetChecked(db[c.key] and true or false) end
    end)
end

function ns.ToggleOptions()
    if not options then Build() end
    options:SetShown(not options:IsShown())
end

-- Eintrag im zentralen Einstellungsfenster schon beim Laden (die Seite entsteht erst beim ersten Öffnen)
if UI.RegisterSettingsLink then
    UI.RegisterSettingsLink({ key = "ForeverAlts", group = UI.SETTINGS_GROUPS.comfort, label = T("Twink-Übersicht", "Alts"),
        open = function() ns.ToggleOptions() end })
end

---------------------------------------------------------------------------
-- Minimap-Knopf (gemeinsame Vorlage; ab zwei Forever-Addons im Sammelknopf) und Chatbefehl
---------------------------------------------------------------------------
local mm = UI.MinimapButton({
    name = "ForeverAltsMinimapButton",
    icon = "Interface\\AddOns\\ForeverAlts\\Media\\ForeverAlts", -- eigenes Logo im Stil von Forever Core UI: drei Charaktere
    title = "ForeverAlts",
    angle = function() return ns.GetDB().minimapAngle end,
    setAngle = function(a) ns.GetDB().minimapAngle = a end,
    onClick = ns.Safe("Minimap", function(_, button)
        if button == "RightButton" then ns.ToggleOptions() else ns.ToggleWindow() end
    end),
    lines = function()
        return {
            T("Linksklick: Übersicht der Twinks", "Left-click: alts overview"),
            T("Rechtsklick: Einstellungen", "Right-click: settings"),
        }
    end,
})

-- Tastenkürzel (Bindings.xml): Spielmenü » Tastaturbelegung » AddOns » ForeverAlts
BINDING_HEADER_FOREVERALTS = "ForeverAlts"
BINDING_NAME_FOREVERALTS_TOGGLE = T("Twinks-Übersicht ein/aus", "Toggle alts overview")

SLASH_FOREVERALTS1 = "/falts"
SLASH_FOREVERALTS2 = "/foreveralts"
SlashCmdList["FOREVERALTS"] = ns.Safe(T("Befehl", "Command"), function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "options" or msg == "optionen" then
        ns.ToggleOptions()
    elseif msg == "reiter" or msg == "tab" then
        -- Prüfbefehl: Zustand des Reiters am Berufe-Fenster (ProfessionTab.lua)
        if ns.CheckProfessionTab then ns.CheckProfessionTab() else print("ForeverAlts: ProfessionTab.lua ist nicht geladen (Spiel komplett neu starten)") end
    else
        ns.ToggleWindow()
    end
end)

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if mm and mm.UpdatePosition then mm.UpdatePosition() end
end)

UI.RegisterSettings({ addon = "ForeverAlts", sv = "ForeverAltsDB", defaults = ns.DEFAULTS, version = 1 })
