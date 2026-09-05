--------------------------------------------------------------------------------
-- bars/snapshot.lua
-- Settings snapshot for the full unit-frame bar restyle. ApplyAllUnitFrameBarTextures
-- (bars.lua) skips its seven-unit dispatch when no bar-related DB value has changed
-- since the last full pass. Targeted per-unit calls via ApplyUnitFrameBarTexturesFor
-- and the deferred combat reapply bypass the guard.
--
-- MAINTENANCE: New bar DB keys MUST be added to BAR_CFG_KEYS / ALT_CFG_KEYS
-- or their changes will be silently ignored until profile switch / /reload.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.BarsSnapshot = addon.BarsSnapshot or {}
local Snapshot = addon.BarsSnapshot

local lastBarSnapshot

-- All cfg keys read by applyForUnit for visual output.
local BAR_CFG_KEYS = {
    -- health bar
    "useCustomBorders",
    "healthBarTexture", "healthBarColorMode", "healthBarTint",
    "healthBarBackgroundTexture", "healthBarBackgroundColorMode", "healthBarBackgroundTint", "healthBarBackgroundOpacity",
    "healthBarHideBorder", "healthBarHideTextureOnly",
    "healthBarHideOverAbsorbGlow", "healthBarHideHealPrediction", "healthBarHideHealthLossAnimation",
    "healthBarBorderStyle", "healthBarBorderTintEnable", "healthBarBorderTintColor",
    "healthBarBorderThickness", "healthBarBorderInset", "healthBarBorderInsetH", "healthBarBorderInsetV",
    -- power bar
    "powerBarTexture", "powerBarColorMode", "powerBarTint",
    "powerBarBackgroundTexture", "powerBarBackgroundColorMode", "powerBarBackgroundTint", "powerBarBackgroundOpacity",
    "powerBarHidden", "powerBarHideTextureOnly",
    "powerBarHideFullSpikes", "powerBarHideFeedback", "powerBarHideSpark", "powerBarHideManaCostPrediction",
    "powerBarBorderStyle", "powerBarBorderTintEnable", "powerBarBorderTintColor",
    "powerBarBorderThickness", "powerBarBorderInset", "powerBarBorderInsetH", "powerBarBorderInsetV",
    "powerBarWidthPct", "powerBarHeightPct", "powerBarOffsetX", "powerBarOffsetY",
    -- generic border (legacy)
    "borderStyle", "borderThickness", "borderInset", "borderInsetH", "borderInsetV", "borderTintEnable", "borderTintColor",
}

-- altPowerBar sub-table keys read by applyForUnit.
local ALT_CFG_KEYS = {
    "enabled", "hidden", "hideTextureOnly",
    "texture", "colorMode", "tint",
    "backgroundTexture", "backgroundColorMode", "backgroundTint", "backgroundOpacity",
    "hideFullSpikes", "hideFeedback", "hideSpark", "hideManaCostPrediction",
    "borderStyle", "borderTintEnable", "borderTintColor", "borderThickness",
    "borderInset", "borderInsetH", "borderInsetV",
    "percentHidden", "valueHidden",
    "textPercent", "textValue",
    "widthPct", "heightPct", "offsetX", "offsetY",
    "width", "height", "x", "y", "fontFace", "size", "style", "color", "alignment",
}

-- Frames.UNITS is frozen in this order; snapshot strings serialize by it.
local SNAPSHOT_UNITS = addon.Frames.UNITS
local SEP = "\1"
local NIL_SENTINEL = "\0"

local function appendValue(parts, v)
    local t = type(v)
    if t == "table" then
        -- Serialize table contents (color tables {r,g,b,a}, text config sub-tables)
        parts[#parts + 1] = "{"
        for k2, v2 in pairs(v) do
            parts[#parts + 1] = tostring(k2)
            parts[#parts + 1] = "="
            local t2 = type(v2)
            if t2 == "table" then
                -- One more level for nested sub-tables (e.g. textPercent.color)
                for k3, v3 in pairs(v2) do
                    parts[#parts + 1] = tostring(k3)
                    parts[#parts + 1] = ":"
                    parts[#parts + 1] = tostring(v3)
                end
            else
                parts[#parts + 1] = tostring(v2)
            end
        end
        parts[#parts + 1] = "}"
    elseif v == nil then
        parts[#parts + 1] = NIL_SENTINEL
    else
        parts[#parts + 1] = tostring(v)
    end
end

local function buildBarSettingsSnapshot()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames") or nil
    local parts = {}
    for u = 1, #SNAPSHOT_UNITS do
        local unit = SNAPSHOT_UNITS[u]
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        parts[#parts + 1] = unit
        if not cfg then
            parts[#parts + 1] = NIL_SENTINEL
        else
            for i = 1, #BAR_CFG_KEYS do
                appendValue(parts, cfg[BAR_CFG_KEYS[i]])
            end
            local altCfg = rawget(cfg, "altPowerBar")
            if altCfg then
                for i = 1, #ALT_CFG_KEYS do
                    appendValue(parts, altCfg[ALT_CFG_KEYS[i]])
                end
            else
                parts[#parts + 1] = NIL_SENTINEL
            end
        end
    end
    return table.concat(parts, SEP)
end

-- True when no bar setting has changed since the last call. Otherwise stores the
-- new snapshot and returns false, so the caller runs the full pass.
function Snapshot.Unchanged()
    local snapshot = buildBarSettingsSnapshot()
    if snapshot == lastBarSnapshot then return true end
    lastBarSnapshot = snapshot
    return false
end

return Snapshot
