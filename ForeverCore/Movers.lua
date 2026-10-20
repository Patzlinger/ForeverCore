-- ForeverCore – Movers.lua: Blizzard-Fenster verschiebbar (Charakter, Händler, Post, Berufe, Talente, Auktionshaus …).
-- Fenster an einer freien Stelle (oder an der Titelleiste) mit der linken Maustaste ziehen. Die Lage wird für den
-- ganzen Account gemerkt (ForeverHubDB.blizzPos) und beim nächsten Öffnen wieder hergestellt; zurücksetzen im
-- Hub-Fenster ("Fensterpositionen zurücksetzen"). Aus: ForeverHubDB.blizzMove = false.
-- Nur Lage und Ziehen: Inhalte und Funktionen der Fenster bleiben Blizzards eigene. Geschützte Fenster werden im
-- Kampf nicht bewegt. Fenster, die ein Forever-Addon selbst ersetzt oder führt (Taschen, Bank, Weltkarte mit
-- Questlog, Spielmenü), sind bewusst nicht dabei.
local hub = _G.ForeverHub
if type(hub) ~= "table" or type(hub.UI) ~= "table" then return end
local UI = hub.UI

-- [Blizzard-Addon] = Fenster; "base" = immer geladen, sonst erst, wenn Blizzard das Addon lädt.
-- (Namen aus Retail und Classic – was es im Forever-Client nicht gibt, wird einfach übersprungen)
local FRAMES = {
    base = { "CharacterFrame", "SpellBookFrame", "FriendsFrame", "PVEFrame", "LFGParentFrame", "MerchantFrame",
        "MailFrame", "OpenMailFrame", "GossipFrame", "QuestFrame", "QuestLogPopupDetailFrame", "TaxiFrame",
        "TradeFrame", "DressUpFrame", "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame",
        "PetStableFrame", "HelpFrame", "AddonList", "SettingsPanel", "ChatConfigFrame", "RaidParentFrame" },
    Blizzard_AuctionHouseUI = { "AuctionHouseFrame" },
    Blizzard_AuctionUI = { "AuctionFrame" },
    Blizzard_Professions = { "ProfessionsFrame" },
    Blizzard_TradeSkillUI = { "TradeSkillFrame" },
    Blizzard_CraftUI = { "CraftFrame" },
    Blizzard_TrainerUI = { "ClassTrainerFrame" },
    Blizzard_InspectUI = { "InspectFrame" },
    Blizzard_MacroUI = { "MacroFrame" },
    Blizzard_Communities = { "CommunitiesFrame" },
    Blizzard_GuildUI = { "GuildFrame" },
    Blizzard_PlayerSpells = { "PlayerSpellsFrame" },
    Blizzard_TalentUI = { "PlayerTalentFrame", "TalentFrame" },
    Blizzard_AchievementUI = { "AchievementFrame" },
    Blizzard_Collections = { "CollectionsJournal" },
    Blizzard_EncounterJournal = { "EncounterJournal" },
    Blizzard_Calendar = { "CalendarFrame" },
    Blizzard_ItemSocketingUI = { "ItemSocketingFrame" },
    Blizzard_FlightMap = { "FlightMapFrame" },
    Blizzard_BindingUI = { "KeyBindingFrame" },
    Blizzard_StableUI = { "StableFrame" },
}

local known = {}   -- [Fenster] = Name (schon verschiebbar gemacht)
local moving

local function DB()
    local db = _G.ForeverHubDB
    if type(db) ~= "table" then return nil end
    if type(db.blizzPos) ~= "table" then db.blizzPos = {} end
    return db
end

function UI.BlizzMoveEnabled()
    local db = DB()
    return not (db and db.blizzMove == false)
end

local function Blocked(frame)
    return InCombatLockdown() and frame:IsProtected()
end

local function Reapply(frame, name)
    local db = DB()
    local pos = db and db.blizzPos[name]
    if type(pos) ~= "table" or not UI.BlizzMoveEnabled() or moving == frame or Blocked(frame) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
end

local function Save(frame, name)
    local db = DB()
    local left, top = frame:GetLeft(), frame:GetTop()
    if db and left and top then db.blizzPos[name] = { math.floor(left + 0.5), math.floor(top + 0.5) } end
end

local function Setup(name)
    local frame = _G[name]
    if type(frame) ~= "table" or not frame.GetObjectType or known[frame] then return end
    known[frame] = name
    if Blocked(frame) then known[frame] = nil return end -- im Kampf nicht anfassen, später nochmal
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    local function StartDrag()
        if not UI.BlizzMoveEnabled() or Blocked(frame) then return end
        moving = frame
        frame:StartMoving()
    end
    local function StopDrag()
        if moving ~= frame then return end
        moving = nil
        frame:StopMovingOrSizing()
        pcall(frame.SetUserPlaced, frame, false) -- Lage merkt sich Forever Core, nicht Blizzards Layout-Datei
        Save(frame, name)
    end
    -- ziehen am Fenster selbst und an seiner Titelleiste (falls sie eigene Mausflächen hat)
    for _, handle in ipairs({ frame, frame.TitleContainer }) do
        if handle and handle.RegisterForDrag then
            handle:EnableMouse(true)
            handle:RegisterForDrag("LeftButton")
            handle:HookScript("OnDragStart", StartDrag)
            handle:HookScript("OnDragStop", StopDrag)
        end
    end
    frame:HookScript("OnHide", StopDrag)
    frame:HookScript("OnShow", function()
        Reapply(frame, name)
        C_Timer.After(0, function() if frame:IsShown() then Reapply(frame, name) end end) -- nach Blizzards Anordnen
    end)
    if frame:IsShown() then Reapply(frame, name) end
end

local function SetupAddon(addon)
    for _, name in ipairs(FRAMES[addon] or {}) do Setup(name) end
end

local function IsLoaded(addon)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    return fn and fn(addon)
end

local function SetupAll()
    SetupAddon("base")
    for addon in pairs(FRAMES) do
        if addon ~= "base" and IsLoaded(addon) then SetupAddon(addon) end
    end
end

-- Blizzard ordnet seine Fenster (links/Mitte/rechts) beim Öffnen anderer Fenster neu: verschobene wieder hinsetzen
if type(_G.UpdateUIPanelPositions) == "function" then
    hooksecurefunc("UpdateUIPanelPositions", function()
        for frame, name in pairs(known) do
            if frame:IsShown() then Reapply(frame, name) end
        end
    end)
end

-- alle gemerkten Lagen vergessen; offene Fenster setzt Blizzard beim nächsten Öffnen wieder an ihren Platz
function UI.ResetBlizzPositions()
    local db = DB()
    if db then db.blizzPos = {} end
    if not InCombatLockdown() and type(_G.UpdateUIPanelPositions) == "function" then
        for frame in pairs(known) do
            if frame:IsShown() then pcall(_G.UpdateUIPanelPositions, frame) end
        end
    end
end

function UI.SetBlizzMove(enabled)
    local db = DB()
    if db then db.blizzMove = (not enabled) and false or nil end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if _G.ForeverHub ~= hub then return end
    local ok, err
    if event == "ADDON_LOADED" then
        if FRAMES[addon] and IsLoggedIn() then ok, err = pcall(SetupAddon, addon) else return end
    else
        ok, err = pcall(SetupAll) -- nach dem Anmelden bzw. nach dem Kampf (dort übersprungene Fenster)
    end
    if not ok and UI.ReportError then UI.ReportError("ForeverCore", "Movers", err) end
end)
