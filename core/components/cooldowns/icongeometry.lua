-- icongeometry.lua - Cooldown Manager: icon sizing, square swipe, decorative ring
-- SetSize() on CDM icons is safe when writing from settings (no reads).
-- Texture coordinates are adjusted to prevent stretching on non-square sizes.
local addonName, addon = ...

local Overlays = addon.CDMOverlays

-- Track swipe modifications and hidden rings (weak keys for GC)
local modifiedSwipes = setmetatable({}, { __mode = "k" })
local hiddenRings = setmetatable({}, { __mode = "k" })

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
local resizeProcGlow = function(cdmIcon, iconWidth, iconHeight)
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
Overlays._ResizeProcGlow = resizeProcGlow

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
    Overlays._sizedIcons[cdmIcon] = { width = iconWidth, height = iconHeight }
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

    Overlays._sizedIcons[cdmIcon] = nil
    Overlays._zoomedIcons[cdmIcon] = nil
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
