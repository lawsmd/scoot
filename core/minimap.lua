--------------------------------------------------------------------------------
-- Scoot Minimap Button
--
-- Creates a minimap button using LibDataBroker and LibDBIcon.
-- Left-click opens the Scoot settings panel (same as /scoot).
-- Right-click also opens settings.
-- Drag to reposition around the minimap.
--------------------------------------------------------------------------------

local addonName, addon = ...

local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)

if not LDB or not LDBIcon then
    return
end

-- Create the data broker object
local ScootLDB = LDB:NewDataObject("Scoot", {
    type = "launcher",
    text = "Scoot",
    icon = "Interface\\AddOns\\Scoot\\ScootIcon",
    OnClick = function(self, button)
        -- Both left and right click open settings panel
        if addon.UI and addon.UI.SettingsPanel and addon.UI.SettingsPanel.Toggle then
            addon.UI.SettingsPanel:Toggle()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("|cff00ff00Scoot|r")
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffffffffClick|r to open settings")
        tooltip:AddLine("|cffffffffDrag|r to move this button")
    end,
})

-- Register the minimap icon on PLAYER_LOGIN
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Get the minimap DB from addon.db, creating it if needed
        local db = addon.db
        if db and db.profile then
            if not db.profile.minimap then
                db.profile.minimap = {
                    hide = false,
                    minimapPos = 220,
                }
            end
            LDBIcon:Register("Scoot", ScootLDB, db.profile.minimap)
        else
            -- Fallback if DB isn't ready yet (shouldn't happen with proper load order)
            LDBIcon:Register("Scoot", ScootLDB, { hide = false, minimapPos = 220 })
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- Expose functions to show/hide the minimap button programmatically
addon.MinimapButton = {}

function addon.MinimapButton:Show()
    if LDBIcon then
        LDBIcon:Show("Scoot")
        if addon.db and addon.db.profile and addon.db.profile.minimap then
            addon.db.profile.minimap.hide = false
        end
    end
end

function addon.MinimapButton:Hide()
    if LDBIcon then
        LDBIcon:Hide("Scoot")
        if addon.db and addon.db.profile and addon.db.profile.minimap then
            addon.db.profile.minimap.hide = true
        end
    end
end

function addon.MinimapButton:Toggle()
    if addon.db and addon.db.profile and addon.db.profile.minimap then
        if addon.db.profile.minimap.hide then
            self:Show()
        else
            self:Hide()
        end
    end
end

function addon.MinimapButton:IsShown()
    if LDBIcon then
        local button = LDBIcon:GetMinimapButton("Scoot")
        return button and button:IsShown()
    end
    return false
end

