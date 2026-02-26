--------------------------------------------------------------------------------
-- bars/utils.lua
-- Shared utility functions for unit frame bar styling
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Create module namespace
addon.BarsUtils = addon.BarsUtils or {}
local Utils = addon.BarsUtils

--------------------------------------------------------------------------------
-- UI Scale and Coordinate Utilities
--------------------------------------------------------------------------------

function Utils.getUiScale()
    if UIParent and UIParent.GetEffectiveScale then
        local scale = UIParent:GetEffectiveScale()
        if scale and scale > 0 then
            return scale
        end
    end
    return 1
end

function Utils.pixelsToUiUnits(px)
    return (tonumber(px) or 0) / Utils.getUiScale()
end

function Utils.uiUnitsToPixels(u)
    return math.floor(((tonumber(u) or 0) * Utils.getUiScale()) + 0.5)
end

function Utils.clampScreenCoordinate(value)
    local v = tonumber(value) or 0
    if v > 2000 then
        v = 2000
    elseif v < -2000 then
        v = -2000
    end
    return math.floor(v + (v >= 0 and 0.5 or -0.5))
end

function Utils.getFrameScreenOffsets(frame)
    if not (frame and frame.GetCenter and UIParent and UIParent.GetCenter) then
        return 0, 0
    end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and fy and px and py) then
        return 0, 0
    end
    return math.floor((fx - px) + 0.5), math.floor((fy - py) + 0.5)
end

--------------------------------------------------------------------------------
-- Frame Type Detection Utilities
--------------------------------------------------------------------------------

-- Check if a CompactUnitFrame is a raid frame (not nameplate/party)
-- Raid frames have names like "CompactRaidFrame1" or "CompactRaidGroup1Member1"
function Utils.isRaidFrame(frame)
    if not frame then return false end
    local ok, name = pcall(function() return frame:GetName() end)
    if not ok or not name then return false end
    if name:match("^CompactRaidFrame%d+$") then return true end
    if name:match("^CompactRaidGroup%d+Member%d+$") then return true end
    return false
end

-- Check if a CompactUnitFrame is a party frame
function Utils.isPartyFrame(frame)
    if not frame then return false end
    local ok, name = pcall(function() return frame:GetName() end)
    if not ok or not name then return false end
    return name:match("^CompactPartyFrameMember%d+$") ~= nil
end

-- Check if a frame is a CompactRaidGroup frame
function Utils.isCompactRaidGroupFrame(frame)
    if not frame then return false end
    local ok, name = pcall(function() return frame:GetName() end)
    if not ok or not name then return false end
    return name:match("^CompactRaidGroup%d+$") ~= nil
end

-- Check if a frame is the CompactPartyFrame
function Utils.isCompactPartyFrame(frame)
    if not frame then return false end
    local ok, name = pcall(function() return frame:GetName() end)
    if not ok or not name then return false end
    return name == "CompactPartyFrame"
end

--------------------------------------------------------------------------------
-- Configuration Detection Utilities
--------------------------------------------------------------------------------

-- Zero-Touch helper: check if table has any of the specified keys
function Utils.hasAnyKey(tbl, keys)
    if not tbl then return false end
    for i = 1, #keys do
        if tbl[keys[i]] ~= nil then return true end
    end
    return false
end

-- Check if text settings have any customization (used for Zero-Touch)
function Utils.hasCustomTextSettings(cfg)
    if not cfg then return false end
    if cfg.fontFace and cfg.fontFace ~= "FRIZQT__" then return true end
    if cfg.size and cfg.size ~= 12 then return true end
    if cfg.style and cfg.style ~= "OUTLINE" then return true end
    if cfg.colorMode and cfg.colorMode ~= "default" then return true end
    if cfg.color then
        local c = cfg.color
        if c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or c[4] ~= 1 then return true end
    end
    if cfg.anchor and cfg.anchor ~= "TOPLEFT" then return true end
    if cfg.offset then
        if (cfg.offset.x and cfg.offset.x ~= 0) or (cfg.offset.y and cfg.offset.y ~= 0) then return true end
    end
    if cfg.hideRealm then return true end
    return false
end

-- Check if bar styling has any customization (used for Zero-Touch)
function Utils.hasCustomBarSettings(cfg)
    if not cfg then return false end
    local hasCustom = (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
                      (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default") or
                      (cfg.healthBarBackgroundTexture and cfg.healthBarBackgroundTexture ~= "default") or
                      (cfg.healthBarBackgroundColorMode and cfg.healthBarBackgroundColorMode ~= "default")
    return hasCustom
end

-- Check if health bar overlay should be active
function Utils.hasCustomHealthBarOverlay(cfg)
    if not cfg then return false end
    return (cfg.healthBarTexture and cfg.healthBarTexture ~= "default") or
           (cfg.healthBarColorMode and cfg.healthBarColorMode ~= "default")
end

--------------------------------------------------------------------------------
-- Text Alignment Utilities
--------------------------------------------------------------------------------

-- Determine SetJustifyH based on anchor's horizontal component
function Utils.getJustifyHFromAnchor(anchor)
    if anchor == "TOPLEFT" or anchor == "LEFT" or anchor == "BOTTOMLEFT" then
        return "LEFT"
    elseif anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
        return "CENTER"
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        return "RIGHT"
    end
    return "LEFT" -- fallback
end

-- Reposition a LEFT-justified name overlay to achieve true CENTER/RIGHT alignment.
-- Uses actual text width (GetStringWidth) to compute the exact horizontal offset.
-- Long names that exceed the container gracefully degrade to left-aligned (start visible).
function Utils.repositionNameOverlay(overlay, container, anchor, offsetX, offsetY)
    if not overlay or not container then return end

    -- Convert 9-way anchor to LEFT-based vertical anchor for right-side truncation
    local vertAnchor
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        vertAnchor = "TOPLEFT"
    elseif anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT" then
        vertAnchor = "LEFT"
    else -- BOTTOMLEFT, BOTTOM, BOTTOMRIGHT
        vertAnchor = "BOTTOMLEFT"
    end

    -- Get container width (addon-owned frame; guarded as defense-in-depth)
    local containerWidth = 0
    if container.GetWidth then
        local ok, w = pcall(container.GetWidth, container)
        if ok and type(w) == "number" and not issecretvalue(w) then
            containerWidth = w
        end
    end

    -- Get actual rendered text width (addon-owned FontString)
    local textWidth = 0
    if overlay.GetStringWidth then
        local ok, tw = pcall(overlay.GetStringWidth, overlay)
        if ok and type(tw) == "number" and not issecretvalue(tw) then
            textWidth = tw
        end
    end

    -- Compute dynamic horizontal offset based on alignment intent
    local baseHOffset = 0
    if anchor == "TOP" or anchor == "CENTER" or anchor == "BOTTOM" then
        baseHOffset = math.max(0, (containerWidth - textWidth) / 2)
    elseif anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
        baseHOffset = math.max(0, containerWidth - textWidth)
    end

    overlay:ClearAllPoints()
    overlay:SetPoint(vertAnchor, container, vertAnchor, offsetX + baseHOffset, offsetY)
end

--------------------------------------------------------------------------------
-- Table/Object Utilities
--------------------------------------------------------------------------------

-- Safe nested table access
function Utils.getNested(root, ...)
    local cur = root
    for i = 1, select('#', ...) do
        local key = select(i, ...)
        if not cur or type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

-- Deep copy a value (table or primitive)
function Utils.deepcopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, vv in pairs(v) do out[k] = Utils.deepcopy(vv) end
    return out
end

--------------------------------------------------------------------------------
-- Role Icon Set Registry
--------------------------------------------------------------------------------

-- Ordered list for selector UI
Utils.ROLE_ICON_SETS = {
    { key = "default",     label = "Blizzard Default" },
    { key = "tiny",        label = "Compact" },
    { key = "groupfinder", label = "Group Finder" },
    { key = "gm",          label = "Raid Manager" },
    { key = "pixel",       label = "Pixel Icons" },
    { key = "pixel_white", label = "Pixel Icons (White)" },
}

-- Texture file mappings for custom TGA-based sets
local ROLE_ICON_PATH = "Interface\\AddOns\\Scoot\\media\\textures\\role-icons\\"

Utils.ROLE_ICON_TEXTURES = {
    pixel = {
        TANK    = ROLE_ICON_PATH .. "TankRoleIcon",
        HEALER  = ROLE_ICON_PATH .. "HealerRoleIcon",
        DAMAGER = ROLE_ICON_PATH .. "DPSRoleIcon",
    },
    pixel_white = {
        TANK    = ROLE_ICON_PATH .. "TankRoleIcon",
        HEALER  = ROLE_ICON_PATH .. "HealerRoleIcon",
        DAMAGER = ROLE_ICON_PATH .. "DPSRoleIcon",
        desaturated = true,
    },
}

-- Atlas mappings per set (keyed by role: TANK, HEALER, DAMAGER)
-- "default" is omitted — means "don't swap, use Blizzard's choice"
Utils.ROLE_ICON_ATLASES = {
    tiny = {
        TANK    = "roleicon-tiny-tank",
        HEALER  = "roleicon-tiny-healer",
        DAMAGER = "roleicon-tiny-dps",
    },
    groupfinder = {
        TANK    = "groupfinder-icon-role-micro-tank",
        HEALER  = "groupfinder-icon-role-micro-heal",
        DAMAGER = "groupfinder-icon-role-micro-dps",
    },
    gm = {
        TANK    = "GM-icon-role-tank",
        HEALER  = "GM-icon-role-healer",
        DAMAGER = "GM-icon-role-dps",
    },
}

--------------------------------------------------------------------------------
-- Background Color Default
--------------------------------------------------------------------------------

-- Get default background color for unit frame bars
function Utils.getDefaultBackgroundColor(unit, barKind)
    -- Based on Blizzard source: Player frame HealthBar.Background uses BLACK_FONT_COLOR (0, 0, 0)
    return 0, 0, 0, 1
end

return Utils
