--------------------------------------------------------------------------------
-- forever/objectivetracker/card.lua
-- One quest card for the Camelot style of Current Objectives (cards.lua lays
-- the cards out): the quest's name centered at the top, its level and tag
-- under it, the tracker header's knobbed bronze line under those, then one
-- row per objective down the card, and a footer under the last row.
--
-- The card draws no backdrop or frame: the text stands on the world in the
-- crisp thick outline. The card is as tall as its content, and cards.lua
-- gives every card in the row the tallest one's height, so the Edit Mode box
-- and the overflow floor agree across the row.
--
-- A row takes the shape of its objective:
--   bar     a count with more than one step: the name over the bar's left
--           end, the count over its right end, the bar empty of text, ticks
--           between the steps when there are ten or fewer. A rise lights the
--           newly filled step (or span) inside its own bounds
--   check   a count of one, an event, a reputation: the text where a bar
--           row's name starts, the box where its count ends, centered on
--           the text and larger when the text wraps
--   percent the ptr2 progress bar objective: a bar with the percent over it
--   money   the gold a quest asks for: a check row reading have / need
-- Objectives of type log and spell, and any with no text, are not drawn.
-- The footer says Failed, Ready for turn-in, or the time left.
--
-- The rows hang from each other by anchor, so no string is measured before
-- the client has laid it out. Measure and Fit run a frame later, once it
-- has. Past the tallest a card may be, a row below the card's floor is
-- hidden and the rows just above it step down toward it, the way
-- overflow.lua fades the Classic pane.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style

local Card = {}
OT.Card = Card

local PAD = 10
local ROW_GAP = 5
local BAR_HEIGHT = 10
-- A check box is the objective font's size plus a pad, a larger pad when
-- the text wraps; the art has a clear margin of about a fifth each side.
local BOX_PAD = 6
local BOX_PAD_WRAPPED = 12
local BOX_GAP = 2
local MAX_TICKS = 10
local FOOTER_GAP = 6
local FOOT_PAD = 6
local COUNT_GAP = 6
local MIN_HEIGHT = 60
local FADE_BAND = 28
local FADE_FLOOR = 0.2
local EASE_SECONDS = 0.3

-- Vanilla art, all in the client.
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local BAR_BORDER = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"
local BOX_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"
local RULE_TEXTURE = "Interface\\QuestFrame\\UI-HorizontalBreak"

-- The tracker's own header (the All Objectives bar), whose Forever art is
-- a bronze line with a knob at each end, a dark band, and the same line
-- again. The bottom line is cut out of the 300x40 atlas by pixel rows,
-- measured on build 1.60.1: 30 to 37, the knobs inside 48 pixels of each
-- end. Caps at their own size and a stretched middle keep the knobs round
-- at any card width.
local HEADER_ATLAS = "ui-questtracker-primary-objective-header"
local HEADER_W, HEADER_H = 300, 40
local LINE_BOTTOM = { 30, 37 }
local CAP = 48

-- Every string on the card unless its setting names another style: the
-- crisp thick outline carries the contrast the removed backdrop gave.
local CARD_FONT_STYLE = "THICKOUTLINESLUG"

-- The rise on a bar: the new step flares and a glint crosses it once.
local DAZZLE = { 1, 0.9, 0.55 }
local DAZZLE_SECONDS = 0.9
local GLINT_WIDTH = 10
local QUEST_GOLD = { 1, 0.82, 0 }
local DONE_GREY = { 0.6, 0.6, 0.6 }
local ROW_WHITE = { 0.9, 0.9, 0.9 }
local BAR_FILL = { 0.86, 0.6, 0.14 }
local BAR_DONE = { 0.3, 0.72, 0.26 }
local FAILED_RED = { 1, 0.2, 0.2 }
local READY_GREEN = { 0.4, 1, 0.4 }

local HIDDEN_TYPES = { log = true, spell = true }

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function isPlain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

-- "Bear Claw: 5/10" and "5/10 Bear Claw" both give "Bear Claw".
local function nameOf(text)
    if type(text) ~= "string" then return "" end
    local name = text:match("^(.-):%s*%d+%s*/%s*%d+%s*$")
        or text:match("^%d+%s*/%s*%d+%s+(.+)$")
    return name or text
end

local function difficultyColor(level)
    if type(level) ~= "number" then return QUEST_GOLD end
    local c = call(_G.GetQuestDifficultyColor, level)
    if type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return QUEST_GOLD
end

-- Seconds left on a timed quest, or nil. The retail read first; Classic's
-- timer list second, matched to the quest through its log index.
local function timeLeft(questID, logIndex)
    local total, elapsed = call(C_QuestLog and C_QuestLog.GetTimeAllowed, questID)
    if type(total) == "number" and type(elapsed) == "number" and total > 0 then
        return math.max(0, total - elapsed), total
    end
    if type(_G.GetQuestTimers) ~= "function" or type(_G.GetQuestIndexForTimer) ~= "function" then return nil end
    local timers = { call(_G.GetQuestTimers) }
    for i, seconds in ipairs(timers) do
        if type(seconds) == "number" and call(_G.GetQuestIndexForTimer, i) == logIndex then
            return seconds, nil
        end
    end
    return nil
end

--- Everything a card draws for a quest, as plain values: { questID, title,
--- level, tag, color, complete, failed, rows = { { kind, text, name, have,
--- need, done, index } }, timer = { left, total, at } }.
function Card.Read(questID)
    local info = { questID = questID, rows = {} }
    local logIndex = call(C_QuestLog.GetLogIndexForQuestID, questID)
    info.title = call(C_QuestLog.GetTitleForQuestID, questID)
    local qinfo = logIndex and call(C_QuestLog.GetInfo, logIndex)
    if type(qinfo) == "table" then
        info.title = info.title or qinfo.title
        info.level = qinfo.level
    end
    if not info.level and logIndex and type(_G.GetQuestLogTitle) == "function" then
        local _, level = call(_G.GetQuestLogTitle, logIndex)
        info.level = level
    end
    if type(info.title) ~= "string" or not isPlain(info.title) then info.title = "?" end
    if not isPlain(info.level) then info.level = nil end
    info.color = difficultyColor(info.level)

    local tag = call(C_QuestLog.GetQuestTagInfo, questID)
    if type(tag) == "table" and type(tag.tagName) == "string" and isPlain(tag.tagName) then
        info.tag = tag.tagName
    end

    info.complete = call(C_QuestLog.IsComplete, questID) == true
    info.failed = call(C_QuestLog.IsFailed, questID) == true

    local objectives = call(C_QuestLog.GetQuestObjectives, questID)
    if type(objectives) == "table" then
        for index, o in ipairs(objectives) do
            if type(o) == "table" and isPlain(o.text) and isPlain(o.numFulfilled) then
                local text, kind = o.text
                local have, need = o.numFulfilled, o.numRequired
                if HIDDEN_TYPES[o.type] or type(text) ~= "string" or text == "" then
                    kind = nil
                elseif o.type == "progressbar" then
                    kind = "percent"
                    have, need = call(_G.GetQuestProgressBarPercent, questID) or 0, 100
                elseif type(need) == "number" and need > 1 and o.type ~= "reputation" then
                    kind = "bar"
                else
                    kind = "check"
                end
                if kind then
                    info.rows[#info.rows + 1] = {
                        kind = kind, index = index, text = text, done = o.finished == true,
                        -- A reputation reads "Neutral / Friendly" and keeps it.
                        name = o.type == "reputation" and text or nameOf(text),
                        have = tonumber(have) or 0, need = tonumber(need) or 1,
                    }
                end
            end
        end
    end

    local money = call(C_QuestLog.GetRequiredMoney, questID)
    if type(money) == "number" and money > 0 then
        local owned = call(_G.GetMoney) or 0
        local fmt = _G.GetCoinTextureString or _G.GetMoneyString or tostring
        info.rows[#info.rows + 1] = {
            kind = "check", index = 0, done = owned >= money,
            name = string.format("%s / %s", call(fmt, owned) or "?", call(fmt, money) or "?"),
        }
    end

    local left, total = timeLeft(questID, logIndex)
    if left then info.timer = { left = left, total = total, at = GetTime() } end
    return info
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function textConfig(key)
    local pane = Style.CARDS
    return {
        fontFace = Style.PaneGet(pane, key, "fontFace"),
        style = Style.PaneGet(pane, key, "style"),
        colorMode = Style.PaneGet(pane, key, "colorMode"),
        color = Style.PaneGet(pane, key, "color"),
    }
end

-- The face, style and size over a string. No stored face keeps the font
-- object's; no stored style takes the card's outline.
local function applyFont(fs, cfg, size)
    local face = cfg.fontFace and addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace) or nil
    face = face or fs:GetFont()
    if not face then return end
    addon.ApplyFontStyle(fs, face, size, cfg.style or CARD_FONT_STYLE)
end

-- The stored custom color, or the card's own.
local function colorFor(cfg, r, g, b)
    local cr, cg, cb, _, source = addon.ResolveColorRGBA(cfg.colorMode, cfg.color, {})
    if source == "custom" then return cr, cg, cb end
    return r, g, b
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function createBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    -- Blizzard's ObjectiveTrackerProgressBarTemplate frame, at its small size.
    local left = bar:CreateTexture(nil, "OVERLAY")
    left:SetTexture(BAR_BORDER)
    left:SetSize(9, BAR_HEIGHT + 4)
    left:SetTexCoord(0.007843, 0.043137, 0.193548, 0.774193)
    left:SetPoint("LEFT", bar, "LEFT", -3, 0)
    local right = bar:CreateTexture(nil, "OVERLAY")
    right:SetTexture(BAR_BORDER)
    right:SetSize(9, BAR_HEIGHT + 4)
    right:SetTexCoord(0.043137, 0.007843, 0.193548, 0.774193)
    right:SetPoint("RIGHT", bar, "RIGHT", 3, 0)
    local mid = bar:CreateTexture(nil, "OVERLAY")
    mid:SetTexture(BAR_BORDER)
    mid:SetTexCoord(0.113726, 0.1490196, 0.193548, 0.774193)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

    -- The rise: a flare over the newly filled span and a glint crossing it
    -- once. The frame is sized to the span and clips its children, so the
    -- glint never leaves it.
    local dazzle = CreateFrame("Frame", nil, bar)
    dazzle:SetFrameLevel(bar:GetFrameLevel() + 1)
    dazzle:SetClipsChildren(true)
    dazzle:Hide()
    local flare = dazzle:CreateTexture(nil, "ARTWORK")
    flare:SetAllPoints()
    flare:SetColorTexture(DAZZLE[1], DAZZLE[2], DAZZLE[3], 1)
    flare:SetBlendMode("ADD")
    flare:SetAlpha(0)
    local glint = CreateFrame("Frame", nil, dazzle)
    glint:SetWidth(GLINT_WIDTH)
    glint:SetPoint("TOPRIGHT", dazzle, "TOPLEFT")
    glint:SetPoint("BOTTOMRIGHT", dazzle, "BOTTOMLEFT")
    local clear, bright = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.9)
    for i = 1, 2 do
        local half = glint:CreateTexture(nil, "ARTWORK")
        half:SetColorTexture(1, 1, 1, 1)
        half:SetBlendMode("ADD")
        half:SetWidth(GLINT_WIDTH / 2)
        half:SetPoint("TOP")
        half:SetPoint("BOTTOM")
        if i == 1 then
            half:SetPoint("LEFT")
            half:SetGradient("HORIZONTAL", clear, bright)
        else
            half:SetPoint("RIGHT")
            half:SetGradient("HORIZONTAL", bright, clear)
        end
    end

    local group = dazzle:CreateAnimationGroup()
    local up = group:CreateAnimation("Alpha")
    up:SetTarget(flare)
    up:SetFromAlpha(0)
    up:SetToAlpha(0.8)
    up:SetDuration(0.08)
    up:SetOrder(1)
    local down = group:CreateAnimation("Alpha")
    down:SetTarget(flare)
    down:SetFromAlpha(0.8)
    down:SetToAlpha(0)
    down:SetStartDelay(0.18)
    down:SetDuration(DAZZLE_SECONDS - 0.18)
    down:SetSmoothing("IN")
    down:SetOrder(1)
    local sweep = group:CreateAnimation("Translation")
    sweep:SetTarget(glint)
    sweep:SetStartDelay(0.06)
    sweep:SetDuration(0.45)
    sweep:SetSmoothing("IN_OUT")
    sweep:SetOrder(1)
    group:SetScript("OnFinished", function() dazzle:Hide() end)
    dazzle.group, dazzle.sweep, dazzle.flare = group, sweep, flare
    bar.Dazzle = dazzle

    bar.ticks = {}
    return bar
end

-- Lights the bar between two values, inside the bar and nowhere else.
local function playDazzle(bar, from, to)
    local width = bar:GetWidth()
    if not (width and width > 0) then return end
    local x1, x2 = width * from, width * to
    if x2 - x1 < 3 then x1 = math.max(0, x2 - 3) end
    local d = bar.Dazzle
    d.group:Stop()
    d.flare:SetAlpha(0)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", bar, "TOPLEFT", x1, -1)
    d:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", x2, 1)
    d.sweep:SetOffset(x2 - x1 + GLINT_WIDTH, 0)
    d:Show()
    d.group:Play()
end

local function layoutTicks(bar, steps)
    local n = (steps and steps > 1 and steps <= MAX_TICKS) and steps - 1 or 0
    local width = bar:GetWidth()
    for i = 1, math.max(n, #bar.ticks) do
        local tick = bar.ticks[i]
        if i <= n then
            if not tick then
                tick = bar:CreateTexture(nil, "ARTWORK", nil, 2)
                tick:SetColorTexture(0, 0, 0, 0.7)
                tick:SetWidth(1)
                bar.ticks[i] = tick
            end
            tick:ClearAllPoints()
            tick:SetPoint("TOP", bar, "TOPLEFT", width * i / steps, 0)
            tick:SetPoint("BOTTOM", bar, "BOTTOMLEFT", width * i / steps, 0)
            tick:Show()
        elseif tick then
            tick:Hide()
        end
    end
end

local function createRow(card)
    local content = card.Content
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(1, 1)
    -- Read by flash.lua the way it reads a tracker line: objectiveKey,
    -- parentBlock.id, Text, and the frame level the burst goes under.
    row.parentBlock = {}

    row.Label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Label:SetJustifyH("LEFT")
    row.Label:SetWordWrap(true)
    row.Label:SetMaxLines(3)

    -- A bar row's count, over the bar's right end.
    row.Count = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Count:SetJustifyH("RIGHT")

    row.Box = content:CreateTexture(nil, "ARTWORK")
    row.Box:SetTexture(BOX_TEXTURE)
    row.Box:SetSize(16, 16)
    row.Check = content:CreateTexture(nil, "OVERLAY")
    row.Check:SetTexture(CHECK_TEXTURE)
    row.Check:SetAllPoints(row.Box)

    row.Bar = createBar(content)
    return row
end

local function hideRow(row)
    row:Hide()
    row.Label:Hide()
    row.Count:Hide()
    row.Box:Hide()
    row.Check:Hide()
    row.Bar:Hide()
    row.Bar.Dazzle.group:Stop()
    row.Bar.Dazzle:Hide()
    row.Label:SetAlpha(1)
    row.Count:SetAlpha(1)
    row.Box:SetAlpha(1)
    row.Check:SetAlpha(1)
    row.Bar:SetAlpha(1)
end

--------------------------------------------------------------------------------
-- The card
--------------------------------------------------------------------------------

local CardMixin = {}

-- One of the header's lines as a frame: two caps and a stretched middle cut
-- out of the atlas by the coords SetAtlas resolved, so the client's own set
-- (Forever's bronze) supplies the sheet. Nil when the atlas is missing.
local function knobbedLine(parent, rows)
    local line = CreateFrame("Frame", nil, parent)
    line:SetHeight(rows[2] - rows[1])
    local parts = {}
    for i = 1, 3 do
        local tex = line:CreateTexture(nil, "ARTWORK")
        if not tex:SetAtlas(HEADER_ATLAS) then
            line:Hide()
            return nil
        end
        parts[i] = tex
    end
    local l, t = parts[1]:GetTexCoord()
    local _, _, _, _, r, _, _, b = parts[1]:GetTexCoord()
    local function u(x) return l + (r - l) * x / HEADER_W end
    local function v(y) return t + (b - t) * y / HEADER_H end
    local top, bottom = v(rows[1]), v(rows[2])
    local left, mid, right = parts[1], parts[2], parts[3]
    left:SetTexCoord(u(0), u(CAP), top, bottom)
    left:SetSize(CAP, rows[2] - rows[1])
    left:SetPoint("LEFT")
    right:SetTexCoord(u(HEADER_W - CAP), u(HEADER_W), top, bottom)
    right:SetSize(CAP, rows[2] - rows[1])
    right:SetPoint("RIGHT")
    mid:SetTexCoord(u(CAP), u(HEADER_W - CAP), top, bottom)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return line
end

function Card.Create(parent)
    local card = CreateFrame("Frame", nil, parent)
    Mixin(card, CardMixin)

    -- Everything drawn sits two levels over the card: the flash's burst goes
    -- between the two.
    local content = CreateFrame("Frame", nil, card)
    content:SetAllPoints()
    content:SetFrameLevel(card:GetFrameLevel() + 2)
    card.Content = content

    local title = content:CreateFontString(nil, "ARTWORK", _G.QuestTitleFontBlackShadow and "QuestTitleFontBlackShadow" or "GameFontNormal")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD - 2)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, -PAD - 2)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(true)
    title:SetMaxLines(2)
    card.Title = title

    local sub = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -2)
    sub:SetJustifyH("CENTER")
    card.Sub = sub
    card.subSize = select(2, sub:GetFont())

    local rule = knobbedLine(content, LINE_BOTTOM)
    if not rule then
        rule = content:CreateTexture(nil, "ARTWORK")
        rule:SetTexture(RULE_TEXTURE)
        rule:SetHeight(8)
    end
    rule:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -4, -3)
    rule:SetPoint("TOPRIGHT", sub, "BOTTOMRIGHT", 4, -3)
    card.Rule = rule

    local footer = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footer:SetJustifyH("CENTER")
    card.Footer = footer
    card.footerSize = select(2, footer:GetFont())

    card.rows = addon.Pool.NewIndexed(function() return createRow(card) end, hideRow)
    card.faded = {}
    card:Hide()
    return card
end

--- The width from the setting. The height waits for Measure: cards.lua sets
--- it once every card in the row has been measured.
function CardMixin:SetCardWidth(width)
    self.width = width
    self:SetWidth(width)
    if not self:GetHeight() or self:GetHeight() < 1 then self:SetHeight(MIN_HEIGHT) end
end

--- The tallest the card may be before its last rows fade: the playing
--- card's 5:7 of its width.
function Card.MaxHeight(width)
    return math.floor(width * 7 / 5 + 0.5)
end

local function setColor(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

-- The row's left edge relative to the card, for chaining the next row.
local function placeRegion(region, prev, prevLeft, left, gap)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", left - prevLeft, -gap)
end

-- The bar's value, eased from the last one drawn when a rise comes in, the
-- risen span lit. A bar the pool moved to another objective starts plain.
local easing = {}
local easeDriver = CreateFrame("Frame")
easeDriver:Hide()
easeDriver:SetScript("OnUpdate", function(self)
    local t = GetTime()
    for bar, e in pairs(easing) do
        local x = (t - e.t) / EASE_SECONDS
        if x >= 1 or not bar:IsVisible() then
            bar:SetValue(e.to)
            easing[bar] = nil
        else
            x = x * x * (3 - 2 * x)
            bar:SetValue(e.from + (e.to - e.from) * x)
        end
    end
    if next(easing) == nil then self:Hide() end
end)

local function setBarValue(bar, key, value, ease)
    local from = bar.key == key and bar.drawn or nil
    bar.key, bar.drawn = key, value
    if ease and from and value > from then
        easing[bar] = { from = from, to = value, t = GetTime() }
        easeDriver:Show()
        playDazzle(bar, from, value)
    else
        easing[bar] = nil
        bar:SetValue(value)
    end
end

local function flashOn()
    return Style.Get("current", "flashProgress") == true
end

--- Draws a quest from Card.Read's table.
function CardMixin:Render(info)
    self.info = info
    self.questID = info.questID
    local width = self.width or 150
    local inner = width - 2 * PAD
    local titleCfg, rowCfg = textConfig("textTitle"), textConfig("textObjective")
    local titleSize = Style.CardTextSize("titleSize")
    local rowSize = Style.CardTextSize("objectiveSize")

    applyFont(self.Title, titleCfg, titleSize)
    applyFont(self.Sub, { style = titleCfg.style }, self.subSize)
    applyFont(self.Footer, { style = rowCfg.style }, self.footerSize)
    self.Title:SetText(info.title)
    local tc = info.complete and QUEST_GOLD or info.color
    self.Title:SetTextColor(colorFor(titleCfg, tc[1], tc[2], tc[3]))

    local sub = info.level and ("Level " .. info.level) or ""
    if info.tag then sub = sub ~= "" and (sub .. " - " .. info.tag) or info.tag end
    self.Sub:SetText(sub)

    local prev, prevLeft = self.Rule, PAD - 4
    local ease = flashOn()
    for i, data in ipairs(info.rows) do
        local row = self.rows:Get(i)
        row:Show()
        row.objectiveKey = data.index
        row.parentBlock.id = info.questID
        row.kind = data.kind
        applyFont(row.Label, rowCfg, rowSize)
        local base = data.done and DONE_GREY or ROW_WHITE
        row.Label:SetTextColor(colorFor(rowCfg, base[1], base[2], base[3]))
        local gap = i == 1 and 4 or ROW_GAP

        if data.kind == "check" then
            row.Bar:Hide()
            row.Count:Hide()
            row.Box:Show()
            row.Check:SetShown(data.done)
            -- The text starts where a bar row's name does and the box ends
            -- where a bar row's count does, centered on however many lines
            -- the text takes. Text that wraps gets the larger box. The box
            -- art's clear margin takes the 2 units past the count's edge.
            local barWidth = inner - 6
            local face = row.Label:GetFont()
            local textWidth = face and addon.MeasureTextWidth
                and addon.MeasureTextWidth(data.name, face, rowSize, rowCfg.style or CARD_FONT_STYLE)
            local box = rowSize + BOX_PAD
            if not textWidth or textWidth > barWidth - box - BOX_GAP + 2 then
                box = rowSize + BOX_PAD_WRAPPED
            end
            placeRegion(row.Label, prev, prevLeft, PAD + 3, gap)
            row.Label:SetWidth(barWidth - box - BOX_GAP + 2)
            row.Label:SetText(data.name)
            row.Label:Show()
            row.Box:SetSize(box, box)
            row.Box:ClearAllPoints()
            row.Box:SetPoint("RIGHT", row.Label, "LEFT", barWidth + 2, 0)
            -- The flash colors the text it finds the count in; a check row's
            -- text has none, so the whole line flashes.
            row.Text = row.Label
            row.noBurst = nil
            -- The next row hangs from the text. The box, centered on it, is
            -- a few units taller at most, and the row gap takes them.
            prev, prevLeft = row.Label, PAD + 3
        else
            row.Box:Hide()
            row.Check:Hide()
            -- The name and the count sit over the bar's two ends; the bar's
            -- frame reaches 3 past its fill on each side.
            local barWidth = inner - 6
            local count = row.Count
            applyFont(count, rowCfg, rowSize)
            count:SetTextColor(colorFor(rowCfg, base[1], base[2], base[3]))
            if data.kind == "percent" then
                count:SetText(string.format("%d%%", data.have))
            else
                count:SetText(string.format("%d/%d", data.have, data.need))
            end
            local face = count:GetFont()
            local countWidth = face and addon.MeasureTextWidth
                and addon.MeasureTextWidth(count:GetText(), face, rowSize, rowCfg.style or CARD_FONT_STYLE)
                or count:GetStringWidth()
            placeRegion(row.Label, prev, prevLeft, PAD + 3, gap)
            row.Label:SetWidth(math.max(20, barWidth - (countWidth or 0) - COUNT_GAP))
            row.Label:SetText(data.name)
            row.Label:Show()

            local bar = row.Bar
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", row.Label, "BOTTOMLEFT", 0, -3)
            bar:SetWidth(barWidth)
            bar:Show()
            -- On the name's last line, which is its only line most of the time.
            count:ClearAllPoints()
            count:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 3)
            count:Show()
            local need = math.max(1, data.need)
            local value = math.min(1, data.have / need)
            setBarValue(bar, info.questID .. ":" .. data.index, value, ease)
            local fill = (data.done or value >= 1) and BAR_DONE or BAR_FILL
            bar:SetStatusBarColor(fill[1], fill[2], fill[3])
            layoutTicks(bar, data.kind == "bar" and data.need or nil)
            row.Text = count
            -- The bar lights its own risen span (setBarValue); the flash only
            -- colors the count.
            row.noBurst = true
            prev, prevLeft = bar, PAD + 3
        end
    end
    self.rows:HideFrom(#info.rows + 1)
    self.lastRegion = prev

    -- Under the last row, across the card. Fit moves it to the card's foot
    -- when the rows run past the tallest a card may be.
    placeRegion(self.Footer, prev, prevLeft, PAD, FOOTER_GAP)
    self.Footer:SetWidth(inner)
    self:RenderFooter()
end

--- The footer: failed, ready, the timer, or nothing. Returns whether the
--- timer needs another tick.
function CardMixin:RenderFooter()
    local info = self.info
    if not info then return false end
    local footer = self.Footer
    if info.failed then
        footer:SetText(FAILED or "Failed")
        setColor(footer, FAILED_RED)
        return false
    end
    if info.complete then
        footer:SetText("Ready for turn-in")
        setColor(footer, READY_GREEN)
        return false
    end
    local timer = info.timer
    if timer then
        local left = math.max(0, timer.left - (GetTime() - timer.at))
        local text = _G.SecondsToClock and _G.SecondsToClock(left) or string.format("%d:%02d", left / 60, left % 60)
        footer:SetText(text)
        -- ObjectiveTrackerTimerBarMixin's steps: white, then yellow under
        -- two thirds, red under one third.
        local share = timer.total and timer.total > 0 and left / timer.total or 1
        if share < 1 / 3 then
            setColor(footer, FAILED_RED)
        elseif share < 2 / 3 then
            footer:SetTextColor(1, 1, 0)
        else
            footer:SetTextColor(1, 1, 1)
        end
        return left > 0
    end
    footer:SetText("")
    return false
end

--------------------------------------------------------------------------------
-- Overflow
--------------------------------------------------------------------------------

local function fadeRegion(card, region, floor, band)
    if not region:IsShown() then return end
    local top, bottom = region:GetTop(), region:GetBottom()
    if not (top and bottom) then return end
    if bottom < floor - 1 then
        region:SetAlpha(0)
        card.faded[region] = true
        card.overflow = true
        return
    end
    local t = ((top + bottom) / 2 - floor) / band
    if t >= 1 then return end
    region:SetAlpha(FADE_FLOOR + (1 - FADE_FLOOR) * math.max(0, t))
    card.faded[region] = true
end

local function lowest(region, low)
    if not (region and region:IsShown()) then return low end
    local bottom = region:GetBottom()
    if not bottom then return low end
    return low and math.min(low, bottom) or bottom
end

--- A frame after a render: the height the card's content asks for, from its
--- top to the lowest thing drawn, plus a short foot. Nil
--- before the client has laid the card out.
function CardMixin:Measure()
    local top = self:GetTop()
    if not top then return nil end
    local low = lowest(self.Rule)
    for i = 1, self.rows:Count() do
        local row = self.rows:Get(i)
        if row:IsShown() then
            low = lowest(row.Label, low)
            low = lowest(row.Count, low)
            low = lowest(row.Box, low)
            low = lowest(row.Bar, low)
        end
    end
    if (self.Footer:GetText() or "") ~= "" then low = lowest(self.Footer, low) end
    if not low then return nil end
    return math.max(MIN_HEIGHT, math.ceil(top - low + FOOT_PAD))
end

--- Sets the height cards.lua chose. When the content asked for more, the
--- footer moves to the card's foot and the rows past it fade out, the rows
--- just above stepping down toward it.
function CardMixin:Fit(height, wanted)
    for region in pairs(self.faded) do region:SetAlpha(1) end
    wipe(self.faded)
    self.overflow = false
    self:SetHeight(height)
    if not wanted or wanted <= height then return end

    local footer = self.Footer
    footer:ClearAllPoints()
    footer:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", PAD, FOOT_PAD - 4)
    footer:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -PAD, FOOT_PAD - 4)
    -- From the top: the new height is not laid out yet, the top is.
    local top = self:GetTop()
    if not top then return end
    local floor = top - height + FOOT_PAD
    if (footer:GetText() or "") ~= "" then floor = floor + footer:GetStringHeight() + FOOTER_GAP end
    self.overflow = true
    for i = 1, self.rows:Count() do
        local row = self.rows:Get(i)
        if row:IsShown() then
            fadeRegion(self, row.Label, floor, FADE_BAND)
            fadeRegion(self, row.Count, floor, FADE_BAND)
            fadeRegion(self, row.Box, floor, FADE_BAND)
            fadeRegion(self, row.Check, floor, FADE_BAND)
            fadeRegion(self, row.Bar, floor, FADE_BAND)
        end
    end
end

--- For flash.lua: the row drawing objective `index`, if this card has it.
function CardMixin:RowFor(index)
    for i = 1, self.rows:Count() do
        local row = self.rows:Get(i)
        if row:IsShown() and row.objectiveKey == index then return row end
    end
    return nil
end

--- The row kinds, for the dump.
function CardMixin:Describe()
    local kinds = {}
    for i = 1, self.rows:Count() do
        local row = self.rows:Get(i)
        if row:IsShown() then kinds[#kinds + 1] = row.kind or "?" end
    end
    return table.concat(kinds, " "), self.overflow
end
