-- settingspanel/ascii.lua - the title bar's ASCII reveal: UTF-8 helpers and
-- the column animation over the product's logo text
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.SettingsPanel = addon.UI.SettingsPanel or {}
local UIPanel = addon.UI.SettingsPanel
local Theme = addon.UI.Theme

-- Animation Constants

local ASCII_ANIMATION_DURATION = 1.0      -- Total animation time in seconds
local ASCII_ANIMATION_TICK = 0.016        -- Update rate (~60fps)

-- UTF-8 String Helpers (for column-by-column ASCII animation)

-- Extract UTF-8 characters from a string via byte-based iteration
local function utf8Chars(s)
    if not s then return {} end
    local chars = {}
    local i = 1
    local len = #s
    while i <= len do
        local c = s:byte(i)
        local charLen = 1
        if c >= 0xF0 then      -- 4-byte sequence (0xF0-0xF4)
            charLen = 4
        elseif c >= 0xE0 then  -- 3-byte sequence (0xE0-0xEF)
            charLen = 3
        elseif c >= 0xC0 then  -- 2-byte sequence (0xC0-0xDF)
            charLen = 2
        end
        table.insert(chars, s:sub(i, i + charLen - 1))
        i = i + charLen
    end
    return chars
end

-- Get first N UTF-8 characters as a string
local function utf8Sub(s, n)
    if not s or n <= 0 then return "" end
    local chars = utf8Chars(s)
    local result = {}
    for i = 1, math.min(n, #chars) do
        table.insert(result, chars[i])
    end
    return table.concat(result)
end

-- Count UTF-8 characters in a string
local function utf8Len(s)
    if not s then return 0 end
    return #utf8Chars(s)
end

-- The logo is the product's, HeaderModel.title.ascii, and the column parse
-- runs once per text.
local parsed = { text = nil, lines = {}, maxCols = 0 }

local function LogoText()
    local model = UIPanel.HeaderModel and UIPanel.HeaderModel.title
    return (model and model.ascii) or ""
end

local function Parsed()
    local text = LogoText()
    if parsed.text == text then return parsed end
    parsed.text, parsed.lines, parsed.maxCols = text, {}, 0
    for line in text:gmatch("[^\n]+") do
        local lineData = { text = line, chars = utf8Chars(line) }
        lineData.len = #lineData.chars
        table.insert(parsed.lines, lineData)
        if lineData.len > parsed.maxCols then
            parsed.maxCols = lineData.len
        end
    end
    return parsed
end

-- ASCII Art Column Animation
-- Reveals one vertical column at a time, left to right.
local function buildPartialAscii(numCols)
    if numCols <= 0 then return "" end
    local data = Parsed()
    if numCols >= data.maxCols then return data.text end

    local lines = {}
    for i, lineData in ipairs(data.lines) do
        local partial = ""
        for j = 1, math.min(numCols, lineData.len) do
            partial = partial .. lineData.chars[j]
        end
        table.insert(lines, partial)
    end
    return table.concat(lines, "\n")
end

function UIPanel:AnimateAsciiReveal()
    local frame = self.frame
    if not frame or not frame._logo then return end

    local logo = frame._logo
    local logoBtn = frame._logoBtn

    self:StopAsciiAnimation()

    local startTime = GetTime()
    local totalColumns = Parsed().maxCols

    local ar, ag, ab = Theme:GetAccentColor()
    logo:SetTextColor(ar, ag, ab, 1)

    logo:SetText("")

    local ticker
    ticker = C_Timer.NewTicker(ASCII_ANIMATION_TICK, function()
        local elapsed = GetTime() - startTime
        local progress = math.min(elapsed / ASCII_ANIMATION_DURATION, 1.0)

        local columnsToShow = math.floor(progress * totalColumns)
        local partialText = buildPartialAscii(columnsToShow)
        logo:SetText(partialText)

        if progress >= 1.0 then
            ticker:Cancel()
            frame._asciiAnimTicker = nil
            logo:SetText(LogoText())
            if logoBtn and not logoBtn:IsMouseOver() then
                local r, g, b = Theme:GetAccentColor()
                logo:SetTextColor(r, g, b, 1)
            end
        end
    end)

    frame._asciiAnimTicker = ticker
end

function UIPanel:StopAsciiAnimation()
    local frame = self.frame
    if not frame then return end

    if frame._asciiAnimTicker then
        frame._asciiAnimTicker:Cancel()
        frame._asciiAnimTicker = nil
    end

    if frame._logo then
        frame._logo:SetText(LogoText())
        if frame._logoBtn and not frame._logoBtn:IsMouseOver() then
            local r, g, b = Theme:GetAccentColor()
            frame._logo:SetTextColor(r, g, b, 1)
        end
    end
end

function UIPanel:IsAsciiAnimationRunning()
    local frame = self.frame
    return frame and frame._asciiAnimTicker ~= nil
end
