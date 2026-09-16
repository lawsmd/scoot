--------------------------------------------------------------------------------
-- forever/unitframes/player.lua
-- The Classic player frame's painter.
--
-- Draw order is the one thing here that is not a straight transcription. The
-- vanilla frame gets its stacking from nesting: the border lives in a child
-- frame, so it draws over the portrait and the bars whatever their layers say,
-- because a child frame outranks every layer of its parent. This rebuild uses
-- three frame levels for the same result and skips the nesting:
--
--   frame     +0   flash, the dark backing, the portrait
--   bars      +1   health and power
--   artFrame  +2   the border, the state art over it, and all the text
--
-- Within artFrame the XML's own layers still order things: BORDER for the
-- frame art, ARTWORK for the rested and attacked state art over it, OVERLAY
-- for the icons and the text.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = addon.UnitFrames.Art
local Values = addon.UnitFrames.Values
local Harness = addon.UnitFrames.Harness

local Player = {}
addon.UnitFrames.Player = Player

--------------------------------------------------------------------------------
-- Static configuration
--------------------------------------------------------------------------------
-- There is no settings page yet and no Edit Mode registration. Change these and
-- reload. The default sits clear of Blizzard's own player frame so the two can
-- be compared side by side.

local POSITION = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 20, y = -240 }
local SCALE = 1.0

-- Vanilla shows no number on either bar: the two FontStrings exist but sit
-- behind the statusText CVar, so the frame at rest is a name and two coloured
-- bars. True here reads the bars while there is no settings page to ask.
local SHOW_BAR_TEXT = true

-- Which host each region is built on. Anything not named here goes on artFrame.
local ON_BASE = {
    flash = true,
    background = true,
    portrait = true,
}

--------------------------------------------------------------------------------
-- Widget construction
--------------------------------------------------------------------------------

local function buildRegion(host, def)
    local tex = host:CreateTexture(nil, def.layer)
    if def.path then tex:SetTexture(def.path) end
    tex:SetSize(def.w, def.h)
    tex:SetPoint(def.point, host, def.point, def.x or 0, def.y or 0)
    if def.coords then
        tex:SetTexCoord(def.coords[1], def.coords[2], def.coords[3], def.coords[4])
    end
    if def.blend then tex:SetBlendMode(def.blend) end
    if def.color then
        tex:SetColorTexture(def.color[1], def.color[2], def.color[3], def.color[4] or 1)
    end
    if def.hidden then tex:Hide() end
    return tex
end

local function buildBar(parent, def, level)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(def.w, def.h)
    bar:SetPoint(def.point, parent, def.point, def.x, def.y)
    bar:SetStatusBarTexture(def.texture)
    bar:SetFrameLevel(level)
    if def.color then
        bar:SetStatusBarColor(def.color[1], def.color[2], def.color[3])
    end
    -- A sane range before the first feed. A bar still ranged (0, 1) when a real
    -- maximum arrives clamps to full for one frame, which reads as a flash.
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    return bar
end

local function buildText(host, def)
    local fs = host:CreateFontString(nil, def.layer, def.font)
    if def.w then fs:SetSize(def.w, def.h) end
    fs:SetPoint(def.point, host, def.relPoint or def.point, def.x or 0, def.y or 0)
    if def.justifyH then fs:SetJustifyH(def.justifyH) end
    if def.justifyV then fs:SetJustifyV(def.justifyV) end
    return fs
end

-- The rested and attacked wash breathes rather than sitting lit.
-- PlayerFrame_OnUpdate flips a sign every half second and ramps alpha between
-- 55/255 and 1 across it, which is a one-second triangle. A looping animation
-- is the same curve without a per-frame script, and a texture can own an
-- animation group directly.
local PULSE_MIN = 55 / 255
local PULSE_HALF = 0.5

local function attachPulse(tex)
    local group = tex:CreateAnimationGroup()
    group:SetLooping("REPEAT")

    local up = group:CreateAnimation("Alpha")
    up:SetFromAlpha(PULSE_MIN)
    up:SetToAlpha(1.0)
    up:SetDuration(PULSE_HALF)
    up:SetOrder(1)

    local down = group:CreateAnimation("Alpha")
    down:SetFromAlpha(1.0)
    down:SetToAlpha(PULSE_MIN)
    down:SetDuration(PULSE_HALF)
    down:SetOrder(2)

    return group
end

-- Show and start, or stop and hide. The stop comes first on the way down, so
-- the texture settles on its own alpha rather than wherever the loop was.
local function setPulsed(tex, group, shown)
    if shown then
        tex:Show()
        if not group:IsPlaying() then group:Play() end
    else
        if group:IsPlaying() then group:Stop() end
        tex:SetAlpha(1.0)
        tex:Hide()
    end
end

function Player.Build()
    if Player.inst then return Player.inst end

    local spec = Art.Player

    local inst = Harness.New({
        unit = "player",
        frameName = "CamelotPlayerFrame",
        width = spec.width,
        height = spec.height,
        hitInsets = spec.hitInsets,
        point = POSITION.point,
        relPoint = POSITION.relPoint,
        x = POSITION.x,
        y = POSITION.y,
        strataLevel = 10,
    })
    inst.frame:SetScale(SCALE)

    local base = inst.frame
    local level = base:GetFrameLevel()

    inst.regions = {}

    -- DrawOrder, not pairs: two regions in one layer are ordered by creation,
    -- and the additive glows have to land on top of the icons they cover.
    for _, key in ipairs(spec.DrawOrder) do
        if ON_BASE[key] then
            inst.regions[key] = buildRegion(base, spec.Regions[key])
        end
    end

    inst.healthBar = buildBar(base, spec.Bars.health, level + 1)
    inst.powerBar = buildBar(base, spec.Bars.power, level + 1)

    local artFrame = CreateFrame("Frame", nil, base)
    artFrame:SetAllPoints(base)
    artFrame:SetFrameLevel(level + 2)
    inst.artFrame = artFrame

    for _, key in ipairs(spec.DrawOrder) do
        if not ON_BASE[key] then
            inst.regions[key] = buildRegion(artFrame, spec.Regions[key])
        end
    end

    inst.pulses = {
        playerStatus = attachPulse(inst.regions.playerStatus),
        restGlow = attachPulse(inst.regions.restGlow),
        attackGlow = attachPulse(inst.regions.attackGlow),
    }

    inst.portrait = inst.regions.portrait
    inst.nameText = buildText(artFrame, spec.Text.name)
    inst.levelText = buildText(artFrame, spec.Text.level)

    -- Vanilla leaves both bar numbers off and gates them behind the statusText
    -- CVar, so the frame at rest shows a name and two coloured bars. The switch
    -- at the top of this file turns them on for a closer read of what the bars
    -- are doing; it becomes a real setting later.
    if SHOW_BAR_TEXT then
        inst.healthText = buildText(artFrame, spec.Text.healthValue)
        inst.powerText = buildText(artFrame, spec.Text.powerValue)
    end

    Player.inst = inst
    Player.WireEvents(inst)

    return inst
end

--------------------------------------------------------------------------------
-- State art
--------------------------------------------------------------------------------

-- Vanilla's own order, from PlayerFrame_UpdateStatus: resting wins over combat,
-- and each state owns both an icon and the additive wash behind the bars. The
-- two vertex colours are Blizzard's.
local function applyStateArt(inst)
    local r = inst.regions
    local p = inst.pulses
    local resting = IsResting()
    local inCombat = UnitAffectingCombat(inst.unit)

    if resting then
        r.playerStatus:SetVertexColor(1.0, 0.88, 0.25, 1.0)
        setPulsed(r.playerStatus, p.playerStatus, true)
        setPulsed(r.restGlow, p.restGlow, true)
        setPulsed(r.attackGlow, p.attackGlow, false)
        r.restIcon:Show()
        r.attackIcon:Hide()
        r.attackBackground:Hide()
    elseif inCombat then
        r.playerStatus:SetVertexColor(1.0, 0.0, 0.0, 1.0)
        setPulsed(r.playerStatus, p.playerStatus, true)
        setPulsed(r.attackGlow, p.attackGlow, true)
        setPulsed(r.restGlow, p.restGlow, false)
        r.attackIcon:Show()
        r.restIcon:Hide()
        r.attackBackground:Show()
    else
        setPulsed(r.playerStatus, p.playerStatus, false)
        setPulsed(r.restGlow, p.restGlow, false)
        setPulsed(r.attackGlow, p.attackGlow, false)
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
-- Paint
--------------------------------------------------------------------------------

function Player.Paint(inst)
    if not inst.frame:IsShown() then return end
    Values.ApplyHealth(inst)
    Values.ApplyPower(inst)
    Values.ApplyBarText(inst)
end

function Player.PaintAll(inst)
    Values.ApplyPowerColor(inst)
    Values.ApplyIdentity(inst)
    Values.ApplyPortrait(inst)
    applyStateArt(inst)
    applyGroupPips(inst)
    Player.Paint(inst)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- The unit events stay on the frame, because RegisterUnitEvent filters them to
-- the unit in C and the handler never has to ask which unit fired. Everything
-- that is not unit-filtered goes through the shared dispatcher instead.
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_LEVEL", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE",
}

local OWNER = "CamelotPlayerFrame"

function Player.WireEvents(inst)
    local frame = inst.frame

    for _, event in ipairs(UNIT_EVENTS) do
        frame:RegisterUnitEvent(event, inst.unit)
    end

    -- Kept off addon.Events: RegisterUnitEvent filters in C to this unit, which
    -- the shared dispatcher cannot do. The plain events below use it.
    frame:SetScript("OnEvent", function(_, event)
        if event == "UNIT_DISPLAYPOWER" then
            Values.ApplyPowerColor(inst)
            Values.ApplyPower(inst)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
            Values.ApplyIdentity(inst)
        elseif event == "UNIT_PORTRAIT_UPDATE" then
            Values.ApplyPortrait(inst)
        else
            Player.Paint(inst)
        end
    end)

    local function onState() applyStateArt(inst) end
    addon.Events.On(OWNER, "PLAYER_UPDATE_RESTING", onState)
    addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", onState)
    addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", onState)

    local function onPips() applyGroupPips(inst) end
    addon.Events.On(OWNER, "PARTY_LEADER_CHANGED", onPips)
    addon.Events.On(OWNER, "PARTY_LOOT_METHOD_CHANGED", onPips)

    addon.Events.OnWorldEntered(function() Player.PaintAll(inst) end)

    -- The paint gates on IsShown, so the manager's show has to trigger one.
    frame:SetScript("OnShow", function() Player.PaintAll(inst) end)
end

--------------------------------------------------------------------------------
-- Show and hide
--------------------------------------------------------------------------------

function Player.SetShown(show)
    local inst = Player.Build()
    inst.enabled = show and true or false
    Harness.UpdateVisibility(inst)
    if inst.enabled then Player.PaintAll(inst) end
    return inst
end
