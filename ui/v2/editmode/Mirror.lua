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
-- Spec entries; value kinds take `label`, `get` and `set`:
--
--     { kind = "selector", values = {k=label}, order = {k}, rebuild = true }
--     { kind = "slider",   min = -200, max = 200, step = 1, precision = 0 }
--     { kind = "toggle" }
--     { kind = "position" }
--
-- `position` is the X/Y pair under a centered label: `get` returns centerX,
-- centerY (or nil while unreadable) and `set` takes one { x, y } table. The pair
-- is the frame's center relative to the screen center, in UI units; the provider
-- in core/editmode/positionables.lua supplies it. The boxes show and accept whole
-- units only: display rounds, and a typed fraction rounds before `set`.
--
-- Action kinds take `label` and `set` (the click handler); they have no `get`:
--
--     { kind = "button", label = "Do The Thing", rebuild = true }
--     { kind = "status", label = "Doing", animate = true, buttonLabel = "Done" }
--
-- `status` is a label on the left (cycling "..." while `animate`) beside a compact
-- button on the right. Both action kinds share one row height so a provider can
-- swap one for the other without the dialog resizing.
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

local ACTION_BTN_H  = 26   -- matches Dialog.lua's BTN_H
local ACTION_ROW_H  = 34   -- button + top gap; both action kinds share it
local STATUS_BTN_W  = 64   -- the compact status-row button

-- Kept off addon.UI.Skin.Metrics: dialog-only squeeze values, sized to the
-- 232px box like every other constant in this file. The label has its own line,
-- so the boxes get the full width: 12 pad + tag + 4 + reach + 80 box + 16 gap +
-- tag + 4 + reach + 80 box + 12 pad, where reach is the input role's art past
-- the box's left edge (5 on a template skin, 0 on flat).
local POS_BOX_W       = 80   -- each coordinate box
local POS_BOX_H       = 22   -- flat draw only; a template box takes its art's 20
local POS_HALF_GAP    = 16   -- between the X half and the Y half
local POS_PAD_BOTTOM  = 4
local POS_ROW_H       = 46   -- label line + box line
local POS_MAX_LETTERS = 6    -- "-12345" is wider than any screen and still fits the box

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

    position = function(Controls, parent, spec, set)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(POS_ROW_H)

        local theme = addon.UI and addon.UI.Theme

        -- The label and the X/Y tags wear the slider and selector row label:
        -- Controls.AddRowChrome's role, size and accent color.
        local function styleLabel(fs)
            if not theme then return end
            theme:ApplyFont(fs, Controls.RowLabelFontRole(), 13)
            fs:SetTextColor(theme:GetAccentColor())
        end

        local label = row:CreateFontString(nil, "OVERLAY")
        styleLabel(label)
        label:SetJustifyH("CENTER")
        label:SetPoint("TOP", row, "TOP", 0, -2)
        label:SetText(spec.label or "")

        -- The pair get() last returned: a committed box supplies one
        -- coordinate and this supplies the other.
        local lastX, lastY

        -- The slider's value box, so the pair wears the input role's draw:
        -- the skin's template art on Camelot, the flat accent border on tui.
        -- Free text validated on commit: SetNumeric rejects the minus sign.
        local function makeBox()
            return Controls.CreateValueInput(row, {
                width      = POS_BOX_W,
                height     = POS_BOX_H,
                fontSize   = 11,
                maxLetters = POS_MAX_LETTERS,
            })
        end

        local function makeTag(text)
            local tag = row:CreateFontString(nil, "OVERLAY")
            styleLabel(tag)
            tag:SetText(text)
            return tag
        end

        -- Each half is tag + box, one on each side of the row's center line, so
        -- the pair sits centered under the label. A template box's art reaches
        -- _artLeft past its left edge, so the tag stands off the art, not the box.
        local xBox = makeBox()
        local reach = xBox._artLeft or 0
        local boxH = xBox:GetHeight()
        xBox:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -POS_HALF_GAP / 2, POS_PAD_BOTTOM)
        makeTag("X"):SetPoint("RIGHT", xBox, "LEFT", -(4 + reach), 0)
        local yTag = makeTag("Y")
        yTag:SetPoint("LEFT", row, "BOTTOM", POS_HALF_GAP / 2, POS_PAD_BOTTOM + boxH / 2)
        local yBox = makeBox()
        yBox:SetPoint("LEFT", yTag, "RIGHT", 4 + reach, 0)

        local function paint(box, v)
            if box:HasFocus() then return end
            local text = (v ~= nil) and ("%d"):format(math.floor(v + 0.5)) or "-"
            box._painted = text
            box:SetText(text)
        end

        -- An EditBox lays its text out at SetText, so a box painted before
        -- the dialog has a rect shows nothing: re-assert once laid out and on
        -- every show, as the slider's value box does.
        local function repaint(box)
            if box:HasFocus() or box._painted == nil then return end
            box:SetText("")
            box:SetText(box._painted)
            box:SetCursorPosition(0)
        end

        local function commit(box, which, text)
            -- Focus loss commits upstream no matter what; act only on a real
            -- edit, or re-committing the rounded display would move a frame
            -- that sits at a fractional position.
            if text == box._painted then return end
            local v = tonumber(text)
            -- tonumber accepts "inf" and "nan"; neither is a position.
            if v ~= nil and v == v and v > -math.huge and v < math.huge
                and lastX ~= nil and lastY ~= nil then
                v = math.floor(v + 0.5)
                if which == "x" then
                    set({ x = v, y = lastY })
                else
                    set({ x = lastX, y = v })
                end
            end
            row:Refresh()
        end

        -- Enter and focus loss commit; Escape restores the painted text
        -- first, so the focus loss it causes finds nothing to commit.
        local function wire(box, which)
            box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            box:SetScript("OnEscapePressed", function(self)
                self:SetText(self._painted or "")
                self:ClearFocus()
            end)
            box:SetScript("OnEditFocusGained", function(self)
                self:HighlightText()
                self._setFocusLook(true)
            end)
            box:SetScript("OnEditFocusLost", function(self)
                self:HighlightText(0, 0)
                self._setFocusLook(false)
                commit(self, which, self:GetText())
            end)
        end
        wire(xBox, "x")
        wire(yBox, "y")

        function row:Refresh()
            local cx, cy = spec.get()
            lastX, lastY = cx, cy
            paint(xBox, cx)
            paint(yBox, cy)
            local enabled = (cx ~= nil) and not InCombatLockdown()
            xBox:SetEnabled(enabled)
            yBox:SetEnabled(enabled)
        end

        local function repaintBoth()
            repaint(xBox)
            repaint(yBox)
        end

        row:Refresh()
        C_Timer.After(0, repaintBoth)
        row:SetScript("OnShow", repaintBoth)
        return row
    end,

    button = function(Controls, parent, spec, set)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ACTION_ROW_H)
        local btn = Controls:CreateButton({
            parent   = row,
            text     = spec.label or "",
            height   = ACTION_BTN_H,
            fontSize = 11,
            onClick  = function() set() end,
        })
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        btn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        function row:Cleanup()
            if btn.Cleanup then btn:Cleanup() end
        end
        return row
    end,

    status = function(Controls, parent, spec, set)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ACTION_ROW_H)

        local btn = Controls:CreateButton({
            parent   = row,
            text     = spec.buttonLabel or "Done",
            width    = STATUS_BTN_W,
            height   = ACTION_BTN_H,
            fontSize = 11,
            onClick  = function() set() end,
        })
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

        local fs = row:CreateFontString(nil, "OVERLAY")
        local theme = addon.UI and addon.UI.Theme
        if theme and theme.ApplyLabelFont then
            theme:ApplyLabelFont(fs, 11)
        end
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        -- Centered on the button's 26px band, not the 34px row.
        fs:SetPoint("LEFT", row, "BOTTOMLEFT", 0, ACTION_BTN_H / 2)
        fs:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        fs:SetText(spec.label or "")

        -- OnUpdate rather than a ticker: it pauses while the row is hidden and
        -- dies with the frame, so Clear() cannot strand a running animation.
        if spec.animate then
            local elapsed, dots = 0, 0
            row:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed >= 0.4 then
                    elapsed = elapsed - 0.4
                    dots = (dots % 3) + 1
                    fs:SetText((spec.label or "") .. string.rep(".", dots))
                end
            end)
        end

        function row:Cleanup()
            self:SetScript("OnUpdate", nil)
            if btn.Cleanup then btn:Cleanup() end
        end
        return row
    end,
}

-- Action kinds carry no readable value; `set` alone is their contract.
local NO_GET_KINDS = { button = true, status = true }

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
        local getOk = type(spec.get) == "function" or NO_GET_KINDS[spec.kind]
        if build and getOk and type(spec.set) == "function" then
            local row = build(Controls, slot, spec, WrapSet(spec, onRebuild))
            if row then
                -- The control set its own height at creation; read it before
                -- anchoring so nothing about the read can depend on the anchors.
                -- TOPLEFT + TOPRIGHT is two HORIZONTAL constraints, which leaves
                -- SetHeight in charge -- mixing axes is what silently overrides it
                -- (the two-vertical-constraints trap).
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
