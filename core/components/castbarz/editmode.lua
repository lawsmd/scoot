--------------------------------------------------------------------------------
-- castbarz/editmode.lua
-- LibEditMode registration and position persistence.
--
-- Phase 1 is free positioning only. Snapping to a unit frame lands in Phase 4,
-- where the drag callback re-applies the snap anchor instead of the dropped
-- position -- kept out of here on purpose, so a snapping bug can never be
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

function CBZ._RestorePositionForLayout(barKey, layoutName)
    local bar = CBZ._bars[barKey]
    if not bar or not layoutName then return end

    -- A snapped bar has no stored position and never consults one: its placement is
    -- an anchor, so it follows its unit frame across layout switches for free.
    if CBZ._ApplySnap(bar) then return end

    local positions = EnsurePositionsDB()
    local pos = positions and positions[layoutName] and positions[layoutName][barKey]
    if not pos then
        pos = DefaultPositionFor(barKey)
    end

    local point = pos.point or "CENTER"
    bar:ClearAllPoints()
    bar:SetPoint(point, UIParent, point,
        CBZ._SnapToPixels(pos.x or 0), CBZ._SnapToPixels(pos.y or 0))
end

--- Re-apply the stored position for the layout that is currently active.
--- No-ops before the first "layout" callback; LibEditMode fires that immediately
--- on registration when a layout is already loaded (LibEditMode.lua:694-695), so
--- there is no window where a bar sits unpositioned.
function CBZ._RestorePosition(bar)
    CBZ._RefreshEditModeName(bar)

    -- Ahead of the layout check on purpose: a snapped bar is positioned by its
    -- anchor, so it must not sit unplaced in the window before the first layout
    -- callback the way a free-positioned one has no choice but to.
    if CBZ._ApplySnap(bar) then return end

    if not CBZ._currentLayout then return end
    CBZ._RestorePositionForLayout(bar.barKey, CBZ._currentLayout)
end

--------------------------------------------------------------------------------
-- LibEditMode registration
--------------------------------------------------------------------------------

--- Register one bar with LibEditMode, at the moment it is created.
---
--- Called from _EnsureBar rather than up front, so a disabled unit correctly does
--- not appear in Edit Mode at all. Registering late is safe: LibEditMode invokes
--- the position callback immediately when a layout is already loaded
--- (LibEditMode.lua:694-695), so a bar enabled mid-session is positioned on the
--- spot rather than waiting for the next layout change.
function CBZ._RegisterBarEditMode(bar, row)
    local lib = LibStub("LibEditMode", true)
    if not lib or bar._editModeRegistered then return end
    bar._editModeRegistered = true

    CBZ._RefreshEditModeName(bar)

    lib:AddFrame(bar, function(frame, layoutName, point, x, y)
        -- Snapped bars discard the drop and spring back. This returns BEFORE the
        -- persist branch below, which is required rather than tidy: that branch
        -- reads frame:GetPoint(1), and a bar anchored to a Blizzard unit frame
        -- answers that with a secret.
        if CBZ._ApplySnap(frame) then return end

        if point and x and y then
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point,
                CBZ._SnapToPixels(x), CBZ._SnapToPixels(y))
        end
        if layoutName then
            -- Persist the RESOLVED anchor, not the one we asked for.
            -- LibEditMode's normalizePosition() picks the anchor point per
            -- screen quadrant and does not preserve what you set, so
            -- storing the requested point drifts the frame on every reload
            -- (see emcustomframes.md).
            --
            -- Reading GetPoint here is safe despite the never-read-our-own-
            -- geometry rule: a free-positioned bar is anchored to UIParent,
            -- so its own anchor chain carries no secrets. Only its children
            -- anchor to the fill texture. Step 6's snapped bars must never
            -- reach this branch -- they spring back instead of persisting a
            -- drop, precisely because their GetPoint would answer secret.
            local savedPoint, _, _, savedX, savedY = frame:GetPoint(1)
            if savedPoint then
                CBZ._SavePosition(row.barKey, layoutName, savedPoint, savedX, savedY)
            else
                CBZ._SavePosition(row.barKey, layoutName, point, x, y)
            end
        end
    end, DefaultPositionFor(row.barKey), nil)

    local Brand = addon.EditMode and addon.EditMode.Brand
    if Brand then
        -- All units share one settings page with a selector strip, so the selected
        -- unit rides in pageState rather than a per-unit section. It carries the
        -- unitKey, not the barKey: every boss bar deep-links to the one Boss page.
        Brand:Register(bar, {
            navKey    = "castBarZ",
            pageState = { key = "_castBarZSelectedUnit", value = row.unitKey },
            -- Snap mode and offsets are editable in the Edit Mode box itself. They
            -- are the settings you judge by looking at the bar, and for a snapped
            -- bar there is no dragging to fall back on.
            mirror    = CBZ._EditModeMirror,
        })
    end
end

function CBZ._InitializeEditMode()
    local lib = LibStub("LibEditMode", true)
    if not lib then return end

    lib:RegisterCallback("layout", function(layoutName)
        CBZ._currentLayout = layoutName
        for barKey in pairs(CBZ._bars) do
            CBZ._RestorePositionForLayout(barKey, layoutName)
        end
    end)

    lib:RegisterCallback("enter", function()
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
    end)

    lib:RegisterCallback("exit", function()
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
    end)
end
