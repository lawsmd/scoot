--------------------------------------------------------------------------------
-- unitframesz/editmode.lua
-- LibEditMode registration and position persistence.
--
-- The Z frames are never click-draggable on the HUD (the harness's drag box did
-- not survive promotion): positioning happens in Edit Mode through LibEditMode's
-- selection overlay, and what gets mirrored into the Edit Mode box is whatever
-- you judge by looking at the frame in place -- Scale everywhere, plus the two
-- stack controls on a stacked unit. Everything else lives on the settings page.
--------------------------------------------------------------------------------

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

-- Starting positions, in UIParent space, flanking screen center so the frames
-- never land on top of each other before a layout is saved. Boss goes to the
-- right edge, where Blizzard's own boss frames live (its Edit Mode preset
-- anchors RIGHT/UIParent/RIGHT).
local DEFAULT_POSITIONS = {
    Player = { point = "CENTER", x = -260, y = -160 },
    Target = { point = "CENTER", x =  260, y = -160 },
    Boss   = { point = "RIGHT",  x = -140, y =  100 },
}

local function DefaultPositionFor(unitKey)
    return DEFAULT_POSITIONS[unitKey] or { point = "CENTER", x = 0, y = -180 }
end

-- Where each frame's "Configure in Scoot" lands: one settings page per unit
-- (unlike Cast Bar Z's one-page-with-selector, so no pageState is needed --
-- Boss has five frames but still exactly one page, and its Edit Mode entry is
-- the stack box rather than any one frame).
local NAV_KEYS = {
    Player = "ufzPlayer",
    Target = "ufzTarget",
    Boss   = "ufzBoss",
}

-- What Edit Mode calls each entry. Stacked units name the group, not a frame.
local function EditModeNameFor(unitKey)
    if UFZ._IsStacked(unitKey) then return "Boss Frames" end
    return unitKey .. " Unit Frame"
end

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
-- The stored position anchors the CONTENT, not the rect
--------------------------------------------------------------------------------
-- The frame rect is a config-derived SUPERSET around the numbers box
-- (engine.lua, computeEnvelope): it reserves room for every satellite the config
-- can ask for, so it grows and shrinks whenever a setting changes what the
-- element may contain. Anchoring THAT rect to the screen makes every one of
-- those changes move the content -- and with a vertically centred anchor point,
-- which is what normalizePosition hands out for anything near the middle of the
-- screen, it moves it BOTH ways at once. Enabling the power text grew the
-- envelope downward by ~14px, the pinned centre pushed the name and the number
-- stack UP by half of it, and the aura rows hanging off the frame's bottom edge
-- went DOWN by the other half (user report 2026-08-10: "the name is supposed to
-- be the anchor of the frame").
--
-- So what the stored numbers pin is the CONTENT ORIGIN -- the numbers box, which
-- is the rect every content anchor in applyLayout is measured from -- and the
-- frame's own anchor is derived from it against the current envelope. The
-- reservation now grows outward from a name that does not move, and the only
-- things that follow the frame's edges are the unboxed aura rows, which are
-- exactly what has to make room.
--
-- The conversion runs both ways and lives here alone: everything outside this
-- file (LibEditMode's drag, GetPoint, SetPoint) still speaks frame rects.

--- The anchor point's position inside a rect, as fractions from its TOPLEFT.
--- LibEditMode hands out the nine UIParent points (normalizePosition).
local function PointFractions(point)
    point = point or "CENTER"
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("TOP") and 0 or point:find("BOTTOM") and 1 or 0.5
    return fx, fy
end

--- The rect Edit Mode positions, and where the content origin sits inside it:
--- rect W/H, plus the origin as an offset from the rect's TOPLEFT (+x right,
--- +y up). Pure config, like the envelope it reads -- nothing here measures a
--- widget. nil before the frame has taken an envelope, which is the callers' cue
--- to leave the stored numbers alone.
local function ContentRect(unitKey)
    local inst = UFZ._HeadInstance(unitKey)
    local env = inst and inst.appliedEnv
    if not env then return nil end

    local W, H = env.W, env.H

    -- applyEnvelope seats the box env.T below the rect's top edge, flush against
    -- the align edge. The reference is its TOPLEFT on BOTH handednesses, rather
    -- than the align-side corner it is actually pinned by: flipping align
    -- mirrors the element, and mirroring it about the box leaves the box roughly
    -- where it was instead of throwing the whole element a frame-width sideways.
    local oy = -env.T
    local ox = (env.align == "left") and 0 or (W - (inst.cfg.width or 0))

    if UFZ._IsStacked(unitKey) then
        -- The box is the union of five overlapping frame rects, and growth
        -- decides which END of it the head frame occupies (stack.lua). The head
        -- frame's content is what a stack position holds still.
        local applied = UFZ._appliedStack and UFZ._appliedStack[unitKey]
        if not applied then return nil end
        H = applied.H + applied.pitch * (applied.count - 1)
        if applied.growth == "up" then oy = oy - (H - applied.H) end
    end

    return W, H, ox, oy
end

--- Stored content position -> the frame-rect anchor offsets that realize it.
local function ToFrameOffsets(unitKey, point, x, y)
    local W, H, ox, oy = ContentRect(unitKey)
    if not W then return x, y end
    local fx, fy = PointFractions(point)
    return x - ox + fx * W, y - oy - fy * H
end

--- Frame-rect anchor offsets (what GetPoint reports) -> the position to store.
--- nil when the rect cannot be resolved, which callers treat as "not converted".
local function ToContentOffsets(unitKey, point, x, y)
    local W, H, ox, oy = ContentRect(unitKey)
    if not W then return nil end
    local fx, fy = PointFractions(point)
    return x + ox - fx * W, y + oy + fy * H
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

--- Store a position. What comes in is the FRAME RECT's anchor -- what GetPoint
--- reports, and what LibEditMode's drag produces -- and what goes out is the
--- content origin expressed against it, so the stored number outlives every
--- later change to the reservation drawn around that content.
function UFZ._SavePosition(unitKey, layoutName, point, x, y)
    local positions = EnsurePositionsDB()
    if not positions or not layoutName then return end
    if not positions[layoutName] then
        positions[layoutName] = {}
    end
    local cx, cy = ToContentOffsets(unitKey, point, x, y)
    positions[layoutName][unitKey] = {
        point = point,
        x = cx or x,
        y = cy or y,
        -- Absent when the rect could not be resolved -- and on everything saved
        -- before this existed, which is what UpgradeStored keys on.
        anchorsContent = cx and true or nil,
    }
end

--- Re-express a position stored before the content anchor existed. Those numbers
--- anchor the frame RECT; converting them against the envelope that rect is
--- wearing right now -- which is the envelope it wore when they were saved,
--- since nothing but a settings change moves it -- lands the frame in exactly
--- the same pixels and gives every LATER settings change a still name to grow
--- around. Deferred until the frame has taken an envelope so it never guesses;
--- until then the restore below uses the raw numbers, which is what it always
--- did.
local function UpgradeStored(unitKey, pos)
    if pos.anchorsContent then return end
    local cx, cy = ToContentOffsets(unitKey, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    if not cx then return end
    pos.x, pos.y, pos.anchorsContent = cx, cy, true
end

--- The frame a config key's stored position applies to.
--- One frame for Player and Target; the stack box for Boss, which is the whole
--- point of the box -- five frames, one position.
function UFZ._PositionFrame(unitKey)
    if UFZ._IsStacked(unitKey) then
        return UFZ._StackAnchor(unitKey)
    end
    local inst = UFZ._HeadInstance(unitKey)
    return inst and inst.frame or nil
end

function UFZ._RestorePositionForLayout(unitKey, layoutName)
    local frame = UFZ._PositionFrame(unitKey)
    if not frame or not layoutName then return end

    -- The secure click child makes the frame anchor-protected: SetPoint on it
    -- is combat-blocked. The stack box inherits that protection transitively,
    -- because the head frame anchors to it. Queue and pay on regen (the drain
    -- re-runs against the then-current layout, so a mid-combat layout change
    -- still lands right).
    if InCombatLockdown() then
        UFZ._QueueRegen(UFZ._HeadInstance(unitKey), "position")
        return
    end

    local positions = EnsurePositionsDB()
    local pos = positions and positions[layoutName] and positions[layoutName][unitKey]
    if pos then
        UpgradeStored(unitKey, pos)
    else
        -- The shipped starting spots are frame-rect anchors and stay that way:
        -- they are arbitrary places to land before the first drag, and the save
        -- that follows it writes a content position.
        pos = DefaultPositionFor(unitKey)
    end

    local point = pos.point or "CENTER"
    local x, y = pos.x or 0, pos.y or 0
    if pos.anchorsContent then
        x, y = ToFrameOffsets(unitKey, point, x, y)
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, SnapToPixels(x, frame), SnapToPixels(y, frame))
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
-- The Edit Mode mirror
--------------------------------------------------------------------------------
-- The bar for inclusion is "you judge it by looking at the frame in place".
-- Scale clears it on every unit. On a stacked unit the two stack controls clear
-- it just as plainly -- the box you are dragging IS the stack, and spacing and
-- growth are the only things that decide what it looks like -- so they join it
-- there rather than making you leave Edit Mode to see the effect.
--
-- Every entry writes through the engine setter the settings page uses, so the
-- two surfaces cannot drift, and the fan-out reaches all five boss frames.

function UFZ._EditModeMirror(frame)
    local unitKey = frame and frame.unitKey
    if not unitKey then return nil end
    local cfg = UFZ._GetUnitConfig(unitKey)
    if not cfg then return nil end

    local function api()
        return UFZ.GetAPI(unitKey)
    end

    local specs = {
        {
            kind = "slider", label = "Scale",
            min = 0.5, max = 2.0, step = 0.05, precision = 2,
            get = function()
                return tonumber(cfg.scale) or 1.0
            end,
            set = function(v)
                local a = api()
                if a then a.SetScale(v) end
            end,
        },
    }

    if UFZ._IsStacked(unitKey) then
        specs[#specs + 1] = {
            kind = "slider", label = "Spacing",
            min = -20, max = 40, step = 1, precision = 0,
            get = function()
                return tonumber(cfg.stackSpacing) or 0
            end,
            set = function(v)
                local a = api()
                if a then a.SetStackSpacing(v) end
            end,
        }
        specs[#specs + 1] = {
            kind = "selector", label = "Growth",
            -- Short labels: the mirror's selector is 132px, and the settings
            -- page is where the "Boss 1 sits at this end" prose lives.
            values = { down = "Down", up = "Up" },
            order = { "down", "up" },
            get = function()
                return cfg.stackGrowth or "down"
            end,
            set = function(v)
                local a = api()
                if a then a.SetStackGrowth(v) end
            end,
        }
    end

    return specs
end

--------------------------------------------------------------------------------
-- LibEditMode registration
--------------------------------------------------------------------------------

--- Register one positionable frame with LibEditMode. That frame is the unit
--- frame for Player and Target and the stack BOX for Boss -- LibEditMode
--- neither knows nor cares which, because everything it needs (a rect, a name,
--- a position callback) is the same either way.
local function AddToEditMode(frame, unitKey)
    if not frame or frame._editModeRegistered then return end
    local lib = LibStub("LibEditMode", true)
    if not lib then return end
    frame._editModeRegistered = true

    frame.unitKey = unitKey
    frame.editModeName = EditModeNameFor(unitKey)

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
                UFZ._SavePosition(unitKey, layoutName, savedPoint, savedX, savedY)
            else
                UFZ._SavePosition(unitKey, layoutName, point, x, y)
            end
        end
    end, DefaultPositionFor(unitKey), nil)

    local Brand = addon.EditMode and addon.EditMode.Brand
    if Brand then
        Brand:Register(frame, {
            navKey = NAV_KEYS[unitKey],
            mirror = UFZ._EditModeMirror,
        })
    end
end

--- Register a stacked unit's box. Idempotent: called from stack.lua the moment
--- the box is built, and every one of the five boss frames reaches that path.
function UFZ._RegisterStackEditMode(unitKey)
    AddToEditMode(UFZ._StackAnchor(unitKey), unitKey)
end

--- Register a frame with LibEditMode, at the moment it is created.
---
--- Called from ensureFrame rather than up front, so a unit that never enters Z
--- mode correctly does not appear in Edit Mode at all. Registering late is
--- safe: LibEditMode invokes the position callback immediately when a layout is
--- already loaded, so a frame enabled mid-session is positioned on the spot.
---
--- A stacked unit registers its BOX instead of its frames: the frames chain off
--- the box and must not be individually draggable.
function UFZ._RegisterFrameEditMode(inst)
    if not inst then return end
    if UFZ._IsStacked(inst.unitKey) then
        UFZ._EnsureStackAnchor(inst.unitKey)   -- builds the box, which registers it
        return
    end
    AddToEditMode(inst.frame, inst.unitKey)
end

function UFZ._InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    -- Per CONFIG key, not per instance: a stacked unit has one stored position
    -- and one box to apply it to, so five boss frames must not each try.
    lib:RegisterCallback("layout", function(layoutName)
        UFZ._currentLayout = layoutName
        for _, unitKey in ipairs(UFZ.UNITS) do
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
        -- grab without a stand-in. Boss frames are targetless outside an
        -- encounter, which is nearly always -- so all five take a stand-in and
        -- the stack is visible for the whole time the user is placing it.
        for _, row in ipairs(UFZ.FRAMES) do
            local inst = UFZ._instances[row.frameKey]
            if inst and UFZ._IsUnitEnabled(row.unitKey) then
                UFZ._ShowEditModePreview(inst)
            end
        end

        -- Stand-ins can change what a frame renders but never its envelope, so
        -- this is a skip-compare no-op in the normal case. It is here for the
        -- one that isn't: a stack whose box has never been sized. The loop above
        -- cannot build a frame -- it reads _instances -- so a unit enabled while
        -- Edit Mode is open takes its stand-in from _ApplyAll's tail instead.
        -- Already guarded: _ApplyStack queues the "stack" slot in lockdown.
        UFZ._ApplyStack("Boss")

        -- The secure click overlay yields the mouse to the LEM selection for
        -- the whole session -- dragging must win over targeting. Hide/Show on
        -- the protected button is combat-blocked, and Edit Mode CAN be open in
        -- combat: CanEnterEditMode (EditModeManager.lua:1636-1655) tests the
        -- EditModeDisabled game rule, NPE restriction and account settings and
        -- nothing else, so the Game Menu button stays live in a fight and this
        -- very callback runs from LibEditMode's OnShow hook. The engine worker
        -- queues a refused write onto PLAYER_REGEN_ENABLED rather than losing it.
        for _, inst in pairs(UFZ._instances) do
            UFZ._ApplyClickOverlayShown(inst)
        end
    end)

    lib:RegisterCallback("exit", function()
        UFZ._editModeActive = false

        -- Where the deferred claim gets paid: re-parenting is skipped while the
        -- Edit Mode manager is on screen, so every suppression that entered
        -- Edit Mode unapplied lands here on the way out.
        UFZ._ReassertAllSuppression()

        -- Same worker as the enter side, and it matters more here: an exit that
        -- landed in combat used to drop the Show outright, leaving the overlay
        -- hidden and click-to-target dead for the rest of the session.
        for _, inst in pairs(UFZ._instances) do
            UFZ._EndEditModePreview(inst)
            UFZ._ApplyClickOverlayShown(inst)
        end
    end)
end
