-- RowScaffold.lua - Slot geometry for multi-widget settings rows
-- Contract: BuildSlotRow lays out the shared chrome and the control cluster
-- of a row that carries several compact widgets. The caller creates the row
-- frame, calls BuildSlotRow with the slot kinds, then builds its widgets into
-- the returned slot frames (usually with the Controls._CreateMini* factories)
-- and keeps all behavior wiring. Slot widths, the gap, the mini-label band,
-- and the cluster clamp come from the active skin's metrics, so identical
-- slot combinations render identically on every page.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme

local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- Kinds whose slots shrink proportionally when the cluster exceeds the
-- maximum cluster width; toggle, swatch, and custom keep their widths.
local FLEXIBLE = { slider = true, selector = true, selectorWide = true, input = true }

--------------------------------------------------------------------------------
-- BuildSlotRow: chrome plus a right-aligned cluster of fixed-width slots
--------------------------------------------------------------------------------
-- opts:
--   rowWidth     : The definite row width (the builder's row width; callers
--                  fall back to the parent width)
--   label        : Row label; nil or "" builds a slot-only row
--   description  : Optional explainer under the label, measured synchronously
--   dimColor     : {r,g,b} for the description and the mini-labels
--   slots        : Array of { kind, label, width }. kind picks the metric
--                  slot width (toggle, slider, selector, swatch, input);
--                  width overrides it and is required for kind "custom".
--                  label puts a mini-label above the slot; a label wider
--                  than its slot pushes the slots apart and widens the
--                  cluster, never the slot.
--
-- Returns the cluster container and the array of slot frames, left to right.
-- Each slot frame is control-height, bottom-aligned in the cluster, and
-- carries _miniLabel when the slot declared a label. The row gains
-- _slotContainer and _slots.
--------------------------------------------------------------------------------

function Controls.BuildSlotRow(row, opts)
    local theme = GetTheme()
    local m = Controls.Metrics()
    local slots = opts.slots or {}
    local dim = opts.dimColor

    local widths = {}
    local total, flexTotal = 0, 0
    for i, s in ipairs(slots) do
        local w = s.width or (m.slots and m.slots[s.kind]) or m.slots.selector
        widths[i] = w
        total = total + w
        if FLEXIBLE[s.kind] then
            flexTotal = flexTotal + w
        end
    end
    local gaps = (#slots - 1) * m.slotGap
    local clusterWidth = total + gaps

    -- Clamp to the maximum cluster width by shrinking the flexible kinds in
    -- proportion.
    if clusterWidth > m.maxClusterWidth and flexTotal > 0 then
        local excess = clusterWidth - m.maxClusterWidth
        local scale = math.max(0, (flexTotal - excess) / flexTotal)
        for i, s in ipairs(slots) do
            if FLEXIBLE[s.kind] then
                widths[i] = math.floor(widths[i] * scale + 0.5)
            end
        end
    end

    -- Mini-labels are measured, and slots move apart until neighbouring labels
    -- sit at least slotGap apart. A label centers over its slot, except that
    -- the last label right-aligns with its slot when wider, so the cluster's
    -- right edge stays on the row padding. The cluster widens by the room the
    -- labels take, and the description's reserve with it.
    local labelWidths = {}
    local hasMiniLabels = false
    for i, s in ipairs(slots) do
        if s.label and s.label ~= "" then
            hasMiniLabels = true
            labelWidths[i] = math.ceil(Controls.MeasureText("miniLabel", s.label) or 0)
        end
    end

    local offsets, alignRight = {}, {}
    local slotRight, labelRight = 0, 0
    for i = 1, #slots do
        local w, lw = widths[i], labelWidths[i] or 0
        -- The label's left edge, relative to the slot's left edge.
        local labelLeft = (w - lw) / 2
        if i == #slots and lw > w then
            labelLeft = w - lw
            alignRight[i] = true
        end
        local x
        if i == 1 then
            x = math.max(0, -labelLeft)
        else
            x = slotRight + m.slotGap
            if lw > 0 then
                x = math.max(x, labelRight + m.slotGap - labelLeft)
            end
        end
        x = math.ceil(x)
        offsets[i] = x
        slotRight = x + w
        labelRight = math.max(slotRight, x + labelLeft + lw)
    end
    clusterWidth = slotRight

    local clusterHeight = m.controlHeight
        + (hasMiniLabels and (m.miniLabelHeight + m.miniLabelGap) or 0)
    local baseHeight = hasMiniLabels and m.dualRowHeight or m.rowHeight

    if opts.label and opts.label ~= "" then
        Controls.AddRowChrome(row, {
            rowWidth = opts.rowWidth,
            baseHeight = baseHeight,
            label = opts.label,
            padLeft = m.rowPadding,
            description = opts.description,
            controlReserve = m.rowPadding + clusterWidth + m.slotGap,
            dimColor = dim,
        })
    else
        row:SetHeight(baseHeight)
    end

    local container = CreateFrame("Frame", nil, row)
    container:SetSize(clusterWidth, clusterHeight)
    Controls.AnchorCluster(row, container, { x = -m.rowPadding, band = baseHeight })
    row._slotContainer = container

    local frames = {}
    for i, s in ipairs(slots) do
        local slot = CreateFrame("Frame", nil, container)
        slot:SetSize(widths[i], m.controlHeight)
        slot:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", offsets[i], 0)
        if s.label and s.label ~= "" then
            local fs = container:CreateFontString(nil, "OVERLAY")
            theme:ApplyFont(fs, "miniLabel")
            if alignRight[i] then
                fs:SetPoint("BOTTOMRIGHT", slot, "TOPRIGHT", 0, m.miniLabelGap)
            else
                fs:SetPoint("BOTTOM", slot, "TOP", 0, m.miniLabelGap)
            end
            fs:SetText(s.label)
            if dim then
                fs:SetTextColor(dim[1], dim[2], dim[3], 0.8)
            end
            slot._miniLabel = fs
        end
        frames[i] = slot
    end
    row._slots = frames

    return container, frames
end
