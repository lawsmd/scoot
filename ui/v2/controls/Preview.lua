-- Preview.lua - Inline preview row for Custom Groups and Class Auras settings
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

local PREVIEW_ROW_HEIGHT = 76
local PREVIEW_ICON_DISPLAY_SIZE = 36
local PREVIEW_BAR_MAX_WIDTH = 120
local PREVIEW_BAR_MAX_HEIGHT = 24
local PREVIEW_PADDING = 12
local PREVIEW_BORDER = 1
local ICON_TEXCOORD_INSET = 0.07
local PREVIEW_MIN_FONT_SIZE = 6
local CA_TEXT_MAX_SIZE = 36

local CA_INSIDE_OFFSETS = {
    TOPLEFT = { 2, -2 }, TOP = { 0, -2 }, TOPRIGHT = { -2, -2 },
    LEFT = { 2, 0 }, CENTER = { 0, 0 }, RIGHT = { -2, 0 },
    BOTTOMLEFT = { 2, 2 }, BOTTOM = { 0, 2 }, BOTTOMRIGHT = { -2, 2 },
}
local CA_GAP = 2

local function clampBarOffsetX(v) return math.max(-20, math.min(20, v or 0)) end
local function clampBarOffsetY(v) return math.max(-16, math.min(16, v or 0)) end

--------------------------------------------------------------------------------
-- TexCoord cropping (mirrors customgroups.lua ApplyTexCoord)
--------------------------------------------------------------------------------

local function ApplyTexCoordToTexture(tex, iconW, iconH)
    local aspectRatio = iconW / iconH
    local inset = ICON_TEXCOORD_INSET
    local left, right, top, bottom = inset, 1 - inset, inset, 1 - inset

    if aspectRatio > 1.0 then
        local cropAmount = 1.0 - (1.0 / aspectRatio)
        local offset = cropAmount / 2.0
        top = top + offset * (1 - 2 * inset)
        bottom = bottom - offset * (1 - 2 * inset)
    elseif aspectRatio < 1.0 then
        local cropAmount = 1.0 - aspectRatio
        local offset = cropAmount / 2.0
        left = left + offset * (1 - 2 * inset)
        right = right - offset * (1 - 2 * inset)
    end

    tex:SetTexCoord(left, right, top, bottom)
end

--------------------------------------------------------------------------------
-- Resolve icon texture (spec icon fallback)
--------------------------------------------------------------------------------

local function ResolveIconTexture(override)
    if override then return override end
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local _, _, _, specIcon = GetSpecializationInfo(specIndex)
        if specIcon then return specIcon end
    end
    return 134400 -- question mark
end

--------------------------------------------------------------------------------
-- Controls:CreatePreview(options)
--
-- Options:
--   parent          Frame    Scroll content frame (set by builder)
--   componentId     string   Component to read settings from
--   mode            string   "icon" / "bar" / "iconbar" / "text"
--   settingKeys     table    Key name mapping (canonical -> actual DB key)
--   iconTexture     number/string/nil  Override icon texture
--   auraDefaultBarColor  table/nil  Default bar foreground color
--   useLightDim     bool     Use lighter dim text color
--------------------------------------------------------------------------------

function Controls:CreatePreview(options)
    local theme = GetTheme()
    if not options or not options.parent then return nil end

    local parent = options.parent
    local componentId = options.componentId
    local mode = options.mode or "icon"
    local settingKeys = options.settingKeys or {}
    local iconTextureOverride = options.iconTexture
    local auraDefaultBarColor = options.auraDefaultBarColor
    local useLightDim = options.useLightDim
    local rowHeight = options.rowHeight or PREVIEW_ROW_HEIGHT

    -- Component settings helpers
    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers(componentId)
    local getSetting = h.get
    local getSubSetting = h.getSubSetting

    -- Resolve a setting key through the mapping table
    local function readSetting(canonicalKey, default)
        local actualKey = settingKeys[canonicalKey] or canonicalKey
        local val = getSetting(actualKey)
        if val == nil then return default end
        return val
    end

    local showIcon = (mode == "icon" or mode == "iconbar")
    local showBar = (mode == "bar" or mode == "iconbar")
    local showTextOnly = (mode == "text")
    local showCDMText = settingKeys._showCDMText and true or false
    local showCAText = settingKeys._showCAText and true or false

    -- Theme colors
    local ar, ag, ab = theme:GetAccentColor()
    local dimR, dimG, dimB
    if useLightDim then
        dimR, dimG, dimB = theme:GetDimTextLightColor()
    else
        dimR, dimG, dimB = theme:GetDimTextColor()
    end

    ----------------------------------------------------------------------------
    -- Row frame
    ----------------------------------------------------------------------------

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowHeight)
    row:EnableMouse(true)

    -- Hover background
    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(ar, ag, ab, 0.08)
    hoverBg:Hide()
    row._hoverBg = hoverBg

    row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
    row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)

    -- Bottom border
    local bottomBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(PREVIEW_BORDER)
    bottomBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._bottomBorder = bottomBorder

    -- "Preview:" label (left side)
    local previewLabelFS = row:CreateFontString(nil, "OVERLAY")
    local labelFont = theme:GetFont("LABEL")
    previewLabelFS:SetFont(labelFont, 13, "")
    previewLabelFS:SetPoint("LEFT", row, "LEFT", PREVIEW_PADDING, 0)
    previewLabelFS:SetText("Preview:")
    previewLabelFS:SetTextColor(ar, ag, ab, 1)
    row._previewLabel = previewLabelFS

    ----------------------------------------------------------------------------
    -- Preview container (clips children)
    ----------------------------------------------------------------------------

    local container = CreateFrame("Frame", nil, row)
    container:SetClipsChildren(true)

    ----------------------------------------------------------------------------
    -- ICON
    ----------------------------------------------------------------------------

    local previewIcon, scaleFactor
    if showIcon then
        local iconTexture = ResolveIconTexture(iconTextureOverride)

        -- Dimensions from settings
        local iconSize = readSetting("iconSize", 30)
        local iconShape = readSetting("iconShape", 0)
        local iconW, iconH = addon.IconRatio.CalculateDimensions(iconSize, iconShape)

        -- Scale to fixed display size
        local maxDim = math.max(iconW, iconH)
        scaleFactor = PREVIEW_ICON_DISPLAY_SIZE / maxDim
        local displayW = math.floor(iconW * scaleFactor + 0.5)
        local displayH = math.floor(iconH * scaleFactor + 0.5)

        previewIcon = CreateFrame("Frame", nil, container)
        previewIcon:SetSize(displayW, displayH)

        -- Icon texture
        local iconTex = previewIcon:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexture(iconTexture)
        previewIcon.Icon = iconTex

        -- Borders (suppress when iconMode ~= "default", matching runtime behavior)
        local iconMode = readSetting("iconMode", "default")

        -- TexCoord cropping (only for default icons — custom pixel art uses full texture)
        if iconMode == "default" then
            ApplyTexCoordToTexture(iconTex, displayW, displayH)
        end
        local borderEnable = readSetting("borderEnable", nil)
        local borderStyle = readSetting("borderStyle", "square")
        local shouldShowBorder = (iconMode == "default") and (borderEnable ~= false) and (borderStyle ~= "none")

        if shouldShowBorder then
            addon.ApplyIconBorderStyle(previewIcon, borderStyle, {
                tintEnabled = readSetting("borderTintEnable", false),
                color = readSetting("borderTintColor", nil),
                thickness = readSetting("borderThickness", 1),
                insetH = readSetting("borderInsetH", 0),
                insetV = readSetting("borderInsetV", 0),
            })
        end

        -- Text elements (CDM-style: CD, Stacks, Keybind)
        if showCDMText then
            local textFrame = CreateFrame("Frame", nil, previewIcon)
            textFrame:SetAllPoints()
            textFrame:SetFrameLevel(previewIcon:GetFrameLevel() + 2)

            -- Helper: resolve CDM color from a sub-table config
            local function resolveCDMTextColor(subTableKey)
                local cfg = getSetting(subTableKey)
                if addon.ResolveCDMColor then
                    return addon.ResolveCDMColor(cfg)
                end
                return {1, 1, 1, 1}
            end

            -- Helper: scale font size for preview
            local function previewFontSize(size)
                local s = (size or 14) * scaleFactor
                return math.max(PREVIEW_MIN_FONT_SIZE, s)
            end

            -- Cooldown text ("CD" at CENTER)
            local cdFont = addon.ResolveFontFace(getSubSetting("textCooldown", "fontFace", "FRIZQT__"))
            local cdSize = previewFontSize(getSubSetting("textCooldown", "size", 14))
            local cdStyle = getSubSetting("textCooldown", "style", "OUTLINE")
            local cdColor = resolveCDMTextColor("textCooldown")
            local cdOffset = getSubSetting("textCooldown", "offset", {x = 0, y = 0})

            local cdText = textFrame:CreateFontString(nil, "OVERLAY")
            addon.ApplyFontStyle(cdText, cdFont, cdSize, cdStyle)
            cdText:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4] or 1)
            cdText:SetPoint("CENTER", textFrame, "CENTER",
                (cdOffset.x or 0) * scaleFactor,
                (cdOffset.y or 0) * scaleFactor)
            cdText:SetText("CD")

            -- Stacks text ("S" at BOTTOMRIGHT)
            local sFont = addon.ResolveFontFace(getSubSetting("textStacks", "fontFace", "FRIZQT__"))
            local sSize = previewFontSize(getSubSetting("textStacks", "size", 16))
            local sStyle = getSubSetting("textStacks", "style", "OUTLINE")
            local sColor = resolveCDMTextColor("textStacks")
            local sOffset = getSubSetting("textStacks", "offset", {x = 0, y = 0})

            local sText = textFrame:CreateFontString(nil, "OVERLAY")
            addon.ApplyFontStyle(sText, sFont, sSize, sStyle)
            sText:SetTextColor(sColor[1], sColor[2], sColor[3], sColor[4] or 1)
            sText:SetPoint("BOTTOMRIGHT", textFrame, "BOTTOMRIGHT",
                (sOffset.x or 0) * scaleFactor,
                (sOffset.y or 0) * scaleFactor)
            sText:SetText("S")

            -- Keybind text ("KB" at configurable anchor)
            local kbEnabled = getSubSetting("textBindings", "enabled", false)
            if kbEnabled then
                local kbFont = addon.ResolveFontFace(getSubSetting("textBindings", "fontFace", "FRIZQT__"))
                local kbSize = previewFontSize(getSubSetting("textBindings", "size", 12))
                local kbStyle = getSubSetting("textBindings", "style", "OUTLINE")
                local kbColor = resolveCDMTextColor("textBindings")
                local kbAnchor = getSubSetting("textBindings", "anchor", "TOPLEFT")
                local kbOffset = getSubSetting("textBindings", "offset", {x = 0, y = 0})

                local kbText = textFrame:CreateFontString(nil, "OVERLAY")
                addon.ApplyFontStyle(kbText, kbFont, kbSize, kbStyle)
                kbText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4] or 1)
                kbText:SetPoint(kbAnchor, textFrame, kbAnchor,
                    (kbOffset.x or 0) * scaleFactor,
                    (kbOffset.y or 0) * scaleFactor)
                kbText:SetText("KB")
            end
        end
    end

    ----------------------------------------------------------------------------
    -- BAR
    ----------------------------------------------------------------------------

    local previewBar
    if showBar then
        local barWidth = math.min(readSetting("barWidth", 120), PREVIEW_BAR_MAX_WIDTH)
        local barHeight = math.min(readSetting("barHeight", 12), PREVIEW_BAR_MAX_HEIGHT)
        local barFGTexKey = readSetting("barForegroundTexture", "bevelled")
        local barBGTexKey = readSetting("barBackgroundTexture", "bevelled")
        local barBGOpacity = (readSetting("barBackgroundOpacity", 50) or 50) / 100

        previewBar = CreateFrame("Frame", nil, container)
        previewBar:SetSize(barWidth, barHeight)

        -- Background
        local barBg = previewBar:CreateTexture(nil, "BACKGROUND")
        barBg:SetAllPoints()
        local bgTexPath = addon.Media.ResolveBarTexturePath(barBGTexKey)
        if bgTexPath then
            barBg:SetTexture(bgTexPath)
        else
            barBg:SetColorTexture(0, 0, 0, 1)
        end

        local bgColorMode = readSetting("barBackgroundColorMode", "custom")
        if bgColorMode == "custom" then
            local bgColor = readSetting("barBackgroundTint", {0, 0, 0, 1})
            barBg:SetVertexColor(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, barBGOpacity)
        else
            barBg:SetVertexColor(1, 1, 1, barBGOpacity)
        end

        -- Foreground (StatusBar at 50%)
        local barFill = CreateFrame("StatusBar", nil, previewBar)
        barFill:SetAllPoints()
        barFill:SetMinMaxValues(0, 1)
        barFill:SetValue(0.5)
        local fgTexPath = addon.Media.ResolveBarTexturePath(barFGTexKey)
        if fgTexPath then
            barFill:SetStatusBarTexture(fgTexPath)
        else
            barFill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        end

        local fgColorMode = readSetting("barForegroundColorMode", "custom")
        if fgColorMode == "custom" then
            local fgColor = readSetting("barForegroundTint", auraDefaultBarColor or {0.68, 0.85, 1.0, 1.0})
            barFill:SetStatusBarColor(fgColor[1] or 1, fgColor[2] or 1, fgColor[3] or 1, fgColor[4] or 1)
        elseif fgColorMode == "class" then
            if addon.GetClassColorRGB then
                local cr, cg, cb = addon.GetClassColorRGB("player")
                barFill:SetStatusBarColor(cr or 1, cg or 1, cb or 1, 1)
            else
                barFill:SetStatusBarColor(1, 1, 1, 1)
            end
        else
            barFill:SetStatusBarColor(1, 1, 1, 1)
        end

        previewBar._barFill = barFill

        -- Bar text
        local barTextFrame = CreateFrame("Frame", nil, previewBar)
        barTextFrame:SetAllPoints()
        barTextFrame:SetFrameLevel(previewBar:GetFrameLevel() + 1)

        local textFont = readSetting("textFont", "FRIZQT__")
        local textSize = readSetting("textSize", 10)
        local textStyle = readSetting("textStyle", "OUTLINE")
        local resolvedFont = addon.ResolveFontFace(textFont)
        local barTextSize = math.max(PREVIEW_MIN_FONT_SIZE, math.min(textSize, barHeight - 2))

        local textColor = readSetting("textColor", {1, 1, 1, 1})
        local tcR = type(textColor) == "table" and (textColor[1] or 1) or 1
        local tcG = type(textColor) == "table" and (textColor[2] or 1) or 1
        local tcB = type(textColor) == "table" and (textColor[3] or 1) or 1
        local tcA = type(textColor) == "table" and (textColor[4] or 1) or 1

        local nameText = barTextFrame:CreateFontString(nil, "OVERLAY")
        addon.ApplyFontStyle(nameText, resolvedFont, barTextSize, textStyle)
        nameText:SetPoint("LEFT", barTextFrame, "LEFT", 2, 0)
        nameText:SetText("Spell Name")
        nameText:SetTextColor(tcR, tcG, tcB, tcA)

        local timerText = barTextFrame:CreateFontString(nil, "OVERLAY")
        addon.ApplyFontStyle(timerText, resolvedFont, barTextSize, textStyle)
        timerText:SetPoint("RIGHT", barTextFrame, "RIGHT", -2, 0)
        timerText:SetText("T")
        timerText:SetTextColor(tcR, tcG, tcB, tcA)

        -- Bar border
        local barBorderStyle = readSetting("barBorderStyle", "none")
        if barBorderStyle and barBorderStyle ~= "none" then
            local barBorderThickness = readSetting("barBorderThickness", 1)
            local barBorderTintEnable = readSetting("barBorderTintEnable", false)
            local barBorderTintColor = readSetting("barBorderTintColor", {0, 0, 0, 1})

            if barBorderStyle == "square" then
                if addon.Borders and addon.Borders.ApplySquare then
                    local color = barBorderTintEnable and barBorderTintColor or {0, 0, 0, 1}
                    addon.Borders.ApplySquare(previewBar, {
                        size = barBorderThickness,
                        color = color,
                        layer = "OVERLAY",
                        layerSublevel = 7,
                        skipDimensionCheck = true,
                    })
                end
            elseif addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                addon.BarBorders.ApplyToBarFrame(barFill, barBorderStyle, {
                    thickness = barBorderThickness,
                    tintEnabled = barBorderTintEnable,
                    tintColor = barBorderTintColor,
                })
            end
        end
    end

    ----------------------------------------------------------------------------
    -- CLASS AURA TEXT
    ----------------------------------------------------------------------------

    local caTextFS
    if showCAText then
        local caTextFont = readSetting("textFont", "FRIZQT__")
        local caTextSize = readSetting("textSize", 24)
        local caTextStyle = readSetting("textStyle", "OUTLINE")
        local caTextColor = readSetting("textColor", {1, 1, 1, 1})
        local caTextPosition = readSetting("textPosition", "inside")
        local caTextInnerAnchor = readSetting("textInnerAnchor", "CENTER")
        local caTextOuterAnchor = readSetting("textOuterAnchor", "RIGHT")

        -- Determine display font size
        local caDisplaySize
        if showTextOnly then
            caDisplaySize = math.min(caTextSize, CA_TEXT_MAX_SIZE)
        elseif scaleFactor then
            caDisplaySize = caTextSize * scaleFactor
        else
            caDisplaySize = math.min(caTextSize, 24)
        end
        caDisplaySize = math.max(PREVIEW_MIN_FONT_SIZE, caDisplaySize)

        local resolvedCAFont = addon.ResolveFontFace(caTextFont)

        caTextFS = container:CreateFontString(nil, "OVERLAY")
        addon.ApplyFontStyle(caTextFS, resolvedCAFont, caDisplaySize, caTextStyle)
        caTextFS:SetText("5")

        if type(caTextColor) == "table" then
            caTextFS:SetTextColor(
                caTextColor[1] or 1, caTextColor[2] or 1,
                caTextColor[3] or 1, caTextColor[4] or 1)
        else
            caTextFS:SetTextColor(1, 1, 1, 1)
        end

        -- Store positioning config for deferred anchoring (needs icon positioned first)
        container._caTextConfig = {
            position = caTextPosition,
            innerAnchor = caTextInnerAnchor,
            outerAnchor = caTextOuterAnchor,
            offsetX = readSetting("textOffsetX", 0),
            offsetY = readSetting("textOffsetY", 0),
        }
    end

    ----------------------------------------------------------------------------
    -- Position elements in container
    ----------------------------------------------------------------------------

    local totalWidth = 0
    local containerHeight = rowHeight - 20

    if showIcon and previewIcon then
        local iconDisplayW = previewIcon:GetWidth()
        totalWidth = totalWidth + iconDisplayW

        if showBar and previewBar then
            local barPosition = readSetting("barPosition", "RIGHT")
            local barOffsetX = clampBarOffsetX(readSetting("barOffsetX", 0))
            local barOffsetY = clampBarOffsetY(readSetting("barOffsetY", 0))
            local barW = previewBar:GetWidth()

            if barPosition == "LEFT" then
                previewIcon:SetPoint("RIGHT", container, "RIGHT", -2, 0)
                previewBar:SetPoint("RIGHT", previewIcon, "LEFT", barOffsetX, barOffsetY)
            else
                previewIcon:SetPoint("LEFT", container, "LEFT", 2, 0)
                previewBar:SetPoint("LEFT", previewIcon, "RIGHT", barOffsetX, barOffsetY)
            end

            totalWidth = totalWidth + barW + math.abs(barOffsetX)
        else
            -- Check if CA text needs outside positioning
            local caConfig = container._caTextConfig
            if caTextFS and caConfig and caConfig.position == "outside" then
                -- Position icon to leave room for outside text (matches runtime LayoutElements)
                local anchor = caConfig.outerAnchor or "RIGHT"
                if anchor == "RIGHT" then
                    previewIcon:SetPoint("LEFT", container, "LEFT", 2, 0)
                elseif anchor == "LEFT" then
                    previewIcon:SetPoint("RIGHT", container, "RIGHT", -2, 0)
                elseif anchor == "ABOVE" then
                    previewIcon:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
                elseif anchor == "BELOW" then
                    previewIcon:SetPoint("TOP", container, "TOP", 0, 0)
                end
            else
                previewIcon:SetPoint("CENTER", container, "CENTER", 0, 0)
            end
        end
    elseif showBar and previewBar then
        previewBar:SetPoint("LEFT", container, "LEFT", 2, 0)
        totalWidth = previewBar:GetWidth()
    elseif showTextOnly and caTextFS then
        -- Text-only mode: center text in container, size to fit
        caTextFS:SetPoint("CENTER", container, "CENTER", 0, 0)
        local textW = caTextFS:GetStringWidth() or 20
        local textH = caTextFS:GetStringHeight() or 16
        totalWidth = textW + 8
        containerHeight = math.max(containerHeight, textH + 4)
    end

    container:SetSize(math.max(totalWidth + 4, PREVIEW_ICON_DISPLAY_SIZE + 4), containerHeight)
    container:SetPoint("CENTER", row, "CENTER", 0, 0)

    -- Anchor CA text for non-text-only modes (icon must be positioned first)
    if caTextFS and not showTextOnly then
        local cfg = container._caTextConfig
        if cfg and previewIcon then
            local txOff = (cfg.offsetX or 0) * (scaleFactor or 1)
            local tyOff = (cfg.offsetY or 0) * (scaleFactor or 1)

            if cfg.position == "inside" then
                local anchor = cfg.innerAnchor or "CENTER"
                local offsets = CA_INSIDE_OFFSETS[anchor] or { 0, 0 }
                local sx = offsets[1] * (scaleFactor or 1) + txOff
                local sy = offsets[2] * (scaleFactor or 1) + tyOff
                caTextFS:SetPoint(anchor, previewIcon, anchor, sx, sy)
            else -- outside
                local anchor = cfg.outerAnchor or "RIGHT"
                if anchor == "RIGHT" then
                    caTextFS:SetPoint("LEFT", previewIcon, "RIGHT", CA_GAP + txOff, tyOff)
                elseif anchor == "LEFT" then
                    caTextFS:SetPoint("RIGHT", previewIcon, "LEFT", -CA_GAP + txOff, tyOff)
                elseif anchor == "ABOVE" then
                    caTextFS:SetPoint("BOTTOM", previewIcon, "TOP", txOff, CA_GAP + tyOff)
                elseif anchor == "BELOW" then
                    caTextFS:SetPoint("TOP", previewIcon, "BOTTOM", txOff, -CA_GAP + tyOff)
                end

                -- Expand container if text would clip
                local textW = caTextFS:GetStringWidth() or 0
                local textH = caTextFS:GetStringHeight() or 0
                if anchor == "RIGHT" or anchor == "LEFT" then
                    totalWidth = totalWidth + CA_GAP + textW
                    container:SetWidth(math.max(totalWidth + 4, container:GetWidth()))
                elseif anchor == "ABOVE" or anchor == "BELOW" then
                    local iconH = previewIcon and previewIcon:GetHeight() or 0
                    containerHeight = math.max(containerHeight, iconH + CA_GAP + textH)
                    container:SetWidth(math.max(math.max(totalWidth, textW) + 4, container:GetWidth()))
                    container:SetHeight(containerHeight)
                end
            end
        elseif not previewIcon then
            -- No icon present: center in container
            caTextFS:SetPoint("CENTER", container, "CENTER", 0, 0)
        end
    end

    ----------------------------------------------------------------------------
    -- Legend (right-aligned, dim)
    ----------------------------------------------------------------------------

    local legendParts = {}
    if showIcon and showCDMText then
        table.insert(legendParts, "CD = Cooldown")
        table.insert(legendParts, "S = Stacks")
        local kbEnabled = getSubSetting("textBindings", "enabled", false)
        if kbEnabled then
            table.insert(legendParts, "KB = Keybind")
        end
    end
    if showBar then
        table.insert(legendParts, "T = Timer")
    end
    if showCAText then
        table.insert(legendParts, "5 = Stacks")
    end

    if #legendParts > 0 then
        local legendFS = row:CreateFontString(nil, "OVERLAY")
        local legendFont = theme:GetFont("VALUE")
        legendFS:SetFont(legendFont, 10, "")
        legendFS:SetPoint("RIGHT", row, "RIGHT", -PREVIEW_PADDING, 0)
        legendFS:SetText(table.concat(legendParts, "\n"))
        legendFS:SetTextColor(dimR, dimG, dimB, 0.7)
        legendFS:SetJustifyH("RIGHT")
        legendFS:SetJustifyV("MIDDLE")
        row._legendFS = legendFS
    end

    ----------------------------------------------------------------------------
    -- Theme subscription
    ----------------------------------------------------------------------------

    local subscribeKey = "Preview_" .. (componentId or tostring(row))
    row._subscribeKey = subscribeKey

    theme:Subscribe(subscribeKey, function(r, g, b)
        if row._hoverBg then
            row._hoverBg:SetColorTexture(r, g, b, 0.08)
        end
        if row._bottomBorder then
            row._bottomBorder:SetColorTexture(r, g, b, 0.2)
        end
        if row._previewLabel then
            row._previewLabel:SetTextColor(r, g, b, 1)
        end
        -- Update legend color
        if row._legendFS then
            local dR, dG, dB
            if useLightDim then
                dR, dG, dB = theme:GetDimTextLightColor()
            else
                dR, dG, dB = theme:GetDimTextColor()
            end
            row._legendFS:SetTextColor(dR, dG, dB, 0.7)
        end
    end)

    ----------------------------------------------------------------------------
    -- Public methods
    ----------------------------------------------------------------------------

    function row:Refresh()
        -- Preview is static; full panel rebuild handles updates
    end

    function row:Cleanup()
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    return row
end
