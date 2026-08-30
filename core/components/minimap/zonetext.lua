--------------------------------------------------------------------------------
-- zonetext.lua - Minimap zone text overlay, PVP colors, and coordinates readout
--
-- Zone text overlay, PVP colors, coordinates overlay, zone event updates.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MM = addon.Minimap

-- Import shared helpers as locals
local getMinimapDB = MM._getMinimapDB
local ensureOverlayTable = MM._ensureOverlayTable
local PVP_COLORS = MM._PVP_COLORS
local HideBlizzardZoneText = MM._HideBlizzardZoneText
local ShowBlizzardZoneText = MM._ShowBlizzardZoneText

-- Timer state
local coordsTimer = nil

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
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.zoneTextFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.zoneTextFontSize) or 12
    local fontStyle = db.zoneTextFontStyle or "OUTLINE"

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
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.zoneTextFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
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

--------------------------------------------------------------------------------
-- Zone Coordinates
--------------------------------------------------------------------------------

local function CreateZoneCoordsDockOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.zoneCoordsDock then
        return overlays.zoneCoordsDock
    end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)
    frame:EnableMouse(false)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    frame.fontString = fontString

    overlays.zoneCoordsDock = frame
    addon.RegisterPetBattleFrame(frame)
    return frame
end

local function UpdateZoneCoordinates()
    local db = getMinimapDB()
    if not db or not db.zoneCoordinatesEnabled then return end

    local overlays = ensureOverlayTable()
    if not overlays then return end

    -- Find the active FontString for coordinates
    local fontString
    if overlays.zoneCoordsDock and overlays.zoneCoordsDock:IsShown() then
        fontString = overlays.zoneCoordsDock.fontString
    elseif overlays.zoneText and overlays.zoneText:IsShown() and overlays.zoneText.coordsFontString then
        fontString = overlays.zoneText.coordsFontString
    end

    if not fontString then return end

    -- Get player coordinates via safe public APIs
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not mapID then
        fontString:SetText("")
        return
    end

    local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok2 or not pos then
        fontString:SetText("")
        return
    end

    local x, y = pos:GetXY()
    if not x or not y or (x == 0 and y == 0) then
        fontString:SetText("")
        return
    end

    fontString:SetText(format("%.1f, %.1f", x * 100, y * 100))
end

local function ApplyZoneCoordinatesStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    -- Cancel existing timer
    if coordsTimer then
        coordsTimer:Cancel()
        coordsTimer = nil
    end

    -- Hide everything if disabled or zone text is hidden
    if not db or not db.zoneCoordinatesEnabled or db.zoneTextHide then
        if overlays.zoneCoordsDock then
            overlays.zoneCoordsDock:Hide()
        end
        if overlays.zoneText and overlays.zoneText.coordsFontString then
            overlays.zoneText.coordsFontString:Hide()
        end
        return
    end

    -- Resolve font settings (match zone text styling)
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.zoneTextFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.zoneTextFontSize) or 12
    local fontStyle = db.zoneTextFontStyle or "OUTLINE"

    local position = db.zoneTextPosition or "dock"

    if position == "dock" then
        -- Dock mode: use dedicated dock overlay anchored below MinimapZoneText
        if overlays.zoneText and overlays.zoneText.coordsFontString then
            overlays.zoneText.coordsFontString:Hide()
        end

        -- Also hide if dock itself is hidden
        if db.dockHide then
            if overlays.zoneCoordsDock then
                overlays.zoneCoordsDock:Hide()
            end
            return
        end

        local frame = overlays.zoneCoordsDock or CreateZoneCoordsDockOverlay()
        if not frame then return end

        local fontString = frame.fontString
        if not fontString then return end

        addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)
        UpdateZoneTextColor(fontString, db)

        local zoneTextFS = _G.MinimapZoneText
        if zoneTextFS then
            frame:ClearAllPoints()
            frame:SetPoint("TOP", zoneTextFS, "BOTTOM", 0, -2)
            frame:SetWidth(zoneTextFS:GetWidth() + 20)
        end

        frame:Show()
    else
        -- Custom overlay mode: add coordsFontString to existing zone text overlay
        if overlays.zoneCoordsDock then
            overlays.zoneCoordsDock:Hide()
        end

        local zoneFrame = overlays.zoneText
        if not zoneFrame then return end

        if not zoneFrame.coordsFontString then
            local fs = zoneFrame:CreateFontString(nil, "OVERLAY")
            fs:SetJustifyH("CENTER")
            zoneFrame.coordsFontString = fs
        end

        local fs = zoneFrame.coordsFontString
        addon.ApplyFontStyle(fs, fontFace, fontSize, fontStyle)
        UpdateZoneTextColor(fs, db)

        fs:ClearAllPoints()
        if zoneFrame.fontString then
            fs:SetPoint("TOP", zoneFrame.fontString, "BOTTOM", 0, -2)
        else
            fs:SetPoint("CENTER", zoneFrame, "CENTER", 0, 0)
        end

        fs:Show()
    end

    -- Start ticker (0.2s interval)
    UpdateZoneCoordinates()
    coordsTimer = C_Timer.NewTicker(0.2, UpdateZoneCoordinates)
end

-- Promote to namespace for core orchestrator and zone event handler
MM._ApplyZoneTextStyle = ApplyZoneTextStyle
MM._ApplyZoneCoordinatesStyle = ApplyZoneCoordinatesStyle
MM._UpdateZoneText = UpdateZoneText
MM._UpdateZoneCoordinates = UpdateZoneCoordinates
