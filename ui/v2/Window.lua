-- Window.lua - the settings window's frame: background, chrome and border,
-- drawn the way the active skin's window role says.
--
-- The window role (addon.UI.Chrome, Spec("window")) is flat or nineSlice.
-- Flat is the panel's own look: a background fill, a noise layer over it,
-- and a solid border windowBorderWidth wide. nineSlice puts Blizzard's
-- nine-slice pieces on a child frame instead, and the content inset the
-- panes anchor from is the skin's windowInset metric either way.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Window = {}
local Window = addon.UI.Window
local Theme = addon.UI.Theme

local function Metrics()
    return addon.UI.Controls.Metrics()
end

--------------------------------------------------------------------------------
-- Window Factory
--------------------------------------------------------------------------------

-- Create the settings window frame
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

    local spec = addon.UI.Chrome.Spec("window")
    frame._chromeSpec = spec

    self:CreateBackground(frame, spec)
    if spec.kind == "nineSlice" then
        frame._chrome = addon.UI.Chrome.NineSlice(frame, spec)
    else
        if spec.noise then
            self:CreateNoiseOverlay(frame, spec.noise)
        end
        self:CreateSolidBorder(frame, spec)
    end

    -- The inset every pane anchors from: the flat border's width, or the
    -- distance a nine-slice frame's art reaches into the rect.
    function frame:GetContentInset()
        local m = Metrics()
        return (m and m.windowInset) or Theme.BORDER_WIDTH or 3
    end

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

function Window:CreateBackground(frame, spec)
    frame._bg = addon.UI.Controls.AddBackground(frame, {
        color = (spec and spec.background) or "window",
        inset = (spec and spec.backgroundInset) or 0,
    })
end

--------------------------------------------------------------------------------
-- Noise Overlay (frosted glass effect)
--------------------------------------------------------------------------------

-- noise = { texture = <Theme.Textures key>, size = <texture side in px>,
--           alpha, blend }, from the window descriptor.
function Window:CreateNoiseOverlay(frame, noiseSpec)
    local path = Theme.Textures and Theme.Textures[noiseSpec.texture or "NOISE_OVERLAY"]
    if not path then return nil end
    local textureSize = noiseSpec.size or 2048

    local noise = frame:CreateTexture(nil, "BACKGROUND", nil, -7)  -- Above bg (-8)
    noise:SetAllPoints()
    noise:SetTexture(path)
    noise:SetAlpha(noiseSpec.alpha or 0.25)
    noise:SetBlendMode(noiseSpec.blend or "ADD")

    -- Manual tex-coord tiling (bypasses unreliable SetHorizTile/SetVertTile)
    local function UpdateNoiseCoords()
        local width, height = frame:GetSize()
        if width and height and width > 0 and height > 0 then
            noise:SetTexCoord(0, width / textureSize, 0, height / textureSize)
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

function Window:CreateSolidBorder(frame, spec)
    local m = Metrics()
    frame._border = addon.UI.Controls.CreateBorder(frame, {
        thickness = (m and m.windowBorderWidth) or Theme.BORDER_WIDTH or 3,
        corners = (spec and spec.corners) or "outset",
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
    if frame._chrome and frame._chrome.Destroy then
        frame._chrome:Destroy()
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
