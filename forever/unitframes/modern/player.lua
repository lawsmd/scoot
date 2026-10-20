--------------------------------------------------------------------------------
-- forever/unitframes/modern/player.lua
-- The Modern player frame: the player frame this client draws itself, as a
-- second style of the player unit frame, on the painter in frame.lua over
-- the art in artplayer.lua beside this file. This file is the state
-- PlayerFrame.lua keeps under the client's override layer: the rested and
-- in-combat art, the rest loop, the leader or guide icon, the PvP badge, the
-- raid group indicator and the ready check.
--
-- Every read below that decides something goes through plain(), which hands
-- back nil for a secret or a missing API, and a nil leaves the resting look.
-- The player's own reads are plain on every client so far; the screen is
-- there for the day one is not.
--
-- Left out, as the Classic frame leaves them out: the vehicle art and the
-- pet-to-player swap, the hit indicator, the animated health loss, the power
-- feedback and full-power pulses, the prestige portrait and the PvP timer,
-- the play-time icon, the class bar container. The role icon is left out
-- because the client's override never shows one on this frame. The threat
-- flash region is built hidden and nothing drives it yet. The max health
-- loss and the mana cost are the bars' own (barsegments.lua, beside the
-- painter).
--------------------------------------------------------------------------------

local addonName, addon = ...

local Frame = addon.UnitFrames.Frame
local Art = addon.UnitFrames.Art

local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

--------------------------------------------------------------------------------
-- State art
--------------------------------------------------------------------------------

-- PlayerFrame_UpdateStatus in the client's own order: auto-attacking
-- (PLAYER_ENTER_COMBAT) first, then on the hate list (PLAYER_REGEN_DISABLED),
-- which shows the swords alone, then resting. Blizzard's hate-list branch
-- leaves the glow as it was; this one hides it, as the Classic frame does.
-- The two vertex colours are Blizzard's. The corner embellishment and the
-- attack icon sit on the same spot, and one of them shows.
local function applyStateArt(inst)
    local r = inst.regions

    if inst.autoAttacking then
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
    elseif IsResting() then
        r.statusTexture:SetVertexColor(1.0, 0.88, 0.25, 1.0)
        Frame.SetPulsed(inst, "statusTexture", true)
        Frame.SetPulsed(inst, "restLoop", true)
        r.attackIcon:Hide()
        r.cornerIcon:Show()
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
    plate:SetPoint("BOTTOMRIGHT", inst.frame, "TOPLEFT", 210, -29 + (inst.spec.lift or 0))
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

--------------------------------------------------------------------------------
-- Ready check
--------------------------------------------------------------------------------

-- PlayerFrame_UpdateReadyCheck: the client's icon over the portrait, 40 by
-- 40 and two levels over the art, on ReadyCheck.lua's own functions, which
-- write only the frame they are handed. A client without the template or
-- the functions builds none.
local function buildReadyCheck(inst)
    if type(_G.ReadyCheck_Start) ~= "function" then return end
    local ok, frame = pcall(CreateFrame, "Frame", nil, inst.artFrame, "ReadyCheckStatusTemplate")
    if not ok or not frame then return end
    frame:SetSize(40, 40)
    frame:SetPoint("CENTER", inst.regions.portrait, "CENTER")
    frame:SetFrameLevel(inst.artFrame:GetFrameLevel() + 2)
    frame:Hide()
    inst.readyCheck = frame
end

-- Not part of paintState: after the check ends the status reads nil while
-- the icon fades, and a repaint would cut the fade short.
local function applyReadyCheck(inst)
    local frame = inst.readyCheck
    if not frame then return end
    local status = not inst.previewStandIn and plain(_G.GetReadyCheckStatus, "player") or nil
    if status == "ready" then
        pcall(_G.ReadyCheck_Confirm, frame, 1)
    elseif status == "notready" then
        pcall(_G.ReadyCheck_Confirm, frame, 0)
    elseif status then
        pcall(_G.ReadyCheck_Start, frame)
    else
        frame:Hide()
    end
end

local function finishReadyCheck(inst)
    local frame = inst.readyCheck
    if not frame then return end
    if not pcall(_G.ReadyCheck_Finish, frame, _G.DEFAULT_READY_CHECK_STAY_TIME or 10) then
        frame:Hide()
    end
end

--------------------------------------------------------------------------------
-- PvP
--------------------------------------------------------------------------------

-- PlayerFrame_UpdatePvPStatus, through the badge writer the Modern frames
-- share (art.lua in this folder, Modern.ApplyPvP); the player's own frame
-- checks for a mercenary, as the client's call does.
local function applyPvP(inst)
    Art.Modern.ApplyPvP(inst, true)
end

--------------------------------------------------------------------------------
-- Definition
--------------------------------------------------------------------------------

local function paintState(inst)
    applyStateArt(inst)
    applyLeader(inst)
    applyPvP(inst)
    applyGroupIndicator(inst)
end

local function applyGroup(inst)
    applyLeader(inst)
    applyGroupIndicator(inst)
    applyReadyCheck(inst)
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
        buildReadyCheck(inst)
    end,

    paintState = paintState,

    events = {
        PLAYER_UPDATE_RESTING = applyStateArt,
        PLAYER_REGEN_DISABLED = applyStateArt,
        PLAYER_REGEN_ENABLED = applyStateArt,
        PLAYER_ENTER_COMBAT = setAutoAttacking(true),
        PLAYER_LEAVE_COMBAT = setAutoAttacking(false),
        PLAYER_ENTERING_WORLD = function(inst)
            inst.autoAttacking = false
            applyStateArt(inst)
        end,
        PLAYER_DEAD = Frame.Paint,
        PLAYER_ALIVE = Frame.Paint,
        PLAYER_UNGHOST = Frame.Paint,
        PARTY_LEADER_CHANGED = applyGroup,
        GROUP_ROSTER_UPDATE = applyGroup,
        HONOR_LEVEL_UPDATE = applyPvP,
        READY_CHECK = applyReadyCheck,
        READY_CHECK_CONFIRM = applyReadyCheck,
        READY_CHECK_FINISHED = finishReadyCheck,
    },
})
