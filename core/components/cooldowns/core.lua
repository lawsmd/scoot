-- core.lua - Cooldown Manager: overlay styling, viewer mappings, shared utilities
local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil

--------------------------------------------------------------------------------
-- Overlay-based icon styling for CooldownViewer frames
--------------------------------------------------------------------------------

-- CooldownViewer icon frames are semi-protected in 12.0; overlay-only styling.
-- SetAlpha on viewer containers is safe and drives the opacity settings.
addon.CDM_TAINT_DIAG = addon.CDM_TAINT_DIAG or {
    skipAllCDM = true,  -- Always true in 12.0+; overlay-based styling only
}

--------------------------------------------------------------------------------
-- CDM Viewer Mappings
--------------------------------------------------------------------------------

addon.CDM_VIEWERS = {
    EssentialCooldownViewer = "essentialCooldowns",
    UtilityCooldownViewer = "utilityCooldowns",
    BuffIconCooldownViewer = "trackedBuffs",
    -- Note: trackedBars (BuffBarCooldownViewer) use direct styling, not overlays
}

local CDM_VIEWERS = addon.CDM_VIEWERS

--------------------------------------------------------------------------------
-- Shared Utility Functions
--------------------------------------------------------------------------------

local cachedDefaultFontFace
local function getDefaultFontFace()
    if not cachedDefaultFontFace then
        cachedDefaultFontFace = select(1, GameFontNormal:GetFont())
    end
    return cachedDefaultFontFace
end
addon.GetDefaultFontFace = getDefaultFontFace

-- Internal: returns r, g, b, a directly (no table allocation)
local function resolveCDMColorRGBA(cfg)
    local colorMode = cfg and cfg.colorMode
    if not colorMode then
        local c = cfg and cfg.color
        if c and (c[1] ~= 1 or c[2] ~= 1 or c[3] ~= 1 or (c[4] or 1) ~= 1) then
            return c[1], c[2], c[3], c[4] or 1
        end
        return 1, 1, 1, 1
    end
    if colorMode == "class" then
        local cr, cg, cb = addon.GetClassColorRGB("player")
        return cr or 1, cg or 1, cb or 1, 1
    elseif colorMode == "custom" then
        local c = cfg and cfg.color
        if c then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        return 1, 1, 1, 1
    else
        return 1, 1, 1, 1
    end
end

-- Exported: returns table (backward compat for external consumers)
local function resolveCDMColor(cfg)
    local r, g, b, a = resolveCDMColorRGBA(cfg)
    return {r, g, b, a}
end
addon.ResolveCDMColor = resolveCDMColor

--------------------------------------------------------------------------------
-- Icon Centering Support
--------------------------------------------------------------------------------
-- Repositions CDM icons symmetrically within the viewer after Blizzard layout.
-- Hooks RefreshLayout, then clears/sets points on visible icons.
--------------------------------------------------------------------------------

-- Center icons within a CDM viewer by repositioning them after Blizzard's layout
-- Two independent features controlled by separate settings:
--   centerAnchor: Row 1 centered symmetrically on anchor point
--   centerAdditionalRows: Rows 2+ centered under row 1 (vs left-aligned)
local function CenterIconsInViewer(viewerFrame, componentId)
    if not viewerFrame then return end
    if viewerFrame.IsForbidden and viewerFrame:IsForbidden() then return end

    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return end

    local db = component.db
    local centerOnAnchor = db.centerAnchor
    local centerAdditionalRows = db.centerAdditionalRows

    -- Early exit if neither feature is enabled
    if not centerOnAnchor and not centerAdditionalRows then return end

    -- Collect visible icon children
    local icons = {}
    local children = { viewerFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child and child:IsShown() and child.Icon then
            icons[#icons + 1] = child
        end
    end

    if #icons == 0 then return end

    -- Sort by layoutIndex for consistent ordering
    table.sort(icons, function(a, b)
        return (a.layoutIndex or 0) < (b.layoutIndex or 0)
    end)

    -- Get layout parameters
    local iconLimit = viewerFrame.iconLimit or 12
    local isHorizontal = viewerFrame.isHorizontal ~= false
    -- Enum.CooldownViewerIconDirection: Left=0, Right=1
    -- Convert to multiplier: Right/Up = +1 (normal), Left/Down = -1 (reversed)
    local iconDirectionRaw = viewerFrame.iconDirection
    local iconDirection = (iconDirectionRaw == 0) and -1 or 1

    -- Get icon dimensions and padding from first icon
    local iconWidth = 0
    local iconHeight = 0
    local padding = 0

    pcall(function()
        iconWidth = icons[1]:GetWidth() or 40
        iconHeight = icons[1]:GetHeight() or 40
        -- Estimate padding from Edit Mode settings or use default
        padding = viewerFrame.iconPadding or 2
    end)

    if iconWidth == 0 then iconWidth = 40 end
    if iconHeight == 0 then iconHeight = 40 end

    -- Group icons into rows/columns based on iconLimit
    local rows = {}
    for i = 1, #icons do
        local rowIndex = math.floor((i - 1) / iconLimit) + 1
        rows[rowIndex] = rows[rowIndex] or {}
        rows[rowIndex][#rows[rowIndex] + 1] = icons[i]
    end

    -- Determine growth direction for rows
    local growFromDirection = viewerFrame.growFromDirection or "TOP"
    local rowOffsetModifier = (growFromDirection == "BOTTOM" or growFromDirection == "RIGHT") and 1 or -1

    -- Calculate row 1's geometry (needed for alignment reference)
    local row1Count = #rows[1]

    if isHorizontal then
        local row1Width = (row1Count * iconWidth) + ((row1Count - 1) * padding)
        local row1LeftEdge, row1Center

        if centerOnAnchor then
            -- Row 1 centered on anchor: left edge is at -width/2
            row1LeftEdge = -row1Width / 2
            row1Center = 0  -- anchor point
        else
            -- Row 1 starts at anchor (Blizzard default): left edge at 0
            row1LeftEdge = 0
            row1Center = row1Width / 2
        end

        -- Position each row
        for rowNum, rowIcons in ipairs(rows) do
            local count = #rowIcons
            local rowWidth = (count * iconWidth) + ((count - 1) * padding)
            local startX
            local yOffset = (rowNum - 1) * (iconHeight + padding) * rowOffsetModifier

            if rowNum == 1 then
                -- Row 1: position based on centerOnAnchor
                if centerOnAnchor then
                    startX = (-rowWidth / 2) + (iconWidth / 2)
                else
                    startX = iconWidth / 2  -- Start from left edge (anchor)
                end
            else
                -- Rows 2+: position based on centerAdditionalRows
                if centerAdditionalRows then
                    -- Center this row on the same center as row 1
                    startX = row1Center - (rowWidth / 2) + (iconWidth / 2)
                else
                    -- Left-align to row 1's left edge
                    startX = row1LeftEdge + (iconWidth / 2)
                end
            end

            for i, icon in ipairs(rowIcons) do
                local xPos = (startX + (i - 1) * (iconWidth + padding)) * iconDirection
                pcall(function()
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", viewerFrame, "TOPLEFT", xPos, -iconHeight / 2 + yOffset)
                end)
            end
        end
    else
        -- Vertical layout: similar logic but for Y axis
        local row1Height = (row1Count * iconHeight) + ((row1Count - 1) * padding)
        local row1TopEdge, row1Center

        if centerOnAnchor then
            -- Row 1 centered on anchor: top edge is at +height/2
            row1TopEdge = row1Height / 2
            row1Center = 0  -- anchor point
        else
            -- Row 1 starts at anchor (Blizzard default): top edge at 0
            row1TopEdge = 0
            row1Center = -row1Height / 2
        end

        -- Position each row (column in vertical layout)
        for rowNum, rowIcons in ipairs(rows) do
            local count = #rowIcons
            local rowHeight = (count * iconHeight) + ((count - 1) * padding)
            local startY
            local xOffset = (rowNum - 1) * (iconWidth + padding) * rowOffsetModifier

            if rowNum == 1 then
                -- Row 1: position based on centerOnAnchor
                if centerOnAnchor then
                    startY = (rowHeight / 2) - (iconHeight / 2)
                else
                    startY = -iconHeight / 2  -- Start from top edge (anchor)
                end
            else
                -- Rows 2+: position based on centerAdditionalRows
                if centerAdditionalRows then
                    -- Center this row on the same center as row 1
                    startY = row1Center + (rowHeight / 2) - (iconHeight / 2)
                else
                    -- Top-align to row 1's top edge
                    startY = row1TopEdge - (iconHeight / 2)
                end
            end

            for i, icon in ipairs(rowIcons) do
                local yPos = (startY - (i - 1) * (iconHeight + padding)) * iconDirection
                pcall(function()
                    icon:ClearAllPoints()
                    icon:SetPoint("CENTER", viewerFrame, "TOPLEFT", iconWidth / 2 + xOffset, yPos)
                end)
            end
        end
    end
end

-- Exposed function to refresh center anchor (called when setting changes)
function addon.RefreshCDMCenterAnchor(componentId)
    if not componentId then return end

    local viewerName
    for vn, cid in pairs(CDM_VIEWERS) do
        if cid == componentId then
            viewerName = vn
            break
        end
    end

    if not viewerName then return end

    local viewerFrame = _G[viewerName]
    if viewerFrame then
        C_Timer.After(0, function()
            local component = addon.Components and addon.Components[componentId]
            local db = component and component.db
            if db and not db.centerAnchor and not db.centerAdditionalRows then
                -- Centering disabled: re-run Layout to restore default positions
                -- (the Layout hook early-exits since centering is off)
                pcall(function() viewerFrame:Layout() end)
            else
                CenterIconsInViewer(viewerFrame, componentId)
            end
        end)
    end
end

-- Apply center anchor on orientation change (called from Edit Mode sync)
-- Orientation changes trigger RefreshLayout → Layout() → the Layout hook,
-- so re-running Layout is enough to pick up the new orientation.
function addon.OnCDMOrientationChanged(viewerFrame, componentId)
    if not viewerFrame or not componentId then return end
    C_Timer.After(0.1, function()
        pcall(function() viewerFrame:Layout() end)
    end)
end

--------------------------------------------------------------------------------
-- Overlay System
--------------------------------------------------------------------------------

addon.CDMOverlays = addon.CDMOverlays or {}
local Overlays = addon.CDMOverlays

local overlayPool = {}
local activeOverlays = {}  -- Map from CDM icon frame to overlay frame

-- Track which icons have been sized (weak keys for GC)
-- Using a local table instead of writing to Blizzard frames avoids taint
-- that can cause allowAvailableAlert and other fields to become secret values
local sizedIcons = setmetatable({}, { __mode = "k" })

-- Track cached FontString references per cooldown frame (weak keys for GC)
-- Using a local table instead of writing _scooterFontString to Blizzard frames avoids taint
local scootFontStrings = setmetatable({}, { __mode = "k" })

-- Track which FontStrings have been decoupled from parent alpha (weak keys for GC)
local textAlphaDecoupled = setmetatable({}, { __mode = "k" })

-- Track icon zoom, swipe modifications, and hidden rings (weak keys for GC)
local zoomedIcons = setmetatable({}, { __mode = "k" })
local modifiedSwipes = setmetatable({}, { __mode = "k" })
local hiddenRings = setmetatable({}, { __mode = "k" })

-- Cache GetChildren() results per viewer to avoid temporary table allocation on every pass
local viewerChildrenCache = {}

local function invalidateChildrenCache(viewerFrameName)
    viewerChildrenCache[viewerFrameName] = nil
end

local function getViewerChildren(viewer, viewerFrameName)
    local cached = viewerChildrenCache[viewerFrameName]
    if cached then return cached end
    cached = { viewer:GetChildren() }
    viewerChildrenCache[viewerFrameName] = cached
    return cached
end

-- Forward declarations
local resizeProcGlow  -- defined in Icon Sizing section, used by hookProcGlowResizing
local applyPerIconCooldownOpacity  -- defined in Per-Icon Cooldown Opacity section
local applyViewerOpacity  -- defined in Viewer Opacity section, used by ApplyToViewer

-- Check if Blizzard's DebuffBorder is present and visible on a CDM icon
-- Used to avoid drawing Scoot borders over Blizzard's debuff-type borders
-- (Magic, Poison, Bleed, Curse, Disease) which have special colored atlases and
-- pandemic timer animations. Only affects trackedBuffs (BuffIconCooldownViewer).
local function hasBlizzardDebuffBorder(itemFrame)
    if not itemFrame then return false end
    local debuffBorder = itemFrame.DebuffBorder
    -- Check if the Texture child is shown, not the frame itself
    -- The DebuffBorder frame is always present, but Texture is only shown for harmful auras
    -- (see AuraUtil.SetAuraBorderAtlasFromAura in Blizzard source)
    if debuffBorder and debuffBorder.Texture and debuffBorder.Texture.IsShown and debuffBorder.Texture:IsShown() then
        return true
    end
    return false
end

--------------------------------------------------------------------------------
-- Overlay Frame Management
--------------------------------------------------------------------------------

local function createOverlayFrame(parent)
    -- Child frame for frame level ordering with SpellActivationAlert (proc glow)
    -- Creating a child frame doesn't cause taint; only modifying protected properties does
    local overlay = CreateFrame("Frame", nil, parent or UIParent)
    overlay:EnableMouse(false)

    -- Separate border frame (sibling of overlay, NOT child) at a lower frame level
    -- so borders render below the pixel glow while text on overlay renders above it.
    -- Must be a sibling because WoW propagates SetFrameLevel from parent to children.
    local borderFrame = CreateFrame("Frame", nil, parent or UIParent)
    borderFrame:EnableMouse(false)
    overlay.borderFrame = borderFrame

    -- Border textures live on borderFrame (low level, below glow)
    overlay.borderEdges = {
        Top = borderFrame:CreateTexture(nil, "BORDER", nil, 1),
        Bottom = borderFrame:CreateTexture(nil, "BORDER", nil, 1),
        Left = borderFrame:CreateTexture(nil, "BORDER", nil, 1),
        Right = borderFrame:CreateTexture(nil, "BORDER", nil, 1),
    }

    -- Create atlas border texture for non-square styles
    overlay.atlasBorder = borderFrame:CreateTexture(nil, "BORDER", nil, 1)
    overlay.atlasBorder:Hide()

    -- Propagate overlay visibility to borderFrame automatically
    overlay:HookScript("OnShow", function() borderFrame:Show() end)
    overlay:HookScript("OnHide", function() borderFrame:Hide() end)

    -- Text FontStrings on overlay (high level, above glow)
    overlay.cooldownText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.cooldownText:SetDrawLayer("OVERLAY", 7)
    overlay.cooldownText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.cooldownText:Hide()

    overlay.chargeText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.chargeText:SetDrawLayer("OVERLAY", 7)
    overlay.chargeText:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -2, 2)
    overlay.chargeText:Hide()

    overlay.keybindText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.keybindText:SetDrawLayer("OVERLAY", 7)
    overlay.keybindText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 2, -2)
    overlay.keybindText:Hide()

    return overlay
end

local function getOverlay(parent)
    local overlay = table.remove(overlayPool)
    if not overlay then
        overlay = createOverlayFrame(parent)
    elseif parent then
        -- Re-parent pooled overlay and its sibling borderFrame to new parent
        overlay:SetParent(parent)
        if overlay.borderFrame then
            overlay.borderFrame:SetParent(parent)
        end
    end
    return overlay
end

local function releaseOverlay(overlay)
    if not overlay then return end
    overlay:Hide()  -- OnHide hook propagates to borderFrame
    overlay:ClearAllPoints()
    overlay:SetParent(UIParent)  -- Prevents holding CDM icon reference
    overlay:SetAlpha(1.0)  -- Reset alpha when returning to pool
    if overlay.borderFrame then
        overlay.borderFrame:ClearAllPoints()
        overlay.borderFrame:SetParent(UIParent)
    end
    if overlay.cooldownText then
        overlay.cooldownText:SetText("")
        overlay.cooldownText:Hide()
    end
    if overlay.chargeText then
        overlay.chargeText:SetText("")
        overlay.chargeText:Hide()
    end
    if overlay.keybindText then
        overlay.keybindText:SetText("")
        overlay.keybindText:Hide()
    end
    table.insert(overlayPool, overlay)
end

--------------------------------------------------------------------------------
-- Border Application (overlay frames, not Blizzard's)
--------------------------------------------------------------------------------

-- Hide edge-based square border textures
local function hideEdgeBorder(overlay)
    if not overlay or not overlay.borderEdges then return end
    for _, tex in pairs(overlay.borderEdges) do
        tex:Hide()
    end
end

-- Hide atlas-based border texture
local function hideAtlasBorder(overlay)
    if not overlay or not overlay.atlasBorder then return end
    overlay.atlasBorder:Hide()
end

-- Apply square border (edges meet at corners, no gaps)
local function applySquareBorder(overlay, opts)
    if not overlay or not overlay.borderEdges then return end

    -- Hide atlas border if it was previously shown
    hideAtlasBorder(overlay)

    local edges = overlay.borderEdges
    local thickness = math.max(1, tonumber(opts.thickness) or 1)
    local col = opts.color or {0, 0, 0, 1}
    local r, g, b, a = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 1

    -- Set color on all edges
    for _, tex in pairs(edges) do
        tex:SetColorTexture(r, g, b, a)
    end

    -- Inset: positive = move border inward, negative = move outward
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0

    -- Fractional insets need pixel-grid snapping relaxed or they round back to whole pixels
    if addon.SetBorderTexturePixelSnap then
        local subPixel = addon.BorderInsetIsSubPixel(insetH, insetV)
        for _, tex in pairs(edges) do
            addon.SetBorderTexturePixelSnap(tex, subPixel)
        end
    end

    -- Horizontal edges span full width; vertical edges trimmed to avoid corner overlap
    edges.Top:ClearAllPoints()
    edges.Top:SetPoint("TOPLEFT", overlay, "TOPLEFT", -insetH, insetV)
    edges.Top:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", insetH, insetV)
    edges.Top:SetHeight(thickness)

    edges.Bottom:ClearAllPoints()
    edges.Bottom:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -insetH, -insetV)
    edges.Bottom:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", insetH, -insetV)
    edges.Bottom:SetHeight(thickness)

    -- Vertical edges: trimmed by thickness at top/bottom to avoid corner overlap
    edges.Left:ClearAllPoints()
    edges.Left:SetPoint("TOPLEFT", overlay, "TOPLEFT", -insetH, insetV - thickness)
    edges.Left:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", -insetH, -insetV + thickness)
    edges.Left:SetWidth(thickness)

    edges.Right:ClearAllPoints()
    edges.Right:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", insetH, insetV - thickness)
    edges.Right:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", insetH, -insetV + thickness)
    edges.Right:SetWidth(thickness)

    for _, tex in pairs(edges) do
        tex:Show()
    end
end

-- Apply atlas-based border style
local function applyAtlasBorder(overlay, opts, styleDef)
    if not overlay or not overlay.atlasBorder then return end

    -- Hide square border edges
    hideEdgeBorder(overlay)

    local atlasTex = overlay.atlasBorder

    -- For atlas borders: use style's default color (typically white) unless tint is enabled
    -- Lets the atlas texture show its natural colors when tint is off
    local col
    if opts.tintEnabled and opts.tintColor then
        col = opts.tintColor
    else
        col = styleDef.defaultColor or {1, 1, 1, 1}
    end
    local r, g, b, a = col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1

    local atlasName = styleDef.atlas
    if not atlasName then return end

    atlasTex:SetAtlas(atlasName, true)
    atlasTex:SetVertexColor(r, g, b, a)

    -- Calculate expansion based on style definition and inset
    local baseExpandX = styleDef.expandX or 0
    local baseExpandY = styleDef.expandY or baseExpandX
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0
    local expandX = baseExpandX - insetH
    local expandY = baseExpandY - insetV

    -- Fractional insets need pixel-grid snapping relaxed or they round back to whole pixels
    if addon.SetBorderTexturePixelSnap then
        addon.SetBorderTexturePixelSnap(atlasTex, addon.BorderInsetIsSubPixel(insetH, insetV))
    end

    -- Position the atlas texture
    atlasTex:ClearAllPoints()
    atlasTex:SetPoint("TOPLEFT", overlay, "TOPLEFT", -expandX, expandY)
    atlasTex:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", expandX, -expandY)
    atlasTex:Show()
end

local function applyBorderToOverlay(overlay, opts)
    if not overlay then return end

    local style = opts.style or "square"

    -- Get style definition for non-square styles
    local styleDef = nil
    if style ~= "square" and addon.IconBorders and addon.IconBorders.GetStyle then
        styleDef = addon.IconBorders.GetStyle(style)
    end

    -- Apply the appropriate border type
    if styleDef and styleDef.type == "atlas" and styleDef.atlas then
        applyAtlasBorder(overlay, opts, styleDef)
    else
        -- Default to square border (with chamfered corners)
        applySquareBorder(overlay, opts)
    end
end

local function hideBorderOnOverlay(overlay)
    hideEdgeBorder(overlay)
    hideAtlasBorder(overlay)
end

--------------------------------------------------------------------------------
-- Text Overlay Application (overlay FontStrings, not Blizzard's)
--------------------------------------------------------------------------------

local function applyTextStyleToFontString(fontString, cfg, defaultSize)
    if not fontString then return end

    local size = tonumber(cfg and cfg.size) or defaultSize or 14
    local style = (cfg and cfg.style) or "OUTLINE"
    local fontFace = getDefaultFontFace()

    if cfg and cfg.fontFace and addon.ResolveFontFace then
        fontFace = addon.ResolveFontFace(cfg.fontFace) or fontFace
    end

    if addon.ApplyFontStyle then
        addon.ApplyFontStyle(fontString, fontFace, size, style)
    else
        fontString:SetFont(fontFace, size, style)
    end

    local color = resolveCDMColor(cfg)
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    fontString:SetTextColor(r, g, b, a)
end

--------------------------------------------------------------------------------
-- Direct Text Styling (12.0)
--------------------------------------------------------------------------------
-- SetFont/SetTextColor/SetShadowOffset work on protected FontStrings.
-- Hooks CooldownFrame_Set, finds the FontString, and styles it directly.
--------------------------------------------------------------------------------

local directTextStyleHooked = false
local CDM_VIEWER_NAMES = {
    ["EssentialCooldownViewer"] = "essentialCooldowns",
    ["UtilityCooldownViewer"] = "utilityCooldowns",
    ["BuffIconCooldownViewer"] = "trackedBuffs",
}

-- ABE (ActionBarsEnhanced) interop: when loaded, ABE manages its own proc animations
local abeLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ActionBarsEnhanced")

-- Find the FlipBook animation within an AnimationGroup (duck-type check)
local function GetFlipBook(animGroup)
    if not animGroup then return nil end
    for i = 1, animGroup:GetNumAnimations() do
        local anim = select(i, animGroup:GetAnimations())
        if anim and anim.SetFlipBookRows then
            return anim
        end
    end
    return nil
end

-- Find the cooldown text FontString inside a Cooldown frame
local function getCooldownFontString(cooldownFrame)
    if not cooldownFrame then return nil end

    -- Use cached reference if available
    if scootFontStrings[cooldownFrame] then
        return scootFontStrings[cooldownFrame]
    end

    -- Prefer the dedicated Cooldown widget API (C++-managed countdown FontString)
    if cooldownFrame.GetCountdownFontString then
        local ok, fs = pcall(cooldownFrame.GetCountdownFontString, cooldownFrame)
        if ok and fs then
            scootFontStrings[cooldownFrame] = fs
            return fs
        end
    end

    -- Fallback: scan regions (for non-Cooldown frame types)
    if cooldownFrame.GetRegions then
        for _, region in ipairs({cooldownFrame:GetRegions()}) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                scootFontStrings[cooldownFrame] = region
                return region
            end
        end
    end
end

-- Find the charge/stack count FontString inside an icon frame
local function getChargeCountFontString(iconFrame)
    if not iconFrame then return nil end

    -- ChargeCount (for cooldowns with charges)
    if iconFrame.ChargeCount then
        local charge = iconFrame.ChargeCount
        -- Check for .Current or .Text child
        local fs = charge.Current or charge.Text or charge.Count
        if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then
            return fs
        end
        -- Search regions
        if charge.GetRegions then
            for _, region in ipairs({charge:GetRegions()}) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end

    -- Applications (for buff stacks)
    if iconFrame.Applications then
        local apps = iconFrame.Applications
        if apps.GetRegions then
            for _, region in ipairs({apps:GetRegions()}) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end
end

-- Identify which CDM viewer a cooldown belongs to
local function identifyCooldownSource(cooldownFrame)
    if not cooldownFrame then return nil end

    local parent = cooldownFrame:GetParent()
    if not parent then return nil end

    -- parent should be the icon frame, check its parent for the viewer
    local viewerFrame = parent:GetParent()
    if viewerFrame and viewerFrame.GetName then
        local viewerName = viewerFrame:GetName()
        if viewerName and CDM_VIEWER_NAMES[viewerName] then
            return CDM_VIEWER_NAMES[viewerName]
        end
    end
end

-- Get text settings for a component
local function getCooldownTextSettings(componentId)
    if not componentId then return nil end
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return nil end
    return component.db.textCooldown
end

local function getChargeTextSettings(componentId)
    if not componentId then return nil end
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return nil end
    return component.db.textStacks
end

-- Apply font styling directly to a Blizzard FontString (no GetText!)
-- isChargeText: if true, uses BOTTOMRIGHT anchor; otherwise uses CENTER
-- parentFrame: the frame to anchor to (defaults to fontString's parent)
local function applyFontStyleDirect(fontString, cfg, isChargeText, parentFrame, skipColor)
    if not fontString or not cfg then return end

    local size = tonumber(cfg.size) or 14
    local style = cfg.style or "OUTLINE"
    local r, g, b, a = resolveCDMColorRGBA(cfg)
    local fontFace = getDefaultFontFace()

    if cfg.fontFace and addon.ResolveFontFace then
        fontFace = addon.ResolveFontFace(cfg.fontFace) or fontFace
    end

    pcall(fontString.SetFont, fontString, fontFace, size, style)
    if not skipColor then
        pcall(fontString.SetTextColor, fontString, r, g, b, a)
    end

    if cfg.shadowX or cfg.shadowY then
        pcall(fontString.SetShadowOffset, fontString, cfg.shadowX or 1, cfg.shadowY or -1)
    end

    -- Always reposition if cfg.offset exists (even if values are 0) to ensure proper reset behavior
    if cfg.offset or cfg.anchor then
        local offsetX = (cfg.offset and tonumber(cfg.offset.x)) or 0
        local offsetY = (cfg.offset and tonumber(cfg.offset.y)) or 0
        local anchor = cfg.anchor
        if not anchor then
            anchor = isChargeText and "BOTTOMRIGHT" or "CENTER"
        end
        local anchorTo = parentFrame or fontString:GetParent()
        if anchorTo then
            pcall(fontString.ClearAllPoints, fontString)
            pcall(fontString.SetPoint, fontString, anchor, anchorTo, anchor, offsetX, offsetY)
        end
    end
end

addon.ApplyFontStyleDirect = applyFontStyleDirect

-- Apply cooldown text styling when a cooldown is set
local function applyCooldownTextStyle(cooldownFrame)
    if not cooldownFrame then return end
    if cooldownFrame.IsForbidden and cooldownFrame:IsForbidden() then return end

    -- Skip action bar cooldowns to avoid taint
    local parent = cooldownFrame:GetParent()
    if parent then
        local parentName = parent:GetName() or ""
        if parentName:match("ActionButton") or parentName:match("MultiBar") or
           parentName:match("PetActionButton") or parentName:match("StanceButton") then
            return
        end
    end

    local componentId = identifyCooldownSource(cooldownFrame)
    if not componentId then return end

    -- Style cooldown timer text (if configured)
    local cfg = getCooldownTextSettings(componentId)
    if cfg then
        -- Clear cached FontString reference to force re-scan
        scootFontStrings[cooldownFrame] = nil

        local fontString = getCooldownFontString(cooldownFrame)
        if fontString then
            -- Cooldown text uses CENTER anchor by default
            applyFontStyleDirect(fontString, cfg, false, cooldownFrame)
        end
    end

    -- Style charge/stack count text (independent of cooldown text config)
    if parent then
        local chargeCfg = getChargeTextSettings(componentId)
        if chargeCfg then
            local chargeFS = getChargeCountFontString(parent)
            if chargeFS then
                -- Charge/stack text uses BOTTOMRIGHT anchor by default
                local iconTexture = parent.Icon or parent.icon
                applyFontStyleDirect(chargeFS, chargeCfg, true, iconTexture or parent)
            end
        end
    end
end

-- Hook into Blizzard's cooldown system to intercept updates
local function hookCooldownTextStyling()
    if directTextStyleHooked then return end

    -- Hook CooldownFrame_Set (the main function that updates cooldowns)
    if CooldownFrame_Set then
        hooksecurefunc("CooldownFrame_Set", function(cooldownFrame, start, duration, enable, forceShowDrawEdge, modRate)
            if not cooldownFrame then return end
            if cooldownFrame.IsForbidden and cooldownFrame:IsForbidden() then return end

            -- Defer text styling to next frame for safety
            C_Timer.After(0, function()
                if cooldownFrame and not (cooldownFrame.IsForbidden and cooldownFrame:IsForbidden()) then
                    pcall(applyCooldownTextStyle, cooldownFrame)
                end
            end)
        end)
    end

    directTextStyleHooked = true
end

-- Proc start style -> animation ID mapping
local PROC_START_ANIM_IDS = {
    flashPulse = "procStartFlashPulse",
    scaleBurst = "procStartScaleBurst",
    ringExpand = "procStartRingExpand",
    crossFlare = "procStartCrossFlare",
    diamondBurst = "procStartDiamondBurst",
    starburst = "procStartStarburst",
    pixelScatter = "procStartPixelScatter",
    spinFade = "procStartSpinFade",
    cornerBrackets = "procStartCornerBrackets",
    doubleRing = "procStartDoubleRing",
}

-- Hook ActionButtonSpellAlertManager:ShowAlert to resize proc glow on custom-sized icons.
-- The alert is created lazily on first proc, so ApplyIconSize can't catch it at init time.
local procGlowHooked = false
local function hookProcGlowResizing()
    if procGlowHooked then return end
    if not ActionButtonSpellAlertManager then return end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, actionButton)
        local sizeInfo = sizedIcons[actionButton]
        if sizeInfo then
            resizeProcGlow(actionButton, sizeInfo.width, sizeInfo.height)
        end
        -- Hide ProcStart / start pixel glow — must run regardless of custom sizing
        if not abeLoaded then
            pcall(function()
                local alert = actionButton.SpellActivationAlert
                if not alert then return end

                local viewerFrame = actionButton:GetParent()
                if not viewerFrame or not viewerFrame.GetName then return end
                local componentId = CDM_VIEWER_NAMES[viewerFrame:GetName()]
                if not componentId then return end
                local component = addon.Components and addon.Components[componentId]
                if not component or not component.db then return end

                local loopStyle = component.db.procLoopStyle
                local useCustomLoop = loopStyle and loopStyle ~= "default" and addon.PixelGlow

                -- Determine proc start behavior
                local procStartStyle = component.db.procStartStyle
                if procStartStyle == nil then
                    procStartStyle = component.db.hideProcStart and "none" or "default"
                end

                -- Handle proc start (isolated pcall — must never break proc loop)
                -- Only play on the FIRST ShowAlert call, not repeated calls while proc is active
                local existingGlow = addon.PixelGlow and addon.PixelGlow.GetForIcon(actionButton)
                local isRepeatedCall = existingGlow and existingGlow:IsPlaying()

                if procStartStyle ~= "default" then
                    pcall(function()
                        -- Suppress Blizzard's ProcStart
                        if alert.ProcStartFlipbook then
                            alert.ProcStartFlipbook:Hide()
                        end
                        if alert.ProcStartAnim then
                            alert.ProcStartAnim:Stop()
                        end

                        -- Play custom proc start only on initial proc (not repeated ShowAlert)
                        if not isRepeatedCall then
                            local animId = PROC_START_ANIM_IDS[procStartStyle]
                            if animId and addon.ProcStart then
                                addon.ProcStart.PlayForIcon(actionButton, {
                                    style = animId,
                                    colorMode = component.db.procStartColor or "custom",
                                    customColor = component.db.procStartCustomColor or {1, 1, 1, 1},
                                    scale = component.db.procStartScale or 1,
                                    iconW = sizeInfo and sizeInfo.width,
                                    iconH = sizeInfo and sizeInfo.height,
                                })
                            end
                        end
                    end)
                end

                -- Handle proc loop (always runs regardless of proc start outcome)
                if useCustomLoop then
                    alert.ProcStartAnim:Stop()
                    alert:Hide()
                    local config = {
                        style = (loopStyle == "pixelDots") and "dots" or "dashes",
                        colorMode = component.db.procLoopColor or "custom",
                        customColor = component.db.procLoopCustomColor or {1, 0.84, 0, 1},
                        speed = component.db.procLoopSpeed or 25,
                        iconW = sizeInfo and sizeInfo.width,
                        iconH = sizeInfo and sizeInfo.height,
                        insetH = component.db.procLoopInsetH or 0,
                        insetV = component.db.procLoopInsetV or 0,
                    }
                    local existingGlow = addon.PixelGlow.GetForIcon(actionButton)
                    if not existingGlow or not existingGlow:IsPlaying() then
                        addon.PixelGlow.StartForIcon(actionButton, config)
                    end
                end
            end)
        end
    end)

    -- Hook HideAlert to clean up pixel glows and proc start overlays
    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, actionButton)
        if addon.PixelGlow then
            addon.PixelGlow.RemovePending(actionButton)
            addon.PixelGlow.ReleaseForIcon(actionButton)
        end
        if addon.ProcStart then
            addon.ProcStart.StopForIcon(actionButton)
        end
    end)

    procGlowHooked = true
end

-- Retroactive scan: find CDM icons where a Blizzard proc glow is active but
-- should be replaced by a pixel glow (or vice-versa after profile switch).
-- Covers the reload timing race (ShowAlert fires before the hook is installed)
-- and profile switches where active procs need glow-type changes.
local function scanAndReplaceActiveBlizzardGlows()
    if abeLoaded then return end
    if not addon.PixelGlow then return end

    for viewerName, componentId in pairs(CDM_VIEWER_NAMES) do
        if componentId ~= "trackedBuffs" then
            local viewer = _G[viewerName]
            if viewer and viewer.IsShown and viewer:IsShown() then
                local component = addon.Components and addon.Components[componentId]
                if component and component.db then
                    local style = component.db.procLoopStyle
                    local children = { viewer:GetChildren() }

                    for _, child in ipairs(children) do
                        pcall(function()
                            if not child then return end

                            -- Detect active proc via visual state
                            local alert = child.SpellActivationAlert
                            local blizzardGlowActive = alert and alert.IsShown and alert:IsShown()
                            local existingGlow = addon.PixelGlow.GetForIcon(child)
                            local scootGlowActive = existingGlow and existingGlow:IsPlaying()

                            if not blizzardGlowActive and not scootGlowActive then return end

                            if style and style ~= "default" then
                                -- Custom style: suppress Blizzard glow, ensure pixel glow
                                if blizzardGlowActive and alert then
                                    alert.ProcStartAnim:Stop()
                                    alert:Hide()
                                end
                                if not scootGlowActive then
                                    local sizeInfo = sizedIcons[child]
                                    local config = {
                                        style = (style == "pixelDots") and "dots" or "dashes",
                                        colorMode = component.db.procLoopColor or "custom",
                                        customColor = component.db.procLoopCustomColor or {1, 0.84, 0, 1},
                                        speed = component.db.procLoopSpeed or 25,
                                        iconW = sizeInfo and sizeInfo.width,
                                        iconH = sizeInfo and sizeInfo.height,
                                        insetH = component.db.procLoopInsetH or 0,
                                        insetV = component.db.procLoopInsetV or 0,
                                    }
                                    addon.PixelGlow.StartForIcon(child, config)
                                end
                            else
                                -- Default style: release pixel glow, restore Blizzard glow
                                if scootGlowActive then
                                    addon.PixelGlow.ReleaseForIcon(child)
                                    if alert then
                                        alert:Show()
                                        if alert.ProcLoop and not alert.ProcLoop:IsPlaying() then
                                            alert.ProcLoop:Play()
                                        end
                                        if alert.ProcLoopFlipbook then
                                            alert.ProcLoopFlipbook:Show()
                                        end
                                    end
                                end
                            end
                        end)
                    end
                end
            end
        end
    end
end

-- Exposed function to refresh text styling (called when settings change)
function addon.RefreshCDMTextStyling()
    -- Apply to all existing cooldowns in CDM viewers
    for viewerName, componentId in pairs(CDM_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        if viewer and viewer.IsShown and viewer:IsShown() then
            local children = {viewer:GetChildren()}
            for _, child in ipairs(children) do
                if child and child.Cooldown then
                    pcall(applyCooldownTextStyle, child.Cooldown)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Frame Validation
--------------------------------------------------------------------------------

local function isValidCDMItemFrame(frame)
    if not frame then return false end
    if frame.Icon or frame.Cooldown or frame.ChargeCount or frame.Applications then
        return true
    end
    if frame.GetIconTexture then
        return true
    end
    return false
end

local function isFrameVisible(frame)
    if not frame then return false end
    if frame.IsShown and not frame:IsShown() then
        return false
    end
    if frame.IsVisible and not frame:IsVisible() then
        return false
    end
    if frame.GetWidth and frame.GetHeight then
        local ok, w, h = pcall(function() return frame:GetWidth(), frame:GetHeight() end)
        if ok and type(w) == "number" and type(h) == "number"
           and not (issecretvalue and issecretvalue(w))
           and not (issecretvalue and issecretvalue(h))
           and (w < 5 or h < 5) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Public Overlay API
--------------------------------------------------------------------------------

-- Raise Blizzard's text-bearing child frames (ChargeCount, Applications)
-- above all Scoot layers so charges/stacks text renders on top of borders.
local function raiseBlizzardTextFrames(cdmIcon, targetLevel)
    if cdmIcon.ChargeCount and cdmIcon.ChargeCount.SetFrameLevel then
        pcall(cdmIcon.ChargeCount.SetFrameLevel, cdmIcon.ChargeCount, targetLevel)
    end
    if cdmIcon.Applications and cdmIcon.Applications.SetFrameLevel then
        pcall(cdmIcon.Applications.SetFrameLevel, cdmIcon.Applications, targetLevel)
    end
end

function Overlays.GetOrCreateForIcon(cdmIcon)
    if not cdmIcon then return nil end
    if not isValidCDMItemFrame(cdmIcon) then
        return nil
    end

    local existing = activeOverlays[cdmIcon]
    if existing then
        return existing
    end

    -- Create overlay as child of CDM icon - this ensures proper layering
    -- with SpellActivationAlert (proc glow). Creating a child frame is safe.
    local overlay = getOverlay(cdmIcon)
    activeOverlays[cdmIcon] = overlay

    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", 0, 0)

    -- Split frame levels across sibling frames:
    --   borderFrame (N+2): borders above icon, below glow (N+10)
    --   overlay (N+12): text above glow
    local iconLevel = cdmIcon:GetFrameLevel()
    overlay:SetFrameLevel(iconLevel + 12)

    if overlay.borderFrame then
        overlay.borderFrame:ClearAllPoints()
        overlay.borderFrame:SetAllPoints(overlay)
        overlay.borderFrame:SetFrameLevel(iconLevel + 2)
    end

    -- Raise Blizzard's text-bearing child frames above every Scoot layer
    raiseBlizzardTextFrames(cdmIcon, iconLevel + 14)

    overlay:Show()  -- OnShow hook propagates to borderFrame
    return overlay
end

function Overlays.ReleaseForIcon(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        activeOverlays[cdmIcon] = nil
        releaseOverlay(overlay)
    end
end

function Overlays.ApplyBorder(cdmIcon, opts)
    if not cdmIcon then return end

    if not isFrameVisible(cdmIcon) then
        Overlays.ReleaseForIcon(cdmIcon)
        return
    end

    local overlay = Overlays.GetOrCreateForIcon(cdmIcon)
    if not overlay then return end

    if opts and opts.enable then
        applyBorderToOverlay(overlay, opts)
        overlay:Show()
    else
        hideBorderOnOverlay(overlay)
        overlay:Hide()
    end
end

function Overlays.HideBorder(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        hideBorderOnOverlay(overlay)
    end
end

function Overlays.ApplyText(cdmIcon, opts)
    if not cdmIcon then return end

    if not isFrameVisible(cdmIcon) then
        return
    end

    local overlay = Overlays.GetOrCreateForIcon(cdmIcon)
    if not overlay then return end

    if opts then
        overlay:Show()
    end
end

function Overlays.HideText(cdmIcon)
    -- No-op: overlay text FontStrings are not created in the current codebase
end

function Overlays.RefreshText(cdmIcon, opts)
    -- No-op: overlay text FontStrings are not created in the current codebase
end

function Overlays.HideAll()
    for cdmIcon, overlay in pairs(activeOverlays) do
        releaseOverlay(overlay)
    end
    wipe(activeOverlays)
end

function Overlays.HideOverlay(cdmIcon)
    if not cdmIcon then return end
    local overlay = activeOverlays[cdmIcon]
    if overlay then
        overlay:Hide()
    end
end

--------------------------------------------------------------------------------
-- Icon Sizing (12.0)
--------------------------------------------------------------------------------
-- SetSize() on CDM icons is safe when writing from settings (no reads).
-- Texture coordinates are adjusted to prevent stretching on non-square sizes.
--------------------------------------------------------------------------------

-- Shared texcoord utility: composes zoom + aspect-ratio crop + optional baseline inset.
-- baseInset allows Custom Groups to layer their border-art removal crop.
addon.CalculateIconTexCoords = function(aspectRatio, zoomPct, baseInset)
    local inset = (baseInset or 0) + math.max(0, math.min(0.30, (tonumber(zoomPct) or 0) / 100))
    local left, right, top, bottom = inset, 1 - inset, inset, 1 - inset
    local range = 1 - 2 * inset
    if aspectRatio > 1.0 then
        local offset = (1.0 - 1.0 / aspectRatio) / 2.0
        top = top + offset * range
        bottom = bottom - offset * range
    elseif aspectRatio < 1.0 then
        local offset = (1.0 - aspectRatio) / 2.0
        left = left + offset * range
        right = right - offset * range
    end
    return left, right, top, bottom
end

-- Resize SpellActivationAlert and its flipbook textures to match custom icon dimensions.
-- ProcStartFlipbook: use SetScale (immediate render transform) instead of SetSize (deferred
-- layout property). SetSize mid-FlipBook causes a hitch; SetScale applies in the GPU pass.
-- ProcLoopFlipbook: explicit sizing is fine — it doesn't start until ProcStartAnim finishes
-- (0.7s), giving the layout engine time to resolve.
resizeProcGlow = function(cdmIcon, iconWidth, iconHeight)
    if not cdmIcon.SpellActivationAlert then return end
    pcall(function()
        local alert = cdmIcon.SpellActivationAlert
        local glowW, glowH = iconWidth * 1.4, iconHeight * 1.4
        alert:SetSize(glowW, glowH)
        -- ProcStartFlipbook: SetScale scales the 150x150 flipbook in render space.
        -- 42 is the standard action button height where scale=1.0 produces the normal glow.
        if alert.ProcStartFlipbook then
            local scale = math.max(iconWidth, iconHeight) / 42
            alert.ProcStartFlipbook:SetScale(scale)
        end
        if alert.ProcLoopFlipbook then
            alert.ProcLoopFlipbook:ClearAllPoints()
            alert.ProcLoopFlipbook:SetSize(glowW, glowH)
            alert.ProcLoopFlipbook:SetPoint("CENTER", alert, "CENTER")
        end
    end)
    -- Update pixel glow dimensions if active
    if addon.PixelGlow then
        local glow = addon.PixelGlow.GetForIcon(cdmIcon)
        if glow then glow:SetTargetSize(iconWidth, iconHeight) end
    end
end

function Overlays.ApplyIconSize(cdmIcon, opts)
    if not cdmIcon then return end
    if not opts then return end
    if cdmIcon.IsForbidden and cdmIcon:IsForbidden() then return end

    local iconWidth = tonumber(opts.width)
    local iconHeight = tonumber(opts.height)
    if not iconWidth or not iconHeight then return end
    if iconWidth <= 0 or iconHeight <= 0 then return end

    -- Find the icon texture (handle both .icon and .Icon for compatibility)
    local iconTexture = cdmIcon.icon or cdmIcon.Icon
    if not iconTexture then return end

    -- Apply size change via pcall to catch any issues
    local ok = pcall(function()
        cdmIcon:SetWidth(iconWidth)
        cdmIcon:SetHeight(iconHeight)
        cdmIcon:SetSize(iconWidth, iconHeight)
    end)

    if not ok then return end

    -- Calculate texture coordinates: aspect-ratio crop + optional zoom
    local zoomPct = tonumber(opts.iconZoom) or 0
    local left, right, top, bottom = addon.CalculateIconTexCoords(iconWidth / iconHeight, zoomPct, 0)
    pcall(function()
        iconTexture:SetTexCoord(left, right, top, bottom)
    end)

    -- Reposition internal elements to match new size
    local padding = 0
    local swipeInset = tonumber(opts.swipeInset) or 0

    -- Cooldown swipe (inset to prevent protrusion on non-square icons)
    if cdmIcon.Cooldown then
        pcall(function()
            cdmIcon.Cooldown:ClearAllPoints()
            cdmIcon.Cooldown:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", swipeInset, -swipeInset)
            cdmIcon.Cooldown:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", -swipeInset, swipeInset)
        end)
    end

    -- Cooldown flash (match swipe inset)
    if cdmIcon.CooldownFlash then
        pcall(function()
            cdmIcon.CooldownFlash:ClearAllPoints()
            cdmIcon.CooldownFlash:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", swipeInset, -swipeInset)
            cdmIcon.CooldownFlash:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", -swipeInset, swipeInset)
        end)
    end

    -- Icon texture itself (full size, no inset)
    pcall(function()
        iconTexture:ClearAllPoints()
        iconTexture:SetPoint("TOPLEFT", cdmIcon, "TOPLEFT", padding, -padding)
        iconTexture:SetPoint("BOTTOMRIGHT", cdmIcon, "BOTTOMRIGHT", -padding, padding)
    end)

    -- Fix proc glow if alert already exists (handles re-sizing after first proc)
    resizeProcGlow(cdmIcon, iconWidth, iconHeight)

    -- Store dimensions so the ShowAlert hook can resize on first proc too
    sizedIcons[cdmIcon] = { width = iconWidth, height = iconHeight }
end

function Overlays.ResetIconSize(cdmIcon)
    if not cdmIcon then return end

    -- Reset texture coordinates to default
    local iconTexture = cdmIcon.icon or cdmIcon.Icon
    if iconTexture then
        pcall(function()
            iconTexture:SetTexCoord(0, 1, 0, 1)
        end)
    end

    sizedIcons[cdmIcon] = nil
    zoomedIcons[cdmIcon] = nil
end

--------------------------------------------------------------------------------
-- Square Cooldown Swipe
--------------------------------------------------------------------------------

local SQUARE_SWIPE_PATH = "Interface\\AddOns\\Scoot\\media\\masks\\squareswipe"

function Overlays.ApplySquareSwipe(cdmIcon)
    if not cdmIcon then return end
    pcall(function()
        for _, child in ipairs({ cdmIcon:GetChildren() }) do
            if child.SetSwipeTexture then
                child:SetSwipeTexture(SQUARE_SWIPE_PATH)
                modifiedSwipes[child] = true
            end
        end
    end)
end

function Overlays.ResetSwipe(cdmIcon)
    if not cdmIcon then return end
    pcall(function()
        for _, child in ipairs({ cdmIcon:GetChildren() }) do
            if modifiedSwipes[child] and child.SetSwipeTexture then
                child:SetSwipeTexture("Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe")
                modifiedSwipes[child] = nil
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Hide Decorative Ring
--------------------------------------------------------------------------------

local RING_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"

function Overlays.HideIconRing(cdmIcon)
    if not cdmIcon then return end
    pcall(function()
        for _, region in ipairs({ cdmIcon:GetRegions() }) do
            if region:IsObjectType("Texture") and not hiddenRings[region] then
                local atlas = region:GetAtlas()
                if atlas == RING_ATLAS then
                    region:SetAlpha(0)
                    hiddenRings[region] = true
                end
            end
        end
    end)
end

function Overlays.RestoreIconRing(cdmIcon)
    if not cdmIcon then return end
    pcall(function()
        for _, region in ipairs({ cdmIcon:GetRegions() }) do
            if hiddenRings[region] then
                region:SetAlpha(1)
                hiddenRings[region] = nil
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Viewer Integration
--------------------------------------------------------------------------------

-- Diagnostic record for /scoot debug cdm: last ApplyToViewer outcome per viewer
local function recordApply(viewerFrameName, outcome)
    Overlays._lastApply = Overlays._lastApply or {}
    Overlays._lastApply[viewerFrameName] = { t = GetTime(), outcome = outcome }
end

function Overlays.ApplyToViewer(viewerFrameName, componentId)
    local viewer = _G[viewerFrameName]
    if not viewer then
        recordApply(viewerFrameName, "no viewer global")
        return
    end

    if viewer.IsVisible and not viewer:IsVisible() then
        for _, child in ipairs(getViewerChildren(viewer, viewerFrameName)) do
            Overlays.ReleaseForIcon(child)
        end
        recordApply(viewerFrameName, "viewer not visible: overlays released")
        return
    end

    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then
        recordApply(viewerFrameName, component and "component has no db" or "component missing")
        return
    end

    local db = component.db
    local borderEnabled = db.borderEnable
    local hasTextConfig = db.textCooldown or db.textStacks
    local hasBindingConfig = db.textBindings and db.textBindings.enabled

    -- Check if icon sizing is configured via ratio
    local ratio = tonumber(db.tallWideRatio) or 0
    local hasCustomSize = ratio ~= 0
    local iconWidth, iconHeight
    if hasCustomSize and addon.IconRatio then
        iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
    end

    local zoom = tonumber(db.iconZoom) or 0
    local useSquareSwipe = db.squareCooldownSwipe
    local hideRing = db.hideDecorativeRing

    local styledCount, invisCount, invalidCount = 0, 0, 0
    for _, child in ipairs(getViewerChildren(viewer, viewerFrameName)) do
        if isValidCDMItemFrame(child) then
            if not isFrameVisible(child) then
                Overlays.ReleaseForIcon(child)
                invisCount = invisCount + 1
            else
                styledCount = styledCount + 1
                -- Apply icon sizing (with zoom) if configured
                if hasCustomSize and iconWidth and iconHeight then
                    Overlays.ApplyIconSize(child, {
                        width = iconWidth,
                        height = iconHeight,
                        iconZoom = zoom,
                        swipeInset = tonumber(db.swipeInset) or 0,
                    })
                    zoomedIcons[child] = zoom > 0 or nil
                elseif sizedIcons[child] then
                    -- Reset if previously sized but no longer configured
                    Overlays.ResetIconSize(child)
                    if zoom > 0 then
                        local iconTexture = child.icon or child.Icon
                        if iconTexture then
                            local l, r, t, b = addon.CalculateIconTexCoords(1.0, zoom, 0)
                            pcall(function() iconTexture:SetTexCoord(l, r, t, b) end)
                        end
                        zoomedIcons[child] = true
                    end
                elseif zoom > 0 then
                    local iconTexture = child.icon or child.Icon
                    if iconTexture then
                        local l, r, t, b = addon.CalculateIconTexCoords(1.0, zoom, 0)
                        pcall(function() iconTexture:SetTexCoord(l, r, t, b) end)
                    end
                    zoomedIcons[child] = true
                elseif zoomedIcons[child] then
                    local iconTexture = child.icon or child.Icon
                    if iconTexture then pcall(function() iconTexture:SetTexCoord(0, 1, 0, 1) end) end
                    zoomedIcons[child] = nil
                end

                -- Square cooldown swipe
                if useSquareSwipe then
                    Overlays.ApplySquareSwipe(child)
                else
                    Overlays.ResetSwipe(child)
                end

                -- Hide decorative ring
                if hideRing then
                    Overlays.HideIconRing(child)
                else
                    Overlays.RestoreIconRing(child)
                end

                if borderEnabled and not hasBlizzardDebuffBorder(child) then
                    Overlays.ApplyBorder(child, {
                        enable = true,
                        style = db.borderStyle or "square",
                        thickness = tonumber(db.borderThickness) or 1,
                        insetH = tonumber(db.borderInsetH) or tonumber(db.borderInset) or -1,
                        insetV = tonumber(db.borderInsetV) or tonumber(db.borderInset) or -1,
                        color = db.borderTintEnable and db.borderTintColor or {0, 0, 0, 1},
                        tintEnabled = db.borderTintEnable,
                        tintColor = db.borderTintColor,
                    })
                elseif hasBlizzardDebuffBorder(child) then
                    -- Hide Scoot border when Blizzard's DebuffBorder is visible
                    Overlays.HideBorder(child)
                else
                    Overlays.HideBorder(child)
                end

                if hasTextConfig then
                    Overlays.ApplyText(child, {
                        cooldown = db.textCooldown,
                        stacks = db.textStacks,
                    })
                else
                    Overlays.HideText(child)
                end

                -- Apply keybind text if enabled (Essential/Utility only)
                if hasBindingConfig then
                    -- Ensure overlay exists for keybind text
                    local kbOverlay = Overlays.GetOrCreateForIcon(child)
                    if kbOverlay and addon.SpellBindings then
                        addon.SpellBindings.ApplyToIcon(child, db.textBindings)
                    end
                else
                    local existingOverlay = activeOverlays[child]
                    if existingOverlay and existingOverlay.keybindText then
                        existingOverlay.keybindText:Hide()
                    end
                end

                local overlay = activeOverlays[child]
                if overlay then
                    if borderEnabled or hasTextConfig or hasBindingConfig then
                        overlay:Show()
                    else
                        overlay:Hide()
                    end
                end
            end
        else
            invalidCount = invalidCount + 1
        end
    end

    recordApply(viewerFrameName, string.format("styled %d, invisible %d, invalid %d",
        styledCount, invisCount, invalidCount))

    -- Apply per-icon cooldown opacity (uses SetAlphaFromBoolean with secret booleans)
    applyPerIconCooldownOpacity(viewerFrameName, componentId)

    -- Re-apply container-level opacity (may have been reset by Blizzard's RefreshLayout/OnShow)
    applyViewerOpacity(viewerFrameName, componentId)
end

--------------------------------------------------------------------------------
-- Hook Registration
--------------------------------------------------------------------------------

local hookedViewers = {}

function Overlays.HookViewer(viewerFrameName, componentId)
    if hookedViewers[viewerFrameName] then return true end

    local viewer = _G[viewerFrameName]
    if not viewer then return false end

    if viewer.OnAcquireItemFrame then
        hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
            invalidateChildrenCache(viewerFrameName)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if not isValidCDMItemFrame(itemFrame) then return end
                    if not isFrameVisible(itemFrame) then return end

                    local component = addon.Components and addon.Components[componentId]
                    if not component or not component.db then return end

                    -- Apply icon sizing if configured via ratio
                    local ratio = tonumber(component.db.tallWideRatio) or 0
                    local zoom = tonumber(component.db.iconZoom) or 0
                    if ratio ~= 0 and addon.IconRatio then
                        local iconWidth, iconHeight = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
                        if iconWidth and iconHeight then
                            Overlays.ApplyIconSize(itemFrame, {
                                width = iconWidth,
                                height = iconHeight,
                                iconZoom = zoom,
                                swipeInset = tonumber(component.db.swipeInset) or 0,
                            })
                        end
                    elseif zoom > 0 then
                        local iconTexture = itemFrame.icon or itemFrame.Icon
                        if iconTexture then
                            local l, r, t, b = addon.CalculateIconTexCoords(1.0, zoom, 0)
                            pcall(function() iconTexture:SetTexCoord(l, r, t, b) end)
                        end
                        zoomedIcons[itemFrame] = true
                    end

                    -- Square cooldown swipe
                    if component.db.squareCooldownSwipe then
                        Overlays.ApplySquareSwipe(itemFrame)
                    end

                    -- Hide decorative ring
                    if component.db.hideDecorativeRing then
                        Overlays.HideIconRing(itemFrame)
                    end

                    if component.db.borderEnable and not hasBlizzardDebuffBorder(itemFrame) then
                        Overlays.ApplyBorder(itemFrame, {
                            enable = true,
                            style = component.db.borderStyle or "square",
                            thickness = tonumber(component.db.borderThickness) or 1,
                            insetH = tonumber(component.db.borderInsetH) or tonumber(component.db.borderInset) or -1,
                            insetV = tonumber(component.db.borderInsetV) or tonumber(component.db.borderInset) or -1,
                            color = component.db.borderTintEnable and component.db.borderTintColor or {0, 0, 0, 1},
                            tintEnabled = component.db.borderTintEnable,
                            tintColor = component.db.borderTintColor,
                        })
                    elseif hasBlizzardDebuffBorder(itemFrame) then
                        -- Hide Scoot border when Blizzard's DebuffBorder is visible
                        Overlays.HideBorder(itemFrame)
                    end

                    local hasTextConfig = component.db.textCooldown or component.db.textStacks
                    if hasTextConfig then
                        Overlays.ApplyText(itemFrame, {
                            cooldown = component.db.textCooldown,
                            stacks = component.db.textStacks,
                        })
                    end

                    -- Apply keybind text if enabled
                    if component.db.textBindings and component.db.textBindings.enabled and addon.SpellBindings then
                        local kbOverlay = Overlays.GetOrCreateForIcon(itemFrame)
                        if kbOverlay then
                            addon.SpellBindings.ApplyToIcon(itemFrame, component.db.textBindings)
                        end
                    end
                end)
            end
        end)
    end

    if viewer.OnReleaseItemFrame then
        hooksecurefunc(viewer, "OnReleaseItemFrame", function(_, itemFrame)
            invalidateChildrenCache(viewerFrameName)
            -- Clear keybind spell cache for released icon
            if addon.SpellBindings and addon.SpellBindings.ClearIconCache then
                addon.SpellBindings.ClearIconCache(itemFrame)
            end
            -- Remove from tracking immediately to prevent catch-up ticker resurrection.
            -- The overlay and activeOverlays table are Scoot-owned, so this is taint-safe.
            local overlay = activeOverlays[itemFrame]
            if overlay then
                activeOverlays[itemFrame] = nil
                overlay:Hide()
            end
            -- Defer heavy cleanup (reparent, pool return) to break Blizzard's call stack
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if overlay then releaseOverlay(overlay) end
                    Overlays.ResetIconSize(itemFrame)
                    Overlays.ResetSwipe(itemFrame)
                    Overlays.RestoreIconRing(itemFrame)
                end)
            else
                if overlay then releaseOverlay(overlay) end
                Overlays.ResetIconSize(itemFrame)
                Overlays.ResetSwipe(itemFrame)
                Overlays.RestoreIconRing(itemFrame)
            end
        end)
    end

    if viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function()
            invalidateChildrenCache(viewerFrameName)
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    Overlays.ApplyToViewer(viewerFrameName, componentId)
                end)
            end
        end)
    end

    -- Hook Layout to apply centering synchronously (no deferral needed for cosmetic APIs).
    -- Eliminates the visible "jerk" on spell transforms where icons briefly appear
    -- at Blizzard's default grid position before snapping to centered position.
    if viewer.Layout then
        hooksecurefunc(viewer, "Layout", function()
            CenterIconsInViewer(viewer, componentId)
        end)
    end

    -- Diagnostic record for /scoot debug cdm: which methods existed at hook time
    -- (RefreshData/OnCooldownDataChanged are recorded but not hooked)
    Overlays._hookState = Overlays._hookState or {}
    Overlays._hookState[viewerFrameName] = string.format(
        "OnAcquireItemFrame=%s OnReleaseItemFrame=%s RefreshLayout=%s Layout=%s RefreshData=%s OnCooldownDataChanged=%s",
        tostring(viewer.OnAcquireItemFrame ~= nil),
        tostring(viewer.OnReleaseItemFrame ~= nil),
        tostring(viewer.RefreshLayout ~= nil),
        tostring(viewer.Layout ~= nil),
        tostring(viewer.RefreshData ~= nil),
        tostring(viewer.OnCooldownDataChanged ~= nil))

    hookedViewers[viewerFrameName] = true
    return true
end

--------------------------------------------------------------------------------
-- Periodic Cleanup
--------------------------------------------------------------------------------

local cleanupTicker = nil
local offCDRefreshTicker = nil

local function runOverlayCleanup()
    -- Part 1: release overlays for invisible icons (collect first to avoid mutation during iteration)
    local toRelease = {}
    for cdmIcon, _overlay in pairs(activeOverlays) do
        if not isFrameVisible(cdmIcon) then
            toRelease[#toRelease + 1] = cdmIcon
        end
    end
    for _, cdmIcon in ipairs(toRelease) do
        Overlays.ReleaseForIcon(cdmIcon)
    end

    -- Part 2: catch-up — detect visible icons that were never styled
    -- (handles hideWhenInactive icons appearing after initial bootstrap)
    for viewerName, componentId in pairs(CDM_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer and (not viewer.IsVisible or viewer:IsVisible()) then
            -- Force fresh children list to catch icons added since last cache
            invalidateChildrenCache(viewerName)
            local component = addon.Components and addon.Components[componentId]
            if component and component.db then
                local db = component.db
                local hasStyling = db.borderEnable or db.textCooldown or db.textStacks
                    or (db.textBindings and db.textBindings.enabled)
                local hasCustomSize = (tonumber(db.tallWideRatio) or 0) ~= 0
                if hasStyling or hasCustomSize then
                    local needsRestyle = false
                    for _, child in ipairs(getViewerChildren(viewer, viewerName)) do
                        if isValidCDMItemFrame(child) and isFrameVisible(child) then
                            if (hasStyling and (not activeOverlays[child] or not activeOverlays[child]:IsShown()))
                                or (hasCustomSize and not sizedIcons[child]) then
                                needsRestyle = true
                                break
                            end
                        end
                    end
                    if needsRestyle then
                        Overlays.ApplyToViewer(viewerName, componentId)
                    end
                end
            end
        end
    end
end

local function startCleanupTicker()
    if cleanupTicker then return end
    if C_Timer and C_Timer.NewTicker then
        cleanupTicker = C_Timer.NewTicker(0.5, runOverlayCleanup)
        Overlays._cleanupTickerStarted = true
    end
end

-- Forward declaration; body defined after applyPerIconCooldownOpacity exists
local startOffCDRefreshTicker

--------------------------------------------------------------------------------
-- Overlay Initialization
--------------------------------------------------------------------------------

local pendingViewers = {}
local initRetryCount = 0
local MAX_INIT_RETRIES = 10

function Overlays.Initialize()
    pendingViewers = {}
    for viewerName, componentId in pairs(CDM_VIEWERS) do
        local hooked = Overlays.HookViewer(viewerName, componentId)
        if hooked then
            Overlays.ApplyToViewer(viewerName, componentId)
            -- Apply icon centering after initial styling (deferred for layout completion)
            local viewer = _G[viewerName]
            if viewer then
                C_Timer.After(0.1, function()
                    CenterIconsInViewer(viewer, componentId)
                end)
            end
        else
            pendingViewers[viewerName] = componentId
        end
    end

    if next(pendingViewers) then
        Overlays.ScheduleRetry()
    end

    startCleanupTicker()

    -- Hook CooldownFrame_Set for direct text styling (12.0)
    hookCooldownTextStyling()
    hookProcGlowResizing()

    -- Catch Blizzard proc glows that fired before the hook was installed
    C_Timer.After(0.15, scanAndReplaceActiveBlizzardGlows)

    -- Initialize keybind system and share the activeOverlays table
    if addon.SpellBindings then
        addon.SpellBindings.SetActiveOverlays(activeOverlays)
        addon.SpellBindings.Initialize()
    end

    -- Expose for diagnostic commands (read-only intent)
    Overlays._activeOverlays = activeOverlays
end

function Overlays.ScheduleRetry()
    initRetryCount = initRetryCount + 1
    if initRetryCount > MAX_INIT_RETRIES then
        pendingViewers = {}
        return
    end

    C_Timer.After(1.0, function()
        local stillPending = {}
        for viewerName, componentId in pairs(pendingViewers) do
            local hooked = Overlays.HookViewer(viewerName, componentId)
            if hooked then
                Overlays.ApplyToViewer(viewerName, componentId)
                -- Apply icon centering after initial styling (deferred for layout completion)
                local viewer = _G[viewerName]
                if viewer then
                    C_Timer.After(0.1, function()
                        CenterIconsInViewer(viewer, componentId)
                    end)
                end
            else
                stillPending[viewerName] = componentId
            end
        end
        pendingViewers = stillPending

        if next(pendingViewers) then
            Overlays.ScheduleRetry()
        end
    end)
end

--------------------------------------------------------------------------------
-- Viewer-Level Opacity System (12.0)
--------------------------------------------------------------------------------
-- SetAlpha on viewer containers is safe. Drives combat, out-of-combat, and
-- with-target opacity settings (stored as 50-100, converted to 0.0-1.0).
--------------------------------------------------------------------------------

-- All viewers that support opacity (including trackedBars)
local CDM_OPACITY_VIEWERS = {
    EssentialCooldownViewer = "essentialCooldowns",
    UtilityCooldownViewer = "utilityCooldowns",
    BuffIconCooldownViewer = "trackedBuffs",
    BuffBarCooldownViewer = "trackedBars",
}

-- Get the appropriate opacity value based on current game state
local function getViewerOpacityForState(componentId)
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return 1.0 end

    local db = component.db
    local inCombat = InCombatLockdown and InCombatLockdown()
    local hasTarget = UnitExists("target")

    -- Priority: combat > target > out-of-combat
    local opacityValue
    if inCombat then
        -- In combat: use combat opacity (Edit Mode setting, stored as 50-100)
        opacityValue = tonumber(db.opacity) or 100
    elseif hasTarget then
        -- Has target: use target opacity
        opacityValue = tonumber(db.opacityWithTarget) or 100
    else
        -- Out of combat, no target: use out-of-combat opacity
        opacityValue = tonumber(db.opacityOutOfCombat) or 100
    end

    -- Convert from percentage (0-100) to alpha (0.0-1.0)
    return math.max(0, math.min(1.0, opacityValue / 100))
end

-- Apply opacity to a single viewer frame and its overlays
applyViewerOpacity = function(viewerName, componentId)
    local viewer = _G[viewerName]
    if not viewer then return end

    if viewer.IsForbidden and viewer:IsForbidden() then return end

    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    local component = addon.Components and addon.Components[componentId]
    if component and component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    local alpha = getViewerOpacityForState(componentId)

    -- Apply to viewer frame
    -- Overlays are parented to CDM icons (children of the viewer), so they
    -- automatically inherit the viewer's alpha through the parent chain.
    -- No need to explicitly set overlay alpha - doing so would double-reduce it.
    pcall(function()
        viewer:SetAlpha(alpha)
    end)
end

-- Update all CDM viewer opacities based on current state
local function updateAllViewerOpacities()
    for viewerName, componentId in pairs(CDM_OPACITY_VIEWERS) do
        applyViewerOpacity(viewerName, componentId)
    end
end

-- Exposed function for settings changes
function addon.RefreshCDMViewerOpacity(componentId)
    if componentId then
        -- Refresh specific component
        for viewerName, cid in pairs(CDM_OPACITY_VIEWERS) do
            if cid == componentId then
                applyViewerOpacity(viewerName, componentId)
                break
            end
        end
    else
        -- Refresh all
        updateAllViewerOpacities()
    end
end

--------------------------------------------------------------------------------
-- Per-Icon Cooldown Opacity (Essential/Utility CDM)
--------------------------------------------------------------------------------
-- Uses SetAlphaFromBoolean with secret boolean from Duration Object IsZero()
-- to dim individual CDM icons when their spell is on cooldown.
-- GCD filtered via isOnGCD (NeverSecret). SetAlphaFromBoolean evaluates secret booleans in C++ without Lua-side inspection.
-- Text opacity can be controlled independently via opacityOnCooldownText.
-- When text differs from icon, SetIgnoreParentAlpha decouples the Cooldown frame
-- from the icon frame's alpha chain and SetAlphaFromBoolean drives it independently.
-- Targets the Cooldown frame (not its FontString) because Blizzard's C++ cooldown
-- renderer resets the FontString's alpha every frame, overriding the styled values.
--------------------------------------------------------------------------------

local function applyTextCooldownAlpha(cooldownFrame, durObj, containerAlpha, textDimAlpha, isGCD, isOffCooldownMode)
    if not cooldownFrame then return end
    pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, true)
    textAlphaDecoupled[cooldownFrame] = true
    if isGCD then
        pcall(cooldownFrame.SetAlpha, cooldownFrame, containerAlpha)
    else
        local readyAlpha = containerAlpha
        local cdAlpha = math.min(containerAlpha, textDimAlpha)
        if isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end
        local zeroOk, isZero = pcall(durObj.IsZero, durObj)
        if not zeroOk then
            pcall(cooldownFrame.SetAlpha, cooldownFrame, containerAlpha)
            return
        end
        pcall(cooldownFrame.SetAlphaFromBoolean, cooldownFrame, isZero, readyAlpha, cdAlpha)
    end
end

local function resetTextAlpha(cooldownFrame)
    if cooldownFrame and textAlphaDecoupled[cooldownFrame] then
        pcall(cooldownFrame.SetIgnoreParentAlpha, cooldownFrame, false)
        pcall(cooldownFrame.SetAlpha, cooldownFrame, 1.0)
        textAlphaDecoupled[cooldownFrame] = nil
    end
end

local function processOneIconOpacity(child, iconSetting, readyAlpha, cdAlpha, needsTextOverride, containerAlpha, textDimAlpha, isOffCooldownMode)
    if not isValidCDMItemFrame(child) or not isFrameVisible(child) then return end

    local idOk, spellId = pcall(child.GetBaseSpellID, child)
    if not idOk or not spellId then return end

    if C_Spell.GetOverrideSpell then
        local overrideOk, overrideId = pcall(C_Spell.GetOverrideSpell, spellId)
        if overrideOk and type(overrideId) == "number"
           and not (issecretvalue and issecretvalue(overrideId))
           and overrideId ~= 0 then
            spellId = overrideId
        end
    end

    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    local isGCD = cdInfo and cdInfo.isOnGCD
    local durObj = not isGCD and C_Spell.GetSpellCooldownDuration(spellId) or nil

    -- Icon frame opacity
    if iconSetting >= 100 then
        pcall(child.SetAlpha, child, 1.0)
    elseif isGCD then
        pcall(child.SetAlpha, child, readyAlpha)
    elseif durObj and durObj.IsZero then
        local zeroOk, isZero = pcall(durObj.IsZero, durObj)
        if zeroOk then
            pcall(child.SetAlphaFromBoolean, child, isZero, readyAlpha, cdAlpha)
        else
            pcall(child.SetAlpha, child, readyAlpha)
        end
    else
        pcall(child.SetAlpha, child, readyAlpha)
    end

    -- Text opacity (independent when text != icon setting)
    if needsTextOverride and child.Cooldown then
        if isGCD then
            applyTextCooldownAlpha(child.Cooldown, nil, containerAlpha, textDimAlpha, true, isOffCooldownMode)
        elseif durObj and durObj.IsZero then
            applyTextCooldownAlpha(child.Cooldown, durObj, containerAlpha, textDimAlpha, false, isOffCooldownMode)
        else
            resetTextAlpha(child.Cooldown)
        end
    elseif not needsTextOverride and child.Cooldown then
        resetTextAlpha(child.Cooldown)
    end
end

applyPerIconCooldownOpacity = function(viewerFrameName, componentId)
    local viewer = _G[viewerFrameName]
    if not viewer then return end
    local component = addon.Components and addon.Components[componentId]
    if not component or not component.db then return end

    local iconSetting = tonumber(component.db.opacityOnCooldown) or 100
    local textSetting = tonumber(component.db.opacityOnCooldownText) or 100

    -- Nothing to do if both are at 100%
    if iconSetting >= 100 and textSetting >= 100 then return end

    local mode = component.db.cooldownOpacityMode
    local isOffCooldownMode = (mode == "offCooldown")

    local containerAlpha = getViewerOpacityForState(componentId)
    local needsTextOverride = not isOffCooldownMode and (textSetting ~= iconSetting)

    -- Compute icon dim alpha (compensated for container opacity)
    local iconDimAlpha = iconSetting / 100
    if iconSetting < 100 and containerAlpha > 0 and containerAlpha < 1.0 then
        iconDimAlpha = math.min(1.0, iconDimAlpha / containerAlpha)
    end

    -- Pre-compute ready/cd alphas based on mode
    local readyAlpha, cdAlpha = 1.0, iconDimAlpha
    if isOffCooldownMode then readyAlpha, cdAlpha = cdAlpha, readyAlpha end

    -- Compute text dim alpha (absolute, used with SetIgnoreParentAlpha)
    local textDimAlpha = textSetting / 100

    for _, child in ipairs(getViewerChildren(viewer, viewerFrameName)) do
        pcall(processOneIconOpacity, child, iconSetting, readyAlpha, cdAlpha,
              needsTextOverride, containerAlpha, textDimAlpha, isOffCooldownMode)
    end

    -- Keep ticker alive while off-cooldown mode needs refresh
    if isOffCooldownMode and iconSetting < 100 then
        startOffCDRefreshTicker()
    end
end

addon.RefreshCDMCooldownOpacity = applyPerIconCooldownOpacity

-- 1s safety ticker: catches long-cooldown-end while idle (no event fires).
-- Self-terminates when no viewer needs off-cooldown refresh.
startOffCDRefreshTicker = function()
    if offCDRefreshTicker then return end
    offCDRefreshTicker = C_Timer.NewTicker(1.0, function()
        local anyActive = false
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            local component = addon.Components and addon.Components[componentId]
            if component and component.db
               and component.db.cooldownOpacityMode == "offCooldown"
               and (tonumber(component.db.opacityOnCooldown) or 100) < 100 then
                applyPerIconCooldownOpacity(viewerName, componentId)
                anyActive = true
            end
        end
        if not anyActive then
            offCDRefreshTicker:Cancel()
            offCDRefreshTicker = nil
        end
    end)
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Combat start
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Combat end
-- UNIT_SPELLCAST_SUCCEEDED removed: SecretWhenUnitSpellCastRestricted makes arg1=="player"
-- fail silently during combat. Path 3 (SetCooldown/Clear timing) handles this instead.

local lastRefreshTime = {}
local REFRESH_THROTTLE = 0.1

local function throttledRefresh(viewerName, componentId)
    local now = GetTime()
    local lastTime = lastRefreshTime[viewerName] or 0
    if now - lastTime < REFRESH_THROTTLE then
        return
    end
    lastRefreshTime[viewerName] = now

    C_Timer.After(0.05, function()
        Overlays.ApplyToViewer(viewerName, componentId)
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        initRetryCount = 0
        C_Timer.After(1.0, function()
            for viewerName, componentId in pairs(CDM_VIEWERS) do
                if not hookedViewers[viewerName] then
                    local hooked = Overlays.HookViewer(viewerName, componentId)
                    if hooked then
                        Overlays.ApplyToViewer(viewerName, componentId)
                    end
                else
                    Overlays.ApplyToViewer(viewerName, componentId)
                end
            end
            startCleanupTicker()
            hookCooldownTextStyling()
            hookProcGlowResizing()

            -- Safety net: catch stale Blizzard proc glows from reload race
            C_Timer.After(0.15, scanAndReplaceActiveBlizzardGlows)

            -- Apply initial viewer opacity based on current state
            updateAllViewerOpacities()
        end)

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: update viewer opacities to combat values
        updateAllViewerOpacities()
        -- Re-apply per-icon cooldown opacity with new container alpha
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            applyPerIconCooldownOpacity(viewerName, componentId)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: update viewer opacities to out-of-combat values
        updateAllViewerOpacities()
        -- Re-apply per-icon cooldown opacity with new container alpha
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            applyPerIconCooldownOpacity(viewerName, componentId)
        end

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            throttledRefresh("BuffIconCooldownViewer", "trackedBuffs")
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update opacity for target state change (no styling depends on target)
        updateAllViewerOpacities()
        -- Re-apply per-icon cooldown opacity with new container alpha
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            applyPerIconCooldownOpacity(viewerName, componentId)
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        -- Only update per-icon cooldown dimming; icon lifecycle is handled by
        -- OnAcquireItemFrame/OnReleaseItemFrame hooks, layout by RefreshLayout hook.
        applyPerIconCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
        applyPerIconCooldownOpacity("UtilityCooldownViewer", "utilityCooldowns")

    end
end)

--------------------------------------------------------------------------------
-- Settings Change Handler
--------------------------------------------------------------------------------

function Overlays.OnSettingsChanged(componentId)
    for viewerName, cid in pairs(CDM_VIEWERS) do
        if cid == componentId then
            Overlays.ApplyToViewer(viewerName, componentId)
            break
        end
    end
end

addon.RefreshCDMOverlays = function(componentId)
    if componentId then
        Overlays.OnSettingsChanged(componentId)
    else
        for viewerName, cid in pairs(CDM_VIEWERS) do
            Overlays.ApplyToViewer(viewerName, cid)
        end
    end

    -- Refresh direct text styling (12.0)
    if addon.RefreshCDMTextStyling then
        C_Timer.After(0.1, function()
            addon.RefreshCDMTextStyling()
        end)
    end

    -- Sync proc glows with current profile settings
    C_Timer.After(0.15, scanAndReplaceActiveBlizzardGlows)

    -- Refresh viewer opacity when settings change
    if addon.RefreshCDMViewerOpacity then
        addon.RefreshCDMViewerOpacity(componentId)
    end

    -- Refresh keybind text on overlays
    if addon.SpellBindings and addon.SpellBindings.RefreshAllIcons then
        addon.SpellBindings.RefreshAllIcons(componentId)
    end
end

--------------------------------------------------------------------------------
-- Shared ApplyStyling for icon-based CDM groups
--------------------------------------------------------------------------------

addon.CDMIconApplyStyling = function(component)
    -- Zero-Touch: skip unconfigured components (still on proxy DB)
    if component._ScootDBProxy and component.db == component._ScootDBProxy then return end

    if addon.RefreshCDMOverlays then
        addon.RefreshCDMOverlays(component.id)
    end
end

-- Lightweight opacity-only refresh for icon-based CDM groups.
-- Used by RefreshOpacityState to avoid full per-icon restyle on combat/target events.
addon.CDMIconRefreshOpacity = function(component)
    for viewerName, cid in pairs(CDM_VIEWERS) do
        if cid == component.id then
            applyViewerOpacity(viewerName, cid)
            applyPerIconCooldownOpacity(viewerName, cid)
            break
        end
    end
    -- Also cover viewers in CDM_OPACITY_VIEWERS but not CDM_VIEWERS (e.g., BuffBarCooldownViewer)
    for viewerName, cid in pairs(CDM_OPACITY_VIEWERS) do
        if cid == component.id and not CDM_VIEWERS[viewerName] then
            applyViewerOpacity(viewerName, cid)
        end
    end
end

--------------------------------------------------------------------------------
-- Component Initializer: Overlay system bootstrap
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    C_Timer.After(0.5, function()
        Overlays.Initialize()
    end)
end, "cooldownManager")

