-- ForeverFrames: Begleiter (Pet) als schmaler, senkrechter Balken neben dem Besitzer
-- Jeder Spieler-Button bekommt einen eigenen sicheren (klickbaren) Begleiter-Button als Kind.
-- Wechselt der Header die Einheit des Besitzers ("raid3"), stellt ein geschuetzter Code-Schnipsel
-- den Begleiter auf "raidpet3" um – das klappt auch im Kampf. Ein-/Ausblenden macht Blizzard
-- (RegisterUnitWatch), je nachdem ob ein Begleiter existiert.
local ADDON_NAME, ns = ...
local T, IsSecret, GetDB, Safe = ns.T, ns.IsSecret, ns.GetDB, ns.Safe

local WHITE = "Interface\\Buttons\\WHITE8x8"
ns.petButtons = {}
local petMap = {} -- Begleiter-Einheit ("pet", "partypet1", "raidpet3") -> Button

-- Laeuft im geschuetzten Bereich, wenn sich die Einheit des Besitzers aendert
local PET_SNIPPET = [[
    if name ~= "unit" then return end
    local pet = self:GetFrameRef("ffpet")
    if not pet then return end
    local petUnit
    if value == "player" then
        petUnit = "pet"
    elseif value then
        local kind, n = strmatch(value, "^(%a+)(%d+)$")
        if kind == "party" or kind == "raid" then petUnit = kind .. "pet" .. n end
    end
    pet:SetAttribute("unit", petUnit)
]]

local function PetUnitFor(unit)
    if unit == "player" then return "pet" end
    local kind, n = (unit or ""):match("^(%a+)(%d+)$")
    if kind == "party" or kind == "raid" then return kind .. "pet" .. n end
end

-- Hat irgendwer in der Gruppe einen Begleiter? Nur dann wird neben den Spielern Platz
-- freigehalten (Blizzards Gruppen-Rahmen kann den Abstand nur fuer alle gleich setzen).
local anyPet = false
local function GroupHasPet()
    if (ns.testCount or 0) > 0 then
        -- Testmodus: Jaeger und Hexenmeister haben einen Beispiel-Begleiter
        for i = 1, ns.testCount do
            local b = ns.fakeButtons and ns.fakeButtons[i]
            local d = b and b.ffFake
            if d and (d.class == "HUNTER" or d.class == "WARLOCK") then return true end
        end
        return false
    end
    if UnitExists("pet") then return true end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if UnitExists("raidpet" .. i) then return true end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            if UnitExists("partypet" .. i) then return true end
        end
    end
    return false
end

-- neu pruefen; aendert sich etwas, Rahmen neu anordnen (im Kampf erst danach)
function ns.UpdatePetSpace()
    local now = GetDB().petShow and GroupHasPet() or false
    if now ~= anyPet then
        anyPet = now
        if ns.ApplyLayout then ns.ApplyLayout() end
    end
end

-- Zusaetzlicher Platz neben jedem Spieler, wenn der Begleiter aussen sitzt (nur wenn es Pets gibt)
function ns.PetExtra()
    local db = GetDB()
    if not db.petShow or db.petPosition == "INSIDE" or not anyPet then return 0 end
    return db.petWidth + db.petGap
end

function ns.PetLeftShift()
    local db = GetDB()
    if db.petShow and db.petPosition == "LEFT" and anyPet then return db.petWidth + db.petGap end
    return 0
end

---------------------------------------------------------------------------
-- Sichtbarer Teil (fuer echte und Test-Begleiter)
---------------------------------------------------------------------------
local function CreatePetVisuals(p)
    local v = {}
    p.ff = v
    v.content = CreateFrame("Frame", nil, p, "BackdropTemplate")
    v.content:SetAllPoints(p)
    v.health = CreateFrame("StatusBar", nil, v.content)
    v.health:SetOrientation("VERTICAL") -- fuellt von unten: fehlende LP verschwinden oben
    v.health:SetMinMaxValues(0, 1)
    v.health:SetValue(1)
    v.healthBg = v.health:CreateTexture(nil, "BACKGROUND")
    v.healthBg:SetAllPoints(v.health)
    -- senkrechte Beschriftung (Buchstaben untereinander)
    v.textLayer = CreateFrame("Frame", nil, v.content)
    v.textLayer:SetAllPoints(v.content)
    v.textLayer:SetFrameLevel(v.health:GetFrameLevel() + 1)
    v.label = v.textLayer:CreateFontString(nil, "OVERLAY")
    v.label:SetFont("Fonts\\ARIALN.TTF", 8, "OUTLINE")
    v.label:SetPoint("CENTER")
    v.label:SetJustifyH("CENTER")
    v.label:SetSpacing(0)
    -- Aufhellen beim Ueberfahren: auf der obersten Ebene, sonst verdeckt der Lebensbalken es
    v.hover = v.textLayer:CreateTexture(nil, "ARTWORK")
    v.hover:SetAllPoints(v.health)
    v.hover:SetColorTexture(1, 1, 1, 0.15)
    v.hover:Hide()
    v.targetBorder = CreateFrame("Frame", nil, v.content, "BackdropTemplate")
    v.targetBorder:SetAllPoints(v.content)
    v.targetBorder:SetFrameLevel(v.health:GetFrameLevel() + 2)
    v.targetBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    v.targetBorder:Hide()
    -- Aggro-Rand wie bei den Spielern: aussen um den Rahmen, ueber allem
    v.aggroBorder = CreateFrame("Frame", nil, v.content, "BackdropTemplate")
    v.aggroBorder:SetPoint("TOPLEFT", v.content, "TOPLEFT", -1, 1)
    v.aggroBorder:SetPoint("BOTTOMRIGHT", v.content, "BOTTOMRIGHT", 1, -1)
    v.aggroBorder:SetFrameLevel(v.health:GetFrameLevel() + 3)
    v.aggroBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    v.aggroBorder:Hide()
    return v
end

local function ApplyPetLook(p)
    local v, db = p.ff, GetDB()
    local bs = db.borderSize
    local tex = ns.TexturePath()
    v.content:SetBackdrop({ bgFile = WHITE })
    v.content:SetBackdropColor(ns.Color("borderColor"))
    v.health:ClearAllPoints()
    v.health:SetPoint("TOPLEFT", bs, -bs)
    v.health:SetPoint("BOTTOMRIGHT", -bs, bs)
    v.health:SetStatusBarTexture(tex)
    v.health:SetRotatesTexture(true)
    v.health:SetReverseFill(db.petReverse) -- umgekehrt: fuellt von oben, fehlende LP verschwinden unten
    v.healthBg:SetTexture(tex)
    v.targetBorder:SetBackdropBorderColor(ns.Color("targetColor"))
    v.aggroBorder:SetBackdropBorderColor(ns.Color("aggroColor"))
    v.label:SetFont(ns.FontPath(), db.petLabelSize, "OUTLINE")
    v.label:SetShown(db.petLabel ~= "none")
end

-- "Wolf" -> "W\no\nl\nf" (UTF-8-sicher), gekuerzt auf die Hoehe des Rahmens
local function VerticalText(text)
    local db = GetDB()
    local maxChars = math.max(1, math.floor((db.height - 2) / (db.petLabelSize + 1)))
    local chars = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #chars >= maxChars then break end
        chars[#chars + 1] = ch
    end
    return table.concat(chars, "\n")
end

local function SetPetLabel(v, name)
    local mode = GetDB().petLabel
    if mode == "none" then v.label:SetText("") return end
    if mode == "name" and not IsSecret(name) and name and name ~= "" then
        v.label:SetText(VerticalText(name))
    else
        v.label:SetText(VerticalText("Pet"))
    end
end

local function PetColor(ownerUnit, ownerClass)
    local db = GetDB()
    if db.petColorMode == "owner" then
        if ownerUnit then return ns.ClassColor(ownerUnit) end
        return ns.ClassColorByFile(ownerClass)
    end
    return ns.Color("petColor")
end

local function SetPetColors(v, r, g, b, dead)
    if dead then
        v.health:SetStatusBarColor(0.4, 0.4, 0.4)
        v.healthBg:SetVertexColor(0.15, 0.15, 0.15)
        return
    end
    v.health:SetStatusBarColor(r, g, b)
    v.healthBg:SetVertexColor(r * 0.22, g * 0.22, b * 0.22)
end

-- Position neben dem Besitzer (Besitzer = Elternrahmen)
local function PlacePet(p)
    local db, owner = GetDB(), p:GetParent()
    p:ClearAllPoints()
    if db.petPosition == "LEFT" then
        p:SetPoint("TOPRIGHT", owner, "TOPLEFT", -db.petGap, 0)
        p:SetPoint("BOTTOMRIGHT", owner, "BOTTOMLEFT", -db.petGap, 0)
    elseif db.petPosition == "INSIDE" then
        p:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
        p:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
    else
        p:SetPoint("TOPLEFT", owner, "TOPRIGHT", db.petGap, 0)
        p:SetPoint("BOTTOMLEFT", owner, "BOTTOMRIGHT", db.petGap, 0)
    end
    p:SetWidth(db.petWidth)
    p:SetFrameLevel(owner:GetFrameLevel() + 12)
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------
local function UpdatePetHealth(p)
    local v, unit = p.ff, p.ffUnit
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if IsSecret(cur, max) then
        v.health:SetMinMaxValues(0, max)
        v.health:SetValue(cur)
    else
        v.health:SetMinMaxValues(0, (max and max > 0) and max or 1)
        v.health:SetValue(cur or 0)
    end
end

local function UpdatePetTarget(p)
    local v = p.ff
    if not GetDB().targetHighlight then v.targetBorder:Hide() return end
    local isTarget = UnitIsUnit(p.ffUnit, "target")
    v.targetBorder:SetShown(not IsSecret(isTarget) and isTarget)
end

-- Aggro: der Begleiter wird angegriffen bzw. hat die Bedrohung (Stufe 2 oder 3)
local function UpdatePetThreat(p)
    local v = p.ff
    if not GetDB().aggroBorder then v.aggroBorder:Hide() return end
    local status = UnitThreatSituation(p.ffUnit)
    v.aggroBorder:SetShown(not IsSecret(status) and status ~= nil and status >= 2)
end

local function UpdatePetRange(p)
    local v, db = p.ff, GetDB()
    if not db.rangeFade then v.content:SetAlpha(1) return end
    local inRange, checked = UnitInRange(p.ffUnit)
    if IsSecret(inRange) or IsSecret(checked) then
        if v.content.SetAlphaFromBoolean then v.content:SetAlphaFromBoolean(inRange, 1, db.rangeAlpha) end
    elseif checked then
        v.content:SetAlpha(inRange and 1 or db.rangeAlpha)
    else
        v.content:SetAlpha(1)
    end
end

local function UpdatePet(p)
    local unit = p.ffUnit
    if not unit or not UnitExists(unit) then return end
    local ownerUnit = p:GetParent().ffUnit
    local r, g, b = PetColor(ownerUnit)
    local dead = UnitIsDeadOrGhost(unit)
    SetPetColors(p.ff, r, g, b, not IsSecret(dead) and dead)
    SetPetLabel(p.ff, (UnitName(unit)))
    UpdatePetHealth(p)
    UpdatePetTarget(p)
    UpdatePetThreat(p)
    UpdatePetRange(p)
end
ns.UpdatePet = UpdatePet

---------------------------------------------------------------------------
-- Einrichtung (ausserhalb des Kampfs, beim Anlegen des Besitzer-Buttons)
---------------------------------------------------------------------------
local function OnPetAttribute(self, name, value)
    if name ~= "unit" then return end
    if self.ffUnit and petMap[self.ffUnit] == self then petMap[self.ffUnit] = nil end
    self.ffUnit = value
    if value then petMap[value] = self end
    local ok, err = pcall(UpdatePet, self)
    if not ok then ns.ReportError(T("Begleiter", "Pet"), err) end
end

local function OnPetEnter(self)
    local db = GetDB()
    if db.mouseoverHighlight then self.ff.hover:Show() end
    if db.tooltip and self.ffUnit then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.ffUnit)
        GameTooltip:Show()
    end
end

local function OnPetLeave(self)
    self.ff.hover:Hide()
    GameTooltip:Hide()
end

function ns.SetupPet(owner)
    if owner.ffPet or InCombatLockdown() then return end
    local p = CreateFrame("Button", owner:GetName() .. "Pet", owner, "SecureUnitButtonTemplate")
    owner.ffPet = p
    p:RegisterForClicks("AnyUp", "AnyDown")
    CreatePetVisuals(p)
    ApplyPetLook(p)
    PlacePet(p)
    p:HookScript("OnAttributeChanged", OnPetAttribute)
    p:HookScript("OnShow", Safe(T("Begleiter", "Pet"), UpdatePet))
    p:HookScript("OnEnter", OnPetEnter)
    p:HookScript("OnLeave", OnPetLeave)

    -- Besitzer kennt seinen Begleiter; der Schnipsel stellt dessen Einheit um
    if owner.SetFrameRef then
        owner:SetFrameRef("ffpet", p)
        owner:SetAttribute("_onattributechanged", PET_SNIPPET)
    end
    p:SetAttribute("unit", PetUnitFor(owner:GetAttribute("unit")))
    tinsert(ns.petButtons, p)
    if ns.ApplyClicksToButton then ns.ApplyClicksToButton(p) end
    ns.UpdatePetVisibility(p)
end

-- Ein/aus: Blizzard zeigt den Button nur, wenn der Begleiter existiert
function ns.UpdatePetVisibility(p)
    ns.OutOfCombat("begleiter-" .. p:GetName(), function()
        if GetDB().petShow then
            RegisterUnitWatch(p)
        else
            UnregisterUnitWatch(p)
            p:Hide()
        end
    end)
end

-- Aussehen und Position aller Begleiter neu setzen (Position nur ausserhalb des Kampfs)
function ns.LayoutPets()
    for _, p in ipairs(ns.petButtons) do
        ApplyPetLook(p)
        if p.ffUnit then UpdatePet(p) end
    end
    ns.OutOfCombat("begleiter-layout", function()
        for _, p in ipairs(ns.petButtons) do
            PlacePet(p)
            ns.UpdatePetVisibility(p)
        end
    end)
end

---------------------------------------------------------------------------
-- Testmodus: Jaeger und Hexenmeister bekommen einen Beispiel-Begleiter
---------------------------------------------------------------------------
function ns.UpdateFakePet(b)
    local d, db = b.ffFake, GetDB()
    if not b.ffPet then
        local p = CreateFrame("Frame", nil, b)
        CreatePetVisuals(p)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self) if GetDB().mouseoverHighlight then self.ff.hover:Show() end end)
        p:SetScript("OnLeave", function(self) self.ff.hover:Hide() end)
        b.ffPet = p
    end
    local p = b.ffPet
    local hasPet = d.class == "HUNTER" or d.class == "WARLOCK"
    if not (db.petShow and hasPet) then p:Hide() return end
    ApplyPetLook(p)
    PlacePet(p)
    local r, g, bl = PetColor(nil, d.class)
    SetPetColors(p.ff, r, g, bl, false)
    SetPetLabel(p.ff, d.class == "HUNTER" and T("Wolf", "Wolf") or T("Wichtel", "Imp"))
    p.ff.health:SetMinMaxValues(0, 100)
    p.ff.health:SetValue(((b.ffIndex or 1) * 37) % 70 + 30)
    p.ff.content:SetAlpha(1)
    -- Testmodus: jeder dritte Beispiel-Begleiter hat Aggro
    p.ff.aggroBorder:SetShown(db.aggroBorder and (b.ffIndex or 1) % 3 == 1)
    p:Show()
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local function ForPet(fn)
    return function(unit)
        local p = unit and petMap[unit]
        if p and p:IsVisible() then fn(p) end
    end
end

local function ForEachPet(fn)
    for _, p in ipairs(ns.petButtons) do
        if p.ffUnit and p:IsVisible() then fn(p) end
    end
end

ns.On("UNIT_HEALTH", T("Begleiter", "Pet"), ForPet(function(p)
    UpdatePetHealth(p)
    local r, g, b = PetColor(p:GetParent().ffUnit)
    local dead = UnitIsDeadOrGhost(p.ffUnit)
    SetPetColors(p.ff, r, g, b, not IsSecret(dead) and dead)
end))
ns.On("UNIT_THREAT_SITUATION_UPDATE", T("Begleiter-Aggro", "Pet aggro"), ForPet(UpdatePetThreat))
ns.On("UNIT_MAXHEALTH", T("Begleiter", "Pet"), ForPet(UpdatePetHealth))
ns.On("UNIT_NAME_UPDATE", T("Begleiter", "Pet"), ForPet(function(p) SetPetLabel(p.ff, (UnitName(p.ffUnit))) end))
ns.On("UNIT_PET", T("Begleiter", "Pet"), function()
    C_Timer.After(0.1, Safe(T("Begleiter", "Pet"), function()
        ForEachPet(UpdatePet)
        ns.UpdatePetSpace()
    end))
end)
ns.On("GROUP_ROSTER_UPDATE", T("Begleiter", "Pet"), function()
    C_Timer.After(0.2, Safe(T("Begleiter", "Pet"), ns.UpdatePetSpace))
end)
-- nach Ladebildschirm und Kampfende nachziehen (z. B. Begleiter waehrend eines Ladebildschirms beschworen),
-- dazu alle 5 s zur Sicherheit (vorher jede Sekunde)
local function PetSpaceSoon()
    C_Timer.After(0.2, Safe(T("Begleiter", "Pet"), function()
        if not InCombatLockdown() then ns.UpdatePetSpace() end
    end))
end
ns.On("PLAYER_ENTERING_WORLD", T("Begleiter", "Pet"), PetSpaceSoon)
ns.On("PLAYER_REGEN_ENABLED", T("Begleiter", "Pet"), PetSpaceSoon)
if ns.SetTestMode then hooksecurefunc(ns, "SetTestMode", PetSpaceSoon) end -- Testmodus (Frames.lua)
C_Timer.NewTicker(5, Safe(T("Begleiter", "Pet"), function()
    if not InCombatLockdown() then ns.UpdatePetSpace() end
end))
ns.On("PLAYER_TARGET_CHANGED", T("Begleiter", "Pet"), function() ForEachPet(UpdatePetTarget) end)

C_Timer.NewTicker(0.25, Safe(T("Begleiter-Reichweite", "Pet range"), function() ForEachPet(UpdatePetRange) end))
