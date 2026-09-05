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
-- and reports a choice through onSelect.
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
    local anchor = opts.anchor
    local optionHeight = opts.optionHeight or 26
    local fontSize = opts.fontSize or 12
    local textInset = opts.textInset or 12
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

    -- Popup chrome: solid fill plus a 1px accent border
    Controls.AddBackground(popup, { alpha = 0.98 })
    popup._border = Controls.CreateBorder(popup, { alpha = 0.8 })

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

    function list:Open()
        if opts.levelFrom then
            popup:SetFrameLevel(math.max(100, opts.levelFrom:GetFrameLevel() + 10))
        end
        popup:ClearAllPoints()

        local kList = getKeys()
        local vMap = getValues()
        local selectedKey = getSelectedKey()
        local optionPadding = 4
        local totalHeight = (#kList * optionHeight) + (optionPadding * 2)
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
            popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        else
            popup:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
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

        local accentR, accentG, accentB = theme:GetAccentColor()

        -- Text moves right when any option carries an info icon
        local hasAnyInfoIcons = infoIcons and next(infoIcons)
        local textLeftOffset = hasAnyInfoIcons and 28 or textInset

        for i, key in ipairs(kList) do
            local optBtn = CreateFrame("Button", nil, popup)
            optBtn:SetSize(width - 2, optionHeight)
            optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -optionPadding - ((i - 1) * optionHeight))
            optBtn:EnableMouse(true)
            optBtn:RegisterForClicks("AnyUp")

            local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            optBg:SetAllPoints()
            optBg:SetColorTexture(0, 0, 0, 0)
            optBtn._bg = optBg

            local optText = optBtn:CreateFontString(nil, "OVERLAY")
            optText:SetFont(theme:GetFont("VALUE"), fontSize, "")
            optText:SetPoint("LEFT", optBtn, "LEFT", textLeftOffset, 0)
            optText:SetPoint("RIGHT", optBtn, "RIGHT", -textInset, 0)
            optText:SetJustifyH("LEFT")
            optText:SetText(vMap[key] or key)
            optBtn._text = optText
            optBtn._key = key

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

            local isSelected = (key == selectedKey)
            local inert = isInert and isInert(key)
            if inert then
                local dr, dg, dbl = theme:GetDimTextColor()
                optText:SetTextColor(dr, dg, dbl, 0.6)
            elseif isSelected then
                optBg:SetColorTexture(accentR, accentG, accentB, 0.3)
                optText:SetTextColor(accentR, accentG, accentB, 1)
            else
                optText:SetTextColor(1, 1, 1, 1)
            end

            if inert then
                -- Listed, not selectable: no hover fill, click ignored.
                optBtn:SetScript("OnClick", function() end)
            else
                optBtn:SetScript("OnEnter", function(btn)
                    if btn._key ~= getSelectedKey() then
                        btn._bg:SetColorTexture(accentR, accentG, accentB, 0.15)
                    else
                        btn._bg:SetColorTexture(accentR, accentG, accentB, 0.35)
                    end
                end)
                optBtn:SetScript("OnLeave", function(btn)
                    if btn._key == getSelectedKey() then
                        btn._bg:SetColorTexture(accentR, accentG, accentB, 0.3)
                    else
                        btn._bg:SetColorTexture(0, 0, 0, 0)
                    end
                end)

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
