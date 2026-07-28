-- Registry.lua - Tracks which Edit Mode frames belong to Scoot
-- Provides: addon.EditMode.Brand, the per-frame registry the branding modules gate on
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
addon.EditMode.Brand = {}
local Brand = addon.EditMode.Brand

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Weak keys so a released frame never pins its entry (see editmode.md, weak-key rule)
local registry = setmetatable({}, { __mode = "k" })
local order = {}          -- array of frames, for theme re-walks
local pendingRetry = setmetatable({}, { __mode = "k" })

-- Set by SelectionSkin's desaturation probe, or by /scoot debug editmode skin
Brand.forceFallbackBorder = false

--------------------------------------------------------------------------------
-- Library access
--------------------------------------------------------------------------------

-- Single accessor so every hook lands on the same LEM object the call sites used.
-- LibEditMode resolves through LibStub, so another addon shipping a higher MINOR can
-- win. Branding is gated per-frame on `registry`, so a foreign frame registered
-- against this copy is never touched.
function Brand.GetLib()
    return addon._LEM or (LibStub and LibStub("LibEditMode", true))
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local function applyBranding(frame, entry)
    local skin = addon.EditMode.SelectionSkin
    if skin and skin.Apply then skin.Apply(entry.selection) end

    local tooltip = addon.EditMode.Tooltip
    if tooltip and tooltip.Attach then tooltip.Attach(entry.selection) end

    local dialog = addon.EditMode.Dialog
    if dialog and dialog.EnsureHooked then dialog.EnsureHooked() end
end

--- Register a frame as Scoot-owned. Call AFTER lib:AddFrame - by then
--- lib.frameSelections[frame] is populated, so this is a pure table read rather
--- than a hook on a library method.
---
--- opts = { navKey, componentId, sectionKey, tab, tabSectionKey, pageState, label }
function Brand:Register(frame, opts)
    if not frame or registry[frame] then return end

    local lib = Brand.GetLib()
    if not lib or not lib.frameSelections then return end

    local selection = lib.frameSelections[frame]
    if not selection then
        -- Registered out of order; retry once on the next frame.
        if not pendingRetry[frame] then
            pendingRetry[frame] = true
            C_Timer.After(0, function() Brand:Register(frame, opts) end)
        end
        return
    end
    pendingRetry[frame] = nil

    opts = opts or {}
    local entry = {
        navKey        = opts.navKey,
        componentId   = opts.componentId,
        sectionKey    = opts.sectionKey,
        tab           = opts.tab,
        tabSectionKey = opts.tabSectionKey,
        pageState     = opts.pageState,
        label         = opts.label,
        selection     = selection,
    }

    registry[frame] = entry
    table.insert(order, frame)

    applyBranding(frame, entry)
end

function Brand:IsScootFrame(frame)
    return frame ~= nil and registry[frame] ~= nil
end

function Brand:GetInfo(frame)
    return frame and registry[frame] or nil
end

--- Iterate every registered frame. fn(frame, entry)
function Brand:ForEach(fn)
    for _, frame in ipairs(order) do
        local entry = registry[frame]
        if entry then fn(frame, entry) end
    end
end

--- Read LEM's GetSystemName closure. It resolves frame.editModeName live, so
--- renames (Custom Groups' UpdateEditModeNames) propagate with no extra plumbing.
function Brand:GetSystemName(selection)
    if not selection or not selection.system then return "" end
    local ok, name = pcall(selection.system.GetSystemName)
    if ok and type(name) == "string" then return name end
    return ""
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

-- Nothing tears these frames down at runtime; this exists for parity with the
-- control convention and for any future profile-reset path.
function Brand:Cleanup()
    local theme = addon.UI and addon.UI.Theme
    if theme and theme.Unsubscribe then
        theme:Unsubscribe("ScootEditModeSelection")
        theme:Unsubscribe("ScootEditModeTooltip")
        theme:Unsubscribe("ScootEditModeDialog")
    end

    local dialog = addon.EditMode.Dialog
    if dialog and dialog.Cleanup then dialog.Cleanup() end
end
