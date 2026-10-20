--------------------------------------------------------------------------------
-- forever/unitframes/modern/pet.lua
-- The Modern pet frame: the pet frame this client draws itself, as a second
-- style of the pet unit frame, on the painter in frame.lua over the art in
-- artpet.lua beside this file. This file is the state PetFrameMixin keeps
-- under the client's override layer: the power text hidden for a pet with
-- no power, the attack wash, and the happiness face the client's own pet
-- XML adds.
--
-- The happiness face is the Classic frame's own read (pet.lua beside this
-- folder, PetState), since both specs name the same region and carry the
-- same cells. Left out, as the Classic frame leaves them out: the vehicle
-- swap to the player unit, the hit indicator, and the threat flash, which
-- is built hidden and nothing drives.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame
local Values = addon.UnitFrames.Values
local PetState = addon.UnitFrames.PetState

-- PetFrameMixin:Update hides the power text for a pet with no power and
-- keeps the bar, which the client's own frame does too. UnitPowerMax is a
-- plain read.
local function applyPowerSlot(inst)
    local noPower = false
    if not inst.previewStandIn then
        local max = UnitPowerMax(inst.unit)
        noPower = not issecretvalue(max) and max == 0
    end
    inst.noPowerText = noPower
    Values.ApplyBarTextShown(inst)
end

local function paintState(inst)
    applyPowerSlot(inst)
    PetState.ApplyHappiness(inst)
    -- PetFrameMixin:Update clears the wash; PET_ATTACK_START brings it back.
    Frame.SetPulsed(inst, "attackMode", false)
end

Frame.Define({
    key = "pet",
    style = "modern",
    unit = "pet",
    label = "Pet",
    frameName = "CamelotModernPetFrame",
    -- The Camelot layout's spot, the Classic instance's own, so a style swap
    -- on that layout keeps the frame where it was; a profile started from a
    -- Blizzard preset has both instances' defaults rewritten from the
    -- preset's data. One table per frame, never shared: Edit Mode keeps it
    -- by reference.
    default = { point = "CENTER", relPoint = "CENTER", x = -312, y = -336 },
    -- Over the player frame, whose lower edge it overlaps.
    strataLevel = 20,

    changeEvents = {
        UNIT_PET = "player",
        PET_UI_UPDATE = true,
    },
    onUnitEvent = function(inst, event)
        if event == "UNIT_MAXPOWER" then applyPowerSlot(inst) end
        if event == "UNIT_HAPPINESS" then
            PetState.ApplyHappiness(inst)
            return true
        end
        return false
    end,
    events = {
        PET_ATTACK_START = function(inst) Frame.SetPulsed(inst, "attackMode", true) end,
        PET_ATTACK_STOP = function(inst) Frame.SetPulsed(inst, "attackMode", false) end,
    },
    paintState = paintState,

    build = PetState.WatchHappiness,
})
