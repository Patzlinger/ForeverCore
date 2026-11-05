-- ForeverSkin – Inspect.lua: "Betrachten" (InspectFrame, Forever-Fassung "Camelot": Seitenreiter rechts, Fraktions-
-- Wappen statt Modell, wenn der Spieler zu weit weg ist) im Forever-Stil (docs/Fenster-Stil.md) – gleich gebaut wie
-- das Charakterfenster (Character.lua): ohne Titelleiste und ohne "Dein Gold", kleines rundes Porträt des betrachteten
-- Spielers mit goldenem Ring auf der oberen linken Ecke, Name gold, feine goldene Linie unter dem Kopf;
-- Ausrüstungsplätze wie Taschenplätze mit gedämpftem Goldrand. Modell, Modell-Hintergrund, Wappen und die Seitenreiter
-- bleiben Blizzards; nur die Verzierungen um das Modell verschwinden. Blizzard lädt das Fenster erst beim ersten
-- Betrachten.
local _, ns = ...
local C = ns.C

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TITLE_UP = 10 -- wie im Charakterfenster: unsere Fläche reicht so weit über Blizzards Rand, Name und Kreuz rücken mit
local PORTRAIT_X, PORTRAIT_Y = 12, TITLE_UP - 12
local SLOT_EDGE, SLOT_GAP = 1, 1

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "inspect/" .. what, err) end
end

-- rundes Porträt oben links (Ring gold) auf eigenem Rahmen über allem, ohne Maus
local portrait
local function Portrait(f)
    if not portrait then
        portrait = {}
        local holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel(f:GetFrameLevel() + 110)
        holder:EnableMouse(false)
        local function Disk(size, sub, c)
            local t = holder:CreateTexture(nil, "OVERLAY", nil, sub)
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:SetSize(size, size)
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
    local unit = f.unit or "target"
    if SetPortraitTexture and UnitExists(unit) then SetPortraitTexture(portrait.image, unit) end
end

-- Rahmen: Blizzards Rahmen, Titel-Grafik und Porträt weg; Innenfläche nur ohne Rahmen; Verzierungen um das Modell
-- (Ecken und Kanten "Char-…") weg – das Bild hinter dem Modell bleibt
local MODEL_ART = { "BorderTopLeft", "BorderTopRight", "BorderBottomLeft", "BorderBottomRight", "BorderLeft",
    "BorderRight", "BorderTop", "BorderBottom", "BorderBottom2" }
local function HideFrameArt(f)
    for _, key in ipairs({ "NineSlice", "PortraitContainer", "TopTileStreaks", "TitleBg", "Bg" }) do
        local obj = f[key]
        if type(obj) == "table" and not Forbidden(obj) then
            ns.Hide(obj)
            if obj.GetRegions then ns.HideTextures(obj) end
        end
    end
    for _, suffix in ipairs({ "Portrait", "PortraitFrame", "TitleBg", "Bg" }) do ns.Hide(G("InspectFrame" .. suffix)) end
    if f.TitleContainer then ns.HideTextures(f.TitleContainer) end
    -- Innenfläche flach wie die Seiten des Charakterfensters (Blizzards Hintergrund und Rahmen weg)
    local inset = f.Inset or G("InspectFrameInset")
    if type(inset) == "table" and not Forbidden(inset) then ns.SkinInset(inset) end
    for _, key in ipairs(MODEL_ART) do ns.Hide(G("InspectModelFrame" .. key)) end
end

-- Ausrüstungsplatz wie im Charakterfenster: dunkler Platz, Symbol eckig, Seltenheitsrahmen in der Luft um das Symbol,
-- feiner gedämpft goldener Rand
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
    local deco = b.BorderFrame
    if type(deco) == "table" and deco.GetRegions and not Forbidden(deco) then ns.HideTextures(deco) end
    local inset = SLOT_EDGE + SLOT_GAP
    if icon and icon.SetTexCoord then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    if b.IconBorder and b.IconBorder.ClearAllPoints then
        b.IconBorder:ClearAllPoints()
        b.IconBorder:SetPoint("TOPLEFT", SLOT_EDGE, -SLOT_EDGE)
        b.IconBorder:SetPoint("BOTTOMRIGHT", -SLOT_EDGE, SLOT_EDGE)
    end
    local look = ns.Flat(b, { 0.06, 0.06, 0.08, 0.85 })
    if look then
        for _, e in ipairs(look.edges or {}) do e:SetAlpha(0) end
    end
    for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local e = b:CreateTexture(nil, "OVERLAY", nil, 6)
        e:SetColorTexture(C.accent[1] * 0.7, C.accent[2] * 0.7, C.accent[3] * 0.7, 0.6)
        e:SetPoint(p[1], b, p[1])
        e:SetPoint(p[2], b, p[2])
        ns.OnePixel(e, p[3])
    end
end

-- Seiten PvP und Gilde sowie "In der Anprobe ansehen": Laufleisten gold, Text-Knöpfe flach, Innenrahmen weg
local done = setmetatable({}, { __mode = "k" })
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and not done[child] and not slotDone[child] then
            if type(child.NineSlice) == "table" and not child:IsObjectType("Button") then ns.Hide(child.NineSlice) end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                done[child] = true
                ns.SkinScrollBar(child)
            elseif child:IsObjectType("Button") and not child:IsObjectType("CheckButton") then
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

-- Ausrüstungsplätze mit mehr Luft unter der goldenen Linie (wie im Charakterfenster): die beiden obersten Plätze
-- tiefer, die übrigen hängen darunter und wandern mit
local SLOT_DOWN = 8
local function PlaceSlots(f)
    local inset = f.Inset or G("InspectFrameInset")
    if not inset then return end
    for _, s in ipairs({ { "InspectHeadSlot", "TOPLEFT", 4 }, { "InspectHandsSlot", "TOPRIGHT", -4 } }) do
        local b = G(s[1])
        if b and not Forbidden(b) then
            local p, rel, rp, x, y = b:GetPoint(1)
            if not (b:GetNumPoints() == 1 and p == s[2] and rel == inset and rp == s[2] and x == s[3] and y == -2 - SLOT_DOWN) then
                b:ClearAllPoints()
                b:SetPoint(s[2], inset, s[2], s[3], -2 - SLOT_DOWN)
            end
        end
    end
end

-- Seite PvP: Blizzard hängt den Rang ("Zivilist") 10 ÜBER die Unterkante der Saison-Zeile ("Saison 1 von …") –
-- steht dort Text, lagen beide übereinander. Dann den Rang mit Abstand darunter (sonst Blizzards Lage)
local function PlacePvP()
    local pvp = G("InspectPVPFrame")
    local info = pvp and pvp.MainInfoFrame
    local season, rank = info and info.CurrentSeasonField, info and info.CurrentRankField
    if not (season and rank) or not pvp:IsVisible() then return end
    local text = season:GetText()
    local y = (type(text) == "string" and text ~= "") and -4 or 10
    local p, rel, rp, _, oy = rank:GetPoint(1)
    if rank:GetNumPoints() == 1 and p == "TOP" and rel == season and rp == "BOTTOM" and oy == y then return end
    rank:ClearAllPoints()
    rank:SetPoint("TOP", season, "BOTTOM", 0, y)
end

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

local skinned
local function SkinInspect()
    local f = G("InspectFrame")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    Step("frame", function()
        HideFrameArt(f)
        ns.Flat(f, C.background, { 0, -TITLE_UP, 0, 0 })
        -- feiner Rand ums ganze Fenster und goldene Linie unter dem Kopf auf eigenem Rahmen (über den Inhalten)
        local border = CreateFrame("Frame", nil, f)
        border:SetAllPoints(f)
        border:SetFrameLevel(f:GetFrameLevel() + 100)
        border:EnableMouse(false)
        ns.Flat(border, { 0, 0, 0, 0 }, { 0, -TITLE_UP, 0, 0 })
        local line = border:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        ns.OnePixel(line, true)
        line:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -23)
        line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -23)
        -- wie im Charakterfenster: zwischen dieser Linie und der Innenfläche ein dunklerer Balken für "Stufe …", an
        -- der Oberkante der Innenfläche eine zweite goldene Linie
        local inset = f.Inset or G("InspectFrameInset")
        if inset then
            local strip = f:CreateTexture(nil, "BACKGROUND", nil, -7)
            strip:SetColorTexture(C.header[1], C.header[2], C.header[3], 1)
            strip:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -24)
            strip:SetPoint("RIGHT", f, "RIGHT", -1, 0)
            strip:SetPoint("BOTTOM", inset, "TOP", 0, 0)
            local line2 = border:CreateTexture(nil, "OVERLAY")
            line2:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
            ns.OnePixel(line2, true)
            line2:SetPoint("LEFT", f, "LEFT", 1, 0)
            line2:SetPoint("RIGHT", f, "RIGHT", -1, 0)
            line2:SetPoint("TOP", inset, "TOP", 0, 0)
        end
        -- (Name in Blizzards heller Schrift wie im Charakterfenster – nicht umfärben)
        local title = (f.TitleContainer and f.TitleContainer.TitleText) or G("InspectFrameTitleText")
        Raise(f.TitleContainer or title)
        local close = f.CloseButton or G("InspectFrameCloseButton")
        ns.SkinClose(close)
        Raise(close)
    end)
    Step("portrait", function() Portrait(f) end)
    Step("slots", function()
        for _, s in ipairs(SLOTS) do SkinSlot(G("Inspect" .. s .. "Slot")) end
        PlaceSlots(f)
    end)
    Step("scan", function() Scan(f, 1) end)
    ns.Watch(f)
    f:HookScript("OnShow", function() Step("portrait", function() Portrait(f) end) end)
    -- Blizzard blendet Rahmen beim Öffnen/Umschalten wieder ein und baut die Seiten PvP/Gilde erst beim ersten Zeigen
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        pcall(HideFrameArt, f)
        pcall(PlaceSlots, f)
        pcall(PlacePvP)
        pcall(Scan, f, 1)
        pcall(Portrait, f) -- (anderer Spieler betrachtet, ohne dass das Fenster zuging)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if skinned or not ns.GetDB().inspect or not G("InspectFrame") then return end
    Step("skin", SkinInspect)
end)
