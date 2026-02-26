local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil or {}

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

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

local function isPRDEnabledByCVar()
    if GetCVarBool then
        return GetCVarBool("nameplateShowSelf")
    end
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar("nameplateShowSelf") == "1"
    end
    return false
end

-- Forward declarations for bar overlay functions (defined in Bar Overlay System section below).
local hidePRDBarOverlay
local showPRDOriginalFill

-- Forward declarations for PRD frame getters (defined later, called by opacity system).
local getHealthContainer
local getPowerBar

-- Forward declaration for text overlay storage (defined in Text Overlay System section).
local textOverlays

-- Forward declarations for opacity system.
local updateAllPRDOpacities

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
    -- Defer all styling to next frame to ensure we're outside any execution chain
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            for component, _ in pairs(prdRegisteredComponents) do
                if component and component.ApplyStyling then
                    component:ApplyStyling()
                end
            end
            -- Always update opacity after styling (handles initial load and state changes)
            updateAllPRDOpacities()
        end)
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

local MIN_HEALTH_BAR_WIDTH = 60
local MAX_HEALTH_BAR_WIDTH = 600
local MIN_HEALTH_BAR_HEIGHT = 4
local MAX_HEALTH_BAR_HEIGHT = 60
local MIN_POWER_BAR_WIDTH = 40
local MAX_POWER_BAR_WIDTH = 600
local MIN_POWER_BAR_HEIGHT = 4
local MAX_POWER_BAR_HEIGHT = 40
local MIN_CLASS_RESOURCE_SCALE_PERCENT = 50
local MAX_CLASS_RESOURCE_SCALE_PERCENT = 150

-- Capture default CVar values to restore them if Static Mode is disabled
local defaultTopInset = (GetCVarDefault and GetCVarDefault("nameplateSelfTopInset")) or 0.5
local defaultBottomInset = (GetCVarDefault and GetCVarDefault("nameplateSelfBottomInset")) or 0.2


-- Power Bar height management.
--
-- CRITICAL: OnSizeChanged and other nameplate-related methods are no longer hooked.
--
-- The problem: ANY hooksecurefunc callback that runs during Blizzard's nameplate setup
-- chain (including OnSizeChanged which fires when SetShown() is called) will taint the
-- execution context, causing SetTargetClampingInsets() to be blocked.
--
-- Instead, power bar height is applied directly via SetHeight() in applyPowerOffsets().
-- This height may be reset by Blizzard during spec changes, instance transitions, etc.,
-- but that's preferable to causing taint errors. Users can re-apply via settings or /reload.
--
-- NOTE: Width control was removed entirely because Blizzard's SetupClassNameplateBars()
-- continuously re-applies TOPLEFT+TOPRIGHT anchors which control width via the layout system.
-- Power bar width now automatically follows the health bar width.

local function ensurePowerBarHooks(component)
    -- INTENTIONALLY EMPTY: No hooks are installed to avoid taint.
    -- Height is applied directly in applyPowerOffsets().
    -- See comment block above for explanation.
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

-- Find the Blizzard-native border frame for a PRD bar.
-- Health bar: border is on the parent container (HealthBarsContainer.border)
-- Power bar: border is directly on the bar (PowerBar.Border)
local function findBlizzardBorderFrame(bar)
    if not bar then return nil end
    local borderFrame = bar.Border or bar.border
    if not borderFrame then
        local ok, parent = pcall(bar.GetParent, bar)
        if ok and parent then
            borderFrame = parent.border or parent.Border
        end
    end
    return borderFrame
end

-- Hide or show the Blizzard-native border frame (Left/Right/Top/Bottom edge textures).
local function setBlizzardBorderVisible(bar, visible)
    local borderFrame = findBlizzardBorderFrame(bar)
    if not borderFrame then return end
    if visible then
        pcall(borderFrame.Show, borderFrame)
    else
        pcall(borderFrame.Hide, borderFrame)
    end
end

local function clearBarBorder(bar)
    if not bar then
        return
    end
    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
        addon.BarBorders.ClearBarFrame(bar)
    end
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(bar)
    end
    -- Restore Blizzard's native border when the custom border is cleared
    setBlizzardBorderVisible(bar, true)
end

--------------------------------------------------------------------------------
-- PRD Opacity System
-- Implements state-based opacity (combat > target > out-of-combat).
-- SetAlpha on PRD frames is safe (not protected).
--------------------------------------------------------------------------------

-- Get opacity value based on current combat/target state
local function getPRDOpacityForState(componentId)
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return 1.0 end

    local db = component.db
    local inCombat = InCombatLockdown and InCombatLockdown()
    local hasTarget = UnitExists("target")

    -- Priority: combat > target > out-of-combat
    local opacityValue
    if inCombat then
        opacityValue = tonumber(db.opacityInCombat) or 100
    elseif hasTarget then
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end

    -- Convert from percentage (1-100) to alpha (0.01-1.0)
    return math.max(0.01, math.min(1.0, opacityValue / 100))
end

-- Apply opacity to prdHealth component
local function applyPRDHealthOpacity()
    local component = addon.Components and addon.Components.prdHealth
    if not component or not component.db then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local container = getHealthContainer()
    if not container then return end

    local alpha = getPRDOpacityForState("prdHealth")
    pcall(container.SetAlpha, container, alpha)

    -- Also apply to the text overlay if it exists
    local storage = textOverlays.health
    if storage and storage.overlay then
        pcall(storage.overlay.SetAlpha, storage.overlay, alpha)
    end
end

-- Apply opacity to prdPower component
local function applyPRDPowerOpacity()
    local component = addon.Components and addon.Components.prdPower
    if not component or not component.db then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local frame = getPowerBar()
    if not frame then return end

    local alpha = getPRDOpacityForState("prdPower")
    pcall(frame.SetAlpha, frame, alpha)

    -- Also apply to the text overlay if it exists
    local storage = textOverlays.power
    if storage and storage.overlay then
        pcall(storage.overlay.SetAlpha, storage.overlay, alpha)
    end
end

-- Apply opacity to prdClassResource component
local function applyPRDClassResourceOpacity()
    local component = addon.Components and addon.Components.prdClassResource
    if not component or not component.db then return end

    -- Skip if bar is hidden
    if component.db.hideBar then return end

    local prd = PersonalResourceDisplayFrame
    if not prd then return end
    local classContainer = prd.ClassFrameContainer
    if not classContainer then return end

    local frame
    if classContainer.GetChildren then
        frame = classContainer:GetChildren()
    end
    if not frame then return end
    if frame.IsForbidden and frame:IsForbidden() then return end

    local alpha = getPRDOpacityForState("prdClassResource")
    pcall(frame.SetAlpha, frame, alpha)
end

-- Update all PRD component opacities based on current state
-- (Assigns to forward-declared local)
updateAllPRDOpacities = function()
    applyPRDHealthOpacity()
    applyPRDPowerOpacity()
    applyPRDClassResourceOpacity()
end

-- Exposed function for settings changes (immediate slider feedback)
function addon.RefreshPRDOpacity(componentId)
    if componentId == "prdHealth" then
        applyPRDHealthOpacity()
    elseif componentId == "prdPower" then
        applyPRDPowerOpacity()
    elseif componentId == "prdClassResource" then
        applyPRDClassResourceOpacity()
    else
        updateAllPRDOpacities()
    end
end

local function storeOriginalAlpha(frame, storageKey)
    if not frame or not frame.GetAlpha then
        return
    end
    storageKey = storageKey or "_ScootPRDOrigAlpha"
    if getProp(frame, storageKey) ~= nil then
        return
    end
    local ok, alpha = pcall(frame.GetAlpha, frame)
    setProp(frame, storageKey, ok and (alpha or 1) or 1)
end

local function applyHiddenAlpha(frame, hidden, storageKey)
    if not frame or not frame.SetAlpha then
        return
    end
    storageKey = storageKey or "_ScootPRDOrigAlpha"
    if hidden then
        storeOriginalAlpha(frame, storageKey)
        pcall(frame.SetAlpha, frame, 0)
    else
        local original = getProp(frame, storageKey)
        if original == nil then
            original = 1
        end
        pcall(frame.SetAlpha, frame, original)
    end
end

--------------------------------------------------------------------------------
-- Text Overlay System
-- Mirrors Player Unit Frame Power/Health Bar text onto the PRD bars via hooks.
-- No UnitPower/UnitHealth calls, no arithmetic, no secrets issues.
-- Source: Player UF ManaBar.LeftText/RightText → PRD PowerBar overlay
-- Source: Player UF HealthBar.LeftText/RightText → PRD HealthBar overlay
--------------------------------------------------------------------------------

-- Storage for text overlay state (one per bar type, not per bar instance)
-- (Assigns to forward-declared local)
textOverlays = {
    health = { lastLeft = nil, lastRight = nil, overlay = nil, leftFS = nil, rightFS = nil },
    power = { lastLeft = nil, lastRight = nil, overlay = nil, leftFS = nil, rightFS = nil },
}

-- Hook installation tracking
local textHooksInstalled = { power = false, health = false }

-- Resolve font path from font name or font key
local function resolveFontPath(fontName)
    if not fontName or fontName == "" then
        return "Fonts\\FRIZQT__.TTF"
    end
    if fontName:match("\\") or fontName:match("/") then
        return fontName
    end
    -- Check addon.Fonts registry (handles keys like ROBOTO_REG, FIRASANS_BOLD, etc.)
    if addon.Fonts and addon.Fonts[fontName] then
        return addon.Fonts[fontName]
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("font", fontName)
        if path then return path end
    end
    local fontMap = {
        ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
        ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
        ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
        ["Skurri"] = "Fonts\\SKURRI.TTF",
    }
    return fontMap[fontName] or "Fonts\\FRIZQT__.TTF"
end

-- Create overlay FontStrings on a PRD bar (one overlay per bar type)
local function ensureTextOverlay(bar, overlayType)
    if not bar then return nil, nil end

    local storage = textOverlays[overlayType]
    if not storage then return nil, nil end

    -- Already created
    if storage.overlay then
        -- Re-anchor in case the bar was recreated
        pcall(storage.overlay.SetPoint, storage.overlay, "TOPLEFT", bar, "TOPLEFT", 0, 0)
        pcall(storage.overlay.SetPoint, storage.overlay, "BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        return storage.leftFS, storage.rightFS
    end

    -- Create overlay frame parented to UIParent, anchored to PRD bar
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameStrata("HIGH")
    overlay:SetFrameLevel(100)
    overlay:Show()

    local leftText = overlay:CreateFontString(nil, "OVERLAY")
    leftText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    leftText:SetPoint("LEFT", overlay, "LEFT", 4, 0)
    leftText:SetJustifyH("LEFT")
    leftText:SetTextColor(1, 1, 1, 1)
    leftText:Show()

    local rightText = overlay:CreateFontString(nil, "OVERLAY")
    rightText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    rightText:SetPoint("RIGHT", overlay, "RIGHT", -4, 0)
    rightText:SetJustifyH("RIGHT")
    rightText:SetTextColor(1, 1, 1, 1)
    rightText:Show()

    storage.overlay = overlay
    storage.leftFS = leftText
    storage.rightFS = rightText

    return leftText, rightText
end

-- Apply text alignment by re-anchoring a FontString within the overlay
local function applyTextAlignment(fs, overlay, alignment)
    if not fs or not overlay then return end
    pcall(fs.ClearAllPoints, fs)
    if alignment == "LEFT" then
        pcall(fs.SetPoint, fs, "LEFT", overlay, "LEFT", 4, 0)
    elseif alignment == "CENTER" then
        pcall(fs.SetPoint, fs, "CENTER", overlay, "CENTER", 0, 0)
    else -- "RIGHT"
        pcall(fs.SetPoint, fs, "RIGHT", overlay, "RIGHT", -4, 0)
    end
end

-- Apply text styling from component settings (per-text independent settings)
local function resolveColorMode(colorMode, rawColor, overlayType)
    -- Backward compat: existing custom color without mode = treat as custom
    if not colorMode then
        local c = rawColor
        if c and (c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or (c[4] or 1) ~= 1) then
            colorMode = "custom"
        else
            colorMode = "default"
        end
    end

    if colorMode == "class" then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        return {cr or 1, cg or 1, cb or 1, 1}
    elseif colorMode == "classPower" and overlayType == "power" then
        local pr, pg, pb = addon.GetPowerColorRGB("player")
        return {pr or 1, pg or 1, pb or 1, 1}
    elseif colorMode == "custom" then
        return rawColor or {1, 1, 1, 1}
    else
        return {1, 1, 1, 1}
    end
end

local function applyTextStyle(leftText, rightText, component, overlayType)
    if not component or not component.db then return end

    local db = component.db
    local storage = textOverlays[overlayType]

    -- Left = percent text
    if leftText then
        local font = db.percentTextFont or "Friz Quadrata TT"
        local size = tonumber(db.percentTextFontSize) or 10
        local flags = db.percentTextFontFlags or "OUTLINE"
        local color = resolveColorMode(db.percentTextColorMode, db.percentTextColor, overlayType)
        local align = db.percentTextAlignment or "LEFT"
        local path = resolveFontPath(font)
        addon.ApplyFontStyle(leftText, path, size, flags)
        pcall(leftText.SetTextColor, leftText, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        pcall(leftText.SetJustifyH, leftText, align)
        if storage then
            applyTextAlignment(leftText, storage.overlay, align)
        end
    end

    -- Right = value text
    if rightText then
        local font = db.valueTextFont or "Friz Quadrata TT"
        local size = tonumber(db.valueTextFontSize) or 10
        local flags = db.valueTextFontFlags or "OUTLINE"
        local color = resolveColorMode(db.valueTextColorMode, db.valueTextColor, overlayType)
        local align = db.valueTextAlignment or "RIGHT"
        local path = resolveFontPath(font)
        addon.ApplyFontStyle(rightText, path, size, flags)
        pcall(rightText.SetTextColor, rightText, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        pcall(rightText.SetJustifyH, rightText, align)
        if storage then
            applyTextAlignment(rightText, storage.overlay, align)
        end
    end
end

-- Apply cached text values after overlay creation based on per-text show flags
-- Note: cached values may be secret values. SetText(secret) is allowed.
local function applyCachedText(overlayType, db)
    local storage = textOverlays[overlayType]
    if not storage then return end
    if db.percentTextShow and storage.leftFS then
        pcall(storage.leftFS.SetText, storage.leftFS, storage.lastLeft)
    end
    if db.valueTextShow and storage.rightFS then
        pcall(storage.rightFS.SetText, storage.rightFS, storage.lastRight)
    end
end

-- Hide text overlay
local function hideTextOverlay(overlayType)
    local storage = textOverlays[overlayType]
    if not storage or not storage.overlay then return end
    pcall(storage.overlay.Hide, storage.overlay)
end

-- Show text overlay
local function showTextOverlay(overlayType)
    local storage = textOverlays[overlayType]
    if not storage or not storage.overlay then return end
    pcall(storage.overlay.Show, storage.overlay)
end

-- Helper: update a single overlay FontString from a hook callback
local function onSourceTextChanged(overlayType, side, text)
    local storage = textOverlays[overlayType]
    if not storage then return end

    if side == "left" then
        storage.lastLeft = text
    else
        storage.lastRight = text
    end

    -- Get the component to check per-text show settings
    local compId = (overlayType == "power") and "prdPower" or "prdHealth"
    local comp = addon.Components and addon.Components[compId]
    if not comp or not comp.db then return end

    local fs = (side == "left") and storage.leftFS or storage.rightFS
    if not fs then return end

    -- text may be a secret value; SetText(secret) is allowed and renders it
    if side == "left" then
        if comp.db.percentTextShow then
            pcall(fs.SetText, fs, text)
        end
    else
        if comp.db.valueTextShow then
            pcall(fs.SetText, fs, text)
        end
    end
end

-- Install hooks on Player UF Power Bar text (ManaBar.LeftText / .RightText)
local function installPowerTextHooks()
    if textHooksInstalled.power then return end

    local manaBar = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
    if not manaBar then return end

    local leftSource = manaBar.LeftText
    local rightSource = manaBar.RightText

    if leftSource then
        hooksecurefunc(leftSource, "SetText", function(self, text)
            onSourceTextChanged("power", "left", text)
        end)
        if leftSource.SetFormattedText then
            hooksecurefunc(leftSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("power", "left", text) end
            end)
        end
        -- Capture initial value (may be secret value; SetText(secret) is allowed)
        local ok, text = pcall(leftSource.GetText, leftSource)
        if ok then
            textOverlays.power.lastLeft = text
        end
    end

    if rightSource then
        hooksecurefunc(rightSource, "SetText", function(self, text)
            onSourceTextChanged("power", "right", text)
        end)
        if rightSource.SetFormattedText then
            hooksecurefunc(rightSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("power", "right", text) end
            end)
        end
        local ok, text = pcall(rightSource.GetText, rightSource)
        if ok then
            textOverlays.power.lastRight = text
        end
    end

    textHooksInstalled.power = true
end

-- Install hooks on Player UF Health Bar text (HealthBar.LeftText / .RightText)
local function installHealthTextHooks()
    if textHooksInstalled.health then return end

    local healthBar = PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
    if not healthBar then return end

    local leftSource = healthBar.LeftText
    local rightSource = healthBar.RightText

    if leftSource then
        hooksecurefunc(leftSource, "SetText", function(self, text)
            onSourceTextChanged("health", "left", text)
        end)
        if leftSource.SetFormattedText then
            hooksecurefunc(leftSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("health", "left", text) end
            end)
        end
        local ok, text = pcall(leftSource.GetText, leftSource)
        if ok then
            textOverlays.health.lastLeft = text
        end
    end

    if rightSource then
        hooksecurefunc(rightSource, "SetText", function(self, text)
            onSourceTextChanged("health", "right", text)
        end)
        if rightSource.SetFormattedText then
            hooksecurefunc(rightSource, "SetFormattedText", function(self, ...)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged("health", "right", text) end
            end)
        end
        local ok, text = pcall(rightSource.GetText, rightSource)
        if ok then
            textOverlays.health.lastRight = text
        end
    end

    textHooksInstalled.health = true
end

-- Apply text overlay for power bar (called from power.ApplyStyling)
local function applyPowerTextOverlay(comp)
    if not comp or not comp.db then return end

    local db = comp.db
    local showValue = db.valueTextShow
    local showPercent = db.percentTextShow

    if (not showValue and not showPercent) or db.hideBar then
        hideTextOverlay("power")
        return
    end

    -- Target: PRD Power Bar
    local prdPowerBar = PersonalResourceDisplayFrame and PersonalResourceDisplayFrame.PowerBar
    if not prdPowerBar then return end

    -- Install hooks on Player UF ManaBar text
    installPowerTextHooks()

    -- Create/get overlay FontStrings anchored to PRD Power Bar
    local leftText, rightText = ensureTextOverlay(prdPowerBar, "power")
    if not leftText and not rightText then return end

    showTextOverlay("power")
    applyTextStyle(leftText, rightText, comp, "power")

    -- Show/hide individual FontStrings
    if showPercent then pcall(leftText.Show, leftText) else pcall(leftText.Hide, leftText) end
    if showValue then pcall(rightText.Show, rightText) else pcall(rightText.Hide, rightText) end

    applyCachedText("power", db)
end

-- Apply text overlay for health bar (called from health.ApplyStyling)
local function applyHealthTextOverlay(comp)
    if not comp or not comp.db then return end

    local db = comp.db
    local showValue = db.valueTextShow
    local showPercent = db.percentTextShow

    if (not showValue and not showPercent) or db.hideBar then
        hideTextOverlay("health")
        return
    end

    -- Target: PRD Health Bar
    local prdHealthBar = PersonalResourceDisplayFrame
        and PersonalResourceDisplayFrame.HealthBarsContainer
        and PersonalResourceDisplayFrame.HealthBarsContainer.healthBar
    if not prdHealthBar then return end

    -- Install hooks on Player UF HealthBar text
    installHealthTextHooks()

    -- Create/get overlay FontStrings anchored to PRD Health Bar
    local leftText, rightText = ensureTextOverlay(prdHealthBar, "health")
    if not leftText and not rightText then return end

    showTextOverlay("health")
    applyTextStyle(leftText, rightText, comp, "health")

    -- Show/hide individual FontStrings
    if showPercent then pcall(leftText.Show, leftText) else pcall(leftText.Hide, leftText) end
    if showValue then pcall(rightText.Show, rightText) else pcall(rightText.Hide, rightText) end

    applyCachedText("health", db)
end

--------------------------------------------------------------------------------
-- Bar Overlay System
-- Uses overlay textures anchored to StatusBarTexture (auto-follows fill level).
-- Overlay frames are parented to UIParent to avoid taint on nameplate frames.
-- Pattern matches Boss/Party/Raid frame overlays (secret-safe, no secret values).
--------------------------------------------------------------------------------

local prdBarOverlays = {
    health = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
    power = { frame = nil, fgTexture = nil, bgFrame = nil, bgTexture = nil, origFillHidden = false, hookedTexture = nil },
}

-- Create or re-anchor the foreground overlay for a PRD bar.
-- The overlay texture is anchored directly to the StatusBarTexture, so it
-- automatically resizes as bar value changes (no hooks needed for width tracking).
local function ensurePRDForegroundOverlay(bar, barType)
    if not bar then return nil end
    local storage = prdBarOverlays[barType]
    if not storage then return nil end

    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not statusBarTex then return nil end

    if not storage.frame then
        local overlayFrame = CreateFrame("Frame", nil, UIParent)
        overlayFrame:SetFrameStrata("MEDIUM")
        overlayFrame:SetFrameLevel(50)

        local fgTexture = overlayFrame:CreateTexture(nil, "ARTWORK")
        fgTexture:SetVertTile(false)
        fgTexture:SetHorizTile(false)
        fgTexture:SetTexCoord(0, 1, 0, 1)

        storage.frame = overlayFrame
        storage.fgTexture = fgTexture
    end

    -- Anchor overlay frame to the StatusBarTexture (the fill portion)
    storage.frame:ClearAllPoints()
    storage.frame:SetPoint("TOPLEFT", statusBarTex, "TOPLEFT")
    storage.frame:SetPoint("BOTTOMRIGHT", statusBarTex, "BOTTOMRIGHT")

    -- Foreground texture fills the overlay frame
    storage.fgTexture:ClearAllPoints()
    storage.fgTexture:SetAllPoints(storage.frame)

    return storage
end

-- Create or re-anchor the background overlay for a PRD bar.
-- Background covers the full bar area (not just the fill portion).
local function ensurePRDBackgroundOverlay(bar, barType)
    if not bar then return nil end
    local storage = prdBarOverlays[barType]
    if not storage then return nil end

    if not storage.bgFrame then
        local bgFrame = CreateFrame("Frame", nil, UIParent)
        bgFrame:SetFrameStrata("MEDIUM")
        bgFrame:SetFrameLevel(49)

        local bgTexture = bgFrame:CreateTexture(nil, "BACKGROUND")
        bgTexture:SetAllPoints(bgFrame)

        storage.bgFrame = bgFrame
        storage.bgTexture = bgTexture
    end

    -- Anchor background to the full bar bounds
    storage.bgFrame:ClearAllPoints()
    storage.bgFrame:SetPoint("TOPLEFT", bar, "TOPLEFT")
    storage.bgFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")

    return storage
end

-- Hide the original StatusBarTexture fill and hook SetAlpha to keep it hidden.
-- Tracks which texture instance was hooked; re-hooks if the bar gets a new instance.
local function hidePRDOriginalFill(bar, barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end

    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not statusBarTex then return end

    pcall(statusBarTex.SetAlpha, statusBarTex, 0)
    storage.origFillHidden = true

    -- Only hook if this is a new/different StatusBarTexture instance
    if hooksecurefunc and storage.hookedTexture ~= statusBarTex then
        storage.hookedTexture = statusBarTex
        hooksecurefunc(statusBarTex, "SetAlpha", function(self, alpha)
            if storage.origFillHidden and storage.hookedTexture == self and alpha > 0 then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if storage.origFillHidden and storage.hookedTexture == self then
                            pcall(self.SetAlpha, self, 0)
                        end
                    end)
                end
            end
        end)
    end
end

-- Restore the original StatusBarTexture fill visibility.
-- (Assigns to forward-declared local)
showPRDOriginalFill = function(bar, barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end

    storage.origFillHidden = false
    if not bar then return end
    local statusBarTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if statusBarTex then
        pcall(statusBarTex.SetAlpha, statusBarTex, 1)
    end
end

-- Apply foreground texture overlay to a PRD bar.
local function applyPRDForegroundStyle(bar, barType, component)
    if not bar or not component then return end

    local textureKey = ensureSettingValue(component, "styleForegroundTexture") or "default"
    local colorMode = ensureSettingValue(component, "styleForegroundColorMode") or "default"
    local tint = ensureColorSetting(component, "styleForegroundTint", {1, 1, 1, 1})

    local isDefaultTex = (textureKey == nil or textureKey == "" or textureKey == "default")
    local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")

    if isDefaultTex and isDefaultColor then
        -- No customization: hide overlay, restore original fill
        local storage = prdBarOverlays[barType]
        if storage and storage.frame then
            storage.frame:Hide()
        end
        showPRDOriginalFill(bar, barType)
        return
    end

    -- Ensure overlay exists and is anchored
    local storage = ensurePRDForegroundOverlay(bar, barType)
    if not storage then return end

    -- Apply texture
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(textureKey)
    if resolvedPath then
        pcall(storage.fgTexture.SetTexture, storage.fgTexture, resolvedPath)
    else
        -- Copy from bar's current StatusBarTexture (atlas or file path)
        local statusBarTex = bar:GetStatusBarTexture()
        if statusBarTex then
            local okAtlas, atlasName = pcall(statusBarTex.GetAtlas, statusBarTex)
            if okAtlas and atlasName and atlasName ~= "" then
                pcall(storage.fgTexture.SetAtlas, storage.fgTexture, atlasName, true)
            else
                local okTex, texPath = pcall(statusBarTex.GetTexture, statusBarTex)
                if okTex and texPath then
                    pcall(storage.fgTexture.SetTexture, storage.fgTexture, texPath)
                end
            end
        end
    end

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
    elseif colorMode == "class" then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        r, g, b, a = cr or 1, cg or 1, cb or 1, 1
    elseif colorMode == "power" and barType == "power" then
        local pr, pg, pb = addon.GetPowerColorRGB("player")
        r, g, b, a = pr or 1, pg or 1, pb or 1, 1
    elseif colorMode == "texture" then
        r, g, b, a = 1, 1, 1, 1  -- Raw texture colors unmodified
    elseif colorMode == "default" then
        -- Blizzard's intended bar color
        if barType == "health" then
            local hr, hg, hb = addon.GetDefaultHealthColorRGB()
            r, g, b, a = hr or 0, hg or 1, hb or 0, 1
        elseif barType == "power" then
            local pr, pg, pb = addon.GetPowerColorRGB("player")
            r, g, b, a = pr or 1, pg or 1, pb or 1, 1
        end
    end
    pcall(storage.fgTexture.SetVertexColor, storage.fgTexture, r, g, b, a)

    -- Show overlay, hide original fill
    storage.frame:Show()
    storage.fgTexture:Show()
    hidePRDOriginalFill(bar, barType)
end

-- Apply background texture overlay to a PRD bar.
local function applyPRDBackgroundStyle(bar, barType, component)
    if not bar or not component then return end

    local bgTextureKey = ensureSettingValue(component, "styleBackgroundTexture") or "default"
    local colorMode = ensureSettingValue(component, "styleBackgroundColorMode") or "default"
    local tint = ensureColorSetting(component, "styleBackgroundTint", {0, 0, 0, 1})
    local opacity = ensureSettingValue(component, "styleBackgroundOpacity")
    opacity = tonumber(opacity) or 50
    opacity = clampValue(math.floor(opacity + 0.5), 0, 100)
    setSettingValue(component, "styleBackgroundOpacity", opacity)

    local isDefaultTex = (bgTextureKey == nil or bgTextureKey == "" or bgTextureKey == "default")
    local isDefaultColor = (colorMode == nil or colorMode == "" or colorMode == "default")

    if isDefaultTex and isDefaultColor then
        local storage = prdBarOverlays[barType]
        if storage and storage.bgFrame then
            storage.bgFrame:Hide()
        end
        return
    end

    -- Ensure background overlay exists
    local storage = ensurePRDBackgroundOverlay(bar, barType)
    if not storage then return end

    -- Apply texture
    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(bgTextureKey)
    if resolvedPath then
        pcall(storage.bgTexture.SetTexture, storage.bgTexture, resolvedPath)
    else
        -- Default: solid color fill
        if storage.bgTexture.SetColorTexture then
            pcall(storage.bgTexture.SetColorTexture, storage.bgTexture, 0, 0, 0, 1)
        end
    end

    -- Apply color
    local r, g, b, a = 0, 0, 0, 1
    if colorMode == "custom" and type(tint) == "table" then
        r, g, b, a = tint[1] or 0, tint[2] or 0, tint[3] or 0, tint[4] or 1
    end
    pcall(storage.bgTexture.SetVertexColor, storage.bgTexture, r, g, b, a)

    -- Apply opacity
    local alphaValue = opacity / 100
    pcall(storage.bgFrame.SetAlpha, storage.bgFrame, alphaValue)

    storage.bgFrame:Show()
    storage.bgTexture:Show()
end

-- Hide all PRD bar overlays (used during cleanup or when bar is hidden).
-- (Assigns to forward-declared local)
hidePRDBarOverlay = function(barType)
    local storage = prdBarOverlays[barType]
    if not storage then return end
    if storage.frame then
        pcall(storage.frame.Hide, storage.frame)
    end
    if storage.bgFrame then
        pcall(storage.bgFrame.Hide, storage.bgFrame)
    end
    storage.origFillHidden = false
    storage.hookedTexture = nil
end

local function applyPRDBarBorder(component, statusBar)
    if not component or not statusBar then
        return
    end
    local db = component.db or {}
    local styleKey = db.borderStyle or "square"
    if styleKey == "none" then
        clearBarBorder(statusBar)
        return
    end
    -- Hide Blizzard's native border edges (Left/Right/Top/Bottom textures)
    -- since a custom border is being applied to this bar.
    setBlizzardBorderVisible(statusBar, false)
    local tintEnabled = db.borderTintEnable and true or false
    local tintColor = ensureColorSetting(component, "borderTintColor", {1, 1, 1, 1})
    local thickness = tonumber(db.borderThickness) or 1
    thickness = clampValue(math.floor(thickness * 2 + 0.5) / 2, 1, 16)
    local insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or 0
    local insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or 0
    insetH = clampValue(math.floor(insetH + 0.5), -4, 4)
    insetV = clampValue(math.floor(insetV + 0.5), -4, 4)
    setSettingValue(component, "borderThickness", thickness)
    setSettingValue(component, "borderInsetH", insetH)
    setSettingValue(component, "borderInsetV", insetV)
    local color
    if tintEnabled then
        color = tintColor
    else
        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
        if styleDef then
            color = {1, 1, 1, 1}
        else
            color = {0, 0, 0, 1}
        end
    end
    if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
        if addon.BarBorders.ClearBarFrame then
            addon.BarBorders.ClearBarFrame(statusBar)
        end
        local handled = addon.BarBorders.ApplyToBarFrame(statusBar, styleKey, {
            color = color,
            thickness = thickness,
            levelOffset = 51,
            insetH = insetH,
            insetV = insetV,
        })
        if handled then
            -- Hide any old square border that may have been applied previously
            if addon.Borders and addon.Borders.HideAll then
                addon.Borders.HideAll(statusBar)
            end
            return
        end
    end
    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
        addon.BarBorders.ClearBarFrame(statusBar)
    end
    if addon.Borders and addon.Borders.ApplySquare then
        local fallbackColor = tintEnabled and tintColor or {0, 0, 0, 1}
        local baseY = (thickness <= 1) and 0 or 1
        local baseX = 1
        local expandY = baseY - insetV
        local expandX = baseX - insetH
        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
        addon.Borders.ApplySquare(statusBar, {
            size = thickness,
            color = fallbackColor,
            layer = "OVERLAY",
            layerSublevel = 3,
            levelOffset = 51,
            expandX = expandX,
            expandY = expandY,
        })
    end
end

-- Hide/restore ManaCostPredictionBar on the PRD power bar.
-- Uses the same recursion-guard hook pattern as hidePRDBarTextures.
local function hidePRDManaCostPrediction(powerBar, hidden)
    if not powerBar then return end
    local manaCostBar = powerBar.ManaCostPredictionBar
    if not manaCostBar then return end

    local flagName = "_ScootPRDManaCostHidden"

    local function installAlphaHook(tex, flag)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flag .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flag) and alpha and alpha > 0 then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flag) and self.SetAlpha then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        setProp(manaCostBar, flagName, true)
        if manaCostBar.SetAlpha then pcall(manaCostBar.SetAlpha, manaCostBar, 0) end
        installAlphaHook(manaCostBar, flagName)
    else
        setProp(manaCostBar, flagName, false)
        if manaCostBar.SetAlpha then pcall(manaCostBar.SetAlpha, manaCostBar, 1) end
    end
end

-- Hide/restore PRD bar fill texture and background, using the same immediate
-- recursion-guard hook pattern as the Player UF SetPowerBarTextureOnlyHidden.
local function hidePRDBarTextures(bar, barType, hidden)
    if not bar or type(bar) ~= "table" then return end

    local fillTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local bgTex = bar.Background or bar.background

    local fillFlag = "_ScootPRDFillHidden_" .. barType
    local bgFlag = "_ScootPRDBGHidden_" .. barType

    local function installAlphaHook(tex, flagName)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flagName .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "_ScootPRDSettingAlpha") then
                        setProp(self, "_ScootPRDSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "_ScootPRDSettingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        if fillTex then
            setProp(fillTex, fillFlag, true)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 0) end
            installAlphaHook(fillTex, fillFlag)
        end
        if bgTex then
            setProp(bgTex, bgFlag, true)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 0) end
            installAlphaHook(bgTex, bgFlag)
        end
    else
        if fillTex then
            setProp(fillTex, fillFlag, false)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 1) end
        end
        if bgTex then
            setProp(bgTex, bgFlag, false)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 1) end
        end
    end
end

-- Helper to get the animated loss bar frame from PlayerFrame
local function getPRDAnimatedLossBar()
    return PlayerFrame
        and PlayerFrame.PlayerFrameContent
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
        and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
end

-- Hide/show the health loss animation (the dark red bar that appears when taking damage)
local function applyPRDHealthLossAnimationVisibility(component)
    local hideAnim = ensureSettingValue(component, "hideHealthLossAnimation") and true or false
    local animatedLossBar = getPRDAnimatedLossBar()

    if not animatedLossBar then return end

    if hideAnim then
        pcall(animatedLossBar.Hide, animatedLossBar)
        -- Install hook to keep it hidden (same pattern as hidePRDBarTextures)
        if not getProp(animatedLossBar, "_ScootHideLossAnimHooked") then
            setProp(animatedLossBar, "_ScootHideLossAnimHooked", true)
            pcall(function()
                hooksecurefunc(animatedLossBar, "Show", function(self)
                    if getProp(self, "_ScootHideLossAnim") then
                        pcall(self.Hide, self)
                    end
                end)
            end)
        end
        setProp(animatedLossBar, "_ScootHideLossAnim", true)
    else
        setProp(animatedLossBar, "_ScootHideLossAnim", false)
        -- Don't force Show - let Blizzard control visibility naturally
    end
end

local function applyPRDHealthVisuals(component, container)
    if not component or not container then
        return
    end
    local statusBar = container.healthBar or container.HealthBar
    if not statusBar then
        return
    end
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    if hide then
        pcall(container.SetAlpha, container, 0)
        pcall(statusBar.SetAlpha, statusBar, 0)
    else
        -- Apply state-based opacity instead of restoring to 1
        local alpha = getPRDOpacityForState("prdHealth")
        pcall(container.SetAlpha, container, alpha)
        pcall(statusBar.SetAlpha, statusBar, alpha)
    end
    if hide then
        clearBarBorder(statusBar)
        hidePRDBarOverlay("health")
        hideTextOverlay("health")
        return
    end
    local hideTextureOnly = ensureSettingValue(component, "hideTextureOnly") and true or false
    if hideTextureOnly then
        hidePRDBarTextures(statusBar, "health", true)
        hidePRDBarOverlay("health")
        clearBarBorder(statusBar)
        setBlizzardBorderVisible(statusBar, false)
        applyHealthTextOverlay(component)
        return
    end
    hidePRDBarTextures(statusBar, "health", false)
    applyPRDForegroundStyle(statusBar, "health", component)
    applyPRDBackgroundStyle(statusBar, "health", component)
    applyPRDBarBorder(component, statusBar)
    applyHealthTextOverlay(component)
    applyPRDHealthLossAnimationVisibility(component)
end

local function applyPRDPowerVisuals(component, frame)
    if not component or not frame then
        return
    end
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    if hide then
        pcall(frame.SetAlpha, frame, 0)
    else
        -- Apply state-based opacity instead of restoring to 1
        local alpha = getPRDOpacityForState("prdPower")
        pcall(frame.SetAlpha, frame, alpha)
    end
    if hide then
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        hidePRDManaCostPrediction(frame, true)
        hidePRDBarOverlay("power")
        hideTextOverlay("power")
        return
    end
    local hideTextureOnly = ensureSettingValue(component, "hideTextureOnly") and true or false
    if hideTextureOnly then
        hidePRDBarTextures(frame, "power", true)
        hidePRDManaCostPrediction(frame, true)
        hidePRDBarOverlay("power")
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        applyPowerTextOverlay(component)
        return
    end
    -- Apply mana cost prediction hiding based on setting (when bar is visible)
    local hideManaCost = component.db and component.db.hideManaCostPrediction
    hidePRDManaCostPrediction(frame, hideManaCost)
    hidePRDBarTextures(frame, "power", false)
    applyPRDForegroundStyle(frame, "power", component)
    applyPRDBackgroundStyle(frame, "power", component)
    applyPRDBarBorder(component, frame)
    applyPowerTextOverlay(component)
end

local function applyPRDClassResourceVisibility(component, frame)
    if not component or not frame then
        return
    end
    local hide = ensureSettingValue(component, "hideBar") and true or false
    setSettingValue(component, "hideBar", hide)
    if hide then
        pcall(frame.SetAlpha, frame, 0)
    else
        -- Apply state-based opacity instead of restoring to 1
        local alpha = getPRDOpacityForState("prdClassResource")
        pcall(frame.SetAlpha, frame, alpha)
    end
end

local function applyScaleToFrame(frame, multiplier, component)
    if not frame or type(multiplier) ~= "number" or multiplier <= 0 then
        return
    end
    if not frame.SetScale then
        return
    end

    if getProp(frame, "_ScootBaseScale") == nil then
        local base = 1
        if frame.GetScale then
            local ok, existing = pcall(frame.GetScale, frame)
            if ok and existing then
                base = existing
            end
        end
        setProp(frame, "_ScootBaseScale", base or 1)
    end

    local baseScale = getProp(frame, "_ScootBaseScale") or 1
    local desired = baseScale * multiplier

    local current
    if frame.GetScale then
        local ok, existing = pcall(frame.GetScale, frame)
        if ok and existing then
            current = existing
        end
    end
    if current and math.abs(current - desired) < 0.0001 then
        return
    end

    local ok = pcall(frame.SetScale, frame, desired)
    if not ok then
        queueAfterCombat(component)
    end
end

local function resolveClassResourceScale(component)
    if not component or not component.db then
        return 1
    end
    local value = tonumber(component.db.scale) or 100
    value = clampValue(math.floor(value + 0.5), MIN_CLASS_RESOURCE_SCALE_PERCENT, MAX_CLASS_RESOURCE_SCALE_PERCENT)
    component.db.scale = value
    return value / 100
end

-- (Assigns to forward-declared local)
getHealthContainer = function()
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

-- (Assigns to forward-declared local)
getPowerBar = function()
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

-- Hook to keep HealthBarsContainer hidden when hideBar is enabled.
-- This intercepts Blizzard's Show() calls (e.g., after closing Trading Post UI)
-- and re-hides the container if the user has "Hide Health Bar" enabled.
local healthContainerShowHookInstalled = false

local function ensureHealthContainerShowHook()
    if healthContainerShowHookInstalled then return end

    local container = getHealthContainer()
    if not container or not container.Show then return end

    healthContainerShowHookInstalled = true

    hooksecurefunc(container, "Show", function(self)
        -- Check if hideBar is enabled for prdHealth
        local component = addon.Components and addon.Components.prdHealth
        local hide = component and component.db and component.db.hideBar
        if hide then
            -- Defer to next frame to avoid re-entrancy issues
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if self and self.Hide then
                        pcall(self.Hide, self)
                    end
                end)
            end
        end
    end)
end

local function applyHealthOffsets(component)
    -- PRD is PersonalResourceDisplayFrame (parented to UIParent), not a nameplate.
    -- Positioning is handled by Edit Mode; this function applies sizing, styling, and visibility.
    if not isPRDEnabledByCVar() then
        -- PRD is disabled; clear any existing borders/overlays and bail out
        local container = getHealthContainer()
        if container then
            local statusBar = container.healthBar or container.HealthBar
            if statusBar then clearBarBorder(statusBar) end
            hidePRDBarOverlay("health")
            hideTextOverlay("health")
        end
        return
    end

    local container = getHealthContainer()
    if not container then
        return
    end

    -- Install hook to intercept Blizzard's Show() calls (e.g., after closing Trading Post)
    ensureHealthContainerShowHook()

    -- Hide bar via Hide()/Show() — frame is IsProtected: false
    local hide = ensureSettingValue(component, "hideBar") and true or false
    if hide then
        pcall(container.Hide, container)
        local statusBar = container.healthBar or container.HealthBar
        if statusBar then
            clearBarBorder(statusBar)
        end
        hidePRDBarOverlay("health")
        hideTextOverlay("health")
        return
    else
        pcall(container.Show, container)
    end

    -- Sizing: apply barWidth/barHeight
    local baseWidth = getProp(container, "_ScootBaseWidth")
    if not baseWidth or baseWidth <= 0 then
        local ok, w = pcall(container.GetWidth, container)
        baseWidth = (ok and w and w > 0) and w or 200
        setProp(container, "_ScootBaseWidth", baseWidth)
    end

    if component.settings and component.settings.barWidth then
        local defaultWidth = math.floor(baseWidth + 0.5)
        if component.settings.barWidth.default ~= defaultWidth then
            component.settings.barWidth.default = defaultWidth
        end
    end

    local storedWidth = component.db and component.db.barWidth
    if storedWidth then
        storedWidth = clampValue(math.floor(storedWidth + 0.5), MIN_HEALTH_BAR_WIDTH, MAX_HEALTH_BAR_WIDTH)
    end

    local baseHeight = getProp(container, "_ScootBaseHeight")
    if not baseHeight or baseHeight <= 0 then
        local ok, h = pcall(container.GetHeight, container)
        baseHeight = (ok and h and h > 0) and h or 12
        setProp(container, "_ScootBaseHeight", baseHeight)
    end

    if component.settings and component.settings.barHeight then
        local defaultHeight = math.floor(baseHeight + 0.5)
        if component.settings.barHeight.default ~= defaultHeight then
            component.settings.barHeight.default = defaultHeight
        end
    end

    local storedHeight = component.db and component.db.barHeight
    if storedHeight then
        storedHeight = clampValue(math.floor(storedHeight + 0.5), MIN_HEALTH_BAR_HEIGHT, MAX_HEALTH_BAR_HEIGHT)
    end

    local desiredWidth = storedWidth or baseWidth
    local desiredHeight = storedHeight or baseHeight

    -- Apply sizing
    if desiredWidth ~= baseWidth then
        pcall(container.SetWidth, container, desiredWidth)
    end
    if desiredHeight ~= baseHeight then
        pcall(container.SetHeight, container, desiredHeight)
    end

    local statusBar = container.healthBar or container.HealthBar
    if statusBar then
        pcall(statusBar.SetAllPoints, statusBar, container)
    end

    -- Apply visuals (styling, borders, text overlays)
    applyPRDHealthVisuals(component, container)
end

local function applyPowerOffsets(component)
    -- PRD power bar is PersonalResourceDisplayFrame.PowerBar (IsProtected: false).
    if not isPRDEnabledByCVar() then
        local frame = getPowerBar()
        if frame then
            clearBarBorder(frame)
            hidePRDBarOverlay("power")
            hideTextOverlay("power")
        end
        return
    end

    local frame = getPowerBar()
    if not frame then
        return
    end

    -- Hide bar via Hide()/Show()
    local hide = ensureSettingValue(component, "hideBar") and true or false
    if hide then
        pcall(frame.Hide, frame)
        pcall(frame.SetAlpha, frame, 0)  -- Alpha fallback: ensures bar stays hidden even if Blizzard shows it
    else
        pcall(frame.Show, frame)
    end

    -- Child frame features (operates on child frames: FullPowerFrame, FeedbackFrame)
    if Util then
        if Util.SetFullPowerSpikeHidden then
            local hideSpikes = (component.db and component.db.hideSpikeAnimations) or hide
            Util.SetFullPowerSpikeHidden(frame, hideSpikes)
        end
        if Util.SetPowerFeedbackHidden then
            local hideFeedback = (component.db and component.db.hidePowerFeedback) or hide
            Util.SetPowerFeedbackHidden(frame, hideFeedback)
        end
    end

    if hide then
        clearBarBorder(frame)
        setBlizzardBorderVisible(frame, false)
        hidePRDManaCostPrediction(frame, true)
        hidePRDBarOverlay("power")
        hideTextOverlay("power")
        return
    end

    -- Sizing: apply barHeight
    local baseHeight = getProp(frame, "_ScootBaseHeight")
    if not baseHeight or baseHeight <= 0 then
        local ok, h = pcall(frame.GetHeight, frame)
        baseHeight = (ok and h and h > 0) and h or 8
        setProp(frame, "_ScootBaseHeight", baseHeight)
    end

    if component.settings and component.settings.barHeight then
        local defaultHeight = math.floor(baseHeight + 0.5)
        if component.settings.barHeight.default ~= defaultHeight then
            component.settings.barHeight.default = defaultHeight
        end
    end

    local storedHeight = component.db and component.db.barHeight
    if storedHeight then
        storedHeight = clampValue(math.floor(storedHeight + 0.5), MIN_POWER_BAR_HEIGHT, MAX_POWER_BAR_HEIGHT)
        if storedHeight ~= baseHeight then
            pcall(frame.SetHeight, frame, storedHeight)
        end
    end

    -- Apply visuals (styling, text overlays)
    if frame.GetStatusBarTexture then
        applyPRDPowerVisuals(component, frame)
    end
end

local function applyClassResourceOffsets(component)
    -- Class resource is inside PersonalResourceDisplayFrame.ClassFrameContainer.
    -- Positioning is handled by Blizzard; this function applies scale and visibility.
    if not isPRDEnabledByCVar() then
        return
    end

    local prd = PersonalResourceDisplayFrame
    if not prd then
        return
    end
    local classContainer = prd.ClassFrameContainer
    if not classContainer then
        return
    end

    -- The class resource frame is a child of ClassFrameContainer (e.g., prdClassFrame)
    local frame
    if classContainer.GetChildren then
        frame = classContainer:GetChildren()
    end
    if not frame then
        return
    end
    if frame.IsForbidden and frame:IsForbidden() then
        return
    end

    local componentScale = resolveClassResourceScale(component)
    applyScaleToFrame(frame, componentScale, component)
    applyPRDClassResourceVisibility(component, frame)

    -- Apply DK rune texture overlay if available
    if addon.ApplyDKRuneTextures then
        addon.ApplyDKRuneTextures("prd")
    end

    -- Apply Mage arcane charge texture overlay if available
    if addon.ApplyMageArcaneChargeTextures then
        addon.ApplyMageArcaneChargeTextures("prd")
    end
end

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

addon:RegisterComponentInitializer(function(self)
    -- PRD Global component - settings placeholder for future use.
    -- PRD positioning is handled entirely via Edit Mode.
    -- The previous CVar-based "Minimize Vertical Movement" feature has been removed.
    local global = Component:New({
        id = "prdGlobal",
        name = "PRD — Global",
        frameName = nil,
        settings = {
            -- Reserved for future settings
        },
    })
    global.ApplyStyling = function(component)
        if not addon or not addon.Components then
            return
        end
        -- Trigger re-styling of child components
        local comps = addon.Components
        local function apply(target)
            if target and target.ApplyStyling then
                target:ApplyStyling()
            end
        end
        apply(comps.prdHealth)
        apply(comps.prdPower)
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
            barWidth = { type = "addon", default = nil, ui = {
                label = "Bar Width", widget = "slider", min = MIN_HEALTH_BAR_WIDTH, max = MAX_HEALTH_BAR_WIDTH, step = 1, section = "Sizing", order = 1, disableTextInput = true,
                tooltip = "Adjusts the health bar width."
            }},
            barHeight = { type = "addon", default = nil, ui = {
                label = "Bar Height", widget = "slider", min = MIN_HEALTH_BAR_HEIGHT, max = MAX_HEALTH_BAR_HEIGHT, step = 1, section = "Sizing", order = 2, disableTextInput = true,
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
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Health Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
            hideTextureOnly = { type = "addon", default = false, ui = {
                label = "Hide the Bar but not its Text", widget = "checkbox", section = "Misc", order = 2,
            }},
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
        applyHealthOffsets(comp)
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
            -- NOTE: Bar Width was removed because Blizzard's SetupClassNameplateBars() continuously
            -- re-applies dual anchors (TOPLEFT+TOPRIGHT) which override any custom width. This caused
            -- visible flickering during combat transitions. Width is now controlled by Health Bar width.
            barHeight = { type = "addon", default = nil, ui = {
                label = "Bar Height", widget = "slider", min = MIN_POWER_BAR_HEIGHT, max = MAX_POWER_BAR_HEIGHT, step = 1, section = "Sizing", order = 1, disableTextInput = true,
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
            hideBar = { type = "addon", default = false, ui = {
                label = "Hide Power Bar", widget = "checkbox", section = "Misc", order = 1,
            }},
            hideTextureOnly = { type = "addon", default = false, ui = {
                label = "Hide the Bar but not its Text", widget = "checkbox", section = "Misc", order = 2,
            }},
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
    power.ApplyStyling = function(comp)
        ensurePowerBarHooks(comp)
        applyPowerOffsets(comp)
    end
    ensureHooks(power)
    self:RegisterComponent(power)

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
            -- Opacity settings (addon-only, 1-100 percentage)
            opacityInCombat = { type = "addon", default = 100, ui = { hidden = true }},
            opacityWithTarget = { type = "addon", default = 100, ui = { hidden = true }},
            opacityOutOfCombat = { type = "addon", default = 100, ui = { hidden = true }},
        },
    })
    classRes.ApplyStyling = applyClassResourceOffsets
    ensureHooks(classRes)
    self:RegisterComponent(classRes)
end)

