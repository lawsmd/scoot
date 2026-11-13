--------------------------------------------------------------------------------
-- forever/notifications/rollingnumber.lua
-- A number whose digits roll: each digit that changes sinks out of view while
-- its replacement comes down from above, as a counter's wheel turns. For any
-- notification source that shows a count going up.
--
--   local number = RollingNumber.Create(parent)
--   number.frame                     the region to anchor; SetValue sizes it
--   number:SetLook(face, size, style, r, g, b)
--   number:SetValue(n, reserve)      snap to n, sized for the wider of n and
--                                    reserve; returns width, height
--   number:RollTo(n)                 returns the seconds the roll takes
--   number:Tick(elapsed)             driven by the owner's OnUpdate
--
-- Construction rules:
--   * One clipping frame holds the whole number, padded past the glyphs, so
--     an outline or a Deep Shadow copy is never shaved at rest. A digit
--     travels the frame's height, and the clip is what hides it.
--   * Every string is a direct region of that frame on OVERLAY, anchored to
--     the frame and never to another string. The layer under it stays empty
--     for the Deep Shadow copy.
--   * A string always holds a digit. A blank leading place is a hidden
--     string, since an empty one has no rect.
--   * A string starts on a font object, so SetText never meets an unfonted
--     string. The look goes on once the string is shown with its text, and
--     the next ticks read the font back and apply it again where it missed:
--     a SetFont on a hidden or empty string can leave the old font in place.
--   * The digits stand as they would in one string: each place is as wide
--     as its own digit's advance, counted from the frame's left. A place
--     whose digit keeps while one before it changes width slides to its new
--     spot over the roll.
--   * Size is the point size. Nothing here scales a frame or a string.
--   * Motion is position alone. Nothing fades per string.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Notifications = addon.Notifications

local RollingNumber = {}
RollingNumber.__index = RollingNumber
Notifications.RollingNumber = RollingNumber

-- Room past the digits' advances inside the clip: a thick outline's reach
-- past the first and last glyph plus the Deep Shadow copy's 2 unit offset.
local PAD_X, PAD_Y = 6, 4
-- One digit's roll, and the wait between a digit and the one to its left.
local ROLL, STAGGER = 0.45, 0.08
-- What a digit's advance falls back to, against the point size, until the
-- ruler answers.
local ADVANCE_GUESS = 0.55
-- A measured advance outside these, against the point size, is a ruler that
-- has not laid out yet.
local ADVANCE_MIN, ADVANCE_MAX = 0.25, 1.5
-- Ticks after a look or a value change that read the fonts back.
local VERIFY_TICKS = 3

local FONT_OBJECT = "GameFontNormalHuge"

local function smooth(p)
    return p * p * (3 - 2 * p)
end

-- Each digit's advance per face, size and style: the step the font takes
-- from one digit to the next inside a string. A string's width is its
-- advances plus what the outline adds at its two ends, so a digit measured
-- alone reads wider than its step; the step is a pair's width less one's.
-- nil while unmeasurable.
local advances = {}
local function digitAdvances(face, size, style)
    if not (face and addon.MeasureTextWidth) then return nil end
    local key = face .. "\031" .. size .. "\031" .. tostring(style)
    if advances[key] then return advances[key] end
    local set = {}
    for digit = 0, 9 do
        local d = tostring(digit)
        local one = addon.MeasureTextWidth(d, face, size, style)
        local two = addon.MeasureTextWidth(d .. d, face, size, style)
        if not (one and two) then return nil end
        local advance = two - one
        if advance < size * ADVANCE_MIN or advance > size * ADVANCE_MAX then return nil end
        set[d] = advance
    end
    advances[key] = set
    return set
end

-- n as `count` places, right-aligned: digits[i] is a one-character string,
-- or nil for a blank leading place.
local function placesOf(n, count)
    local text = tostring(math.max(0, math.floor(tonumber(n) or 0)))
    local places = {}
    local lead = count - #text
    for i = 1, count do
        if i > lead then places[i] = text:sub(i - lead, i - lead) end
    end
    return places
end

local function lengthOf(n)
    return #tostring(math.max(0, math.floor(tonumber(n) or 0)))
end

function RollingNumber.Create(parent)
    local self = setmetatable({}, RollingNumber)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetClipsChildren(true)
    frame:SetSize(1, 1)
    self.frame = frame
    self.cells = {}
    self.count = 0
    self.size = 22
    self.guess = math.ceil(self.size * ADVANCE_GUESS)
    self.height = self.size + PAD_Y * 2
    self.span = 0
    self.color = { 1, 1, 1 }
    self.verify = 0
    return self
end

local function newString(frame)
    local fs = frame:CreateFontString(nil, "OVERLAY", FONT_OBJECT)
    fs:SetText("0")
    fs:Hide()
    return fs
end

local function cellAt(self, i)
    local cell = self.cells[i]
    if not cell then
        cell = { shown = newString(self.frame), spare = newString(self.frame), x = PAD_X }
        self.cells[i] = cell
    end
    return cell
end

-- x is the string's center, from the frame's left edge.
local function place(self, fs, x, y)
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", self.frame, "LEFT", x, y)
end

local function styleString(self, fs)
    if not self.face then return end
    addon.ApplyFontStyle(fs, self.face, self.size, self.style)
    local c = self.color
    fs:SetTextColor(c[1], c[2], c[3])
end

-- A digit on a string, shown and then styled, in that order.
local function fill(self, fs, digit, x, y)
    fs:SetText(digit)
    place(self, fs, x, y)
    fs:Show()
    styleString(self, fs)
end

local function measure(self)
    self.advances = digitAdvances(self.face, self.size, self.style)
    self.measured = self.advances ~= nil
    self.guess = math.ceil(self.size * ADVANCE_GUESS)
end

-- Where each place's center stands for a row of digits, and how wide the
-- row is. A blank place takes no room, so a number short of its places
-- stands at the left.
local function centers(self, places, count)
    local set = self.advances
    local xs, x = {}, PAD_X
    for i = 1, count do
        local digit = places[i]
        local advance = digit and ((set and set[digit]) or self.guess) or 0
        xs[i] = x + advance / 2
        x = x + advance
    end
    return xs, x - PAD_X
end

local function sizeFrame(self)
    self.height = math.ceil(self.size) + PAD_Y * 2
    local width = math.ceil(self.span) + PAD_X * 2
    self.frame:SetSize(math.max(1, width), self.height)
    return width, self.height
end

-- A roll or a slide cut short lands at once.
local function settle(self, cell)
    if cell.sliding then
        cell.sliding = nil
        cell.x = cell.toX
        if cell.digit then place(self, cell.shown, cell.x, 0) end
    end
    if not cell.rolling then return end
    cell.rolling = nil
    cell.shown:Hide()
    cell.shown, cell.spare = cell.spare, cell.shown
    cell.digit = cell.to
    cell.x = cell.toX
    if cell.digit then
        place(self, cell.shown, cell.x, 0)
    else
        cell.shown:Hide()
    end
end

-- `places` at rest on the first `count` cells, and the cells past them
-- hidden.
local function rest(self, places, count)
    local xs, total = centers(self, places, count)
    for i = 1, count do
        local cell = cellAt(self, i)
        cell.rolling, cell.sliding, cell.to = nil, nil, nil
        cell.digit = places[i]
        cell.x = xs[i]
        cell.spare:Hide()
        if places[i] then
            fill(self, cell.shown, places[i], cell.x, 0)
        else
            cell.shown:Hide()
        end
    end
    for i = count + 1, #self.cells do
        local cell = self.cells[i]
        cell.rolling, cell.sliding, cell.digit = nil, nil, nil
        cell.shown:Hide()
        cell.spare:Hide()
    end
    self.count = count
    return total
end

-- The frame holds the wider of the value and the value it will roll to.
local function span(self, total)
    self.span = total
    if self.reserve then
        local _, reserved = centers(self, placesOf(self.reserve, self.count), self.count)
        if reserved > self.span then self.span = reserved end
    end
    return sizeFrame(self)
end

--- The face (a file path), the point size, the style key and the color.
--- Takes effect at the next SetValue; a number already showing restyles on
--- the next ticks.
function RollingNumber:SetLook(face, size, style, r, g, b)
    self.face, self.size, self.style = face, tonumber(size) or self.size, style
    self.color[1], self.color[2], self.color[3] = r or 1, g or 1, b or 1
    measure(self)
    self.verify = VERIFY_TICKS
end

--- Snap to n. `reserve` is a value the number will roll to: the frame is
--- sized for the wider of the two, so the roll never outgrows it.
function RollingNumber:SetValue(n, reserve)
    local count = lengthOf(n)
    if reserve then count = math.max(count, lengthOf(reserve)) end
    self.value, self.reserve = n, reserve
    if not self.measured then measure(self) end

    local total = rest(self, placesOf(n, count), count)
    self.verify = VERIFY_TICKS
    return span(self, total)
end

--- Roll to n: the places whose digit changes move, the rest stay. Returns
--- the seconds until the last place lands, 0 when nothing changes.
function RollingNumber:RollTo(n)
    for i = 1, self.count do
        settle(self, self.cells[i])
    end

    local count = math.max(self.count, lengthOf(n))
    if count ~= self.count then
        -- No place was reserved for the new leading digit: the shown digits
        -- move one cell over to make it.
        rest(self, placesOf(self.value or 0, count), count)
    end
    self.value = n

    local places = placesOf(n, count)
    local xs, total = centers(self, places, count)
    if total > self.span then
        self.span = total
        sizeFrame(self)
    end

    local last = 0
    for i = count, 1, -1 do
        local cell = self.cells[i]
        if places[i] ~= cell.digit then
            local wait = (count - i) * STAGGER
            cell.rolling, cell.t = true, -wait
            cell.to, cell.toX = places[i], xs[i]
            if cell.to then
                fill(self, cell.spare, cell.to, cell.toX, self.height)
            else
                cell.spare:Hide()
            end
            if wait + ROLL > last then last = wait + ROLL end
        elseif cell.digit and xs[i] ~= cell.x then
            -- Its digit keeps and a place before it changes width
            cell.sliding, cell.t = true, 0
            cell.fromX, cell.toX = cell.x, xs[i]
            if ROLL > last then last = ROLL end
        else
            cell.x = xs[i]
        end
    end
    if last > 0 then self.verify = VERIFY_TICKS end
    return last
end

-- The ruler answered after the number was laid out on the guess: the digits
-- land where they are going and take their measured places.
local function relayout(self)
    local places = {}
    for i = 1, self.count do
        local cell = self.cells[i]
        settle(self, cell)
        places[i] = cell.digit
    end
    span(self, rest(self, places, self.count))
end

local function verifyFonts(self)
    if not (self.face and addon.FontReadsAs) then return end
    for i = 1, self.count do
        local cell = self.cells[i]
        for _, fs in ipairs({ cell.shown, cell.spare }) do
            if fs:IsShown() and addon.FontReadsAs(fs, self.face, self.size, self.style) == false then
                styleString(self, fs)
            end
        end
    end
end

function RollingNumber:Tick(elapsed)
    if not self.measured and self.face then
        measure(self)
        if self.measured then relayout(self) end
    end

    for i = 1, self.count do
        local cell = self.cells[i]
        if cell.rolling then
            cell.t = cell.t + elapsed
            if cell.t >= ROLL then
                settle(self, cell)
            elseif cell.t > 0 then
                local eased = smooth(cell.t / ROLL)
                if cell.digit then place(self, cell.shown, cell.x, -self.height * eased) end
                if cell.to then place(self, cell.spare, cell.toX, self.height * (1 - eased)) end
            end
        elseif cell.sliding then
            cell.t = cell.t + elapsed
            if cell.t >= ROLL then
                settle(self, cell)
            else
                local eased = smooth(cell.t / ROLL)
                place(self, cell.shown, cell.fromX + (cell.toX - cell.fromX) * eased, 0)
            end
        end
    end

    if self.verify > 0 then
        -- The read-back is a frame behind the SetFont it checks, so the tick
        -- that set the look only counts down.
        if self.verify < VERIFY_TICKS then verifyFonts(self) end
        self.verify = self.verify - 1
    end
end

function RollingNumber:IsRolling()
    for i = 1, self.count do
        local cell = self.cells[i]
        if cell.rolling or cell.sliding then return true end
    end
    return false
end
