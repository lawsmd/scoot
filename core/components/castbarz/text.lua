--------------------------------------------------------------------------------
-- castbarz/text.lua
-- Spell name rendering: the clipped-column banded ramp, fonts, and shrink-to-fit.
--
-- Why a banded ramp instead of a per-character |cff gradient:
--
-- addon.BuildColorRampString emits one |cff per character and hard-bails on
-- secret strings (colorramp.lua:143), and there is no native FontString gradient
-- (SetGradient is texture-only). On any unit that is not player/pet the spell
-- name is a secret, so a per-character ramp is impossible there by construction.
--
-- The banded ramp sidesteps both problems: N copies of the SAME string, each
-- clipped to a vertical column, each given one solid SetTextColor. It works
-- identically on readable and secret text, which is why Phase 2 adds units
-- without touching this file.
--
-- It also deletes the root cause of Cast Bar X pitfall #28 (the apostrophe
-- ghost). Every copy is byte-identical plain text with no escape codes at all,
-- so WoW's shaper cannot resolve kerning differently between them -- the glyph
-- alignment X had to fight for is guaranteed here by construction.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

CBZ.PREVIEW_SPELL_NAME = "Example Spell"

-- Shrink-to-fit floors, ported from textfill.lua:37-38. Expressed in point size
-- as well as a fraction of the configured size, because 0.55 of a 10pt name is
-- unreadable regardless of how well it fits. Below the floor the name is not
-- shrunk further -- it is ellipsized instead.
local FIT_MIN_POINT_SIZE = 7
local FIT_MIN_SCALE = 0.55

-- Padding either side of the name so it never touches the end caps.
local CAP_CLEARANCE = 4

--------------------------------------------------------------------------------
-- Ramp resolution
--------------------------------------------------------------------------------

-- Every unit that is not the player or their pet draws its spell name in this one
-- red ramp: dark on the left, hot on the right, the same left-to-right value climb
-- the spec gradient makes on the player's own bar.
--
-- Red because gold is already the line behind it and the two must not merge.
--
-- It used to class-color any player unit -- a target, a focus (2026-08-06, user).
-- A target's class is already stated by the target frame the bar is snapped to, so
-- spending the cast bar's only hue on it says nothing new, while making the one
-- element whose job is "something is casting at you" change color per pull. One
-- fixed red reads as a state; a class color reads as an identity, and identity is
-- not what a cast on a unit that is not you is about.
--
-- END is the color a gradient-OFF bar draws and is deliberately the exact flat red
-- that shipped before there was a ramp here, so turning the gradient off restores
-- the old look byte for byte. BASE is END darkened 35% -- deeper than the 25% the
-- class gradients used, because a single hue has only value to climb through and no
-- hue shift to carry the ramp.
CBZ.RED_RAMP_END  = { 1.00, 0.30, 0.25 }
CBZ.RED_RAMP_BASE = { 0.65, 0.20, 0.16 }

--- Interpolate NUM_BANDS stops between two endpoints.
---
--- "Flat" is expressed as a ramp with equal endpoints, so there is exactly one code
--- path and callers never branch on whether a gradient is in play.
local function BuildRamp(r1, g1, b1, r2, g2, b2)
    r1, g1, b1 = r1 or 1, g1 or 1, b1 or 1
    r2, g2, b2 = r2 or r1, g2 or g1, b2 or b1

    -- Gradient off: every band takes the ramp's endpoint -- the curated, brighter
    -- stop. Legibility beats the darker base color when there is only one.
    if CBZ._GetSetting("gradient") == false then
        r1, g1, b1 = r2, g2, b2
    end

    local n = CBZ.NUM_BANDS
    local ramp = {}
    local denom = math.max(n - 1, 1)
    for i = 1, n do
        local t = (i - 1) / denom
        ramp[i] = {
            r1 + (r2 - r1) * t,
            g1 + (g2 - g1) * t,
            b1 + (b2 - b1) * t,
        }
    end
    return ramp
end

--- Returns lineColor{r,g,b}, ramp[1..NUM_BANDS] where each entry is {r,g,b}.
---
--- Takes the BAR, not a config key. The palette belongs to whoever is casting, and
--- on the player that is the spec they are currently in; the unit itself is no
--- longer consulted on any other bar, which is what makes a Target bar's colors
--- immune to what it happens to be targeting.
---
---   Player / Pet    the player's spec gradient, whatever they are casting on
---   everything else the fixed red ramp
function CBZ._ResolveCastRamp(bar)
    local line = CBZ._ResolveLineColor(bar.unitKey)

    -- Records which branch answered, for /scoot debug castz fit. Kept now that the
    -- non-player branch is unconditional, because the player half still has two
    -- resolutions that can both render near-white -- a white-ish spec gradient and
    -- the CastBars-unavailable fallback -- and only this says which was in play.
    local function Note(source, ramp)
        bar.rampInfo = { source = source, first = ramp[1], last = ramp[#ramp], line = line }
        return line, ramp
    end

    if CBZ.OWN_CAST_UNITS[bar.unitKey] then
        local CB = addon.CastBars
        if CB and CB._resolveGradientColors then
            return Note("spec gradient", BuildRamp(CB._resolveGradientColors("specGradient", {})))
        end
        return Note("white (CastBars unavailable)", BuildRamp(1, 1, 1))
    end

    -- No unit read at all, which is the point: a preview and a live bar resolve
    -- identically, and neither repaints when the target changes.
    local base, hot = CBZ.RED_RAMP_BASE, CBZ.RED_RAMP_END
    return Note("red ramp", BuildRamp(base[1], base[2], base[3], hot[1], hot[2], hot[3]))
end

--- The palette to draw with right now.
---
--- _StartCast resolves once and caches, so the colors cannot shift mid-cast and
--- the unit is queried once rather than once per band. Three callers run when no
--- cast is in flight -- the layout pass, a spec change, and the Edit Mode stand-in
--- -- so a cache miss resolves fresh instead of erroring or drawing nothing.
function CBZ._GetRamp(bar)
    if bar.ramp then return bar.ramp end
    local _, ramp = CBZ._ResolveCastRamp(bar)
    return ramp
end

function CBZ._GetLineColor(bar)
    return bar.lineColor or CBZ._ResolveLineColor(bar.unitKey)
end

--- Drop the cached palette so the next cast resolves against its own unit.
function CBZ._ClearCastPalette(bar)
    bar.ramp = nil
    bar.lineColor = nil
end

--------------------------------------------------------------------------------
-- Font and color application
--------------------------------------------------------------------------------

local function ForEachBand(bar, fn)
    for i = 1, CBZ.NUM_BANDS do
        local dim = bar.dimBands and bar.dimBands[i]
        local bright = bar.brightBands and bar.brightBands[i]
        if dim then fn(dim.fs, i) end
        if bright then fn(bright.fs, i) end
    end
end
CBZ._ForEachBand = ForEachBand

--- Apply the configured font and the resolved ramp to all 2N FontStrings.
--- Idempotent; call it on any settings change.
function CBZ._ApplyBandFonts(bar)
    local face  = addon.ResolveFontFace(CBZ._GetSetting("fontFace"))
    local size  = tonumber(CBZ._GetSetting("fontSize")) or 14
    local style = tostring(CBZ._GetSetting("fontStyle") or "SHADOWTHICKOUTLINE")

    local ramp = CBZ._GetRamp(bar)

    ForEachBand(bar, function(fs, i)
        addon.ApplyFontStyle(fs, face, size, style)
        -- Explicitly OFF, reversing what Cast Bar X needs. Smooth scaling stops WoW
        -- snapping a scaled line height to a whole number, which matters only while
        -- something is scaling the text -- X scales, Z does not (see FitText). What
        -- it costs is sharpness: it resamples the glyph atlas instead of
        -- re-rasterising, so under a fractional UI scale every band renders soft.
        if fs.SetSmoothScaling then fs:SetSmoothScaling(false) end
        local c = ramp[i]
        if c then fs:SetTextColor(c[1], c[2], c[3], 1) end
    end)
end

--- Re-apply only the colors. Used mid-cast when interruptibility flips, where
--- re-applying the font would needlessly re-shape every copy.
function CBZ._ApplyBandColors(bar, ramp)
    ramp = ramp or CBZ._GetRamp(bar)
    ForEachBand(bar, function(fs, i)
        local c = ramp[i]
        if c then fs:SetTextColor(c[1], c[2], c[3], 1) end
    end)
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

--- Width available to the name, from DB numbers only -- never GetWidth().
local function AvailableWidth(bar)
    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    local barW = tonumber(bar.widthOverride) or tonumber(cfg and cfg.barWidth) or 200
    local capW = math.max(2, CBZ._GetCapSize() * 0.3)
    local avail = barW - (2 * capW + CAP_CLEARANCE)
    if avail <= 0 then return nil end
    return avail
end

--- Size the name to the bar.
---
--- Shrinking re-rasterises at a smaller POINT SIZE; it does not apply
--- SetTextScale. Cast Bar X has to scale, because its strings carry per-character
--- |cff codes whose hex values participate in kerning, so re-rasterising its two
--- copies could shape them differently (pitfall #28). Z's 2N copies are
--- byte-identical with no escape codes at all, so one shared integer point size
--- shapes them identically by construction -- which buys back the sharpness
--- scaling costs. SetTextScale resamples the glyph atlas rather than re-rendering,
--- and at the 0.55 floor that is visibly soft next to any other text on screen.
---
--- SetWidth(avail) is applied on EVERY path, not just the unmeasurable one. It is
--- the backstop rather than the mechanism, and it has to be unconditional because
--- three separate things can leave the name wider than the bar: the measurement
--- can under-report, the shrink floor can bite on a long name at a large font
--- size, and a settings change mid-cast re-applies the full size behind us. Z
--- deliberately carries no horizontal clip overflow -- band edges ARE the columns
--- (frames.lua:20-23) -- so an overflowing name is not merely untidy, it is sliced
--- off at both ends by the outermost bands. Bounded, the engine ellipsizes.
---
--- The measurable / unmeasurable split is decided BEFORE measuring, never inferred
--- from a nil return. addon.MeasureTextWidth pours whatever it is handed into one
--- module-local FontString shared by every caller in the addon, and SetText stamps
--- Enum.SecretAspect.Text onto whatever holds it (see
--- secret-text-is-not-measurable.md). One secret target name would therefore
--- poison that ruler for the rest of the session -- every shrink-to-fit in Scoot
--- silently stops working, addon-wide, with no error anywhere. The helper now
--- refuses secrets itself, but the caller must not be relying on that to be safe.
---
--- Engine truncation is safe here even though it wrecked Cast Bar X, for the same
--- reason re-rasterising is: no escape codes, so all 2N copies truncate alike.
local function FitText(bar, text)
    local face  = addon.ResolveFontFace(CBZ._GetSetting("fontFace"))
    local size  = tonumber(CBZ._GetSetting("fontSize")) or 14
    local style = tostring(CBZ._GetSetting("fontStyle") or "SHADOWTHICKOUTLINE")
    local avail = AvailableWidth(bar)

    if not avail then
        ForEachBand(bar, function(fs)
            fs:SetWidth(0)
            addon.ApplyFontStyle(fs, face, size, style)
        end)
        bar.fitInfo = { avail = nil, secret = false, natural = nil, size = size }
        return size
    end

    local secret = (issecretvalue and issecretvalue(text)) and true or false
    local natural
    if not secret and addon.MeasureTextWidth then
        natural = addon.MeasureTextWidth(text, face, size, style)
    end

    local fitted = size
    if natural and natural > avail then
        -- Rendered width is very close to linear in point size for a fixed string,
        -- so one division lands it. Floor rather than round, so the result errs
        -- inside the bar; the width constraint absorbs whatever it still misses.
        fitted = math.floor(size * avail / natural)
        local floorSize = math.max(FIT_MIN_POINT_SIZE, math.floor(size * FIT_MIN_SCALE))
        if floorSize > size then floorSize = size end
        if fitted < floorSize then fitted = floorSize end
    end

    ForEachBand(bar, function(fs)
        addon.ApplyFontStyle(fs, face, fitted, style)
        fs:SetWidth(avail)
    end)

    -- Plain numbers only, for /scoot debug castz fit. The point of recording them
    -- is that "the name did not shrink" has three possible causes and they are
    -- indistinguishable on screen: no measurement, a measurement that came back
    -- small enough to look like a fit, or the floor clamping.
    bar.fitInfo = { avail = avail, secret = secret, natural = natural, size = fitted }
    return fitted
end
CBZ._FitText = FitText
-- Exported alongside FitText for the same reason: anything that paints a bar
-- without a cast (previews, the local showcase) must build its ramp with the
-- same lerp and the same gradient-off collapse the live bar uses.
CBZ._BuildRamp = BuildRamp

--- Set the same bytes on every copy, then size them.
--- `text` may be a secret string; nothing here reads it back.
function CBZ._SetText(bar, text)
    if text == nil then
        CBZ._ClearText(bar)
        return
    end
    ForEachBand(bar, function(fs)
        pcall(fs.SetText, fs, text)
    end)
    FitText(bar, text)
end

--- Drop the text and, with it, the Text secret aspect.
--- ClearText releases the aspect; SetText("") does not, and a FontString left
--- holding the aspect answers every later measurement with a secret.
function CBZ._ClearText(bar)
    ForEachBand(bar, function(fs)
        if fs.ClearText then
            pcall(fs.ClearText, fs)
        else
            pcall(fs.SetText, fs, "")
        end
        fs:SetWidth(0)
    end)
    -- bar.fitInfo is deliberately NOT cleared: it is the record of the last fit,
    -- and the only moment anyone wants to read it is after the cast that looked
    -- wrong has already ended.
end
