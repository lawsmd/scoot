-- Preview.lua - Inline preview row for Custom Groups and ScootAuras settings
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
-- Bars build at their true configured size and SetScale to this display budget,
-- so borders, insets and text keep their real proportions (same idea as the icon path).
local PREVIEW_BAR_DISPLAY_MAX_WIDTH = 280
local PREVIEW_BAR_DISPLAY_MAX_HEIGHT = 40
local PREVIEW_PADDING = 12
local PREVIEW_BORDER = 1
local ICON_TEXCOORD_INSET = 0.07
local PREVIEW_MIN_FONT_SIZE = 6
local CA_TEXT_MAX_SIZE = 36

-- Growth ceilings. The preview box measures its contents and grows to fit; these bound how
-- far it can go before SetClipsChildren takes over, so a slider pinned to its limit can't
-- shove the row into the "Preview:" label, the legend, or the sections below it.
local PREVIEW_MAX_CONTENT_WIDTH = 400
local PREVIEW_MAX_ROW_HEIGHT = 160
local PREVIEW_CONTENT_PAD = 4
-- Border art draws outside the icon frame. iconborders.lua clamps expandX/expandY to [-8, 8]
-- but doesn't report them back, so reserve the ceiling rather than widen a border helper
-- that every component shares.
local PREVIEW_BORDER_SLACK = 8

local CA_INSIDE_OFFSETS = {
    TOPLEFT = { 2, -2 }, TOP = { 0, -2 }, TOPRIGHT = { -2, -2 },
    LEFT = { 2, 0 }, CENTER = { 0, 0 }, RIGHT = { -2, 0 },
    BOTTOMLEFT = { 2, 2 }, BOTTOM = { 0, 2 }, BOTTOMRIGHT = { -2, 2 },
}
local CA_GAP = 2

local function clampBarOffsetX(v) return math.max(-20, math.min(20, v or 0)) end
local function clampBarOffsetY(v) return math.max(-16, math.min(16, v or 0)) end

--------------------------------------------------------------------------------
-- Content measurement
--------------------------------------------------------------------------------

-- Anchor point expressed as a fraction of the box, measured from its center.
local ANCHOR_FRACTION = {
    TOPLEFT    = { -0.5,  0.5 }, TOP    = { 0,  0.5 }, TOPRIGHT    = {  0.5,  0.5 },
    LEFT       = { -0.5,  0   }, CENTER = { 0,  0   }, RIGHT       = {  0.5,  0   },
    BOTTOMLEFT = { -0.5, -0.5 }, BOTTOM = { 0, -0.5 }, BOTTOMRIGHT = {  0.5, -0.5 },
}

-- How far an element reaches from the center of the box it anchors into. The icon stays
-- centered in the container, so only the largest absolute extent on each axis matters.
local function ElementHalfExtents(anchor, boxW, boxH, offsetX, offsetY, elemW, elemH)
    local f = ANCHOR_FRACTION[anchor] or ANCHOR_FRACTION.CENTER
    local px = f[1] * boxW + (offsetX or 0)
    local py = f[2] * boxH + (offsetY or 0)
    -- A LEFT-anchored string extends right from its anchor, a RIGHT-anchored one extends
    -- left, and a centered one splits the difference.
    local left = px - (f[1] + 0.5) * elemW
    local bottom = py - (f[2] + 0.5) * elemH
    return math.max(math.abs(left), math.abs(left + elemW)),
           math.max(math.abs(bottom), math.abs(bottom + elemH))
end

-- MeasureTextWidth rules a UIParent-anchored FontString with GetUnboundedStringWidth, so it
-- reports correctly before the panel has rendered. Height comes from the size applied above
-- because GetStringHeight under-reports until a FontString has rendered once, and all of this
-- runs synchronously while the panel is being built.
local function MeasureString(fs, text, face, size, style)
    local w = addon.MeasureTextWidth and addon.MeasureTextWidth(text, face, size, style)
    if (not w or w <= 0) and fs then
        local ok, sw = pcall(fs.GetStringWidth, fs)
        if ok and type(sw) == "number" and sw > 0 then w = sw end
    end
    if not w or w <= 0 then w = #text * size * 0.6 end
    return w, size * 1.3
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
--   settingKeys     table    Key name mapping (canonical -> real DB key)
--   iconTexture     number/string/nil  Override icon texture
--   auraDefaultBarColor  table/nil  Default bar foreground color
--   caTextSource    string/nil  Source of the CA text element ("duration"/"applications");
--                            picks the placeholder glyph ("T"/"5") and legend entry
--   caTextLiteral   string/nil  Exact text for the CA text element instead of the
--                            countdown placeholder; the ticker leaves it alone (a
--                            missing-buff reminder shows the aura name)
--   previewNameLabel string/nil  Aura label shown as the bar's name text when the
--                            Aura Name feature is enabled (hideNameText false)
--   useLightDim     bool     Use lighter dim text color
--   rowHeight       number   Base row height (default 76). A floor, not a ceiling: the row
--                            grows to fit its measured contents, up to maxRowHeight.
--   previewScale    number/nil  Opt-in true-size mode (icon/bar/iconbar): render at
--                            configured size x (scale setting / 100) x previewScale
--                            instead of normalizing to the display budget. 1 = 1:1.
--   maxRowHeight    number/nil  Row growth ceiling (default PREVIEW_MAX_ROW_HEIGHT).
--   borderPath      string   Which border implementation to draw with: "shared" (default,
--                            addon.ApplyIconBorderStyle) or "customGroups" (the CG HUD path).
--                            Must match whichever one the previewed system uses at runtime.
--   getSetting      fn/nil   Override for the settings read path (key -> value). Lets a
--                            draft (no component db yet) drive the preview.
--   getSubSetting   fn/nil   Override for the sub-table read path (tableKey, key, default).
--   shapeAtlas      string/nil  Render the icon element as this atlas instead of a spell
--                            texture (shape-style trackers). Suppresses crop and borders.
--   shapeColor      table/nil   {r,g,b,a} vertex color for shapeAtlas.
--   shapeDrain      bool     Animate a drain sweep over shapeAtlas: a Cooldown clipped to
--                            the glyph, driven by the same 15s cycle as the countdown.
--   noBottomBorder  bool     Skip the divider line under the row.
--   noHover         bool     Skip the accent hover highlight on the row.
--   noLabel         bool     Skip the "Preview:" label (caller draws its own).
--   timerEpoch      table/nil  Caller-owned countdown anchor { start = <GetTime()> }.
--                            Seeded on first use; a rebuilt row resumes the same
--                            15s cycle instead of restarting it. The caller resets
--                            the table (or its start) to restart the countdown.
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
    local caTextSource = options.caTextSource
    local caTextLiteral = options.caTextLiteral
    local previewNameLabel = options.previewNameLabel
    local useLightDim = options.useLightDim
    local rowHeight = options.rowHeight or PREVIEW_ROW_HEIGHT
    local maxRowHeight = options.maxRowHeight or PREVIEW_MAX_ROW_HEIGHT
    local borderPath = options.borderPath or "shared"

    -- Component settings helpers (overridable so a draft can drive the preview)
    local Helpers = addon.UI.Settings.Helpers
    local h = Helpers.CreateComponentHelpers(componentId)
    local getSetting = options.getSetting or h.get
    local getSubSetting = options.getSubSetting or h.getSubSetting

    -- Resolve a setting key through the mapping table
    local function readSetting(canonicalKey, default)
        local actualKey = settingKeys[canonicalKey] or canonicalKey
        local val = getSetting(actualKey)
        if val == nil then return default end
        return val
    end

    -- True-size mode: one factor for art and text. nil when previewScale is
    -- absent, leaving every normalized path exactly as before (the scale key
    -- is not even read).
    local trueScale = options.previewScale
        and (options.previewScale * (readSetting("scale", 100) / 100))
        or nil

    local showIcon = (mode == "icon" or mode == "iconbar")
    local showBar = (mode == "bar" or mode == "iconbar")
    local showTextOnly = (mode == "text")
    local showCDMText = settingKeys._showCDMText and true or false
    -- Mirror live behavior: hideText suppresses the duration/stacks text everywhere
    local showCAText = (settingKeys._showCAText and true or false)
        and (readSetting("hideText", false) ~= true)

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
    if not options.noHover then
        row._hoverBg = Controls.AddHoverFill(row, { sublevel = Controls.SUBLEVEL_BG })

        row:SetScript("OnEnter", function(self) self._hoverBg:Show() end)
        row:SetScript("OnLeave", function(self) self._hoverBg:Hide() end)
    end

    -- Bottom border
    local bottomBorder = row:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(PREVIEW_BORDER)
    bottomBorder:SetColorTexture(ar, ag, ab, 0.2)
    row._bottomBorder = bottomBorder
    if options.noBottomBorder then bottomBorder:Hide() end

    -- "Preview:" label (left side)
    if not options.noLabel then
        local previewLabelFS = row:CreateFontString(nil, "OVERLAY")
        local labelFont = theme:GetFont("LABEL")
        previewLabelFS:SetFont(labelFont, 13, "")
        previewLabelFS:SetPoint("LEFT", row, "LEFT", PREVIEW_PADDING, 0)
        previewLabelFS:SetText("Preview:")
        previewLabelFS:SetTextColor(ar, ag, ab, 1)
        row._previewLabel = previewLabelFS
    end

    ----------------------------------------------------------------------------
    -- Preview container (clips children)
    ----------------------------------------------------------------------------

    local container = CreateFrame("Frame", nil, row)
    container:SetClipsChildren(true)

    ----------------------------------------------------------------------------
    -- ICON
    ----------------------------------------------------------------------------

    local previewIcon, scaleFactor
    local iconW, iconH = 0, 0
    -- Measured half-extents of everything drawn around the icon center, used to size the
    -- clip container once all the pieces exist.
    local contentHalfW, contentHalfH = 0, 0
    if showIcon then
        local iconTexture = ResolveIconTexture(iconTextureOverride)

        -- Dimensions from settings
        local iconSize = readSetting("iconSize", 30)
        local iconShape = readSetting("iconShape", 0)
        iconW, iconH = addon.IconRatio.CalculateDimensions(iconSize, iconShape)

        -- Build at true HUD dimensions and shrink the frame as a unit. Border art, insets,
        -- thickness and text then keep their real proportions instead of being applied as raw
        -- pixels to a resized icon. Everything below works in icon-local pixels; scaleFactor
        -- converts to screen pixels once, when the clip container is sized.
        scaleFactor = trueScale or (PREVIEW_ICON_DISPLAY_SIZE / math.max(iconW, iconH, 1))

        previewIcon = CreateFrame("Frame", nil, container)
        previewIcon:SetSize(iconW, iconH)
        previewIcon:SetScale(scaleFactor)
        contentHalfW, contentHalfH = iconW / 2, iconH / 2

        -- Icon texture (or shape atlas: shape-style trackers preview their atlas art)
        local iconTex = previewIcon:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        if options.shapeAtlas then
            iconTex:SetAtlas(options.shapeAtlas)
            local sc = options.shapeColor
            if sc then
                iconTex:SetVertexColor(sc[1] or 1, sc[2] or 1, sc[3] or 1, sc[4] or 1)
            end
            if options.shapeDrain then
                -- Same recipe as the live tracker: the atlas resolved to its
                -- file and texcoords clips the swipe to the glyph. The
                -- animation block below re-arms it each countdown cycle.
                local cd = CreateFrame("Cooldown", nil, previewIcon, "CooldownFrameTemplate")
                cd:SetAllPoints()
                cd:SetDrawBling(false)
                cd:SetDrawEdge(false)
                cd:SetHideCountdownNumbers(true)
                -- Reverse = the dark swipe grows as time runs out (full color at
                -- max duration), matching the live tracker's drain direction
                cd:SetReverse(true)
                cd:SetSwipeColor(0, 0, 0, 0.6)
                local info = C_Texture and C_Texture.GetAtlasInfo
                    and C_Texture.GetAtlasInfo(options.shapeAtlas)
                if info and (info.file or info.filename) then
                    pcall(cd.SetSwipeTexture, cd, info.file or info.filename)
                    pcall(cd.SetTexCoordRange, cd,
                        { x = info.leftTexCoord, y = info.topTexCoord },
                        { x = info.rightTexCoord, y = info.bottomTexCoord })
                end
                row._shapeCooldown = cd
            end
        else
            iconTex:SetTexture(iconTexture)
        end
        previewIcon.Icon = iconTex

        -- Borders (suppress when iconMode ~= "default", matching runtime behavior)
        local iconMode = readSetting("iconMode", "default")

        -- TexCoord cropping (only for default icons — custom pixel art uses full texture).
        -- Shares the HUD's cropping math so the Icon Zoom slider reads the same here.
        if iconMode == "default" and not options.shapeAtlas then
            local l, r, t, b = addon.CalculateIconTexCoords(
                iconW / iconH, readSetting("iconZoom", 0), ICON_TEXCOORD_INSET)
            iconTex:SetTexCoord(l, r, t, b)
        end
        local borderEnable = readSetting("borderEnable", nil)
        local borderStyle = readSetting("borderStyle", "square")
        local shouldShowBorder = (iconMode == "default") and (borderEnable ~= false) and (borderStyle ~= "none")
            and not options.shapeAtlas

        if shouldShowBorder then
            -- Custom Groups draw borders through their own HUD code rather than the shared
            -- helper every other system uses. Route the preview to whichever one owns this
            -- component so the two can't drift, and take the reported outward reach so the
            -- clip box is sized from what was drawn.
            local CG = addon.CustomGroups
            local cgComponent = (borderPath == "customGroups") and h.getComponent() or nil
            local cgDb = cgComponent and cgComponent.db
            local useCG = cgDb and CG and CG.BuildBorderOpts and CG.ApplyBorderToIcon
                and CG.EnsureIconBorderTextures

            local reachX, reachY
            if useCG then
                CG.EnsureIconBorderTextures(previewIcon)
                reachX, reachY = CG.ApplyBorderToIcon(previewIcon, CG.BuildBorderOpts(cgDb))
            else
                local _, ex, ey = addon.ApplyIconBorderStyle(previewIcon, borderStyle, {
                    tintEnabled = readSetting("borderTintEnable", false),
                    color = readSetting("borderTintColor", nil),
                    thickness = readSetting("borderThickness", 1),
                    insetH = readSetting("borderInsetH", 0),
                    insetV = readSetting("borderInsetV", 0),
                })
                reachX, reachY = ex, ey
            end

            -- Fall back to the clamp ceiling when a border helper reports nothing.
            contentHalfW = contentHalfW + math.max(0, reachX or PREVIEW_BORDER_SLACK)
            contentHalfH = contentHalfH + math.max(0, reachY or PREVIEW_BORDER_SLACK)
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

            -- Helper: font size in icon-local units. previewIcon's SetScale does the shrinking,
            -- so the legibility floor is divided out to stay a floor on the rendered result.
            local function previewFontSize(size)
                return math.max(PREVIEW_MIN_FONT_SIZE / scaleFactor, size or 14)
            end

            -- Helper: grow the measured content box to cover a newly placed string
            local function trackText(fs, text, anchor, face, size, style, ox, oy)
                local tw, th = MeasureString(fs, text, face, size, style)
                local ex, ey = ElementHalfExtents(anchor, iconW, iconH, ox, oy, tw, th)
                contentHalfW = math.max(contentHalfW, ex)
                contentHalfH = math.max(contentHalfH, ey)
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
            local cdX, cdY = cdOffset.x or 0, cdOffset.y or 0
            cdText:SetPoint("CENTER", textFrame, "CENTER", cdX, cdY)
            cdText:SetText("CD")
            trackText(cdText, "CD", "CENTER", cdFont, cdSize, cdStyle, cdX, cdY)

            -- Stacks text ("S" at BOTTOMRIGHT)
            local sFont = addon.ResolveFontFace(getSubSetting("textStacks", "fontFace", "FRIZQT__"))
            local sSize = previewFontSize(getSubSetting("textStacks", "size", 16))
            local sStyle = getSubSetting("textStacks", "style", "OUTLINE")
            local sColor = resolveCDMTextColor("textStacks")
            local sOffset = getSubSetting("textStacks", "offset", {x = 0, y = 0})

            local sText = textFrame:CreateFontString(nil, "OVERLAY")
            addon.ApplyFontStyle(sText, sFont, sSize, sStyle)
            sText:SetTextColor(sColor[1], sColor[2], sColor[3], sColor[4] or 1)
            local sX, sY = sOffset.x or 0, sOffset.y or 0
            sText:SetPoint("BOTTOMRIGHT", textFrame, "BOTTOMRIGHT", sX, sY)
            sText:SetText("S")
            trackText(sText, "S", "BOTTOMRIGHT", sFont, sSize, sStyle, sX, sY)

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
                local kbX, kbY = kbOffset.x or 0, kbOffset.y or 0
                kbText:SetPoint(kbAnchor, textFrame, kbAnchor, kbX, kbY)
                kbText:SetText("KB")
                trackText(kbText, "KB", kbAnchor, kbFont, kbSize, kbStyle, kbX, kbY)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- BAR
    ----------------------------------------------------------------------------

    local previewBar, barScale
    if showBar then
        -- Build at the TRUE configured size and scale as a unit (same approach as the icon
        -- path) so border thickness, insets and text keep their real proportions.
        local barWidth = readSetting("barWidth", 120)
        local barHeight = readSetting("barHeight", 12)
        local barFGTexKey = readSetting("barForegroundTexture", "bevelled")
        local barBGTexKey = readSetting("barBackgroundTexture", "bevelled")
        local barBGOpacity = (readSetting("barBackgroundOpacity", 50) or 50) / 100

        previewBar = CreateFrame("Frame", nil, container)
        previewBar:SetSize(barWidth, barHeight)

        if showIcon and previewIcon then
            if not trueScale then
                -- Icon & Bar: one composite factor so the pair keeps its relative proportions
                local offX = math.abs(clampBarOffsetX(readSetting("barOffsetX", 0)))
                local fitW = (PREVIEW_MAX_CONTENT_WIDTH - 24) / math.max(iconW + offX + barWidth + 4, 1)
                local fitH = (PREVIEW_MAX_ROW_HEIGHT - 28) / math.max(iconH, barHeight, 1)
                scaleFactor = math.min(scaleFactor or 1, fitW, fitH)
                previewIcon:SetScale(scaleFactor)
            end
            -- True-size: the icon already carries trueScale; the bar shares the factor
            barScale = scaleFactor
        else
            -- Fill the display budget; modest upscale cap keeps small bars honest
            barScale = trueScale
                or math.min(PREVIEW_BAR_DISPLAY_MAX_WIDTH / math.max(barWidth, 1),
                            PREVIEW_BAR_DISPLAY_MAX_HEIGHT / math.max(barHeight, 1),
                            2.5)
        end
        previewBar:SetScale(barScale)

        -- Background (sublevel -1, matching the live bar)
        local barBg = previewBar:CreateTexture(nil, "BACKGROUND", nil, -1)
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
        row._barFill = barFill

        -- Bar border (mirrors the live paths in scootauras/styling.lua)
        local barBorderStyle = readSetting("barBorderStyle", "none")
        if barBorderStyle and barBorderStyle ~= "none" then
            local barBorderThickness = math.max(1, tonumber(readSetting("barBorderThickness", 1)) or 1)
            local barBorderInsetH = tonumber(readSetting("barBorderInsetH", 0)) or 0
            local barBorderInsetV = tonumber(readSetting("barBorderInsetV", 0)) or 0
            local hiddenEdges = readSetting("barBorderHiddenEdges", nil)
            local barBorderTintEnable = readSetting("barBorderTintEnable", false)
            local barBorderTintColor = readSetting("barBorderTintColor", { 1, 1, 1, 1 })
            local borderColor = (barBorderTintEnable and barBorderTintColor) or { 0, 0, 0, 1 }

            if barBorderStyle == "square" then
                -- Edges live in their own container ABOVE the fill StatusBar: regions of
                -- previewBar itself would draw below the barFill child frame regardless of layer.
                addon.Borders.ApplySquare(barFill, {
                    size = barBorderThickness,
                    color = borderColor,
                    layer = "OVERLAY",
                    layerSublevel = 1,
                    levelOffset = 1,
                    containerParent = previewBar,
                    containerAnchorRegion = previewBar,
                    expandX = barBorderInsetH,
                    expandY = barBorderInsetV,
                    hiddenEdges = hiddenEdges,
                    skipDimensionCheck = true,
                })
            elseif addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                addon.BarBorders.ApplyToBarFrame(barFill, barBorderStyle, {
                    thickness = barBorderThickness,
                    insetH = barBorderInsetH,
                    insetV = barBorderInsetV,
                    color = borderColor,
                    hiddenEdges = hiddenEdges,
                })
            end
        end
    end

    -- Anchors a FontString to the preview bar per an inside/outside position config.
    -- Offsets are raw: callers live inside the scaled bar subtree, so barScale applies.
    local function AnchorTextToBar(fs, bar, cfg)
        local txOff = cfg.offsetX or 0
        local tyOff = cfg.offsetY or 0
        if cfg.position == "outside" then
            local anchor = cfg.outerAnchor or "RIGHT"
            if anchor == "RIGHT" then
                fs:SetJustifyH("LEFT")
                fs:SetPoint("LEFT", bar, "RIGHT", CA_GAP + txOff, tyOff)
            elseif anchor == "LEFT" then
                fs:SetJustifyH("RIGHT")
                fs:SetPoint("RIGHT", bar, "LEFT", -CA_GAP + txOff, tyOff)
            elseif anchor == "ABOVE" then
                fs:SetJustifyH("CENTER")
                fs:SetPoint("BOTTOM", bar, "TOP", txOff, CA_GAP + tyOff)
            else -- BELOW
                fs:SetJustifyH("CENTER")
                fs:SetPoint("TOP", bar, "BOTTOM", txOff, -CA_GAP + tyOff)
            end
        else
            local anchor = cfg.innerAnchor or "CENTER"
            local offsets = CA_INSIDE_OFFSETS[anchor] or { 0, 0 }
            fs:SetPoint(anchor, bar, anchor, offsets[1] + txOff, offsets[2] + tyOff)
        end
    end

    ----------------------------------------------------------------------------
    -- AURA NAME (bar name text, shown when the Aura Name feature is enabled)
    ----------------------------------------------------------------------------

    local nameTextFS, nameTextCfg
    if showBar and previewBar and previewNameLabel and (readSetting("hideNameText", true) ~= true) then
        local nameFont = readSetting("nameTextFont", "FRIZQT__")
        local nameSize = readSetting("nameTextSize", 10)
        local nameStyle = readSetting("nameTextStyle", "OUTLINE")
        local nameColor = readSetting("nameTextColor", { 1, 1, 1, 1 })

        local nameFrame = CreateFrame("Frame", nil, previewBar)
        nameFrame:SetAllPoints(previewBar)
        nameFrame:SetFrameLevel(previewBar._barFill:GetFrameLevel() + 2)

        nameTextFS = nameFrame:CreateFontString(nil, "OVERLAY")
        local nameDisplaySize = math.max(PREVIEW_MIN_FONT_SIZE / barScale, nameSize)
        addon.ApplyFontStyle(nameTextFS, addon.ResolveFontFace(nameFont), nameDisplaySize, nameStyle)
        if type(nameColor) == "table" then
            nameTextFS:SetTextColor(nameColor[1] or 1, nameColor[2] or 1, nameColor[3] or 1, nameColor[4] or 1)
        end
        nameTextFS:SetText(previewNameLabel)

        nameTextCfg = {
            position = readSetting("nameTextPosition", "inside"),
            innerAnchor = readSetting("nameTextInnerAnchor", "LEFT"),
            outerAnchor = readSetting("nameTextOuterAnchor", "ABOVE"),
            offsetX = readSetting("nameTextOffsetX", 0),
            offsetY = readSetting("nameTextOffsetY", 0),
        }
        AnchorTextToBar(nameTextFS, previewBar, nameTextCfg)
    end

    ----------------------------------------------------------------------------
    -- AURA TEXT
    ----------------------------------------------------------------------------

    local caTextFS
    local caTextFrame
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

        -- Trackers on the icon-beside-bar model (marked by barIconSide) put the
        -- duration on the bar even with the icon shown, matching their live
        -- layout; legacy icon+bar components keep their icon-anchored text.
        local caOnBar = showBar and previewBar ~= nil
            and (not showIcon or readSetting("barIconSide", nil) ~= nil)
        if caOnBar then
            -- Bar-only mode: text lives inside the scaled bar subtree at its true font
            -- size, above the fill (mirrors the live elevated text frame)
            caTextFrame = CreateFrame("Frame", nil, previewBar)
            caTextFrame:SetAllPoints(previewBar)
            caTextFrame:SetFrameLevel(previewBar._barFill:GetFrameLevel() + 2)
            caDisplaySize = math.max(PREVIEW_MIN_FONT_SIZE / barScale, caTextSize)
        else
            caTextFrame = CreateFrame("Frame", nil, container)
            caTextFrame:SetAllPoints()
        end
        caTextFS = caTextFrame:CreateFontString(nil, "OVERLAY")
        addon.ApplyFontStyle(caTextFS, resolvedCAFont, caDisplaySize, caTextStyle)
        -- "15" is the widest value the animated countdown shows, so the width
        -- measurements below reserve two digits before the ticker takes over.
        caTextFS:SetText(caTextLiteral or (caTextSource == "applications" and "5" or "15"))
        row._caTextFS = caTextFS

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
            onBar = caOnBar,
        }
    end

    ----------------------------------------------------------------------------
    -- Position elements in container
    ----------------------------------------------------------------------------

    local totalWidth = 0
    local containerHeight = rowHeight - 20

    if showIcon and previewIcon then
        -- previewIcon is scaled, so GetWidth reports its own-space width. Convert to screen.
        local iconDisplayW = previewIcon:GetWidth() * (scaleFactor or 1)
        totalWidth = totalWidth + iconDisplayW

        if showBar and previewBar then
            local barPosition = readSetting("barPosition", "RIGHT")
            local barOffsetX = clampBarOffsetX(readSetting("barOffsetX", 0))
            local barOffsetY = clampBarOffsetY(readSetting("barOffsetY", 0))
            -- Trackers on the icon-beside-bar model carry barIconSide and
            -- barIconGap instead; map them onto the legacy side + signed
            -- spacing vocabulary this block already speaks.
            local iconSide = readSetting("barIconSide", nil)
            if iconSide then
                barPosition = (iconSide == "RIGHT") and "LEFT" or "RIGHT"
                local g = tonumber(readSetting("barIconGap", 2)) or 2
                barOffsetX = (barPosition == "LEFT") and -g or g
                barOffsetY = 0
            end
            -- previewBar is scaled; convert own-space width and offsets to screen
            local barW = previewBar:GetWidth() * barScale

            if barPosition == "LEFT" then
                previewIcon:SetPoint("RIGHT", container, "RIGHT", -2, 0)
                previewBar:SetPoint("RIGHT", previewIcon, "LEFT", barOffsetX, barOffsetY)
            else
                previewIcon:SetPoint("LEFT", container, "LEFT", 2, 0)
                previewBar:SetPoint("LEFT", previewIcon, "RIGHT", barOffsetX, barOffsetY)
            end

            totalWidth = totalWidth + barW + math.abs(barOffsetX) * barScale
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
        -- Centered like the live bar-only layout, leaving room for outside-anchored text
        previewBar:SetPoint("CENTER", container, "CENTER", 0, 0)
        totalWidth = previewBar:GetWidth() * barScale
    elseif showTextOnly and caTextFS then
        -- Text-only mode: center text in container, size to fit
        caTextFS:SetPoint("CENTER", container, "CENTER", 0, 0)
        local textW = caTextFS:GetStringWidth() or 20
        local textH = caTextFS:GetStringHeight() or 16
        totalWidth = textW + 8
        containerHeight = math.max(containerHeight, textH + 4)
    end

    -- Grow to fit what was measured, then clamp. Dead space around the icon is fine; clipping
    -- is the backstop for offsets pinned to a slider limit, not the everyday case.
    -- contentHalf* accumulated in icon-local pixels; the container is unscaled, so convert.
    local iconScale = scaleFactor or 1
    local halfW, halfH = contentHalfW * iconScale, contentHalfH * iconScale
    local neededWidth = math.max(totalWidth + PREVIEW_CONTENT_PAD,
                                 2 * halfW + PREVIEW_CONTENT_PAD,
                                 PREVIEW_ICON_DISPLAY_SIZE + PREVIEW_CONTENT_PAD)
    local neededRowHeight = math.max(2 * halfH + PREVIEW_CONTENT_PAD, containerHeight) + 20

    -- The caller's row height is a floor, never a ceiling, so ScootAuras keeps its 152.
    rowHeight = math.min(math.max(rowHeight, neededRowHeight), maxRowHeight)
    containerHeight = rowHeight - 20

    row:SetHeight(rowHeight) -- re-set: the initial SetHeight ran before anything was measured
    container:SetSize(math.min(neededWidth, PREVIEW_MAX_CONTENT_WIDTH), containerHeight)
    container:SetPoint("CENTER", row, "CENTER", 0, 0)

    -- Anchor CA text for non-text-only modes (icon must be positioned first)
    if caTextFS and not showTextOnly then
        local cfg = container._caTextConfig
        -- Boost frame level so text renders above the icon texture (bar-hosted
        -- text was already leveled above the bar fill at creation)
        if caTextFrame and previewIcon and not (cfg and cfg.onBar) then
            caTextFrame:SetFrameLevel(previewIcon:GetFrameLevel() + 2)
        end
        if cfg and cfg.onBar and previewBar then
            -- Bar-hosted text: anchor to the bar itself (raw offsets; the text
            -- lives inside the scaled bar subtree), then grow the clip
            -- container for outside placements
            AnchorTextToBar(caTextFS, previewBar, cfg)
            if cfg.position == "outside" then
                local tw = (caTextFS:GetStringWidth() or 0) * barScale
                local th = (caTextFS:GetStringHeight() or 0) * barScale
                local anchor = cfg.outerAnchor or "RIGHT"
                if anchor == "LEFT" or anchor == "RIGHT" then
                    container:SetWidth(container:GetWidth() + 2 * (CA_GAP * barScale + tw))
                else
                    container:SetHeight(container:GetHeight() + 2 * (CA_GAP * barScale + th))
                end
            end
        elseif cfg and previewIcon then
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
                    local iconDisplayH = previewIcon and (previewIcon:GetHeight() * (scaleFactor or 1)) or 0
                    containerHeight = math.max(containerHeight, iconDisplayH + CA_GAP + textH)
                    container:SetWidth(math.max(math.max(totalWidth, textW) + 4, container:GetWidth()))
                    container:SetHeight(containerHeight)
                end
            end
        elseif not previewIcon then
            -- No icon or bar present: center in container
            caTextFS:SetPoint("CENTER", container, "CENTER", 0, 0)
        end
    end

    -- Grow the container for outside-anchored preview name text (same ceilings re-apply below)
    if nameTextFS and previewBar and nameTextCfg and nameTextCfg.position == "outside" then
        local tw = (nameTextFS:GetStringWidth() or 0) * (barScale or 1)
        local th = (nameTextFS:GetStringHeight() or 0) * (barScale or 1)
        local anchor = nameTextCfg.outerAnchor or "ABOVE"
        if anchor == "LEFT" or anchor == "RIGHT" then
            container:SetWidth(container:GetWidth() + 2 * (CA_GAP * (barScale or 1) + tw))
        else
            container:SetHeight(container:GetHeight() + 2 * (CA_GAP * (barScale or 1) + th))
        end
    end

    -- Outside-anchored CA text grows the container after the fact. Apply the same ceilings
    -- to it, and keep the row tall enough that a grown container still sits inside its row.
    if container:GetWidth() > PREVIEW_MAX_CONTENT_WIDTH then
        container:SetWidth(PREVIEW_MAX_CONTENT_WIDTH)
    end
    if container:GetHeight() + 20 > rowHeight then
        rowHeight = math.min(container:GetHeight() + 20, maxRowHeight)
        container:SetHeight(rowHeight - 20)
        row:SetHeight(rowHeight)
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
    if showCAText and caTextSource == "applications" then
        -- Duration text needs no legend entry: the animated countdown explains
        -- itself. Stacks keep the static "5" placeholder and its key.
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
    -- Animation: a 15-second looping countdown drives the duration text and
    -- the bar fill, so the preview shows what live tracking looks like.
    -- Hidden frames skip OnUpdate, so hiding the row pauses it for free.
    ----------------------------------------------------------------------------

    local animText = (caTextSource ~= "applications" and not caTextLiteral) and row._caTextFS or nil
    local animFill = row._barFill
    local animDrain = row._shapeCooldown
    if animText or animFill or animDrain then
        local epoch = options.timerEpoch
        local startTime
        if epoch then
            epoch.start = epoch.start or GetTime()
            startTime = epoch.start
        else
            startTime = GetTime()
        end
        local lastShown, lastCycle
        row:SetScript("OnUpdate", function()
            local remaining = 15 - ((GetTime() - startTime) % 15)
            if animFill then
                animFill:SetValue(remaining / 15)
            end
            if animText then
                local shown = math.ceil(remaining)
                if shown ~= lastShown then
                    lastShown = shown
                    animText:SetText(tostring(shown))
                end
            end
            if animDrain then
                -- One SetCooldown per cycle; the Cooldown animates itself. A
                -- past start (resumed epoch) lands mid-sweep correctly.
                local cycle = math.floor((GetTime() - startTime) / 15)
                if cycle ~= lastCycle then
                    lastCycle = cycle
                    animDrain:SetCooldown(startTime + cycle * 15, 15)
                end
            end
        end)
    end

    ----------------------------------------------------------------------------
    -- Public methods
    ----------------------------------------------------------------------------

    function row:Refresh()
        -- Preview is static; full panel rebuild handles updates
    end

    function row:Cleanup()
        self:SetScript("OnUpdate", nil)
        if self._subscribeKey then
            theme:Unsubscribe(self._subscribeKey)
        end
    end

    return row
end
