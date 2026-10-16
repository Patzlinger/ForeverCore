local addonName, ns = ...

-- Symbol an der Minimap über die gemeinsame Forever-Core-Vorlage (ForeverHub: UI.MinimapButton):
-- Linksklick Menü, Rechtsklick Tracker ein-/ausblenden, ziehen = um die Minimap verschieben.
-- Ab zwei Forever-Addons sammelt der Hub das Symbol im Forever-Core-Knopf.

local button

function ns.UpdateMinimapButton()
    if button then
        button:SetShown(ns.db.showMinimapButton)
    end
end

function ns.CreateMinimapButton()
    if button or not Minimap then return end
    button = ForeverHub.UI.MinimapButton({
        name = "ForeverQuestsMinimapButton",
        icon = "Interface\\GossipFrame\\AvailableQuestIcon",
        title = ns.L("ADDON_NAME"),
        angle = function() return ns.db.minimapAngle or 220 end,
        setAngle = function(angle) ns.db.minimapAngle = angle end,
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                ns.ToggleTracker()
            else
                ns.ToggleOptions()
            end
        end,
        -- "Ziehen: Knopf verschieben" ergänzt die Vorlage selbst
        lines = function() return { ns.L("MM_LEFT"), ns.L("MM_RIGHT") } end,
    })
    ns.UpdateMinimapButton()
end
