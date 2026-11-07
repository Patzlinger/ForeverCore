-- ForeverSkin – ClickBinding.lua: Klickbelegung (ClickBindingFrame – Zauber/Makros auf Mausklicks über Einheitenfenster)
-- samt "Info zur Klickbelegung" im Forever-Stil (docs/Fenster-Stil.md): flache Fläche, Titelleiste mit goldener Linie,
-- unser Schließen-Kreuz, Liste als flacher Kasten, Einträge als flache Felder, rote Knöpfe unten flach, Haken flach,
-- Laufleiste gold. Zauber-Symbole sowie die runden Knöpfe "Zauberbuch"/"Makros" oben rechts bleiben Blizzards; im
-- Info-Fenster bleibt das Erklärbild. Blizzard lädt das Fenster erst beim ersten Öffnen (Blizzard_ClickBindingUI).
local _, ns = ...
local C = ns.C

local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

local done = setmetatable({}, { __mode = "k" })

local function FlatButton(b)
    if not b or done[b] or Forbidden(b) then return end
    done[b] = true
    ns.SkinButton(b)
    for _, key in ipairs({ "Left", "Middle", "Right", "Center" }) do ns.Hide(b[key]) end
    ns.HideTextures(b)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if b[get] then ns.Hide(b[get](b)) end
    end
end

-- Eintrag der Liste: Blizzards Hintergrund weg, flaches Feld; Symbol und Texte bleiben
local function SkinLine(line)
    if done[line] or Forbidden(line) then return end
    done[line] = true
    for _, key in ipairs({ "Background", "BackgroundTexture", "Bg" }) do
        local t = line[key]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
    end
    ns.Flat(line, C.input, 1)
end

-- Unter-Rahmen ohne Knopf-Funktion mit Blizzard-Rahmen (Kasten um die Liste): Rahmen weg, flacher Kasten
local function SkinBoxes(f)
    for _, child in ipairs({ f:GetChildren() }) do
        if not Forbidden(child) and not child:IsObjectType("Button") and type(child.NineSlice) == "table" then
            ns.Hide(child.NineSlice)
            ns.HideTextures(child)
            if not done[child] then
                done[child] = true
                ns.Flat(child, C.input)
            end
        end
    end
end

local function SkinTutorial(tut)
    if not tut or done[tut] or Forbidden(tut) then return end
    done[tut] = true
    ns.noGold[tut] = true
    ns.SkinWindow(tut, nil, true) -- (nur Rahmen, Titel-Hintergrund, Porträt – das Erklärbild bleibt)
    ns.Watch(tut)
end

local skinned
local function SkinClickBinding()
    local f = _G.ClickBindingFrame
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    SkinBoxes(f)
    for _, key in ipairs({ "ResetButton", "AddBindingButton", "SaveButton" }) do FlatButton(f[key]) end
    -- übrige Text-Knöpfe (falls Forever andere Namen nutzt)
    for _, child in ipairs({ f:GetChildren() }) do
        if child:IsObjectType("Button") and not child:IsObjectType("CheckButton") and not Forbidden(child)
            and child.GetText and (child:GetText() or "") ~= "" and (child:GetWidth() or 0) >= 60 then
            FlatButton(child)
        elseif child:IsObjectType("CheckButton") and not done[child] then
            done[child] = true
            ns.SkinCheck(child)
        end
    end
    local check = f.EnableMouseoverCastCheckbox
    if check and not done[check] then done[check] = true ns.SkinCheck(check) end
    if f.MouseoverCastKeyDropdown and ns.SkinDropdown then pcall(ns.SkinDropdown, f.MouseoverCastKeyDropdown) end
    if f.ScrollBar then ns.SkinScrollBar(f.ScrollBar) end
    ns.Watch(f)
    -- Einträge baut Blizzard beim Öffnen/Ändern neu; das Info-Fenster erscheint beim ersten Mal bzw. über "?"
    local function Refresh()
        if f.ScrollBox and f.ScrollBox.ForEachFrame then pcall(f.ScrollBox.ForEachFrame, f.ScrollBox, SkinLine) end
        if f.TutorialFrame then pcall(SkinTutorial, f.TutorialFrame) end
    end
    Refresh()
    local last = 0
    local watch = CreateFrame("Frame", nil, f)
    watch:SetScript("OnUpdate", function(_, elapsed)
        last = last + elapsed
        if last < ns.Tick(0.1) then return end
        last = 0
        Refresh()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self)
    if not ns.GetDB().clickbinding then return end
    if _G.ClickBindingFrame and not skinned then
        local ok, err = pcall(SkinClickBinding)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "clickbinding", err) end
    end
    if skinned then self:UnregisterAllEvents() end
end)
