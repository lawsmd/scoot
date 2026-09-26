--------------------------------------------------------------------------------
-- castbarz/engine.lua
-- The cast bar engine's namespace, bar registry, and reconcile pass.
--
-- Both TOCs list this file. It draws nothing and stores nothing: a HOST file
-- loaded directly after it supplies the bars and the settings, and a PAINTER
-- supplies the draw. Every host and painter name is read at the moment of use.
--
-- Host (core.lua here, forever/castbars/host.lua there):
--   CBZ.BARS, CBZ.NUM_BOSS_BARS     one row per bar; rows may carry frameName,
--                                   defaultPosition and pageState
--   CBZ._IsModuleEnabled()          the feature's master switch
--   CBZ._IsUnitEnabled(unitKey)
--   CBZ._GetUnitConfig(unitKey)     a table: enabled, barWidth, positionMode, ...
--   CBZ._GetSetting(key, unitKey)   unitKey optional; a single-unit host may ignore it
--   CBZ._PositionStore              { get(barKey, layoutName), set(barKey, layoutName, point, x, y) }
--   CBZ.NAV_KEY                     the settings page the Edit Mode dialog opens
--
-- Painter: every name in PAINTER_CONTRACT, and bar.progressBar, a StatusBar the
-- engine hands the cast clock to with SetTimerDuration.
--
-- Optional modules: casttime.lua and empowered.lua. A host that leaves them off
-- its TOC gets a bar without a readout or tier segments (events.lua, Optional).
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.CastBarZ = addon.CastBarZ or {}
local CBZ = addon.CastBarZ

-- Runtime state (not persisted)
CBZ._bars = {}          -- [barKey] = bar frame, built lazily by _EnsureBar
CBZ._initialized = false

-- Units whose casts are the player's own. Nobody kicks their own cast, so the
-- uninterruptible treatment never applies to them (events.lua), and a painter
-- may draw them in the player's palette.
CBZ.OWN_CAST_UNITS = { Player = true, Pet = true }

CBZ.PAINTER_CONTRACT = {
    "_CreateBar", "_ApplyBar",
    "_SetText", "_ClearText",
    "_SetSparkShown", "_RefreshSparkVisibility",
    "_ShowEditModePreview",
    "_QueueFinishFX", "_StopFinishFX",
    "_BeginCastLook", "_ApplyInterruptLook", "_ShowFailureLook",
    "_StopFlash", "_ResetCastLook",
}

--- Names the loaded painter does not define. Empty on a complete painter.
function CBZ._MissingPainterNames()
    local missing = {}
    for _, name in ipairs(CBZ.PAINTER_CONTRACT) do
        if type(CBZ[name]) ~= "function" then
            missing[#missing + 1] = name
        end
    end
    return missing
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

function CBZ._RowForBarKey(barKey)
    for _, row in ipairs(CBZ.BARS) do
        if row.barKey == barKey then return row end
    end
    return nil
end

--- The first bar belonging to a config. For everything but Boss that is the only
--- one; for Boss it is boss1, which is what the settings preview should model.
function CBZ._RowForUnitKey(unitKey)
    for _, row in ipairs(CBZ.BARS) do
        if row.unitKey == unitKey then return row end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Pixel snapping
--------------------------------------------------------------------------------

-- Snap a layout offset to whole physical pixels.
--
-- Snapped against UIParent, never against the bar: reading the bar's own
-- effective scale would be a geometry read on a frame that may be secret. The bar
-- is parented to UIParent and is never re-parented or scaled, so UIParent's
-- effective scale is exactly the right divisor.
function CBZ._SnapToPixels(value)
    if not (PixelUtil and PixelUtil.GetNearestPixelSize) then return value end
    local es = UIParent and UIParent:GetEffectiveScale()
    if not es or es <= 0 then return value end
    return PixelUtil.GetNearestPixelSize(value, es)
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

--- Park the sweep at a fixed fraction. Used for the static Edit Mode preview and
--- for resetting between casts; live casts use SetTimerDuration instead.
function CBZ._SetStaticProgress(bar, frac)
    local pb = bar.progressBar
    pb:SetMinMaxValues(0, 1)
    pb:SetValue(math.max(0, math.min(1, frac or 0)))
end

--- Stop the sweep exactly where it stands, without knowing where that is.
---
--- SetTimerDuration hands the bar to C++ and nothing in Lua stops it again, so a
--- cast that ends before its duration expires keeps filling through the hold and
--- the fade. That describes EVERY empowered cast -- releasing early is the whole
--- mechanic -- and parking at 0 or 1 is a lie either way: release at tier 2 and
--- the bar reports an emptied channel or a completed one, never the tier you got.
---
--- The round trip is legal on a secret-valued bar in both directions and never
--- inspects what it moves: GetValue is SecretReturnsForAspect { BarValue }
--- (SimpleStatusBarAPIDocumentation.lua:149-161) and SetValue is
--- SecretArguments = "AllowedWhenTainted" (:331-341). The value is read and handed
--- straight back -- no comparison, no arithmetic, no type test, so there is
--- nothing for the secret system to object to.
---
--- Writing an explicit value also overrides the running timer, which is the same
--- property _FinishCast already relies on to stop an interrupted cast from
--- finishing its fill.
function CBZ._FreezeProgress(bar)
    local pb = bar.progressBar
    local ok, value = pcall(pb.GetValue, pb)
    if not ok then return false end
    return (pcall(pb.SetValue, pb, value))
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function CBZ._Initialize()
    if CBZ._initialized then return end
    CBZ._initialized = true

    -- Bars themselves are built lazily by _EnsureBar; only the machinery that has
    -- to exist before any of them do is set up here.
    CBZ._InitializeEvents()
    CBZ._InitializeEditMode()
end

--- Build a bar the first time its unit is switched on.
---
--- A disabled unit costs nothing and correctly does not appear in Edit Mode; it
--- starts existing the moment it is enabled, and is never torn down again for the
--- session.
function CBZ._EnsureBar(barKey)
    local existing = CBZ._bars[barKey]
    if existing then return existing end

    local row = CBZ._RowForBarKey(barKey)
    if not row then return nil end

    local bar = CBZ._CreateBar(row)
    CBZ._bars[barKey] = bar

    CBZ._RegisterBarEvents(bar, row)
    CBZ._RegisterBarEditMode(bar, row)

    -- The unit may already be casting -- enabling a bar mid-cast is the obvious way
    -- to test one. Deferred so the caller's _ApplyBar has laid the frame out first;
    -- syncing into an unlaid bar would paint a name across a zero-width frame.
    C_Timer.After(0, function()
        CBZ._SyncCastState(row.barKey)
    end)

    return bar
end

--------------------------------------------------------------------------------
-- Reconcile
--------------------------------------------------------------------------------

--- Bring every bar and every Blizzard-bar claim in line with the settings.
--- The one entry point for a settings change, a profile switch, and login.
function CBZ._Reconcile()
    -- Guard for profile switches: the feature stays loaded for the session, so
    -- this can be reached with it turned off.
    if not CBZ._IsModuleEnabled() then
        if CBZ._initialized then
            for _, bar in pairs(CBZ._bars) do
                bar:Hide()
            end
        end
        -- Hand Blizzard's bars back. Safe on a profile that never enabled the
        -- feature: this only ever writes to a frame the engine itself suppressed.
        CBZ._ApplySuppression()
        return
    end

    CBZ._Initialize()

    for _, row in ipairs(CBZ.BARS) do
        if CBZ._IsUnitEnabled(row.unitKey) then
            CBZ._EnsureBar(row.barKey)
        end
        CBZ._ApplyBar(row.barKey)
    end

    -- Last, and covering every bar in one pass rather than per row: Boss is five
    -- bars behind one enable, and this is the only place that knows the whole
    -- picture. Writes only on a change, so a slider drag costs nothing here.
    CBZ._ApplySuppression()
end
