-- subgrid.lua - Visual sub-grid overlay for Edit Mode's Show Grid
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local SUB_LINE_THICKNESS = 0.6
local SUB_LINE_COLOR = { 0.5, 0.5, 0.5, 0.50 } -- subtle gray at 50% alpha
local SUBDIVISIONS = 10
local MIN_SUB_SPACING = 5 -- skip rendering if sub-spacing < 5px

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local subGridFrame   -- our overlay frame
local linePool       -- CreateObjectPool for Line objects
local cachedSpacing  -- last known grid spacing from SetGridSpacing hook

--------------------------------------------------------------------------------
-- DB Helper
--------------------------------------------------------------------------------

local function isEnabled()
    local profile = addon and addon.db and addon.db.profile
    local qol = profile and profile.qol
    return qol and qol.editModeSubGrid
end

--------------------------------------------------------------------------------
-- Frame + Pool Creation (once)
--------------------------------------------------------------------------------

local function ensureSubGrid()
    if subGridFrame then return end

    subGridFrame = CreateFrame("Frame", "ScootSubGridOverlay", UIParent)
    subGridFrame:SetFrameStrata("BACKGROUND")
    subGridFrame:SetAllPoints(UIParent)
    subGridFrame:Hide()

    -- Set frame level just above Blizzard's grid
    if EditModeManagerFrame and EditModeManagerFrame.Grid then
        subGridFrame:SetFrameLevel(EditModeManagerFrame.Grid:GetFrameLevel() + 1)
    end

    local function lineFactory(pool)
        return subGridFrame:CreateLine(nil, "BACKGROUND")
    end

    local function lineReset(pool, line)
        line:Hide()
        line:ClearAllPoints()
    end

    linePool = CreateObjectPool(lineFactory, lineReset)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local function updateSubGrid()
    if not subGridFrame then return end
    if not subGridFrame:IsShown() then return end

    linePool:ReleaseAll()

    local spacing = cachedSpacing
    if not spacing or spacing <= 0 then return end

    local subSpacing = spacing / SUBDIVISIONS
    if subSpacing < MIN_SUB_SPACING then return end

    local width = subGridFrame:GetWidth()
    local height = subGridFrame:GetHeight()
    if not width or width <= 0 or not height or height <= 0 then return end

    local r, g, b, a = SUB_LINE_COLOR[1], SUB_LINE_COLOR[2], SUB_LINE_COLOR[3], SUB_LINE_COLOR[4]

    -- Vertical sub-lines: radiate from center
    local halfVertical = math.floor((width / subSpacing) / 2)
    for i = 1, halfVertical do
        -- Skip every SUBDIVISIONS-th line (coincides with Blizzard's major grid)
        if i % SUBDIVISIONS ~= 0 then
            local xOffset = i * subSpacing

            -- Right of center
            local line = linePool:Acquire()
            line:SetColorTexture(r, g, b, a)
            line:SetStartPoint("TOP", subGridFrame, xOffset, 0)
            line:SetEndPoint("BOTTOM", subGridFrame, xOffset, 0)
            local thickness = PixelUtil.GetNearestPixelSize(SUB_LINE_THICKNESS, line:GetEffectiveScale(), SUB_LINE_THICKNESS)
            line:SetThickness(thickness)
            line:Show()

            -- Left of center
            line = linePool:Acquire()
            line:SetColorTexture(r, g, b, a)
            line:SetStartPoint("TOP", subGridFrame, -xOffset, 0)
            line:SetEndPoint("BOTTOM", subGridFrame, -xOffset, 0)
            thickness = PixelUtil.GetNearestPixelSize(SUB_LINE_THICKNESS, line:GetEffectiveScale(), SUB_LINE_THICKNESS)
            line:SetThickness(thickness)
            line:Show()
        end
    end

    -- Horizontal sub-lines: radiate from center
    local halfHorizontal = math.floor((height / subSpacing) / 2)
    for i = 1, halfHorizontal do
        if i % SUBDIVISIONS ~= 0 then
            local yOffset = i * subSpacing

            -- Above center
            local line = linePool:Acquire()
            line:SetColorTexture(r, g, b, a)
            line:SetStartPoint("LEFT", subGridFrame, 0, yOffset)
            line:SetEndPoint("RIGHT", subGridFrame, 0, yOffset)
            local thickness = PixelUtil.GetNearestPixelSize(SUB_LINE_THICKNESS, line:GetEffectiveScale(), SUB_LINE_THICKNESS)
            line:SetThickness(thickness)
            line:Show()

            -- Below center
            line = linePool:Acquire()
            line:SetColorTexture(r, g, b, a)
            line:SetStartPoint("LEFT", subGridFrame, 0, -yOffset)
            line:SetEndPoint("RIGHT", subGridFrame, 0, -yOffset)
            thickness = PixelUtil.GetNearestPixelSize(SUB_LINE_THICKNESS, line:GetEffectiveScale(), SUB_LINE_THICKNESS)
            line:SetThickness(thickness)
            line:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Show / Hide
--------------------------------------------------------------------------------

local function showSubGrid()
    if not isEnabled() then return end
    if not EditModeManagerFrame or not EditModeManagerFrame.Grid then return end
    if not EditModeManagerFrame.Grid:IsVisible() then return end

    ensureSubGrid()
    subGridFrame:Show()
    updateSubGrid()
end

local function hideSubGrid()
    if subGridFrame then
        subGridFrame:Hide()
        if linePool then
            linePool:ReleaseAll()
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

local hooksInstalled = false

local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    local grid = EditModeManagerFrame.Grid

    -- Capture spacing from SetGridSpacing hook (avoids reading frame table directly)
    hooksecurefunc(grid, "SetGridSpacing", function(_, spacing)
        cachedSpacing = spacing
        if subGridFrame and subGridFrame:IsShown() then
            updateSubGrid()
        end
    end)

    -- Show/hide with Blizzard's grid
    grid:HookScript("OnShow", function()
        showSubGrid()
    end)

    grid:HookScript("OnHide", function()
        hideSubGrid()
    end)

    -- Redraw on resolution/scale changes
    local function onDisplayChanged()
        if subGridFrame and subGridFrame:IsShown() then
            updateSubGrid()
        end
    end
    addon.Events.On("EditMode:SubGrid", "DISPLAY_SIZE_CHANGED", onDisplayChanged)
    addon.Events.On("EditMode:SubGrid", "UI_SCALE_CHANGED", onDisplayChanged)

    -- Seed cachedSpacing if grid already has a value
    if grid.gridSpacing then
        cachedSpacing = grid.gridSpacing
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.EditMode.InitSubGrid()
    if EditModeManagerFrame and EditModeManagerFrame.Grid then
        installHooks()
    else
        addon.Events.Once("EditMode:SubGrid", "EDIT_MODE_LAYOUTS_UPDATED", function()
            if EditModeManagerFrame and EditModeManagerFrame.Grid then
                installHooks()
            end
        end)
    end
end

function addon.EditMode.SetSubGridEnabled(enabled)
    if enabled then
        showSubGrid()
    else
        hideSubGrid()
    end
end

-- Initialize when this file loads (safe: sets up deferred hooks)
addon.EditMode.InitSubGrid()
