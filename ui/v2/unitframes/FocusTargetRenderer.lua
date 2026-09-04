-- FocusTargetRenderer.lua - Target of Focus TUI renderer
-- FocusTarget is not in Edit Mode, so has addon-controlled positioning and scale
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames
local SettingsBuilder = addon.UI.SettingsBuilder

local COMPONENT_ID = "ufFocusTarget"
local UNIT_KEY = "FocusTarget"

--------------------------------------------------------------------------------
-- Bound Helpers
--------------------------------------------------------------------------------

local B = UF.BindUnit(UNIT_KEY)

--------------------------------------------------------------------------------
-- Apply Functions
--------------------------------------------------------------------------------

local function applyPosition()
    if addon.ApplyFocusTargetPosition then
        addon.ApplyFocusTargetPosition()
    end
end

local function applyScale()
    if addon.ApplyFocusTargetScale then
        addon.ApplyFocusTargetScale()
    end
end

local function applyCustomBorders()
    if addon.ApplyFocusTargetCustomBorders then
        addon.ApplyFocusTargetCustomBorders()
    end
    B.applyBarTextures()
end

local function applyPowerVisibility()
    if addon.ApplyFocusTargetPowerBarVisibility then
        addon.ApplyFocusTargetPowerBarVisibility()
    end
end

local function applyPortrait()
    B.applyPortrait()
    B.applyStyles()
end

local function applyNameText()
    if addon.ApplyFoTNameText then
        addon.ApplyFoTNameText()
    end
    B.applyStyles()
end

--------------------------------------------------------------------------------
-- Shared Tab Builders
--------------------------------------------------------------------------------

local function buildStyleTab(inner, barPrefix, applyFn, colorValues, colorOrder, colorInfoIcons)
    local get, set = B.barAccessors(barPrefix)
    inner:AddBarStyleBlock({
        get = get, set = set, apply = applyFn,
        foreground = { values = colorValues, order = colorOrder, infoIcons = colorInfoIcons },
    })
    inner:Finalize()
end

local function buildBorderTab(inner, barPrefix, applyFn)
    local get, set = B.barAccessors(barPrefix)
    inner:AddBarBorderBlock({ get = get, set = set, apply = applyFn })
    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Portrait Tab Builders
--------------------------------------------------------------------------------

local function buildPortraitPositioningTab(inner)
    inner:AddDualSlider({
        label = "Offset",
        sliderA = {
            axisLabel = "X",
            min = -100, max = 100, step = 1,
            get = function() local t = B.getPortraitDB() or {}; return tonumber(t.offsetX) or 0 end,
            set = function(v) local t = B.ensurePortraitDB(); if t then t.offsetX = tonumber(v) or 0; applyPortrait() end end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -100, max = 100, step = 1,
            get = function() local t = B.getPortraitDB() or {}; return tonumber(t.offsetY) or 0 end,
            set = function(v) local t = B.ensurePortraitDB(); if t then t.offsetY = tonumber(v) or 0; applyPortrait() end end,
        },
    })

    inner:Finalize()
end

local function buildPortraitSizingTab(inner)
    inner:AddSlider({
        label = "Portrait Size (Scale)",
        min = 50, max = 200, step = 1,
        get = function() local t = B.getPortraitDB() or {}; return tonumber(t.scale) or 100 end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.scale = tonumber(v) or 100; applyPortrait() end end,
        minLabel = "50%", maxLabel = "200%",
    })

    inner:Finalize()
end

local function buildPortraitMaskTab(inner)
    inner:AddSlider({
        label = "Portrait Zoom",
        min = 100, max = 200, step = 1,
        get = function() local t = B.getPortraitDB() or {}; return tonumber(t.zoom) or 100 end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.zoom = tonumber(v) or 100; applyPortrait() end end,
        minLabel = "100%", maxLabel = "200%",
    })

    inner:Finalize()
end

local function buildPortraitBorderTab(inner)
    inner:AddToggle({
        label = "Use Custom Border",
        get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderEnable == true end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderEnable = (v == true); applyPortrait() end end,
    })

    inner:AddSelector({
        label = "Border Style",
        values = UF.portraitBorderValues, order = UF.portraitBorderOrder,
        get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderStyle or "texture_c" end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderStyle = v or "texture_c"; applyPortrait() end end,
    })

    inner:AddSlider({
        label = "Border Inset",
        min = 1, max = 8, step = 0.5, precision = 1,
        get = function() local t = B.getPortraitDB() or {}; local v = tonumber(t.portraitBorderThickness) or 1; return math.max(1, math.min(8, math.floor(v * 2 + 0.5) / 2)) end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderThickness = math.max(1, math.min(8, math.floor((tonumber(v) or 1) * 2 + 0.5) / 2)); applyPortrait() end end,
    })

    inner:AddSelectorColorPicker({
        label = "Border Color",
        values = UF.portraitBorderColorValues, order = UF.portraitBorderColorOrder,
        get = function() local t = B.getPortraitDB() or {}; return t.portraitBorderColorMode or "texture" end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.portraitBorderColorMode = v or "texture"; applyPortrait() end end,
        getColor = function() local t = B.getPortraitDB() or {}; local c = t.portraitBorderTintColor or {1,1,1,1}; return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end,
        setColor = function(r,g,b,a) local t = B.ensurePortraitDB(); if t then t.portraitBorderTintColor = {r or 1, g or 1, b or 1, a or 1}; applyPortrait() end end,
        customValue = "custom", hasAlpha = true,
    })

    inner:Finalize()
end

local function buildPortraitVisibilityTab(inner)
    inner:AddToggle({
        label = "Hide Portrait",
        get = function() local t = B.getPortraitDB() or {}; return t.hidePortrait == true end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.hidePortrait = (v == true); applyPortrait() end end,
    })

    inner:AddSlider({
        label = "Portrait Opacity",
        min = 1, max = 100, step = 1,
        get = function() local t = B.getPortraitDB() or {}; return tonumber(t.opacity) or 100 end,
        set = function(v) local t = B.ensurePortraitDB(); if t then t.opacity = tonumber(v) or 100; applyPortrait() end end,
        minLabel = "1%", maxLabel = "100%",
    })

    inner:Finalize()
end

--------------------------------------------------------------------------------
-- Renderer Function
--------------------------------------------------------------------------------

function UF.RenderFocusTarget(panel, scrollContent)
    panel:ClearContent()

    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder

    builder:SetOnRefresh(function()
        UF.RenderFocusTarget(panel, scrollContent)
    end)

    -- Debounce timer for position writes
    local _pendingWriteTimer

    local function writeOffsets(newX, newY)
        local t = B.ensureUFDB()
        if not t then return end

        if newX ~= nil then t.offsetX = math.floor(newX + 0.5) end
        if newY ~= nil then t.offsetY = math.floor(newY + 0.5) end

        -- Debounce the apply
        if _pendingWriteTimer and _pendingWriteTimer.Cancel then _pendingWriteTimer:Cancel() end
        _pendingWriteTimer = C_Timer.NewTimer(0.1, function()
            applyPosition()
        end)
    end

    --------------------------------------------------------------------------------
    -- Parent-Level Settings
    --------------------------------------------------------------------------------

    builder:AddToggle({
        label = "Hide Blizzard Frame Art & Animations",
        description = "REQUIRED for custom borders. Hides default frame art.",
        emphasized = true,
        get = function()
            local t = B.getUFDB() or {}
            return not not t.useCustomBorders
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.useCustomBorders = not not v
            applyCustomBorders()
        end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })

    -- Not in Edit Mode; scale is controlled directly
    builder:AddSlider({
        label = "Scale",
        description = "Overall scale of the Target of Focus frame.",
        min = 0.5, max = 2.0, step = 0.05, precision = 2,
        get = function()
            local t = B.getUFDB() or {}
            return tonumber(t.scale) or 1.0
        end,
        set = function(v)
            local t = B.ensureUFDB()
            if not t then return end
            t.scale = tonumber(v) or 1.0
            -- Debounce the scale application
            if _pendingWriteTimer and _pendingWriteTimer.Cancel then _pendingWriteTimer:Cancel() end
            _pendingWriteTimer = C_Timer.NewTimer(0.1, function()
                applyScale()
            end)
        end,
        minLabel = "0.5x", maxLabel = "2.0x",
    })

    builder:AddDualSlider({
        label = "Position Offset",
        sliderA = {
            axisLabel = "X",
            min = -300, max = 300, step = 1,
            get = function()
                local t = B.getUFDB() or {}
                return tonumber(t.offsetX) or 0
            end,
            set = function(v)
                writeOffsets(v, nil)
            end,
        },
        sliderB = {
            axisLabel = "Y",
            min = -300, max = 300, step = 1,
            get = function()
                local t = B.getUFDB() or {}
                return tonumber(t.offsetY) or 0
            end,
            set = function(v)
                writeOffsets(nil, v)
            end,
        },
    })

    --------------------------------------------------------------------------------
    -- Health Bar (Style, Border tabs)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Health Bar",
        componentId = COMPONENT_ID,
        sectionKey = "healthBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "healthBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "healthBar", B.applyBarTextures) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "healthBar", B.applyBarTextures) end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Power Bar (Style, Border, Visibility tabs)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Power Bar",
        componentId = COMPONENT_ID,
        sectionKey = "powerBar",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "style", label = "Style" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "powerBar_tabs",
                buildContent = {
                    style = function(cf, tabInner) buildStyleTab(tabInner, "powerBar", B.applyBarTextures, UF.powerColorValues, UF.powerColorOrder) end,
                    border = function(cf, tabInner) buildBorderTab(tabInner, "powerBar", B.applyBarTextures) end,
                    visibility = function(cf, tabInner)
                        tabInner:AddToggle({
                            label = "Hide Power Bar",
                            get = function() local t = B.getUFDB() or {}; return not not t.powerBarHidden end,
                            set = function(v) local t = B.ensureUFDB(); if t then t.powerBarHidden = v and true or false; applyPowerVisibility() end end,
                        })
                        tabInner:Finalize()
                    end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Portrait (Positioning, Sizing, Mask, Border, Visibility tabs)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Portrait",
        componentId = COMPONENT_ID,
        sectionKey = "portrait",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            inner:AddTabbedSection({
                tabs = {
                    { key = "positioning", label = "Positioning" },
                    { key = "sizing", label = "Sizing" },
                    { key = "mask", label = "Mask" },
                    { key = "border", label = "Border" },
                    { key = "visibility", label = "Visibility" },
                },
                componentId = COMPONENT_ID,
                sectionKey = "portrait_tabs",
                buildContent = {
                    positioning = function(cf, tabInner) buildPortraitPositioningTab(tabInner) end,
                    sizing = function(cf, tabInner) buildPortraitSizingTab(tabInner) end,
                    mask = function(cf, tabInner) buildPortraitMaskTab(tabInner) end,
                    border = function(cf, tabInner) buildPortraitBorderTab(tabInner) end,
                    visibility = function(cf, tabInner) buildPortraitVisibilityTab(tabInner) end,
                },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Name Text (non-tabbed collapsible section)
    --------------------------------------------------------------------------------

    builder:AddCollapsibleSection({
        title = "Name Text",
        componentId = COMPONENT_ID,
        sectionKey = "nameText",
        defaultExpanded = false,
        buildContent = function(contentFrame, inner)
            local get, set = B.textAccessors("textName", { hiddenKey = "nameTextHidden" })
            inner:AddTextStyleBlock({
                get = get, set = set, apply = applyNameText,
                defaults = { size = 10 },
                hideToggle = { label = "Disable Name Text" },
                size = { min = 6, max = 24 },
                alignment = { kind = "align", default = "LEFT" },
            })
            inner:Finalize()
        end,
    })

    --------------------------------------------------------------------------------
    -- Finalize
    --------------------------------------------------------------------------------

    builder:Finalize()
end

--------------------------------------------------------------------------------
-- Self-register with settings panel
addon.UI.SettingsPanel:RegisterRenderer("ufFocusTarget", function(panel, scrollContent)
    UF.RenderFocusTarget(panel, scrollContent)
end)

-- Return renderer for registration
--------------------------------------------------------------------------------

return UF.RenderFocusTarget
