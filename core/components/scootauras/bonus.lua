-- scootauras/bonus.lua - Bonus auras: trackers the addon defines whole
--
-- A bonus aura is built on the tracker code and carries what a tracker the
-- player builds cannot. Each is one entry in the registry below: a key, the
-- title and tooltip its settings section shows, and an `available` test the
-- settings page and both nav models read, so a host without what an aura
-- needs shows neither the aura nor an empty page.
--
-- All Cooldowns, the first: one group of icons, a cell per class ability
-- that is cooling, shown while the Dynamic Layout holds its dynamic state.
-- Every cell is a Spell Cooldown element set (cooldown.lua) painted by the
-- tracker chain through one settings component, so the swipe, the countdown
-- and the charge count are the tracker's own and legal in every secrecy
-- state. The group owns what the chain does not: which spells get a cell,
-- where the cells sit, and when the group shows.
--
--   container (UIParent, the Edit Mode drag unit: one row of cells)
--    +- cell (pooled)                 sized from the icon settings
--        +- element set (Cooldown.BuildVisual)
--
-- The container is a full row wide whatever is cooling, and the cells sit in
-- it centered, or at its left or right, by the Alignment setting.
--
-- The spells are the spellbook's: every skill line but General, active and
-- not off-spec, one per name so a book that lists each rank gives one cell.
-- Membership is Cooldown.IsCooling per spell, read on the two cooldown
-- events, on each cell's own completion script, and on a slow ticker while a
-- cell stands, since nothing fires when a cooldown runs out. Hidden, the
-- group holds no event and no ticker.
--
-- The state is one function, Evaluate: hidden; the sample row while Edit Mode
-- is open; live while the layout is dynamic; fading out after it. The
-- resolver's edge and the Edit Mode pair are what call it.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine
local Cooldown = SAU.Cooldown
local CopyTable = _G.CopyTable

local Bonus = {}
SAU.Bonus = Bonus

-- The settings page's nav key. A plain constant: it is never persisted, so
-- both hosts' nav models use the one value.
Bonus.NAV_KEY = "bonusAuras"

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

local defs = {}
local byKey = {}

local function Register(def)
    defs[#defs + 1] = def
    byKey[def.key] = def
end

--- The bonus auras this host can run, in registration order. Each is
-- { key, title, info, available }; the key is also the id its settings
-- component and its section on the page carry.
function Bonus.List()
    local out = {}
    for _, def in ipairs(defs) do
        if def.available() then out[#out + 1] = def end
    end
    return out
end

function Bonus.IsAvailable(key)
    local def = byKey[key]
    return def ~= nil and def.available() == true
end

function Bonus.AnyAvailable()
    for _, def in ipairs(defs) do
        if def.available() then return true end
    end
    return false
end

--- The settings component id of one bonus aura, nil for an unknown key.
function Bonus.ComponentId(key)
    return byKey[key] and SAU.GetComponentId(key) or nil
end

--------------------------------------------------------------------------------
-- All Cooldowns
--------------------------------------------------------------------------------

local KEY = "bonusAllCooldowns"
local TITLE = "All Cooldowns"
local OWNER = "aurasBonusAllCooldowns"
-- Beside the trackers' "t<id>" and the groups' "g<gid>" in the position store.
local POSITION_KEY = "bAllCooldowns"
-- Under the Personal Resource Display's dynamic place, with room for a
-- second row above the screen's edge.
local DEFAULT_POSITION = { point = "BOTTOM", x = 0, y = 40 }
local TICK_SECONDS = 1
-- The layout.lua gap between an icon and text set outside it.
local TEXT_GAP = 2
-- What the chain reads off a tracker record; a cell adds its spell.
local SHAPE = { kind = "cooldown", shape = "icon" }

local container, pool
local cells = {}       -- [spell id] = cell, one per cooling spell
local order = {}       -- the same cells in spellbook order
local samples = {}     -- the Edit Mode row's cells
local candidates = {}  -- spell ids in spellbook order
local candidatesStale = true
local handles = {}
local armed = false
local ticker
local passPending = false
local passToken = 0
local mode = "off"     -- "off", "edit", "live", "leaving"
local alphaNow = 0
local fade

local RequestPass, Evaluate

--------------------------------------------------------------------------------
-- Dynamic Layouts
--------------------------------------------------------------------------------

-- The engine, read at the moment of use: one host loads it and the other
-- does not, and both list this file.
local function Layouts()
    local DL = addon.DynamicLayouts
    if type(DL) ~= "table" or type(DL.Resolver) ~= "table" then return nil end
    return DL, DL.Resolver
end

local function Available()
    return Layouts() ~= nil
end

-- A profile where no frame takes part has no dynamic layout to pair with,
-- and its action bars stand where the group's default place is.
local function AnyFrameTakesPart(DL)
    if type(DL.Ids) ~= "function" or type(DL.IsParticipating) ~= "function" then return true end
    for _, id in ipairs(DL.Ids()) do
        if DL.IsParticipating(id) then return true end
    end
    return false
end

-- The feature on, the main lane answering dynamic, and a frame to follow it.
-- The resolver answers by its triggers alone, so the two others are asked
-- here.
local function Engaged()
    local DL, resolver = Layouts()
    if not DL then return false end
    local store = addon.DynamicLayoutsStore
    if type(store) ~= "table" or type(store.IsEnabled) ~= "function" or not store.IsEnabled() then
        return false
    end
    return resolver.Answer("main") == "dynamic" and AnyFrameTakesPart(DL)
end

local function Speed(direction)
    local DL = Layouts()
    local seconds = DL and type(DL.Speed) == "function" and DL.Speed(direction) or nil
    return type(seconds) == "number" and seconds or 0.5
end

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function Number(value, fallback)
    return tonumber(value) or fallback
end

local function Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- A tracker's settings, so the chain and the editor's Duration tab read the
-- keys they know, with four changes. The state opacity keys go: the group
-- has one opacity, and a component that declares them is restyled on every
-- combat and target edge. The host's look for a new icon tracker is folded
-- into the defaults, where a stamp would write the table at load. The
-- countdown starts smaller, for a row of icons. Desaturation starts off:
-- every icon here is cooling, so the gray would never lift.
local function BuildSettings()
    local settings = SAU.DefaultSettings()
    for _, key in pairs(addon.Opacity.Keys.InCombat) do
        settings[key] = nil
    end
    for _, stamp in ipairs(SAU.StartingValueStamps(SHAPE.kind, SHAPE.shape)) do
        for key, value in pairs(stamp) do
            if settings[key] then
                settings[key].default = type(value) == "table" and CopyTable(value) or value
            end
        end
    end
    settings.textSize.default = 16
    settings.cooldownDesaturate.default = false
    settings.bonusEnabled = { type = "addon", default = true }
    settings.bonusSpacing = { type = "addon", default = 4 }
    settings.bonusColumns = { type = "addon", default = 12 }
    settings.bonusAlign = { type = "addon", default = "center" }
    settings.bonusOpacity = { type = "addon", default = 50 }
    return settings
end

--- A cell's size, the step from one cell to the next on each axis, and the
-- row length, from settings alone. Text set outside the icon hangs past the
-- cell on one side; the step on that axis grows by the room a countdown
-- takes at its size, so the text sits in the gap and never on the next cell.
local function Metrics(db)
    local vis = SAU.ResolveVisibility(SHAPE, db)
    local w, h = SAU.IconDimensions(db, vis)
    w, h = math.max(w, 1), math.max(h, 1)
    local spacing = Clamp(Number(db.bonusSpacing, 4), 0, 100)
    local columns = Clamp(math.floor(Number(db.bonusColumns, 12)), 1, 40)
    local stepX, stepY = w + spacing, h + spacing
    if vis.showText and db.textPosition == "outside" then
        local size = Number(db.textSize, 16)
        local anchor = db.textOuterAnchor or "RIGHT"
        if anchor == "ABOVE" or anchor == "BELOW" then
            stepY = stepY + math.ceil(size * 1.2) + TEXT_GAP
        else
            local digits = db.textDecimal == true and 5 or 3
            stepX = stepX + math.ceil(size * 0.6 * digits) + TEXT_GAP
        end
    end
    return w, h, stepX, stepY, columns
end

--------------------------------------------------------------------------------
-- The spells
--------------------------------------------------------------------------------

-- The spells are SAU.WalkSpellbook's (core.lua): every active, castable
-- spell in the class's skill lines, one per name. A walk that throws keeps
-- the list it had and reads again on the next pass.
local function RebuildCandidates()
    local book = C_SpellBook
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo
        and book.GetSpellBookItemInfo) then
        candidatesStale = false
        return
    end
    local fresh = {}
    if pcall(SAU.WalkSpellbook, fresh) then
        candidates = fresh
        candidatesStale = false
    end
end

--------------------------------------------------------------------------------
-- Cells
--------------------------------------------------------------------------------

local function CreateCell()
    local cell = CreateFrame("Frame", nil, container)
    cell:Hide()
    cell.cooldown = Cooldown.BuildVisual(cell, function() RequestPass() end)
    cell.tracker = { kind = SHAPE.kind, shape = SHAPE.shape }
    cell.shim = { container = cell, elements = cell.cooldown.elements }
    return cell
end

-- Cooldown.Release hides the set's root, which is the cell, stops the
-- countdown and clears the swipe.
local function ResetCell(cell)
    Cooldown.Release(nil, cell)
    cell.tracker.spellId = nil
    cell.seen = nil
end

-- The tracker chain on one cell. It sizes nothing without a pool entry, so
-- the cell takes its size here; the icon then fills it.
local function StyleCell(cell, w, h)
    cell:SetSize(w, h)
    Cooldown.PaintElementSet(KEY, cell.tracker, cell.shim, cell.cooldown)
end

-- Rows fill left to right and hang below the first. A row shorter than the
-- container sits at its middle, its left or its right by the Alignment
-- setting, each row on its own count, so a last row of two centers under a
-- full one. The offset is whole, so no icon lands between pixels.
local function PlaceCells(list, db)
    local w, h, stepX, stepY, columns = Metrics(db)
    local width = (columns - 1) * stepX + w
    container:SetSize(width, h)
    local align = db.bonusAlign
    local total = #list
    for i, cell in ipairs(list) do
        local column = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local inRow = math.min(columns, total - row * columns)
        local slack = width - ((inRow - 1) * stepX + w)
        local offset = 0
        if align == "right" then
            offset = slack
        elseif align ~= "left" then
            offset = math.floor(slack / 2 + 0.5)
        end
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", container, "TOPLEFT", offset + column * stepX, -row * stepY)
    end
end

local function ReleaseLive()
    for spellId, cell in pairs(cells) do
        cells[spellId] = nil
        pool:Release(cell)
    end
    for i = #order, 1, -1 do order[i] = nil end
end

local function ReleaseSamples()
    for i = #samples, 1, -1 do
        pool:Release(samples[i])
        samples[i] = nil
    end
end

--------------------------------------------------------------------------------
-- The live pass
--------------------------------------------------------------------------------

local function UpdateTicker()
    local want = armed and next(cells) ~= nil
    if want and not ticker then
        ticker = C_Timer.NewTicker(TICK_SECONDS, function() RequestPass(true) end)
    elseif ticker and not want then
        ticker:Cancel()
        ticker = nil
    end
end

--- Membership, then values. A spell that started cooling takes a cell, styled
-- once and fed; one that stopped gives its cell back; the cells are placed
-- again only when the set changed. `repaint` feeds every standing cell too,
-- for an event that may have moved a cooldown; the ticker asks for
-- membership alone.
local function Pass(repaint)
    if mode ~= "live" then return end
    local db = SAU.GetDB(KEY)
    if not db then return end
    if candidatesStale then RebuildCandidates() end
    passToken = passToken + 1
    local w, h = Metrics(db)
    local changed = false
    local count = 0
    for _, spellId in ipairs(candidates) do
        if Cooldown.IsCooling(spellId) then
            local cell = cells[spellId]
            if not cell then
                cell = pool:Acquire()
                cell.tracker.spellId = spellId
                cells[spellId] = cell
                StyleCell(cell, w, h)
                Cooldown.PaintValues(KEY, cell.tracker, cell.cooldown, db)
                cell:Show()
                changed = true
            elseif repaint then
                Cooldown.PaintValues(KEY, cell.tracker, cell.cooldown, db)
            end
            cell.seen = passToken
            count = count + 1
            if order[count] ~= cell then
                order[count] = cell
                changed = true
            end
        end
    end
    for i = #order, count + 1, -1 do order[i] = nil end
    for spellId, cell in pairs(cells) do
        if cell.seen ~= passToken then
            cells[spellId] = nil
            pool:Release(cell)
            changed = true
        end
    end
    if changed then PlaceCells(order, db) end
    UpdateTicker()
end

-- One pass a frame, however many cooldown events arrive in it; the first
-- arrives on every GCD. A request that feeds values outranks one that does
-- not.
local passRepaint = false

function RequestPass(membershipOnly)
    if not armed then return end
    if not membershipOnly then passRepaint = true end
    if passPending then return end
    passPending = true
    C_Timer.After(0, function()
        passPending = false
        local repaint = passRepaint
        passRepaint = false
        Pass(repaint)
    end)
end

local function OnCooldownEvent()
    RequestPass()
end

-- The specialization event fires for group members too; only the player's
-- own moves the book.
local function OnBookEvent(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= nil and unit ~= "player" then return end
    candidatesStale = true
    RequestPass()
end

local BOOK_EVENTS = {
    "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED",
}

-- A client that does not know an event hands back an inert handle.
local function Arm()
    if armed then return end
    armed = true
    candidatesStale = true
    handles[#handles + 1] = addon.Events.On(OWNER, "SPELL_UPDATE_COOLDOWN", OnCooldownEvent)
    handles[#handles + 1] = addon.Events.On(OWNER, "SPELL_UPDATE_CHARGES", OnCooldownEvent)
    for _, event in ipairs(BOOK_EVENTS) do
        handles[#handles + 1] = addon.Events.On(OWNER, event, OnBookEvent)
    end
end

local function Disarm()
    if not armed then return end
    armed = false
    for i = #handles, 1, -1 do
        handles[i]:Off()
        handles[i] = nil
    end
    UpdateTicker()
end

--------------------------------------------------------------------------------
-- The Edit Mode row
--------------------------------------------------------------------------------

-- A cell as it looks mid-cooldown, with nothing running: the countdown is a
-- fixed number written here, so the font, size and place can be judged.
local function PaintSample(cell, db)
    local cdv = cell.cooldown
    if cdv.binding then pcall(cdv.binding.SetEnabled, cdv.binding, false) end
    if cdv.cd then pcall(cdv.cd.widget.Clear, cdv.cd.widget) end
    local stacks = cdv.stacks and cdv.stacks.widget
    if stacks then stacks:Hide() end
    local icon = cdv.icon and cdv.icon.widget
    if icon then pcall(icon.SetDesaturation, icon, 0) end
    local text = cdv.duration and cdv.duration.widget
    if text then
        if SAU.ResolveVisibility(cell.tracker, db).showText then
            -- ClearText first: the binding may have left an engine-written
            -- string on it.
            if text.ClearText then text:ClearText() end
            text:SetText(db.textDecimal == true and "12.3" or "12")
            text:Show()
        else
            text:Hide()
        end
    end
end

-- The book's first spells, half a row of them: the drag box is a full row
-- wide, so a short row shows where the Alignment setting puts the icons in it.
local function ShowSamples(db)
    if candidatesStale then RebuildCandidates() end
    local w, h, _, _, columns = Metrics(db)
    local count = math.min(#candidates, math.max(1, math.ceil(columns / 2)))
    for i = #samples, count + 1, -1 do
        pool:Release(samples[i])
        samples[i] = nil
    end
    for i = 1, count do
        local cell = samples[i]
        if not cell then
            cell = pool:Acquire()
            samples[i] = cell
        end
        cell.tracker.spellId = candidates[i]
        StyleCell(cell, w, h)
        PaintSample(cell, db)
        cell:Show()
    end
    PlaceCells(samples, db)
end

--------------------------------------------------------------------------------
-- The fade
--------------------------------------------------------------------------------

local function SetGroupAlpha(alpha)
    alphaNow = alpha
    container:SetAlpha(alpha)
end

local function StopFade()
    fade = nil
    container:SetScript("OnUpdate", nil)
end

-- Smoothstep, the layout's own easing, over the layout's own duration. The
-- script stands only while a fade runs.
local function OnFadeUpdate(_, elapsed)
    local f = fade
    if not f then
        container:SetScript("OnUpdate", nil)
        return
    end
    f.elapsed = f.elapsed + elapsed
    local p = f.elapsed / f.duration
    if p >= 1 then
        StopFade()
        SetGroupAlpha(f.to)
        if f.done then f.done() end
        return
    end
    SetGroupAlpha(f.from + (f.to - f.from) * (p * p * (3 - 2 * p)))
end

local function FadeTo(alpha, seconds, done)
    StopFade()
    if seconds <= 0 or alpha == alphaNow or not container:IsShown() then
        SetGroupAlpha(alpha)
        if done then done() end
        return
    end
    fade = { from = alphaNow, to = alpha, elapsed = 0, duration = seconds, done = done }
    container:SetScript("OnUpdate", OnFadeUpdate)
end

--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------

-- One setting written as the page writes it: the component's table, made on
-- the first write, then the restyle.
local function WriteSetting(key, value)
    local component = addon.Components and addon.Components[SAU.GetComponentId(KEY)]
    local db = component and addon:EnsureComponentDB(component)
    if not db then return end
    db[key] = value
    Evaluate(true, true)
end

-- The branded Edit Mode dialog's rows under the shared position row: the
-- page's Icon Size, Icon Spacing and Columns, over the same keys and ranges,
-- so the two surfaces cannot drift. Short labels: the dialog's label budget
-- is narrow, and a longer one runs under the track.
local function EditModeMirror()
    if not SAU.GetDB(KEY) then return nil end
    local function slider(label, key, low, high, fallback)
        return {
            kind = "slider", label = label,
            min = low, max = high, step = 1, precision = 0,
            get = function()
                local db = SAU.GetDB(KEY)
                return Number(db and db[key], fallback)
            end,
            set = function(v) WriteSetting(key, v) end,
        }
    end
    return {
        slider("Size", "iconSize", 16, 64, 32),
        slider("Spacing", "bonusSpacing", 0, 20, 4),
        slider("Columns", "bonusColumns", 1, 20, 12),
    }
end

-- Built on the first state that shows it. The box stays live in the dynamic
-- view of Edit Mode (dynamicViewMember): the group is on screen only in the
-- dynamic layout, so that view is where it is placed against the rest.
local function EnsureContainer()
    if container then return end
    container = CreateFrame("Frame", addon.Brand .. "BonusAllCooldowns", UIParent)
    addon.Strata.ApplyHUD(container, 25)
    container:SetSize(32, 32)
    container:SetPoint(DEFAULT_POSITION.point, UIParent, DEFAULT_POSITION.point,
        DEFAULT_POSITION.x, DEFAULT_POSITION.y)
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    container:SetAlpha(0)
    container:Hide()
    container.editModeName = TITLE
    addon.RegisterPetBattleFrame(container)

    pool = addon.Pool.New(CreateCell, ResetCell)

    addon.EditMode.RegisterPositionable(container, {
        key = POSITION_KEY,
        default = DEFAULT_POSITION,
        store = { get = Engine._GetStoredPosition, set = Engine.SavePosition },
        restoreDefault = true,
        dynamicViewMember = true,
        brand = {
            navKey = Bonus.NAV_KEY, componentId = Bonus.NAV_KEY, sectionKey = KEY,
            mirror = EditModeMirror,
        },
    })
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local function Conceal(snap)
    Disarm()
    -- A fade already on its way out keeps its clock.
    if mode == "leaving" and fade and not snap then return end
    if mode == "live" or mode == "leaving" then
        mode = "leaving"
        FadeTo(0, snap and 0 or Speed("out"), function()
            if mode ~= "leaving" then return end
            mode = "off"
            ReleaseLive()
            container:Hide()
        end)
        return
    end
    mode = "off"
    StopFade()
    ReleaseLive()
    ReleaseSamples()
    SetGroupAlpha(0)
    container:Hide()
end

local function ShowEditRow(db)
    Disarm()
    mode = "edit"
    StopFade()
    ReleaseLive()
    ShowSamples(db)
    SetGroupAlpha(1)
    container:Show()
end

-- Cells left by a fade that had not landed stay; the pass keeps the ones
-- still cooling.
local function ShowLive(db, restyle, snap)
    local entering = mode ~= "live"
    if entering then
        ReleaseSamples()
        mode = "live"
        Arm()
        container:Show()
    end
    if entering or restyle then
        local w, h = Metrics(db)
        for _, cell in pairs(cells) do
            StyleCell(cell, w, h)
        end
        PlaceCells(order, db)
    end
    Pass(true)
    local target = Clamp(Number(db.bonusOpacity, 50), 0, 100) / 100
    if entering then
        FadeTo(target, snap and 0 or Speed("in"))
    elseif fade then
        fade.to = target
    else
        SetGroupAlpha(target)
    end
end

--- The one state function. `restyle` repaints the standing cells for a
-- settings change; `snap` lands the alpha with no fade, for the first
-- resolution and for Edit Mode's edges, as the layout's own frames do.
function Evaluate(restyle, snap)
    local db = Available() and SAU.IsModuleActive() and SAU.GetDB(KEY) or nil
    if not db or db.bonusEnabled == false then
        if container then Conceal(true) end
        return
    end
    if addon.EditMode.IsEditing() then
        EnsureContainer()
        ShowEditRow(db)
    elseif Engaged() then
        EnsureContainer()
        ShowLive(db, restyle, snap)
    elseif container then
        Conceal(snap)
    end
end

-- Both lanes publish; the group follows the main one.
local function OnLayoutEdge(_, info)
    if type(info) == "table" then
        if info.lane ~= nil and info.lane ~= "main" then return end
        Evaluate(false, info.initial == true or info.origin == "editmode")
        return
    end
    Evaluate(false, false)
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

Register({
    key = KEY,
    title = TITLE,
    info = "While your Dynamic Layout is engaged, this icon group shows the remaining cooldown on all "
        .. "class abilities currently on cooldown. Meant for pairing with the default Dynamic Layout "
        .. "arrangement, for observing cooldowns while your Action Bars are off-screen/hidden.",
    available = Available,
})

-- Registered at init so the component links to its persisted table with the
-- trackers'. Gated inline, as theirs is: the category is a host token.
addon:RegisterComponentInitializer(function()
    if not (SAU.IsModuleActive() and Available()) then return end
    addon:RegisterComponent(addon.ComponentPrototype:New({
        id = SAU.GetComponentId(KEY),
        name = addon.Brand .. "Auras: " .. TITLE,
        settings = BuildSettings(),
        -- Beside the trackers' styling in the account-wide store.
        GetContainer = SAU.GetStylingContainer,
        ApplyStyling = function() Evaluate(true, true) end,
    }))
end)

-- The resolver's first resolution lands after the world entry and arrives as
-- an edge. A component linked before the saved table was readable sits on its
-- defaults, so it links again here.
addon.Events.OnWorldEntered(function()
    local _, resolver = Layouts()
    if not (resolver and SAU.IsModuleActive()) then return end
    local component = addon.Components and addon.Components[SAU.GetComponentId(KEY)]
    if component and addon.IsComponentUnconfigured(component) then
        addon:LinkComponent(component)
    end
    resolver.Subscribe(OWNER, OnLayoutEdge)
    addon.EditMode.OnEditMode(OWNER, {
        enter = function() Evaluate(false, true) end,
        exit = function() Evaluate(false, true) end,
    })
    Evaluate(false, true)
end)
