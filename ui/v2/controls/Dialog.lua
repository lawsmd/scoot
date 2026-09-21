-- Dialog.lua - the modal dialog every addon.Dialogs call opens, drawn the
-- way the active skin says.
--
-- The surface is the dialog chrome role: flat is the solid fill inside the
-- framework border, the look the dialog shipped with; a template kind builds
-- the frame on the skin's panel template, whose border, title plate and close
-- button come with it. The X is the closeButton role, the two buttons are
-- Controls:CreateButton, the name prompt is Controls.CreateValueInput on the
-- input role, and the layout list is rows on the navRow role inside a tabBody
-- box with Controls.CreateScrollBar beside them. The name on top is the
-- dialogTitle role: the template's plate, a string in the header role, or
-- the product's banner image. The numbers are metrics.dialog; the width and
-- the list height there are the room inside the art, and art that draws into
-- the rect grows the frame by windowInset. The height is the content's: the
-- message is measured after it is set, and the frame closes around it, the
-- input or the list, and the buttons.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

-- The dialog title and its frame names carry the brand: both addons load this
-- file in the retail client, and one global cannot hold two frames.
local BRAND = addon.Brand or "Scoot"
local Theme -- Lazy loaded

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

local function M()
    return Controls.Metrics().dialog
end

local function GetChrome()
    return addon.UI.Chrome
end

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local dialogFrame
local modalBackdrop
local dialogRegistry = {}

--------------------------------------------------------------------------------
-- The list: rows on the navRow role in a tabBody box, the skin's scrollbar
-- beside them. Rows are reused across shows; the extras past the option
-- count hide.
--------------------------------------------------------------------------------

local function CreateListContainer(parent, height)
    local theme = GetTheme()
    local Chrome = GetChrome()
    local m = M()
    local sb = Controls.Metrics().scrollBar
    local listHeight = height or m.listHeight
    -- The rows stand one pixel inside the box's line
    local inset = Controls.Metrics().tab.borderWidth + 1
    local containerWidth = m.width - m.contentPadding * 2
    -- The gutter the bar stands in: the bar, its margin off the scroll
    -- frame, and the skin's gap off the box's edge
    local gutter = sb.width + sb.margin + sb.gap
    local contentWidth = containerWidth - inset * 2 - gutter

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(containerWidth, listHeight)
    container._listHeight = listHeight
    container._contentWidth = contentWidth
    container._backdrop = Chrome.Backdrop("tabBody", container)

    local scrollFrame = CreateFrame("ScrollFrame", nil, container)
    scrollFrame:SetPoint("TOPLEFT", inset, -inset)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(inset + gutter), inset)
    container._scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth, listHeight)
    scrollFrame:SetScrollChild(content)
    container._content = content

    -- The bar, the way the scrollBar role says; anchored as the picker
    -- shell anchors its own. The factory owns OnScrollRangeChanged and
    -- leaves the wheel to the caller.
    local bar = Controls.CreateScrollBar({ parent = container, scrollFrame = scrollFrame })
    if bar then
        bar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", sb.margin + sb.width, 0)
        bar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", sb.margin + sb.width, 0)
    end
    container._scrollBar = bar

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 1))
        if maxScroll <= 0 then return end
        local target = (self:GetVerticalScroll() or 0) - delta * m.listItemHeight * 2
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, target)))
        if bar then bar:Sync() end
    end)
    container:EnableMouseWheel(true)
    container:SetScript("OnMouseWheel", function(_, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end)

    container._items = {}
    container._selectedValue = nil
    container._onSelect = nil
    -- A skin whose selected row is art of its own says so already; the
    -- [sel] mark is for the flat draw, whose states are two fills of the
    -- same color, and the one-pixel separator under each row is the flat
    -- draw's too.
    local rowSpec = Chrome.Spec("navRow")
    container._markUsed = not rowSpec.selected
    local flatRows = rowSpec.kind == "flat"

    local function NewRow(index)
        local item = CreateFrame("Button", nil, content)
        item:SetSize(contentWidth, m.listItemHeight)
        item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((index - 1) * m.listItemHeight))
        item._isSelected = false

        local label = item:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(label, "value")
        label:SetPoint("LEFT", item, "LEFT", m.listTextInset, 0)
        label:SetPoint("RIGHT", item, "RIGHT", -m.listTextInset, 0)
        label:SetJustifyH("LEFT")
        item._label = label

        item._backdrop = Chrome.Backdrop("navRow", item, { variant = "child", label = label })

        if flatRows then
            local separator = item:CreateTexture(nil, "ARTWORK", nil, 1)
            separator:SetPoint("BOTTOMLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", 0, 0)
            separator:SetHeight(1)
            Controls.RegisterThemedFill(separator, 0.2)
        end

        local mark = item:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(mark, "value", 11)
        mark:SetPoint("RIGHT", item, "RIGHT", -m.listTextInset, 0)
        mark:SetText("[sel]")
        mark:SetTextColor(theme:GetAccentColor())
        mark:Hide()
        item._mark = mark

        function item:SetSelected(selected)
            self._isSelected = selected and true or false
            self._backdrop:SetSelected(self._isSelected)
            self._mark:SetShown(self._isSelected and container._markUsed)
        end

        item:SetScript("OnEnter", function(self) self._backdrop:SetHover(true) end)
        item:SetScript("OnLeave", function(self) self._backdrop:SetHover(false) end)
        item:SetScript("OnClick", function(self)
            for _, other in ipairs(container._items) do
                if other ~= self then other:SetSelected(false) end
            end
            self:SetSelected(true)
            container._selectedValue = self._value
            if container._onSelect then
                container._onSelect(self._value)
            end
        end)
        return item
    end

    function container:SetListOptions(options, selectedValue, onSelect)
        self._onSelect = onSelect
        self._selectedValue = nil
        local count = options and #options or 0

        -- Sized from the stored numbers: the frame has no rect before layout
        local visible = self._listHeight - inset * 2
        content:SetSize(contentWidth, math.max(count * m.listItemHeight, visible))

        for i = 1, count do
            local opt = options[i]
            local item = self._items[i]
            if not item then
                item = NewRow(i)
                self._items[i] = item
            end
            item._value = opt.value
            item._label:SetText(opt.label or opt.value)
            local picked = selectedValue ~= nil and opt.value == selectedValue
            item:SetSelected(picked)
            if picked then self._selectedValue = opt.value end
            item:Show()
        end
        for i = count + 1, #self._items do
            self._items[i]:Hide()
        end

        -- The first row when nothing matched
        if self._selectedValue == nil and count > 0 then
            self._selectedValue = options[1].value
            self._items[1]:SetSelected(true)
        end

        scrollFrame:SetVerticalScroll(0)
        -- The bar reads the scroll range once the frame has been laid out
        C_Timer.After(0, function()
            if bar then bar:Sync() end
        end)
    end

    function container:GetSelectedValue()
        return self._selectedValue
    end

    return container
end

--------------------------------------------------------------------------------
-- Dialog Frame Creation
--------------------------------------------------------------------------------

local function CreateDialogFrame()
    if dialogFrame then
        return dialogFrame, modalBackdrop
    end

    local theme = GetTheme()
    local Chrome = GetChrome()
    local m = M()

    -- Modal backdrop: the black wash over the whole screen, which also takes
    -- the clicks that miss the dialog
    modalBackdrop = CreateFrame("Frame", BRAND .. "DialogBackdrop", UIParent)
    modalBackdrop:SetFrameStrata("FULLSCREEN_DIALOG")
    modalBackdrop:SetFrameLevel(0)
    modalBackdrop:SetAllPoints(UIParent)
    modalBackdrop:EnableMouse(true)
    modalBackdrop:Hide()

    local dimmer = modalBackdrop:CreateTexture(nil, "BACKGROUND")
    dimmer:SetAllPoints()
    dimmer:SetColorTexture(0, 0, 0, m.dimmerAlpha)
    Chrome.ApplyOpacity("dialogDimmer", dimmer)
    modalBackdrop._dimmer = dimmer

    -- The dialog's surface, the way the dialog role says
    local spec = Chrome.Spec("dialog")
    local f = Chrome.CreateFrame(spec, "Frame", BRAND .. "Dialog", modalBackdrop)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(10)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    -- How far the content stands off the frame's edge. Art that draws into
    -- the rect keeps it at the skin's windowInset; the flat border is its
    -- own width and the content padding already clears it.
    local edge = 0
    if spec.kind == "template" then
        addon.UI.Window:BuildTemplateParts(f, spec)
        edge = Controls.Metrics().windowInset or 0
    elseif spec.kind == "nineSlice" then
        f._bg = Controls.AddBackground(f, { color = spec.background or "solid" })
        f._chrome = Chrome.NineSlice(f, spec)
        edge = Controls.Metrics().windowInset or 0
    else
        f._bg = Controls.AddBackground(f, { color = spec.background or "solid", alpha = 1, inset = m.borderWidth })
        f._border = Controls.CreateBorder(f, { thickness = m.borderWidth, corners = "overlap", sublevel = 1 })
    end
    local pad = m.contentPadding + edge
    f._edge = edge
    f._pad = pad
    -- The height is the content's, set on every show; the width is the skin's
    f:SetSize(m.width + edge * 2, m.textTop + m.contentPadding + edge * 2)

    -- Title bar area (for dragging)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", edge, -edge)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(edge + 30), -edge)
    titleBar:SetHeight(30)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    -- The name on top, by the dialogTitle role. texture is an image drawn
    -- over the border art in place of the plate's text: the skin's own
    -- texture where the descriptor names one (a name in the skin's textures
    -- table, or a path), else the image the product's HeaderModel names, the
    -- one the title bar draws, at the model's aspect. A descriptor naming
    -- nothing on a product with no image takes the fallback, the way the
    -- title bar does. window is the template's own plate. text is a string
    -- in the header role.
    local hasPlate = f.SetTitle and f.GetTitleText and f.TitleContainer
    local header = addon.UI.SettingsPanel and addon.UI.SettingsPanel.HeaderModel
    local model = header and header.title or {}
    local titleSpec = Chrome.Spec("dialogTitle")
    if titleSpec.kind == "texture" and titleSpec.texture then
        local key = titleSpec.texture
        model = { texture = (theme.Textures and theme.Textures[key]) or key, aspect = titleSpec.aspect or 1 }
    end
    if titleSpec.kind == "texture" and not model.texture then
        titleSpec = Chrome.Resolve(titleSpec.fallback, { kind = "text" })
    end
    if titleSpec.kind == "window" and not hasPlate then
        titleSpec = { kind = "text" }
    end
    if titleSpec.kind == "texture" then
        if hasPlate then f:SetTitle("") end
        -- Over the plate: the template's TitleContainer is a child at a
        -- fixed level above its NineSlice, the level Window:GetOverlayLevel
        -- answers. This frame has no such method; a step past the plate
        -- clears both, and the flat kind has no plate to clear.
        local art = CreateFrame("Frame", nil, f)
        local over = f.TitleContainer and f.TitleContainer:GetFrameLevel()
        if f.NineSlice then
            over = math.max(over or 0, f.NineSlice:GetFrameLevel())
        end
        art:SetFrameLevel((over or f:GetFrameLevel()) + 1)
        local height = titleSpec.height or 36
        art:SetSize(titleSpec.width or (model.aspect and height * model.aspect) or 120, height)
        art:SetPoint(titleSpec.point or "TOP", f, titleSpec.point or "TOP", titleSpec.x or 0, titleSpec.y or 0)
        local tex = art:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(model.texture)
        if model.texCoord then
            tex:SetTexCoord(unpack(model.texCoord))
        end
        f._titleArt = art
    elseif titleSpec.kind == "window" then
        f:SetTitle(BRAND)
        f._title = f:GetTitleText()
    else
        local title = f:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(title, "header", m.titleFontSize)
        title:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(m.titleTop + edge))
        title:SetText(BRAND)
        title:SetTextColor(theme:GetAccentColor())
        f._title = title
        f._titleThemed = true
    end

    local function cancel()
        f:Hide()
        modalBackdrop:Hide()
        if f._onCancel then
            f._onCancel(f._data)
        end
    end

    -- The X, from the closeButton role: a window kind adopts the one the
    -- template already built and keeps its corner, so only the rest is placed
    local closeBtn, closeSpec = Controls:CreateCloseButton({ parent = f, onClick = cancel })
    if not (closeSpec and closeSpec.kind == "window") then
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    end
    f._closeBtn = closeBtn

    -- Message text. Its width is set, never anchored: a FontString with a
    -- width answers GetStringHeight for the wrapped text as soon as the text
    -- is set, and ShowDialog sizes the frame from that answer.
    local text = f:CreateFontString(nil, "ARTWORK")
    theme:ApplyFont(text, "value", m.textFontSize)
    text:SetWidth(m.width - m.contentPadding * 2)
    text:SetPoint("TOP", f, "TOP", 0, -(m.textTop + edge))
    text:SetJustifyH("CENTER")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetTextColor(1, 1, 1, 1)
    f._text = text

    -- The name prompt, on the input role: the flat bordered box, or the
    -- skin's own input art
    local editBox = Controls.CreateValueInput(f, {
        width = m.width - m.contentPadding * 2, height = m.inputHeight,
        maxLetters = 32, justifyH = "LEFT", textInset = m.inputTextInset,
    })
    editBox:SetPoint("TOP", text, "BOTTOM", 0, -m.controlGap)
    editBox:Hide()
    editBox:SetScript("OnEditFocusGained", function(self) self._setFocusLook(true) end)
    editBox:SetScript("OnEditFocusLost", function(self) self._setFocusLook(false) end)
    f._editBox = editBox

    -- List container (hidden by default, created lazily)
    f._listContainer = nil

    -- The two buttons, on the button role. The handlers read the show's
    -- callbacks at click time, so a show sets fields and no scripts.
    local buttonHeight = Controls.Metrics().button.height
    f._acceptBtn = Controls:CreateButton({
        parent = f, text = YES or "Yes", width = m.buttonMinWidth, height = buttonHeight,
        onClick = function()
            local editText = f._hasEditBox and f._editBox:GetText() or nil
            local selectedValue = f._hasList and f._listContainer and f._listContainer:GetSelectedValue() or nil
            f:Hide()
            modalBackdrop:Hide()
            if f._onAccept then
                f._onAccept(f._data, editText, selectedValue)
            end
        end,
    })
    f._cancelBtn = Controls:CreateButton({
        parent = f, text = NO or "No", width = m.buttonMinWidth, height = buttonHeight,
        onClick = cancel,
    })

    -- ESC to close (via OnKeyDown)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            cancel()
        end
    end)

    -- Store defaults for locked dialog restoration
    f._defaultOnKeyDown = f:GetScript("OnKeyDown")

    -- What is left to retint by hand: the flat title and the flat rows'
    -- marks. Buttons, the X, borders, backdrops and the scrollbar each hold
    -- their own subscription.
    theme:Subscribe("Dialog_Main", function(r, g, b)
        if f._titleThemed then
            f._title:SetTextColor(r, g, b, 1)
        end
        if f._listContainer then
            for _, item in ipairs(f._listContainer._items) do
                item._mark:SetTextColor(r, g, b, 1)
            end
        end
    end)

    dialogFrame = f
    return f, modalBackdrop
end

--------------------------------------------------------------------------------
-- Public API: Register dialog definition
--------------------------------------------------------------------------------

function Controls:RegisterDialog(name, definition)
    if not name or not definition then return end
    dialogRegistry[name] = definition
end

--------------------------------------------------------------------------------
-- Public API: Show dialog
--------------------------------------------------------------------------------

function Controls:ShowDialog(name, options)
    options = options or {}
    local def = dialogRegistry[name]
    if not def then
        -- Fallback: treat name as text if not registered
        def = { text = name }
    end

    local f, backdrop = CreateDialogFrame()
    local m = M()
    local edge, pad = f._edge, f._pad
    -- The frame closes around its content; the height a definition or a
    -- show passes is the least room inside the art, and the art adds its
    -- inset on each side
    local grow = edge * 2
    local buttonHeight = Controls.Metrics().button.height
    local body = m.textTop

    local locked = options.locked or def.locked

    -- Set text (with optional format arguments)
    local displayText = options.text or def.text or "Are you sure?"
    local formatArgs = options.formatArgs or def.formatArgs
    if formatArgs and type(formatArgs) == "table" and #formatArgs > 0 then
        displayText = string.format(displayText, unpack(formatArgs))
    end
    f._text:SetText(displayText)
    f._text:ClearAllPoints()
    f._text:SetWidth(m.width - m.contentPadding * 2)
    f._text:SetPoint("TOP", f, "TOP", 0, -(m.textTop + edge))
    body = body + (f._text:GetStringHeight() or 0)

    -- Handle edit box
    local hasEditBox = options.hasEditBox or def.hasEditBox
    if hasEditBox then
        f._editBox:Show()
        f._editBox:SetText(options.editBoxText or def.editBoxText or "")
        f._editBox:SetMaxLetters(options.maxLetters or def.maxLetters or 32)
        f._editBox:HighlightText()
        f._editBox:SetFocus()
        body = body + m.controlGap + m.inputHeight
    else
        f._editBox:Hide()
        f._editBox:SetText("")
    end

    -- Handle list options
    local listOptions = options.listOptions or def.listOptions
    local hasList = listOptions and #listOptions > 0
    if hasList then
        local listHeight = options.listHeight or def.listHeight or m.listHeight
        -- Create list container lazily
        if not f._listContainer then
            f._listContainer = CreateListContainer(f, listHeight)
        end
        f._listContainer:SetSize(m.width - m.contentPadding * 2, listHeight)
        f._listContainer:Show()

        local selectedValue = options.selectedValue or def.selectedValue
        f._listContainer:SetListOptions(listOptions, selectedValue, nil)

        body = body + m.controlGap + listHeight
    else
        if f._listContainer then
            f._listContainer:Hide()
        end
    end

    body = body + m.buttonTop + buttonHeight + m.contentPadding
    f:SetHeight(math.max(body, options.height or def.height or 0) + grow)

    -- Determine if info-only (just OK, no cancel)
    local infoOnly = locked and true or (options.infoOnly or def.infoOnly)

    -- Set button text
    local acceptText = options.acceptText or def.acceptText or (infoOnly and (OKAY or "OK")) or YES or "Yes"
    local cancelText = options.cancelText or def.cancelText or NO or "No"
    f._acceptBtn:SetText(acceptText)
    f._cancelBtn:SetText(cancelText)

    -- Calculate button widths
    local acceptWidth = options.acceptWidth or def.acceptWidth or m.buttonMinWidth
    local cancelWidth = options.cancelWidth or def.cancelWidth or m.buttonMinWidth
    f._acceptBtn:SetSize(acceptWidth, buttonHeight)
    f._cancelBtn:SetSize(cancelWidth, buttonHeight)

    -- Position buttons
    f._acceptBtn:ClearAllPoints()
    f._cancelBtn:ClearAllPoints()

    if infoOnly then
        -- Single centered button
        f._acceptBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, pad)
        f._cancelBtn:Hide()
    else
        -- Two buttons side by side, centered. The affirmative action is always
        -- the left button, across every dialog in the addon.
        local totalWidth = acceptWidth + cancelWidth + m.buttonGap
        f._acceptBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", -totalWidth/2, pad)
        f._cancelBtn:SetPoint("BOTTOMLEFT", f._acceptBtn, "BOTTOMRIGHT", m.buttonGap, 0)
        f._cancelBtn:Show()
    end

    -- Layout, top down: the message, then the list or the input under it;
    -- the buttons stand on the bottom padding and the height above closes
    -- the gaps
    if hasList then
        f._listContainer:ClearAllPoints()
        f._listContainer:SetPoint("TOP", f._text, "BOTTOM", 0, -m.controlGap)
        f._listContainer:SetPoint("LEFT", f, "LEFT", pad, 0)
        f._listContainer:SetPoint("RIGHT", f, "RIGHT", -pad, 0)
    elseif hasEditBox then
        f._editBox:ClearAllPoints()
        f._editBox:SetPoint("TOP", f._text, "BOTTOM", 0, -m.controlGap)
        f._editBox:SetPoint("LEFT", f, "LEFT", pad, 0)
        f._editBox:SetPoint("RIGHT", f, "RIGHT", -pad, 0)
    end

    -- Lockdown behavior (cannot dismiss without primary action)
    if locked then
        f._closeBtn:Hide()
        -- A locked dialog ignores ESC
        f:SetScript("OnKeyDown", function() end)
    else
        f._closeBtn:Show()
        f:SetScript("OnKeyDown", f._defaultOnKeyDown)
    end

    -- Store callbacks and data; the buttons and the X read these at click
    -- time, so nothing is rewired per show
    f._onAccept = options.onAccept
    f._onCancel = options.onCancel
    f._data = options.data
    f._hasEditBox = hasEditBox
    f._hasList = hasList

    -- Wire up Enter/Escape in edit box
    if hasEditBox then
        f._editBox:SetScript("OnEnterPressed", function()
            local editText = f._editBox:GetText()
            f:Hide()
            backdrop:Hide()
            if f._onAccept then
                f._onAccept(f._data, editText)
            end
        end)
        f._editBox:SetScript("OnEscapePressed", function()
            if not locked then
                f:Hide()
                backdrop:Hide()
                if f._onCancel then
                    f._onCancel(f._data)
                end
            end
        end)
    end

    -- Show the dialog
    backdrop:Show()
    f:Show()
    f:Raise()

    return f
end

--------------------------------------------------------------------------------
-- Public API: Hide dialog
--------------------------------------------------------------------------------

function Controls:HideDialog()
    if dialogFrame and dialogFrame:IsShown() then
        dialogFrame:Hide()
    end
    if modalBackdrop and modalBackdrop:IsShown() then
        modalBackdrop:Hide()
    end
end

--------------------------------------------------------------------------------
-- Public API: Quick confirmation dialog
--------------------------------------------------------------------------------

function Controls:ConfirmDialog(message, onAccept, onCancel)
    return self:ShowDialog(nil, {
        text = message,
        onAccept = onAccept,
        onCancel = onCancel,
    })
end

--------------------------------------------------------------------------------
-- Public API: Quick info dialog (OK only)
--------------------------------------------------------------------------------

function Controls:InfoDialog(message, onDismiss)
    return self:ShowDialog(nil, {
        text = message,
        onAccept = onDismiss,
        infoOnly = true,
    })
end

--------------------------------------------------------------------------------
-- Integration: Override addon.Dialogs to use TUI dialogs when v2 UI is active
--------------------------------------------------------------------------------

-- Store reference to original Dialogs module
local originalDialogs = addon.Dialogs

-- Create a wrapper that delegates to TUI dialogs
local function SetupDialogIntegration()
    if not originalDialogs then return end

    -- Override Show to use TUI dialogs
    local originalShow = originalDialogs.Show
    originalDialogs.Show = function(self, name, options)
        -- Check if TUI settings panel exists and use TUI dialogs
        if addon.UI and addon.UI.Controls and addon.UI.Controls.ShowDialog then
            -- Copy registrations from old system to new
            if dialogRegistry[name] == nil and originalDialogs._registry and originalDialogs._registry[name] then
                dialogRegistry[name] = originalDialogs._registry[name]
            end
            return Controls:ShowDialog(name, options)
        end
        -- Fallback to original
        return originalShow(self, name, options)
    end

    -- Override Confirm
    local originalConfirm = originalDialogs.Confirm
    originalDialogs.Confirm = function(self, message, onAccept, onCancel)
        if addon.UI and addon.UI.Controls and addon.UI.Controls.ConfirmDialog then
            return Controls:ConfirmDialog(message, onAccept, onCancel)
        end
        return originalConfirm(self, message, onAccept, onCancel)
    end

    -- Override Info
    local originalInfo = originalDialogs.Info
    originalDialogs.Info = function(self, message, onDismiss)
        if addon.UI and addon.UI.Controls and addon.UI.Controls.InfoDialog then
            return Controls:InfoDialog(message, onDismiss)
        end
        return originalInfo(self, message, onDismiss)
    end

    -- Override Hide
    local originalHide = originalDialogs.Hide
    originalDialogs.Hide = function(self)
        if addon.UI and addon.UI.Controls and addon.UI.Controls.HideDialog then
            Controls:HideDialog()
        end
        if originalHide then
            originalHide(self)
        end
    end

    -- Override Register to populate both systems
    local originalRegister = originalDialogs.Register
    originalDialogs.Register = function(self, name, definition)
        if originalRegister then
            originalRegister(self, name, definition)
        end
        -- Also register in TUI system
        if name and definition then
            dialogRegistry[name] = definition
        end
    end
end

-- Setup integration once Scoot itself finishes loading
addon.Events.OnAddonLoaded(addonName, function()
    -- Defer slightly to ensure all modules are loaded
    C_Timer.After(0, function()
        SetupDialogIntegration()
    end)
end)

--------------------------------------------------------------------------------
-- Pre-register common dialogs (mirrors dialogs.lua registrations)
--------------------------------------------------------------------------------

Controls:RegisterDialog("SCOOT_DELETE_RULE", {
    text = "Are you sure you want to delete this rule?",
    acceptText = YES or "Yes",
    cancelText = NO or "No",
})

Controls:RegisterDialog("SCOOT_RESET_DEFAULTS", {
    text = "Reset %s to all default settings and location?\n\nThis action is irreversible and requires a UI reload.",
    acceptText = "Reset & Reload",
    acceptWidth = 130,
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_UF_CONFIRM", {
    text = "Copy supported Unit Frame settings from %s to %s?",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_UF_ERROR", {
    text = "%s",
    infoOnly = true,
})

Controls:RegisterDialog("SCOOT_COPY_ACTIONBAR_CONFIRM", {
    text = "Copy settings from %s to %s?\nThis will overwrite all settings on the destination.",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_CUSTOMGROUP_CONFIRM", {
    text = "Copy settings from %s to %s?\nThis will overwrite all settings on the destination.",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_DMY_CONFIRM", {
    text = "Copy columns and sizing from Window %s to Window %s?\nThis will overwrite columns, width, height, and scale.",
    acceptText = "Copy",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COMBAT_FONT_RESTART", {
    text = "In order for Combat Font changes to take effect, you'll need to fully exit and re-open World of Warcraft.",
    infoOnly = true,
})

Controls:RegisterDialog("SCOOT_DELETE_LAYOUT", {
    text = "Delete layout '%s'?",
    acceptText = OKAY or "OK",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_CLONE_PRESET", {
    text = "Enter a name for the new layout based on %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_RENAME_LAYOUT", {
    text = "Rename layout:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_COPY_LAYOUT", {
    text = "Copy layout %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_CREATE_LAYOUT", {
    text = "Create layout:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = ACCEPT or "Accept",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_SPEC_PROFILE_RELOAD", {
    text = "Switching profiles for a spec change requires a UI reload so Blizzard can rebuild a clean baseline.\n\nReload now?",
    acceptText = "Reload",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_PROFILE_RELOAD", {
    text = "Switching profiles requires a UI reload so Blizzard can rebuild a clean baseline.\n\nReload now?",
    acceptText = "Reload",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_APPLY_PRESET", {
    text = "Enter a name for the new profile/layout based on %s:",
    hasEditBox = true,
    maxLetters = 32,
    acceptText = "Create",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_PRESET_TARGET_CHOICE", {
    text = "How would you like to apply the %s preset?",
    acceptText = "Create New Profile",
    cancelText = "Apply to Existing",
    acceptWidth = 180,
    cancelWidth = 180,
})

Controls:RegisterDialog("SCOOT_PRESET_OVERWRITE_CONFIRM", {
    text = "This will overwrite both the Edit Mode layout settings AND the " .. BRAND .. " profile for '%s'.\n\nAll existing customizations will be replaced with %s preset data.\n\nContinue?",
    acceptText = "Overwrite",
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_IMPORT_CONSOLEPORT", {
    text = "This preset includes a ConsolePort profile.\n\nImport it too?\n\n(If you select Yes, your current ConsolePort profile/settings may be overwritten.)",
    acceptText = YES or "Yes",
    cancelText = NO or "No",
})

Controls:RegisterDialog("SCOOT_DM_RESET_CONFIRM", {
    text = "You've entered an instance. Reset all Damage Meter data?",
    acceptText = "Reset",
    cancelText = "Keep Data",
})

Controls:RegisterDialog("SCOOT_EXTERNAL_LAYOUT_DELETED", {
    text = "The Edit Mode layout '%s' was deleted outside of " .. BRAND .. ".\n\nA UI reload is required to properly sync your profile state.",
    acceptText = "Reload UI",
    locked = true,
})

Controls:RegisterDialog("SCOOT_APPLYALL_FONTS", {
    text = "Set the Global Header Font to '%s' and the Global Body Font to '%s'?\n\nEvery font field holding a Global Font token follows these values. A UI reload is required to apply the change.",
    acceptText = "Apply & Reload",
    acceptWidth = 130,
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_APPLYALL_TEXTURES", {
    text = "Set the Global Bar Texture to '%s'?\n\nEvery texture field holding the Global Bar Texture token follows this value. A UI reload is required to apply the change.",
    acceptText = "Apply & Reload",
    acceptWidth = 130,
    cancelText = CANCEL or "Cancel",
})

Controls:RegisterDialog("SCOOT_SELECT_EXISTING_LAYOUT", {
    text = "Select an existing layout to apply the %s preset to:",
    acceptText = "Apply",
    cancelText = CANCEL or "Cancel",
    listHeight = 150,
})
