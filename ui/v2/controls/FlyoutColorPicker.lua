-- FlyoutColorPicker.lua - Labeled swatch trigger opening a flyout of color rows
-- The trigger is a compact label-plus-swatch button. Clicking it opens a flyout,
-- built on first use, holding an optional source toggle, a color row, and an
-- optional reset button. The swatch shows the resolved color, which is not
-- always the color the row edits: a source toggle can override it.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local TRIGGER_SWATCH_WIDTH = 44
local TRIGGER_SWATCH_HEIGHT = 18
local TRIGGER_SWATCH_BORDER = 2
local TRIGGER_LABEL_GAP = 8
local TRIGGER_LABEL_SIZE = 12
local TRIGGER_BORDER_ALPHA = 0.8

local PANEL_WIDTH = 260
local PANEL_PADDING = 10
local PANEL_GAP = 6
local PANEL_DIRECTION = "DOWN"
local PANEL_BORDER_WIDTH = 1

local RESET_HEIGHT = 22
local RESET_FONT_SIZE = 11
local RESET_GAP = 10

--------------------------------------------------------------------------------
-- Controls:CreateFlyoutColorPicker(options)
--------------------------------------------------------------------------------
-- Options:
--   parent            : Frame   (required)
--   name              : string  optional global frame name
--   label             : string  trigger label (default "Color")
--   fontSize          : number  trigger label size (default 12)
--   swatchWidth       : number  (default 44)
--   swatchHeight      : number  (default 18)
--   labelGap          : number  label-to-swatch spacing (default 8)
--   get / set         : the color the flyout's color row edits
--   preview           : function -> r, g, b for the trigger swatch (default get)
--   colorLabel        : string  color row label (default "Custom Color")
--   colorDescription  : string  color row description
--   colorDisabled     : function -> boolean, greys the color row
--   toggleLabel       : string  builds a toggle row above the color row
--   toggleDescription : string
--   toggleGet / toggleSet : the toggle's binding
--   resetLabel        : string  reset button text (default "Reset")
--   onReset           : function, builds a reset button below the rows
--   direction / width / padding / gap : flyout geometry; the height is measured
--                                       from the rows the options build
--------------------------------------------------------------------------------

function Controls:CreateFlyoutColorPicker(options)
    local theme = GetTheme()
    if not options or not options.parent then
        return nil
    end

    local parent = options.parent
    local name = options.name
    local label = options.label or "Color"
    local fontSize = options.fontSize or TRIGGER_LABEL_SIZE
    local swatchWidth = options.swatchWidth or TRIGGER_SWATCH_WIDTH
    local swatchHeight = options.swatchHeight or TRIGGER_SWATCH_HEIGHT
    local labelGap = options.labelGap or TRIGGER_LABEL_GAP
    local panelWidth = options.width or PANEL_WIDTH
    local panelPadding = options.padding or PANEL_PADDING

    local getColor = options.get or function() return 1, 1, 1, 1 end
    local setColor = options.set or function() end
    local preview = options.preview or getColor

    ---------------------------------------------------------------------------
    -- Trigger
    ---------------------------------------------------------------------------

    local trigger = CreateFrame("Button", name, parent)
    trigger:SetHeight(math.max(swatchHeight + 4, fontSize + 6))
    trigger:EnableMouse(true)
    trigger:RegisterForClicks("AnyUp")

    local ar, ag, ab = theme:GetAccentColor()

    local labelFS = trigger:CreateFontString(nil, "OVERLAY")
    labelFS:SetFont(theme:GetFont("LABEL"), fontSize, "")
    labelFS:SetText(label)
    labelFS:SetTextColor(ar, ag, ab, 1)
    labelFS:SetPoint("LEFT", trigger, "LEFT", 0, 0)
    trigger._label = labelFS

    local swatch = CreateFrame("Frame", nil, trigger)
    swatch:SetSize(swatchWidth, swatchHeight)
    swatch:SetPoint("LEFT", labelFS, "RIGHT", labelGap, 0)
    trigger._swatch = swatch

    swatch._border = Controls.CreateBorder(swatch, {
        thickness = TRIGGER_SWATCH_BORDER,
        getAlpha = function() return trigger:IsMouseOver() and 1 or TRIGGER_BORDER_ALPHA end,
    })

    local colorFill = swatch:CreateTexture(nil, "ARTWORK", nil, 0)
    colorFill:SetPoint("TOPLEFT", TRIGGER_SWATCH_BORDER, -TRIGGER_SWATCH_BORDER)
    colorFill:SetPoint("BOTTOMRIGHT", -TRIGGER_SWATCH_BORDER, TRIGGER_SWATCH_BORDER)
    trigger._colorFill = colorFill

    local function UpdateTriggerColor()
        local r, g, b = preview()
        colorFill:SetColorTexture(r or 1, g or 1, b or 1, 1)
    end
    UpdateTriggerColor()

    -- The label width is 0 until the font file loads, so measure again next frame.
    local function MeasureWidth()
        trigger:SetWidth((labelFS:GetStringWidth() or 0) + labelGap + swatchWidth)
    end
    MeasureWidth()
    C_Timer.After(0, MeasureWidth)

    trigger:SetScript("OnEnter", function()
        swatch._border:Refresh()
    end)
    trigger:SetScript("OnLeave", function()
        swatch._border:Refresh()
    end)

    ---------------------------------------------------------------------------
    -- Flyout, built on first open
    ---------------------------------------------------------------------------

    local panel, toggleRow, colorRow, resetBtn

    local function Refresh()
        UpdateTriggerColor()
        if toggleRow then
            toggleRow:Refresh()
        end
        if colorRow then
            colorRow:Refresh()
            -- Refresh repaints only on a state change, and the color row's own
            -- theme subscription relights its label. Re-assert whichever state
            -- it is in so a greyed row stays grey.
            colorRow:SetDisabled(colorRow:IsDisabled())
        end
    end

    -- Returns the stacked height of the rows it builds.
    local function BuildContent(content)
        local y = 0

        if options.toggleLabel then
            toggleRow = Controls:CreateToggle({
                parent = content,
                label = options.toggleLabel,
                description = options.toggleDescription,
                get = options.toggleGet,
                set = function(value)
                    if options.toggleSet then
                        options.toggleSet(value)
                    end
                    Refresh()
                end,
            })
            if toggleRow then
                toggleRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                toggleRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
                y = y - toggleRow:GetHeight()
            end
        end

        colorRow = Controls:CreateColorPicker({
            parent = content,
            label = options.colorLabel or "Custom Color",
            description = options.colorDescription,
            hasAlpha = false,
            get = getColor,
            -- Fires on every drag frame in ColorPickerFrame, so it does the one
            -- cheap update rather than a full Refresh.
            set = function(r, g, b, a)
                setColor(r, g, b, a)
                UpdateTriggerColor()
            end,
            disabled = options.colorDisabled,
        })
        if colorRow then
            colorRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            colorRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            y = y - colorRow:GetHeight()
        end

        if options.onReset then
            resetBtn = Controls:CreateButton({
                parent = content,
                text = options.resetLabel or "Reset",
                height = RESET_HEIGHT,
                fontSize = RESET_FONT_SIZE,
                onClick = function()
                    options.onReset()
                    Refresh()
                end,
            })
            if resetBtn then
                resetBtn:SetPoint("TOP", content, "TOP", 0, y - RESET_GAP)
                y = y - RESET_GAP - resetBtn:GetHeight()
            end
        end

        return -y
    end

    local function EnsurePanel()
        if panel then return panel end
        if not Controls.CreateFlyout then return nil end

        panel = Controls:CreateFlyout({
            anchor = trigger,
            direction = options.direction or PANEL_DIRECTION,
            width = panelWidth,
            padding = panelPadding,
            gap = options.gap or PANEL_GAP,
            name = name and (name .. "Flyout") or nil,
        })
        if not panel then return nil end

        local contentHeight = BuildContent(panel:GetContent())
        panel:SetFlyoutSize(panelWidth, contentHeight + (panelPadding + PANEL_BORDER_WIDTH) * 2)
        return panel
    end

    trigger:SetScript("OnClick", function()
        local p = EnsurePanel()
        if not p then return end
        Refresh()
        p:Toggle()
    end)

    ---------------------------------------------------------------------------
    -- Theme
    ---------------------------------------------------------------------------

    local subscribeKey = "FlyoutColorPicker_" .. (name or tostring(trigger))
    trigger._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        labelFS:SetTextColor(r, g, b, 1)
        UpdateTriggerColor()
    end)

    ---------------------------------------------------------------------------
    -- Public methods
    ---------------------------------------------------------------------------

    function trigger:Refresh()
        Refresh()
    end

    function trigger:GetFlyout()
        return panel
    end

    function trigger:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
            self._subscribeKey = nil
        end
        if toggleRow and toggleRow.Cleanup then toggleRow:Cleanup() end
        if colorRow and colorRow.Cleanup then colorRow:Cleanup() end
        if resetBtn and resetBtn.Cleanup then resetBtn:Cleanup() end
        if panel then
            panel:Cleanup()
        end
    end

    return trigger
end
