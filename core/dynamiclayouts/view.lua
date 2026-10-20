--------------------------------------------------------------------------------
-- core/dynamiclayouts/view.lua
-- The dynamic view of Edit Mode: the state behind the strip and the panel
-- that ui/v2/editmode/DynamicView.lua draws. While the view holds, every
-- participating frame sits in its dynamic state, its selection box writes
-- the dynamic record, and the resolver's answer waits under Edit Mode. Entry
-- and exit play the real transition at the player's speed for that direction,
-- and input is held off for that window. The view ends three ways: Done plays the transition
-- back; Edit Mode closing under it tears down at once and lets the exit
-- resolution decide the state; combat entry ends it inside the engine's
-- regen-disabled handler, where the base snap is still legal, and the
-- engine calls back here to tear the surface down.
--
-- The boxes: a participating frame's selection box is raised into the
-- holds' strata over the holds the drawing side keeps, at its template's
-- level, whatever a click's raise left it at before the view, and with its
-- top-level raise off, so it can be dragged and stays under the edge tabs
-- and the panel; another frame's box goes to alpha 0 with its mouse off,
-- since the library re-shows every box whenever its dialog hides and a Hide
-- would not hold, and an invisible box must not take a click. Both are
-- undone on exit. The drawing side asks for the faded boxes to hold their
-- rects against the mouse.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DL = addon.DynamicLayouts
local EM = addon.EditMode
local Resolver = DL.Resolver

local View = {}
DL.View = View

local OWNER = "dynamicLayoutsView"
-- The holds' strata (ui/v2/editmode/DynamicView.lua holds its levels): the
-- box goes there at its template's level, over the holds and under the edge
-- tabs; the panel stands a strata up. The level is set, not floored: the
-- template is top-level, so a click before the view leaves the box at the
-- top of its strata, and a floor carried that into the view.
local RAISED_STRATA = "DIALOG"
local RAISED_LEVEL = 1000
local LOCK_PAD = 0.1   -- past the tween's duration, so its finish lands first

local active = false
local locked = false
local lockToken = 0
local host = nil       -- the drawing side's handlers: onEnter, onExit, onLock, onParticipation
local raised = setmetatable({}, { __mode = "k" })  -- selection -> { strata, level, toplevel } before the raise
local faded = setmetatable({}, { __mode = "k" })   -- selection -> { mouse } while at alpha 0

local function Store()
    local store = addon.DynamicLayoutsStore
    if type(store) == "table" and type(store.GetRecord) == "function" then return store end
    return nil
end

local function call(name, ...)
    local fn = host and host[name]
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
end

local function hideLibraryDialog()
    if EventRegistry and EventRegistry.TriggerEvent then
        pcall(EventRegistry.TriggerEvent, EventRegistry, "EditModeExternal.hideDialog")
    end
end

local function recolorBoxes()
    local skin = EM.SelectionSkin
    if skin and skin.RefreshAll then skin.RefreshAll() end
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

function View.SetHost(handlers)
    host = handlers
end

function View.IsActive()
    return active
end

function View.IsLocked()
    return locked
end

function View.IsFeatureOn()
    local store = Store()
    return (store and store.IsEnabled and store.IsEnabled()) and true or false
end

-- Lockdown, or combat before lockdown engages: inside the regen-disabled
-- handler the first reads false and the second true, and the strip's button
-- asks from there.
local function inCombat()
    if InCombatLockdown() then return true end
    local ok, fighting = pcall(UnitAffectingCombat, "player")
    return ok and fighting == true
end

--- Out of combat, inside Edit Mode, with the feature on and no view running.
function View.CanEnter()
    return View.IsFeatureOn() and EM.IsEditing() and not active and not locked
        and not inCombat()
end

--- Whether a frame takes part: its group's checkbox, or its own.
function View.IsParticipating(id)
    return DL.IsParticipating(id) and true or false
end

--- Whether a participation key's checkbox is on.
function View.IsKeyParticipating(key)
    local store = Store()
    return (store and store.GetParticipating and store.GetParticipating(key)) and true or false
end

function View.GetTrigger(name)
    local store = Store()
    return (store and store.GetTrigger(name)) and true or false
end

--- The session mask and the profile value together, as the debug verb does.
function View.SetTrigger(name, on)
    on = on and true or false
    if Resolver and Resolver.SetTriggerEnabled then Resolver.SetTriggerEnabled(name, on) end
    DL.PersistTrigger(name, on)
end

--- direction: "in", the transition into the dynamic layout, or "out".
function View.GetSpeed(direction)
    return DL.Speed(direction)
end

function View.SetSpeed(direction, seconds)
    local store = Store()
    local v = tonumber(seconds)
    if not (store and store.SetSpeed and v) then return end
    if v < DL.SPEED_MIN then v = DL.SPEED_MIN end
    if v > DL.SPEED_MAX then v = DL.SPEED_MAX end
    store.SetSpeed(direction, v)
end

--- The delay before a return to the dynamic layout, in seconds.
function View.GetDelay()
    return DL.Delay()
end

function View.SetDelay(seconds)
    local store = Store()
    local v = tonumber(seconds)
    if not (store and store.SetDelay and v) then return end
    if v < DL.DELAY_MIN then v = DL.DELAY_MIN end
    if v > DL.DELAY_MAX then v = DL.DELAY_MAX end
    store.SetDelay(v)
end

--- The target rule: the requirement counts only an NPC the player can attack.
function View.GetTargetAttackableNPCs()
    return DL.TargetAttackableNPCs()
end

function View.SetTargetAttackableNPCs(on)
    local store = Store()
    if not (store and store.SetTargetAttackableNPCs) then return end
    store.SetTargetAttackableNPCs(on and true or false)
    -- The probe reads the rule, so a change outside Edit Mode re-resolves;
    -- inside it the exit's own resolution reads the new value.
    if Resolver and Resolver.Rearm then Resolver.Rearm("TARGET_RULE") end
end

--------------------------------------------------------------------------------
-- Boxes
--------------------------------------------------------------------------------

-- The box's own strata, level and top-level raise are kept for the exit. The
-- raise goes off so a click never lifts the box over the panel or the dialog.
local function raiseBox(selection)
    if raised[selection] then return end
    local level = selection:GetFrameLevel() or 0
    local top = (selection.IsToplevel and selection:IsToplevel()) and true or false
    raised[selection] = {
        strata = selection:GetFrameStrata() or "MEDIUM",
        level = level,
        toplevel = top,
    }
    selection:SetFrameStrata(RAISED_STRATA)
    selection:SetFrameLevel(RAISED_LEVEL)
    if top and selection.SetToplevel then selection:SetToplevel(false) end
end

local function lowerBox(selection)
    local kept = raised[selection]
    if not kept then return end
    raised[selection] = nil
    selection:SetFrameStrata(kept.strata)
    selection:SetFrameLevel(kept.level)
    if kept.toplevel and selection.SetToplevel then selection:SetToplevel(true) end
end

-- The mouse setting is kept with the fade, as the template enables it.
local function fadeBox(selection)
    if faded[selection] then return end
    local mouse = (selection.IsMouseEnabled and selection:IsMouseEnabled()) and true or false
    faded[selection] = { mouse = mouse }
    selection:SetAlpha(0)
    if selection.EnableMouse then selection:EnableMouse(false) end
end

local function unfadeBox(selection)
    local kept = faded[selection]
    if not kept then return end
    faded[selection] = nil
    selection:SetAlpha(1)
    if selection.EnableMouse then selection:EnableMouse(kept.mouse) end
end

local function arrangeBoxes()
    if not EM.ForEachPositionable then return end
    EM.ForEachPositionable(function(frame, selection)
        if not selection then return end
        local id = DL.IdForFrame(frame)
        if id and View.IsParticipating(id) then
            unfadeBox(selection)
            raiseBox(selection)
        else
            lowerBox(selection)
            fadeBox(selection)
        end
    end)
end

local function restoreBoxes()
    if not EM.ForEachPositionable then return end
    EM.ForEachPositionable(function(_, selection)
        if not selection then return end
        lowerBox(selection)
        unfadeBox(selection)
    end)
end

--- The boxes at alpha 0 in the view, for the drawing side's holds.
function View.ForEachFadedBox(fn)
    for selection in pairs(faded) do
        fn(selection)
    end
end

--------------------------------------------------------------------------------
-- The transition lock
--------------------------------------------------------------------------------

local function unlock(token)
    if token ~= lockToken then return end
    locked = false
    call("onLock", false)
end

local function releaseLock()
    lockToken = lockToken + 1
    if locked then
        locked = false
        call("onLock", false)
    end
end

-- `direction` is the transition the lock covers: "in" on entry, "out" on Done.
local function lock(direction)
    lockToken = lockToken + 1
    local token = lockToken
    locked = true
    call("onLock", true)
    C_Timer.After(DL.Speed(direction) + LOCK_PAD, function() unlock(token) end)
end

--------------------------------------------------------------------------------
-- Entry and exit
--------------------------------------------------------------------------------

-- The common teardown: the flag the positionable seams read, the boxes, the
-- palette, then the drawing side.
local function finish(reason)
    active = false
    if EM.SetDynamicView then EM.SetDynamicView(false) end
    restoreBoxes()
    recolorBoxes()
    call("onExit", reason)
end

--- Called back by the engine when it ends the view itself, at combat entry.
--- The engine has already cleared its flag and landed every frame at base.
function View.End(reason)
    if not active then return end
    releaseLock()
    finish(reason or "combat")
end

function View.Enter()
    if not View.CanEnter() then return false end
    active = true
    hideLibraryDialog()
    if EM.SetDynamicView then EM.SetDynamicView(true) end
    arrangeBoxes()
    -- The drawing side builds its shield on the first entry, so it goes
    -- before the lock that raises it.
    call("onEnter")
    lock("in")
    DL.SetView(true, nil, View.End)
    recolorBoxes()
    return true
end

--- The Done button: the transition back, under the lock.
function View.Exit()
    if not active then return end
    hideLibraryDialog()
    lock("out")
    DL.SetView(false, "tween")
    finish("done")
end

--- A group of frames joins or leaves the dynamic layout from the panel's
--- checkbox. Their boxes show or fade with it, and each frame tweens to the
--- state it now has.
function View.SetParticipating(key, on)
    if not (Store() and active) then return end
    on = on and true or false
    DL.SetParticipating(key, on)
    if not on then hideLibraryDialog() end
    arrangeBoxes()
    call("onParticipation", key, on)
end

--- A record write from the dialog that the drawing side shows off the frame
--- (the off-screen tabs).
function View.NotifyRecord(id)
    call("onRecord", id)
end

-- Edit Mode closing under the view: no transition of the view's own. The
-- engine's flag clears and one refresh lands after the resolver's exit
-- resolution, so the frames make one motion to whatever the triggers say.
EM.OnEditMode(OWNER, {
    exit = function()
        if not active then return end
        releaseLock()
        DL.SetView(false, "defer")
        finish("editmode")
    end,
})
