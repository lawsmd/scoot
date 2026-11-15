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
-- (settings.lua, Settings.ATTACH: the target of target off the target) and
-- holds no spot of its own: a drop
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
-- The legacy attach
--------------------------------------------------------------------------------
-- Until 4 November 2026 the target hung off the player frame (settings.lua,
-- Settings.LEGACY_ATTACH). A profile whose switch still reads on gets the
-- spot that anchor gave the target written out as the target's own position,
-- once, so a target that followed a dragged or scaled player frame stays
-- where it stood. The spot is worked out from the stored records and the two
-- base scales, never from the frames on screen: Dynamic Layouts may hold
-- either frame somewhere else at the time. A profile with nothing stored for
-- either frame, both scales at 1 and no offset needs nothing written: the
-- target's own default is that spot.

local CARRIED_PATH = "unitFrames.legacyAttachCarried"

local function round2(n)
    return math.floor(n * 100 + 0.5) / 100
end

--- The record the legacy anchor resolves to for one frame, written to the
--- store, or nil when there is nothing to carry or it cannot be worked out
--- yet. Sets the profile's flag once every legacy row is settled.
local function carryLegacyAttach(inst, layoutName)
    local a = inst and Settings.LEGACY_ATTACH[inst.key]
    if not a or DB.Get(CARRIED_PATH) == true then return nil end
    if not layoutName then return nil end

    local key = inst.key
    local carried
    if DB.Get(Settings.AttachPath(key, "attach")) == true and UF.IsEnabled(a.to) then
        local host = UF.Frames[a.to]
        -- The host builds first (UF.ORDER); until it has, wait for a later restore.
        if not (host and host.spec and host.def) then return nil end

        local hostRecord = store.get(a.to, layoutName)
        local ax, ay = UF.AttachOffsets(key)
        local hostScale, scale = UF.GetScale(a.to), UF.GetScale(key)
        if hostRecord or store.get(key, layoutName)
            or hostScale ~= 1 or scale ~= 1 or ax ~= 0 or ay ~= 0 then
            hostRecord = hostRecord or host.def.default
            local f = addon.EditMode.AnchorFraction(hostRecord.point)
            local W, H = UIParent:GetSize()
            local hw, hh = host.spec.width, host.spec.height
            local w, h = inst.spec.width, inst.spec.height
            if f and W and H and hw and hh and w and h then
                -- The host's centre from the screen centre, in UI units
                -- (core/editmode/positionables.lua, centerFromRecord).
                local hcx = (hostRecord.x or 0) * hostScale + (f[1] - 0.5) * (W - hw * hostScale)
                local hcy = (hostRecord.y or 0) * hostScale + (f[2] - 0.5) * (H - hh * hostScale)
                -- The frame's LEFT on the host's RIGHT, offsets in its own units.
                local cx = hcx + hw * hostScale / 2 + ax * scale + w * scale / 2
                local cy = hcy + ay * scale
                carried = {
                    point = hostRecord.point,
                    x = round2((cx - (f[1] - 0.5) * (W - w * scale)) / scale),
                    y = round2((cy - (f[2] - 0.5) * (H - h * scale)) / scale),
                }
                store.set(key, layoutName, carried.point, carried.x, carried.y)
            end
        end
    end
    DB.Set(CARRIED_PATH, true)
    return carried
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
        -- The one-time carry of the target's old attach: the restore lands
        -- the record it writes.
        if reason == "restore" and Settings.LEGACY_ATTACH[inst.key] then
            local carried = carryLegacyAttach(inst, addon.EditMode.GetActiveLayoutName())
            if carried then point, x, y = carried.point, carried.x, carried.y end
        end
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

--- The carry's second chance, at the end of a UF.ApplyAll pass: a restore
--- that ran before the host was built, or before a layout was active, left
--- the carry owed, and this restore settles it.
function EditMode.SettleLegacyAttach()
    if DB.Get(CARRIED_PATH) == true then return end
    for key in pairs(Settings.LEGACY_ATTACH) do
        local inst = UF.Frames[key]
        if inst then addon.EditMode.RestorePositionable(inst.frame) end
    end
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

-- A style swap retires the frame the dialog is open on and shows the other
-- style's instance in its place, so the selection moves to the new frame:
-- the old box goes back to highlighted, and the new one takes the click the
-- library selects a frame with. A frame later, once the pass has shown it.
local function reselect(key, oldFrame)
    C_Timer.After(0, function()
        if not addon.EditMode.IsEditing() or InCombatLockdown() then return end
        local inst = UF.Frames[key]
        if not (inst and inst.frame and inst.frame ~= oldFrame) then return end
        local old = oldFrame and oldFrame.camelotEditModeSelection
        if old and old.isSelected and old.ShowHighlighted then old:ShowHighlighted() end
        local sel = inst.frame.camelotEditModeSelection
        local click = sel and sel:IsVisible() and sel:GetScript("OnMouseDown")
        if click then click(sel, "LeftButton") end
    end)
end

-- The rows every frame carries, before its own: the style it draws, its
-- size, and the portrait, the three a player judges by looking at the frame.
-- Each is the page's own write (page.lua), so the two cannot drift.
local function frameRows(frame, key)
    local hiddenPath = Settings.PortraitPath(key, "hidden")
    local specs = {
        {
            kind = "selector", label = "Style",
            values = UF.STYLES, order = UF.STYLE_ORDER,
            get = function() return UF.StyleOf(key) end,
            set = function(v)
                if UF.StyleOf(key) == v then return end
                UF.SetStyle(key, v)
                reselect(key, frame)
            end,
        },
        {
            kind = "slider", label = "Scale",
            min = UF.SCALE_MIN * 100, max = UF.SCALE_MAX * 100, step = 5, precision = 0,
            get = function() return math.floor(UF.GetScale(key) * 100 + 0.5) end,
            set = function(v) UF.SetScale(key, (tonumber(v) or 100) / 100) end,
        },
        {
            -- The portrait key carries the style's prefix, so the row reads
            -- the style on screen.
            kind = "toggle", label = "Hide Portrait",
            get = function() return Settings.Portrait(key, "hidden") == true end,
            set = function(v)
                DB.Set(hiddenPath, v and true or false)
                UF.RefreshPortrait(key)
            end,
        },
    }
    if Settings.COMBO_POINTS[key] then
        specs[#specs + 1] = {
            kind = "toggle", label = "Combo Points",
            get = function() return UF.ShowComboPoints(key) end,
            set = function(v) UF.SetComboPoints(key, v) end,
        }
    end
    if Settings.HIDE_WHEN_SELF[key] then
        specs[#specs + 1] = {
            kind = "toggle", label = "Hide When Self",
            get = function() return UF.HideWhenSelf(key) end,
            set = function(v) UF.SetHideWhenSelf(key, v) end,
        }
    end
    return specs
end

function EditMode.Mirror(frame)
    local inst = instByFrame[frame]
    if not inst then return nil end
    local key = inst.key

    local specs = frameRows(frame, key)
    local a = Settings.ATTACH[key]
    if not a then return specs end

    specs[#specs + 1] = {
        kind = "toggle", label = a.short, rebuild = true,
        get = function() return UF.IsAttachOn(key) end,
        set = function(v) UF.SetAttach(key, v) end,
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

    inst.frame.camelotEditModeSelection = addon.EditMode.RegisterPositionable(inst.frame, {
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
