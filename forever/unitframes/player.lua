--------------------------------------------------------------------------------
-- forever/unitframes/player.lua
-- The Classic player frame: what it has that no other unit frame does, the
-- rested and in-combat state art, the leader and master looter pips, and the
-- repaint on death and release. The painter is
-- frame.lua and the art is artplayer.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame

--------------------------------------------------------------------------------
-- State art
--------------------------------------------------------------------------------

-- Vanilla's own order, from PlayerFrame_UpdateStatus: resting, then attacking
-- (auto-attack on, PLAYER_ENTER_COMBAT), then on the hate list (in combat,
-- PLAYER_REGEN_DISABLED), which shows the swords alone. Vanilla's hate-list
-- branch leaves the red wash up after the swing stops; this one hides it. The
-- two vertex colours are Blizzard's.
local function applyStateArt(inst)
    local r = inst.regions
    local resting = IsResting()

    if resting then
        r.playerStatus:SetVertexColor(1.0, 0.88, 0.25, 1.0)
        Frame.SetPulsed(inst, "playerStatus", true)
        Frame.SetPulsed(inst, "restGlow", true)
        Frame.SetPulsed(inst, "attackGlow", false)
        r.restIcon:Show()
        r.attackIcon:Hide()
        r.attackBackground:Hide()
    elseif inst.autoAttacking then
        r.playerStatus:SetVertexColor(1.0, 0.0, 0.0, 1.0)
        Frame.SetPulsed(inst, "playerStatus", true)
        Frame.SetPulsed(inst, "attackGlow", true)
        Frame.SetPulsed(inst, "restGlow", false)
        r.attackIcon:Show()
        r.restIcon:Hide()
        r.attackBackground:Show()
    elseif UnitAffectingCombat(inst.unit) then
        Frame.SetPulsed(inst, "playerStatus", false)
        Frame.SetPulsed(inst, "restGlow", false)
        Frame.SetPulsed(inst, "attackGlow", false)
        r.attackIcon:Show()
        r.restIcon:Hide()
        r.attackBackground:Hide()
    else
        Frame.SetPulsed(inst, "playerStatus", false)
        Frame.SetPulsed(inst, "restGlow", false)
        Frame.SetPulsed(inst, "attackGlow", false)
        r.restIcon:Hide()
        r.attackIcon:Hide()
        r.attackBackground:Hide()
    end
end

local function setAutoAttacking(on)
    return function(inst)
        inst.autoAttacking = on
        applyStateArt(inst)
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

    -- 6603 is Auto Attack; a reload mid-swing sends no PLAYER_ENTER_COMBAT.
    build = function(inst)
        local ok, on = pcall(IsCurrentSpell, 6603)
        inst.autoAttacking = ok and on == true
    end,

    paintState = function(inst)
        applyStateArt(inst)
        applyGroupPips(inst)
    end,

    events = {
        PLAYER_UPDATE_RESTING = applyStateArt,
        PLAYER_REGEN_DISABLED = applyStateArt,
        PLAYER_REGEN_ENABLED = applyStateArt,
        PLAYER_ENTER_COMBAT = setAutoAttacking(true),
        PLAYER_LEAVE_COMBAT = setAutoAttacking(false),
        PLAYER_ENTERING_WORLD = setAutoAttacking(false),
        PLAYER_DEAD = Frame.Paint,
        PLAYER_ALIVE = Frame.Paint,
        PLAYER_UNGHOST = Frame.Paint,
        PARTY_LEADER_CHANGED = applyGroupPips,
        PARTY_LOOT_METHOD_CHANGED = applyGroupPips,
    },
})
