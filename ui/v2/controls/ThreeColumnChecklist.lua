-- ThreeColumnChecklist.lua - Multi-column checkbox grid for filter lists
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_COLUMNS = 3
local DEFAULT_ITEM_HEIGHT = 24
local CHECK_SIZE = 12
local CHECK_PADDING = 6
local ROW_PADDING = 8

--------------------------------------------------------------------------------
-- ThreeColumnChecklist
--
-- Options:
--   parent     : Frame   - Parent frame to anchor into
--   items      : table[] - Array of { key, label, get, set }
--   columns    : number  - Number of columns (default 3)
--   itemHeight : number  - Height per row (default 24)
--   onToggle   : func    - Optional callback(key, newValue)
--   isDisabled : func    - Optional function returning true to disable all items
--------------------------------------------------------------------------------

function Controls:CreateThreeColumnChecklist(options)
    if not options or not options.parent or not options.items then
        return nil
    end

    local parent = options.parent
    local items = options.items
    local columns = options.columns or DEFAULT_COLUMNS
    local itemHeight = options.itemHeight or DEFAULT_ITEM_HEIGHT
    local onToggle = options.onToggle
    local isDisabled = options.isDisabled

    local rows = math.ceil(#items / columns)
    local totalHeight = rows * itemHeight + ROW_PADDING * 2

    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(totalHeight)

    -- Label row (optional)
    if options.label then
        local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFS:SetPoint("TOPLEFT", container, "TOPLEFT", ROW_PADDING, -ROW_PADDING)
        labelFS:SetText(options.label)
        labelFS:SetTextColor(1, 1, 1, 0.9)
        container._label = labelFS
    end

    local colWidth = 1 / columns
    local checkItems = {}

    for i, item in ipairs(items) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)

        local xOffset = col * colWidth
        local yOffset = -(row * itemHeight + ROW_PADDING)

        -- Item frame
        local itemFrame = CreateFrame("Button", nil, container)
        itemFrame:SetHeight(itemHeight)

        -- Use relative positioning within the container
        itemFrame:SetPoint("TOPLEFT", container, "TOPLEFT", xOffset * container:GetWidth() + ROW_PADDING, yOffset)
        itemFrame:SetPoint("RIGHT", container, "LEFT", (xOffset + colWidth) * container:GetWidth() - ROW_PADDING, 0)

        -- Checkbox background
        local checkBg = itemFrame:CreateTexture(nil, "BACKGROUND")
        checkBg:SetSize(CHECK_SIZE, CHECK_SIZE)
        checkBg:SetPoint("LEFT", itemFrame, "LEFT", 0, 0)
        checkBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
        itemFrame._checkBg = checkBg

        -- Checkmark
        local checkMark = itemFrame:CreateTexture(nil, "ARTWORK")
        checkMark:SetSize(CHECK_SIZE - 2, CHECK_SIZE - 2)
        checkMark:SetPoint("CENTER", checkBg, "CENTER", 0, 0)
        checkMark:SetAtlas("checkmark-minimal")
        checkMark:Hide()
        itemFrame._checkMark = checkMark

        -- Label text
        local label = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", checkBg, "RIGHT", CHECK_PADDING, 0)
        label:SetPoint("RIGHT", itemFrame, "RIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetText(item.label)
        label:SetTextColor(0.9, 0.9, 0.9, 1)
        itemFrame._label = label

        -- State management
        local function UpdateState()
            local checked = item.get and item.get() or false
            local disabled = isDisabled and isDisabled() or false

            if checked then
                checkMark:Show()
                local r, g, b = addon.GetAccentColorRGB()
                checkMark:SetVertexColor(r, g, b, 1)
                checkBg:SetColorTexture(r * 0.3, g * 0.3, b * 0.3, 0.6)
            else
                checkMark:Hide()
                checkBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
            end

            if disabled then
                label:SetAlpha(0.4)
                checkBg:SetAlpha(0.4)
                checkMark:SetAlpha(0.4)
            else
                label:SetAlpha(1)
                checkBg:SetAlpha(1)
                checkMark:SetAlpha(1)
            end
        end

        -- Click handler
        itemFrame:SetScript("OnClick", function()
            if isDisabled and isDisabled() then return end
            local newVal = not (item.get and item.get() or false)
            if item.set then item.set(newVal) end
            if onToggle then onToggle(item.key, newVal) end
            UpdateState()
        end)

        -- Hover highlight
        itemFrame:SetScript("OnEnter", function(self)
            if isDisabled and isDisabled() then return end
            self._label:SetTextColor(1, 1, 1, 1)
        end)
        itemFrame:SetScript("OnLeave", function(self)
            self._label:SetTextColor(0.9, 0.9, 0.9, 1)
        end)

        UpdateState()
        checkItems[i] = { frame = itemFrame, update = UpdateState, item = item }
    end

    -- Public API
    container._items = checkItems

    function container:Refresh()
        for _, entry in ipairs(checkItems) do
            entry.update()
        end
    end

    function container:Cleanup()
        -- Nothing to unsubscribe currently
    end

    function container:GetContentHeight()
        return totalHeight
    end

    return container
end

return Controls
