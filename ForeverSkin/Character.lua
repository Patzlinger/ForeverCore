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
    for _, page in ipairs({ "PaperDollFrame", "ReputationFrame", "TokenFrame" }) do
        local host = G(page) and G(page).TopBackgroundStripHost
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
                        -- Blizzards Trennlinie ist 11 breit mit dunklem Schatten (wirkte neben dem Gold wie ein
                        -- schwarzer Streifen): unsichtbar, stattdessen eine eigene goldene Linie von 1 px in ihrer Mitte
                        r:SetAlpha(0)
                        if not dividerLines[r] then
                            local holder = CreateFrame("Frame", nil, right)
                            holder:SetAllPoints(right)
                            holder:SetFrameLevel(child:GetFrameLevel() + 1)
                            holder:EnableMouse(false)
                            local line = holder:CreateTexture(nil, "OVERLAY", nil, 7)
                            line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
                            line:SetWidth(1)
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
        if p[3] then e:SetHeight(SLOT_EDGE) else e:SetWidth(SLOT_EDGE) end
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
    local function Line(parent, anchor, up)
        -- (auf eigenem Unter-Rahmen: das Ausblenden der Grafiken von parent im Takt trifft ihn nicht)
        local holder = CreateFrame("Frame", nil, parent)
        holder:SetAllPoints(parent)
        holder:EnableMouse(false)
        local line = holder:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, up or 0)
        line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, up or 0)
    end
    local paper = G("PaperDollFrame")
    local host = paper and paper.TopBackgroundStripHost
    if type(host) == "table" and not Forbidden(host) then Line(host, host.TopBackgroundStrip or host) end
    local right, stone = G("CharacterFrameRightPaneHost"), G("CharacterFrameRightPaneHostStoneBg")
    -- (der Steinstreifen reicht ein Stück unter die Reiter – Linie RIGHT_LINE_UP höher, auf Wunsch)
    if right and stone and not Forbidden(right) then Line(right, stone, RIGHT_LINE_UP) end
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
local kept = setmetatable({}, { __mode = "k" })
local function KeepInvisible(tex)
    if kept[tex] == nil then
        kept[tex] = true
        local function Again(t)
            if kept[t] == "busy" then return end
            kept[t] = "busy"
            t:SetAlpha(0)
            kept[t] = true
        end
        for _, method in ipairs({ "SetAlpha", "Show", "SetShown", "SetAtlas", "SetTexture", "SetVertexColor" }) do
            if type(tex[method]) == "function" then hooksecurefunc(tex, method, Again) end
        end
    end
    tex:SetAlpha(0)
end
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
end
local function FindRepHeaders()
    local rep = G("ReputationFrame")
    local list = rep and (rep.ScrollBox or G("ReputationFrameScrollBox") or G("ReputationListScrollFrame"))
    local target = list and StatTarget(list)
    if not target then return end
    for _, entry in ipairs({ target:GetChildren() }) do
        if not Forbidden(entry) and not repHeaders[entry] and entry:IsShown() and HasText(entry)
            and not HasStatusBar(entry, 1) then
            for _, key in ipairs(WideArt(entry)) do headerArt[key] = true end
            MarkHeader(entry)
        end
    end
end

-- übrige Seiten (Statistiken, Währung, Fertigkeiten …): in allen sichtbaren Listen des Fensters Einträge mit der
-- Überschrift-Leiste (wie bei Ruf, oder "header" im Grafiknamen) – die Werte-Listen haben ihre eigene Behandlung
local function IsHeaderArt(key)
    return headerArt[key] or (type(key) == "string" and key:lower():find("header") ~= nil)
end
local function FindPageHeaders(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and child:IsVisible() and not slotDone[child] then
            local name = child:GetName() or ""
            local target = (child.GetScrollTarget and child:GetScrollTarget())
                or (child:IsObjectType("ScrollFrame") and child:GetScrollChild())
            if target and not name:find("Stats") then
                for _, entry in ipairs({ target:GetChildren() }) do
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

local function SkinCharacter()
    local f = G("CharacterFrame")
    if not f or ns.characterSkinned or Forbidden(f) then return end
    ns.characterSkinned = true
    Step("frame", function()
        HideFrameArt(f)
        ns.Flat(f, C.background, { 0, -TITLE_UP, 0, 0 })
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
        line:SetHeight(1)
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
        local close = f.CloseButton or G("CharacterFrameCloseButton")
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
    ns.Watch(f)
    f:HookScript("OnShow", function() Step("portrait", function() Portrait(f) end) end)
    -- Blizzard blendet Rahmen beim Öffnen/Umschalten wieder ein und baut Seiten erst beim ersten Zeigen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        pcall(SkinRepHeaders) -- (jedes Bild: Blizzard setzt die Leisten der Ruf-Überschriften neu)
        waited = waited + elapsed
        if waited < 0.3 then return end
        local rep = G("ReputationFrame")
        if rep and rep:IsVisible() then pcall(FindRepHeaders) end
        pcall(FindPageHeaders, f, 1)
        -- Werte-Listen außer der eigenen (z. B. Begleiter) – gleiche Behandlung
        local ok, lists = pcall(FindStatLists, f, 1, {})
        if ok then
            for _, l in ipairs(lists) do
                if l ~= G("CharacterStatsPaneScrollBox") then pcall(SkinStatList, l) end
            end
        end
        waited = 0
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
