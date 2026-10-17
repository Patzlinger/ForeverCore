local addonName, ns = ...

-- Bags.lua: das Taschenfenster.
-- Aufbau: ein Fenster im Forever-Stil (UI.Window), darin für jede Tasche ein unsichtbarer Rahmen mit der
-- Taschen-Nummer (SetID) und für jeden Platz Blizzards eigener Taschenplatz-Knopf
-- ("ContainerFrameItemButtonTemplate", ID = Platz). So bleibt alles, was Blizzard daran erledigt, erhalten:
-- Benutzen (Rechtsklick, auch im Kampf), Ziehen, Verkaufen beim Händler, Tooltip, Gegenstand verlinken.
-- Wir zeichnen nur Symbol, Anzahl, Qualitätsrand, Abklingzeit und Suchtreffer neu.
--
-- Blizzards Taschenfenster: ersetzt (Einstellung "replaceBlizzard"). Ihr Öffnen hören wir über hooksecurefunc
-- (ToggleAllBags, OpenAllBags, ToggleBackpack …) mit und öffnen dann unser Fenster; Blizzards Fenster werden in
-- OnShow per :Hide() wieder zugemacht. Das ist eine dokumentierte Ausnahme der Taint-Regel (CLAUDE.md,
-- Abschnitt 4): Blizzards Taschenfenster sind keine geschützten Rahmen; ein Taschen-Addon kommt daran nicht vorbei.

local L = ns.L
local UI = ForeverHub.UI
local C = UI.COLOR

local SLOT = 37           -- Kantenlänge eines Taschenplatzes (wie bei Blizzard)
local PAD = 8             -- Innenabstand des Fensters
local HEADER = 27         -- Titelleiste von UI.Window (26 + 1 px Rand)
local TOOLBAR = 28        -- Zeile mit Suche und Sortieren
local FOOTER = 24         -- Zeile mit freien Plätzen und Gold
local DEFAULT_POS = { -20, 120 } -- untere rechte Ecke: 20 px vom rechten, 120 px vom unteren Rand

-- Taschen in Anzeige-Reihenfolge: Rucksack, vier Taschen, Reagenzientasche (falls es sie gibt)
local function BagList()
    local list = { 0, 1, 2, 3, 4 }
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if reagent then list[#list + 1] = reagent end
    return list
end

local window, content, searchBox, freeText, moneyText
local bagFrames = {}   -- [Tasche] = unsichtbarer Rahmen mit SetID(Tasche)
local buttons = {}     -- [Tasche][Platz] = Knopf
local createPending = false

---------------------------------------------------------------------------
-- Ein Taschenplatz
---------------------------------------------------------------------------
local function StyleSlot(button)
    -- Blizzards Platz-Rahmen ausblenden, dafür dunkle Fläche + 1-px-Rand im Forever-Stil
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    local edge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetFrameLevel(button:GetFrameLevel() + 2)
    edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    edge:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    edge:EnableMouse(false)
    button.fbagsEdge = edge
    local icon = button.icon or button.Icon or _G[button:GetName() .. "IconTexture"]
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    button:HookScript("OnEnter", function(self)
        self.fbagsEdge:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    end)
    button:HookScript("OnLeave", function(self)
        self.fbagsEdge:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
end

local function CreateSlot(bag, slot)
    local parent = bagFrames[bag]
    if not parent then
        parent = CreateFrame("Frame", nil, content)
        parent:SetAllPoints(content)
        parent:SetID(bag)
        bagFrames[bag] = parent
    end
    local button = CreateFrame("ItemButton", "ForeverBagsSlot" .. bag .. "_" .. slot, parent,
        "ContainerFrameItemButtonTemplate")
    button:SetID(slot)
    if button.SetBagID then pcall(button.SetBagID, button, bag) end
    button:SetSize(SLOT, SLOT)
    StyleSlot(button)
    buttons[bag] = buttons[bag] or {}
    buttons[bag][slot] = button
    return button
end

-- Anzeige eines Platzes aus den Taschendaten (geht auch im Kampf: keine geschützten Änderungen)
local function UpdateSlot(button, bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local texture = info and info.iconFileID
    SetItemButtonTexture(button, texture)
    SetItemButtonCount(button, info and info.stackCount or 0)
    SetItemButtonDesaturated(button, info and info.isLocked)
    -- Qualitätsrand (Blizzards IconBorder), auf Wunsch aus
    if button.SetItemButtonQuality then
        pcall(button.SetItemButtonQuality, button, info and info.quality, info and info.hyperlink)
    end
    if button.IconBorder and not ns.db.qualityBorder then button.IconBorder:Hide() end
    -- Suchtreffer: Blizzards Suche markiert nicht passende Gegenstände (isFiltered)
    local filtered = info and info.isFiltered
    if button.SetMatchesSearch then
        button:SetMatchesSearch(not filtered)
    else
        button:SetAlpha(filtered and 0.3 or 1)
    end
    -- Neu erhaltene Gegenstände
    local isNew = ns.db.highlightNew and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot)
    if button.NewItemTexture then button.NewItemTexture:SetShown(isNew and true or false) end
    -- Abklingzeit
    if button.UpdateCooldown then pcall(button.UpdateCooldown, button, texture) end
    button:Show()
end

---------------------------------------------------------------------------
-- Anordnung
---------------------------------------------------------------------------
local function SlotCount(bag)
    return C_Container.GetContainerNumSlots(bag) or 0
end

-- Fehlende Plätze anlegen (nur außerhalb des Kampfes: die Vorlage enthält geschützte Teile)
local function EnsureSlots()
    if InCombatLockdown() then
        if not createPending then
            createPending = true
            ns.Print(L("COMBAT_LATER"))
        end
        return false
    end
    createPending = false
    for _, bag in ipairs(BagList()) do
        for slot = 1, SlotCount(bag) do
            if not (buttons[bag] and buttons[bag][slot]) then CreateSlot(bag, slot) end
        end
    end
    return true
end

function ns.LayoutBags()
    if not window then return end
    local complete = EnsureSlots()
    local db = ns.db
    local columns = math.max(4, db.columns or 10)
    local gap = math.max(0, db.spacing or 2)
    local index, used, total = 0, 0, 0
    for _, bag in ipairs(BagList()) do
        local count = SlotCount(bag)
        for slot, button in pairs(buttons[bag] or {}) do
            if slot > count then button:Hide() end -- Tasche getauscht: kleinere Tasche
        end
        for slot = 1, count do
            local button = buttons[bag] and buttons[bag][slot]
            if button then
                local col, row = index % columns, math.floor(index / columns)
                if not InCombatLockdown() then
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SLOT + gap), -row * (SLOT + gap))
                end
                UpdateSlot(button, bag, slot)
                index = index + 1
                total = total + 1
                if C_Container.GetContainerItemID(bag, slot) then used = used + 1 end
            end
        end
    end
    local rows = math.max(1, math.ceil(index / columns))
    local width = columns * SLOT + (columns - 1) * gap
    local height = rows * SLOT + (rows - 1) * gap
    if not InCombatLockdown() then
        content:SetSize(width, height)
        window:SetSize(width + 2 * PAD, HEADER + TOOLBAR + height + FOOTER + 2 * PAD)
    end
    freeText:SetText(L("FREE_SLOTS", total - used, total))
    moneyText:SetText(GetMoneyString and GetMoneyString(GetMoney(), true) or tostring(GetMoney()))
    return complete
end

-- Nur die Anzeige (Daten geändert, Anordnung gleich)
local function RefreshSlots()
    if not window or not window:IsShown() then return end
    ns.LayoutBags()
end

---------------------------------------------------------------------------
-- Position, Verschieben (mit Einrasten an anderen Forever-Rahmen), Sperren
---------------------------------------------------------------------------
local function RestorePosition()
    local pos = ns.db.pos or DEFAULT_POS
    window:ClearAllPoints()
    window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", pos[1], pos[2])
end

local function SavePosition()
    local right, bottom = window:GetRight(), window:GetBottom()
    if not (right and bottom) then return end
    local s = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ns.db.pos = { UI.Round(right * s - UIParent:GetRight()), UI.Round(bottom * s) }
    RestorePosition()
end

function ns.ResetPosition()
    ns.db.pos = nil
    if window then RestorePosition() end
    ns.Print(L("POS_RESET"))
end

local function StartDrag()
    if ns.db.locked or InCombatLockdown() then return end
    window.fbagsMoving = true
    window:StartMoving()
    if UI.BeginDrag then UI.BeginDrag(window, { snap = true }) end
end

local function StopDrag()
    if not window.fbagsMoving then return end
    window.fbagsMoving = nil
    window:StopMovingOrSizing()
    local dx, dy = 0, 0
    if UI.EndDrag then dx, dy = UI.EndDrag() end
    local left, top = window:GetLeft(), window:GetTop()
    if (dx ~= 0 or dy ~= 0) and left and top then
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + dx, top + dy)
    end
    SavePosition()
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local function CreateWindow()
    window = UI.Window("ForeverBagsFrame", L("WINDOW_TITLE"), 400, 300)
    window:SetFrameStrata("HIGH") -- über den Leisten, unter Menüs und Dialogen
    -- Ziehen nur an der Titelleiste und nur entsperrt; mit Einrasten (UI.Window bringt einfaches Ziehen mit)
    window:SetScript("OnDragStart", nil)
    window:SetScript("OnDragStop", nil)
    window.header:SetScript("OnDragStart", StartDrag)
    window.header:SetScript("OnDragStop", StopDrag)
    if UI.AddMover then UI.AddMover(window) end

    -- Suche (Blizzards Taschensuche: gilt wie bei Blizzard auch für die Bank)
    searchBox = UI.EditBox(window, 180, 20)
    searchBox:SetPoint("TOPLEFT", PAD, -HEADER - 4)
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 7, 0)
    placeholder:SetText(L("SEARCH"))
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "" and not self:HasFocus())
        if C_Container.SetItemSearch then C_Container.SetItemSearch(text) end
    end)
    searchBox:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self) placeholder:SetShown((self:GetText() or "") == "") end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- Sortieren (Blizzards Aufräumen)
    local sort = UI.Button(window, L("SORT"), 80, function()
        if C_Container.SortBags then C_Container.SortBags() end
    end)
    sort:SetPoint("TOPRIGHT", -PAD, -HEADER - 4)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L("TIP_SORT"))
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", GameTooltip_Hide)

    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", PAD, -HEADER - TOOLBAR)
    content:SetSize(1, 1)

    -- Fußzeile: freie Plätze links, Gold rechts (rechte untere Ecke bleibt frei für den Größen-Griff)
    freeText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("BOTTOMLEFT", PAD, PAD + 2)
    moneyText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moneyText:SetPoint("BOTTOMRIGHT", -PAD - 16, PAD + 2)
    moneyText:SetJustifyH("RIGHT")

    -- HookScript statt SetScript: der Hub hängt eigene Dinge an OnShow (Fenster-Stapel, Größen-Griff)
    window:HookScript("OnShow", function()
        ns.LayoutBags()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    end)
    window:HookScript("OnHide", function()
        if window.fbagsMoving then StopDrag() end
        searchBox:ClearFocus()
        -- "neu" gilt als gesehen, sobald man die Taschen einmal offen hatte
        if C_NewItems and C_NewItems.ClearAll then C_NewItems.ClearAll() end
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_CLOSE then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
    end)
    RestorePosition()
end

function ns.OpenBags()
    if not window then return end
    if not window:IsShown() then window:Show() end
end

function ns.CloseBags()
    if window and window:IsShown() then window:Hide() end
end

function ns.ToggleBags()
    if not window then return end
    window:SetShown(not window:IsShown())
end

---------------------------------------------------------------------------
-- Blizzards Taschen ersetzen
---------------------------------------------------------------------------
local function Replacing() return ns.db and ns.db.replaceBlizzard end

-- Blizzards Taschenfenster sofort wieder zumachen, wenn sie aufgehen (siehe Erklärung am Dateianfang)
local function KeepClosed(frame)
    if not frame or frame.fbagsHooked then return end
    frame.fbagsHooked = true
    frame:HookScript("OnShow", function(self)
        if Replacing() then self:Hide() end
    end)
end

local function HookBlizzard()
    KeepClosed(_G.ContainerFrameCombinedBags)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do KeepClosed(_G["ContainerFrame" .. i]) end
    -- Öffnen/Schließen: Blizzard ruft diese Funktionen bei B, Rucksack-Knopf, Händler, Post, Bank …
    -- (nur mitgehört; Blizzards eigene Fenster gehen dabei kurz auf und werden oben wieder zugemacht).
    -- Blizzards "Umschalten" ruft intern selbst "Öffnen"/"Schließen" auf – alles im selben Bild. Darum zählt der
    -- Zustand unseres Fensters vom Beginn dieses Bildes: Umschalten dreht genau den einmal um.
    local stampTime, stampShown
    local function Remember()
        local now = GetTime()
        if stampTime ~= now then
            stampTime, stampShown = now, window:IsShown()
        end
    end
    local function Hook(name, fn)
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() if Replacing() then Remember() fn() end end)
        end
    end
    local function Toggle() window:SetShown(not stampShown) end
    Hook("ToggleAllBags", Toggle)
    Hook("ToggleBackpack", Toggle)
    Hook("ToggleBag", Toggle)
    Hook("OpenAllBags", ns.OpenBags)
    Hook("OpenBackpack", ns.OpenBags)
    Hook("OpenBag", ns.OpenBags)
    Hook("CloseAllBags", ns.CloseBags)
    Hook("CloseBackpack", ns.CloseBags)
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local updateQueued = false
local function QueueRefresh()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.05, function()
        updateQueued = false
        RefreshSlots()
    end)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if createPending and window and window:IsShown() then ns.LayoutBags() end
        return
    end
    QueueRefresh()
end)

function ns.SetupBags()
    if window then return end
    CreateWindow()
    HookBlizzard()
    EnsureSlots() -- alle Plätze gleich beim Login anlegen: dann muss im Kampf nichts Neues entstehen
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_MONEY",
        "INVENTORY_SEARCH_UPDATE", "BAG_NEW_ITEMS_UPDATED", "PLAYER_REGEN_ENABLED", "BAG_CONTAINER_UPDATE" }) do
        pcall(events.RegisterEvent, events, event)
    end
end
