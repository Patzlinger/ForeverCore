-- ForeverAlts – Window.lua: Übersicht aller Charaktere als Tabelle (Klick auf eine Spaltenüberschrift sortiert).
-- Maus über einer Zeile: alle Einzelheiten; Rechtsklick: Taschen/Bank (ForeverBags), Dungeon (ForeverQuests), Vergessen.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T
local C = UI.COLOR

local ROW_H = 32 -- zwei Textzeilen (Berufe)
local PAD = 12
local MIN_WIDTH = 560 -- Platz für die Spalten-Schalter unten
-- Spalten: Schlüssel, Überschrift, Breite, Sortierung (nil = nicht sortierbar), fixed = immer sichtbar.
-- Jede andere Spalte lässt sich unten im Fenster ein- und ausschalten (ns.GetDB().hiddenColumns).
local COLUMNS = {
    { key = "name",   title = function() return T("Charakter", "Character") end, width = 170, sort = "name", fixed = true },
    { key = "level",  title = function() return T("Stufe", "Level") end,         width = 70,  sort = "level" },
    { key = "rested", title = function() return T("Erholung", "Rested") end,     width = 80,  sort = "rested" },
    { key = "money",  title = function() return T("Gold", "Gold") end,           width = 130, sort = "money" },
    { key = "zone",   title = function() return T("Ort", "Location") end,        width = 140, sort = "zone" },
    { key = "profs",  title = function() return T("Berufe", "Professions") end,  width = 190 },
    { key = "played", title = function() return T("Spielzeit", "Played") end,    width = 84,  sort = "played" },
    { key = "mail",   title = function() return T("Post", "Mail") end,           width = 84,  sort = "mail" },
    { key = "honor",  title = function() return T("Ehre", "Honor") end,          width = 84,  sort = "honor" },
    { key = "last",   title = function() return T("Letzter Login", "Last login") end, width = 96, sort = "updated" },
}

local window, scroll, content, footer, headerButtons, toggles
local rows = {}

local function Visible(col) return col.fixed or not ns.GetDB().hiddenColumns[col.key] end

local function VisibleWidth()
    local w = 16
    for _, col in ipairs(COLUMNS) do if Visible(col) then w = w + col.width end end
    return w
end

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

-- Dauer in Sekunden: "12 T 4 Std" bzw. "5 Std 3 Min"
local function Duration(seconds)
    if not seconds then return nil end
    local days, hours, mins = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
    if days > 0 then return string.format(T("%d T %d Std", "%dd %dh"), days, hours) end
    return string.format(T("%d Std %d Min", "%dh %dm"), hours, mins)
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
        local recipes = {}
        for _, r in ipairs(ns.RecipeProfessions(c)) do recipes[r.prof] = r.count end
        for _, p in ipairs(c.profs) do
            local icon = p.icon and ("|T" .. p.icon .. ":14:14:0:0|t ") or ""
            local known = recipes[p.name] and string.format(T("  |cff8a8a8a%d Rezepte|r", "  |cff8a8a8a%d recipes|r"), recipes[p.name]) or ""
            tip:AddDoubleLine(icon .. (p.name or "?") .. known, (p.rank or "?") .. " / " .. (p.max or "?"), 1, 1, 1, 0.8, 0.8, 0.8)
        end
        tip:AddLine(T("Rezepte: Berufsfenster auf dem Charakter einmal öffnen", "Recipes: open the profession window on that character once"),
            0.5, 0.5, 0.5, true)
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
    tip:AddLine(" ")
    tip:AddLine(T("Rechtsklick: Taschen, Bank, Rezepte, Dungeon, Vergessen", "Right-click: bags, bank, recipes, dungeon, forget"), 0.5, 0.5, 0.5)
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
    -- Rezepte (gespeichert, sobald der Charakter sein Berufsfenster einmal geöffnet hat)
    local recipeProfs = ns.RecipeProfessions(entry.data)
    if #recipeProfs > 0 then
        items[#items + 1] = { divider = true }
        for _, r in ipairs(recipeProfs) do
            items[#items + 1] = { text = string.format(T("Rezepte: %s (%d)", "Recipes: %s (%d)"), r.prof, r.count),
                onClick = function() ns.ShowRecipes(entry.key, r.prof) end }
        end
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
    -- je Spalte eine obere und eine untere Zeile (die untere nutzen Stufe und Berufe); Lage setzt RefreshWindow
    row.cells, row.cells2 = {}, {}
    for j, col in ipairs(COLUMNS) do
        for _, list in ipairs({ row.cells, row.cells2 }) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWidth(col.width - 10)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            list[j] = fs
        end
    end
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() UI.GetTooltip():Hide() end)
    row:SetScript("OnClick", function(self, button) if button == "RightButton" then RowMenu(self) end end)
    rows[i] = row
    return row
end

-- Texte je Spalte: { obere Zeile, untere Zeile }
local function CellTexts(entry)
    local c = entry.data
    local maxed = c.maxLevel and c.level and c.level >= c.maxLevel
    local xpLine = (not maxed and c.xpMax and c.xpMax > 0)
        and string.format("|cff8a8a8a%d %% EP|r", math.floor((c.xp or 0) / c.xpMax * 100)) or ""
    local rested, estimated = ns.RestedPercent(entry)
    local restedText = rested and string.format("|cff4d99ff%s%d %%|r", estimated and "≈ " or "", rested) or "|cff6a6a6a–|r"
    -- Berufe auf zwei Zeilen: die ersten beiden oben, der Rest (meist Nebenberufe) unten
    local top, bottom = {}, {}
    for i, p in ipairs(c.profs or {}) do
        local text = (p.name or "?") .. " |cffffffff" .. (p.rank or "") .. "|r"
        table.insert(i <= 2 and top or bottom, text)
    end
    local subZone = (c.subZone and c.subZone ~= "" and c.subZone ~= c.zone) and c.subZone or ""
    -- gespielte Zeit: gesamt, darunter auf dieser Stufe
    local playedTotal, playedLevel = ns.PlayedNow(entry)
    local played = { playedTotal and Duration(playedTotal) or "|cff6a6a6a–|r",
        playedLevel and ("|cff8a8a8a" .. T("Stufe: ", "Level: ") .. Duration(playedLevel) .. "|r") or "" }
    -- Post: neu (gold), Anzahl im Briefkasten, früheste Ablaufzeit (rot unter 3 Tagen)
    local mail, mailLine = "|cff6a6a6a–|r", ""
    if c.mail then
        if c.mail.new then mail = "|cffffd100" .. T("Neue Post", "New mail") .. "|r"
        elseif c.mail.count and c.mail.count > 0 then mail = string.format(T("%d Briefe", "%d letters"), c.mail.count) end
        if c.mail.expires and c.mail.count and c.mail.count > 0 then
            local days = (c.mail.expires - time()) / 86400
            mailLine = string.format("%s" .. T("läuft ab: %d T", "expires: %dd") .. "|r", days < 3 and "|cffff5050" or "|cff8a8a8a",
                math.max(0, math.floor(days)))
        end
    end
    -- Ehre: Punkte, darunter Rang bzw. ehrenhafte Siege
    local honor = c.honor and BreakUpLargeNumbers and BreakUpLargeNumbers(c.honor) or (c.honor and tostring(c.honor)) or "|cff6a6a6a–|r"
    local honorLine = c.pvpRank or (c.honorKills and c.honorKills > 0 and string.format(T("%d Siege", "%d kills"), c.honorKills)) or ""
    return {
        name = { ns.ColoredName(c), "|cff6a6a6a" .. (c.realm or "") .. "|r" },
        played = played,
        mail = { mail, mailLine },
        honor = { "|cffe08050" .. honor .. "|r", "|cff8a8a8a" .. honorLine .. "|r" },
        last = { entry.me and ("|cff33ff99" .. T("eingeloggt", "logged in") .. "|r") or Ago(c.updated),
            c.updated and ("|cff8a8a8a" .. date("%d.%m. %H:%M", c.updated) .. "|r") or "" },
        level = { tostring(c.level or "?"), xpLine },
        rested = { restedText, "" },
        money = { Money(c.money), "" },
        zone = { "|cffbbbbbb" .. (c.zone or "?") .. "|r", "|cff8a8a8a" .. subZone .. "|r" },
        profs = { "|cffbbbbbb" .. (#top > 0 and table.concat(top, ", ") or "–") .. "|r",
            "|cff8a8a8a" .. table.concat(bottom, ", ") .. "|r" },
    }
end

function ns.RefreshWindow()
    if not window or not window:IsShown() then return end
    local list = ns.Characters()
    local inner = VisibleWidth()
    window:SetWidth(math.max(MIN_WIDTH, inner + PAD * 2))
    local width = inner - 16
    content:SetWidth(width)
    local total, playedSum = 0, 0
    for i, entry in ipairs(list) do
        playedSum = playedSum + (ns.PlayedNow(entry) or 0)
        local row = GetRow(i)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetWidth(width)
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
        row.mark:SetShown(entry.me)
        local texts, x = CellTexts(entry), 8
        for j, col in ipairs(COLUMNS) do
            local upper, lower = row.cells[j], row.cells2[j]
            local shown = Visible(col)
            upper:SetShown(shown)
            lower:SetShown(shown)
            if shown then
                local t = texts[col.key]
                upper:ClearAllPoints()
                lower:ClearAllPoints()
                -- nur eine Zeile: senkrecht mittig; zwei Zeilen: oben und unten
                if t[2] == "" then
                    upper:SetPoint("LEFT", x, 0)
                else
                    upper:SetPoint("TOPLEFT", x, -4)
                    lower:SetPoint("BOTTOMLEFT", x, 4)
                end
                upper:SetText(t[1])
                lower:SetText(t[2])
                x = x + col.width
            end
        end
        row:Show()
        total = total + (entry.data.money or 0)
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * ROW_H))
    footer:SetText(string.format(T("%d Charaktere  ·  Gold gesamt: %s", "%d characters  ·  total gold: %s"), #list, Money(total))
        .. (playedSum > 0 and ("  ·  " .. T("Spielzeit gesamt: ", "total played: ") .. Duration(playedSum)) or ""))
    local db = ns.GetDB()
    local hx = PAD + 8
    for i, b in ipairs(headerButtons) do
        b:SetShown(Visible(COLUMNS[i]))
        if b:IsShown() then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", window, "TOPLEFT", hx, -34)
            hx = hx + COLUMNS[i].width
        end
    end
    for _, cb in ipairs(toggles) do cb:SetChecked(Visible(cb.column)) end
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
    window = UI.Window("ForeverAltsWindow", T("Twinks", "Alts"), math.max(MIN_WIDTH, VisibleWidth() + PAD * 2), 460)

    -- Spaltenüberschriften (Klick: danach sortieren, nochmal: umdrehen); Lage setzt RefreshWindow
    headerButtons = {}
    for _, col in ipairs(COLUMNS) do
        local b = CreateFrame("Button", nil, window)
        b:SetSize(col.width, 20)
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
                if db.sortKey == self.sort then
                    db.sortDesc = not db.sortDesc
                else
                    db.sortKey, db.sortDesc = self.sort, self.sort ~= "name" and self.sort ~= "zone"
                end
                ns.RefreshWindow()
            end)
        end
        headerButtons[#headerButtons + 1] = b
    end
    local line = window:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", PAD, -56)
    line:SetPoint("TOPRIGHT", -PAD, -56)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.08)

    scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", PAD, -60)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 16, 72)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxScroll, math.max(0, self:GetVerticalScroll() - delta * ROW_H * 2)))
    end)

    -- Spalten ein-/ausschalten (unten, über der Fußzeile)
    local toggleLine = window:CreateTexture(nil, "ARTWORK")
    toggleLine:SetPoint("BOTTOMLEFT", PAD, 66)
    toggleLine:SetPoint("BOTTOMRIGHT", -PAD, 66)
    toggleLine:SetHeight(1)
    toggleLine:SetColorTexture(1, 1, 1, 0.08)
    toggles = {}
    local prev
    for _, col in ipairs(COLUMNS) do
        if not col.fixed then
            local cb = UI.Check(window, nil, nil, col.title(), ns.Safe(T("Spalten", "Columns"), function(checked)
                ns.GetDB().hiddenColumns[col.key] = (not checked) or nil
                ns.RefreshWindow()
            end))
            cb.column = col
            if prev then
                cb:SetPoint("LEFT", prev.label, "RIGHT", 16, 0)
            else
                cb:SetPoint("BOTTOMLEFT", PAD + 4, 44)
            end
            toggles[#toggles + 1] = cb
            prev = cb
        end
    end
    -- Mindestbreite: alle Spalten-Schalter passen nebeneinander
    local togglesWidth = 0
    for _, cb in ipairs(toggles) do togglesWidth = togglesWidth + 16 + 8 + cb.label:GetStringWidth() + 16 end
    MIN_WIDTH = math.max(MIN_WIDTH, math.ceil(togglesWidth) + PAD * 2 + 8)

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
