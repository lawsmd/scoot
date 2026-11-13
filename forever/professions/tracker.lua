--------------------------------------------------------------------------------
-- forever/professions/tracker.lua
-- The Professions Tracker (professions.lua holds the settings, data.lua the
-- read): one row per known profession, stacked, lowest level at the top
-- unless the order is turned.
--
-- A row is the profession's icon at the left, centered on the height of what
-- stands beside it: the name and the level on one line, the name at the
-- bar's left end and the level at its right, over the bar. The bar is
-- vanilla's skill bar, its art and its blue, filled by the level's progress
-- through its 75-point band. There is no header.
--
-- The icon wears the border the aura tracker's icons start with, through the
-- shared dispatcher, and Icon below is also what the skill-up toast draws
-- its icon with (skillups.lua). A left click on a row's icon opens that
-- profession's window, or closes it when it is already open, outside combat
-- and outside Edit Mode.
--
-- One holder, one Edit Mode box. While the tracker is off, or the character
-- knows no profession outside Edit Mode, the holder is hidden. The holder's
-- opacity follows the player's state: the Visibility tab's In Combat value
-- in combat, its With Target value with a target, full otherwise, in Edit
-- Mode, and under the cursor while Mouseover Mode is on.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Professions = addon.Professions
local Data = Professions.Data
local DB = addon.DB

local OWNER = "CamelotProfessionsTracker"
local LAYOUT_KEY = "professionsTracker"

local DEFAULT_POSITION = { point = "LEFT", x = 20, y = -60 }
local HUD_LEVEL = 15

-- Vanilla's skill bar (SkillStatusBarTemplate).
local BAR_FILL = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
local BAR_BORDER = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"
-- The border file's left cap, its middle run and the rows they stand in, as
-- texture coordinates; the right cap is the left one mirrored. The caps are
-- CAP_WIDTH wide on a border CAP_HEIGHT tall and scale with the bar.
local CAP_LEFT, CAP_RIGHT = 0.007843, 0.043137
local MID_LEFT, MID_RIGHT = 0.113726, 0.1490196
local BORDER_TOP, BORDER_BOTTOM = 0.193548, 0.774193
local CAP_WIDTH, CAP_HEIGHT = 9, 14
-- How far the border stands past the bar: above and below together, and at
-- each end on a CAP_HEIGHT border.
local BORDER_GROW, BORDER_OUT = 4, 3

local ICON_GAP = 5
local LABEL_GAP = 3
local NAME_GAP = 4
-- A level's room at the bar's right end, which the name stops short of.
local LEVEL_RESERVE = "000"
local ICON_CROP = 0.08
local ICON_STYLE = "blizzard"

-- What Edit Mode shows on a character with no profession. The icon is the
-- one the client's professions book draws for an empty slot.
local SAMPLE_ICON = "Interface\\Icons\\INV_Scroll_04"
local SAMPLES = {
    { skillLine = -1, name = "Profession", icon = SAMPLE_ICON, rank = 37, cap = 75, lower = 0, upper = 75 },
    { skillLine = -2, name = "Profession", icon = SAMPLE_ICON, rank = 112, cap = 150, lower = 75, upper = 150 },
}

local function get(key)
    return Professions.TrackerGet(key)
end

--------------------------------------------------------------------------------
-- The bordered icon
--------------------------------------------------------------------------------
-- A frame holding the icon texture, with a border frame over it. The frame
-- is the mask's owner, one per icon, since the dispatcher keeps one mask per
-- owner.

local Icon = {}
Professions.Icon = Icon

function Icon.Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, 1)
    frame.Texture = frame:CreateTexture(nil, "ARTWORK")
    frame.Texture:SetAllPoints()
    frame.Texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    frame.Border = CreateFrame("Frame", nil, frame)
    frame.Border:SetAllPoints()
    return frame
end

--- The texture, the size and the border. opts carries the border block's
--- values: enabled (false for none), style, thickness, insetH, insetV,
--- tintEnabled, tintColor.
function Icon.Paint(frame, texture, size, opts)
    opts = opts or {}
    frame:SetSize(size, size)
    frame.Texture:SetTexture(texture)

    local style = opts.style or ICON_STYLE
    local border = frame.Border
    if opts.enabled == false or style == "none" then
        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(border) end
        border:Hide()
        addon.ClearIconMask(frame.Texture)
        return
    end
    border:Show()
    local tinted = (opts.tintEnabled and type(opts.tintColor) == "table") and true or false
    addon.ApplyIconBorderStyle(border, style, {
        thickness = opts.thickness,
        insetH = tonumber(opts.insetH) or 0,
        insetV = tonumber(opts.insetV) or 0,
        tintEnabled = tinted,
        color = tinted and opts.tintColor or nil,
        simpleTint = true,
        styleAdjusts = true,
        expandClamp = 12,
        -- A rounded style rounds the icon to match, on this icon's own frame.
        maskTarget = frame.Texture,
        maskOwner = frame,
        maskWidth = size,
        maskHeight = size,
    })
end

local function iconOptions()
    return {
        enabled = get("icon.borderEnable") ~= false,
        style = get("icon.borderStyle"),
        thickness = get("icon.borderThickness"),
        insetH = get("icon.borderInsetH"),
        insetV = get("icon.borderInsetV"),
        tintEnabled = get("icon.borderTintEnable"),
        tintColor = get("icon.borderTintColor"),
    }
end

--------------------------------------------------------------------------------
-- Looks
--------------------------------------------------------------------------------

-- A text's face, size, style and color: the stored ones, else the font
-- object's own.
local function textLook(key)
    local face, size, r, g, b = Professions.TextObject(key)
    local stored = get(key .. ".fontFace")
    if stored and addon.ResolveFontFace then face = addon.ResolveFontFace(stored) end
    size = tonumber(get(key .. ".size")) or size
    local style = get(key .. ".style") or Professions.TEXT_STYLE
    local cr, cg, cb, _, source = addon.ResolveColorRGBA(get(key .. ".colorMode"), get(key .. ".color"), nil)
    if source == "custom" then r, g, b = cr, cg, cb end
    return { face = face, size = size, style = style, r = r, g = g, b = b }
end

local function styleText(fs, look)
    addon.ApplyFontStyle(fs, look.face, look.size, look.style)
    fs:SetTextColor(look.r, look.g, look.b)
end

local fillFallback, backFallback = {}, {}
do
    local c = Professions.BAR_COLOR
    fillFallback.fbR, fillFallback.fbG, fillFallback.fbB, fillFallback.fbA = c[1], c[2], c[3], 1
    backFallback.fbR, backFallback.fbG, backFallback.fbB, backFallback.fbA = 0, 0, 0, 1
end

local function paintBar(bar, height)
    bar:SetHeight(height)
    addon.Media.ApplyBarFill(bar, get("bar.texture"), BAR_FILL)
    local r, g, b = addon.ResolveColorRGBA(get("bar.colorMode"), get("bar.color"), fillFallback)
    bar:SetStatusBarColor(r, g, b)

    -- A key that names no texture leaves the background on the bar's rect
    -- for the plain fill.
    local back = bar.Background
    if not addon.Media.ApplyBarBackground(back, get("bar.bgTexture"), bar) then
        back:SetColorTexture(1, 1, 1, 1)
    end
    local br, bg, bb = addon.ResolveColorRGBA(get("bar.bgColorMode"), get("bar.bgColor"), backFallback)
    local opacity = tonumber(get("bar.bgOpacity")) or Professions.BACKGROUND_OPACITY
    back:SetVertexColor(br, bg, bb, math.max(0, math.min(100, opacity)) / 100)

    local capHeight = height + BORDER_GROW
    local ratio = capHeight / CAP_HEIGHT
    local capWidth = math.max(1, math.floor(CAP_WIDTH * ratio + 0.5))
    local out = BORDER_OUT * ratio
    bar.Left:SetSize(capWidth, capHeight)
    bar.Left:ClearAllPoints()
    bar.Left:SetPoint("LEFT", bar, "LEFT", -out, 0)
    bar.Right:SetSize(capWidth, capHeight)
    bar.Right:ClearAllPoints()
    bar.Right:SetPoint("RIGHT", bar, "RIGHT", out, 0)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local holder
local rows
local preview = false

local function createBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(BAR_FILL)

    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()

    bar.Left = bar:CreateTexture(nil, "OVERLAY")
    bar.Left:SetTexture(BAR_BORDER)
    bar.Left:SetTexCoord(CAP_LEFT, CAP_RIGHT, BORDER_TOP, BORDER_BOTTOM)
    bar.Right = bar:CreateTexture(nil, "OVERLAY")
    bar.Right:SetTexture(BAR_BORDER)
    bar.Right:SetTexCoord(CAP_RIGHT, CAP_LEFT, BORDER_TOP, BORDER_BOTTOM)
    bar.Middle = bar:CreateTexture(nil, "OVERLAY")
    bar.Middle:SetTexture(BAR_BORDER)
    bar.Middle:SetTexCoord(MID_LEFT, MID_RIGHT, BORDER_TOP, BORDER_BOTTOM)
    bar.Middle:SetPoint("TOPLEFT", bar.Left, "TOPRIGHT")
    bar.Middle:SetPoint("BOTTOMRIGHT", bar.Right, "BOTTOMLEFT")
    return bar
end

-- Opens a profession's window the way Blizzard's alert toasts do, or closes
-- it when that profession is the one open. OpenTradeSkill is unprotected; the
-- combat check keeps the click to quiet moments only.
local function openProfession(skillLine)
    if InCombatLockdown() then return end
    if type(skillLine) ~= "number" or skillLine <= 0 then return end
    local TS = C_TradeSkillUI
    if not (TS and TS.OpenTradeSkill) then return end
    if ProfessionsFrame and ProfessionsFrame:IsShown() and TS.GetBaseProfessionInfo and TS.CloseTradeSkill then
        local ok, info = pcall(TS.GetBaseProfessionInfo)
        if ok and type(info) == "table" and info.professionID == skillLine then
            pcall(TS.CloseTradeSkill)
            return
        end
    end
    pcall(TS.OpenTradeSkill, skillLine)
end

local function onIconMouseUp(self, button)
    if button ~= "LeftButton" or preview or not self:IsMouseOver() then return end
    openProfession(self.skillLine)
end

local function createRow()
    local row = CreateFrame("Frame", nil, holder)
    row:SetSize(1, 1)
    row:Hide()
    row.Icon = Icon.Create(row)
    row.Icon:EnableMouse(true)
    row.Icon:SetScript("OnMouseUp", onIconMouseUp)
    row.Bar = createBar(row)
    row.Name = row:CreateFontString(nil, "OVERLAY", Professions.TEXT_OBJECTS.textName)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Level = row:CreateFontString(nil, "OVERLAY", Professions.TEXT_OBJECTS.textLevel)
    row.Level:SetJustifyH("RIGHT")
    return row
end

-- The professions to draw, sorted. Edit Mode stands samples in for a
-- character with none.
local function listed()
    local list = {}
    local secondary = get("secondary") ~= false
    for _, entry in ipairs(Data.Current()) do
        if secondary or not entry.secondary then list[#list + 1] = entry end
    end
    if #list == 0 and preview then
        for i, sample in ipairs(SAMPLES) do list[i] = sample end
    end
    local highFirst = get("order") == "highFirst"
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            if highFirst then return a.rank > b.rank end
            return a.rank < b.rank
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.skillLine < b.skillLine
    end)
    return list
end

local looks

-- A pooled string can keep the font it was created with when it is styled
-- before it has drawn, so the shown rows' fonts are read back a frame on.
local verifyPending = false
local function verifyFonts()
    verifyPending = false
    if not (holder and holder:IsShown() and looks and addon.FontReadsAs) then return end
    for _, row in ipairs(rows.items) do
        if row:IsShown() then
            if addon.FontReadsAs(row.Name, looks.name.face, looks.name.size, looks.name.style) == false then
                styleText(row.Name, looks.name)
            end
            if addon.FontReadsAs(row.Level, looks.level.face, looks.level.size, looks.level.style) == false then
                styleText(row.Level, looks.level)
            end
        end
    end
end

-- The holder's opacity by the player's state (core/opacity.lua): combat
-- first, then a target, else full, a change of state carried there by the
-- state fade. Edit Mode and the mouseover reveal show the tracker at full
-- opacity, with no state, so it lands at once.
local opacityValues = {}
local function applyAlpha()
    if not (holder and holder:IsShown()) then return end
    local alpha, state = 1, nil
    if not (preview or addon.HoverFade.IsOver(holder)) then
        local keys = Professions.OPACITY_KEYS
        opacityValues[keys.combat] = get(keys.combat)
        opacityValues[keys.target] = get(keys.target)
        alpha, state = addon.Opacity.Resolve(opacityValues, keys)
    end
    holder:SetAlpha(addon.Opacity.Fade(holder, alpha, state))
end

-- Mouseover Mode watches the holder's rect (core/hoverfade.lua) while the
-- tracker is shown outside Edit Mode, and each change of answer takes the
-- opacity again.
local function applyHover()
    if holder and holder:IsShown() and not preview and get("mouseoverMode") == true then
        addon.HoverFade.Watch(holder, { frame = holder, onChange = applyAlpha })
    else
        addon.HoverFade.Unwatch(holder)
    end
end

local function refresh()
    if not holder then return end
    local list = Professions.TrackerOn() and listed() or {}
    if #list == 0 then
        rows:HideFrom(1)
        holder:Hide()
        applyHover()
        -- The next show writes its opacity at once, whatever state passed
        -- while the tracker was hidden.
        addon.Opacity.FadeForget(holder)
        return
    end

    local width = Professions.Clamp(get("width"), Professions.WIDTH)
    local barHeight = Professions.Clamp(get("barHeight"), Professions.BAR_HEIGHT)
    local iconSize = Professions.Clamp(get("iconSize"), Professions.ICON_SIZE)
    local spacing = Professions.Clamp(get("spacing"), Professions.SPACING)
    local showIcon = get("showIcon") ~= false
    local iconOpts = showIcon and iconOptions() or nil
    looks = { name = textLook("textName"), level = textLook("textLevel") }

    local barLeft = showIcon and (iconSize + ICON_GAP) or 0
    local labelHeight = math.max(looks.name.size, looks.level.size) + 1
    local blockHeight = labelHeight + LABEL_GAP + barHeight
    local rowHeight = math.max(showIcon and iconSize or 0, blockHeight)
    local barBottom = (rowHeight - blockHeight) / 2
    local reserve = addon.MeasureTextWidth
        and addon.MeasureTextWidth(LEVEL_RESERVE, looks.level.face, looks.level.size, looks.level.style)
        or (looks.level.size * #LEVEL_RESERVE * 0.6)
    local nameWidth = math.max(1, width - barLeft - reserve - NAME_GAP)

    holder:SetSize(width, #list * rowHeight + (#list - 1) * spacing)
    holder:Show()
    applyHover()
    applyAlpha()

    for i, entry in ipairs(list) do
        local row = rows:Get(i)
        row:SetSize(width, rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * (rowHeight + spacing))
        row:Show()

        row.Icon:SetShown(showIcon)
        row.Icon.skillLine = entry.skillLine
        if showIcon then
            row.Icon:ClearAllPoints()
            row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            Icon.Paint(row.Icon, entry.icon, iconSize, iconOpts)
        end

        local bar = row.Bar
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", barLeft, barBottom)
        bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, barBottom)
        paintBar(bar, barHeight)
        local span = entry.upper - entry.lower
        bar:SetValue(span > 0 and math.max(0, math.min(1, (entry.rank - entry.lower) / span)) or 1)

        -- Text, then the look: a string takes its font once it holds text
        -- and is shown.
        row.Name:SetText(entry.name)
        row.Name:ClearAllPoints()
        row.Name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, LABEL_GAP)
        row.Name:SetWidth(nameWidth)
        row.Level:SetText(tostring(entry.rank))
        row.Level:ClearAllPoints()
        row.Level:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, LABEL_GAP)
        styleText(row.Name, looks.name)
        styleText(row.Level, looks.level)
    end
    rows:HideFrom(#list + 1)

    if not verifyPending then
        verifyPending = true
        C_Timer.After(0, verifyFonts)
    end
end

Professions.RefreshTracker = refresh

--------------------------------------------------------------------------------
-- Edit Mode
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

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "CamelotProfessionsTracker", UIParent)
    holder:SetSize(Professions.WIDTH.default, 1)
    holder:SetPoint(DEFAULT_POSITION.point, DEFAULT_POSITION.x, DEFAULT_POSITION.y)
    addon.Strata.ApplyHUD(holder, HUD_LEVEL)
    holder:Hide()
    rows = addon.Pool.NewIndexed(createRow)
end

local registered = false
local function registerEditMode()
    if registered or not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true
    holder.editModeName = "Professions Tracker"
    addon.EditMode.RegisterPositionable(holder, {
        key = LAYOUT_KEY,
        default = DEFAULT_POSITION,
        restoreDefault = true,
        store = store,
        brand = {
            navKey = Professions.NAV_KEY, componentId = Professions.NAV_KEY,
            sectionKey = "tracker",
        },
    })
    addon.EditMode.OnEditMode(OWNER, {
        enter = function()
            preview = true
            refresh()
        end,
        exit = function()
            preview = false
            refresh()
        end,
    })
    if addon.EditMode.IsEditing() then
        preview = true
    end
end

--- What the tracker holds, for the professions dump (skillups.lua).
function Professions.TrackerState()
    return {
        built = holder ~= nil,
        shown = holder ~= nil and holder:IsShown(),
        alpha = holder and holder:GetAlpha() or 1,
        rows = rows and rows:Count() or 0,
        preview = preview,
    }
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

Data.OnChanged(refresh)

addon.Events.OnWorldEntered(function()
    build()
    registerEditMode()
    refresh()
end)

-- The opacity's edges, as the action bars take theirs
-- (forever/actionbars/visibility.lua): the pull one frame late so the state
-- reads settle, the regen a tenth of a second late, the target change and a
-- later world entry at once. SetAlpha is unprotected, so the combat edge
-- runs in combat.
addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", function() C_Timer.After(0, applyAlpha) end)
addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", function() C_Timer.After(0.1, applyAlpha) end)
addon.Events.On(OWNER, "PLAYER_TARGET_CHANGED", applyAlpha)
addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", applyAlpha)

-- After a profile switch the tracker reads the new profile's settings. A
-- resync pass keeps the profile it had. The new profile may have a feature on
-- that the old one had off, with no read in between, so the professions are
-- taken again first. The position is per profile too: a login can restore it
-- from the profile the database opened on, before the switch to the layout's
-- own, and no layout change follows to restore it again.
addon.Profiles.RegisterApplyStep("camelotProfessions", function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Data.Refresh()
    refresh()
    addon.EditMode.RestorePositionable(holder)
end, 40)
