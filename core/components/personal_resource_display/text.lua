--------------------------------------------------------------------------------
-- personal_resource_display/text.lua
-- Text overlay system: FontString creation, hook installation, text caching,
-- styling. Mirrors the PRD's own native bar text (12.0.7+) onto Scoot-owned
-- overlay FontStrings via hooks. Blizzard's native bar text is force-shown via
-- the Edit Mode "Show Bar Text" setting (so it populates in a clean context),
-- harvested, then hidden in favor of our styled overlay.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PRD

-- Import from core
local getHealthContainer = PRD._getHealthContainer
local getPowerBar = PRD._getPowerBar

--------------------------------------------------------------------------------
-- Text Overlay State
--------------------------------------------------------------------------------

-- Storage for text overlay state (one per bar type, not per bar instance)
local textOverlays = {
    health = { lastLeft = nil, lastRight = nil, overlay = nil, leftFS = nil, rightFS = nil },
    power = { lastLeft = nil, lastRight = nil, overlay = nil, leftFS = nil, rightFS = nil },
}

-- Promote for opacity.lua to access
PRD._textOverlays = textOverlays

-- Hook installation tracking
local textHooksInstalled = { power = false, health = false }

--------------------------------------------------------------------------------
-- Native Bar Text (Blizzard 12.0.7+)
--------------------------------------------------------------------------------
-- The PRD bars (PersonalResourceStatusBar) carry their own native value/percent
-- FontStrings: LeftText (percent), RightText (value), TextString (center).
-- We harvest those, render our own styled overlay on top, and keep the native
-- FontStrings hidden (alpha 0). The native text only populates while Blizzard's
-- Edit Mode "Show Bar Text" setting is on, which we drive Edit-Mode-first.

local NATIVE_TEXT_KEYS = { "LeftText", "RightText", "TextString" }

local function hideNativeBarTextOn(bar)
    if not bar then return end
    for _, key in ipairs(NATIVE_TEXT_KEYS) do
        local fs = bar[key]
        if fs then pcall(fs.SetAlpha, fs, 0) end
    end
end

-- Hide Blizzard's native PRD bar text across health, power, and alternate power
-- bars. (We only overlay health/power; the alt-power bar simply shows no text,
-- which matches pre-12.0.7 behavior.)
local function hidePRDNativeBarText()
    local prd = PersonalResourceDisplayFrame
    if not prd then return end
    local healthBar = prd.HealthBarsContainer and prd.HealthBarsContainer.healthBar
    hideNativeBarTextOn(healthBar)
    hideNativeBarTextOn(prd.PowerBar)
    hideNativeBarTextOn(prd.AlternatePowerBar)
end

-- Last ShowBarText state Scoot requested via Edit Mode.
-- nil = never requested (fresh/default profile — leave the layout untouched).
local nativeBarTextRequested = nil

-- True if the user has configured any PRD bar text (value or percent) on either bar.
local function anyPRDTextConfigured()
    local comps = addon.Components
    if not comps then return false end
    if comps.prdHealth and comps.prdHealth.db
        and (comps.prdHealth.db.valueTextShow or comps.prdHealth.db.percentTextShow) then
        return true
    end
    if comps.prdPower and comps.prdPower.db
        and (comps.prdPower.db.valueTextShow or comps.prdPower.db.percentTextShow) then
        return true
    end
    return false
end

-- Drive Blizzard's native "Show Bar Text" Edit Mode setting so the PRD's own bar
-- FontStrings get populated. Edit-Mode-first: never write the frame directly.
-- Zero-touch: we never disable a setting we never enabled, so default profiles
-- are left untouched.
local function setNativeBarTextEnabled(enabled)
    enabled = enabled and true or false
    if not enabled and nativeBarTextRequested ~= true then
        nativeBarTextRequested = false
        return
    end
    if nativeBarTextRequested ~= enabled then
        if addon.EditMode and addon.EditMode.WritePRDSetting then
            addon.EditMode.WritePRDSetting("show_bar_text", enabled and 1 or 0)
        end
        nativeBarTextRequested = enabled
    end
    -- Re-assert hidden native text whenever it should be on (idempotent).
    if enabled then hidePRDNativeBarText() end
end

PRD._setNativeBarTextEnabled = setNativeBarTextEnabled
PRD._anyPRDTextConfigured = anyPRDTextConfigured

--------------------------------------------------------------------------------
-- Font Resolution
--------------------------------------------------------------------------------

-- Resolve font path from font name or font key.
-- Delegates to addon.ResolveFontFace which handles internal keys, LSM keys, and fallback.
local function resolveFontPath(fontName)
    if not fontName or fontName == "" then
        return "Fonts\\FRIZQT__.TTF"
    end
    -- If it looks like a file path already, use it directly
    if fontName:match("\\") or fontName:match("/") then
        return fontName
    end
    return addon.ResolveFontFace(fontName)
end

--------------------------------------------------------------------------------
-- Overlay Creation
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Text Styling
--------------------------------------------------------------------------------

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

-- Check if text should be visible for the current Druid shapeshift form.
-- Returns true for non-Druids or when no per-form restrictions are set.
-- Storage is per-spec: valueTextDruidForms[specIndex][formID] = false to hide.
local function isDruidTextVisible(db, textType)
    local _, playerClass = UnitClass("player")
    if playerClass ~= "DRUID" then return true end

    local allSpecs = (textType == "value") and db.valueTextDruidForms or db.percentTextDruidForms
    if not allSpecs or not next(allSpecs) then return true end

    local specIndex = GetSpecialization and GetSpecialization() or 1
    local forms = allSpecs[specIndex]
    if not forms or not next(forms) then return true end

    local formID = GetShapeshiftFormID and GetShapeshiftFormID() or 0
    -- Normalize moonkin talent variant to base moonkin ID
    if formID == 35 then formID = 31 end
    -- Travel (3), Aquatic (4), Flight (27) share base form visibility setting
    if formID == 3 or formID == 4 or formID == 27 then formID = 0 end

    return forms[formID] ~= false
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
    elseif colorMode == "dkSpec" and overlayType == "power" then
        local dr, dg, db = addon.GetDKSpecColorRGB()
        return {dr or 1, dg or 1, db or 1, 1}
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
        local effectivePercentMode = addon.ReadColorMode(
            function() return db.percentTextColorMode end,
            function() return db.percentTextColorModeDK end
        )
        local color = resolveColorMode(effectivePercentMode, db.percentTextColor, overlayType)
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
        local effectiveValueMode = addon.ReadColorMode(
            function() return db.valueTextColorMode end,
            function() return db.valueTextColorModeDK end
        )
        local color = resolveColorMode(effectiveValueMode, db.valueTextColor, overlayType)
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

--------------------------------------------------------------------------------
-- Cached Text Application
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Hook Callbacks
--------------------------------------------------------------------------------

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
        if comp.db.percentTextShow and isDruidTextVisible(comp.db, "percent") then
            pcall(fs.Show, fs)
            pcall(fs.SetText, fs, text)
        else
            pcall(fs.Hide, fs)
        end
    else
        if comp.db.valueTextShow and isDruidTextVisible(comp.db, "value") then
            pcall(fs.Show, fs)
            pcall(fs.SetText, fs, text)
        else
            pcall(fs.Hide, fs)
        end
    end
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

-- Install hooks on a native PRD bar's own text FontStrings (LeftText = percent,
-- RightText = value). Blizzard populates these via SetText in its own clean
-- context; we mirror onto our overlay and keep the native FontStrings hidden.
local function installNativeBarTextHooks(overlayType, bar)
    if not bar then return false end

    local leftSource = bar.LeftText
    local rightSource = bar.RightText

    if leftSource then
        pcall(leftSource.SetAlpha, leftSource, 0)
        hooksecurefunc(leftSource, "SetText", function(self, text)
            pcall(self.SetAlpha, self, 0)
            onSourceTextChanged(overlayType, "left", text)
        end)
        if leftSource.SetFormattedText then
            hooksecurefunc(leftSource, "SetFormattedText", function(self, ...)
                pcall(self.SetAlpha, self, 0)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged(overlayType, "left", text) end
            end)
        end
        -- Capture initial value (may be secret value; SetText(secret) is allowed)
        local ok, text = pcall(leftSource.GetText, leftSource)
        if ok then
            textOverlays[overlayType].lastLeft = text
        end
    end

    if rightSource then
        pcall(rightSource.SetAlpha, rightSource, 0)
        hooksecurefunc(rightSource, "SetText", function(self, text)
            pcall(self.SetAlpha, self, 0)
            onSourceTextChanged(overlayType, "right", text)
        end)
        if rightSource.SetFormattedText then
            hooksecurefunc(rightSource, "SetFormattedText", function(self, ...)
                pcall(self.SetAlpha, self, 0)
                local ok, text = pcall(self.GetText, self)
                if ok then onSourceTextChanged(overlayType, "right", text) end
            end)
        end
        local ok, text = pcall(rightSource.GetText, rightSource)
        if ok then
            textOverlays[overlayType].lastRight = text
        end
    end

    return true
end

-- Install hooks on the PRD Power Bar's own native text (PowerBar.LeftText/.RightText)
local function installPowerTextHooks()
    if textHooksInstalled.power then return end

    local powerBar = PersonalResourceDisplayFrame and PersonalResourceDisplayFrame.PowerBar
    if not powerBar then return end

    if installNativeBarTextHooks("power", powerBar) then
        textHooksInstalled.power = true
    end
end

-- Install hooks on the PRD Health Bar's own native text (healthBar.LeftText/.RightText)
local function installHealthTextHooks()
    if textHooksInstalled.health then return end

    local healthBar = PersonalResourceDisplayFrame
        and PersonalResourceDisplayFrame.HealthBarsContainer
        and PersonalResourceDisplayFrame.HealthBarsContainer.healthBar
    if not healthBar then return end

    if installNativeBarTextHooks("health", healthBar) then
        textHooksInstalled.health = true
    end
end

--------------------------------------------------------------------------------
-- Entry Points
--------------------------------------------------------------------------------

-- Apply text overlay for power bar (called from power.ApplyStyling)
local function applyPowerTextOverlay(comp)
    if not comp or not comp.db then return end

    local db = comp.db

    -- Drive Blizzard's native bar text (PRD-wide) based on whether either bar
    -- wants text. This also re-hides the native FontStrings on all PRD bars.
    setNativeBarTextEnabled(anyPRDTextConfigured())

    local showValue = db.valueTextShow
    local showPercent = db.percentTextShow

    -- Druid per-form override: hide text in specific shapeshift forms
    if showValue then showValue = isDruidTextVisible(db, "value") end
    if showPercent then showPercent = isDruidTextVisible(db, "percent") end

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

    -- Drive Blizzard's native bar text (PRD-wide) based on whether either bar
    -- wants text. This also re-hides the native FontStrings on all PRD bars.
    setNativeBarTextEnabled(anyPRDTextConfigured())

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
-- Namespace Promotions
--------------------------------------------------------------------------------

PRD._applyHealthTextOverlay = applyHealthTextOverlay
PRD._applyPowerTextOverlay = applyPowerTextOverlay
PRD._hideTextOverlay = hideTextOverlay
