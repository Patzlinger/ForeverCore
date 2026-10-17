local addonName, ns = ...

-- Bags.lua: das Taschenfenster.
-- Aufbau: ein Fenster im Forever-Stil (UI.Window), darin für jede Tasche ein unsichtbarer Rahmen mit der
-- Taschen-Nummer (SetID) und für jeden Platz Blizzards eigener Taschenplatz-Knopf
-- ("ContainerFrameItemButtonTemplate", ID = Platz). So bleibt alles, was Blizzard daran erledigt, erhalten:
-- Benutzen (Rechtsklick, auch im Kampf), Ziehen, Verkaufen beim Händler, Tooltip, Gegenstand verlinken.
-- Wir zeichnen nur Symbol, Anzahl, Qualitätsrand, Abklingzeit und Suchtreffer neu.
--
-- Ansicht: die eigenen Taschen (echt, benutzbar) oder – nur zum Ansehen – die gespeicherten Taschen bzw. die Bank
-- eines Charakters (Data.lua). Die gespeicherten Plätze sind einfache Knöpfe mit Symbol, Anzahl und Tooltip.
--
-- Blizzards Taschenfenster: ersetzt (Einstellung "replaceBlizzard"). Ihr Öffnen hören wir über hooksecurefunc
-- (ToggleAllBags, OpenAllBags, ToggleBackpack …) mit und öffnen dann unser Fenster; Blizzards Fenster werden in
-- OnShow per :Hide() wieder zugemacht. Das ist eine dokumentierte Ausnahme der Taint-Regel (CLAUDE.md,
-- Abschnitt 4): Blizzards Taschenfenster sind keine geschützten Rahmen; ein Taschen-Addon kommt daran nicht vorbei.

local L = ns.L
local UI = ForeverHub.UI
local C = UI.COLOR

local SLOT = 37           -- Kantenlänge eines Taschenplatzes (wie bei Blizzard)
local BAGSLOT = 26        -- Knöpfe der Taschenleiste
local PAD = 8             -- Innenabstand des Fensters
local HEADER = 27         -- Titelleiste von UI.Window (26 + 1 px Rand)
local TOOLBAR = 28        -- Zeile mit Ansicht, Suche, Taschenleiste, Sortieren
local FOOTER = 24         -- Zeile mit freien Plätzen und Gold
local DEFAULT_POS = { -20, 120 } -- untere rechte Ecke: 20 px vom rechten, 120 px vom unteren Rand
local REAGENT_COLOR = { 0.25, 0.75, 0.55, 1 } -- Rand der Plätze in der Reagenzientasche

local function ReagentBag() return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag end

local window, content, searchBox, freeText, moneyText, viewButton, bagBar
local bagFrames = {}   -- [Tasche] = unsichtbarer Rahmen mit SetID(Tasche)
local buttons = {}     -- [Tasche][Platz] = Knopf (echte Taschen)
local offline = {}     -- Knöpfe der gespeicherten Ansicht (werden wiederverwendet)
local createPending = false
-- Ansicht: nil = eigene Taschen (echt); sonst { key = "Name-Realm", kind = "bags" | "bank" }
local view

local function EdgeColor(bag)
    if bag ~= nil and bag == ReagentBag() then return REAGENT_COLOR end
    return C.border
end

---------------------------------------------------------------------------
-- Ein echter Taschenplatz
---------------------------------------------------------------------------
local function AddForeverLook(button, bag)
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    local edge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetFrameLevel(button:GetFrameLevel() + 2)
    edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    edge:EnableMouse(false)
    button.fbagsEdge = edge
    button.fbagsBag = bag
    edge:SetBackdropBorderColor(unpack(EdgeColor(bag)))
    button:HookScript("OnEnter", function(self)
        self.fbagsEdge:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    end)
    button:HookScript("OnLeave", function(self)
        self.fbagsEdge:SetBackdropBorderColor(unpack(EdgeColor(self.fbagsBag)))
    end)
end

local function StyleSlot(button, bag)
    -- Blizzards Platz-Rahmen ausblenden, dafür dunkle Fläche + 1-px-Rand im Forever-Stil
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    AddForeverLook(button, bag)
    local icon = button.icon or button.Icon or _G[button:GetName() .. "IconTexture"]
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
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
    StyleSlot(button, bag)
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
    -- Neu erhaltene Gegenstände (erst nach dem Login erhaltene – siehe ClearAll beim Einloggen). Blizzards
    -- Leucht-Animationen der Vorlage sonst anhalten, sonst leuchten alle Plätze
    local isNew = ns.db.highlightNew and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot)
    if button.NewItemTexture then button.NewItemTexture:SetShown(isNew and true or false) end
    if not isNew then
        for _, anim in ipairs({ button.newitemglowAnim, button.flashAnim }) do
            if anim and anim.Stop then anim:Stop() end
        end
        if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    end
    -- Abklingzeit
    if button.UpdateCooldown then pcall(button.UpdateCooldown, button, texture) end
    button:Show()
end

---------------------------------------------------------------------------
-- Gespeicherte Ansicht (anderer Charakter oder Bank): einfache Knöpfe, nur zum Ansehen
---------------------------------------------------------------------------
local function OfflineButton(i)
    local b = offline[i]
    if b then return b end
    b = CreateFrame("Button", nil, content)
    b:SetSize(SLOT, SLOT)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.quality = b:CreateTexture(nil, "OVERLAY")
    b.quality:SetAllPoints()
    b.quality:SetTexture("Interface\\Common\\WhiteIconFrame")
    AddForeverLook(b, nil)
    b:HookScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
    -- Shift-Klick: Gegenstand in den Chat verlinken
    b:SetScript("OnClick", function(self) if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end end)
    offline[i] = b
    return b
end

-- passt ein gespeicherter Gegenstand zur Suche? (Name aus dem Link, ohne Groß-/Kleinschreibung)
local function MatchesSearch(link)
    local text = searchBox and strtrim(searchBox:GetText() or ""):lower() or ""
    if text == "" then return true end
    local name = link and link:match("%[(.-)%]")
    return name ~= nil and name:lower():find(text, 1, true) ~= nil
end

local function ShowOffline(entry, columns, gap)
    local containers = view.kind == "bank" and entry.bank or entry.bags
    local index, used, total = 0, 0, 0
    local ids = view.kind == "bank" and ns.BankIDs() or ns.BagIDs()
    for _, bag in ipairs(ids) do
        local c = containers and containers[bag]
        for slot = 1, (c and c.size or 0) do
            index = index + 1
            total = total + 1
            local b = OfflineButton(index)
            local item = c[slot]
            local col, row = (index - 1) % columns, math.floor((index - 1) / columns)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SLOT + gap), -row * (SLOT + gap))
            b.fbagsBag = bag
            b.fbagsEdge:SetBackdropBorderColor(unpack(EdgeColor(bag)))
            b.link = item and item[1]
            b.icon:SetTexture(item and item[3] or nil)
            b.count:SetText(item and item[2] and item[2] > 1 and item[2] or "")
            local q = item and item[4]
            local color = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            b.quality:SetShown(color ~= nil and ns.db.qualityBorder)
            if color then b.quality:SetVertexColor(color.r, color.g, color.b) end
            b:SetAlpha(MatchesSearch(b.link) and 1 or 0.3)
            if item then used = used + 1 end
            b:Show()
        end
    end
    for i = index + 1, #offline do offline[i]:Hide() end
    return index, used, total
end

---------------------------------------------------------------------------
-- Taschenleiste im Fenster (ein-/ausblendbar): die angelegten Taschen; Tasche hineinziehen = anlegen,
-- herausziehen = abnehmen; Maus darüber hebt ihre Plätze hervor
---------------------------------------------------------------------------
local bagButtons = {}

local function InventorySlot(bag)
    return C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag)
end

local function HighlightBag(bag)
    for b, slots in pairs(buttons) do
        for _, button in pairs(slots) do
            button:SetAlpha((bag == nil or b == bag) and 1 or 0.35)
        end
    end
end

local function CreateBagBar()
    bagBar = CreateFrame("Frame", nil, window)
    bagBar:SetHeight(BAGSLOT)
    local x = 0
    for _, bag in ipairs(ns.BagIDs()) do
        if bag > 0 then
            local b = CreateFrame("Button", nil, bagBar)
            b:SetSize(BAGSLOT, BAGSLOT)
            b:SetPoint("LEFT", x, 0)
            x = x + BAGSLOT + 3
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            AddForeverLook(b, bag)
            b.bag = bag
            b:RegisterForDrag("LeftButton")
            b:HookScript("OnEnter", function(self)
                HighlightBag(self.bag)
                local inv = InventorySlot(self.bag)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                if inv and GetInventoryItemLink("player", inv) then
                    GameTooltip:SetInventoryItem("player", inv)
                else
                    GameTooltip:AddLine(L("BAG_EMPTY"))
                end
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function()
                HighlightBag(nil)
                GameTooltip:Hide()
            end)
            local function Put(self)
                local inv = InventorySlot(self.bag)
                if inv and CursorHasItem() then PutItemInBag(inv) end
            end
            b:SetScript("OnReceiveDrag", Put)
            b:SetScript("OnClick", Put)
            b:SetScript("OnDragStart", function(self)
                local inv = InventorySlot(self.bag)
                if inv then PickupBagFromSlot(inv) end
            end)
            bagButtons[#bagButtons + 1] = b
        end
    end
    bagBar:SetWidth(math.max(1, x - 3))
end

local function UpdateBagBar()
    for _, b in ipairs(bagButtons) do
        local inv = InventorySlot(b.bag)
        b.icon:SetTexture(inv and GetInventoryItemTexture("player", inv) or nil)
    end
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
    for _, bag in ipairs(ns.BagIDs()) do
        for slot = 1, SlotCount(bag) do
            if not (buttons[bag] and buttons[bag][slot]) then CreateSlot(bag, slot) end
        end
    end
    return true
end

local function ShowLive(columns, gap)
    local index, used, total = 0, 0, 0
    for _, bag in ipairs(ns.BagIDs()) do
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
    return index, used, total
end

local function ViewLabel()
    if not view then return L("VIEW_MINE") end
    local c = ns.CharacterData(view.key)
    local name = c and ns.ColoredName(c) or view.key
    return name .. " – " .. L(view.kind == "bank" and "VIEW_BANK" or "VIEW_BAGS")
end

function ns.LayoutBags()
    if not window then return end
    local db = ns.db
    local columns = math.max(4, db.columns or 10)
    local gap = math.max(0, db.spacing or 2)
    local live = view == nil
    local showBar = live and db.showBagBar

    -- echte Plätze: in der gespeicherten Ansicht ausblenden (nur außerhalb des Kampfes möglich)
    if live then EnsureSlots() end
    for _, frame in pairs(bagFrames) do
        if not InCombatLockdown() then frame:SetShown(live) end
    end
    if bagBar then bagBar:SetShown(showBar and true or false) end

    local index, used, total
    if live then
        for i = 1, #offline do offline[i]:Hide() end
        index, used, total = ShowLive(columns, gap)
        UpdateBagBar()
    else
        local entry = ns.CharacterData(view.key) or {}
        index, used, total = ShowOffline(entry, columns, gap)
    end

    local rows = math.max(1, math.ceil(index / columns))
    local width = columns * SLOT + (columns - 1) * gap
    local height = rows * SLOT + (rows - 1) * gap
    local barSpace = showBar and (BAGSLOT + 6) or 0
    if not InCombatLockdown() then
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", PAD, -HEADER - TOOLBAR - barSpace)
        content:SetSize(width, height)
        window:SetSize(math.max(width + 2 * PAD, 330), HEADER + TOOLBAR + barSpace + height + FOOTER + 2 * PAD)
    end
    viewButton:SetText(ViewLabel())
    freeText:SetText(L("FREE_SLOTS", total - used, total))
    local money = live and GetMoney() or ((ns.CharacterData(view.key) or {}).money or 0)
    moneyText:SetText(GetMoneyString and GetMoneyString(money, true) or tostring(money))
end

local function RefreshSlots()
    if not window or not window:IsShown() then return end
    ns.LayoutBags()
end

local function SetView(newView)
    view = newView
    -- Taschensuche von Blizzard gilt nur für die echten Taschen; in der gespeicherten Ansicht sucht ForeverBags selbst
    ns.LayoutBags()
end

-- Auswahl: eigene Taschen, jeder gespeicherte Charakter mit Taschen und (falls besucht) Bank
local function ViewMenu(owner)
    local items = { { radio = true, text = L("VIEW_MINE"), checked = function() return view == nil end,
        onClick = function() SetView(nil) end } }
    for _, entry in ipairs(ns.Characters()) do
        local c, key = entry.data, entry.key
        items[#items + 1] = { divider = true }
        items[#items + 1] = { title = ns.ColoredName(c) .. (c.realm and ("  |cff8a8a8a" .. c.realm .. "|r") or "") }
        if key ~= ns.CharKey() then
            items[#items + 1] = { radio = true, text = L("VIEW_BAGS"),
                checked = function() return view and view.key == key and view.kind == "bags" end,
                onClick = function() SetView({ key = key, kind = "bags" }) end }
        end
        if c.bank then
            items[#items + 1] = { radio = true, text = L("VIEW_BANK"),
                checked = function() return view and view.key == key and view.kind == "bank" end,
                onClick = function() SetView({ key = key, kind = "bank" }) end }
        elseif key == ns.CharKey() then
            items[#items + 1] = { text = L("BANK_NOT_SEEN"), disabled = true }
        end
    end
    UI.ShowMenu(owner, items, { align = "LEFT" })
end

---------------------------------------------------------------------------
-- Gold aller Charaktere (Tooltip über dem Gold)
---------------------------------------------------------------------------
-- Tooltip im Forever-Stil (dunkel, goldene Linie oben) – für alles außer Gegenständen (die bleiben im
-- Blizzard-Tooltip, an den sich andere Addons hängen, z. B. Preise)
local function Tip() return UI.GetTooltip and UI.GetTooltip() or GameTooltip end
local function SimpleTip(owner, text)
    local tip = Tip()
    tip:SetOwner(owner, "ANCHOR_TOP")
    tip:AddLine(text, 1, 1, 1)
    tip:Show()
end
local function HideTip() Tip():Hide() end

local function MoneyTooltip(owner)
    local tip = Tip()
    tip:SetOwner(owner, "ANCHOR_TOP")
    tip:AddLine(L("MONEY_TITLE"), C.accent[1], C.accent[2], C.accent[3])
    local sum = 0
    for _, entry in ipairs(ns.Characters()) do
        local money = entry.key == ns.CharKey() and GetMoney() or (entry.data.money or 0)
        sum = sum + money
        tip:AddDoubleLine(ns.ColoredName(entry.data), GetMoneyString(money, true), 1, 1, 1, 1, 1, 1)
    end
    tip:AddLine(" ")
    tip:AddDoubleLine(L("MONEY_TOTAL"), GetMoneyString(sum, true), C.accent[1], C.accent[2], C.accent[3], 1, 1, 1)
    tip:Show()
end

---------------------------------------------------------------------------
-- Position und Verschieben (immer möglich, an der Titelleiste; ohne Raster und Hilfslinien)
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
    if InCombatLockdown() then return end
    window.fbagsMoving = true
    window:StartMoving()
end

local function StopDrag()
    if not window.fbagsMoving then return end
    window.fbagsMoving = nil
    window:StopMovingOrSizing()
    SavePosition()
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local function HeaderButton(texture, tip, onClick)
    local b = CreateFrame("Button", nil, window.header)
    b:SetSize(16, 16)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(texture)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetAlpha(0.8)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        SimpleTip(self, tip)
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.8)
        HideTip()
    end)
    return b
end

local function CreateWindow()
    window = UI.Window("ForeverBagsFrame", L("WINDOW_TITLE"), 400, 300)
    window:SetFrameStrata("HIGH") -- über den Leisten, unter Menüs und Dialogen
    -- Ziehen an der Titelleiste (UI.Window bringt einfaches Ziehen der ganzen Fläche mit – das stört bei Taschen)
    window:SetScript("OnDragStart", nil)
    window:SetScript("OnDragStop", nil)
    window.header:SetScript("OnDragStart", StartDrag)
    window.header:SetScript("OnDragStop", StopDrag)
    if UI.AddMover then UI.AddMover(window) end -- andere Forever-Rahmen rasten an den Taschen ein

    -- Titelleiste: Zahnrad (Einstellungen) links neben dem Schließen-Kreuz
    local gear = HeaderButton("Interface\\Icons\\INV_Misc_Gear_01", L("TIP_GEAR"), function() ns.ToggleOptions() end)
    gear:SetPoint("RIGHT", window.CloseButton, "LEFT", -4, 0)

    -- Werkzeugzeile: Ansicht (welcher Charakter, Taschen/Bank), Suche, Taschenleiste, Sortieren
    viewButton = UI.Button(window, "", 120, function(self) ViewMenu(self) end)
    if UI.AddArrow then UI.AddArrow(viewButton) end
    viewButton:SetPoint("TOPLEFT", PAD, -HEADER - 4)

    local sort = UI.Button(window, L("SORT"), 64, function()
        if view == nil and C_Container.SortBags then C_Container.SortBags() end
    end)
    sort:SetPoint("TOPRIGHT", -PAD, -HEADER - 4)
    sort:HookScript("OnEnter", function(self) SimpleTip(self, L("TIP_SORT")) end)
    sort:HookScript("OnLeave", HideTip)

    local bagsToggle = UI.Button(window, "", 22, function()
        ns.db.showBagBar = not ns.db.showBagBar
        ns.LayoutBags()
    end)
    bagsToggle:SetPoint("RIGHT", sort, "LEFT", -4, 0)
    local bagIcon = bagsToggle:CreateTexture(nil, "ARTWORK")
    bagIcon:SetPoint("TOPLEFT", 3, -3)
    bagIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    bagIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    bagIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bagsToggle:HookScript("OnEnter", function(self) SimpleTip(self, L("TIP_BAGBAR")) end)
    bagsToggle:HookScript("OnLeave", HideTip)

    -- Suche (eigene Taschen: Blizzards Taschensuche, gilt wie bei Blizzard auch für die Bank)
    searchBox = UI.EditBox(window, 100, 22)
    searchBox:SetPoint("LEFT", viewButton, "RIGHT", 4, 0)
    searchBox:SetPoint("RIGHT", bagsToggle, "LEFT", -4, 0)
    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 7, 0)
    placeholder:SetText(L("SEARCH"))
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        placeholder:SetShown(text == "" and not self:HasFocus())
        if C_Container.SetItemSearch then C_Container.SetItemSearch(text) end
        if view ~= nil then ns.LayoutBags() end -- gespeicherte Ansicht: selbst filtern
    end)
    searchBox:SetScript("OnEditFocusGained", function() placeholder:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self) placeholder:SetShown((self:GetText() or "") == "") end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    CreateBagBar()
    bagBar:SetPoint("TOPLEFT", PAD, -HEADER - TOOLBAR)

    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", PAD, -HEADER - TOOLBAR)
    content:SetSize(1, 1)

    -- Fußzeile: freie Plätze links, Gold rechts (Maus darüber: Gold aller Charaktere; rechte untere Ecke bleibt
    -- frei für den Größen-Griff)
    freeText = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    freeText:SetPoint("BOTTOMLEFT", PAD, PAD + 2)
    local moneyArea = CreateFrame("Frame", nil, window)
    moneyArea:SetPoint("BOTTOMRIGHT", -PAD - 16, PAD)
    moneyArea:SetSize(160, 16)
    moneyText = moneyArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    moneyText:SetPoint("RIGHT")
    moneyText:SetJustifyH("RIGHT")
    moneyArea:EnableMouse(true)
    moneyArea:SetScript("OnEnter", MoneyTooltip)
    moneyArea:SetScript("OnLeave", HideTip)

    -- HookScript statt SetScript: der Hub hängt eigene Dinge an OnShow (Fenster-Stapel, Größen-Griff)
    window:HookScript("OnShow", function()
        ns.LayoutBags()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    end)
    window:HookScript("OnHide", function()
        if window.fbagsMoving then StopDrag() end
        searchBox:ClearFocus()
        view = nil -- beim nächsten Öffnen wieder die eigenen Taschen
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
events:SetScript("OnEvent", function(_, event, isInitialLogin)
    if event == "PLAYER_ENTERING_WORLD" then
        -- beim Einloggen meldet das Spiel viele Gegenstände als "neu": nicht alles leuchten lassen
        if isInitialLogin and C_NewItems and C_NewItems.ClearAll then C_NewItems.ClearAll() end
        return
    end
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
        "INVENTORY_SEARCH_UPDATE", "BAG_NEW_ITEMS_UPDATED", "PLAYER_REGEN_ENABLED", "BAG_CONTAINER_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, event)
    end
end
