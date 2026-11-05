-- ForeverSkin – Books.lua: Buch-/Brieftexte (ItemTextFrame – Bücher, Briefe, Tafeln, Schilder) im Forever-Stil
-- (docs/Fenster-Stil.md): flache Fläche, Titelleiste mit goldener Linie, unser Schließen-Kreuz; statt Pergament ein
-- flacher Kasten hinter dem Text, der Text hell (Überschriften gold), Seitenzahl hell, Blättern als feine Pfeile,
-- Laufleiste gold. Blizzard färbt den Text je nach "Material" (Pergament, Stein, Bronze …) dunkel – nach jedem
-- Laden einer Seite wieder hell. Namen aus Retail und Classic; was fehlt, wird übersprungen.
local _, ns = ...
local C = ns.C

local WHITE = "Interface\\Buttons\\WHITE8x8"
local TEXT = { 0.9, 0.9, 0.9 }

local function G(name) return _G[name] end
local function Forbidden(obj) return obj and obj.IsForbidden and obj:IsForbidden() end

-- Pergament und Material-Bilder (oben/unten, links/rechts) unsichtbar
local MATERIAL = { "ItemTextMaterialTopLeft", "ItemTextMaterialTopRight", "ItemTextMaterialBotLeft",
    "ItemTextMaterialBotRight", "ItemTextFrameBg", "ItemTextFramePageBg" }

local function Recolor()
    local html = G("ItemTextPageText")
    if html and html.SetTextColor then
        -- SimpleHTML: Farbe je Textart (Absatz, Überschriften)
        pcall(html.SetTextColor, html, "P", TEXT[1], TEXT[2], TEXT[3])
        for _, h in ipairs({ "H1", "H2", "H3" }) do pcall(html.SetTextColor, html, h, C.accent[1], C.accent[2], C.accent[3]) end
    end
    local page = G("ItemTextCurrentPage")
    if page and page.SetTextColor then page:SetTextColor(0.85, 0.85, 0.85) end
    for _, n in ipairs(MATERIAL) do ns.Hide(G(n)) end
end

local skinned
local function SkinBooks()
    local f = G("ItemTextFrame")
    if not f or skinned or Forbidden(f) then return end
    skinned = true
    ns.noGold[f] = true
    ns.SkinWindow(f)
    for _, n in ipairs(MATERIAL) do ns.Hide(G(n)) end
    -- (Blizzards Innenfläche macht ns.SkinWindow schon zu unserem flachen Kasten – kein zweiter Kasten dahinter)
    local inset = f.Inset or G("ItemTextFrameInset")
    local scroll = G("ItemTextScrollFrame") or f.ScrollFrame
    if not inset and scroll then
        -- ohne Innenfläche: ein eigener Kasten um den Laufbereich
        local box = CreateFrame("Frame", nil, f)
        box:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
        box:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 26, -6)
        box:SetFrameLevel(math.max(0, scroll:GetFrameLevel() - 1))
        ns.Flat(box, C.panel)
    end
    if scroll then
        ns.HideTextures(scroll)
        local bar = scroll.ScrollBar or G("ItemTextScrollFrameScrollBar")
        if bar then ns.SkinScrollBar(bar) end
    end
    -- Blättern: feine Pfeile (die Beschriftung "Weiter"/"Zurück" daneben bleibt)
    local prev, nextB = G("ItemTextPrevPageButton"), G("ItemTextNextPageButton")
    if prev then ns.SkinArrowOnly(prev, "left") end
    if nextB then ns.SkinArrowOnly(nextB, "right") end
    ns.Watch(f)
    f:HookScript("OnShow", function() C_Timer.After(0, function() pcall(Recolor) end) end)
    Recolor()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ITEM_TEXT_BEGIN")
events:RegisterEvent("ITEM_TEXT_READY")
events:SetScript("OnEvent", function(_, event)
    if not ns.GetDB().books then return end
    if not skinned and G("ItemTextFrame") then
        local ok, err = pcall(SkinBooks)
        if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "books", err) end
    end
    -- Blizzard färbt jede neue Seite nach ihrem Material: danach wieder hell
    if skinned and (event == "ITEM_TEXT_READY" or event == "ITEM_TEXT_BEGIN") then
        C_Timer.After(0, function() pcall(Recolor) end)
    end
end)
