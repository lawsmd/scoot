-- core.lua - Cooldown Manager: overlay styling, viewer mappings, shared utilities
local addonName, addon = ...

local Component = addon.ComponentPrototype
local Util = addon.ComponentsUtil
local SS = addon.SecretSafe

addon.CDMOverlays = addon.CDMOverlays or {}
local Overlays = addon.CDMOverlays

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

-- Internal: returns r, g, b, a directly (no table allocation). legacySniff
-- keeps the historical "no mode set but a non-white color stored" inference.
local CDM_COLOR_OPTS = { legacySniff = true }
local function resolveCDMColorRGBA(cfg)
    return addon.ResolveColorRGBA(cfg and cfg.colorMode, cfg and cfg.color, CDM_COLOR_OPTS)
end

-- Exported: returns table (backward compat for external consumers)
local function resolveCDMColor(cfg)
    local r, g, b, a = resolveCDMColorRGBA(cfg)
    return {r, g, b, a}
end
addon.ResolveCDMColor = resolveCDMColor

--------------------------------------------------------------------------------
-- Overlay System
--------------------------------------------------------------------------------

local activeOverlays = {}  -- Map from CDM icon frame to overlay frame
Overlays._activeOverlays = activeOverlays

-- Track which icons have been sized (weak keys for GC)
-- Using a local table instead of writing to Blizzard frames avoids taint
-- that can cause allowAvailableAlert and other fields to become secret values
local sizedIcons = setmetatable({}, { __mode = "k" })
Overlays._sizedIcons = sizedIcons

-- Track cached FontString references per cooldown frame (weak keys for GC)
-- Using a local table instead of writing _scooterFontString to Blizzard frames avoids taint
local scootFontStrings = setmetatable({}, { __mode = "k" })

-- Track icon zoom (weak keys for GC)
local zoomedIcons = setmetatable({}, { __mode = "k" })
Overlays._zoomedIcons = zoomedIcons

-- Cache GetChildren() results per viewer to avoid temporary table allocation on every pass
local viewerChildrenCache = {}

local function invalidateChildrenCache(viewerFrameName)
    viewerChildrenCache[viewerFrameName] = nil
end
Overlays._InvalidateChildrenCache = invalidateChildrenCache

local function getViewerChildren(viewer, viewerFrameName)
    local cached = viewerChildrenCache[viewerFrameName]
    if cached then return cached end
    cached = { viewer:GetChildren() }
    viewerChildrenCache[viewerFrameName] = cached
    return cached
end
Overlays._GetViewerChildren = getViewerChildren

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
Overlays._HasBlizzardDebuffBorder = hasBlizzardDebuffBorder

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

    -- Border art lives on borderFrame (low level, below glow), applied through
    -- addon.ApplyIconBorderStyle in applyBorderToOverlay.

    -- Propagate overlay visibility to borderFrame automatically
    overlay:HookScript("OnShow", function() borderFrame:Show() end)
    overlay:HookScript("OnHide", function() borderFrame:Hide() end)

    -- Text FontString on overlay (high level, above glow). Cooldown and
    -- charge text style Blizzard's own FontStrings (applyFontStyleDirect);
    -- only the keybind text is drawn by Scoot.
    overlay.keybindText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlay.keybindText:SetDrawLayer("OVERLAY", 7)
    overlay.keybindText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 2, -2)
    overlay.keybindText:Hide()

    return overlay
end

local function resetOverlay(overlay)
    overlay:Hide()  -- OnHide hook propagates to borderFrame
    overlay:ClearAllPoints()
    overlay:SetParent(UIParent)  -- Prevents holding CDM icon reference
    overlay:SetAlpha(1.0)  -- Reset alpha when returning to pool
    if overlay.borderFrame then
        overlay.borderFrame:ClearAllPoints()
        overlay.borderFrame:SetParent(UIParent)
    end
    if overlay.keybindText then
        overlay.keybindText:SetText("")
        overlay.keybindText:Hide()
    end
end

local overlayPool = addon.Pool.New(createOverlayFrame, resetOverlay)
Overlays._overlayPool = overlayPool

local function getOverlay(parent)
    local overlay, isNew = overlayPool:Acquire(parent)
    if not isNew and parent then
        -- Re-parent pooled overlay and its sibling borderFrame to new parent
        overlay:SetParent(parent)
        if overlay.borderFrame then
            overlay.borderFrame:SetParent(parent)
        end
    end
    return overlay
end

--------------------------------------------------------------------------------
-- Border Application (overlay frames, not Blizzard's)
--------------------------------------------------------------------------------

-- Everything the border art depends on, so unchanged applies can be skipped.
-- Keyed by borderFrame (weak): pooled overlays keep their border art across
-- reuse, and the edges are anchored to borderFrame, so geometry follows the
-- frame without a re-apply. Cleared on every hide, or the skip would leave
-- hidden edges hidden on the next apply.
local borderFingerprints = setmetatable({}, { __mode = "k" })

local function applyBorderToOverlay(overlay, opts)
    if not overlay or not overlay.borderFrame then return end
    local borderFrame = overlay.borderFrame

    local style = opts.style or "square"
    local thickness = math.max(1, tonumber(opts.thickness) or 1)
    local insetH = tonumber(opts.insetH) or tonumber(opts.inset) or 0
    local insetV = tonumber(opts.insetV) or tonumber(opts.inset) or 0
    local tinted = (opts.tintEnabled and opts.tintColor) and true or false
    local tint = tinted and opts.tintColor or nil

    local fp = borderFingerprints[borderFrame]
    if fp
        and fp.style == style
        and fp.thickness == thickness
        and fp.insetH == insetH
        and fp.insetV == insetV
        and fp.tinted == tinted
        and (not tinted or (fp.tintR == tint[1] and fp.tintG == tint[2]
            and fp.tintB == tint[3] and fp.tintA == tint[4]))
    then
        return
    end

    -- This dispatcher's square branch has always been outward-positive; the shared
    -- dispatcher is inward-positive, so square styles negate. Atlas styles were
    -- inward-positive here already and pass through unchanged.
    local styleDef = addon.IconBorders and addon.IconBorders.GetStyle and addon.IconBorders.GetStyle(style)
    local dispatchH, dispatchV = insetH, insetV
    if not styleDef or styleDef.type == "square" then
        dispatchH, dispatchV = -insetH, -insetV
    end

    addon.ApplyIconBorderStyle(borderFrame, style, {
        thickness = thickness,
        insetH = dispatchH,
        insetV = dispatchV,
        tintEnabled = tinted,
        color = tint,
        simpleTint = true,
        manageSubPixel = true,
        expandClamp = 12,
    })

    borderFingerprints[borderFrame] = {
        style = style,
        thickness = thickness,
        insetH = insetH,
        insetV = insetV,
        tinted = tinted,
        tintR = tint and tint[1],
        tintG = tint and tint[2],
        tintB = tint and tint[3],
        tintA = tint and tint[4],
    }
end

local function hideBorderOnOverlay(overlay)
    if not overlay or not overlay.borderFrame then return end
    borderFingerprints[overlay.borderFrame] = nil
    if addon.Borders and addon.Borders.HideAll then
        addon.Borders.HideAll(overlay.borderFrame)
    end
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
    -- Above the cache read, not just the writes: the lookup below is already
    -- keyed on cooldownFrame, and a secret key marks scootFontStrings secret
    -- for the rest of the session.
    cooldownFrame = SS.plainFrame(cooldownFrame)
    if not cooldownFrame then return nil end

    -- Use cached reference if available
    if scootFontStrings[cooldownFrame] then
        return scootFontStrings[cooldownFrame]
    end

    -- Prefer the dedicated Cooldown widget API (C++-managed countdown FontString)
    if cooldownFrame.GetCountdownFontString then
        local ok, fs = pcall(cooldownFrame.GetCountdownFontString, cooldownFrame)
        -- Screen the result too. A secret is safe as a table value, but
        -- applyFontStyleDirect would index it and the cache would then serve
        -- that throw for the rest of the session.
        if ok and SS.plainFrame(fs) then
            scootFontStrings[cooldownFrame] = fs
            return fs
        end
    end

    -- Fallback: scan regions (for non-Cooldown frame types)
    if cooldownFrame.GetRegions then
        for _, region in ipairs({cooldownFrame:GetRegions()}) do
            if SS.plainFrame(region) and region.GetObjectType and region:GetObjectType() == "FontString" then
                scootFontStrings[cooldownFrame] = region
                return region
            end
        end
    end
end

-- Find the charge/stack count FontString inside an icon frame
local function getChargeCountFontString(iconFrame)
    iconFrame = SS.plainFrame(iconFrame)
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
    cooldownFrame = SS.plainFrame(cooldownFrame)
    if not cooldownFrame then return nil end

    local parent = SS.plainFrame(cooldownFrame:GetParent())
    if not parent then return nil end

    -- parent should be the icon frame, check its parent for the viewer
    local viewerFrame = SS.plainFrame(parent:GetParent())
    if viewerFrame and viewerFrame.GetName then
        -- A secret string used as a table key throws, so screen before the lookup
        local viewerName = SS.plainString(viewerFrame:GetName())
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
-- Routes through ApplyFontStyle so the pseudo-style prefixes (SHADOW*/HEAVY*)
-- decode into their shadow calls instead of being dropped by SetFont.
-- isChargeText: if true, uses BOTTOMRIGHT anchor; otherwise uses CENTER
-- parentFrame: the frame to anchor to (defaults to fontString's parent)
local cdmTextFontOpts = { size = 14, gameFontDefault = true }
local function applyFontStyleDirect(fontString, cfg, isChargeText, parentFrame, skipColor)
    if not fontString or not cfg then return end

    local fontFace, size, style = addon.ResolveTextFont(cfg, cdmTextFontOpts)
    local r, g, b, a = resolveCDMColorRGBA(cfg)

    addon.ApplyFontStyle(fontString, fontFace, size, style)
    if not skipColor then
        pcall(fontString.SetTextColor, fontString, r, g, b, a)
    end

    -- Debug knob: explicit offsets override the style's own shadow. The
    -- applier zeroes the shadow for shadowless styles, so give the offset a
    -- visible color in that case.
    if cfg.shadowX or cfg.shadowY then
        if not (style:find("SHADOW", 1, true) or style:find("HEAVY", 1, true)) then
            pcall(fontString.SetShadowColor, fontString, 0, 0, 0, 0.8)
        end
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
    -- Reachable from the CooldownFrame_Set hook and from
    -- addon.RefreshCDMTextStyling, which passes child.Cooldown straight off a
    -- viewer, so the screen lives here rather than at either caller.
    cooldownFrame = SS.plainFrame(cooldownFrame)
    if not cooldownFrame then return end
    if cooldownFrame.IsForbidden and cooldownFrame:IsForbidden() then return end

    -- Skip action bar cooldowns to avoid taint
    local parent = SS.plainFrame(cooldownFrame:GetParent())
    if parent then
        local rawName = parent.GetName and parent:GetName()
        -- type() is legal on a secret and reports "string" for a secret string,
        -- so it tells an unnamed frame apart from a name we may not read without
        -- comparing anything. :match on a secret string throws.
        if type(rawName) == "string" then
            local parentName = SS.plainString(rawName)
            if not parentName then return end
            if parentName:match("ActionButton") or parentName:match("MultiBar") or
               parentName:match("PetActionButton") or parentName:match("StanceButton") then
                return
            end
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

-- Diagnostic record for /scoot debug cdm: how often a secret frame reached the
-- CooldownFrame_Set hook. Frame identity is unreadable by design, so only counts
-- and the probe shape of the last reject are kept.
local hookStats = { calls = 0, rejects = 0, lastReject = nil, lastShape = nil }
Overlays._hookStats = hookStats

-- Probe a value without indexing or comparing it. Returns a short plain token,
-- so nothing secret can reach the debug window's table.concat.
local function probeToken(fn, v)
    if type(fn) ~= "function" then return "n/a" end
    local ok, result = pcall(fn, v)
    if not ok then return "err" end
    if type(result) ~= "boolean" then return "?" end
    return result and "yes" or "no"
end

-- Record which restriction tripped. issecretvalue=yes means the handle itself is
-- secret, which points at a secure-environment caller (private auras, target
-- frame aura buttons). issecretvalue=no with canaccesstable=no means the handle
-- is plain but its table is closed to us, which points at a forbidden object
-- table (the arena CC-remover frames). Different subsystems, and nothing else
-- tells them apart.
local function recordSecretReject(frame)
    hookStats.rejects = hookStats.rejects + 1
    local now = GetTime()
    -- Counting is free; probing is three pcalls and a format, and this runs
    -- inside a hook on a global Blizzard calls constantly. The first reject plus
    -- one per second after it is enough to name the subsystem.
    if hookStats.lastShape and hookStats.lastReject and (now - hookStats.lastReject) < 1 then
        hookStats.lastReject = now
        return
    end
    hookStats.lastReject = now
    hookStats.lastShape = string.format(
        "type=%s issecretvalue=%s issecrettable=%s canaccesstable=%s",
        type(frame),
        probeToken(_G.issecretvalue, frame),
        probeToken(_G.issecrettable, frame),
        probeToken(_G.canaccesstable, frame))
end

-- Hook into Blizzard's cooldown system to intercept updates
local function hookCooldownTextStyling()
    if directTextStyleHooked then return end

    -- Hook CooldownFrame_Set (the main function that updates cooldowns)
    if CooldownFrame_Set then
        hooksecurefunc("CooldownFrame_Set", function(cooldownFrame, start, duration, enable, forceShowDrawEdge, modRate)
            hookStats.calls = hookStats.calls + 1

            -- Blizzard calls this global from scopes we cannot enter: private
            -- auras and target frame aura buttons run in a secure environment,
            -- and the arena CC-remover frames come from a forbidden object
            -- table. Those handles arrive secret and the first index throws, so
            -- the screen has to be the first thing that touches the argument.
            -- Nothing may be inserted above it, a truthiness test included.
            local frame = SS.plainFrame(cooldownFrame)
            if not frame then
                if type(cooldownFrame) == "table" then
                    recordSecretReject(cooldownFrame)
                end
                return
            end
            if frame.IsForbidden and frame:IsForbidden() then return end

            -- Defer text styling to next frame for safety
            C_Timer.After(0, function()
                if frame.IsForbidden and frame:IsForbidden() then return end
                pcall(applyCooldownTextStyle, frame)
            end)
        end)
    end

    directTextStyleHooked = true
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
Overlays._IsValidCDMItemFrame = isValidCDMItemFrame

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
Overlays._IsFrameVisible = isFrameVisible

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
        overlayPool:Release(overlay)
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
        overlayPool:Release(overlay)
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
    Overlays._ApplyPerIconCooldownOpacity(viewerFrameName, componentId)

    -- Re-apply container-level opacity (may have been reset by Blizzard's RefreshLayout/OnShow)
    Overlays._ApplyViewerOpacity(viewerFrameName, componentId)
end

--------------------------------------------------------------------------------
-- Periodic Cleanup
--------------------------------------------------------------------------------

local cleanupTicker = nil

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
                    Overlays._CenterIconsInViewer(viewer, componentId)
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
    Overlays._HookProcGlowResizing()

    -- Catch Blizzard proc glows that fired before the hook was installed
    C_Timer.After(0.15, Overlays._ScanAndReplaceActiveBlizzardGlows)

    -- Initialize keybind system and share the activeOverlays table
    if addon.SpellBindings then
        addon.SpellBindings.SetActiveOverlays(activeOverlays)
        addon.SpellBindings.Initialize()
    end
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
                        Overlays._CenterIconsInViewer(viewer, componentId)
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
-- Event Handling
--------------------------------------------------------------------------------

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

local function onCDMEvent(event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        initRetryCount = 0
        C_Timer.After(1.0, function()
            for viewerName, componentId in pairs(CDM_VIEWERS) do
                if not Overlays._hookedViewers[viewerName] then
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
            Overlays._HookProcGlowResizing()

            -- Safety net: catch stale Blizzard proc glows from reload race
            C_Timer.After(0.15, Overlays._ScanAndReplaceActiveBlizzardGlows)

            -- Apply initial viewer opacity based on current state
            Overlays._UpdateAllViewerOpacities()
        end)

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started: update viewer opacities to combat values
        Overlays._UpdateAllViewerOpacities()
        -- Re-apply per-icon cooldown opacity with new container alpha
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            Overlays._ApplyPerIconCooldownOpacity(viewerName, componentId)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended: update viewer opacities to out-of-combat values
        Overlays._UpdateAllViewerOpacities()
        -- Re-apply per-icon cooldown opacity with new container alpha
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            Overlays._ApplyPerIconCooldownOpacity(viewerName, componentId)
        end

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            throttledRefresh("BuffIconCooldownViewer", "trackedBuffs")
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Update opacity for target state change (no styling depends on target)
        Overlays._UpdateAllViewerOpacities()
        -- Re-apply per-icon cooldown opacity with new container alpha
        for viewerName, componentId in pairs(CDM_VIEWERS) do
            Overlays._ApplyPerIconCooldownOpacity(viewerName, componentId)
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" then
        -- Only update per-icon cooldown dimming; icon lifecycle is handled by
        -- OnAcquireItemFrame/OnReleaseItemFrame hooks, layout by RefreshLayout hook.
        Overlays._ApplyPerIconCooldownOpacity("EssentialCooldownViewer", "essentialCooldowns")
        Overlays._ApplyPerIconCooldownOpacity("UtilityCooldownViewer", "utilityCooldowns")

    end
end

for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "UNIT_AURA",
    "PLAYER_TARGET_CHANGED",
    "SPELL_UPDATE_COOLDOWN",
    "SPELL_UPDATE_CHARGES",
    "PLAYER_REGEN_DISABLED",  -- Combat start
    "PLAYER_REGEN_ENABLED",   -- Combat end
}) do
    addon.Events.On("Cooldowns", event, onCDMEvent)
end

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
    C_Timer.After(0.15, Overlays._ScanAndReplaceActiveBlizzardGlows)

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
    if addon.IsComponentUnconfigured(component) then return end

    if addon.RefreshCDMOverlays then
        addon.RefreshCDMOverlays(component.id)
    end
end

-- Lightweight opacity-only refresh for icon-based CDM groups.
-- Used by RefreshOpacityState to avoid full per-icon restyle on combat/target events.
addon.CDMIconRefreshOpacity = function(component)
    for viewerName, cid in pairs(CDM_VIEWERS) do
        if cid == component.id then
            Overlays._ApplyViewerOpacity(viewerName, cid)
            Overlays._ApplyPerIconCooldownOpacity(viewerName, cid)
            break
        end
    end
    -- Also cover viewers in Overlays._opacityViewers but not CDM_VIEWERS (e.g., BuffBarCooldownViewer)
    for viewerName, cid in pairs(Overlays._opacityViewers) do
        if cid == component.id and not CDM_VIEWERS[viewerName] then
            Overlays._ApplyViewerOpacity(viewerName, cid)
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

