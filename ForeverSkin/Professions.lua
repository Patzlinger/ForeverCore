-- ForeverSkin – Professions.lua: Berufe-Fenster (Berufsbuch) im Forever-Stil, nach docs/Fenster-Stil.md.
--  * Fenster flach mit Titelleiste "Berufe" (ohne "Dein Gold" – kein Bezug zum Gold)
--  * Kästen der Berufe: nur Blizzards schmale Rahmenteile weg, ALLES Größere (Hintergrund mit den Zeichnungen der
--    Berufe) bleibt unangetastet; dazu ein feiner grauer Rand
--  * Fortschrittsbalken flach (Füllung und Text bleiben), Zauber-Symbole wie Taschenplätze, "Verlernen" als flaches X
-- Blizzard lädt das Fenster erst beim ersten Öffnen (Blizzard_ProfessionsBook). Wie überall: Blizzards Grafiken nur
-- unsichtbar, eigene darunter, nichts in Blizzards Tabellen; die Zauber-Knöpfe sind geschützt – nur ihr Aussehen.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local BORDER_MAX = 16 -- so schmal (Breite oder Höhe) sind Rahmenteile; Größeres ist Hintergrund/Zeichnung und bleibt

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "professions/" .. what, err) end
end

-- Kasten eines Berufs: schmale Rahmenteile unsichtbar, Zeichnung/Hintergrund bleiben; feiner Rand ohne Füllung
local boxes = setmetatable({}, { __mode = "k" })
local function SkinSection(section)
    if not section or Forbidden(section) then return end
    if section.NineSlice then ns.Hide(section.NineSlice) end
    for _, r in ipairs({ section:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(section, r) then
            local w, h = r:GetWidth() or 0, r:GetHeight() or 0
            -- (die Karte "Profession-overview-Card" bleibt: die Zeichnung des Berufs ist Teil derselben Grafik)
            if w <= BORDER_MAX or h <= BORDER_MAX then
                r:SetAlpha(0)
            else
                -- Blizzards Hintergrund des Berufs bleibt (die allgemeine Fenster-Umgestaltung hatte ihn schon
                -- ausgeblendet – darum wieder sichtbar machen)
                r:SetAlpha(1)
            end
        end
    end
    -- (früher hier zusätzlich ein feiner grauer Rand – mit der Karte auf Wunsch weg)
end

-- Lücke zwischen Titelleiste und den Berufen (Berufsübersicht) schließen: den Inhalt so weit nach oben, dass der
-- erste Beruf GAP_TOP unter der Fensteroberkante beginnt. Misst jedes Mal neu (verschiebt nur, wenn die Lücke größer
-- ist) – nur außerhalb des Kampfs (darin stecken geschützte Zauber-Knöpfe)
local GAP_TOP = 24 + 6
local function CloseTopGap(f)
    if InCombatLockdown() then return end
    -- (im Forever-Client tiefer: BookPage > ProfessionsContentFrame > PrimaryProfession1)
    local page = f.BookPage
    local list = type(page) == "table" and page.ProfessionsContentFrame
    local first = f.PrimaryProfession1 or (type(list) == "table" and list.PrimaryProfession1) or G("PrimaryProfession1")
    if not first or Forbidden(first) or not first:IsVisible() then return end
    local content = first:GetParent()
    if not content or content == f or Forbidden(content) or not (first:GetTop() and f:GetTop()) then return end
    -- gemessen an der sichtbaren Karte (sie beginnt tiefer als der Rahmen des Berufs), sonst am Rahmen
    local top = first:GetTop()
    for _, r in ipairs({ first:GetRegions() }) do
        local atlas = r:IsObjectType("Texture") and r.GetAtlas and r:GetAtlas()
        if type(atlas) == "string" and atlas:find("overview%-Card") and r:GetTop() then top = r:GetTop() end
    end
    local s = first:GetEffectiveScale() / f:GetEffectiveScale()
    local extra = (f:GetTop() - top * s) - GAP_TOP
    if extra <= 1 then return end
    local dy = extra / s
    local points = {}
    for i = 1, content:GetNumPoints() do
        local p, rel, rp, x, y = content:GetPoint(i)
        points[i] = { p, rel, rp, x or 0, (y or 0) + dy }
    end
    if #points == 0 then return end
    content:ClearAllPoints()
    for _, pt in ipairs(points) do content:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

-- Fortschrittsbalken: Rahmen weg, flacher dunkler Hintergrund; Füllung und Text bleiben
local barLooks = setmetatable({}, { __mode = "k" })
local headerFrame -- das Berufe-/Herstellungsfenster (für die Lage im Fenster)
local function SkinBar(bar)
    if not bar or Forbidden(bar) or boxes[bar] then return end
    boxes[bar] = true
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    for _, r in ipairs({ bar:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= fill then r:SetAlpha(0) end
    end
    for _, child in ipairs({ bar:GetChildren() }) do
        if not Forbidden(child) and not child:IsObjectType("Button") then ns.HideTextures(child) end
    end
    barLooks[bar] = ns.Flat(bar, C.input or C.button, -1)
end

-- Balken im Kopfbereich (Herstellungsfenster): ganz ohne Hintergrund, nur Füllung und Text – sonst lag er über der
-- goldenen Linie der Titelleiste
local function NoBarBackground(bar)
    local look = barLooks[bar]
    local f = headerFrame
    if not (look and f and f:GetTop() and bar:GetTop()) then return end
    local s = bar:GetEffectiveScale() / f:GetEffectiveScale()
    if f:GetTop() - bar:GetTop() * s > 70 then return end -- (nur oben im Fenster)
    look.fill:SetAlpha(0)
    for _, e in ipairs(look.edges or {}) do e:SetAlpha(0) end
    -- der Balken liegt teils in einem eigenen kleinen Rahmen mit Hintergrund: dessen Grafiken ebenfalls weg
    local holder = bar:GetParent()
    if holder and holder ~= f and not Forbidden(holder) and (holder:GetHeight() or 99) <= 50 then
        ns.HideTextures(holder)
        if holder.NineSlice then ns.Hide(holder.NineSlice) end
    end
end

-- Zauber-Symbol (geschützter Knopf – nur das Aussehen): wie ein Taschenplatz
local function SkinSpell(button)
    if not button or Forbidden(button) or boxes[button] then return end
    boxes[button] = true
    local name = button:GetName()
    local icon = button.iconTexture or button.icon or (name and (G(name .. "IconTexture") or G(name .. "Icon")))
    -- Nur Fach-Hintergrund und erkennbare Rahmen weg. Das Bild des Knopfs (bei manchen Knöpfen die "normale" Grafik,
    -- z. B. der herzustellende Gegenstand) bleibt immer – sonst verschwand es
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    for _, r in ipairs({ button:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= icon and r ~= normal then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r.GetTexture and r:GetTexture()
            local s = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
            if r:GetDrawLayer() == "BACKGROUND" or s:find("border") or s:find("frame") or s:find("slot")
                or s:find("ring") then
                r:SetAlpha(0)
            end
        end
    end
    local pushed = button.GetPushedTexture and button:GetPushedTexture()
    if pushed and pushed ~= icon then pushed:SetAlpha(0) end
    -- runde Maske eckig machen (z. B. "CircleMask" am herzustellenden Gegenstand): ihr Bild durch ein volles Quadrat
    -- ersetzen – wirkt auch, wenn Blizzard die Maske neu anbringt (nur lesen, welche Masken der Knopf hat)
    for _, v in pairs(button) do
        if type(v) == "table" and v.IsObjectType and v:IsObjectType("MaskTexture") then
            pcall(v.SetTexture, v, "Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
    end
    -- runde Maske entfernen: das Bild eckig wie in den übrigen Plätzen (rund im eckigen Kasten passte nicht)
    for _, t in ipairs({ icon or false, normal or false }) do
        if t and t.GetNumMaskTextures and t.GetMaskTexture and t.RemoveMaskTexture then
            for m = t:GetNumMaskTextures(), 1, -1 do
                local mask = t:GetMaskTexture(m)
                if mask then t:RemoveMaskTexture(mask) end
            end
        end
        if t and t.SetTexCoord then t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    end
    if icon and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    ns.Flat(button, { 0.06, 0.06, 0.08, 0.85 }, -1)
    ns.Hover(button)
end

local function SkinProfession(frame)
    if not frame or Forbidden(frame) then return end
    SkinSection(frame)
    local name = frame:GetName()
    SkinBar(frame.statusBar or frame.StatusBar or (name and G(name .. "StatusBar")))
    local unlearn = frame.UnlearnButton or frame.unlearn or (name and G(name .. "UnlearnButton"))
    if unlearn and not Forbidden(unlearn) then ns.SkinClose(unlearn) end
    for _, suffix in ipairs({ "SpellButtonTop", "SpellButtonBottom", "SpellButtonLeft", "SpellButtonRight" }) do
        SkinSpell(frame[suffix] or (name and G(name .. suffix)))
    end
    -- Symbol des Berufs (links neben dem Namen) wie ein Taschenplatz-Rand
    local icon = frame.icon
    if icon and icon.SetTexCoord then icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
end

-- WhatsTraining (Fremd-Addon, wird nie geändert) legt über das Herstellungsfenster eine eigene Seite
-- "WhatsTrainingCraftingPage" samt Titel, Porträt und einem Reiter. Hier nur Hilfen; Umgestaltung weiter unten (SkinWT).
local function WTPage() return G("WhatsTrainingCraftingPage") end
local function WTActive()
    local p = WTPage()
    return p and p:IsShown() or false
end
local function InsideWT(frame)
    local p = WTPage()
    local x = frame
    while x do
        if x == p then return true end
        x = x.GetParent and x:GetParent() or nil
    end
    return false
end

-- Text-Knöpfe ("Erstellen", "Alle erstellen" …) flach, mit eigenem Kasten dahinter (Blizzard setzt seine roten
-- Grafiken teils neu) – laufend unsichtbar gehalten
local textButtons = {}
local function SkinTextButton(b)
    if not b or Forbidden(b) or textButtons[b] then return end
    ns.SkinButton(b)
    local box = CreateFrame("Frame", nil, b:GetParent())
    box:SetAllPoints(b)
    box:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    ns.Flat(box, C.button)
    textButtons[b] = box
end
local function KeepButtonsFlat()
    for b, box in pairs(textButtons) do
        ns.HideTextures(b)
        for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(b[key]) end
        box:SetShown(b:IsVisible() and b:GetAlpha() > 0.01)
        local over = b:IsMouseOver() and b:IsEnabled()
        if box.over ~= over then
            box.over = over
            ns.EdgeColor(box, over and C.accent or C.border, 1)
        end
    end
end

-- Eingabefeld (Menge): Blizzards Rahmen weg, flache Fläche
local function SkinEdit(edit)
    if not edit or Forbidden(edit) or boxes[edit] then return end
    boxes[edit] = true
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(edit[key]) end
    ns.HideTextures(edit)
    ns.Flat(edit, C.input or C.button, { -4, 0, -2, 0 })
end

-- Fortschrittsbalken ganz oben (Herstellungsfenster): unter der goldenen Linie der Titelleiste lassen (er lag
-- darüber) – Oberkante mindestens HEADER_GAP unter der Linie; einmalig verschoben
local HEADER_LINE, HEADER_GAP = 24, 6
local headerShifted = setmetatable({}, { __mode = "k" })
local function KeepBelowHeader(bar)
    local f = headerFrame
    if not f or headerShifted[bar] or not bar:GetTop() or not f:GetTop() then return end
    local s = bar:GetEffectiveScale() / f:GetEffectiveScale()
    local below = f:GetTop() - bar:GetTop() * s -- Abstand der Balken-Oberkante zur Fenster-Oberkante
    if below > HEADER_LINE + HEADER_GAP or below < 0 then return end
    headerShifted[bar] = true
    local dy = (HEADER_LINE + HEADER_GAP - below) / s
    local points = {}
    for i = 1, bar:GetNumPoints() do
        local p, rel, rp, x, y = bar:GetPoint(i)
        points[i] = { p, rel, rp, x or 0, (y or 0) - dy }
    end
    bar:ClearAllPoints()
    for _, pt in ipairs(points) do bar:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

-- Blizzards Leiste hinter den Knöpfen unten ("Alle erstellen", Menge, "Erstellen"): breite, flache Grafik direkt am
-- unteren Rand – unsichtbar; dahinter liegt unsere Fußleiste (ns.ContentBox, feine goldene Linie)
local FOOTER = 30
local bottomControls = setmetatable({}, { __mode = "k" }) -- Bedienelemente der unteren Reihe (über unsere Leiste)

-- Eigene Ebenen ÜBER Blizzards Inhalt: die goldene Linie der Titelleiste (Blizzards Fortschrittsbalken lag darüber)
-- und die Fußleiste unten (Blizzards Leiste hinter den Knöpfen ließ sich nicht sicher ausblenden). Die Knöpfe der
-- unteren Reihe werden darüber gehoben, damit sie sichtbar und klickbar bleiben.
local overlay
local wtHidden = setmetatable({}, { __mode = "k" }) -- Bedienelemente, die wegen der WhatsTraining-Seite versteckt sind
local function Overlays(f)
    if not overlay then
        overlay = {}
        overlay.top = CreateFrame("Frame", nil, f)
        overlay.top:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -24)
        overlay.top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -24)
        ns.OnePixel(overlay.top, true)
        local line = overlay.top:CreateTexture(nil, "OVERLAY")
        line:SetAllPoints()
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        overlay.foot = CreateFrame("Frame", nil, f)
        overlay.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        overlay.foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        overlay.foot:SetHeight(FOOTER)
        overlay.foot:EnableMouse(false)
        local fill = overlay.foot:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
        -- (ohne goldene Trennlinie – auf Wunsch)
    end
    -- Ebenen: Linie oben über allem; Fußleiste über Blizzards Inhalt, die Bedienelemente der unteren Reihe darüber
    -- (angehobene Bedienelemente und ihre Kästen zählen nicht mit – sonst schaukelte sich die Ebene hoch)
    local skip = {}
    for b, box in pairs(textButtons) do skip[b], skip[box] = true, true end
    for c in pairs(bottomControls) do skip[c] = true end
    local highest = f:GetFrameLevel()
    local function Walk(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if not Forbidden(child) and child ~= overlay.top and child ~= overlay.foot and not skip[child] then
                highest = math.max(highest, child:GetFrameLevel())
                if depth < 3 then Walk(child, depth + 1) end
            end
        end
    end
    Walk(f, 1)
    overlay.top:SetFrameLevel(highest + 5)
    overlay.foot:SetFrameLevel(highest + 1)
    local fb = f:GetBottom()
    local controls = {}
    for b in pairs(textButtons) do controls[b] = true end
    for c in pairs(bottomControls) do controls[c] = true end
    -- Ist die Seite von WhatsTraining offen: die Knöpfe/Mengenfelder des Herstellens gehören nicht dazu – unsichtbar
    -- und ohne Maus (sonst liegen sie über dem Ende der Liste und schneiden deren Text ab)
    local wtOn = WTActive()
    for c in pairs(controls) do
        if not InsideWT(c) and not InCombatLockdown() then
            if wtOn and not wtHidden[c] then
                wtHidden[c] = true
                c:SetAlpha(0)
                pcall(c.EnableMouse, c, false)
            elseif not wtOn and wtHidden[c] then
                wtHidden[c] = nil
                c:SetAlpha(1)
                pcall(c.EnableMouse, c, true)
            end
        end
        if not wtOn and c:IsVisible() and fb and c:GetBottom() and (c:GetBottom() - fb) < FOOTER then
            if c:GetFrameLevel() <= highest + 1 then c:SetFrameLevel(highest + 3) end
            local box = textButtons[c]
            if box and box:GetFrameLevel() ~= c:GetFrameLevel() - 1 then box:SetFrameLevel(c:GetFrameLevel() - 1) end
        end
    end
    -- nur im Herstellungsfenster (dort gibt es die untere Reihe); im Berufsbuch keine Fußleiste. Breite: nur unter der
    -- Reihe der Knöpfe (vom linken Knopf bis zum rechten Rand) – links unter der Rezeptliste nichts
    local leftmost
    for c in pairs(controls) do
        if c:IsVisible() and fb and c:GetBottom() and (c:GetBottom() - fb) < FOOTER and c:GetLeft() then
            leftmost = math.min(leftmost or c:GetLeft(), c:GetLeft())
        end
    end
    overlay.foot:SetShown(leftmost ~= nil and not wtOn)
    if leftmost and f:GetLeft() then
        local x = math.floor(leftmost - f:GetLeft() - 6)
        if overlay.footX ~= x then
            overlay.footX = x
            overlay.foot:ClearAllPoints()
            overlay.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 1)
            overlay.foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            overlay.foot:SetHeight(FOOTER)
        end
    end
end
-- Text-Knöpfe der unteren Reihe ("Alle erstellen", "Erstellen") kleiner, Schrift gleich groß: Höhe 22, Breite nach
-- Text (nur außerhalb des Kampfs)
-- Blizzard setzt die Breite laufend neu (nach dem Text) – darum direkt nach jeder Größenänderung durch Blizzard die
-- eigene Größe setzen (Haken an SetWidth/SetHeight/SetSize, mit Sperre gegen Schleifen); sonst wackelten die Knöpfe
local BTN_HEIGHT, BTN_PAD, BTN_MIN = 22, 24, 70
local shrunk = setmetatable({}, { __mode = "k" })
local function ApplySmall(b)
    if shrunk[b] ~= true or InCombatLockdown() then return end
    local fs = b.GetFontString and b:GetFontString()
    local w = math.max(BTN_MIN, math.floor((fs and fs:GetStringWidth() or 0) + BTN_PAD + 0.5))
    if math.abs(b:GetWidth() - w) <= 0.5 and math.abs(b:GetHeight() - BTN_HEIGHT) <= 0.5 then return end
    shrunk[b] = "busy"
    pcall(b.SetSize, b, w, BTN_HEIGHT)
    shrunk[b] = true
end
local function ShrinkBottomButtons(f)
    if InCombatLockdown() or not f:GetBottom() then return end
    for b in pairs(textButtons) do
        if shrunk[b] == nil and b:IsVisible() and b:GetBottom() and (b:GetBottom() - f:GetBottom()) < FOOTER then
            shrunk[b] = true
            for _, method in ipairs({ "SetWidth", "SetHeight", "SetSize", "SetText" }) do
                hooksecurefunc(b, method, ApplySmall)
            end
            ApplySmall(b)
        end
    end
end

-- Lage der unteren Knöpfe feiner: alle NUDGE_UP höher, der linke ("Alle erstellen") NUDGE_RIGHT weiter rechts.
-- Blizzard setzt die Anker teils neu – dann gilt dessen Lage als neue Grundlage (nur außerhalb des Kampfs). Hängt ein
-- Knopf an einem anderen Bedienelement der Reihe, wandert er mit diesem schon nach oben (nicht doppelt)
local NUDGE_UP, NUDGE_RIGHT = 3, 8
local nudged = setmetatable({}, { __mode = "k" }) -- [Knopf] = { x, y } (von uns gesetzt)
local function NudgeBottomButtons(f)
    if InCombatLockdown() or not f:GetBottom() then return end
    local row, leftmost = {}, nil
    for b in pairs(textButtons) do
        if shrunk[b] and b:IsVisible() and b:GetLeft() then
            row[#row + 1] = b
            if not leftmost or b:GetLeft() < leftmost:GetLeft() then leftmost = b end
        end
    end
    for _, b in ipairs(row) do
        if b:GetNumPoints() == 1 then
            local p, rel, rp, x, y = b:GetPoint(1)
            local mine = nudged[b]
            if not (mine and math.abs(x - mine[1]) < 0.01 and math.abs(y - mine[2]) < 0.01) then
                local chained = rel and (textButtons[rel] or bottomControls[rel])
                local nx = x + (b == leftmost and NUDGE_RIGHT or 0)
                local ny = y + (chained and 0 or NUDGE_UP)
                nudged[b] = { nx, ny }
                b:SetPoint(p, rel, rp, nx, ny)
            end
        end
    end
end

local function HideBottomBar(frame)
    local f = headerFrame
    if not f or not f:GetBottom() then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(frame, r) and r:GetBottom() then
            local w, h = r:GetWidth() or 0, r:GetHeight() or 0
            if w > 250 and h >= 14 and h <= 44 and (r:GetBottom() - f:GetBottom()) < 12 then r:SetAlpha(0) end
        end
    end
end

-- Schlüssel eines Unter-Rahmens in seinem Eltern-Rahmen ("UnlearnButton", "SpellButtonTop" …) – nur lesen
local KeyOf = ns.KeyOf -- (gemeinsam in Core.lua)

local function HasStatusBar(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and child:IsObjectType("StatusBar") then return true end
    end
    return false
end

-- Im Forever-Client heißt das Fenster "ProfessionsFrame" und seine Teile tragen andere Namen als bei Blizzard –
-- darum allgemein nach Art und Rolle suchen: Fortschrittsbalken, "Verlernen"-Knöpfe, Zauber-Symbole, Berufs-Kästen
-- (großer Rahmen mit Fortschrittsbalken darin oder "Profession" im Namen)
-- Blizzards Hintergrundbild der Herstellungsseite ("Profession-Background-Template…", laut /fskin grafik in der
-- CraftingPage): enthält den dunklen Streifen oben hinter dem Fortschrittsbalken und die Leiste unten – unsichtbar,
-- darunter liegt unsere flache Fläche (die Zeichnung im Rezeptbereich ist eine eigene Grafik und bleibt)
local function HidePageBackground(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and r:GetAlpha() > 0 then
            local atlas = r.GetAtlas and r:GetAtlas()
            if type(atlas) == "string" and atlas:find("^Profession%-Background") then r:SetAlpha(0) end
        end
    end
end

local function Scan(frame, depth)
    HidePageBackground(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            local key = ((KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
            local w, h = child:GetWidth() or 0, child:GetHeight() or 0
            local isBar = (type(child.Track) == "table" and (child.Track.Thumb or child.Back))
                or (child:IsObjectType("Slider") and key:find("scroll"))
            local isDropdown = (child.IsObjectType and child:IsObjectType("DropdownButton"))
                or (type(child.Arrow) == "table" and type(child.Text) == "table" and not child:IsObjectType("CheckButton"))
            if isBar then
                -- Laufleiste (Liste der Rezepte, Beschreibung …): gold wie überall
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("StatusBar") then
                SkinBar(child)
                KeepBelowHeader(child)
                NoBarBackground(child)
            elseif child:IsObjectType("EditBox") then
                SkinEdit(child) -- (Menge beim Herstellen)
                bottomControls[child] = true
                -- die Pfeile der Menge stecken im Eingabefeld selbst
                for _, sub in ipairs({ child:GetChildren() }) do
                    if not Forbidden(sub) and sub:IsObjectType("Button") then
                        local subKey = ((KeyOf(child, sub) or "") .. "|" .. (sub:GetName() or "")):lower()
                        local left = subKey:find("decrement") or subKey:find("minus") or subKey:find("left")
                            or (sub:GetLeft() and child:GetLeft() and sub:GetLeft() < child:GetLeft() + 5)
                        ns.SkinArrowOnly(sub, left and "left" or "right") -- (nur der Pfeil, ohne Kasten)
                        bottomControls[sub] = true
                    end
                end
            elseif isDropdown then
                ns.SkinDropdown(child) -- ("Filter")
                if depth < 4 then Scan(child, depth + 1) end -- (darin z. B. das rote X "Filter zurücksetzen")
            elseif key:find("unlearn") or key:find("reset") then
                ns.SkinClose(child)
            elseif child:IsObjectType("Button") or child:IsObjectType("CheckButton") then
                local label = child.GetText and child:GetText()
                local hasIcon = child.iconTexture or child.icon or child.Icon
                if type(label) == "string" and label ~= "" and child ~= frame.CloseButton
                    and not child:IsObjectType("CheckButton") then
                    SkinTextButton(child) -- ("Erstellen", "Alle erstellen")
                elseif key:find("spell") or (hasIcon and w >= 28 and w <= 56 and h >= 28 and h <= 56) then
                    SkinSpell(child)
                elseif key:find("increment") or key:find("decrement") or key:find("plus") or key:find("minus") then
                    -- Pfeile neben der Menge (nur der Pfeil, ohne Kasten)
                    ns.SkinArrowOnly(child, (key:find("decrement") or key:find("minus")) and "left" or "right")
                    bottomControls[child] = true
                end
            else
                HideBottomBar(child)
                if w > 200 and h > 60 and (key:find("profession") or HasStatusBar(child)) then SkinSection(child) end
                if depth < 4 then Scan(child, depth + 1) end
            end
        end
    end
end

-- WhatsTraining im Herstellungsfenster in den Forever-Stil bringen (nur Aussehen, nichts im Addon ändern):
--  * Seite: braune Fläche und Blizzards Hintergrundgrafiken (auch die Deckflächen über den Fortschrittsbalken) →
--    flache Fenster-Farbe
--  * Titel und Porträt der Seite (kopieren Blizzards Kopfleiste samt Titeltext über unsere Titelleiste) → unsichtbar,
--    es gilt unsere Titelleiste
--  * Reiter ("WhatsTrainingCraftingTab" / "…ReturnTab"): flacher Kasten statt Blizzards Seitenreiter, goldener Rand
--    wenn die Seite offen ist
local wtDone = setmetatable({}, { __mode = "k" })
local wtBoxes = setmetatable({}, { __mode = "k" })

local function FlattenWTCanvas(frame, depth)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") and not wtDone[r] then
            local atlas = r.GetAtlas and r:GetAtlas()
            if type(atlas) == "string" and atlas:find("^Profession%-Background") then
                wtDone[r] = true
                r:SetAlpha(0)
            elseif not atlas and r:GetDrawLayer() == "BACKGROUND" and type(r:GetTexture()) ~= "string" then
                wtDone[r] = true
                r:SetColorTexture(C.background[1], C.background[2], C.background[3], 1)
            end
        end
    end
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            -- die Rezeptliste selbst bleibt unangetastet (hat "Refresh")
            if not Forbidden(child) and not child.Refresh then FlattenWTCanvas(child, depth - 1) end
        end
    end
end

local function HoldInvisible(frame)
    if not frame or wtDone[frame] then return end
    wtDone[frame] = true
    frame:SetAlpha(0)
    hooksecurefunc(frame, "SetAlpha", function(self, a)
        if a ~= 0 and not self.fsHolding then
            self.fsHolding = true
            self:SetAlpha(0)
            self.fsHolding = false
        end
    end)
end

local function SkinWTTab(tab)
    if not tab or Forbidden(tab) then return end
    local box = wtBoxes[tab]
    if not box then
        for _, key in ipairs({ "Background", "SelectedTexture", "TabGlow", "HighlightTexture" }) do ns.Hide(tab[key]) end
        if tab.Icon and tab.Icon.SetTexCoord then tab.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        box = CreateFrame("Frame", nil, tab:GetParent())
        box:SetAllPoints(tab)
        ns.Flat(box, C.button)
        wtBoxes[tab] = box
    end
    box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
    box:SetShown(tab:IsShown())
    local ok, checked = pcall(tab.GetChecked, tab)
    local on = (ok and checked) and true or false
    if box.on ~= on then
        box.on = on
        ns.EdgeColor(box, on and C.accent or C.border, 1)
    end
end

local function SkinWT(f)
    local page = WTPage()
    if not page or Forbidden(page) then return end
    if not wtDone[page] then
        wtDone[page] = true
        -- Seite öffnen/schließen sofort nachziehen (sonst bis zu 0,5 s Flackern der unteren Knöpfe)
        page:HookScript("OnShow", function() pcall(Overlays, f) end)
        page:HookScript("OnHide", function() pcall(Overlays, f) end)
    end
    FlattenWTCanvas(page, 3)
    HoldInvisible(G("WhatsTrainingCraftingTitle"))
    HoldInvisible(G("WhatsTrainingCraftingPortrait"))
    SkinWTTab(G("WhatsTrainingCraftingTab"))
    SkinWTTab(G("WhatsTrainingCraftingReturnTab"))
end

local function SkinBook()
    local f = G("ProfessionsBookFrame") or G("ProfessionsFrame")
    if not f or ns.professionsSkinned or Forbidden(f) then return end
    ns.professionsSkinned = true
    headerFrame = f
    ns.SkinWindow(f)
    -- (Fußleiste und goldene Linie oben als eigene Ebenen: siehe Overlays)
    Step("sections", function()
        for _, n in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2",
            "SecondaryProfession3", "SecondaryProfession4" }) do
            SkinProfession(f[n] or G(n))
        end
        Scan(f, 1)
    end)
    ns.Watch(f)
    -- Blizzard baut Teile beim Öffnen bzw. Lernen/Verlernen neu: dann nochmals (die Zeichnungen bleiben unberührt)
    f:HookScript("OnShow", function()
        C_Timer.After(0, function() Step("sections", function() Scan(f, 1) end) end)
    end)
    -- solange offen: Blizzards Knopf-Grafiken unsichtbar halten, aufgeklappte Auswahlliste flach, alle 0,5 s neu
    -- entstandene Teile suchen (die Rezept-Ansicht baut Blizzard erst beim Wechseln auf)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        pcall(KeepButtonsFlat)
        pcall(CloseTopGap, f) -- (jedes Bild: sonst rutschte der Inhalt erst Sekunden nach dem Öffnen hoch)
        pcall(NudgeBottomButtons, f)
        if ns.SkinOpenMenu then pcall(ns.SkinOpenMenu) end
        waited = waited + elapsed
        if waited >= 0.5 then
            waited = 0
            pcall(Scan, f, 1)
            pcall(SkinWT, f)
            pcall(Overlays, f)
            pcall(ShrinkBottomButtons, f)
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    -- (welches Blizzard-Paket das Fenster lädt, ist im Forever-Client anders – einfach nachsehen, ob es da ist)
    if ns.professionsSkinned or not ns.GetDB().professions then return end
    if not (G("ProfessionsBookFrame") or G("ProfessionsFrame")) then return end
    Step("skin", SkinBook)
end)
