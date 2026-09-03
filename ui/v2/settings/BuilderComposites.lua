-- BuilderComposites.lua - Multi-control composites over SettingsBuilder atoms
-- Loaded after settings/Helpers.lua; attaches methods to addon.UI.SettingsBuilder.
-- Instances created by Builder:CreateFor resolve these through the metatable, so
-- every builder (including the inner builders of collapsible/tabbed sections)
-- can call them.
local addonName, addon = ...

local Builder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

--------------------------------------------------------------------------------
-- Shared defaults and option normalization
--------------------------------------------------------------------------------

local BUILTIN_DEFAULTS = {
    fontFace = "FRIZQT__",
    style = "OUTLINE",
    size = 14,
    colorMode = "default",
    color = { 1, 1, 1, 1 },
}

-- Per-control opt: false disables the control, true or nil selects defaults,
-- a table carries overrides.
local function norm(opt)
    if opt == false then return nil end
    if opt == true or opt == nil then return {} end
    return opt
end

--------------------------------------------------------------------------------
-- AddOffsetPair: X/Y offset dual slider
--------------------------------------------------------------------------------
-- Options:
--   get(axis)   : returns the stored value for axis "x" or "y" (side-effect-free)
--   set(axis,v) : stores the value; must not call apply
--   apply       : called after every write
--   label       : default "Offset"
--   range       : symmetric bound, default 100 (min = -range, max = range)
--   min, max    : explicit bounds for asymmetric ranges (override range)
--   step        : default 1
--   minLabel, maxLabel, description, key, disabled : forwarded
-- Values are coerced with tonumber(...) or 0 on both read and write.
--------------------------------------------------------------------------------

function Builder:AddOffsetPair(opts)
    local apply = opts.apply
    local range = opts.range or 100
    local minV = opts.min or -range
    local maxV = opts.max or range
    local step = opts.step or 1

    local function slider(axis, axisLabel)
        return {
            axisLabel = axisLabel,
            min = minV, max = maxV, step = step,
            minLabel = opts.minLabel, maxLabel = opts.maxLabel,
            get = function() return tonumber(opts.get(axis)) or 0 end,
            set = function(v)
                opts.set(axis, tonumber(v) or 0)
                if apply then apply() end
            end,
        }
    end

    return self:AddDualSlider({
        label = opts.label or "Offset",
        description = opts.description,
        key = opts.key,
        disabled = opts.disabled,
        sliderA = slider("x", "X"),
        sliderB = slider("y", "Y"),
    })
end

--------------------------------------------------------------------------------
-- AddTextStyleBlock: the standard text styling control block
--------------------------------------------------------------------------------
-- Composes the font/style/size/color/alignment/offset controls a text surface
-- exposes, in one canonical order: hide toggle, hide-realm toggle, Font,
-- Style, Size, Color, Alignment, Offset. The composite speaks a fixed field
-- vocabulary and never touches the db; the caller supplies two closures that
-- translate fields to its storage shape:
--
--   get(field) -> value|nil   Side-effect-free. Must never materialize
--                             tables: SetOnRefresh re-renders on every
--                             expand/collapse and search-index scans render
--                             every page, so a get that writes would seed
--                             bare tables into untouched profiles.
--   set(field, value)         Materializing. Must not call apply; the
--                             composite calls opts.apply after every write.
--
-- Fields: hidden, hideRealm, fontFace, style, size, colorMode, colorModeDK,
-- color, alignment, alignmentMode, nameAnchor, anchor, offsetX, offsetY.
--
-- Options:
--   get, set, apply : required, as above
--   applyHidden     : apply used by the hide toggle only (default opts.apply)
--   defaults        : overlay over { fontFace = "FRIZQT__", style = "OUTLINE",
--                     size = 14, colorMode = "default", color = {1,1,1,1} }
--   hideToggle      : nil (omit) | true | { label = "Disable Text", description, key }
--   hideRealmToggle : nil (omit) | true | { label = "Hide Realm Name", description, key }
--   font            : true (default) | false | { label, description, key }
--   style           : true (default) | false | { label, description, key,
--                     values, order }   -- pass Helpers.fontStyleOrderPaired etc.
--   size            : true (default) | false | { label, description, key,
--                     min = 6, max = 48, step = 1, minLabel, maxLabel }
--   color           : true (default) | false | { label, description, key,
--                     kind = "selector" (colorMode dropdown + swatch) | "plain"
--                     (swatch only), values, order, optionInfoIcons,
--                     customValue = "custom", hasAlpha = true, dkPair = false }
--                     dkPair routes the mode through addon.ReadColorMode /
--                     addon.WriteColorMode over the colorMode/colorModeDK pair.
--   alignment       : nil (omit) | { kind = "align" (LEFT/CENTER/RIGHT over
--                     field "alignment") | "anchor9" (nine-point over field
--                     "anchor") | "bossDual" (mode dropdown over field
--                     "alignmentMode" ("bar"|"name") paired with a second
--                     dropdown writing field "alignment" in bar mode or
--                     "nameAnchor" in name mode; requires key so the second
--                     dropdown's options can be swapped on mode change;
--                     catalogs default from addon.UI.UnitFrames),
--                     default, label, description, key, values, order }
--   offset          : true (default) | false | { label, range, min, max, step,
--                     minLabel, maxLabel, description, key }
--   disabled        : function() -> boolean, forwarded to every control
--
-- Returns self. Does not call Finalize(); callers do.
--------------------------------------------------------------------------------

function Builder:AddTextStyleBlock(opts)
    local get, set, apply = opts.get, opts.set, opts.apply
    local disabled = opts.disabled
    local overlay = opts.defaults or {}
    local function default(field)
        local v = overlay[field]
        if v == nil then v = BUILTIN_DEFAULTS[field] end
        return v
    end

    local hideToggle = opts.hideToggle
    if hideToggle then
        if hideToggle == true then hideToggle = {} end
        self:AddToggle({
            label = hideToggle.label or "Disable Text",
            description = hideToggle.description,
            key = hideToggle.key,
            disabled = disabled,
            get = function() return not not get("hidden") end,
            set = function(v)
                set("hidden", v and true or false)
                ;(opts.applyHidden or apply)()
            end,
        })
    end

    local hideRealm = opts.hideRealmToggle
    if hideRealm then
        if hideRealm == true then hideRealm = {} end
        self:AddToggle({
            label = hideRealm.label or "Hide Realm Name",
            description = hideRealm.description,
            key = hideRealm.key,
            disabled = disabled,
            get = function() return not not get("hideRealm") end,
            set = function(v)
                set("hideRealm", v and true or false)
                apply()
            end,
        })
    end

    local font = norm(opts.font)
    if font then
        self:AddFontSelector({
            label = font.label or "Font",
            description = font.description,
            key = font.key,
            get = function() return get("fontFace") or default("fontFace") end,
            set = function(v)
                set("fontFace", v or default("fontFace"))
                apply()
            end,
        })
    end

    local style = norm(opts.style)
    if style then
        self:AddSelector({
            label = style.label or "Style",
            description = style.description,
            key = style.key,
            values = style.values or Helpers.fontStyleValues,
            order = style.order or Helpers.fontStyleOrder,
            disabled = disabled,
            get = function() return get("style") or default("style") end,
            set = function(v)
                set("style", v)
                apply()
            end,
        })
    end

    local size = norm(opts.size)
    if size then
        self:AddSlider({
            label = size.label or "Size",
            description = size.description,
            key = size.key,
            min = size.min or 6,
            max = size.max or 48,
            step = size.step or 1,
            minLabel = size.minLabel,
            maxLabel = size.maxLabel,
            disabled = disabled,
            get = function() return tonumber(get("size")) or default("size") end,
            set = function(v)
                set("size", tonumber(v) or default("size"))
                apply()
            end,
        })
    end

    local color = norm(opts.color)
    if color then
        local function getColor()
            local c = get("color")
            if type(c) ~= "table" then c = default("color") end
            return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        end
        local function setColor(r, g, b, a)
            set("color", { r or 1, g or 1, b or 1, a or 1 })
            apply()
        end

        if (color.kind or "selector") == "selector" then
            self:AddSelectorColorPicker({
                label = color.label or "Color",
                description = color.description,
                key = color.key,
                values = color.values or Helpers.textColorValues,
                order = color.order or Helpers.textColorOrder,
                optionInfoIcons = color.optionInfoIcons,
                disabled = disabled,
                get = function()
                    if color.dkPair then
                        return addon.ReadColorMode(
                            function() return get("colorMode") end,
                            function() return get("colorModeDK") end
                        )
                    end
                    return get("colorMode") or default("colorMode")
                end,
                set = function(v)
                    if color.dkPair then
                        addon.WriteColorMode(v or default("colorMode"),
                            function() return get("colorMode") end,
                            function(val) set("colorMode", val) end,
                            function() return get("colorModeDK") end,
                            function(val) set("colorModeDK", val) end
                        )
                    else
                        set("colorMode", v or default("colorMode"))
                    end
                    apply()
                end,
                getColor = getColor,
                setColor = setColor,
                customValue = color.customValue or "custom",
                hasAlpha = color.hasAlpha ~= false,
            })
        else -- kind == "plain": swatch only, field "color"
            self:AddColorPicker({
                label = color.label or "Color",
                description = color.description,
                key = color.key,
                disabled = disabled,
                hasAlpha = color.hasAlpha ~= false,
                get = getColor,
                set = setColor,
            })
        end
    end

    local alignment = opts.alignment
    if alignment and alignment.kind == "bossDual" then
        -- Port of the boss health/power text alignment control: selector A
        -- picks the mode, selector B's options and target field follow it.
        local Catalogs = addon.Catalogs
        local modeValues = alignment.modeValues or Catalogs.AlignmentMode.values
        local modeOrder = alignment.modeOrder or Catalogs.AlignmentMode.order
        local barValues = alignment.values or Helpers.alignmentValues
        local barOrder = alignment.order or Helpers.alignmentOrder
        local nameValues = alignment.nameValues or Catalogs.NameAnchor.values
        local nameOrder = alignment.nameOrder or Catalogs.NameAnchor.order
        local fallback = alignment.default or "LEFT"
        local key = alignment.key
        local initialName = (get("alignmentMode") or "bar") == "name"
        self:AddDualSelector({
            label = alignment.label or "Alignment",
            description = alignment.description,
            key = key,
            disabled = disabled,
            selectorA = {
                values = modeValues,
                order = modeOrder,
                get = function() return get("alignmentMode") or "bar" end,
                set = function(v)
                    set("alignmentMode", v or "bar")
                    apply()
                    local dual = key and self:GetControl(key)
                    if dual then
                        if v == "name" then
                            dual:SetOptionsB(nameValues, nameOrder)
                        else
                            dual:SetOptionsB(barValues, barOrder)
                        end
                    end
                end,
            },
            selectorB = {
                values = initialName and nameValues or barValues,
                order = initialName and nameOrder or barOrder,
                get = function()
                    if (get("alignmentMode") or "bar") == "name" then
                        return get("nameAnchor") or "RIGHT_OF_NAME"
                    end
                    return get("alignment") or fallback
                end,
                set = function(v)
                    if (get("alignmentMode") or "bar") == "name" then
                        set("nameAnchor", v or "RIGHT_OF_NAME")
                    else
                        set("alignment", v or fallback)
                    end
                    apply()
                end,
            },
        })
    elseif alignment then
        local anchor9 = alignment.kind == "anchor9"
        local field = anchor9 and "anchor" or "alignment"
        local fallback = alignment.default or (anchor9 and "CENTER" or "LEFT")
        self:AddSelector({
            label = alignment.label or (anchor9 and "Anchor" or "Alignment"),
            description = alignment.description,
            key = alignment.key,
            values = alignment.values or (anchor9 and Helpers.anchorValues or Helpers.alignmentValues),
            order = alignment.order or (anchor9 and Helpers.anchorOrder or Helpers.alignmentOrder),
            disabled = disabled,
            get = function() return get(field) or fallback end,
            set = function(v)
                set(field, v or fallback)
                apply()
            end,
        })
    end

    if opts.offset ~= false then
        local offset = norm(opts.offset) or {}
        self:AddOffsetPair({
            label = offset.label,
            description = offset.description,
            key = offset.key,
            range = offset.range,
            min = offset.min,
            max = offset.max,
            step = offset.step,
            minLabel = offset.minLabel,
            maxLabel = offset.maxLabel,
            disabled = disabled,
            apply = apply,
            get = function(axis) return get(axis == "x" and "offsetX" or "offsetY") end,
            set = function(axis, v) set(axis == "x" and "offsetX" or "offsetY", v) end,
        })
    end

    return self
end
