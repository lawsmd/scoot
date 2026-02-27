--------------------------------------------------------------------------------
-- bars/raidframes/text.lua
-- Raid frame text styling: legacy text, name overlays, status text overlays,
-- group title styling, and text hook installation.
--
-- Loaded after raidframes/core.lua. Imports shared state from
-- addon.BarsRaidFrames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Get module namespace (created in core.lua)
local RaidFrames = addon.BarsRaidFrames

-- Import shared state from core.lua
local RaidFrameState = addon.BarsRaidFrames._RaidFrameState
local getState = addon.BarsRaidFrames._getState
local ensureState = addon.BarsRaidFrames._ensureState
local isEditModeActive = addon.BarsRaidFrames._isEditModeActive

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to raid frame name text elements.
-- Target: CompactRaidGroup*Member*Name (the name FontString on each raid unit frame)
--------------------------------------------------------------------------------

-- Apply text settings to a raid frame's name FontString
local function applyTextToRaidFrame(frame, cfg)
    if not frame or not cfg then return end

    -- Get the name FontString (frame.name is the standard CompactUnitFrame name element)
    local nameFS = frame.name
    if not nameFS then return end

    -- Resolve font face
    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        -- Fallback to GameFontNormal's font
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    -- Get settings with defaults
    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    -- Apply font (SetFont must be called before SetText)
    local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
    if not success then
        -- Fallback to default font on failure
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color
    if nameFS.SetTextColor then
        pcall(nameFS.SetTextColor, nameFS, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    -- Apply text alignment based on anchor's horizontal component
    if nameFS.SetJustifyH then
        pcall(nameFS.SetJustifyH, nameFS, Utils.getJustifyHFromAnchor(anchor))
    end

    -- Capture baseline position on first application for later restoration
    local nameState = ensureState(nameFS)
    if nameState and not nameState.originalPoint then
        local point, relativeTo, relativePoint, x, y = nameFS:GetPoint(1)
        if point then
            nameState.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    -- Apply anchor-based positioning with offsets relative to selected anchor
    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and nameState and nameState.originalPoint then
        -- Restore baseline (stock position) when user has reset to default
        local orig = nameState.originalPoint
        nameFS:ClearAllPoints()
        nameFS:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        -- Also restore default text alignment
        if nameFS.SetJustifyH then
            pcall(nameFS.SetJustifyH, nameFS, "LEFT")
        end
    else
        -- Position the name FontString using the user-selected anchor, relative to the frame
        nameFS:ClearAllPoints()
        nameFS:SetPoint(anchor, frame, anchor, offsetX, offsetY)
    end
end

-- Collect all raid frame name FontStrings
local raidNameTexts = {}

local function collectRaidNameTexts()
    if wipe then
        wipe(raidNameTexts)
    else
        raidNameTexts = {}
    end

    -- Scan CompactRaidFrame1 through CompactRaidFrame40 (combined layout)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name then
            local nameState = ensureState(frame.name)
            if nameState and not nameState.raidTextCounted then
                nameState.raidTextCounted = true
                table.insert(raidNameTexts, frame)
            end
        end
    end

    -- Scan CompactRaidGroup1Member1 through CompactRaidGroup8Member5 (group layout)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name then
                local nameState = ensureState(frame.name)
                if nameState and not nameState.raidTextCounted then
                    nameState.raidTextCounted = true
                    table.insert(raidNameTexts, frame)
                end
            end
        end
    end
end

-- Main entry point: Apply raid frame text styling from DB settings
function addon.ApplyRaidFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if user hasn't actually changed anything from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Deprecated: Raid Player Name styling is now driven by overlay FontStrings
    -- (see ApplyRaidFrameNameOverlays). Moving Blizzard's `frame.name` must be avoided
    -- because the overlay clipping container copies its anchor geometry to preserve
    -- truncation. Touching `frame.name` here reintroduces leaking/incorrect clipping.
    if addon.ApplyRaidFrameNameOverlays then
        addon.ApplyRaidFrameNameOverlays()
    end
end

-- Install hooks to reapply text styling when raid frames update
local function installRaidFrameTextHooks()
    if addon._RaidFrameTextHooksInstalled then return end
    addon._RaidFrameTextHooksInstalled = true

    -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
    -- Overlay system installs its own hooks (installRaidNameOverlayHooks()).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because only
-- addon-owned FontStrings are manipulated.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

-- Shared helper: create/return the clipping container that spans the full unit frame.
-- Used by both name and status text overlays for 9-way alignment.
local function ensureOverlayContainer(frame)
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

        -- Elevate roleIcon when creating overlay container
        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        frameState.nameOverlayContainer = container
    end

    return frameState.nameOverlayContainer
end

local function styleRaidNameOverlay(frame, cfg)
    if not frame or not cfg then return end
    local state = getState(frame)
    if not state or not state.nameOverlayText then return end

    local overlay = state.nameOverlayText
    local container = state.nameOverlayContainer or frame

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    -- Determine color based on colorMode
    local colorMode = cfg.colorMode or "default"
    local r, g, b, a = 1, 1, 1, 1
    if colorMode == "class" then
        -- Use the raid member's class color
        local unit = frame.unit
        if addon.GetClassColorRGB and unit then
            local cr, cg, cb = addon.GetClassColorRGB(unit)
            r, g, b, a = cr or 1, cg or 1, cb or 1, 1
        end
    elseif colorMode == "custom" then
        local color = cfg.color or { 1, 1, 1, 1 }
        r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
    else
        -- "default" - use white
        r, g, b, a = 1, 1, 1, 1
    end

    pcall(overlay.SetTextColor, overlay, r, g, b, a)

    -- Always use LEFT justify so truncation only happens on the right side.
    -- This ensures player names always show the beginning of the name.
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

    -- Position using dynamic text-width-based alignment.
    -- repositionNameOverlay computes exact CENTER/RIGHT offset from GetStringWidth().
    Utils.repositionNameOverlay(overlay, container, anchor, offsetX, offsetY)

    -- Store alignment params so the SetText hook can reposition after text changes.
    if state then
        state.nameAnchor = anchor
        state.nameOffsetX = offsetX
        state.nameOffsetY = offsetY
    end
end

local function hideBlizzardRaidNameText(frame)
    if not frame or not frame.name then return end
    local blizzName = frame.name

    local nameState = ensureState(blizzName)
    if nameState then nameState.hidden = true end
    if blizzName.SetAlpha then
        pcall(blizzName.SetAlpha, blizzName, 0)
    end
    if blizzName.Hide then
        pcall(blizzName.Hide, blizzName)
    end

    if _G.hooksecurefunc and nameState and not nameState.alphaHooked then
        nameState.alphaHooked = true
        _G.hooksecurefunc(blizzName, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if _G.hooksecurefunc and nameState and not nameState.showHooked then
        nameState.showHooked = true
        _G.hooksecurefunc(blizzName, "Show", function(self)
            local st = getState(self)
            if not (st and st.hidden) then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide to break chains.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
                        if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                        if self.Hide then pcall(self.Hide, self) end
                    end
                end)
            else
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                if self.Hide then pcall(self.Hide, self) end
            end
        end)
    end
end

local function showBlizzardRaidNameText(frame)
    if not frame or not frame.name then return end
    local nameState = getState(frame.name)
    if nameState then nameState.hidden = nil end
    if frame.name.SetAlpha then
        pcall(frame.name.SetAlpha, frame.name, 1)
    end
    if frame.name.Show then
        pcall(frame.name.Show, frame.name)
    end
end

local function ensureRaidNameOverlay(frame, cfg)
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
        showBlizzardRaidNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container that spans the FULL unit frame.
    -- This allows 9-way alignment to position text anywhere within the frame.
    ensureOverlayContainer(frame)

    -- Create overlay FontString if it doesn't exist (as a child of the clipping container)
    if frameState and not frameState.nameOverlayText then
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
                    if type(text) == "string" then
                        local displayText = text
                        -- Strip realm suffix: "Name-Realm" -> "Name"
                        -- WoW names cannot contain hyphens; hyphen always delimits realm.
                        if ownerState.hideRealmEnabled and displayText ~= "" then
                            displayText = displayText:match("^([^%-]+)") or displayText
                        end
                        ownerState.nameOverlayText:SetText(displayText)
                    else
                        -- Secret or other type -- SetText handles secrets natively
                        pcall(ownerState.nameOverlayText.SetText, ownerState.nameOverlayText, text)
                    end
                    -- Reposition after text change so CENTER/RIGHT alignment adapts to new text width
                    if ownerState.nameAnchor then
                        Utils.repositionNameOverlay(ownerState.nameOverlayText,
                            ownerState.nameOverlayContainer or frame,
                            ownerState.nameAnchor, ownerState.nameOffsetX or 0, ownerState.nameOffsetY or 0)
                    end
                end
            end)
        end
    end

    -- Build fingerprint to detect config changes AND unit-specific state.
    -- When colorMode is "class", include the resolved class token so the
    -- fingerprint changes when unit data becomes available (e.g., zone-in).
    local fpColorMode = cfg.colorMode or "default"
    local classKey = ""
    if fpColorMode == "class" and frame.unit then
        local ok, _, token = pcall(function() return UnitClass(frame.unit) end)
        if ok and type(token) == "string" then
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

    -- Skip re-styling if config hasn't changed and overlay is visible
    if frameState.lastNameFingerprint == fingerprint and frameState.nameOverlayText and frameState.nameOverlayText:IsShown() then
        return
    end
    frameState.lastNameFingerprint = fingerprint

    styleRaidNameOverlay(frame, cfg)
    hideBlizzardRaidNameText(frame)

    local textCopied = false
    if frameState and frameState.nameOverlayText and frame.name and frame.name.GetText then
        local ok, currentText = pcall(frame.name.GetText, frame.name)
        if ok and type(currentText) == "string" and currentText ~= "" then
            local displayText = currentText
            -- Strip realm suffix: "Name-Realm" -> "Name"
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            frameState.nameOverlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Fallback: if GetText failed (secret/nil), try GetUnitName
    if not textCopied and frameState and frameState.nameOverlayText and frame.unit then
        local unitOk, unitName = pcall(GetUnitName, frame.unit, true)
        if unitOk and type(unitName) == "string" and unitName ~= "" then
            local displayText = unitName
            -- Strip realm suffix: "Name-Realm" -> "Name"
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            frameState.nameOverlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Last resort: if both returned secrets, pass through directly
    if not textCopied and frameState and frameState.nameOverlayText and frame.name and frame.name.GetText then
        local ok, rawText = pcall(frame.name.GetText, frame.name)
        if ok then
            pcall(frameState.nameOverlayText.SetText, frameState.nameOverlayText, rawText)
        end
    end

    -- Reposition after initial text copy so CENTER/RIGHT alignment uses actual text width
    if frameState and frameState.nameAnchor and frameState.nameOverlayText then
        Utils.repositionNameOverlay(frameState.nameOverlayText,
            frameState.nameOverlayContainer or frame,
            frameState.nameAnchor, frameState.nameOffsetX or 0, frameState.nameOffsetY or 0)
    end

    if frameState and frameState.nameOverlayText then
        frameState.nameOverlayText:Show()
    end
end

local function disableRaidNameOverlay(frame)
    if not frame then return end
    local frameState = getState(frame)
    if frameState then
        frameState.nameOverlayActive = false
        if frameState.nameOverlayText then
            frameState.nameOverlayText:Hide()
        end
    end
    showBlizzardRaidNameText(frame)

    -- Restore roleIcon to stock draw layer
    local okR, roleIcon = pcall(function() return frame.roleIcon end)
    if okR and roleIcon and roleIcon.SetDrawLayer then
        pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
    end
end

function addon.ApplyRaidFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local cfg = rawget(raidCfg, "textPlayerName") or nil
    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- If no custom settings, skip - let RestoreRaidFrameNameOverlays handle cleanup
    if not hasCustom then return end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.name then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensureRaidNameOverlay(frame, cfg)
            else
                local state = getState(frame)
                if state and state.nameOverlayText then
                    styleRaidNameOverlay(frame, cfg)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.name then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidNameOverlay(frame, cfg)
                else
                    local state = getState(frame)
                    if state and state.nameOverlayText then
                        styleRaidNameOverlay(frame, cfg)
                    end
                end
            end
        end
    end
end

function addon.RestoreRaidFrameNameOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidNameOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidNameOverlay(frame)
            end
        end
    end
end

local function installRaidNameOverlayHooks()
    if addon._RaidNameOverlayHooksInstalled then return end
    addon._RaidNameOverlayHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textPlayerName") or nil
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not unit then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not (frame and frame.name and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidNameOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidNameOverlay(frameRef, cfgRef)
            end
        end)
    end

    -- Event-driven re-application for raid composition changes.
    if not addon._RaidNameRosterEventInstalled then
        addon._RaidNameRosterEventInstalled = true
        local rosterFrame = CreateFrame("Frame")
        rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterFrame:SetScript("OnEvent", function()
            if isEditModeActive() then return end

            local cfg = getCfg()
            if not cfg or (cfg.colorMode or "default") ~= "class" then return end
            if not Utils.hasCustomTextSettings(cfg) then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.5, function()
                    if isEditModeActive() then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    if addon.ApplyRaidFrameNameOverlays then
                        addon.ApplyRaidFrameNameOverlays()
                    end
                end)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Overlay (Status Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on raid frames that visually replace
-- Blizzard's statusText. These overlays persist during combat because only
-- addon-owned FontStrings are manipulated. Blizzard can reset its own
-- statusText all it wants -- our overlay stays styled.
--
-- Pattern: Mirror text via SetText/SetFormattedText hooks, style on setup,
-- hide Blizzard's element via SetAlpha(0).
--------------------------------------------------------------------------------

local function styleRaidStatusTextOverlay(frame, cfg)
    if not frame or not cfg then return end
    local state = getState(frame)
    if not state or not state.statusTextOverlay then return end

    local overlay = state.statusTextOverlay
    local container = state.nameOverlayContainer or frame

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color
    local color = cfg.color or { 1, 1, 1, 1 }
    pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    -- Justify based on anchor
    pcall(overlay.SetJustifyH, overlay, Utils.getJustifyHFromAnchor(anchor))
    if overlay.SetJustifyV then
        -- Derive vertical justify from anchor
        local justV = "MIDDLE"
        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
            justV = "TOP"
        elseif anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            justV = "BOTTOM"
        end
        pcall(overlay.SetJustifyV, overlay, justV)
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

    -- Position within the clipping container
    overlay:ClearAllPoints()
    overlay:SetPoint(anchor, container, anchor, offsetX, offsetY)

    -- Store alignment params for fingerprint checks
    if state then
        state.statusTextAnchor = anchor
        state.statusTextOffsetX = offsetX
        state.statusTextOffsetY = offsetY
    end
end

local function hideBlizzardRaidStatusText(frame)
    if not frame or not frame.statusText then return end
    local blizzST = frame.statusText

    local stState = ensureState(blizzST)
    if stState then stState.hidden = true end
    if blizzST.SetAlpha then
        pcall(blizzST.SetAlpha, blizzST, 0)
    end

    if _G.hooksecurefunc and stState and not stState.alphaHooked then
        stState.alphaHooked = true
        _G.hooksecurefunc(blizzST, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if _G.hooksecurefunc and stState and not stState.showHooked then
        stState.showHooked = true
        _G.hooksecurefunc(blizzST, "Show", function(self)
            local st = getState(self)
            if not (st and st.hidden) then return end
            -- Kill visibility immediately (avoid flicker), then defer Hide.
            if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local st2 = getState(self)
                    if self and st2 and st2.hidden then
                        if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
                    end
                end)
            else
                if self.SetAlpha then pcall(self.SetAlpha, self, 0) end
            end
        end)
    end
end

local function showBlizzardRaidStatusText(frame)
    if not frame or not frame.statusText then return end
    local stState = getState(frame.statusText)
    if stState then stState.hidden = nil end
    if frame.statusText.SetAlpha then
        pcall(frame.statusText.SetAlpha, frame.statusText, 1)
    end
end

local function ensureRaidStatusTextOverlay(frame, cfg)
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
        showBlizzardRaidStatusText(frame)
        return
    end

    -- Ensure shared clipping container
    ensureOverlayContainer(frame)

    -- Create overlay FontString if it doesn't exist
    if frameState and not frameState.statusTextOverlay then
        local parentForText = frameState.nameOverlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 5)  -- Below name text (7) and role icon (6)
        frameState.statusTextOverlay = overlay

        -- Install mirroring hooks on Blizzard's statusText
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
                -- Mirror visibility: if Blizzard is showing status text, show our overlay
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

    -- Build fingerprint to detect config changes
    local fingerprint = string.format("%s|%s|%s|%s|%s|%s",
        tostring(cfg.fontFace or ""),
        tostring(cfg.size or ""),
        tostring(cfg.style or ""),
        tostring(cfg.anchor or ""),
        cfg.color and string.format("%.2f,%.2f,%.2f,%.2f",
            cfg.color[1] or 1, cfg.color[2] or 1, cfg.color[3] or 1, cfg.color[4] or 1) or "",
        cfg.offset and string.format("%.1f,%.1f", cfg.offset.x or 0, cfg.offset.y or 0) or ""
    )

    -- Skip re-styling if config hasn't changed and overlay is visible
    if frameState.lastStatusTextFingerprint == fingerprint and frameState.statusTextOverlay and frameState.statusTextOverlay:IsShown() then
        return
    end
    frameState.lastStatusTextFingerprint = fingerprint

    styleRaidStatusTextOverlay(frame, cfg)
    hideBlizzardRaidStatusText(frame)

    -- Copy current text from Blizzard's statusText to the overlay
    if frameState and frameState.statusTextOverlay and frame.statusText then
        local blizzST = frame.statusText
        -- Check if Blizzard's statusText is currently shown
        local isVisible = false
        if blizzST.IsShown then
            local okV, vis = pcall(blizzST.IsShown, blizzST)
            isVisible = okV and vis
        end

        if blizzST.GetText then
            local ok, currentText = pcall(blizzST.GetText, blizzST)
            if ok and type(currentText) == "string" and currentText ~= "" then
                frameState.statusTextOverlay:SetText(currentText)
            elseif ok then
                -- Secret or non-string -- forward directly
                pcall(frameState.statusTextOverlay.SetText, frameState.statusTextOverlay, currentText)
            end
        end

        -- Match Blizzard's visibility state
        if isVisible then
            frameState.statusTextOverlay:Show()
        else
            frameState.statusTextOverlay:Hide()
        end
    end
end

local function disableRaidStatusTextOverlay(frame)
    if not frame then return end
    local frameState = getState(frame)
    if frameState then
        frameState.statusTextOverlayActive = false
        if frameState.statusTextOverlay then
            frameState.statusTextOverlay:Hide()
        end
    end
    showBlizzardRaidStatusText(frame)
end

function addon.ApplyRaidFrameStatusTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid status text styling.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textStatusText") or nil
    if not cfg then
        return
    end

    -- Zero-Touch: if user hasn't actually changed anything from the defaults, do nothing.
    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.statusText then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensureRaidStatusTextOverlay(frame, cfg)
            else
                -- During combat: only re-style existing overlays (no frame creation)
                local state = getState(frame)
                if state and state.statusTextOverlay then
                    styleRaidStatusTextOverlay(frame, cfg)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1..8Member1..5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame and frame.statusText then
                if not (InCombatLockdown and InCombatLockdown()) then
                    ensureRaidStatusTextOverlay(frame, cfg)
                else
                    local state = getState(frame)
                    if state and state.statusTextOverlay then
                        styleRaidStatusTextOverlay(frame, cfg)
                    end
                end
            end
        end
    end
end

function addon.RestoreRaidFrameStatusTextOverlays()
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            disableRaidStatusTextOverlay(frame)
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                disableRaidStatusTextOverlay(frame)
            end
        end
    end
end

local function installRaidFrameStatusTextHooks()
    if addon._RaidFrameStatusTextHooksInstalled then return end
    addon._RaidFrameStatusTextHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local raidCfg = gf and rawget(gf, "raid") or nil
        return raidCfg and rawget(raidCfg, "textStatusText") or nil
    end

    -- Hook CompactUnitFrame_UpdateAll for overlay setup on full refresh
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if isEditModeActive() then return end
            if not (frame and frame.statusText and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidStatusTextOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidStatusTextOverlay(frameRef, cfgRef)
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit for overlay setup on unit assignment
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            if isEditModeActive() then return end
            if not unit then return end
            if not (frame and frame.statusText and Utils.isRaidFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queueRaidFrameReapply()
                        return
                    end
                    ensureRaidStatusTextOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                ensureRaidStatusTextOverlay(frameRef, cfgRef)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Group Numbers / Group Titles)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Player Name to raid group title text.
-- Target: CompactRaidGroup1..8Title (Button, parentKey "title").
--------------------------------------------------------------------------------

-- Get the current raid group orientation from Edit Mode settings
-- Returns "horizontal" or "vertical"
local function getGroupOrientation()
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    local EMSetting = _G.Enum and _G.Enum.EditModeUnitFrameSetting
    local RGD = _G.Enum and _G.Enum.RaidGroupDisplayType
    if not (mgr and EM and EMSys and EMSetting and RGD and mgr.GetRegisteredSystemFrame) then
        return "vertical" -- Default fallback
    end
    local raidFrame = mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, EM.Raid)
    if not raidFrame then return "vertical" end
    if not (addon and addon.EditMode and addon.EditMode.GetSetting) then
        return "vertical"
    end
    local displayType = addon.EditMode.GetSetting(raidFrame, EMSetting.RaidGroupDisplayType)
    if displayType == RGD.SeparateGroupsHorizontal or displayType == RGD.CombineGroupsHorizontal then
        return "horizontal"
    end
    return "vertical"
end

-- Apply number-only text and auto-centering to a group title
-- groupIndex: the group number (1-8)
local function applyNumberOnlyToGroupTitle(titleButton, groupIndex, cfg)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    -- Set text to just the number
    if fs.SetText then
        pcall(fs.SetText, fs, tostring(groupIndex or ""))
    end

    -- Determine orientation and set auto-centering
    local orientation = getGroupOrientation()

    -- Apply centering based on orientation
    if orientation == "vertical" then
        -- Vertical layout: groups stacked vertically, title centered above each column
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "CENTER")
        end
        -- Position at TOP, centered horizontally
        local offsetX = cfg and cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg and cfg.offset and tonumber(cfg.offset.y) or 0
        fs:ClearAllPoints()
        fs:SetPoint("TOP", titleButton, "TOP", offsetX, offsetY)
    else
        -- Horizontal layout: groups laid out horizontally, title beside each row
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
        -- Position at LEFT
        local offsetX = cfg and cfg.offset and tonumber(cfg.offset.x) or 0
        local offsetY = cfg and cfg.offset and tonumber(cfg.offset.y) or 0
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", titleButton, "LEFT", offsetX, offsetY)
    end
end

local function applyTextToFontString_GroupTitle(fs, ownerFrame, cfg)
    if not fs or not ownerFrame or not cfg then return end

    local fontFace = cfg.fontFace or "FRIZQT__"
    local resolvedFace
    if addon and addon.ResolveFontFace then
        resolvedFace = addon.ResolveFontFace(fontFace)
    else
        local defaultFont = _G.GameFontNormal and _G.GameFontNormal:GetFont()
        resolvedFace = defaultFont or "Fonts\\FRIZQT__.TTF"
    end

    local fontSize = tonumber(cfg.size) or 12
    local fontStyle = cfg.style or "OUTLINE"
    local color = cfg.color or { 1, 1, 1, 1 }
    local anchor = cfg.anchor or "TOPLEFT"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(fs.SetFont, fs, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(fs.SetFont, fs, fallback, fontSize, fontStyle)
        end
    end

    if fs.SetTextColor then
        pcall(fs.SetTextColor, fs, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if fs.SetJustifyH then
        pcall(fs.SetJustifyH, fs, Utils.getJustifyHFromAnchor(anchor))
    end

    local fsState = ensureState(fs)
    if fsState and not fsState.originalPointGroupTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointGroupTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointGroupTitle then
        local orig = fsState.originalPointGroupTitle
        fs:ClearAllPoints()
        fs:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
        if fs.SetJustifyH then
            pcall(fs.SetJustifyH, fs, "LEFT")
        end
    else
        fs:ClearAllPoints()
        fs:SetPoint(anchor, ownerFrame, anchor, offsetX, offsetY)
    end
end

local function applyGroupTitleToButton(titleButton, cfg, groupIndex)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    -- Check if numbers-only mode is enabled
    local db = addon and addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid
    local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

    if numbersOnly and groupIndex then
        -- Apply font styling first (font face, size, style, color)
        applyTextToFontString_GroupTitle(fs, titleButton, cfg)
        -- Then apply number-only text and auto-centering (overrides anchor/position)
        applyNumberOnlyToGroupTitle(titleButton, groupIndex, cfg)
    else
        -- Standard styling with full "Group N" text
        applyTextToFontString_GroupTitle(fs, titleButton, cfg)
    end
end

function addon.ApplyRaidFrameGroupTitlesStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    -- Zero-Touch: only apply if user has configured raid group title styling
    -- OR if numbers-only mode is enabled.
    local groupFrames = rawget(db, "groupFrames")
    local raidCfg = groupFrames and rawget(groupFrames, "raid") or nil
    local cfg = raidCfg and rawget(raidCfg, "textGroupNumbers") or nil
    local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

    -- If no text config and numbers-only is not enabled, skip (Zero-Touch)
    if not cfg and not numbersOnly then
        return
    end

    -- If text config exists, check if it has custom settings
    -- Numbers-only mode alone is enough to proceed
    if cfg and not Utils.hasCustomTextSettings(cfg) and not numbersOnly then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queueRaidFrameReapply()
        return
    end

    -- Ensure cfg exists for applyGroupTitleToButton (use empty table as fallback)
    local effectiveCfg = cfg or {}

    for group = 1, 8 do
        local groupFrame = _G["CompactRaidGroup" .. group]
        local titleButton = (groupFrame and groupFrame.title) or _G["CompactRaidGroup" .. group .. "Title"]
        if titleButton then
            applyGroupTitleToButton(titleButton, effectiveCfg, group)
        end
    end
end

local function installRaidFrameGroupTitleHooks()
    if addon._RaidFrameGroupTitleHooksInstalled then return end
    addon._RaidFrameGroupTitleHooksInstalled = true

    local function tryApplyTitle(groupFrame, groupIndex)
        -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
        if isEditModeActive() then return end
        if not groupFrame or not Utils.isCompactRaidGroupFrame(groupFrame) then
            return
        end
        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local db = addon and addon.db and addon.db.profile
        local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil
        local cfg = raidCfg and raidCfg.textGroupNumbers or nil
        local numbersOnly = raidCfg and raidCfg.groupTitleNumbersOnly == true

        -- Zero-Touch: skip if no text config and numbers-only is not enabled
        if not cfg and not numbersOnly then
            return
        end
        if cfg and not Utils.hasCustomTextSettings(cfg) and not numbersOnly then
            return
        end

        -- Extract group index from frame name if not provided
        local effectiveGroupIndex = groupIndex
        if not effectiveGroupIndex then
            local frameName = groupFrame:GetName()
            if frameName then
                effectiveGroupIndex = tonumber(frameName:match("CompactRaidGroup(%d+)"))
            end
        end

        local titleRef = titleButton
        local cfgRef = cfg or {}
        local groupIndexRef = effectiveGroupIndex
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queueRaidFrameReapply()
                    return
                end
                applyGroupTitleToButton(titleRef, cfgRef, groupIndexRef)
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queueRaidFrameReapply()
                return
            end
            applyGroupTitleToButton(titleRef, cfgRef, groupIndexRef)
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", function(groupFrame)
                -- Extract group index from frame
                local groupIndex = groupFrame and groupFrame.GetID and groupFrame:GetID()
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
        if _G.CompactRaidGroup_InitializeForGroup then
            _G.hooksecurefunc("CompactRaidGroup_InitializeForGroup", function(groupFrame, groupIndex)
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", function(groupFrame)
                -- Extract group index from frame
                local groupIndex = groupFrame and groupFrame.GetID and groupFrame:GetID()
                tryApplyTitle(groupFrame, groupIndex)
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function RaidFrames.installTextHooks()
    installRaidFrameTextHooks()
    installRaidNameOverlayHooks()
    installRaidFrameStatusTextHooks()
    installRaidFrameGroupTitleHooks()
end

-- Install text hooks on load
RaidFrames.installTextHooks()
