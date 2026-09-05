-- IconPicker.lua - Reusable icon style selection popup
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local PICKER_WIDTH = 440
local PICKER_HEIGHT = 340
local PADDING = 12

-- Icon grid layout (no text labels, just icons)
local ICONS_PER_ROW = 7
local ICON_BUTTON_SIZE = 36
local ICON_BUTTON_SPACING = 6
local ICON_PREVIEW_SIZE = 28  -- Atlas rendered inside button

-- Animated tab layout (wider buttons for animation previews + labels)
local ANIM_ICONS_PER_ROW = 3
local ANIM_ICON_BUTTON_SIZE = 90
local ANIM_ICON_BUTTON_SPACING = 8
local ANIM_ICON_PREVIEW_SIZE = 28

-- Fallback accent colors

--------------------------------------------------------------------------------
-- Icon Categories
--------------------------------------------------------------------------------

local SIMPLE_ICONS = {
    -- Special: use the spell's own icon
    { key = "spell" },
    -- Circles
    { key = "CircleMask" },
    { key = "border:CircleMask" },
    { key = "common-radiobutton-circle" },
    { key = "common-radiobutton-dot" },
    -- Squares
    { key = "SquareMask" },
    { key = "border:SquareMask" },
    { key = "talents-node-square-gray" },
    { key = "wide:talents-node-square-gray" },
    { key = "UI-Frame-IconMask" },
    -- Diamonds
    { key = "activities-complete-diamond" },
    { key = "activities-incomplete-diamond" },
    -- Stars
    { key = "Bonus-Objective-Star" },
    { key = "ChallengeMode-SpikeyStar" },
    { key = "campcollection-icon-star" },
    -- Plus / Cross
    { key = "common-icon-plus" },
    -- Rings
    { key = "Azerite-CenterTrait-Ring" },
    -- Coins (from Blizzard tooltip system)
    { key = "coin-gold" },
    { key = "coin-silver" },
    { key = "coin-copper" },
    -- Crafting Quality Tiers
    { key = "Professions-ChatIcon-Quality-Tier1" },
    { key = "Professions-ChatIcon-Quality-Tier2" },
    { key = "Professions-ChatIcon-Quality-Tier3" },
    { key = "Professions-ChatIcon-Quality-Tier4" },
    { key = "Professions-ChatIcon-Quality-Tier5" },
    -- Misc Atlas
    { key = "bags-glow-white" },
    { key = "wide:bags-glow-white" },
    { key = "checkmark-minimal" },
    { key = "waypoint-mappin-minimap-tracked" },
    { key = "levelup-dot-gold" },
}

-- Animated icons (built lazily from AnimEngine registry)
local ANIMATED_ICONS = {}
local function BuildAnimatedIconList()
    if #ANIMATED_ICONS > 0 then return end
    local AE = addon.AuraTracking and addon.AuraTracking.AnimEngine
    if not AE then return end
    for _, def in ipairs(AE.GetAllDefs()) do
        table.insert(ANIMATED_ICONS, { key = "anim:" .. def.id, label = def.label })
    end
end

local TABS = {
    { key = "simple", label = "Simple", icons = SIMPLE_ICONS },
    { key = "animated", label = "Animated", icons = ANIMATED_ICONS },
}

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------

local pickerFrame = nil
local pickerCallback = nil
local pickerAnchor = nil
local pickerOptions = nil
local selectedTab = "simple"
local currentSelection = nil

-- Stop all running animation previews in the picker
local function StopAllAnimatedPreviews()
    if not pickerFrame then return end
    local AE = addon.AuraTracking and addon.AuraTracking.AnimEngine
    if not AE then return end
    for _, btn in ipairs(pickerFrame.IconButtons) do
        if btn._animCtrl then
            AE.Release(btn)
            btn._animCtrl = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Close Function
--------------------------------------------------------------------------------

local function CloseIconPicker()
    StopAllAnimatedPreviews()
    if pickerFrame then
        pickerFrame:Hide()
    end
    pickerCallback = nil
    pickerAnchor = nil
    pickerOptions = nil
end

--------------------------------------------------------------------------------
-- Picker Frame Creation
--------------------------------------------------------------------------------

local function CreateIconPicker()
    if pickerFrame then return pickerFrame end

    -- Content area width
    local contentWidth = (ICON_BUTTON_SIZE * ICONS_PER_ROW) + (ICON_BUTTON_SPACING * (ICONS_PER_ROW - 1)) + (PADDING * 2)

    local frame = Controls.CreatePickerShell({
        name = "ScootIconPickerFrame",
        width = PICKER_WIDTH,
        height = PICKER_HEIGHT,
        contentWidth = contentWidth,
        title = "Select Icon Style",
        onClose = CloseIconPicker,
        tabs = TABS,
        getSelectedTab = function() return selectedTab end,
        onTabSelected = function(key) selectedTab = key end,
        onHide = StopAllAnimatedPreviews,
    })

    -- Button pool
    frame.IconButtons = {}

    -- Populate icon grid
    function frame:PopulateContent()
        -- Stop any running animated previews before repopulating
        StopAllAnimatedPreviews()

        local currentTab = nil
        for _, tabData in ipairs(TABS) do
            if tabData.key == selectedTab then
                currentTab = tabData
                break
            end
        end
        if not currentTab then return end

        -- Build animated icon list on first visit
        if selectedTab == "animated" then
            BuildAnimatedIconList()
        end

        local icons = currentTab.icons
        if pickerOptions and pickerOptions.hideSpellEntry and selectedTab == "simple" then
            local filtered = {}
            for _, iconData in ipairs(icons) do
                if iconData.key ~= "spell" then
                    table.insert(filtered, iconData)
                end
            end
            icons = filtered
        end
        local contentFrame = self.Content
        local ar, ag, ab = self._accentR, self._accentG, self._accentB

        -- Tab-dependent layout values
        local isAnimTab = (selectedTab == "animated")
        local colCount = isAnimTab and ANIM_ICONS_PER_ROW or ICONS_PER_ROW
        local btnW = isAnimTab and ANIM_ICON_BUTTON_SIZE or ICON_BUTTON_SIZE
        local btnH = isAnimTab and ANIM_ICON_BUTTON_SIZE or ICON_BUTTON_SIZE
        local btnSpacing = isAnimTab and ANIM_ICON_BUTTON_SPACING or ICON_BUTTON_SPACING

        -- Calculate content height (selector at top of animated tab)
        local numRows = math.ceil(#icons / colCount)
        local gridHeight = (numRows * btnH) + ((numRows - 1) * btnSpacing)
        local contentHeight = gridHeight + PADDING
        contentFrame:SetHeight(contentHeight)

        -- Show/hide scrollbar
        local sf = self.ScrollFrame
        local sb = self._scrollBar
        if sb and sf then
            local visibleH = sf:GetHeight()
            if contentHeight > visibleH then
                sb:Show()
                if sb._trackBg then sb._trackBg:Show() end
            else
                sb:Hide()
                if sb._trackBg then sb._trackBg:Hide() end
            end
        end

        -- Hide existing buttons
        for _, btn in ipairs(self.IconButtons) do
            btn:Hide()
        end

        local lFont = (GetTheme() and GetTheme().GetFont and GetTheme():GetFont("LABEL")) or "Fonts\\FRIZQT__.TTF"

        -- Create/reuse buttons
        for i, iconData in ipairs(icons) do
            local btn = self.IconButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, contentFrame)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                -- Background (selection/hover)
                local btnBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
                btnBg:SetAllPoints()
                btnBg:SetColorTexture(0, 0, 0, 0)
                btn._bg = btnBg

                -- Icon preview texture (used by Simple tab, hidden for Animated)
                local preview = btn:CreateTexture(nil, "ARTWORK")
                preview:SetSize(ICON_PREVIEW_SIZE, ICON_PREVIEW_SIZE)
                preview:SetPoint("CENTER")
                btn._preview = preview

                self.IconButtons[i] = btn
            end

            -- Resize button for current tab
            btn:SetSize(btnW, btnH)

            -- Position in grid (offset below selector on animated tab)
            local col = (i - 1) % colCount
            local row = math.floor((i - 1) / colCount)
            local xOff = col * (btnW + btnSpacing)
            local yOff = -(row * (btnH + btnSpacing))
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", xOff, yOff)

            local iconKey = iconData.key

            if isAnimTab then
                -- Animated tab: live preview + label
                btn._preview:Hide()

                -- Ensure preview frame exists
                if not btn._previewFrame then
                    local pf = CreateFrame("Frame", nil, btn)
                    pf:SetSize(ANIM_ICON_PREVIEW_SIZE, ANIM_ICON_PREVIEW_SIZE)
                    pf:SetPoint("CENTER", btn, "CENTER", 0, 8)
                    pf:EnableMouse(false)
                    btn._previewFrame = pf
                end
                btn._previewFrame:Show()

                -- Ensure label exists
                if not btn._label then
                    local lbl = btn:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(lFont, 9, "")
                    lbl:SetPoint("BOTTOM", btn, "BOTTOM", 0, 6)
                    lbl:SetTextColor(0.65, 0.65, 0.65, 1)
                    btn._label = lbl
                end
                btn._label:SetText(iconData.label or iconKey)
                btn._label:Show()

                -- Start live animation preview
                local AE = addon.AuraTracking and addon.AuraTracking.AnimEngine
                if AE then
                    local animId = iconKey:sub(6)  -- strip "anim:" prefix
                    local ctrl = AE.Acquire(btn, btn._previewFrame)
                    if ctrl then
                        ctrl:Configure(animId, ANIM_ICON_PREVIEW_SIZE)
                        ctrl:SetColor(0.8, 0.8, 0.8, 1)
                        ctrl:Play()
                        btn._animCtrl = ctrl
                    end
                end
            else
                -- Simple tab: static icon preview
                if btn._previewFrame then btn._previewFrame:Hide() end
                if btn._label then btn._label:Hide() end

                local preview = btn._preview
                preview:SetSize(ICON_PREVIEW_SIZE, ICON_PREVIEW_SIZE)
                preview:ClearAllPoints()
                preview:SetPoint("CENTER")
                preview:Show()

                -- Reset border backing texture from previous use (pooled buttons)
                if btn._borderTex then btn._borderTex:Hide() end

                -- Parse prefix variants
                local isBordered = iconKey:sub(1, 7) == "border:"
                local isWide = iconKey:sub(1, 5) == "wide:"
                local baseKey = iconKey
                if isBordered then
                    baseKey = iconKey:sub(8)
                elseif isWide then
                    baseKey = iconKey:sub(6)
                end

                if isBordered then
                    -- Same-shape black backing for 1px border effect
                    if not btn._borderTex then
                        local bt = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
                        bt:SetPoint("CENTER")
                        btn._borderTex = bt
                    end
                    -- Use the same atlas colored black for matching silhouette
                    local borderOk = pcall(btn._borderTex.SetAtlas, btn._borderTex, baseKey)
                    if not borderOk then
                        btn._borderTex:SetColorTexture(0, 0, 0, 1)
                    end
                    btn._borderTex:SetDesaturated(true)
                    btn._borderTex:SetVertexColor(0, 0, 0, 1)
                    btn._borderTex:SetSize(ICON_PREVIEW_SIZE, ICON_PREVIEW_SIZE)
                    btn._borderTex:Show()
                    preview:SetSize(ICON_PREVIEW_SIZE - 2, ICON_PREVIEW_SIZE - 2)
                    local atlasOk = pcall(preview.SetAtlas, preview, baseKey)
                    if atlasOk then
                        preview:SetDesaturated(true)
                        preview:SetVertexColor(0.8, 0.8, 0.8, 1)
                    else
                        preview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        preview:SetDesaturated(true)
                        preview:SetVertexColor(0.5, 0.5, 0.5, 1)
                    end
                elseif isWide then
                    -- 3:1 aspect ratio preview
                    local wideH = math.ceil(ICON_PREVIEW_SIZE / 3)
                    preview:SetSize(ICON_PREVIEW_SIZE, wideH)
                    local atlasOk = pcall(preview.SetAtlas, preview, baseKey)
                    if atlasOk then
                        preview:SetDesaturated(true)
                        preview:SetVertexColor(0.8, 0.8, 0.8, 1)
                    else
                        preview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        preview:SetDesaturated(true)
                        preview:SetVertexColor(0.5, 0.5, 0.5, 1)
                    end
                elseif iconKey == "spell" then
                    preview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    preview:SetDesaturated(true)
                    preview:SetVertexColor(0.8, 0.8, 0.8, 1)
                elseif iconKey:sub(1, 5) == "file:" then
                    local path = iconKey:sub(6)
                    preview:SetTexture(path)
                    preview:SetDesaturated(true)
                    preview:SetVertexColor(0.8, 0.8, 0.8, 1)
                else
                    local atlasOk = pcall(preview.SetAtlas, preview, iconKey)
                    if atlasOk then
                        preview:SetDesaturated(true)
                        preview:SetVertexColor(0.8, 0.8, 0.8, 1)
                    else
                        preview:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                        preview:SetDesaturated(true)
                        preview:SetVertexColor(0.5, 0.5, 0.5, 1)
                    end
                end
            end

            -- Highlight if this is the current selection
            local isSelected = (currentSelection == iconKey)
            if isSelected then
                btn._bg:SetColorTexture(ar, ag, ab, 0.25)
                if not isAnimTab then
                    btn._preview:SetVertexColor(1, 1, 1, 1)
                end
            else
                btn._bg:SetColorTexture(0, 0, 0, 0)
            end

            btn._iconKey = iconKey

            -- Hover
            btn:SetScript("OnEnter", function(self)
                if currentSelection ~= self._iconKey then
                    self._bg:SetColorTexture(ar, ag, ab, 0.12)
                else
                    self._bg:SetColorTexture(ar, ag, ab, 0.35)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if currentSelection == self._iconKey then
                    self._bg:SetColorTexture(ar, ag, ab, 0.25)
                else
                    self._bg:SetColorTexture(0, 0, 0, 0)
                end
            end)

            -- Click to select
            btn:SetScript("OnClick", function(self)
                currentSelection = self._iconKey
                if pickerCallback then
                    pickerCallback(self._iconKey)
                end
                CloseIconPicker()
            end)

            btn:Show()
        end

    end


    frame:Hide()
    pickerFrame = frame
    return frame
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- options (all optional):
--   hideSpellEntry  : omit the "use the spell's own icon" entry from the
--                     Simple tab (callers whose shapes are always atlas art)
--   hideAnimatedTab : omit the Animated tab entirely
function addon.ShowIconPicker(anchor, currentValue, callback, options)
    local frame = CreateIconPicker()
    if not frame then return end

    currentSelection = currentValue
    pickerCallback = callback
    pickerAnchor = anchor
    pickerOptions = options

    -- Build working tabs (Animated omitted on request)
    local workingTabs = {}
    for _, tabData in ipairs(TABS) do
        if not (tabData.key == "animated" and options and options.hideAnimatedTab) then
            workingTabs[#workingTabs + 1] = tabData
        end
    end
    frame._workingTabs = workingTabs

    -- Position relative to anchor or screen center
    frame:ClearAllPoints()
    if anchor then
        local anchorBottom = anchor:GetBottom()
        local screenHeight = UIParent:GetHeight()
        local spaceBelow = anchorBottom or (screenHeight / 2)

        if spaceBelow > PICKER_HEIGHT + 20 then
            frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        else
            frame:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Reset scroll position
    if frame.ScrollFrame then
        frame.ScrollFrame:SetVerticalScroll(0)
    end

    selectedTab = "simple"
    frame:UpdateTabs()
    frame:UpdateTabVisuals()
    frame:PopulateContent()
    frame:Show()
    frame:Raise()
end

function addon.CloseIconPicker()
    CloseIconPicker()
end

-- Backward compatibility aliases
addon.ShowAuraIconPicker = addon.ShowIconPicker
addon.CloseAuraIconPicker = addon.CloseIconPicker
