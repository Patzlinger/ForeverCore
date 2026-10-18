-- ForeverAlts – Recipes.lua: Rezepte jedes Charakters. Ein fremdes Berufsfenster lässt sich nicht öffnen – darum merkt
-- sich ForeverAlts die Rezepte, sobald ein Charakter sein EIGENES Berufsfenster öffnet (einmal pro Beruf reicht, danach
-- bei jedem Öffnen aktualisiert). Anzeige: Rechtsklick in der Übersicht » "Rezepte: …" (Liste mit Suche), und im
-- Gegenstands-Tooltip "Herstellbar von: …", wenn ein Twink das Rezept kennt.
-- Gelesen wird über die neue Berufs-Schnittstelle (C_TradeSkillUI) oder, falls der Client die alte hat, über
-- GetTradeSkillInfo bzw. GetCraftInfo (z. B. Verzauberkunst). Gespeichert in ForeverAltsData.chars[...].recipes.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local function ItemIDOf(link)
    return link and tonumber(link:match("item:(%d+)")) or nil
end

-- neue Schnittstelle: Liste aller gelernten Rezepte des offenen Berufs
local function ReadModern()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return nil end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return nil end
    local prof
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local okInfo, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        prof = okInfo and info and info.professionName
    end
    if (not prof or prof == "") and C_TradeSkillUI.GetTradeSkillLine then
        local okLine, _, name = pcall(C_TradeSkillUI.GetTradeSkillLine)
        prof = okLine and name or nil
    end
    local list = {}
    for _, id in ipairs(ids) do
        local okRecipe, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
        if okRecipe and r and r.learned and r.name then
            local item
            if C_TradeSkillUI.GetRecipeItemLink then
                local okLink, link = pcall(C_TradeSkillUI.GetRecipeItemLink, id)
                item = okLink and ItemIDOf(link) or nil
            end
            list[#list + 1] = { name = r.name, icon = r.icon, item = item }
        end
    end
    return prof, list
end

-- alte Schnittstelle (Classic): Berufe über GetTradeSkillInfo, Verzauberkunst über GetCraftInfo
local function ReadClassic(kind)
    local list, prof = {}, nil
    if kind == "craft" then
        if not GetNumCrafts then return nil end
        prof = GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or (GetCraftSkillLine and GetCraftSkillLine(1))
        for i = 1, GetNumCrafts() or 0 do
            local name, _, craftType = GetCraftInfo(i)
            if name and craftType ~= "header" then
                list[#list + 1] = { name = name, icon = GetCraftIcon and GetCraftIcon(i),
                    item = GetCraftItemLink and ItemIDOf(GetCraftItemLink(i)) or nil }
            end
        end
    else
        if not GetNumTradeSkills then return nil end
        prof = GetTradeSkillLine and GetTradeSkillLine()
        for i = 1, GetNumTradeSkills() or 0 do
            local name, skillType = GetTradeSkillInfo(i)
            if name and skillType ~= "header" and skillType ~= "subheader" then
                list[#list + 1] = { name = name, icon = GetTradeSkillIcon and GetTradeSkillIcon(i),
                    item = GetTradeSkillItemLink and ItemIDOf(GetTradeSkillItemLink(i)) or nil }
            end
        end
    end
    return prof, list
end

-- Zeigt das Berufsfenster gerade einen verlinkten Beruf (eines Twinks, Gildenmitglieds …)? Dann nicht als eigene
-- Rezepte speichern
local function IsLinked()
    local ok, linked = pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return true end
        if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return true end
        if IsTradeSkillLinked and IsTradeSkillLinked() then return true end
        return false
    end)
    return ok and linked
end

-- Link auf die eigene Rezeptliste (damit ein anderer Charakter später Blizzards Berufsfenster damit öffnen kann)
local function ListLink()
    local ok, link = pcall(function()
        if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillListLink then return C_TradeSkillUI.GetTradeSkillListLink() end
        if GetTradeSkillListLink then return GetTradeSkillListLink() end
    end)
    return ok and type(link) == "string" and link ~= "" and link or nil
end

local function Save(kind)
    if IsLinked() then return end
    local prof, list = ReadModern()
    if not list then prof, list = ReadClassic(kind) end
    if not prof or prof == "" or prof == "UNKNOWN" or not list or #list == 0 then return end
    local c = ns.CharacterData(ns.CharKey())
    if not c then return end
    c.recipes = c.recipes or {}
    table.sort(list, function(a, b) return a.name < b.name end)
    c.recipes[prof] = { updated = time(), list = list, link = kind ~= "craft" and ListLink() or nil }
    ns.recipeVersion = (ns.recipeVersion or 0) + 1
end

-- Blizzards Berufsfenster mit den gespeicherten Rezepten eines Charakters öffnen (über den Link, den er beim
-- letzten Öffnen hinterlegt hat – wie ein Klick auf einen Berufs-Link im Chat). true = Link vorhanden und geöffnet.
function ns.OpenProfessionWindow(key, prof)
    local c = ns.CharacterData(key)
    local data = c and c.recipes and c.recipes[prof]
    if not (data and data.link) or InCombatLockdown() then return false end
    local linkData = data.link:match("|H(trade:[^|]+)|h")
    if not linkData then return false end
    local ok = pcall(SetItemRef, linkData, data.link, "LeftButton")
    return ok
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
-- Rezeptliste eines Charakters (Fenster mit Suche)
---------------------------------------------------------------------------
local viewer, viewRows, search, info = nil, {}, nil, nil
local ROW_H = 20

local function RefreshViewer()
    if not viewer or not viewer:IsShown() then return end
    local c = ns.CharacterData(viewer.key)
    local data = c and c.recipes and c.recipes[viewer.prof]
    local filter = strtrim(search:GetText() or ""):lower()
    local shown = 0
    for _, r in ipairs(data and data.list or {}) do
        if filter == "" or r.name:lower():find(filter, 1, true) then
            shown = shown + 1
            local row = viewRows[shown]
            if not row then
                row = CreateFrame("Button", nil, viewer.content)
                row:SetHeight(ROW_H)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", 4, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetPoint("RIGHT", -4, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.06)
                -- Gegenstand des Rezepts als Tooltip (falls bekannt), Shift-Klick verlinkt ihn
                row:SetScript("OnEnter", function(self)
                    if not self.item then return end
                    local tip = GameTooltip
                    tip:SetOwner(self, "ANCHOR_RIGHT")
                    tip:SetItemByID(self.item)
                    tip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row:SetScript("OnClick", function(self)
                    if self.item and IsModifiedClick("CHATLINK") then
                        local _, link = C_Item.GetItemInfo(self.item)
                        if link then HandleModifiedItemClick(link) end
                    end
                end)
                viewRows[shown] = row
            end
            row.item = r.item
            row.icon:SetTexture(r.icon or 134400)
            row.text:SetText(r.name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", viewer.content, "TOPLEFT", 0, -(shown - 1) * ROW_H)
            row:SetPoint("RIGHT", viewer.content, "RIGHT")
            row:Show()
        end
    end
    for i = shown + 1, #viewRows do viewRows[i]:Hide() end
    viewer.content:SetHeight(math.max(1, shown * ROW_H))
    info:SetText(string.format(T("%d von %d Rezepten  ·  Stand: %s", "%d of %d recipes  ·  as of %s"), shown,
        data and #data.list or 0, data and date("%d.%m.%Y %H:%M", data.updated) or "?"))
end

function ns.ShowRecipes(key, prof)
    if not viewer then
        viewer = UI.Window("ForeverAltsRecipes", "", 340, 460)
        search = UI.EditBox and UI.EditBox(viewer, 200, 20) or CreateFrame("EditBox", nil, viewer, "InputBoxTemplate")
        search:SetSize(316, 20)
        search:SetPoint("TOPLEFT", 12, -36)
        search:SetAutoFocus(false)
        search:SetScript("OnTextChanged", RefreshViewer)
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local scroll = CreateFrame("ScrollFrame", nil, viewer)
        scroll:SetPoint("TOPLEFT", 12, -64)
        scroll:SetPoint("BOTTOMRIGHT", -12, 34)
        viewer.content = CreateFrame("Frame", nil, scroll)
        viewer.content:SetSize(316, 1)
        scroll:SetScrollChild(viewer.content)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = math.max(0, viewer.content:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 3)))
        end)
        info = viewer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("BOTTOMLEFT", 14, 12)
        viewer:HookScript("OnShow", RefreshViewer)
    end
    viewer.key, viewer.prof = key, prof
    local c = ns.CharacterData(key)
    viewer.TitleText:SetText((c and ns.ColoredName(c) or "?") .. "|cffffd100 – " .. prof .. "|r")
    search:SetText("")
    viewer:Show()
    RefreshViewer()
end

-- bekannte Berufe mit Rezepten eines Charakters: { { prof, count } }
function ns.RecipeProfessions(c)
    local list = {}
    for prof, data in pairs(c and c.recipes or {}) do list[#list + 1] = { prof = prof, count = #(data.list or {}) } end
    table.sort(list, function(a, b) return a.prof < b.prof end)
    return list
end

---------------------------------------------------------------------------
-- Gegenstands-Tooltip: welche (anderen) Charaktere den Gegenstand herstellen können
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
        local ok = pcall(AddMakers, tooltip, data and data.id)
        if not ok then return end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local _, link = tooltip:GetItem()
        pcall(AddMakers, tooltip, ItemIDOf(link))
    end)
end
-- neue Rezepte ⇒ Herstellerliste neu aufbauen
ns.recipeVersion = 0
