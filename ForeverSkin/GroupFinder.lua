-- ForeverSkin – GroupFinder.lua: Fenster "Suche nach Gruppe" (im Forever-Client LFGParentFrame) im Forever-Stil
-- (docs/Fenster-Stil.md). Auf Wunsch bleiben Hintergrund und die Grafiken der Knöpfe (Rollen, Kategorien, "Zurück",
-- "Selbst anmelden") unverändert – nur Rahmen und Titelleiste werden flach, das Auge (Porträt) sitzt klein links in
-- der Titelleiste. Die Knöpfe unten ("Zurück", "Selbst anmelden") werden flach. Rechts unter Blizzards Reitern ein
-- eigener Reiter, der das Dungeonfenster von ForeverQuests öffnet (Schnittstelle UI.API.ForeverQuests.Toggle).
local _, ns = ...

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "groupfinder/" .. what, err) end
end

local footerHeight -- Höhe unserer Fußleiste (sobald angelegt) – der Kasten der Innenfläche endet darüber
-- Seiten des Fensters: "Anmelden", "Durchsuchen", "Wer ist da" – alle gleich umgestaltet
local PAGES = { "LFGListingFrame", "LFGBrowseFrame", "LFGWhoListFrame" }

local function KeyOf(parent, child)
    for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
end

-- ganz verstecken (nicht nur durchsichtig – manche Grafiken setzt Blizzard per Animation wieder sichtbar, z. B. der
-- Steinstreifen "groupfinder-Stat-StoneBG" oben auf "Durchsuchen") und versteckt halten
local kept = setmetatable({}, { __mode = "k" })
local function KeepHidden(tex)
    if type(tex) ~= "table" or not tex.Hide then return end
    tex:SetAlpha(0)
    tex:Hide()
    if not kept[tex] then
        kept[tex] = true
        hooksecurefunc(tex, "Show", function(t) t:Hide() end)
    end
end

-- Innenfläche: Bild ("groupfinder-background") und verzierter Rahmen ("common-insideframe") weg – flache Fläche mit
-- feinem Rand; endet 6 über unserer Fußleiste (Blizzards Innenfläche reicht bis fast nach unten)
local function SkinInset(f, inset)
    for _, key in ipairs({ "CustomBG", "Border", "Bg", "NineSlice" }) do ns.Hide(inset[key]) end
    ns.HideTextures(inset)
    local cut = 0
    if footerHeight and inset:GetBottom() and f:GetBottom() then
        local s = inset:GetEffectiveScale() / f:GetEffectiveScale()
        local footTop = f:GetBottom() + footerHeight + 6
        cut = math.max(0, (footTop - inset:GetBottom() * s) / s)
    end
    ns.Flat(inset, ns.C.panel, { 0, 0, 0, cut })
end

-- Blizzards Rahmen und das runde Porträt: Blizzard blendet sie teils wieder ein – darum jedes Teil einzeln, immer wieder
local function HideFrameArt(f)
    for _, key in ipairs({ "NineSlice", "PortraitContainer", "PortraitFrame" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            ns.HideTextures(obj)
        end
    end
    local name = f:GetName()
    if name then
        for _, suffix in ipairs({ "Portrait", "PortraitFrame", "PortraitTexture" }) do ns.Hide(G(name .. suffix)) end
    end
    ns.Hide(f.portrait)
    ns.Hide(f.Portrait)
    -- Ring des Auges ("groupfinder-eye-frame" im Rahmen LFGParentFramePortrait) – unser kleines Auge sitzt in der
    -- Titelleiste
    local portrait = G("LFGParentFramePortrait")
    if type(portrait) == "table" and not Forbidden(portrait) then
        ns.Hide(portrait)
        if portrait.GetRegions then ns.HideTextures(portrait) end
    end
    ns.Hide(f.TopTileStreaks)
    -- Streifen hinter den Rollen-Symbolen (oben): "groupfinder-roles-background" und darunter der dunkle Hintergrund
    -- der Seite ("Bg") – weg, auf Wunsch; dort zeigt sich unsere Fläche. Das Bild der Innenfläche bleibt
    ns.Hide(G("LFGListingFrameRoleBackground"))
    -- die Seiten haben einen eigenen Metallrahmen mit Kopf oben (laut /fskin grafik: NineSlice mit
    -- "UI-Frame-PortraitMetal-…") und einen dunklen Seitenhintergrund ("Bg") – weg
    for _, pageName in ipairs(PAGES) do
        local page = G(pageName)
        if page and not Forbidden(page) then
            KeepHidden(page.Bg)
            KeepHidden(G(pageName .. "Bg"))
            -- Seiten ohne eigene Innenfläche (z. B. "Wer ist da"): Bild, verzierter Rahmen und Steinstreifen hängen
            -- direkt an der Seite (laut /fskin lfg) – weg; an die Stelle des Bildes unser flacher Kasten
            KeepHidden(page.headerBackground)
            KeepHidden(page.insideFrame)
            local art = page.BackgroundArt
            if type(art) == "table" and art.GetPoint then
                KeepHidden(art)
                if not page.foreverBox then
                    page.foreverBox = CreateFrame("Frame", nil, page)
                    page.foreverBox:SetAllPoints(art)
                    page.foreverBox:SetFrameLevel(math.max(0, page:GetFrameLevel()))
                end
                SkinInset(f, page.foreverBox)
            end
            for _, key in ipairs({ "NineSlice", "TitleContainer", "PortraitContainer" }) do
                local obj = page[key]
                if type(obj) == "table" and not Forbidden(obj) then
                    ns.Hide(obj)
                    ns.HideTextures(obj)
                end
            end
            -- Rollenbereich oben: seine Hintergrund-Grafiken weg (die Rollen-Knöpfe sind eigene Rahmen und bleiben)
            local roles = page.RolesSection
            if type(roles) == "table" and not Forbidden(roles) then ns.HideTextures(roles) end
            -- braune Trennlinie mit Rauten (DividerFrame, "common-framedivider") und die Streifen unter der Titelleiste
            -- (TopTileStreaks) – zusammen wirkte das wie ein Kasten (laut /fskin lfg)
            local divider = page.DividerFrame
            if type(divider) == "table" and not Forbidden(divider) then
                ns.Hide(divider)
                ns.HideTextures(divider)
            end
            ns.Hide(page.TopTileStreaks)
            -- Innenflächen (Schlüssel "Inset", "ListInset" …): flach; die Kategorie-Knöpfe darin bleiben
            for _, child in ipairs({ page:GetChildren() }) do
                local key = KeyOf(page, child)
                if key and key:lower():find("inset") and not Forbidden(child) then SkinInset(f, child) end
            end
        end
    end
end

-- das Auge klein links in der Titelleiste (erstes Bild der Augen-Animation, wie im Quest-Tracker)
local function AddEye(f)
    local eye = f:CreateTexture(nil, "OVERLAY")
    eye:SetSize(18, 18)
    eye:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    if eye:SetTexture("Interface\\LFGFrame\\LFG-Eye") ~= false then
        eye:SetTexCoord(0, 0.125, 0, 0.25)
    else
        eye:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
        eye:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Reiter rechts für das Dungeonfenster von ForeverQuests (nur, wenn ForeverQuests geladen ist): gebaut wie Blizzards
-- Seiten-Reiter ("common-sidetab", runde Maske, "common-sidetab-hover"), unter dem letzten Reiter im selben Abstand
local function Quests() return ns.UI.API and ns.UI.API.ForeverQuests end
local DUNGEON_ICON = "Interface\\AddOns\\ForeverQuests\\Media\\ForeverQuests" -- (Logo von ForeverQuests: "!")
local dungeonTab

-- Blizzards Reiter rechts am Fenster, von oben nach unten. Im Forever-Client sind das KEINE Knöpfe, sondern einfache
-- Rahmen direkt am Fenster (laut /fskin maus) – darum jeder sichtbare Rahmen, der rechts über die Fensterkante
-- hinausragt und höchstens 80 breit ist (einzelner Reiter oder ein Behälter mit allen Reitern)
local function SideTabs(f)
    local list, seen = {}, {}
    local function Consider(b)
        -- (verglichen in Bildschirmpunkten: Reiter und Fenster können unterschiedlich skaliert sein)
        if b and b ~= dungeonTab and not seen[b] and not Forbidden(b) and b.IsObjectType and b:IsObjectType("Frame")
            and b:IsShown() and b:GetLeft() and b:GetTop() and f:GetRight()
            and b:GetLeft() * b:GetEffectiveScale() >= (f:GetRight() - 20) * f:GetEffectiveScale()
            and (b:GetWidth() or 0) >= 30 and (b:GetWidth() or 0) <= 80 then
            seen[b] = true
            list[#list + 1] = b
        end
    end
    -- (die Reiter hängen teils in Unter-Rahmen – darum bis in die dritte Ebene suchen)
    local function Walk(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) then
                Consider(child)
                if depth < 3 and not child:IsObjectType("Button") then Walk(child, depth + 1) end
            end
        end
    end
    Walk(f, 1)
    local name = f:GetName()
    for i = 1, 8 do Consider(name and G(name .. "Tab" .. i)) end
    table.sort(list, function(a, b) return a:GetTop() * a:GetEffectiveScale() > b:GetTop() * b:GetEffectiveScale() end)
    return list
end

-- /fskin lfg: welche Reiter gefunden wurden und wo unser Reiter hängt (zur Fehlersuche)
function ns.DumpGroupFinderTabs()
    local function Say(text) print("|cffffcc00ForeverSkin|r: " .. tostring(text)) end
    local f = G("LFGParentFrame")
    if not f then return Say("LFGParentFrame nicht gefunden") end
    Say(string.format("Fenster: rechts %.0f, Skalierung %.2f, offen %s", (f:GetRight() or 0), f:GetEffectiveScale(),
        tostring(f:IsShown())))
    -- ausgeblendete Grafiken: wirklich unsichtbar?
    local listing = G("LFGListingFrame")
    for label, obj in pairs({ RoleBackground = G("LFGListingFrameRoleBackground"), Bg = G("LFGListingFrameBg"),
        NineSlice = listing and listing.NineSlice }) do
        if type(obj) == "table" and obj.GetAlpha then
            Say(string.format("Grafik %s: Alpha %.2f, sichtbar %s", label, obj:GetAlpha(), tostring(obj:IsVisible())))
        else
            Say("Grafik " .. label .. ": nicht gefunden")
        end
    end
    local ok, err = pcall(HideFrameArt, f)
    Say("Ausblenden: " .. (ok and "ok" or ("Fehler " .. tostring(err))))
    -- sichtbare Linien/Leisten (flach und breit) in allen Unter-Rahmen – z. B. Verzierungen, die /fskin grafik nicht
    -- findet (Rahmen ohne Maus)
    local function KeyOf(parent, child)
        for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
    end
    local shown = 0
    local function Lines(frame, depth, path)
        for _, r in ipairs({ frame:GetRegions() }) do
            -- wirklich sichtbar: auch die Eltern nicht durchsichtig (GetEffectiveAlpha)
            local alpha = r.GetEffectiveAlpha and r:GetEffectiveAlpha() or r:GetAlpha()
            if shown < 60 and r:IsObjectType("Texture") and r:IsVisible() and alpha > 0.05 and not ns.IsMine(frame, r) then
                shown = shown + 1
                local w, h = r:GetWidth() or 0, r:GetHeight() or 0
                local atlas = r.GetAtlas and r:GetAtlas()
                Say(string.format("  Linie: %s.%s | %s | %dx%d | oben %.0f links %.0f", path,
                    tostring(r:GetName() or KeyOf(frame, r) or "-"), tostring(atlas or r:GetTexture()), w, h,
                    r:GetTop() or 0, r:GetLeft() or 0))
            end
        end
        if depth < 5 then
            for _, child in ipairs({ frame:GetChildren() }) do
                if not Forbidden(child) and child:IsVisible() then
                    Lines(child, depth + 1, path .. ">" .. tostring(KeyOf(frame, child) or child:GetName() or "?"))
                end
            end
        end
    end
    Lines(f, 1, "LFGParentFrame")
    for i, b in ipairs(SideTabs(f)) do
        Say(string.format("Reiter %d: %s, links %.0f, oben %.0f, %dx%d, Skalierung %.2f", i,
            tostring(b:GetName() or b:GetDebugName()), b:GetLeft() or 0, b:GetTop() or 0, b:GetWidth() or 0,
            b:GetHeight() or 0, b:GetEffectiveScale()))
    end
    -- alle Knöpfe rechts außen (auch die nicht erkannten), damit man sieht, woran es hängt
    local function Walk(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) then
                if child:IsObjectType("Button") and child:IsShown() and child:GetLeft() and f:GetRight()
                    and child:GetLeft() * child:GetEffectiveScale() > (f:GetRight() - 60) * f:GetEffectiveScale() then
                    Say(string.format("  Knopf rechts: %s, links %.0f, %dx%d", tostring(child:GetDebugName()),
                        child:GetLeft(), child:GetWidth() or 0, child:GetHeight() or 0))
                end
                if depth < 4 then Walk(child, depth + 1) end
            end
        end
    end
    Walk(f, 1)
end

local function BuildDungeonTab(f)
    local tab = CreateFrame("Button", nil, f)
    tab:SetSize(55, 59)
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if not bg:SetAtlas("common-sidetab") then bg:SetColorTexture(0.1, 0.1, 0.12, 0.9) end
    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(49, 49)
    icon:SetPoint("CENTER")
    icon:SetTexture(DUNGEON_ICON)
    local mask = tab:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetAtlas("common-sidetab-mask")
    icon:AddMaskTexture(mask)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    if not hl:SetAtlas("common-sidetab-hover") then hl:SetColorTexture(1, 1, 1, 0.15) end
    tab:SetScript("OnClick", function()
        local api = Quests()
        if api and api.Toggle then pcall(api.Toggle) end
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ForeverQuests", 1, 0.82, 0)
        GameTooltip:AddLine(ns.T("Dungeons: Quests, Level und Gruppensuche", "Dungeons: quests, levels and group finder"),
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

local function PlaceDungeonTab(f)
    if not Quests() then
        if dungeonTab then dungeonTab:Hide() end
        return
    end
    dungeonTab = dungeonTab or BuildDungeonTab(f)
    local tabs = SideTabs(f)
    local last = tabs[#tabs]
    dungeonTab:ClearAllPoints()
    if last then
        -- einzelner Reiter: dieselbe Größe; Behälter mit mehreren Reitern (hoch): Standardgröße, direkt darunter
        local single = (last:GetHeight() or 0) <= 80
        if single then dungeonTab:SetSize(last:GetWidth(), last:GetHeight()) else dungeonTab:SetSize(55, 59) end
        dungeonTab:SetFrameLevel(last:GetFrameLevel() + 1)
        local gap = 4
        if tabs[2] then gap = math.max(0, (tabs[1]:GetBottom() or 0) - (tabs[2]:GetTop() or 0)) end
        dungeonTab:SetPoint("TOP", last, "BOTTOM", 0, -gap)
    else
        dungeonTab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -40)
    end
    dungeonTab:Show()
end

-- Knöpfe unten ("Zurück", "Selbst anmelden"): flach wie überall. Nur Text-Knöpfe in Knopfhöhe unten im Fenster –
-- die großen Kategorie-Knöpfe ("Dungeons" …) behalten ihre Grafik (auf Wunsch)
local bottomButtons = setmetatable({}, { __mode = "k" })
local function SkinBottomButtons(f, frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                if not bottomButtons[child] and type(text) == "string" and text ~= "" and child:GetHeight() <= 30
                    and child:GetBottom() and f:GetBottom() and child:GetBottom() - f:GetBottom() < 50 then
                    bottomButtons[child] = true
                    ns.SkinButton(child)
                end
            elseif depth < 4 then
                SkinBottomButtons(f, child, depth + 1)
            end
        end
    end
end

-- Bedienelemente aller Seiten wie in den übrigen Forever-Fenstern: Auswahllisten und "Filter" flach, Suchleiste als
-- flaches Eingabefeld, Symbol-Knöpfe ("Aktualisieren", Lupe) nur als helles Symbol, Laufleisten gold; Blizzards braune
-- Trennlinien ("…divider…", "…ScrollLine") weg
local browseDone = setmetatable({}, { __mode = "k" })
local function SkinSearch(box)
    local keep = {}
    for _, key in ipairs({ "searchIcon", "SearchIcon", "Instructions", "clearButton" }) do
        local t = box[key]
        if type(t) == "table" and t.IsObjectType and t:IsObjectType("Texture") then keep[t] = true end
    end
    ns.HideTextures(box, keep)
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(box[key]) end
    ns.Flat(box, ns.C.input, { -4, 2, 0, 2 })
end
local function SkinRefresh(b)
    -- (Symbol: eigene Grafik "Icon" – sonst ist das Bild des Knopfs selbst das Symbol, z. B. die Lupe)
    local icon = b.Icon or b.icon or (b.GetNormalTexture and b:GetNormalTexture())
    ns.HideTextures(b, icon and { [icon] = true } or nil)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = b[get] and b[get](b)
        if t and t ~= icon then ns.Hide(t) end
    end
    -- nur das Symbol, ohne Kasten (auf Wunsch): hellgrau, beim Überfahren gold – wie unsere feinen Pfeile
    if icon and icon.SetDesaturated then
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.85, 0.85, 0.87)
        b:HookScript("OnEnter", function() icon:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3]) end)
        b:HookScript("OnLeave", function() icon:SetVertexColor(0.85, 0.85, 0.87) end)
    end
end
local function GoldDividers(frame, depth)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) then
            local atlas = r.GetAtlas and r:GetAtlas()
            local key = KeyOf(frame, r) or r:GetName() or ""
            -- (Trennlinien heißen hier "LFGBrowseFrameBarTop/-Middle" mit der Grafik "groupfinder-ScrollLine")
            local a = type(atlas) == "string" and atlas:lower() or ""
            if a:find("divider") or a:find("scrollline") or key:lower():find("divider") then
                r:SetAlpha(0) -- (erst gold gefärbt, dann auf Wunsch ganz entfernt)
            end
        end
    end
    if depth < 4 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) then GoldDividers(child, depth + 1) end
        end
    end
end
local function SkinBrowse(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not browseDone[child] then
            local key = ((KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
            local isDropdown = child:IsObjectType("DropdownButton")
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            local text = child.GetText and child:GetText()
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                browseDone[child] = true
                ns.SkinScrollBar(child) -- (Laufleiste gold)
            elseif isDropdown then
                browseDone[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("EditBox") and not (child.IsMultiLine and child:IsMultiLine()) then
                -- (mehrzeilige Felder wie die Gruppenbeschreibung: siehe SkinActivityView)
                browseDone[child] = true
                SkinSearch(child)
            elseif child:IsObjectType("Button") and key:find("filter") and type(text) == "string" and text ~= "" then
                browseDone[child] = true
                ns.SkinButton(child) -- ("Filter" als Text-Knopf)
            elseif child:IsObjectType("Button") and (key:find("refresh") or key:find("search"))
                and not (type(text) == "string" and text ~= "") then
                browseDone[child] = true
                SkinRefresh(child) -- (Aktualisieren, Lupe: nur das Symbol)
            elseif not child:IsObjectType("Button") and depth < 4 then
                SkinBrowse(child, depth + 1)
            end
        end
    end
end

-- Ergebnislisten ("Wer ist da", "Durchsuchen"): Einträge als flache graue Balken mit feinem Rand (wie die Zeilen der
-- übrigen Forever-Fenster), die Knöpfe darin (z. B. Einladen) flach mit ihrem Symbol. Blizzard legt die Einträge beim
-- Blättern neu an – darum im Takt
local entryDone = setmetatable({}, { __mode = "k" })
-- nur Hintergrund und Rahmen (breite Flächen, dünne Kanten, "border/frame/background" im Namen) – kleine Symbole
-- (Rolle, Klasse, Anführer) bleiben
local function HideBackdrop(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) then
            local w, h = r:GetWidth() or 0, r:GetHeight() or 0
            local atlas = r.GetAtlas and r:GetAtlas()
            local s = (type(atlas) == "string" and atlas or ""):lower()
            if w >= 60 or h >= 60 or w <= 6 or h <= 6 or s:find("border") or s:find("frame") or s:find("background")
                or s:find("bg") then
                r:SetAlpha(0)
            end
        end
    end
end
local function SkinEntryButton(b)
    local icon = b.Icon or b.icon
    if icon then
        ns.HideTextures(b, { [icon] = true })
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
            local t = b[get] and b[get](b)
            if t and t ~= icon then ns.Hide(t) end
        end
    end
    ns.Flat(b, ns.C.button)
    ns.Hover(b)
end
-- Balken: rechts ENTRY_RIGHT Abstand zur Laufleiste, oben/unten je ENTRY_GAP (= Luft zwischen den Einträgen); die
-- Knöpfe rücken um ENTRY_RIGHT mit nach links
local ENTRY_RIGHT, ENTRY_GAP = 4, 2
local BUTTON_GAP, TEXT_PAD = 9, 4 -- Abstand Balken–Knopf; Text endet so weit vor der Balkenkante
local CONTENT_UP = 4               -- Inhalt so viel höher im Balken
local entryButtons = setmetatable({}, { __mode = "k" }) -- [Eintrag] = { Knöpfe ohne Text }
local function SkinEntry(entry)
    if type(entry.NineSlice) == "table" then ns.Hide(entry.NineSlice) end
    HideBackdrop(entry)
    ns.Flat(entry, ns.C.button, { 0, ENTRY_GAP, ENTRY_RIGHT, ENTRY_GAP })
    if entry:IsObjectType("Button") then ns.Hover(entry) end
    local list = {}
    for _, child in ipairs({ entry:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.NineSlice) == "table" then ns.Hide(child.NineSlice) end
            local text = child.GetText and child:GetText()
            if child:IsObjectType("Button") and not (type(text) == "string" and text ~= "") then
                SkinEntryButton(child)
                list[#list + 1] = child
                -- (einmal um ENTRY_RIGHT nach links – gleicher Abstand zum rechten Rand des Balkens wie vorher)
                if child:GetNumPoints() == 1 then
                    local p, rel, rp, x, y = child:GetPoint(1)
                    child:SetPoint(p, rel, rp, (x or 0) - ENTRY_RIGHT, y or 0)
                end
            elseif not child:IsObjectType("Button") then
                HideBackdrop(child) -- (Rahmen-Teile in Unter-Rahmen des Eintrags)
            end
        end
    end
    entryButtons[entry] = list
end

-- Text eines Eintrags nicht unter die Knöpfe laufen lassen: Zeilen, die über den linken Rand des ersten Knopfs
-- reichen, enden 6 davor (einzeilig, mit "…") – bei jedem Durchgang (Blizzard füllt die Einträge beim Blättern neu)
local function FitEntryTexts(entry)
    local left
    for _, b in ipairs(entryButtons[entry] or {}) do
        if b:IsShown() and b:GetLeft() then left = math.min(left or b:GetLeft(), b:GetLeft()) end
    end
    if not left or not entry:GetRight() then return end
    -- Balken endet BUTTON_GAP vor dem ersten Knopf: der Knopf steht frei daneben (auf Wunsch)
    local cut = math.floor(entry:GetRight() - left + BUTTON_GAP + 0.5)
    -- Text nur im Balken: endet TEXT_PAD vor dessen rechter Kante (gekürzt mit "…"); was erst kurz davor beginnt,
    -- wird ausgeblendet. Beim nächsten Füllen durch Blizzard wieder zurückgesetzt, wenn der Text passt
    local limit = entry:GetRight() - cut - TEXT_PAD
    -- Zeilen mit mehreren Texten (z. B. "Stufe 26 | Volk | Klasse"): ragt der letzte hinaus, wird der breiteste andere
    -- gekürzt – hängen die Texte aneinander, rückt der letzte (die Klasse) dadurch ganz in den Balken
    local function Gather(frame, out)
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("FontString") and r:IsShown() and r:GetLeft() and r:GetTop() then
                -- neuer Text (Blizzard hat den Eintrag neu gefüllt): zurück auf Blizzards Breite, dann neu messen
                local text = r:GetText()
                if r.foreverFit and r.foreverText ~= text then
                    r:SetWidth(0)
                    r.foreverFit = nil
                end
                r.foreverText = text
                if r.foreverHidden and r.foreverHiddenText ~= text then
                    r:SetAlpha(1)
                    r.foreverHidden = nil
                end
                out[#out + 1] = r
            end
        end
    end
    local texts = {}
    Gather(entry, texts)
    for _, child in ipairs({ entry:GetChildren() }) do
        if not Forbidden(child) and not child:IsObjectType("Button") then Gather(child, texts) end
    end
    -- Text senkrecht mittig im Balken: Balken so verschieben, dass über dem obersten und unter dem untersten Text
    -- gleich viel Rand ist (oben + unten zusammen bleibt 2 × ENTRY_GAP, also auch der Abstand zwischen den Balken)
    local textTop, textBottom
    for _, r in ipairs(texts) do
        if not r.foreverHidden and (r:GetText() or "") ~= "" and r:GetBottom() then
            textTop = math.max(textTop or r:GetTop(), r:GetTop())
            textBottom = math.min(textBottom or r:GetBottom(), r:GetBottom())
        end
    end
    local top = ENTRY_GAP + CONTENT_UP
    if textTop and entry:GetTop() and entry:GetBottom() then
        top = math.floor((entry:GetTop() - textTop - textBottom + entry:GetBottom() + 2 * ENTRY_GAP) / 2 + 0.5)
    end
    if entry.foreverCut ~= cut or entry.foreverTop ~= top then
        entry.foreverCut, entry.foreverTop = cut, top
        ns.Flat(entry, ns.C.button, { 0, top, cut, 2 * ENTRY_GAP - top })
    end
    local lines = {}
    for _, r in ipairs(texts) do
        local key = math.floor(r:GetTop() / 4 + 0.5)
        lines[key] = lines[key] or {}
        table.insert(lines[key], r)
    end
    for _, line in pairs(lines) do
        if #line > 1 then
            table.sort(line, function(a, b) return a:GetLeft() < b:GetLeft() end)
            local last = line[#line]
            local over = (last:GetRight() or 0) - limit
            if over > 0.5 then
                local widest
                for i = 1, #line - 1 do
                    if not widest or line[i]:GetWidth() > widest:GetWidth() then widest = line[i] end
                end
                if widest and widest:GetWidth() - over >= 30 then
                    widest:SetWordWrap(false)
                    widest:SetWidth(widest:GetWidth() - over)
                    widest.foreverFit = true
                end
            end
        end
    end
    local function Fit(frame)
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("FontString") and r:IsShown() and r:GetLeft() then
                local full = (r.GetUnboundedStringWidth and r:GetUnboundedStringWidth()) or r:GetStringWidth() or 0
                local maxW = limit - r:GetLeft()
                if maxW < 12 then
                    if full > 0 then
                        r:SetAlpha(0)
                        r.foreverHidden = true
                        r.foreverHiddenText = r:GetText()
                    end
                else
                    -- (nur, wenn der Text selbst noch hinausragt – sonst bleibt die Kürzung von oben)
                    if (r:GetRight() or 0) > limit + 0.5 and full > maxW + 0.5 then
                        r:SetWordWrap(false)
                        r:SetWidth(maxW)
                        r.foreverFit = true
                    end
                end
            end
        end
    end
    Fit(entry)
    for _, child in ipairs({ entry:GetChildren() }) do
        if not Forbidden(child) and not child:IsObjectType("Button") then Fit(child) end
    end
end
-- Liste und Laufleiste enden über unserer Fußleiste (Blizzards reichen bis an den Rand und liefen darunter):
-- untere Ankerpunkte so weit hoch, dass die Unterkante 6 über der goldenen Linie liegt (gemessen, nur wenn nötig)
local function AboveFooter(f, frame, gap)
    if not (footerHeight and frame:GetBottom() and f:GetBottom()) then return end
    local s = frame:GetEffectiveScale() / f:GetEffectiveScale()
    local delta = (f:GetBottom() + footerHeight + (gap or 6) - frame:GetBottom() * s) / s
    if delta <= 0.5 then return end
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local p, rel, rp, x, y = frame:GetPoint(i)
        if p:find("BOTTOM") then y = (y or 0) + delta end
        points[i] = { p, rel, rp, x or 0, y or 0 }
    end
    frame:ClearAllPoints()
    for _, pt in ipairs(points) do frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

-- Listenanfang etwas höher im Kasten (auf Wunsch): obere Ankerpunkte der Liste einmal LIST_UP nach oben
local LIST_UP = 11
local function ListHigher(list)
    if list.foreverRaised then return end
    list.foreverRaised = true
    local points = {}
    for i = 1, list:GetNumPoints() do
        local p, rel, rp, x, y = list:GetPoint(i)
        if p:find("TOP") then y = (y or 0) + LIST_UP end
        points[i] = { p, rel, rp, x or 0, y or 0 }
    end
    list:ClearAllPoints()
    for _, pt in ipairs(points) do list:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

local function SkinResults(frame, depth, f)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            local isBar = type(child.Track) == "table" and (child.Track.Thumb or child.Back)
            -- (die Liste selbst 5 weiter hoch als die Laufleiste – auf Wunsch)
            if f and (child.GetScrollTarget or isBar) and child:IsVisible() then
                pcall(AboveFooter, f, child, child.GetScrollTarget and 11 or 6)
            end
            if child.GetScrollTarget then
                pcall(ListHigher, child)
                local target = child:GetScrollTarget()
                if target then
                    for _, entry in ipairs({ target:GetChildren() }) do
                        if not Forbidden(entry) then
                            if not entryDone[entry] then
                                entryDone[entry] = true
                                SkinEntry(entry)
                            end
                            if entry:IsVisible() then FitEntryTexts(entry) end
                        end
                    end
                end
            elseif depth < 4 then
                SkinResults(child, depth + 1, f)
            end
        end
    end
end

-- "Anmelden" > Aktivitätenauswahl (LFGListingFrame.ActivityView): Häkchen flach (wie überall), das mehrzeilige
-- Beschreibungsfeld als EIN flaches Eingabefeld (Blizzards heller Rand weg), Bedienelemente unten (z. B. "Voicechat")
-- über unserer Fußleiste statt auf der Kastenkante
local viewDone = setmetatable({}, { __mode = "k" })
local function SkinDescription(view, edit)
    -- Kasten des Feldes: höchster Rahmen über dem Eingabefeld, der noch feldgroß ist (höchstens 160 hoch)
    local box, frame = nil, edit:GetParent()
    while frame and frame ~= view and not Forbidden(frame) and (frame:GetHeight() or 999) <= 160 do
        if type(frame.NineSlice) == "table" then ns.Hide(frame.NineSlice) end
        ns.HideTextures(frame)
        box = frame
        frame = frame:GetParent()
    end
    ns.HideTextures(edit)
    if box then ns.Flat(box, ns.C.input) end
end
local function RaiseAboveFooter(f, frame)
    if not (footerHeight and frame:GetBottom() and f:GetBottom()) then return end
    local s = frame:GetEffectiveScale() / f:GetEffectiveScale()
    local delta = (f:GetBottom() + footerHeight + 10 - frame:GetBottom() * s) / s
    if delta <= 0.5 or frame:GetNumPoints() == 0 then return end
    local points = {}
    for i = 1, frame:GetNumPoints() do
        local p, rel, rp, x, y = frame:GetPoint(i)
        points[i] = { p, rel, rp, x or 0, (y or 0) + delta }
    end
    frame:ClearAllPoints()
    for _, pt in ipairs(points) do frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end
-- Auf-/Zuklappen (rotes Plus/Minus vor "Kalimdor" …): feiner Pfeil wie in den übrigen Listen. Den Zustand verrät
-- Blizzards (unsichtbare) Knopfgrafik: Minus = aufgeklappt, Plus = zugeklappt (Pfad, Atlas oder Datei-Nummer)
local MINUS_IDS = { [130821] = true, [130822] = true } -- UI-MinusButton-Up/-Down
local PLUS_IDS = { [130838] = true, [130836] = true }  -- UI-PlusButton-Up/-Down
local function ToggleState(b)
    local t = b.GetNormalTexture and b:GetNormalTexture()
    if not t then return nil end
    local atlas = t.GetAtlas and t:GetAtlas()
    local tex = t:GetTexture()
    local s = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
    if s:find("minus") or s:find("open") or MINUS_IDS[tex] then return true end
    if s:find("plus") or s:find("closed") or PLUS_IDS[tex] then return false end
    return nil
end

local function SkinActivityView(f, view, depth)
    for _, child in ipairs({ view:GetChildren() }) do
        if not Forbidden(child) then
            local isDropdown = child:IsObjectType("DropdownButton")
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if child:IsObjectType("CheckButton") then
                if not viewDone[child] then
                    viewDone[child] = true
                    ns.SkinCheck(child)
                end
            elseif child:IsObjectType("EditBox") and child.IsMultiLine and child:IsMultiLine() then
                if not viewDone[child] then
                    viewDone[child] = true
                    SkinDescription(view, child)
                end
            elseif child:IsObjectType("Button") and (child:GetWidth() or 0) <= 24 and ToggleState(child) ~= nil then
                ns.SkinToggle(child, ToggleState(child)) -- (bei jedem Durchgang: Richtung nach dem Zustand)
            else
                if isDropdown and depth == 1 then pcall(RaiseAboveFooter, f, child) end
                if depth < 6 and not isDropdown then SkinActivityView(f, child, depth + 1) end
            end
        end
    end
end

-- Fußleiste mit feiner goldener Linie hinter den Knöpfen unten (wie bei allen Forever-Fenstern, ns.ContentBox):
-- Höhe nach den Knöpfen (deren Oberkante + 7), einmal sobald die Knöpfe da sind
local footerDone
local function AddFooter(f)
    if footerDone or not f:GetBottom() then return end
    local top
    for b in pairs(bottomButtons) do
        if b:IsVisible() and b:GetTop() then top = math.max(top or 0, b:GetTop() - f:GetBottom()) end
    end
    if not top then return end
    footerDone = true
    footerHeight = math.floor(top + 7.5)
    ns.ContentBox(f, footerHeight, nil, true)
end

local function SkinGroupFinder()
    local f = G("LFGParentFrame")
    if not f or ns.groupFinderSkinned or Forbidden(f) then return end
    ns.groupFinderSkinned = true
    -- "leicht": Hintergrund und Knopf-Grafiken bleiben (auf Wunsch)
    ns.SkinWindow(f, nil, true)
    Step("frame", function() HideFrameArt(f) end)
    Step("eye", function() AddEye(f) end)
    ns.Watch(f)
    -- (Blizzards Reiter und Knöpfe stehen erst nach dem Öffnen fest – darum im Takt einreihen bzw. umgestalten)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.2 then return end
        waited = 0
        -- (Fehler beim Ausblenden einmal melden statt still zu schlucken – sonst fehlte jeder Hinweis)
        local ok, err = pcall(HideFrameArt, f)
        if not ok and not watch.reported then
            watch.reported = true
            if ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "groupfinder/frame", err) end
        end
        pcall(PlaceDungeonTab, f)
        pcall(SkinBottomButtons, f, f, 1)
        pcall(AddFooter, f)
        for _, pageName in ipairs(PAGES) do
            local page = G(pageName)
            if page and page:IsVisible() and not Forbidden(page) then
                pcall(SkinBrowse, page, 1)
                pcall(GoldDividers, page, 1)
                if pageName == "LFGListingFrame" then
                    -- (keine Ergebnisliste: die Aktivitätenauswahl hat Häkchen statt Einträgen mit Knöpfen)
                    local view = page.ActivityView
                    if type(view) == "table" and view:IsVisible() then pcall(SkinActivityView, f, view, 1) end
                else
                    pcall(SkinResults, page, 1, f)
                end
            end
        end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.groupFinderSkinned or not ns.GetDB().groupFinder or not G("LFGParentFrame") then return end
    Step("skin", SkinGroupFinder)
end)
