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

function DMY._RestorePosition(windowIndex, layoutName)
    local positions = EnsurePositionsDB()
    if not positions or not positions[layoutName] then return end
    local pos = positions[layoutName][windowIndex]
    if not pos then return end

    local win = DMY._windows[windowIndex]
    if not win or not win.frame then return end

    win.frame:ClearAllPoints()
    win.frame:SetPoint(pos.point or "BOTTOMLEFT", UIParent, pos.point or "BOTTOMLEFT",
        DMY._SnapToPixels(pos.x or 0, win.frame), DMY._SnapToPixels(pos.y or 0, win.frame))
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

function DMY._InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    for i = 1, DMY.MAX_WINDOWS do
        local win = DMY._windows[i]
        if win and win.frame then
            win.frame.editModeName = "Damage Meter " .. i

            lib:AddFrame(win.frame, function(frame, layoutName, point, x, y)
                if point and x and y then
                    frame:ClearAllPoints()
                    frame:SetPoint(point, UIParent, point, DMY._SnapToPixels(x, frame), DMY._SnapToPixels(y, frame))
                end
                if layoutName then
                    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
                    if savedPoint then
                        DMY._SavePosition(i, layoutName, savedPoint, savedX, savedY)
                    else
                        DMY._SavePosition(i, layoutName, point, x, y)
                    end
                end
            end, {
                point = "BOTTOMLEFT",
                x = 20,
                y = 200 + (i - 1) * 60,
            }, nil)

            local Brand = addon.EditMode and addon.EditMode.Brand
            if Brand then
                -- No per-window settings section exists; the window selector's
                -- state carries the target instead.
                Brand:Register(win.frame, {
                    navKey    = "damageMeterV2",
                    pageState = { key = "_damageMeterYSelectedWindow", value = i },
                    mirror    = DMY._EditModeMirror,
                })
            end

            -- Column divider lifecycle rides the LEM selection states: LEM
            -- has no select/deselect callbacks, so hook the selection overlay
            -- (SelectionSkin pattern). ShowHighlighted is the deselected/
            -- hover state — it fires when the selection moves elsewhere.
            local selection = lib.frameSelections and lib.frameSelections[win.frame]
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

    lib:RegisterCallback("layout", function(layoutName, layoutIndex)
        for i = 1, DMY.MAX_WINDOWS do
            DMY._RestorePosition(i, layoutName)
        end
    end)

    lib:RegisterCallback("enter", function()
        DMY._editModeActive = true
        -- Show all enabled windows for positioning (even "hidden" visibility)
        for i = 1, DMY.MAX_WINDOWS do
            local win = DMY._windows[i]
            local cfg = DMY._GetWindowConfig(i)
            if win and cfg and cfg.enabled then
                win.frame:Show()
            end
        end
    end)

    lib:RegisterCallback("exit", function()
        DMY._editModeActive = false
        if DMY.Dividers then DMY.Dividers.Detach() end
        -- Restore normal visibility rules
        if DMY._comp then
            for i = 1, DMY.MAX_WINDOWS do
                DMY._UpdateVisibility(i, DMY._comp)
            end
        end
    end)
end
