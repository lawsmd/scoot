-- HighScoreWindow.lua - Arcade-styled "High Score" damage meter export display
local addonName, addon = ...

-- The frame name carries the brand because both addons load this file in the
-- retail client; the media root is the loading addon's folder because the
-- Forever client has no Scoot folder to resolve against.
local BRAND = addon.Brand
local ROOT = addon.MediaPath

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
        or ROOT .. "media\\fonts\\PressStart2P-Regular.ttf"
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

-- The row's content, built once on the Button the scroll list made
local function BuildRow(row)
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

-- A row for the player at a rank: the fonts first, because a FontString
-- styled while empty keeps its creation font
local function RenderRow(row, p, rank, data)
    SetRowFont(row, GetArcadeFont(), 12)

    row.rank:SetText(tostring(rank) .. ".")
    row.rank:SetTextColor(1, 1, 1, 0.6)

    local name = p.name or "Unknown"
    row.name:SetText(string.upper(name))
    local cr, cg, cb = GetClassColor(p.classFilename)
    row.name:SetTextColor(cr, cg, cb, 1)

    if row.specInfo then
        -- The formatter belongs to the damage meter, which not every
        -- addon loading this file carries.
        local info = addon.FormatPlayerSpecInfo and addon.FormatPlayerSpecInfo(p)
        if info then
            row.specInfo:SetText(string.upper(info))
            row.specInfo:SetTextColor(0.5, 0.5, 0.5, 0.8)
        else
            row.specInfo:SetText("")
        end
    end

    for i = 1, NUM_DATA_COLS do
        local mt = data.columns[i]
        if mt then
            row.cols[i]:SetText(data.GetDisplayValue(p.guid, mt))
            row.cols[i]:SetTextColor(1, 1, 1, 0.9)
        else
            row.cols[i]:SetText("")
        end
    end

    -- The local player's row carries a faint white wash
    row._backdrop:SetStatus(p.isLocalPlayer and { 1, 1, 1, 0.04 } or nil)
end

local function CreateHighScoreFrame()
    if highScoreFrame then return highScoreFrame end

    -- Kept off addon.UI.WindowShell: the export look is solid black with a
    -- grey border, apart from the skin's window role, so a screenshot reads
    -- the same under every skin.
    local frame = CreateFrame("Frame", BRAND .. "HighScoreFrame", UIParent)
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
    local ar, ag, ab = addon.GetAccentColorRGB()
    closeBg:SetColorTexture(ar, ag, ab, 1)
    closeBg:Hide()

    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY")
    local closeFontPath = Theme and Theme.GetFont and Theme:GetFont("BUTTON")
        or ROOT .. "media\\fonts\\JetBrainsMono-Medium.ttf"
    closeLabel:SetFont(closeFontPath, 16, "")
    closeLabel:SetPoint("CENTER", 0, -1)
    closeLabel:SetText("X")
    closeLabel:SetTextColor(ar, ag, ab, 1)

    closeBtn:SetScript("OnEnter", function()
        local r, g, b = addon.GetAccentColorRGB()
        closeBg:SetColorTexture(r, g, b, 1)
        closeBg:Show()
        closeLabel:SetTextColor(0, 0, 0, 1)
        frame._closeHovered = true
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBg:Hide()
        local r, g, b = addon.GetAccentColorRGB()
        closeLabel:SetTextColor(r, g, b, 1)
        frame._closeHovered = false
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- ESC-close
    tinsert(UISpecialFrames, BRAND .. "HighScoreFrame")

    -- Banner (ScootBanner.png, top centre)
    local banner = frame:CreateTexture(nil, "ARTWORK")
    banner:SetSize(400, BANNER_HEIGHT)
    banner:SetPoint("TOP", frame, "TOP", 0, 30)
    banner:SetTexture(ROOT .. "media\\ScootBanner.png")
    frame._banner = banner

    -- "HIGH SCORES" title
    local arcadeFont = GetArcadeFont()
    local title = frame:CreateFontString(nil, "OVERLAY")
    pcall(title.SetFont, title, arcadeFont, 18, "")
    title:SetPoint("TOP", banner, "BOTTOM", 0, 50)
    title:SetText("HIGH SCORES")
    title:SetTextColor(ar, ag, ab, 1)
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
    headerDiv:SetColorTexture(ar, ag, ab, 0.4)

    -- The window is built once and cached for the session, so it outlives any
    -- accent change and reads once at build is not enough.
    if Theme and Theme.Subscribe then
        Theme:Subscribe("ScootHighScoreWindow", function(r, g, b)
            closeBg:SetColorTexture(r, g, b, 1)
            -- Black while the cursor is on the button; OnLeave repaints it.
            if not frame._closeHovered then
                closeLabel:SetTextColor(r, g, b, 1)
            end
            title:SetTextColor(r, g, b, 1)
            headerDiv:SetColorTexture(r, g, b, 0.4)
        end)
    end

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

    -- The rows: a scroll list with the skin's bar in the right margin. The
    -- rows take no hover and no selection; a row is a line of a table.
    local list = addon.UI.Controls.CreateScrollList({
        parent = frame, rowHeight = ROW_HEIGHT, rowGap = ROW_GAP, hover = false,
        createRow = BuildRow,
        render = function(row, entry, rank)
            RenderRow(row, entry.player, rank, frame._data)
        end,
    })
    list.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -CONTENT_TOP_OFFSET)
    list.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 36)
    frame._list = list

    -- Populate method
    function frame:Populate(data)
        if not data then return end
        frame._data = data

        -- Update column headers
        for i = 1, NUM_DATA_COLS do
            local headerText = data.columnNames[i] or ""
            frame._colHeaders[i]:SetText(string.upper(headerText))
        end

        local items = {}
        for _, guid in ipairs(data.playerOrder) do
            local p = data.players[guid]
            if not p then break end
            p.guid = p.guid or guid
            items[#items + 1] = { player = p }
        end
        list:SetItems(items)
        list:ScrollToTop()

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
