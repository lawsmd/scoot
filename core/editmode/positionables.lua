--------------------------------------------------------------------------------
-- positionables.lua
-- Scoot-owned frames in Edit Mode (refactor #30)
-- One registration for a frame LibEditMode can drag: AddFrame, the drop
-- callback that persists the resolved anchor per layout, the restore on every
-- layout switch, the branding, and one enter/exit dispatch. Each component
-- keeps its own storage behind a store adapter, so the seven stores keep the
-- shapes they have; only the code around them is shared.
--
-- RegisterPositionable(frame, {
--     key            = value | function(frame) -> key | nil   nil: skip save and restore
--     default        = { point, x, y }       a table; LibEditMode keeps it for Reset Position
--     store          = { get = function(key, layoutName) -> pos | nil,
--                        set = function(key, layoutName, point, x, y) }
--     apply          = function(frame, point, x, y, reason) -> handled
--                      optional; reason is "drop" or "restore"; the default is
--                      ClearAllPoints + SetPoint(point, x, y); returning true on
--                      "drop" skips the persist (a snapped Cast Bar Z bar)
--     restoreDefault = boolean               apply `default` when nothing is stored
--     positionEditable = function(frame) -> boolean
--                      optional; the dialog's X/Y position row renders only
--                      while this returns true (a snapped Cast Bar Z bar)
--     brand          = table                 Brand:Register(frame, brand) options
-- })
-- Returns the LibEditMode selection frame, nil without the library. A repeat
-- call for the same frame is a no-op that returns the existing selection.
--
-- Design notes (emcustomframes.md):
--   * The stored anchor is the one GetPoint(1) reports after the drop, never the
--     requested one: LibEditMode's normalizePosition picks the point per screen
--     quadrant, so storing the requested point drifts the frame on reload.
--   * LibEditMode applies nothing at AddFrame. A "layout" registration fires at
--     once when a layout is active, so the first registration restores every
--     entry through that, and later ones restore themselves.
--   * Every restore and every enter/exit handler runs under securecallfunction,
--     as the library runs its own callbacks: one throwing component never
--     stops the others.
--   * brand.mirror is composed here: every registration's dialog list starts
--     with the shared X/Y position row, then the component's own entries.
--------------------------------------------------------------------------------

local addonName, addon = ...

local EM = addon.EditMode
local SS = addon.SecretSafe

local function GetLib()
    return LibStub and LibStub("LibEditMode", true)
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Weak keys so a released frame never pins its entry; `order` keeps restores
-- and the debug dump deterministic (the Registry.lua pattern).
local registry = setmetatable({}, { __mode = "k" })
local order = {}

local listeners = {}          -- array of { owner, enter, exit }, first-registration order
local listenerByOwner = {}
local hooked = {}             -- event name -> true once registered with the library

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

local function resolveKey(entry, frame)
    local key = entry.key
    if type(key) == "function" then
        return key(frame)
    end
    return key
end

local function defaultApply(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, x, y)
end

local function applyPosition(entry, frame, point, x, y, reason)
    local apply = entry.apply or defaultApply
    return apply(frame, point, x, y, reason)
end

local function restore(entry, frame, layoutName)
    if not layoutName then return end
    local key = resolveKey(entry, frame)
    if key == nil then return end
    local pos = entry.store.get(key, layoutName)
    if pos and pos.point then
        applyPosition(entry, frame, pos.point, pos.x or 0, pos.y or 0, "restore")
    elseif entry.restoreDefault then
        local d = entry.default
        applyPosition(entry, frame, d.point, d.x, d.y, "restore")
    end
end

-- Called by the library on drag-stop, nudge, and Reset Position, always with a
-- point (both TriggerCallback paths compute one). Apply first, then persist
-- what the frame resolved to.
local function onDrop(frame, layoutName, point, x, y)
    local entry = registry[frame]
    if not entry then return end
    if not (point and x and y) then return end
    if applyPosition(entry, frame, point, x, y, "drop") then return end

    local key = resolveKey(entry, frame)
    if not layoutName or key == nil then return end
    local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
    if savedPoint then
        entry.store.set(key, layoutName, savedPoint, savedX, savedY)
    else
        entry.store.set(key, layoutName, point, x, y)
    end
end

local function onLayout(layoutName)
    for _, frame in ipairs(order) do
        local entry = registry[frame]
        if entry then
            securecallfunction(restore, entry, frame, layoutName)
        end
    end
end

--------------------------------------------------------------------------------
-- Position row
--------------------------------------------------------------------------------
-- The X/Y boxes on the branded dialog: the frame's center relative to the
-- screen center, in UI units, so (0, 0) is dead center. The resting readout
-- derives from the STORED record, so it echoes what was typed and what the
-- next login restores; live geometry is read only mid-drag. A typed pair becomes a NudgeFrame delta against the
-- live center, computed at commit: an absolute set, with no cached value to
-- drift.

-- Anchor points as rect fractions: LEFT 0 / CENTER 0.5 / RIGHT 1 across,
-- BOTTOM 0 / CENTER 0.5 / TOP 1 up. With them the conversion
--     centerX = x*s + (fx - 0.5) * (W - w*s)
-- is exact for every point, so the readout never depends on which anchor
-- normalizePosition picked on the last drop.
local ANCHOR_FRACTIONS = {
    TOPLEFT    = { 0, 1 },     TOP    = { 0.5, 1 },     TOPRIGHT    = { 1, 1 },
    LEFT       = { 0, 0.5 },   CENTER = { 0.5, 0.5 },   RIGHT       = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 },     BOTTOM = { 0.5, 0 },     BOTTOMRIGHT = { 1, 0 },
}

-- Geometry reads screened like describeLive below: a secret or a missing rect
-- comes back nil, never as an error.
local function frameScale(frame)
    local ok, s = pcall(frame.GetScale, frame)
    s = ok and SS.safeNumber(s) or nil
    return (s and s > 0) and s or nil
end

local function frameSize(frame)
    local ok, w, h = pcall(frame.GetSize, frame)
    if not ok then return nil end
    w, h = SS.safeNumber(w), SS.safeNumber(h)
    if not (w and h) then return nil end
    return w, h
end

--- Live center relative to the screen center, in UI units.
local function liveCenter(frame)
    local s = frameScale(frame)
    if not s then return nil end
    local ok, cx, cy = pcall(frame.GetCenter, frame)
    if not ok then return nil end
    cx, cy = SS.safeNumber(cx), SS.safeNumber(cy)
    if not (cx and cy) then return nil end
    local ux, uy = UIParent:GetCenter()
    return cx * s - ux, cy * s - uy
end

--- Stored record -> center pair. Offsets are in the frame's own scale (what
--- GetPoint reports and SetPoint takes); sizes convert through it. Today's
--- positionables all run at scale 1; s keeps the math right if one ever
--- does not.
local function centerFromRecord(frame, point, x, y)
    local f = ANCHOR_FRACTIONS[point]
    if not f then return nil end
    local w, h = frameSize(frame)
    local s = frameScale(frame)
    if not (w and s) then return nil end
    local W, H = UIParent:GetSize()
    return x * s + (f[1] - 0.5) * (W - w * s),
           y * s + (f[2] - 0.5) * (H - h * s)
end

--- What the boxes display. Stored first; live while dragging, and for a frame
--- with nothing stored yet (a Note before its first drag, a ScootAuras shell
--- whose key resolves nil).
local function positionCurrent(entry, frame)
    if not entry.dragging then
        local lib = GetLib()
        local layoutName = lib and lib:GetActiveLayoutName()
        local key = resolveKey(entry, frame)
        if key ~= nil and layoutName then
            local pos = entry.store.get(key, layoutName)
            if pos and pos.point then
                local cx, cy = centerFromRecord(frame, pos.point, pos.x or 0, pos.y or 0)
                if cx then return cx, cy end
            end
        end
    end
    return liveCenter(frame)
end

--- Commit a typed pair. Clamped to the screen rect so a mistyped -9999 cannot
--- lose the frame; the clamp is skipped on an axis where the frame outsizes
--- the screen. The delta is against the LIVE center because NudgeFrame
--- re-normalizes from live geometry before adding it: delta in, absolute
--- position out. Combat: the library refuses the move silently, so refuse
--- here too (the row also disables its boxes).
local function commitPosition(entry, frame, pos)
    if type(pos) ~= "table" or InCombatLockdown() then return end
    local lib = GetLib()
    if not lib then return end
    local tx, ty = tonumber(pos.x), tonumber(pos.y)
    if not (tx and ty) then return end

    local w, h = frameSize(frame)
    local s = frameScale(frame)
    if not (w and s) then return end
    local W, H = UIParent:GetSize()
    local rx, ry = (W - w * s) / 2, (H - h * s) / 2
    if rx > 0 then tx = math.max(-rx, math.min(rx, tx)) end
    if ry > 0 then ty = math.max(-ry, math.min(ry, ty)) end

    local cx, cy = liveCenter(frame)
    if not cx then return end
    lib:NudgeFrame(frame, (tx - cx) / s, (ty - cy) / s)
end

--- The provider Brand:Register gets: the shared position row first, then the
--- component's own mirror entries. The component provider runs under pcall so
--- one bad list cannot take the row down with it.
local function composeMirror(entry, componentMirror)
    return function(frame)
        local specs
        if type(componentMirror) == "function" then
            local ok, list = pcall(componentMirror, frame)
            if ok and type(list) == "table" then specs = list end
        end
        specs = specs or {}

        local show = true
        if type(entry.positionEditable) == "function" then
            local ok, allowed = pcall(entry.positionEditable, frame)
            show = (ok and allowed) and true or false
        end
        if show then
            table.insert(specs, 1, {
                kind  = "position",
                label = "Position",
                get   = function() return positionCurrent(entry, frame) end,
                set   = function(p) commitPosition(entry, frame, p) end,
            })
        end
        return specs
    end
end

--------------------------------------------------------------------------------
-- Enter and exit
--------------------------------------------------------------------------------

local function dispatch(which)
    for _, listener in ipairs(listeners) do
        local fn = listener[which]
        if fn then
            securecallfunction(fn)
        end
    end
end

local function ensureHook(lib, event)
    if hooked[event] then return end
    hooked[event] = true
    if event == "layout" then
        lib:RegisterCallback("layout", onLayout)
    else
        lib:RegisterCallback(event, function() dispatch(event) end)
    end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function EM.RegisterPositionable(frame, opts)
    if not frame or type(opts) ~= "table" then return nil end
    local existing = registry[frame]
    if existing then return existing.selection end
    local lib = GetLib()
    if not lib then return nil end

    local entry = {
        key = opts.key,
        default = opts.default,
        store = opts.store,
        apply = opts.apply,
        restoreDefault = opts.restoreDefault and true or false,
        positionEditable = opts.positionEditable,
        brand = opts.brand,
    }
    -- Before AddFrame: the first AddFrame of a session creates the dialog and
    -- runs onEditModeChanged, which fires every layout callback from inside it.
    registry[frame] = entry
    order[#order + 1] = frame

    lib:AddFrame(frame, onDrop, entry.default, nil)
    entry.selection = lib.frameSelections and lib.frameSelections[frame] or nil

    -- The library's drag scripts live on the selection overlay; hooking the
    -- instance marks the window where the position row reads live geometry.
    if entry.selection and entry.selection.HookScript then
        entry.selection:HookScript("OnDragStart", function() entry.dragging = true end)
        entry.selection:HookScript("OnDragStop", function() entry.dragging = nil end)
    end

    -- Registry.lua loads after every consumer; look it up here, never at load.
    local Brand = EM.Brand
    if Brand and entry.brand then
        entry.brand.mirror = composeMirror(entry, entry.brand.mirror)
        Brand:Register(frame, entry.brand)
    end

    if not hooked.layout then
        -- Fires at once when a layout is active, restoring every entry.
        ensureHook(lib, "layout")
    else
        local layoutName = lib:GetActiveLayoutName()
        if layoutName then
            securecallfunction(restore, entry, frame, layoutName)
        end
    end

    -- A frame registered while Edit Mode is open missed the enter pass and
    -- would be undraggable until Edit Mode bounces.
    if lib:IsInEditMode() and entry.selection then
        pcall(entry.selection.ShowHighlighted, entry.selection)
    end

    return entry.selection
end

--- Re-applies the stored position (or the default, when the frame opted in).
--- layoutName defaults to the active layout; nil layout or unknown frame: no-op.
function EM.RestorePositionable(frame, layoutName)
    local entry = frame and registry[frame]
    if not entry then return end
    if layoutName == nil then
        local lib = GetLib()
        layoutName = lib and lib:GetActiveLayoutName()
    end
    restore(entry, frame, layoutName)
end

--- Enter and exit handlers for one component. Re-registering an owner replaces
--- its handlers in place, so a second init pass never doubles them.
function EM.OnEditMode(owner, handlers)
    if not owner or type(handlers) ~= "table" then return end
    local lib = GetLib()
    if not lib then return end
    local listener = listenerByOwner[owner]
    if not listener then
        listener = { owner = owner }
        listenerByOwner[owner] = listener
        listeners[#listeners + 1] = listener
    end
    listener.enter = handlers.enter
    listener.exit = handlers.exit
    ensureHook(lib, "enter")
    ensureHook(lib, "exit")
end

--- LibEditMode's own flag: set before its enter callbacks run and cleared
--- before its exit callbacks run. Not IsEditModeActiveOrOpening, which adds
--- the one-second transition windows the enter/exit bodies must not see.
function EM.IsEditing()
    local lib = GetLib()
    return (lib and lib:IsInEditMode()) or false
end

function EM.GetActiveLayoutName()
    local lib = GetLib()
    return lib and lib:GetActiveLayoutName() or nil
end

--------------------------------------------------------------------------------
-- Introspection: /scoot debug positionables, or /run ScootAddon.EditMode.DumpPositionables()
--------------------------------------------------------------------------------

local function describePos(pos)
    if type(pos) ~= "table" then return "-" end
    return ("%s %s,%s"):format(tostring(pos.point), tostring(pos.x), tostring(pos.y))
end

-- The live anchor of a snapped Cast Bar Z bar answers secret; read it screened.
local function describeLive(frame)
    local ok, point, _, _, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok then return "?" end
    point = SS.plainString(point)
    if not point then return "secret" end
    return ("%s %s,%s"):format(point, tostring(SS.safeNumber(x)), tostring(SS.safeNumber(y)))
end

function EM.DumpPositionables()
    local rows = {}
    local layoutName = EM.GetActiveLayoutName()
    rows[#rows + 1] = "layout: " .. tostring(layoutName)
    local count = 0
    for _, frame in ipairs(order) do
        local entry = registry[frame]
        if entry then
            count = count + 1
            local name = "?"
            if frame.GetDebugName then
                local ok, n = pcall(frame.GetDebugName, frame)
                if ok then name = SS.plainString(n) or "?" end
            end
            local key = resolveKey(entry, frame)
            local stored = nil
            if key ~= nil and layoutName then
                stored = entry.store.get(key, layoutName)
            end
            rows[#rows + 1] = ("%s [%s] key=%s stored=%s default=%s%s live=%s"):format(
                name,
                tostring(entry.brand and entry.brand.navKey),
                tostring(key),
                describePos(stored),
                describePos(entry.default),
                entry.restoreDefault and " (restoreDefault)" or "",
                describeLive(frame))
        end
    end
    rows[#rows + 1] = ("positionables: %d, listeners: %d"):format(count, #listeners)
    if addon.DebugShowWindow then
        addon.DebugShowWindow(("Positionables (%d)"):format(count), rows)
    end
    return rows
end

addon:RegisterDebugCommand({
    name = "positionables",
    help = "Scoot frames in Edit Mode: key, stored and default position per layout, live anchor",
    handler = function() EM.DumpPositionables() end,
})
