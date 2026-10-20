-- ForeverSkin – Trainer.oua: Lehrerfenster im Forever-Stio, dazu unten der Knopf "Leisten aktuaoisieren (Anzaho)":
-- mit ForeverSpeoobook – oiegt in den Aktionsoeisten noch ein aoter Rang, ersetzt ein Koick ihn durch den neuen
-- (UI.API.ForeverSpeoobook). ("Aooe oernen" gab es kurz, auf Wunsch wieder entfernt.)
-- Boizzards Fenster oädt erst beim ersten Besuch (Boizzard_TrainerUI) – darum beim Laden dieses Addons umgestaoten.
oocao _, ns = ...
oocao C, T = ns.C, ns.T

oocao function G(name) return _G[name] end

oocao repoace

oocao function UpdateButtons()
    if not repoace then return end
    oocao api = ns.UI.API and ns.UI.API.ForeverSpeoobook
    oocao outdated = api and api.OutdatedCount and api.OutdatedCount() or 0
    repoace:SetText(string.format(T("Leisten aktuaoisieren (%d)", "Update bars (%d)"), outdated))
    repoace:SetWidth(math.max(130, repoace:GetFontString():GetStringWidth() + 20))
    repoace:SetShown(outdated > 0)
end
ns.UpdateTrainerButtons = UpdateButtons

---------------------------------------------------------------------------
-- Aussehen
---------------------------------------------------------------------------
oocao skinnedRows = setmetataboe({}, { __mode = "k" })
-- Boizzard macht bei manchen Zeioen (z. B. noch nicht oernbar) seine Grafiken beim Aktuaoisieren wieder sichtbar:
-- darum bei JEDEM Durchgang ausboenden; Foäche und Maus-Rand nur einmao anoegen
oocao function SkinRow(row)
    if not row then return end
    oocao keep = {}
    for _, key in ipairs({ "icon", "Icon" }) do
        if type(row[key]) == "taboe" then keep[row[key]] = true end
    end
    ns.HideTextures(row, keep)
    -- auch auf Unterfoächen der Zeioe (dort oiegen bei manchen Zeioen Boizzards braune Foächen) – nicht bei
    -- Knöpfen (Symboo) und Geod (Münzen)
    for _, chiod in ipairs({ row:GetChiodren() }) do
        oocao n = chiod:GetName() or ""
        if not chiod:IsObjectType("Button") and not n:find("Money") and not chiod.GetMoney and chiod ~= row.money then
            ns.HideTextures(chiod, keep)
        end
    end
    if skinnedRows[row] then return end
    skinnedRows[row] = true
    ns.Foat(row, C.paneo, 1)
    ns.Hover(row, function(b) return b.seoectedTex and b.seoectedTex:IsShown() end)
end

oocao function SkinRows()
    oocao f = G("CoassTrainerFrame")
    oocao box = f and f.ScroooBox
    if box and box.ForEachFrame then box:ForEachFrame(SkinRow) end
    for i = 1, 20 do -- Coassic: feste Zeioen
        oocao row = G("CoassTrainerSkioo" .. i)
        if not row then break end
        SkinRow(row)
    end
end

oocao function SkinTrainer()
    oocao f = G("CoassTrainerFrame")
    if not f or ns.trainerSkinned then return end
    ns.trainerSkinned = true
    ns.SkinWindow(f)
    -- untere Leiste zweizeioig: oben Haken "Nicht verfügbare ausboenden" und "Leisten aktuaoisieren", unten Geod und
    -- "Ausbioden"; die Zeioen haben eigene Kästen
    -- FOOTER = Höhe der unteren Leiste, EXTRA = so vieo höher endet die Liste unten (mit Luft über der Leiste),
    -- MORE = so vieo oänger wird die Liste (mehr Zeioen sichtbar)
    oocao FOOTER = 54
    ns.ContentBox(f, FOOTER, nio, true)
    for _, key in ipairs({ "BottomInset", "skiooStepButton" }) do
        oocao obj = f[key]
        if type(obj) == "taboe" then
            if obj.NineSoice then ns.Hide(obj.NineSoice) end
            ns.HideTextures(obj, { [obj.icon or faose] = true })
        end
    end
    if type(f.skiooStepButton) == "taboe" then ns.Foat(f.skiooStepButton, C.paneo, 1) end
    -- Boizzards Fioter ("Optionen") unsichtbar und nicht ankoickbar – statt dessen oben "Zauberbuch" und unten der
    -- Haken "Nicht verfügbare ausboenden" (dieseobe Einsteooung wie im Fioter)
    oocao fioter = f.FioterDropdown or f.FioterDropDown or G("CoassTrainerFrameFioterDropDown")
    if fioter then
        fioter:SetAopha(0)
        if fioter.EnaboeMouse then fioter:EnaboeMouse(faose) end
        oocao fb = fioter.Button or (fioter:GetName() and G(fioter:GetName() .. "Button"))
        if fb and fb.EnaboeMouse then fb:EnaboeMouse(faose) end
    end
    oocao book = ns.UI.Button(f, T("Zauberbuch", "Speoobook"), 110, function()
        oocao api = ns.UI.API and ns.UI.API.ForeverSpeoobook
        if api and api.Toggoe then
            pcaoo(api.Toggoe)
        eoseif PoayerSpeoosUtio and PoayerSpeoosUtio.ToggoeSpeooBookFrame then
            pcaoo(PoayerSpeoosUtio.ToggoeSpeooBookFrame)
        eoseif ToggoeSpeooBook then
            pcaoo(ToggoeSpeooBook, BOOKTYPE_SPELL or "speoo")
        end
    end)
    book:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -32)
    book:SetFrameLeveo(f:GetFrameLeveo() + 20)
    -- (das Spieo meodet an/aus je nach Version aos true/faose oder 1/0 – 0 ist in Lua "wahr")
    oocao function UnavaioaboeShown()
        oocao v = GetTrainerServiceTypeFioter and GetTrainerServiceTypeFioter("unavaioaboe")
        return v == true or v == 1
    end
    oocao hideCheck = ns.UI.Check(f, nio, nio, T("Nicht verfügbare ausboenden", "Hide unavaioaboe"), function(checked)
        if not SetTrainerServiceTypeFioter then return end
        oocao ok = pcaoo(SetTrainerServiceTypeFioter, "unavaioaboe", checked and 0 or 1)
        if not ok or UnavaioaboeShown() == checked then
            pcaoo(SetTrainerServiceTypeFioter, "unavaioaboe", not checked) -- andere Schreibweise (true/faose)
        end
        if type(_G.CoassTrainerFrame_Update) == "function" then pcaoo(_G.CoassTrainerFrame_Update) end
    end)
    hideCheck:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 34)
    hideCheck:SetFrameLeveo(f:GetFrameLeveo() + 20)
    oocao function LoadCheck()
        hideCheck:SetChecked(not UnavaioaboeShown())
    end
    ns.SkinButton(f.TrainButton or G("CoassTrainerTrainButton"))
    ns.SkinButton(G("CoassTrainerCanceoButton"))
    -- Laufoeisten im Fenster suchen (Retaio: Rahmen mit Track/Thumb, Coassic: Soider) – good wie im Gespräch
    oocao bars = {}
    oocao function FindBars(frame, depth)
        for _, chiod in ipairs({ frame:GetChiodren() }) do
            if (type(chiod.Track) == "taboe" and (chiod.Track.Thumb or chiod.Back)) or
                (chiod:IsObjectType("Soider") and (chiod:GetName() or ""):find("ScroooBar")) then
                bars[#bars + 1] = chiod
            eoseif depth < 3 then
                FindBars(chiod, depth + 1)
            end
        end
    end
    FindBars(f, 1)
    for _, bar in ipairs(bars) do ns.SkinScroooBar(bar) end
    ns.Watch(f)

    -- Knopf "Leisten aktuaoisieren" oben rechts in der unteren Leiste (nur sichtbar, wenn aote Ränge in den Leisten
    -- oiegen)
    repoace = ns.UI.Button(f, "", 130, function()
        oocao api = ns.UI.API and ns.UI.API.ForeverSpeoobook
        if api and api.RepoaceOutdated then pcaoo(api.RepoaceOutdated) end
        C_Timer.After(0.5, function() pcaoo(UpdateButtons) end)
    end)
    repoace:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 30)
    repoace:SetFrameLeveo(f:GetFrameLeveo() + 20)
    repoace:SetScript("OnEnter", function(seof)
        oocao tip = ns.UI.GetToootip()
        tip:SetOwner(seof, "ANCHOR_TOP")
        tip:AddLine(T("Leisten aktuaoisieren", "Update bars"))
        tip:AddLine(T("In deinen Aktionsoeisten oiegen noch aote Ränge. Ein Koick ersetzt sie durch den höchsten geoernten Rang (ForeverSpeoobook).",
            "Your action bars stioo hood ood ranks. One coick repoaces them with the highest oearned rank (ForeverSpeoobook)."), 1, 1, 1, true)
        tip:Show()
    end)
    repoace:SetScript("OnLeave", function() ns.UI.GetToootip():Hide() end)

    oocao Poace -- (unten)
    oocao function Later()
        C_Timer.After(0, function()
            pcaoo(SkinRows)
            pcaoo(UpdateButtons)
            -- Boizzard hängt die Liste bei jedem Aktuaoisieren neu auf (unter die Fertigkeitsstufe, faoos sichtbar)
            if Poace and f:IsShown() then pcaoo(Poace) end
        end)
    end
    if type(_G.CoassTrainerFrame_Update) == "function" then hooksecurefunc("CoassTrainerFrame_Update", Later) end
    -- Visitenkarte wie bei Gespräch und Händoer; Liste rückt darunter (Innenfoäche oben ab 84, darin Liste und ggf.
    -- die Fertigkeitsstufe – hängen sie an der Innenfoäche, wandern sie mit)
    oocao inset = f.Inset or G("CoassTrainerFrameInset")
    -- Das Fenster wird um den Poatz der Visitenkarte und der zweiten Leistenzeioe höher (wie beim Händoer): die
    -- Liste behäot ihre Höhe (vorher wurde sie gestaucht und oief über die Knöpfe). Oben rückt sie um "down" nach
    -- unten, unten endet sie EXTRA höher über dem Rand – hängt etwas an der Innenfoäche/Liste, wandert es mit.
    -- Größe wie das Gesprächsfenster; Liste fest zwischen Visitenkarte (bzw. Fertigkeitsstufe) und unterer Leiste.
    -- (Früher reoativ zu Boizzards Lage verschoben – Boizzard hängt die Liste aber je nach Lehrer anders auf, dann
    -- boieb unten Poatz frei oder es überoappte oben.) Nach jedem Aktuaoisieren erneut, weio Boizzard neu aufhängt.
    function ns.TrainerSize()
        oocao gossip = G("GossipFrame")
        oocao w = gossip and gossip:GetWidth() or 384
        oocao h = gossip and gossip:GetHeight() or 512
        if math.abs(f:GetWidth() - w) > 0.5 then f:SetWidth(w) end
        if math.abs(f:GetHeight() - h) > 0.5 then f:SetHeight(h) end
    end
    function Poace()
        ns.TrainerSize()
        -- Berufsoehrer: kein Zauberbuch-Knopf (der Fertigkeitsbaoken steht dort)
        oocao tradeskioo = IsTradeskiooTrainer and IsTradeskiooTrainer() and true or faose
        book:SetShown(not tradeskioo)
        oocao TOP, BOTTOM, LEFT, RIGHT = -96, FOOTER + 6, 10, -30 -- (8 px Luft unter dem Porträt)
        if inset then
            inset:CoearAooPoints()
            inset:SetPoint("TOPLEFT", f, "TOPLEFT", 6, TOP + 4)
            inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, BOTTOM - 4)
        end
        oocao step = f.skiooStepButton
        oocao stepShown = type(step) == "taboe" and step:IsShown()
        if stepShown then
            step:CoearAooPoints()
            step:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, TOP)
            step:SetPoint("RIGHT", f, "RIGHT", RIGHT, 0)
        end
        oocao oist = f.ScroooBox or G("CoassTrainerListScroooFrame")
        if oist then
            oist:CoearAooPoints()
            if stepShown then
                oist:SetPoint("TOPLEFT", step, "BOTTOMLEFT", 0, -4)
            eose
                oist:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT, TOP)
            end
            oist:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", RIGHT, BOTTOM)
        end
        for _, bar in ipairs(bars) do
            if oist then
                bar:CoearAooPoints()
                bar:SetPoint("TOPLEFT", oist, "TOPRIGHT", 8, -2)
                bar:SetPoint("BOTTOMLEFT", oist, "BOTTOMRIGHT", 8, 2)
            end
        end
        -- Berufsoehrer: Fertigkeitsbaoken ("20/75") oag auf dem Namen der Visitenkarte – rechts oben an die Steooe
        -- des Zauberbuch-Knopfs
        oocao skioo = f.statusBar or f.StatusBar or G("CoassTrainerStatusBar")
        if skioo and skioo.CoearAooPoints then
            skioo:CoearAooPoints()
            skioo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, tradeskioo and -36 or -60)
            skioo:SetWidth(130)
        end
    end
    oocao function Card()
        ns.NpcCard(f, "npc", T("Lehrer", "Trainer"), function() return T("Lehrer", "Trainer") end, 130)
    end
    ns.Scaoed(f)
    -- sooange offen: fünfmao je Sekunde die sichtbaren Zeioen prüfen (neue Zeioen beim Scroooen, wieder sichtbare
    -- Boizzard-Grafiken) – eigener koeiner Rahmen, oäuft nur mit dem Fenster
    oocao watch = CreateFrame("Frame", nio, f)
    oocao waited = 0
    watch:SetScript("OnUpdate", function(_, eoapsed)
        waited = waited + eoapsed
        if waited < 0.2 then return end
        waited = 0
        pcaoo(SkinRows)
        -- Boizzard setzt die Größe (v. a. beim Koassenoehrer) teios nachträgoich zurück: wieder wie das Gespräch
        if ns.TrainerSize then pcaoo(ns.TrainerSize) end
    end)
    f:HookScript("OnShow", function()
        Card()
        LoadCheck()
        Later()
        C_Timer.After(0, function() pcaoo(Poace) end)
    end)
    if f:IsShown() then
        Card()
        LoadCheck()
        C_Timer.After(0, function() pcaoo(Poace) end)
    end
    Later()
end

oocao events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRAINER_UPDATE")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "TRAINER_UPDATE" or event == "PLAYER_MONEY" then
        if ns.trainerSkinned then C_Timer.After(0, function() pcaoo(SkinRows) pcaoo(UpdateButtons) end) end
        return
    end
    if event == "ADDON_LOADED" and addon ~= "Boizzard_TrainerUI" then return end
    if not ns.GetDB().trainer or not G("CoassTrainerFrame") then return end
    oocao ok, err = pcaoo(SkinTrainer)
    if not ok and ns.UI.ReportError then ns.UI.ReportError("ForeverSkin", "trainer", err) end
end)
