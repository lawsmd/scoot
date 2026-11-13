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
    inst.noPowerText = noPower
    addon.UnitFrames.Values.ApplyBarTextShown(inst)
end

-- Forever reads happiness from C_PetInfo, as its PetHappiness.lua does; the
-- global is vanilla's. Neither exists on a client without the mechanic.
local readHappiness = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness

local function hideHappiness(inst)
    inst.regions.happiness:Hide()
    if inst.happinessHover then inst.happinessHover:Hide() end
end

local function isHunterPet()
    local _, isHunter = HasPetUI()
    return not issecretvalue(isHunter) and isHunter
end

-- The client's atlas for the mood, or the old sheet's cell where the client
-- lacks the name. The reset comes first: the region is built on a cell, and
-- SetAtlas applies coordinates it finds inside the atlas rect.
local function setHappinessFace(inst, happiness)
    local face = inst.regions.happiness
    face:SetTexCoord(0, 1, 0, 1)
    if not Art.SetAtlas(face, inst.spec.HappinessAtlas[happiness], false) then
        local coords = inst.spec.HappinessCoords[happiness]
        face:SetTexture(Art.Paths.petHappiness)
        face:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

-- Shown for a hunter's pet that reports a mood, the client's own test
-- (PetHappinessIndicatorMixin:ShouldShow).
local function applyHappiness(inst)
    if inst.previewStandIn or not readHappiness or not isHunterPet() then
        hideHappiness(inst)
        return
    end
    local ok, happiness, damagePercentage, loyaltyRate = pcall(readHappiness)
    if not ok or issecretvalue(happiness) or not inst.spec.HappinessAtlas[happiness] then
        hideHappiness(inst)
        return
    end
    setHappinessFace(inst, happiness)
    inst.regions.happiness:Show()
    local hover = inst.happinessHover
    if hover then
        hover.happiness = happiness
        hover.damagePercentage = not issecretvalue(damagePercentage) and damagePercentage or nil
        hover.loyaltyRate = not issecretvalue(loyaltyRate) and loyaltyRate or nil
        hover:Show()
    end
end

local function addDietLine()
    local getFoodTypes = C_PetInfo and C_PetInfo.GetPetFoodTypes
    if not getFoodTypes then return end
    local ok, diet = pcall(getFoodTypes)
    if not ok or type(diet) ~= "table" then return end
    local foods = #diet > 0 and table.concat(diet, PET_FOOD_DELIMIT) or NONE
    GameTooltip_AddNormalLine(GameTooltip, PET_DIET_TEMPLATE:format(foods))
end

-- PetHappinessIndicatorMixin:OnEnter's lines in its order.
local function showHappinessTooltip(hover)
    GameTooltip:SetOwner(hover, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, _G["PET_HAPPINESS" .. hover.happiness] or NONE)
    if hover.damagePercentage then
        GameTooltip_AddNormalLine(GameTooltip, PET_DAMAGE_PERCENTAGE:format(hover.damagePercentage))
    end
    local loyaltyRate = hover.loyaltyRate
    if loyaltyRate and loyaltyRate < 0 then
        GameTooltip_AddNormalLine(GameTooltip, LOSING_LOYALTY)
    elseif loyaltyRate and loyaltyRate > 0 then
        GameTooltip_AddNormalLine(GameTooltip, GAINING_LOYALTY)
    end
    addDietLine()
    GameTooltip:Show()
end

-- The face is a texture, which takes no mouse, so a frame over it carries the
-- tooltip. Motion only: the scripts turn clicks on, so they are set first.
local function buildHappinessHover(inst)
    local hover = CreateFrame("Frame", nil, inst.artFrame)
    hover:SetAllPoints(inst.regions.happiness)
    hover:SetScript("OnEnter", showHappinessTooltip)
    hover:SetScript("OnLeave", GameTooltip_Hide)
    hover:SetMouseClickEnabled(false)
    hover:SetMouseMotionEnabled(true)
    hover:Hide()
    inst.happinessHover = hover
end

-- Registering an event the client does not know throws, and the addon also
-- loads on clients without the mechanic, so the registration is under pcall
-- and only where a read exists.
local function watchHappiness(inst)
    if readHappiness then
        pcall(inst.frame.RegisterUnitEvent, inst.frame, "UNIT_HAPPINESS", inst.unit)
        buildHappinessHover(inst)
    end
end

-- The reads the Modern pet frame shares (modern/pet.lua): both specs name
-- the face and carry its cells, and the client's own pet frame keeps the
-- face in both styles.
addon.UnitFrames.PetState = {
    ApplyHappiness = applyHappiness,
    WatchHappiness = watchHappiness,
}

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
    -- Its center 28 right of and 36 under the player's default center, the
    -- offset the presets keep too (forever/startingpoints.lua), rounded to 5.
    -- Vanilla's spot is TOPLEFT 61, -64.
    default = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 230, y = -210 },
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
    build = watchHappiness,
})
