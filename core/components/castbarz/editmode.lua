--------------------------------------------------------------------------------
-- castbarz/editmode.lua
-- LibEditMode registration and position persistence.
--
-- Free positioning only. Snapping to a unit frame is handled elsewhere, by a
-- drag callback that re-applies the snap anchor instead of the dropped
-- position. Kept out of this file on purpose, so a snapping bug can never be
-- mistaken for a rendering bug.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

-- The host supplies the starting position on each row (row.defaultPosition) and
-- the storage (CBZ._PositionStore); see engine.lua.
local FALLBACK_POSITION = { point = "CENTER", x = 0, y = -180 }

-- A snapped bar discards a drop and springs back. Returning true also skips
-- the persist, which is required rather than tidy: the persist reads
-- frame:GetPoint(1), and a bar anchored to a Blizzard unit frame answers that
-- with a secret. On a restore the same check keeps a snapped bar on its
-- anchor: it has no stored position and never consults one, so it follows its
-- unit frame across layout switches for free.
local function ApplyBarPosition(bar, point, x, y)
    if CBZ._ApplySnap(bar) then return true end
    bar:ClearAllPoints()
    bar:SetPoint(point, UIParent, point, CBZ._SnapToPixels(x), CBZ._SnapToPixels(y))
end

--- Re-apply the stored position, or the default, for the active layout.
--- A no-op before the first "layout" callback, except for a snapped bar.
function CBZ._RestorePosition(bar)
    CBZ._RefreshEditModeName(bar)

    -- Ahead of the layout check on purpose: a snapped bar is positioned by its
    -- anchor, so it must not sit unplaced in the window before the first layout
    -- callback the way a free-positioned one has no choice but to.
    if CBZ._ApplySnap(bar) then return end

    addon.EditMode.RestorePositionable(bar)
end

--------------------------------------------------------------------------------
-- LibEditMode registration
--------------------------------------------------------------------------------

--- Register one bar as a positionable (core/editmode/positionables.lua), at the
--- moment it is created. Storage is the host's (CBZ._PositionStore).
---
--- Called from _EnsureBar rather than up front, so a disabled unit correctly does
--- not appear in Edit Mode at all. Registering late is safe: the helper restores
--- the bar at registration when a layout is already loaded, so a bar enabled
--- mid-session is positioned on the spot rather than waiting for the next layout
--- change.
function CBZ._RegisterBarEditMode(bar, row)
    CBZ._RefreshEditModeName(bar)

    addon.EditMode.RegisterPositionable(bar, {
        key = row.barKey,
        default = row.defaultPosition or FALLBACK_POSITION,
        store = CBZ._PositionStore,
        apply = ApplyBarPosition,
        restoreDefault = true,
        -- A snapped bar discards drops and its live anchor answers secret, so
        -- the dialog's position row renders only in free mode.
        positionEditable = function(b)
            return CBZ._GetPositionMode(b.unitKey) == "free"
        end,
        brand = {
            navKey    = CBZ.NAV_KEY,
            pageState = row.pageState,
            mirror    = CBZ._EditModeMirror,
        },
    })
end

function CBZ._InitializeEditMode()
    addon.EditMode.OnEditMode("castBarZ", {
        enter = function()
            -- Blizzard force-shows its own cast bar for the whole of Edit Mode --
            -- UpdateShownState bails out early with StopFinishAnims / ApplyAlpha(1.0)
            -- / Show() the moment isInEditMode is set (CastingBarFrame.lua:84-90),
            -- which Edit Mode sets on entry via EditModeFrameSetup -> RefreshCastBar
            -- (EditModeManager.lua:2188). A parked frame is immune to all three, but
            -- this re-asserts the green selection outline, which is ignoreParentAlpha
            -- and so has to be suppressed on its own terms.
            CBZ._ReassertAllSuppression()

            -- Cast bars are invisible unless something is casting, so Edit Mode has
            -- nothing to grab without a stand-in.
            for _, bar in pairs(CBZ._bars) do
                if CBZ._IsUnitEnabled(bar.unitKey) then
                    CBZ._ShowEditModePreview(bar)
                end
            end
        end,
        exit = function()
            -- Where the deferred claim gets paid. Re-parenting is skipped while the
            -- Edit Mode manager is on screen (writing there taints the manager itself,
            -- not just the frame), so every suppression that entered Edit Mode unapplied
            -- lands here on the way out.
            CBZ._ReassertAllSuppression()

            for _, bar in pairs(CBZ._bars) do
                if not bar.casting then
                    bar:Hide()
                    CBZ._ClearText(bar)
                    CBZ._SetStaticProgress(bar, 0)
                end
            end
        end,
    })
end
