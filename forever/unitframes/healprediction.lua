--------------------------------------------------------------------------------
-- forever/unitframes/healprediction.lua
-- Incoming heals, absorb shields and heal absorbs on the Classic health bars.
--
-- Vanilla draws all three (UnitFrameHealPredictionBars_Update in
-- Classic/UnitFrame.lua on origin/classic_era), on the player, target, focus
-- and pet frames:
--   * the player's own incoming heals, then everyone else's, from the health
--     edge, capped at the bar's end (MAX_INCOMING_HEAL_OVERFLOW 1.0);
--   * the absorb shield after them, UI-StatusBar under a tiled Shield-Overlay,
--     capped at the bar's end, with the Shield-Overshield glow on the bar's
--     right edge when the shield would run past it;
--   * the heal absorb from the health edge backwards over the fill, with an
--     Absorb-Edge shadow at its left end and the Absorb-Overabsorb glow on the
--     bar's left edge when it would eat more than the health there is.
-- Incoming heals sit behind the unitFramesDisplayIncomingHeals CVar; nothing
-- gates the rest.
--
-- Vanilla does that math in Lua on UnitHealth, which is secret here. The
-- calculator (CreateUnitHealPredictionCalculator) does it in C with the same
-- clamps and hands back amounts this file passes to SetValue unread, and a
-- clamped flag it passes to SetAlphaFromBoolean unread. So each segment is a
-- StatusBar the health bar's size, and the chain is anchoring: each segment
-- starts at the right edge of the one before's fill.
--
-- Where vanilla draws the incoming heals from the heal absorb's far end and
-- hides the heal absorb under them, the calculator's ReducedByIncomingHeals
-- mode nets the two first. What shows past the health edge is the same.
--
-- The reads that are the unit frames' alone go through a host table on the
-- instance ("Host" below), so the Personal Resource Display draws the same
-- segments on its own bar with no second copy of this file.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local Settings = UF.Settings

local HP = {}
UF.HealPrediction = HP

local FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local SHIELD_OVERLAY = "Interface\\RaidFrame\\Shield-Overlay"
local SHIELD_GLOW = "Interface\\RaidFrame\\Shield-Overshield"
local HEAL_ABSORB_GLOW = "Interface\\RaidFrame\\Absorb-Overabsorb"
local ABSORB_EDGE = "Interface\\RaidFrame\\Absorb-Edge"

-- The fill colors are engine globals on every client; these stand in only if
-- one is missing.
local COLORS = {
    myHeal = { "HEALTHBAR_MY_HEAL_PREDICTION_COLOR", 0.0, 0.827, 0.765 },
    otherHeal = { "HEALTHBAR_OTHER_HEAL_PREDICTION_COLOR", 0.0, 0.631, 0.557 },
    absorb = { "HEALTHBAR_TOTAL_ABSORB_COLOR", 1.0, 1.0, 1.0 },
    healAbsorb = { "HEALTHBAR_HEAL_ABSORB_COLOR", 0.4, 0.0, 0.0 },
}

local function enumValue(enumName, field, fallback)
    local e = Enum and Enum[enumName]
    return (e and e[field]) or fallback
end

local CLAMP_DAMAGE_MISSING = enumValue("UnitDamageAbsorbClampMode", "MissingHealth", 0)
local CLAMP_HEAL_ABSORB_CURRENT = enumValue("UnitHealAbsorbClampMode", "CurrentHealth", 0)
local CLAMP_INCOMING_MISSING = enumValue("UnitIncomingHealClampMode", "MissingHealth", 0)
local HEAL_ABSORB_NETTED = enumValue("UnitHealAbsorbMode", "ReducedByIncomingHeals", 0)
local MAX_INCOMING_HEAL_OVERFLOW = 1.0

--- True when this client has the calculator. /camelot state reports it.
function HP.Available()
    return type(_G.CreateUnitHealPredictionCalculator) == "function"
        and type(_G.UnitGetDetailedHealPrediction) == "function"
end

local lastError

function HP.LastError()
    return lastError
end

local function fillColor(name)
    local entry = COLORS[name]
    local c = _G[entry[1]]
    if type(c) == "table" and c.GetRGB then return c:GetRGB() end
    return entry[2], entry[3], entry[4]
end

--------------------------------------------------------------------------------
-- Host
--------------------------------------------------------------------------------
-- The five things this file reads that are the unit frames' alone, behind an
-- optional table on the instance, read at the moment of use. A guest sets
-- inst.healHost before its first HP.Apply; a unit frame instance sets
-- nothing, and the file derives its own here. HP.HostSeam is what a guest
-- tests before calling.
--
--   inst.healHost = {
--       surface = bool,              whether the bar has prediction at all
--       size = function() -> w, h,   the segment size, never a read of the bar
--       glowParent = frame,          where the two edge glows are drawn
--       show = function(field),      the four switches
--       standIn = function(),        true while an Edit Mode stand-in shows
--   }

HP.HostSeam = true

local function unitFrameHost(inst)
    return {
        surface = Settings.SURFACE[inst.key].health == true,
        size = function()
            local s = inst.spec.Bars.health
            return s.w, s.h
        end,
        glowParent = inst.artFrame,
        show = function(field) return Settings.Health(inst.key, field) ~= false end,
        standIn = function() return inst.previewStandIn end,
    }
end

local function hostOf(inst)
    if not inst.healHost then inst.healHost = unitFrameHost(inst) end
    return inst.healHost
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function buildSegment(inst, host, name, reverse)
    local health = inst.healthBar
    local bar = CreateFrame("StatusBar", nil, health)
    bar:SetFrameLevel(health:GetFrameLevel())
    -- The host's size, not a read of the health bar: a StatusBar fed a secret
    -- can throw on its own geometry getters.
    bar:SetSize(host.size())
    bar:SetStatusBarTexture(FILL)
    bar:SetStatusBarColor(fillColor(name))
    bar:SetReverseFill(reverse and true or false)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()
    return bar
end

local function buildGlow(host, path)
    local glow = host.glowParent:CreateTexture(nil, "ARTWORK", nil, 1)
    glow:SetTexture(path)
    glow:SetBlendMode("ADD")
    glow:SetWidth(16)
    glow:SetAlpha(0)
    return glow
end

local function build(inst)
    local host = hostOf(inst)
    local health = inst.healthBar
    local fill = health:GetStatusBarTexture()
    local parts = {}

    -- The chain. A StatusBar at zero still has its fill's left edge where the
    -- bar starts, so an empty segment passes the edge straight through.
    parts.myHeal = buildSegment(inst, host, "myHeal")
    parts.myHeal:SetPoint("LEFT", fill, "RIGHT")
    parts.otherHeal = buildSegment(inst, host, "otherHeal")
    parts.otherHeal:SetPoint("LEFT", parts.myHeal:GetStatusBarTexture(), "RIGHT")
    parts.absorb = buildSegment(inst, host, "absorb")
    parts.absorb:SetPoint("LEFT", parts.otherHeal:GetStatusBarTexture(), "RIGHT")

    local absorbFill = parts.absorb:GetStatusBarTexture()
    local overlay = parts.absorb:CreateTexture(nil, "ARTWORK")
    overlay:SetTexture(SHIELD_OVERLAY, "REPEAT", "REPEAT")
    overlay:SetHorizTile(true)
    overlay:SetVertTile(true)
    overlay:SetAllPoints(absorbFill)
    parts.absorbOverlay = overlay

    -- Backwards from the health edge, over the fill.
    parts.healAbsorb = buildSegment(inst, host, "healAbsorb", true)
    parts.healAbsorb:SetPoint("RIGHT", fill, "RIGHT")
    local edge = parts.healAbsorb:CreateTexture(nil, "ARTWORK")
    edge:SetTexture(ABSORB_EDGE)
    edge:SetWidth(8)
    local healAbsorbFill = parts.healAbsorb:GetStatusBarTexture()
    edge:SetPoint("TOPLEFT", healAbsorbFill, "TOPLEFT")
    edge:SetPoint("BOTTOMLEFT", healAbsorbFill, "BOTTOMLEFT")
    parts.healAbsorbEdge = edge

    -- UnitFrame_Initialize's anchors.
    parts.overAbsorbGlow = buildGlow(host, SHIELD_GLOW)
    parts.overAbsorbGlow:SetPoint("TOPLEFT", health, "TOPRIGHT", -7, 0)
    parts.overAbsorbGlow:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", -7, 0)
    parts.overHealAbsorbGlow = buildGlow(host, HEAL_ABSORB_GLOW)
    parts.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", health, "BOTTOMLEFT", 7, 0)
    parts.overHealAbsorbGlow:SetPoint("TOPRIGHT", health, "TOPLEFT", 7, 0)

    local calc = CreateUnitHealPredictionCalculator()
    calc:SetIncomingHealClampMode(CLAMP_INCOMING_MISSING)
    calc:SetIncomingHealOverflowPercent(MAX_INCOMING_HEAL_OVERFLOW)
    calc:SetDamageAbsorbClampMode(CLAMP_DAMAGE_MISSING)
    calc:SetHealAbsorbClampMode(CLAMP_HEAL_ABSORB_CURRENT)
    calc:SetHealAbsorbMode(HEAL_ABSORB_NETTED)
    parts.calc = calc

    inst.healPrediction = parts
end

--------------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------------

local SEGMENTS = { "myHeal", "otherHeal", "absorb", "healAbsorb" }

-- A guest's bar size can follow its settings; each segment takes the host's
-- size again on every apply. One anchor and an explicit size, so this is a
-- write and nothing reads the bar.
local function resize(parts, host)
    local w, h = host.size()
    for _, name in ipairs(SEGMENTS) do parts[name]:SetSize(w, h) end
end

function HP.Hide(inst)
    local parts = inst.healPrediction
    if not parts then return end
    for _, name in ipairs(SEGMENTS) do parts[name]:Hide() end
    parts.overAbsorbGlow:SetAlpha(0)
    parts.overHealAbsorbGlow:SetAlpha(0)
end

local function show(inst, field)
    return hostOf(inst).show(field)
end

local function feed(bar, maxHealth, amount, shown)
    if not shown then
        bar:Hide()
        return
    end
    bar:SetMinMaxValues(0, maxHealth)
    bar:SetValue(amount)
    bar:Show()
end

local function paint(inst)
    local parts = inst.healPrediction
    local unit = inst.unit
    local calc = parts.calc
    UnitGetDetailedHealPrediction(unit, "player", calc)

    local maxHealth = UnitHealthMax(unit)
    local heals = show(inst, "incomingHeals")
        and (not GetCVarBool or GetCVarBool("unitFramesDisplayIncomingHeals") ~= false)
    local _, fromPlayer, fromOthers = calc:GetIncomingHeals()
    feed(parts.myHeal, maxHealth, fromPlayer, heals)
    feed(parts.otherHeal, maxHealth, fromOthers, heals)

    local absorb, absorbClamped = calc:GetDamageAbsorbs()
    feed(parts.absorb, maxHealth, absorb, show(inst, "absorb"))
    if show(inst, "absorb") and show(inst, "overAbsorbGlow") then
        parts.overAbsorbGlow:SetAlphaFromBoolean(absorbClamped, 1, 0)
    else
        parts.overAbsorbGlow:SetAlpha(0)
    end

    local healAbsorb, healAbsorbClamped = calc:GetHealAbsorbs()
    local healAbsorbShown = show(inst, "healAbsorb")
    feed(parts.healAbsorb, maxHealth, healAbsorb, healAbsorbShown)
    -- The shadow would sit over the incoming heals; vanilla shows it only
    -- where there are none, and here the netting leaves none past a heal absorb.
    parts.healAbsorbEdge:SetShown(healAbsorbShown)
    if healAbsorbShown then
        parts.overHealAbsorbGlow:SetAlphaFromBoolean(healAbsorbClamped, 1, 0)
    else
        parts.overHealAbsorbGlow:SetAlpha(0)
    end
end

--- Repaint from the unit. Frame.Paint calls it on every health event and on
--- the three prediction events.
function HP.Update(inst)
    local parts = inst.healPrediction
    if not parts then return end
    if hostOf(inst).standIn() then
        HP.Hide(inst)
        return
    end
    local ok, err = pcall(paint, inst)
    if not ok then
        lastError = tostring(err)
        HP.Hide(inst)
    end
end

--- Build on the first call, then size and repaint. The frame's build and the
--- settings pass. A frame whose health bar has no prediction in vanilla gets
--- none.
function HP.Apply(inst)
    local host = hostOf(inst)
    if not host.surface then return end
    if not inst.healPrediction then
        if not HP.Available() then return end
        local ok, err = pcall(build, inst)
        if not ok then
            lastError = tostring(err)
            return
        end
    end
    resize(inst.healPrediction, host)
    HP.Update(inst)
end

--- A line for /camelot state.
function HP.Describe(inst)
    if not hostOf(inst).surface then return "none on this frame" end
    if not HP.Available() then return "calculator missing on this client" end
    if not inst.healPrediction then return "not built" end
    return lastError and ("built; last error: " .. lastError) or "built"
end
