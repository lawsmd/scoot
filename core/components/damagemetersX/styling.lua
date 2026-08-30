local addonName, addon = ...

-- damagemetersX/styling.lua — Entry-level styling orchestration, enhanced title system,
-- window/title/timer/button/header styling, main ApplyDamageMeterStyling orchestrator.

local DMX = addon.DamageMetersX

-- Local aliases for frequently used namespace functions
local SafeSetAlpha = DMX._SafeSetAlpha
local SafeSetShown = DMX._SafeSetShown
local PlayerInCombat = DMX._PlayerInCombat
local getWindowState = DMX._getWindowState
local getElementState = DMX._getElementState
local elementState = DMX._elementState
local knownSessionWindows = DMX._knownSessionWindows

--------------------------------------------------------------------------------
-- Enhanced Title Feature: Display session type alongside meter type
-- e.g., "DPS (Current)", "HPS (Overall)", "Interrupts (Segment 3)"
--------------------------------------------------------------------------------

-- Lookup tables for meter type and session type display names
-- Uses Blizzard's global strings with fallbacks
local METER_TYPE_NAMES = {
    [Enum.DamageMeterType.DamageDone] = DAMAGE_METER_DAMAGE_DONE or "Damage Done",
    [Enum.DamageMeterType.Dps] = DAMAGE_METER_DPS or "DPS",
    [Enum.DamageMeterType.HealingDone] = DAMAGE_METER_HEALING_DONE or "Healing Done",
    [Enum.DamageMeterType.Hps] = DAMAGE_METER_HPS or "HPS",
    [Enum.DamageMeterType.Absorbs] = DAMAGE_METER_ABSORBS or "Absorbs",
    [Enum.DamageMeterType.Interrupts] = DAMAGE_METER_INTERRUPTS or "Interrupts",
    [Enum.DamageMeterType.Dispels] = DAMAGE_METER_DISPELS or "Dispels",
    [Enum.DamageMeterType.DamageTaken] = DAMAGE_METER_DAMAGE_TAKEN or "Damage Taken",
    [Enum.DamageMeterType.AvoidableDamageTaken] = DAMAGE_METER_AVOIDABLE_DAMAGE_TAKEN or "Avoidable Damage",
    [Enum.DamageMeterType.Deaths] = DAMAGE_METER_TYPE_DEATHS or "Deaths",
    [Enum.DamageMeterType.EnemyDamageTaken] = DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN or "Enemy Damage Taken",
}

local SESSION_TYPE_NAMES = {
    [Enum.DamageMeterSessionType.Overall] = "Overall",
    [Enum.DamageMeterSessionType.Current] = "Current",
}

-- Category structure for the meter type context menu (mirrors Blizzard's DAMAGE_METER_CATEGORIES)
local DAMAGE_METER_CATEGORIES = {
    { name = DAMAGE_METER_CATEGORY_DAMAGE or "Damage",
      types = {
          Enum.DamageMeterType.DamageDone,
          Enum.DamageMeterType.Dps,
          Enum.DamageMeterType.DamageTaken,
          Enum.DamageMeterType.AvoidableDamageTaken,
          Enum.DamageMeterType.EnemyDamageTaken,
      }},
    { name = DAMAGE_METER_CATEGORY_HEALING or "Healing",
      types = {
          Enum.DamageMeterType.HealingDone,
          Enum.DamageMeterType.Hps,
      }},
    { name = DAMAGE_METER_CATEGORY_ACTIONS or "Actions",
      types = {
          Enum.DamageMeterType.Interrupts,
          Enum.DamageMeterType.Dispels,
          Enum.DamageMeterType.Deaths,
      }},
}

-- Build enhanced title string combining meter type and session info
local function GetEnhancedTitle(sessionWindow)
    if not sessionWindow then return nil end

    local meterType = sessionWindow.damageMeterType
    local sessionType = sessionWindow.sessionType
    local sessionID = sessionWindow.sessionID

    -- Get meter type name
    local typeName = METER_TYPE_NAMES[meterType] or "Unknown"

    -- Get session name based on type or ID
    local sessionName
    if sessionType then
        sessionName = SESSION_TYPE_NAMES[sessionType] or "Unknown"
    elseif sessionID then
        sessionName = "Segment " .. sessionID
    else
        sessionName = "Unknown"
    end

    return typeName .. " (" .. sessionName .. ")"
end

-- Update a single session window's title with enhanced text
local function UpdateEnhancedTitle(sessionWindow)
    if not sessionWindow then return end

    -- Get the component's db to check setting
    local comp = addon.Components and addon.Components["damageMeter"]
    if not comp or not comp.db or not comp.db.showSessionInTitle then return end

    -- Get the TypeName FontString
    local typeNameFS = sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.TypeName
    if not typeNameFS or not typeNameFS.SetText then return end

    local enhancedTitle = GetEnhancedTitle(sessionWindow)
    if enhancedTitle then
        pcall(typeNameFS.SetText, typeNameFS, enhancedTitle)
    end
end

-- Restore a single session window's title to the original (meter type only)
local function RestoreOriginalTitle(sessionWindow)
    if not sessionWindow then return end

    local typeNameFS = sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.TypeName
    if not typeNameFS or not typeNameFS.SetText then return end

    local meterType = sessionWindow.damageMeterType
    local typeName = METER_TYPE_NAMES[meterType] or ""
    pcall(typeNameFS.SetText, typeNameFS, typeName)
end

-- Refresh all visible window titles (enhanced or original based on setting)
local function RefreshAllWindowTitles()
    if not DamageMeter then return end

    local comp = addon.Components and addon.Components["damageMeter"]
    if not comp or not comp.db then return end

    local showEnhanced = comp.db.showSessionInTitle

    -- Iterate through numbered windows
    for i = 1, 10 do
        local windowName = "DamageMeterSessionWindow" .. i
        local window = _G[windowName]
        if window and window:IsShown() then
            if showEnhanced then
                UpdateEnhancedTitle(window)
            else
                RestoreOriginalTitle(window)
            end
        end
    end

    -- Also check DamageMeter.sessionWindows array
    if DamageMeter.sessionWindows then
        for _, window in ipairs(DamageMeter.sessionWindows) do
            if window and window:IsShown() then
                if showEnhanced then
                    UpdateEnhancedTitle(window)
                else
                    RestoreOriginalTitle(window)
                end
            end
        end
    end
end

-- Hook right-click on title text to open meter type dropdown
local function HookSessionWindowTitleRightClick(sessionWindow)
    if not sessionWindow then return false end
    local state = getWindowState(sessionWindow)
    if state.titleRightClickHooked then return false end

    local dropdown = sessionWindow.DamageMeterTypeDropdown
    local typeNameFS = dropdown and dropdown.TypeName
    if not typeNameFS then return false end

    state.titleRightClickHooked = true

    -- Create invisible overlay button covering the TypeName FontString
    -- Parented to UIParent (not dropdown) to avoid tainting the dropdown frame.
    -- In 12.0.1, dropdown anchors to SessionTimer TOPRIGHT; tainting it causes
    -- Menu.lua secret value errors when SessionTimer triggers layout recalculation.
    local overlay = CreateFrame("Button", nil, UIParent)
    overlay:SetAllPoints(typeNameFS)         -- anchoring TO Blizzard frames is safe
    overlay:SetFrameStrata("MEDIUM")
    local ok, level = pcall(dropdown.GetFrameLevel, dropdown)
    if ok and type(level) == "number" then
        overlay:SetFrameLevel(level + 10)
    end
    overlay:RegisterForClicks("RightButtonUp")  -- Only right-click
    overlay:EnableMouse(false)  -- Disabled by default

    state.titleRightClickOverlay = overlay

    overlay:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" or InCombatLockdown() then return end

        -- Build a Scoot-owned context menu replicating the type-switcher dropdown.
        -- Using MenuUtil.CreateContextMenu with the Scoot overlay (UIParent-parented) as
        -- owner avoids taint: the Blizzard dropdown is an Edit Mode system frame
        -- child whose geometry returns secret values when read from addon context.
        MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
            rootDescription:SetTag("MENU_DAMAGE_METER_WINDOW_TRACKED_TYPE")

            for _, categoryData in ipairs(DAMAGE_METER_CATEGORIES) do
                local categorySubmenu = rootDescription:CreateButton(categoryData.name)

                for _, meterType in ipairs(categoryData.types) do
                    local typeName = METER_TYPE_NAMES[meterType] or tostring(meterType)
                    categorySubmenu:CreateRadio(typeName,
                        function() return sessionWindow.damageMeterType == meterType end,
                        function()
                            local dmOwner = sessionWindow.GetDamageMeterOwner and sessionWindow:GetDamageMeterOwner()
                            if dmOwner and dmOwner.SetSessionWindowDamageMeterType then
                                dmOwner:SetSessionWindowDamageMeterType(sessionWindow, meterType)
                            end
                        end,
                        meterType)
                end
            end
        end)
    end)

    return true
end

-- Enable/disable the right-click overlay based on setting
local function UpdateTitleRightClickState(sessionWindow, enabled)
    local state = sessionWindow and getWindowState(sessionWindow)
    local overlay = state and state.titleRightClickOverlay
    if overlay then
        overlay:EnableMouse(enabled)
        overlay:SetShown(enabled)    -- hide entirely when not needed (UIParent child)
    end
end

--------------------------------------------------------------------------------
-- Entry Styling
--------------------------------------------------------------------------------

-- Apply styling to a single entry via overlay system
-- Zero direct method calls on Blizzard entry or its children — all styling on Scoot-owned frames
local function ApplySingleEntryStyle(entry, db, sessionWindow)
    if not entry or not db then return end

    -- Get/create clip frame for this session window
    local ws = getWindowState(sessionWindow)
    if not ws.clipFrame then
        ws.clipFrame = DMX._CreateClipFrame(sessionWindow)
    end
    if ws.clipFrame then ws.clipFrame:Show() end

    -- Determine parent (clip frame for scroll entries, UIParent for LocalPlayerEntry)
    local isLocalPlayerEntry = (entry == sessionWindow.LocalPlayerEntry)
    local parentFrame = isLocalPlayerEntry and UIParent or ws.clipFrame

    -- Get/create entry overlay
    local elSt = getElementState(entry)
    if not elSt.entryOverlay then
        elSt.entryOverlay = DMX._CreateEntryOverlay(parentFrame)
        DMX._registerDMOverlay(sessionWindow, elSt.entryOverlay)
    end

    local overlay = elSt.entryOverlay
    local classToken = entry.classFilename
    if issecretvalue(classToken) then classToken = nil end
    classToken = classToken or ""

    -- OPT-18: Skip full restyle if entry hasn't changed since last full pass
    if elSt._cacheGen == DMX._dmStyleGeneration and elSt._cacheClass == classToken and classToken ~= "" then
        DMX._HideBlizzardEntryContent(entry)
        DMX._UpdateEntryOverlayData(overlay, entry, db)
        overlay:Show()
        return
    end

    DMX._PopulateEntryOverlay(overlay, entry, db, sessionWindow)

    elSt._cacheGen = DMX._dmStyleGeneration
    elSt._cacheClass = classToken
end

--------------------------------------------------------------------------------
-- Window-Level Styling
--------------------------------------------------------------------------------

-- Apply window-level styling (border, background)
local function ApplyWindowStyling(window, db)
    if not window or not db then return end

    -- Window border
    if db.windowShowBorder then
        -- Apply border using addon border system if available
        if addon and addon.ApplyFrameBorder then
            local borderOpts = {
                style = db.windowBorderStyle or "default",
                color = db.windowBorderColor,
                thickness = db.windowBorderThickness or 1,
            }
            addon.ApplyFrameBorder(window, borderOpts)
        end
    end

    -- Window background
    if db.windowCustomBackdrop and db.windowBackdropTexture then
        -- Apply custom backdrop
        if window.SetBackdrop and addon and addon.ResolveBackdropTexture then
            local texturePath = addon.ResolveBackdropTexture(db.windowBackdropTexture)
            if texturePath then
                local backdrop = {
                    bgFile = texturePath,
                    edgeFile = nil,
                    tile = true,
                    tileSize = 16,
                    edgeSize = 0,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                }
                pcall(window.SetBackdrop, window, backdrop)

                if db.windowBackdropColor and window.SetBackdropColor then
                    local c = db.windowBackdropColor
                    pcall(window.SetBackdropColor, window, c[1] or 0.1, c[2] or 0.1, c[3] or 0.1, c[4] or 0.9)
                end
            end
        end
    end
end

-- Default color for GameFontNormalMed1 (from Blizzard FontStyles.xml)
-- Gold/yellow color used by default for damage meter title text
local TITLE_DEFAULT_COLOR = { 1.0, 0.82, 0, 1 }

-- Apply title/header text styling to a session window
-- Note: Font styling applies to both TypeName and SessionName
-- Color styling only applies to TypeName (SessionName color is controlled by Button Tint)
local function ApplyTitleStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    local titleCfg = rawget(db, "textTitle")

    -- Collect ALL title FontStrings for font styling (font face, size, style)
    local allTitleTargets = {}

    -- DamageMeterTypeDropdown.TypeName (meter type: "Damage Done", "DPS", etc.)
    local typeNameFS = sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.TypeName
    if typeNameFS then
        table.insert(allTitleTargets, typeNameFS)
    end

    -- SessionDropdown.SessionName (session letter in button - font only, color via Button Tint)
    local sessionNameFS = sessionWindow.SessionDropdown and sessionWindow.SessionDropdown.SessionName
    if sessionNameFS then
        table.insert(allTitleTargets, sessionNameFS)
    end

    -- Apply font styling (font face, size, style) to ALL title FontStrings
    if titleCfg then
        for _, fs in ipairs(allTitleTargets) do
            if fs and fs.SetFont then
                if titleCfg.fontFace and addon and addon.ResolveFontFace then
                    local face = addon.ResolveFontFace(titleCfg.fontFace)
                    local baseSize = 12
                    local scale = titleCfg.scaleMultiplier or 1.0
                    local size = baseSize * scale
                    local flags = titleCfg.fontStyle or "OUTLINE"
                    addon.ApplyFontStyle(fs, face, size, flags)
                end
            end
        end

        -- Apply color ONLY to TypeName (SessionName color is controlled by Button Tint)
        if typeNameFS and typeNameFS.SetTextColor then
            local colorMode = titleCfg.colorMode or "default"
            if colorMode == "custom" and titleCfg.color then
                local c = titleCfg.color
                pcall(typeNameFS.SetTextColor, typeNameFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            elseif colorMode == "default" then
                -- Restore Blizzard's default gold color
                pcall(typeNameFS.SetTextColor, typeNameFS, TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4])
            end
        end
    end

    -- Apply enhanced title if enabled (e.g., "DPS (Current)" instead of just "DPS")
    if db.showSessionInTitle then
        UpdateEnhancedTitle(sessionWindow)
    else
        RestoreOriginalTitle(sessionWindow)
    end

    -- Hook and update right-click behavior
    HookSessionWindowTitleRightClick(sessionWindow)
    UpdateTitleRightClickState(sessionWindow, db.titleTextRightClickMeterType or false)
end

-- Default color for SessionTimer (inherits GameFontNormalMed1 - same gold as title)
local TIMER_DEFAULT_COLOR = { 1.0, 0.82, 0, 1 }

-- Apply session timer text styling (the [00:05:23] timer next to the title)
local function ApplyTimerStyling(sessionWindow, db)
    if not sessionWindow or not db then return end
    local timerFS = sessionWindow.SessionTimer
    if not timerFS or not timerFS.SetFont then return end

    local timerCfg = rawget(db, "textTimer")
    if not timerCfg then return end

    -- Font face and style
    if timerCfg.fontFace and addon and addon.ResolveFontFace then
        local face = addon.ResolveFontFace(timerCfg.fontFace)
        local baseSize = 12
        local flags = timerCfg.fontStyle or "OUTLINE"
        addon.ApplyFontStyle(timerFS, face, baseSize, flags)
    end

    -- Color
    local colorMode = timerCfg.colorMode or "default"
    if colorMode == "custom" and timerCfg.color then
        local c = timerCfg.color
        pcall(timerFS.SetTextColor, timerFS, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    elseif colorMode == "default" then
        pcall(timerFS.SetTextColor, timerFS, TIMER_DEFAULT_COLOR[1], TIMER_DEFAULT_COLOR[2], TIMER_DEFAULT_COLOR[3], TIMER_DEFAULT_COLOR[4])
    end
end

--------------------------------------------------------------------------------
-- Button Styling
--------------------------------------------------------------------------------

-- Apply button tint styling to a session window
-- Tint all button visuals consistently:
-- - DamageMeterTypeDropdown.Arrow (the arrow IS the button)
-- - SessionDropdown.Background + Arrow + SessionName (separate background + icons)
-- - SettingsDropdown.Icon (the gear IS the button)
local function ApplyButtonTintStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    -- Check if tint mode is custom; if default, restore original colors
    local tintMode = db.buttonTintMode or "default"

    -- Collect ALL button textures (icons and backgrounds)
    local buttonTextures = {}

    -- DamageMeterTypeDropdown.Arrow (the arrow IS the entire button visual)
    if sessionWindow.DamageMeterTypeDropdown and sessionWindow.DamageMeterTypeDropdown.Arrow then
        table.insert(buttonTextures, sessionWindow.DamageMeterTypeDropdown.Arrow)
    end

    -- SessionDropdown - has separate Background + Arrow + SessionName
    if sessionWindow.SessionDropdown then
        -- Background (the circular button background)
        if sessionWindow.SessionDropdown.Background then
            table.insert(buttonTextures, sessionWindow.SessionDropdown.Background)
        end
        -- Arrow (the small arrow below the letter)
        if sessionWindow.SessionDropdown.Arrow then
            table.insert(buttonTextures, sessionWindow.SessionDropdown.Arrow)
        end
    end

    -- SettingsDropdown.Icon (the gear IS the entire button visual)
    if sessionWindow.SettingsDropdown and sessionWindow.SettingsDropdown.Icon then
        table.insert(buttonTextures, sessionWindow.SettingsDropdown.Icon)
    end

    -- SessionDropdown.SessionName (the C/O letter - uses SetTextColor, not SetVertexColor)
    local sessionNameFS = sessionWindow.SessionDropdown and sessionWindow.SessionDropdown.SessionName

    if tintMode == "custom" then
        local tint = db.buttonTint
        if not tint then return end

        local r = tint.r or tint[1] or 1
        local g = tint.g or tint[2] or 1
        local b = tint.b or tint[3] or 1
        local a = tint.a or tint[4] or 1

        -- Apply tint to all button textures
        -- Desaturate first to convert to grayscale, then SetVertexColor tints uniformly
        for _, tex in ipairs(buttonTextures) do
            if tex then
                if tex.SetDesaturated then
                    pcall(tex.SetDesaturated, tex, true)
                end
                if tex.SetVertexColor then
                    pcall(tex.SetVertexColor, tex, r, g, b, a)
                end
            end
        end

        -- Apply same tint color to SessionName text (SetTextColor - absolute)
        if sessionNameFS and sessionNameFS.SetTextColor then
            pcall(sessionNameFS.SetTextColor, sessionNameFS, r, g, b, a)
        end
    else
        -- Default mode: restore original colors and disable desaturation
        for _, tex in ipairs(buttonTextures) do
            if tex then
                if tex.SetDesaturated then
                    pcall(tex.SetDesaturated, tex, false)
                end
                if tex.SetVertexColor then
                    pcall(tex.SetVertexColor, tex, 1, 1, 1, 1)
                end
            end
        end

        -- Restore SessionName to default gold color
        if sessionNameFS and sessionNameFS.SetTextColor then
            pcall(sessionNameFS.SetTextColor, sessionNameFS, TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4])
        end
    end
end

--------------------------------------------------------------------------------
-- Button Icon Overlays
--------------------------------------------------------------------------------

-- Create a Scoot-owned overlay texture for a button icon
-- Uses SetAtlas with built-in WoW graphics for consistent styling
local function CreateButtonIconOverlay(parent, atlasName, anchorTo, size, yOffset)
    local overlay = parent:CreateTexture(nil, "OVERLAY", nil, 7)

    -- Position at the same location as the anchor, with optional Y offset
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", anchorTo, "CENTER", 0, yOffset or 0)

    -- Set size
    overlay:SetSize(size[1], size[2])

    -- Set the atlas
    overlay:SetAtlas(atlasName, false)  -- false = don't use atlas size, set explicitly above

    getElementState(overlay).isScootOverlay = true
    overlay:Hide()  -- Start hidden
    return overlay
end

-- Get or create button overlays for a session window
-- Only creates overlays for Button 1 (type dropdown arrow) and Button 3 (settings gear)
-- Button 2 just needs its background hidden, no overlay replacement
local function GetOrCreateButtonOverlays(sessionWindow)
    local st = getWindowState(sessionWindow)
    if st.buttonOverlays then
        return st.buttonOverlays
    end

    st.buttonOverlays = {}

    -- Button 1: DamageMeterTypeDropdown.Arrow
    -- Replace the full button with just a simple downward arrow (no background)
    -- Atlas: friendslist-categorybutton-arrow-down (icon-only, no button backdrop)
    local typeDropdown = sessionWindow.DamageMeterTypeDropdown
    if typeDropdown and typeDropdown.Arrow then
        st.buttonOverlays.typeArrow = CreateButtonIconOverlay(
            typeDropdown,
            "friendslist-categorybutton-arrow-down",
            typeDropdown.Arrow,
            { 13, 13 },  -- Small arrow size (10% bigger)
            2            -- Nudge up 2 pixels
        )
    end

    -- Button 3: SettingsDropdown.Icon
    -- Replace the full button with just a gear icon (no background)
    -- Atlas: GM-icon-settings (simple gear icon used in raid frames)
    local settingsDropdown = sessionWindow.SettingsDropdown
    if settingsDropdown and settingsDropdown.Icon then
        st.buttonOverlays.settingsIcon = CreateButtonIconOverlay(
            settingsDropdown,
            "GM-icon-settings",
            settingsDropdown.Icon,
            { 25, 25 },  -- Gear icon size (25% bigger than before)
            3            -- Nudge up 3 pixels
        )
    end

    return st.buttonOverlays
end

-- Apply button icon overlay styling
-- When enabled:
--   Button 1: Hide Blizzard arrow, show the overlay arrow
--   Button 2: Just hide the background (keep letter visible)
--   Button 3: Hide Blizzard gear, show the overlay gear
-- When disabled:
--   Restore all Blizzard visuals
local function ApplyButtonIconOverlays(sessionWindow, db)
    if not sessionWindow or not db then return end

    local overlaysEnabled = db.buttonIconOverlaysEnabled
    local overlays = GetOrCreateButtonOverlays(sessionWindow)

    -- Get tint settings (used for overlays when enabled)
    local tintMode = db.buttonTintMode or "default"
    local r, g, b, a = 1, 1, 1, 1

    if tintMode == "custom" and db.buttonTint then
        local c = db.buttonTint
        r = c.r or c[1] or 1
        g = c.g or c[2] or 1
        b = c.b or c[3] or 1
        a = c.a or c[4] or 1
    end

    if overlaysEnabled then
        -- === Button 1: DamageMeterTypeDropdown ===
        -- Hide Blizzard's arrow, show the overlay
        local typeDropdown = sessionWindow.DamageMeterTypeDropdown
        if typeDropdown and typeDropdown.Arrow then
            pcall(typeDropdown.Arrow.SetAlpha, typeDropdown.Arrow, 0)

            local overlay = overlays.typeArrow
            if overlay then
                overlay:Show()
                -- Always desaturate the arrow to make it solid color
                pcall(overlay.SetDesaturated, overlay, true)
                if tintMode == "custom" then
                    pcall(overlay.SetVertexColor, overlay, r, g, b, a)
                else
                    -- Default: use white for solid appearance
                    pcall(overlay.SetVertexColor, overlay, 1, 1, 1, 1)
                end
            end
        end

        -- === Button 2: SessionDropdown ===
        -- Just hide the background, keep the letter/arrow visible
        local sessionDropdown = sessionWindow.SessionDropdown
        if sessionDropdown and sessionDropdown.Background then
            pcall(sessionDropdown.Background.SetAlpha, sessionDropdown.Background, 0)
        end

        -- === Button 3: SettingsDropdown ===
        -- Hide Blizzard's gear icon, show the overlay
        local settingsDropdown = sessionWindow.SettingsDropdown
        if settingsDropdown and settingsDropdown.Icon then
            pcall(settingsDropdown.Icon.SetAlpha, settingsDropdown.Icon, 0)

            local overlay = overlays.settingsIcon
            if overlay then
                overlay:Show()
                -- Always desaturate the gear to make it solid color
                pcall(overlay.SetDesaturated, overlay, true)
                if tintMode == "custom" then
                    pcall(overlay.SetVertexColor, overlay, r, g, b, a)
                else
                    -- Default: use white for solid appearance
                    pcall(overlay.SetVertexColor, overlay, 1, 1, 1, 1)
                end
            end
        end

        return true  -- Signal that button styling was handled
    else
        -- === Restore all Blizzard visuals ===

        -- Button 1: Restore arrow
        local typeDropdown = sessionWindow.DamageMeterTypeDropdown
        if typeDropdown and typeDropdown.Arrow then
            pcall(typeDropdown.Arrow.SetAlpha, typeDropdown.Arrow, 1)
        end
        if overlays.typeArrow then
            overlays.typeArrow:Hide()
        end

        -- Button 2: Restore background
        local sessionDropdown = sessionWindow.SessionDropdown
        if sessionDropdown and sessionDropdown.Background then
            pcall(sessionDropdown.Background.SetAlpha, sessionDropdown.Background, 1)
        end

        -- Button 3: Restore gear icon
        local settingsDropdown = sessionWindow.SettingsDropdown
        if settingsDropdown and settingsDropdown.Icon then
            pcall(settingsDropdown.Icon.SetAlpha, settingsDropdown.Icon, 1)
        end
        if overlays.settingsIcon then
            overlays.settingsIcon:Hide()
        end

        return false  -- Signal that ApplyButtonTintStyling should handle it
    end
end

--------------------------------------------------------------------------------
-- Header Backdrop Styling
--------------------------------------------------------------------------------

-- Apply header backdrop styling to a session window
local function ApplyHeaderBackdropStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    local header = sessionWindow.Header
    if not header then return end

    -- Show/hide control
    local show = db.headerBackdropShow
    if show == false then
        SafeSetShown(header, false)
        return
    else
        SafeSetShown(header, true)
    end

    -- Apply tint color
    local tint = db.headerBackdropTint
    if tint and header.SetVertexColor then
        local r = tint.r or tint[1] or 1
        local g = tint.g or tint[2] or 1
        local b = tint.b or tint[3] or 1
        local a = tint.a or tint[4] or 1
        pcall(header.SetVertexColor, header, r, g, b, a)
    end
end

--------------------------------------------------------------------------------
-- Bulk Styling Operations
--------------------------------------------------------------------------------

-- OPT-18: Bump generation and restyle all visible entries in one pass.
local function styleAllVisibleEntries(sessionWindow, db)
    DMX._dmStyleGeneration = DMX._dmStyleGeneration + 1
    DMX._ForEachVisibleEntry(sessionWindow, function(entryFrame)
        ApplySingleEntryStyle(entryFrame, db, sessionWindow)
    end)
end

-- Update all visible overlay data across all windows (combat-safe: bar fill + text only)
local function UpdateAllOverlayData(comp)
    if not comp or not comp.db then return end
    -- Zero-Touch: if still on proxy DB, do nothing (no config = no overlays)
    if comp._ScootDBProxy and comp.db == comp._ScootDBProxy then return end
    local dmFrame = _G.DamageMeter
    if not dmFrame or not dmFrame:IsShown() then
        DMX._hideAllDMOverlays()
        return
    end
    local windows = DMX._GetAllSessionWindows()
    for _, sessionWindow in ipairs(windows) do
        DMX._ForEachVisibleEntry(sessionWindow, function(entryFrame)
            local elSt = elementState[entryFrame]
            if elSt and elSt.entryOverlay and elSt.entryOverlay:IsShown() then
                DMX._UpdateEntryOverlayData(elSt.entryOverlay, entryFrame, comp.db)
            else
                -- Entry needs overlay (new post-reset entry, or overlay hidden by reset cleanup)
                ApplySingleEntryStyle(entryFrame, comp.db, sessionWindow)
            end
        end)
        -- Also update LocalPlayerEntry overlay
        local lpe = sessionWindow.LocalPlayerEntry
        if lpe then
            local ok, shown = pcall(lpe.IsShown, lpe)
            if ok and shown then
                local elSt = elementState[lpe]
                if elSt and elSt.entryOverlay and elSt.entryOverlay:IsShown() then
                    DMX._UpdateEntryOverlayData(elSt.entryOverlay, lpe, comp.db)
                else
                    ApplySingleEntryStyle(lpe, comp.db, sessionWindow)
                end
            else
                -- LocalPlayerEntry hidden: hide overlay and restore Blizzard content
                local elSt = elementState[lpe]
                if elSt and elSt.entryOverlay then
                    elSt.entryOverlay:Hide()
                    DMX._RestoreBlizzardEntryContent(lpe)
                end
            end
        end
    end
end

-- Lightweight per-tick refresh: sync entry overlays + LPE without full window restyle.
-- OPT-18 cache prevents redundant full populates — cache hits do data-only updates.
-- Does NOT bump dmStyleGeneration (full restyle via ApplyStyling handles that on events).
local function RefreshVisibleOverlays(comp)
    if not comp or not comp.db then return end
    if comp._ScootDBProxy and comp.db == comp._ScootDBProxy then return end
    local dmFrame = _G.DamageMeter
    if not dmFrame or not dmFrame:IsShown() then return end

    local db = comp.db
    local windows = DMX._GetAllSessionWindows()
    for _, sessionWindow in ipairs(windows) do
        -- Refresh all visible scroll entries
        DMX._ForEachVisibleEntry(sessionWindow, function(entryFrame)
            ApplySingleEntryStyle(entryFrame, db, sessionWindow)
        end)

        -- Refresh LocalPlayerEntry
        local lpe = sessionWindow.LocalPlayerEntry
        if lpe then
            local ok, shown = pcall(lpe.IsShown, lpe)
            if ok and shown then
                ApplySingleEntryStyle(lpe, db, sessionWindow)
            else
                local elSt = elementState[lpe]
                if elSt and elSt.entryOverlay then
                    elSt.entryOverlay:Hide()
                    DMX._RestoreBlizzardEntryContent(lpe)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Main Orchestrator
--------------------------------------------------------------------------------

-- Main styling function
local function ApplyDamageMeterStyling(self)
    DMX._InvalidateSessionWindowCache()

    -- If Y is active, X becomes a no-op
    if addon.IsModuleEnabled and addon:IsModuleEnabled("damageMeter", "damageMeterV2") then
        if addon.DamageMetersY and addon.DamageMetersY._initialized then
            DMX._hideAllDMOverlays()
            return
        end
    end

    local dmFrame = _G.DamageMeter
    if not dmFrame then
        DMX._hideAllDMOverlays()
        return
    end

    -- Frame exists but is hidden (CVar disabled, etc.) — clean up overlays
    if not dmFrame:IsShown() then
        DMX._hideAllDMOverlays()
        return
    end

    -- Zero-Touch: if still on proxy DB, do nothing
    if self._ScootDBProxy and self.db == self._ScootDBProxy then
        DMX._hideAllDMOverlays()
        return
    end

    local db = self.db
    if type(db) ~= "table" then
        DMX._hideAllDMOverlays()
        return
    end

    local windows = DMX._GetAllSessionWindows()

    -- Combat-safe: defer window-level styling during combat
    -- No cleanup here: meters still visible, just can't restyle
    if PlayerInCombat() then
        return
    end

    -- Style all session windows and their entries
    for _, sessionWindow in ipairs(windows) do
        knownSessionWindows[sessionWindow] = true  -- track for cleanup

        -- Reset this window's UIParent-parented overlays before re-styling visible entries
        DMX._hideWindowOverlays(sessionWindow)

        -- Apply window styling
        ApplyWindowStyling(sessionWindow, db)

        -- Apply title bar styling (title text, buttons, backdrop)
        ApplyTitleStyling(sessionWindow, db)
        ApplyTimerStyling(sessionWindow, db)

        -- Apply button icon overlays (if enabled) - must come before button tint
        local overlaysHandledButtons = ApplyButtonIconOverlays(sessionWindow, db)

        -- Apply button tint styling (only affects Blizzard textures when overlays disabled)
        -- When overlays enabled, this only affects SessionName text color
        if not overlaysHandledButtons then
            ApplyButtonTintStyling(sessionWindow, db)
        else
            -- When overlays are enabled, still need to tint SessionName text
            local tintMode = db.buttonTintMode or "default"
            local sessionNameFS = sessionWindow.SessionDropdown and sessionWindow.SessionDropdown.SessionName
            if sessionNameFS and sessionNameFS.SetTextColor then
                if tintMode == "custom" and db.buttonTint then
                    local c = db.buttonTint
                    local r = c.r or c[1] or 1
                    local g = c.g or c[2] or 1
                    local b = c.b or c[3] or 1
                    local a = c.a or c[4] or 1
                    pcall(sessionNameFS.SetTextColor, sessionNameFS, r, g, b, a)
                else
                    pcall(sessionNameFS.SetTextColor, sessionNameFS, TITLE_DEFAULT_COLOR[1], TITLE_DEFAULT_COLOR[2], TITLE_DEFAULT_COLOR[3], TITLE_DEFAULT_COLOR[4])
                end
            end
        end

        ApplyHeaderBackdropStyling(sessionWindow, db)

        -- Apply export button styling (late-binding: DMX._ApplyExportButtonStyling set by export.lua)
        DMX._ApplyExportButtonStyling(sessionWindow, db)

        -- OPT-18: Bump generation and style all visible entries in this window
        styleAllVisibleEntries(sessionWindow, db)

        -- Style LocalPlayerEntry (sticky player row at bottom when scrolled past own position)
        -- This entry is a sibling of ScrollBox, not a child, so ForEachVisibleEntry misses it
        -- Guard with visibility check: after data clear, entry still exists but is hidden;
        -- ApplySingleEntryStyle calls overlay:Show(), which would leave a stuck overlay
        local localPlayerEntry = sessionWindow.LocalPlayerEntry
        if localPlayerEntry then
            local ok, shown = pcall(localPlayerEntry.IsShown, localPlayerEntry)
            if ok and shown then
                ApplySingleEntryStyle(localPlayerEntry, db, sessionWindow)
            else
                -- Entry hidden/gone — hide its overlay if it exists
                local elSt = elementState[localPlayerEntry]
                if elSt and elSt.entryOverlay then
                    elSt.entryOverlay:Hide()
                end
            end
        end
    end

    -- Apply state-based opacity (OOC fade)
    DMX._RefreshDamageMeterOpacity(self)
end

--------------------------------------------------------------------------------
-- Namespace Promotion
--------------------------------------------------------------------------------

DMX._ApplyDamageMeterStyling = ApplyDamageMeterStyling
DMX._UpdateAllOverlayData = UpdateAllOverlayData
DMX._RefreshVisibleOverlays = RefreshVisibleOverlays
DMX._RefreshAllWindowTitles = RefreshAllWindowTitles
