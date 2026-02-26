-- Window.lua - Base window component with glow border and frosted glass effect
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Window = {}
local Window = addon.UI.Window
local Theme = addon.UI.Theme

--------------------------------------------------------------------------------
-- Noise Overlay Constants
--------------------------------------------------------------------------------

local NOISE_TEXTURE_PATH = "Interface\\AddOns\\Scoot\\media\\textures\\frosted-noise"
local NOISE_TEXTURE_SIZE = 2048  -- Matches the 2048x2048 frosted-noise.tga
local NOISE_ALPHA = 0.25       -- Very subtle (0.05-0.15 range)

--------------------------------------------------------------------------------
-- Window Factory
--------------------------------------------------------------------------------

-- Create a UI-styled window with glow border and frosted glass background
-- @param name: Global frame name
-- @param parent: Parent frame (default UIParent)
-- @param width: Window width (default 900)
-- @param height: Window height (default 650)
-- @return: The created frame
function Window:Create(name, parent, width, height)
    local frame = CreateFrame("Frame", name, parent or UIParent)
    frame:SetSize(width or 900, height or 650)
    -- Use DIALOG strata to match old SettingsPanel - HIGH strata + SetToplevel
    -- can cause Blizzard's ShowUIPanel to hide the frame unexpectedly
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Store dimensions for reference
    frame._defaultWidth = width or 900
    frame._defaultHeight = height or 650

    -- Build window layers
    self:CreateBackground(frame)
    self:CreateNoiseOverlay(frame)  -- Frosted glass effect
    -- self:CreateGlowBorder(frame)  -- Disabled: needs gradient texture for real glow
    self:CreateSolidBorder(frame)

    -- Subscribe to accent color changes
    local subscribeKey = name .. "_UIWindow"
    Theme:Subscribe(subscribeKey, function(r, g, b, a)
        self:UpdateBorderColors(frame, r, g, b)
    end)

    -- Store subscription key for cleanup
    frame._themeSubscribeKey = subscribeKey

    -- NOTE: Dragging is NOT registered on the main frame.
    -- The SettingsPanel creates a title bar that handles dragging instead,
    -- so users can only drag the window by the title bar area (not the entire window).
    -- Position saving is handled by the title bar's OnDragStop in SettingsPanel.lua.

    -- Mark as UI window
    frame._isSettingsWindow = true

    return frame
end

--------------------------------------------------------------------------------
-- Background Layer (semi-transparent dark)
--------------------------------------------------------------------------------

function Window:CreateBackground(frame)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    local r, g, b, a = Theme:GetBackgroundColor()
    bg:SetColorTexture(r, g, b, a)
    frame._bg = bg
end

--------------------------------------------------------------------------------
-- Noise Overlay (frosted glass effect)
--------------------------------------------------------------------------------

function Window:CreateNoiseOverlay(frame)
    local noise = frame:CreateTexture(nil, "BACKGROUND", nil, -7)  -- Above bg (-8)
    noise:SetAllPoints()
    noise:SetTexture(NOISE_TEXTURE_PATH)
    noise:SetAlpha(NOISE_ALPHA)
    noise:SetBlendMode("ADD")

    -- Manual tex-coord tiling (bypasses unreliable SetHorizTile/SetVertTile)
    local function UpdateNoiseCoords()
        local width, height = frame:GetSize()
        if width and height and width > 0 and height > 0 then
            noise:SetTexCoord(0, width / NOISE_TEXTURE_SIZE, 0, height / NOISE_TEXTURE_SIZE)
        end
    end

    -- Update on resize
    frame:HookScript("OnSizeChanged", UpdateNoiseCoords)

    -- Initial update
    UpdateNoiseCoords()

    frame._noise = noise
    return noise
end

--------------------------------------------------------------------------------
-- Solid Border (clean square border with proper corners)
--------------------------------------------------------------------------------

function Window:CreateSolidBorder(frame)
    local ar, ag, ab = Theme:GetBorderColor()
    local borderWidth = Theme.BORDER_WIDTH or 3
    local border = {}

    -- TOP edge (extends full width including corners)
    local top = frame:CreateTexture(nil, "BORDER", nil, -1)
    top:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -borderWidth, 0)
    top:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", borderWidth, 0)
    top:SetHeight(borderWidth)
    top:SetColorTexture(ar, ag, ab, 1)
    border.TOP = top

    -- BOTTOM edge (extends full width including corners)
    local bottom = frame:CreateTexture(nil, "BORDER", nil, -1)
    bottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -borderWidth, 0)
    bottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", borderWidth, 0)
    bottom:SetHeight(borderWidth)
    bottom:SetColorTexture(ar, ag, ab, 1)
    border.BOTTOM = bottom

    -- LEFT edge (between top and bottom borders)
    local left = frame:CreateTexture(nil, "BORDER", nil, -1)
    left:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(borderWidth)
    left:SetColorTexture(ar, ag, ab, 1)
    border.LEFT = left

    -- RIGHT edge (between top and bottom borders)
    local right = frame:CreateTexture(nil, "BORDER", nil, -1)
    right:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(borderWidth)
    right:SetColorTexture(ar, ag, ab, 1)
    border.RIGHT = right

    frame._border = border
end

--------------------------------------------------------------------------------
-- Color Update (called by theme subscriber)
--------------------------------------------------------------------------------

function Window:UpdateBorderColors(frame, r, g, b)
    if not frame then return end

    -- Update solid border
    if frame._border then
        for _, tex in pairs(frame._border) do
            if tex and tex.SetColorTexture then
                tex:SetColorTexture(r, g, b, 1)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Window:Destroy(frame)
    if not frame then return end

    -- Unsubscribe from theme
    if frame._themeSubscribeKey then
        Theme:Unsubscribe(frame._themeSubscribeKey)
    end

    -- Hide and clear
    frame:Hide()
    frame:SetParent(nil)
end

--------------------------------------------------------------------------------
-- Position Restoration
--------------------------------------------------------------------------------

function Window:RestorePosition(frame)
    if not frame or not addon.db or not addon.db.global then return end

    local pos = addon.db.global.windowPosition
    if pos and pos.point and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        -- Default to center
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
