--------------------------------------------------------------------------------
-- forever/actionbars/compact.lua
-- Compact Filled Buttons. With Show Empty Buttons off, a member's buttons
-- that hold an action pack toward the middle, the start or the end of the
-- bar's slot run, and every slot comes back whenever the grid shows: a
-- pickup, an open spellbook, Quick Keybind, Edit Mode. The slots never move.
-- Blizzard's UpdateGridLayout keeps every button container in its grid
-- place, so the bar's rect, the cluster, the end caps and the Edit Mode box
-- stay what they were; each button is re-anchored inside its own container
-- by a count of slot pitches, a half pitch for the middle, and un-packing
-- is the same write at zero. Compaction is per line: a row of a multi-row
-- bar packs on its own, and a short last line centers on the bar's full
-- stride.
--
-- Action Bar 1 pages in a fight and nothing below can move in one, so its
-- filled set is the union over page 1, the page it shows and the bonus
-- pages: one layout across every form, a slot any form uses keeps its
-- place, and a form that leaves it empty shows a gap there.
--
-- The grid bits live here too. A button's SetShowGrid writes its showgrid
-- attribute only from secure code, and a call from this addon is not, so
-- the bar's SetShowGrid override writes the reason's bit before Blizzard's
-- pass reads it: the CVAR bit of Show Empty Buttons, the EVENT bit of a
-- pickup and Quick Keybind, the SPELLCOLLECTION bit of an open spellbook,
-- and this addon's own Edit Mode bit. The spellbook and Quick Keybind reach
-- Blizzard's multibars through one global pair, hooked below.
--
-- Every write is a SetPoint or a SetAttribute on a secure button: out of
-- combat only. A grid call that lands in a fight is replayed at regen, the
-- latest per bar; Blizzard's pass still records the pickup and spellbook
-- reasons on the bar in a fight, and the next shown pass out of combat
-- writes the buttons' bits from that record, so a drop in a fight never
-- leaves slots showing.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Compact = {}
ActionBars.Compact = Compact

local OWNER = ActionBars.OWNER .. ".compact"

-- Blizzard's reasons are the bits 1, 2 and 4; Edit Mode is this addon's.
Compact.REASON_EDITMODE = 8

local REASON_EVENT = ACTION_BUTTON_SHOW_GRID_REASON_EVENT
local REASON_SPELLCOLLECTION = ACTION_BUTTON_SHOW_GRID_REASON_SPELLCOLLECTION
-- The reasons Blizzard's SetShowGrid records on the bar itself.
local RECORDED = bit.bor(REASON_EVENT, REASON_SPELLCOLLECTION)

-- Slots per page, and the pages Action Bar 1 shows besides the manual ones:
-- page 1 and the five bonus bars, which the page driver maps to 7 to 11
-- (paging.lua).
local SLOTS = NUM_ACTIONBAR_BUTTONS or 12
local UNION_PAGES = { 1, 7, 8, 9, 10, 11 }

local function queue(fn, key)
    addon.Events.RunOutOfCombat(fn, key)
end

local function keyFor(prefix, bar)
    return prefix .. (bar:GetName() or tostring(bar))
end

-- The built bars, in pool order.
local function eachBar(fn)
    local frames = ActionBars.Frames or {}
    for _, token in ipairs(ActionBars.POOL_ORDER or {}) do
        local bar = frames[token]
        if bar then fn(bar, token) end
    end
end

--------------------------------------------------------------------------------
-- The grid bits
--------------------------------------------------------------------------------

--- Set or clear one reason's bit on every button's showgrid attribute. Out
--- of combat only: the attribute is protected.
function Compact.SetGridBit(bar, show, reason)
    for _, button in ipairs(bar.actionButtons) do
        local current = button:GetAttribute("showgrid") or 0
        local wanted = show and bit.bor(current, reason) or bit.band(current, bit.bnot(reason))
        if wanted ~= current then
            button:SetAttribute("showgrid", wanted)
        end
    end
end

--- Write the pickup and spellbook bits from the bar's own record, which
--- Blizzard's SetShowGrid keeps in a fight too. Out of combat only.
function Compact.SyncBits(bar)
    local recorded = bit.band(bar.showAllButtons or 0, RECORDED)
    for _, button in ipairs(bar.actionButtons) do
        local current = button:GetAttribute("showgrid") or 0
        local wanted = bit.bor(bit.band(current, bit.bnot(RECORDED)), recorded)
        if wanted ~= current then
            button:SetAttribute("showgrid", wanted)
        end
    end
end

--- The body of CamelotActionBarMixin:SetShowGrid. Blizzard's own early
--- returns come first, so no bit is written for a pass that will not run:
--- no clear in Quick Keybind mode, and on the Forever client no show under
--- the gamepad UI, a check its ActionBar.lua adds and live's lacks, so it is
--- tested bare. In a fight the attribute is protected: the call is replayed
--- at regen, the latest per bar, while Blizzard's pass runs now for its
--- record and the alpha pass.
function Compact.ShowGrid(bar, show, reason)
    if not show and KeybindFrames_InQuickKeybindMode() then return end
    if show and InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
        return
    end
    if InCombatLockdown() then
        queue(function() bar:SetShowGrid(show, reason) end, keyFor("camelotActionBars.grid.", bar))
    else
        Compact.SetGridBit(bar, show, reason)
    end
    ActionBarMixin.SetShowGrid(bar, show, reason)
end

--------------------------------------------------------------------------------
-- The member
--------------------------------------------------------------------------------

--- Carry a member's settings onto its bar before the layout's SetShowGrid:
--- the mode, nil for off (a bar with noSpacers packs by itself), whether the
--- bar pages, and the Edit Mode bit, which follows the mode while Edit Mode
--- is open so a bar made compact from the page inside it shows its slots.
--- The caller runs out of combat.
function Compact.Prepare(bar, m)
    bar.compactPaged = m.identity == "bar1"
    bar.compactAlign = (m.compact and not bar.noSpacers) and (m.compactAlign or "center") or nil
    local editing = addon.EditMode.IsEditing and addon.EditMode.IsEditing()
    Compact.SetGridBit(bar, editing and bar.compactAlign ~= nil, Compact.REASON_EDITMODE)
end

-- Whether a button draws an action: on the paging bar, on any page of the
-- union; elsewhere, on its own slot.
local function filled(bar, button)
    if button:GetAttribute("statehidden") then return false end
    if bar.compactPaged then
        for _, page in ipairs(UNION_PAGES) do
            if C_ActionBar.HasAction((page - 1) * SLOTS + button.index) then return true end
        end
    end
    local action = button.action
    return action ~= nil and C_ActionBar.HasAction(action) or false
end

--------------------------------------------------------------------------------
-- The pass
--------------------------------------------------------------------------------

-- Anchor a button inside its container, dx and dy in the button's own
-- units. One CENTER point replaces the template's.
local function place(button, dx, dy)
    if button.compactX == dx and button.compactY == dy then return end
    button.compactX, button.compactY = dx, dy
    button:SetPoint("CENTER", button.container, "CENTER", dx, dy)
end

--- Lay one bar's buttons: packed by line when the member is compact and no
--- grid shows, else every button at its slot. Runs at the end of the bar's
--- shown pass (mixins.lua) and after the cluster layout (clusters.lua); a
--- pass asked for in a fight is queued once per bar for regen.
function Compact.Apply(bar)
    if InCombatLockdown() then
        queue(function() Compact.Apply(bar) end, keyFor("camelotActionBars.compact.", bar))
        return
    end
    local buttons = bar.actionButtons
    if not buttons or #buttons == 0 then return end

    local align = bar.compactAlign
    local gridShown = (buttons[1]:GetAttribute("showgrid") or 0) > 0
    local packing = align ~= nil and not gridShown and not bar.noSpacers
    local showable = math.min(bar.numButtonsShowable or #buttons, #buttons)
    local stride = math.max(1, math.ceil(showable / math.max(1, bar.numRows or 1)))

    -- The pitch between slot centers in the container's units, which the
    -- button shares: the grid anchors each container at its width plus the
    -- padding past the last, with no other spacing.
    local pitch = 0
    if packing then
        pitch = (buttons[1].container:GetWidth() or 0)
            + math.max(bar.minButtonPadding or 2, bar.buttonPadding or 2)
    end
    local horizontal = bar.isHorizontal

    local held = {}
    for first = 1, showable, stride do
        local last = math.min(first + stride - 1, showable)
        local count = 0
        for i = first, last do
            held[i] = packing and filled(bar, buttons[i]) or false
            if held[i] then count = count + 1 end
        end
        local offset = 0
        if align == "end" then
            offset = stride - count
        elseif align == "center" then
            offset = (stride - count) / 2
        end
        local rank = 0
        for i = first, last do
            local delta = 0
            if held[i] then
                delta = offset + rank - (i - first)
                rank = rank + 1
            end
            if horizontal then
                place(buttons[i], delta * pitch, 0)
            else
                place(buttons[i], 0, -delta * pitch)
            end
        end
    end
    for i = showable + 1, #buttons do
        place(buttons[i], 0, 0)
    end
end

--- One phrase for the report: the mode, and the grid bits while any shows.
function Compact.Describe(bar)
    local align = bar.compactAlign
    if not align then return "compact off" end
    local word = (align == "start" and "start") or (align == "end" and "end") or "middle"
    local first = bar.actionButtons and bar.actionButtons[1]
    local bits = first and (first:GetAttribute("showgrid") or 0) or 0
    if bits > 0 then
        return string.format("compact %s, grid shown (bits %d)", word, bits)
    end
    return "compact " .. word
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

--- Every slot of a compact bar shows while Edit Mode is open. Called from
--- the enter and exit handlers in bars.lua, which fire in a fight too: the
--- grid call replays itself at regen.
function Compact.OnEditMode(entering)
    eachBar(function(bar)
        if entering then
            if bar.compactAlign then bar:SetShowGrid(true, Compact.REASON_EDITMODE) end
        else
            bar:SetShowGrid(false, Compact.REASON_EDITMODE)
        end
    end)
end

--------------------------------------------------------------------------------
-- The hooks
--------------------------------------------------------------------------------

-- A slot change on a page Action Bar 1 is not showing reaches no button's
-- own update, so the bar is laid out again when the slot is in the union.
local function onSlotChanged(_, slot)
    local bar = ActionBars.Frames and ActionBars.Frames.bar1
    slot = tonumber(slot)
    if not bar or not bar.compactAlign or not slot or slot < 1 then return end
    local page = math.floor((slot - 1) / SLOTS) + 1
    local union = false
    for _, p in ipairs(UNION_PAGES) do
        if p == page then union = true end
    end
    if not union then return end
    local button = bar.actionButtons[(slot - 1) % SLOTS + 1]
    if button and button.action == slot then return end
    Compact.Apply(bar)
end

-- The spellbook's and Quick Keybind's grid calls, forwarded to every bar.
local function forwardAll(show)
    return function(reason)
        if not reason then return end
        eachBar(function(bar) bar:SetShowGrid(show, reason) end)
    end
end

local installed = false

--- Once, from the bars' build: the global pair the spellbook and Quick
--- Keybind call on Blizzard's multibars, and the slot-change listener.
function Compact.Install()
    if installed then return end
    installed = true
    if MultiActionBar_ShowAllGrids then
        hooksecurefunc("MultiActionBar_ShowAllGrids", forwardAll(true))
    end
    if MultiActionBar_HideAllGrids then
        hooksecurefunc("MultiActionBar_HideAllGrids", forwardAll(false))
    end
    addon.Events.On(OWNER, "ACTIONBAR_SLOT_CHANGED", onSlotChanged)
end
