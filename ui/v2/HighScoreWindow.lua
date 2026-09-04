-- HighScoreWindow.lua - Arcade-styled "High Score" damage meter export display
local addonName, addon = ...

local FRAME_WIDTH = 920
local FRAME_HEIGHT = 780
local BANNER_HEIGHT = 200
local TITLE_HEIGHT = 30
local HEADER_HEIGHT = 24
local ROW_HEIGHT = 20
local CONTENT_TOP_OFFSET = BANNER_HEIGHT + HEADER_HEIGHT + 24
local SIDE_PADDING = 42
local ROW_GAP = 2

-- Column layout
local RANK_COL = 36
local NAME_COL = 280
local DATA_COL = 120
local COL_GAP = 8
local NUM_DATA_COLS = 4

local highScoreFrame = nil

local function GetClassColor(classToken)
    if not classToken then return 1, 1, 1, 1 end
    local r, g, b = addon.GetClassColorRGB(classToken)
    return r or 1, g or 1, b or 1, 1
end

local function GetArcadeFont()
    return addon.ResolveFontFace and addon.ResolveFontFace("PRESS_START_2P")
        or "Interface\\AddOns\\Scoot\\media\\fonts\\PressStart2P-Regular.ttf"
end

local function TruncateToWidth(fontString, text, maxWidth)
    fontString:SetText(text)
    if fontString:GetStringWidth() <= maxWidth then return end
    for i = #text, 1, -1 do
        fontString:SetText(text:sub(1, i) .. "...")
        if fontString:GetStringWidth() <= maxWidth then return end
    end
    fontString:SetText("...")
end

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local xStart = SIDE_PADDING

    -- Rank
    row.rank = row:CreateFontString(nil, "OVERLAY")
    row.rank:SetPoint("LEFT", row, "LEFT", xStart, 0)
    row.rank:SetWidth(RANK_COL)
    row.rank:SetJustifyH("LEFT")

    -- Name (auto-width, no truncation)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetPoint("LEFT", row, "LEFT", xStart + RANK_COL + COL_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Spec/ilvl info (smaller, grey, appended directly after name text)
    row.specInfo = row:CreateFontString(nil, "OVERLAY")
    row.specInfo:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.specInfo:SetJustifyH("LEFT")
    row.specInfo:SetWordWrap(false)

    -- Data columns
    row.cols = {}
    for i = 1, NUM_DATA_COLS do
        local col = row:CreateFontString(nil, "OVERLAY")
        local colX = xStart + RANK_COL + COL_GAP + NAME_COL + COL_GAP + ((i - 1) * (DATA_COL + COL_GAP))
        col:SetPoint("LEFT", row, "LEFT", colX, 0)
        col:SetWidth(DATA_COL)
        col:SetJustifyH("RIGHT")
        row.cols[i] = col
    end

    -- Local player highlight (subtle bg)
    row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, -4)
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.04)
    row.highlight:Hide()

    return row
end

local function SetRowFont(row, font, size)
    pcall(row.rank.SetFont, row.rank, font, size, "")
    pcall(row.name.SetFont, row.name, font, size, "")
    if row.specInfo then
        pcall(row.specInfo.SetFont, row.specInfo, font, math.max(6, size - 6), "")
    end
    for _, col in ipairs(row.cols) do
        pcall(col.SetFont, col, font, size, "")
    end
end

local rowPool = addon.Pool.NewIndexed(function(index, parent)
    return CreateRow(parent, index)
end)

local function CreateHighScoreFrame()
    if highScoreFrame then return highScoreFrame end

    local frame = CreateFrame("Frame", "ScootHighScoreFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    -- Solid black background (full coverage)
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)

    -- Solid border (same pattern as Window:CreateSolidBorder, gray for export)
    local borderWidth = 3
    local br, bg_c, bb = 0.25, 0.25, 0.25

    local borderTop = frame:CreateTexture(nil, "BORDER", nil, -1)
    borderTop:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -borderWidth, 0)
    borderTop:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", borderWidth, 0)
    borderTop:SetHeight(borderWidth)
    borderTop:SetColorTexture(br, bg_c, bb, 1)

    local borderBottom = frame:CreateTexture(nil, "BORDER", nil, -1)
    borderBottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -borderWidth, 0)
    borderBottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", borderWidth, 0)
    borderBottom:SetHeight(borderWidth)
    borderBottom:SetColorTexture(br, bg_c, bb, 1)

    local borderLeft = frame:CreateTexture(nil, "BORDER", nil, -1)
    borderLeft:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(borderWidth)
    borderLeft:SetColorTexture(br, bg_c, bb, 1)

    local borderRight = frame:CreateTexture(nil, "BORDER", nil, -1)
    borderRight:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(borderWidth)
    borderRight:SetColorTexture(br, bg_c, bb, 1)

    -- Close button (custom Scoot-style X)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    closeBtn:EnableMouse(true)
    closeBtn:RegisterForClicks("AnyUp", "AnyDown")

    local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    local Theme = addon.UI and addon.UI.Theme
    local ar, ag, ab = Theme and Theme:GetAccentColor() or 0.20, 0.90, 0.30
    closeBg:SetColorTexture(ar, ag, ab, 1)
    closeBg:Hide()

    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY")
    local closeFontPath = Theme and Theme.GetFont and Theme:GetFont("BUTTON")
        or "Interface\\AddOns\\Scoot\\media\\fonts\\JetBrainsMono-Medium.ttf"
    closeLabel:SetFont(closeFontPath, 16, "")
    closeLabel:SetPoint("CENTER", 0, -1)
    closeLabel:SetText("X")
    closeLabel:SetTextColor(ar, ag, ab, 1)

    closeBtn:SetScript("OnEnter", function(btn)
        local r, g, b = Theme and Theme:GetAccentColor() or ar, ag, ab
        closeBg:SetColorTexture(r, g, b, 1)
        closeBg:Show()
        closeLabel:SetTextColor(0, 0, 0, 1)
    end)
    closeBtn:SetScript("OnLeave", function(btn)
        closeBg:Hide()
        local r, g, b = Theme and Theme:GetAccentColor() or ar, ag, ab
        closeLabel:SetTextColor(r, g, b, 1)
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ESC-close
    tinsert(UISpecialFrames, "ScootHighScoreFrame")

    -- Banner (ScootBanner.png at top center)
    local banner = frame:CreateTexture(nil, "ARTWORK")
    banner:SetSize(400, BANNER_HEIGHT)
    banner:SetPoint("TOP", frame, "TOP", 0, 30)
    banner:SetTexture("Interface\\AddOns\\Scoot\\media\\ScootBanner")
    frame._banner = banner

    -- "HIGH SCORES" title
    local arcadeFont = GetArcadeFont()
    local title = frame:CreateFontString(nil, "OVERLAY")
    pcall(title.SetFont, title, arcadeFont, 18, "")
    title:SetPoint("TOP", banner, "BOTTOM", 0, 50)
    title:SetText("HIGH SCORES")
    title:SetTextColor(0.20, 0.90, 0.30, 1)
    frame._title = title

    -- Column headers
    local headerFrame = CreateFrame("Frame", nil, frame)
    headerFrame:SetSize(FRAME_WIDTH - SIDE_PADDING * 2, HEADER_HEIGHT)
    headerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(BANNER_HEIGHT + 16))

    local xStart = SIDE_PADDING

    -- "#" header
    local rankHeader = headerFrame:CreateFontString(nil, "OVERLAY")
    pcall(rankHeader.SetFont, rankHeader, arcadeFont, 11, "")
    rankHeader:SetPoint("LEFT", headerFrame, "LEFT", xStart, 0)
    rankHeader:SetWidth(RANK_COL)
    rankHeader:SetJustifyH("LEFT")
    rankHeader:SetText("#")
    rankHeader:SetTextColor(1, 1, 1, 0.7)

    -- "PLAYER" header
    local nameHeader = headerFrame:CreateFontString(nil, "OVERLAY")
    pcall(nameHeader.SetFont, nameHeader, arcadeFont, 11, "")
    nameHeader:SetPoint("LEFT", headerFrame, "LEFT", xStart + RANK_COL + COL_GAP, 0)
    nameHeader:SetWidth(NAME_COL)
    nameHeader:SetJustifyH("LEFT")
    nameHeader:SetText("PLAYER")
    nameHeader:SetTextColor(1, 1, 1, 0.7)

    -- Data column headers (dynamic)
    frame._colHeaders = {}
    for i = 1, NUM_DATA_COLS do
        local colHeader = headerFrame:CreateFontString(nil, "OVERLAY")
        pcall(colHeader.SetFont, colHeader, arcadeFont, 11, "")
        local colX = xStart + RANK_COL + COL_GAP + NAME_COL + COL_GAP + ((i - 1) * (DATA_COL + COL_GAP))
        colHeader:SetPoint("LEFT", headerFrame, "LEFT", colX, 0)
        colHeader:SetWidth(DATA_COL)
        colHeader:SetJustifyH("RIGHT")
        colHeader:SetTextColor(1, 1, 1, 0.7)
        frame._colHeaders[i] = colHeader
    end

    -- Header divider line
    local headerDiv = headerFrame:CreateTexture(nil, "ARTWORK")
    headerDiv:SetSize(FRAME_WIDTH - SIDE_PADDING * 2, 1)
    headerDiv:SetPoint("BOTTOMLEFT", headerFrame, "BOTTOMLEFT", xStart, -2)
    headerDiv:SetColorTexture(0.20, 0.90, 0.30, 0.4)

    frame._headerFrame = headerFrame

    -- Session footer (bottom-left: "Overall (30m)")
    local footer = frame:CreateFontString(nil, "OVERLAY")
    pcall(footer.SetFont, footer, GetArcadeFont(), 10, "")
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE_PADDING, 12)
    footer:SetTextColor(1, 1, 1, 0.5)
    frame._footer = footer

    -- Zone info (bottom-right): label + value pairs for aligned START:/END:
    frame._zoneLabel1 = frame:CreateFontString(nil, "OVERLAY")
    pcall(frame._zoneLabel1.SetFont, frame._zoneLabel1, arcadeFont, 10, "")
    frame._zoneLabel1:SetTextColor(1, 1, 1, 0.5)
    frame._zoneLabel1:SetJustifyH("RIGHT")

    frame._zoneValue1 = frame:CreateFontString(nil, "OVERLAY")
    pcall(frame._zoneValue1.SetFont, frame._zoneValue1, arcadeFont, 10, "")
    frame._zoneValue1:SetTextColor(1, 1, 1, 0.5)
    frame._zoneValue1:SetJustifyH("LEFT")

    frame._zoneLabel2 = frame:CreateFontString(nil, "OVERLAY")
    pcall(frame._zoneLabel2.SetFont, frame._zoneLabel2, arcadeFont, 10, "")
    frame._zoneLabel2:SetTextColor(1, 1, 1, 0.5)
    frame._zoneLabel2:SetJustifyH("RIGHT")

    frame._zoneValue2 = frame:CreateFontString(nil, "OVERLAY")
    pcall(frame._zoneValue2.SetFont, frame._zoneValue2, arcadeFont, 10, "")
    frame._zoneValue2:SetTextColor(1, 1, 1, 0.5)
    frame._zoneValue2:SetJustifyH("LEFT")

    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -CONTENT_TOP_OFFSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 36)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(FRAME_WIDTH - 20, 100)
    scrollFrame:SetScrollChild(scrollContent)

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local contentHeight = scrollContent:GetHeight()
        local visibleHeight = self:GetHeight()
        local maxScroll = math.max(0, contentHeight - visibleHeight)
        if maxScroll <= 0 then return end
        local current = self:GetVerticalScroll() or 0
        local step = ROW_HEIGHT * 3
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        self:SetVerticalScroll(newScroll)
    end)

    frame._scrollFrame = scrollFrame
    frame._scrollContent = scrollContent

    -- Populate method
    function frame:Populate(data)
        if not data then return end

        local arcadeFontPath = GetArcadeFont()

        -- Update column headers
        for i = 1, NUM_DATA_COLS do
            local headerText = data.columnNames[i] or ""
            frame._colHeaders[i]:SetText(string.upper(headerText))
        end

        -- Hide old rows
        rowPool:HideFrom(1)

        local contentHeight = 0
        for rank, guid in ipairs(data.playerOrder) do
            local p = data.players[guid]
            if not p then break end

            local row = rowPool:Get(rank, frame._scrollContent)
            row:SetParent(frame._scrollContent)
            row:SetSize(FRAME_WIDTH - 20, ROW_HEIGHT)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame._scrollContent, "TOPLEFT", 0, -((rank - 1) * (ROW_HEIGHT + ROW_GAP)))

            SetRowFont(row, arcadeFontPath, 12)

            -- Rank
            row.rank:SetText(tostring(rank) .. ".")
            row.rank:SetTextColor(1, 1, 1, 0.6)

            -- Name with class color
            local name = p.name or "Unknown"
            row.name:SetText(string.upper(name))
            local cr, cg, cb = GetClassColor(p.classFilename)
            row.name:SetTextColor(cr, cg, cb, 1)

            -- Spec/ilvl annotation
            if row.specInfo then
                local info = addon.FormatPlayerSpecInfo(p)
                if info then
                    row.specInfo:SetText(string.upper(info))
                    row.specInfo:SetTextColor(0.5, 0.5, 0.5, 0.8)
                else
                    row.specInfo:SetText("")
                end
            end

            -- Data columns
            for i = 1, NUM_DATA_COLS do
                local mt = data.columns[i]
                if mt then
                    row.cols[i]:SetText(data.GetDisplayValue(guid, mt))
                    row.cols[i]:SetTextColor(1, 1, 1, 0.9)
                else
                    row.cols[i]:SetText("")
                end
            end

            -- Local player highlight
            if p.isLocalPlayer then
                row.highlight:Show()
            else
                row.highlight:Hide()
            end

            row:Show()
            contentHeight = contentHeight + ROW_HEIGHT + ROW_GAP
        end

        frame._scrollContent:SetHeight(math.max(contentHeight, 100))

        -- Reset scroll position
        frame._scrollFrame:SetVerticalScroll(0)

        -- Update footer with session label and duration
        if frame._footer then
            local label = data.sessionLabel or ""
            if data.duration and data.duration > 0 then
                local m = math.floor(data.duration / 60)
                local durStr = m > 0 and (m .. "m") or (math.floor(data.duration) .. "s")
                label = label .. " (" .. durStr .. ")"
            end
            frame._footer:SetText(label)
        end

        -- Zone display (bottom-right)
        local endZone = data.instanceLabel or "Open World"
        local startZone = data.startZoneLabel or endZone
        local ZONE_LABEL_GAP = 10
        local ZONE_VALUE_MAX_WIDTH = 340

        -- Clear all 4 font strings
        frame._zoneLabel1:ClearAllPoints(); frame._zoneLabel1:SetText("")
        frame._zoneValue1:ClearAllPoints(); frame._zoneValue1:SetText("")
        frame._zoneLabel2:ClearAllPoints(); frame._zoneLabel2:SetText("")
        frame._zoneValue2:ClearAllPoints(); frame._zoneValue2:SetText("")

        if startZone == endZone then
            -- Single zone: just the name, right-aligned
            frame._zoneValue1:SetJustifyH("RIGHT")
            frame._zoneValue1:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE_PADDING, 12)
            TruncateToWidth(frame._zoneValue1, endZone, ZONE_VALUE_MAX_WIDTH)
        else
            -- Dual zone: aligned labels + values
            -- Measure label column width from the wider label
            frame._zoneLabel1:SetText("START:")
            local labelWidth = frame._zoneLabel1:GetStringWidth()

            -- Row 2 (bottom): END
            frame._zoneLabel2:SetText("END:")
            frame._zoneLabel2:SetWidth(labelWidth)
            frame._zoneLabel2:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",
                -(SIDE_PADDING + ZONE_VALUE_MAX_WIDTH + ZONE_LABEL_GAP), 12)
            frame._zoneValue2:SetJustifyH("LEFT")
            frame._zoneValue2:SetPoint("LEFT", frame._zoneLabel2, "RIGHT", ZONE_LABEL_GAP, 0)
            TruncateToWidth(frame._zoneValue2, endZone, ZONE_VALUE_MAX_WIDTH)

            -- Row 1 (above): START
            frame._zoneLabel1:SetWidth(labelWidth)
            frame._zoneLabel1:SetPoint("BOTTOMRIGHT", frame._zoneLabel2, "TOPRIGHT", 0, 2)
            frame._zoneValue1:SetJustifyH("LEFT")
            frame._zoneValue1:SetPoint("LEFT", frame._zoneLabel1, "RIGHT", ZONE_LABEL_GAP, 0)
            TruncateToWidth(frame._zoneValue1, startZone, ZONE_VALUE_MAX_WIDTH)
        end
    end

    frame:Hide()
    highScoreFrame = frame
    return frame
end

function addon.ShowHighScoreWindow(data)
    local frame = CreateHighScoreFrame()
    frame:Populate(data)
    frame:Show()
    frame:Raise()
end
