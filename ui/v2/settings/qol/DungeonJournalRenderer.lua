-- DungeonJournalRenderer.lua - Quality of Life: Dungeon Journal settings
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Settings = addon.UI.Settings or {}
addon.UI.Settings.QoL = addon.UI.Settings.QoL or {}
addon.UI.Settings.QoL.DungeonJournal = {}

local DJUI = addon.UI.Settings.QoL.DungeonJournal
local SettingsBuilder = addon.UI.SettingsBuilder
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- DB Helpers
--   getQoL: read-only — must NOT materialize the qol{} table.
--   ensureQoL: writer-only — used by set callbacks.
--------------------------------------------------------------------------------

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    if not profile then return nil end
    return rawget(profile, "qol")
end

local function ensureQoL()
    if not (addon and addon.db and addon.db.profile) then return nil end
    addon.db.profile.qol = addon.db.profile.qol or {}
    return addon.db.profile.qol
end

local function getMarkCount()
    local DJ = addon.DungeonJournal
    return (DJ and DJ.CountMarks and DJ.CountMarks()) or 0
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------

function DJUI.Render(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    -- Master enable — emphasized "hero toggle" at the top.
    builder:AddToggle({
        label = "Enable Dungeon Journal Checkboxes",
        emphasized = true,
        description = "Adds a checkbox to the left of every loot row in the Encounter Journal for the current season's 8 dungeons. Click an empty box to mark an item as received on this character; click a checked box and confirm to clear it.",
        get = function()
            local q = getQoL()
            return (q and rawget(q, "dungeonJournalEnabled")) == true
        end,
        set = function(value)
            local q = ensureQoL()
            if not q then return end
            q.dungeonJournalEnabled = value and true or false
            local DJ = addon.DungeonJournal
            if DJ and DJ.RefreshAllVisible then
                DJ.RefreshAllVisible()
            end
        end,
    })

    builder:AddDescription(
        "Marks are stored per character (not per profile), so switching Scoot profiles on the same character keeps your list intact.",
        { topPadding = 8 }
    )

    local countLine = string.format("%d items marked on this character.", getMarkCount())
    builder:AddDescription(countLine, { topPadding = 12 })

    -- Reset button — anchored manually below the last builder row. The search
    -- index scan runs every renderer against the shared scroll content, so a
    -- control the builder does not own would survive the teardown and stack up
    -- on whatever page the scan ran from.
    if Controls and Controls.CreateButton and not SettingsBuilder._scanMode then
        builder._currentY = builder._currentY - 16

        local btn = Controls:CreateButton({
            parent  = scrollContent,
            text    = "Reset all marks (this character)",
            width   = 260,
            height  = 28,
            onClick = function()
                local DJ = addon.DungeonJournal
                if not DJ then return end
                local message = string.format(
                    "Clear all received-loot marks on this character?\n\n%d item(s) will be cleared. This cannot be undone.",
                    getMarkCount()
                )
                if addon.Dialogs and addon.Dialogs.Confirm then
                    addon.Dialogs:Confirm(message, function()
                        DJ.ResetAllMarks()
                        DJUI.Render(panel, scrollContent)
                    end)
                else
                    DJ.ResetAllMarks()
                    DJUI.Render(panel, scrollContent)
                end
            end,
        })
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 8, builder._currentY)
            builder._currentY = builder._currentY - 28 - 8
            -- Register with the builder so Clear() releases it on navigation.
            table.insert(builder._controls, btn)
        end
    end

    builder:Finalize()
end

addon.UI.SettingsPanel:RegisterRenderer("qolDungeonJournal", function(panel, scrollContent)
    DJUI.Render(panel, scrollContent)
end)

return DJUI
