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
-- above it when the screen has no room below.
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
--
-- Returns a handle: Open, Close, Toggle, IsShown, Destroy, frame.
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

    function list:IsShown()
        return popup:IsShown()
    end

    function list:Close()
        popup:Hide()
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

    -- A row's text and wash for its state. Under the role's colors the
    -- chosen row keeps its color under the cursor and only the wash comes
    -- up, as Blizzard's own list does; flat lifts both.
    local function Paint(btn, hover)
        local selected = btn._key == getSelectedKey()
        if colors then
            local state = btn._inert and "disabled" or (selected and "selected") or (hover and "hover") or "normal"
            btn._text:SetTextColor(Chrome.Color(colors[state] or colors.normal or "white"))
            btn._bg:SetShown(hover and not btn._inert)
            return
        end
        local accentR, accentG, accentB = theme:GetAccentColor()
        if btn._inert then
            local dr, dg, dbl = theme:GetDimTextColor()
            btn._text:SetTextColor(dr, dg, dbl, 0.6)
        elseif selected then
            btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.35 or 0.3)
            btn._text:SetTextColor(accentR, accentG, accentB, 1)
        else
            btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.15 or 0)
            btn._text:SetTextColor(1, 1, 1, 1)
        end
    end

    function list:Open()
        if opts.levelFrom then
            popup:SetFrameLevel(math.max(100, opts.levelFrom:GetFrameLevel() + 10))
        end
        popup:ClearAllPoints()

        local kList = getKeys()
        local vMap = getValues()
        local totalHeight = (#kList * optionHeight) + padT + padB
        local width = opts.width
        if not width then
            width = anchor:GetWidth()
            if width < 60 then width = 150 end
        end

        popup:SetSize(width, totalHeight)

        -- Open below the anchor when there is room, above otherwise
        local anchorBottom = select(2, anchor:GetCenter()) - (anchor:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = anchorBottom * scale

        if spaceBelow > totalHeight + 10 then
            popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        else
            popup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
        end

        -- Clear existing option buttons
        for _, btn in ipairs(popup._optionButtons) do
            if btn._infoIcon then
                btn._infoIcon:Cleanup()
            end
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(popup._optionButtons)

        -- Text moves right when any option carries an info icon
        local hasAnyInfoIcons = infoIcons and next(infoIcons)
        local textLeftOffset = hasAnyInfoIcons and 28 or textInset

        for i, key in ipairs(kList) do
            local optBtn = CreateFrame("Button", nil, popup)
            optBtn:SetSize(width - padL - padR, optionHeight)
            optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", padL, -padT - ((i - 1) * optionHeight))
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

            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            theme:ApplyFont(optText, fontRole, fontSize)
            optText:SetPoint("LEFT", optBtn, "LEFT", textLeftOffset, 0)
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
                    onSelect(btn._key)
                    list:Close()
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                end)
            end

            table.insert(popup._optionButtons, optBtn)
        end

        dismiss:Show()
        dismiss:SetFrameLevel(popup:GetFrameLevel() - 1)

        popup:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
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
        for _, btn in ipairs(popup._optionButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
        popup:Hide()
        popup:SetParent(nil)
    end

    return list
end
