--------------------------------------------------------------------------------
-- notes/render.lua - a note's body as rows, one per block of its markdown.
--
-- A row is a wrapping FontString with whatever stands to its left: a bullet,
-- a number, a checkbox, a quote bar. Rows come from an indexed pool on the
-- shell and are placed top to bottom by measured height.
--
-- A checkbox is a button. A click on it outside editing mode removes its
-- line from the note.
--------------------------------------------------------------------------------

local _, addon = ...

local N = addon.Notes

local ROW_GAP = 3
local HEADING_GAP = 5        -- extra room above a heading that is not first
local INDENT = 12            -- one level of a nested list
local BULLET_SIZE = 4
local BULLET_TEXT_X = 12
local BOX_SIZE = 16
local BOX_TEXT_X = 19
local NUMBER_GAP = 4
local QUOTE_BAR = 2
local QUOTE_TEXT_X = 9
local RULE_HEIGHT = 9
local CHECK_DELAY = 0.3      -- a checked line stays this long before it goes
local DIM = 0.6

local BOX_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

local function Hex(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5))
end

local function CreateRow(_, shell)
    local row = CreateFrame("Frame", nil, shell._body)
    row:SetSize(N.MIN_WIDTH, 12)

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetFont(addon.GetGameFontNormalFace(), 12, "OUTLINE")
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    row.text = text

    local marker = row:CreateFontString(nil, "OVERLAY")
    marker:SetFont(addon.GetGameFontNormalFace(), 12, "OUTLINE")
    marker:SetJustifyH("LEFT")
    marker:SetWordWrap(false)
    row.marker = marker

    row.bullet = row:CreateTexture(nil, "OVERLAY")
    row.bullet:SetSize(BULLET_SIZE, BULLET_SIZE)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetWidth(QUOTE_BAR)

    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetHeight(1)

    local box = CreateFrame("Button", nil, row)
    box:SetSize(BOX_SIZE, BOX_SIZE)
    box:SetNormalTexture(BOX_TEXTURE)
    local check = box:CreateTexture(nil, "OVERLAY")
    check:SetTexture(CHECK_TEXTURE)
    check:SetAllPoints(box)
    box.check = check
    box:SetScript("OnClick", function()
        if row.line then N.CheckOff(shell, row) end
    end)
    row.box = box

    return row
end

local function Rows(shell)
    if not shell._rows then
        shell._rows = addon.Pool.NewIndexed(CreateRow)
    end
    return shell._rows
end

--- Fills the shell's rows from shell._blocks. Sizes and places are
--- N.LayoutRows' work.
function N.RenderRows(shell)
    local rows = Rows(shell)
    local blocks = shell._blocks or {}
    local titleFace, titleSize, titleStyle = N.TitleFont()
    local bodyFace, bodySize, bodyStyle = N.BodyFont()
    local hr, hg, hb, ha = N.HeaderColor()
    local br, bg, bb, ba = N.BodyColor()
    local colors = { strong = Hex(hr, hg, hb), dim = Hex(br * DIM, bg * DIM, bb * DIM) }
    local headingSizes = { titleSize, math.ceil((titleSize + bodySize) / 2), bodySize }

    local count = 0
    for index = shell._firstBlock or 1, #blocks do
        local block = blocks[index]
        count = count + 1
        local row = rows:Get(count, shell)
        row.block = block
        row.line = nil
        row:SetAlpha(1)
        row.marker:Hide()
        row.bullet:Hide()
        row.bar:Hide()
        row.rule:Hide()
        row.box:Hide()
        row.text:Show()
        row.text:SetAlpha(1)

        local kind = block.kind
        local indent = (block.indent or 0) * INDENT
        row.textX = 0
        row.lineHeight = bodySize

        if kind == "heading" then
            local size = headingSizes[block.level] or bodySize
            addon.ApplyFontStyle(row.text, titleFace, size, titleStyle)
            row.text:SetTextColor(hr, hg, hb, ha)
            row.lineHeight = size
        else
            addon.ApplyFontStyle(row.text, bodyFace, bodySize, bodyStyle)
            row.text:SetTextColor(br, bg, bb, ba)
        end

        if kind == "bullet" then
            row.bullet:SetColorTexture(br, bg, bb, ba)
            row.bullet:ClearAllPoints()
            row.bullet:SetPoint("TOPLEFT", row, "TOPLEFT", indent + 3, -math.floor((bodySize - BULLET_SIZE) / 2 + 1))
            row.bullet:Show()
            row.textX = indent + BULLET_TEXT_X
        elseif kind == "number" then
            addon.ApplyFontStyle(row.marker, bodyFace, bodySize, bodyStyle)
            row.marker:SetTextColor(br, bg, bb, ba)
            row.marker:SetText(block.number .. ".")
            row.marker:ClearAllPoints()
            row.marker:SetPoint("TOPLEFT", row, "TOPLEFT", indent, 0)
            row.marker:Show()
            row.textX = indent + math.ceil(row.marker:GetStringWidth() or 0) + NUMBER_GAP
        elseif kind == "task" then
            row.line = block.line
            row.box:ClearAllPoints()
            row.box:SetPoint("TOPLEFT", row, "TOPLEFT", indent - 2, math.floor((BOX_SIZE - bodySize) / 2))
            row.box.check:SetShown(block.checked)
            row.box:EnableMouse(true)
            row.box:Show()
            row.textX = indent + BOX_TEXT_X
            if block.checked then row.text:SetAlpha(DIM) end
        elseif kind == "quote" then
            row.bar:SetColorTexture(br, bg, bb, 0.5)
            row.bar:ClearAllPoints()
            row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.bar:Show()
            row.text:SetAlpha(DIM + 0.15)
            row.textX = QUOTE_TEXT_X
        elseif kind == "rule" then
            row.rule:SetColorTexture(br, bg, bb, 0.35)
            row.rule:ClearAllPoints()
            row.rule:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.rule:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.rule:Show()
            row.text:Hide()
        elseif kind == "blank" then
            row.text:Hide()
        end

        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", row.textX, 0)
        row.text:SetWidth(0)
        row.text:SetText(addon.Markdown.Inline(block.text, colors))
        row:Show()
    end

    rows:HideFrom(count + 1)
    shell._rowCount = count
end

--- Sizes and places the rows. Returns the body's width and height; a note
--- with no rows returns 0, 0.
function N.LayoutRows(shell)
    local rows = Rows(shell)
    local count = shell._rowCount or 0
    if count == 0 then return 0, 0 end

    -- The width the widest row would take on one line, inside the limits.
    local width = N.MIN_WIDTH
    for index = 1, count do
        local row = rows:Get(index, shell)
        if row.text:IsShown() then
            row.text:SetWidth(0)
            local natural = row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth()
                or row.text:GetStringWidth() or 0
            width = math.max(width, row.textX + math.ceil(natural))
        end
    end
    width = math.min(width, N.MAX_WIDTH)

    local y = 0
    for index = 1, count do
        local row = rows:Get(index, shell)
        local kind = row.block.kind
        local height
        if kind == "rule" then
            height = RULE_HEIGHT
        elseif kind == "blank" then
            height = math.floor(row.lineHeight * 0.6)
        else
            row.text:SetWidth(width - row.textX)
            height = math.max(math.ceil(row.text:GetStringHeight() or 0), row.lineHeight)
        end
        if index > 1 then
            y = y + ROW_GAP + (kind == "heading" and HEADING_GAP or 0)
        end
        row:SetSize(width, height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", shell._body, "TOPLEFT", 0, -y)
        y = y + height
    end

    shell._body:SetSize(width, y)
    return width, y
end

--- A click on a checkbox: the box shows its check, the line dims, and a
--- moment later the line leaves the note.
function N.CheckOff(shell, row)
    local record = shell._record
    local lineIndex = row.line
    if not record or not lineIndex or shell._editing then return end
    local expected = addon.Markdown.Lines(record.text)[lineIndex]
    if not expected then return end

    row.box.check:Show()
    row.box:EnableMouse(false)
    row:SetAlpha(DIM)

    C_Timer.After(CHECK_DELAY, function()
        if shell._record ~= record or shell._editing then return end
        local lines = addon.Markdown.Lines(record.text)
        -- The text changed under the timer: leave it to the next draw.
        if lines[lineIndex] ~= expected then return end
        record.text = addon.Markdown.RemoveLine(record.text, lineIndex)
        if addon.NotesHost then addon.NotesHost.Commit() end
        N.Render(shell)
    end)
end
