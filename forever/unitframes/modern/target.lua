--------------------------------------------------------------------------------
-- forever/unitframes/modern/target.lua
-- The Modern target frame and the focus frame, which the client builds from
-- one template: the target frame this client draws itself, as a second
-- style of each, on the painter in frame.lua over the art in arttarget.lua
-- beside this file. This file is the state TargetFrameMixin keeps under the
-- client's override layer: the frame art, the boss art and the quest icon by
-- classification, the level or the skull in the circle, the reputation
-- strip's colour, the portrait's tint, the dead and unconscious texts, and
-- the leader, PvP and raid marker icons. The level and the tint are the
-- Classic target frame's own reads (target.lua beside this folder,
-- TargetState), since both frames name the same regions.
--
-- Every read below that decides something goes through plain(), which hands
-- back nil for a secret or a missing API, and a nil leaves the resting look:
-- the plain frame art, the level in its gold, no icon. The reaction colour
-- is the one value that is only ever passed along, so it goes to its setter
-- unread.
--
-- Left out, as the Classic frame leaves them out: the portrait's red under
-- twenty percent, a compare on a secret; the threat flash and the numeric
-- threat, until the threat read is known plain on the beta; the max-health
-- loss, the parity phase's; the focus frame's small size. The rare star and
-- the battle pet icon are out because the override never shows them, and
-- the prestige portrait and badge because the override hands the PvP writer
-- the badge alone.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Frame = addon.UnitFrames.Frame
local Values = addon.UnitFrames.Values
local TargetState = addon.UnitFrames.TargetState
local Modern = Art.Modern

local FAMILY = Modern.FAMILY.Target

local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- GetBossPortraitFrameData in the override: the winged gold for a boss, the
-- winged silver for a rare or a rare elite, the gold for an elite, each at
-- its own offset from the frame's top-right corner.
local BOSS_ART = {
    boss = { FAMILY .. "-Boss-Gold-Winged", 11, -4 },
    rare = { FAMILY .. "-Boss-Rare-Silver-Winged", 8, -7 },
    elite = { FAMILY .. "-Boss-Gold", 0, 1 },
}

-- UnitIsBossMob first, as the override reads it; a client without that read
-- takes the world boss classification for the same art.
local function bossArtFor(inst, classification)
    local boss = plain(_G.UnitIsBossMob, inst.unit)
    if boss == true or (boss == nil and classification == "worldboss") then
        return BOSS_ART.boss
    elseif classification == "rare" or classification == "rareelite" then
        return BOSS_ART.rare
    elseif classification == "elite" then
        return BOSS_ART.elite
    end
    return nil
end

-- CheckClassification under the override. The frame art and the flash swap
-- for a rare or a minus mob and the power bar hides on a minus mob, as
-- retail has it; the health bar keeps the override's one shape. The boss
-- art shows at its offset, and the quest icon by UnitIsQuestBoss. The rare
-- star never shows.
local function applyClassification(inst)
    local r = inst.regions
    local classification = not inst.previewStandIn and plain(UnitClassification, inst.unit) or nil
    local state
    if classification == "minus" then
        state = "minus"
    elseif classification == "rare" or classification == "rareelite" then
        state = "rare"
    end
    Art.ApplyRegionAtlas(inst, "frameTexture", state)
    Art.ApplyRegionAtlas(inst, "frameFlash", state)

    local minus = classification == "minus"
    inst.minus = minus
    inst.powerBar:SetShown(not minus)
    -- The power value's shown state is applyDead's, which runs after this.

    local art = not inst.previewStandIn and bossArtFor(inst, classification) or nil
    local boss = r.bossArt
    if art then
        if boss.camelotAtlas ~= art[1] then Art.SetAtlas(boss, art[1], true) end
        boss:ClearAllPoints()
        boss:SetPoint("TOPRIGHT", inst.frame, "TOPRIGHT", art[2], art[3])
        boss:SetShown(not boss.camelotAtlasMissing)
    else
        boss:Hide()
    end

    r.questIcon:SetShown(not inst.previewStandIn and plain(_G.UnitIsQuestBoss, inst.unit) == true)
end

-- CheckFaction under the override. The strip takes the selection colour at
-- the art's own alpha, grey for a mob someone else tapped; the portrait its
-- tint; then the PvP badge through the writer the Modern frames share
-- (art.lua in this folder, Modern.ApplyPvP), which the client gates on its
-- game rule.
local function applyFaction(inst)
    local r = inst.regions
    local unit = inst.unit
    local strip = r.reputationColor

    if inst.previewStandIn then
        strip:SetVertexColor(0.5, 0.5, 0.5)
        r.pvpIcon:Hide()
        return
    end

    local tapped = plain(UnitPlayerControlled, unit) == false and plain(UnitIsTapDenied, unit) == true
    if tapped then
        strip:SetVertexColor(0.5, 0.5, 0.5)
    else
        -- The three colour values only; they may be secret, and go to the
        -- setter unread.
        local ok, cr, cg, cb = pcall(UnitSelectionColor, unit)
        if not (ok and pcall(strip.SetVertexColor, strip, cr, cg, cb)) then
            strip:SetVertexColor(0.5, 0.5, 0.5)
        end
    end
    TargetState.ApplyPortraitTint(inst)
    Modern.ApplyPvP(inst, false)
end

-- CheckDead. UnitIsDeadOrGhost is a plain read where the client's UnitHealth
-- <= 0 is not. The client reads Unconscious in place of Dead where
-- UnitIsUnconscious exists and says so. Both bar values hide on a dead
-- unit, where they only ever read 0, and the power value on a minus mob,
-- which has no power bar to label.
local function applyDead(inst)
    local dead = not inst.previewStandIn and plain(UnitIsDeadOrGhost, inst.unit) == true
    local unconscious = dead and plain(_G.UnitIsUnconscious, inst.unit) == true
    inst.texts.dead:SetShown(dead and not unconscious)
    inst.texts.unconscious:SetShown(unconscious)
    inst.barTextDead = dead
    inst.noPowerText = inst.minus
    Values.ApplyBarTextShown(inst)
end

-- CheckPartyLeader and UpdateRaidTargetIcon: the guide icon for a leader
-- under dungeon finder restrictions, the leader icon otherwise, through
-- UnitLeadsAnyGroup where the client has it; the raid marker over the
-- portrait.
local function applyIcons(inst)
    local r = inst.regions
    if inst.previewStandIn then
        r.leaderIcon:Hide()
        r.guideIcon:Hide()
        r.raidTargetIcon:Hide()
        return
    end

    local leader = plain(_G.UnitLeadsAnyGroup, inst.unit)
    if leader == nil then leader = plain(UnitIsGroupLeader, inst.unit) end
    leader = leader == true
    local restricted = leader and plain(_G.HasLFGRestrictions) == true
    r.leaderIcon:SetShown(leader and not restricted)
    r.guideIcon:SetShown(leader and restricted)

    local index = plain(GetRaidTargetIndex, inst.unit)
    if type(index) == "number" and SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(r.raidTargetIcon, index)
        r.raidTargetIcon:Show()
    else
        r.raidTargetIcon:Hide()
    end
end

local function paintState(inst)
    applyClassification(inst)
    TargetState.ApplyLevel(inst)
    applyFaction(inst)
    applyDead(inst)
    applyIcons(inst)
end

local function onUnitEvent(inst, event)
    if event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" then
        paintState(inst)
        -- A reaction change swaps which aura block comes first.
        addon.UnitFrames.Auras.Refresh(inst)
        return true
    elseif event == "UNIT_HEALTH" then
        applyDead(inst)
        TargetState.ApplyPortraitTint(inst)
    elseif event == "PLAYER_FLAGS_CHANGED" then
        applyIcons(inst)
        return true
    end
    return false
end

local function iconsIfShown(inst)
    if inst.frame:IsShown() then applyIcons(inst) end
end

--------------------------------------------------------------------------------
-- Definitions
--------------------------------------------------------------------------------

local function define(key, unit, label, frameName, default, changeEvent)
    Frame.Define({
        key = key,
        style = "modern",
        unit = unit,
        label = label,
        frameName = frameName,
        -- The Camelot layout's spot, the Classic instance's own, so a style
        -- swap on that layout keeps the frame where it was; a profile
        -- started from a Blizzard preset has both instances' defaults
        -- rewritten from the preset's data. One table per frame, never
        -- shared: Edit Mode keeps it by reference.
        default = default,
        strataLevel = 10,
        unitEvents = { "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED", "PLAYER_FLAGS_CHANGED" },
        onUnitEvent = onUnitEvent,
        changeEvents = { [changeEvent] = true },
        events = {
            RAID_TARGET_UPDATE = iconsIfShown,
            GROUP_ROSTER_UPDATE = iconsIfShown,
            PARTY_LEADER_CHANGED = iconsIfShown,
        },
        paintState = paintState,
    })
end

define("target", "target", "Target", "CamelotModernTargetFrame",
    { point = "CENTER", relPoint = "CENTER", x = 340, y = -300 }, "PLAYER_TARGET_CHANGED")
define("focus", "focus", "Focus", "CamelotModernFocusFrame",
    { point = "TOPLEFT", relPoint = "TOPLEFT", x = 174, y = -178 }, "PLAYER_FOCUS_CHANGED")
