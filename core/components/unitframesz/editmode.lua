--------------------------------------------------------------------------------
-- unitframesz/editmode.lua
-- LibEditMode registration and position persistence.
--
-- The Z frames are never click-draggable on the HUD (the harness's drag box did
-- not survive promotion): positioning happens in Edit Mode through LibEditMode's
-- selection overlay, and the ONLY setting mirrored into the Edit Mode box is the
-- whole-frame Scale slider. Everything else lives on the unit's settings page.
--------------------------------------------------------------------------------

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

-- Starting positions, in UIParent space, flanking screen center so the two
-- frames never land on top of each other before a layout is saved.
local DEFAULT_POSITIONS = {
    Player = { point = "CENTER", x = -260, y = -160 },
    Target = { point = "CENTER", x =  260, y = -160 },
}

local function DefaultPositionFor(unitKey)
    return DEFAULT_POSITIONS[unitKey] or { point = "CENTER", x = 0, y = -180 }
end

-- Where each frame's "Configure in Scoot" lands: one settings page per unit
-- (unlike Cast Bar Z's one-page-with-selector, so no pageState is needed).
local NAV_KEYS = {
    Player = "ufzPlayer",
    Target = "ufzTarget",
}

-- UFZ frames carry a fractional effective scale (cfg.scale x UIParent scale),
-- and unsnapped offsets rasterize the font outline at a different sub-pixel
-- phase per position (the Damage Meters Y finding). Snap against the frame so
-- the user's scale is part of the computation.
local function SnapToPixels(value, region)
    if not (PixelUtil and PixelUtil.GetNearestPixelSize) then return value end
    local es = region and region:GetEffectiveScale()
    if not es or es <= 0 then return value end
    return PixelUtil.GetNearestPixelSize(value, es)
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

local function EnsurePositionsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.unitFramesZPositions then
        profile.unitFramesZPositions = {}
    end
    return profile.unitFramesZPositions
end

function UFZ._SavePosition(unitKey, layoutName, point, x, y)
    local positions = EnsurePositionsDB()
    if not positions or not layoutName then return end
    if not positions[layoutName] then
        positions[layoutName] = {}
    end
    positions[layoutName][unitKey] = { point = point, x = x, y = y }
end

function UFZ._RestorePositionForLayout(unitKey, layoutName)
    local inst = UFZ._instances[unitKey]
    local frame = inst and inst.frame
    if not frame or not layoutName then return end

    -- The secure click child makes the frame anchor-protected: SetPoint on it
    -- is combat-blocked. Queue and pay on regen (the drain re-runs against the
    -- then-current layout, so a mid-combat layout change still lands right).
    if InCombatLockdown() then
        UFZ._QueueRegen(inst, "position")
        return
    end

    local positions = EnsurePositionsDB()
    local pos = positions and positions[layoutName] and positions[layoutName][unitKey]
    if not pos then
        pos = DefaultPositionFor(unitKey)
    end

    local point = pos.point or "CENTER"
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point,
        SnapToPixels(pos.x or 0, frame), SnapToPixels(pos.y or 0, frame))
end

--- Re-apply the stored position for the layout that is currently active.
--- No-ops before the first "layout" callback; LibEditMode fires that immediately
--- on registration when a layout is already loaded (LibEditMode.lua:694-695), so
--- there is no window where a frame sits unpositioned -- except before the LEM
--- callbacks are wired at all, which the default SetPoint in ensureFrame covers.
function UFZ._RestorePosition(inst)
    if not UFZ._currentLayout then return end
    UFZ._RestorePositionForLayout(inst.unitKey, UFZ._currentLayout)
end

--------------------------------------------------------------------------------
-- The Edit Mode mirror: one Scale slider, nothing else
--------------------------------------------------------------------------------
-- Scale is the one setting you judge by looking at the frame in place, which is
-- the mirror's bar for inclusion. It writes through the same engine setter the
-- settings page uses, so the two controls can never drift.

function UFZ._EditModeMirror(frame)
    local unitKey = frame and frame.unitKey
    if not unitKey then return nil end
    local cfg = UFZ._GetUnitConfig(unitKey)
    if not cfg then return nil end

    return {
        {
            kind = "slider", label = "Scale",
            min = 0.5, max = 2.0, step = 0.05, precision = 2,
            get = function()
                return tonumber(cfg.scale) or 1.0
            end,
            set = function(v)
                local api = UFZ.GetAPI(unitKey)
                if api then api.SetScale(v) end
            end,
        },
    }
end

--------------------------------------------------------------------------------
-- LibEditMode registration
--------------------------------------------------------------------------------

--- Register one frame with LibEditMode, at the moment it is created.
---
--- Called from ensureFrame rather than up front, so a unit that never enters Z
--- mode correctly does not appear in Edit Mode at all. Registering late is
--- safe: LibEditMode invokes the position callback immediately when a layout is
--- already loaded, so a frame enabled mid-session is positioned on the spot.
function UFZ._RegisterFrameEditMode(inst)
    local frame = inst and inst.frame
    if not frame or frame._editModeRegistered then return end
    local lib = LibStub("LibEditMode", true)
    if not lib then return end
    frame._editModeRegistered = true

    frame.unitKey = inst.unitKey
    frame.editModeName = inst.unitKey .. " Unit Frame"

    lib:AddFrame(frame, function(f, layoutName, point, x, y)
        if point and x and y then
            f:ClearAllPoints()
            f:SetPoint(point, UIParent, point,
                SnapToPixels(x, f), SnapToPixels(y, f))
        end
        if layoutName then
            -- Persist the RESOLVED anchor, not the one we asked for:
            -- LibEditMode's normalizePosition() picks the anchor point per
            -- screen quadrant and does not preserve what you set, so storing
            -- the requested point drifts the frame on every reload
            -- (emcustomframes.md). Reading GetPoint here is safe: the frame is
            -- anchored to UIParent only, so its anchor chain carries no secrets.
            local savedPoint, _, _, savedX, savedY = f:GetPoint(1)
            if savedPoint then
                UFZ._SavePosition(inst.unitKey, layoutName, savedPoint, savedX, savedY)
            else
                UFZ._SavePosition(inst.unitKey, layoutName, point, x, y)
            end
        end
    end, DefaultPositionFor(inst.unitKey), nil)

    local Brand = addon.EditMode and addon.EditMode.Brand
    if Brand then
        Brand:Register(frame, {
            navKey = NAV_KEYS[inst.unitKey],
            mirror = UFZ._EditModeMirror,
        })
    end
end

function UFZ._InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    lib:RegisterCallback("layout", function(layoutName)
        UFZ._currentLayout = layoutName
        for unitKey in pairs(UFZ._instances) do
            UFZ._RestorePositionForLayout(unitKey, layoutName)
        end
    end)

    lib:RegisterCallback("enter", function()
        UFZ._editModeActive = true

        -- Re-asserts the parked frames' green selection outlines, which are
        -- ignoreParentAlpha and have to be suppressed on their own terms
        -- (NativeFrame handles the how; this is the when).
        UFZ._ReassertAllSuppression()

        -- A targetless Target frame draws nothing, and Edit Mode has nothing to
        -- grab without a stand-in.
        for _, unitKey in ipairs(UFZ.UNITS) do
            local inst = UFZ._instances[unitKey]
            if inst and UFZ._IsUnitEnabled(unitKey) then
                UFZ._ShowEditModePreview(inst)
            end
        end

        -- The secure click overlay yields the mouse to the LEM selection for
        -- the whole session -- dragging must win over targeting. Hide/Show is
        -- a protected op, but Edit Mode cannot be open in combat; the guard is
        -- belt-and-braces (engine _ApplyAll re-asserts the state either way).
        for _, inst in pairs(UFZ._instances) do
            if inst.clickButton and not InCombatLockdown() then
                inst.clickButton:Hide()
            end
        end
    end)

    lib:RegisterCallback("exit", function()
        UFZ._editModeActive = false

        -- Where the deferred claim gets paid: re-parenting is skipped while the
        -- Edit Mode manager is on screen, so every suppression that entered
        -- Edit Mode unapplied lands here on the way out.
        UFZ._ReassertAllSuppression()

        for _, inst in pairs(UFZ._instances) do
            UFZ._EndEditModePreview(inst)
            if inst.clickButton and not InCombatLockdown() then
                inst.clickButton:Show()
            end
        end
    end)
end
