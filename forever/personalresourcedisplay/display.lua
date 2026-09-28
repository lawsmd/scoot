--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/display.lua
-- The Personal Resource Display: CamelotPersonalResourceDisplay fed from the
-- player unit, Blizzard's PersonalResourceDisplayFrame parked, and
-- /camelot prd.
--
-- The feeds are the Classic unit frames' (forever/unitframes/values.lua):
-- SetMinMaxValues then SetValue, never a read back, so a secret goes in as
-- it comes. The heal prediction segments are the unit frames' file on its
-- host seam (forever/unitframes/healprediction.lua), and the mana cost is a
-- reverse-fill segment over the fill's right end, fed the spell's cost, a
-- plain number. Blizzard's own PRD Lua compares UnitHealth and UnitPower
-- and does not run here.
--
-- Visibility is Blizzard's rule without the enabled half: Edit Mode shows;
-- Always shows; In Combat shows while the player is in combat; Hidden
-- hides. The nameplateShowSelf CVar and the Edit Mode account checkbox keep
-- acting on the parked Blizzard frame and never on this one.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style

local Display = {}
PRD.Display = Display

local OWNER = PRD.OWNER

-- Blizzard's show-time unit events, each with what it refreshes here.
local UNIT_EVENTS = {
    UNIT_HEALTH = "health",
    UNIT_MAXHEALTH = "health",
    UNIT_MAX_HEALTH_MODIFIERS_CHANGED = "health",
    UNIT_HEAL_PREDICTION = "health",
    UNIT_ABSORB_AMOUNT_CHANGED = "health",
    UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "health",
    UNIT_POWER_FREQUENT = "power",
    UNIT_MAXPOWER = "power",
    UNIT_DISPLAYPOWER = "displaypower",
    UNIT_SPELLCAST_START = "cost",
    UNIT_SPELLCAST_STOP = "cost",
    UNIT_SPELLCAST_FAILED = "cost",
}

-- Blizzard's ManaCostPredictionBar: UI-StatusBar in the mana prediction
-- color, an engine global; the XML's own blue stands in.
local COST_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function costColor()
    local c = _G.POWERBAR_PREDICTION_COLOR_MANA
    if type(c) == "table" and c.GetRGBA then return c:GetRGBA() end
    return 0, 0.447, 1, 1
end

-- For the reads that decide something: nil for a secret, an error or a
-- missing API.
local function plain(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

local built = false
local inst
local lastCost = 0

local function values()
    return addon.UnitFrames and addon.UnitFrames.Values
end

--------------------------------------------------------------------------------
-- Feeds
--------------------------------------------------------------------------------

-- The temporary max health loss bar, Blizzard's mixin on Blizzard's input.
-- The percent is plain on the API's word; a secret, a missing function or
-- an error inside the mixin hides the bar.
local function refreshMaxHealthLoss()
    local loss = inst.frame.HealthBarsContainer.TempMaxHealthLoss
    local percent = plain(_G.GetUnitTotalModifiedMaxHealthPercent, "player")
    if type(percent) ~= "number" or not loss.initialized then
        loss:Hide()
        return
    end
    local ok = pcall(loss.OnMaxHealthModifiersChanged, loss, percent)
    if not ok then loss:Hide() end
end

-- The spell being cast and its cost in the displayed power: both plain, and
-- anything else reads as no cost.
local function readCost()
    local spellID = plain(function() return select(9, UnitCastingInfo("player")) end)
    if type(spellID) ~= "number" then return 0 end
    local powerType = plain(UnitPowerType, "player")
    if type(powerType) ~= "number" then return 0 end
    local costs = plain(C_Spell.GetSpellPowerCost, spellID)
    if type(costs) ~= "table" then return 0 end
    for _, info in pairs(costs) do
        if type(info) == "table" and info.type == powerType and type(info.cost) == "number" then
            return info.cost
        end
    end
    return 0
end

--- The mana cost segment: ranged to the power's max and fed the cost, in
--- reverse from the fill's right edge.
function Display.RefreshCost()
    if not built then return end
    local seg = inst.cost
    local ok, cost = pcall(readCost)
    if not ok or type(cost) ~= "number" then cost = 0 end
    lastCost = cost
    if cost > 0 and Style.Get("power", "hideManaCostPrediction") ~= true then
        seg:SetMinMaxValues(0, UnitPowerMax("player"))
        seg:SetValue(cost)
        seg:Show()
    else
        seg:Hide()
    end
end

-- The percent strings, through the shared chain (core/percent.lua): the
-- secret string into SetText, and ClearText when the chain gives none, so a
-- failed read shows a blank rather than a stale number. The verdicts are
-- what /camelot prd prints.
local lastPercent = { health = "not run", power = "not run" }

local function feedPercent(fs, kind)
    if not fs then
        lastPercent[kind] = "off"
        return
    end
    local Percent = addon.Percent
    if not Percent then
        lastPercent[kind] = "addon.Percent missing"
        fs:ClearText()
        return
    end
    local str, verdict
    if kind == "health" then
        str, verdict = Percent.Health("player", true, nil)
    else
        str, verdict = Percent.Power("player", nil, nil)
    end
    lastPercent[kind] = verdict
    if not (str and pcall(fs.SetText, fs, str)) then
        fs:ClearText()
        if str then lastPercent[kind] = "SetText failed" end
    end
end

function Display.RefreshHealth()
    if not built then return end
    local Values = values()
    if not Values then return end
    Values.ApplyHealth(inst)
    Values.ApplyBarText(inst)
    feedPercent(inst.healthPercentText, "health")
    local HP = addon.UnitFrames.HealPrediction
    if HP and inst.healPrediction then HP.Update(inst) end
    refreshMaxHealthLoss()
end

function Display.RefreshPower()
    if not built then return end
    local Values = values()
    if not Values then return end
    local state = inst.powerState
    Values.ApplyPower(inst)
    -- The feed recolors on a state change (dead, offline, back); a custom
    -- tint goes back on after it.
    if inst.powerState ~= state then Style.ApplyPowerColor() end
    Values.ApplyBarText(inst)
    feedPercent(inst.powerPercentText, "power")
    Display.RefreshCost()
end

--- Everything the events feed, plus the cost segment's size, which follows
--- the bar's settings. Style.Apply and world entry.
function Display.Refresh()
    if not built then return end
    inst.cost:SetSize(Style.BarWidthPixels(), Style.Height("power"))
    Display.RefreshHealth()
    Display.RefreshPower()
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

local function inCombat()
    return plain(UnitAffectingCombat, "player") == true
end

--- Blizzard's UpdateShownState without the enabled half.
function Display.UpdateShownState()
    if not built then return end
    local editing = addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing()
    local visibility = Style.Visibility()
    local shown = editing or visibility == "always" or (visibility == "combat" and inCombat())
    inst.frame:SetShown(shown and true or false)
end

--------------------------------------------------------------------------------
-- Suppression
--------------------------------------------------------------------------------
-- Blizzard's frame is a UIParent child and parks under the hidden holder.
-- Never released: the Features switch lands at reload, and a feature off at
-- login never claims. The park is skipped in combat, so a reload in a fight
-- leaves Blizzard's frame live until regen.

local claimed = false

local function claim()
    if claimed or not PRD.IsEnabled() then return end
    local target = PersonalResourceDisplayFrame
    if not (target and addon.NativeFrame) then return end
    if not addon.NativeFrame:IsSuppressed(target) then
        addon.NativeFrame:Suppress(target, OWNER, "park")
    end
    claimed = true
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function buildCost(powerBar)
    local seg = CreateFrame("StatusBar", nil, powerBar)
    seg:SetFrameLevel(powerBar:GetFrameLevel())
    seg:SetStatusBarTexture(COST_TEXTURE)
    seg:SetStatusBarColor(costColor())
    seg:SetReverseFill(true)
    seg:SetMinMaxValues(0, 1)
    seg:SetValue(0)
    -- Anchored to the fill on purpose: the segment ends where the fill ends.
    seg:SetPoint("RIGHT", powerBar:GetStatusBarTexture(), "RIGHT")
    seg:SetSize(Style.BarWidthPixels(), Style.Height("power"))
    seg:Hide()
    return seg
end

local function onUnitEvent(_, event)
    local kind = UNIT_EVENTS[event]
    if kind == "health" then
        Display.RefreshHealth()
    elseif kind == "power" then
        Display.RefreshPower()
    elseif kind == "displaypower" then
        Style.ApplyPowerColor()
        Display.RefreshPower()
    elseif kind == "cost" then
        Display.RefreshCost()
    end
end

local function onVehicle()
    Style.ApplyPowerColor()
    Display.RefreshPower()
end

local function wireEvents(frame)
    -- Under pcall: an event this client lacks throws on registration.
    for event in pairs(UNIT_EVENTS) do
        pcall(frame.RegisterUnitEvent, frame, event, "player")
    end
    -- Kept off addon.Events: RegisterUnitEvent filters in C to this unit, which
    -- the shared dispatcher cannot do. The plain events below use it.
    frame:SetScript("OnEvent", onUnitEvent)

    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function()
        claim()
        Display.Refresh()
        Display.UpdateShownState()
    end)
    addon.Events.On(OWNER, "PLAYER_IN_COMBAT_CHANGED", Display.UpdateShownState)
    addon.Events.On(OWNER, "PLAYER_GAINS_VEHICLE_DATA", onVehicle)
    addon.Events.On(OWNER, "PLAYER_LOSES_VEHICLE_DATA", onVehicle)
end

-- Clicks never: a click child would make the frame protected. Motion only
-- while a text is On Hover (style.lua, ApplyText).
local function wireHover(frame)
    pcall(frame.SetMouseClickEnabled, frame, false)
    frame:SetScript("OnEnter", function()
        PRD.hovering = true
        Style.ApplyHover(true)
    end)
    frame:SetScript("OnLeave", function()
        PRD.hovering = false
        Style.ApplyHover(false)
    end)
end

function Display.Build()
    if built or not PRD.IsEnabled() then return end
    local frame = Style.Frame()
    if not frame then return end

    local healthBar = Style.Bar(frame, "health")
    local powerBar = Style.Bar(frame, "power")

    -- The instance table the unit frames' feeds and heal prediction take.
    -- spec.Bars.health.color is what ApplyHealth restores each tick; the
    -- style writes it. healHost is healprediction.lua's seam. The four text
    -- fields are the style's to set or clear (Style.ApplyText).
    inst = {
        unit = "player",
        frame = frame,
        healthBar = healthBar,
        powerBar = powerBar,
        healthText = healthBar.RightText,
        powerText = powerBar.RightText,
        healthPercentText = healthBar.LeftText,
        powerPercentText = powerBar.LeftText,
        spec = { Bars = { health = {} } },
    }
    inst.healHost = {
        surface = true,
        size = function() return Style.BarWidthPixels(), Style.Height("health") end,
        glowParent = healthBar,
        show = function(field) return Style.Get("health", field) ~= false end,
        standIn = function() return false end,
    }
    PRD.inst = inst

    addon.Strata.ApplyHUD(frame, 30)
    -- Ranged before the first feed, so a large first value cannot clamp.
    healthBar:SetMinMaxValues(0, 1)
    powerBar:SetMinMaxValues(0, 1)
    inst.cost = buildCost(powerBar)

    wireHover(frame)
    wireEvents(frame)
    built = true

    Style.Apply()
    claim()
    if PRD.EditMode then PRD.EditMode.Register(frame) end
    if PRD.Dynamic then PRD.Dynamic.Register(frame) end
    Display.UpdateShownState()
end

function Display.IsBuilt()
    return built
end

addon.Events.OnWorldEntered(function()
    Display.Build()
end)

--------------------------------------------------------------------------------
-- /camelot prd
--------------------------------------------------------------------------------

local POWER_TYPES = { "Mana", "Rage", "Energy", "ComboPoints" }

local function secrecyName(value)
    if type(value) ~= "number" then return tostring(value) end
    for name, tbl in pairs(Enum) do
        if type(name) == "string" and name:find("Secrecy") and type(tbl) == "table" then
            for k, v in pairs(tbl) do
                if v == value then return name .. "." .. k .. " (" .. value .. ")" end
            end
        end
    end
    return tostring(value)
end

local function secrecy(typeName)
    local powerType = Enum.PowerType and Enum.PowerType[typeName]
    if not powerType then return "no Enum.PowerType." .. typeName end
    if not (C_Secrets and C_Secrets.GetPowerTypeSecrecy) then return "no C_Secrets.GetPowerTypeSecrecy" end
    local ok, value = pcall(C_Secrets.GetPowerTypeSecrecy, powerType)
    if not ok then return "error: " .. tostring(value) end
    return secrecyName(value)
end

local function anchorText(a)
    if type(a) ~= "table" then return "none" end
    return string.format("%s to %s %s (%s, %s)", tostring(a.point), tostring(a.relativeTo),
        tostring(a.relativePoint), tostring(a.offsetX), tostring(a.offsetY))
end

-- Blizzard's PRD anchor in each custom layout. The presets are not in the
-- list C_EditMode hands back; the Modern preset's anchor is the constant in
-- style.lua.
local function layoutAnchors(push)
    local ok, err = pcall(function()
        local info = C_EditMode.GetLayouts()
        push("  Edit Mode: active layout index %s, %d custom layouts",
            tostring(info and info.activeLayout), info and info.layouts and #info.layouts or 0)
        local system = Enum.EditModeSystem and Enum.EditModeSystem.PersonalResourceDisplay
        for _, layout in ipairs(info and info.layouts or {}) do
            local found = "no PRD entry"
            for _, sys in ipairs(layout.systems or {}) do
                if sys.system == system then found = anchorText(sys.anchorInfo) end
            end
            push("    %s: %s", tostring(layout.layoutName), found)
        end
    end)
    if not ok then push("  Edit Mode layouts: error %s", tostring(err)) end
end

local function frameLine(push, label, frame)
    if not frame then
        push("  %s: absent", label)
        return
    end
    local ok, text = pcall(function()
        local parent = frame:GetParent()
        local point, rel, relPoint, x, y = frame:GetPoint(1)
        return string.format("parent %s, shown %s, visible %s, alpha %.2f, scale %.2f, size %.0f x %.0f, point %s to %s %s (%.1f, %.1f)",
            parent and parent:GetName() or tostring(parent), tostring(frame:IsShown()), tostring(frame:IsVisible()),
            frame:GetAlpha(), frame:GetScale(), frame:GetWidth(), frame:GetHeight(),
            tostring(point), rel and rel.GetName and rel:GetName() or tostring(rel), tostring(relPoint), x or 0, y or 0)
    end)
    push("  %s: %s", label, ok and text or ("unreadable: " .. tostring(text)))
end

function Display.Dump()
    local lines, push = addon.DebugLines()
    local frame = Style.Frame()
    push("Camelot Personal Resource Display: enabled %s, built %s, lockdown %s, editing %s",
        tostring(PRD.IsEnabled()), tostring(built), tostring(InCombatLockdown()),
        tostring(addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing()))
    frameLine(push, "Camelot frame", frame)
    frameLine(push, "Blizzard frame", PersonalResourceDisplayFrame)
    push("  Blizzard frame parked: %s",
        tostring(PersonalResourceDisplayFrame and addon.NativeFrame
            and addon.NativeFrame:IsSuppressed(PersonalResourceDisplayFrame)))
    push("  settings: visibility %s, scale %s, bar width %s%%, spacing %s, opacity %s",
        Style.Visibility(), Style.Scale(), Style.BarWidthPercent(), Style.Padding(), Style.Opacity())
    for _, key in ipairs(Style.BARS) do
        push("  %s: height %s, hide %s, texture %s, color %s, border %s, value text %s, percent text %s",
            key, Style.Height(key), tostring(Style.Get(key, "hide")), tostring(Style.Get(key, "foregroundTexture")),
            tostring(Style.Get(key, "foregroundColorMode")), tostring(Style.Get(key, "borderStyle")),
            Style.TextShow(key, "value"), Style.TextShow(key, "percent"))
    end
    push("  percent chain: health %s, power %s", tostring(lastPercent.health), tostring(lastPercent.power))
    local HP = addon.UnitFrames and addon.UnitFrames.HealPrediction
    push("  heal prediction: %s", (HP and HP.HostSeam and inst) and HP.Describe(inst) or "seam not present")
    push("  last mana cost read: %s; hide %s", tostring(lastCost), tostring(Style.Get("power", "hideManaCostPrediction")))
    for _, name in ipairs(POWER_TYPES) do
        push("  secrecy of %s: %s", name, secrecy(name))
    end
    push("  specialization: %s", tostring(plain(function() return C_SpecializationInfo.GetSpecialization() end)))
    push("  power type: %s", tostring(plain(UnitPowerType, "player")))
    layoutAnchors(push)
    if PRD.Dynamic then push("  dynamic layouts: %s", PRD.Dynamic.Describe()) end
    addon.DebugShowWindow("Camelot Personal Resource Display", lines)
end

addon:RegisterSlashCommand({
    name = "prd",
    help = "show the Personal Resource Display: the frame, its settings, the parked Blizzard frame, the power type secrecies",
    handler = function() Display.Dump() end,
})
