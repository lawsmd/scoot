--------------------------------------------------------------------------------
-- forever/unitframes/tot.lua
-- The Classic target-of-target frame. The painter is frame.lua and the art is
-- arttot.lua.
--
-- The client sends no unit events for targettarget, so the unit events
-- frame.lua registers never arrive. Vanilla polls too: its health bar runs
-- frequentUpdates, a read every frame. This frame repaints whole when the
-- target changes or picks a new target, and feeds its bars five times a second
-- in between, which is the only way a health change reaches it.
--
-- It is a frame of its own here, with its own Edit Mode position, where
-- vanilla hangs it off the target frame's lower right corner. The default spot
-- is that corner, measured from the target frame's default.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame
local Values = addon.UnitFrames.Values

local POLL_SECONDS = 0.2

-- TargetOfTargetMixin:CheckDead, which also darkens the backing, and
-- TargetofTargetHealthCheck's dead and ghost portrait tints.
local function applyDead(inst)
    local dead = false
    local r, g, b
    if not inst.previewStandIn then
        local ok, value = pcall(UnitIsDeadOrGhost, inst.unit)
        dead = ok and not issecretvalue(value) and value == true
        r, g, b = Values.DeadTint(inst.unit)
    end
    inst.texts.dead:SetShown(dead)
    inst.regions.background:SetAlpha(dead and 0.9 or 1)
    inst.regions.portrait:SetVertexColor(r or 1, g or 1, b or 1)
end

Frame.Define({
    key = "targettarget",
    unit = "targettarget",
    label = "Target of Target",
    frameName = "CamelotTargetOfTargetFrame",
    -- Beta stand-in: level with the target and 2 units off its right edge.
    -- Vanilla's spot is TOPLEFT 373, -73.
    default = { point = "CENTER", relPoint = "CENTER", x = 505, y = -300 },
    -- Over the target frame, whose corner it covers.
    strataLevel = 20,
    -- TargetOfTargetMixin:Update hides the frame while the target is dead. Its
    -- other rule, a target that is the player, has no macro conditional, and
    -- the restricted environment has no UnitIsUnit, so the frame shows the
    -- player there.
    visibilityDriver = "[@target,dead] hide; [@targettarget,exists] show; hide",

    changeEvents = {
        PLAYER_TARGET_CHANGED = true,
        UNIT_TARGET = "target",
    },
    paintState = applyDead,

    build = function(inst)
        C_Timer.NewTicker(POLL_SECONDS, function()
            if inst.frame:IsShown() and not inst.previewStandIn then
                Frame.Paint(inst)
                applyDead(inst)
                -- No UNIT_AURA reaches the container for this unit either.
                addon.UnitFrames.Auras.Kick(inst)
            end
        end)
    end,
})
