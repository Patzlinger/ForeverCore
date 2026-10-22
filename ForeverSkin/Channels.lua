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
            if s:find("header") then return true end
        end
    end
    return false
end

local done = setmetatable({}, { __mode = "k" })
local function Scan(f, frame, depth)
    for _, child in ipairs({ frame:GetChildren() }) do
        if not Forbidden(child) then
            if type(child.Track) == "table" and (child.Track.Thumb or child.Back) then
                if not done[child] then
                    done[child] = true
                    ns.SkinScrollBar(child)
                end
            elseif child.GetScrollTarget then
                local target = child:GetScrollTarget()
                for _, entry in ipairs(target and { target:GetChildren() } or {}) do
                    if not done[entry] and not Forbidden(entry) and entry:IsObjectType("Button") and IsHeader(entry) then
                        done[entry] = true
                        ns.SkinButton(entry) -- (Überschrift als flacher Balken; das +/− bleibt)
                    end
                end
            elseif child:IsObjectType("Button") then
                local text = child.GetText and child:GetText()
                if not done[child] and type(text) == "string" and text ~= "" then
                    done[child] = true
                    ns.SkinButton(child) -- ("Hinzufügen", "Optionen")
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
        waited = waited + elapsed
        if waited < 0.3 then return end
        waited = 0
        for _, key in ipairs({ "NineSlice", "PortraitContainer" }) do
            if type(f[key]) == "table" then ns.Hide(f[key]) end
        end
        pcall(Scan, f, f, 1)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function()
    if ns.channelsSkinned or not ns.GetDB().chatConfig or not G("ChannelFrame") then return end
    Step("skin", SkinChannels)
end)
