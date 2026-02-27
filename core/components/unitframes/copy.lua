local addonName, addon = ...

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

local function getOffsetX(setting)
    if type(setting) ~= "table" then
        return nil
    end
    local offset = setting.offset
    if type(offset) ~= "table" then
        return nil
    end
    return offset.x
end

local function setOffsetX(setting, value)
    if type(setting) ~= "table" then
        return
    end
    local offset = setting.offset
    if type(offset) ~= "table" then
        if value == nil then
            return
        end
        offset = {}
        setting.offset = offset
    end
    offset.x = value
end

-- Helper to get font size from a text settings table
local function getFontSize(setting)
    if type(setting) ~= "table" then
        return nil
    end
    return setting.size
end

-- Helper to set font size on a text settings table
local function setFontSize(setting, value)
    if type(setting) ~= "table" then
        return
    end
    setting.size = value
end

local function canonicalUnit(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local lower = string.lower(unit)
    if lower == "player" then return "Player" end
    if lower == "target" then return "Target" end
    if lower == "focus"  then return "Focus"  end
    if lower == "pet"    then return "Pet"    end
    if lower == "targetoftarget" then return "TargetOfTarget" end
    if lower == "focustarget" then return "FocusTarget" end
end

local unitCaps = {
    Player = {
        orientation = "left",
        hasCastBar = true,
        supportsSpellNameText = true,
        supportsCastTimeText = true,
        supportsShowCastTime = true,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = true,
        supportsPortraitStatusTexture = true,
        supportsPortraitCornerIcon = true,
        supportsFullCircleMask = true,
        supportsDamageText = true,
        supportsIconPadding = true,
    },
    Target = {
        orientation = "right",
        hasCastBar = true,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = true,
    },
    Focus = {
        orientation = "right",
        hasCastBar = true,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = true,
    },
    Pet = {
        orientation = "left",
        hasCastBar = false,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = false,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = false,
    },
    -- ToT is destination-only for full unit frames (can only copy to/from FoT)
    TargetOfTarget = {
        orientation = "right",
        hasCastBar = false,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = false,
        -- ToT has limited settings: only bar style/border and name text
        isToT = true,
    },
    -- FoT has same capabilities as ToT (identical template)
    FocusTarget = {
        orientation = "right",
        hasCastBar = false,
        supportsSpellNameText = false,
        supportsCastTimeText = false,
        supportsShowCastTime = false,
        supportsPortraitOffset = true,
        supportsPortraitRestLoop = false,
        supportsPortraitStatusTexture = false,
        supportsPortraitCornerIcon = false,
        supportsFullCircleMask = false,
        supportsDamageText = false,
        supportsIconPadding = false,
        -- FoT has same limited settings as ToT
        isToT = true,
    },
}

local copyKeysRoot = {
    "scaleMult",
    "useCustomBorders",
    -- Health Bar
    "healthBarTexture",
    "healthBarColorMode",
    "healthBarTint",
    "healthBarBackgroundTexture",
    "healthBarBackgroundColorMode",
    "healthBarBackgroundTint",
    "healthBarBackgroundOpacity",
    "healthBarBorderStyle",
    "healthBarBorderTintEnable",
    "healthBarBorderTintColor",
    "healthBarBorderThickness",
    "healthBarBorderInset",
    "healthBarBorderInsetH",
    "healthBarBorderInsetV",
    "healthBarHideBorder",
    "healthBarHideTextureOnly",
    "healthBarHideOverAbsorbGlow",
    "healthBarHideHealPrediction",
    "healthPercentHidden",
    "healthValueHidden",
    "textHealthPercent",
    "textHealthValue",
    -- Power Bar
    "powerBarHidden",
    "powerBarOffsetX",
    "powerBarOffsetY",
    "powerBarWidthPct",
    "powerBarHeightPct",
    "powerBarTexture",
    "powerBarColorMode",
    "powerBarTint",
    "powerBarBackgroundTexture",
    "powerBarBackgroundColorMode",
    "powerBarBackgroundTint",
    "powerBarBackgroundOpacity",
    "powerBarBorderStyle",
    "powerBarBorderTintEnable",
    "powerBarBorderTintColor",
    "powerBarBorderThickness",
    "powerBarBorderInset",
    "powerBarBorderInsetH",
    "powerBarBorderInsetV",
    "powerBarHideTextureOnly",
    "powerBarHideFullSpikes",
    "powerBarHideFeedback",
    "powerBarHideSpark",
    "powerBarHideManaCostPrediction",
    "powerPercentHidden",
    "powerValueHidden",
    "textPowerPercent",
    "textPowerValue",
    -- Name Backdrop
    "nameBackdropEnabled",
    "nameBackdropTexture",
    "nameBackdropColorMode",
    "nameBackdropTint",
    "nameBackdropWidthPct",
    "nameBackdropOpacity",
    "nameBackdropBorderEnabled",
    "nameBackdropBorderStyle",
    "nameBackdropBorderTintEnable",
    "nameBackdropBorderTintColor",
    "nameBackdropBorderThickness",
    "nameBackdropBorderInset",
    "nameBackdropBorderInsetH",
    "nameBackdropBorderInsetV",
    -- Name/Level Text
    "nameTextHidden",
    "textName",
    "levelTextHidden",
    "textLevel",
    -- Visibility (opacity sliders)
    "opacity",
    "opacityInCombat",
    "opacityWithTarget",
    "opacityOutOfCombat",
    -- Misc
    "hideRoleIcon",
    "hideGroupNumber",
    "hidePvPIcons",
}

local preserveXOffsetKeys = {
    textHealthPercent = true,
    textHealthValue = true,
    textPowerPercent = true,
    textPowerValue = true,
    textName = true,
    textLevel = true,
}

-- Keys that have a .size field which should be preserved when copying to Pet
-- (Pet frame is smaller, so font sizes should remain independent)
local preserveSizeKeys = {
    textHealthPercent = true,
    textHealthValue = true,
    textPowerPercent = true,
    textPowerValue = true,
    textName = true,
    textLevel = true,
}

-- Cast Bar settings are intentionally excluded from Copy From functionality.
-- Each unit frame's cast bar must be configured independently.

-- Keys that ToT supports for copy (subset of full unit frames)
local totCopyKeysRoot = {
    -- Health Bar style/border only (no text)
    "healthBarTexture",
    "healthBarColorMode",
    "healthBarTint",
    "healthBarBackgroundTexture",
    "healthBarBackgroundColorMode",
    "healthBarBackgroundTint",
    "healthBarBackgroundOpacity",
    "healthBarBorderStyle",
    "healthBarBorderTintEnable",
    "healthBarBorderTintColor",
    "healthBarBorderThickness",
    "healthBarBorderInset",
    "healthBarBorderInsetH",
    "healthBarBorderInsetV",
    -- Power Bar style/border/visibility (no text)
    "powerBarHidden",
    "powerBarTexture",
    "powerBarColorMode",
    "powerBarTint",
    "powerBarBackgroundTexture",
    "powerBarBackgroundColorMode",
    "powerBarBackgroundTint",
    "powerBarBackgroundOpacity",
    "powerBarBorderStyle",
    "powerBarBorderTintEnable",
    "powerBarBorderTintColor",
    "powerBarBorderThickness",
    "powerBarBorderInset",
    "powerBarBorderInsetH",
    "powerBarBorderInsetV",
}

function addon.CopyUnitFrameSettings(sourceUnit, destUnit, opts)
    local src = canonicalUnit(sourceUnit)
    local dst = canonicalUnit(destUnit)
    if not src or not dst then
        return false, "invalid_unit"
    end
    if src == dst then
        return false, "same_unit"
    end

    local srcCap = unitCaps[src]
    local dstCap = unitCaps[dst]
    if not srcCap or not dstCap then
        return false, "invalid_unit"
    end

    -- ToT/FoT can only copy to each other, not to full unit frames
    if srcCap.isToT and not dstCap.isToT then
        return false, "invalid_unit"
    end

    local db = addon and addon.db and addon.db.profile
    if not db then
        return false, "db_unavailable"
    end
    db.unitFrames = db.unitFrames or {}

    local srcCfg = db.unitFrames[src] or {}
    local dstCfg = db.unitFrames[dst]
    if not dstCfg then
        dstCfg = {}
        db.unitFrames[dst] = dstCfg
    end

    -- Handle ToT destination specially (limited settings)
    if dstCap.isToT then
        -- Copy only bar style/border settings
        for _, key in ipairs(totCopyKeysRoot) do
            dstCfg[key] = deepCopy(srcCfg[key])
        end

        -- Copy Name Text settings (font, style, size, color, Y offset only)
        -- X offset is preserved per policy
        local srcTextName = type(srcCfg.textName) == "table" and srcCfg.textName or {}
        dstCfg.textName = dstCfg.textName or {}
        local dstTextName = dstCfg.textName
        local prevOffsetX = dstTextName.offset and dstTextName.offset.x or 0
        dstTextName.fontFace = deepCopy(srcTextName.fontFace)
        dstTextName.style = deepCopy(srcTextName.style)
        dstTextName.size = deepCopy(srcTextName.size)
        dstTextName.colorMode = deepCopy(srcTextName.colorMode)
        dstTextName.color = deepCopy(srcTextName.color)
        dstTextName.offset = dstTextName.offset or {}
        dstTextName.offset.y = srcTextName.offset and srcTextName.offset.y or 0
        dstTextName.offset.x = prevOffsetX

        -- Copy Portrait settings
        local srcPortrait = type(srcCfg.portrait) == "table" and srcCfg.portrait or {}
        dstCfg.portrait = dstCfg.portrait or {}
        local dstPortrait = dstCfg.portrait
        dstPortrait.scale = deepCopy(srcPortrait.scale)
        dstPortrait.zoom = deepCopy(srcPortrait.zoom)
        dstPortrait.hidePortrait = deepCopy(srcPortrait.hidePortrait)
        dstPortrait.opacity = deepCopy(srcPortrait.opacity)
        dstPortrait.portraitBorderEnable = deepCopy(srcPortrait.portraitBorderEnable)
        dstPortrait.portraitBorderStyle = deepCopy(srcPortrait.portraitBorderStyle)
        dstPortrait.portraitBorderThickness = deepCopy(srcPortrait.portraitBorderThickness)
        dstPortrait.portraitBorderColorMode = deepCopy(srcPortrait.portraitBorderColorMode)
        dstPortrait.portraitBorderTintColor = deepCopy(srcPortrait.portraitBorderTintColor)
        -- Preserve ToT-specific offsets (separate from source)
        -- dstPortrait.offsetX and dstPortrait.offsetY are NOT copied

        -- Apply styling (works for both ToT and FoT destinations)
        if addon.ApplyUnitFrameBarTexturesFor then
            addon.ApplyUnitFrameBarTexturesFor(dst)
        end
        if addon.ApplyUnitFramePortraitFor then
            addon.ApplyUnitFramePortraitFor(dst)
        end
        -- Apply name text based on destination
        if dst == "TargetOfTarget" and addon.ApplyToTNameText then
            addon.ApplyToTNameText()
        elseif dst == "FocusTarget" and addon.ApplyFoTNameText then
            addon.ApplyFoTNameText()
        end
        if addon.ApplyStyles then
            addon:ApplyStyles()
        end

        return true, nil
    end

    local skipFrameSize = opts and opts.skipFrameSize
    local frameSizeOk, frameSizeErr = true, nil
    if not skipFrameSize and addon.EditMode and addon.EditMode.CopyUnitFrameFrameSize then
        frameSizeOk, frameSizeErr = addon.EditMode.CopyUnitFrameFrameSize(src, dst)
    end

    local function copyRootKey(key)
        if key == "powerBarOffsetX" then
            return
        end
        local prevOffsetX = nil
        local prevSize = nil
        if preserveXOffsetKeys[key] then
            prevOffsetX = getOffsetX(dstCfg[key])
        end
        -- When copying to Pet, preserve font sizes (Pet frame is smaller)
        if dst == "Pet" and preserveSizeKeys[key] then
            prevSize = getFontSize(dstCfg[key])
        end
        dstCfg[key] = deepCopy(srcCfg[key])
        if preserveXOffsetKeys[key] then
            setOffsetX(dstCfg[key], prevOffsetX)
        end
        if dst == "Pet" and preserveSizeKeys[key] then
            setFontSize(dstCfg[key], prevSize)
        end
    end

    for _, key in ipairs(copyKeysRoot) do
        copyRootKey(key)
    end

    local srcPortrait = type(srcCfg.portrait) == "table" and srcCfg.portrait or {}
    dstCfg.portrait = dstCfg.portrait or {}
    local dstPortrait = dstCfg.portrait

    if dstCap.supportsPortraitOffset and srcCap.supportsPortraitOffset then
        dstPortrait.offsetY = deepCopy(srcPortrait.offsetY)
    elseif not dstCap.supportsPortraitOffset then
        dstPortrait.offsetX = nil
        dstPortrait.offsetY = nil
    end

    dstPortrait.hidePortrait = deepCopy(srcPortrait.hidePortrait)

    if dstCap.supportsPortraitRestLoop then
        if srcCap.supportsPortraitRestLoop then
            dstPortrait.hideRestLoop = deepCopy(srcPortrait.hideRestLoop)
        end
    else
        dstPortrait.hideRestLoop = nil
    end

    if dstCap.supportsPortraitStatusTexture then
        if srcCap.supportsPortraitStatusTexture then
            dstPortrait.hideStatusTexture = deepCopy(srcPortrait.hideStatusTexture)
        end
    else
        dstPortrait.hideStatusTexture = nil
    end

    if dstCap.supportsPortraitCornerIcon then
        if srcCap.supportsPortraitCornerIcon then
            dstPortrait.hideCornerIcon = deepCopy(srcPortrait.hideCornerIcon)
        end
    else
        dstPortrait.hideCornerIcon = nil
    end

    dstPortrait.scale = deepCopy(srcPortrait.scale)
    dstPortrait.opacity = deepCopy(srcPortrait.opacity)
    dstPortrait.zoom = deepCopy(srcPortrait.zoom)

    if dstCap.supportsFullCircleMask and srcCap.supportsFullCircleMask then
        dstPortrait.useFullCircleMask = deepCopy(srcPortrait.useFullCircleMask)
    elseif not dstCap.supportsFullCircleMask then
        dstPortrait.useFullCircleMask = nil
    end

    dstPortrait.portraitBorderEnable = deepCopy(srcPortrait.portraitBorderEnable)
    dstPortrait.portraitBorderStyle = deepCopy(srcPortrait.portraitBorderStyle)
    dstPortrait.portraitBorderThickness = deepCopy(srcPortrait.portraitBorderThickness)
    dstPortrait.portraitBorderColorMode = deepCopy(srcPortrait.portraitBorderColorMode)
    dstPortrait.portraitBorderTintColor = deepCopy(srcPortrait.portraitBorderTintColor)

    if dstCap.supportsDamageText and srcCap.supportsDamageText then
        local prevDamageOffsetX = getOffsetX(dstPortrait.damageText)
        dstPortrait.damageTextDisabled = deepCopy(srcPortrait.damageTextDisabled)
        dstPortrait.damageText = deepCopy(srcPortrait.damageText)
        setOffsetX(dstPortrait.damageText, prevDamageOffsetX)
    elseif not dstCap.supportsDamageText then
        dstPortrait.damageTextDisabled = nil
        dstPortrait.damageText = nil
    end

    -- Cast Bar settings are intentionally NOT copied between unit frames.
    -- Each unit frame's cast bar settings are independent and must be configured separately.
    -- Pet does not have a cast bar, so its castBar table is cleared when copying to Pet.
    if not dstCap.hasCastBar then
        dstCfg.castBar = nil
    end

    if addon.ApplyUnitFrameScaleMultFor then
        addon.ApplyUnitFrameScaleMultFor(dst)
    end
    if addon.ApplyUnitFrameBarTexturesFor then
        addon.ApplyUnitFrameBarTexturesFor(dst)
    end
    if addon.ApplyUnitFrameHealthTextVisibilityFor then
        addon.ApplyUnitFrameHealthTextVisibilityFor(dst)
    end
    if addon.ApplyUnitFramePowerTextVisibilityFor then
        addon.ApplyUnitFramePowerTextVisibilityFor(dst)
    end
    if addon.ApplyUnitFrameNameLevelTextFor then
        addon.ApplyUnitFrameNameLevelTextFor(dst)
    end
    if addon.ApplyUnitFramePortraitFor then
        addon.ApplyUnitFramePortraitFor(dst)
    end
    if dstCap.hasCastBar and addon.ApplyUnitFrameCastBarFor then
        addon.ApplyUnitFrameCastBarFor(dst)
    end
    if addon.ApplyStyles then
        addon:ApplyStyles()
    end

    return frameSizeOk, frameSizeErr
end

