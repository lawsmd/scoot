--------------------------------------------------------------------------------
-- forever/unitframes/target.lua
-- The Classic target frame and the focus frame, which vanilla builds from one
-- template. The painter is frame.lua and the art is arttarget.lua; this file
-- is the state TargetFrameMixin keeps: the border by classification, the level
-- or the skull, the name strip's reaction colour, the dead text, and the
-- leader, PvP and raid marker icons.
--
-- Every read below that decides something goes through plain(), which hands
-- back nil for a secret. A nil leaves the frame in its resting look: the stock
-- border, the level in the font's own yellow, no icon. The reaction colour is
-- the one value that is only ever passed along, so it goes to its setter
-- unread.
--
-- Left out on purpose: vanilla tints the portrait red under 20 percent health,
-- which is a compare on a secret.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Frame = addon.UnitFrames.Frame

local PVP_ROOT = "Interface\\TargetingFrame\\UI-PVP-"

local function plain(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- TARGET_FRAME_TEXTURES. Vanilla has no rare-elite art and points that row at
-- the elite file (Vanilla/TargetFrameOverrides.lua).
local BORDER_BY_CLASSIFICATION = {
    worldboss = "borderElite",
    elite = "borderElite",
    rareelite = "borderElite",
    rare = "borderRare",
    minus = "borderMinus",
}

-- CheckClassification. A minus mob has no power bar and no name strip, and
-- the dark backing shrinks to the one bar that is left.
local function applyClassification(inst)
    local r = inst.regions
    local classification = not inst.previewStandIn and plain(UnitClassification, inst.unit) or nil
    Art.ApplyBorder(inst, BORDER_BY_CLASSIFICATION[classification] or "border")

    local minus = classification == "minus"
    r.nameBackground:SetShown(not minus)
    inst.powerBar:SetShown(not minus)
    if inst.powerText then inst.powerText:SetShown(not minus) end

    local bg = r.background
    bg:ClearAllPoints()
    if minus then
        bg:SetSize(119, 12)
        bg:SetPoint("TOPRIGHT", inst.frame, "TOPRIGHT", -89.5, -44)
    else
        bg:SetSize(119, 41)
        bg:SetPoint("TOPRIGHT", inst.frame, "TOPRIGHT", -89.5, -26)
    end
end

-- CheckLevel. The skull stands for a level the client will not tell (-1) and
-- for a corpse. The number takes the difficulty colour against an attackable
-- unit and the font's yellow otherwise.
local function applyLevel(inst)
    local levelText, skull = inst.levelText, inst.regions.skull
    if inst.previewStandIn then
        skull:Hide()
        return
    end

    local level = UnitLevel(inst.unit)
    local hidden = plain(UnitIsCorpse, inst.unit) == true
    if not hidden and not issecretvalue(level) then
        hidden = type(level) ~= "number" or level <= 0
    end

    levelText:SetShown(not hidden)
    skull:SetShown(hidden)
    if hidden then return end

    local r, g, b = 1.0, 0.82, 0
    if not issecretvalue(level) and plain(UnitCanAttack, "player", inst.unit) == true
        and GetCreatureDifficultyColor then
        local ok, color = pcall(GetCreatureDifficultyColor, level)
        if ok and type(color) == "table" and type(color.r) == "number" then
            r, g, b = color.r, color.g, color.b
        end
    end
    levelText:SetVertexColor(r, g, b)
end

-- CheckFaction. Grey for a mob someone else tapped, the selection colour
-- otherwise.
local function applyFaction(inst)
    local r = inst.regions
    local unit = inst.unit
    local strip, portrait = r.nameBackground, r.portrait

    if inst.previewStandIn then
        strip:SetVertexColor(0.5, 0.5, 0.5)
        r.pvpIcon:Hide()
        return
    end

    local tapped = plain(UnitPlayerControlled, unit) == false and plain(UnitIsTapDenied, unit) == true
    if tapped then
        strip:SetVertexColor(0.5, 0.5, 0.5)
        portrait:SetVertexColor(0.5, 0.5, 0.5)
    else
        if not pcall(strip.SetVertexColor, strip, UnitSelectionColor(unit)) then
            strip:SetVertexColor(0.5, 0.5, 0.5)
        end
        portrait:SetVertexColor(1, 1, 1)
    end

    local icon = r.pvpIcon
    local faction = plain(UnitFactionGroup, unit)
    if plain(UnitIsPVPFreeForAll, unit) == true then
        icon:SetTexture(PVP_ROOT .. "FFA")
        icon:Show()
    elseif (faction == "Alliance" or faction == "Horde") and plain(UnitIsPVP, unit) == true then
        icon:SetTexture(PVP_ROOT .. faction)
        icon:Show()
    else
        icon:Hide()
    end
end

-- CheckDead. The dead text shares the health value's spot, so one hides the
-- other. UnitIsDeadOrGhost is a plain read; vanilla's UnitHealth <= 0 is not.
local function applyDead(inst)
    local dead = not inst.previewStandIn and plain(UnitIsDeadOrGhost, inst.unit) == true
    inst.texts.dead:SetShown(dead)
    if inst.healthText then inst.healthText:SetShown(not dead) end
end

local function applyIcons(inst)
    local r = inst.regions
    if inst.previewStandIn then
        r.leaderIcon:Hide()
        r.raidTargetIcon:Hide()
        return
    end

    r.leaderIcon:SetShown(plain(UnitIsGroupLeader, inst.unit) == true)

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
    applyLevel(inst)
    applyFaction(inst)
    applyDead(inst)
    applyIcons(inst)
end

local function onUnitEvent(inst, event)
    if event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" then
        paintState(inst)
        return true
    elseif event == "UNIT_HEALTH" then
        applyDead(inst)
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
        unit = unit,
        label = label,
        frameName = frameName,
        default = default,
        strataLevel = 10,
        unitEvents = { "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED" },
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

-- The target is on a beta stand-in that mirrors the player frame around the
-- screen center. Vanilla's own spot, from the TargetFrame XML, is TOPLEFT
-- 250, -4. The focus frame takes the Classic Edit Mode preset's.
define("target", "target", "Target", "CamelotTargetFrame",
    { point = "CENTER", relPoint = "CENTER", x = 340, y = -300 }, "PLAYER_TARGET_CHANGED")
define("focus", "focus", "Focus", "CamelotFocusFrame",
    { point = "TOPLEFT", relPoint = "TOPLEFT", x = 174, y = -178 }, "PLAYER_FOCUS_CHANGED")
