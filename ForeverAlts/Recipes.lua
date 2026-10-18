-- ForeverAlts – Recipes.lua: Rezepte jedes Charakters und ein eigenes Berufsfenster dafür.
-- Blizzards Berufsfenster zeigt nur die Berufe des eingeloggten Charakters (verlinkte Berufe brauchen Daten vom
-- Server, für ausgeloggte Charaktere öffnet es sich nicht). Darum merkt sich ForeverAlts beim Öffnen des EIGENEN
-- Berufsfensters alles, was das Fenster zeigt – Kategorien, Schwierigkeitsfarbe, Ergebnis und Reagenzien – und zeigt
-- es später auf jedem Charakter in einem Fenster im Aufbau des Berufsfensters: links die Rezepte nach Kategorien mit
-- Suche, rechts das gewählte Rezept mit Reagenzien (mit ForeverBags: wie viele du und alle Twinks davon haben).
-- Dazu im Gegenstands-Tooltip "Herstellbar von: …". Gelesen wird über C_TradeSkillUI oder – falls der Client die
-- alte Schnittstelle hat – über GetTradeSkillInfo bzw. GetCraftInfo (Verzauberkunst). Gespeichert in
-- ForeverAltsData.chars[...].recipes[Beruf] = { updated, rank, max, list = { { name, icon, item, cat, diff, desc,
-- reagents = { { item, name, icon, count } } } } }
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local function ItemIDOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Schwierigkeit wie im Berufsfenster: orange (sicher Punkte), gelb, grün, grau (keine Punkte mehr)
local DIFF_COLOR = {
    optimal = { 1, 0.5, 0.25 }, medium = { 1, 1, 0 }, easy = { 0.25, 0.75, 0.25 }, trivial = { 0.5, 0.5, 0.5 },
}
local DIFF_MODERN = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

---------------------------------------------------------------------------
-- Lesen (nur das eigene, offene Berufsfenster)
---------------------------------------------------------------------------
local function ReadModern()
    local TS = C_TradeSkillUI
    if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo) then return nil end
    local ok, ids = pcall(TS.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return nil end
    local prof, rank, max
    if TS.GetBaseProfessionInfo then
        local okInfo, info = pcall(TS.GetBaseProfessionInfo)
        if okInfo and info then prof, rank, max = info.professionName, info.skillLevel, info.maxSkillLevel end
    end
    if (not prof or prof == "") and TS.GetTradeSkillLine then
        local okLine, _, name, r, m = pcall(TS.GetTradeSkillLine)
        if okLine then prof, rank, max = name, r, m end
    end
    local list = {}
    for _, id in ipairs(ids) do
        local okRecipe, r = pcall(TS.GetRecipeInfo, id)
        if okRecipe and r and r.learned and r.name then
            local entry = { name = r.name, icon = r.icon, diff = DIFF_MODERN[r.relativeDifficulty], reagents = {} }
            if r.categoryID and TS.GetCategoryInfo then
                local okCat, cat = pcall(TS.GetCategoryInfo, r.categoryID)
                entry.cat = okCat and cat and cat.name or nil
            end
            if TS.GetRecipeItemLink then
                local okLink, link = pcall(TS.GetRecipeItemLink, id)
                entry.item = okLink and ItemIDOf(link) or nil
            end
            if not entry.item and TS.GetRecipeOutputItemData then
                local okOut, out = pcall(TS.GetRecipeOutputItemData, id)
                entry.item = okOut and out and out.itemID or nil
            end
            -- Reagenzien: neue Rezept-Beschreibung (Schematic) oder die ältere Einzel-Abfrage
            if TS.GetRecipeSchematic then
                local okS, s = pcall(TS.GetRecipeSchematic, id, false)
                for _, slot in ipairs(okS and s and s.reagentSlotSchematics or {}) do
                    local first = slot.reagents and slot.reagents[1]
                    local basic = not slot.reagentType or (Enum and Enum.CraftingReagentType
                        and slot.reagentType == Enum.CraftingReagentType.Basic) or slot.reagentType == 1
                    if first and first.itemID and basic then
                        entry.reagents[#entry.reagents + 1] = { item = first.itemID, count = slot.quantityRequired or 1 }
                    end
                end
            elseif TS.GetRecipeNumReagents and TS.GetRecipeReagentInfo then
                for i = 1, TS.GetRecipeNumReagents(id) or 0 do
                    local okR, name, icon, count = pcall(TS.GetRecipeReagentInfo, id, i)
                    if okR and name then
                        local link = TS.GetRecipeReagentItemLink and TS.GetRecipeReagentItemLink(id, i)
                        entry.reagents[#entry.reagents + 1] = { name = name, icon = icon, count = count, item = ItemIDOf(link) }
                    end
                end
            end
            list[#list + 1] = entry
        end
    end
    return prof, list, rank, max
end

local function ReadClassic(kind)
    local list, prof, rank, max = {}, nil, nil, nil
    local cat
    if kind == "craft" then
        if not GetNumCrafts then return nil end
        if GetCraftDisplaySkillLine then prof, rank, max = GetCraftDisplaySkillLine() end
        for i = 1, GetNumCrafts() or 0 do
            local name, _, craftType = GetCraftInfo(i)
            if craftType == "header" then
                cat = name
            elseif name then
                local entry = { name = name, icon = GetCraftIcon and GetCraftIcon(i), cat = cat, diff = craftType,
                    item = GetCraftItemLink and ItemIDOf(GetCraftItemLink(i)) or nil,
                    desc = GetCraftDescription and GetCraftDescription(i) or nil, reagents = {} }
                for r = 1, (GetCraftNumReagents and GetCraftNumReagents(i) or 0) do
                    local rName, rIcon, rCount = GetCraftReagentInfo(i, r)
                    entry.reagents[#entry.reagents + 1] = { name = rName, icon = rIcon, count = rCount,
                        item = GetCraftReagentItemLink and ItemIDOf(GetCraftReagentItemLink(i, r)) or nil }
                end
                list[#list + 1] = entry
            end
        end
    else
        if not GetNumTradeSkills then return nil end
        if GetTradeSkillLine then prof, rank, max = GetTradeSkillLine() end
        for i = 1, GetNumTradeSkills() or 0 do
            local name, skillType = GetTradeSkillInfo(i)
            if skillType == "header" or skillType == "subheader" then
                cat = name
            elseif name then
                local entry = { name = name, icon = GetTradeSkillIcon and GetTradeSkillIcon(i), cat = cat, diff = skillType,
                    item = GetTradeSkillItemLink and ItemIDOf(GetTradeSkillItemLink(i)) or nil,
                    desc = GetTradeSkillDescription and GetTradeSkillDescription(i) or nil, reagents = {} }
                for r = 1, (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i) or 0) do
                    local rName, rIcon, rCount = GetTradeSkillReagentInfo(i, r)
                    entry.reagents[#entry.reagents + 1] = { name = rName, icon = rIcon, count = rCount,
                        item = GetTradeSkillReagentItemLink and ItemIDOf(GetTradeSkillReagentItemLink(i, r)) or nil }
                end
                list[#list + 1] = entry
            end
        end
    end
    return prof, list, rank, max
end

-- Zeigt das Berufsfenster gerade einen verlinkten Beruf (eines Gildenmitglieds …)? Dann nicht speichern
local function IsLinked()
    local ok, linked = pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return true end
        if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return true end
        if IsTradeSkillLinked and IsTradeSkillLinked() then return true end
        return false
    end)
    return ok and linked
end

local function Save(kind)
    if IsLinked() then return end
    local prof, list, rank, max = ReadModern()
    if not list then prof, list, rank, max = ReadClassic(kind) end
    if not prof or prof == "" or prof == "UNKNOWN" or not list or #list == 0 then return end
    local c = ns.CharacterData(ns.CharKey())
    if not c then return end
    c.recipes = c.recipes or {}
    -- Reihenfolge wie im Berufsfenster: nach Kategorie (in der Reihenfolge des Spiels), darin nach Name
    local catIndex, n = {}, 0
    for _, r in ipairs(list) do
        if r.cat and not catIndex[r.cat] then
            n = n + 1
            catIndex[r.cat] = n
        end
    end
    table.sort(list, function(a, b)
        local ca, cb = catIndex[a.cat or ""] or 999, catIndex[b.cat or ""] or 999
        if ca ~= cb then return ca < cb end
        return a.name < b.name
    end)
    c.recipes[prof] = { updated = time(), rank = rank, max = max, list = list }
    ns.recipeVersion = (ns.recipeVersion or 0) + 1
end

local pending, scheduled = {}, false
local function Queue(kind)
    pending[kind] = true
    if scheduled then return end
    scheduled = true
    -- kurz warten: die Liste füllt sich nach dem Öffnen erst nach und nach
    C_Timer.After(1.5, ns.Safe("Rezepte", function()
        scheduled = false
        for k in pairs(pending) do Save(k) end
        pending = {}
    end))
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "NEW_RECIPE_LEARNED", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    Queue((event == "CRAFT_SHOW" or event == "CRAFT_UPDATE") and "craft" or "trade")
end)

---------------------------------------------------------------------------
-- Berufsfenster eines Charakters (Aufbau wie Blizzards Fenster)
---------------------------------------------------------------------------
local W, H, LIST_W = 680, 500, 300
local ROW_H = 18
local viewer, search, info, listContent, detail
local rows, reagentRows = {}, {}
local pendingItems = {}

local function BagsAPI() return UI.API and UI.API.ForeverBags end

-- Name/Symbol/Qualität eines Gegenstands; fehlt er noch im Speicher des Spiels, wird er angefordert
local function ItemInfo(itemID, fallbackName, fallbackIcon)
    if not itemID then return fallbackName, fallbackIcon, nil end
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if not name and not pendingItems[itemID] and Item and Item.CreateFromItemID then
        pendingItems[itemID] = true
        Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
            pendingItems[itemID] = nil
            if viewer and viewer:IsShown() then viewer.Refresh() end
        end)
    end
    return name or fallbackName, icon or fallbackIcon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)), quality
end

local function ItemTooltip(owner, itemID)
    if not itemID then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

local function LinkItem(itemID)
    if not itemID or not IsModifiedClick("CHATLINK") then return end
    local _, link = C_Item.GetItemInfo(itemID)
    if link then HandleModifiedItemClick(link) end
end

local function Data()
    local c = viewer and ns.CharacterData(viewer.key)
    return c and c.recipes and c.recipes[viewer.prof], c
end

-- rechte Seite: gewähltes Rezept
local function RefreshDetail()
    local data = Data()
    local r = data and viewer.selected and data.list[viewer.selected]
    detail:SetShown(r ~= nil)
    if not r then return end
    local name, icon, quality = ItemInfo(r.item, r.name, r.icon)
    detail.icon:SetTexture(r.icon or icon or 134400)
    detail.iconButton.item = r.item
    detail.name:SetText(r.name)
    local qr, qg, qb = 1, 0.82, 0
    if quality and C_Item.GetItemQualityColor then qr, qg, qb = C_Item.GetItemQualityColor(quality) end
    detail.name:SetTextColor(qr, qg, qb)
    local d = DIFF_COLOR[r.diff or ""]
    detail.sub:SetText((r.cat and (r.cat .. "  ·  ") or "") .. (d and string.format("|cff%02x%02x%02x%s|r", d[1] * 255, d[2] * 255,
        d[3] * 255, ({ optimal = T("bringt sicher Punkte", "always skill-up"), medium = T("bringt oft Punkte", "often skill-up"),
            easy = T("bringt selten Punkte", "rarely skill-up"), trivial = T("keine Punkte mehr", "no skill-up") })[r.diff] or "") or ""))
    detail.desc:SetText(r.desc or "")
    -- Reagenzien mit Bestand (mit ForeverBags: du / alle Charaktere)
    local bags = BagsAPI()
    local y = -(detail.desc:GetStringHeight() + 96)
    detail.reagentTitle:ClearAllPoints()
    detail.reagentTitle:SetPoint("TOPLEFT", 12, y)
    detail.reagentTitle:SetShown(#(r.reagents or {}) > 0)
    y = y - 22
    for i, rg in ipairs(r.reagents or {}) do
        local row = reagentRows[i]
        if not row then
            row = CreateFrame("Button", nil, detail, "BackdropTemplate")
            row:SetSize(W - LIST_W - 52, 34)
            UI.SetFlat(row, C.panel)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(28, 28)
            row.icon:SetPoint("LEFT", 3, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", -90, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.have = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.have:SetPoint("RIGHT", -8, 0)
            row.have:SetJustifyH("RIGHT")
            row:SetScript("OnEnter", function(self) ItemTooltip(self, self.item) end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnClick", function(self) LinkItem(self.item) end)
            reagentRows[i] = row
        end
        local rName, rIcon = ItemInfo(rg.item, rg.name, rg.icon)
        row.item = rg.item
        row.icon:SetTexture(rIcon or 134400)
        row.count:SetText((rg.count or 1) > 1 and rg.count or "")
        row.text:SetText(rName or T("Gegenstand lädt …", "Item loading …"))
        local have = ""
        if bags and bags.CountItem and rg.item then
            local mine, total = bags.CountItem(rg.item)
            have = string.format(T("du: %d  ·  alle: %d", "you: %d  ·  all: %d"), mine or 0, total or 0)
        end
        row.have:SetText(have)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 12, y)
        row:Show()
        y = y - 38
    end
    for i = #(r.reagents or {}) + 1, #reagentRows do reagentRows[i]:Hide() end
end

-- linke Seite: Liste nach Kategorien, gefiltert mit der Suche
local function RefreshList()
    local data, c = Data()
    local filter = strtrim(search:GetText() or ""):lower()
    local shown, lastCat, y = 0, nil, 0
    local function Row()
        shown = shown + 1
        local row = rows[shown]
        if not row then
            row = CreateFrame("Button", nil, listContent)
            row:SetHeight(ROW_H)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14)
            row.icon:SetPoint("LEFT", 14, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("RIGHT", -4, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
            row.hl = row:CreateTexture(nil, "HIGHLIGHT")
            row.hl:SetAllPoints()
            row.hl:SetColorTexture(1, 1, 1, 0.06)
            row:SetScript("OnClick", function(self)
                if not self.index then return end
                if self.item and IsModifiedClick("CHATLINK") then LinkItem(self.item) return end
                viewer.selected = self.index
                viewer.Refresh()
            end)
            row:SetScript("OnEnter", function(self) if self.item then ItemTooltip(self, self.item) end end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            rows[shown] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", listContent, "RIGHT")
        row:Show()
        y = y + ROW_H
        return row
    end
    local firstVisible
    for i, r in ipairs(data and data.list or {}) do
        if filter == "" or r.name:lower():find(filter, 1, true) or (r.cat and r.cat:lower():find(filter, 1, true)) then
            if r.cat ~= lastCat then
                lastCat = r.cat
                if r.cat then
                    -- Kategorie-Überschrift (gold, ohne Klick)
                    local head = Row()
                    head.index, head.item = nil, nil
                    head.icon:Hide()
                    head.sel:Hide()
                    head.hl:Hide()
                    head.text:ClearAllPoints()
                    head.text:SetPoint("LEFT", 4, 0)
                    head.text:SetPoint("RIGHT", -4, 0)
                    head.text:SetText(r.cat)
                    head.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
                end
            end
            local row = Row()
            row.index, row.item = i, r.item
            row.icon:Show()
            row.icon:SetTexture(r.icon or 134400)
            row.hl:Show()
            row.sel:SetShown(viewer.selected == i)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", -4, 0)
            row.text:SetText(r.name)
            local d = DIFF_COLOR[r.diff or ""] or { 0.9, 0.9, 0.9 }
            row.text:SetTextColor(d[1], d[2], d[3])
            firstVisible = firstVisible or i
        end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    listContent:SetHeight(math.max(1, y))
    -- gewähltes Rezept nicht (mehr) in der Liste: das erste sichtbare wählen
    if firstVisible and (not viewer.selected or not data.list[viewer.selected]) then viewer.selected = firstVisible end
    local rankText = data and data.rank and (" (" .. data.rank .. (data.max and ("/" .. data.max) or "") .. ")") or ""
    viewer.TitleText:SetText((c and ns.ColoredName(c) or "?") .. "|cffffd100 – " .. viewer.prof .. rankText .. "|r")
    info:SetText(string.format(T("%d Rezepte  ·  Stand: %s  ·  Shift-Klick: im Chat verlinken",
        "%d recipes  ·  as of %s  ·  Shift-click: link in chat"), data and #data.list or 0,
        data and date("%d.%m.%Y %H:%M", data.updated) or "?"))
end

local function Build()
    viewer = UI.Window("ForeverAltsRecipes", "", W, H)
    viewer.Refresh = function()
        if not viewer:IsShown() then return end
        RefreshList()
        RefreshDetail()
    end
    -- links: Suche und Liste
    search = UI.EditBox and UI.EditBox(viewer, LIST_W, 20) or CreateFrame("EditBox", nil, viewer, "InputBoxTemplate")
    search:SetSize(LIST_W, 20)
    search:SetPoint("TOPLEFT", 12, -36)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() viewer.Refresh() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText(T("Suchen …", "Search …"))
    search:HookScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)

    local listBox = CreateFrame("Frame", nil, viewer, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", 12, -62)
    listBox:SetPoint("BOTTOMLEFT", 12, 30)
    listBox:SetWidth(LIST_W)
    UI.SetFlat(listBox, C.panel)
    local scroll = CreateFrame("ScrollFrame", nil, listBox)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    listContent = CreateFrame("Frame", nil, scroll)
    listContent:SetSize(LIST_W - 8, 1)
    scroll:SetScrollChild(listContent)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, listContent:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 3)))
    end)

    -- rechts: gewähltes Rezept
    detail = CreateFrame("Frame", nil, viewer, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 10, 26)
    detail:SetPoint("BOTTOMRIGHT", -12, 30)
    UI.SetFlat(detail, C.panel)
    detail.iconButton = CreateFrame("Button", nil, detail)
    detail.iconButton:SetSize(44, 44)
    detail.iconButton:SetPoint("TOPLEFT", 12, -12)
    detail.icon = detail.iconButton:CreateTexture(nil, "ARTWORK")
    detail.icon:SetAllPoints()
    detail.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    detail.iconButton:SetScript("OnEnter", function(self) ItemTooltip(self, self.item) end)
    detail.iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    detail.iconButton:SetScript("OnClick", function(self) LinkItem(self.item) end)
    detail.name = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detail.name:SetPoint("TOPLEFT", detail.iconButton, "TOPRIGHT", 10, -2)
    detail.name:SetPoint("RIGHT", -12, 0)
    detail.name:SetJustifyH("LEFT")
    detail.sub = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.sub:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -6)
    detail.sub:SetPoint("RIGHT", -12, 0)
    detail.sub:SetJustifyH("LEFT")
    detail.desc = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.desc:SetPoint("TOPLEFT", 12, -70)
    detail.desc:SetPoint("RIGHT", -12, 0)
    detail.desc:SetJustifyH("LEFT")
    detail.desc:SetTextColor(0.8, 0.8, 0.8)
    detail.reagentTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detail.reagentTitle:SetText(T("Reagenzien", "Reagents"))

    info = viewer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("BOTTOMLEFT", 14, 10)
    viewer:HookScript("OnShow", function() viewer.Refresh() end)
end

function ns.ShowRecipes(key, prof)
    if not viewer then Build() end
    if viewer.key ~= key or viewer.prof ~= prof then viewer.selected = nil end
    viewer.key, viewer.prof = key, prof
    search:SetText("")
    viewer:Show()
    viewer:Raise()
    viewer.Refresh()
end

-- bekannte Berufe mit Rezepten eines Charakters: { { prof, count } }
function ns.RecipeProfessions(c)
    local list = {}
    for prof, data in pairs(c and c.recipes or {}) do list[#list + 1] = { prof = prof, count = #(data.list or {}) } end
    table.sort(list, function(a, b) return a.prof < b.prof end)
    return list
end

---------------------------------------------------------------------------
-- Gegenstands-Tooltip: welche Charaktere den Gegenstand herstellen können
---------------------------------------------------------------------------
local makers, makersVersion -- [itemID] = { "Name (Beruf)", … }
local function Makers(itemID)
    if makersVersion ~= ns.recipeVersion or not makers then
        makers, makersVersion = {}, ns.recipeVersion
        local me = ns.CharKey()
        for _, entry in ipairs(ns.Characters()) do
            for prof, data in pairs(entry.data.recipes or {}) do
                for _, r in ipairs(data.list or {}) do
                    if r.item then
                        makers[r.item] = makers[r.item] or {}
                        local who = ns.ColoredName(entry.data) .. (entry.key == me and (" |cff8a8a8a" .. T("(du)", "(you)") .. "|r") or "")
                        table.insert(makers[r.item], who .. " |cff8a8a8a(" .. prof .. ")|r")
                    end
                end
            end
        end
    end
    return makers[itemID]
end

local function AddMakers(tooltip, itemID)
    if not itemID or not ns.GetDB().recipeTooltip then return end
    local list = Makers(itemID)
    if not list or #list == 0 then return end
    tooltip:AddLine(T("Herstellbar von: ", "Can be made by: ") .. table.concat(list, ", "), C.accent[1], C.accent[2], C.accent[3], true)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        pcall(AddMakers, tooltip, data and data.id)
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local _, link = tooltip:GetItem()
        pcall(AddMakers, tooltip, ItemIDOf(link))
    end)
end
-- neue Rezepte ⇒ Herstellerliste neu aufbauen
ns.recipeVersion = 0
