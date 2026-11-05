-- ForeverSkin – Character.lua: Charakterfenster (CharacterFrame: Ausrüstung, Ruf, Währungen) im Forever-Stil
-- (docs/Fenster-Stil.md). Auf Wunsch wie die Anprobe: OHNE Titelleiste und ohne "Dein Gold", dafür das kleine runde
-- Porträt mit goldenem Ring; Blizzards Hintergrundgrafiken (Bild hinter dem Modell, Hintergründe der Innenflächen)
-- bleiben, nur Rahmen, Titel-Grafik und Porträt-Ring weg. Dazu unsere Bausteine: Ausrüstungsplätze wie Taschenplätze,
-- flache Reiter, goldene Laufleisten, flache Häkchen/Auswahllisten/Text-Knöpfe. Die Einträge von Ruf und Währungen
-- bleiben Blizzards.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TITLE_UP = 10            -- Titelleiste so viel höher als Blizzards Fensterrand (siehe Raise)
local PORTRAIT_X, PORTRAIT_Y = 12, TITLE_UP - 12 -- Mitte des Porträts: auf der oberen linken Ecke (leicht innen)
-- goldener Rand der Ausrüstungsplätze (Dicke) und Luft zwischen Rand und Symbol – in der Luft zeigt sich die
-- Seltenheitsfarbe (Blizzards IconBorder wird genau dorthin gesetzt)
local SLOT_EDGE, SLOT_GAP = 1, 1
local RIGHT_LINE_UP = 8 -- Trennlinie unter den 4 Reitern rechts so viel über der Unterkante des Steinstreifens
local HEADER_INSET = { 10, 6, 10, 6 } -- Balken der Überschriften in der Werte-Spalte: Abstand zum Eintrag (l, o, r, u)
local DIVIDER_RIGHT = 2 -- Trennlinie zwischen Vorschau und Werten so viel weiter rechts

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "character/" .. what, err) end
end

-- kleines rundes Porträt oben links (wie bei der Anprobe), Ring gold
-- (auf eigenem Rahmen ÜBER den Hintergründen links/rechts – die sind eigene Rahmen und verdeckten sonst das Porträt)
local portrait
local function Portrait(f)
    if not portrait then
        portrait = {}
        local holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel(f:GetFrameLevel() + 110) -- (über dem Rand)
        holder:EnableMouse(false)
        portrait.holder = holder
        local function Disk(size, sub, c)
            local t = holder:CreateTexture(nil, "OVERLAY", nil, sub)
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:SetSize(size, size)
            -- (auf der oberen linken Ecke unserer Fläche, die TITLE_UP über Blizzards Rand reicht – ragt leicht hinaus)
            t:SetPoint("CENTER", f, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
            local mask = holder:CreateMaskTexture()
            mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(t)
            t:AddMaskTexture(mask)
            return t
        end
        portrait.ring = Disk(52, 1, C.accent)
        portrait.gap = Disk(49, 2, C.background)
        portrait.image = Disk(47, 3, { 1, 1, 1 })
    end
    if SetPortraitTexture then SetPortraitTexture(portrait.image, "player") end
end

local movedDivider = setmetatable({}, { __mode = "k" })
local ourFrames = setmetatable({}, { __mode = "k" }) -- eigene Hilfsrahmen (Linien): nie mit verschieben
local rightLines = {} -- Linien unter den 4 Reitern rechts (je Seite eine: Ausrüstung, Spieler gegen Spieler, Währung)
local dividerLines = setmetatable({}, { __mode = "k" }) -- [Blizzards Trennlinie] = unsere goldene Linie

-- Rahmen: nur Blizzards Rahmen, Titel-Grafik, Streifen und Porträt weg – Hintergründe bleiben; flache Fläche darunter
local function HideFrameArt(f)
    for _, key in ipairs({ "NineSlice", "PortraitContainer", "TopTileStreaks", "TitleBg" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            if obj.GetRegions then ns.HideTextures(obj) end
        end
    end
    for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TitleBg" }) do ns.Hide(G("CharacterFrame" .. suffix)) end
    if f.TitleContainer then ns.HideTextures(f.TitleContainer) end
    -- Streifen hinter "Stufe …, Klasse" (TopBackgroundStrip der Seiten) und Steinstreifen hinter den 4 Reitern der
    -- rechten Spalte (laut /fskin grafik) – weg, auf Wunsch; die großen Hintergründe dahinter bleiben
    -- (auf jeder Seite, die einen hat – z. B. auch Statistiken: dort lag er über dem Anfang der Liste)
    local pages = { G("PaperDollFrame") or false, G("ReputationFrame") or false, G("TokenFrame") or false }
    for _, child in ipairs({ f:GetChildren() }) do pages[#pages + 1] = child end
    for _, page in ipairs(pages) do
        local host = page and not Forbidden(page) and page.TopBackgroundStripHost
        if type(host) == "table" and not Forbidden(host) then
            ns.Hide(host.TopBackgroundStrip)
            ns.HideTextures(host)
        end
    end
    ns.Hide(G("CharacterFrameRightPaneHostStoneBg"))
    -- Hintergrundbilder der beiden Seiten ("UI-Character-Info-General-BG" links, "…-Stat-BG" rechts): durch unsere
    -- flache Innenfläche ersetzt (auf Wunsch); das Bild hinter dem Modell gehört zur Modellansicht und bleibt
    local leftHost, rightHost = G("CharacterFrameLeftPaneHost"), G("CharacterFrameRightPaneHost")
    for _, host in ipairs({ leftHost or false, rightHost or false }) do
        if host and not Forbidden(host) then
            ns.HideTextures(host)
            -- (rechts: Fläche nach links bis an die linke Seite – sonst blieb zwischen beiden ein dunkler Streifen)
            local gap = 0
            if host == rightHost and leftHost and leftHost:GetRight() and host:GetLeft() then
                gap = math.max(0, math.floor(host:GetLeft() - leftHost:GetRight() + 0.5))
            end
            local look = ns.Flat(host, C.panel, { -gap, 0, 0, 0 })
            -- innere Randlinien an der Trennlinie weg (wirkten neben der goldenen Linie wie ein schwarzer Streifen):
            -- links die rechte Kante, rechts die linke (ns.Flat: Kanten oben, unten, links, rechts)
            local edges = look and look.edges
            if edges then
                if host == leftHost and edges[4] then edges[4]:SetAlpha(0) end
                if host == rightHost and edges[3] then edges[3]:SetAlpha(0) end
            end
        end
    end
    -- Trennlinie zwischen linker und rechter Seite ("common-framedivider", samt Verzierung unten): gold
    local right = G("CharacterFrameRightPaneHost")
    if right and not Forbidden(right) then
        for _, child in ipairs({ right:GetChildren() }) do
            if not Forbidden(child) then
                for _, r in ipairs({ child:GetRegions() }) do
                    local atlas = r:IsObjectType("Texture") and r.GetAtlas and r:GetAtlas()
                    if type(atlas) == "string" and atlas:find("framedivider") then
                        -- (der Rahmen der Trennlinie darf nie mit nach unten geschoben werden – sonst rutschte die
                        -- senkrechte Linie auf den übrigen Seiten unter den Fensterrand)
                        ourFrames[child] = true
                        -- Blizzards Trennlinie ist 11 breit mit dunklem Schatten (wirkte neben dem Gold wie ein
                        -- schwarzer Streifen): unsichtbar, stattdessen eine eigene goldene Linie von 1 px in ihrer Mitte
                        r:SetAlpha(0)
                        if not dividerLines[r] then
                            local holder = CreateFrame("Frame", nil, right)
                            ourFrames[holder] = true
                            holder:SetAllPoints(right)
                            holder:SetFrameLevel(child:GetFrameLevel() + 1)
                            holder:EnableMouse(false)
                            local line = holder:CreateTexture(nil, "OVERLAY", nil, 7)
                            line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                            ns.OnePixel(line, false)
                            line:SetPoint("TOP", r, "TOP", 0, 0)
                            line:SetPoint("BOTTOM", r, "BOTTOM", 0, 0)
                            dividerLines[r] = line
                        end
                        -- einmal DIVIDER_RIGHT nach rechts (auf Wunsch)
                        if not movedDivider[r] and r:GetNumPoints() > 0 then
                            movedDivider[r] = true
                            local points = {}
                            for i = 1, r:GetNumPoints() do
                                local p, rel, rp, x, y = r:GetPoint(i)
                                points[i] = { p, rel, rp, (x or 0) + DIVIDER_RIGHT, y or 0 }
                            end
                            r:ClearAllPoints()
                            for _, pt in ipairs(points) do r:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
                        end
                    end
                end
            end
        end
    end
    -- Innenflächen: nur ihr Rahmen weg (ihr Hintergrund bleibt)
    for _, key in ipairs({ "Inset", "InsetRight", "InsetLeft" }) do
        local inset = f[key] or G("CharacterFrame" .. key)
        if type(inset) == "table" and inset.NineSlice and not Forbidden(inset) then ns.Hide(inset.NineSlice) end
    end
end

-- Ausrüstungsplatz wie ein Taschenplatz (ForeverBags): dunkler Platz, feiner Rand, beim Überfahren gold; Blizzards
-- Rahmen-Grafiken weg, Symbol eckig mit 1 px Rand, Seltenheitsrahmen (IconBorder) bleibt
local SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs",
    "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }
local slotDone = setmetatable({}, { __mode = "k" })
local function SkinSlot(b)
    if not b or slotDone[b] or Forbidden(b) then return end
    slotDone[b] = true
    local name = b:GetName()
    local icon = b.icon or b.Icon or (name and G(name .. "IconTexture"))
    local keep = {}
    if icon then keep[icon] = true end
    if b.IconBorder then keep[b.IconBorder] = true end
    for _, key in ipairs({ "IconOverlay", "IconOverlay2", "Count", "searchOverlay", "ItemContextOverlay" }) do
        if type(b[key]) == "table" then keep[b[key]] = true end
    end
    ns.HideTextures(b, keep)
    ns.Hide(b.GetNormalTexture and b:GetNormalTexture())
    ns.Hide(name and G(name .. "Frame"))
    -- Blizzards Verzierung um den Platz ("UI-Character-Info-GearSlot" im Unter-Rahmen BorderFrame): weg – unser
    -- goldener Rand ersetzt sie (auf Wunsch)
    local deco = b.BorderFrame
    if type(deco) == "table" and deco.GetRegions and not Forbidden(deco) then ns.HideTextures(deco) end
    -- Symbol innerhalb von Rand + Luft
    local inset = SLOT_EDGE + SLOT_GAP
    if icon and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    -- Seltenheitsrahmen direkt innerhalb des goldenen Randes: füllt die Luft um das Symbol mit der Seltenheitsfarbe
    if b.IconBorder and b.IconBorder.ClearAllPoints then
        b.IconBorder:ClearAllPoints()
        b.IconBorder:SetPoint("TOPLEFT", SLOT_EDGE, -SLOT_EDGE)
        b.IconBorder:SetPoint("BOTTOMRIGHT", -SLOT_EDGE, SLOT_EDGE)
    end
    -- dunkle Fläche; der feine Rand von ns.Flat weg – stattdessen ein eigener goldener Rand SLOT_EDGE dick (auf Wunsch,
    -- ersetzt Blizzards Verzierung); dauerhaft gold, Blizzards Hervorhebung beim Überfahren bleibt
    local look = ns.Flat(b, { 0.06, 0.06, 0.08, 0.85 })
    if look then
        for _, e in ipairs(look.edges or {}) do e:SetAlpha(0) end
    end
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local e = b:CreateTexture(nil, "OVERLAY", nil, 6)
        -- (gedämpftes Gold – auf Wunsch weniger grell: dunkler und etwas durchscheinend)
        e:SetColorTexture(C.accent[1] * 0.7, C.accent[2] * 0.7, C.accent[3] * 0.7, 0.6)
        e:SetPoint(p[1], b, p[1])
        e:SetPoint(p[2], b, p[2])
        ns.OnePixel(e, p[3]) -- (SLOT_EDGE = 1: genau ein Bildschirmpixel)
    end
end

-- Reiter unten ("Charakter", "Ruf", "Währung"): flach, der gewählte gold (PanelTemplates sperren den gewählten)
local function TabSelected(tab)
    if type(tab.isSelected) == "boolean" then return tab.isSelected end
    return tab.IsEnabled and not tab:IsEnabled()
end

-- übrige Bedienelemente: Laufleisten gold, Häkchen/Auswahllisten flach, Text-Knöpfe flach – aber nur echte Knöpfe
-- (mit Blizzards Knopf-Teilen Left/Middle/Right), nicht die Einträge der Ruf-/Währungsliste
local done = setmetatable({}, { __mode = "k" })
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] and not slotDone[child] then
            local isDropdown = child:IsObjectType("DropdownButton")
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("CheckButton") and (child:GetWidth() or 0) <= 32 then
                done[child] = true
                ns.SkinCheck(child)
            elseif isDropdown then
                done[child] = true
                ns.SkinDropdown(child)
            elseif child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                if type(text) == "string" and text ~= "" and type(child.Left) == "table" and type(child.Right) == "table" then
                    done[child] = true
                    ns.SkinButton(child)
                end
            elseif depth < 5 then
                Scan(child, depth + 1)
            end
        end
    end
end

-- Titelleiste (Name + Schließen) TITLE_UP höher: unsere Fläche reicht oben so weit über Blizzards Fensterrand
-- hinaus, Name und Kreuz rücken mit – Blizzards Inhalt bleibt, wo er ist (wie beim Handelsfenster)
local raised = setmetatable({}, { __mode = "k" })
local function Raise(obj)
    if not obj or raised[obj] or not obj.GetNumPoints or obj:GetNumPoints() == 0 then return end
    raised[obj] = true
    local points = {}
    for i = 1, obj:GetNumPoints() do
        local p, rel, rp, x, y = obj:GetPoint(i)
        points[i] = { p, rel, rp, x or 0, (y or 0) + TITLE_UP }
    end
    obj:ClearAllPoints()
    for _, pt in ipairs(points) do obj:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

-- Knopf zum Ein-/Ausklappen der Werte (gelber Pfeil oben rechts neben "Stufe …"): feiner Pfeil ohne Kasten wie bei
-- uns überall, grau, beim Überfahren gold; zeigt nach links, solange die Werte offen sind, sonst nach rechts
local expandArrow
local function IsExpandButton(b)
    if (b:GetWidth() or 0) > 32 or (b:GetHeight() or 0) > 32 then return false end
    local text = b.GetText and b:GetText()
    if type(text) == "string" and text ~= "" then return false end
    local key = (b:GetName() or ""):lower()
    if key:find("expand") or key:find("collapse") then return true end
    local t = b.GetNormalTexture and b:GetNormalTexture()
    if not t then return false end
    local atlas = t.GetAtlas and t:GetAtlas()
    local tex = t:GetTexture()
    local s = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
    return s:find("arrow") or s:find("expand") or s:find("collapse") or s:find("pagebutton")
end
local function FindExpandButton(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not slotDone[child] then
            if child:IsObjectType("Button") and not child:IsObjectType("CheckButton") and IsExpandButton(child) then
                return child
            end
            if depth < 3 then
                local found = FindExpandButton(child, depth + 1)
                if found then return found end
            end
        end
    end
end
local function SkinExpandButton(f)
    if not expandArrow then
        -- (im Forever-Client: CharacterFrameRightPaneToggleButton, laut /fskin maus)
        local b = G("CharacterFrameRightPaneToggleButton") or G("CharacterFrameExpandButton")
            or FindExpandButton(G("PaperDollFrame") or f, 1)
        if not b or Forbidden(b) then return end
        -- unser Pfeil auf eigenem Unter-Rahmen: das Ausblenden der Knopf-Grafiken im Takt trifft ihn nicht
        local holder = CreateFrame("Frame", nil, b)
        holder:SetAllPoints(b)
        holder:EnableMouse(false)
        local arrow = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetSize(11, 11)
        arrow:SetPoint("CENTER")
        arrow:SetVertexColor(0.8, 0.8, 0.82)
        b:HookScript("OnEnter", function() arrow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3]) end)
        b:HookScript("OnLeave", function() arrow:SetVertexColor(0.8, 0.8, 0.82) end)
        expandArrow = { button = b, arrow = arrow }
    end
    -- (Blizzard setzt seine Grafiken beim Umschalten neu: weiter unsichtbar halten; Richtung nach dem Zustand)
    local b = expandArrow.button
    ns.HideTextures(b) -- (der Pfeil ist hier eine eigene Grafik des Knopfs, Ebene ARTWORK)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = b[get] and b[get](b)
        if t then ns.Hide(t) end
    end
    local right = G("CharacterFrameRightPaneHost") or G("CharacterStatsPane")
    local open = right and right:IsShown()
    expandArrow.arrow:SetRotation(open and math.pi or 0)
end

-- feine goldene Trennlinien: unter "Stufe …, Klasse" (Unterkante des früheren Streifens der Ausrüstungsseite) und
-- rechts unter den 4 Reitern (Unterkante des früheren Steinstreifens) – wie die Linie unter der Titelleiste
local function SubLines()
    local function Line(parent, anchor, up, left, owner)
        -- (auf eigenem Unter-Rahmen: das Ausblenden der Grafiken von parent im Takt trifft ihn nicht. owner: Rahmen,
        -- mit dem die Linie ein-/ausgeblendet wird – z. B. nur auf der Ausrüstungsseite)
        local holder = CreateFrame("Frame", nil, owner or parent)
        ourFrames[holder] = true
        holder:SetAllPoints(parent)
        if owner then holder:SetFrameLevel(parent:GetFrameLevel() + 5) end
        holder:EnableMouse(false)
        local line = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        ns.OnePixel(line, true)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", left or 0, up or 0)
        line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, up or 0)
        return line
    end
    local paper = G("PaperDollFrame")
    local host = paper and paper.TopBackgroundStripHost
    if type(host) == "table" and not Forbidden(host) then Line(host, host.TopBackgroundStrip or host) end
    local right, stone = G("CharacterFrameRightPaneHost"), G("CharacterFrameRightPaneHostStoneBg")
    -- (der Steinstreifen reicht ein Stück unter die Reiter – Linie RIGHT_LINE_UP höher, auf Wunsch)
    -- (1 px später beginnen: sonst lag sie 1 px über der senkrechten Trennlinie. Nur auf der Ausrüstungsseite – dort
    -- sind die 4 Reiter; auf den übrigen Seiten lief sie mitten durch die Texte)
    -- Auf Wunsch auch auf "Spieler gegen Spieler" und "Währung" – dort rückt der Detailbereich darunter (siehe
    -- FixDetailFrames, rightLines)
    if right and stone and not Forbidden(right) then
        for _, owner in ipairs({ paper or false, G("PVPRankFrame") or false, G("TokenFrame") or false }) do
            if owner and not Forbidden(owner) then
                rightLines[#rightLines + 1] = Line(right, stone, RIGHT_LINE_UP, 1, owner)
            end
        end
    end
end

-- Werte-Spalte rechts: Überschriften ("Allgemein", "Primäre Eigenschaften" …: Rahmen mit Titel und Hintergrund) als
-- flacher grauer Balken mit goldener Schrift; Wertezeilen (Beschriftung + Wert): Blizzards braune Streifen weg, der
-- Wechsel der Zeilen bleibt als dezenter heller Streifen (sichtbar, wenn Blizzard dort einen Streifen zeigt)
local statDone = setmetatable({}, { __mode = "k" })
local function StatBackground(frame)
    return frame.Background or frame.background or frame.Bg
end
local function SkinStatFrame(frame)
    local bg = StatBackground(frame)
    local title = frame.Title or frame.title or frame.Header
    local label = frame.Label or frame.label
    if title and title.SetTextColor and type(bg) == "table" then
        -- Überschrift
        if not statDone[frame] then
            statDone[frame] = "header"
            ns.Flat(frame, C.button, { 2, 1, 2, 1 })
        end
        ns.HideTextures(frame)
        title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    elseif label and (frame.Value or frame.value) and type(bg) == "table" then
        -- Wertezeile: eigener dezenter Streifen, sichtbar wie Blizzards (der selbst unsichtbar wird)
        if not statDone[frame] then
            statDone[frame] = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            statDone[frame]:SetColorTexture(1, 1, 1, 0.04)
            statDone[frame]:SetAllPoints(bg)
        end
        statDone[frame]:SetShown(bg:IsShown())
        bg:SetAlpha(0)
    end
end
local function SkinStats(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not slotDone[child] then
            SkinStatFrame(child)
            if depth < 6 then SkinStats(child, depth + 1) end
        end
    end
end

-- Im Forever-Client ist die Werte-Spalte eine eigene Laufliste direkt am Fenster (CharacterStatsPaneScrollBox, laut
-- /fskin grafik) – Einträge allgemein erkannt: Überschrift = Kopf-/Kategorie-Grafik oder mindestens 24 hoch, sonst
-- Wertezeile. Rand der Liste ("common-insideframe") weg; das Klassenbild dahinter bleibt
local function IsStatHeader(entry)
    if (entry:GetHeight() or 0) >= 24 then return true end
    for _, r in ipairs({ entry:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local atlas = r.GetAtlas and r:GetAtlas()
            local s = (type(atlas) == "string" and atlas or ""):lower()
            if s:find("header") or s:find("category") or s:find("title") then return true end
        end
    end
    return false
end
local stripes = setmetatable({}, { __mode = "k" })
-- Blizzards Zeilenstreifen ("UI-Character-Info-Line-Bounce2"): Blizzard setzt ihre Sichtbarkeit für den Zeilenwechsel
-- ständig neu – darum gleich nach jeder solchen Änderung wieder unsichtbar (Haken mit Sperre gegen Schleifen)
local KeepInvisible = ns.KeepInvisible -- (gemeinsam in Core.lua)
-- Inhalt der Liste: moderne Liste (ScrollTarget) oder ältere (ScrollFrame mit Inhalt)
-- (im Forever-Client ist "CharacterStatsPaneScrollBox" ein einfacher Rahmen, laut /fskin werte: die Liste steckt
-- darin – sonst ist der Rahmen selbst der Behälter)
local function StatTarget(list)
    if list.GetScrollTarget then return list:GetScrollTarget() end
    if list.GetScrollChild and list:GetScrollChild() then return list:GetScrollChild() end
    for _, child in ipairs({ list:GetChildren() }) do
        if not Forbidden(child) then
            if child.GetScrollTarget and child:GetScrollTarget() then return child:GetScrollTarget() end
            if child.GetScrollChild and child:GetScrollChild() then return child:GetScrollChild() end
        end
    end
    return list
end
-- Einträge = Rahmen mit Text (auch tiefer verschachtelt: Behälter ohne eigenen Text werden durchsucht)
local function HasText(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("FontString") and (r:GetText() or "") ~= "" then return true end
    end
    return false
end
local function StatEntries(frame, out, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and child:IsShown() and not (child.Track or child:IsObjectType("Slider")) then
            if HasText(child) then out[#out + 1] = child end
            -- (auch in Einträgen weitersuchen: die Wertezeilen hängen teils IN ihrer Überschrift)
            if depth < 5 then StatEntries(child, out, depth + 1) end
        end
    end
    return out
end

-- /fskin werte: Aufbau der Werte-Spalte im Chat (Fehlersuche)
function ns.DumpStats()
    local function Say(t) print("|cffffcc00ForeverSkin|r: " .. tostring(t)) end
    local list = G("CharacterStatsPaneScrollBox")
    if not list then return Say("CharacterStatsPaneScrollBox nicht gefunden") end
    local target = StatTarget(list)
    Say(string.format("Liste: %s, Inhalt: %s", list:GetObjectType(), tostring(target and target:GetDebugName())))
    if not target then return end
    for i, entry in ipairs(StatEntries(target, {}, 1)) do
        if i > 12 then break end
        local tex = {}
        for _, r in ipairs({ entry:GetRegions() }) do
            if r:IsObjectType("Texture") then
                tex[#tex + 1] = tostring(r.GetAtlas and r:GetAtlas() or r:GetTexture())
            end
        end
        Say(string.format("%d. %s %dx%d Kopf=%s | %s", i, tostring(entry:GetDebugName()), entry:GetWidth() or 0,
            entry:GetHeight() or 0, tostring(IsStatHeader(entry)), table.concat(tex, ", ")))
    end
end

-- Laufleiste der Werte-Spalte SCROLL_RIGHT nach rechts: mehr Luft zu den Werten (auf Wunsch) – einmal
local SCROLL_RIGHT = 5
local scrollMoved = setmetatable({}, { __mode = "k" })
local function MoveStatScrollBar(list)
    local bar = list.ScrollBar
    if type(bar) ~= "table" then
        for _, child in ipairs({ list:GetChildren() }) do
            if not Forbidden(child) and type(child.Track) == "table" then bar = child end
        end
    end
    if type(bar) ~= "table" or Forbidden(bar) or scrollMoved[bar] or bar:GetNumPoints() == 0 then return end
    scrollMoved[bar] = true
    local points = {}
    for i = 1, bar:GetNumPoints() do
        local p, rel, rp, x, y = bar:GetPoint(i)
        points[i] = { p, rel, rp, (x or 0) + SCROLL_RIGHT, y or 0 }
    end
    bar:ClearAllPoints()
    for _, pt in ipairs(points) do bar:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

local function SkinStatList(list)
    if type(list.Border) == "table" then ns.Hide(list.Border) end
    pcall(MoveStatScrollBar, list)
    -- Klassenbild hinter der Werte-Spalte ("UI-Character-Info-<Klasse>-BG"): weg, auf Wunsch – darunter unsere
    -- flache Innenfläche der rechten Seite
    if type(list.ClassBackground) == "table" then ns.Hide(list.ClassBackground) end
    local target = StatTarget(list)
    if not target then return end
    local rows = {}
    for _, entry in ipairs(StatEntries(target, {}, 1)) do
        if not Forbidden(entry) and entry:IsShown() and entry:GetTop() then
            local header = IsStatHeader(entry)
            if header then
                if statDone[entry] ~= "header" then
                    statDone[entry] = "header"
                    ns.Flat(entry, C.button, HEADER_INSET) -- (etwas kleiner als der Eintrag – auf Wunsch)
                end
                ns.HideTextures(entry)
                for _, r in ipairs({ entry:GetRegions() }) do
                    if r:IsObjectType("FontString") then r:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
                end
                if stripes[entry] then stripes[entry]:Hide() end
            else
                for _, r in ipairs({ entry:GetRegions() }) do
                    if r:IsObjectType("Texture") and r ~= stripes[entry] then KeepInvisible(r) end
                end
                if not stripes[entry] then
                    stripes[entry] = entry:CreateTexture(nil, "BACKGROUND", nil, -7)
                    stripes[entry]:SetColorTexture(1, 1, 1, 0.04)
                    stripes[entry]:SetAllPoints(entry)
                end
                rows[#rows + 1] = entry
            end
        end
    end
    -- Zeilenwechsel: jede zweite Zeile (von oben) mit dezentem Streifen
    table.sort(rows, function(a, b) return a:GetTop() > b:GetTop() end)
    for i, entry in ipairs(rows) do stripes[entry]:SetShown(i % 2 == 0) end
end

-- Ruf-Seite: Überschriften ("Horde", "Steamwheedle-Kartell" …) als flacher grauer Balken wie in der Werte-Spalte.
-- Überschrift = Eintrag OHNE Rufbalken (die Zeilen mit "Neutral" … haben einen und bleiben). Nur breite Grafiken weg –
-- das kleine "−" zum Zuklappen bleibt. Blizzard setzt die Leisten beim Auf-/Zuklappen neu: darum in jedem Bild
local repHeaders = setmetatable({}, { __mode = "k" })
local HookRepList -- (weiter unten gesetzt: Ruf-Liste beim Befüllen prüfen)
local function HasStatusBar(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("StatusBar") then return true end
            if depth < 3 and HasStatusBar(child, depth + 1) then return true end
        end
    end
    return false
end
local function HideWide(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) and (r:GetWidth() or 0) >= 30 then r:SetAlpha(0) end
    end
end
local function SkinRepHeaders()
    for entry in pairs(repHeaders) do
        if entry:IsVisible() then
            HideWide(entry)
            for _, child in ipairs({ entry:GetChildren() }) do
                if not Forbidden(child) and not child:IsObjectType("Button") then HideWide(child) end
            end
        end
    end
end
-- Grafiken der Ruf-Überschriften merken: dieselbe braune Leiste haben die Überschriften der übrigen Seiten
-- (Statistiken, Währung, Fertigkeiten) – daran werden sie dort erkannt (dazu alles mit "header" im Namen)
local headerArt = {}
local function WideArt(frame)
    local list = {}
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) and r:GetDrawLayer() ~= "HIGHLIGHT"
            and (r:GetWidth() or 0) >= 30 then
            local atlas = r.GetAtlas and r:GetAtlas()
            local key = (type(atlas) == "string" and atlas ~= "" and atlas) or r:GetTexture()
            if key then list[#list + 1] = key end
        end
    end
    return list
end
local function MarkHeader(entry)
    repHeaders[entry] = true
    ns.Flat(entry, C.button, { 0, 1, 0, 1 })
    -- breite Blizzard-Grafiken (die Leiste) dauerhaft unsichtbar: Haken an der Grafik selbst – Blizzard macht sie
    -- beim Öffnen wieder sichtbar, das blitzte sonst kurz auf
    local function Keep(frame)
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsObjectType("Texture") and not ns.IsMine(frame, r) and r:GetDrawLayer() ~= "HIGHLIGHT"
                and (r:GetWidth() or 0) >= 30 then
                KeepInvisible(r)
            end
        end
    end
    Keep(entry)
    for _, child in ipairs({ entry:GetChildren() }) do
        if not Forbidden(child) and not child:IsObjectType("Button") then Keep(child) end
    end
end
local function FindRepHeaders()
    local rep = G("ReputationFrame")
    local list = rep and (rep.ScrollBox or G("ReputationFrameScrollBox") or G("ReputationListScrollFrame"))
    local target = list and StatTarget(list)
    if not target then return end
    if list.GetScrollTarget and HookRepList then HookRepList(list) end
    for _, entry in ipairs({ target:GetChildren() }) do
        if not Forbidden(entry) and not repHeaders[entry] and entry:IsShown() and HasText(entry)
            and not HasStatusBar(entry, 1) then
            for _, key in ipairs(WideArt(entry)) do headerArt[key] = true end
            MarkHeader(entry)
        end
    end
end

-- Auf-/Zuklappen in den Listen (rotes Plus/Minus vor "Schlachtfelder" …): feiner Pfeil wie überall – zugeklappt
-- nach rechts, aufgeklappt nach unten. Den Zustand verrät Blizzards (unsichtbare) Knopfgrafik
local ToggleState = ns.ToggleState -- (gemeinsam in Core.lua)
local function SkinToggles(entry)
    for _, child in ipairs({ entry:GetChildren() }) do
        if not Forbidden(child) and child:IsObjectType("Button") and (child:GetWidth() or 0) <= 24 then
            local state = ToggleState(child)
            if state ~= nil then ns.SkinToggle(child, state) end
        end
    end
end

-- übrige Seiten (Statistiken, Währung, Fertigkeiten …): in allen sichtbaren Listen des Fensters Einträge mit der
-- Überschrift-Leiste (wie bei Ruf, oder "header" im Grafiknamen) – die Werte-Listen haben ihre eigene Behandlung
local function IsHeaderArt(key)
    return headerArt[key] or (type(key) == "string" and key:lower():find("header") ~= nil)
end
-- Eintrag sofort beim Befüllen durch Blizzard prüfen (noch bevor er gezeichnet wird – sonst sah man beim Öffnen kurz
-- Blizzards Leiste): Überschrift erkannt -> Balken und Leiste weg. rep = Ruf-Liste (Überschrift = ohne Rufbalken)
local function ClassifyEntry(entry, rep)
    if Forbidden(entry) or not HasText(entry) then return end
    if not repHeaders[entry] then
        local header = false
        if rep then
            header = not HasStatusBar(entry, 1)
            if header then
                for _, key in ipairs(WideArt(entry)) do headerArt[key] = true end
            end
        else
            for _, key in ipairs(WideArt(entry)) do
                if IsHeaderArt(key) then header = true break end
            end
        end
        if header then MarkHeader(entry) end
    end
    if repHeaders[entry] then
        HideWide(entry)
        for _, child in ipairs({ entry:GetChildren() }) do
            if not Forbidden(child) and not child:IsObjectType("Button") then HideWide(child) end
        end
    end
    pcall(SkinToggles, entry)
end
local hookedLists = setmetatable({}, { __mode = "k" })
local function HookList(list, rep)
    if hookedLists[list] or not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    hookedLists[list] = true
    pcall(ScrollUtil.AddInitializedFrameCallback, list, function(_, entry) pcall(ClassifyEntry, entry, rep) end, list)
end
HookRepList = function(list) HookList(list, true) end

local function FindPageHeaders(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and child:IsVisible() and not slotDone[child] then
            local name = child:GetName() or ""
            local target = (child.GetScrollTarget and child:GetScrollTarget())
                or (child:IsObjectType("ScrollFrame") and child:GetScrollChild())
            if target and not name:find("Stats") then
                if child.GetScrollTarget then HookList(child, frame == G("ReputationFrame")) end
                -- Ausrüstungsmanager und Titel ("Neues Set", gespeicherte Sets, Titel): jeder Eintrag als flacher
                -- grauer Balken (breite Blizzard-Grafiken weg, Symbole bleiben)
                local debug = (child.GetDebugName and child:GetDebugName() or "") .. "|" .. (frame:GetDebugName() or "")
                if debug:find("EquipmentManager") or debug:find("TitleManager") or debug:find("GearManager") then
                    for _, entry in ipairs({ target:GetChildren() }) do
                        if not Forbidden(entry) and not repHeaders[entry] and entry:IsShown() then MarkHeader(entry) end
                    end
                end
                for _, entry in ipairs({ target:GetChildren() }) do
                    if not Forbidden(entry) and entry:IsShown() then pcall(SkinToggles, entry) end
                    if not Forbidden(entry) and not repHeaders[entry] and entry:IsShown() and HasText(entry) then
                        for _, key in ipairs(WideArt(entry)) do
                            if IsHeaderArt(key) then
                                MarkHeader(entry)
                                break
                            end
                        end
                    end
                end
            elseif depth < 4 and not name:find("Stats") then
                FindPageHeaders(child, depth + 1)
            end
        end
    end
end

-- alle Werte-Listen (eigene Werte, Begleiter …): Rahmen mit "Stats" im Namen und einer Liste darin
local function FindStatLists(frame, depth, out)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and child:IsVisible() then
            local name = child:GetName() or ""
            if name:find("Stats") and StatTarget(child) ~= child then
                out[#out + 1] = child
            elseif depth < 3 then
                FindStatLists(child, depth + 1, out)
            end
        end
    end
    return out
end

-- Detailbereich rechts (Ruf, Fertigkeiten, Spieler gegen Spieler: Name, Stand, Beschreibung …) beginnt bei Blizzard
-- über unserer goldenen Linie unter der Titelleiste: so weit nach unten, dass er DETAIL_GAP darunter beginnt.
-- Nur große Bereiche rechts, die über die Linie ragen (nicht die 4 Reiter, nicht die Werte-Liste); gemessen
local DETAIL_GAP = 8
local function LowerDetails(f)
    local left, right = G("CharacterFrameLeftPaneHost"), G("CharacterFrameRightPaneHost")
    if not (left and right and left:GetTop() and right:GetLeft()) then return end
    local lineTop = left:GetTop()
    local function Check(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            -- (DetailFrame nicht hier – der wird unten als Ganzes behandelt, sonst zweimal verschoben)
            if not Forbidden(child) and not ourFrames[child] and child ~= frame.DetailFrame and child:IsVisible()
                and child:GetTop() and child:GetLeft()
                and child:GetLeft() >= right:GetLeft() - 4 and (child:GetHeight() or 0) > 60
                and not (child:GetName() or ""):find("Stats") and child:GetNumPoints() > 0 then
                local delta = child:GetTop() - (lineTop - DETAIL_GAP)
                if delta > 0.5 then
                    local points = {}
                    for i = 1, child:GetNumPoints() do
                        local p, rel, rp, x, y = child:GetPoint(i)
                        points[i] = { p, rel, rp, x or 0, (y or 0) - delta }
                    end
                    child:ClearAllPoints()
                    for _, pt in ipairs(points) do child:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
                end
            end
        end
    end
    Check(right)
    for _, page in ipairs({ "ReputationFrame", "TokenFrame", "SkillFrame", "PVPFrame", "HonorFrame" }) do
        if G(page) and G(page):IsVisible() then Check(G(page)) end
    end
end

-- Seiten mit "DetailFrame" (z. B. PVPRankFrame, laut /fskin maus): den ganzen Block unter unsere goldene Linie unter
-- der Titelleiste (so bleiben die Texte darin richtig zueinander) und seinen hellen Balken
-- ("UI-Character-Info-ScrollLine") weg. Eigener Schritt, unabhängig von den Seitenflächen (die gibt es nicht überall)
-- Blizzards "ScrollLine"-Grafiken (z. B. "UI-Character-Info-ScrollLine-Long" über dem Anfang der Listen, die hellen
-- Balken in den Detailbereichen) im ganzen Charakterfenster weg – lagen über den Texten (auf Wunsch überall)
local function NoScrollLines(frame, depth)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local atlas = r.GetAtlas and r:GetAtlas()
            -- (dazu Blizzards Innenrahmen mit Zierecken, "common-insideframe" – z. B. um den Ausrüstungsmanager)
            if type(atlas) == "string" and (atlas:find("ScrollLine") or atlas:find("insideframe")) then r:SetAlpha(0) end
        end
    end
    if depth < 7 then
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) and not ourFrames[child] then NoScrollLines(child, depth + 1) end
        end
    end
end

local titleLine -- unsere goldene Linie unter der Titelleiste (Maß für "darunter")
local function DetailLineTop()
    local lineTop = titleLine and titleLine:GetTop()
    -- ist auf der Seite die Linie unter den Reitern rechts zu sehen, gilt sie (sie liegt tiefer)
    for _, l in ipairs(rightLines) do
        if l:IsVisible() and l:GetTop() then lineTop = math.min(lineTop or l:GetTop(), l:GetTop()) end
    end
    return lineTop
end
local detailHooked = setmetatable({}, { __mode = "k" }) -- [Bereich] = true / "busy" (Sperre beim eigenen Verschieben)
local detailHookSet = setmetatable({}, { __mode = "k" }) -- [Bereich] = Haken an SetPoint gesetzt
local FixDetailFrames
local function FixDetailFrames_(f)
    local lineTop = DetailLineTop()
    if not lineTop then return end
    -- Detailbereiche: Schlüssel "DetailFrame" oder ein Unter-Rahmen mit "Detail" im Namen (z. B. SkillDetailFrame
    -- in SkillsFrame, laut /fskin grafik)
    local details = {}
    for _, page in ipairs({ f:GetChildren() }) do
        if not Forbidden(page) and page:IsVisible() then
            if type(page.DetailFrame) == "table" then details[#details + 1] = page.DetailFrame end
            for _, child in ipairs({ page:GetChildren() }) do
                if not Forbidden(child) and child ~= page.DetailFrame and (child:GetName() or ""):find("Detail") then
                    details[#details + 1] = child
                end
            end
        end
    end
    -- oberste sichtbare Kante des Bereichs: auch Texte/Grafiken, die über seinen Rand hinausragen (z. B. der Titel
    -- "Zivilist" sitzt über der Oberkante des Bereichs)
    local function ContentTop(frame)
        local top = frame:GetTop()
        for _, r in ipairs({ frame:GetRegions() }) do
            if r:IsShown() and r:GetTop() and (r:GetAlpha() or 1) > 0 then top = math.max(top or r:GetTop(), r:GetTop()) end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) and child:IsShown() and child:GetTop() then top = math.max(top or child:GetTop(), child:GetTop()) end
        end
        return top
    end
    for _, detail in ipairs(details) do
        if type(detail) == "table" and not Forbidden(detail) and detail:IsVisible() then
            local function NoScrollLine(frame, depth)
                for _, r in ipairs({ frame:GetRegions() }) do
                    local atlas = r:IsObjectType("Texture") and r.GetAtlas and r:GetAtlas()
                    if type(atlas) == "string" and atlas:find("ScrollLine") then r:SetAlpha(0) end
                end
                if depth < 2 then
                    for _, child in ipairs({ frame:GetChildren() }) do
                        if not Forbidden(child) then NoScrollLine(child, depth + 1) end
                    end
                end
            end
            ns.Hide(detail.Divider)
            NoScrollLine(detail, 1)
            if detailHooked[detail] ~= "busy" then
                local delta = (ContentTop(detail) or lineTop) - (lineTop - DETAIL_GAP)
                if delta > 0.5 and detail:GetNumPoints() > 0 then
                    detailHooked[detail] = "busy"
                    local points = {}
                    for i = 1, detail:GetNumPoints() do
                        local p, rel, rp, x, y = detail:GetPoint(i)
                        points[i] = { p, rel, rp, x or 0, (y or 0) - delta }
                    end
                    detail:ClearAllPoints()
                    for _, pt in ipairs(points) do detail:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
                    detailHooked[detail] = true
                end
            end
            -- setzt Blizzard die Lage neu (z. B. anderer Eintrag gewählt): sofort wieder darunter (kein Springen)
            if not detailHookSet[detail] then
                detailHookSet[detail] = true
                hooksecurefunc(detail, "SetPoint", function()
                    if detailHooked[detail] ~= "busy" then pcall(FixDetailFrames, f) end
                end)
            end
        end
    end
end
FixDetailFrames = FixDetailFrames_

-- Listen auf den übrigen Seiten (Statistiken, Ruf, Währung …) samt Laufleiste: oben kürzer, so dass sie LIST_GAP
-- unter unserer goldenen Linie beginnen (sie reichten darüber, Text lag unter dem Streifen) – nur die oberen
-- Ankerpunkte, die Unterkante bleibt; gemessen, nur wenn nötig. Werte-Listen und eigene Rahmen nicht
local LIST_GAP = 6
local function ShortenLists(f)
    local left = G("CharacterFrameLeftPaneHost")
    if not (left and left:GetTop()) then return end
    local limit = left:GetTop() - LIST_GAP
    local function Walk(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) and not ourFrames[child] and child:IsVisible()
                and not (child:GetName() or ""):find("Stats") then
                local isList = child.GetScrollTarget or (child:IsObjectType("ScrollFrame") and child:GetScrollChild())
                    or type(child.Track) == "table"
                if isList then
                    local delta = (child:GetTop() or limit) - limit
                    if delta > 0.5 and child:GetNumPoints() > 0 then
                        local points = {}
                        for i = 1, child:GetNumPoints() do
                            local p, rel, rp, x, y = child:GetPoint(i)
                            if p:find("TOP") then y = (y or 0) - delta end
                            points[i] = { p, rel, rp, x or 0, y or 0 }
                        end
                        child:ClearAllPoints()
                        for _, pt in ipairs(points) do child:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
                    end
                elseif depth < 4 then
                    Walk(child, depth + 1)
                end
            end
        end
    end
    Walk(f, 1)
end

-- Knopf "Neues Set" im Ausrüstungsmanager (PaperDollFrameNewSet, laut /fskin maus): flacher Knopf; Blizzards
-- Hintergrund ("StateTexture", setzt Blizzard bei jeder Maus-Bewegung neu) und übrige breite Grafiken bei jedem
-- Durchgang unsichtbar – das grüne Plus bleibt (schmal)
local function SkinNewSet()
    local b = G("PaperDollFrameNewSet")
    if not b or Forbidden(b) then return end
    if not b.foreverSkinned then
        b.foreverSkinned = true
        ns.Flat(b, C.button, { 0, 1, 0, 1 })
        ns.Hover(b)
    end
    ns.Hide(b.StateTexture)
    HideWide(b)
end

local function SkinCharacter()
    local f = G("CharacterFrame")
    if not f or ns.characterSkinned or Forbidden(f) then return end
    ns.characterSkinned = true
    Step("frame", function()
        HideFrameArt(f)
        ns.Flat(f, C.background, { 0, -TITLE_UP, 0, 0 })
        ns.KeepOnScreen(f, TITLE_UP, 0)
        -- feiner Rand ums ganze Fenster auf eigenem Rahmen ÜBER den Hintergründen links/rechts (die verdeckten ihn),
        -- unter dem Porträt; ohne Füllung, ohne Maus
        local border = CreateFrame("Frame", nil, f)
        border:SetAllPoints(f)
        border:SetFrameLevel(f:GetFrameLevel() + 100) -- (der linke Hintergrund liegt hoch und verdeckte den Rand)
        border:EnableMouse(false)
        ns.Flat(border, { 0, 0, 0, 0 }, { 0, -TITLE_UP, 0, 0 })
        -- goldene Trennlinie unter der Titelleiste: an der Oberkante der Hintergründe (linke Seite), sonst 23 unter
        -- Blizzards Rand
        local line = border:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        ns.OnePixel(line, true)
        titleLine = line
        local function PlaceLine()
            local pane = G("CharacterFrameLeftPaneHost")
            local y = -23
            if pane and pane:GetTop() and f:GetTop() then y = math.floor(pane:GetTop() - f:GetTop() + 0.5) end
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, y)
            line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, y)
        end
        PlaceLine()
        f:HookScript("OnShow", function() C_Timer.After(0, PlaceLine) end)
        f:HookScript("OnSizeChanged", function() C_Timer.After(0, PlaceLine) end)
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or G("CharacterFrameTitleText")
        if title then title:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end
        Raise(f.TitleContainer or title)
        local close = ns.FindCloseButton(f)
        ns.SkinClose(close)
        Raise(close)
    end)
    Step("portrait", function() Portrait(f) end)
    Step("lines", SubLines)
    Step("slots", function()
        for _, s in ipairs(SLOTS) do SkinSlot(G("Character" .. s .. "Slot")) end
    end)
    Step("tabs", function()
        for i = 1, 6 do
            local tab = G("CharacterFrameTab" .. i)
            if tab and not Forbidden(tab) then ns.SkinTab(tab, TabSelected) end
        end
    end)
    Step("scan", function() Scan(f, 1) end)
    -- Listen gleich einhaken (Einträge werden dann schon beim ersten Befüllen umgestaltet)
    Step("lists", function()
        FindRepHeaders()
        FindPageHeaders(f, 1)
    end)
    -- jede Seite: sobald sie gezeigt wird (Blizzard hat die Liste dann schon gefüllt, gezeichnet wird erst danach)
    -- Überschriften suchen und umgestalten – sonst sah man beim Öffnen kurz Blizzards Leisten
    local function OnPageShow()
        pcall(FindRepHeaders)
        pcall(FindPageHeaders, f, 1)
        pcall(SkinRepHeaders)
        -- (Detailbereiche und Listen gleich an ihren Platz – sonst sah man die Texte kurz springen)
        pcall(NoScrollLines, f, 1)
        pcall(FixDetailFrames, f)
        if not (G("PaperDollFrame") and G("PaperDollFrame"):IsVisible()) then
            pcall(LowerDetails, f)
            pcall(ShortenLists, f)
        end
    end
    f:HookScript("OnShow", OnPageShow)
    for _, page in ipairs({ f:GetChildren() }) do
        if not Forbidden(page) and page.HookScript then page:HookScript("OnShow", OnPageShow) end
    end
    ns.Watch(f)
    f:HookScript("OnShow", function() Step("portrait", function() Portrait(f) end) end)
    -- Blizzard blendet Rahmen beim Öffnen/Umschalten wieder ein und baut Seiten erst beim ersten Zeigen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    -- nach dem Öffnen und jedem Reiterwechsel eine halbe Sekunde lang in JEDEM Bild umgestalten – sonst sah man
    -- Blizzards Grafiken kurz, bis zur nächsten Prüfung
    local fastUntil = 0
    local function Fast() fastUntil = GetTime() + 0.5 end
    f:HookScript("OnShow", Fast)
    for i = 1, 8 do
        local tab = G("CharacterFrameTab" .. i)
        if tab and not Forbidden(tab) then tab:HookScript("OnClick", Fast) end
    end
    watch:SetScript("OnUpdate", function(_, elapsed)
        pcall(SkinRepHeaders) -- (jedes Bild: Blizzard setzt die Leisten der Ruf-Überschriften neu)
        waited = waited + elapsed
        if waited < 0.3 and GetTime() > fastUntil then return end
        local rep = G("ReputationFrame")
        if rep and rep:IsVisible() then pcall(FindRepHeaders) end
        pcall(FindPageHeaders, f, 1)
        if not (G("PaperDollFrame") and G("PaperDollFrame"):IsVisible()) then
            pcall(LowerDetails, f)
            pcall(ShortenLists, f)
        end
        pcall(NoScrollLines, f, 1)
        -- Symbol-Auswahl für Ausrüstungssets: gleiche Umgestaltung wie die Makro-Symbol-Auswahl (Macro.lua)
        local gearPopup = G("GearManagerPopupFrame")
        if gearPopup and ns.SkinIconPopup and not Forbidden(gearPopup) then
            pcall(ns.SkinIconPopup, gearPopup)
            -- OK/Abbrechen hier 4 tiefer (auf Wunsch; OK hängt an Abbrechen und wandert mit) – einmal
            local cancel = gearPopup.BorderBox and gearPopup.BorderBox.CancelButton
            if cancel and not cancel.foreverLowered and cancel:GetNumPoints() == 1 then
                cancel.foreverLowered = true
                local p, rel, rp, x, y = cancel:GetPoint(1)
                cancel:SetPoint(p, rel, rp, x or 0, (y or 0) - 4)
            end
        end
        pcall(SkinNewSet)
        -- (Fehler einmal melden statt still zu schlucken)
        local okDetail, errDetail = pcall(FixDetailFrames, f)
        if not okDetail and not watch.detailReported then
            watch.detailReported = true
            if ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "character/details", errDetail) end
        end
        -- Werte-Listen außer der eigenen (z. B. Begleiter) – gleiche Behandlung
        local ok, lists = pcall(FindStatLists, f, 1, {})
        if ok then
            for _, l in ipairs(lists) do
                if l ~= G("CharacterStatsPaneScrollBox") then pcall(SkinStatList, l) end
            end
        end
        waited = 0
        -- Linie unter den 4 Reitern rechts nur, solange die Werte-Spalte offen ist (zugeklappt ragte sie sonst rechts
        -- über das Fenster hinaus)
        local rightHost = G("CharacterFrameRightPaneHost")
        local rightOpen = rightHost and rightHost:IsVisible() and true or false
        for _, l in ipairs(rightLines) do l:SetShown(rightOpen) end
        pcall(HideFrameArt, f)
        pcall(SkinExpandButton, f)
        pcall(Scan, f, 1)
        local right = G("CharacterFrameRightPaneHost")
        if right and right:IsVisible() then pcall(SkinStats, right, 1) end
        local statList = G("CharacterStatsPaneScrollBox")
        if statList and statList:IsVisible() and not Forbidden(statList) then pcall(SkinStatList, statList) end
        for i = 1, 6 do
            local tab = G("CharacterFrameTab" .. i)
            if tab and tab:IsShown() then pcall(ns.CenterText, tab) end
        end
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.characterSkinned or not ns.GetDB().character or not G("CharacterFrame") then return end
    Step("skin", SkinCharacter)
end)
