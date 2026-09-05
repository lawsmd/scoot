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

return UF.Sections
