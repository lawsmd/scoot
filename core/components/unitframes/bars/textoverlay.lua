--------------------------------------------------------------------------------
-- bars/textoverlay.lua
-- Shared FontString-mirror overlay factory for the compact group frames.
-- Promoted from the raidframes implementation; partyframes/text.lua and
-- raidframes/text.lua each bind a family via TO.NewFamily and keep only their
-- public entry points, DB gating, and hook installation.
--
-- Pattern: an addon-owned FontString on a clipping container visually
-- replaces a Blizzard text element. Blizzard's element mirrors into the
-- overlay via hooksecurefunc, the original is held invisible by enforcement
-- hooks, and only addon-owned FontStrings are written during combat.
--
-- State discipline: everything lives in the family's weak side tables
-- (unit-frame-keyed and FontString-keyed) through the injected getState/
-- ensureState; nothing is ever written onto Blizzard frames.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Utils = addon.BarsUtils

local TO = {}
addon.BarsTextOverlay = TO

-- Font-half opts shared by the overlay stylers
local overlayFontOpts = { size = 12 }

-- Hide-enforcement (core/enforce.lua). A name is held at alpha 0, plus Hide()
-- on the direct path and the deferred re-assert; status text stays alpha-only,
-- since Hide would fight Blizzard's own visibility logic. Show kills alpha at
-- once and then defers, SetAlpha defers.
local Enforce = addon.Enforce
local HIDE_METHODS = { "Show", "SetAlpha" }
local HIDE_TIMING = { Show = "both", SetAlpha = "defer" }

local function applyNameHidden(region, method)
    region:SetAlpha(0)
    if method == nil then
        local hide = region.HideBase or region.Hide
        if hide then hide(region) end
    end
end

local function restoreName(region)
    if region.SetAlpha then pcall(region.SetAlpha, region, 1) end
    if region.Show then pcall(region.Show, region) end
end

local NAME_HIDE_OPTS = { methods = HIDE_METHODS, timing = HIDE_TIMING, apply = applyNameHidden, restore = restoreName }
local ALPHA_ONLY = { methods = HIDE_METHODS, timing = HIDE_TIMING }

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

-- Create/return the clipping container spanning the unit frame (3px inset).
-- Shared by the name and status overlays for 9-way alignment. Elevates the
-- frame's roleIcon to OVERLAY,6: above the status overlay (5), below the name
-- overlay (7). Z-order is draw-layer sublevels only; no SetFrameStrata, so
-- the container inherits the unit frame's own level.
function TO.ensureContainer(frame, ensureState)
    if not frame then return nil end
    local frameState = ensureState(frame)
    if not frameState then return nil end

    if not frameState.nameOverlayContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        -- Span the entire unit frame with small padding for visual breathing room.
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        frameState.nameOverlayContainer = container
    end

    return frameState.nameOverlayContainer
end

-- Strip a realm suffix: "Name-Realm" -> "Name". WoW names cannot contain
-- hyphens, so a hyphen always delimits the realm; the second match drops
-- anything after a space.
function TO.stripRealm(text)
    if text == "" then return text end
    text = text:match("^([^%-]+)") or text
    return text:match("^(%S+)") or text
end

-- Hide a Blizzard text element and keep it hidden (core/enforce.lua): opts is
-- NAME_HIDE_OPTS by default and ALPHA_ONLY for status text. The Show and
-- SetAlpha hooks install once per region.
function TO.enforceHidden(region, opts)
    Enforce.Set(region, "textOverlay", true, opts or NAME_HIDE_OPTS)
end

-- Clear the hidden flag and restore visibility. The enforcement hooks stay
-- installed permanently and no-op once the flag is clear.
function TO.releaseHidden(region, opts)
    Enforce.Set(region, "textOverlay", false, opts or NAME_HIDE_OPTS)
end

-- Name-overlay fingerprint: config fields plus, in class color mode, the
-- resolved class token, so the fingerprint changes when unit data becomes
-- available (e.g. zone-in). Returns fingerprint, classKeyUnresolved; the
-- caller must not cache while classKeyUnresolved is true, so re-styling
-- retries until the class resolves.
function TO.nameFingerprint(cfg, frame)
    local fpColorMode = cfg.colorMode or "default"
    local classKey = ""
    if fpColorMode == "class" and frame.unit then
        local token = addon.GetClassTokenForUnit(frame.unit)
        if token then
            classKey = token
        end
    end

    local fingerprint = string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
        tostring(cfg.fontFace or ""),
        tostring(cfg.size or ""),
        tostring(cfg.style or ""),
        tostring(cfg.anchor or ""),
        tostring(cfg.hideRealm or ""),
        cfg.color and string.format("%.2f,%.2f,%.2f,%.2f",
            cfg.color[1] or 1, cfg.color[2] or 1, cfg.color[3] or 1, cfg.color[4] or 1) or "",
        cfg.offset and string.format("%.1f,%.1f", cfg.offset.x or 0, cfg.offset.y or 0) or "",
        fpColorMode,
        classKey
    )

    local classKeyUnresolved = (fpColorMode == "class" and classKey == "" and frame.unit ~= nil)
    return fingerprint, classKeyUnresolved
end

-- Status-overlay fingerprint: config fields only (no colorMode, no class).
function TO.statusFingerprint(cfg)
    return string.format("%s|%s|%s|%s|%s|%s",
        tostring(cfg.fontFace or ""),
        tostring(cfg.size or ""),
        tostring(cfg.style or ""),
        tostring(cfg.anchor or ""),
        cfg.color and string.format("%.2f,%.2f,%.2f,%.2f",
            cfg.color[1] or 1, cfg.color[2] or 1, cfg.color[3] or 1, cfg.color[4] or 1) or "",
        cfg.offset and string.format("%.1f,%.1f", cfg.offset.x or 0, cfg.offset.y or 0) or ""
    )
end

-- Vertical justify derived from a 9-way anchor.
function TO.deriveJustifyV(anchor)
    if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        return "TOP"
    elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
        return "BOTTOM"
    end
    return "MIDDLE"
end

--------------------------------------------------------------------------------
-- Family factory
--------------------------------------------------------------------------------
-- desc fields:
--   getState, ensureState   the family's weak side-table accessors
--   isEditModeActive        the family's Edit Mode gate
--   isTarget                frame filter (Utils.isRaidFrame / isPartyFrame)
--   screenFrame             secret-frame screen (SS.plainFrame) used by hook
--                           handlers created with opts.screen
--   queueReapply            the family's combat reapply queue
--   statusDefaultAnchor     "TOPLEFT" (raid) / "CENTER" (party)
--   colorScratch            the family's ResolveColorRGBA scratch opts table
function TO.NewFamily(desc)
    local getState = desc.getState
    local ensureState = desc.ensureState
    local colorScratch = desc.colorScratch or {}
    local statusDefaultAnchor = desc.statusDefaultAnchor or "TOPLEFT"

    local family = {}

    local function hideBlizzardName(frame)
        if not frame or not frame.name then return end
        TO.enforceHidden(frame.name)
    end

    local function showBlizzardName(frame)
        if not frame or not frame.name then return end
        TO.releaseHidden(frame.name)
    end

    local function hideBlizzardStatus(frame)
        if not frame or not frame.statusText then return end
        TO.enforceHidden(frame.statusText, ALPHA_ONLY)
    end

    local function showBlizzardStatus(frame)
        if not frame or not frame.statusText then return end
        TO.releaseHidden(frame.statusText, ALPHA_ONLY)
    end

    ----------------------------------------------------------------------------
    -- Name overlay
    ----------------------------------------------------------------------------

    function family.styleNameOverlay(frame, cfg)
        if not frame or not cfg then return end
        local state = getState(frame)
        if not state or not state.nameOverlayText then return end

        local overlay = state.nameOverlayText
        local container = state.nameOverlayContainer or frame

        local anchor = cfg.anchor or "TOPLEFT"
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        addon.ApplyTextFont(overlay, cfg, overlayFontOpts)

        -- Determine color based on colorMode. No barKind: text default is
        -- white, and a class miss stays white; class with no unit skips the
        -- resolve until roster data arrives.
        local colorMode = cfg.colorMode or "default"
        local r, g, b, a = 1, 1, 1, 1
        if colorMode ~= "class" or frame.unit then
            colorScratch.unitForClass = frame.unit
            r, g, b, a = addon.ResolveColorRGBA(colorMode, cfg.color, colorScratch)
        end
        pcall(overlay.SetTextColor, overlay, r, g, b, a)

        -- Always LEFT justify so truncation only happens on the right side;
        -- player names always show the beginning of the name.
        pcall(overlay.SetJustifyH, overlay, "LEFT")
        if overlay.SetJustifyV then
            pcall(overlay.SetJustifyV, overlay, "MIDDLE")
        end
        if overlay.SetWordWrap then
            pcall(overlay.SetWordWrap, overlay, false)
        end
        if overlay.SetNonSpaceWrap then
            pcall(overlay.SetNonSpaceWrap, overlay, false)
        end
        if overlay.SetMaxLines then
            pcall(overlay.SetMaxLines, overlay, 1)
        end

        -- Width-aware positioning: repositionNameOverlay computes the exact
        -- CENTER/RIGHT offset from GetStringWidth().
        Utils.repositionNameOverlay(overlay, container, anchor, offsetX, offsetY)

        -- Store alignment params so the SetText hook can reposition after text changes.
        state.nameAnchor = anchor
        state.nameOffsetX = offsetX
        state.nameOffsetY = offsetY
    end

    function family.ensureNameOverlay(frame, cfg)
        if not frame then return end

        local hasCustom = Utils.hasCustomTextSettings(cfg)
        local frameState = ensureState(frame)
        if frameState then
            frameState.nameOverlayActive = hasCustom
            frameState.hideRealmEnabled = cfg and cfg.hideRealm and true or false
        end

        if not hasCustom then
            if frameState and frameState.nameOverlayText then
                frameState.nameOverlayText:Hide()
            end
            showBlizzardName(frame)
            return
        end
        if not frameState then return end

        -- Addon-owned clipping container spanning the FULL unit frame, so
        -- 9-way alignment can position text anywhere within the frame.
        TO.ensureContainer(frame, ensureState)

        -- Create the overlay FontString once, as a child of the container
        if not frameState.nameOverlayText then
            local parentForText = frameState.nameOverlayContainer or frame
            local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
            overlay:SetDrawLayer("OVERLAY", 7)
            frameState.nameOverlayText = overlay

            local nameState = frame.name and ensureState(frame.name) or nil
            if frame.name and _G.hooksecurefunc and nameState and not nameState.textMirrorHooked then
                nameState.textMirrorHooked = true
                local ownerState = frameState
                _G.hooksecurefunc(frame.name, "SetText", function(_, text)
                    if ownerState and ownerState.nameOverlayText and ownerState.nameOverlayActive then
                        -- text may be a secret value in 12.0; branch on type
                        if type(text) == "string" and not issecretvalue(text) then
                            local displayText = text
                            if ownerState.hideRealmEnabled and displayText ~= "" then
                                displayText = TO.stripRealm(displayText)
                            end
                            ownerState.nameOverlayText:SetText(displayText)
                        else
                            -- Secret or other type -- SetText handles secrets natively
                            pcall(ownerState.nameOverlayText.SetText, ownerState.nameOverlayText, text)
                        end
                        -- Reposition after text change so CENTER/RIGHT alignment
                        -- adapts to the new text width
                        if ownerState.nameAnchor then
                            Utils.repositionNameOverlay(ownerState.nameOverlayText,
                                ownerState.nameOverlayContainer or frame,
                                ownerState.nameAnchor, ownerState.nameOffsetX or 0, ownerState.nameOffsetY or 0)
                        end
                    end
                end)
            end
        end

        local fingerprint, classKeyUnresolved = TO.nameFingerprint(cfg, frame)
        if not classKeyUnresolved and frameState.lastNameFingerprint == fingerprint
            and frameState.nameOverlayText and frameState.nameOverlayText:IsShown() then
            return
        end
        frameState.lastNameFingerprint = classKeyUnresolved and nil or fingerprint

        family.styleNameOverlay(frame, cfg)
        hideBlizzardName(frame)

        -- Copy the current name into the overlay: plain GetText, then
        -- GetUnitName, then a direct secret passthrough as the last resort.
        local textCopied = false
        if frameState.nameOverlayText and frame.name and frame.name.GetText then
            local ok, currentText = pcall(frame.name.GetText, frame.name)
            if ok and type(currentText) == "string" and not issecretvalue(currentText) and currentText ~= "" then
                local displayText = currentText
                if cfg and cfg.hideRealm then
                    displayText = TO.stripRealm(displayText)
                end
                frameState.nameOverlayText:SetText(displayText)
                textCopied = true
            end
        end

        if not textCopied and frameState.nameOverlayText and frame.unit then
            local unitOk, unitName = pcall(GetUnitName, frame.unit, true)
            if unitOk and type(unitName) == "string" and not issecretvalue(unitName) and unitName ~= "" then
                local displayText = unitName
                if cfg and cfg.hideRealm then
                    displayText = TO.stripRealm(displayText)
                end
                frameState.nameOverlayText:SetText(displayText)
                textCopied = true
            end
        end

        if not textCopied and frameState.nameOverlayText and frame.name and frame.name.GetText then
            local ok, rawText = pcall(frame.name.GetText, frame.name)
            if ok then
                pcall(frameState.nameOverlayText.SetText, frameState.nameOverlayText, rawText)
            end
        end

        -- Reposition after the first text copy so CENTER/RIGHT alignment uses
        -- rendered width
        if frameState.nameAnchor and frameState.nameOverlayText then
            Utils.repositionNameOverlay(frameState.nameOverlayText,
                frameState.nameOverlayContainer or frame,
                frameState.nameAnchor, frameState.nameOffsetX or 0, frameState.nameOffsetY or 0)
        end

        if frameState.nameOverlayText then
            frameState.nameOverlayText:Show()
        end
    end

    function family.disableNameOverlay(frame)
        if not frame then return end
        local frameState = getState(frame)
        if frameState then
            frameState.nameOverlayActive = false
            if frameState.nameOverlayText then
                frameState.nameOverlayText:Hide()
            end
        end
        showBlizzardName(frame)

        -- Restore roleIcon to stock draw layer
        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
        end
    end

    ----------------------------------------------------------------------------
    -- Status-text overlay
    ----------------------------------------------------------------------------

    function family.styleStatusOverlay(frame, cfg)
        if not frame or not cfg then return end
        local state = getState(frame)
        if not state or not state.statusTextOverlay then return end

        local overlay = state.statusTextOverlay
        local container = state.nameOverlayContainer or frame

        local anchor = cfg.anchor or statusDefaultAnchor
        local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

        addon.ApplyTextFont(overlay, cfg, overlayFontOpts)

        -- Direct color only; status text has no colorMode
        local color = cfg.color or { 1, 1, 1, 1 }
        pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

        pcall(overlay.SetJustifyH, overlay, Utils.getJustifyHFromAnchor(anchor))
        if overlay.SetJustifyV then
            pcall(overlay.SetJustifyV, overlay, TO.deriveJustifyV(anchor))
        end
        if overlay.SetWordWrap then
            pcall(overlay.SetWordWrap, overlay, false)
        end
        if overlay.SetNonSpaceWrap then
            pcall(overlay.SetNonSpaceWrap, overlay, false)
        end
        if overlay.SetMaxLines then
            pcall(overlay.SetMaxLines, overlay, 1)
        end

        -- Static positioning within the clipping container (no width-aware
        -- repositioning for status text)
        overlay:ClearAllPoints()
        overlay:SetPoint(anchor, container, anchor, offsetX, offsetY)

        state.statusTextAnchor = anchor
        state.statusTextOffsetX = offsetX
        state.statusTextOffsetY = offsetY
    end

    function family.ensureStatusOverlay(frame, cfg)
        if not frame then return end

        local hasCustom = Utils.hasCustomTextSettings(cfg)
        local frameState = ensureState(frame)
        if frameState then
            frameState.statusTextOverlayActive = hasCustom
        end

        if not hasCustom then
            if frameState and frameState.statusTextOverlay then
                frameState.statusTextOverlay:Hide()
            end
            showBlizzardStatus(frame)
            return
        end
        if not frameState then return end

        TO.ensureContainer(frame, ensureState)

        if not frameState.statusTextOverlay then
            local parentForText = frameState.nameOverlayContainer or frame
            local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
            overlay:SetDrawLayer("OVERLAY", 5)  -- Below name text (7) and role icon (6)
            frameState.statusTextOverlay = overlay

            -- Mirror hooks on Blizzard's statusText: text via SetText and
            -- SetFormattedText, visibility via Show/Hide
            local stState = frame.statusText and ensureState(frame.statusText) or nil
            if frame.statusText and _G.hooksecurefunc and stState and not stState.textMirrorHooked then
                stState.textMirrorHooked = true
                local ownerState = frameState

                _G.hooksecurefunc(frame.statusText, "SetText", function(_, text)
                    if not (ownerState and ownerState.statusTextOverlay and ownerState.statusTextOverlayActive) then return end
                    -- text may be a secret value in 12.0; pcall for safety
                    if type(text) == "string" then
                        ownerState.statusTextOverlay:SetText(text)
                    else
                        pcall(ownerState.statusTextOverlay.SetText, ownerState.statusTextOverlay, text)
                    end
                    if ownerState.statusTextOverlay.Show then
                        ownerState.statusTextOverlay:Show()
                    end
                end)

                _G.hooksecurefunc(frame.statusText, "SetFormattedText", function(self, fmt, ...)
                    if not (ownerState and ownerState.statusTextOverlay and ownerState.statusTextOverlayActive) then return end
                    -- Forward formatted text via pcall (args may contain secrets)
                    local ok, result = pcall(string.format, fmt, ...)
                    if ok and type(result) == "string" then
                        ownerState.statusTextOverlay:SetText(result)
                    else
                        -- Fallback: try GetText after the format has been applied
                        local okGet, currentText = pcall(self.GetText, self)
                        if okGet then
                            pcall(ownerState.statusTextOverlay.SetText, ownerState.statusTextOverlay, currentText)
                        end
                    end
                    if ownerState.statusTextOverlay.Show then
                        ownerState.statusTextOverlay:Show()
                    end
                end)

                _G.hooksecurefunc(frame.statusText, "Show", function()
                    if ownerState and ownerState.statusTextOverlay and ownerState.statusTextOverlayActive then
                        ownerState.statusTextOverlay:Show()
                    end
                end)

                _G.hooksecurefunc(frame.statusText, "Hide", function()
                    if ownerState and ownerState.statusTextOverlay then
                        ownerState.statusTextOverlay:Hide()
                    end
                end)
            end
        end

        local fingerprint = TO.statusFingerprint(cfg)
        if frameState.lastStatusTextFingerprint == fingerprint
            and frameState.statusTextOverlay and frameState.statusTextOverlay:IsShown() then
            return
        end
        frameState.lastStatusTextFingerprint = fingerprint

        family.styleStatusOverlay(frame, cfg)
        hideBlizzardStatus(frame)

        -- Copy current text and visibility from Blizzard's statusText
        if frameState.statusTextOverlay and frame.statusText then
            local blizzST = frame.statusText
            local isVisible = false
            if blizzST.IsShown then
                local okV, vis = pcall(blizzST.IsShown, blizzST)
                isVisible = okV and vis
            end

            if blizzST.GetText then
                local ok, currentText = pcall(blizzST.GetText, blizzST)
                if ok and type(currentText) == "string" and not issecretvalue(currentText) and currentText ~= "" then
                    frameState.statusTextOverlay:SetText(currentText)
                elseif ok then
                    -- Secret or non-string -- forward directly
                    pcall(frameState.statusTextOverlay.SetText, frameState.statusTextOverlay, currentText)
                end
            end

            if isVisible then
                frameState.statusTextOverlay:Show()
            else
                frameState.statusTextOverlay:Hide()
            end
        end
    end

    function family.disableStatusOverlay(frame)
        if not frame then return end
        local frameState = getState(frame)
        if frameState then
            frameState.statusTextOverlayActive = false
            if frameState.statusTextOverlay then
                frameState.statusTextOverlay:Hide()
            end
        end
        showBlizzardStatus(frame)
    end

    ----------------------------------------------------------------------------
    -- CompactUnitFrame hook handlers
    ----------------------------------------------------------------------------
    -- kind: "name" | "status". getCfg returns the current cfg sub-table (or
    -- nil). opts:
    --   requireUnit  bail when the hook's unit argument is nil (SetUnit
    --                fires with nil on teardown)
    --   screen       run the frame through desc.screenFrame before indexing
    --                its text element (indexing a secret handle throws)
    --   combatBail   "always": queue the family reapply and return during
    --                lockdown. "ifNoOverlay": queue only when the overlay
    --                does not exist yet, otherwise proceed so an existing
    --                overlay restyles mid-combat.
    function family.makeCUFHandler(kind, getCfg, opts)
        local elementKey = (kind == "status") and "statusText" or "name"
        local overlayKey = (kind == "status") and "statusTextOverlay" or "nameOverlayText"
        local ensureFn = (kind == "status") and family.ensureStatusOverlay or family.ensureNameOverlay
        local requireUnit = opts and opts.requireUnit
        local screen = opts and opts.screen and desc.screenFrame or nil
        local bailMode = (opts and opts.combatBail) or "always"

        return function(frame, unit)
            -- CRITICAL: skip ALL processing when Edit Mode is active to avoid taint
            if desc.isEditModeActive() then return end
            if requireUnit and not unit then return end
            if screen then
                frame = screen(frame)
            end
            if not (frame and frame[elementKey] and desc.isTarget(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            local function apply()
                if not frameRef then return end
                if InCombatLockdown and InCombatLockdown() then
                    if bailMode == "always" then
                        desc.queueReapply()
                        return
                    end
                    local state = getState(frameRef)
                    if not state or not state[overlayKey] then
                        desc.queueReapply()
                        return
                    end
                end
                ensureFn(frameRef, cfgRef)
            end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, apply)
            else
                apply()
            end
        end
    end

    return family
end
