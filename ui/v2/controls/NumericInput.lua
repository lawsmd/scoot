-- NumericInput.lua - a short boxed number with a range: the box from
-- Controls.CreateValueInput on the input role, a value clamped to min and
-- max and rounded to a step on commit.
--
-- opts:
--   width, height   default 60 and metrics.controlHeight
--   min, max        the range; nil leaves that side open
--   step            default 1; a value is rounded to the nearest step
--   value           the starting value; default min or 0
--   onChange(value) runs on commit (Enter or the focus leaving) when the
--                   value changed
--   fontSize, maxLetters (default 8), justifyH (default "CENTER")
--   inset           the flat border's reach past the box, default 2; a 1
--                   stands the box beside a single-line field's holder
--
-- Returns the EditBox carrying SetValue(n), GetValue(), SetRange(min, max),
-- SetInputEnabled(bool). Text that is not a number reverts to the last
-- value; Escape reverts and drops the focus.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local function Format(n, step)
    if step and step % 1 == 0 then return tostring(math.floor(n + 0.5)) end
    return tostring(n)
end

function Controls.CreateNumericInput(parent, opts)
    opts = opts or {}
    local m = Controls.Metrics()
    local box = Controls.CreateValueInput(parent, {
        width = opts.width or 60, height = opts.height or m.controlHeight or 24,
        fontSize = opts.fontSize, maxLetters = opts.maxLetters or 8,
        justifyH = opts.justifyH or "CENTER", textInset = opts.textInset, inset = opts.inset,
    })
    box._min, box._max = opts.min, opts.max
    box._step = opts.step or 1
    box._value = opts.value or opts.min or 0

    local function Clamp(n)
        local step = box._step
        if step and step > 0 then n = math.floor(n / step + 0.5) * step end
        if box._min and n < box._min then n = box._min end
        if box._max and n > box._max then n = box._max end
        return n
    end

    function box:SetValue(n)
        n = tonumber(n)
        if n == nil then n = self._value end
        self._value = Clamp(n)
        self:SetText(Format(self._value, self._step))
    end

    function box:GetValue()
        return self._value
    end

    function box:SetRange(min, max)
        self._min, self._max = min, max
        self:SetValue(self._value)
    end

    function box:SetInputEnabled(enabled)
        self:EnableMouse(enabled and true or false)
        self:SetAlpha(enabled and 1 or 0.5)
        if not enabled then self:ClearFocus() end
    end

    local function Commit()
        local before = box._value
        box:SetValue(tonumber(box:GetText()))
        if box._value ~= before and opts.onChange then opts.onChange(box._value) end
    end

    box:SetScript("OnEditFocusGained", function(self)
        self._setFocusLook(true)
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self._setFocusLook(false)
        Commit()
    end)
    box:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetValue(self._value)
        self:ClearFocus()
    end)

    box:SetValue(box._value)
    return box
end
