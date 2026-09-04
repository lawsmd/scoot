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

-- Stands in for opts.apply when the caller's set applies on its own.
local function NOOP() end

--------------------------------------------------------------------------------
-- Axis pairs: AddOffsetPair (X/Y) and AddInsetPair (H/V)
--------------------------------------------------------------------------------
-- Shared options:
--   get(axis)   : returns the stored value for the axis key (side-effect-free)
--   set(axis,v) : stores the value; must not call apply
--   apply       : optional; called after every write. Omit it when set
--                 applies on its own (a self-applying API, or a setSetting
--                 that applies).
--   label, description, key, disabled : forwarded
--   min, max    : explicit bounds (override the method's default range)
--   step        : default 1
--   precision   : forwarded to both sliders
--   minLabel, maxLabel : end labels; false omits one the method defaults
-- Values are coerced with tonumber(...) or 0 on both read and write, so a
-- non-zero default or a legacy-key fallback lives in the caller's get.
--
-- AddOffsetPair: axis keys "x"/"y", labels X/Y, label "Offset"; range
--   (default 100) sets min = -range, max = range; no end labels.
-- AddInsetPair:  axis keys "h"/"v", labels H/V, label "Border Inset";
--   min -4, max 4; end labels "-4" and "+4".
--------------------------------------------------------------------------------

local function endLabel(value, default)
    if value == false then return nil end
    if value == nil then return default end
    return value
end

local function addAxisPair(self, opts, spec)
    local apply = opts.apply or NOOP
    local minV = opts.min or spec.min
    local maxV = opts.max or spec.max
    local step = opts.step or 1
    local minLabel = endLabel(opts.minLabel, spec.minLabel)
    local maxLabel = endLabel(opts.maxLabel, spec.maxLabel)

    local function slider(axis, axisLabel)
        return {
            axisLabel = axisLabel,
            min = minV, max = maxV, step = step,
            precision = opts.precision,
            minLabel = minLabel, maxLabel = maxLabel,
            get = function() return tonumber(opts.get(axis)) or 0 end,
            set = function(v)
                opts.set(axis, tonumber(v) or 0)
                apply()
            end,
        }
    end

    return self:AddDualSlider({
        label = opts.label or spec.label,
        description = opts.description,
        key = opts.key,
        disabled = opts.disabled,
        sliderA = slider(spec.axes[1], spec.axisLabels[1]),
        sliderB = slider(spec.axes[2], spec.axisLabels[2]),
    })
end

function Builder:AddOffsetPair(opts)
    local range = opts.range or 100
    return addAxisPair(self, opts, {
        axes = { "x", "y" }, axisLabels = { "X", "Y" },
        label = "Offset", min = -range, max = range,
    })
end

function Builder:AddInsetPair(opts)
    return addAxisPair(self, opts, {
        axes = { "h", "v" }, axisLabels = { "H", "V" },
        label = "Border Inset", min = -4, max = 4,
        minLabel = "-4", maxLabel = "+4",
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
--   get, set        : required, as above
--   apply           : optional; called after every write. Omit it when set
--                     applies on its own (a self-applying API, or a
--                     setSetting that applies).
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
    local get, set, apply = opts.get, opts.set, opts.apply or NOOP
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

--------------------------------------------------------------------------------
-- Color helpers shared by the bar composites
--------------------------------------------------------------------------------
-- Stored colors are {r, g, b, a} tables; a missing table or channel falls
-- back to the row's default, channel by channel, the way the unit-frame bars
-- always read them.

local function unpackColor(c, default)
    if type(c) ~= "table" then c = default end
    return c[1] or default[1], c[2] or default[2], c[3] or default[3], c[4] or default[4]
end

local function packColor(r, g, b, a, default)
    return { r or default[1], g or default[2], b or default[3], a or default[4] }
end

--------------------------------------------------------------------------------
-- AddBarStyleBlock: foreground and background bar style
--------------------------------------------------------------------------------
-- Foreground (texture, color mode, tint) and Background rows on
-- AddDualBarStyleRow, a spacer between them, and the Background Opacity
-- slider. Same contract as AddTextStyleBlock: get(field) is side-effect-free,
-- set(field, value) stores, apply (optional) runs after every write.
--
-- Fields: texture, colorMode, color, bgTexture, bgColorMode, bgColor,
-- bgOpacity.
--
-- Options:
--   get, set, apply, disabled : as AddTextStyleBlock
--   foreground : { label = "Foreground", description, key, values, order,
--                  infoIcons (false for none), customValue = "custom",
--                  hasAlpha = true, textureDefault = "default",
--                  colorModeDefault = "default", colorDefault = {1,1,1,1} };
--                  values, order, and infoIcons default to
--                  Catalogs.ColorMode.Health
--   spacer     : true (default) | false; the AddSpacer(8) before Background
--   background : true (default) | false | the same table; values and order
--                default to Catalogs.ColorMode.Background, no info icons,
--                colorDefault = {0,0,0,1}
--   opacity    : true (default) | false | { label = "Background Opacity",
--                description, key, min = 0, max = 100, step = 1,
--                default = 50, minLabel, maxLabel }
--
-- Returns self. Does not call Finalize(); callers do.
--------------------------------------------------------------------------------

local function addBarStyleRow(self, opts, row, defaultLabel, fields, catalog, colorDefault)
    local get, set, apply = opts.get, opts.set, opts.apply
    local textureDefault = row.textureDefault or "default"
    local modeDefault = row.colorModeDefault or "default"
    local color = row.colorDefault or colorDefault
    local infoIcons = row.infoIcons
    if infoIcons == nil then infoIcons = catalog.infoIcons end
    if infoIcons == false then infoIcons = nil end

    self:AddDualBarStyleRow({
        label = row.label or defaultLabel,
        description = row.description,
        key = row.key,
        disabled = opts.disabled,
        getTexture = function() return get(fields.texture) or textureDefault end,
        setTexture = function(v)
            set(fields.texture, v or textureDefault)
            apply()
        end,
        colorValues = row.values or catalog.values,
        colorOrder = row.order or catalog.order,
        colorInfoIcons = infoIcons,
        getColorMode = function() return get(fields.colorMode) or modeDefault end,
        setColorMode = function(v)
            set(fields.colorMode, v or modeDefault)
            apply()
        end,
        getColor = function() return unpackColor(get(fields.color), color) end,
        setColor = function(r, g, b, a)
            set(fields.color, packColor(r, g, b, a, color))
            apply()
        end,
        customColorValue = row.customValue or "custom",
        hasAlpha = row.hasAlpha ~= false,
    })
end

function Builder:AddBarStyleBlock(opts)
    local o = { get = opts.get, set = opts.set, apply = opts.apply or NOOP, disabled = opts.disabled }
    local Catalogs = addon.Catalogs

    addBarStyleRow(self, o, norm(opts.foreground) or {}, "Foreground",
        { texture = "texture", colorMode = "colorMode", color = "color" },
        Catalogs.ColorMode.Health, { 1, 1, 1, 1 })

    local background = norm(opts.background)
    if background then
        if opts.spacer ~= false then self:AddSpacer(8) end
        addBarStyleRow(self, o, background, "Background",
            { texture = "bgTexture", colorMode = "bgColorMode", color = "bgColor" },
            { values = Catalogs.ColorMode.Background.values, order = Catalogs.ColorMode.Background.order },
            { 0, 0, 0, 1 })
    end

    local opacity = norm(opts.opacity)
    if opacity then
        local default = opacity.default or 50
        self:AddSlider({
            label = opacity.label or "Background Opacity",
            description = opacity.description,
            key = opacity.key,
            min = opacity.min or 0,
            max = opacity.max or 100,
            step = opacity.step or 1,
            minLabel = opacity.minLabel,
            maxLabel = opacity.maxLabel,
            disabled = opts.disabled,
            get = function() return tonumber(o.get("bgOpacity")) or default end,
            set = function(v)
                o.set("bgOpacity", tonumber(v) or default)
                o.apply()
            end,
        })
    end

    return self
end

--------------------------------------------------------------------------------
-- AddBarBorderBlock: bar border style, tint, thickness, inset
--------------------------------------------------------------------------------
-- Optional enable toggle, Border Style (AddBarBorderSelector with the
-- hidden-edges pair), Border Tint (AddToggleColorPicker), Border Thickness
-- (AddSlider), Border Inset (AddInsetPair). Same get/set/apply contract as
-- AddTextStyleBlock.
--
-- Fields: enabled, style, hiddenEdges, tintEnabled, tintColor, thickness,
-- insetH, insetV.
--
-- Options:
--   get, set, apply, disabled : as AddTextStyleBlock. disabled reaches the
--                  toggle, tint, thickness, and inset; AddBarBorderSelector
--                  takes none.
--   enableToggle : nil (omit) | true | { label = "Enable Border",
--                  description, key }
--   style     : true (default) | false | { label = "Border Style",
--               description, key, includeNone = true, includeBlizzardDefault,
--               default = "square", hiddenEdges = true }
--   tint      : true (default) | false | { label = "Border Tint",
--               description, key, hasAlpha = true, default = {1,1,1,1} }
--   thickness : true (default) | false | { label = "Border Thickness",
--               description, key, min = 1, max = 8, step = 0.5,
--               precision = 1, default = 1, clamp = true, minLabel,
--               maxLabel }. clamp rounds to the step and the bounds on read
--               and write, the way the unit-frame bars store it.
--   inset     : true (default) | false | the AddInsetPair option table
--               (label, description, key, min, max, step, precision,
--               minLabel, maxLabel). A non-zero default or a legacy-key
--               fallback lives in the caller's get.
--
-- Returns self. Does not call Finalize(); callers do.
--------------------------------------------------------------------------------

function Builder:AddBarBorderBlock(opts)
    local get, set, apply = opts.get, opts.set, opts.apply or NOOP
    local disabled = opts.disabled

    local toggle = opts.enableToggle
    if toggle then
        if toggle == true then toggle = {} end
        self:AddToggle({
            label = toggle.label or "Enable Border",
            description = toggle.description,
            key = toggle.key,
            disabled = disabled,
            get = function() return not not get("enabled") end,
            set = function(v)
                set("enabled", v and true or false)
                apply()
            end,
        })
    end

    local style = norm(opts.style)
    if style then
        local styleDefault = style.default or "square"
        local selector = {
            label = style.label or "Border Style",
            description = style.description,
            key = style.key,
            includeNone = style.includeNone ~= false,
            includeBlizzardDefault = style.includeBlizzardDefault,
            get = function() return get("style") or styleDefault end,
            set = function(v)
                set("style", v or styleDefault)
                apply()
            end,
        }
        if style.hiddenEdges ~= false then
            selector.getHiddenEdges = function() return get("hiddenEdges") end
            selector.setHiddenEdges = function(v)
                set("hiddenEdges", v)
                apply()
            end
        end
        self:AddBarBorderSelector(selector)
    end

    local tint = norm(opts.tint)
    if tint then
        local colorDefault = tint.default or { 1, 1, 1, 1 }
        self:AddToggleColorPicker({
            label = tint.label or "Border Tint",
            description = tint.description,
            key = tint.key,
            disabled = disabled,
            hasAlpha = tint.hasAlpha ~= false,
            get = function() return not not get("tintEnabled") end,
            set = function(v)
                set("tintEnabled", not not v)
                apply()
            end,
            getColor = function() return unpackColor(get("tintColor"), colorDefault) end,
            setColor = function(r, g, b, a)
                set("tintColor", packColor(r, g, b, a, colorDefault))
                apply()
            end,
        })
    end

    local thickness = norm(opts.thickness)
    if thickness then
        local minV, maxV = thickness.min or 1, thickness.max or 8
        local step = thickness.step or 0.5
        local default = thickness.default or 1
        local clamp = thickness.clamp ~= false
        local function snap(v)
            v = tonumber(v) or default
            if not clamp then return v end
            return math.max(minV, math.min(maxV, math.floor(v / step + 0.5) * step))
        end
        self:AddSlider({
            label = thickness.label or "Border Thickness",
            description = thickness.description,
            key = thickness.key,
            min = minV,
            max = maxV,
            step = step,
            precision = thickness.precision or 1,
            minLabel = thickness.minLabel,
            maxLabel = thickness.maxLabel,
            disabled = disabled,
            get = function() return snap(get("thickness")) end,
            set = function(v)
                set("thickness", snap(v))
                apply()
            end,
        })
    end

    if opts.inset ~= false then
        local inset = norm(opts.inset) or {}
        self:AddInsetPair({
            label = inset.label,
            description = inset.description,
            key = inset.key,
            min = inset.min,
            max = inset.max,
            step = inset.step,
            precision = inset.precision,
            minLabel = inset.minLabel,
            maxLabel = inset.maxLabel,
            disabled = disabled,
            apply = opts.apply,
            get = function(axis) return get(axis == "h" and "insetH" or "insetV") end,
            set = function(axis, v) set(axis == "h" and "insetH" or "insetV", v) end,
        })
    end

    return self
end

--------------------------------------------------------------------------------
-- AddStateOpacityBlock: the in-combat / with-target / out-of-combat triple
--------------------------------------------------------------------------------
-- Three AddSlider rows in one fixed order: Opacity in Combat, Opacity With
-- Target, Opacity Out of Combat, the order addon.Opacity.Resolve
-- (core/opacity.lua) resolves them in. The first rendered slider carries the
-- one Opacity Priority info icon. Same contract as AddTextStyleBlock:
-- get(field) is side-effect-free, set(field, value) stores, apply (optional)
-- runs after every write. Values are 0-100 integers; both directions coerce
-- with tonumber(...) or the default.
--
-- Fields: combat, target, ooc. addon.Opacity.Keys.Plain / .InCombat / .Bar
-- map these fields to a component's stored keys, so a flat-key site hands one
-- of them to Helpers.CreateFlatAccessors as the map and passes the pair here.
--
-- Options:
--   get, set, apply, disabled : as AddTextStyleBlock
--   combatMin : floor of the In Combat slider (default: min). Auras and the
--               Edit Mode-backed CDM viewers use 50.
--   min       : floor of the With Target and Out of Combat sliders (default 1)
--   max, step : shared bounds (default 100, 1)
--   default   : value read when a key is unset (default 100)
--   endLabels : true (default) | false. Derived end labels on every slider:
--               a floor of 0 reads "Hidden", any other bound reads "N%".
--   infoIcon  : true (default: Builder.STATE_OPACITY_TOOLTIP on the first
--               slider) | false | { tooltipTitle, tooltipText }
--   combat, target, ooc : true (default) | false | { label, description,
--               key, min, max, step, minLabel, maxLabel, default, apply,
--               debounceKey, debounceDelay, onEditModeSync }. apply replaces
--               opts.apply for that slider; apply = false skips it (an Edit
--               Mode-synced key whose sync applies). The debounce trio is
--               forwarded to AddSlider unchanged.
--
-- Returns self. Does not call Finalize(); callers do.
--------------------------------------------------------------------------------

Builder.STATE_OPACITY_TOOLTIP = {
    tooltipTitle = "Opacity Priority",
    tooltipText = "In Combat takes precedence, then With Target, then Out of Combat. "
        .. "The highest priority condition that applies determines the opacity.",
}

local STATE_OPACITY_CONTROLS = {
    { field = "combat", label = "Opacity in Combat" },
    { field = "target", label = "Opacity With Target" },
    { field = "ooc",    label = "Opacity Out of Combat" },
}

local function pctLabel(v)
    if v == 0 then return "Hidden" end
    return tostring(v) .. "%"
end

function Builder:AddStateOpacityBlock(opts)
    local get, set, apply = opts.get, opts.set, opts.apply or NOOP
    local disabled = opts.disabled
    local blockMin = opts.min or 1
    local blockMax = opts.max or 100
    local blockStep = opts.step or 1
    local blockDefault = opts.default or 100
    local endLabels = opts.endLabels ~= false

    local infoIcon = opts.infoIcon
    if infoIcon == nil or infoIcon == true then infoIcon = Builder.STATE_OPACITY_TOOLTIP end
    if infoIcon == false then infoIcon = nil end

    for _, spec in ipairs(STATE_OPACITY_CONTROLS) do
        local field = spec.field
        local ctl = norm(opts[field])
        if ctl then
            local minV = ctl.min
            if minV == nil and field == "combat" then minV = opts.combatMin end
            if minV == nil then minV = blockMin end
            local maxV = ctl.max or blockMax
            local default = ctl.default or blockDefault

            local applyFor = apply
            if ctl.apply == false then
                applyFor = NOOP
            elseif ctl.apply then
                applyFor = ctl.apply
            end

            local minLabel, maxLabel
            if endLabels then
                minLabel = endLabel(ctl.minLabel, pctLabel(minV))
                maxLabel = endLabel(ctl.maxLabel, pctLabel(maxV))
            end

            self:AddSlider({
                label = ctl.label or spec.label,
                description = ctl.description,
                key = ctl.key,
                min = minV,
                max = maxV,
                step = ctl.step or blockStep,
                minLabel = minLabel,
                maxLabel = maxLabel,
                disabled = disabled,
                infoIcon = infoIcon,
                debounceKey = ctl.debounceKey,
                debounceDelay = ctl.debounceDelay,
                onEditModeSync = ctl.onEditModeSync,
                get = function() return tonumber(get(field)) or default end,
                set = function(v)
                    set(field, tonumber(v) or default)
                    applyFor()
                end,
            })
            infoIcon = nil -- one icon, on the first rendered slider
        end
    end

    return self
end
