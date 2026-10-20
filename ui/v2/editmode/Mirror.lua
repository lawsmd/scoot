-- Mirror.lua - Scoot settings controls rendered inside the Edit Mode dialog
--
-- The branded dialog (Dialog.lua) has always reserved `skin.MirrorSlot` for this.
-- What lands in it comes from the component, but only as a DESCRIPTION: a component
-- returns a spec list saying "a selector called Snap To over these values", and this
-- file decides what a selector looks like in a 312px box. Components therefore never
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
-- A header takes `label` alone; it has no value and no handler:
--
--     { kind = "header", label = "Health Bar" }
--
-- It opens a section: one box around it and the rows under it, to the next
-- header or to an `end` entry, drawn by the editDialog role's `section`
-- descriptor. A section groups its rows the way a page section does, so a
-- long list can carry short labels ("Height" under "Health Bar" rather than
-- "Health Bar Height", which the slider's label band cannot hold). Rows
-- before the first header stand in the slot with no box.
--
-- A header given `values` and `order`, with `get` and `set`, is the bare
-- dropdown control in the title's place: the section's subject is picked
-- where its name would stand, and the rows under it follow the pick.
--
--     { kind = "header", values = {k=label}, order = {k}, get = ..., set = ... }
--
-- `{ kind = "end" }` closes the open section, so the rows after it stand in
-- the slot with no box: buttons that act on the whole, under a box that
-- edits one part of it.
--
-- `{ kind = "columns", count = 2 }` lays the sections after it side by side,
-- `count` to a line, left to right, each line as tall as its tallest box.
-- `count = 1` goes back to full width, as does any row outside a section.
-- A box in a column is narrower than the slot, so its sliders and selectors
-- take the column widths below; a registration that uses columns gives the
-- dialog a `dialogWidth` that leaves them room (Dialog.lua).
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
-- Every control is sized to the dialog's 312px content width beside its
-- label. Selector: 12 pad + ~128 label + 160 control + 12 pad. Slider: 12 pad +
-- ~102 label + (20 arrow + 100 track + 20 arrow + 8 gap + 38 input) + 12 pad.
-- The label band is the number to protect: at 62 the longer labels ran under
-- their arrows. A row inside a section box gives up SECTION_PAD_X on each
-- side of it. The arrows and the typed input are still how an exact value
-- gets entered on a short track.

local SELECTOR_W    = 160
local SLIDER_TRACK_W = 100
local SLIDER_INPUT_W = 38
-- Kept off addon.UI.Skin.Metrics: dialog-only, sized to a column box, a
-- 242 column of the 520 dialog split in two, which leaves the label band
-- about 60.
local COLUMN_SELECTOR_W     = 130
local COLUMN_SLIDER_TRACK_W = 60

local ACTION_BTN_H  = 26   -- matches Dialog.lua's BTN_H
local ACTION_ROW_H  = 34   -- button + top gap; both action kinds share it
local STATUS_BTN_W  = 64   -- the compact status-row button

-- Kept off addon.UI.Skin.Metrics: the header and its section box are
-- dialog-only, sized to the 312px box like the rest of this file. The
-- header's text sits at the foot of its row, so the row's slack is the gap
-- under the box's top edge, and stands SECTION_TEXT_INSET in, level with the
-- row labels below it: their rows sit SECTION_PAD_X inside the box and their
-- labels 12 inside their rows. The face and size are the header font role's
-- own, the page's section title.
local HEADER_ROW_H       = 30
local HEADER_PAD_BOTTOM  = 4
-- A header that is a dropdown stands the control at the title's inset and
-- foot, in the action row's height so the box's edge clears it, at the
-- skin's dropdown height and this width: room for a name between the
-- skin's steppers, which the metric's own width has not.
local HEADER_PICK_W      = 210
local SECTION_PAD_X      = 4
local SECTION_PAD_BOTTOM = 8
local SECTION_GAP        = 8    -- between one box and the next, and under the last
local SECTION_TEXT_INSET = 16

-- Kept off addon.UI.Skin.Metrics: dialog-only values, sized to the 312px box
-- like every other constant in this file. The label has its own line and the
-- pair sits centered under it: tag + 4 + reach + 80 box + 16 gap + tag + 4 +
-- reach + 80 box, where reach is the input role's art past the box's left
-- edge (5 on a template skin, 0 on flat), with the row's slack either side.
local POS_BOX_W       = 80   -- each coordinate box
local POS_BOX_H       = 22   -- flat draw only; a template box takes its art's 20
local POS_HALF_GAP    = 16   -- between the X half and the Y half
local POS_PAD_BOTTOM  = 4
local POS_ROW_H       = 46   -- label line + box line
local POS_MAX_LETTERS = 6    -- "-12345" is wider than any screen and still fits the box
-- The dynamic view's row, when the spec carries `offscreen`: the label over
-- the left half and the X and Y boxes stacked under it, Move Off Screen and
-- its direction picker in the right half, level with the two boxes.
local POS_LABEL_H     = 22   -- the label's line, over the first box
local POS_STACK_GAP   = 6    -- between the X box and the Y box
local POS_STACK_ROW_H = 76   -- label line + two boxes + the gap + the pad
local POS_PAIR_SHIFT  = 8    -- moves box and tag right, so the pair centers
local POS_CHECK_FIT   = 24   -- the checkbox's box, at most
local POS_DIR_W       = 140  -- the direction picker, inside the half
local POS_DIMMED      = 0.4  -- the boxes and tags while Move Off Screen holds

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
    selector = function(Controls, parent, spec, set, narrow)
        return Controls:CreateSelector({
            parent = parent,
            label  = spec.label,
            values = spec.values or {},
            order  = spec.order,
            width  = narrow and COLUMN_SELECTOR_W or SELECTOR_W,
            get    = spec.get,
            set    = set,
        })
    end,

    slider = function(Controls, parent, spec, set, narrow)
        return Controls:CreateSlider({
            parent     = parent,
            label      = spec.label,
            min        = spec.min,
            max        = spec.max,
            step       = spec.step,
            precision  = spec.precision,
            width      = narrow and COLUMN_SLIDER_TRACK_W or SLIDER_TRACK_W,
            inputWidth = SLIDER_INPUT_W,
            get        = spec.get,
            set        = set,
        })
    end,

    toggle = function(Controls, parent, spec, set)
        local row = Controls:CreateToggle({
            parent = parent,
            label  = spec.label,
            get    = spec.get,
            set    = set,
            indicatorRole = spec.indicatorRole,
        })
        -- A label broken over lines by its own newlines: the row grows to
        -- hold them, the label centered on it as on a one-line row.
        local label = row and row._label
        local _, breaks = string.gsub(spec.label or "", "\n", "")
        if label and breaks > 0 then
            label:SetJustifyH("LEFT")
            local _, size = label:GetFont()
            local lineH = (tonumber(size) or 13) + 3
            local need = (breaks + 1) * lineH + 12
            if need > (row:GetHeight() or 0) then row:SetHeight(need) end
        end
        return row
    end,

    position = function(Controls, parent, spec, set)
        local row = CreateFrame("Frame", nil, parent)
        local stacked = type(spec.offscreen) == "table"
        row:SetHeight(stacked and POS_STACK_ROW_H or POS_ROW_H)

        -- The stacked row's two halves, split at the row's center line.
        local leftHalf, rightHalf = row, nil
        if stacked then
            leftHalf = CreateFrame("Frame", nil, row)
            leftHalf:SetPoint("TOPLEFT", row, "TOPLEFT")
            leftHalf:SetPoint("BOTTOMRIGHT", row, "BOTTOM")
            rightHalf = CreateFrame("Frame", nil, row)
            rightHalf:SetPoint("TOPLEFT", row, "TOP")
            rightHalf:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
        end

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
        label:SetPoint("TOP", leftHalf, "TOP", 0, -2)
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
        local xTag = makeTag("X")
        local yTag = makeTag("Y")
        local yBox = makeBox()
        if stacked then
            -- Stacked in the left half, each tag left of its box.
            xBox:SetPoint("TOP", leftHalf, "TOP", POS_PAIR_SHIFT, -POS_LABEL_H)
            yBox:SetPoint("TOP", xBox, "BOTTOM", 0, -POS_STACK_GAP)
            xTag:SetPoint("RIGHT", xBox, "LEFT", -(4 + reach), 0)
            yTag:SetPoint("RIGHT", yBox, "LEFT", -(4 + reach), 0)
        else
            xBox:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -POS_HALF_GAP / 2, POS_PAD_BOTTOM)
            xTag:SetPoint("RIGHT", xBox, "LEFT", -(4 + reach), 0)
            yTag:SetPoint("LEFT", row, "BOTTOM", POS_HALF_GAP / 2, POS_PAD_BOTTOM + boxH / 2)
            yBox:SetPoint("LEFT", yTag, "RIGHT", 4 + reach, 0)
        end

        -- Move Off Screen: the checkbox and its name level with the X box,
        -- centered in the right half; the direction picker under it, level
        -- with the Y box, shown while the box is checked. Checked, the
        -- frame's position is its edge's, so the X and Y boxes dim and take
        -- no input until it is unchecked.
        local check, dirPick
        if stacked then
            local off = spec.offscreen
            local function toggle()
                if InCombatLockdown() then return end
                off.set(off.get() == nil and "BOTTOM" or false)
                row:Refresh()
            end
            check = Controls.CreateToggleIndicator(rightHalf, {
                clickable = true, fit = POS_CHECK_FIT, onClick = toggle,
            })
            local caption = rightHalf:CreateFontString(nil, "OVERLAY")
            styleLabel(caption)
            caption:SetText(off.label or "Move Off Screen?")
            local pairW = check.width + 6 + caption:GetStringWidth()
            check.frame:SetPoint("LEFT", rightHalf, "TOP", -pairW / 2, -(POS_LABEL_H + boxH / 2))
            caption:SetPoint("LEFT", check.frame, "RIGHT", 6, 0)
            -- The name takes the click too, as a checkbox's label does.
            local hit = CreateFrame("Button", nil, rightHalf)
            hit:SetAllPoints(caption)
            hit:SetScript("OnClick", toggle)

            dirPick = Controls:CreateDropdown({
                parent = rightHalf,
                values = off.values,
                order  = off.order,
                width  = POS_DIR_W,
                get    = off.get,
                set    = function(edge)
                    if InCombatLockdown() then return end
                    off.set(edge)
                    row:Refresh()
                end,
            })
            dirPick:SetPoint("TOP", rightHalf, "TOP", 0, -(POS_LABEL_H + boxH + POS_STACK_GAP))
        end

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
            local edge = stacked and spec.offscreen.get() or nil
            local enabled = (cx ~= nil) and edge == nil and not InCombatLockdown()
            xBox:SetEnabled(enabled)
            yBox:SetEnabled(enabled)
            if stacked then
                local alpha = (edge == nil) and 1 or POS_DIMMED
                for _, region in ipairs({ xBox, yBox, xTag, yTag }) do region:SetAlpha(alpha) end
                check:SetState(edge ~= nil, InCombatLockdown())
                dirPick:SetShown(edge ~= nil)
                if edge ~= nil then dirPick:Refresh() end
            end
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

    -- The settings page's section title, in the header role at its own size
    -- and in the primary text color, a step up from the accent the row labels
    -- wear. Its row is the top of the section box, which Build draws. Given
    -- `values`, the title's place holds the bare dropdown control instead,
    -- and the section's subject is picked there.
    header = function(Controls, parent, spec, set)
        local row = CreateFrame("Frame", nil, parent)
        if spec.values then
            row:SetHeight(ACTION_ROW_H)
            local pick = Controls:CreateDropdown({
                parent = row,
                width  = HEADER_PICK_W,
                values = spec.values,
                order  = spec.order,
                get    = spec.get,
                set    = set or spec.set,
            })
            if pick then
                pick:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SECTION_TEXT_INSET, HEADER_PAD_BOTTOM)
                function row:Refresh() pick:Refresh() end
                function row:Cleanup()
                    if pick.Cleanup then pick:Cleanup() end
                end
            end
            return row
        end
        row:SetHeight(HEADER_ROW_H)
        local fs = row:CreateFontString(nil, "OVERLAY")
        -- Justified before the font goes on: a Deep Shadow header role gives
        -- the string a copy that takes its justification at that moment, and
        -- a copy left centered draws the title a second time mid-row.
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        local theme = addon.UI and addon.UI.Theme
        if theme then theme:ApplyFont(fs, "header") end
        local Chrome = addon.UI and addon.UI.Chrome
        local r, g, b = 1, 1, 1
        if Chrome and Chrome.Color then r, g, b = Chrome.Color("primary") end
        fs:SetTextColor(r, g, b, 1)
        fs:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", SECTION_TEXT_INSET, HEADER_PAD_BOTTOM)
        fs:SetPoint("RIGHT", row, "RIGHT", -SECTION_TEXT_INSET, 0)
        fs:SetText(spec.label or "")
        return row
    end,
}

-- Action kinds carry no readable value; `set` alone is their contract.
local NO_GET_KINDS = { button = true, status = true }

-- Label kinds need neither; a header is a caption over the rows below it,
-- or, given values, the dropdown that picks what they show.
local LABEL_KINDS = { header = true }

-- The entry that closes a section without opening the next.
local END_KIND = "end"
-- The entry that sets how many sections stand side by side.
local COLUMNS_KIND = "columns"

-- The box a header opens, on the editDialog role's `section` descriptor: a
-- nine-slice where the skin declares one, the flat accent border otherwise.
local function SectionSpec()
    local Chrome = addon.UI and addon.UI.Chrome
    local dialog = Chrome and Chrome.Spec and Chrome.Spec("editDialog")
    if not dialog then return { kind = "flat" } end
    return Chrome.Resolve(dialog.section, nil)
end

local function CreateSection(Controls, slot)
    local box = CreateFrame("Frame", nil, slot)
    local spec = SectionSpec()
    if spec.kind == "nineSlice" then
        box._art = addon.UI.Chrome.NineSlice(box, spec)
    else
        box._border = Controls.CreateBorder(box, { thickness = 1 })
    end
    return box
end

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
    -- The open section box and the height filled inside it. A header closes
    -- the one before it and opens the next, an end entry closes it alone; a
    -- row lands in the open box, or in the slot while none is open. A box
    -- keeps SECTION_GAP under it, off the next row, the next box or the
    -- dialog's buttons; `gapped` says the last thing laid was that gap, so
    -- a box after a box takes one gap, not two.
    local section, sy
    local gapped = false
    -- Columns: how many to a line, the next box's column, the line's top
    -- and its tallest box so far.
    local columns, col, lineTop, lineH = 1, 0, 0, 0

    local function flushLine()
        if col == 0 then return end
        y = lineTop + lineH + SECTION_GAP
        col, lineH = 0, 0
        gapped = true
    end

    local function closeSection()
        if not section then return end
        local h = sy + SECTION_PAD_BOTTOM
        section:SetHeight(h)
        if section._inColumn then
            if h > lineH then lineH = h end
            col = col + 1
            if col >= columns then flushLine() end
        else
            y = y + h + SECTION_GAP
            gapped = true
        end
        section, sy = nil, nil
    end

    local function openSection()
        closeSection()
        if col == 0 then
            if y > 0 and not gapped then y = y + SECTION_GAP end
            lineTop = y
        end
        section = CreateSection(Controls, slot)
        if columns > 1 then
            local w = ((slot:GetWidth() or 0) - (columns - 1) * SECTION_GAP) / columns
            section:SetPoint("TOPLEFT", slot, "TOPLEFT", col * (w + SECTION_GAP), -lineTop)
            section:SetWidth(w)
            section._inColumn = true
        else
            section:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -y)
            section:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -y)
        end
        sy = 0
        active[#active + 1] = section
    end

    for _, spec in ipairs(specs) do
        local kind = type(spec) == "table" and spec.kind or nil
        local build = kind and BUILDERS[kind]
        local labelOnly = build and LABEL_KINDS[kind]
        local getOk = type(spec.get) == "function" or NO_GET_KINDS[kind]
        local setOk = type(spec.set) == "function"
        if kind == END_KIND then
            closeSection()
        elseif kind == COLUMNS_KIND then
            closeSection()
            flushLine()
            columns = math.max(1, math.floor(tonumber(spec.count) or 1))
        elseif build and (labelOnly or (getOk and setOk)) then
            if labelOnly then
                openSection()
            elseif not section then
                flushLine()
            end
            local parent = section or slot
            local narrow = section and section._inColumn or false
            local row = build(Controls, parent, spec, setOk and WrapSet(spec, onRebuild) or nil, narrow)
            if row then
                -- The control set its own height at creation; read it before
                -- anchoring so nothing about the read can depend on the anchors.
                -- TOPLEFT + TOPRIGHT is two HORIZONTAL constraints, which leaves
                -- SetHeight in charge -- mixing axes is what silently overrides it
                -- (the two-vertical-constraints trap).
                local h = row:GetHeight() or 0

                row:ClearAllPoints()
                if section then
                    -- The header spans the box; the rows stand in from its edge.
                    local inset = labelOnly and 0 or SECTION_PAD_X
                    row:SetPoint("TOPLEFT", section, "TOPLEFT", inset, -sy)
                    row:SetPoint("TOPRIGHT", section, "TOPRIGHT", -inset, -sy)
                    sy = sy + h
                else
                    row:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, -y)
                    row:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, -y)
                    y = y + h
                    gapped = false
                end
                active[#active + 1] = row
            end
        end
    end

    closeSection()
    flushLine()
    return y
end
