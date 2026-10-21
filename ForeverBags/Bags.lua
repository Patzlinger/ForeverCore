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
local QUEST_COLOR = { 0.95, 0.80, 0.25, 0.95 } -- Questgegenstände: warmes, etwas gedämpftes Gelb
local CURRENCY_ROW = 18   -- Zeile mit den gewählten Währungen (nur, wenn welche gewählt sind)
ns.SLOT = SLOT

local function ReagentBag() return Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag end

local window, content, searchBox, freeText, moneyText, viewButton, bagBar
local bagFrames = {}   -- [Tasche] = unsichtbarer Rahmen mit SetID(Tasche)
local buttons = {}     -- [Tasche][Platz] = Knopf (echte Taschen)
local offline = {}     -- Knöpfe der gespeicherten Ansicht (werden wiederverwendet)
local createPending = false
-- Ansicht: nil = eigene Taschen (echt); sonst { key = "Name-Realm", kind = "bags" | "bank" }
local view

-- Randfarbe eines Platzes: Reagenzientasche in eigener (einstellbarer) Farbe, sonst grau
local function EdgeColor(bag)
    if bag ~= nil and bag == ReagentBag() then
        local c = ns.db and ns.db.reagentColor or { 0.25, 0.75, 0.55 }
        return { c[1], c[2], c[3], 1 }
    end
    return C.border
end

-- Rand neu setzen: beim Darüberfahren gold, Questgegenstand gelb (1 px plus schwacher Innenrand = etwas
-- kräftiger als normal, aber nicht mehr 2 px dick), sonst Farbe der Tasche
local function ApplyEdge(button, hovered)
    local edge = button.fbagsEdge
    if not edge then return end
    local size = 1
    if not edge.fbagsInner then
        local inner = CreateFrame("Frame", nil, edge, "BackdropTemplate")
        inner:SetPoint("TOPLEFT", 1, -1)
        inner:SetPoint("BOTTOMRIGHT", -1, 1)
        inner:EnableMouse(false)
        inner:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        edge.fbagsInner = inner
    end
    if button.fbagsQuest and not hovered then
        edge.fbagsInner:SetBackdropBorderColor(QUEST_COLOR[1], QUEST_COLOR[2], QUEST_COLOR[3], 0.35)
        edge.fbagsInner:Show()
    else
        edge.fbagsInner:Hide()
    end
    if edge.fbagsSize ~= size then
        edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = size })
        edge.fbagsSize = size
    end
    if hovered then
        edge:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.9)
    elseif button.fbagsQuest then
        edge:SetBackdropBorderColor(unpack(QUEST_COLOR))
    else
        edge:SetBackdropBorderColor(unpack(EdgeColor(button.fbagsBag)))
    end
end
ns.ApplyEdge = ApplyEdge

---------------------------------------------------------------------------
-- Ein echter Taschenplatz
---------------------------------------------------------------------------
local function AddForeverLook(button, bag)
    local bg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    button.fbagsBg = bg
    local edge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    edge:SetAllPoints()
    edge:SetFrameLevel(button:GetFrameLevel() + 2)
    edge:EnableMouse(false)
    button.fbagsEdge = edge
    button.fbagsBag = bag
    ApplyEdge(button, false)
    button:HookScript("OnEnter", function(self) ApplyEdge(self, true) end)
    button:HookScript("OnLeave", function(self) ApplyEdge(self, false) end)
end
ns.AddForeverLook = AddForeverLook

-- Blizzards Kontext-Prüfung abschalten: Blizzard dunkelt Plätze ab, die zum gerade aktiven "Kontext" (z. B. Bank-
-- oder Händler-Ansicht seiner eigenen Fenster) nicht passen. In unseren Fenstern ergab das fälschlich "passt nicht"
-- (alles dunkel). Die Suche dunkelt weiter über SetMatchesSearch ab.
local function NoItemContext(button)
    local result = ItemButtonUtil and ItemButtonUtil.ItemContextMatchResult
    if result and result.DoesNotApply then
        button.GetItemContextMatchResult = function() return result.DoesNotApply end
    end
    if button.UpdateItemContextMatching then pcall(button.UpdateItemContextMatching, button) end
end
ns.NoItemContext = NoItemContext

-- Masque (optional): Taschenplätze in der Gruppe "Forever Core › ForeverBags". Gestaltet Masque, überlässt ForeverBags ihm
-- Rahmen, Fläche und Symbol; unser feiner Rand (Questgegenstände gelb, beim Darüberfahren gold) bleibt darüber.
local MSQ = _G.LibStub and _G.LibStub("Masque", true)
local masqueGroup
if MSQ and MSQ.Group then
    local ok, g = pcall(MSQ.Group, MSQ, "Forever Core", "ForeverBags")
    if ok then masqueGroup = g end
end
local function MasqueActive()
    return masqueGroup ~= nil and not (masqueGroup.db and masqueGroup.db.Disabled)
end

-- Blizzards Platz-Vorlage hat eine FESTE Ebene (frameLevel="10"). Holt der Hub unser Fenster nach vorne (Ebene steigt),
-- bleiben die Plätze auf 10 stehen und landen hinter der eigenen Fensterfläche (alles dunkel, nicht anklickbar).
-- Darum: Festlegung aufheben und knapp über den eigenen Rahmen setzen – danach wandern sie mit dem Fenster mit.
function ns.FollowParentLevel(button)
    if InCombatLockdown() and button.IsProtected and button:IsProtected() then return end
    if button.SetFixedFrameLevel then pcall(button.SetFixedFrameLevel, button, false) end
    local parent = button:GetParent()
    if parent then pcall(button.SetFrameLevel, button, parent:GetFrameLevel() + 2) end
end

function ns.StyleSlot(button, bag)
    ns.FollowParentLevel(button)
    NoItemContext(button)
    local masque = MasqueActive()
    if masqueGroup and not button.fbagsMasque then
        button.fbagsMasque = true
        pcall(masqueGroup.AddButton, masqueGroup, button, nil, "Item")
    end
    -- Blizzards Platz-Rahmen ausblenden, dafür dunkle Fläche + 1-px-Rand im Forever-Stil (mit Masque: Masques Stil)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal and not masque then normal:SetAlpha(0) end
    AddForeverLook(button, bag)
    if masque then
        if button.fbagsBg then button.fbagsBg:Hide() end
        return
    end
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
    ns.StyleSlot(button, bag)
    buttons[bag] = buttons[bag] or {}
    buttons[bag][slot] = button
    return button
end

-- Anzeige eines Platzes aus den Taschendaten (geht auch im Kampf: keine geschützten Änderungen).
-- Auch für das Bankfenster (Bank.lua).
function ns.UpdateSlot(button, bag, slot)
    -- liegt der Platz (noch) nicht über seinem Rahmen: nachziehen (siehe ns.FollowParentLevel)
    local parent = button:GetParent()
    if parent and button:GetFrameLevel() <= parent:GetFrameLevel() and ns.FollowParentLevel then
        ns.FollowParentLevel(button)
    end
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
    -- Suchtreffer: Blizzards Suche markiert nicht passende Gegenstände (isFiltered) – aber nur, wenn in UNSEREM Suchfeld
    -- etwas steht. Bei geöffneter neuer Bank meldet das Spiel "gefiltert" auch ohne Suche (Blizzards Bankfenster im
    -- Hintergrund) – das hat Bank und Taschen komplett abgedunkelt.
    local searching = searchBox and strtrim(searchBox:GetText() or "") ~= ""
    local filtered = searching and info and info.isFiltered
    if button.SetMatchesSearch then
        button:SetMatchesSearch(not filtered)
    else
        button:SetAlpha(filtered and 0.3 or 1)
    end
    if button.UpdateItemContextMatching then pcall(button.UpdateItemContextMatching, button) end
    -- Neu erhaltene Gegenstände (erst nach dem Login erhaltene – siehe ClearAll beim Einloggen). Blizzards
    -- Leucht-Animationen der Vorlage sonst anhalten, sonst leuchten alle Plätze
    local isNew = ns.db.highlightNew and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot)
    local newTex = button.NewItemTexture
    if newTex then
        if isNew then
            -- eigener, sanft goldener Schimmer (Blizzard färbt ihn nach Qualität – blau sah aus wie ein blauer Gegenstand)
            pcall(newTex.SetAtlas, newTex, "bags-glow-white") -- jedes Mal: Blizzard setzt sonst wieder seine Farbe
            newTex:SetVertexColor(1, 0.82, 0.35, 0.9)
            local glow = button.newitemglowAnim
            if glow and glow.IsPlaying and not glow:IsPlaying() then glow:Play() end
        end
        newTex:SetShown(isNew and true or false)
    end
    if not isNew then
        for _, anim in ipairs({ button.newitemglowAnim, button.flashAnim }) do
            if anim and anim.Stop then anim:Stop() end
        end
        if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
    end
    -- Abklingzeit
    if button.UpdateCooldown then pcall(button.UpdateCooldown, button, texture) end
    -- Questgegenstand: gelber, dickerer Rand
    local quest = info and C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    button.fbagsQuest = quest and (quest.isQuestItem or quest.questID ~= nil) and true or false
    -- Startet der Gegenstand eine Quest (gehört zu einer Quest, die man noch nicht hat): Blizzards gelbes
    -- Ausrufezeichen über dem Symbol, wie in Blizzards Taschen
    local starter = quest and quest.questID ~= nil and not quest.isActive
    local bang = button.IconQuestTexture or button.fbagsBang
    if not bang and starter then
        bang = button:CreateTexture(nil, "OVERLAY", nil, 2)
        bang:SetAllPoints()
        button.fbagsBang = bang
    end
    if bang then
        if starter then
            bang:SetTexture(_G.TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang")
            bang:Show()
        else
            bang:Hide()
        end
    end
    ApplyEdge(button, button:IsMouseOver())
    button:Show()
end
local UpdateSlot = ns.UpdateSlot

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

---------------------------------------------------------------------------
-- Platzierung der Plätze im Raster. Mit "Taschen getrennt anzeigen" beginnt jede Tasche in einer neuen Reihe,
-- dazwischen etwas Luft und eine feine goldene Linie.
---------------------------------------------------------------------------
local BAG_SEP = 9 -- zusätzlicher Abstand zwischen zwei Taschen (Linie in der Mitte)
local separators = {}

local function Separator(n, y)
    local line = separators[n]
    if not line then
        line = content:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        separators[n] = line
    end
    line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.28)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y)
    line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -y)
    line:Show()
end

local function NewPlacer(columns, gap)
    local p = { col = 0, y = 0, seps = 0, started = false }
    -- neue Tasche (nur aufrufen, wenn sie Plätze hat)
    function p:StartBag()
        if ns.db.separateBags and self.started then
            if self.col > 0 then
                self.col = 0
                self.y = self.y + SLOT + gap
            end
            self.seps = self.seps + 1
            Separator(self.seps, self.y - gap + math.floor((BAG_SEP + gap) / 2))
            self.y = self.y + BAG_SEP
        end
        self.started = true
    end
    -- Position des nächsten Platzes
    function p:Next()
        local x, y = self.col * (SLOT + gap), self.y
        self.col = self.col + 1
        if self.col >= columns then
            self.col = 0
            self.y = self.y + SLOT + gap
        end
        return x, y
    end
    function p:Height()
        if not self.started then return SLOT end
        return self.col > 0 and (self.y + SLOT) or (self.y - gap)
    end
    function p:Finish()
        for i = self.seps + 1, #separators do separators[i]:Hide() end
    end
    return p
end

local function ShowOffline(entry, placer)
    local containers = view.kind == "bank" and entry.bank or entry.bags
    local index, used, total = 0, 0, 0
    local ids = view.kind == "bank" and ns.BankIDs() or ns.BagIDs()
    for _, bag in ipairs(ids) do
        local c = containers and containers[bag]
        if c and (c.size or 0) > 0 then placer:StartBag() end
        for slot = 1, (c and c.size or 0) do
            index = index + 1
            total = total + 1
            local b = OfflineButton(index)
            local item = c[slot]
            local x, y = placer:Next()
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
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

local function ShowLive(placer)
    local index, used, total = 0, 0, 0
    for _, bag in ipairs(ns.BagIDs()) do
        local count = SlotCount(bag)
        for slot, button in pairs(buttons[bag] or {}) do
            if slot > count then button:Hide() end -- Tasche getauscht: kleinere Tasche
        end
        if count > 0 then placer:StartBag() end
        for slot = 1, count do
            local button = buttons[bag] and buttons[bag][slot]
            if button then
                local x, y = placer:Next()
                if not InCombatLockdown() then
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
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

    local _, used, total
    local placer = NewPlacer(columns, gap)
    if live then
        for i = 1, #offline do offline[i]:Hide() end
        _, used, total = ShowLive(placer)
        UpdateBagBar()
    else
        local entry = ns.CharacterData(view.key) or {}
        _, used, total = ShowOffline(entry, placer)
    end
    placer:Finish()

    local width = columns * SLOT + (columns - 1) * gap
    local height = math.max(SLOT, placer:Height())
    local barSpace = showBar and (BAGSLOT + 6) or 0
    local currencySpace = ns.UpdateCurrencies() and CURRENCY_ROW or 0
    if not InCombatLockdown() then
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", PAD, -HEADER - TOOLBAR - barSpace)
        content:SetSize(width, height)
        window:SetSize(math.max(width + 2 * PAD, 330),
            HEADER + TOOLBAR + barSpace + height + currencySpace + FOOTER + 2 * PAD)
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
    -- mit ForeverAlts: Klick aufs Gold öffnet die Übersicht aller Charaktere
    local alts = UI.API and UI.API.ForeverAlts
    if alts and alts.Toggle then tip:AddLine(L("TIP_MONEY_ALTS"), 0.6, 0.6, 0.6) end
    tip:Show()
end

---------------------------------------------------------------------------
-- Währungen in der Fußzeile: die gewählten (Rechtsklick auf die Fußzeile = Auswahl). Beim ersten Start die
-- in Blizzards Währungsfenster "im Rucksack anzeigen" markierten.
---------------------------------------------------------------------------
local currencyRow
local currencyButtons = {}

local function CurrencyID(index)
    local info = C_CurrencyInfo.GetCurrencyListInfo(index)
    if not info then return nil end
    if info.currencyID then return info.currencyID, info end
    local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(index)
    return link and tonumber(link:match("currency:(%d+)")), info
end

local function SelectedCurrencies()
    local db = ns.db
    db.currencies = db.currencies or {}
    if not db.currencyInit and C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
        db.currencyInit = true
        for i = 1, 5 do
            local info = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
            local id = info and (info.currencyTypesID or info.currencyID)
            if id then db.currencies[id] = true end
        end
    end
    local list = {}
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for id in pairs(db.currencies) do
            local info = C_CurrencyInfo.GetCurrencyInfo(id)
            if info and info.name then list[#list + 1] = { id = id, info = info } end
        end
    end
    table.sort(list, function(a, b) return a.info.name < b.info.name end)
    return list
end

-- Zeile neu füllen; Rückgabe: true, wenn mindestens eine Währung gezeigt wird
function ns.UpdateCurrencies()
    if not currencyRow then return false end
    local list = SelectedCurrencies()
    local x = 0
    for i, entry in ipairs(list) do
        local b = currencyButtons[i]
        if not b then
            b = CreateFrame("Frame", nil, currencyRow)
            b:SetHeight(CURRENCY_ROW)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT")
            b:EnableMouse(true)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                if GameTooltip.SetCurrencyByID then GameTooltip:SetCurrencyByID(self.id) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", GameTooltip_Hide)
            b:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then ns.CurrencyMenu() end end)
            currencyButtons[i] = b
        end
        b.id = entry.id
        b.text:SetText(string.format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s", entry.info.iconFileID or 134400,
            BreakUpLargeNumbers and BreakUpLargeNumbers(entry.info.quantity or 0) or (entry.info.quantity or 0)))
        b:SetWidth(b.text:GetStringWidth() + 4)
        b:ClearAllPoints()
        b:SetPoint("LEFT", currencyRow, "LEFT", x, 0)
        b:Show()
        x = x + b:GetWidth() + 10
    end
    for i = #list + 1, #currencyButtons do currencyButtons[i]:Hide() end
    currencyRow:SetShown(#list > 0)
    return #list > 0
end

-- Auswahl aller bekannten Währungen (nach Blizzards Gruppen), Häkchen = in der Fußzeile zeigen
function ns.CurrencyMenu()
    local items = { { title = L("CURRENCY_TITLE") } }
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
        for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local id, info = CurrencyID(index)
            if info and info.isHeader then
                items[#items + 1] = { divider = true }
                items[#items + 1] = { title = info.name }
            elseif id and info then
                items[#items + 1] = { checkbox = true,
                    text = string.format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s", info.iconFileID or 134400, info.name),
                    checked = function() return ns.db.currencies and ns.db.currencies[id] == true end,
                    onClick = function()
                        ns.db.currencies = ns.db.currencies or {}
                        ns.db.currencies[id] = not ns.db.currencies[id] or nil
                        ns.LayoutBags()
                    end }
            end
        end
    end
    if #items == 1 then items[#items + 1] = { text = L("CURRENCY_NONE"), disabled = true } end
    UI.ShowMenu(window, items, { atCursor = true })
end

---------------------------------------------------------------------------
-- Position und Verschieben (immer möglich, an der Titelleiste; ohne Raster und Hilfslinien).
-- Gespeichert in UIParent-Einheiten; beim Setzen durch die eigene Größe (Griff unten rechts) geteilt.
---------------------------------------------------------------------------
local function RestorePosition()
    local pos = ns.db.pos or DEFAULT_POS
    local scale = window:GetScale()
    window:ClearAllPoints()
    window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", pos[1] / scale, pos[2] / scale)
end

local function SavePosition()
    local right, bottom = window:GetRight(), window:GetBottom()
    if not (right and bottom) then return end
    local s = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
    ns.db.pos = { UI.Round(right * s - UIParent:GetRight()), UI.Round(bottom * s) }
    RestorePosition()
end

-- Beim Öffnen: beim Händler unter dem ForeverVendor-Fenster (bzw. rechts neben dem Händlerfenster), sonst an
-- der Mausposition (Einstellung "openAtCursor"; aus = gespeicherte Position). Bildschirmränder hält UI.Window ein.
local vendorHooked = false
-- Andocken: an Bank, ForeverVendor-Fenster bzw. Händlerfenster HÄNGT die Tasche (Anker an deren Rahmen) – wird das
-- Fenster verschoben, wandert sie sofort mit. Zieht man die Tasche selbst, löst sie sich (window.fbagsDetached) und
-- bleibt, wo man sie hinlegt, bis Bank/Händler zu sind bzw. die Tasche geschlossen wird.
local function PlaceOnOpen()
    if not window or window.fbagsMoving or not window:IsShown() then return end
    local bankOpen = _G.ForeverBagsBank and _G.ForeverBagsBank:IsShown()
    local merchantOpen = _G.MerchantFrame and _G.MerchantFrame:IsShown()
    local tradeOpen = _G.TradeFrame and _G.TradeFrame:IsShown()
    if not (bankOpen or merchantOpen or tradeOpen) then
        window.fbagsDetached = nil
    elseif window.fbagsDetached then
        return
    end
    -- ForeverVendor-Fenster ändert Größe/Lage, solange der Händler offen ist: unser Fenster bleibt darunter
    local vendorPanel = _G.ForeverVendorMerchantPanel
    if vendorPanel and not vendorHooked then
        vendorHooked = true
        local function Again()
            local m = _G.MerchantFrame
            if m and m:IsShown() then C_Timer.After(0, PlaceOnOpen) end
        end
        vendorPanel:HookScript("OnSizeChanged", Again)
        vendorPanel:HookScript("OnShow", Again)
    end
    local ws = window:GetEffectiveScale()
    local function At(point, frame, x, y)
        window:ClearAllPoints()
        window:SetPoint(point, UIParent, "BOTTOMLEFT", x / ws, y / ws)
    end
    local function Dock(relative, relPoint, x, y)
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", relative, relPoint, x, y)
    end
    local bankWin = _G.ForeverBagsBank
    if bankWin and bankWin:IsShown() then
        Dock(bankWin, "TOPRIGHT", 4, 0)
        return
    end
    local merchant = _G.MerchantFrame
    if merchant and merchant:IsShown() then
        local vendor = _G.ForeverVendorMerchantPanel
        if vendor and vendor:IsShown() then
            Dock(vendor, "BOTTOMLEFT", 0, -4)
        else
            Dock(merchant, "TOPRIGHT", 4, 0)
        end
        return
    end
    -- Handel: rechts neben das Handelsfenster, oben bündig (mit ForeverSkin ist dessen Titelleiste nach oben
    -- erweitert – dann an deren Oberkante, ForeverSkinTradeTop)
    local trade = _G.TradeFrame
    if trade and trade:IsShown() then
        local top = _G.ForeverSkinTradeTop
        Dock((top and top:IsShown()) and top or trade, "TOPRIGHT", 4, 0)
        return
    end
    if ns.db.openAtCursor == false then
        RestorePosition()
        return
    end
    local x, y = GetCursorPosition()
    -- untere rechte Ecke am Mauszeiger (das Fenster öffnet sich nach links oben vom Zeiger weg)
    At("BOTTOMRIGHT", nil, x, y)
end

function ns.ResetPosition()
    ns.db.pos = nil
    if window then RestorePosition() end
    ns.Print(L("POS_RESET"))
end

local function StartDrag()
    if InCombatLockdown() then return end
    window.fbagsMoving = true
    -- Vor dem Ziehen an der linken oberen Ecke festmachen, genau an der jetzigen Stelle: das Fenster hängt sonst an
    -- der unteren rechten Ecke (gespeicherte Lage) bzw. an Bank/Händler (angedockt) – ändert sich beim Ziehen die
    -- Höhe (Taschen aktualisieren sich), wuchs es nach oben weg und sprang unter der Maus davon
    local left, top = window:GetLeft(), window:GetTop()
    if left and top then
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    window:StartMoving()
end

local function StopDrag()
    if not window.fbagsMoving then return end
    window.fbagsMoving = nil
    window:StopMovingOrSizing()
    -- bei Bank/Händler selbst gezogen: abgedockt, bis die wieder zu sind
    if (_G.ForeverBagsBank and _G.ForeverBagsBank:IsShown()) or (_G.MerchantFrame and _G.MerchantFrame:IsShown())
        or (_G.TradeFrame and _G.TradeFrame:IsShown()) then
        window.fbagsDetached = true
    end
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
    window.gear = gear

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

    -- Währungen über der Fußzeile; Rechtsklick auf Fußzeile oder Währungen = Auswahl der Währungen
    currencyRow = CreateFrame("Frame", nil, window)
    currencyRow:SetPoint("BOTTOMLEFT", PAD, PAD + FOOTER - 4)
    currencyRow:SetPoint("BOTTOMRIGHT", -PAD - 16, PAD + FOOTER - 4)
    currencyRow:SetHeight(CURRENCY_ROW)
    local footer = CreateFrame("Frame", nil, window)
    footer:SetPoint("BOTTOMLEFT", PAD, PAD)
    footer:SetPoint("BOTTOMRIGHT", moneyArea, "BOTTOMLEFT", -4, 0)
    footer:SetHeight(FOOTER)
    footer:EnableMouse(true)
    local function FooterClick(_, button) if button == "RightButton" then ns.CurrencyMenu() end end
    footer:SetScript("OnMouseUp", FooterClick)
    -- Gold: Linksklick öffnet (mit ForeverAlts) die Twinks-Übersicht, Rechtsklick wie die Fußzeile
    moneyArea:SetScript("OnMouseUp", function(self, button)
        local alts = UI.API and UI.API.ForeverAlts
        if button == "LeftButton" and alts and alts.Toggle then alts.Toggle() return end
        FooterClick(self, button)
    end)
    currencyRow:EnableMouse(true)
    currencyRow:SetScript("OnMouseUp", FooterClick)
    footer:SetScript("OnEnter", function(self) SimpleTip(self, L("TIP_CURRENCY")) end)
    footer:SetScript("OnLeave", HideTip)

    -- HookScript statt SetScript: der Hub hängt eigene Dinge an OnShow (Fenster-Stapel, Größen-Griff)
    window:HookScript("OnShow", function()
        PlaceOnOpen()
        -- ForeverVendor baut sein Händler-Fenster im selben Moment auf (Größe erst danach): mehrmals nachsetzen
        for _, delay in ipairs({ 0, 0.1, 0.3, 0.6 }) do
            C_Timer.After(delay, function()
                local m = _G.MerchantFrame
                if m and m:IsShown() then PlaceOnOpen() end
            end)
        end
        ns.LayoutBags()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_BACKPACK_OPEN then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
    end)
    window:HookScript("OnHide", function()
        if window.fbagsMoving then StopDrag() end
        window.fbagsDetached = nil -- beim nächsten Öffnen wieder an Bank/Händler andocken
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

-- Bankfenster verschoben oder in der Größe geändert: Taschen wieder rechts daneben
function ns.DockBagsToBank()
    if window and window:IsShown() then PlaceOnOpen() end
end

function ns.CloseBags()
    if window and window:IsShown() then window:Hide() end
end

function ns.ToggleBags()
    if not window then return end
    window:SetShown(not window:IsShown())
end

-- Schnittstelle für andere Forever-Addons (ForeverAlts): Taschen bzw. Bank eines gespeicherten Charakters zeigen,
-- freie Plätze eines Charakters
if UI.API then
    UI.API.ForeverBags = {
        -- above (optional): Fenster, über dem die Taschen liegen sollen (z. B. die Übersicht von ForeverAlts) – bis zum
        -- Schließen auf dessen Ebene und darüber, danach wieder auf der eigenen
        ShowCharacter = function(key, kind, above)
            if not window then return end
            if above and above.GetFrameStrata then
                window.fbOwnStrata = window.fbOwnStrata or window:GetFrameStrata()
                window:SetFrameStrata(above:GetFrameStrata())
                window:SetFrameLevel(above:GetFrameLevel() + 20)
                if not window.fbStrataHook then
                    window.fbStrataHook = true
                    window:HookScript("OnHide", function(self)
                        if self.fbOwnStrata then self:SetFrameStrata(self.fbOwnStrata) self.fbOwnStrata = nil end
                    end)
                end
            end
            local c = ns.CharacterData(key)
            if key == ns.CharKey() and kind ~= "bank" then
                SetView(nil)
            elseif c and c[kind == "bank" and "bank" or "bags"] then
                SetView({ key = key, kind = kind == "bank" and "bank" or "bags" })
            else
                return false
            end
            if not window:IsShown() then window:Show() end
            return true
        end,
        -- Zeigt das Fenster gerade die Taschen bzw. Bank dieses Charakters? (für Ein-/Ausschalten per Knopf)
        IsShowing = function(key, kind)
            if not (window and window:IsShown()) then return false end
            kind = kind == "bank" and "bank" or "bags"
            if view == nil then return key == ns.CharKey() and kind == "bags" end
            return view.key == key and view.kind == kind
        end,
        Close = function()
            if window and window:IsShown() then window:Hide() end
        end,
        -- Anzahl eines Gegenstands in Taschen und Bank: beim eingeloggten Charakter, bei allen gespeicherten zusammen
        -- und (wenn key angegeben) bei diesem Charakter
        CountItem = function(itemID, key)
            if not itemID then return 0, 0, 0 end
            local pattern = "item:" .. itemID .. "[:|]"
            local me, total, forKey = ns.CharKey(), 0, 0
            local mine = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, true) or 0
            for _, entry in ipairs(ns.Characters()) do
                local count = 0
                if entry.key == me then
                    count = mine
                else
                    for _, part in ipairs({ entry.data.bags or {}, entry.data.bank or {} }) do
                        for _, bag in pairs(part) do
                            for slot = 1, (type(bag) == "table" and bag.size or 0) do
                                local item = bag[slot]
                                if item and type(item[1]) == "string" and (item[1] .. ":"):find(pattern) then
                                    count = count + (item[2] or 1)
                                end
                            end
                        end
                    end
                end
                total = total + count
                if entry.key == key then forKey = count end
            end
            return mine, total, forKey
        end,
        HasBank = function(key)
            local c = ns.CharacterData(key)
            return c and c.bank ~= nil or false
        end,
        FreeSlots = function(key)
            local c = ns.CharacterData(key)
            if not (c and c.bags) then return nil end
            local free, total = 0, 0
            for _, bag in pairs(c.bags) do
                local size = type(bag) == "table" and bag.size or 0
                total = total + size
                for slot = 1, size do
                    if not bag[slot] then free = free + 1 end
                end
            end
            return free, total
        end,
    }
end

---------------------------------------------------------------------------
-- Blizzards Bank-/Gildenbank-Fenster unsichtbar und nicht anklickbar machen (Bank.lua, GuildBank.lua).
-- Schließen geht nicht: deren OnHide beendet den Besuch beim Bankier. Nur Deckkraft und Maus – keine
-- geschützten Rahmen werden verändert (die überspringen wir im Kampf).
---------------------------------------------------------------------------
local hiddenPanels = {}
-- Deckkraft bleibt 0, auch wenn Blizzard sie später selbst wieder hochsetzt (Nachladen der Fächer, Einblenden):
-- sonst lag das Fenster halb sichtbar über unseren und fing die Klicks ab
local function KeepTransparent(frame)
    if frame.fbagsAlphaHooked then return end
    frame.fbagsAlphaHooked = true
    hooksecurefunc(frame, "SetAlpha", function(self)
        if hiddenPanels[self] and not self.fbagsSettingAlpha then
            self.fbagsSettingAlpha = true
            self:SetAlpha(0)
            self.fbagsSettingAlpha = nil
        end
    end)
end
function ns.HideBlizzardPanel(frame)
    if not frame then return end
    local parts = hiddenPanels[frame] or {}
    hiddenPanels[frame] = parts
    KeepTransparent(frame)
    frame:SetAlpha(0)
    local function Walk(f, depth)
        if f.IsMouseEnabled and f:IsMouseEnabled() and not (InCombatLockdown() and f.IsProtected and f:IsProtected()) then
            if pcall(f.EnableMouse, f, false) then parts[f] = true end
        end
        if depth < 8 then
            for _, child in ipairs({ f:GetChildren() }) do Walk(child, depth + 1) end
        end
    end
    Walk(frame, 0)
end

function ns.RestoreBlizzardPanel(frame)
    local parts = frame and hiddenPanels[frame]
    if not parts then return end
    hiddenPanels[frame] = nil
    frame:SetAlpha(1)
    for part in pairs(parts) do pcall(part.EnableMouse, part, true) end
end

-- Kleines Fenster-Gerüst wie das Taschenfenster: Titelleiste ziehbar (Position wird gespeichert), Zahnrad
function ns.CreateBagWindow(name, title, posKey, defaultPos)
    local w = UI.Window(name, title, 400, 300)
    w:SetFrameStrata("HIGH")
    w:SetScript("OnDragStart", nil)
    w:SetScript("OnDragStop", nil)
    local function Restore()
        local pos = ns.db[posKey] or defaultPos
        local scale = w:GetScale()
        w:ClearAllPoints()
        if pos == "CENTER" then
            -- noch nie verschoben: mittig auf dem Bildschirm, etwas über der Mitte (frei von den Aktionsleisten)
            w:SetPoint("CENTER", UIParent, "CENTER", 0, 80 / scale)
            return
        end
        w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1] / scale, pos[2] / scale)
    end
    w.header:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        w.fbagsMoving = true
        -- an der linken oberen Ecke festmachen (Standardlage "Mitte" hängt an der Mitte – Höhenänderung beim Ziehen
        -- ließ das Fenster sonst unter der Maus wegrutschen)
        local left, top = w:GetLeft(), w:GetTop()
        if left and top then
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        w:StartMoving()
    end)
    w.header:SetScript("OnDragStop", function()
        if not w.fbagsMoving then return end
        w.fbagsMoving = nil
        w:StopMovingOrSizing()
        local left, top = w:GetLeft(), w:GetTop()
        if left and top then
            local s = w:GetEffectiveScale() / UIParent:GetEffectiveScale()
            ns.db[posKey] = { UI.Round(left * s), UI.Round(top * s) }
        end
        Restore()
    end)
    w.RestorePosition = Restore
    if UI.AddMover then UI.AddMover(w) end
    local gear = CreateFrame("Button", nil, w.header)
    gear:SetSize(16, 16)
    gear:SetPoint("RIGHT", w.CloseButton, "LEFT", -4, 0)
    gear.icon = gear:CreateTexture(nil, "ARTWORK")
    gear.icon:SetAllPoints()
    gear.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    gear.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    gear.icon:SetAlpha(0.8)
    gear:SetScript("OnClick", function() ns.ToggleOptions() end)
    gear:SetScript("OnEnter", function(self) self.icon:SetAlpha(1) SimpleTip(self, L("TIP_GEAR")) end)
    gear:SetScript("OnLeave", function(self) self.icon:SetAlpha(0.8) HideTip() end)
    Restore()
    return w
end
ns.SimpleTip, ns.HideTip = SimpleTip, HideTip

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
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "CURRENCY_DISPLAY_UPDATE", "QUEST_ACCEPTED",
        "QUEST_REMOVED" }) do
        pcall(events.RegisterEvent, events, event)
    end
    -- Handel: Taschen öffnen und rechts ans Handelsfenster hängen; beim Schließen des Handels wieder zu, wenn wir
    -- sie geöffnet hatten
    local trade = CreateFrame("Frame")
    local openedForTrade = false
    for _, event in ipairs({ "TRADE_SHOW", "TRADE_CLOSED" }) do pcall(trade.RegisterEvent, trade, event) end
    trade:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SHOW" then
            openedForTrade = not window:IsShown()
            window.fbagsDetached = nil
            ns.OpenBags()
            -- (das Handelsfenster ist im selben Moment erst im Aufbau: kurz danach nochmals anlegen)
            for _, delay in ipairs({ 0, 0.1, 0.3 }) do C_Timer.After(delay, function() pcall(PlaceOnOpen) end) end
        else
            if openedForTrade then ns.CloseBags() end
            openedForTrade = false
        end
    end)
end

---------------------------------------------------------------------------
-- Berufe am Rand: eine schmale Leiste bündig am rechten Fensterrand (gleicher Rahmen wie das Fenster) mit
-- Knöpfen für die Berufsfenster (je Beruf das erste Fenster, dazu Gifte/Wildtierausbildung). Ein Knopf in der
-- Titelleiste (links neben dem Zahnrad) klappt sie ein/aus (ns.db.profCollapsed).
-- Öffnen ist ein Zauber -> geschützte Knöpfe (SecureActionButtonTemplate). Solche Knöpfe (und ihr Halter) dürfen
-- im Kampf nicht ein-/ausgeblendet werden: der Halter hängt deshalb NICHT am Fenster, sondern ist eigenständig;
-- zu Kampfbeginn (PLAYER_REGEN_DISABLED, kurz bevor die Sperre greift) wird er ausgeblendet und fest an den
-- Bildschirm gehängt, nach dem Kampf wieder angezeigt. Aufbau nur außerhalb des Kampfs.
---------------------------------------------------------------------------
do
    local SIZE, GAP, INSET = 22, 2, 3
    local CLASS_TRADES = { 2842, 5149 } -- Gifte (Schurke), Wildtierausbildung (Jäger)
    local holder, tab
    local buttons = {}
    local dirty = true

    local function Known(spellID)
        if C_SpellBook and C_SpellBook.IsSpellKnown then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
            if ok and known then return true end
        end
        return IsPlayerSpell and IsPlayerSpell(spellID) or false
    end

    local function BookSpell(slot)
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
            local info = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if info and info.spellID and not info.isPassive then return info.spellID end
        end
    end

    -- je Beruf das Berufsfenster (erste aktive Fähigkeit des Berufs), Sammelberufe ohne Fenster fallen weg
    local function Professions()
        local list = {}
        if GetProfessions and GetProfessionInfo then
            local indices = { GetProfessions() }
            for i = 1, 6 do
                local index = indices[i]
                if index then
                    local name, icon, _, _, numSpells, offset = GetProfessionInfo(index)
                    local spellID = (numSpells or 0) > 0 and BookSpell((offset or 0) + 1)
                    if spellID and i ~= 4 then -- 4 = Angeln (kein Berufsfenster)
                        list[#list + 1] = { spell = spellID, name = name, icon = icon }
                    end
                end
            end
        end
        for _, id in ipairs(CLASS_TRADES) do
            if Known(id) then
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                list[#list + 1] = { spell = id, name = name, icon = icon }
            end
        end
        return list
    end

    local function Flat(f, hover)
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95)
        local e = hover and C.accent or C.border
        f:SetBackdropBorderColor(e[1], e[2], e[3], hover and 0.9 or 1)
    end

    local function Button(i)
        local b = buttons[i]
        if b then return b end
        b = CreateFrame("Button", "ForeverBagsProfession" .. i, holder, "SecureActionButtonTemplate,BackdropTemplate")
        b:SetSize(SIZE, SIZE)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "spell")
        Flat(b)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:SetAlpha(0.85)
        b:HookScript("OnEnter", function(self)
            Flat(self, true)
            self.icon:SetAlpha(1)
            if self.fbName then SimpleTip(self, self.fbName) end
        end)
        b:HookScript("OnLeave", function(self)
            Flat(self)
            self.icon:SetAlpha(0.85)
            HideTip()
        end)
        buttons[i] = b
        return b
    end

    local function Anchor()
        -- 1 px überlappend: Leiste und Fenster teilen sich den Rand, unter der Titelleiste
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", window, "TOPRIGHT", -1, -HEADER + 1)
    end

    -- Knöpfe neu belegen (nur außerhalb des Kampfs)
    local function Rebuild()
        if InCombatLockdown() or not holder then return end
        local list = Professions()
        for i, entry in ipairs(list) do
            local b = Button(i)
            b:SetAttribute("spell", entry.spell)
            b.icon:SetTexture(entry.icon)
            b.fbName = entry.name
            b:ClearAllPoints()
            b:SetPoint("TOP", holder, "TOP", 0, -INSET - (i - 1) * (SIZE + GAP))
            b:Show()
        end
        for i = #list + 1, #buttons do buttons[i]:Hide() end
        holder:SetSize(SIZE + 2 * INSET, math.max(1, #list * (SIZE + GAP) - GAP) + 2 * INSET)
        holder.count = #list
        if list[1] then tab.icon:SetTexture(list[1].icon) end -- Schalter zeigt das Symbol des ersten Berufs
        dirty = false
    end

    local function Update()
        if not (holder and tab) then return end
        local open = window and window:IsShown()
        tab:SetShown((holder.count or 0) > 0)
        tab.icon:SetDesaturated(ns.db.profCollapsed and true or false) -- eingeklappt: grau
        if InCombatLockdown() then return end -- im Kampf nichts an geschützten Rahmen ändern
        if dirty then Rebuild() end
        Anchor()
        holder:SetShown(open and not ns.db.profCollapsed and (holder.count or 0) > 0 and true or false)
    end
    ns.UpdateProfessionEdge = Update

    local function Setup()
        if holder or not window or InCombatLockdown() then return end
        holder = CreateFrame("Frame", "ForeverBagsProfessions", UIParent, "BackdropTemplate")
        holder:SetFrameStrata(window:GetFrameStrata())
        UI.SetFlat(holder, C.background) -- wie das Fenster selbst
        holder:Hide()
        -- Schalter in der Titelleiste links neben dem Zahnrad (gehört zum Fenster, nicht geschützt)
        tab = HeaderButton("Interface\\Icons\\INV_Misc_Book_09", "", function()
            ns.db.profCollapsed = not ns.db.profCollapsed
            Update()
        end)
        tab:SetPoint("RIGHT", window.gear, "LEFT", -6, 0)
        tab:SetScript("OnEnter", function(self)
            self.icon:SetAlpha(1)
            SimpleTip(self, ns.db.profCollapsed and L("PROF_SHOW") or L("PROF_HIDE"))
        end)
        window:HookScript("OnShow", Update)
        window:HookScript("OnHide", Update)
        Rebuild()
        Update()
    end

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- kurz vor der Kampfsperre: ausblenden und vom Fenster lösen (das Fenster darf im Kampf weiter wandern)
            if holder then
                local l, t = holder:GetLeft(), holder:GetTop()
                holder:Hide()
                if l and t then
                    holder:ClearAllPoints()
                    holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
                end
            end
            return
        end
        if event ~= "PLAYER_REGEN_ENABLED" then dirty = true end
        if not holder then
            C_Timer.After(1, function() pcall(Setup) end)
        else
            C_Timer.After(0.2, function() pcall(Update) end)
        end
    end)
end
