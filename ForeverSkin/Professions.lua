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

local function SkinBook()
    local f = G("ProfessionsBookFrame")
    if not f or ns.professionsSkinned or Forbidden(f) then return end
    ns.professionsSkinned = true
    ns.SkinWindow(f)
    Step("sections", function()
        for _, n in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1", "SecondaryProfession2",
            "SecondaryProfession3", "SecondaryProfession4" }) do
            SkinProfession(f[n] or G(n))
        end
    end)
    ns.Watch(f)
    -- Blizzard setzt beim Lernen/Verlernen Teile neu: beim Öffnen nochmals (die Zeichnungen bleiben dabei unberührt)
    f:HookScript("OnShow", function()
        Step("sections", function()
            for _, n in ipairs({ "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
                "SecondaryProfession2", "SecondaryProfession3", "SecondaryProfession4" }) do
                local section = f[n] or G(n)
                if section then SkinSection(section) end
            end
        end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "Blizzard_ProfessionsBook" then return end
    if not ns.GetDB().professions or not G("ProfessionsBookFrame") then return end
    Step("skin", SkinBook)
end)
