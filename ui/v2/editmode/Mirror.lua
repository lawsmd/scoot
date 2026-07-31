-- Mirror.lua - Scoot settings controls rendered inside the Edit Mode dialog
--
-- The branded dialog (Dialog.lua) has always reserved `skin.MirrorSlot` for this.
-- What lands in it comes from the component, but only as a DESCRIPTION: a component
-- returns a spec list saying "a selector called Snap To over these values", and this
-- file decides what a selector looks like in a 232px box. Components therefore never
-- reach into addon.UI.Controls, and the box can be re-laid-out in one place.
--
-- A provider is registered alongside the frame:
--
--     Brand:Register(bar, { navKey = "castBarZ", mirror = MyComponent._EditModeMirror })
--
-- and is called with the frame each time the slot is built, so the list can vary
-- with current state -- offset sliders that only exist while a bar is snapped, an
-- entry hidden for one unit, and so on.
--
-- Spec entries, all of which take `label`, `get` and `set`:
--
--     { kind = "selector", values = {k=label}, order = {k}, rebuild = true }
--     { kind = "slider",   min = -200, max = 200, step = 1, precision = 0 }
--     { kind = "toggle" }
--
-- `rebuild = true` means writing this value changes the SHAPE of the list, so the
-- whole slot is rebuilt afterwards rather than just re-read.
--
-- Descriptions are deliberately not supported. Both Selector and Slider measure a
-- description's wrapped height on a 0.1s timer and grow the row afterwards, which
-- would resize the dialog a frame after it opened -- and at this width there is no
-- room for one anyway. Labels have to carry the meaning; the settings page is where
-- the prose lives.
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
addon.EditMode.Mirror = {}
local Mirror = addon.EditMode.Mirror

--------------------------------------------------------------------------------
-- Sizing
--------------------------------------------------------------------------------
-- Every control is squeezed to fit the dialog's 232px content width beside its
-- label. Selector: 12 pad + ~76 label + 132 control + 12 pad. Slider: 12 pad +
-- ~62 label + (20 arrow + 60 track + 20 arrow + 8 gap + 38 input) + 12 pad.
-- The narrow track is why the arrows and the typed input matter more here than on
-- the settings page: they are how an exact value gets entered.

local SELECTOR_W    = 132
local SLIDER_TRACK_W = 60
local SLIDER_INPUT_W = 38

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Controls currently living in the slot. Rebuilt wholesale rather than pooled:
-- the list is three rows at most, and a pool would have to reconcile kind changes.
local active = {}

--------------------------------------------------------------------------------
-- Builders
--------------------------------------------------------------------------------

local BUILDERS = {
    selector = function(Controls, parent, spec, set)
        return Controls:CreateSelector({
            parent = parent,
            label  = spec.label,
            values = spec.values or {},
            order  = spec.order,
            width  = SELECTOR_W,
            get    = spec.get,
            set    = set,
        })
    end,

    slider = function(Controls, parent, spec, set)
        return Controls:CreateSlider({
            parent     = parent,
            label      = spec.label,
            min        = spec.min,
            max        = spec.max,
            step       = spec.step,
            precision  = spec.precision,
            width      = SLIDER_TRACK_W,
            inputWidth = SLIDER_INPUT_W,
            get        = spec.get,
            set        = set,
        })
    end,

    toggle = function(Controls, parent, spec, set)
        return Controls:CreateToggle({
            parent = parent,
            label  = spec.label,
            get    = spec.get,
            set    = set,
        })
    end,
}

--- Wrap the spec's setter so a shape-changing write rebuilds the slot.
---
--- Deferred by a frame on purpose: the control that fired this is still inside its
--- own click handler and touches itself again on the way out (UpdateDisplay, the
--- sound, the dropdown close), so tearing it down synchronously would pull the rug
--- from under it.
local function WrapSet(spec, onRebuild)
    return function(value)
        spec.set(value)
        if spec.rebuild and onRebuild then
            C_Timer.After(0, onRebuild)
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Tear down whatever is in the slot. Safe to call when nothing is.
function Mirror.Clear()
    for _, row in ipairs(active) do
        if row.Cleanup then pcall(row.Cleanup, row) end
        row:Hide()
        row:ClearAllPoints()
        row:SetParent(nil)
    end
    wipe(active)
end

--- Re-read every control's value without rebuilding.
---
--- The dialog re-enters Scoot mode on every UpdateButtons -- including while the
--- element is being dragged -- so this is the cheap path that keeps displayed
--- values honest when something else changed them.
function Mirror.Refresh()
    for _, row in ipairs(active) do
        if row.Refresh then pcall(row.Refresh, row) end
    end
end

--- Build `provider(frame)`'s spec list into `slot`, and return the total height.
---
--- Returns 0 for every "nothing to show" case -- no provider, a provider that
--- errored, an empty list -- so the caller has one number to act on rather than a
--- set of states.
function Mirror.Build(slot, frame, provider, onRebuild)
    Mirror.Clear()

    if not slot or type(provider) ~= "function" then return 0 end

    local Controls = addon.UI and addon.UI.Controls
    if not Controls then return 0 end

    local ok, specs = pcall(provider, frame)
    if not ok or type(specs) ~= "table" then return 0 end

    local y = 0
    for _, spec in ipairs(specs) do
        local build = type(spec) == "table" and BUILDERS[spec.kind]
        if build and type(spec.get) == "function" and type(spec.set) == "function" then
            local row = build(Controls, slot, spec, WrapSet(spec, onRebuild))
            if row then
                -- The control set its own height at creation; read it before
                -- anchoring so nothing about the read can depend on the anchors.
                -- TOPLEFT + TOPRIGHT is two HORIZONTAL constraints, which leaves
                -- SetHeight in charge -- mixing axes is what silently overrides it
                -- (embranding.md, the two-vertical-constraints trap).
                local h = row:GetHeight() or 0

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -y)

                y = y + h
                active[#active + 1] = row
            end
        end
    end

    return y
end
