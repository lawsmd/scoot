--------------------------------------------------------------------------------
-- forever/unitframes/suppression.lua
-- Takes Blizzard's unit frame off screen while Camelot draws the unit.
--
-- The how is addon.NativeFrame (core/nativeframe.lua): a top-level frame is
-- parked under a hidden holder, and a child of a system frame is dimmed,
-- because a system's own code reads its children's parent. This file is the
-- when, and the list.
--
-- Parking PlayerFrame takes its subtree with it: PetFrame, the totem frame,
-- and the player cast bar while it is locked to the player frame. Parking
-- TargetFrame takes TargetFrameToT and the target cast bar. The pet and
-- target-of-target rows below cover the case where Camelot draws the small
-- frame and Blizzard still draws the large one. ComboFrame is its own
-- top-level frame anchored to TargetFrame, so it goes with the target's row
-- (combopoints.lua draws the points).
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames

local Suppression = {}
UF.Suppression = Suppression

local OWNER = "camelotUnitFrames"

-- Player, target and focus are not frame-manager frames, so the Edit Mode
-- layout pass never re-parents them and none needs a quiet list.
local BLIZZARD_FRAME = {
    player       = { name = "PlayerFrame", method = "park" },
    target       = { name = "TargetFrame", method = "park", also = { "ComboFrame" } },
    focus        = { name = "FocusFrame", method = "park" },
    targettarget = { name = "TargetFrameToT", method = "alpha" },
    pet          = { name = "PetFrame", method = "alpha" },
}

-- Which frames Camelot holds. Nothing is released that was not suppressed
-- first, so a profile with the frames off never sees this file touch a
-- Blizzard frame in either direction.
local suppressed = {}

function Suppression.FrameName(key)
    local row = BLIZZARD_FRAME[key]
    return row and row.name or nil
end

function Suppression.IsSuppressed(key)
    local row = BLIZZARD_FRAME[key]
    local frame = row and _G[row.name]
    return frame and addon.NativeFrame:IsSuppressed(frame) or false
end

--- Re-assert every claim held. Called on Edit Mode enter and exit, both inside
--- the window in which NativeFrame refuses to re-parent: the call schedules its
--- retry, which pays the park once the window closes.
function Suppression.ReassertAll()
    if not next(suppressed) then return end
    addon.NativeFrame:Reapply()
end

--- Reconcile every Blizzard frame against what Camelot is drawing. Writes only
--- on a transition.
function Suppression.Apply()
    local moduleOn = addon.DB.IsModuleEnabled("unitFrames")

    for _, key in ipairs(UF.ORDER) do
        local row = BLIZZARD_FRAME[key]
        local want = (moduleOn and row ~= nil and UF.IsEnabled(key)) or false

        if want ~= (suppressed[key] == true) then
            local frame = row and _G[row.name]
            -- A frame that does not exist yet leaves the row unclaimed, so the
            -- next pass tries again.
            if frame then
                if want then
                    addon.NativeFrame:Suppress(frame, OWNER, row.method)
                else
                    addon.NativeFrame:Release(frame, OWNER)
                end
                for _, name in ipairs(row.also or {}) do
                    local other = _G[name]
                    if other and want then
                        addon.NativeFrame:Suppress(other, OWNER, "park")
                    elseif other then
                        addon.NativeFrame:Release(other, OWNER)
                    end
                end
                suppressed[key] = want or nil
            end
        end
    end
end
