-- SettingsBuilderRows.lua - Single-widget rows over SettingsBuilder
-- Attaches methods to addon.UI.SettingsBuilder; instances created by
-- Builder:CreateFor resolve them through the metatable.
local addonName, addon = ...

local Builder = addon.UI.SettingsBuilder
local Theme = addon.UI.Theme
local Controls = addon.UI.Controls

local CONTENT_PADDING = Builder._CONTENT_PADDING

--------------------------------------------------------------------------------
-- AddToggle: Add a toggle (boolean) setting
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current value
--   set         : Function(newValue) to save value
--   key         : Optional unique key for dynamic updates (SetLabel, etc.)
--   emphasized  : Optional boolean for "Hero Toggle" styling (master controls)
--   infoIcon    : Optional { tooltipText, tooltipTitle } for inline info icon
--------------------------------------------------------------------------------

function Builder:AddToggle(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("toggle", options.label, options.description) then return self end

    local toggle = Controls:CreateToggle({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        useLightDim = self._useLightDim,
        emphasized = options.emphasized,
        infoIcon = options.infoIcon,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(toggle, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSelector: Add a selector/dropdown setting
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   values      : Table of { key = "Display Text" } pairs
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   width       : Selector width (optional)
--   key         : Optional unique key for dynamic updates (SetLabel, SetOptions)
--   emphasized  : Optional boolean for "Hero" styling (master controls)
--   labelAlign  : "field" right-aligns the label against the field's left edge
--   noBottomBorder : Optional boolean to hide the 1px row bottom border
--   sizeScale   : Optional factor scaling the whole control (fonts, heights);
--                 not supported together with description or emphasized
--   gear        : Optional in-field gear button opening a sub-options fly-out.
--                 { pages = { [optionKey] = { build = function(content, panel,
--                 key), tooltip, width, height } }, width, height, direction }.
--                 The gear shows only while an option carrying a page is
--                 selected. See ui/v2/controls/SelectorGear.lua. A sub-option
--                 whose set triggers a page re-render closes the fly-out.
--------------------------------------------------------------------------------

function Builder:AddSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("selector", options.label, options.description) then return self end

    local selector = Controls:CreateSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        values = options.values,
        order = options.order,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
        emphasized = options.emphasized,
        labelAlign = options.labelAlign,
        noBottomBorder = options.noBottomBorder,
        sizeScale = options.sizeScale,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        optionInfoIcons = options.optionInfoIcons,
        disabledOptions = options.disabledOptions,
        gear = options.gear,
    })

    self:_PlaceRow(selector, options)
    self:_AttachInfoIcon(selector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSlider: Add a numeric slider setting
--------------------------------------------------------------------------------
-- Options:
--   label          : Setting label text
--   description    : Optional description below label
--   min            : Minimum value (required)
--   max            : Maximum value (required)
--   step           : Step increment (default 1)
--   get            : Function returning current value
--   set            : Function(newValue) to save value
--   minLabel       : Optional tiny label under left end
--   maxLabel       : Optional tiny label under right end
--   width          : Slider track width (optional)
--   inputWidth     : Text input width (optional)
--   precision      : Decimal places for display (default 0)
--   key            : Optional unique key for dynamic updates (SetLabel, SetMinMax)
--   onEditModeSync : Function(newValue) to call for Edit Mode sync (debounced)
--   debounceDelay  : Delay before Edit Mode sync (default 0.2s)
--   debounceKey    : Unique key for debounce timer (auto-generated if nil)
--   infoIcon       : Optional table { tooltipText, tooltipTitle } to add info icon
--------------------------------------------------------------------------------

function Builder:AddSlider(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("slider", options.label, options.description) then return self end

    local slider = Controls:CreateSlider({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        emphasized = options.emphasized,
        min = options.min,
        max = options.max,
        step = options.step,
        get = options.get,
        set = options.set,
        minLabel = options.minLabel,
        maxLabel = options.maxLabel,
        width = options.width,
        inputWidth = options.inputWidth,
        precision = options.precision,
        displayMultiplier = options.displayMultiplier,
        displaySuffix = options.displaySuffix,
        -- Edit Mode sync support
        onEditModeSync = options.onEditModeSync,
        debounceDelay = options.debounceDelay,
        debounceKey = options.debounceKey,
        useLightDim = self._useLightDim,
        -- Disabled state support
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(slider, options)
    self:_AttachInfoIcon(slider, options)

    return self
end

--------------------------------------------------------------------------------
-- AddFontSelector: Add a font selection dropdown with popup picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current font key (e.g., "FRIZQT__")
--   set         : Function(fontKey) to save selected font
--   width       : Selector box width (optional)
--------------------------------------------------------------------------------

function Builder:AddFontSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("font", options.label, options.description) then return self end

    local fontSelector = Controls:CreateFontSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
    })

    self:_PlaceRow(fontSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddBarTextureSelector: Add a bar texture selection dropdown with popup picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current texture key (e.g., "bevelled")
--   set         : Function(textureKey) to save selected texture
--   width       : Selector box width (optional)
--------------------------------------------------------------------------------

function Builder:AddBarTextureSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("texture", options.label, options.description) then return self end

    local barTextureSelector = Controls:CreateBarTextureSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        useLightDim = self._useLightDim,
    })

    self:_PlaceRow(barTextureSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddBarBorderSelector: Add a bar border selection dropdown with popup picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current border key (e.g., "mmtPixel")
--   set         : Function(borderKey) to save selected border
--   width       : Selector box width (optional)
--   includeNone : Whether to show "No Border" option (default true)
--------------------------------------------------------------------------------

function Builder:AddBarBorderSelector(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("border", options.label, options.description) then return self end

    local barBorderSelector = Controls:CreateBarBorderSelector({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        width = options.width,
        includeNone = options.includeNone,
        includeBlizzardDefault = options.includeBlizzardDefault,
        useLightDim = self._useLightDim,
        getHiddenEdges = options.getHiddenEdges,
        setHiddenEdges = options.setHiddenEdges,
    })

    self:_PlaceRow(barBorderSelector, options)

    return self
end

--------------------------------------------------------------------------------
-- AddColorPicker: Add a color selection row with swatch
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning {r, g, b, a} or r, g, b, a
--   set         : Function(r, g, b, a) to save color
--   hasAlpha    : Boolean, show opacity slider (default false)
--   swatchWidth : Swatch width (optional)
--   swatchHeight: Swatch height (optional)
--------------------------------------------------------------------------------

function Builder:AddColorPicker(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("color", options.label, options.description) then return self end

    local colorPicker = Controls:CreateColorPicker({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        hasAlpha = options.hasAlpha,
        swatchWidth = options.swatchWidth,
        swatchHeight = options.swatchHeight,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(colorPicker, options)

    return self
end

--------------------------------------------------------------------------------
-- AddToggleColorPicker: Add a toggle with inline color picker
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning toggle state (boolean)
--   set         : Function(newValue) to save toggle state
--   getColor    : Function returning {r, g, b, a} or r, g, b, a
--   setColor    : Function(r, g, b, a) to save color
--   hasAlpha    : Boolean, show opacity slider (default true)
--   swatchWidth : Swatch width (optional)
--   swatchHeight: Swatch height (optional)
--------------------------------------------------------------------------------

function Builder:AddToggleColorPicker(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("toggle + color", options.label, options.description) then return self end

    local toggleColor = Controls:CreateToggleColorPicker({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        get = options.get,
        set = options.set,
        getColor = options.getColor,
        setColor = options.setColor,
        hasAlpha = options.hasAlpha,
        swatchWidth = options.swatchWidth,
        swatchHeight = options.swatchHeight,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
    })

    self:_PlaceRow(toggleColor, options)

    return self
end

--------------------------------------------------------------------------------
-- AddSelectorColorPicker: Add a selector with inline color swatch for custom
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   values      : Table of { key = "Display Text" } pairs
--   order       : Optional array of keys for display order
--   get         : Function returning current key
--   set         : Function(newKey) to save value
--   getColor    : Function returning {r, g, b, a} or r, g, b, a (for custom mode)
--   setColor    : Function(r, g, b, a) to save custom color
--   customValue : Key value that triggers color swatch display (default "custom")
--   hasAlpha    : Boolean, show opacity slider (default true)
--   width       : Selector width (optional)
--------------------------------------------------------------------------------

function Builder:AddSelectorColorPicker(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    if self:_ScanRecord("selector + color", options.label, options.description) then return self end

    local selectorColor = Controls:CreateSelectorColorPicker({
        parent = scrollContent,
        label = options.label,
        description = options.description,
        values = options.values,
        order = options.order,
        get = options.get,
        set = options.set,
        getColor = options.getColor,
        setColor = options.setColor,
        customValue = options.customValue,
        hasAlpha = options.hasAlpha,
        width = options.width,
        useLightDim = self._useLightDim,
        disabled = options.disabled,
        isDisabled = options.isDisabled,
        optionInfoIcons = options.optionInfoIcons,
    })

    self:_PlaceRow(selectorColor, options)

    return self
end

--------------------------------------------------------------------------------
-- AddTextInput: Add a single-line text input
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   description : Optional description below label
--   get         : Function returning current text string
--   set         : Function(newText) to save text
--   placeholder : Optional placeholder text
--   maxLetters  : Max character count (0 = unlimited)
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddTextInput(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local textInput = Controls:CreateSingleLineEditBox({
        parent = scrollContent,
        label = options.label,
        placeholder = options.placeholder,
        maxLetters = options.maxLetters,
        text = options.get and options.get() or "",
        width = scrollContent:GetWidth() - (CONTENT_PADDING * 2),
    })

    if textInput then
        self:_PlaceRow(textInput, options)

        -- Wire up set callback
        textInput:SetOnChange(function(text)
            if options.set then
                options.set(text)
            end
        end)

        -- Add description if provided
        if options.description then
            self._currentY = self._currentY - 4
            local descFS = scrollContent:CreateFontString(nil, "OVERLAY")
            local fontPath = Theme:GetFont("VALUE")
            descFS:SetFont(fontPath, 11, "")
            descFS:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", CONTENT_PADDING + 2, self._currentY)
            descFS:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -CONTENT_PADDING, self._currentY)
            descFS:SetText(options.description)
            descFS:SetJustifyH("LEFT")
            descFS:SetWordWrap(true)
            if self._useLightDim then
                descFS:SetTextColor(0.55, 0.55, 0.55, 1)
            else
                local dimR, dimG, dimB = Theme:GetDimTextColor()
                descFS:SetTextColor(dimR, dimG, dimB, 1)
            end
            table.insert(self._controls, descFS)
            self._currentY = self._currentY - (descFS:GetStringHeight() or 14)
        end
    end

    return self
end

--------------------------------------------------------------------------------
-- AddMultiLineEditBox: Add a multi-line text input
--------------------------------------------------------------------------------
-- Options:
--   label       : Setting label text
--   get         : Function returning current text string
--   set         : Function(newText) to save text
--   placeholder : Optional placeholder text
--   height      : Edit box height (default 120)
--   key         : Optional unique key for dynamic updates
--------------------------------------------------------------------------------

function Builder:AddMultiLineEditBox(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local editBox = Controls:CreateMultiLineEditBox({
        parent = scrollContent,
        label = options.label,
        placeholder = options.placeholder,
        height = options.height or 120,
        text = options.get and options.get() or "",
        width = scrollContent:GetWidth() - (CONTENT_PADDING * 2),
    })

    if editBox then
        self:_PlaceRow(editBox, options)

        -- Wire up change detection on focus loss
        local innerEditBox = editBox._editBox
        if innerEditBox and options.set then
            innerEditBox:HookScript("OnEditFocusLost", function(self)
                options.set(self:GetText())
            end)
        end
    end

    return self
end

--------------------------------------------------------------------------------
-- AddPreview: Inline preview row for Custom Groups / ScootAuras
--------------------------------------------------------------------------------

function Builder:AddPreview(options)
    local scrollContent = self._scrollContent
    if not scrollContent then return self end

    local preview = Controls:CreatePreview({
        parent = scrollContent,
        componentId = options.componentId,
        mode = options.mode,
        settingKeys = options.settingKeys,
        iconTexture = options.iconTexture,
        auraDefaultBarColor = options.auraDefaultBarColor,
        caTextSource = options.caTextSource,
        caTextLiteral = options.caTextLiteral,
        previewNameLabel = options.previewNameLabel,
        useLightDim = self._useLightDim,
        rowHeight = options.rowHeight,
        previewScale = options.previewScale,
        maxRowHeight = options.maxRowHeight,
        borderPath = options.borderPath,
        getSetting = options.getSetting,
        getSubSetting = options.getSubSetting,
        shapeAtlas = options.shapeAtlas,
        shapeColor = options.shapeColor,
        shapeDrain = options.shapeDrain,
        noBottomBorder = options.noBottomBorder,
        noHover = options.noHover,
        noLabel = options.noLabel,
        timerEpoch = options.timerEpoch,
    })

    self:_PlaceRow(preview, options)

    return self
end
