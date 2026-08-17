--------------------------------------------------------------------------------
-- castbarz/casttime.lua
-- The numeric cast time readout beside the bar.
--
-- Cast Bar Z has no OnUpdate anywhere, on purpose (events.lua:9-12), and every
-- obvious way to draw a ticking number reintroduces one. This file has none
-- either, because 12.0 ships a purpose-built facility for exactly this:
--
--   C_DurationUtil.CreateDurationTextBinding() returns an object that writes a
--   FontString from a LuaDurationObject on ITS OWN schedule. SetUpdateInterval(0)
--   is every game tick. The sampling, the arithmetic and the formatting all
--   happen engine-side, so nothing here ever touches a value that might be
--   secret -- which is the second reason Blizzard's own approach is unusable.
--
-- Blizzard's CastingBarMixin:UpdateCastTimeText computes `max - GetValue()` in
-- Lua (CastingBarFrame.lua:761-780). That is arithmetic on a secret the moment
-- the unit is restricted, and it runs from OnUpdate (:519-549). Its PLACEMENT is
-- worth copying -- CastTimeText anchors LEFT to the bar's RIGHT at x=10
-- (CastingBarFrame.xml:336-340) -- and so is its lifecycle: it hides the readout
-- the instant a cast ends (UpdateCastTimeTextShown, :749-759). Its mechanism is
-- not.
--
-- Note for anyone extending this: the binding API has ZERO call sites in
-- Blizzard's 12.0 UI. There is no reference implementation to check against, so
-- the annotations are the entire spec and edge cases have to be measured. The
-- expiry behaviour below was found that way, by /scoot debug castz time.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

CBZ.CAST_TIME_MODES = { "remaining", "elapsed", "both" }

-- Shown in Edit Mode and in the settings preview, where there is no real cast to
-- bind to. Blizzard's equivalent is a hardcoded `seconds = 10`.
CBZ.PREVIEW_CAST_TIME = "2.4"

-- Fallback when the color setting is missing. Light gray rather than white: the
-- readout sits beside a spell name drawn in the spec gradient and should not
-- compete with it.
local DEFAULT_TIME_COLOR = { 0.85, 0.85, 0.85, 1 }

-- What the binding writes once the duration has run out.
--
-- This is not decoration. A duration can expire a frame or two BEFORE its
-- UNIT_SPELLCAST_STOP arrives, and a binding whose expired text was never
-- configured writes an empty string
-- (DurationTextBindingObjectAPIDocumentation.lua:205-214) -- so without this,
-- every completed cast blanks its own readout just before the bar freezes.
--
-- One constant for all three readouts. It is the correct final value for the
-- countdown, which is the default and the only mode where a constant CAN be
-- right; for the two count-up modes the true final value is the cast's total
-- duration, which is unknowable here and secret on most units anyway. It is
-- visible for at most a frame or two either way, because _StopCastTime hides the
-- FontString on the same event.
local EXPIRED_TEXT = "0.0"

--------------------------------------------------------------------------------
-- Formatter
--------------------------------------------------------------------------------

-- One formatter for every bar. A NumericRuleFormatter holds breakpoints and
-- nothing per-caller, so there is nothing to keep apart; Copy() exists if that
-- ever stops being true.
local sharedFormatter
local formatterFailed = false

--- Tenths below ten seconds, whole numbers above.
---
--- A 30-second channel ticking through hundredths is noise, and the digit count
--- changing under the reader is worse than the precision is worth.
---
--- `rounding` is passed explicitly even though it is defaulted, because it is
--- annotated Nilable = false (NumericRuleFormatterSharedDocumentation.lua:25) --
--- the same shape as SetTimerDuration's `interpolation`, which this component
--- already learned to pass rather than assume. Measured optional; sent anyway.
local function GetFormatter()
    if sharedFormatter then return sharedFormatter end
    if formatterFailed then return nil end

    local su = C_StringUtil
    if not (su and su.CreateNumericRuleFormatter) then
        formatterFailed = true
        return nil
    end

    local ok, f = pcall(su.CreateNumericRuleFormatter)
    if not ok or not f then
        formatterFailed = true
        return nil
    end

    local nearest = Enum and Enum.NumericRuleFormatRounding
        and Enum.NumericRuleFormatRounding.Nearest

    local okSet = pcall(f.SetBreakpoints, f, {
        { threshold = 0,  step = 0.1, rounding = nearest, format = "%.1f" },
        { threshold = 10, step = 1,   rounding = nearest, format = "%.0f" },
    })
    if not okSet then
        formatterFailed = true
        return nil
    end

    sharedFormatter = f
    return sharedFormatter
end

--------------------------------------------------------------------------------
-- Readout modes
--------------------------------------------------------------------------------

--- Which property the readout samples, given the setting and the cast.
---
--- An empowered cast overrides the setting. Its bar FILLS rather than drains, so
--- a countdown beside it contradicts what the sweep is doing -- the same reason
--- ApplyDuration flips the timer direction for one (events.lua:201-208).
--- "both" already counts up, so only the countdown needs redirecting.
local function ResolveMode(mode, countUp)
    if mode ~= "elapsed" and mode ~= "both" then mode = "remaining" end
    if countUp and mode == "remaining" then return "elapsed" end
    return mode
end

--- Point the binding at the right duration property.
---
--- SetTextFormat takes '{}' placeholders, one per component, so "1.2 / 2.5" is a
--- single format string rather than two bindings fighting over one FontString.
local function ApplyFormat(binding, mode, formatter)
    local P = Enum and Enum.DurationTextBindingProperty
    if not (binding and P and formatter) then return false end

    local format, components
    if mode == "both" then
        format = "{} / {}"
        components = {
            { property = P.ElapsedDuration, formatter = formatter },
            { property = P.TotalDuration,   formatter = formatter },
        }
    elseif mode == "elapsed" then
        format = "{}"
        components = { { property = P.ElapsedDuration, formatter = formatter } }
    else
        format = "{}"
        components = { { property = P.RemainingDuration, formatter = formatter } }
    end

    return (pcall(binding.SetTextFormat, binding, format, components))
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function CBZ._IsCastTimeEnabled()
    return CBZ._GetSetting("castTime") == true
end

--- Which typeface the readout uses.
---
--- nil means "follow the spell name", which is what an untouched profile stores,
--- so the readout tracks the shared font until the user picks one for it -- and
--- then stops, permanently. That inheritance is why castTimeFont is declared
--- without a default (core.lua): a default would be handed back by the settings
--- metatable and there would be no nil left to mean "inherit".
---
--- Style is deliberately NOT forked the same way. Size and face are what keep a
--- number from competing with the name beside it; a readout in a different weight
--- to its own bar's text reads as a bug rather than a choice.
function CBZ._GetCastTimeFontFace()
    local face = CBZ._GetSetting("castTimeFont")
    if type(face) ~= "string" or face == "" then
        face = CBZ._GetSetting("fontFace")
    end
    return face
end

function CBZ._GetCastTimeColor()
    local c = CBZ._GetSetting("castTimeColor")
    if type(c) ~= "table" or type(c[1]) ~= "number" then return DEFAULT_TIME_COLOR end
    return c
end

--- Which side of the bar the readout sits on.
---
--- Per unit, not shared, because it is a property of where that bar SITS rather
--- than of how it looks. Boss defaults to positionMode "left" -- bar's RIGHT edge
--- against the boss frame's LEFT edge -- so a right-side readout would land on
--- top of the boss frame it belongs to.
function CBZ._GetCastTimeSide(unitKey)
    local cfg = CBZ._GetUnitConfig(unitKey)
    local side = cfg and cfg.castTimeSide
    if side == "left" then return "left" end
    return "right"
end

--------------------------------------------------------------------------------
-- Binding lifecycle
--------------------------------------------------------------------------------

--- Build this bar's binding, once.
---
--- Cached failure as well as success: if the API is missing there is no point
--- retrying on every cast, and a bar with no binding simply never shows a
--- readout rather than erroring.
function CBZ._EnsureCastTimeBinding(bar)
    if bar.timeBinding then return bar.timeBinding end
    if bar.timeBindingFailed then return nil end

    local fs = bar.castTimeText
    local du = C_DurationUtil
    local formatter = GetFormatter()

    if not (fs and du and du.CreateDurationTextBinding and formatter) then
        bar.timeBindingFailed = true
        return nil
    end

    local ok, binding = pcall(du.CreateDurationTextBinding)
    if not ok or not binding then
        bar.timeBindingFailed = true
        return nil
    end

    local built = pcall(function()
        binding:SetFontString(fs)
        binding:SetFormatter(formatter)
        -- Zero: every game tick. Anything larger makes the readout visibly step,
        -- which on a 1.5s cast reads as the bar having stalled.
        binding:SetUpdateInterval(0)
        binding:SetExpiredText(EXPIRED_TEXT)
        binding:SetZeroDurationText(EXPIRED_TEXT)
    end)
    if not built then
        bar.timeBindingFailed = true
        return nil
    end

    bar.timeBinding = binding
    return binding
end

--- Start the readout for a cast that has just begun.
---
--- `dur` is the SAME LuaDurationObject the progress bar was handed, so the number
--- and the sweep cannot disagree about when the cast ends.
---
--- SetDuration is annotated SecretArguments = "AllowedWhenUntainted", which reads
--- like a gate and is not one: it tests whether the ARGUMENT is a secret, and a
--- LuaDurationObject is plain userdata that merely holds secrets internally. Same
--- finding as SetTimerDuration (events.lua:185-192), measured again for this call
--- specifically by /scoot debug castz time on 2026-07-31.
function CBZ._StartCastTime(bar, dur, countUp)
    if not CBZ._IsCastTimeEnabled() then return end

    local fs = bar.castTimeText
    if not fs or not dur then return end

    local binding = CBZ._EnsureCastTimeBinding(bar)
    if not binding then return end

    -- Re-sent every cast rather than cached: it is one call per cast, not per
    -- frame, and caching it would need invalidating from the settings page, the
    -- empowered override and a profile switch alike.
    if not ApplyFormat(binding, ResolveMode(CBZ._GetSetting("castTimeReadout"), countUp), GetFormatter()) then
        return
    end

    if not pcall(binding.SetDuration, binding, dur) then return end
    pcall(binding.Enable, binding)
    fs:Show()
end

--- Re-point the readout at a replacement clock (pushback, channel tick change).
---
--- Rebinding rather than assuming the old object mutates in place: it is one call
--- on an event that fires a handful of times per cast at most.
function CBZ._RefreshCastTime(bar, dur)
    local binding = bar.timeBinding
    if not binding or not dur then return end
    if not bar.castTimeText or not bar.castTimeText:IsShown() then return end
    pcall(binding.SetDuration, binding, dur)
end

--- Stop and clear the readout.
---
--- Hiding at cast end is Blizzard's own behaviour (UpdateCastTimeTextShown gates
--- on `casting or channeling or isInEditMode`, CastingBarFrame.lua:749-759), and
--- here it also sidesteps the expiry blank entirely: the hold-and-fade shows the
--- spell name and the completion effect, and a frozen "0.0" beside them adds
--- nothing.
---
--- ClearText, never SetText(""). On a restricted unit the binding writes a SECRET
--- string, which stamps Enum.SecretAspect.Text onto this FontString exactly as a
--- secret spell name does to the bands. Only ClearText releases that aspect --
--- SetText("") leaves it in place, and a FontString still holding it answers every
--- later measurement with a secret. This FontString must likewise never be handed
--- to addon.MeasureTextWidth; see the ruler note in text.lua's FitText.
function CBZ._StopCastTime(bar)
    local binding = bar.timeBinding
    if binding then pcall(binding.Disable, binding) end

    local fs = bar.castTimeText
    if not fs then return end

    fs:Hide()
    if fs.ClearText then
        pcall(fs.ClearText, fs)
    else
        pcall(fs.SetText, fs, "")
    end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

--- The clock for a cast already in flight.
---
--- Only the layout pass needs this. Every other path is handed the duration by
--- ApplyDuration, which is the object the sweep itself was given; this one has to
--- ask, because a settings change arrives with no cast context at all. Both getters
--- are MayReturnNothing (UnitDocumentation.lua:798, 841), so nil is a normal answer
--- and callers treat it as "leave the readout alone".
local function LiveDuration(bar)
    if not bar.casting or not bar.unit then return nil end
    local ok, dur
    if bar.channelled then
        ok, dur = pcall(UnitChannelDuration, bar.unit)
    else
        ok, dur = pcall(UnitCastingDuration, bar.unit)
    end
    if ok then return dur end
    return nil
end

--- Place, size and color the readout. DB numbers only -- never a geometry read.
---
--- The bar's own RIGHT edge is already the outer edge of the right end tick (the
--- cap anchors RIGHT to bar RIGHT, frames.lua:448-452), so the gap measures from
--- past the tick without needing to know how wide one is.
---
--- JustifyH is load-bearing rather than cosmetic: the text has to grow AWAY from
--- the bar, or a two-digit channel timer creeps back over the end tick it was
--- placed clear of. SetWidth(0) leaves it unbounded, which is safe here precisely
--- because it sits outside the bar -- unlike the name bands, whose columns ARE
--- the clip.
function CBZ._LayoutCastTime(bar)
    local fs = bar.castTimeText
    if not fs then return end

    if not CBZ._IsCastTimeEnabled() then
        CBZ._StopCastTime(bar)
        return
    end

    local face  = addon.ResolveFontFace(CBZ._GetCastTimeFontFace())
    local size  = tonumber(CBZ._GetSetting("castTimeSize")) or 12
    local style = tostring(CBZ._GetSetting("fontStyle") or "SHADOWTHICKOUTLINE")
    addon.ApplyFontStyle(fs, face, size, style)
    -- Off for the same reason the bands turn it off: nothing scales this text, and
    -- smooth scaling only costs sharpness under a fractional UI scale.
    if fs.SetSmoothScaling then fs:SetSmoothScaling(false) end

    local c = CBZ._GetCastTimeColor()
    fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)

    local gap = CBZ._SnapToPixels(tonumber(CBZ._GetSetting("castTimeGap")) or 10)
    local dy  = CBZ._SnapToPixels(tonumber(CBZ._GetSetting("castTimeOffsetY")) or 0)

    fs:ClearAllPoints()
    fs:SetWidth(0)
    if CBZ._GetCastTimeSide(bar.unitKey) == "left" then
        fs:SetJustifyH("RIGHT")
        fs:SetPoint("RIGHT", bar, "LEFT", -gap, dy)
    else
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", bar, "RIGHT", gap, dy)
    end

    -- A settings change mid-cast has to reach the live binding, or the readout is
    -- stale until the next cast: switching Remaining to Elapsed would keep counting
    -- down, and switching the whole feature ON would show nothing at all. Restarting
    -- covers both, because _StartCastTime re-applies the format, rebinds and shows.
    -- Same reason _RelayoutEmpowered is the last thing the layout pass does.
    if bar.casting then
        CBZ._StartCastTime(bar, LiveDuration(bar), bar.empowered)
    end
end

--- A static stand-in, for Edit Mode and the settings preview.
---
--- Neither has a LuaDurationObject to bind -- Edit Mode is not casting anything,
--- and the settings preview drives progressBar:SetValue directly because
--- SetTimerDuration needs a real cast. Blizzard has the same problem and solves it
--- the same way, with a hardcoded `seconds = 10` in its Edit Mode branch
--- (CastingBarFrame.lua:774-775). Without it the readout is invisible at exactly
--- the moment the user is positioning the thing it has to fit beside.
function CBZ._ShowCastTimePlaceholder(bar, text)
    local fs = bar.castTimeText
    if not fs then return end

    if not CBZ._IsCastTimeEnabled() then
        fs:Hide()
        return
    end

    local binding = bar.timeBinding
    if binding then pcall(binding.Disable, binding) end

    pcall(fs.SetText, fs, text or EXPIRED_TEXT)
    fs:Show()
end
