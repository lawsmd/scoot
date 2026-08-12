--------------------------------------------------------------------------------
-- unitframesz/stack.lua
-- The boss stack: five frames, one configuration, one Edit Mode handle.
--
-- Every other Z unit is one frame, so the frame IS the thing Edit Mode moves.
-- Boss is five, and moving them individually is not what anyone wants -- so an
-- invisible ANCHOR frame sized to the whole stack becomes the Edit Mode target,
-- and the frames chain off it:
--
--     +-------------------------+  <- the anchor: no art, no mouse, the union
--     |  Boss1   95 / 324k      |     of the five frame rects. LibEditMode
--     |  Boss2   95 / 324k      |     registers THIS, so the selection outline
--     |  Boss3   95 / 324k      |     covers the whole stack and one stored
--     |  Boss4   95 / 324k      |     position moves all five.
--     |  Boss5   95 / 324k      |
--     +-------------------------+
--
-- All five read one config table, so they share one envelope -- which is what
-- makes a TOP/BOTTOM (horizontally centred) chain exact rather than approximate,
-- and lets the box be computed rather than measured.
--
-- GAPS ARE NOT COLLAPSED. An encounter with three bosses leaves slots 4 and 5
-- empty rather than shrinking the stack. That is not a shortcut: the frames are
-- anchor-protected (each carries a secure click child), so re-anchoring them is
-- combat-blocked, and combat is exactly when boss slots come and go.
-- Unconditional chaining is the only legal shape. Blizzard collapses its own
-- gaps only because BossTargetFrameContainer's VerticalLayoutFrame:Layout()
-- runs in secure context; both local reference addons chain unconditionally for
-- the same reason we do. Encounters fill boss1..N in order, so it rarely shows.
--
-- PROTECTION. Boss1 anchors to the box, so the box inherits the frames'
-- anchor-protection transitively -- SetPoint and SetSize on it are blocked in
-- lockdown just like the frames themselves. Hence the combat guard here and the
-- "stack" regen slot in engine.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

-- The one config key that stacks today. Written as a lookup rather than an
-- equality test so Focus/Pet never accidentally grow a stack, and so a second
-- stacking unit (arena, if it ever lands) is one entry.
local STACKED = { Boss = true }

--------------------------------------------------------------------------------
-- The anchor box
--------------------------------------------------------------------------------

--- Created on demand, once, when the stacked unit is first enabled. A unit that
--- never enters Z mode never gets a frame and never appears in Edit Mode.
---
--- Deliberately bare: no textures, no backdrop, mouse off. Its entire job is to
--- be a rect -- for LibEditMode's selection overlay to cover, and for the
--- stored position to apply to.
local function EnsureAnchor(unitKey)
    if UFZ._stackAnchors and UFZ._stackAnchors[unitKey] then
        return UFZ._stackAnchors[unitKey]
    end
    UFZ._stackAnchors = UFZ._stackAnchors or {}

    local anchor = CreateFrame("Frame", "ScootUnitFrameZ" .. unitKey .. "Anchor", UIParent)
    anchor:SetSize(140, 64)   -- placeholder until the first _ApplyStack
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    anchor:EnableMouse(false)
    -- Same rung as the frames it holds (core/strata.lua doctrine): the box has
    -- nothing to draw, but LibEditMode's selection outline is created as its
    -- CHILD and inherits this, and that outline does need to sit above the HUD.
    addon.Strata.ApplyHUD(anchor, 10)
    anchor:Hide()

    UFZ._stackAnchors[unitKey] = anchor

    -- Registration and creation are one step on purpose: the placeholder point
    -- above is only correct until LibEditMode answers, and registering here
    -- means there is no path that produces an unpositioned box.
    UFZ._RegisterStackEditMode(unitKey)
    return anchor
end

--- The frame Edit Mode positions for a config key, or nil.
--- editmode.lua routes every position read and write through this.
function UFZ._StackAnchor(unitKey)
    return UFZ._stackAnchors and UFZ._stackAnchors[unitKey] or nil
end

function UFZ._IsStacked(unitKey)
    return STACKED[unitKey] == true
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- Chain anchors per growth direction. "down" pins Boss1 to the top of the box
-- and each frame hangs off the one above; "up" mirrors it. The box does not
-- move either way -- growth decides which END of it Boss1 occupies, which is
-- why flipping the setting never shifts the stack on screen.
local CHAIN = {
    down = { head = "TOP",    tail = "BOTTOM", sign = -1 },
    up   = { head = "BOTTOM", tail = "TOP",    sign =  1 },
}

--- Lay out (or retire) a stacked unit's frames and their Edit Mode box.
---
--- Idempotent and cheap to over-call: applyEnvelope and applyScale both reach
--- here once per frame, so a single settings pass calls this five times and
--- four of them must cost nothing. The applied-state cache is what makes that
--- true, and -- exactly as with the envelope cache -- it is also what keeps the
--- protected SetSize/SetPoint calls off the per-tick path entirely.
function UFZ._ApplyStack(unitKey)
    if not STACKED[unitKey] then return end

    local enabled = UFZ._IsUnitEnabled(unitKey)
        and addon:IsModuleEnabled("unitFramesZ")

    local anchor = UFZ._StackAnchor(unitKey)
    if not enabled then
        -- Nothing to lay out. Hide the box if it was ever built. Hide is legal
        -- here where it is not on the frames themselves: the frames are
        -- ANCHORED to the box, not children of it, so hiding it hides nothing
        -- protected -- the visibility restriction is a parent/child one.
        if anchor then anchor:Hide() end
        -- Drop the cache rather than keep it across the off state, so a
        -- re-enable always does a full re-layout and nothing has to reason
        -- about what might have changed while the stack was retired.
        if UFZ._appliedStack then UFZ._appliedStack[unitKey] = nil end
        return
    end

    local cfg = UFZ._GetUnitConfig(unitKey)
    if not cfg then return end

    local rows = UFZ._RowsForUnitKey(unitKey)
    if #rows == 0 then return end

    -- Every frame in the stack must exist before any of them can be chained --
    -- a missing link would leave the frames below it anchored to nothing.
    local frames = {}
    for i, row in ipairs(rows) do
        local inst = UFZ._instances[row.frameKey]
        local frame = inst and inst.frame
        if not frame then return end
        frames[i] = frame
    end

    -- The envelope is pure config and all five share one config, so the first
    -- instance's applied rect describes every frame in the stack.
    local env = UFZ._instances[rows[1].frameKey].appliedEnv
    if not env then return end

    local scale = tonumber(cfg.scale) or 1
    local spacing = tonumber(cfg.stackSpacing) or 0
    local growth = CHAIN[cfg.stackGrowth] and cfg.stackGrowth or "down"
    local count = #rows

    -- The step from one frame's top edge to the next, which is NOT the envelope
    -- height: env.snug is the band of rect each frame reserves for name lines it
    -- usually does not use (engine.lua, computeEnvelope), and on a lone frame
    -- nobody can see it. Stacked, it is the entire apparent gap -- which is why
    -- these read as far apart at every spacing the slider offered. Taking it out
    -- of the step makes the slider measure the distance between what is ON
    -- SCREEN, so 0 is "as close as the content allows" and the frames only ever
    -- touch, never overlap, when a name actually wraps.
    local pitch = env.H - (env.snug or 0) + spacing

    -- A set cache implies the box exists (it is only written after the layout
    -- below builds one), so this branch only ever has to re-show it.
    local applied = UFZ._appliedStack and UFZ._appliedStack[unitKey]
    if applied and applied.W == env.W and applied.H == env.H
        and applied.scale == scale and applied.pitch == pitch
        and applied.growth == growth and applied.count == count then
        if anchor and not anchor:IsShown() then anchor:Show() end
        return
    end

    if InCombatLockdown() then
        -- Flags only, and queued against the head frame so one drain does the
        -- whole stack (the worker recomputes from scratch).
        UFZ._QueueRegen(UFZ._HeadInstance(unitKey), "stack")
        return
    end

    anchor = anchor or EnsureAnchor(unitKey)

    -- The box carries the frames' scale, so spacing and the envelope resolve in
    -- one coordinate space and the rect is an exact fit rather than a converted
    -- one. It also matches how editmode.lua snaps stored offsets, which uses
    -- the positioned frame's own effective scale.
    anchor:SetScale(scale)
    -- One whole envelope plus a step for each frame after the first: the box is
    -- the union of five overlapping rects, not five stacked ones.
    anchor:SetSize(env.W, env.H + pitch * (count - 1))

    -- Head-to-head chaining, one pitch apart. (Head-to-TAIL would put the gap
    -- between the rects, which is exactly the reservation this steps over.)
    local chain = CHAIN[growth]
    for i, frame in ipairs(frames) do
        frame:ClearAllPoints()
        if i == 1 then
            frame:SetPoint(chain.head, anchor, chain.head, 0, 0)
        else
            frame:SetPoint(chain.head, frames[i - 1], chain.head, 0, chain.sign * pitch)
        end
    end

    anchor:Show()

    UFZ._appliedStack = UFZ._appliedStack or {}
    UFZ._appliedStack[unitKey] = {
        W = env.W, H = env.H, scale = scale,
        pitch = pitch, growth = growth, count = count,
    }

    -- The box just changed shape, and the stored position anchors the head
    -- frame's CONTENT rather than this rect (editmode.lua), so its anchor has to
    -- be re-derived against the new one -- otherwise a taller envelope pays for
    -- itself out of where Boss1's name sits. After the cache write, deliberately:
    -- the conversion reads the box's dimensions back out of it. No-ops before the
    -- first LibEditMode layout callback, exactly like every other restore.
    UFZ._RestorePositionForLayout(unitKey, UFZ._currentLayout)
end

--- Build the box on demand. editmode.lua calls this from the registration path
--- so a boss frame's creation produces the box that positions it.
function UFZ._EnsureStackAnchor(unitKey)
    if not STACKED[unitKey] then return nil end
    return EnsureAnchor(unitKey)
end
