-- ForeverAlts – Window.lua: Übersicht aller Charaktere als Tabelle (Klick auf eine Spaltenüberschrift sortiert).
-- Maus über einer Zeile: alle Einzelheiten; Rechtsklick: Taschen/Bank (ForeverBags), Dungeon (ForeverQuests), Vergessen.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local ROW_H = 22
local PAD = 12
-- Spalten: Schlüssel, Überschrift, Breite, Sortierung (nil = nicht sortierbar)
local COLUMNS = {
    { key = "name",   title = function() return T("Charakter", "Character") end, width = 170, sort = "name" },
    { key = "level",  title = function() return T("Stufe", "Level") end,         width = 60,  sort = "level" },
    { key = "rested", title = function() return T("Erholung", "Rested") end,     width = 76,  sort = "rested" },
    { key = "money",  title = function() return T("Gold", "Gold") end,           width = 120, sort = "money" },
    { key = "zone",   title = function() return T("Ort", "Location") end,        width = 150, sort = "updated" },
    { key = "profs",  title = function() return T("Berufe", "Professions") end,  width = 150 },
    { key = "quests", title = function() return T("Quests", "Quests") end,       width = 64 },
}
local WIDTH = PAD * 2 + 16
for _, col in ipairs(COLUMNS) do WIDTH = WIDTH + col.width end

local window, scroll, content, footer, headerButtons
local rows = {}

local function Money(value)
    value = value or 0
    if GetMoneyString then return GetMoneyString(value, true) end
    return tostring(math.floor(value / 10000)) .. "g"
end

local function Short(n)
    if not n then return "?" end
    if n >= 10000 then return string.format("%.1fK", n / 1000) end
    return tostring(n)
end

-- "vor 3 Std." usw.
local function Ago(timestamp)
    if not timestamp then return "?" end
    local s = math.max(0, time() - timestamp)
    if s < 120 then return T("gerade eben", "just now") end
    if s < 7200 then return string.format(T("vor %d Min.", "%d min ago"), math.floor(s / 60)) end
    if s < 172800 then return string.format(T("vor %d Std.", "%d h ago"), math.floor(s / 3600)) end
    return string.format(T("vor %d Tagen", "%d days ago"), math.floor(s / 86400))
end

local function DungeonQuests(c)
    local list = {}
    for questID, q in pairs(c.quests or {}) do
        if q.dungeon then list[#list + 1] = { id = questID, q = q } end
    end
    table.sort(list, function(a, b)
        if a.q.dungeon ~= b.q.dungeon then return a.q.dungeon < b.q.dungeon end
        return (a.q.title or "") < (b.q.title or "")
    end)
    return list
end

local function BagsAPI() return UI.API and UI.API.ForeverBags end
local function QuestsAPI() return UI.API and UI.API.ForeverQuests end

---------------------------------------------------------------------------
-- Tooltip einer Zeile
---------------------------------------------------------------------------
local function RowTooltip(row)
    local entry = row.entry
    if not entry then return end
    local c = entry.data
    local tip = UI.GetTooltip()
    tip:SetOwner(row, "ANCHOR_RIGHT")
    tip:AddDoubleLine(ns.ColoredName(c), c.realm or "", 1, 1, 1, 0.6, 0.6, 0.6)
    tip:AddLine(string.format(T("Stufe %s %s", "Level %s %s"), c.level or "?", c.race or ""), 0.85, 0.85, 0.85)
    if c.xpMax and c.xpMax > 0 and not (c.maxLevel and c.level and c.level >= c.maxLevel) then
        tip:AddLine(string.format(T("Erfahrung: %s / %s (%d %%)", "Experience: %s / %s (%d %%)"), Short(c.xp), Short(c.xpMax),
            math.floor((c.xp or 0) / c.xpMax * 100)), 0.6, 0.6, 1)
        local rested, estimated = ns.RestedPercent(entry)
        if rested then
            tip:AddLine(string.format(estimated and T("Erholt: ≈ %d %% (geschätzt)", "Rested: ≈ %d %% (estimated)")
                or T("Erholt: %d %%", "Rested: %d %%"), rested), 0.3, 0.6, 1)
        end
    end
    if c.ilvl then tip:AddLine(string.format(T("Gegenstandsstufe: %d", "Item level: %d"), c.ilvl), 0.85, 0.85, 0.85) end
    tip:AddDoubleLine(T("Gold", "Gold"), Money(c.money), 0.85, 0.85, 0.85, 1, 1, 1)
    if c.zone then
        tip:AddDoubleLine(T("Ort", "Location"), c.zone .. ((c.subZone and c.subZone ~= "" and c.subZone ~= c.zone)
            and (" – " .. c.subZone) or ""), 0.85, 0.85, 0.85, 1, 1, 1)
    end
    tip:AddDoubleLine(T("Zuletzt gesehen", "Last seen"), entry.me and T("jetzt", "now") or Ago(c.updated),
        0.85, 0.85, 0.85, 0.7, 0.7, 0.7)
    local bags = BagsAPI()
    if bags and bags.FreeSlots then
        local free, total = bags.FreeSlots(entry.key)
        if free then tip:AddDoubleLine(T("Taschen frei", "Free bag slots"), free .. " / " .. total, 0.85, 0.85, 0.85, 1, 1, 1) end
    end
    if c.profs and #c.profs > 0 then
        tip:AddLine(" ")
        tip:AddLine(T("Berufe", "Professions"), C.accent[1], C.accent[2], C.accent[3])
        for _, p in ipairs(c.profs) do
            local icon = p.icon and ("|T" .. p.icon .. ":14:14:0:0|t ") or ""
            tip:AddDoubleLine(icon .. (p.name or "?"), (p.rank or "?") .. " / " .. (p.max or "?"), 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    local dungeon = DungeonQuests(c)
    if #dungeon > 0 then
        tip:AddLine(" ")
        tip:AddLine(T("Dungeonquests im Log", "Dungeon quests in the log"), C.accent[1], C.accent[2], C.accent[3])
        for _, d in ipairs(dungeon) do
            local state = d.q.complete and ("|cff00ff00" .. T("fertig", "done") .. "|r")
                or (d.q.total and (d.q.done .. "/" .. d.q.total)) or ""
            tip:AddDoubleLine((d.q.title or ("Quest " .. d.id)) .. " |cff8a8a8a– " .. d.q.dungeon .. "|r", state,
                1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    if c.questCount then
        tip:AddLine(string.format(T("%d Quests im Log", "%d quests in the log"), c.questCount), 0.6, 0.6, 0.6)
    end
    tip:AddLine(" ")
    tip:AddLine(T("Rechtsklick: Taschen, Bank, Dungeon, Vergessen", "Right-click: bags, bank, dungeon, forget"), 0.5, 0.5, 0.5)
    tip:Show()
end

---------------------------------------------------------------------------
-- Rechtsklick-Menü einer Zeile
---------------------------------------------------------------------------
StaticPopupDialogs["FOREVERALTS_FORGET"] = {
    text = T("%s aus der Übersicht entfernen? (Kommt beim nächsten Login dieses Charakters zurück.)",
        "Remove %s from the overview? (Returns the next time this character logs in.)"),
    button1 = YES, button2 = NO,
    OnAccept = function(_, key)
        ns.ForgetCharacter(key)
        ns.RefreshWindow()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function RowMenu(row)
    local entry = row.entry
    if not entry then return end
    local items = { { title = ns.ColoredName(entry.data) } }
    local bags = BagsAPI()
    if bags and bags.ShowCharacter then
        items[#items + 1] = { text = T("Taschen ansehen", "Show bags"), onClick = function() bags.ShowCharacter(entry.key, "bags") end }
        local hasBank = bags.HasBank and bags.HasBank(entry.key)
        items[#items + 1] = { text = hasBank and T("Bank ansehen", "Show bank") or T("Bank (noch nicht besucht)", "Bank (not visited yet)"),
            disabled = not hasBank, onClick = function() bags.ShowCharacter(entry.key, "bank") end }
    end
    local quests = QuestsAPI()
    if quests and quests.ShowDungeonOfQuest then
        local seen, divider = {}, false
        for _, d in ipairs(DungeonQuests(entry.data)) do
            if not seen[d.q.dungeon] then
                seen[d.q.dungeon] = true
                if not divider then
                    items[#items + 1] = { divider = true }
                    divider = true
                end
                items[#items + 1] = { text = string.format(T("Dungeon: %s", "Dungeon: %s"), d.q.dungeon),
                    onClick = function() quests.ShowDungeonOfQuest(d.id) end }
            end
        end
    end
    if not entry.me then
        items[#items + 1] = { divider = true }
        items[#items + 1] = { text = T("Vergessen …", "Forget …"), onClick = function()
            StaticPopup_Show("FOREVERALTS_FORGET", entry.data.name or entry.key, nil, entry.key)
        end }
    end
    UI.ShowMenu(row, items, { atCursor = true })
end

---------------------------------------------------------------------------
-- Zeilen
---------------------------------------------------------------------------
local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(3)
    row.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
    row.cells = {}
    local x = 8
    for j, col in ipairs(COLUMNS) do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(col.width - 8)
        fs:SetJustifyH(col.key == "money" and "RIGHT" or "LEFT")
        fs:SetWordWrap(false)
        row.cells[j] = fs
        x = x + col.width
    end
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)
    row:SetScript("OnClick", function(self, button) if button == "RightButton" then RowMenu(self) end end)
    rows[i] = row
    return row
end

local function CellTexts(entry)
    local c = entry.data
    local maxed = c.maxLevel and c.level and c.level >= c.maxLevel
    local level = tostring(c.level or "?")
    if not maxed and c.xpMax and c.xpMax > 0 then
        level = level .. string.format(" |cff8a8a8a%d%%|r", math.floor((c.xp or 0) / c.xpMax * 100))
    end
    local rested, estimated = ns.RestedPercent(entry)
    local restedText = rested and string.format("|cff4d99ff%s%d %%|r", estimated and "≈ " or "", rested) or "|cff6a6a6a–|r"
    local profs = {}
    for _, p in ipairs(c.profs or {}) do profs[#profs + 1] = (p.name or "?") .. " " .. (p.rank or "") end
    local dungeon = #DungeonQuests(c)
    local quests = tostring(c.questCount or 0)
    if dungeon > 0 then quests = quests .. string.format(" |cffffd100(%d)|r", dungeon) end
    return {
        ns.ColoredName(c) .. (entry.me and (" |cff8a8a8a" .. T("(du)", "(you)") .. "|r") or ""),
        level, restedText, Money(c.money),
        "|cffbbbbbb" .. (c.zone or "?") .. "|r",
        "|cffbbbbbb" .. (#profs > 0 and table.concat(profs, ", ") or "–") .. "|r",
        quests,
    }
end

function ns.RefreshWindow()
    if not window or not window:IsShown() then return end
    local list = ns.Characters()
    local width = WIDTH - PAD * 2 - 16
    content:SetWidth(width)
    local total = 0
    for i, entry in ipairs(list) do
        local row = GetRow(i)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetWidth(width)
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
        row.mark:SetShown(entry.me)
        for j, text in ipairs(CellTexts(entry)) do row.cells[j]:SetText(text) end
        row:Show()
        total = total + (entry.data.money or 0)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * ROW_H))
    footer:SetText(string.format(T("%d Charaktere  ·  Gold gesamt: %s", "%d characters  ·  total gold: %s"), #list, Money(total)))
    local db = ns.GetDB()
    for _, b in ipairs(headerButtons) do
        local active = b.sort and b.sort == db.sortKey
        b.text:SetText(b.title())
        b.text:SetTextColor(active and C.accent[1] or 0.8, active and C.accent[2] or 0.8, active and C.accent[3] or 0.8)
        -- Pfeil hinter der aktiven Spalte (Text-Pfeile kennt die WoW-Schrift nicht)
        b.arrow:SetShown(active and true or false)
        b.arrow:SetTexture(db.sortDesc and "Interface\\Buttons\\Arrow-Down-Up" or "Interface\\Buttons\\Arrow-Up-Up")
    end
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local function Build()
    window = UI.Window("ForeverAltsWindow", T("Twinks", "Alts"), WIDTH, 440)
    window:SetResizeBounds(WIDTH, 220, WIDTH, 1000)

    -- Spaltenüberschriften (Klick: danach sortieren, nochmal: umdrehen)
    headerButtons = {}
    local x = PAD + 8 -- wie die Zellen der Zeilen (Inhalt beginnt bei PAD, Zellen 8 weiter innen)
    for _, col in ipairs(COLUMNS) do
        local b = CreateFrame("Button", nil, window)
        b:SetSize(col.width, 20)
        b:SetPoint("TOPLEFT", x, -34)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("LEFT")
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetSize(12, 12)
        b.arrow:SetPoint("LEFT", b.text, "RIGHT", 2, 0)
        b.arrow:Hide()
        b.sort, b.title = col.sort, col.title
        if col.sort then
            b:SetScript("OnClick", function(self)
                local db = ns.GetDB()
                if db.sortKey == self.sort then db.sortDesc = not db.sortDesc else db.sortKey, db.sortDesc = self.sort, self.sort ~= "name" end
                ns.RefreshWindow()
            end)
        end
        headerButtons[#headerButtons + 1] = b
        x = x + col.width
    end
    local line = window:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", PAD, -56)
    line:SetPoint("TOPRIGHT", -PAD, -56)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)

    scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", PAD, -60)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 16, 40)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 2)))
    end)

    footer = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", PAD + 4, 16)
    local settings = UI.Button(window, T("Einstellungen", "Settings"), 110, function() ns.ToggleOptions() end)
    settings:SetPoint("BOTTOMRIGHT", -PAD - 16, 10)

    window:HookScript("OnShow", ns.Safe("Fenster", function()
        ns.Update() -- eigener Stand frisch
        ns.RefreshWindow()
    end))
end

function ns.ToggleWindow()
    if not window then Build() end
    window:SetShown(not window:IsShown())
end
