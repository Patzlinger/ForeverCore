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
            if w <= BORDER_MAX or h <= BORDER_MAX then r:SetAlpha(0) end
        end
    end
    if not boxes[section] then
        boxes[section] = true
        local look = ns.Flat(section, { 0, 0, 0, 0 })
        if look then ns.EdgeColor(section, C.border, 1) end
    end
end

-- Fortschrittsbalken: Rahmen weg, flacher dunkler Hintergrund; Füllung und Text bleiben
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
    ns.Flat(bar, C.input or C.button, -1)
end

-- Zauber-Symbol (geschützter Knopf – nur das Aussehen): wie ein Taschenplatz
local function SkinSpell(button)
    if not button or Forbidden(button) or boxes[button] then return end
    boxes[button] = true
    local name = button:GetName()
    local icon = button.iconTexture or button.icon or (name and (G(name .. "IconTexture") or G(name .. "Icon")))
    for _, r in ipairs({ button:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= icon then
            local w = r:GetWidth() or 0
            -- (Rahmen und Fach-Hintergrund des Knopfs; Texte/Glanz anderer Größe bleiben)
            if w >= (button:GetWidth() or 0) - 2 or r:GetDrawLayer() == "BACKGROUND" then r:SetAlpha(0) end
        end
    end
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
        local t = button[get] and button[get](button)
        if t and t ~= icon then t:SetAlpha(0) end
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

-- Schlüssel eines Unter-Rahmens in seinem Eltern-Rahmen ("UnlearnButton", "SpellButtonTop" …) – nur lesen
local function KeyOf(parent, child)
    for k, v in pairs(parent) do
        if v == child and type(k) == "string" then return k end
    end
end

local function HasStatusBar(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) and child:IsObjectType("StatusBar") then return true end
    end
    return false
end

-- Im Forever-Client heißt das Fenster "ProfessionsFrame" und seine Teile tragen andere Namen als bei Blizzard –
-- darum allgemein nach Art und Rolle suchen: Fortschrittsbalken, "Verlernen"-Knöpfe, Zauber-Symbole, Berufs-Kästen
-- (großer Rahmen mit Fortschrittsbalken darin oder "Profession" im Namen)
local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            local key = ((KeyOf(frame, child) or "") .. "|" .. (child:GetName() or "")):lower()
            local w, h = child:GetWidth() or 0, child:GetHeight() or 0
            if child:IsObjectType("StatusBar") then
                SkinBar(child)
            elseif key:find("unlearn") then
                ns.SkinClose(child)
            elseif child:IsObjectType("Button") or child:IsObjectType("CheckButton") then
                local hasIcon = child.iconTexture or child.icon or child.Icon
                if key:find("spell") or (hasIcon and w >= 28 and w <= 56 and h >= 28 and h <= 56) then SkinSpell(child) end
            else
                if w > 200 and h > 60 and (key:find("profession") or HasStatusBar(child)) then SkinSection(child) end
                if depth < 4 then Scan(child, depth + 1) end
            end
        end
    end
end

local function SkinBook()
    local f = G("ProfessionsBookFrame") or G("ProfessionsFrame")
    if not f or ns.professionsSkinned or Forbidden(f) then return end
    ns.professionsSkinned = true
    ns.SkinWindow(f)
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
