--------------------------------------------------------------------------------
-- core/dynamiclayouts/view.lua
-- The dynamic view of Edit Mode: the state behind the strip and the panel
-- that ui/v2/editmode/DynamicView.lua draws. While the view holds, every
-- participating frame sits in its dynamic state, its selection box writes
-- the dynamic record, and the resolver's answer waits under Edit Mode. Entry
-- and exit play the real transition at the player's speed, and input is held
-- off for that window. The view ends three ways: Done plays the transition
-- back; Edit Mode closing under it tears down at once and lets the exit
-- resolution decide the state; combat entry ends it inside the engine's
-- regen-disabled handler, where the base snap is still legal, and the
-- engine calls back here to tear the surface down.
--
-- The boxes: a participating frame's selection box is raised into the
-- shield's strata over the shield the drawing side holds, at its template's
-- level and with its top-level raise off, so it can be dragged and stays
-- under the panel; another frame's box goes to alpha 0, since the library
-- re-shows every box whenever its dialog hides and a Hide would not hold.
-- Both are undone on exit.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DL = addon.DynamicLayouts
local EM = addon.EditMode
local Resolver = DL.Resolver

local View = {}
DL.View = View

local OWNER = "dynamicLayoutsView"
-- The shield's strata (ui/v2/editmode/DynamicView.lua holds its levels): the
-- box goes there at no less than its template's level, which stands over the
-- shield's hold and under the panel.
local RAISED_STRATA = "DIALOG"
local RAISED_LEVEL = 1000
local LOCK_PAD = 0.1   -- past the tween's duration, so its finish lands first

local active = false
local locked = false
local lockToken = 0
local host = nil       -- the drawing side's handlers: onEnter, onExit, onLock, onParticipation
local raised = setmetatable({}, { __mode = "k" })  -- selection -> { strata, level, toplevel } before the raise
local faded = setmetatable({}, { __mode = "k" })   -- selection -> true while at alpha 0

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

function View.IsParticipating(id)
    local store = Store()
    local rec = store and store.GetRecord(id)
    return (rec and rec.enabled) and true or false
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

function View.GetSpeed()
    return DL.Speed()
end

function View.SetSpeed(seconds)
    local store = Store()
    local v = tonumber(seconds)
    if not (store and store.SetSpeed and v) then return end
    if v < DL.SPEED_MIN then v = DL.SPEED_MIN end
    if v > DL.SPEED_MAX then v = DL.SPEED_MAX end
    store.SetSpeed(v)
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
    if level < RAISED_LEVEL then selection:SetFrameLevel(RAISED_LEVEL) end
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

local function arrangeBoxes()
    if not EM.ForEachPositionable then return end
    EM.ForEachPositionable(function(frame, selection)
        if not selection then return end
        local id = DL.IdForFrame(frame)
        if id and View.IsParticipating(id) then
            if faded[selection] then
                faded[selection] = nil
                selection:SetAlpha(1)
            end
            raiseBox(selection)
        else
            lowerBox(selection)
            if not faded[selection] then
                faded[selection] = true
                selection:SetAlpha(0)
            end
        end
    end)
end

local function restoreBoxes()
    if not EM.ForEachPositionable then return end
    EM.ForEachPositionable(function(_, selection)
        if not selection then return end
        lowerBox(selection)
        if faded[selection] then
            faded[selection] = nil
            selection:SetAlpha(1)
        end
    end)
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

local function lock()
    lockToken = lockToken + 1
    local token = lockToken
    locked = true
    call("onLock", true)
    C_Timer.After(DL.Speed() + LOCK_PAD, function() unlock(token) end)
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
    lock()
    DL.SetView(true, nil, View.End)
    recolorBoxes()
    return true
end

--- The Done button: the transition back, under the lock.
function View.Exit()
    if not active then return end
    hideLibraryDialog()
    lock()
    DL.SetView(false, "tween")
    finish("done")
end

--- A frame joins or leaves the dynamic layout from the panel's checkbox. Its
--- box shows or fades with it, and the frame tweens to the state it now has.
function View.SetParticipating(id, on)
    local store = Store()
    if not (store and active) then return end
    on = on and true or false
    store.SetRecord(id, { enabled = on })
    if not on then hideLibraryDialog() end
    arrangeBoxes()
    DL.Refresh(id, "tween")
    call("onParticipation", id, on)
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
