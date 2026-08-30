-- Tooltip.lua - Scoot-branded hover tooltip for Edit Mode selection frames
-- Replaces Blizzard's yellow-on-black GameTooltip for Scoot-owned frames only.
-- GameTooltip itself is never touched: the only code path that reaches it,
-- CheckShowInstructionalTooltip, is overridden per selection frame.
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}
addon.EditMode.Tooltip = {}
local Tooltip = addon.EditMode.Tooltip
local Brand = addon.EditMode.Brand

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BORDER_WIDTH = 2
local PAD          = 8
local ROW_GAP      = 3
local TITLE_SIZE   = 15

-- A literal third of 15px is 5px, which is illegible at any UI scale. 7px is the
-- practical floor for the brand row.
local BRAND_SIZE = math.max(7, math.floor(TITLE_SIZE / 3))
local ICON_GAP   = 3

-- Matches the Edit Mode dialog's title so the two branded surfaces agree.
-- Swap to "PROPORTIONAL_MED" for Roboto Medium.
local TITLE_FONT_KEY = "HEADER"

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local frame

local function GetTheme()
    return addon.UI and addon.UI.Theme
end

local function GetAccent()
    local theme = GetTheme()
    if theme and theme.GetAccentColor then return theme:GetAccentColor() end
    return 0.2, 0.9, 0.3, 1
end

local function GetTitleFont()
    local theme = GetTheme()
    if theme and theme.GetFont then return theme:GetFont(TITLE_FONT_KEY) end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetBrandFont()
    -- Same face as the title so the two rows read as one lockup.
    return GetTitleFont()
end

--------------------------------------------------------------------------------
-- Shared brand row (icon + "Scoot"), reused by the Edit Mode dialog
--------------------------------------------------------------------------------

--- Returns { icon, text, height }. Anchor the icon yourself.
function Tooltip.BuildBrandRow(parent, size)
    size = size or BRAND_SIZE
    local iconSize = size + 2

    local theme = GetTheme()
    local iconPath = (theme and theme.Textures and theme.Textures.SCOOT_ICON)
        or "Interface\\AddOns\\Scoot\\ScootIcon"

    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(iconPath)
    icon:SetSize(iconSize, iconSize)

    local text = parent:CreateFontString(nil, "OVERLAY")
    pcall(text.SetFont, text, GetBrandFont(), size, "")
    text:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
    text:SetText("Scoot")
    text:SetJustifyH("LEFT")

    local r, g, b = GetAccent()
    text:SetTextColor(r, g, b, 1)

    return { icon = icon, text = text, height = iconSize }
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

local function FollowCursor(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not scale or scale == 0 then return end
    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 12, (y / scale) + 12)
end

local function EnsureFrame()
    if frame then return frame end

    local theme = GetTheme()
    local bgR, bgG, bgB = 0.004, 0.004, 0.006
    if theme and theme.GetBackgroundSolidColor then
        bgR, bgG, bgB = theme:GetBackgroundSolidColor()
    end

    frame = CreateFrame("Frame", "ScootEditModeTooltip", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:Hide()

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
    bg:SetPoint("BOTTOMRIGHT", -BORDER_WIDTH, BORDER_WIDTH)
    bg:SetColorTexture(bgR, bgG, bgB, 0.98)
    frame._bg = bg

    frame._border = addon.UI.Controls.CreateBorder(frame, { thickness = BORDER_WIDTH })

    local brand = Tooltip.BuildBrandRow(frame, BRAND_SIZE)
    brand.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + BORDER_WIDTH, -(PAD + BORDER_WIDTH))
    frame._brand = brand

    local title = frame:CreateFontString(nil, "OVERLAY")
    pcall(title.SetFont, title, GetTitleFont(), TITLE_SIZE, "")
    title:SetPoint("TOPLEFT", brand.icon, "BOTTOMLEFT", 0, -ROW_GAP)
    title:SetJustifyH("LEFT")
    frame._title = title

    return frame
end

--------------------------------------------------------------------------------
-- Show / Hide
--------------------------------------------------------------------------------

local function SetContent(name)
    local f = EnsureFrame()
    local r, g, b = GetAccent()

    f._title:SetText(name or "")
    f._title:SetTextColor(r, g, b, 1)
    f._brand.text:SetTextColor(r, g, b, 1)

    local brandW = f._brand.icon:GetWidth() + ICON_GAP + f._brand.text:GetStringWidth()
    local titleW = f._title:GetStringWidth()
    local width  = math.max(brandW, titleW) + (PAD * 2) + (BORDER_WIDTH * 2)
    local height = f._brand.height + ROW_GAP + f._title:GetStringHeight()
        + (PAD * 2) + (BORDER_WIDTH * 2)

    f:SetSize(math.ceil(width), math.ceil(height))
end

function Tooltip.ShowFor(selection)
    if not selection then return end

    local name = Brand and Brand.GetSystemName and Brand:GetSystemName(selection) or ""
    SetContent(name)

    local f = EnsureFrame()
    FollowCursor(f)
    f:SetScript("OnUpdate", FollowCursor)
    f:Show()
end

function Tooltip.Hide()
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
end

--------------------------------------------------------------------------------
-- Attach to a selection frame
--------------------------------------------------------------------------------

--- Overrides the two tooltip methods rather than OnEnter/OnLeave, so
--- ShowEditInstructions (the MouseOverHighlight toggle) keeps working untouched
--- and GameTooltip is never contacted for this frame.
function Tooltip.Attach(selection)
    if not selection or selection._scootTooltipAttached then return end
    selection._scootTooltipAttached = true

    selection.CheckShowInstructionalTooltip = function(self)
        if not self:IsSelected() then
            Tooltip.ShowFor(self)
        else
            Tooltip.Hide()
        end
    end

    selection.HideInstructionalTooltip = function()
        Tooltip.Hide()
    end
end

local theme = addon.UI and addon.UI.Theme
if theme and theme.Subscribe then
    theme:Subscribe("ScootEditModeTooltip", function(r, g, b)
        if not frame then return end
        frame._title:SetTextColor(r, g, b, 1)
        frame._brand.text:SetTextColor(r, g, b, 1)
    end)
end
