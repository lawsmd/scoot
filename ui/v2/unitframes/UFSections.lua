-- UFSections.lua - Shared section and tab builders for the unit frame settings
-- renderers. Not UFZSections.lua, which holds the Unit Frames Z pages.
--
-- Every builder takes B (the UF.BindUnit table) and an options table. Tab
-- builders take the tab's inner builder as opts.inner and call Finalize on it;
-- section builders take the page builder as opts.builder plus opts.componentId
-- and own their section and tab keys, which the collapse and tab state and the
-- deep links depend on. get closures read through B.get*DB only; ensure* is
-- for set closures (the search scan renders every page).
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.UnitFrames = addon.UI.UnitFrames or {}
local UF = addon.UI.UnitFrames

UF.Sections = UF.Sections or {}
local Sections = UF.Sections

--------------------------------------------------------------------------------
-- Tab Builders
--------------------------------------------------------------------------------

-- Bar style tab: one AddBarStyleBlock over the bar's prefixed key family.
-- opts: inner, barPrefix, apply, colorValues, colorOrder, colorInfoIcons.
function Sections.BuildStyleTab(B, opts)
    local get, set = B.barAccessors(opts.barPrefix)
    opts.inner:AddBarStyleBlock({
        get = get, set = set, apply = opts.apply,
        foreground = { values = opts.colorValues, order = opts.colorOrder, infoIcons = opts.colorInfoIcons },
    })
    opts.inner:Finalize()
end

-- Bar border tab: one AddBarBorderBlock.
-- opts: inner, barPrefix, apply, accessorOpts (forwarded to B.barAccessors),
-- enableToggle (nil omits the enable row).
function Sections.BuildBorderTab(B, opts)
    local get, set = B.barAccessors(opts.barPrefix, opts.accessorOpts)
    opts.inner:AddBarBorderBlock({ get = get, set = set, apply = opts.apply, enableToggle = opts.enableToggle })
    opts.inner:Finalize()
end

-- Text style tab: one AddTextStyleBlock over a text sub-table.
-- opts: inner, textKey, applyHidden, defaultAlignment, colorValues, colorOrder,
-- alignmentKind ("align" unless "bossDual", which derives the dual selector key
-- from textKey), hideToggle (true unless overridden).
function Sections.BuildTextTab(B, opts)
    local get, set = B.textAccessors(opts.textKey)
    local alignment
    if opts.alignmentKind == "bossDual" then
        alignment = { kind = "bossDual", default = opts.defaultAlignment, key = opts.textKey .. "AlignmentDual" }
    else
        alignment = { kind = "align", default = opts.defaultAlignment }
    end
    local hideToggle = opts.hideToggle
    if hideToggle == nil then hideToggle = true end
    opts.inner:AddTextStyleBlock({
        get = get, set = set, apply = B.applyStyles,
        applyHidden = opts.applyHidden,
        hideToggle = hideToggle,
        color = { values = opts.colorValues, order = opts.colorOrder },
        alignment = alignment,
    })
    opts.inner:Finalize()
end

--------------------------------------------------------------------------------
-- Section Builders
--------------------------------------------------------------------------------

-- Parent-level controls above the sections: the Hide Blizzard Art toggle, then
-- Use Larger Frame, Frame Size or the Boss Scale slider, and Scale Multiplier
-- as the unit carries them.
-- opts: builder, componentId; useCustomBorders = { clearHealthBorder = false
-- to skip the healthBarHideBorder reset (Boss), onDisable = function(t,
-- wasEnabled) for extra resets (Player) }; useLargerFrame = { description }
-- (Focus, Boss); frameSize/scaleMult = false to skip (Boss); bossScale = true
-- for the Boss db scale slider.
function Sections.BuildParentControls(B, opts)
    local builder = opts.builder
    local ucb = opts.useCustomBorders or {}
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
            local wasEnabled = t.useCustomBorders
            t.useCustomBorders = not not v
            if not v then
                if ucb.clearHealthBorder ~= false then t.healthBarHideBorder = false end
                if ucb.onDisable then ucb.onDisable(t, wasEnabled) end
            end
            B.applyBarTextures()
        end,
        infoIcon = UF.TOOLTIPS.hideBlizzardArt,
    })
    if opts.useLargerFrame then
        builder:AddToggle({
            label = "Use Larger Frame",
            description = opts.useLargerFrame.description,
            get = function()
                return UF.getUseLargerFrame(opts.componentId)
            end,
            set = function(v)
                UF.setUseLargerFrame(opts.componentId, v)
            end,
        })
    end
    if opts.frameSize ~= false then
        builder:AddSlider({
            label = "Frame Size (Scale)",
            description = "Blizzard's Edit Mode scale (100-200%).",
            min = 100,
            max = 200,
            step = 5,
            get = function()
                return UF.getEditModeFrameSize(opts.componentId)
            end,
            set = function(v)
                UF.setEditModeFrameSize(opts.componentId, v)
            end,
            minLabel = "100%",
            maxLabel = "200%",
            infoIcon = UF.TOOLTIPS.frameSize,
        })
    end
    if opts.bossScale then
        builder:AddSlider({
            label = "Scale",
            description = "Overall scale of boss frames.",
            min = 0.5, max = 2.0, step = 0.05, precision = 2,
            get = function() local t = B.getUFDB() or {}; return tonumber(t.scale) or 1.0 end,
            set = function(v) local t = B.ensureUFDB(); if t then t.scale = tonumber(v) or 1.0; B.applyStyles() end end,
            minLabel = "0.5x", maxLabel = "2.0x",
        })
    end
    if opts.scaleMult ~= false then
        builder:AddSlider({
            label = "Scale Multiplier",
            description = "Addon multiplier on top of Edit Mode scale.",
            min = 1.0,
            max = 2.0,
            step = 0.05,
            precision = 2,
            get = function()
                local t = B.getUFDB() or {}
                return tonumber(t.scaleMult) or 1.0
            end,
            set = function(v)
                local t = B.ensureUFDB()
                if not t then return end
                t.scaleMult = tonumber(v) or 1.0
                B.applyScaleMult()
            end,
            minLabel = "1.0x",
            maxLabel = "2.0x",
            infoIcon = UF.TOOLTIPS.scaleMult,
        })
    end
end

return UF.Sections
