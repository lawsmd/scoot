local addonName, addon = ...

-- damagemetersX/export.lua — Export data gathering, export menu UI,
-- chat export, export button creation/styling.

local DMX = addon.DamageMetersX

-- Local aliases for frequently used namespace functions
local PlayerInCombat = DMX._PlayerInCombat
local SafeSetShown = DMX._SafeSetShown
local getWindowState = DMX._getWindowState

-- The export data path (addon.GatherDamageMeterExportData,
-- addon.FormatPlayerSpecInfo and the zone an export names) is
-- core/components/damagemetersY/export.lua, read here at click time.

--------------------------------------------------------------------------------
-- Export Menu State
--------------------------------------------------------------------------------

-- Active export menu (only one open at a time)
local activeExportMenu = nil

local function CloseExportMenu()
    if activeExportMenu then
        activeExportMenu:Hide()
        activeExportMenu = nil
    end
end

--------------------------------------------------------------------------------
-- Chat Export
--------------------------------------------------------------------------------

-- Validate and return available chat channels
local function GetAvailableChatChannels()
    local channels = {}
    -- SAY always available
    table.insert(channels, { key = "SAY", label = "Say" })
    -- PARTY when in group but not raid
    if IsInGroup() and not IsInRaid() then
        table.insert(channels, { key = "PARTY", label = "Party" })
    end
    -- RAID when in raid
    if IsInRaid() then
        table.insert(channels, { key = "RAID", label = "Raid" })
    end
    -- INSTANCE_CHAT when in instance group
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        table.insert(channels, { key = "INSTANCE_CHAT", label = "Instance" })
    end
    -- GUILD when in guild
    if IsInGuild() then
        table.insert(channels, { key = "GUILD", label = "Guild" })
    end
    return channels
end

local function IsChannelAvailable(channel)
    if channel == "SAY" then return true end
    if channel == "PARTY" then return IsInGroup() and not IsInRaid() end
    if channel == "RAID" then return IsInRaid() end
    if channel == "INSTANCE_CHAT" then return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
    if channel == "GUILD" then return IsInGuild() end
    return false
end

-- Send damage meter data to chat with throttle
local function SendExportToChat(sessionWindow)
    if PlayerInCombat() then
        if addon.Print then addon:Print("Export not available during combat.") end
        return
    end

    local comp = addon.Components and addon.Components["damageMeter"]
    if not comp or not comp.db then return end
    local db = comp.db

    local channel = db.exportChatChannel or "PARTY"
    local lineCount = db.exportChatLineCount or 5

    -- Validate channel
    if not IsChannelAvailable(channel) then
        -- Fall back to SAY
        channel = "SAY"
    end

    -- Get data from the originating window
    local sessionType = sessionWindow.sessionType or Enum.DamageMeterSessionType.Overall
    local primaryMeterType = sessionWindow.damageMeterType or Enum.DamageMeterType.Dps

    local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
    if not data then
        if addon.Print then addon:Print(err or "No export data available.") end
        return
    end

    -- Build messages
    local messages = {}
    -- Header
    local headerName = data.columnNames[1] or "DPS"
    table.insert(messages, string.format("Scoot - %s (%s) [%s]:", headerName, data.sessionLabel, data.FormatDuration(data.duration)))

    -- Player lines (limited by lineCount)
    local count = math.min(lineCount, #data.playerOrder)
    for i = 1, count do
        local guid = data.playerOrder[i]
        local p = data.players[guid]
        local mt = data.columns[1]
        local val = data.GetDisplayValue(guid, mt)
        local info = addon.FormatPlayerSpecInfo(p)
        local nameStr = info and (p.name .. " " .. info) or p.name
        table.insert(messages, string.format("#%d. %s - %s", i, nameStr, val))
    end

    -- Send all messages synchronously to preserve secure execution context
    -- (C_Timer.After breaks the hardware-event chain, causing ADDON_ACTION_BLOCKED)
    for _, msg in ipairs(messages) do
        SendChatMessage(msg, channel)
    end
end

--------------------------------------------------------------------------------
-- Export Menu UI
--------------------------------------------------------------------------------

-- Create the flyout menu for an export button
local function CreateExportMenu(exportBtn, sessionWindow)
    local st = getWindowState(sessionWindow)
    if st.exportMenu then return st.exportMenu end

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetSize(200, 210)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)

    -- Dark background
    local bg = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.95)

    -- Thin border
    addon.Borders.ApplySquare(menu, {
        size = 1,
        color = { 0.3, 0.3, 0.35, 0.8 },
        layer = "BORDER",
        skipDimensionCheck = true,
    })

    local yOff = -8
    local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

    -- "Export to Window" row
    local windowBtn = CreateFrame("Button", nil, menu)
    windowBtn:SetSize(184, 24)
    windowBtn:SetPoint("TOP", menu, "TOP", 0, yOff)
    windowBtn:EnableMouse(true)
    windowBtn:RegisterForClicks("AnyUp")

    local windowBtnBg = windowBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    windowBtnBg:SetAllPoints()
    windowBtnBg:SetColorTexture(1, 1, 1, 0)

    local windowBtnText = windowBtn:CreateFontString(nil, "OVERLAY")
    windowBtnText:SetFont(defaultFont, 11, "")
    windowBtnText:SetPoint("LEFT", 8, 0)
    windowBtnText:SetText("Export to Window")
    windowBtnText:SetTextColor(1, 1, 1, 0.9)

    windowBtn:SetScript("OnEnter", function() windowBtnBg:SetColorTexture(1, 1, 1, 0.08) end)
    windowBtn:SetScript("OnLeave", function() windowBtnBg:SetColorTexture(1, 1, 1, 0) end)
    windowBtn:SetScript("OnClick", function()
        CloseExportMenu()
        if PlayerInCombat() then
            if addon.Print then addon:Print("Export not available during combat.") end
            return
        end
        local sessionType = sessionWindow.sessionType or Enum.DamageMeterSessionType.Overall
        local primaryMeterType = sessionWindow.damageMeterType or Enum.DamageMeterType.Dps
        local data, err = addon.GatherDamageMeterExportData(sessionType, primaryMeterType)
        if not data then
            if addon.Print then addon:Print(err or "No export data available.") end
            return
        end
        if addon.ShowHighScoreWindow then
            addon.ShowHighScoreWindow(data)
        end
    end)

    yOff = yOff - 28

    -- Divider
    local divider = menu:CreateTexture(nil, "ARTWORK")
    divider:SetSize(180, 1)
    divider:SetPoint("TOP", menu, "TOP", 0, yOff)
    divider:SetColorTexture(0.3, 0.3, 0.35, 0.5)

    yOff = yOff - 8

    -- "Export to Chat" label
    local chatLabel = menu:CreateFontString(nil, "OVERLAY")
    chatLabel:SetFont(defaultFont, 11, "")
    chatLabel:SetPoint("TOPLEFT", menu, "TOPLEFT", 16, yOff)
    chatLabel:SetText("Export to Chat")
    chatLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    yOff = yOff - 20

    -- Channel dropdown button
    local channelBtn = CreateFrame("Button", nil, menu)
    channelBtn:SetSize(168, 22)
    channelBtn:SetPoint("TOP", menu, "TOP", 0, yOff)
    channelBtn:EnableMouse(true)
    channelBtn:RegisterForClicks("AnyUp")

    local channelBg = channelBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    channelBg:SetAllPoints()
    channelBg:SetColorTexture(0.1, 0.1, 0.12, 1)

    local channelText = channelBtn:CreateFontString(nil, "OVERLAY")
    channelText:SetFont(defaultFont, 10, "")
    channelText:SetPoint("LEFT", 8, 0)
    channelText:SetTextColor(1, 1, 1, 0.9)

    local channelArrow = channelBtn:CreateFontString(nil, "OVERLAY")
    channelArrow:SetFont(defaultFont, 10, "")
    channelArrow:SetPoint("RIGHT", -8, 0)
    channelArrow:SetText("v")
    channelArrow:SetTextColor(0.6, 0.6, 0.6, 1)

    -- Channel label names
    local channelLabels = {
        SAY = "Say", PARTY = "Party", RAID = "Raid",
        INSTANCE_CHAT = "Instance", GUILD = "Guild",
    }

    local function UpdateChannelText()
        local comp = addon.Components and addon.Components["damageMeter"]
        local ch = comp and comp.db and comp.db.exportChatChannel or "PARTY"
        channelText:SetText("Channel: " .. (channelLabels[ch] or ch))
    end

    channelBtn:SetScript("OnEnter", function() channelBg:SetColorTexture(0.15, 0.15, 0.18, 1) end)
    channelBtn:SetScript("OnLeave", function() channelBg:SetColorTexture(0.1, 0.1, 0.12, 1) end)
    channelBtn:SetScript("OnClick", function()
        -- Toggle: if submenu exists and shown, hide it; otherwise create/show
        if channelBtn._submenu and channelBtn._submenu:IsShown() then
            channelBtn._submenu:Hide()
            return
        end

        -- Create submenu once (lazy)
        if not channelBtn._submenu then
            local sub = CreateFrame("Frame", nil, menu)  -- child of menu for parent-chain walk
            sub:SetSize(168, 5 * 20 + 8)  -- 5 channels x 20px + padding
            sub:SetFrameStrata("FULLSCREEN_DIALOG")
            sub:SetFrameLevel(210)  -- above menu (200)
            sub:EnableMouse(true)

            -- Dark background
            local subBg = sub:CreateTexture(nil, "BACKGROUND", nil, -8)
            subBg:SetAllPoints()
            subBg:SetColorTexture(0.08, 0.08, 0.10, 0.98)

            -- Thin border (same style as parent menu)
            addon.Borders.ApplySquare(sub, {
                size = 1,
                color = { 0.3, 0.3, 0.35, 0.8 },
                layer = "BORDER",
                skipDimensionCheck = true,
            })

            local allChannels = {
                { key = "SAY", label = "Say" },
                { key = "PARTY", label = "Party" },
                { key = "RAID", label = "Raid" },
                { key = "INSTANCE_CHAT", label = "Instance" },
                { key = "GUILD", label = "Guild" },
            }
            sub._rows = {}

            for idx, ch in ipairs(allChannels) do
                local row = CreateFrame("Button", nil, sub)
                row:SetSize(160, 20)
                row:SetPoint("TOPLEFT", sub, "TOPLEFT", 4, -(4 + (idx - 1) * 20))
                row:EnableMouse(true)
                row:RegisterForClicks("AnyUp")

                local rowBg = row:CreateTexture(nil, "BACKGROUND", nil, -6)
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(1, 1, 1, 0)

                local rowText = row:CreateFontString(nil, "OVERLAY")
                rowText:SetFont(defaultFont, 10, "")
                rowText:SetPoint("LEFT", 6, 0)
                rowText:SetText(ch.label)

                -- Checkmark for selected channel
                local check = row:CreateFontString(nil, "OVERLAY")
                check:SetFont(defaultFont, 10, "")
                check:SetPoint("RIGHT", -6, 0)
                check:SetText("")

                row._key = ch.key
                row._text = rowText
                row._check = check
                row._bg = rowBg

                row:SetScript("OnEnter", function()
                    if row._available then
                        rowBg:SetColorTexture(1, 1, 1, 0.08)
                    end
                end)
                row:SetScript("OnLeave", function()
                    rowBg:SetColorTexture(1, 1, 1, 0)
                end)
                row:SetScript("OnClick", function()
                    if not row._available then return end
                    local comp = addon.Components and addon.Components["damageMeter"]
                    if comp and comp.db then
                        comp.db.exportChatChannel = ch.key
                    end
                    UpdateChannelText()
                    sub:Hide()
                end)

                sub._rows[idx] = row
            end

            -- Refresh function: update availability + checkmark
            function sub:Refresh()
                local avail = {}
                for _, c in ipairs(GetAvailableChatChannels()) do
                    avail[c.key] = true
                end
                local comp = addon.Components and addon.Components["damageMeter"]
                local current = comp and comp.db and comp.db.exportChatChannel or "PARTY"
                local ar, ag, ab = addon.GetAccentColorRGB()
                for _, row in ipairs(self._rows) do
                    local isAvail = avail[row._key] or false
                    row._available = isAvail
                    row._text:SetTextColor(1, 1, 1, isAvail and 0.9 or 0.3)
                    row._check:SetText(row._key == current and ">" or "")
                    row._check:SetTextColor(ar, ag, ab, 1)
                end
            end

            channelBtn._submenu = sub
        end

        -- Position and show
        channelBtn._submenu:ClearAllPoints()
        channelBtn._submenu:SetPoint("TOPLEFT", channelBtn, "BOTTOMLEFT", 0, -2)
        channelBtn._submenu:Refresh()
        channelBtn._submenu:Show()
    end)

    yOff = yOff - 28

    -- Lines slider
    local sliderLabel = menu:CreateFontString(nil, "OVERLAY")
    sliderLabel:SetFont(defaultFont, 10, "")
    sliderLabel:SetPoint("TOPLEFT", menu, "TOPLEFT", 16, yOff)
    sliderLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    local function UpdateSliderLabel()
        local comp = addon.Components and addon.Components["damageMeter"]
        local count = comp and comp.db and comp.db.exportChatLineCount or 5
        sliderLabel:SetText("Lines: " .. count)
    end

    yOff = yOff - 16

    local slider = CreateFrame("Slider", nil, menu, "OptionsSliderTemplate")
    slider:SetSize(168, 14)
    slider:SetPoint("TOP", menu, "TOP", 0, yOff)
    slider:SetMinMaxValues(1, 20)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    -- Hide default text elements
    if slider.Text then slider.Text:SetText("") end
    if slider.Low then slider.Low:SetText("") end
    if slider.High then slider.High:SetText("") end

    slider:SetScript("OnValueChanged", function(self, value)
        local comp = addon.Components and addon.Components["damageMeter"]
        if comp and comp.db then
            comp.db.exportChatLineCount = math.floor(value)
        end
        UpdateSliderLabel()
    end)

    yOff = yOff - 24

    -- Send button
    local sendBtn = CreateFrame("Button", nil, menu)
    sendBtn:SetSize(168, 24)
    sendBtn:SetPoint("TOP", menu, "TOP", 0, yOff)
    sendBtn:EnableMouse(true)
    sendBtn:RegisterForClicks("AnyUp")

    local sendBg = sendBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
    sendBg:SetAllPoints()
    sendBg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local sendText = sendBtn:CreateFontString(nil, "OVERLAY")
    sendText:SetFont(defaultFont, 11, "")
    sendText:SetPoint("CENTER")
    sendText:SetText("Send to Chat")
    sendText:SetTextColor(1, 1, 1, 0.9)

    sendBtn:SetScript("OnEnter", function() sendBg:SetColorTexture(0.2, 0.2, 0.24, 1) end)
    sendBtn:SetScript("OnLeave", function() sendBg:SetColorTexture(0.15, 0.15, 0.18, 1) end)
    sendBtn:SetScript("OnClick", function()
        CloseExportMenu()
        SendExportToChat(sessionWindow)
    end)

    -- Events live only while the menu is shown; handles armed in OnShow,
    -- released in OnHide.
    local menuEventHandles = nil

    local function onMenuEvent(event)
        if event == "PLAYER_REGEN_DISABLED" then
            CloseExportMenu()
        elseif event == "GLOBAL_MOUSE_DOWN" then
            C_Timer.After(0.05, function()
                if not menu:IsShown() then return end
                local foci = GetMouseFoci()
                local focus = foci and foci[1]
                if not focus then return end
                if focus == exportBtn then return end
                -- Walk parent chain: if focus is menu or any child of menu, stay open
                local f = focus
                while f do
                    if f == menu then return end
                    f = f:GetParent()
                end
                CloseExportMenu()
            end)
        end
    end

    -- Menu show/hide logic
    menu:SetScript("OnShow", function()
        UpdateChannelText()
        UpdateSliderLabel()
        local comp = addon.Components and addon.Components["damageMeter"]
        local count = comp and comp.db and comp.db.exportChatLineCount or 5
        slider:SetValue(count)

        -- Close on click-away via GLOBAL_MOUSE_DOWN
        menuEventHandles = {
            addon.Events.On("DamageMetersX:Export", "GLOBAL_MOUSE_DOWN", onMenuEvent),
            addon.Events.On("DamageMetersX:Export", "PLAYER_REGEN_DISABLED", onMenuEvent),
        }
    end)

    menu:SetScript("OnHide", function(self)
        if menuEventHandles then
            for _, handle in ipairs(menuEventHandles) do
                handle:Off()
            end
            menuEventHandles = nil
        end
        if activeExportMenu == self then
            activeExportMenu = nil
        end
    end)

    menu:Hide()
    st.exportMenu = menu
    return menu
end

--------------------------------------------------------------------------------
-- Export Button
--------------------------------------------------------------------------------

-- Create or retrieve the export button for a session window
local function GetOrCreateExportButton(sessionWindow)
    local st = getWindowState(sessionWindow)
    if st.exportButton then return st.exportButton end

    local sessionDropdown = sessionWindow.SessionDropdown
    if not sessionDropdown then return nil end

    -- Create UIParent-parented button (avoids taint)
    local btn = CreateFrame("Button", nil, UIParent)
    btn:SetSize(36, 36)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(100)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")

    -- Backdrop circle (copy atlas from SessionDropdown.Background)
    local backdrop = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    backdrop:SetSize(36, 36)
    backdrop:SetPoint("CENTER")
    if sessionDropdown.Background then
        local atlas = sessionDropdown.Background:GetAtlas()
        if atlas then
            backdrop:SetAtlas(atlas, false)
        else
            local tex = sessionDropdown.Background:GetTexture()
            if tex then
                backdrop:SetTexture(tex)
            end
        end
    end
    btn._backdrop = backdrop

    -- Horn icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(27, 27)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetAtlas("UI-EventPoi-Horn-big", false)
    btn._icon = icon

    -- Custom icon overlay (for overlay mode)
    local overlayIcon = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    overlayIcon:SetSize(27, 27)
    overlayIcon:SetPoint("CENTER", 0, 1)
    overlayIcon:SetAtlas("UI-EventPoi-Horn-big", false)
    overlayIcon:Hide()
    btn._overlayIcon = overlayIcon

    -- Click handler: toggle flyout
    btn:SetScript("OnClick", function(self)
        if PlayerInCombat() then
            if addon.Print then addon:Print("Export not available during combat.") end
            return
        end
        local menu = CreateExportMenu(self, sessionWindow)
        if menu:IsShown() then
            CloseExportMenu()
        else
            CloseExportMenu() -- Close any other open menu
            menu:ClearAllPoints()
            menu:SetPoint("BOTTOM", self, "TOP", 0, 4)
            menu:Show()
            activeExportMenu = menu
        end
    end)

    btn:Hide() -- Start hidden; shown by ApplyExportButtonStyling
    st.exportButton = btn
    return btn
end

-- Position and style the export button
local function ApplyExportButtonStyling(sessionWindow, db)
    if not sessionWindow or not db then return end

    local enabled = db.exportEnabled
    local st = getWindowState(sessionWindow)

    if not enabled then
        -- Hide export button + menu if they exist
        if st.exportButton then st.exportButton:Hide() end
        if st.exportMenu then st.exportMenu:Hide() end
        return
    end

    if PlayerInCombat() then
        -- Hide during combat
        if st.exportButton then st.exportButton:Hide() end
        if st.exportMenu then st.exportMenu:Hide() end
        return
    end

    local btn = GetOrCreateExportButton(sessionWindow)
    if not btn then return end

    -- Position: anchor RIGHT of export button to LEFT of SessionDropdown with offset
    local sessionDropdown = sessionWindow.SessionDropdown
    if sessionDropdown then
        local xOffset = db.exportButtonXOffset or 0
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", sessionDropdown, "LEFT", -6 + xOffset, 0)
    end

    -- Determine styling mode
    local overlaysEnabled = db.buttonIconOverlaysEnabled
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
        -- Custom icons mode: no backdrop, show overlay icon desaturated + tinted
        btn._backdrop:Hide()
        btn._icon:Hide()
        btn._overlayIcon:Show()
        pcall(btn._overlayIcon.SetDesaturated, btn._overlayIcon, true)
        if tintMode == "custom" then
            pcall(btn._overlayIcon.SetVertexColor, btn._overlayIcon, r, g, b, a)
        else
            pcall(btn._overlayIcon.SetVertexColor, btn._overlayIcon, 1, 1, 1, 1)
        end
    else
        -- Default mode: show backdrop + icon with tint
        btn._backdrop:Show()
        btn._icon:Show()
        btn._overlayIcon:Hide()
        if tintMode == "custom" then
            pcall(btn._backdrop.SetDesaturated, btn._backdrop, true)
            pcall(btn._backdrop.SetVertexColor, btn._backdrop, r, g, b, a)
            pcall(btn._icon.SetDesaturated, btn._icon, true)
            pcall(btn._icon.SetVertexColor, btn._icon, r, g, b, a)
        else
            pcall(btn._backdrop.SetDesaturated, btn._backdrop, false)
            pcall(btn._backdrop.SetVertexColor, btn._backdrop, 1, 1, 1, 1)
            -- Default horn icon: goldish-yellow tint
            pcall(btn._icon.SetDesaturated, btn._icon, false)
            pcall(btn._icon.SetVertexColor, btn._icon, 1, 0.82, 0, 1)
        end
    end

    btn:Show()
end

--------------------------------------------------------------------------------
-- Namespace Promotion
--------------------------------------------------------------------------------

DMX._ApplyExportButtonStyling = ApplyExportButtonStyling
