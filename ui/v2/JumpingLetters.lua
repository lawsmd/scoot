-- JumpingLetters.lua - Animated "Features" text for new users (all modules off)
local addonName, addon = ...

local Navigation = addon.UI.Navigation
local Theme = addon.UI.Theme

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local JUMP_HEIGHT = 5          -- pixels each letter jumps up
local JUMP_DURATION = 0.12     -- seconds for one direction (up or down)
local CHAR_STAGGER = 0.08      -- delay between each letter's jump start
local CYCLE_PAUSE = 1.5        -- seconds between animation cycles
local LABEL_TEXT = "Features"
local LABEL_SIZE = 12
local LABEL_LEFT_OFFSET = 8    -- matches CreateParentRow label positioning

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local jumpRow          -- the row frame being animated
local jumpContainer    -- parent frame holding all char frames
local charFrames = {}  -- per-character frames
local charFontStrings = {}  -- per-character FontStrings
local charAnimGroups = {}   -- per-character AnimationGroups (nil for space)
local lastAnimGroup    -- the final non-space character's anim group (for cycle timing)
local replayTimer      -- C_Timer handle for cycle pause
local isActive = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function MeasureCharWidth(row)
    local font = Theme:GetFont("LABEL")
    if not font then return 0 end
    local tmp = row:CreateFontString(nil, "OVERLAY")
    pcall(tmp.SetFont, tmp, font, LABEL_SIZE, "")
    tmp:SetText("W")
    local w = tmp:GetStringWidth() or 0
    tmp:Hide()
    tmp:SetParent(nil)
    return w
end

local function GetLabelColor(row)
    if row._label and row._label.GetTextColor then
        return row._label:GetTextColor()
    end
    local r, g, b = Theme:GetAccentColor()
    return r, g, b, 1
end

local function SetAllCharColors(r, g, b, a)
    for _, fs in ipairs(charFontStrings) do
        fs:SetTextColor(r, g, b, a or 1)
    end
end

--------------------------------------------------------------------------------
-- Animation Playback
--------------------------------------------------------------------------------

local function PlayAllAnimGroups()
    for _, ag in ipairs(charAnimGroups) do
        if ag then
            ag:Stop()
            ag:Play()
        end
    end
end

local function StopAllAnimGroups()
    for _, ag in ipairs(charAnimGroups) do
        if ag then ag:Stop() end
    end
end

function Navigation:ReplayJumpingLetters()
    if not isActive then return end
    if not jumpContainer or not jumpContainer:IsShown() then return end
    PlayAllAnimGroups()
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local function DoSetup(row)
    local charWidth = MeasureCharWidth(row)
    if charWidth < 1 then
        -- Font not loaded yet; retry next frame
        C_Timer.After(0, function()
            if not isActive then return end
            DoSetup(row)
        end)
        return
    end

    jumpRow = row

    -- Container anchored where the original label sits
    jumpContainer = CreateFrame("Frame", nil, row)
    jumpContainer:SetPoint("LEFT", row, "LEFT", LABEL_LEFT_OFFSET, 0)
    jumpContainer:SetHeight(row:GetHeight() or 28)
    jumpContainer:SetWidth(#LABEL_TEXT * charWidth)

    local r, g, b, a = GetLabelColor(row)
    local font = Theme:GetFont("LABEL")
    local lastNonSpaceIdx = 0

    for i = 1, #LABEL_TEXT do
        local ch = LABEL_TEXT:sub(i, i)
        local cf = CreateFrame("Frame", nil, jumpContainer)
        cf:SetSize(charWidth, jumpContainer:GetHeight())
        if i == 1 then
            cf:SetPoint("LEFT", jumpContainer, "LEFT", 0, 0)
        else
            cf:SetPoint("LEFT", charFrames[i - 1], "RIGHT", 0, 0)
        end

        local fs = cf:CreateFontString(nil, "OVERLAY")
        pcall(fs.SetFont, fs, font, LABEL_SIZE, "")
        fs:SetPoint("CENTER", cf, "CENTER", 0, 0)
        fs:SetText(ch)
        fs:SetTextColor(r, g, b, a or 1)

        charFrames[i] = cf
        charFontStrings[i] = fs

        -- Animate non-space characters
        if ch ~= " " then
            local ag = cf:CreateAnimationGroup()
            ag:SetLooping("NONE")

            local up = ag:CreateAnimation("Translation")
            up:SetOffset(0, JUMP_HEIGHT)
            up:SetDuration(JUMP_DURATION)
            up:SetStartDelay((i - 1) * CHAR_STAGGER)
            up:SetSmoothing("OUT")
            up:SetOrder(1)

            local down = ag:CreateAnimation("Translation")
            down:SetOffset(0, -JUMP_HEIGHT)
            down:SetDuration(JUMP_DURATION)
            down:SetSmoothing("IN")
            down:SetOrder(2)

            charAnimGroups[i] = ag
            lastNonSpaceIdx = i
        else
            charAnimGroups[i] = nil
        end
    end

    -- Wire up cycle replay on the last non-space character's animation finish
    if lastNonSpaceIdx > 0 then
        lastAnimGroup = charAnimGroups[lastNonSpaceIdx]
        lastAnimGroup:SetScript("OnFinished", function()
            if not isActive then return end
            replayTimer = C_Timer.After(CYCLE_PAUSE, function()
                replayTimer = nil
                Navigation:ReplayJumpingLetters()
            end)
        end)
    end

    -- Hide original label
    row._label:Hide()

    -- Hover and leave go through the row's backdrop, and the character
    -- FontStrings take the label color it resolves
    row:SetScript("OnEnter", function(self)
        self._backdrop:SetHover(true)
        SetAllCharColors(self._backdrop:LabelColor())
    end)

    row:SetScript("OnLeave", function(self)
        self._backdrop:SetHover(false)
        SetAllCharColors(self._backdrop:LabelColor())
    end)

    -- Start first cycle
    PlayAllAnimGroups()
end

function Navigation:SetupJumpingLetters(row)
    isActive = true
    -- Defer one frame to ensure font metrics are ready
    C_Timer.After(0, function()
        if not isActive then return end
        if not row or not row:IsShown() then return end
        DoSetup(row)
    end)
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function Navigation:CleanupJumpingLetters()
    if not isActive then return end
    isActive = false

    StopAllAnimGroups()

    if replayTimer then
        replayTimer = nil
    end

    for _, cf in ipairs(charFrames) do
        if cf then cf:Hide(); cf:SetParent(nil) end
    end

    if jumpContainer then
        jumpContainer:Hide()
        jumpContainer:SetParent(nil)
        jumpContainer = nil
    end

    -- Restore original label visibility
    if jumpRow and jumpRow._label then
        jumpRow._label:Show()
    end

    jumpRow = nil
    lastAnimGroup = nil
    charFrames = {}
    charFontStrings = {}
    charAnimGroups = {}
end

--------------------------------------------------------------------------------
-- Color Sync (called from Navigation:UpdateRowSelectionState)
--------------------------------------------------------------------------------

function Navigation:UpdateJumpingLettersColor(row)
    if not isActive then return end
    if row ~= jumpRow then return end
    local r, g, b, a = GetLabelColor(row)
    SetAllCharColors(r, g, b, a)
end

--------------------------------------------------------------------------------
-- Condition Check & Entry Point
--------------------------------------------------------------------------------

function Navigation:MaybeStartJumpingLetters()
    if not addon.AreAllModulesDisabled then return end
    if not addon:AreAllModulesDisabled() then return end

    -- Find the "Features" row
    for _, row in ipairs(self._rows) do
        if row and row._key == "startHere" then
            self:SetupJumpingLetters(row)
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Hook BuildRows to auto-setup/cleanup
--------------------------------------------------------------------------------

local originalBuildRows = Navigation.BuildRows

function Navigation:BuildRows(contentFrame)
    self:CleanupJumpingLetters()
    originalBuildRows(self, contentFrame)
    self:MaybeStartJumpingLetters()
end
