--------------------------------------------------------------------------------
-- forever/unitframes/editmode.lua
-- The host side of addon.EditMode.RegisterPositionable for Camelot's unit
-- frames: where a position is stored, how it is applied around combat, the
-- attach that hangs one frame off another in place of a position, the
-- dialog's rows, and which settings page the dialog's Configure button
-- opens. The engine is core/editmode/positionables.lua and ui/v2/editmode/,
-- shared with Scoot.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local Harness = UF.Harness
local Settings = UF.Settings
local DB = addon.DB

local EditMode = {}
UF.EditMode = EditMode

-- unit key -> settings page key (forever/menu.lua)
local NAV_KEYS = UF.Text.NAV_KEYS

local instByFrame = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- Store
--------------------------------------------------------------------------------
-- One layout entry per frame, with a position per Edit Mode layout inside it:
-- layout[key] = { scale, positions = { [layoutName] = { point, x, y } } }

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}

--------------------------------------------------------------------------------
-- Attach
--------------------------------------------------------------------------------
-- A frame with its attach on hangs off the frame its descriptor names
-- (settings.lua, Settings.ATTACH) and holds no spot of its own: a drop
-- springs back, the dialog's position row is absent, and the stored free
-- position waits for the setting to go off. The anchor is live, so the frame
-- follows its host through a drag and a scale change with no position math.
-- The dynamic layout ignores the attach (dynamic.lua): there the frame keeps
-- a place of its own and its host's slide leaves it. The host has to be on screen: with it
-- disabled the frame falls back to its own position, and comes back when
-- the host does, since UF.ApplyAll re-lands every attached frame at the end
-- of each pass.

--- The frame a key hangs off right now, with its descriptor; nil while the
--- setting is off or the host is not up.
local function attachHost(key)
    local a = Settings.ATTACH[key]
    if not (a and UF.IsAttachOn(key)) then return nil end
    local host = UF.Frames[a.to]
    if not (host and host.enabled and host.frame) then return nil end
    return host.frame, a
end

--- Whether the frame for a key is anchored to its host rather than placed.
function EditMode.IsAttached(key)
    return attachHost(key) ~= nil
end

-- The dialog's title and the tooltip read the name lazily, so it can say
-- which frame is not for dragging.
local function refreshName(inst)
    local label = inst.editModeLabel or inst.key
    if EditMode.IsAttached(inst.key) then label = label .. " (attached)" end
    inst.frame.editModeName = label
end

local function applyAttach(inst)
    local host, a = attachHost(inst.key)
    if not host then return false end
    local x, y = UF.AttachOffsets(inst.key)
    inst.frame:ClearAllPoints()
    inst.frame:SetPoint(a.point, host, a.relPoint, x, y)
    return true
end

--- The attach as the Dynamic Layouts adapter's `attach` answers it: the host
--- frame, the two points and the offsets in UI units at the frame's regular
--- scale. nil while the frame is placed by its position.
function EditMode.AttachSpec(key)
    local host, a = attachHost(key)
    if not host then return nil end
    local x, y = UF.AttachOffsets(key)
    local s = UF.GetScale(key) or 1
    return host, a.point, a.relPoint, x * s, y * s
end

--- Hang the frame on screen for a key back off its host; the adapter's
--- `reattach`, when the frame lands at base from a dynamic spot.
function EditMode.Reattach(key)
    local inst = UF.Frames[key]
    if inst then applyAttach(inst) end
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------
-- The secure click child makes the frame anchor-protected, so a move in combat
-- is blocked. A drop cannot happen in combat (the library refuses the drag); a
-- restore can, on a reload or a layout switch. That one queues the harness's
-- position slot, whose worker re-reads the store when combat drops.

-- A restore lands the base position; if Dynamic Layouts holds the dynamic
-- state, it puts its own position and scale back on top. Only the active
-- instance of a unit asks: both styles' frames restore from one store, and
-- the parked one must not re-snap the one on screen.
local function reassert(inst, reason)
    if reason ~= "restore" then return end
    local DL = addon.DynamicLayouts
    if DL and DL.Reassert and inst and UF.Frames[inst.key] == inst then
        DL.Reassert(inst.key)
    end
end

local function ApplyPosition(frame, point, x, y, reason)
    local inst = instByFrame[frame]
    if InCombatLockdown() then
        Harness.QueueRegen(inst, "position")
        return true
    end
    if inst then
        refreshName(inst)
        -- An attached frame takes its host's anchor in place of the position.
        -- On a drop the true return also skips the persist, so the stored
        -- free spot keeps for the day the setting goes off.
        if applyAttach(inst) then
            reassert(inst, reason)
            return true
        end
    end
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
    reassert(inst, reason)
    return false
end

Harness.RegisterAction("position", function(inst)
    if inst and inst.frame then
        addon.EditMode.RestorePositionable(inst.frame)
    end
end)

--- Re-land one frame after its attach setting or an offset changed: the
--- positionable restore applies the anchor or the free position, and a
--- dynamic state held by Dynamic Layouts goes back on top.
function EditMode.ApplyAttach(key)
    local inst = UF.Frames[key]
    if not inst then return end
    addon.EditMode.RestorePositionable(inst.frame)
end

--- Every frame with an attach, at the end of a UF.ApplyAll pass: a host
--- swapped, enabled or disabled by the pass changes what the anchor lands
--- on, or whether it lands at all.
function EditMode.ReapplyAttached()
    for key in pairs(Settings.ATTACH) do
        if UF.Frames[key] then EditMode.ApplyAttach(key) end
    end
end

--------------------------------------------------------------------------------
-- The dialog
--------------------------------------------------------------------------------
-- The rows under the position row for a frame with an attach: the switch,
-- and while it is on the two offsets. Short labels; the dialog has no room
-- for descriptions. The switch changes the shape of the list (the position
-- row goes, the offsets come), so it rebuilds the slot.

local OFFSET = Settings.ATTACH_OFFSET_RANGE

function EditMode.Mirror(frame)
    local inst = instByFrame[frame]
    local a = inst and Settings.ATTACH[inst.key]
    if not a then return nil end
    local key = inst.key

    local specs = {
        {
            kind = "toggle", label = a.short, rebuild = true,
            get = function() return UF.IsAttachOn(key) end,
            set = function(v) UF.SetAttach(key, v) end,
        },
    }
    if UF.IsAttachOn(key) then
        specs[#specs + 1] = {
            kind = "slider", label = "Offset X", min = -OFFSET, max = OFFSET, step = 1, precision = 0,
            get = function() return (UF.AttachOffsets(key)) end,
            set = function(v) UF.SetAttachOffset(key, "x", v) end,
        }
        specs[#specs + 1] = {
            kind = "slider", label = "Offset Y", min = -OFFSET, max = OFFSET, step = 1, precision = 0,
            get = function() return select(2, UF.AttachOffsets(key)) end,
            set = function(v) UF.SetAttachOffset(key, "y", v) end,
        }
    end
    return specs
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

--- Register one built unit frame. `default` is kept by reference: it is what
--- Reset To Default Position returns the frame to.
function EditMode.Register(inst, opts)
    if not (inst and inst.frame) then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end

    local navKey = NAV_KEYS[opts.key]
    instByFrame[inst.frame] = inst
    inst.editModeLabel = opts.label
    refreshName(inst)

    addon.EditMode.RegisterPositionable(inst.frame, {
        key = opts.key,
        default = opts.default,
        restoreDefault = true,
        store = store,
        apply = ApplyPosition,
        -- The X/Y row stands only for a frame placed by its position.
        positionEditable = function() return not EditMode.IsAttached(opts.key) end,
        brand = { navKey = navKey, componentId = navKey, mirror = EditMode.Mirror },
    })
end
