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

-- Starting positions, one per BAR, in UIParent space. Keyed by barKey so the five
-- boss bars can stack rather than land on top of each other.
local DEFAULT_POSITIONS = {
    Player = { point = "CENTER", x =    0, y = -180 },
    Target = { point = "CENTER", x =    0, y =  180 },
    Focus  = { point = "CENTER", x = -320, y =  180 },
    Pet    = { point = "CENTER", x =    0, y = -224 },
}

-- Boss bars stack downward rather than sharing a point. They are snap-only from
-- step 6 onward, so these are only ever seen in the window before a layout is
-- saved -- but five bars at one position reads as one broken bar, not five.
for i = 1, CBZ.NUM_BOSS_BARS do
    DEFAULT_POSITIONS["Boss" .. i] = {
        point = "CENTER", x = 320, y = 180 - (i - 1) * 44,
    }
end

local function DefaultPositionFor(barKey)
    return DEFAULT_POSITIONS[barKey] or { point = "CENTER", x = 0, y = -180 }
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

local function EnsurePositionsDB()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end
    if not profile.castBarZPositions then
        profile.castBarZPositions = {}
    end
    return profile.castBarZPositions
end

function CBZ._SavePosition(barKey, layoutName, point, x, y)
    local positions = EnsurePositionsDB()
    if not positions or not layoutName then return end
    if not positions[layoutName] then
        positions[layoutName] = {}
    end
    positions[layoutName][barKey] = { point = point, x = x, y = y }
end

local function GetBarPosition(barKey, layoutName)
    local positions = EnsurePositionsDB()
    return positions and positions[layoutName] and positions[layoutName][barKey] or nil
end

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
--- moment it is created. Storage stays castBarZPositions[layoutName][barKey].
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
        default = DefaultPositionFor(row.barKey),
        store = { get = GetBarPosition, set = CBZ._SavePosition },
        apply = ApplyBarPosition,
        restoreDefault = true,
        brand = {
            navKey    = "castBarZ",
            pageState = { key = "_castBarZSelectedUnit", value = row.unitKey },
            mirror    = CBZ._EditModeMirror,
        },
    })
end

function CBZ._InitializeEditMode()
    addon.EditMode.OnEditMode("castBarZ", {
        enter = function()
            CBZ._editModeActive = true

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
            CBZ._editModeActive = false

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
