--------------------------------------------------------------------------------
-- forever/unitframes/player.lua
-- The Classic player frame: what it has that no other unit frame does, the
-- rested and in-combat state art and the master looter pip. The painter is
-- frame.lua and the art is artplayer.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame

--------------------------------------------------------------------------------
-- State art
--------------------------------------------------------------------------------

-- Vanilla's own order, from PlayerFrame_UpdateStatus: resting wins over combat,
-- and each state owns both an icon and the additive wash behind the bars. The
-- two vertex colours are Blizzard's.
local function applyStateArt(inst)
    local r = inst.regions
    local resting = IsResting()
    local inCombat = UnitAffectingCombat(inst.unit)

    if resting then
        r.playerStatus:SetVertexColor(1.0, 0.88, 0.25, 1.0)
        Frame.SetPulsed(inst, "playerStatus", true)
        Frame.SetPulsed(inst, "restGlow", true)
        Frame.SetPulsed(inst, "attackGlow", false)
        r.restIcon:Show()
        r.attackIcon:Hide()
        r.attackBackground:Hide()
    elseif inCombat then
        r.playerStatus:SetVertexColor(1.0, 0.0, 0.0, 1.0)
        Frame.SetPulsed(inst, "playerStatus", true)
        Frame.SetPulsed(inst, "attackGlow", true)
        Frame.SetPulsed(inst, "restGlow", false)
        r.attackIcon:Show()
        r.restIcon:Hide()
        r.attackBackground:Show()
    else
        Frame.SetPulsed(inst, "playerStatus", false)
        Frame.SetPulsed(inst, "restGlow", false)
        Frame.SetPulsed(inst, "attackGlow", false)
        r.restIcon:Hide()
        r.attackIcon:Hide()
        r.attackBackground:Hide()
    end
end

local function applyGroupPips(inst)
    local r = inst.regions
    r.leaderIcon:SetShown(UnitIsGroupLeader and UnitIsGroupLeader(inst.unit) or false)

    local shown = false
    if GetLootMethod then
        local method, partyIndex = GetLootMethod()
        shown = method == "master" and partyIndex == 0
    end
    r.masterLooterIcon:SetShown(shown and true or false)
end

--------------------------------------------------------------------------------
-- Definition
--------------------------------------------------------------------------------

Frame.Define({
    key = "player",
    unit = "player",
    label = "Player",
    frameName = "CamelotPlayerFrame",
    -- Beta stand-in, in center-origin coordinates: the Forever beta keeps no
    -- Edit Mode position across a reload, so the default is the layout.
    -- Vanilla's own spot, from the PlayerFrame XML, is TOPLEFT -19, -4.
    default = { point = "CENTER", relPoint = "CENTER", x = -340, y = -300 },
    strataLevel = 10,

    paintState = function(inst)
        applyStateArt(inst)
        applyGroupPips(inst)
    end,

    events = {
        PLAYER_UPDATE_RESTING = applyStateArt,
        PLAYER_REGEN_DISABLED = applyStateArt,
        PLAYER_REGEN_ENABLED = applyStateArt,
        PARTY_LEADER_CHANGED = applyGroupPips,
        PARTY_LOOT_METHOD_CHANGED = applyGroupPips,
    },
})
