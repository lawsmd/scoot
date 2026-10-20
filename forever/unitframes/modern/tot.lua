--------------------------------------------------------------------------------
-- forever/unitframes/modern/tot.lua
-- The Modern target-of-target frame: the small frame this client draws
-- itself, as a second style of the target-of-target unit frame, on the
-- painter in frame.lua over the art in arttot.lua beside this file. This
-- file is the state TargetOfTargetMixin keeps: the dead or unconscious text
-- over the health bar and the portrait's tint for a dead or ghost player.
--
-- The client sends no unit events for targettarget, so the frame repaints
-- whole when the target changes or picks a new target and feeds its bars
-- five times a second in between, the Classic frame's own poll (tot.lua
-- beside this folder, ToTState), which runs the style's own state after
-- each feed. The visibility driver and the alpha rule for a target that is
-- the player are the Classic frame's too.
--
-- Every read below that decides something goes through plain(), which hands
-- back nil for a secret or a missing API, and a nil leaves the resting look.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame
local Values = addon.UnitFrames.Values
local ToTState = addon.UnitFrames.ToTState

local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

-- TargetOfTargetMixin:CheckDead and HealthCheck. UnitIsDeadOrGhost is a
-- plain read where the client's UnitHealth <= 0 is not; the client reads
-- Unconscious in place of Dead where UnitIsUnconscious exists and says so.
-- The portrait greys for a dead player and blues for a ghost.
local function applyDead(inst)
    local dead, unconscious = false, false
    local r, g, b
    if not inst.previewStandIn then
        dead = plain(UnitIsDeadOrGhost, inst.unit) == true
        unconscious = dead and plain(_G.UnitIsUnconscious, inst.unit) == true
        r, g, b = Values.DeadTint(inst.unit)
    end
    inst.texts.dead:SetShown(dead and not unconscious)
    inst.texts.unconscious:SetShown(unconscious)
    inst.regions.portrait:SetVertexColor(r or 1, g or 1, b or 1)
    Frame.ApplyAlpha(inst)
end

Frame.Define({
    key = "targettarget",
    style = "modern",
    unit = "targettarget",
    label = "Target of Target",
    frameName = "CamelotModernTargetOfTargetFrame",
    -- The Camelot layout's spot, the Classic instance's own, so a style swap
    -- on that layout keeps the frame where it was; a profile started from a
    -- Blizzard preset has both instances' defaults rewritten from the
    -- preset's data. One table per frame, never shared: Edit Mode keeps it
    -- by reference.
    default = { point = "CENTER", relPoint = "CENTER", x = 505, y = -300 },
    -- Over the target frame, whose corner it covers.
    strataLevel = 20,
    visibilityDriver = "[@target,dead] hide; [@targettarget,exists] show; hide",

    changeEvents = {
        PLAYER_TARGET_CHANGED = true,
        UNIT_TARGET = "target",
    },
    paintState = applyDead,
    alphaRule = ToTState.SelfAlpha,
    build = ToTState.StartPoll,
})
