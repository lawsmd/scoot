-- Helpers.lua - Shared helpers for Group Frame TUI renderers
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.GroupFrames = addon.UI.GroupFrames or {}
local GF = addon.UI.GroupFrames

--------------------------------------------------------------------------------
-- Edit Mode Frame Getters
--------------------------------------------------------------------------------

function GF.getPartyFrame()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Party)
end

function GF.getRaidFrame()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Raid)
end

--------------------------------------------------------------------------------
-- Database Access
--------------------------------------------------------------------------------

function GF.ensurePartyDB()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    db.groupFrames = db.groupFrames or {}
    db.groupFrames.party = db.groupFrames.party or {}
    return db.groupFrames.party
end

function GF.ensureRaidDB()
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    db.groupFrames = db.groupFrames or {}
    db.groupFrames.raid = db.groupFrames.raid or {}
    return db.groupFrames.raid
end

function GF.ensurePartyTextDB(textKey)
    local t = GF.ensurePartyDB()
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

function GF.ensureRaidTextDB(textKey)
    local t = GF.ensureRaidDB()
    if not t then return nil end
    t[textKey] = t[textKey] or {}
    return t[textKey]
end

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

function GF.applyPartyStyles()
    if addon and addon.ApplyGroupFrameStylesFor then
        addon.ApplyGroupFrameStylesFor("party")
        return
    end
    -- Apply only party-specific functions instead of global ApplyStyles
    -- This prevents party frames from refreshing when unrelated settings change
    if addon.ApplyPartyFrameHealthBarStyle then
        addon.ApplyPartyFrameHealthBarStyle()
    end
    if addon.ApplyPartyFrameHealthOverlays then
        addon.ApplyPartyFrameHealthOverlays()
    end
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
    if addon.ApplyPartyFrameHealthBarBorders then
        addon.ApplyPartyFrameHealthBarBorders()
    end
    if addon.ApplyPartyFrameTitleStyle then
        addon.ApplyPartyFrameTitleStyle()
    end
    if addon.ApplyPartyFrameStatusTextStyle then
        addon.ApplyPartyFrameStatusTextStyle()
    end
    if addon.ApplyPartyOverAbsorbGlowVisibility then
        addon.ApplyPartyOverAbsorbGlowVisibility()
    end
    if addon.ApplyPartyHealPredictionVisibility then
        addon.ApplyPartyHealPredictionVisibility()
    end
    if addon.ApplyPartyAbsorbBarsVisibility then
        addon.ApplyPartyAbsorbBarsVisibility()
    end
    if addon.ApplyPartyHealPredictionClipping then
        addon.ApplyPartyHealPredictionClipping()
    end
    if addon.ApplyPartyGroupLeadIcons then
        addon.ApplyPartyGroupLeadIcons()
    end
end

function GF.applyRaidStyles()
    if addon and addon.ApplyGroupFrameStylesFor then
        addon.ApplyGroupFrameStylesFor("raid")
        return
    end
    -- Apply only raid-specific functions instead of global ApplyStyles
    -- This prevents raid frames from refreshing when unrelated settings change
    if addon.ApplyRaidFrameHealthBarStyle then
        addon.ApplyRaidFrameHealthBarStyle()
    end
    if addon.ApplyRaidFrameHealthOverlays then
        addon.ApplyRaidFrameHealthOverlays()
    end
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
    if addon.ApplyRaidFrameHealthBarBorders then
        addon.ApplyRaidFrameHealthBarBorders()
    end
    if addon.ApplyRaidFrameStatusTextStyle then
        addon.ApplyRaidFrameStatusTextStyle()
    end
    if addon.ApplyRaidFrameGroupTitlesStyle then
        addon.ApplyRaidFrameGroupTitlesStyle()
    end
    if addon.ApplyRaidOverAbsorbGlowVisibility then
        addon.ApplyRaidOverAbsorbGlowVisibility()
    end
    if addon.ApplyRaidHealPredictionVisibility then
        addon.ApplyRaidHealPredictionVisibility()
    end
    if addon.ApplyRaidAbsorbBarsVisibility then
        addon.ApplyRaidAbsorbBarsVisibility()
    end
    if addon.ApplyRaidHealPredictionClipping then
        addon.ApplyRaidHealPredictionClipping()
    end
    if addon.ApplyRaidGroupLeadIcons then
        addon.ApplyRaidGroupLeadIcons()
    end
end

function GF.applyPartyText()
    if addon and addon.ApplyGroupFrameTextFor then
        addon.ApplyGroupFrameTextFor("party")
    else
        GF.applyPartyStyles()
    end
end

function GF.applyRaidText()
    if addon and addon.ApplyGroupFrameTextFor then
        addon.ApplyGroupFrameTextFor("raid")
    else
        GF.applyRaidStyles()
    end
end

function GF.applyPartyRoleIcons()
    if addon.ApplyPartyRoleIcons then addon.ApplyPartyRoleIcons() end
end

function GF.applyRaidRoleIcons()
    if addon.ApplyRaidRoleIcons then addon.ApplyRaidRoleIcons() end
end

function GF.applyPartyGroupLeadIcons()
    if addon.ApplyPartyGroupLeadIcons then addon.ApplyPartyGroupLeadIcons() end
end

function GF.applyRaidGroupLeadIcons()
    if addon.ApplyRaidGroupLeadIcons then addon.ApplyRaidGroupLeadIcons() end
end

function GF.applyPartyHealthBarBorders()
    if addon and addon.ApplyPartyFrameHealthBarBorders then
        addon.ApplyPartyFrameHealthBarBorders()
    end
end

function GF.applyRaidHealthBarBorders()
    if addon and addon.ApplyRaidFrameHealthBarBorders then
        addon.ApplyRaidFrameHealthBarBorders()
    end
end

--------------------------------------------------------------------------------
-- Edit Mode Helpers
--------------------------------------------------------------------------------

function GF.getEditModeSetting(frame, settingId)
    if not frame or not settingId then return nil end
    if addon and addon.EditMode and addon.EditMode.GetSetting then
        return addon.EditMode.GetSetting(frame, settingId)
    end
end

function GF.setEditModeSetting(frame, settingId, value, options)
    if not frame or not settingId then return end
    if addon and addon.EditMode and addon.EditMode.WriteSetting then
        addon.EditMode.WriteSetting(frame, settingId, value, options or {})
    end
end

--------------------------------------------------------------------------------
-- Selector/Dropdown Options
--------------------------------------------------------------------------------

-- Font style options (same as Unit Frames)
GF.fontStyleValues = {
    NONE = "Regular",
    OUTLINE = "Outline",
    THICKOUTLINE = "Thick Outline",
    HEAVYTHICKOUTLINE = "Heavy Thick Outline",
    SHADOW = "Shadow",
    SHADOWOUTLINE = "Shadow Outline",
    SHADOWTHICKOUTLINE = "Shadow Thick Outline",
}
GF.fontStyleOrder = { "NONE", "OUTLINE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE" }

-- 9-way alignment anchor options
GF.anchorValues = {
    TOPLEFT = "Top-Left",
    TOP = "Top-Center",
    TOPRIGHT = "Top-Right",
    LEFT = "Left",
    CENTER = "Center",
    RIGHT = "Right",
    BOTTOMLEFT = "Bottom-Left",
    BOTTOM = "Bottom-Center",
    BOTTOMRIGHT = "Bottom-Right",
}
GF.anchorOrder = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- Health bar color mode options
GF.healthColorValues = {
    default = "Default",
    texture = "Texture Original",
    class = "Class Color",
    value = "Color by Value",
    valueDark = "Color by Value (Dark)",
    custom = "Custom",
}
GF.healthColorOrder = { "default", "texture", "class", "value", "valueDark", "custom" }

GF.healthColorInfoIcons = {
    valueDark = {
        tooltipText = "Dark bar at full health. Below 100%, uses the standard Color by Value color curve.",
    },
}

-- Background color mode options
GF.bgColorValues = {
    default = "Default",
    texture = "Texture Original",
    custom = "Custom",
}
GF.bgColorOrder = { "default", "texture", "custom" }

-- Font/text color mode options
GF.fontColorValues = {
    default = "Default",
    class = "Class Color",
    custom = "Custom",
}
GF.fontColorOrder = { "default", "class", "custom" }

-- Party Frame: Sort By options
GF.partySortByValues = {
    [0] = "Role",
    [1] = "Group",
    [2] = "Alphabetical",
}
GF.partySortByOrder = { 0, 1, 2 }

-- Raid Frame: Groups display type options
GF.raidGroupsValues = {}
GF.raidGroupsOrder = {}
do
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if RGD then
        GF.raidGroupsValues = {
            [RGD.SeparateGroupsVertical] = "Separate Groups (Vertical)",
            [RGD.SeparateGroupsHorizontal] = "Separate Groups (Horizontal)",
            [RGD.CombineGroupsVertical] = "Combine Groups (Vertical)",
            [RGD.CombineGroupsHorizontal] = "Combine Groups (Horizontal)",
        }
        GF.raidGroupsOrder = {
            RGD.SeparateGroupsVertical,
            RGD.SeparateGroupsHorizontal,
            RGD.CombineGroupsVertical,
            RGD.CombineGroupsHorizontal,
        }
    end
end

-- Raid Frame: Sort By options (same values as party)
GF.raidSortByValues = GF.partySortByValues
GF.raidSortByOrder = GF.partySortByOrder

-- Role Icon Set selector options (built from Utils registry)
GF.roleIconSetValues = {}
GF.roleIconSetOrder = {}
do
    local sets = addon.BarsUtils and addon.BarsUtils.ROLE_ICON_SETS or {}
    for _, entry in ipairs(sets) do
        GF.roleIconSetValues[entry.key] = entry.label
        table.insert(GF.roleIconSetOrder, entry.key)
    end
end

--------------------------------------------------------------------------------
-- Conditional Helpers
--------------------------------------------------------------------------------

-- Check if party is in Raid-Style mode
function GF.isRaidStyleParty()
    local frame = GF.getPartyFrame()
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    if not (frame and EM and EM.UseRaidStylePartyFrames) then return false end
    local v = GF.getEditModeSetting(frame, EM.UseRaidStylePartyFrames)
    return v and v ~= 0
end

-- Check if raid is in Separate Groups mode
function GF.isRaidSeparateGroups()
    local frame = GF.getRaidFrame()
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if not (frame and EM and RGD and EM.RaidGroupDisplayType) then return false end
    local v = GF.getEditModeSetting(frame, EM.RaidGroupDisplayType)
    return v == RGD.SeparateGroupsVertical or v == RGD.SeparateGroupsHorizontal
end

-- Check if raid is in Combine Groups mode
function GF.isRaidCombineGroups()
    return not GF.isRaidSeparateGroups()
end

--------------------------------------------------------------------------------
-- Info Icon Tooltips
--------------------------------------------------------------------------------

GF.TOOLTIPS = {
    raidStyleParty = {
        title = "Raid-Style Party Frames",
        text = "When enabled, party frames use the compact raid frame style. This enables additional customization options like frame width/height, borders, and sorting.",
    },
    displayBorder = {
        title = "Display Border",
        text = "Shows Blizzard's default border around each group. Only available when using Separate Groups layout.",
    },
    displayBorderRaid = {
        title = "Display Border",
        text = "Shows Blizzard's default border around each raid GROUP. Only available when Groups is set to 'Separate Groups'.",
    },
    sortBy = {
        title = "Sort By",
        text = "Determines how players are sorted within the combined groups view. Only available when Groups is set to 'Combine Groups'.",
    },
    columnSize = {
        title = "Column Size",
        text = "Number of frames per row or column in the combined groups view. Only available when Groups is set to 'Combine Groups'.",
    },
    groupTitleNumbersOnly = {
        title = "Show Groups as Numbers Only",
        text = "Display just the number instead of 'Group N'. Auto-centers beside-the-row (horizontal) or above-the-column (vertical).",
    },
}
