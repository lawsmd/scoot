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
-- It is a frame of its own here, hanging off the target frame's right side
-- by default (settings.lua, "Attach"), where vanilla hangs it off the lower
-- right corner; with the attach off it holds its own Edit Mode position.
--
-- Vanilla's other rule, no frame while the target is the player, is alpha
-- here (selfAlpha), since the secure manager cannot say so.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local Frame = UF.Frame
local Values = UF.Values

local POLL_SECONDS = 0.2

-- What both styles share (modern/tot.lua): the poll and the rule below are
-- the unit's, not the style's.
local ToTState = {}
UF.ToTState = ToTState

-- TargetOfTargetMixin:CheckDead, which also darkens the backing, and
-- TargetofTargetHealthCheck's dead and ghost portrait tints. The self rule
-- re-reads here too, since paintState runs on every target change.
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
    Frame.ApplyAlpha(inst)
end

-- TargetOfTargetMixin:Update's other rule: no frame while the target is the
-- player, whose target's target is the player again. No macro conditional
-- says so and the secure manager has no UnitIsUnit, so the driver keeps the
-- frame shown and this takes it to alpha 0 instead, legal in combat on the
-- protected frame (frame.lua, Frame.ApplyAlpha, which calls it with the
-- alpha Dynamic Layouts or the redress asked for). UnitIsUnit answers secret
-- under identity restrictions, so the answer goes to SetAlphaFromBoolean
-- unread; a plain answer also keeps the tooltip off the empty spot
-- (inst.selfHidden). The click child under the invisible frame still
-- answers a click, which targets the player again.
local function selfAlpha(inst, alpha)
    inst.selfHidden = nil
    if not UF.HideWhenSelf(inst.key) then return false end
    local ok, isSelf = pcall(UnitIsUnit, "target", "player")
    if not ok then return false end
    if not issecretvalue(isSelf) then
        inst.selfHidden = isSelf == true or nil
        inst.frame:SetAlpha(inst.selfHidden and 0 or alpha)
        return true
    end
    return pcall(inst.frame.SetAlphaFromBoolean, inst.frame, isSelf, 0, alpha)
end
ToTState.SelfAlpha = selfAlpha

-- The poll, which both styles run (modern/tot.lua): the bars fed, then the
-- style's own state, then the auras, since no UNIT_AURA reaches the
-- container for this unit either. A parked instance (the other style's on
-- screen) costs the tick one boolean.
local function startPoll(inst)
    C_Timer.NewTicker(POLL_SECONDS, function()
        if inst.enabled and inst.frame:IsShown() and not inst.previewStandIn then
            Frame.Paint(inst)
            inst.def.paintState(inst)
            addon.UnitFrames.Auras.Kick(inst)
        end
    end)
end

ToTState.StartPoll = startPoll

Frame.Define({
    key = "targettarget",
    unit = "targettarget",
    label = "Target of Target",
    frameName = "CamelotTargetOfTargetFrame",
    -- The free spot, for the attach off: level with the target's default and
    -- 2 units off its right edge, which the attach at 0, 0 all but matches.
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
    alphaRule = selfAlpha,
    build = startPoll,
})
