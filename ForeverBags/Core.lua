local addonName, ns = ...

-- ForeverBags: alle Taschen in einem schlanken Fenster im Forever-Stil.
-- Core.lua: Standardwerte, Start, Chatbefehl, Minimap-Knopf, Anbindung an den Hub (Profile).

local L = ns.L
local UI = ForeverHub.UI

ns.defaults = {
    replaceBlizzard = true, -- Blizzards Taschenfenster ersetzen (B, Rucksack-Knopf, Händler usw. öffnen dann dieses)
    -- (kein Sperren: das Taschenfenster lässt sich an der Titelleiste immer verschieben – wie Blizzards Taschen)
    showBagBar = false,     -- Leiste mit den angelegten Taschen im Fenster (Knopf in der Werkzeugzeile)
    separateBags = false,   -- jede Tasche in eigener Reihe, dezent getrennt (feine Linie)
    pos = nil,            -- { x, y }: untere rechte Ecke ab der unteren rechten Bildschirmecke; nil = Standard
    columns = 10,           -- Taschenplätze pro Reihe
    spacing = 2,            -- Abstand zwischen den Plätzen (px)
    qualityBorder = true,   -- Rand in Qualitätsfarbe (grün, blau, episch …)
    highlightNew = true,    -- neu erhaltene Gegenstände leuchten, bis man mit der Maus darüberfährt
    openAtCursor = true,    -- beim Öffnen an der Mausposition (beim Händler: unter ForeverVendor / neben dem Händler)
    reagentColor = { 0.25, 0.75, 0.55 }, -- Rand der Plätze in der Reagenzientasche
    replaceBank = true,     -- eigenes Bankfenster beim Bankier
    bankColumns = 14,
    replaceGuildBank = true, -- eigenes Gildenbankfenster
    tooltipCounts = true,   -- im Gegenstands-Tooltip: wie viele jeder Charakter hat
    currencies = {},        -- [Währungs-ID] = true: in der Fußzeile zeigen (Rechtsklick auf die Fußzeile)
    currencyInit = false,   -- beim ersten Mal Blizzards "im Rucksack anzeigen" übernehmen
    showMinimapButton = true,
    minimapAngle = 235,
}

-- Fehlende Werte aus den Standardwerten ergänzen (Tabellen kopieren, damit die Standardwerte unverändert bleiben)
local function FillDefaults()
    for key, value in pairs(ns.defaults) do
        if ForeverBagsDB[key] == nil then
            ForeverBagsDB[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
end

function ns.Print(text)
    UI.Chat("ForeverBags", text)
end

---------------------------------------------------------------------------
-- Minimap-Knopf (gemeinsame Vorlage aus dem Hub; ab zwei Forever-Addons im Sammelknopf)
---------------------------------------------------------------------------
local minimapButton
function ns.UpdateMinimapButton()
    if minimapButton then minimapButton:SetShown(ns.db.showMinimapButton) end
end

local function CreateMinimapButton()
    if minimapButton or not Minimap then return end
    minimapButton = UI.MinimapButton({
        name = "ForeverBagsMinimapButton",
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        texCoord = { 0.08, 0.92, 0.08, 0.92 },
        title = L("ADDON_NAME"),
        angle = function() return ns.db.minimapAngle end,
        setAngle = function(angle) ns.db.minimapAngle = angle end,
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                ns.ToggleBags()
            else
                ns.ToggleOptions()
            end
        end,
        lines = function() return { L("TIP_LEFT"), L("TIP_RIGHT") } end,
    })
    ns.UpdateMinimapButton()
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        ForeverBagsDB = ForeverBagsDB or {}
        FillDefaults()
        ns.db = ForeverBagsDB
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Nochmals ergänzen: ForeverCore schreibt beim Laden das Profil in dieselbe Tabelle
        FillDefaults()
        CreateMinimapButton()
        if ns.SetupBags then ns.SetupBags() end
    end
end)

---------------------------------------------------------------------------
-- Chatbefehl: /fbags (Menü), /fbags bags (Taschen), /fbags reset (Position)
---------------------------------------------------------------------------
SLASH_FOREVERBAGS1 = "/fbags"
SLASH_FOREVERBAGS2 = "/foreverbags"
SlashCmdList.FOREVERBAGS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "bags" or msg == "open" then
        ns.ToggleBags()
    elseif msg == "reset" then
        ns.ResetPosition()
    elseif msg == "bankcheck" then
        if ns.BankCheck then ns.BankCheck() end
    else
        ns.ToggleOptions()
    end
end

---------------------------------------------------------------------------
-- Gemeinsame Einstellungs-Verwaltung (ForeverCore): Profile je Charakter, Zurücksetzen, Export/Import
---------------------------------------------------------------------------
UI.RegisterSettings({ addon = "ForeverBags", sv = "ForeverBagsDB", defaults = ns.defaults, version = 1,
    global = { "showMinimapButton" } })
