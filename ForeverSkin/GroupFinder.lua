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
    ns.Hide(G("LFGListingFrameBg"))
    ns.Hide(G("LFGBrowseFrameBg"))
    -- die Seiten ("Anmelden" = LFGListingFrame, "Durchsuchen" = LFGBrowseFrame) haben einen eigenen Metallrahmen mit
    -- Kopf oben (laut /fskin grafik: NineSlice mit "UI-Frame-PortraitMetal-…") – weg; Hintergrund und der Streifen
    -- hinter den Rollen bleiben
    for _, page in ipairs({ G("LFGListingFrame") or false, G("LFGBrowseFrame") or false }) do
        if page and not Forbidden(page) then
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
            -- Innenfläche: Bild ("groupfinder-background") und verzierter Rahmen ("common-insideframe", mit der Linie
            -- samt Rauten oben) weg – flache Fläche mit feinem Rand wie überall; die Kategorie-Knöpfe bleiben
            local inset = page.Inset
            if type(inset) == "table" and not Forbidden(inset) then
                for _, key in ipairs({ "CustomBG", "Border", "Bg", "NineSlice" }) do ns.Hide(inset[key]) end
                ns.HideTextures(inset)
                -- (Blizzards Innenfläche reicht bis fast nach unten: unser Kasten endet 6 über der Fußleiste)
                local cut = 0
                if footerHeight and inset:GetBottom() and f:GetBottom() then
                    local s = inset:GetEffectiveScale() / f:GetEffectiveScale()
                    local footTop = f:GetBottom() + footerHeight + 6
                    cut = math.max(0, (footTop - inset:GetBottom() * s) / s)
                end
                ns.Flat(inset, ns.C.panel, { 0, 0, 0, cut })
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

-- Seite "Durchsuchen" (LFGBrowseFrame): Auswahllisten ("Kategorie", "Nach Aktivität filtern") flach, der Knopf
-- "Aktualisieren" daneben flach mit hellem Symbol; Blizzards braune Trennlinien ("…divider…") gold gefärbt
local browseDone = setmetatable({}, { __mode = "k" })
local function KeyOf(parent, child)
    for k, v in pairs(parent) do if v == child and type(k) == "string" then return k end end
end
local function SkinRefresh(b)
    local icon = b.Icon or b.icon
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
                r:SetDesaturated(true)
                r:SetVertexColor(ns.C.accent[1], ns.C.accent[2], ns.C.accent[3], 1)
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
            if isDropdown then
                browseDone[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("Button") and key:find("refresh") then
                browseDone[child] = true
                SkinRefresh(child)
            elseif not child:IsObjectType("Button") and depth < 4 then
                SkinBrowse(child, depth + 1)
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
        local browse = G("LFGBrowseFrame")
        if browse and browse:IsVisible() and not Forbidden(browse) then
            pcall(SkinBrowse, browse, 1)
            pcall(GoldDividers, browse, 1)
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
