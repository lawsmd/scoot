--------------------------------------------------------------------------------
-- personal_resource_display/core.lua
-- Namespace, FrameState proxy, combat watcher, event framework, constants,
-- utilities, frame getters, border options builder, component registration.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil or {}

-- Create module namespace
addon.PRD = addon.PRD or {}
local PRD = addon.PRD

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
    return FS.Get(frame)
end

local function getProp(frame, key)
    local st = FS.Get(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = FS.Get(frame)
    if st then
        st[key] = value
    end
end

--------------------------------------------------------------------------------
-- Combat Restriction System
--------------------------------------------------------------------------------

local pendingCombatComponents = {}
local combatWatcherFrame

local function ensureCombatWatcher()
    if combatWatcherFrame or not CreateFrame then
        return
    end
    combatWatcherFrame = CreateFrame("Frame")
    combatWatcherFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatcherFrame:SetScript("OnEvent", function()
        for component in pairs(pendingCombatComponents) do
            pendingCombatComponents[component] = nil
            component._awaitingCombatEnd = nil
            if component.ApplyStyling then
                component:ApplyStyling()
            end
        end
    end)
end

local function isRestricted()
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return true
    end
    return false
end

local function queueAfterCombat(component)
    if not component then
        return
    end
    if component._awaitingCombatEnd then
        pendingCombatComponents[component] = true
        return
    end
    component._awaitingCombatEnd = true
    ensureCombatWatcher()
    pendingCombatComponents[component] = true
end

--------------------------------------------------------------------------------
-- CVar Check
--------------------------------------------------------------------------------

local function isPRDEnabledByCVar()
    if GetCVarBool then
        return GetCVarBool("nameplateShowSelf")
    end
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar("nameplateShowSelf") == "1"
    end
    return false
end

--------------------------------------------------------------------------------
-- Event Framework
--------------------------------------------------------------------------------

-- PRD re-application via events.
--
-- CRITICAL: hooksecurefunc cannot be used on any nameplate-related functions because
-- hook callbacks that run during Blizzard's nameplate setup chain taint the execution
-- context, causing SetTargetClampingInsets() to be blocked.
--
-- Instead, EVENT HANDLERS are used to re-apply styling. Events fire in separate execution
-- contexts and don't cause taint. The events used are:
-- - NAME_PLATE_UNIT_ADDED: Fires when a nameplate appears (after setup completes)
-- - PLAYER_TARGET_CHANGED: PRD may move when targeting changes
-- - PLAYER_REGEN_DISABLED/ENABLED: PRD visibility often changes with combat state
--
-- C_Timer.After(0, ...) defers styling to the next frame, ensuring execution is
-- completely outside any Blizzard execution chain.

local prdEventFrame = nil
local prdRegisteredComponents = {}

local function scheduleComponentApply(component)
    if not component or not component.ApplyStyling then
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if component and component.ApplyStyling then
                component:ApplyStyling()
            end
        end)
    end
end

local function onPRDEvent(self, event, ...)
    if not (C_Timer and C_Timer.After) then return end
    local function doApply()
        for component, _ in pairs(prdRegisteredComponents) do
            if component and component.ApplyStyling then
                -- Zero-Touch: skip unconfigured components (still on proxy DB)
                if not (component._ScootDBProxy and component.db == component._ScootDBProxy) then
                    component:ApplyStyling()
                end
            end
        end
        -- Always update opacity after styling (handles initial load and state changes)
        -- Late-bound: opacity.lua sets PRD._updateAllPRDOpacities before runtime calls
        PRD._updateAllPRDOpacities()
    end
    -- Defer to next frame to ensure execution is outside any callback chain
    C_Timer.After(0, doApply)
    -- UPDATE_SHAPESHIFT_FORM fires before UnitPowerType("player") transitions, so
    -- classPower color can resolve to the old power type on the first pass. Run
    -- a second pass once the power type has settled to correct the stuck color.
    if event == "UPDATE_SHAPESHIFT_FORM" then
        C_Timer.After(0.2, doApply)
    end
end

local function ensureEventFrame()
    if prdEventFrame then
        return prdEventFrame
    end

    prdEventFrame = CreateFrame("Frame")
    prdEventFrame:SetScript("OnEvent", onPRDEvent)

    -- Register events that indicate PRD state may have changed
    -- These fire AFTER Blizzard's nameplate setup completes
    prdEventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    prdEventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    prdEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    prdEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    prdEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    prdEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    prdEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    prdEventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    prdEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    -- Blizzard re-evaluates the alternate power bar on talent updates too.
    prdEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

    return prdEventFrame
end

local function ensureHooks(component)
    -- Register component for event-based re-application
    if component._hooksInstalled then
        return
    end
    component._hooksInstalled = true

    -- Set up the event frame (shared across all PRD components)
    ensureEventFrame()

    -- Register this component for event-driven updates
    prdRegisteredComponents[component] = true
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Druid form ID → display name lookup (for future UI consumption)
PRD.DRUID_FORM_NAMES = {
    [0]  = "Caster",
    [1]  = "Cat",
    [2]  = "Tree of Life",
    [3]  = "Travel",
    [5]  = "Bear",
    [31] = "Moonkin",
    [35] = "Moonkin",  -- talent variant, same display name
}

-- Sizing is native Edit Mode (12.0.7+): HealthBarHeight / PowerBarHeight are 10..30 px
-- sliders on PersonalResourceDisplayFrame; BarWidth / Size / Padding / Opacity are
-- PRD-wide and live on prdGlobal. Ranges below mirror EditModeSettingDisplayInfo.lua.
local MIN_BAR_HEIGHT = 10
local MAX_BAR_HEIGHT = 30
local DEFAULT_BAR_HEIGHT = 15
local MIN_CLASS_RESOURCE_SCALE_PERCENT = 50
local MAX_CLASS_RESOURCE_SCALE_PERCENT = 150

-- Classes that Blizzard gives an alternate power bar in the PRD
-- (CLASS_ALT_POWER_BAR_INFO_MAP, Blizzard_PersonalResourceDisplay.lua). The bar itself
-- shows only in one spec per class (Devourer, Augmentation, Brewmaster, Shadow, Balance).
local ALT_POWER_CLASSES = {
    DEMONHUNTER = true,
    EVOKER = true,
    MONK = true,
    PRIEST = true,
    DRUID = true,
}
PRD.ALT_POWER_CLASSES = ALT_POWER_CLASSES

function PRD.PlayerClassHasAltPowerBar()
    local _, playerClass = UnitClass("player")
    return ALT_POWER_CLASSES[playerClass] == true
end

-- Capture default CVar values to restore them if Static Mode is disabled
local defaultTopInset = (GetCVarDefault and GetCVarDefault("nameplateSelfTopInset")) or 0.5
local defaultBottomInset = (GetCVarDefault and GetCVarDefault("nameplateSelfBottomInset")) or 0.2

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

-- Power Bar hooks.
--
-- CRITICAL: no hooksecurefunc on the PRD's bars or their methods (Rule 11). Any hook
-- callback that runs during Blizzard's setup chain taints the execution context.
-- Sizing is no longer applied by Scoot at all: bar heights, width, scale and spacing are
-- Blizzard Edit Mode settings, mirrored two-way by editmode.lua (Edit-Mode-first).

local function ensurePowerBarHooks(component)
    -- INTENTIONALLY EMPTY: No hooks are installed to avoid taint.
end

local function clampValue(value, minValue, maxValue)
    if minValue and value < minValue then
        value = minValue
    end
    if maxValue and value > maxValue then
        value = maxValue
    end
    return value
end

local function copyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copyValue(v)
    end
    return out
end

local function ensureSettingValue(component, key)
    if not component or not component.db then return nil end
    return component.db[key]
end

local function ensureColorSetting(component, key, fallback)
    local value = ensureSettingValue(component, key)
    local base = fallback or {1, 1, 1, 1}
    if type(value) ~= "table" then
        value = copyValue(base)
    end
    return {
        value[1] or base[1] or 1,
        value[2] or base[2] or 1,
        value[3] or base[3] or 1,
        value[4] or base[4] or 1,
    }
end

local function setSettingValue(component, key, value)
    if not component or not component.db then
        return
    end
    if type(value) == "table" then
        component.db[key] = copyValue(value)
    else
        component.db[key] = value
    end
end

--------------------------------------------------------------------------------
-- Frame Getters
--------------------------------------------------------------------------------

local function getHealthContainer()
    local prd = PersonalResourceDisplayFrame
    if not prd then
        return nil
    end
    local container = prd.HealthBarsContainer
    if not container or (container.IsForbidden and container:IsForbidden()) then
        return nil
    end
    return container
end

local function getPowerBar()
    local prd = PersonalResourceDisplayFrame
    if not prd then
        return nil
    end
    local bar = prd.PowerBar
    if not bar or (bar.IsForbidden and bar:IsForbidden()) then
        return nil
    end
    return bar
end

-- The alternate power bar (12.0.7). Blizzard creates it for every class and shows it
-- only when the class/spec has an alternate resource (alternatePowerRequirementsMet).
local function getAltPowerBar()
    local prd = PersonalResourceDisplayFrame
    if not prd then
        return nil
    end
    local bar = prd.AlternatePowerBar
    if not bar or (bar.IsForbidden and bar:IsForbidden()) then
        return nil
    end
    return bar
end

--------------------------------------------------------------------------------
-- Border Options Builder
--------------------------------------------------------------------------------

local function buildPRDBorderOptions()
    local base = addon.BuildBarBorderOptionsContainer and addon.BuildBarBorderOptionsContainer() or {}
    local hasNone = false
    if type(base) == "table" then
        for _, entry in ipairs(base) do
            if entry and entry.value == "none" then
                hasNone = true
                break
            end
        end
    end
    if Settings and Settings.CreateControlTextContainer then
        local container = Settings.CreateControlTextContainer()
        if not hasNone then
            container:Add("none", "None")
        end
        if type(base) == "table" then
            for _, entry in ipairs(base) do
                if entry and entry.value and entry.text then
                    container:Add(entry.value, entry.text)
                end
            end
        end
        if type(base) ~= "table" or #base == 0 then
            container:Add("square", "Default (Square)")
        end
        return container:GetData()
    end
    local results = {}
    if not hasNone then
        table.insert(results, { value = "none", text = "None" })
    end
    local added = false
    if type(base) == "table" then
        for _, entry in ipairs(base) do
            table.insert(results, entry)
            added = true
        end
    end
    if not added then
        table.insert(results, { value = "square", text = "Default (Square)" })
    end
    return results
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    -- PRD Global component: PRD-wide Blizzard Edit Mode settings, mirrored two-way by
    -- editmode.lua (native applies them; Scoot only stores and syncs). Positioning is
    -- handled entirely via Edit Mode.
    local global = Component:New({
        id = "prdGlobal",
        name = "PRD — Global",
        frameName = nil,
        settings = {
            -- Native VisibleSetting: always / combat / never (Always, Only in Combat, Hidden)
            visibleSetting = { type = "addon", default = "always", ui = { hidden = true }},
            -- Native Size (whole-PRD scale), percent
            scale = { type = "addon", default = 100, ui = { hidden = true }},
            -- Native BarWidth, percent of Blizzard's default width; sets every PRD bar
            barWidth = { type = "addon", default = 100, ui = { hidden = true }},
            -- Native Padding: extra gap between bars
            barPadding = { type = "addon", default = 0, ui = { hidden = true }},
            -- Native Opacity (whole-PRD alpha, 50-100). Per-bar state opacity multiplies on top.
            opacity = { type = "addon", default = 100, ui = { hidden = true }},
        },
    })
    global.ApplyStyling = function(component)
        if not addon or not addon.Components then
            return
        end
        -- Trigger re-styling of child components. Skip parts still on their zero-touch
        -- proxy: running their applicators would materialize them (write-back
        -- normalizations) and draw default borders the user never asked for.
        local comps = addon.Components
        local function apply(target)
            if not target or not target.ApplyStyling then return end
            if target._ScootDBProxy and target.db == target._ScootDBProxy then return end
            target:ApplyStyling()
        end
        apply(comps.prdHealth)
        apply(comps.prdPower)
        apply(comps.prdAltPower)
        apply(comps.prdClassResource)
    end
    ensureHooks(global)
    self:RegisterComponent(global)

    local health = Component:New({
        id = "prdHealth",
        name = "PRD — Health Bar",
        frameName = nil,
        supportsEmptyStyleSection = true,
        supportsEmptyVisibilitySection = true,
        settings = {
            -- Native HealthBarHeight (Edit Mode, 10-30 px). Width is PRD-wide: prdGlobal.barWidth.
            barHeight = { type = "addon", default = DEFAULT_BAR_HEIGHT, ui = {
                label = "Bar Height", widget = "slider", min = MIN_BAR_HEIGHT, max = MAX_BAR_HEIGHT, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the health bar height."
            }},
            styleForegroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundTint = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            styleBackgroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundTint = { type = "addon", default = {0, 0, 0, 1}, ui = { hidden = true }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = { hidden = true }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = buildPRDBorderOptions,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1, 1, 1, 1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4,
            }},
            borderInset = { type = "addon", default = 0, ui = { hidden = true }},
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            borderHiddenEdges = { type = "addon", default = nil },
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Health Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
            hideTextureOnly = { type = "addon", default = false, ui = {
                label = "Hide the Bar but not its Text", widget = "checkbox", section = "Misc", order = 2,
            }},
            -- Hides Blizzard's 12.0.7 bar backdrop art (UI-HUD-CoolDownManager-Bar-BG)
            -- while keeping the bar fill visible. Rendered manually by HealthBarRenderer.
            hideBarBackground = { type = "addon", default = false, ui = { hidden = true }},
            hideHealthLossAnimation = { type = "addon", default = false, ui = {
                label = "Hide Health Loss Animation", widget = "checkbox", section = "Misc", order = 3,
            }},
            -- Opacity settings (addon-only, 1-100 percentage)
            opacityInCombat = { type = "addon", default = 100, ui = { hidden = true }},
            opacityWithTarget = { type = "addon", default = 100, ui = { hidden = true }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = { hidden = true }},
            -- Per-text overlay settings (value = right text, percent = left text)
            valueTextShow = { type = "addon", default = false, ui = { hidden = true }},
            valueTextFont = { type = "addon", default = "Friz Quadrata TT", ui = { hidden = true }},
            valueTextFontSize = { type = "addon", default = 10, ui = { hidden = true }},
            valueTextFontFlags = { type = "addon", default = "OUTLINE", ui = { hidden = true }},
            valueTextColor = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            valueTextColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            valueTextAlignment = { type = "addon", default = "RIGHT", ui = { hidden = true }},
            percentTextShow = { type = "addon", default = false, ui = { hidden = true }},
            percentTextFont = { type = "addon", default = "Friz Quadrata TT", ui = { hidden = true }},
            percentTextFontSize = { type = "addon", default = 10, ui = { hidden = true }},
            percentTextFontFlags = { type = "addon", default = "OUTLINE", ui = { hidden = true }},
            percentTextColor = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            percentTextColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            percentTextAlignment = { type = "addon", default = "LEFT", ui = { hidden = true }},
        },
    })
    health.ApplyStyling = function(comp)
        -- Late-bound: bars.lua sets PRD._applyHealthOffsets before runtime calls
        PRD._applyHealthOffsets(comp)
    end
    ensureHooks(health)
    self:RegisterComponent(health)

    local power = Component:New({
        id = "prdPower",
        name = "PRD — Power Bar",
        frameName = nil,
        supportsEmptyStyleSection = true,
        supportsEmptyVisibilitySection = true,
        settings = {
            -- Native PowerBarHeight (Edit Mode, 10-30 px). Blizzard applies the same height to
            -- the alternate power bar. Width is PRD-wide: prdGlobal.barWidth.
            barHeight = { type = "addon", default = DEFAULT_BAR_HEIGHT, ui = {
                label = "Bar Height", widget = "slider", min = MIN_BAR_HEIGHT, max = MAX_BAR_HEIGHT, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the power bar height."
            }},
            styleForegroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundTint = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            styleBackgroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundTint = { type = "addon", default = {0, 0, 0, 1}, ui = { hidden = true }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = { hidden = true }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = buildPRDBorderOptions,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1, 1, 1, 1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4,
            }},
            borderInset = { type = "addon", default = 0, ui = { hidden = true }},
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            borderHiddenEdges = { type = "addon", default = nil },
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Power Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
            hideTextureOnly = { type = "addon", default = false, ui = {
                label = "Hide the Bar but not its Text", widget = "checkbox", section = "Misc", order = 2,
            }},
            -- Hides Blizzard's 12.0.7 bar backdrop art (UI-HUD-CoolDownManager-Bar-BG)
            -- while keeping the bar fill visible. Rendered manually by PowerBarRenderer.
            hideBarBackground = { type = "addon", default = false, ui = { hidden = true }},
            hideSpikeAnimations = { type = "addon", default = false, ui = {
                label = "Hide Full Bar Animations", widget = "checkbox", section = "Misc", order = 3,
            }},
            hidePowerFeedback = { type = "addon", default = false, ui = {
                label = "Hide Power Feedback", widget = "checkbox", section = "Misc", order = 4,
            }},
            hideManaCostPrediction = { type = "addon", default = false, ui = {
                label = "Hide Mana Cost Predictions", widget = "checkbox", section = "Misc", order = 5,
            }},
            -- Opacity settings (addon-only, 1-100 percentage)
            opacityInCombat = { type = "addon", default = 100, ui = { hidden = true }},
            opacityWithTarget = { type = "addon", default = 100, ui = { hidden = true }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = { hidden = true }},
            -- Per-text overlay settings (value = right text, percent = left text)
            valueTextShow = { type = "addon", default = false, ui = { hidden = true }},
            valueTextFont = { type = "addon", default = "Friz Quadrata TT", ui = { hidden = true }},
            valueTextFontSize = { type = "addon", default = 10, ui = { hidden = true }},
            valueTextFontFlags = { type = "addon", default = "OUTLINE", ui = { hidden = true }},
            valueTextColor = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            valueTextColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            valueTextColorModeDK = { type = "addon", default = nil, ui = { hidden = true }},
            valueTextAlignment = { type = "addon", default = "RIGHT", ui = { hidden = true }},
            percentTextShow = { type = "addon", default = false, ui = { hidden = true }},
            percentTextFont = { type = "addon", default = "Friz Quadrata TT", ui = { hidden = true }},
            percentTextFontSize = { type = "addon", default = 10, ui = { hidden = true }},
            percentTextFontFlags = { type = "addon", default = "OUTLINE", ui = { hidden = true }},
            percentTextColor = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            percentTextColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            percentTextColorModeDK = { type = "addon", default = nil, ui = { hidden = true }},
            percentTextAlignment = { type = "addon", default = "LEFT", ui = { hidden = true }},
            -- Druid per-form text visibility: table of formID → false to hide. Empty = all visible.
            valueTextDruidForms = { type = "addon", default = {}, ui = { hidden = true }},
            percentTextDruidForms = { type = "addon", default = {}, ui = { hidden = true }},
        },
    })
    power.ApplyStyling = function(comp)
        if comp.db then
            addon.MigrateDKColorMode(
                function() return comp.db.valueTextColorMode end,
                function(v) comp.db.valueTextColorMode = v end,
                function() return comp.db.valueTextColorModeDK end,
                function(v) comp.db.valueTextColorModeDK = v end
            )
            addon.MigrateDKColorMode(
                function() return comp.db.percentTextColorMode end,
                function(v) comp.db.percentTextColorMode = v end,
                function() return comp.db.percentTextColorModeDK end,
                function(v) comp.db.percentTextColorModeDK = v end
            )
        end
        -- Late-bound: bars.lua sets PRD._ensurePowerBarHooks and PRD._applyPowerOffsets
        PRD._ensurePowerBarHooks(comp)
        PRD._applyPowerOffsets(comp)
    end
    ensureHooks(power)
    self:RegisterComponent(power)

    -- Alternate power bar (12.0.7): PersonalResourceDisplayFrame.AlternatePowerBar.
    -- Same PersonalResourceStatusBar template as the power bar, minus the full-power /
    -- feedback / mana-cost children and minus a percent stream (value only, in TextString).
    -- Height follows the power bar natively; width is PRD-wide.
    local altPower = Component:New({
        id = "prdAltPower",
        name = "PRD — Alternate Power Bar",
        frameName = nil,
        supportsEmptyStyleSection = true,
        supportsEmptyVisibilitySection = true,
        settings = {
            styleForegroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            -- "default" follows Blizzard's live colour (stagger thresholds, void metamorphosis, mana)
            styleForegroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleForegroundTint = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            styleBackgroundTexture = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            styleBackgroundTint = { type = "addon", default = {0, 0, 0, 1}, ui = { hidden = true }},
            styleBackgroundOpacity = { type = "addon", default = 50, ui = { hidden = true }},
            borderStyle = { type = "addon", default = "square", ui = {
                label = "Border Style", widget = "dropdown", section = "Border", order = 1,
                optionsProvider = buildPRDBorderOptions,
            }},
            borderTintEnable = { type = "addon", default = false, ui = {
                label = "Border Tint", widget = "checkbox", section = "Border", order = 2,
            }},
            borderTintColor = { type = "addon", default = {1, 1, 1, 1}, ui = {
                label = "Tint Color", widget = "color", section = "Border", order = 3,
            }},
            borderThickness = { type = "addon", default = 1, ui = {
                label = "Border Thickness", widget = "slider", min = 1, max = 8, step = 0.5, section = "Border", order = 4,
            }},
            borderInset = { type = "addon", default = 0, ui = { hidden = true }},
            borderInsetH = { type = "addon", default = 0 },
            borderInsetV = { type = "addon", default = 0 },
            borderHiddenEdges = { type = "addon", default = nil },
            -- Mirrors native HideAltPower (Edit Mode)
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Alternate Power Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
            hideTextureOnly = { type = "addon", default = false, ui = {
                label = "Hide the Bar but not its Text", widget = "checkbox", section = "Misc", order = 2,
            }},
            hideBarBackground = { type = "addon", default = false, ui = { hidden = true }},
            -- Opacity settings (addon-only, 1-100 percentage)
            opacityInCombat = { type = "addon", default = 100, ui = { hidden = true }},
            opacityWithTarget = { type = "addon", default = 100, ui = { hidden = true }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = { hidden = true }},
            -- Value text only (the alt bar has no percent stream)
            valueTextShow = { type = "addon", default = false, ui = { hidden = true }},
            valueTextFont = { type = "addon", default = "Friz Quadrata TT", ui = { hidden = true }},
            valueTextFontSize = { type = "addon", default = 10, ui = { hidden = true }},
            valueTextFontFlags = { type = "addon", default = "OUTLINE", ui = { hidden = true }},
            valueTextColor = { type = "addon", default = {1, 1, 1, 1}, ui = { hidden = true }},
            valueTextColorMode = { type = "addon", default = "default", ui = { hidden = true }},
            valueTextAlignment = { type = "addon", default = "RIGHT", ui = { hidden = true }},
            -- Druid per-form text visibility (Balance shows a mana alt bar in every form)
            valueTextDruidForms = { type = "addon", default = {}, ui = { hidden = true }},
        },
    })
    altPower.ApplyStyling = function(comp)
        -- Late-bound: bars.lua sets PRD._applyAltPowerOffsets
        PRD._applyAltPowerOffsets(comp)
    end
    ensureHooks(altPower)
    self:RegisterComponent(altPower)

    local classRes = Component:New({
        id = "prdClassResource",
        name = "PRD — Class Resource",
        frameName = nil,
        supportsEmptyVisibilitySection = true,
        settings = {
            scale = { type = "addon", default = 100, ui = {
                label = "Scale", widget = "slider", min = MIN_CLASS_RESOURCE_SCALE_PERCENT, max = MAX_CLASS_RESOURCE_SCALE_PERCENT, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the class resource size."
            }},
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Class Resource", widget = "checkbox", section = "Misc", order = 1,
            }},
            -- 12.0.7 native toggle: hides the class resource shown under the regular
            -- Player Frame (independent of the PRD). Rendered manually by ClassResourceRenderer.
            hideClassInfoOnPlayerFrame = { type = "addon", default = false, ui = { hidden = true }},
            -- Opacity settings (addon-only, 1-100 percentage)
            opacityInCombat = { type = "addon", default = 100, ui = { hidden = true }},
            opacityWithTarget = { type = "addon", default = 100, ui = { hidden = true }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = { hidden = true }},
        },
    })
    classRes.ApplyStyling = function(comp)
        -- Late-bound: bars.lua sets PRD._applyClassResourceOffsets before runtime calls
        PRD._applyClassResourceOffsets(comp)
    end
    ensureHooks(classRes)
    self:RegisterComponent(classRes)
end, "prd")

--------------------------------------------------------------------------------
-- Namespace Promotions
--------------------------------------------------------------------------------

PRD._getState = getState
PRD._getProp = getProp
PRD._setProp = setProp
PRD._isPRDEnabledByCVar = isPRDEnabledByCVar
PRD._getHealthContainer = getHealthContainer
PRD._getPowerBar = getPowerBar
PRD._getAltPowerBar = getAltPowerBar
PRD._clampValue = clampValue
PRD._copyValue = copyValue
PRD._ensureSettingValue = ensureSettingValue
PRD._setSettingValue = setSettingValue
PRD._ensureColorSetting = ensureColorSetting
PRD._queueAfterCombat = queueAfterCombat
PRD._buildPRDBorderOptions = buildPRDBorderOptions
PRD._ensurePowerBarHooks = ensurePowerBarHooks
PRD._MIN_BAR_HEIGHT = MIN_BAR_HEIGHT
PRD._MAX_BAR_HEIGHT = MAX_BAR_HEIGHT
PRD._DEFAULT_BAR_HEIGHT = DEFAULT_BAR_HEIGHT
PRD._MIN_CLASS_RESOURCE_SCALE_PERCENT = MIN_CLASS_RESOURCE_SCALE_PERCENT
PRD._MAX_CLASS_RESOURCE_SCALE_PERCENT = MAX_CLASS_RESOURCE_SCALE_PERCENT
