--------------------------------------------------------------------------------
-- castbarz/anchoring.lua
-- Snapping a cast bar to the unit frame it belongs to.
--
-- Kept out of frames.lua (which owns construction) and editmode.lua (which owns
-- persistence) because placement against ANOTHER frame is a third concern, and
-- because _ResolveAnchorFrame is the single seam a future Unit Frame Z has to
-- reach: one function changes, and every bar follows the custom frame instead of
-- the Blizzard one.
--
-- Two things about snapping that the architecture already anticipated, restated
-- here because they are easy to undo by accident:
--
--   * Anchor secrecy PROPAGATES. A bar anchored to a Blizzard unit frame answers
--     GetWidth/GetHeight/GetPoint with secrets. The hard rule stands unchanged --
--     every dimension comes from the DB -- and one caller in particular
--     (editmode.lua's drag persist, which reads GetPoint) must be skipped entirely
--     on the snapped path rather than merely guarded.
--
--   * LibEditMode has no non-draggable mode. Its onMouseDown sets SetMovable(true)
--     itself (LibEditMode.lua:398), so a snapped bar registers normally, drags
--     visibly, and SPRINGS BACK on release because the callback re-applies the
--     anchor instead of storing the drop. editModeName says "(snapped)" so the
--     tooltip explains that rather than leaving it reading as a bug.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

CBZ.POSITION_MODES = { "free", "above", "below", "left", "right" }

-- Which edge of the bar meets which edge of the unit frame. above/below align
-- horizontal centers; left/right align vertical centers.
local SNAP_ANCHORS = {
    above = { barPoint = "BOTTOM", anchorPoint = "TOP" },
    below = { barPoint = "TOP",    anchorPoint = "BOTTOM" },
    left  = { barPoint = "RIGHT",  anchorPoint = "LEFT" },
    right = { barPoint = "LEFT",   anchorPoint = "RIGHT" },
}

-- Boss bars are never free. A floating boss bar cannot say WHICH boss it belongs
-- to, and five of them floating is worse than one. Coerced here rather than only
-- hidden in the settings page, so a hand-edited or migrated profile cannot detach
-- one either.
local SNAP_ONLY_UNITS = { Boss = true }

-- Blizzard's own boss placement is beside the frame, not above it
-- (BossSpellBarMixin.castBarOnSide), so that is what a coerced Boss lands on.
local COERCED_SNAP_MODE = "left"

function CBZ._IsSnapOnly(unitKey)
    return SNAP_ONLY_UNITS[unitKey] == true
end

--- The mode this unit actually renders in, after validation and coercion.
--- Never returns something SNAP_ANCHORS cannot answer for, except "free".
function CBZ._GetPositionMode(unitKey)
    local cfg = CBZ._GetUnitConfig(unitKey)
    local mode = cfg and cfg.positionMode or "free"

    if mode ~= "free" and not SNAP_ANCHORS[mode] then
        mode = "free"
    end
    if mode == "free" and SNAP_ONLY_UNITS[unitKey] then
        mode = COERCED_SNAP_MODE
    end
    return mode
end

--- The frame this bar snaps to, or nil.
---
--- The Unit Frame Z seam: a Scoot-owned frame for this unit wins over the Blizzard
--- root. Until that exists the hook is simply absent, which is why it is called
--- through a nil check rather than declared here.
---
--- Frame names come from the row (core.lua), which takes them from the verified
--- paths in ufboss.md -- never guessed, never derived from the unit token.
function CBZ._ResolveAnchorFrame(bar)
    local row = CBZ._RowForBarKey(bar.barKey)
    if not row or not row.anchorFrame then return nil end

    if CBZ._ResolveCustomAnchorFrame then
        local custom = CBZ._ResolveCustomAnchorFrame(row)
        if custom then return custom end
    end

    local frame = _G[row.anchorFrame]
    if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then
        return nil
    end
    if frame.IsForbidden and frame:IsForbidden() then return nil end
    return frame
end

--- Anchor the bar to its unit frame. Returns false when this bar is not snapped or
--- its anchor does not exist, in which case the caller positions it freely.
---
--- Anchoring is LIVE: the bar follows its unit frame when that frame is moved in
--- Edit Mode, with no position math and no re-sync. The requirement is met by
--- construction rather than by watching for changes.
function CBZ._ApplySnap(bar)
    local pair = SNAP_ANCHORS[CBZ._GetPositionMode(bar.unitKey)]
    if not pair then return false end

    local anchor = CBZ._ResolveAnchorFrame(bar)
    if not anchor then return false end

    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    local ox = CBZ._SnapToPixels(tonumber(cfg and cfg.offsetX) or 0)
    local oy = CBZ._SnapToPixels(tonumber(cfg and cfg.offsetY) or 0)

    bar:ClearAllPoints()
    bar:SetPoint(pair.barPoint, anchor, pair.anchorPoint, ox, oy)
    return true
end

--------------------------------------------------------------------------------
-- Edit Mode mirror
--------------------------------------------------------------------------------

-- Short labels, not the settings page's "Above Frame" / "Left of Frame". The
-- mirrored selector's value area is ~74px; the page's is more than twice that.
local SNAP_LABELS = { free = "Free", above = "Above", below = "Below",
                      left = "Left", right = "Right" }

--- The settings controls shown inside the Edit Mode dialog when this bar is clicked.
---
--- Position is the one part of the page worth having in Edit Mode: it is the only
--- section whose result you judge by looking at the screen rather than at the panel,
--- and for a snapped bar dragging is not an option. Everything else stays one
--- "Configure in Scoot" click away.
---
--- Returned as a description rather than built here -- the component says what it
--- wants, ui/v2/editmode/Mirror.lua decides what that looks like in a 232px box.
--- Reads and writes the same config the page does, so the two cannot drift.
function CBZ._EditModeMirror(bar)
    local unitKey = bar and bar.unitKey
    local cfg = unitKey and CBZ._GetUnitConfig(unitKey)
    if not cfg then return nil end

    local values, order = {}, {}
    for _, mode in ipairs(CBZ.POSITION_MODES) do
        -- Boss is coerced to snapped in _GetPositionMode, so offering Free here
        -- would be a control that silently refuses -- worse than one that is absent.
        if not (mode == "free" and SNAP_ONLY_UNITS[unitKey]) then
            values[mode] = SNAP_LABELS[mode]
            order[#order + 1] = mode
        end
    end

    -- The full styling pass, exactly as the settings page's setter runs it: it ends
    -- in _RestorePosition for every bar, which is what re-anchors this one and
    -- renames it.
    local function apply()
        if CBZ._comp then CBZ._ApplyStyling(CBZ._comp) end
    end

    local specs = {
        {
            kind = "selector", label = "Snap To",
            values = values, order = order,
            -- Switching to or from Free adds or removes the two sliders below, so
            -- the slot's shape changes with the value.
            rebuild = true,
            get = function() return CBZ._GetPositionMode(unitKey) end,
            set = function(v) cfg.positionMode = v; apply() end,
        },
    }

    if CBZ._GetPositionMode(unitKey) ~= "free" then
        specs[#specs + 1] = {
            kind = "slider", label = "Offset X", min = -200, max = 200, step = 1,
            get = function() return tonumber(cfg.offsetX) or 0 end,
            set = function(v) cfg.offsetX = v; apply() end,
        }
        specs[#specs + 1] = {
            kind = "slider", label = "Offset Y", min = -200, max = 200, step = 1,
            get = function() return tonumber(cfg.offsetY) or 0 end,
            set = function(v) cfg.offsetY = v; apply() end,
        }
    end

    return specs
end

--- Keep the Edit Mode label in step with the current mode.
---
--- Set on every apply pass rather than once at registration, because the mode is a
--- runtime setting: a bar registered free and later snapped would otherwise keep
--- advertising itself as draggable right up until the user tried it.
function CBZ._RefreshEditModeName(bar)
    local label = (CBZ.UNIT_LABELS[bar.unitKey] or bar.unitKey) .. " Cast Bar"

    -- Boss bars name themselves individually. They share one configuration, but
    -- five identically-named boxes in Edit Mode cannot be told apart on screen.
    if CBZ._IsSnapOnly(bar.unitKey) and bar.barKey ~= bar.unitKey then
        label = bar.barKey .. " Cast Bar"
    end
    if CBZ._GetPositionMode(bar.unitKey) ~= "free" then
        label = label .. " (snapped)"
    end

    bar.editModeName = label
end
