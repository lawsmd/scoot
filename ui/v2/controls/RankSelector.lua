-- RankSelector.lua — horizontal Priority slot strip
--
-- Visual design: "Priority" label on the left, then a row of square slot
-- boxes. Each box displays the spell icon of the aura currently occupying
-- that priority position within the edited aura's anchor group. Below each
-- box is its slot number (1, 2, 3, …).
--
-- Three per-slot states:
--   • SELF            — slot holds the aura currently being edited
--                       (accent-colored border + icon, click is a no-op)
--   • OCCUPIED_OTHER  — slot holds a different enabled aura in this anchor
--                       (neutral border + icon, click triggers set() → reorder)
--   • EMPTY           — slot is beyond the group's current size
--                       (dim border, no icon, click is a no-op)
--
-- The whole strip dims to 50% alpha when the edited aura is not currently in
-- this anchor group — the strip is informational until the user enables the
-- aura or changes its anchor to this one.

local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme

local function GetTheme()
    if not Theme then Theme = addon.UI.Theme end
    return Theme
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BOX_SIZE        = 28
local BOX_SPACING     = 4           -- gap between boxes
local BOX_STEP        = BOX_SIZE + BOX_SPACING  -- left-to-left distance
local ICON_INSET      = 2
local NUMBER_GAP      = 2           -- gap between box bottom and number label
local NUMBER_FONT_SIZE = 10
local LABEL_FONT_SIZE  = 12
local LABEL_RIGHT_GAP  = 10         -- gap between label and first box
local ROW_HEIGHT      = BOX_SIZE + NUMBER_GAP + NUMBER_FONT_SIZE + 4
local NOT_IN_GROUP_ALPHA = 0.5

-- Palette for borders / numbers
local NEUTRAL_BD_R, NEUTRAL_BD_G, NEUTRAL_BD_B, NEUTRAL_BD_A = 0.30, 0.30, 0.35, 0.75
local EMPTY_BD_R,   EMPTY_BD_G,   EMPTY_BD_B,   EMPTY_BD_A   = 0.18, 0.18, 0.20, 0.40
local NEUTRAL_BG_R, NEUTRAL_BG_G, NEUTRAL_BG_B, NEUTRAL_BG_A = 0.10, 0.10, 0.12, 0.80
local EMPTY_BG_R,   EMPTY_BG_G,   EMPTY_BG_B,   EMPTY_BG_A   = 0.06, 0.06, 0.08, 0.70
local NUMBER_R, NUMBER_G, NUMBER_B                            = 0.70, 0.70, 0.70
local NUMBER_DIM_R, NUMBER_DIM_G, NUMBER_DIM_B                = 0.40, 0.40, 0.45

--------------------------------------------------------------------------------
-- Spell icon resolution (falls back if provided callback is missing)
--------------------------------------------------------------------------------

local function ResolveSpellTexture(spellId)
    if not spellId then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellId)
    if ok and tex then return tex end
    return nil
end

--------------------------------------------------------------------------------
-- Per-slot paint
--------------------------------------------------------------------------------

local function PaintBox(box, state, accentR, accentG, accentB)
    local bdR, bdG, bdB, bdA
    local bgR, bgG, bgB, bgA
    local showIcon

    if state == "self" then
        bdR, bdG, bdB, bdA = accentR, accentG, accentB, 0.95
        bgR, bgG, bgB, bgA = NEUTRAL_BG_R, NEUTRAL_BG_G, NEUTRAL_BG_B, NEUTRAL_BG_A
        showIcon = true
    elseif state == "occupied" then
        bdR, bdG, bdB, bdA = NEUTRAL_BD_R, NEUTRAL_BD_G, NEUTRAL_BD_B, NEUTRAL_BD_A
        bgR, bgG, bgB, bgA = NEUTRAL_BG_R, NEUTRAL_BG_G, NEUTRAL_BG_B, NEUTRAL_BG_A
        showIcon = true
    else  -- "empty"
        bdR, bdG, bdB, bdA = EMPTY_BD_R, EMPTY_BD_G, EMPTY_BD_B, EMPTY_BD_A
        bgR, bgG, bgB, bgA = EMPTY_BG_R, EMPTY_BG_G, EMPTY_BG_B, EMPTY_BG_A
        showIcon = false
    end

    if box._bg then box._bg:SetColorTexture(bgR, bgG, bgB, bgA) end
    if box._borders then
        for _, tex in pairs(box._borders) do
            tex:SetColorTexture(bdR, bdG, bdB, bdA)
        end
    end
    if box._icon then
        if showIcon then
            box._icon:Show()
        else
            box._icon:Hide()
        end
    end

    -- Number below the box dims for empty slots
    if box._number then
        if state == "empty" then
            box._number:SetTextColor(NUMBER_DIM_R, NUMBER_DIM_G, NUMBER_DIM_B, 1)
        else
            box._number:SetTextColor(NUMBER_R, NUMBER_G, NUMBER_B, 1)
        end
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- options:
--   parent          (required)  host frame
--   count           (optional, default 6)  number of slots rendered
--   labelText       (optional, default "Priority")  left-side label
--   get             function() -> integer  current rank of the edited aura
--                                          (1..count; used to pick the SELF slot)
--   set             function(newRank)  called when user clicks another slot
--   isInGroup       function() -> bool  whether the edited aura is currently
--                                       enabled AND in the anchor being shown;
--                                       when false, whole strip dims and clicks
--                                       no-op
--   spellIdAt       function(rank) -> spellId_or_nil  returns the spellId
--                                       occupying that slot in the current
--                                       anchor's ordered list
--   currentSpellId  function() -> spellId  the edited aura's spellId
--                                       (used to match against spellIdAt for
--                                       the SELF visual)
function Controls:CreateRankSelector(options)
    local parent = options and options.parent
    if not parent then return nil end

    local count        = tonumber(options.count) or 6
    local labelText    = options.labelText or "Priority"
    local getFn        = options.get or function() return 1 end
    local setFn        = options.set or function() end
    local isInGroupFn  = options.isInGroup or function() return true end
    local spellIdAtFn  = options.spellIdAt or function() return nil end
    local currentSpellIdFn = options.currentSpellId or function() return nil end

    local theme = GetTheme()
    local ar, ag, ab = 0.2, 0.9, 0.3
    if theme and theme.GetAccentColor then ar, ag, ab = theme:GetAccentColor() end
    local dimR, dimG, dimB = 0.5, 0.5, 0.5
    if theme and theme.GetDimTextColor then dimR, dimG, dimB = theme:GetDimTextColor() end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Left-side "Priority" label
    local labelFS = row:CreateFontString(nil, "OVERLAY")
    if theme and theme.ApplyLabelFont then
        theme:ApplyLabelFont(labelFS, LABEL_FONT_SIZE)
    else
        labelFS:SetFont("Fonts\\FRIZQT__.TTF", LABEL_FONT_SIZE, "OUTLINE")
    end
    labelFS:SetPoint("LEFT", row, "LEFT", 0, (NUMBER_FONT_SIZE + NUMBER_GAP) / -2)  -- vertically centered on box row
    labelFS:SetText(labelText)
    labelFS:SetTextColor(ar, ag, ab, 1)
    row._label = labelFS

    -- Boxes anchor relative to label
    local function boxLeftOffset(i)
        return labelFS:GetStringWidth() + LABEL_RIGHT_GAP + (i - 1) * BOX_STEP
    end

    row._boxes = {}

    local function HandleClick(i)
        if not isInGroupFn() then return end     -- strip is informational-only
        local cur = tonumber(getFn()) or 1
        if i == cur then return end              -- click own slot: no-op
        local box = row._boxes[i]
        if not box or box._state ~= "occupied" then return end
        setFn(i)
    end

    for i = 1, count do
        local box = CreateFrame("Button", nil, row)
        box:SetSize(BOX_SIZE, BOX_SIZE)
        -- Positioned in deferred pass (labelFS width unknown at construct time
        -- on first frame) — also re-positioned inside RepaintAll in case the
        -- label text ever changes.
        box:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        box._bg = bg

        local icon = box:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", box, "TOPLEFT", ICON_INSET, -ICON_INSET)
        icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim default Blizzard icon border
        icon:Hide()
        box._icon = icon

        -- Static color: RepaintBox owns all tinting (per-state colors).
        box._borders = Controls.CreateBorder(box, {
            corners = "overlap",
            sublevel = 0,
            color = { 0, 0, 0, 0 },
        })

        local number = row:CreateFontString(nil, "OVERLAY")
        if theme and theme.ApplyValueFont then
            theme:ApplyValueFont(number, NUMBER_FONT_SIZE)
        else
            number:SetFont("Fonts\\FRIZQT__.TTF", NUMBER_FONT_SIZE, "OUTLINE")
        end
        number:SetPoint("TOP", box, "BOTTOM", 0, -NUMBER_GAP)
        number:SetText(tostring(i))
        box._number = number

        box:RegisterForClicks("LeftButtonUp")
        box:SetScript("OnClick", function() HandleClick(i) end)

        row._boxes[i] = box
    end

    local function RepositionBoxes()
        local baseX = labelFS:GetStringWidth() + LABEL_RIGHT_GAP
        for i, box in ipairs(row._boxes) do
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", row, "TOPLEFT", baseX + (i - 1) * BOX_STEP, 0)
        end
        row:SetWidth(baseX + count * BOX_STEP + 4)
    end

    local function RepaintAll()
        local acR, acG, acB = ar, ag, ab
        if theme and theme.GetAccentColor then acR, acG, acB = theme:GetAccentColor() end

        labelFS:SetTextColor(acR, acG, acB, 1)
        RepositionBoxes()

        local inGroup = isInGroupFn() and true or false
        row:SetAlpha(inGroup and 1.0 or NOT_IN_GROUP_ALPHA)

        local selfSpellId = currentSpellIdFn()

        for i, box in ipairs(row._boxes) do
            local occupantSpellId = spellIdAtFn(i)
            local state
            if occupantSpellId and selfSpellId and occupantSpellId == selfSpellId then
                state = "self"
            elseif occupantSpellId then
                state = "occupied"
            else
                state = "empty"
            end
            box._state = state

            if state ~= "empty" then
                local tex = ResolveSpellTexture(occupantSpellId)
                if tex then box._icon:SetTexture(tex) end
            end

            PaintBox(box, state, acR, acG, acB)
        end
    end

    -- Defer once so labelFS:GetStringWidth() reports a stable width
    C_Timer.After(0, function()
        if row and row.GetParent and row:GetParent() then RepaintAll() end
    end)
    RepaintAll()

    function row:Refresh()
        RepaintAll()
    end

    return row
end
