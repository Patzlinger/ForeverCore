-- ForeverChat – Copy.lua: Text kopieren (Webadresse) und Chatverlauf kopieren.
-- WoW kann nicht selbst in die Zwischenablage schreiben: Text wird markiert in ein Feld gelegt,
-- der Spieler drueckt Strg+C.
local ADDON_NAME, ns = ...
local UI, T = ns.UI, ns.T

local COPY_LINES = 300 -- so viele Zeilen hoechstens im Kopierfenster

---------------------------------------------------------------------------
-- Text fuer das Kopierfenster bereinigen (Farben, Links, Symbole entfernen)
---------------------------------------------------------------------------
local function Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")      -- Link -> nur der sichtbare Text
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "") -- Symbole
    text = text:gsub("||", "|")
    return text
end

---------------------------------------------------------------------------
-- Fenster mit Eingabefeld (eine Zeile oder viele)
---------------------------------------------------------------------------
local copyWindow
local function BuildCopyWindow()
    local f = UI.Window("ForeverChatCopy", "", 560, 380)
    f:SetFrameStrata("FULLSCREEN_DIALOG")

    f.hint = UI.Hint(f, 14, -34, 530, "")

    local box = UI.Box(f, 0.6)
    box:SetPoint("TOPLEFT", 12, -54)
    box:SetPoint("BOTTOMRIGHT", -12, 44)

    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    if not ok then scroll = CreateFrame("ScrollFrame", nil, box, "ScrollFrameTemplate") end
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(500)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Text bleibt unveraendert (nur kopieren, nicht bearbeiten)
    edit:SetScript("OnTextChanged", function(self, user)
        if user and f.text then self:SetText(f.text) self:HighlightText() end
    end)
    scroll:SetScrollChild(edit)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.edit, f.scroll = edit, scroll

    local close = UI.Button(f, T("Schließen", "Close"), 110, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -16, 12)
    local all = UI.Button(f, T("Alles markieren", "Select all"), 130, function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    all:SetPoint("RIGHT", close, "LEFT", -8, 0)
    copyWindow = f
    return f
end

-- title, text; single = eine Zeile (Webadresse) -> kleines Fenster
function ns.ShowCopyText(title, text, single)
    local f = copyWindow or BuildCopyWindow()
    f.TitleText:SetText(title)
    f.hint:SetText(T("Strg+C kopiert den markierten Text.", "Ctrl+C copies the selected text."))
    f:SetSize(560, single and 150 or 380)
    f.text = text
    f.edit:SetWidth(math.max(200, f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 500))
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    if not single then
        C_Timer.After(0, function() f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange()) end)
    end
end

---------------------------------------------------------------------------
-- Chat kopieren: Zeilen des gerade gewaehlten Chatfensters (gesperrte Zeilen werden uebersprungen)
---------------------------------------------------------------------------
function ns.ShowCopyChat()
    local frame = ns.SelectedChatFrame()
    if not (frame and frame.GetNumMessages and frame.GetMessageInfo) then return end
    local lines, skipped = {}, 0
    local count = math.min(frame:GetNumMessages(), COPY_LINES)
    -- GetMessageInfo(1) ist die neueste Zeile: von alt nach neu einsammeln
    for i = count, 1, -1 do
        local ok, text = pcall(frame.GetMessageInfo, frame, i)
        if ok and type(text) == "string" and ns.CanRead(text) then
            lines[#lines + 1] = Plain(text)
        else
            skipped = skipped + 1
        end
    end
    local tab = _G[frame:GetName() .. "Tab"]
    local name = tab and tab:GetText() or frame:GetName()
    ns.ShowCopyText(string.format(T("Chat kopieren – %s", "Copy chat – %s"), name), table.concat(lines, "\n"))
    if skipped > 0 then
        copyWindow.hint:SetText(string.format(T("Strg+C kopiert den markierten Text. %d gesperrte Zeilen (Kampf) ausgelassen.",
            "Ctrl+C copies the selected text. %d locked lines (combat) left out."), skipped))
    end
end
