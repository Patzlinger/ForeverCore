local addonName, ns = ...

-- Symbol an der Minimap über die gemeinsame Forever-Core-Vorlage (ForeverHub: UI.MinimapButton):
-- Linksklick Menü, Rechtsklick Leisten entsperren/sperren, ziehen = um die Minimap verschieben.
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
        name = "ForeverBarsMinimapButton",
        -- Eigenes Symbol: Tastatur-Taste mit goldenem W (Media\KeyIcon.tga, 64 x 64)
        icon = "Interface\\AddOns\\ForeverBars\\Media\\KeyIcon",
        texCoord = { 0, 1, 0, 1 },
        title = ns.L("ADDON_NAME"),
        angle = function() return ns.db.minimapAngle or 200 end,
        setAngle = function(angle) ns.db.minimapAngle = angle end,
        onClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                ns.SetUnlocked(not ns.unlocked)
            else
                ns.ToggleOptions()
            end
        end,
        -- "Ziehen: Knopf verschieben" ergänzt die Vorlage selbst
        lines = function() return { ns.L("MM_LEFT"), ns.L("MM_RIGHT") } end,
    })
    ns.UpdateMinimapButton()
end
