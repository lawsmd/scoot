--------------------------------------------------------------------------------
-- forever/unitframes/modern/player.lua
-- The Modern player frame: retail's PlayerFrame as a second style of the
-- player unit frame, on the painter in frame.lua over the art in
-- artplayer.lua beside this file. This file is the state PlayerFrame.lua
-- keeps: the rested and in-combat art, the rest loop, the leader or guide
-- icon, the role icon, the PvP badge, and the raid group indicator.
--
-- Every read below that decides something goes through plain(), which hands
-- back nil for a secret or a missing API, and a nil leaves the resting look.
-- The player's own reads are plain on every client so far; the screen is
-- there for the day one is not.
--
-- Left out, as the Classic frame leaves them out: the vehicle art and the
-- pet-to-player swap, the hit indicator, the animated health loss, the power
-- feedback and full-power pulses, the prestige portrait and the PvP timer,
-- the play-time icon, the class bar container. The threat flash region is
-- built hidden and nothing drives it yet. The ready check and the max-health
-- loss are the parity phase's.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame
local Art = addon.UnitFrames.Art
local Shared = Art.Modern.Shared

local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

--------------------------------------------------------------------------------
-- State art
--------------------------------------------------------------------------------

-- PlayerFrame_UpdateStatus, in its order: resting, then auto-attacking
-- (PLAYER_ENTER_COMBAT), then on the hate list (PLAYER_REGEN_DISABLED),
-- which shows the swords alone. Retail's hate-list branch leaves the glow as
-- it was; this one hides it, as the Classic frame does. The two vertex
-- colours are Blizzard's. The corner embellishment and the attack icon sit
-- on the same spot, and one of them shows.
local function applyStateArt(inst)
    local r = inst.regions
    local resting = IsResting()

    if resting then
        r.statusTexture:SetVertexColor(1.0, 0.88, 0.25, 1.0)
        Frame.SetPulsed(inst, "statusTexture", true)
        Frame.SetPulsed(inst, "restLoop", true)
        r.attackIcon:Hide()
        r.cornerIcon:Show()
    elseif inst.autoAttacking then
        r.statusTexture:SetVertexColor(1.0, 0.0, 0.0, 1.0)
        Frame.SetPulsed(inst, "statusTexture", true)
        Frame.SetPulsed(inst, "restLoop", false)
        r.attackIcon:Show()
        r.cornerIcon:Hide()
    elseif UnitAffectingCombat(inst.unit) then
        Frame.SetPulsed(inst, "statusTexture", false)
        Frame.SetPulsed(inst, "restLoop", false)
        r.attackIcon:Show()
        r.cornerIcon:Hide()
    else
        Frame.SetPulsed(inst, "statusTexture", false)
        Frame.SetPulsed(inst, "restLoop", false)
        r.attackIcon:Hide()
        r.cornerIcon:Show()
    end
end

local function setAutoAttacking(on)
    return function(inst)
        inst.autoAttacking = on
        applyStateArt(inst)
    end
end

--------------------------------------------------------------------------------
-- Group
--------------------------------------------------------------------------------

-- PlayerFrame_UpdatePartyLeader: the guide icon for a leader under dungeon
-- finder restrictions, the leader icon otherwise.
local function applyLeader(inst)
    local r = inst.regions
    local leader = not inst.previewStandIn and plain(UnitIsGroupLeader, inst.unit) == true
    local restricted = leader and plain(HasLFGRestrictions) == true
    r.leaderIcon:SetShown(leader and not restricted)
    r.guideIcon:SetShown(leader and restricted)
end

-- PlayerFrame_UpdateGroupIndicator: "Group N" in a three-piece plate above
-- the name, in a raid, sized to its text plus 40. The roster name and the
-- player's own are compared, so both have to be plain; the subgroup joins a
-- string Camelot owns, so it has to be too.
local function buildGroupIndicator(inst)
    local art = inst.artFrame
    local plate = CreateFrame("Frame", nil, art)
    plate:SetSize(10, 16)
    plate:SetPoint("BOTTOMRIGHT", inst.frame, "TOPLEFT", 210, -29)
    plate:SetFrameLevel(art:GetFrameLevel())

    local left = plate:CreateTexture(nil, "BACKGROUND")
    Art.SetAtlas(left, "UI-HUD-UnitFrame-Player-GroupIndicatorLeft", true)
    left:SetPoint("TOPLEFT")
    local right = plate:CreateTexture(nil, "BACKGROUND")
    Art.SetAtlas(right, "UI-HUD-UnitFrame-Player-GroupIndicatorRight", true)
    right:SetPoint("TOPRIGHT")
    -- A tiling member: the atlas carries the repeat, and the two anchors
    -- give the width.
    local mid = plate:CreateTexture(nil, "BACKGROUND")
    Art.SetAtlas(mid, "_UI-HUD-UnitFrame-Player-GroupIndicatorMid", true)
    mid:SetPoint("LEFT", left, "RIGHT")
    mid:SetPoint("RIGHT", right, "LEFT")

    local text = plate:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    text:SetAlpha(0.7)
    text:SetPoint("LEFT", 20, 2)
    plate.text = text
    plate.pieces = { left, right, mid }

    plate:Hide()
    inst.groupIndicator = plate
end

local function applyGroupIndicator(inst)
    local plate = inst.groupIndicator
    if not plate then return end
    plate:Hide()
    if inst.previewStandIn or plain(IsInRaid) ~= true then return end

    local count = plain(GetNumGroupMembers)
    local me = plain(UnitName, "player")
    if type(count) ~= "number" or type(me) ~= "string" then return end
    for i = 1, count do
        local ok, name, _, subgroup = pcall(GetRaidRosterInfo, i)
        if ok and type(name) == "string" and not issecretvalue(name) and name == me then
            if type(subgroup) ~= "number" or issecretvalue(subgroup) then return end
            plate.text:SetText((_G.GROUP or "Group") .. " " .. subgroup)
            plate:SetWidth(plate.text:GetStringWidth() + 40)
            plate:Show()
            return
        end
    end
end

-- PlayerFrame_UpdateRolesAssigned: the role icon inside an instance, and
-- the level hidden while it shows, since both sit on the same spot. Retail
-- reads the enum; the string form stands in where the enum reader is
-- missing.
local ROLE_ATLAS = {
    TANK = Shared.roleTank,
    HEALER = Shared.roleHealer,
    DAMAGER = Shared.roleDamage,
}

local function roleToken()
    local role = plain(UnitGroupRolesAssignedEnum, "player")
    if type(role) == "number" and Enum.LFGRole then
        if role == Enum.LFGRole.Tank then return "TANK" end
        if role == Enum.LFGRole.Healer then return "HEALER" end
        if role == Enum.LFGRole.Damage then return "DAMAGER" end
        return nil
    end
    role = plain(UnitGroupRolesAssigned, "player")
    return ROLE_ATLAS[role] and role or nil
end

local function inInstance()
    local ok, _, instanceType = pcall(GetInstanceInfo)
    if not ok or type(instanceType) ~= "string" or issecretvalue(instanceType) then return false end
    return instanceType ~= "none"
end

local function applyRole(inst)
    local icon = inst.regions.roleIcon
    local atlas
    if not inst.previewStandIn and inInstance() then
        local token = roleToken()
        atlas = token and ROLE_ATLAS[token] or nil
    end
    if atlas and Art.AtlasResolves(atlas) then
        if icon.camelotAtlas ~= atlas then Art.SetAtlas(icon, atlas, false) end
        icon:Show()
    else
        atlas = nil
        icon:Hide()
    end
    if inst.levelText then
        inst.levelText:SetShown(not atlas and not inst.textHidden.level)
    end
end

--------------------------------------------------------------------------------
-- PvP
--------------------------------------------------------------------------------

-- PlayerFrame_UpdatePvPStatus. Blizzard's own writer first, on a texture
-- Camelot owns: behind a secure delegate it reads the faction, the
-- free-for-all flag and the honor badge, and writes the atlas and the shown
-- state, secret-wrapped where the unit's identity is. Only the badge is
-- handed over, no prestige pieces, which the writer tolerates. A client
-- without the writer, or a refusal, takes the plain path below with the same
-- three names, as the Classic target frame does with the vanilla files.
local function applyPvP(inst)
    local icon = inst.regions.pvpIcon
    if inst.previewStandIn then
        icon:Hide()
        return
    end
    local util = _G.UnitFrameUtil
    if type(util) == "table" and util.UpdateUnitPvPIndicator then
        if pcall(util.UpdateUnitPvPIndicator, { pvpIcon = icon }, inst.unit, true) then
            return
        end
    end

    local name
    if plain(UnitIsPVPFreeForAll, inst.unit) == true then
        name = Shared.pvpFFA
    else
        local faction = plain(UnitFactionGroup, inst.unit)
        if (faction == "Horde" or faction == "Alliance") and plain(UnitIsPVP, inst.unit) == true then
            if plain(UnitIsMercenary, inst.unit) == true then
                faction = faction == "Horde" and "Alliance" or "Horde"
            end
            name = faction == "Horde" and Shared.pvpHorde or Shared.pvpAlliance
        end
    end
    if name and Art.AtlasResolves(name) then
        if icon.camelotAtlas ~= name then Art.SetAtlas(icon, name, true) end
        icon:Show()
    else
        icon:Hide()
    end
end

--------------------------------------------------------------------------------
-- Definition
--------------------------------------------------------------------------------

local function paintState(inst)
    applyStateArt(inst)
    applyLeader(inst)
    applyRole(inst)
    applyPvP(inst)
    applyGroupIndicator(inst)
end

local function applyGroup(inst)
    applyLeader(inst)
    applyGroupIndicator(inst)
end

local function onUnitEvent(inst, event)
    if event == "UNIT_FACTION" then
        applyPvP(inst)
        return true
    end
    return false
end

Frame.Define({
    key = "player",
    style = "modern",
    unit = "player",
    label = "Player",
    frameName = "CamelotModernPlayerFrame",
    -- The Camelot layout's player spot, the Classic instance's own, so a
    -- style swap on that layout keeps the frame where it was; a profile
    -- started from a Blizzard preset has both instances' defaults rewritten
    -- from the preset's data. One table per frame, never shared: Edit Mode
    -- keeps it by reference.
    default = { point = "CENTER", relPoint = "CENTER", x = -340, y = -300 },
    strataLevel = 10,

    unitEvents = { "UNIT_FACTION" },
    onUnitEvent = onUnitEvent,

    -- 6603 is Auto Attack; a reload mid-swing sends no PLAYER_ENTER_COMBAT.
    build = function(inst)
        local ok, on = pcall(IsCurrentSpell, 6603)
        inst.autoAttacking = ok and on == true
        buildGroupIndicator(inst)
    end,

    paintState = paintState,

    events = {
        PLAYER_UPDATE_RESTING = applyStateArt,
        PLAYER_REGEN_DISABLED = applyStateArt,
        PLAYER_REGEN_ENABLED = applyStateArt,
        PLAYER_ENTER_COMBAT = setAutoAttacking(true),
        PLAYER_LEAVE_COMBAT = setAutoAttacking(false),
        -- Retail re-reads the role on entering the world, which is also the
        -- edge into and out of an instance.
        PLAYER_ENTERING_WORLD = function(inst)
            inst.autoAttacking = false
            applyStateArt(inst)
            applyRole(inst)
        end,
        PLAYER_DEAD = Frame.Paint,
        PLAYER_ALIVE = Frame.Paint,
        PLAYER_UNGHOST = Frame.Paint,
        PARTY_LEADER_CHANGED = applyGroup,
        GROUP_ROSTER_UPDATE = applyGroup,
        PLAYER_ROLES_ASSIGNED = applyRole,
        HONOR_LEVEL_UPDATE = applyPvP,
    },
})
