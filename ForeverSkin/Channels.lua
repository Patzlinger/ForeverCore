-- ForeverSkin – Channels.lua: Fenster "Chat-Channels" (ChannelFrame) im Forever-Stil (docs/Fenster-Stil.md).
-- Fenster flach (Porträt, Rahmen und rote Knöpfe weg, ohne "Dein Gold"), die beiden Listen als flache Kästen,
-- Laufleisten gold; Überschriften der Liste ("Gruppe", "Welt", "Benutzerdefiniert") und die Knöpfe unten
-- ("Hinzufügen", "Optionen") flach. Die Einträge (Channels, Namen) bleiben samt Markierung des gewählten Channels.
-- Blizzard lädt das Fenster erst beim ersten Öffnen und legt die Einträge beim Blättern neu an – darum im Takt.
local _, ns = ...

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local function Step(what, fn)
    local ok, err = pcall(fn)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "channels/" .. what, err) end
end

-- Überschrift der Liste: Knopf mit Text und Blizzards abgerundeter Leiste (Left/Middle/Right oder "header"-Grafik)
local function IsHeader(entry)
    if type(entry.Left) == "table" or type(entry.Middle) == "table" then return true end
    for _, r in ipairs({ entry:GetRegions() }) do
        if r:IsObjectType("Texture") then
            local atlas = r.GetAtlas and r:GetAtlas()
            local tex = r:GetTexture()
            local s = ((type(atlas) == "string" and atlas or "") .. "|" .. (type(tex) == "string" and tex or "")):lower()
            -- (im Forever-Client: "voicechat-channellist-category-background")
            if s:find("header") or s:find("category") then return true end
        end
    end
    return false
end

-- Einträge der Listen: alle gleich breit (so breit wie die Liste, rechts ENTRY_RIGHT Abstand zur Laufleiste) und mit
-- ENTRY_GAP Luft dazwischen – der flache Balken wird dafür an der Liste statt am Eintrag ausgerichtet
local ENTRY_RIGHT, ENTRY_GAP = 6, 1
local function EvenEntry(entry, target)
    local look = ns.Flat(entry, ns.C.button)
    if not look or not look.fill then return end
    look.fill:ClearAllPoints()
    look.fill:SetPoint("TOP", entry, "TOP", 0, -ENTRY_GAP)
    look.fill:SetPoint("BOTTOM", entry, "BOTTOM", 0, ENTRY_GAP)
    look.fill:SetPoint("LEFT", target, "LEFT", 2, 0)
    look.fill:SetPoint("RIGHT", target, "RIGHT", -ENTRY_RIGHT, 0)
end

-- Knöpfe unten ("Hinzufügen", "Optionen"): BUTTON_IN nach innen, BUTTON_UP höher – einmal
local BUTTON_IN, BUTTON_UP, LIST_ABOVE = 6, 4, 8
local bottomButtons = setmetatable({}, { __mode = "k" })
local function NudgeButton(f, b)
    if bottomButtons[b] or b:GetNumPoints() ~= 1 or not (b:GetCenter() and f:GetCenter()) then return end
    bottomButtons[b] = true
    local p, rel, rp, x, y = b:GetPoint(1)
    local inward = b:GetCenter() < f:GetCenter() and BUTTON_IN or -BUTTON_IN
    b:SetPoint(p, rel, rp, (x or 0) + inward, (y or 0) + BUTTON_UP)
end

-- Listen (Innenflächen) enden LIST_ABOVE über den Knöpfen unten: untere Ankerpunkte hoch (gemessen, nur wenn nötig)
local function KeepAboveButtons(frame)
    local top
    for b in pairs(bottomButtons) do
        if b:IsShown() and b:GetTop() then top = math.max(top or 0, b:GetTop()) end
    end
    if not top or not frame:GetBottom() then return end
    local delta = top + LIST_ABOVE - frame:GetBottom()
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

-- Blizzard zeichnet die abgerundeten Leisten der Überschriften beim Aktualisieren neu (lagen dann über unserem
-- Balken, ungleich breit): bei jedem Durchgang wieder weg – nur breite Grafiken, das kleine +/− bleibt
local function HideBars(entry)
    for _, r in ipairs({ entry:GetRegions() }) do
        if r:IsObjectType("Texture") and not ns.IsMine(entry, r) and (r:GetWidth() or 0) >= 30 then r:SetAlpha(0) end
    end
    for _, key in ipairs({ "Left", "Middle", "Right" }) do ns.Hide(entry[key]) end
end

local done = setmetatable({}, { __mode = "k" })
local headers = setmetatable({}, { __mode = "k" }) -- bekannte Überschriften: Leisten in jedem Bild weg (kein Aufblitzen)
local function Scan(f, frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            -- Listen und Laufleisten enden über den Knöpfen unten (die Namensliste hängt direkt am Fenster, nicht an
            -- der Innenfläche – darum hier für jede einzeln)
            local isScrollFrame = child:IsObjectType("ScrollFrame") and child:GetScrollChild() ~= nil
            if (child.GetScrollTarget or isScrollFrame or type(child.Track) == "table") and child:IsVisible() then
                pcall(KeepAboveButtons, child)
            end
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                if not done[child] then
                    done[child] = true
                    ns.SkinScrollBar(child)
                    -- kein Kasten hinter der Laufleiste: ihre eigenen Hintergrund-Grafiken weg (Schiene/Schieber bleiben)
                    ns.HideTextures(child)
                    for _, key in ipairs({ "Background", "NineSlice", "Bg" }) do ns.Hide(child[key]) end
                end
            elseif child.GetScrollTarget or isScrollFrame then
                -- (moderne Liste: ScrollTarget; ältere wie die Channel-Liste: ScrollFrame mit "Child")
                local target = child.GetScrollTarget and child:GetScrollTarget() or child:GetScrollChild()
                for _, entry in ipairs(target and { target:GetChildren() } or {}) do
                    if not Forbidden(entry) and entry:IsObjectType("Button") then
                        if not done[entry] then
                            done[entry] = true
                            ns.SkinButton(entry) -- (Überschriften, Channels, Namen – je ein flacher Balken)
                            EvenEntry(entry, target)
                        end
                        -- (nur Überschriften – bei den Channels ist eine breite Grafik die Markierung des gewählten)
                        if IsHeader(entry) then
                            headers[entry] = true
                            HideBars(entry)
                        end
                    end
                end
            elseif child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                if not done[child] and type(text) == "string" and text ~= "" then
                    done[child] = true
                    ns.SkinButton(child) -- ("Hinzufügen", "Optionen")
                end
                -- Knöpfe unten am Fenster: etwas nach innen und höher
                if frame == f and child:GetBottom() and f:GetBottom() and child:GetBottom() - f:GetBottom() < 30 then
                    NudgeButton(f, child)
                end
            elseif depth < 4 then
                Scan(f, child, depth + 1)
            end
        end
    end
end

local function SkinChannels()
    local f = G("ChannelFrame")
    if not f or ns.channelsSkinned or Forbidden(f) then return end
    ns.channelsSkinned = true
    ns.SkinWindow(f)
    for _, key in ipairs({ "LeftInset", "RightInset", "Inset" }) do
        if type(f[key]) == "table" and not Forbidden(f[key]) then ns.SkinInset(f[key]) end
    end
    Step("scan", function() Scan(f, f, 1) end)
    ns.Watch(f)
    local watch = CreateFrame("Frame", nil, f)
    local waited = 0
    watch:SetScript("OnUpdate", function(_, elapsed)
        -- jedes Bild: Leisten der Überschriften weg (Blizzard zeichnet sie beim Umschalten neu – sonst kurz sichtbar)
        for h in pairs(headers) do
            if h:IsVisible() then pcall(HideBars, h) end
        end
        waited = waited + elapsed
        if waited < ns.Tick(0.1) then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(Scan, f, f, 1)
        for _, key in ipairs({ "LeftInset", "RightInset", "Inset" }) do
            if type(f[key]) == "table" and not Forbidden(f[key]) then pcall(KeepAboveButtons, f[key]) end
        end
    end)
end

-- "Neuer Channel" (CreateChannelPopup): flache Titelleiste mit dem Titel mittig, Eingabefelder und Knöpfe flach
local function SkinCreatePopup()
    local p = G("CreateChannelPopup")
    if not p or ns.createChannelSkinned or Forbidden(p) then return end
    ns.createChannelSkinned = true
    if p.ClearBackdrop then pcall(p.ClearBackdrop, p) end
    for _, key in ipairs({ "Border", "BG", "Bg" }) do
        local obj = p[key]
        if type(obj) == "table" and obj.GetRegions and not Forbidden(obj) then ns.HideTextures(obj) end
        ns.Hide(obj)
    end
    ns.SkinWindow(p)
    local header = p.Header
    if type(header) == "table" and not Forbidden(header) then
        ns.HideTextures(header)
        local title = header.Text
        if title and title.ClearAllPoints then
            title:SetParent(p)
            title:ClearAllPoints()
            title:SetPoint("CENTER", p, "TOP", 0, -12)
            title:SetDrawLayer("OVERLAY", 7)
        end
    end
    for _, child in ipairs({ p:GetChildren() }) do
        if not Forbidden(child) then
            if child:IsObjectType("EditBox") then
                for _, k in ipairs({ "Left", "Middle", "Right", "Mid" }) do ns.Hide(child[k]) end
                ns.HideTextures(child)
                ns.Flat(child, ns.C.input, { -4, 0, -2, 0 })
            elseif child:IsObjectType("Button") and child ~= p.CloseButton then
                local text = child.GetText and child:GetText()
                if type(text) == "string" and text ~= "" then ns.SkinButton(child) end
            end
        end
    end
    ns.SkinClose(p.CloseButton)
    ns.Watch(p)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if not ns.GetDB().chatConfig then return end
    if not ns.channelsSkinned and G("ChannelFrame") then Step("skin", SkinChannels) end
    if not ns.createChannelSkinned and G("CreateChannelPopup") then Step("create", SkinCreatePopup) end
end)
