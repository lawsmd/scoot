-- petbattle.lua - Hide addon frames during pet battles
local addonName, addon = ...

local isInPetBattle = false
local registeredFrames = {}   -- { [frame] = true }
local savedVisibility = {}    -- { [frame] = wasShown }

-- Public API
function addon.RegisterPetBattleFrame(frame)
    if not frame or registeredFrames[frame] then return end
    registeredFrames[frame] = true
    -- Safety net: immediately re-hide if shown during pet battle
    frame:HookScript("OnShow", function(self)
        if isInPetBattle then self:Hide() end
    end)
    -- Late registration: if pet battle already active, hide immediately
    if isInPetBattle and frame:IsShown() then
        savedVisibility[frame] = true
        frame:Hide()
    end
end

function addon.IsInPetBattle()
    return isInPetBattle
end

-- Internal
local function HideAll()
    for frame in pairs(registeredFrames) do
        local shown = frame:IsShown()
        savedVisibility[frame] = shown
        if shown then frame:Hide() end
    end
end

local function RestoreAll()
    for frame, wasShown in pairs(savedVisibility) do
        if wasShown and registeredFrames[frame] then
            frame:Show()
        end
    end
    wipe(savedVisibility)
end

-- Events
local function onEvent(event)
    if event == "PET_BATTLE_OPENING_START" then
        isInPetBattle = true
        HideAll()
    elseif event == "PET_BATTLE_CLOSE" then
        isInPetBattle = false
        RestoreAll()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Safety: handle /reload during pet battle
        if C_PetBattles and C_PetBattles.IsInBattle() then
            isInPetBattle = true
            HideAll()
        end
    end
end
addon.Events.On("PetBattle", "PET_BATTLE_OPENING_START", onEvent)
addon.Events.On("PetBattle", "PET_BATTLE_CLOSE", onEvent)
addon.Events.On("PetBattle", "PLAYER_ENTERING_WORLD", onEvent)
