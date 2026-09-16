--------------------------------------------------------------------------------
-- forever/unitframes/harness.lua
-- The game-facing half of an addon-owned unit frame: lifecycle, the secure
-- click child, combat-deferred work, and unit visibility.
--
-- Nothing here decides how a frame looks. The painter builds its widgets into
-- inst.frame and registers workers by name; this file decides when they are
-- allowed to run.
--
-- This is a second implementation of a shape that already works elsewhere in
-- the tree. It is written out rather than borrowed because the original is
-- welded to its own painter and its own config schema, and because two working
-- copies are what make the common file measurable instead of predicted. The
-- diff is the deliverable.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Harness = {}
addon.UnitFrames.Harness = Harness

--------------------------------------------------------------------------------
-- Combat-deferred work
--------------------------------------------------------------------------------
-- The secure click child calls SetAllPoints on the outer frame, which makes the
-- frame anchor-protected: in combat, insecure code cannot move, resize or
-- rescale it. Its visibility is protected by the same relationship, because
-- hiding the parent would hide the protected child. So every worker that
-- touches protected state queues itself here and pays on PLAYER_REGEN_ENABLED.
--
-- Flags only, never values. The drain re-runs the worker, which recomputes from
-- whatever is true at drain time rather than replaying a stale argument.

local pendingRegen = {}
local regenActions = {}

-- Drained in this order: a restored position lands before the resize around it,
-- and the watch settles before the visibility pass that trusts it.
local REGEN_ORDER = {
    "position", "geometry", "click", "clickShown", "watch", "visibility",
}

local drainInst

drainInst = function(inst)
    local flags = pendingRegen[inst]
    if not flags then return end
    if InCombatLockdown() then
        -- Still in lockdown at drain time. Re-queue for the next edge rather
        -- than run protected work now.
        addon.Events.RunOutOfCombat(function() drainInst(inst) end, inst)
        return
    end
    -- Cleared before the workers run, so a worker's own re-queue starts a fresh
    -- flag set for the next cycle instead of being wiped by this one.
    pendingRegen[inst] = nil
    for _, name in ipairs(REGEN_ORDER) do
        if flags[name] and regenActions[name] then
            regenActions[name](inst)
        end
    end
end

--- Defer one named worker for this instance until combat drops.
function Harness.QueueRegen(inst, what)
    if not inst then return end
    local flags = pendingRegen[inst]
    if not flags then
        flags = {}
        pendingRegen[inst] = flags
    end
    flags[what] = true
    -- Keyed on the instance table, so repeat queues coalesce onto one drain
    -- that pays this instance's flags out in REGEN_ORDER.
    addon.Events.RunOutOfCombat(function() drainInst(inst) end, inst)
end

--- Bind a worker to a regen slot. The painter calls this for its own geometry.
function Harness.RegisterAction(name, fn)
    regenActions[name] = fn
end

--- What is still owed, for the state dump.
function Harness.PendingFlags(inst)
    return pendingRegen[inst]
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

-- RegisterUnitWatch hands show and hide to Blizzard's secure manager, which is
-- the one channel that stays legal in combat for a frame whose visibility is
-- protected by the click child. The player unit always exists, so a player
-- frame never registers; the branch is here because the harness is written to
-- carry other units.
function Harness.ApplyUnitWatch(inst)
    local frame = inst.frame
    if not frame then return end

    local wantWatch = inst.enabled and inst.unit ~= "player"

    if InCombatLockdown() then
        -- Steady state needs nothing. Only a real transition queues.
        if (not wantWatch) == (not inst.watchRegistered)
            and (not wantWatch or inst.watchUnit == inst.unit) then
            return
        end
        Harness.QueueRegen(inst, "watch")
        return
    end

    if wantWatch then
        -- The manager resolves the unit from the watched frame itself, so the
        -- attribute has to be on the frame and not only on the click child.
        frame:SetAttribute("unit", inst.unit)
        RegisterUnitWatch(frame)
        inst.watchRegistered = true
        inst.watchUnit = inst.unit
    elseif inst.watchRegistered then
        UnregisterUnitWatch(frame)
        inst.watchRegistered = nil
        inst.watchUnit = nil
    end
end
regenActions.watch = Harness.ApplyUnitWatch

--- Camelot's own Show/Hide on the outer frame, for the enable transitions and
--- for the always-present player unit. Blocked in lockdown by the click child,
--- so a combat call queues a fresh visibility pass instead of dropping.
function Harness.SetShownSafe(inst, show)
    local frame = inst.frame
    if not frame then return end
    if frame:IsShown() == show then return end
    if InCombatLockdown() then
        Harness.QueueRegen(inst, "visibility")
        return
    end
    if show then frame:Show() else frame:Hide() end
end

function Harness.UpdateVisibility(inst)
    Harness.ApplyUnitWatch(inst)
    if inst.unit == "player" or not inst.watchRegistered then
        Harness.SetShownSafe(inst, inst.enabled and true or false)
    end
end
regenActions.visibility = function(inst) Harness.UpdateVisibility(inst) end

--------------------------------------------------------------------------------
-- The secure click child
--------------------------------------------------------------------------------

-- Click-enabled and motion-disabled, so a click targets the unit while hover
-- falls through to whatever sits under the frame. No mouse button is written
-- here beyond the two Blizzard's own loader sets, so the player's click
-- bindings are consulted first.
function Harness.ApplyClickAttributes(inst)
    local click = inst.clickButton
    if not click then return end
    if InCombatLockdown() then
        Harness.QueueRegen(inst, "click")
        return
    end
    -- Anchored here rather than at creation: SetAllPoints on the protected
    -- button is itself blocked in lockdown, so a frame born in combat pays its
    -- anchors and its attributes together on the drain. Idempotent out of it.
    click:SetAllPoints(inst.frame)
    if SecureUnitButton_OnLoad then
        SecureUnitButton_OnLoad(click, inst.unit)
    else
        click:RegisterForClicks("AnyUp")
        click:SetAttribute("*type1", "target")
        click:SetAttribute("unit", inst.unit)
    end
    -- togglemenu resolves the right unit menu on its own and opens it, so no
    -- menu-function attribute is needed.
    click:SetAttribute("*type2", "togglemenu")
end
regenActions.click = function(inst) Harness.ApplyClickAttributes(inst) end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- def = { unit, frameName, width, height, hitInsets, strataLevel }
--- Returns the instance. The painter fills inst.frame and sets inst.enabled.
function Harness.New(def)
    local inst = {
        unit = def.unit,
        frameName = def.frameName,
        enabled = false,
    }

    -- A plain Frame, not a Button. The outer frame carries no mouse of its own:
    -- unit interactivity belongs to the secure child below, and leaving the
    -- insecure frame out of the hit test keeps the two from competing.
    local frame = CreateFrame("Frame", def.frameName, UIParent)
    frame:SetSize(def.width, def.height)
    local point = def.point or "CENTER"
    frame:SetPoint(point, UIParent, def.relPoint or point, def.x or 0, def.y or 0)
    frame:Hide()

    -- Strata and the mouse setting both go on before the click child exists.
    -- Once that child calls SetAllPoints the frame is protected, and these
    -- become combat-blocked writes on a frame that may already be in a fight.
    -- MEDIUM rather than HIGH, with an explicit level, because a child of
    -- UIParent otherwise lands at the floor of the band.
    addon.Strata.ApplyHUD(frame, def.strataLevel or 10)
    frame:EnableMouse(false)

    inst.frame = frame

    local click = CreateFrame("Button", def.frameName .. "Click", frame, "SecureUnitButtonTemplate")
    click:SetFrameLevel(frame:GetFrameLevel() + 1)
    click:SetMouseMotionEnabled(false)
    -- The insets ride the child, because the child is what holds the mouse. The
    -- vanilla frame puts them on its own button for the same reason: the art is
    -- a good deal smaller than the rect around it.
    if def.hitInsets then
        local h = def.hitInsets
        click:SetHitRectInsets(h.left, h.right, h.top, h.bottom)
    end
    inst.clickButton = click

    Harness.ApplyClickAttributes(inst)

    return inst
end
