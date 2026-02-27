--------------------------------------------------------------------------------
-- bars/partyframes/text.lua
-- Party frame text styling: legacy text, name overlays, party title styling,
-- and text hook installation.
--
-- Loaded after partyframes/core.lua. Imports shared state from
-- addon.BarsPartyFrames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Get module namespace (created in core.lua)
local PartyFrames = addon.BarsPartyFrames

-- Import shared state from core.lua
local PartyFrameState = addon.BarsPartyFrames._PartyFrameState
local getState = addon.BarsPartyFrames._getState
local ensureState = addon.BarsPartyFrames._ensureState
local isEditModeActive = addon.BarsPartyFrames._isEditModeActive

--------------------------------------------------------------------------------
-- Text Styling (Player Name)
--------------------------------------------------------------------------------
-- Applies font settings to party frame name text elements.
-- Target: CompactPartyFrameMember[1-5].name (FontString with parentKey="name")
--------------------------------------------------------------------------------

local function applyTextToPartyFrame(frame, cfg)
    if not frame or not cfg then return end

    local nameFS = frame.name
    if not nameFS then return end

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

    local success = pcall(nameFS.SetFont, nameFS, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(nameFS.SetFont, nameFS, fallback, fontSize, fontStyle)
        end
    end

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

    -- Preserve Blizzard's truncation/clipping behavior: explicitly constrain the name FontString width.
    -- Blizzard normally constrains this via a dual-anchor layout (TOPLEFT + TOPRIGHT). The single-point
    -- anchor (for 9-way alignment) removes that implicit width, so SetWidth restores it.
    if nameFS.SetMaxLines then
        pcall(nameFS.SetMaxLines, nameFS, 1)
    end
    if frame.GetWidth and nameFS.SetWidth then
        local frameWidth = frame:GetWidth()
        local roleIconWidth = 0
        if frame.roleIcon and frame.roleIcon.GetWidth then
            roleIconWidth = frame.roleIcon:GetWidth() or 0
        end
        -- 3px right padding + (role icon area) + 3px left padding ~= 6px padding total, matching CUF defaults.
        local availableWidth = (frameWidth or 0) - (roleIconWidth or 0) - 6
        if availableWidth and availableWidth > 1 then
            pcall(nameFS.SetWidth, nameFS, availableWidth)
        else
            pcall(nameFS.SetWidth, nameFS, 1)
        end
    end
end

local partyFramesForText = {}
local function collectPartyFramesForText()
    if wipe then
        wipe(partyFramesForText)
    else
        partyFramesForText = {}
    end
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.name then
            local nameState = getState(frame.name)
            if not nameState or not nameState.partyTextCounted then
                local st = ensureState(frame.name)
                if st then st.partyTextCounted = true end
                table.insert(partyFramesForText, frame)
            end
        end
    end
end

function addon.ApplyPartyFrameTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPlayerName") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    -- Deprecated: Party Player Name styling is now driven by overlay FontStrings
    -- (see ApplyPartyFrameNameOverlays). Avoid touching Blizzard's `frame.name`
    -- so overlay clipping preserves stock truncation behavior.
    if addon.ApplyPartyFrameNameOverlays then
        addon.ApplyPartyFrameNameOverlays()
    end
end

local function installPartyFrameTextHooks()
    if addon._PartyFrameTextHooksInstalled then return end
    addon._PartyFrameTextHooksInstalled = true

    -- Deprecated: name styling hooks must not touch Blizzard's `frame.name`.
    -- Overlay system installs its own hooks (installPartyNameOverlayHooks()).
end

--------------------------------------------------------------------------------
-- Text Overlay (Name Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's name text. These overlays can be styled during initial setup and
-- their text content can be updated during combat without taint because only
-- addon-owned FontStrings are manipulated.
--
-- Pattern: Mirror text via SetText hook, style on setup, hide Blizzard's element.
--------------------------------------------------------------------------------

-- Apply styling to the overlay FontString
local function stylePartyNameOverlay(frame, cfg)
    local state = getState(frame)
    if not frame or not state or not state.overlayText or not cfg then return end

    local overlay = state.overlayText
    local container = state.overlayContainer or frame

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

    -- Apply font
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
        -- Use the party member's class color
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

    -- Apply color
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
    state.nameAnchor = anchor
    state.nameOffsetX = offsetX
    state.nameOffsetY = offsetY
end

-- Hide Blizzard's name FontString and install alpha-enforcement hook
local function hideBlizzardPartyNameText(frame)
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

    -- Install alpha-enforcement hook (only once)
    if nameState and not nameState.alphaHooked and _G.hooksecurefunc then
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

    if nameState and not nameState.showHooked and _G.hooksecurefunc then
        nameState.showHooked = true
        _G.hooksecurefunc(blizzName, "Show", function(self)
            local st = getState(self)
            if not st or not st.hidden then return end
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

-- Show Blizzard's name FontString (for restore/cleanup)
local function showBlizzardPartyNameText(frame)
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

-- Create or update the party name text overlay for a specific frame
-- TAINT PREVENTION: Uses lookup table instead of writing to Blizzard frames
local function ensurePartyNameOverlay(frame, cfg)
    if not frame then return end

    local hasCustom = Utils.hasCustomTextSettings(cfg)
    local state = ensureState(frame)
    state.overlayActive = hasCustom
    state.hideRealmEnabled = cfg and cfg.hideRealm and true or false

    if not hasCustom then
        -- Disable overlay, show Blizzard's text
        if state.overlayText then
            state.overlayText:Hide()
        end
        showBlizzardPartyNameText(frame)
        return
    end

    -- Ensure an addon-owned clipping container for name text.
    -- IMPORTANT: This container must span the full available unit-frame area so 9-way alignment
    -- (e.g., BOTTOM / BOTTOMRIGHT) can genuinely reach the bottom of the frame.
    if not state.overlayContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        container:ClearAllPoints()
        -- Small insets to match CUF's typical text padding and avoid touching frame edges.
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        -- Elevate roleIcon when creating name overlay container
        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        state.overlayContainer = container
    end

    -- Create overlay FontString if it doesn't exist
    if not state.overlayText then
        local parentForText = state.overlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 7) -- High sublayer to ensure visibility
        state.overlayText = overlay

        -- Install SetText hook on Blizzard's name FontString to mirror text
        -- Store hook state in the addon lookup table, not on Blizzard's frame
        if frame.name and not state.textMirrorHooked and _G.hooksecurefunc then
            state.textMirrorHooked = true
            -- Capture state reference for the closure
            local frameState = state
            _G.hooksecurefunc(frame.name, "SetText", function(self, text)
                if frameState and frameState.overlayText and frameState.overlayActive then
                    -- text may be a secret value in 12.0; branch on type
                    if type(text) == "string" then
                        local displayText = text
                        -- Strip realm suffix: split on first hyphen (WoW names never contain hyphens).
                        -- Ambiguate("none") only strips same/connected realms, not cross-realm.
                        if frameState.hideRealmEnabled and displayText ~= "" then
                            displayText = displayText:match("^([^%-]+)") or displayText
                        end
                        frameState.overlayText:SetText(displayText)
                    else
                        -- Secret or other type — SetText handles secrets natively
                        pcall(frameState.overlayText.SetText, frameState.overlayText, text)
                    end
                    -- Reposition after text change so CENTER/RIGHT alignment adapts to new text width
                    if frameState.nameAnchor then
                        Utils.repositionNameOverlay(frameState.overlayText,
                            frameState.overlayContainer or frame,
                            frameState.nameAnchor, frameState.nameOffsetX or 0, frameState.nameOffsetY or 0)
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
    if state.lastNameFingerprint == fingerprint and state.overlayText:IsShown() then
        return
    end
    state.lastNameFingerprint = fingerprint

    -- Style the overlay and hide Blizzard's text
    stylePartyNameOverlay(frame, cfg)
    hideBlizzardPartyNameText(frame)

    -- Copy current text from Blizzard's FontString to the overlay
    -- Wrap in pcall as GetText() can return secrets in 12.0
    local textCopied = false
    if frame.name and frame.name.GetText then
        local ok, currentText = pcall(frame.name.GetText, frame.name)
        if ok and type(currentText) == "string" and currentText ~= "" then
            local displayText = currentText
            -- Apply realm stripping if enabled
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            state.overlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Fallback: if GetText failed (secret/nil), try GetUnitName
    if not textCopied and frame.unit then
        local unitOk, unitName = pcall(GetUnitName, frame.unit, true)
        if unitOk and type(unitName) == "string" and unitName ~= "" then
            local displayText = unitName
            if cfg and cfg.hideRealm and displayText ~= "" then
                displayText = displayText:match("^([^%-]+)") or displayText
            end
            state.overlayText:SetText(displayText)
            textCopied = true
        end
    end

    -- Last resort: if both returned secrets, pass through directly
    -- SetText handles secrets natively (renders correctly, applies Text aspect)
    if not textCopied and frame.name and frame.name.GetText then
        local ok, rawText = pcall(frame.name.GetText, frame.name)
        if ok then
            pcall(state.overlayText.SetText, state.overlayText, rawText)
        end
    end

    -- Reposition after initial text copy so CENTER/RIGHT alignment uses actual text width
    if state.nameAnchor then
        Utils.repositionNameOverlay(state.overlayText, state.overlayContainer or frame,
            state.nameAnchor, state.nameOffsetX or 0, state.nameOffsetY or 0)
    end

    state.overlayText:Show()
end

-- Disable overlay and restore Blizzard's appearance for a frame
local function disablePartyNameOverlay(frame)
    if not frame then return end
    local state = getState(frame)
    if state then
        state.overlayActive = false
        if state.overlayText then
            state.overlayText:Hide()
        end
    end
    showBlizzardPartyNameText(frame)

    -- Restore roleIcon to stock draw layer
    local okR, roleIcon = pcall(function() return frame.roleIcon end)
    if okR and roleIcon and roleIcon.SetDrawLayer then
        pcall(roleIcon.SetDrawLayer, roleIcon, "ARTWORK", 0)
    end
end

-- Apply overlays to all party frames
function addon.ApplyPartyFrameNameOverlays()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local cfg = rawget(partyCfg, "textPlayerName") or nil
    local hasCustom = Utils.hasCustomTextSettings(cfg)

    -- If no custom settings, skip - let RestorePartyFrameNameOverlays handle cleanup
    if not hasCustom then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            -- Only create overlays out of combat (initial setup)
            local state = getState(frame)
            if not (InCombatLockdown and InCombatLockdown()) then
                ensurePartyNameOverlay(frame, cfg)
            elseif state and state.overlayText then
                -- Already have overlay, just update styling (safe during combat for addon-owned FontString)
                stylePartyNameOverlay(frame, cfg)
            end
        end
    end
end

-- Restore all party frames to stock appearance
function addon.RestorePartyFrameNameOverlays()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            disablePartyNameOverlay(frame)
        end
    end
end

-- Install hooks that trigger overlay setup/updates via CompactUnitFrame events
local function installPartyNameOverlayHooks()
    if addon._PartyNameOverlayHooksInstalled then return end
    addon._PartyNameOverlayHooksInstalled = true

    -- Hook CompactUnitFrame_UpdateAll to set up overlays
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit for unit assignment changes
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not unit or not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Hook CompactUnitFrame_UpdateName for name text updates
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateName then
        _G.hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            -- CRITICAL: Skip ALL processing when Edit Mode is active to avoid taint
            if isEditModeActive() then return end
            if not frame or not frame.name or not Utils.isPartyFrame(frame) then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil

            if Utils.hasCustomTextSettings(cfg) then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if not frame then return end
                        local state = getState(frame)
                        if not state or not state.overlayText then
                            if InCombatLockdown and InCombatLockdown() then
                                Combat.queuePartyFrameReapply()
                                return
                            end
                        end
                        ensurePartyNameOverlay(frame, cfg)
                    end)
                end
            end
        end)
    end

    -- Event-driven re-application for party composition changes.
    -- When entering a Follower Dungeon (or any party change), unit class data
    -- may not be ready when CompactUnitFrame hooks first fire.
    -- GROUP_ROSTER_UPDATE provides a reliable secondary trigger.
    if not addon._PartyNameRosterEventInstalled then
        addon._PartyNameRosterEventInstalled = true
        local rosterFrame = CreateFrame("Frame")
        rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        rosterFrame:SetScript("OnEvent", function()
            if isEditModeActive() then return end

            local db = addon and addon.db and addon.db.profile
            local partyCfg = db and db.groupFrames and db.groupFrames.party or nil
            local cfg = partyCfg and partyCfg.textPlayerName or nil
            if not cfg or (cfg.colorMode or "default") ~= "class" then return end
            if not Utils.hasCustomTextSettings(cfg) then return end

            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0.5, function()
                    if isEditModeActive() then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queuePartyFrameReapply()
                        return
                    end
                    if addon.ApplyPartyFrameNameOverlays then
                        addon.ApplyPartyFrameNameOverlays()
                    end
                end)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Styling (Party Title)
--------------------------------------------------------------------------------
-- Applies the same 7 settings as Party Frames > Text > Player Name to the party frame title text.
-- Target: CompactPartyFrame.title (Button from CompactRaidGroupTemplate: "$parentTitle", parentKey="title").
--------------------------------------------------------------------------------

local function applyTextToFontString_PartyTitle(fs, ownerFrame, cfg)
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
    if fsState and not fsState.originalPointPartyTitle then
        local point, relativeTo, relativePoint, x, y = fs:GetPoint(1)
        if point then
            fsState.originalPointPartyTitle = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
    end

    local isDefaultAnchor = (anchor == "TOPLEFT")
    local isZeroOffset = (offsetX == 0 and offsetY == 0)

    if isDefaultAnchor and isZeroOffset and fsState and fsState.originalPointPartyTitle then
        local orig = fsState.originalPointPartyTitle
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

local function applyPartyTitle(titleButton, cfg)
    if not titleButton or not cfg then return end
    if not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    if cfg.hide == true then
        -- Hide always wins; styling is irrelevant while hidden.
        -- The hide logic is handled by hideBlizzardPartyTitleText below.
        return
    end
    applyTextToFontString_PartyTitle(fs, titleButton, cfg)
end

-- Hide Blizzard's party title FontString and install alpha-enforcement hook
local function hideBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end

    local fsState = ensureState(fs)
    if fsState then fsState.hidden = true end
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 0)
    end
    if fs.Hide then
        pcall(fs.Hide, fs)
    end

    -- Install alpha-enforcement hook (only once)
    if fsState and not fsState.alphaHooked and _G.hooksecurefunc then
        fsState.alphaHooked = true
        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
            local st = getState(self)
            if alpha > 0 and st and st.hidden then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        local st2 = getState(self)
                        if self and st2 and st2.hidden then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end
        end)
    end

    if fsState and not fsState.showHooked and _G.hooksecurefunc then
        fsState.showHooked = true
        _G.hooksecurefunc(fs, "Show", function(self)
            local st = getState(self)
            if not st or not st.hidden then return end
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

-- Show Blizzard's party title FontString (for restore/cleanup)
local function showBlizzardPartyTitleText(titleButton)
    if not titleButton or not titleButton.GetFontString then return end
    local fs = titleButton:GetFontString()
    if not fs then return end
    local fsState = getState(fs)
    if fsState then fsState.hidden = nil end
    if fs.SetAlpha then
        pcall(fs.SetAlpha, fs, 1)
    end
    if fs.Show then
        pcall(fs.Show, fs)
    end
end

function addon.ApplyPartyFrameTitleStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textPartyTitle") or nil
    if not cfg then
        return
    end

    -- If the user has asked to hide it, do that even if other style settings are default.
    if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        Combat.queuePartyFrameReapply()
        return
    end

    local partyFrame = _G.CompactPartyFrame
    local titleButton = partyFrame and partyFrame.title or _G.CompactPartyFrameTitle
    if titleButton then
        if cfg.hide == true then
            hideBlizzardPartyTitleText(titleButton)
        else
            showBlizzardPartyTitleText(titleButton)
            applyPartyTitle(titleButton, cfg)
        end
    end
end

local function installPartyTitleHooks()
    if addon._PartyFrameTitleHooksInstalled then return end
    addon._PartyFrameTitleHooksInstalled = true

    local function tryApply(groupFrame)
        if not groupFrame or not Utils.isCompactPartyFrame(groupFrame) then
            return
        end
        local db = addon and addon.db and addon.db.profile
        local cfg = db and db.groupFrames and db.groupFrames.party and db.groupFrames.party.textPartyTitle or nil
        if not cfg then
            return
        end
        if cfg.hide ~= true and not Utils.hasCustomTextSettings(cfg) then
            return
        end

        local titleButton = groupFrame.title or _G[groupFrame:GetName() .. "Title"]
        if not titleButton then return end

        local titleRef = titleButton
        local cfgRef = cfg
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queuePartyFrameReapply()
                    return
                end
                if cfgRef.hide == true then
                    hideBlizzardPartyTitleText(titleRef)
                else
                    showBlizzardPartyTitleText(titleRef)
                    applyPartyTitle(titleRef, cfgRef)
                end
            end)
        else
            if InCombatLockdown and InCombatLockdown() then
                Combat.queuePartyFrameReapply()
                return
            end
            if cfgRef.hide == true then
                hideBlizzardPartyTitleText(titleRef)
            else
                showBlizzardPartyTitleText(titleRef)
                applyPartyTitle(titleRef, cfgRef)
            end
        end
    end

    if _G.hooksecurefunc then
        if _G.CompactRaidGroup_UpdateLayout then
            _G.hooksecurefunc("CompactRaidGroup_UpdateLayout", tryApply)
        end
        if _G.CompactRaidGroup_UpdateUnits then
            _G.hooksecurefunc("CompactRaidGroup_UpdateUnits", tryApply)
        end
        if _G.CompactRaidGroup_UpdateBorder then
            _G.hooksecurefunc("CompactRaidGroup_UpdateBorder", tryApply)
        end
    end
end

--------------------------------------------------------------------------------
-- Text Overlay (Status Text - Combat-Safe Persistence)
--------------------------------------------------------------------------------
-- Creates addon-owned FontString overlays on party frames that visually replace
-- Blizzard's statusText. These overlays persist during combat because only
-- addon-owned FontStrings are manipulated. Blizzard can reset its own
-- statusText all it wants -- our overlay stays styled.
--
-- Pattern: Mirror text via SetText/SetFormattedText hooks, style on setup,
-- hide Blizzard's element via SetAlpha(0).
--------------------------------------------------------------------------------

local function stylePartyStatusTextOverlay(frame, cfg)
    if not frame or not cfg then return end
    local state = getState(frame)
    if not state or not state.statusTextOverlay then return end

    local overlay = state.statusTextOverlay
    local container = state.overlayContainer or frame

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
    local anchor = cfg.anchor or "CENTER"
    local offsetX = cfg.offset and tonumber(cfg.offset.x) or 0
    local offsetY = cfg.offset and tonumber(cfg.offset.y) or 0

    local success = pcall(overlay.SetFont, overlay, resolvedFace, fontSize, fontStyle)
    if not success then
        local fallback = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
        if fallback then
            pcall(overlay.SetFont, overlay, fallback, fontSize, fontStyle)
        end
    end

    -- Apply color (direct color only, no colorMode for status text)
    local color = cfg.color or { 1, 1, 1, 1 }
    pcall(overlay.SetTextColor, overlay, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)

    -- Justify based on anchor
    pcall(overlay.SetJustifyH, overlay, Utils.getJustifyHFromAnchor(anchor))
    if overlay.SetJustifyV then
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

local function hideBlizzardPartyStatusText(frame)
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

local function showBlizzardPartyStatusText(frame)
    if not frame or not frame.statusText then return end
    local stState = getState(frame.statusText)
    if stState then stState.hidden = nil end
    if frame.statusText.SetAlpha then
        pcall(frame.statusText.SetAlpha, frame.statusText, 1)
    end
end

local function ensurePartyStatusTextOverlay(frame, cfg)
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
        showBlizzardPartyStatusText(frame)
        return
    end

    -- Ensure shared clipping container (reuse the same container as name overlay)
    if not frameState.overlayContainer then
        local container = CreateFrame("Frame", nil, frame)
        container:SetClipsChildren(true)

        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
        container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

        -- Elevate roleIcon when creating overlay container
        local okR, roleIcon = pcall(function() return frame.roleIcon end)
        if okR and roleIcon and roleIcon.SetDrawLayer then
            pcall(roleIcon.SetDrawLayer, roleIcon, "OVERLAY", 6)
        end

        frameState.overlayContainer = container
    end

    -- Create overlay FontString if it doesn't exist
    if frameState and not frameState.statusTextOverlay then
        local parentForText = frameState.overlayContainer or frame
        local overlay = parentForText:CreateFontString(nil, "OVERLAY", nil)
        overlay:SetDrawLayer("OVERLAY", 5) -- Below name text (7) and role icon (6)
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

    stylePartyStatusTextOverlay(frame, cfg)
    hideBlizzardPartyStatusText(frame)

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

local function disablePartyStatusTextOverlay(frame)
    if not frame then return end
    local frameState = getState(frame)
    if frameState then
        frameState.statusTextOverlayActive = false
        if frameState.statusTextOverlay then
            frameState.statusTextOverlay:Hide()
        end
    end
    showBlizzardPartyStatusText(frame)
end

function addon.ApplyPartyFrameStatusTextStyle()
    local db = addon and addon.db and addon.db.profile
    if not db then return end

    local groupFrames = rawget(db, "groupFrames")
    local partyCfg = groupFrames and rawget(groupFrames, "party") or nil
    local cfg = partyCfg and rawget(partyCfg, "textStatusText") or nil
    if not cfg then
        return
    end

    if not Utils.hasCustomTextSettings(cfg) then
        return
    end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.statusText then
            if not (InCombatLockdown and InCombatLockdown()) then
                ensurePartyStatusTextOverlay(frame, cfg)
            else
                -- During combat: only re-style existing overlays (no frame creation)
                local state = getState(frame)
                if state and state.statusTextOverlay then
                    stylePartyStatusTextOverlay(frame, cfg)
                end
            end
        end
    end
end

function addon.RestorePartyFrameStatusTextOverlays()
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            disablePartyStatusTextOverlay(frame)
        end
    end
end

local function installPartyStatusTextHooks()
    if addon._PartyStatusTextHooksInstalled then return end
    addon._PartyStatusTextHooksInstalled = true

    local function getCfg()
        local db = addon and addon.db and addon.db.profile
        local gf = db and rawget(db, "groupFrames") or nil
        local partyCfg = gf and rawget(gf, "party") or nil
        return partyCfg and rawget(partyCfg, "textStatusText") or nil
    end

    -- Hook CompactUnitFrame_UpdateAll for overlay setup on full refresh
    if _G.hooksecurefunc and _G.CompactUnitFrame_UpdateAll then
        _G.hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
            if isEditModeActive() then return end
            if not (frame and frame.statusText and Utils.isPartyFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queuePartyFrameReapply()
                        return
                    end
                    ensurePartyStatusTextOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queuePartyFrameReapply()
                    return
                end
                ensurePartyStatusTextOverlay(frameRef, cfgRef)
            end
        end)
    end

    -- Hook CompactUnitFrame_SetUnit for overlay setup on unit assignment
    if _G.hooksecurefunc and _G.CompactUnitFrame_SetUnit then
        _G.hooksecurefunc("CompactUnitFrame_SetUnit", function(frame, unit)
            if isEditModeActive() then return end
            if not unit then return end
            if not (frame and frame.statusText and Utils.isPartyFrame(frame)) then return end
            local cfg = getCfg()
            if not Utils.hasCustomTextSettings(cfg) then return end

            local frameRef = frame
            local cfgRef = cfg
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    if not frameRef then return end
                    if InCombatLockdown and InCombatLockdown() then
                        Combat.queuePartyFrameReapply()
                        return
                    end
                    ensurePartyStatusTextOverlay(frameRef, cfgRef)
                end)
            else
                if InCombatLockdown and InCombatLockdown() then
                    Combat.queuePartyFrameReapply()
                    return
                end
                ensurePartyStatusTextOverlay(frameRef, cfgRef)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Text Hook Installation
--------------------------------------------------------------------------------

function PartyFrames.installTextHooks()
    installPartyFrameTextHooks()
    installPartyNameOverlayHooks()
    installPartyStatusTextHooks()
    installPartyTitleHooks()
end

-- Install text hooks on load
PartyFrames.installTextHooks()
