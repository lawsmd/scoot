--------------------------------------------------------------------------------
-- forever/objectivetracker/cards.lua
-- The Camelot style of Current Objectives: one upright card per current quest
-- (card.lua), in a row centered on one anchor at the top of the screen, or
-- in a column hanging from it.
--
-- The quests are the Classic style's: current.lua decides which quests are
-- current, in watch-list order, and tells this file when the set changes.
-- With this style on, current.lua's Current twin draws nothing, so the
-- Classic pane stays empty and hidden, and a current quest still leaves the
-- main tracker.
--
-- Card i of n sits at (i - (n + 1) / 2) * (width + spacing) from the anchor:
-- one card on it, two either side of it, three with the middle one on it.
-- A new card fades in at its place over the Fade setting's length while the
-- others slide to theirs; a card whose quest stops being current fades out
-- where it stands. One OnUpdate drives both and stops when nothing moves.
--
-- The Layout setting puts the cards in a column instead: centered under the
-- anchor, each as tall as its own content, Spacing apart, in watch order top
-- to bottom. A card's place there waits for the heights above it, which the
-- client lays out a frame after the render, so a card new to the column stays
-- clear until fitRow gives it a place. Switching Layout slides the cards from
-- one arrangement to the other.
--
-- The container takes no mouse input and the cards carry no quest item
-- button: the button is a secure frame and would bring the combat rules onto
-- a frame that has none. The drag in Edit Mode is on LibEditMode's selection
-- box, a child of the container, so the container is hidden whenever the
-- style is Classic and its box goes with it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style
local DB = addon.DB

local Cards = {}
OT.Cards = Cards

local OWNER = "camelotObjectiveTrackerCards"
local FRAME_NAME = "CamelotCurrentObjectiveCards"
local KEY = "currentObjectivesCards"
local NAV_KEY = "currentObjectives"
local LABEL = "Current Objective Cards"
local DEFAULT = { point = "TOP", x = 0, y = -40 }
local SLIDE_RATE = 12  -- per second: a slide is 95% there in a quarter second
local INSTANT = { install = true, apply = true, ["editmode enter"] = true, ["editmode exit"] = true }

-- Edit Mode's preview when no quest is current: a count, a check and a timer.
local SAMPLES = {
    { questID = -1, title = "Bear Necessities", level = 12, color = { 0.25, 0.75, 0.25 },
      rows = {
          { kind = "bar", index = 1, name = "Bear Claw", have = 6, need = 10 },
          { kind = "check", index = 2, name = "Mother Bear slain" },
      } },
    { questID = -2, title = "The Lost Foreman", level = 14, tag = "Elite", color = { 1, 1, 0 },
      rows = {
          { kind = "check", index = 1, name = "Find the foreman in the mine", done = true },
          { kind = "bar", index = 2, name = "Kobold Candle", have = 3, need = 5 },
      } },
    { questID = -3, title = "Against the Tide", level = 13, color = { 1, 0.5, 0.25 },
      rows = {
          { kind = "check", index = 1, name = "Light the lighthouse beacon" },
      },
      timer = { left = 272, total = 600 } },
}

local container
local shown = {}    -- questID -> card, the cards in the row now
local leaving = {}  -- card -> true, fading out where they stand
local order = {}    -- questIDs in the row, left to right
local extra = 0     -- current quests past Max Cards
local previewing = false
local lastWhy = "never built"
local cardPool
local driver
local ticker

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

--- Whether the cards draw the current set: the style, the pane's switch and
--- the tracker feature all on.
function Cards.Active()
    return Style.CurrentStyle() == "camelot"
        and OT.Current ~= nil and OT.Current.Enabled()
        and OT.IsEnabled ~= nil and OT.IsEnabled()
end

local function editing()
    local EM = addon.EditMode
    return EM and EM.IsEditing and EM.IsEditing() or false
end

local function fadeSeconds()
    return Style.FadeSeconds()
end

local function slotX(i, n)
    return (i - (n + 1) / 2) * (Style.CardWidth() + Style.CardSpacing())
end

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

local function column()
    return Style.CardLayout() == "column"
end

-- A card with no y is new to the column and waits, clear, for fitRow.
local function place(card)
    card:ClearAllPoints()
    card:SetPoint("TOP", container, "TOP", card.x, card.y or 0)
    card:SetAlpha(card.y and card.alpha * Style.CardOpacity() or 0)
end

local function approach(value, target, elapsed)
    local d = target - value
    if math.abs(d) < 0.5 then return target, false end
    return value + d * math.min(1, elapsed * SLIDE_RATE), true
end

local function step(card, elapsed, rate, wantAlpha)
    if not card.y then
        place(card)
        return wantAlpha > 0  -- one leaving before its fit is done
    end
    local moving, movingY
    card.x, moving = approach(card.x, card.targetX, elapsed)
    card.y, movingY = approach(card.y, card.targetY or card.y, elapsed)
    moving = moving or movingY
    if card.alpha ~= wantAlpha then
        if wantAlpha > card.alpha then
            card.alpha = math.min(wantAlpha, card.alpha + rate)
        else
            card.alpha = math.max(wantAlpha, card.alpha - rate)
        end
        moving = moving or card.alpha ~= wantAlpha
    end
    place(card)
    return moving
end

local function onUpdate(self, elapsed)
    local seconds = fadeSeconds()
    local rate = seconds > 0 and elapsed / seconds or 1
    local busy = false
    for _, card in pairs(shown) do
        if step(card, elapsed, rate, 1) then busy = true end
    end
    for card in pairs(leaving) do
        if step(card, elapsed, rate, 0) then
            busy = true
        else
            leaving[card] = nil
            cardPool:Release(card)
        end
    end
    if not busy then
        self:Hide()
        if next(shown) == nil then container:Hide() end
    end
end

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------

local function tick()
    local running = false
    for _, card in pairs(shown) do
        if card:RenderFooter() then running = true end
    end
    if not running and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, tick)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function sampleInfo(sample)
    local info = {}
    for k, v in pairs(sample) do info[k] = v end
    if sample.timer then
        info.timer = { left = sample.timer.left, total = sample.timer.total, at = GetTime() }
    end
    return info
end

local function releaseAll()
    for _, card in pairs(shown) do cardPool:Release(card) end
    for card in pairs(leaving) do cardPool:Release(card) end
    wipe(shown)
    wipe(leaving)
    wipe(order)
    extra = 0
end

-- The questIDs the row draws now, and the infos for them.
local function wanted()
    local list = OT.Current.List()
    if #list == 0 and editing() then
        previewing = true
        local ids, infos = {}, {}
        for i, sample in ipairs(SAMPLES) do
            ids[i] = sample.questID
            infos[sample.questID] = sampleInfo(sample)
        end
        return ids, infos
    end
    previewing = false
    local infos = {}
    for _, questID in ipairs(list) do infos[questID] = OT.Card.Read(questID) end
    return list, infos
end

--- A frame after a rebuild, once the client has laid the text out: every
--- card in the row takes the tallest one's height, up to the playing card's
--- 5:7, past which that card's last rows fade. In the column each card takes
--- its own height, to the same cap, and its place under the ones above.
local fitQueued = false

local function fitColumn(cap)
    local y, spacing = 0, Style.CardSpacing()
    for _, questID in ipairs(order) do
        local card = shown[questID]
        if card then
            local want = card:Measure()
            local height = math.min(want or card:GetHeight() or cap, cap)
            card:Fit(height, want)
            card.targetY = -y
            if not card.y then card.y = card.targetY end
            y = y + height + spacing
        end
    end
    container:SetHeight(math.max(1, y - spacing))
    driver:Show()
end

local function fitRow()
    fitQueued = false
    if not container then return end
    local width = Style.CardWidth()
    local cap = OT.Card.MaxHeight(width)
    if column() then return fitColumn(cap) end
    local tallest, wants = 0, {}
    for _, card in pairs(shown) do
        local want = card:Measure()
        if want then
            wants[card] = want
            tallest = math.max(tallest, want)
        end
    end
    if tallest == 0 then return end
    local height = math.min(tallest, cap)
    for card, want in pairs(wants) do card:Fit(height, want) end
    container:SetHeight(height)
end

local function queueFit()
    if fitQueued then return end
    fitQueued = true
    C_Timer.After(0, fitRow)
end

--- Re-reads the current set and lays the row out. Cards new to the row
--- fade in at their place; the rest slide.
function Cards.Rebuild(why)
    lastWhy = why or "?"
    if not container then return end
    if not Cards.Active() then
        releaseAll()
        container:Hide()
        return
    end

    local ids, infos = wanted()
    local max = Style.CardMax()
    extra = math.max(0, #ids - max)
    local n = math.min(#ids, max)
    local width = Style.CardWidth()
    local stacked = column()
    -- Login, Edit Mode's edges and a settings change cut; the rest fade.
    local instant = fadeSeconds() <= 0 or INSTANT[lastWhy] == true

    local keep = {}
    for i = 1, n do keep[ids[i]] = true end
    for questID, card in pairs(shown) do
        if not keep[questID] then
            shown[questID] = nil
            if instant then
                cardPool:Release(card)
            else
                leaving[card] = true
            end
        end
    end

    wipe(order)
    local timed = false
    for i = 1, n do
        local questID = ids[i]
        local card = shown[questID]
        local x = stacked and 0 or slotX(i, n)
        if not card then
            card = cardPool:Acquire()
            card.x = x
            card.y = not stacked and 0 or nil
            card.alpha = instant and 1 or 0
            shown[questID] = card
        end
        card.targetX = x
        -- The column's y waits for fitRow; the row's is the anchor's.
        if not stacked then card.targetY = 0 end
        card:SetCardWidth(width)
        card:SetScale(1)
        card:Show()
        card:Render(infos[questID])
        if infos[questID].timer then timed = true end
        place(card)
        order[i] = questID
    end

    if stacked then
        container:SetWidth(width)
    else
        container:SetWidth(math.max(width, n * width + math.max(0, n - 1) * Style.CardSpacing()))
    end
    local more = container.More
    more:ClearAllPoints()
    if stacked then
        more:SetPoint("TOP", container, "BOTTOM", 0, -4)
    else
        more:SetPoint("LEFT", container, "RIGHT", 8, 0)
    end
    more:SetShown(extra > 0)
    container.More:SetText(extra > 0 and ("+" .. extra) or "")
    container:SetShown(n > 0 or next(leaving) ~= nil)
    if timed then startTicker() end
    driver:Show()
    queueFit()
end

local rebuildQueued = false

--- One rebuild on the next frame, however many changes asked for it.
function Cards.Queue(why)
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0, function()
        rebuildQueued = false
        Cards.Rebuild(why)
    end)
end

--- The pages' apply and a style switch: the look, then the row. A Layout
--- switch passes "layout", which slides where "apply" cuts.
function Cards.Apply(why)
    if not container then return end
    container:SetScale(Style.CardScale())
    if OT.Dynamic then OT.Dynamic.Reassert(container) end
    Cards.Rebuild(why or "apply")
end

--- The Layout setting's write, from the page and the Edit Mode dialog.
function Cards.SetLayout(v)
    DB.Set(Style.PanePath(Style.CARDS, "layout"), v == "column" and "column" or "row")
    Cards.Apply("layout")
end

--- For flash.lua: the row drawing a quest's objective, and the card it sits
--- on, or nil.
function Cards.Row(questID, index)
    local card = shown[questID]
    if not card then return nil end
    local row = card:RowFor(index)
    if not row then return nil end
    return row, card
end

--------------------------------------------------------------------------------
-- Edit Mode and Dynamic Layouts
--------------------------------------------------------------------------------

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}

-- A drop is stored as the row's top center, whatever point LibEditMode chose
-- from where it fell: the row's width changes with its cards, and any other
-- point would move the center with it.
local function toTopCenter(frame)
    local left, right, top = frame:GetLeft(), frame:GetRight(), frame:GetTop()
    if not (left and right and top) then return end
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    local x = (left + right) / 2 - UIParent:GetWidth() * ratio / 2
    local y = top - UIParent:GetHeight() * ratio
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", x, y)
end

local function applyPosition(frame, point, x, y, reason)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
    if reason == "drop" then toTopCenter(frame) end
    if reason == "restore" and addon.DynamicLayouts and addon.DynamicLayouts.Reassert then
        addon.DynamicLayouts.Reassert(KEY)
    end
    return false
end

local function basePosition()
    local entry = DB.GetLayout(KEY)
    local layoutName = addon.EditMode.GetActiveLayoutName()
    local pos = entry and entry.positions and layoutName and entry.positions[layoutName]
    if pos and pos.point then return pos.point, pos.x or 0, pos.y or 0 end
    return DEFAULT.point, DEFAULT.x, DEFAULT.y
end

local function slider(label, range, get, set, scaleBy)
    scaleBy = scaleBy or 1
    return {
        kind = "slider", label = label,
        min = range.min * scaleBy, max = range.max * scaleBy, step = range.step * scaleBy,
        precision = 0,
        get = function() return math.floor(get() * scaleBy + 0.5) end,
        set = function(v)
            set((tonumber(v) or range.default * scaleBy) / scaleBy)
            Cards.Apply()
        end,
    }
end

local function mirror()
    local function setter(key)
        return function(v) DB.Set(Style.PanePath(Style.CARDS, key), v) end
    end
    return {
        { kind = "selector", label = "Layout", values = Style.CARD_LAYOUTS,
          order = Style.CARD_LAYOUT_ORDER, get = Style.CardLayout, set = Cards.SetLayout },
        slider("Card Width", Style.CARD_WIDTH, Style.CardWidth, setter("width")),
        slider("Scale", Style.SCALE, Style.CardScale, setter("scale"), 100),
        slider("Opacity", Style.OPACITY, function() return Style.CardOpacity() * 100 end,
            function(v) DB.Set(Style.PanePath(Style.CARDS, "opacity"), v) end),
    }
end

local registered = false

local function registerEditMode()
    if registered or not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true
    container.editModeName = LABEL
    addon.EditMode.RegisterPositionable(container, {
        key = KEY,
        default = DEFAULT,
        restoreDefault = true,
        store = store,
        apply = applyPosition,
        brand = { navKey = NAV_KEY, componentId = NAV_KEY, mirror = mirror },
    })

    local DL = addon.DynamicLayouts
    if DL and DL.Register then
        DL.Register({
            id = KEY,
            label = "Current Objectives (Camelot)",  -- the dynamic view's panel lists both styles
            frame = container,
            tier = "plain",
            channels = { "opacity", "scale", "position" },
            base = {
                opacity = function() return 1 end,
                scale = function() return Style.CardScale() end,
                position = basePosition,
            },
            apply = {
                position = function(f, point, x, y)
                    f:ClearAllPoints()
                    f:SetPoint(point, UIParent, point, x, y)
                end,
            },
        })
    end

    -- The preview comes in with Edit Mode and goes with it.
    addon.EditMode.OnEditMode(OWNER, {
        enter = function() Cards.Rebuild("editmode enter") end,
        exit = function() Cards.Rebuild("editmode exit") end,
    })
end

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

local function create()
    container = CreateFrame("Frame", FRAME_NAME, UIParent)
    container:SetSize(Style.CardWidth(), 1)
    container:SetPoint(DEFAULT.point, UIParent, DEFAULT.point, DEFAULT.x, DEFAULT.y)
    container:SetClampedToScreen(true)
    container:EnableMouse(false)
    addon.Strata.ApplyHUD(container, 5)
    container:Hide()

    local more = container:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    more:Hide()
    container.More = more

    cardPool = addon.Pool.New(function() return OT.Card.Create(container) end, function(card)
        card:Hide()
        card.info, card.questID = nil, nil
    end)

    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", onUpdate)
end

local installed = false

--- Once, from Current.Install, after the routing is on.
function Cards.Install()
    if installed or not OT.Current then return end
    installed = true
    create()
    container:SetScale(Style.CardScale())
    OT.Current.OnChanged(function() Cards.Queue("current set") end)
    addon.Events.On(OWNER, "QUEST_LOG_UPDATE", function() Cards.Queue("log") end)
    addon.Events.On(OWNER, "PLAYER_MONEY", function() Cards.Queue("money") end)
    registerEditMode()
    Cards.Rebuild("install")
end

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

function Cards.Dump(push)
    push("cards: style %s, layout %s, active %s, installed %s, shown %s, preview %s, %d leaving, %d past max, last build %s",
        Style.CurrentStyle(), Style.CardLayout(), tostring(Cards.Active()), tostring(installed),
        tostring(container ~= nil and container:IsShown()), tostring(previewing),
        (function() local c = 0 for _ in pairs(leaving) do c = c + 1 end return c end)(),
        extra, lastWhy)
    for i, questID in ipairs(order) do
        local card = shown[questID]
        if card then
            local kinds, overflow = card:Describe()
            push("  %d. %-6d %-36s x %.0f, y %s, alpha %.2f, rows: %s%s", i, questID,
                card.info and card.info.title or "?", card.x or 0,
                card.y and string.format("%.0f", card.y) or "unplaced", card.alpha or 0, kinds,
                overflow and " (overflow)" or "")
        end
    end
end
