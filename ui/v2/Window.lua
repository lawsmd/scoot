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
local NOISE_ALPHA = 0.25       -- Subtle noise blending

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
    frame._bg = addon.UI.Controls.AddBackground(frame, { color = "window" })
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
    frame._border = addon.UI.Controls.CreateBorder(frame, {
        thickness = Theme.BORDER_WIDTH or 3,
        corners = "outset",
    })
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Window:Destroy(frame)
    if not frame then return end

    if frame._border and frame._border.Destroy then
        frame._border:Destroy()
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
