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

-- An NPC has no class and no gradient worth inventing, so its name is drawn flat.
-- Red because gold is already the line behind it and the two must not merge.
CBZ.NPC_RAMP_COLOR = { 1.00, 0.30, 0.25 }

-- The treatment Cast Bar X applies to every gradient it builds
-- (unitframes/cast/core.lua:66-67, :79-80): darken the base, lighten the curated
-- endpoint. Duplicated as named constants rather than reached for through CB,
-- because CB._resolveGradientColors hardcodes "player" and cannot answer for a
-- target -- but the two must still look like the same addon drew them.
local GRADIENT_DARKEN  = 0.25
local GRADIENT_LIGHTEN = 0.10

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

--- Is this unit a player character? Plain answers only.
---
--- Guard order is type() -> issecretvalue() -> use, never the reverse: type()
--- reports the REAL type of a secret, so a `type(v) == "boolean"` test PASSES on a
--- secret and any following truth-test throws (secret-guard-ordering).
---
--- This gate is mandatory before class coloring, not defensive: NPCs carry class
--- tokens that mean nothing (npc-identity-not-always-secret), so skipping it paints
--- a boar in Rogue yellow.
local function IsPlayerUnit(unit)
    if not unit or not UnitIsPlayer then return false end
    local ok, v = pcall(UnitIsPlayer, unit)
    if not ok then return false end
    if type(v) ~= "boolean" then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return v
end

--- That unit's own class gradient, or nil when the class cannot be read.
---
--- addon.GetClassTokenForUnit is already fully secret-guarded and returns nil
--- rather than a secret (colors.lua:155-188), so there is no second guard here --
--- adding one would only hide which layer refused.
local function ClassGradientFor(unit)
    local token = addon.GetClassTokenForUnit and addon.GetClassTokenForUnit(unit)
    if not token then return nil end

    local r, g, b = addon.GetClassColorRGB(token)
    if not r then return nil end

    local endpoints = addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[token]
    if not endpoints then
        local CB = addon.CastBars
        local lr, lg, lb = addon.LightenColor(r, g, b, (CB and CB.SPELL_LIGHTEN_RATIO) or 0.35)
        return r, g, b, lr, lg, lb
    end

    local dr, dg, db = addon.DarkenColor(r, g, b, GRADIENT_DARKEN)
    local er, eg, eb = addon.LightenColor(endpoints[1], endpoints[2], endpoints[3], GRADIENT_LIGHTEN)
    return dr, dg, db, er, eg, eb
end

--- Returns lineColor{r,g,b}, ramp[1..NUM_BANDS] where each entry is {r,g,b}.
---
--- Takes the BAR, not a config key. The palette belongs to whoever is casting
--- (`bar.unit`), which is fixed for the player but changes under Target and Focus;
--- resolving from the config key would leave a target bar painted in the previous
--- unit's colors until something else forced a restyle.
---
---   Player / Pet    the player's spec gradient, whatever they are casting on
---   any other player that unit's class gradient
---   NPC             flat red
function CBZ._ResolveCastRamp(bar)
    local line = CBZ._ResolveLineColor(bar.unitKey)
    local flat = CBZ.NPC_RAMP_COLOR

    -- Records which branch answered, for /scoot debug castz fit. Not cleared with
    -- the palette: three different resolutions can render as "white" (a near-white
    -- class gradient, the spec fallback, and the uninterruptible override painted
    -- over any of them) and only this says which one was in play. The override
    -- itself is unrecordable -- it is chosen from a secret, so no branch of ours
    -- ever learns which color it produced.
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

    -- A preview never consults a live unit. bar.unit on a preview is a real token,
    -- so without this the Target pane would repaint itself every time the user
    -- changed target with the settings panel open -- and a swatch that moves while
    -- you are reading it is worse than one that is merely representative.
    if bar.isPreview then
        return Note("preview flat red", BuildRamp(flat[1], flat[2], flat[3]))
    end

    if IsPlayerUnit(bar.unit) then
        local r1, g1, b1, r2, g2, b2 = ClassGradientFor(bar.unit)
        if r1 then
            return Note("class gradient", BuildRamp(r1, g1, b1, r2, g2, b2))
        end
        return Note("flat red (player, class unreadable)", BuildRamp(flat[1], flat[2], flat[3]))
    end

    return Note("flat red (not a player unit)", BuildRamp(flat[1], flat[2], flat[3]))
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
    local style = tostring(CBZ._GetSetting("fontStyle") or "OUTLINE")

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
    local style = tostring(CBZ._GetSetting("fontStyle") or "OUTLINE")
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
