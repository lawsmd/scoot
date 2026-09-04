-- damagemetersY/editmode.lua - Position save/restore for Edit Mode integration
local _, addon = ...
local DMY = addon.DamageMetersY

--------------------------------------------------------------------------------
-- Position Save/Restore
--------------------------------------------------------------------------------

local function EnsurePositionsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.damageMeterV2Positions then
        profile.damageMeterV2Positions = {}
    end
    return profile.damageMeterV2Positions
end

function DMY._SavePosition(windowIndex, layoutName, point, x, y)
    local positions = EnsurePositionsDB()
    if not positions then return end
    if not positions[layoutName] then
        positions[layoutName] = {}
    end
    positions[layoutName][windowIndex] = {
        point = point,
        x = x,
        y = y,
    }
end

local function GetWindowPosition(windowIndex, layoutName)
    local positions = EnsurePositionsDB()
    return positions and positions[layoutName] and positions[layoutName][windowIndex] or nil
end

local function ApplyWindowPosition(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, DMY._SnapToPixels(x, frame), DMY._SnapToPixels(y, frame))
end

--------------------------------------------------------------------------------
-- Edit Mode Mirror
--------------------------------------------------------------------------------

-- Sizing controls mirrored into the branded Edit Mode dialog for the selected
-- window. Bounds match the settings panel's Sizing sliders; both surfaces
-- write through DMY.SetWindowSizing.
function DMY._EditModeMirror(frame)
    local i = frame and frame.dmyWindowIndex
    if not i then return nil end
    local cfg = DMY._GetWindowConfig(i)
    if not cfg then return nil end

    local specs = {
        {
            kind = "slider", label = "Scale",
            min = 0.5, max = 2.0, step = 0.05, precision = 2,
            get = function()
                local c = DMY._GetWindowConfig(i)
                return tonumber(c and c.windowScale) or 1.0
            end,
            set = function(v) DMY.SetWindowSizing(i, "windowScale", v) end,
        },
        {
            kind = "slider", label = "Width",
            min = 100, max = 800, step = 10,
            get = function()
                local c = DMY._GetWindowConfig(i)
                return tonumber(c and c.frameWidth) or 350
            end,
            set = function(v) DMY.SetWindowSizing(i, "frameWidth", v) end,
        },
        {
            kind = "slider", label = "Height",
            min = 100, max = 600, step = 10,
            get = function()
                local c = DMY._GetWindowConfig(i)
                return tonumber(c and c.frameHeight) or 250
            end,
            set = function(v) DMY.SetWindowSizing(i, "frameHeight", v) end,
        },
    }

    -- Every window has a draggable name column, so every window can reset.
    specs[#specs + 1] = {
        kind = "button", label = "Reset Column Widths",
        set = function()
            local c = DMY._GetWindowConfig(i)
            if c then
                c.nameWidthFraction = nil
                if c.columns then
                    for _, col in ipairs(c.columns) do
                        col.widthFraction = nil
                    end
                end
            end
            if DMY._comp then
                DMY._CalculateColumnWidths(i, DMY._comp)
                DMY._LayoutBarRows(i, DMY._comp)
            end
            if DMY.Dividers and DMY.Dividers.Refresh then
                DMY.Dividers.Refresh()
            end
        end,
    }

    return specs
end

--------------------------------------------------------------------------------
-- LibEditMode Registration
--------------------------------------------------------------------------------

-- One positionable per window (core/editmode/positionables.lua). Storage stays
-- damageMeterV2Positions[layoutName][i]; a window with nothing stored keeps the
-- _CreateWindow parking spot rather than jumping to the Edit Mode default.
function DMY._InitializeEditMode()
    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        if win and win.frame then
            win.frame.editModeName = "Damage Meter " .. i

            -- No per-window settings section exists; the window selector's
            -- state carries the target instead.
            local selection = addon.EditMode.RegisterPositionable(win.frame, {
                key = i,
                default = { point = "BOTTOMLEFT", x = 20, y = 200 + (i - 1) * 60 },
                store = { get = GetWindowPosition, set = DMY._SavePosition },
                apply = ApplyWindowPosition,
                restoreDefault = false,
                brand = {
                    navKey    = "damageMeterV2",
                    pageState = { key = "_damageMeterYSelectedWindow", value = i },
                    mirror    = DMY._EditModeMirror,
                },
            })

            -- Column divider lifecycle rides the LEM selection states: LEM
            -- has no select/deselect callbacks, so hook the selection overlay
            -- (SelectionSkin pattern). ShowHighlighted is the deselected/
            -- hover state — it fires when the selection moves elsewhere.
            if selection and DMY.Dividers then
                local winIdx = i
                hooksecurefunc(selection, "ShowSelected", function()
                    DMY.Dividers.Attach(winIdx)
                end)
                hooksecurefunc(selection, "ShowHighlighted", function()
                    if DMY.Dividers.IsActiveFor(winIdx) then
                        DMY.Dividers.Detach()
                    end
                end)
            end
        end
    end

    addon.EditMode.OnEditMode("damageMetersY", {
        enter = function()
            DMY._editModeActive = true
            -- Show all enabled windows for positioning (even "hidden" visibility)
            for i = 1, DMY.MAX_WINDOWS do
                local win = DMY._windows[i]
                local cfg = DMY._GetWindowConfig(i)
                if win and cfg and cfg.enabled then
                    win.frame:Show()
                end
            end
        end,
        exit = function()
            DMY._editModeActive = false
            if DMY.Dividers then DMY.Dividers.Detach() end
            -- Restore normal visibility rules
            if DMY._comp then
                for i = 1, DMY.MAX_WINDOWS do
                    DMY._UpdateVisibility(i, DMY._comp)
                end
            end
        end,
    })
end
