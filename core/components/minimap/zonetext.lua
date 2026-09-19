--------------------------------------------------------------------------------
-- zonetext.lua - Minimap zone text overlay and PVP colors
--
-- Zone text overlay, PVP colors, zone event updates. The coordinates readout
-- is coordinates.lua.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MM = addon.Minimap

-- Import shared helpers as locals
local getMinimapDB = MM._getMinimapDB
local ensureOverlayTable = MM._ensureOverlayTable
local PVP_COLORS = MM._PVP_COLORS
local HideBlizzardZoneText = MM._HideBlizzardZoneText
local ShowBlizzardZoneText = MM._ShowBlizzardZoneText

--------------------------------------------------------------------------------
-- Zone Text Overlay
--------------------------------------------------------------------------------

local function CreateZoneTextOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.zoneText then
        return overlays.zoneText
    end

    local minimap = _G.Minimap

    -- Create frame parented to UIParent
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)
    frame:EnableMouse(false)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    frame.fontString = fontString

    overlays.zoneText = frame
    addon.RegisterPetBattleFrame(frame)
    return frame
end

local function UpdateZoneTextColor(fontString, db)
    if not fontString then return end

    local r, g, b, a = 1, 0.82, 0, 1  -- Default gold

    if db.zoneTextColorMode == "custom" and db.zoneTextCustomColor then
        r = db.zoneTextCustomColor[1] or 1
        g = db.zoneTextCustomColor[2] or 0.82
        b = db.zoneTextCustomColor[3] or 0
        a = db.zoneTextCustomColor[4] or 1
    else
        -- PVP type color
        local pvpType = C_PvP and C_PvP.GetZonePVPInfo() or GetZonePVPInfo()
        pvpType = pvpType or "normal"

        local color = PVP_COLORS[pvpType] or PVP_COLORS.normal
        r, g, b, a = color[1], color[2], color[3], color[4]
    end

    fontString:SetTextColor(r, g, b, a)
end

local function UpdateZoneText()
    local db = getMinimapDB()
    if not db then return end

    local overlays = ensureOverlayTable()
    if not overlays or not overlays.zoneText then return end

    local fontString = overlays.zoneText.fontString
    if not fontString then return end

    local text = GetMinimapZoneText() or ""
    fontString:SetText(text)
    UpdateZoneTextColor(fontString, db)
end

-- Apply font settings to Blizzard's zone text FontString
local function ApplyFontToBlizzardZoneText(db)
    if not db then return end

    -- Get the FontString: MinimapZoneText is the text element
    local fontString = _G.MinimapZoneText
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace(db.zoneTextFont)
    local fontSize = tonumber(db.zoneTextFontSize) or 12
    -- Deep Shadow draws a companion string on the parent frame, which here
    -- would be Blizzard's; the base style stands in.
    local fontStyle = addon.FontStyles.Unpaired(db.zoneTextFontStyle or "OUTLINE")

    addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)

    -- Apply color
    UpdateZoneTextColor(fontString, db)
end

local function ApplyZoneTextStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Hide the overlay if user chose to hide zone text
    if not db or db.zoneTextHide then
        if overlays.zoneText then
            overlays.zoneText:Hide()
        end
        -- When hiding, also hide Blizzard's if it's being managed
        if db then
            HideBlizzardZoneText()
        end
        return
    end

    local position = db.zoneTextPosition or "dock"

    if position == "dock" then
        -- Show Blizzard's zone text (unless dock is hidden)
        if not db.dockHide then
            ShowBlizzardZoneText()
        end
        -- Apply custom font/color settings to Blizzard's FontString
        ApplyFontToBlizzardZoneText(db)
        -- Hide the overlay
        if overlays.zoneText then
            overlays.zoneText:Hide()
        end
        return
    end

    -- Custom position: Hide Blizzard's zone text, show the custom overlay
    HideBlizzardZoneText()

    local frame = overlays.zoneText or CreateZoneTextOverlay()
    if not frame then return end

    local fontString = frame.fontString
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace(db.zoneTextFont)
    local fontSize = tonumber(db.zoneTextFontSize) or 12
    local fontStyle = db.zoneTextFontStyle or "OUTLINE"

    addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)

    -- Position using the custom anchor
    local offsetX = tonumber(db.zoneTextOffsetX) or 0
    local offsetY = tonumber(db.zoneTextOffsetY) or 0

    frame:ClearAllPoints()
    frame:SetPoint(position, minimap, position, offsetX, offsetY)
    frame:SetWidth(minimap:GetWidth() - 10)

    -- Update text and color
    local text = GetMinimapZoneText() or ""
    fontString:SetText(text)
    UpdateZoneTextColor(fontString, db)

    frame:Show()
end

-- Promote to namespace for core orchestrator and zone event handler
MM._ApplyZoneTextStyle = ApplyZoneTextStyle
MM._UpdateZoneText = UpdateZoneText
