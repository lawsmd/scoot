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
        brand = opts.brand,
    }
    -- Before AddFrame: the first AddFrame of a session creates the dialog and
    -- runs onEditModeChanged, which fires every layout callback from inside it.
    registry[frame] = entry
    order[#order + 1] = frame

    lib:AddFrame(frame, onDrop, entry.default, nil)
    entry.selection = lib.frameSelections and lib.frameSelections[frame] or nil

    -- Registry.lua loads after every consumer; look it up here, never at load.
    local Brand = EM.Brand
    if Brand and entry.brand then
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
