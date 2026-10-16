local addonName, ns = ...

local button

-- Button am Rand der Minimap platzieren (Winkel in Grad, 0 = rechts, 90 = oben)
local function UpdatePosition()
    local angle = math.rad(ns.db.minimapAngle or 220)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- Während des Ziehens: Winkel aus der Mausposition berechnen
local function OnDragUpdate()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cursorX, cursorY = cursorX / scale, cursorY / scale
    ns.db.minimapAngle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
    UpdatePosition()
end

function ns.UpdateMinimapButton()
    if button then
        button:SetShown(ns.db.showMinimapButton)
    end
end

function ns.CreateMinimapButton()
    if button or not Minimap then return end

    button = CreateFrame("Button", "ForeverQuestsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Aussehen wie die üblichen runden Minimap-Buttons
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    -- Linksklick: Menü, Rechtsklick: Tracker ein-/ausblenden
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ns.ToggleTracker()
        else
            ns.ToggleOptions()
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        ns.Style.GetTooltip():SetOwner(self, "ANCHOR_LEFT")
        ns.Style.GetTooltip():AddLine(ns.L("ADDON_NAME"))
        ns.Style.GetTooltip():AddLine(ns.L("MM_LEFT"), 1, 1, 1)
        ns.Style.GetTooltip():AddLine(ns.L("MM_RIGHT"), 1, 1, 1)
        ns.Style.GetTooltip():AddLine(ns.L("MM_DRAG"), 1, 1, 1)
        ns.Style.GetTooltip():Show()
    end)
    button:SetScript("OnLeave", function()
        ns.Style.GetTooltip():Hide()
    end)

    UpdatePosition()
    ns.UpdateMinimapButton()
end
