--------------------------------------------------------------------------------
-- forever/gamepad.lua
-- Forever's gamepad UI, as the rest of Camelot reads it.
--
-- The client draws a second interface for a controller (Blizzard_Gamepad and
-- Blizzard_GamepadActionBars, an alpha). Every Edit Mode layout carries an
-- interfaceStyle, Mkb or Gamepad; the Gamepad preset is the one preset of the
-- gamepad style, and the Edit Mode dropdown offers a layout only for the
-- current style. The options checkbox that switches the style reloads the UI,
-- so a session has one style. Camelot asks one question of all this,
-- IsActive: the active layout is a gamepad layout, or the gamepad UI is on.
-- On a transition inside a session, which the client may raise on its own,
-- the two flip in an order no Lua fixes, so either one answers yes.
--
-- The active layout is read off C_EditMode.GetLayouts() and the preset
-- manager, never off EditModeManagerFrame: a method call on that frame taints
-- every registered system frame (core/profiles/core.lua). Every Blizzard name
-- is tested bare, because this file loads on retail through the junction too
-- and answers no there.
--------------------------------------------------------------------------------

local _, addon = ...

local Gamepad = {}
addon.Gamepad = Gamepad

local OWNER = "Gamepad"
local EVENT = "INPUT_DEVICE_INTERFACE_TRANSITION"

local function styleEnum()
    return Enum and Enum.InputDeviceInterfaceType or nil
end

--- "gamepad" or "mkb" for a layout info table; nil on a client with no
--- interface styles. A layout with no field is Mkb, as Blizzard reads it.
function Gamepad.LayoutStyle(info)
    local styles = styleEnum()
    if not styles then return nil end
    local style = type(info) == "table" and info.interfaceStyle or nil
    if style ~= nil and style == styles.Gamepad then return "gamepad" end
    return "mkb"
end

local function presetLayouts()
    local manager = EditModePresetLayoutManager
    local ok, layouts = pcall(function() return manager:GetCopyOfPresetLayouts() end)
    return ok and type(layouts) == "table" and layouts or {}
end

local function presetOffset()
    local fn = addon.Profiles and addon.Profiles._presetLayoutOffset
    if fn then return fn() end
    local meta = Enum and Enum.EditModePresetLayoutsMeta
    return (meta and meta.NumValues) or 2
end

--- The active layout's info table, from the presets-prepended list the
--- manager indexes: a preset from the preset manager, a saved layout from
--- C_EditMode.GetLayouts(). nil when neither is readable.
function Gamepad.ActiveLayoutInfo()
    if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
    local ok, info = pcall(C_EditMode.GetLayouts)
    local index = ok and type(info) == "table" and tonumber(info.activeLayout) or nil
    if not index then return nil end
    local offset = presetOffset()
    if index <= offset then
        return presetLayouts()[index]
    end
    local layouts = type(info.layouts) == "table" and info.layouts or nil
    return layouts and layouts[index - offset] or nil
end

--- True while the active layout is a gamepad layout.
function Gamepad.IsLayoutActive()
    return Gamepad.LayoutStyle(Gamepad.ActiveLayoutInfo()) == "gamepad"
end

--- True while the client draws its gamepad UI. Forever only; false elsewhere.
function Gamepad.IsUIEnabled()
    if InputUtil and InputUtil.IsGamepadUIEnabled then
        return InputUtil.IsGamepadUIEnabled() and true or false
    end
    return false
end

--- The one question a feature asks: a gamepad layout is in use.
function Gamepad.IsActive()
    return Gamepad.IsLayoutActive() or Gamepad.IsUIEnabled()
end

-- A preset's style by its client name, matched without case, remembered
-- once the preset list has been read: DB.StartingPoint reads it per
-- positionable, and the list is a copy of three layouts of fifty systems on
-- each call. The list is fixed for the session.
local presetStyles = {}

function Gamepad.PresetStyle(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    local cached = presetStyles[key]
    if cached ~= nil then return cached or nil end
    local layouts = presetLayouts()
    local style = false
    for _, layout in ipairs(layouts) do
        if type(layout.layoutName) == "string" and layout.layoutName:lower() == key then
            style = Gamepad.LayoutStyle(layout) or false
            break
        end
    end
    if #layouts > 0 then presetStyles[key] = style end
    return style or nil
end

--- True for the client preset of the gamepad style, by name. The preset is
--- known by its style, never by its name: a preset's name is a localized
--- string the client owns.
function Gamepad.IsPresetGamepad(name)
    return Gamepad.PresetStyle(name) == "gamepad"
end

--------------------------------------------------------------------------------
-- Transitions
--------------------------------------------------------------------------------
-- The options switch is a reload and never reaches this event; it is the
-- in-session transition the client may raise on its own. The layout switch
-- that comes with one reaches a feature through the profile engine's apply
-- steps; this is the other edge, the UI itself.

local lastTransition

local function styleName(value)
    local styles = styleEnum()
    if styles and value ~= nil then
        for name, id in pairs(styles) do
            if id == value then return name end
        end
    end
    return tostring(value)
end

--- fn(active, newType, oldType) on every interface transition. The handle
--- is the events module's, dead on a client without the event.
function Gamepad.OnChange(owner, fn)
    return addon.Events.On(owner, EVENT, function(_, newType, oldType)
        fn(Gamepad.IsActive(), newType, oldType)
    end)
end

local handle = addon.Events.On(OWNER, EVENT, function(_, newType, oldType)
    lastTransition = { new = newType, old = oldType, at = GetTime() }
end)

--------------------------------------------------------------------------------
-- The gamepad managers' state
--------------------------------------------------------------------------------
-- Every panel close under the gamepad UI runs through the frame controls
-- manager and the binding stack into SetPreferredGamepadInteractTarget, a
-- protected call. A field marked tainted here was last written on an
-- addon's path, and the next Blizzard close that reads it is forbidden with
-- no addon in the stack. Reads only.

local function mark(t, key)
    if type(t) ~= "table" then return "absent" end
    local ok, secure, by = pcall(issecurevariable, t, key)
    if not ok then return "unreadable" end
    if secure then return "secure" end
    return "tainted by " .. tostring(by)
end

local function nameOf(f)
    if type(f) ~= "table" then return tostring(f) end
    local ok, name = pcall(function() return f:GetName() end)
    if ok and name then return name end
    return tostring(f.name or f.DisplayName or "unnamed")
end

--- Lines for /camelot gamepad: the frame controls manager, the binding
--- stack and the gamepad action bar's page unit, each field's security.
function Gamepad.ReportManagers(push)
    local fcm = GamepadMode and GamepadMode.FrameControlsManager
    push("Frame controls manager: %s", fcm and "present" or "absent")
    if fcm then
        for _, key in ipairs({ "isUIFocused", "focusedFrame", "topSuspendedFrame", "shownFrames",
            "isPopupFrame", "gamepadBindings" }) do
            push("  %-18s %s", key, mark(fcm, key))
        end
        push("  UI focused %s, focused frame %s", tostring(fcm.isUIFocused), nameOf(fcm.focusedFrame))
        for i, f in ipairs(fcm.shownFrames or {}) do
            push("  shown %d  %s", i, nameOf(f))
        end
    end

    local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    push("Binding manager: %s", manager and "present" or "absent")
    if manager then
        for _, key in ipairs({ "currentCoreBindingActive", "assumeCoreBindingsUsable", "bindingSetStack",
            "coreSet", "coreBindingListenerFunctions" }) do
            push("  %-28s %s", key, mark(manager, key))
        end
        push("  core active %s", tostring(manager.currentCoreBindingActive))
        for i, set in ipairs(manager.bindingSetStack or {}) do
            push("  stack %d  %-40s core %-5s (%s)", i, tostring(set.name), tostring(set.treatBindsAsCore),
                mark(set, "treatBindsAsCore"))
        end
    end

    local unit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
    push("Gamepad action bar page unit: %s", unit and "present" or "absent")
    if unit then
        push("  %-18s %s", "activeBar", mark(unit, "activeBar"))
        local names = {}
        for name in pairs(unit.actionBars or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local bar = unit.actionBars[name]
            push("  %-22s actionBarScaledUp %s, IsActionBarUsable %s", name,
                mark(bar, "actionBarScaledUp"), mark(bar, "IsActionBarUsable"))
        end
    end
end

--------------------------------------------------------------------------------
-- /camelot gamepad
--------------------------------------------------------------------------------

addon:RegisterSlashCommand({
    name = "gamepad",
    help = "the gamepad UI and every layout's interface style, as Camelot reads them",
    handler = function()
        local lines, push = addon.DebugLines()
        local styles = styleEnum()
        push("Interface styles: %s", styles and "present" or "absent: this client has no gamepad UI")
        local current = InputUtil and InputUtil.GetCurrentInterfaceStyle and InputUtil.GetCurrentInterfaceStyle()
        push("Current style: %s", styleName(current))
        push("Gamepad UI enabled: %s", tostring(Gamepad.IsUIEnabled()))
        push("Gamepad layout active: %s", tostring(Gamepad.IsLayoutActive()))
        push("IsActive: %s", tostring(Gamepad.IsActive()))
        push("")

        local ok, info = pcall(function() return C_EditMode.GetLayouts() end)
        info = ok and type(info) == "table" and info or nil
        local offset = presetOffset()
        local active = Gamepad.ActiveLayoutInfo()
        push("Active layout: index %s, %s, style %s", tostring(info and info.activeLayout),
            tostring(active and active.layoutName), tostring(Gamepad.LayoutStyle(active)))
        push("Presets (%d before the saved layouts):", offset)
        for i, layout in ipairs(presetLayouts()) do
            push("  %d  %s  interfaceStyle %s (%s)", i, tostring(layout.layoutName),
                tostring(layout.interfaceStyle), tostring(Gamepad.LayoutStyle(layout)))
        end
        push("Saved layouts:")
        for i, layout in ipairs(info and info.layouts or {}) do
            push("  %d  %s  interfaceStyle %s (%s)", i + offset, tostring(layout.layoutName),
                tostring(layout.interfaceStyle), tostring(Gamepad.LayoutStyle(layout)))
        end
        push("")

        local DB = addon.DB
        local start = DB and DB.StartingPoint and DB.StartingPoint() or "?"
        push("Profile start: %s, reads set %s", tostring(start),
            tostring(DB and DB.PresetSet and DB.PresetSet(start) or "camelot"))
        push("Transition event: %s", handle:IsActive() and "subscribed" or "not on this client")
        if lastTransition then
            push("Last transition: %s from %s, %.1f s ago", styleName(lastTransition.new),
                styleName(lastTransition.old), GetTime() - lastTransition.at)
        else
            push("Last transition: none this session")
        end
        push("")
        Gamepad.ReportManagers(push)
        addon.DebugShowWindow("Camelot gamepad", lines)
    end,
})
