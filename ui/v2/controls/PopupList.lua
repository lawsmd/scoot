-- PopupList.lua - Shared floating option list for selector-family controls
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

-- The floating option list every selector-family control opens: one frame on
-- UIParent above everything, rebuilt from the caller's keys on every open,
-- dismissed by ESC or any click outside. The caller owns the current value
-- and the field that displays it; the list reads state through the callbacks
-- and reports a choice through onSelect. The list opens under the field, and
-- above it when the screen has no room below; OpenAt and OpenAtCursor open
-- it at a point instead, for a context menu on a row.
--
-- The popupList chrome role decides the draw. Flat is the framework's own:
-- a solid fill inside the accent border, the chosen row on an accent wash
-- with its text in the accent, the row under the cursor on a fainter wash.
-- An atlas kind is a skin's box stretched over the rows, reaching past the
-- frame by spec.reach where the art carries a margin, with the rows kept off
-- the edge by spec.padding; the rows are then text alone, colored by
-- spec.labelColors (normal, hover, selected, disabled), and spec.highlight,
-- an atlas at an alpha, lies over the row under the cursor. A skin that
-- names metrics.popupList (optionHeight, fontSize, textInset, fontRole, gap)
-- puts every list on those numbers over the caller's, so the rows read the
-- same under every field.
--
-- Three modes beyond the single choice. multiSelect draws a check mark
-- before each row and keeps the list open: a click flips the row and
-- reports it through onToggle, and isChecked says which rows are on.
-- filter puts a box above the rows that narrows them to the labels holding
-- the typed text; Enter takes the one row left, Escape closes. maxRows caps
-- the rows drawn, for a list long enough to need the filter.
--
-- opts:
--   anchor          the field frame the list opens against; also the width
--                   source when width is nil
--   width           fixed width; nil measures anchor:GetWidth() at open and
--                   falls back to 150 while the anchor has no layout yet
--   optionHeight    default 26
--   fontSize        option label size (default 12)
--   textInset       option label inset from both edges (default 12)
--   levelFrom       frame tracked at open so the list clears a host that sits
--                   at or above this strata's base level (a Flyout raises
--                   itself); nil keeps the fixed base level
--   getKeys         function() -> ordered key list
--   getValues       function() -> key-to-label map
--   getSelectedKey  function() -> the current key, for the highlight
--   isInert         function(key) -> true lists the option dimmed, with hover
--                   and click ignored
--   infoIcons       key -> { tooltipTitle, tooltipText } info icon per option
--   onSelect        function(key) -> commit; the list closes and plays the
--                   click sound afterwards
--   multiSelect     true for check rows; then isChecked(key) and
--                   onToggle(key, checked)
--   filter          true for the box above the rows; filterLetters caps it
--                   (default 32)
--   maxRows         the most rows drawn
--
-- Returns a handle: Open, OpenAt(x, y), OpenAtCursor, Close, Toggle,
-- IsShown, Destroy, frame.
function Controls.CreatePopupList(opts)
    local theme = GetTheme()
    local Chrome = addon.UI.Chrome
    local spec = Chrome.Spec("popupList")
    local art = spec.kind ~= "flat"
    local pm = Controls.Metrics().popupList or {}
    local anchor = opts.anchor
    local optionHeight = pm.optionHeight or opts.optionHeight or 26
    local fontSize = pm.fontSize or opts.fontSize or 12
    local textInset = pm.textInset or opts.textInset or 12
    local fontRole = pm.fontRole or "value"
    -- The room between the field's edge and the list's
    local gap = pm.gap or 2
    local getKeys = opts.getKeys
    local getValues = opts.getValues
    local getSelectedKey = opts.getSelectedKey
    local isInert = opts.isInert
    local infoIcons = opts.infoIcons
    local onSelect = opts.onSelect
    local multi = opts.multiSelect and true or false
    local isChecked = opts.isChecked
    local onToggle = opts.onToggle
    local withFilter = opts.filter and true or false
    local maxRows = opts.maxRows
    local filterHeight = pm.filterHeight or 22

    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(100)
    popup:SetClampedToScreen(true)
    popup:Hide()

    -- What the rows keep off the frame's edge: the role's padding, else the
    -- flat draw's one unit inside the border across and four above and below
    local padding = spec.padding
    if type(padding) == "number" then
        padding = { left = padding, right = padding, top = padding, bottom = padding }
    elseif type(padding) ~= "table" then
        padding = { left = 1, right = 1, top = 4, bottom = 4 }
    end
    local padL, padR = padding.left or 0, padding.right or 0
    local padT, padB = padding.top or 0, padding.bottom or 0

    if art then
        popup._backdrop = Chrome.Backdrop("popupList", popup)
    else
        -- Popup chrome: solid fill plus a 1px accent border
        Controls.AddBackground(popup, { alpha = 0.98 })
        popup._border = Controls.CreateBorder(popup, { alpha = 0.8 })
    end
    local colors = art and spec.labelColors or nil
    local highlight = art and spec.highlight or nil

    popup._optionButtons = {}

    local list = { frame = popup }
    local dismiss
    local filterBox
    local filterText = ""

    function list:IsShown()
        return popup:IsShown()
    end

    function list:Close()
        popup:Hide()
        if filterBox then filterBox:ClearFocus() end
        if dismiss then
            dismiss:Hide()
        end
    end

    dismiss = Controls.AttachDismissOnClickOutside(function()
        list:Close()
    end)

    -- ESC key handling
    addon.EscapeKey.Attach(popup, function()
        list:Close()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)

    local function RowOn(btn)
        if multi then
            return (isChecked and isChecked(btn._key)) and true or false
        end
        return btn._key == getSelectedKey()
    end

    -- A row's text and wash for its state. Under the role's colors the
    -- chosen row keeps its color under the cursor and only the wash comes
    -- up, as Blizzard's own list does; flat lifts both.
    local function Paint(btn, hover)
        local selected = RowOn(btn)
        if btn._check then
            btn._check:SetText(selected and "[x]" or "[ ]")
        end
        if colors then
            local state = btn._inert and "disabled" or (selected and "selected") or (hover and "hover") or "normal"
            local r, g, b, a = Chrome.Color(colors[state] or colors.normal or "white")
            btn._text:SetTextColor(r, g, b, a)
            if btn._check then btn._check:SetTextColor(r, g, b, a) end
            btn._bg:SetShown(hover and not btn._inert)
            return
        end
        local accentR, accentG, accentB = theme:GetAccentColor()
        if btn._inert then
            local dr, dg, dbl = theme:GetDimTextColor()
            btn._text:SetTextColor(dr, dg, dbl, 0.6)
            if btn._check then btn._check:SetTextColor(dr, dg, dbl, 0.6) end
        elseif selected then
            btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.35 or 0.3)
            btn._text:SetTextColor(accentR, accentG, accentB, 1)
            if btn._check then btn._check:SetTextColor(accentR, accentG, accentB, 1) end
        else
            btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.15 or 0)
            btn._text:SetTextColor(1, 1, 1, 1)
            if btn._check then btn._check:SetTextColor(1, 1, 1, 1) end
        end
    end

    local function ClearRows()
        for _, btn in ipairs(popup._optionButtons) do
            if btn._infoIcon then
                btn._infoIcon:Cleanup()
            end
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(popup._optionButtons)
    end

    local function Matches(label)
        if filterText == "" then return true end
        return string.find(string.lower(tostring(label)), string.lower(filterText), 1, true) ~= nil
    end

    -- The rows for the keys the filter leaves, from the top down; returns
    -- the frame's height for them
    local function BuildRows(width)
        ClearRows()
        local vMap = getValues()
        local keys = {}
        for _, key in ipairs(getKeys()) do
            if Matches(vMap[key] or key) then
                keys[#keys + 1] = key
                if maxRows and #keys >= maxRows then break end
            end
        end

        local top = padT + (withFilter and (filterHeight + gap) or 0)
        -- Text moves right when any option carries an info icon
        local hasAnyInfoIcons = infoIcons and next(infoIcons)
        local textLeftOffset = hasAnyInfoIcons and 28 or textInset
        local checkWidth = multi and (fontSize * 2 + 6) or 0

        for i, key in ipairs(keys) do
            local optBtn = CreateFrame("Button", nil, popup)
            optBtn:SetSize(width - padL - padR, optionHeight)
            optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", padL, -top - ((i - 1) * optionHeight))
            optBtn:EnableMouse(true)
            optBtn:RegisterForClicks("AnyUp")

            local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            optBg:SetAllPoints()
            if highlight then
                optBg:SetAtlas(highlight.atlas)
                optBg:SetAlpha(highlight.alpha or 1)
                optBg:Hide()
            else
                optBg:SetColorTexture(0, 0, 0, 0)
            end
            optBtn._bg = optBg

            if multi then
                local check = optBtn:CreateFontString(nil, "OVERLAY")
                theme:ApplyFont(check, fontRole, fontSize)
                check:SetPoint("LEFT", optBtn, "LEFT", textLeftOffset, 0)
                check:SetJustifyH("LEFT")
                optBtn._check = check
            end

            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            theme:ApplyFont(optText, fontRole, fontSize)
            optText:SetPoint("LEFT", optBtn, "LEFT", textLeftOffset + checkWidth, 0)
            optText:SetPoint("RIGHT", optBtn, "RIGHT", -textInset, 0)
            optText:SetJustifyH("LEFT")
            optText:SetText(vMap[key] or key)
            optBtn._text = optText
            optBtn._key = key
            optBtn._inert = (isInert and isInert(key)) and true or false

            if infoIcons and infoIcons[key] then
                local iconData = infoIcons[key]
                local infoIcon = Controls:CreateInfoIcon({
                    parent = optBtn,
                    tooltipText = iconData.tooltipText,
                    tooltipTitle = iconData.tooltipTitle,
                    size = 14,
                })
                if infoIcon then
                    infoIcon:SetPoint("LEFT", optBtn, "LEFT", 8, 0)
                    optBtn._infoIcon = infoIcon
                end
            end

            Paint(optBtn, false)

            if optBtn._inert then
                -- Listed, not selectable: no hover, click ignored.
                optBtn:SetScript("OnClick", function() end)
            else
                optBtn:SetScript("OnEnter", function(btn) Paint(btn, true) end)
                optBtn:SetScript("OnLeave", function(btn) Paint(btn, false) end)
                optBtn:SetScript("OnClick", function(btn)
                    if multi then
                        local now = not RowOn(btn)
                        if onToggle then onToggle(btn._key, now) end
                        Paint(btn, true)
                        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                        return
                    end
                    onSelect(btn._key)
                    list:Close()
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                end)
            end

            table.insert(popup._optionButtons, optBtn)
        end

        local totalHeight = top + (#keys * optionHeight) + padB
        popup:SetHeight(totalHeight)
        return totalHeight
    end

    local function EnsureFilterBox(width)
        if filterBox then
            filterBox:SetWidth(width - padL - padR - 8)
            return
        end
        filterBox = Controls.CreateValueInput(popup, {
            width = width - padL - padR - 8, height = filterHeight - 4,
            maxLetters = opts.filterLetters or 32, justifyH = "LEFT", textInset = 6,
        })
        filterBox:SetPoint("TOPLEFT", popup, "TOPLEFT", padL + 4, -padT - 2)
        filterBox:SetScript("OnEditFocusGained", function(self) self._setFocusLook(true) end)
        filterBox:SetScript("OnEditFocusLost", function(self) self._setFocusLook(false) end)
        filterBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            filterText = self:GetText() or ""
            BuildRows(popup:GetWidth())
        end)
        filterBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            list:Close()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end)
        filterBox:SetScript("OnEnterPressed", function()
            local only
            for _, btn in ipairs(popup._optionButtons) do
                if not btn._inert then
                    if only then only = nil break end
                    only = btn
                end
            end
            if only then only:Click() end
        end)
    end

    -- Where the list stands: under the anchor with room below it, above it
    -- otherwise; or at a point, its top-left corner there, lifted when it
    -- would run off the bottom
    local function Place(totalHeight, at)
        popup:ClearAllPoints()
        if at then
            if at.y - totalHeight < 0 then
                popup:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", at.x, at.y)
            else
                popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at.x, at.y)
            end
            return
        end
        local anchorBottom = select(2, anchor:GetCenter()) - (anchor:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = anchorBottom * scale
        if spaceBelow > totalHeight + 10 then
            popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        else
            popup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
        end
    end

    local function OpenWith(at)
        if opts.levelFrom then
            popup:SetFrameLevel(math.max(100, opts.levelFrom:GetFrameLevel() + 10))
        end
        local width = opts.width
        if not width then
            width = anchor and anchor:GetWidth() or 0
            if width < 60 then width = 150 end
        end
        popup:SetWidth(width)
        filterText = ""
        if withFilter then
            EnsureFilterBox(width)
            filterBox:SetText("")
        end
        local totalHeight = BuildRows(width)
        Place(totalHeight, at)

        dismiss:Show()
        dismiss:SetFrameLevel(popup:GetFrameLevel() - 1)

        popup:Show()
        if withFilter then filterBox:SetFocus() end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    end

    function list:Open()
        OpenWith(nil)
    end

    -- x and y in UIParent's space, from its bottom-left corner
    function list:OpenAt(x, y)
        OpenWith({ x = x, y = y })
    end

    function list:OpenAtCursor()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        OpenWith({ x = x / scale, y = y / scale })
    end

    function list:Toggle()
        if popup:IsShown() then
            list:Close()
        else
            list:Open()
        end
    end

    -- Eager teardown for owners that rebuild on re-render
    function list:Destroy()
        list:Close()
        dismiss:SetParent(nil)
        ClearRows()
        if filterBox then
            filterBox:Hide()
            filterBox:SetParent(nil)
            filterBox = nil
        end
        popup:Hide()
        popup:SetParent(nil)
    end

    return list
end
