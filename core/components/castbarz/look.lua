--------------------------------------------------------------------------------
-- castbarz/look.lua
-- Cast Bar Z's answers to the engine's cast-state calls (engine.lua,
-- PAINTER_CONTRACT): what a starting, locked, failed and reset cast look like.
--
-- The engine (events.lua) decides WHEN each of these happens and never what it
-- draws. Everything here is Z's draw: the banded ramp, the line, the glow.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

-- Interrupt / failure presentation. The glow's peak alpha belongs to the texture,
-- not to this file: it depends on which art the frame ended up with (frames.lua).
-- Blizzard fades InterruptGlow over 1.0s (CastingBarFrame.xml:188); shortened here
-- so the glow is spent before the bar itself starts fading at HOLD_FAILED.
-- Two reds, not one. The name sits directly on the line, so a single red made the
-- word and its backdrop the same value and the text stopped separating. The line
-- goes lighter (toward white) and the text darker, splitting them either side of
-- the original 0.95/0.35/0.30.
local FAIL_LINE_COLOR = { 0.96, 0.48, 0.44 }
local FAIL_TEXT_COLOR = { 0.76, 0.28, 0.24 }
local FLASH_TIME = 0.60

--- Resolve the palette once and cache it for the life of the cast. Every
--- consumer -- bands, spark, completion FX -- reads the cache.
function CBZ._BeginCastLook(bar)
    bar.lineColor, bar.ramp = CBZ._ResolveCastRamp(bar)

    -- The spark and the completion effect are colored by the layout pass, which
    -- runs on settings changes only -- so without this they would keep the palette
    -- of whoever this bar's unit was when the panel was last touched. Cheap: both
    -- reuse their existing regions rather than rebuilding.
    CBZ._RecolorSpark(bar)
    CBZ._RecolorFinishFX(bar)
end

--- Interruptibility is the LINE's axis: white for locked, gold for kickable,
--- right behind the word. Applied as a color override rather than by selecting a
--- different palette, because selecting anything would require reading the flag.
function CBZ._ApplyInterruptLook(bar, notInterruptible)
    local line = CBZ._PickColor(notInterruptible, CBZ.LINE_COLOR_LOCKED, CBZ._GetLineColor(bar))
    -- No-op while tier segments are up -- they carry a palette, not one color.
    CBZ._ApplyLineColor(bar, line[1], line[2], line[3])

    -- The NAME takes no interruptibility override -- it keeps its ramp whatever the
    -- flag says. Draining the word to grey-white as well spent the bar's two
    -- channels saying one thing twice, and on a boss it read as the bar having lost
    -- its colors rather than as a cast you cannot kick -- the same misreading that
    -- took the override off player and pet (events.lua, _ApplyInterruptState).
    CBZ._ApplyBandColors(bar, CBZ._GetRamp(bar))
end

--- The interrupted / failed look. The engine has already snapped the sweep to
--- full and written the reason into the name.
function CBZ._ShowFailureLook(bar, reason)
    local flat = {}
    for i = 1, CBZ.NUM_BANDS do flat[i] = FAIL_TEXT_COLOR end
    CBZ._ApplyBandColors(bar, flat)
    CBZ._ApplyLineColor(bar, FAIL_LINE_COLOR[1], FAIL_LINE_COLOR[2], FAIL_LINE_COLOR[3])

    local flash = bar.flashFrame
    if flash then
        UIFrameFadeRemoveFrame(flash)
        local peak = flash.peakAlpha or 1
        flash:SetAlpha(peak)
        flash:Show()
        UIFrameFadeOut(flash, FLASH_TIME, peak, 0)
    end
end

function CBZ._StopFlash(bar)
    if bar.flashFrame then
        UIFrameFadeRemoveFrame(bar.flashFrame)
        bar.flashFrame:Hide()
    end
end

--- Drop the cached palette so the next cast resolves against its own unit.
--- `repaint` redraws the idle bar from a fresh palette, for a spec change.
function CBZ._ResetCastLook(bar, repaint)
    CBZ._ClearCastPalette(bar)
    if repaint then
        CBZ._ApplyBandColors(bar, nil)
    end
end
