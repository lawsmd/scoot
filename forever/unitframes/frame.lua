--------------------------------------------------------------------------------
-- forever/unitframes/frame.lua
-- The painter every Classic unit frame shares, and the registry of them.
--
-- A frame is a definition (Frame.Define, called by player.lua, target.lua,
-- tot.lua and pet.lua) over an art spec (Art.Frames). This file builds the
-- widgets, feeds them, wires the events every unit needs, holds a targetless
-- frame on screen for Edit Mode, and reconciles the set against the database.
-- What is particular to one unit, the rested glow or the elite border, is the
-- definition's own paintState and events.
--
-- Draw order is the one thing here that is not a straight transcription. The
-- vanilla frames get their stacking from nesting: the border lives in a child
-- frame, so it draws over the portrait and the bars whatever their layers say,
-- because a child frame outranks every layer of its parent. The rebuild uses
-- three frame levels for the same result and skips the nesting:
--
--   frame     +0   the spec's onBase regions: flash, backing, portrait
--   bars      +1   health and power
--   artFrame  +2   the border, the state art over it, and all the text
--
-- Within artFrame the XML's own layers still order things.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames
local Art = UF.Art
local Values = UF.Values
local Harness = UF.Harness
local Suppression = UF.Suppression
local DB = addon.DB

local Frame = {}
UF.Frame = Frame

-- Build and reconcile order. The target comes before the frame that reads its
-- target.
UF.ORDER = { "player", "target", "focus", "targettarget", "pet" }

-- key -> instance, for every frame built this session.
UF.Frames = {}

local defs = {}

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------
-- There is no settings page yet. These are the values one will write.

DB.RegisterModule("unitFrames", true)

do
    local map = {
        -- Vanilla shows no number on either bar: the two FontStrings exist but
        -- sit behind the statusText CVar. On here until a page can ask.
        ["unitFrames.showBarText"] = true,
        -- The Forever bronze. "stock" is Blizzard's silver, kept for a toggle
        -- on the settings page once there is one.
        ["unitFrames.borderStyle"] = "tint",
    }
    for _, key in ipairs(UF.ORDER) do
        map["unitFrames." .. key .. ".enabled"] = true
        map["unitFrames." .. key .. ".scale"] = 1
    end
    DB.RegisterDefaults(map)
end

-- The Features page rows (forever/features.lua).
do
    local labels = { player = "Player", target = "Target", focus = "Focus",
                     targettarget = "Target of Target", pet = "Pet" }
    for _, key in ipairs(UF.ORDER) do
        addon.Features.Register({ group = "unitFrames", groupLabel = "Unit Frames",
            id = key, label = labels[key], path = "unitFrames." .. key .. ".enabled" })
    end
end

function UF.IsEnabled(key)
    if not DB.IsModuleEnabled("unitFrames") then return false end
    -- Held for the session: the Features page changes it at the reload.
    return DB.SessionGet("unitFrames." .. key .. ".enabled") and true or false
end

--------------------------------------------------------------------------------
-- Definitions
--------------------------------------------------------------------------------

--- def = {
---     key, unit, label, frameName,
---     default = { point, relPoint, x, y },   one table per frame, never shared:
---                                            Edit Mode keeps it by reference
---     strataLevel,
---     unitEvents = { ... },                  beyond the ones every frame takes
---     onUnitEvent = fn(inst, event) -> handled,
---     changeEvents = { EVENT = true | "unit" },  the unit token now names
---                                            someone else: repaint everything
---     events = { EVENT = fn(inst, ...) },    plain events, this unit's own
---     build = fn(inst),                      widgets beyond the spec
---     paintState = fn(inst),                 everything but bars and identity
--- }
function Frame.Define(def)
    defs[def.key] = def
end

--------------------------------------------------------------------------------
-- Widget construction
--------------------------------------------------------------------------------

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
    local nudge = def.nudge
    fs:SetPoint(def.point, host, def.relPoint or def.point,
        (def.x or 0) + (nudge and nudge.x or 0), (def.y or 0) + (nudge and nudge.y or 0))
    if def.justifyH then fs:SetJustifyH(def.justifyH) end
    if def.justifyV then fs:SetJustifyV(def.justifyV) end
    return fs
end

-- State art breathes rather than sitting lit. PlayerFrame_OnUpdate flips a
-- sign every half second and ramps alpha between 55/255 and 1 across it, which
-- is a one-second triangle, and the pet frame's attack wash does the same. A
-- looping animation is the same curve without a per-frame script, and a texture
-- can own an animation group directly.
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

--- Show and start a pulsed region, or stop and hide it. The stop comes first on
--- the way down, so the texture settles on its own alpha rather than wherever
--- the loop was.
function Frame.SetPulsed(inst, key, shown)
    local tex, group = inst.regions[key], inst.pulses[key]
    if not (tex and group) then return end
    if shown then
        tex:Show()
        if not group:IsPlaying() then group:Play() end
    else
        if group:IsPlaying() then group:Stop() end
        tex:SetAlpha(1.0)
        tex:Hide()
    end
end

-- The additive copy of the border the tint style lights (art.lua).
local function buildBorderLight(host, def)
    local copy = {}
    for k, v in pairs(def) do copy[k] = v end
    copy.blend = "ADD"
    copy.sublevel = (def.sublevel or 0) + 1
    copy.hidden = true
    return Art.BuildRegion(host, copy)
end

function Frame.Build(key)
    if UF.Frames[key] then return UF.Frames[key] end
    local def = defs[key]
    local spec = Art.Frames[key]
    if not (def and spec) then return nil end

    local inst = Harness.New({
        unit = def.unit,
        frameName = def.frameName,
        width = spec.width,
        height = spec.height,
        hitInsets = spec.hitInsets,
        point = def.default.point,
        relPoint = def.default.relPoint,
        x = def.default.x,
        y = def.default.y,
        strataLevel = def.strataLevel or 10,
    })
    inst.key = key
    inst.def = def
    inst.spec = spec
    inst.frame:SetScale(DB.Get("unitFrames." .. key .. ".scale") or 1)

    local base = inst.frame
    local level = base:GetFrameLevel()
    local onBase = spec.onBase or {}

    inst.regions = {}
    inst.pulses = {}
    inst.texts = {}

    -- DrawOrder, not pairs: two regions in one layer are ordered by creation,
    -- and an additive glow has to land on top of the icon it covers.
    for _, name in ipairs(spec.DrawOrder) do
        if onBase[name] then
            inst.regions[name] = Art.BuildRegion(base, spec.Regions[name])
        end
    end

    inst.healthBar = buildBar(base, spec.Bars.health, level + 1)
    inst.powerBar = buildBar(base, spec.Bars.power, level + 1)

    local artFrame = CreateFrame("Frame", nil, base)
    artFrame:SetAllPoints(base)
    artFrame:SetFrameLevel(level + 2)
    inst.artFrame = artFrame

    for _, name in ipairs(spec.DrawOrder) do
        if not onBase[name] then
            local regionDef = spec.Regions[name]
            inst.regions[name] = Art.BuildRegion(artFrame, regionDef)
            if regionDef.border then
                inst.borderLight = buildBorderLight(artFrame, regionDef)
            end
        end
    end

    for name, regionDef in pairs(spec.Regions) do
        if regionDef.pulse then
            inst.pulses[name] = attachPulse(inst.regions[name])
        end
    end

    local showBarText = DB.Get("unitFrames.showBarText")
    for name, textDef in pairs(spec.Text) do
        local isBarText = name == "healthValue" or name == "powerValue"
        if showBarText or not isBarText then
            inst.texts[name] = buildText(artFrame, textDef)
        end
    end
    inst.portrait = inst.regions.portrait
    inst.nameText = inst.texts.name
    inst.levelText = inst.texts.level
    inst.healthText = inst.texts.healthValue
    inst.powerText = inst.texts.powerValue
    if inst.texts.dead then
        inst.texts.dead:SetText(_G.DEAD or "Dead")
        inst.texts.dead:Hide()
    end

    if def.build then def.build(inst) end
    Art.ApplyBorder(inst)

    UF.Frames[key] = inst
    Frame.WireEvents(inst)

    -- def.default is where the frame sits until Edit Mode restores a stored
    -- spot, and the spot Reset To Default Position returns it to.
    UF.EditMode.Register(inst, {
        key = key,
        label = def.label,
        default = def.default,
    })

    return inst
end

--------------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------------

-- What a frame with no unit shows while Edit Mode holds it: the label for a
-- name, the player's own face and level, and two part-full bars. Static values
-- only, so nothing here can be secret.
local function paintStandIn(inst)
    if inst.nameText then inst.nameText:SetText(inst.def.label) end
    if inst.levelText then
        inst.levelText:SetText(UnitLevel("player"))
        inst.levelText:SetVertexColor(1.0, 0.82, 0)
        inst.levelText:Show()
    end
    if inst.portrait then
        pcall(SetPortraitTexture, inst.portrait, "player")
        inst.portrait:SetVertexColor(1, 1, 1)
    end
    inst.healthBar:SetMinMaxValues(0, 1)
    inst.healthBar:SetValue(0.72)
    inst.powerBar:SetMinMaxValues(0, 1)
    inst.powerBar:SetValue(0.45)
    inst.powerBar:SetStatusBarColor(0, 0, 1.0)
    inst.powerBar:Show()
    if inst.healthText then inst.healthText:ClearText() end
    if inst.powerText then inst.powerText:ClearText() end
end

function Frame.Paint(inst)
    if not inst.frame:IsShown() or inst.previewStandIn then return end
    Values.ApplyHealth(inst)
    Values.ApplyPower(inst)
    Values.ApplyBarText(inst)
end

function Frame.PaintAll(inst)
    if not inst.frame:IsShown() then return end
    if inst.previewStandIn then
        if inst.def.paintState then inst.def.paintState(inst) end
        paintStandIn(inst)
        return
    end
    Values.ApplyPowerColor(inst)
    Values.ApplyIdentity(inst)
    Values.ApplyPortrait(inst)
    if inst.def.paintState then inst.def.paintState(inst) end
    Frame.Paint(inst)
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

function Frame.WireEvents(inst)
    local frame = inst.frame
    local def = inst.def
    local owner = def.frameName

    for _, event in ipairs(UNIT_EVENTS) do
        frame:RegisterUnitEvent(event, inst.unit)
    end
    for _, event in ipairs(def.unitEvents or {}) do
        frame:RegisterUnitEvent(event, inst.unit)
    end

    -- Kept off addon.Events: RegisterUnitEvent filters in C to this unit, which
    -- the shared dispatcher cannot do. The plain events below use it.
    frame:SetScript("OnEvent", function(_, event)
        if inst.previewStandIn then return end
        if def.onUnitEvent and def.onUnitEvent(inst, event) then return end
        if event == "UNIT_DISPLAYPOWER" then
            Values.ApplyPowerColor(inst)
            Values.ApplyPower(inst)
        elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
            Values.ApplyIdentity(inst)
            if def.paintState then def.paintState(inst) end
        elseif event == "UNIT_PORTRAIT_UPDATE" then
            Values.ApplyPortrait(inst)
        else
            Frame.Paint(inst)
        end
    end)

    -- A unit event never fires because the token moved to another unit, so a
    -- new target would keep the last one's name and face without these.
    for event, filter in pairs(def.changeEvents or {}) do
        addon.Events.On(owner, event, function(_, unit)
            if filter ~= true and unit ~= filter then return end
            Frame.PaintAll(inst)
        end)
    end

    for event, fn in pairs(def.events or {}) do
        addon.Events.On(owner, event, function(_, ...) fn(inst, ...) end)
    end

    -- PORTRAITS_UPDATED carries no unit, so the C filter cannot narrow it. It
    -- is the global portrait refresh that Blizzard's own unit frames register
    -- beside UNIT_PORTRAIT_UPDATE.
    addon.Events.On(owner, "PORTRAITS_UPDATED", function()
        if not inst.previewStandIn then Values.ApplyPortrait(inst) end
    end)

    -- The paint gates on IsShown, so the manager's show has to trigger one.
    frame:SetScript("OnShow", function() Frame.PaintAll(inst) end)
end

--------------------------------------------------------------------------------
-- Edit Mode stand-in
--------------------------------------------------------------------------------
-- A targetless target frame is hidden, and Edit Mode has nothing to grab. While
-- Edit Mode is open every enabled frame drops its unit watch and shows. Two
-- flags: previewActive means Edit Mode is holding the frame, and previewStandIn
-- is the narrower claim that there is no unit to read, which is what swaps the
-- paint. A held frame that has a unit keeps its live paint.

function Frame.ShowPreview(inst)
    if not inst.enabled then return end
    inst.previewActive = true
    -- The watch first: a watched targetless frame would be hidden again by the
    -- manager's next scan. Both calls queue themselves in lockdown, and Edit
    -- Mode can be opened in combat.
    Harness.ApplyUnitWatch(inst)
    Harness.SetShownSafe(inst, true)
    if not inst.frame:IsShown() then
        Harness.QueueRegen(inst, "preview")
        return
    end

    local ok, exists = pcall(UnitExists, inst.unit)
    local noUnit = not ok or (not issecretvalue(exists) and exists == false)
    inst.previewStandIn = noUnit or nil
    Frame.PaintAll(inst)
end

function Frame.EndPreview(inst)
    if not inst.previewActive then return end
    inst.previewActive = nil
    inst.previewStandIn = nil
    -- Repaint from the unit while still shown, then let the watch decide.
    Frame.PaintAll(inst)
    Harness.UpdateVisibility(inst)
end

Harness.RegisterAction("preview", function(inst)
    if inst.previewActive then Frame.ShowPreview(inst) end
end)

local function onEditModeEnter()
    Suppression.ReassertAll()
    for _, key in ipairs(UF.ORDER) do
        local inst = UF.Frames[key]
        if inst then
            Frame.ShowPreview(inst)
            Harness.ApplyClickShown(inst)
        end
    end
end

local function onEditModeExit()
    Suppression.ReassertAll()
    for _, key in ipairs(UF.ORDER) do
        local inst = UF.Frames[key]
        if inst then
            Frame.EndPreview(inst)
            Harness.ApplyClickShown(inst)
        end
    end
end

--------------------------------------------------------------------------------
-- The set
--------------------------------------------------------------------------------

--- Reconcile every frame against the database: build what is enabled, show or
--- hide it, repaint it, and park or release Blizzard's frame for the unit.
function UF.ApplyAll()
    local editing = addon.EditMode.IsEditing and addon.EditMode.IsEditing()

    for _, key in ipairs(UF.ORDER) do
        local enabled = UF.IsEnabled(key)
        local inst = UF.Frames[key]
        if enabled and not inst then
            inst = Frame.Build(key)
        end
        if inst then
            inst.enabled = enabled
            if not enabled and inst.previewActive then
                inst.previewActive = nil
                inst.previewStandIn = nil
            end
            Harness.UpdateVisibility(inst)
            if enabled and editing then
                Frame.ShowPreview(inst)
            end
            Art.ApplyBorder(inst)
            Frame.PaintAll(inst)
        end
    end

    Suppression.Apply()
end

--- The profile engine's repaint entry point (forever/profiles.lua).
function UF.RefreshAll()
    UF.ApplyAll()
end

--- The enable switch, until a settings page owns it.
function UF.SetEnabled(key, on)
    if not defs[key] then return false end
    DB.Set("unitFrames." .. key .. ".enabled", on and true or false)
    DB.ClearSession("unitFrames." .. key .. ".enabled")
    UF.ApplyAll()
    return true
end

--- "stock", "tint" or "bronze" (art.lua, "The border style").
function UF.SetBorderStyle(style)
    if not Art.BORDER_STYLES[style] then return false end
    DB.Set("unitFrames.borderStyle", style)
    for _, inst in pairs(UF.Frames) do
        Art.ApplyBorder(inst)
    end
    return true
end

-- The definitions register at file scope below this file on the TOC, and the
-- database is read at ADDON_LOADED, so both are in place by the first world
-- entry. The queue runs once per session.
addon.Events.OnWorldEntered(function()
    addon.EditMode.OnEditMode("camelotUnitFrames", {
        enter = onEditModeEnter,
        exit = onEditModeExit,
    })
    UF.ApplyAll()
end)
