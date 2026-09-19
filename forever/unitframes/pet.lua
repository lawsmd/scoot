--------------------------------------------------------------------------------
-- forever/unitframes/pet.lua
-- The Classic pet frame. The painter is frame.lua and the art is artpet.lua;
-- this file is what PetFrameMixin keeps: the border for a pet with no power
-- bar, the attack wash, and the happiness face.
--
-- Vanilla parents the pet frame to the player frame and lets a layout
-- container place it. Here it is a frame of its own with its own Edit Mode
-- position, and its default is the spot the old PetFrame XML gave it against
-- the player frame's default.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Frame = addon.UnitFrames.Frame

-- UnitPowerMax is a plain read. A pet with none takes the art with the lower
-- bar slot closed.
local function applyPowerSlot(inst)
    local noPower = false
    if not inst.previewStandIn then
        local max = UnitPowerMax(inst.unit)
        noPower = not issecretvalue(max) and max == 0
    end
    Art.ApplyBorder(inst, noPower and "borderSmallNoMana" or "borderSmall")
    inst.powerBar:SetShown(not noPower)
    if inst.powerText then inst.powerText:SetShown(not noPower) end
end

-- The face is built only where the client still has the mechanic. It shows for
-- a pet that reports a happiness, which in vanilla is a hunter's.
local function applyHappiness(inst)
    local face = inst.regions.happiness
    if inst.previewStandIn or not GetPetHappiness then
        face:Hide()
        return
    end
    local ok, happiness = pcall(GetPetHappiness)
    local coords = ok and not issecretvalue(happiness) and inst.spec.HappinessCoords[happiness]
    if coords then
        face:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        face:Show()
    else
        face:Hide()
    end
end

local function paintState(inst)
    applyPowerSlot(inst)
    applyHappiness(inst)
    -- PetFrameMixin:Update clears the wash; PET_ATTACK_START brings it back.
    Frame.SetPulsed(inst, "attackMode", false)
end

Frame.Define({
    key = "pet",
    unit = "pet",
    label = "Pet",
    frameName = "CamelotPetFrame",
    -- Beta stand-in: vanilla's offset from the player frame (80 right, 60
    -- down), kept against the player's stand-in. Vanilla's spot is TOPLEFT
    -- 61, -64.
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
            applyHappiness(inst)
            return true
        end
        return false
    end,
    events = {
        PET_ATTACK_START = function(inst) Frame.SetPulsed(inst, "attackMode", true) end,
        PET_ATTACK_STOP = function(inst) Frame.SetPulsed(inst, "attackMode", false) end,
    },
    paintState = paintState,

    build = function(inst)
        -- Registering an event the client does not know throws, and whether
        -- Forever knows this one is the open question.
        if GetPetHappiness then
            pcall(inst.frame.RegisterUnitEvent, inst.frame, "UNIT_HAPPINESS", inst.unit)
        end
    end,
})
