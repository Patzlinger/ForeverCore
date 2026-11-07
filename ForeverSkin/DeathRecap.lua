-- ForeverSkin – DeathRecap.lua: Todesursache (DeathRecapFrame – wer hat dich womit getroffen) im Forever-Stil
-- (docs/Fenster-Stil.md): flache Fläche, Titelleiste mit goldener Linie und Titel, unser Schließen-Kreuz statt des
-- roten X, "Schließen" unten flach, Laufleiste gold; die Zauber-Symbole mit feinem Rand statt Blizzards goldenem.
-- Schadenszahlen, Namen und der Grabstein bleiben. Blizzard lädt das Fenster erst beim ersten Tod (Blizzard_DeathRecap).
local _, ns = ...
local C = ns.C

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

local function FlatButton(b)
    if done[b] then return end
    done[b] = true
    ns.SkinButton(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

-- Eintrag (Zauber mit Symbol): Blizzards goldener Rahmen ums Symbol weg, feiner Rand dahinter
local function SkinEntry(entry)
    if done[entry] or Forbidden(entry) then return end
    done[entry] = true
    local info = entry.SpellInfo or entry
    local icon = info.Icon or info.icon
    if type(info.IconBorder) == "table" then info.IconBorder:SetAlpha(0) end
    if type(icon) == "table" and icon.GetParent then
        local holder = CreateFrame("Frame", nil, info)
        holder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        holder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        holder:SetFrameLevel(math.max(0, info:GetFrameLevel() - 1))
        ns.Flat(holder, C.input)
    end
end

local function Scan(frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                if not done[child] then done[child] = true ns.SkinScrollBar(child) end
            elseif type(child.SpellInfo) == "table" then
                SkinEntry(child)
            elseif child:IsObjectType("Button") and child.GetText and (child:GetText() or "") ~= ""
                and (child:GetWidth() or 0) >= 60 then
                FlatButton(child)
            elseif depth < 5 and not child:IsObjectType("Button") then
                Scan(child, depth + 1)
            end
        end
    end
end

local skinned
local function SkinDeathRecap()
    local f = _G.DeathRecapFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    for _, key in ipairs({ "Border", "Background", "BG", "Divider" }) do
        local part = f[key]
        if type(part) == "table" then
            if part.IsObjectType and part:IsObjectType("Texture") then part:SetAlpha(0)
            else ns.HideTextures(part) if type(part.NineSlice) == "table" then ns.Hide(part.NineSlice) end end
        end
    end
    pcall(Scan, f, 1)
    ns.Watch(f)
    -- Einträge kommen beim Öffnen bzw. Blättern dazu
    f:HookScript("OnShow", function(self)
        pcall(Scan, self, 1)
        C_Timer.After(0, function() pcall(Scan, self, 1) end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().deathrecap then return end
    if _G.DeathRecapFrame and not skinned then
        local ok, err = pcall(SkinDeathRecap)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "deathrecap", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
