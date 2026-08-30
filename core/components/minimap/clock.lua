--------------------------------------------------------------------------------
-- clock.lua - Minimap clock overlay, FPS and latency readout, timer management
--
-- Clock overlay, system data overlay (FPS/Latency), timer management.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MM = addon.Minimap

-- Import shared helpers as locals
local getMinimapDB = MM._getMinimapDB
local getClassColor = MM._getClassColor
local ensureOverlayTable = MM._ensureOverlayTable
local HideBlizzardClock = MM._HideBlizzardClock
local ShowBlizzardClock = MM._ShowBlizzardClock

-- Timer state
local clockTimer = nil
local systemDataTimer = nil

--------------------------------------------------------------------------------
-- Clock Overlay
--------------------------------------------------------------------------------

local function CreateClockOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.clock then
        return overlays.clock
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

    overlays.clock = frame
    addon.RegisterPetBattleFrame(frame)
    return frame
end

local function UpdateClockText()
    local db = getMinimapDB()
    if not db or db.clockHide then return end

    -- If position is "dock", the overlay is not updated (Blizzard handles it)
    local position = db.clockPosition or "dock"
    if position == "dock" then return end

    local overlays = ensureOverlayTable()
    if not overlays or not overlays.clock then return end

    local fontString = overlays.clock.fontString
    if not fontString then return end

    local hour, minute
    if db.clockTimeSource == "server" then
        hour, minute = GetGameTime()
    else
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    end

    local text
    if db.clockUse24Hour then
        text = string.format("%02d:%02d", hour, minute)
    else
        local suffix = hour >= 12 and "PM" or "AM"
        hour = hour % 12
        if hour == 0 then hour = 12 end
        text = string.format("%d:%02d %s", hour, minute, suffix)
    end

    fontString:SetText(text)

    -- Schedule next update
    if clockTimer then
        clockTimer:Cancel()
        clockTimer = nil
    end
    clockTimer = C_Timer.NewTimer(60, UpdateClockText)
end

-- Apply font/color settings to Blizzard's clock FontString
local function ApplyFontToBlizzardClock(db)
    if not db then return end

    -- Get the FontString: TimeManagerClockTicker is the text element
    local fontString = _G.TimeManagerClockTicker
    if not fontString and TimeManagerClockButton then
        fontString = TimeManagerClockButton.TimeManagerClockTicker
    end
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.clockFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.clockFontSize) or 12
    local fontStyle = db.clockFontStyle or "OUTLINE"

    addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if db.clockColorMode == "class" then
        r, g, b, a = getClassColor()
    elseif db.clockColorMode == "custom" and db.clockCustomColor then
        r = db.clockCustomColor[1] or 1
        g = db.clockCustomColor[2] or 1
        b = db.clockCustomColor[3] or 1
        a = db.clockCustomColor[4] or 1
    end

    pcall(function()
        fontString:SetTextColor(r, g, b, a)
    end)
end

local function ApplyClockStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Cancel existing timer
    if clockTimer then
        clockTimer:Cancel()
        clockTimer = nil
    end

    -- Hide the overlay if user chose to hide clock
    if not db or db.clockHide then
        if overlays.clock then
            overlays.clock:Hide()
        end
        -- When hiding, also hide Blizzard's if it's being managed
        if db then
            HideBlizzardClock()
        end
        return
    end

    local position = db.clockPosition or "dock"

    if position == "dock" then
        -- Show Blizzard's clock (unless dock is hidden)
        if not db.dockHide then
            ShowBlizzardClock()
        end
        -- Apply custom font/color settings to Blizzard's FontString
        ApplyFontToBlizzardClock(db)
        -- Hide the overlay
        if overlays.clock then
            overlays.clock:Hide()
        end
        return
    end

    -- Custom position: Hide Blizzard's clock, show the custom overlay
    HideBlizzardClock()

    local frame = overlays.clock or CreateClockOverlay()
    if not frame then return end

    local fontString = frame.fontString
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.clockFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.clockFontSize) or 12
    local fontStyle = db.clockFontStyle or "OUTLINE"

    addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if db.clockColorMode == "class" then
        r, g, b, a = getClassColor()
    elseif db.clockColorMode == "custom" and db.clockCustomColor then
        r = db.clockCustomColor[1] or 1
        g = db.clockCustomColor[2] or 1
        b = db.clockCustomColor[3] or 1
        a = db.clockCustomColor[4] or 1
    end
    fontString:SetTextColor(r, g, b, a)

    -- Position using the custom anchor
    local offsetX = tonumber(db.clockOffsetX) or 0
    local offsetY = tonumber(db.clockOffsetY) or 0

    frame:ClearAllPoints()
    frame:SetPoint(position, minimap, position, offsetX, offsetY)
    frame:SetWidth(minimap:GetWidth())

    frame:Show()

    -- Start clock updates
    UpdateClockText()
end

--------------------------------------------------------------------------------
-- System Data Overlay (FPS/Latency)
--------------------------------------------------------------------------------

local function CreateSystemDataOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end

    if overlays.systemData then
        return overlays.systemData
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

    overlays.systemData = frame
    addon.RegisterPetBattleFrame(frame)
    return frame
end

local function UpdateSystemDataText()
    local db = getMinimapDB()
    if not db then return end

    -- Check if anything is enabled to show
    local showFPS = db.systemDataShowFPS
    local showLatency = db.systemDataShowLatency
    if not showFPS and not showLatency then return end

    local overlays = ensureOverlayTable()
    if not overlays or not overlays.systemData then return end

    local fontString = overlays.systemData.fontString
    if not fontString then return end

    local parts = {}

    if showFPS then
        local fps = math.floor(GetFramerate())
        table.insert(parts, string.format("%d FPS", fps))
    end

    if showLatency then
        local _, _, latencyHome, latencyWorld = GetNetStats()
        local latency = db.systemDataLatencySource == "world" and latencyWorld or latencyHome
        table.insert(parts, string.format("%d MS", latency or 0))
    end

    local text = table.concat(parts, " | ")
    fontString:SetText(text)

    -- Schedule next update (every 2 seconds)
    if systemDataTimer then
        systemDataTimer:Cancel()
        systemDataTimer = nil
    end
    systemDataTimer = C_Timer.NewTimer(2, UpdateSystemDataText)
end

local function ApplySystemDataStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Cancel existing timer
    if systemDataTimer then
        systemDataTimer:Cancel()
        systemDataTimer = nil
    end

    -- Hide if neither FPS nor Latency is enabled
    local showFPS = db and db.systemDataShowFPS
    local showLatency = db and db.systemDataShowLatency

    if not db or (not showFPS and not showLatency) then
        if overlays.systemData then
            overlays.systemData:Hide()
        end
        return
    end

    local frame = overlays.systemData or CreateSystemDataOverlay()
    if not frame then return end

    local fontString = frame.fontString
    if not fontString then return end

    -- Apply font settings
    local fontFace = addon.ResolveFontFace and addon.ResolveFontFace(db.systemDataFont or "FRIZQT__")
        or (select(1, _G.GameFontNormal:GetFont()))
    local fontSize = tonumber(db.systemDataFontSize) or 11
    local fontStyle = db.systemDataFontStyle or "OUTLINE"

    addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)

    -- Apply color
    local r, g, b, a = 1, 1, 1, 1
    if db.systemDataColorMode == "class" then
        r, g, b, a = getClassColor()
    elseif db.systemDataColorMode == "custom" and db.systemDataCustomColor then
        r = db.systemDataCustomColor[1] or 1
        g = db.systemDataCustomColor[2] or 1
        b = db.systemDataCustomColor[3] or 1
        a = db.systemDataCustomColor[4] or 1
    end
    fontString:SetTextColor(r, g, b, a)

    -- Position
    local anchor = db.systemDataAnchor or "BOTTOM"
    local offsetX = tonumber(db.systemDataOffsetX) or 0
    local offsetY = tonumber(db.systemDataOffsetY) or -18

    frame:ClearAllPoints()
    frame:SetPoint(anchor, minimap, anchor, offsetX, offsetY)
    frame:SetWidth(minimap:GetWidth())

    frame:Show()

    -- Start updates
    UpdateSystemDataText()
end

-- Promote to namespace for core orchestrator and addon-loaded handler
MM._ApplyClockStyle = ApplyClockStyle
MM._ApplySystemDataStyle = ApplySystemDataStyle
