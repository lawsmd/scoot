-- SettingsBuilderCompactRows.lua - Multi-control compact rows over SettingsBuilder
-- Attaches methods to addon.UI.SettingsBuilder; instances created by
-- Builder:CreateFor resolve them through the metatable.
local addonName, addon = ...

local Builder = addon.UI.SettingsBuilder
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- AddDualSlider: Add two compact sliders side-by-side (for X/Y offset pairs)
--------------------------------------------------------------------------------
-- Options:
--   label          : Setting label text (left side)
--   description    : Optional description below label
--   sliderA        : Table with slider A options (see below)
--   sliderB        : Table with slider B options (see below)
--   trackWidth     : Slider track width override (optional, default 90)
--   inputWidth     : Text input width override (optional, default 36)
--   debounceKey    : Unique key for debounce timer (optional)
--   onEditModeSync : Function(aVal, bVal) for Edit Mode sync (debounced)
--   key            : Optional unique key for dynamic updates
--
-- Slider A/B options:
--   axisLabel  : Small prefix label (e.g., "X" or "Y")
--   min, max   : Value range (required)
--   step       : Step increment (default 1)
--   get        : Function returning current value
--   set        : Function(newValue) to save value
--   minLabel   : Optional tiny label under left end
--   maxLabel   : Optional tiny label under right end
--   precision  : Decimal places for display (default 0)
--------------------------------------------------------------------------------

function Builder:AddDualSlider(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("slider", options.label, options.description) then return self end

    local dualSlider = Controls:CreateDualSlider({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        sliderA = options.sliderA,
        sliderB = options.sliderB,
        trackWidth = options.trackWidth,
        inputWidth = options.inputWidth,
        debounceKey = options.debounceKey,
        onEditModeSync = options.onEditModeSync,
        debounceDelay = options.debounceDelay,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(dualSlider, options)

    return self
end

--------------------------------------------------------------------------------
-- AddDualSelector: Add two compact selectors side-by-side
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text (left side, optional)
--   description : Optional description below label
--   selectorA   : Table with selector A options (see below)
--   selectorB   : Table with selector B options (see below)
--   key         : Optional unique key for dynamic updates
--   disabled    : Function returning disabled state (optional)
--
-- Selector A/B options:
--   values      : Table of { key = "Display Text" }
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   syncCooldown: Optional cooldown for sync lock
--------------------------------------------------------------------------------

function Builder:AddDualSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local dualSelector = Controls:CreateDualSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        selectorA = options.selectorA,
        selectorB = options.selectorB,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
        maxContainerWidth = options.maxContainerWidth,
    })

    self:_PlaceRow(dualSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSelectorToggleRow: Selector + Toggle compact row
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text (left side, optional)
--   description : Optional description below label
--   selector    : Table with selector options (values, order, get, set)
--   toggle      : Table with toggle options (get, set, label)
--   key         : Optional unique key for dynamic updates
--   disabled    : Function returning disabled state (optional)
--------------------------------------------------------------------------------

function Builder:AddSelectorToggleRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("selector toggle", options.label, options.description) then return self end

    local selectorToggle = Controls:CreateSelectorToggleRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        selector = options.selector,
        toggle = options.toggle,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(selectorToggle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddToggleSliderRow: Toggle + Slider compact row
--------------------------------------------------------------------------------
-- Options:
--   label       : Row label text
--   description : Optional description below label
--   toggle      : Table with toggle options (get, set, label)
--   slider      : Table with slider options (get, set, min, max, step, suffix, label)
--   disabled / isDisabled : Function returning disabled state
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddToggleSliderRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("toggle slider", options.label, options.description) then return self end

    local toggleSlider = Controls:CreateToggleSliderRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        toggle = options.toggle,
        slider = options.slider,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(toggleSlider, options)

    return self
end

--------------------------------------------------------------------------------
-- AddMultiToggleRow: Several compact toggles in one row
--------------------------------------------------------------------------------
-- Options:
--   label       : Row label text
--   description : Optional explainer below the label
--   toggles     : Array of { key, label, get, set }
--   disabled / isDisabled : Function returning disabled state
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddMultiToggleRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if Builder._scanMode and options.label then
        -- Fold the per-toggle labels into the indexed text so searching for an
        -- individual toggle still surfaces the row that holds it.
        local searchText = options.description or ""
        if type(options.toggles) == "table" then
            local names = {}
            for _, def in ipairs(options.toggles) do
                if def.label and def.label ~= "" then
                    table.insert(names, def.label)
                end
            end
            if #names > 0 then
                searchText = searchText .. " " .. table.concat(names, " ")
            end
        end

        self:_ScanRecord("multi toggle", options.label, searchText)
        return self
    end

    local multiToggle = Controls:CreateMultiToggleRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        toggles = options.toggles,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(multiToggle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddDualBarStyleRow: Texture + Color compact row
--------------------------------------------------------------------------------
-- Options:
--   label              : Row label text (e.g. "Foreground", "Background")
--   description        : Optional description below label
--   getTexture / setTexture : Texture get/set callbacks
--   colorValues / colorOrder / colorInfoIcons : Color selector options
--   getColorMode / setColorMode : Color mode get/set callbacks
--   getColor / setColor : Custom color get/set callbacks
--   customColorValue   : Key that triggers swatch (default "custom")
--   hasAlpha           : Whether color picker supports alpha
--   disabled / isDisabled : Function returning disabled state
--   key                : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddDualBarStyleRow(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("bar style", options.label, options.description) then return self end

    local dualBarStyle = Controls:CreateDualBarStyleRow({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        getTexture = options.getTexture,
        setTexture = options.setTexture,
        colorValues = options.colorValues,
        colorOrder = options.colorOrder,
        colorInfoIcons = options.colorInfoIcons,
        getColorMode = options.getColorMode,
        setColorMode = options.setColorMode,
        getColor = options.getColor,
        setColor = options.setColor,
        customColorValue = options.customColorValue,
        hasAlpha = options.hasAlpha,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        name = options.name,
    })

    self:_PlaceRow(dualBarStyle, options)

    return self
end
