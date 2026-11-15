--------------------------------------------------------------------------------
-- notes/core.lua - Notes: text windows the player makes, writes and deletes
-- on screen.
--
-- A note is a record { id, text, collapsed } in a list the host keeps
-- (addon.NotesHost: core/noteshost.lua in one addon, forever/notes/host.lua
-- in the other). "Create Note" on the minimap button's right-click menu makes
-- one. The text is markdown (core/markdown.lua): render.lua draws it as rows,
-- editor.lua is the pencil's editing mode.
--
-- A note draws in a shell, a frame from a pool: the pet battle hide keeps
-- every frame it is handed, so a deleted note's shell is hidden and given to
-- the next note. The player drags a note by its title row or any empty part
-- of it, at any time; a note has one place, stored by its id. Notes are not
-- Edit Mode frames.
--
-- Fonts come from the Tooltip component. The window (backdrop, border, title
-- plate) is the five look keys, drawn through core/panelart.lua.
--------------------------------------------------------------------------------

local _, addon = ...

local N = {}
addon.Notes = N

N.MAX_WIDTH = 300
N.MIN_WIDTH = 120
N.PADDING = 12
local PADDING = N.PADDING
local TITLE_TOP = 7          -- above the title text, inside the title row
local TITLE_BOTTOM = 5       -- under it
local TITLE_SHRINK = 2       -- the title draws this far under the Tooltip's title size
local TITLE_MIN_SIZE = 9
local BODY_GAP = 6           -- title row to the body
local TITLE_MAX_LETTERS = 60
local BUTTON_SIZE = 14
local BUTTON_GAP = 4
local BUTTONS_WIDTH = BUTTON_SIZE * 2 + BUTTON_GAP + 6
local DEFAULT_TITLE = "Note"

-- Default tooltip background color (matches Blizzard's TOOLTIP_DEFAULT_BACKGROUND_COLOR)
local DEFAULT_BG_COLOR = { 0.09, 0.09, 0.19 }

-- The pencil is a file, the guild roster's note glyph: the one pencil atlas
-- (Pencil-Icon) is drawn on a round button, which stood out beside the bare X.
local PENCIL_ATLAS = { "Interface\\Buttons\\UI-GuildButton-PublicNote-Up" }
local DONE_ATLAS = { "common-icon-checkmark", "checkmark-minimal" }
local DELETE_ATLAS = { "common-icon-delete", "common-icon-redx", "common-icon-yellowx" }

local shells = {}      -- every shell made this session, by slot
local byId = {}        -- note id -> the shell that holds it
local pool

--------------------------------------------------------------------------------
-- The component, the host and the Tooltip's fonts
--------------------------------------------------------------------------------

function N.DB()
    local comp = addon.Components and addon.Components["notes"]
    return comp and comp.db
end

local function Host()
    return addon.NotesHost
end

local function TooltipDB()
    local comp = addon.Components and addon.Components["tooltip"]
    return comp and comp.db
end

local function TextConfig(key, defaultSize)
    local db = TooltipDB()
    local cfg = db and type(db[key]) == "table" and db[key] or {}
    return addon.ResolveFontFace(cfg.fontFace or "FRIZQT__"), tonumber(cfg.size) or defaultSize,
        cfg.style or "OUTLINE"
end

--- The title's and the body's face, size and style.
function N.TitleFont() return TextConfig("textTitle", 14) end
function N.BodyFont() return TextConfig("textEverythingElse", 12) end

local function Color(value, r, g, b)
    if type(value) == "table" then
        return value[1] or r, value[2] or g, value[3] or b, value[4] or 1
    end
    return r, g, b, 1
end

function N.HeaderColor()
    local db = N.DB()
    return Color(db and db.headerColor, 0.1, 1.0, 0.1)
end

function N.BodyColor()
    local db = N.DB()
    return Color(db and db.bodyColor, 1, 1, 1)
end

-- The first name the client can draw. A name that is a path is a file.
local function SetAtlasFrom(texture, names)
    -- A file drawn after an atlas would keep the atlas's texture coordinates.
    texture:SetTexCoord(0, 1, 0, 1)
    for _, name in ipairs(names) do
        if name:find("\\", 1, true) then
            texture:SetTexture(name)
            return
        end
        if pcall(texture.SetAtlas, texture, name) and texture:GetAtlas() then return end
    end
end

--------------------------------------------------------------------------------
-- The look: backdrop, border and title plate (core/panelart.lua)
--------------------------------------------------------------------------------

local function Fraction(percent, default)
    local value = tonumber(percent) or default
    return math.max(0, math.min(100, value)) / 100
end

local function ApplyBorderTint(nineSlice)
    if not nineSlice or not nineSlice.SetBorderColor then return end
    local db = TooltipDB()
    if db and db.borderTintEnable then
        local c = db.borderTintColor or { 1, 1, 1, 1 }
        nineSlice:SetBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
        nineSlice:SetBorderColor(1, 1, 1, 1)
    end
end

-- One set of values for every note. "solid", "tooltip" and "none" are this
-- file's own; any other key is an entry of the art catalog. An art key this
-- client cannot draw paints as "solid", "tooltip" or "none" does.
--   windowBackdropTexture    "solid" | a "window" key
--   windowBorderStyle        "tooltip" | "none" | a "border" key
--   titleBarBackdropTexture  "none" | a "title" key, drawn behind the title row
-- An art border draws at the title bar's opacity, as the damage meter's does.
local function ApplyLook(shell, db)
    local PanelArt = addon.PanelArt
    local nineSlice = shell._nineSlice
    local windowAlpha = Fraction(db.windowBackdropOpacity, 100)
    local titleAlpha = Fraction(db.titleBarBackdropOpacity, 100)
    local borderKey = db.windowBorderStyle or "tooltip"

    local borderArt = PanelArt.Apply(shell, "border", borderKey, titleAlpha)
    local titleArt = PanelArt.Apply(shell._titleRegion, "title", db.titleBarBackdropTexture,
        titleAlpha, nil, borderArt)
    local windowArt = PanelArt.Apply(shell, "window", db.windowBackdropTexture, windowAlpha,
        titleArt and shell._titleRegion or nil)

    local bg = shell._bgColor
    local tooltipBorder = borderKey ~= "none" and not borderArt
    nineSlice:SetShown(tooltipBorder)
    if tooltipBorder then
        nineSlice:SetCenterColor(bg[1], bg[2], bg[3], windowArt and 0 or windowAlpha)
        ApplyBorderTint(nineSlice)
    end
    local flat = not tooltipBorder and not windowArt
    shell._flatBg:SetShown(flat)
    if flat then
        shell._flatBg:SetColorTexture(bg[1], bg[2], bg[3], windowAlpha)
    end
end

--------------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------------

local function StartDrag(shell)
    if not shell._record then return end
    shell._dragging = true
    shell:StartMoving()
end

-- The dropped note is re-anchored by its top left corner, so text added
-- later grows it down and to the right, and that place is stored.
local function StopDrag(shell)
    if not shell._dragging then return end
    shell._dragging = nil
    shell:StopMovingOrSizing()
    local left, top = shell:GetLeft(), shell:GetTop()
    local scale = shell:GetScale()
    if not left or not top or not scale or scale <= 0 then return end
    local x, y = left, top - UIParent:GetHeight() / scale
    shell:ClearAllPoints()
    shell:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    local host = Host()
    if host and shell._noteId then host.SetPosition(shell._noteId, "TOPLEFT", x, y) end
end

local function MakeDraggable(region, shell)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function() StartDrag(shell) end)
    region:SetScript("OnDragStop", function() StopDrag(shell) end)
end

--------------------------------------------------------------------------------
-- Shells
--------------------------------------------------------------------------------

local function UpdateButtons(shell)
    local show = shell._editing or shell._hovered
    shell._editBtn:SetShown(show and true or false)
    shell._deleteBtn:SetShown(show and true or false)
end
N.UpdateButtons = UpdateButtons

local function CreateShell()
    local slot = #shells + 1
    local shell = CreateFrame("Frame", addon.Brand .. "Note" .. slot, UIParent)
    shell._slot = slot
    shell:SetFrameStrata("MEDIUM")
    shell:SetClampedToScreen(true)
    shell:SetMovable(true)
    shell:SetSize(N.MIN_WIDTH, 40)
    shell:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Frame levels, bottom to top: the shell's own textures (the flat or art
    -- backdrop, the art border), the title region's plate, the tooltip
    -- nine-slice, the title row's click target, then the text and buttons.
    local baseLevel = shell:GetFrameLevel()

    local nineSlice = CreateFrame("Frame", nil, shell, "NineSlicePanelTemplate")
    nineSlice:SetAllPoints(shell)
    nineSlice:SetFrameLevel(baseLevel + 2)
    local layout = NineSliceUtil.GetLayout("TooltipDefaultLayout")
    if layout then
        NineSliceUtil.ApplyLayout(nineSlice, layout)
        NineSliceUtil.DisableSharpening(nineSlice)
    end
    local bgColor = TOOLTIP_DEFAULT_BACKGROUND_COLOR
    local bgR, bgG, bgB
    if bgColor and bgColor.GetRGB then
        bgR, bgG, bgB = bgColor:GetRGB()
    else
        bgR, bgG, bgB = DEFAULT_BG_COLOR[1], DEFAULT_BG_COLOR[2], DEFAULT_BG_COLOR[3]
    end
    nineSlice:SetCenterColor(bgR, bgG, bgB, 1)
    shell._nineSlice = nineSlice
    shell._bgColor = { bgR, bgG, bgB }

    -- The flat backdrop of a window with no tooltip border.
    local flatBg = shell:CreateTexture(nil, "BACKGROUND", nil, -8)
    flatBg:SetAllPoints(shell)
    flatBg:Hide()
    shell._flatBg = flatBg

    local content = CreateFrame("Frame", nil, shell)
    content:SetAllPoints(shell)
    content:SetFrameLevel(baseLevel + 4)
    shell._content = content

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont(addon.GetGameFontNormalFace(), 14, "OUTLINE")
    title:SetPoint("TOPLEFT", shell, "TOPLEFT", PADDING, -TITLE_TOP)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    shell._title = title

    -- The title row: a click collapses or opens the note, a right-click asks
    -- for a new title, a drag moves the note.
    local toggleBtn = CreateFrame("Button", nil, shell)
    toggleBtn:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, 0)
    toggleBtn:SetPoint("TOPRIGHT", shell, "TOPRIGHT", 0, 0)
    toggleBtn:SetHeight(TITLE_TOP + 12 + TITLE_BOTTOM)
    toggleBtn:SetFrameLevel(baseLevel + 3)
    toggleBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    toggleBtn:SetScript("OnClick", function(_, button)
        local record = shell._record
        if not record or shell._editing then return end
        if button == "RightButton" then
            N.PromptTitle(shell)
            return
        end
        record.collapsed = not record.collapsed or nil
        if Host() then Host().Commit() end
        N.Render(shell)
    end)
    shell._toggleBtn = toggleBtn
    MakeDraggable(toggleBtn, shell)
    MakeDraggable(shell, shell)

    -- The title row as a title bar, for a title art key (ApplyLook). It
    -- covers the click target's rect, the whole shell while collapsed.
    local titleRegion = CreateFrame("Frame", nil, shell)
    titleRegion:SetFrameLevel(baseLevel + 1)
    titleRegion:SetAllPoints(toggleBtn)
    shell._titleRegion = titleRegion

    -- Delete and edit, shown while the mouse is over the note or it is
    -- being edited.
    local Controls = addon.UI.Controls
    local deleteBtn = Controls:CreateGlyphButton({ parent = content, atlas = DELETE_ATLAS,
        tooltip = "Delete Note", size = BUTTON_SIZE })
    deleteBtn:SetPoint("RIGHT", toggleBtn, "RIGHT", -(PADDING - 3), 0)
    deleteBtn:SetScript("OnClick", function() N.ConfirmDelete(shell) end)
    shell._deleteBtn = deleteBtn

    local editBtn = Controls:CreateGlyphButton({ parent = content, atlas = DONE_ATLAS,
        tooltip = "Edit Note", size = BUTTON_SIZE })
    editBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -BUTTON_GAP, 0)
    editBtn:SetScript("OnClick", function()
        if shell._editing then N.EndEdit(shell) else N.BeginEdit(shell) end
    end)
    shell._editBtn = editBtn

    -- Where the rows and the edit box stand.
    local body = CreateFrame("Frame", nil, content)
    body:SetSize(N.MIN_WIDTH, 1)
    shell._body = body
    -- The body takes the mouse once the editor has given it a script, so it
    -- carries the drag as well.
    MakeDraggable(body, shell)

    shell:SetScript("OnShow", function(self)
        self._hovered = addon.HoverFade.Watch("note" .. slot, {
            frame = self,
            onChange = function(isOver)
                self._hovered = isOver
                UpdateButtons(self)
            end,
        })
        UpdateButtons(self)
    end)
    shell:SetScript("OnHide", function(self)
        addon.HoverFade.Unwatch("note" .. slot)
        if self._dragging then
            self._dragging = nil
            self:StopMovingOrSizing()
        end
    end)

    shell:Hide()
    shells[slot] = shell
    addon.RegisterPetBattleFrame(shell)

    return shell
end

local function ResetShell(shell)
    if shell._editing then N.EndEdit(shell, true) end
    if shell._noteId then byId[shell._noteId] = nil end
    shell._noteId = nil
    shell._record = nil
    shell:Hide()
end

-- Puts a record in a shell and stands the shell where the note was left, or
-- at `fresh`, the place a new note is given, which is stored at once so a
-- later shell does not inherit it.
local function Bind(shell, record, fresh)
    shell._noteId = record.id
    shell._record = record
    byId[record.id] = shell

    local host = Host()
    local place = host and host.GetPosition(record.id)
    local stored = place ~= nil
    place = place or fresh or { point = "CENTER", x = 0, y = 0 }
    shell:ClearAllPoints()
    shell:SetPoint(place.point, UIParent, place.point, place.x, place.y)
    if host and not stored then
        host.SetPosition(record.id, place.point, place.x, place.y)
    end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- The title is the first line when that line is a level one heading.
local function SplitTitle(blocks)
    local first = blocks[1]
    if first and first.kind == "heading" and first.level == 1 and first.text ~= "" then
        return first.text, 2
    end
    return DEFAULT_TITLE, 1
end

-- Sizes the shell around the title row and whichever body is showing. The
-- existing anchor is kept, so the note grows away from the point it was
-- placed or dropped by.
local function Layout(shell)
    local record = shell._record
    if not record then return end

    local titleHeight = math.max(math.ceil(shell._title:GetStringHeight() or 0), TITLE_MIN_SIZE)
    local rowHeight = TITLE_TOP + titleHeight + TITLE_BOTTOM
    shell._toggleBtn:SetHeight(rowHeight)

    local bodyWidth, bodyHeight = 0, 0
    if shell._editing then
        bodyWidth, bodyHeight = N.LayoutEditor(shell)
    elseif not record.collapsed then
        bodyWidth, bodyHeight = N.LayoutRows(shell)
    end

    local titleRoom = N.MAX_WIDTH - BUTTONS_WIDTH
    shell._title:SetWidth(0)
    local natural = shell._title.GetUnboundedStringWidth and shell._title:GetUnboundedStringWidth()
        or shell._title:GetStringWidth() or 0
    local titleWidth = math.min(natural, titleRoom)
    local inner = math.max(N.MIN_WIDTH, bodyWidth,
        titleWidth + BUTTONS_WIDTH)
    shell._title:SetWidth(inner - BUTTONS_WIDTH)

    local height = rowHeight
    if bodyHeight > 0 then
        shell._body:ClearAllPoints()
        shell._body:SetPoint("TOPLEFT", shell, "TOPLEFT", PADDING, -(rowHeight + BODY_GAP))
        height = rowHeight + BODY_GAP + bodyHeight + PADDING
    end
    shell._body:SetShown(bodyHeight > 0)

    shell._titleRegion:ClearAllPoints()
    shell._titleRegion:SetAllPoints(bodyHeight > 0 and shell._toggleBtn or shell)

    local point, relativeTo, relativePoint, x, y = shell:GetPoint(1)
    shell:SetSize(inner + PADDING * 2, height)
    if point then
        shell:ClearAllPoints()
        shell:SetPoint(point, relativeTo, relativePoint, x, y)
    end
end

--- Lays the shell out now and again a frame later: a FontString reports one
--- line's height until it has drawn once.
function N.Layout(shell)
    Layout(shell)
    local record = shell._record
    C_Timer.After(0, function()
        if shell._record == record and shell:IsShown() then Layout(shell) end
    end)
end

--- Draws one note from its record: title, fonts, look, rows.
function N.Render(shell)
    local record = shell._record
    local db = N.DB()
    if not record or not db then return end

    local blocks = addon.Markdown.Parse(record.text)
    local titleText, firstBlock = SplitTitle(blocks)
    shell._blocks = blocks
    shell._firstBlock = firstBlock

    local face, size, style = N.TitleFont()
    addon.ApplyFontStyle(shell._title, face, math.max(TITLE_MIN_SIZE, size - TITLE_SHRINK), style)
    shell._title:SetTextColor(N.HeaderColor())
    shell._title:SetText(titleText)

    SetAtlasFrom(shell._editBtn._tex, shell._editing and DONE_ATLAS or PENCIL_ATLAS)

    ApplyLook(shell, db)
    shell:SetScale(math.max(0.25, math.min(2.0, tonumber(db.scale) or 1.0)))

    if not shell._editing then N.RenderRows(shell) end
    UpdateButtons(shell)
    N.Layout(shell)
end

--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

--- Brings the shells in line with the host's list: every record in a shell,
--- every shell without a record released. The component's ApplyStyling.
function N.Refresh()
    local host = Host()
    if not host or not N.DB() then return end
    if not (addon.UI and addon.UI.Controls and addon.UI.Controls.CreateGlyphButton) then return end

    local list = host.GetNotes()
    local live = {}
    for _, record in ipairs(list) do
        live[record.id] = record
    end
    for id, shell in pairs(byId) do
        if live[id] ~= shell._record then pool:Release(shell) end
    end
    for _, record in ipairs(list) do
        local shell = byId[record.id]
        if not shell then
            shell = pool:Acquire()
            Bind(shell, record)
        end
        shell:Show()
        N.Render(shell)
    end
end

--- A new note at the screen center, a step down for each note showing, open
--- for writing.
function N.Create()
    local host = Host()
    local db = N.DB()
    if not host or not db or InCombatLockdown() then return end

    -- Under a host with a zero-touch state, this write is what marks the
    -- component configured, so its styling pass runs from here on.
    if not db.created then db.created = true end

    local showing = 0
    for _ in pairs(byId) do showing = showing + 1 end

    local record = host.NewNote()
    if not record then return end
    local shell = pool:Acquire()
    Bind(shell, record, { point = "CENTER", x = (showing % 6) * 24, y = 120 - (showing % 6) * 40 })
    shell:Show()
    N.Render(shell)
    N.BeginEdit(shell)
end

function N.Delete(shell)
    local record = shell._record
    local host = Host()
    if not record or not host then return end
    pool:Release(shell)
    host.RemoveNote(record.id)
end

function N.ConfirmDelete(shell)
    local record = shell._record
    if not record then return end
    addon.Dialogs:Show("NOTE_DELETE", {
        onAccept = function()
            -- The shell may hold another note by the time the player answers.
            if shell._record == record then N.Delete(shell) end
        end,
    })
end

--- Writes the note's title: the text's first line as a level one heading. An
--- empty title takes that line away, and the note reads "Note" again.
function N.SetTitle(shell, title)
    local record = shell._record
    local host = Host()
    if not record or not host or shell._editing then return end
    title = type(title) == "string" and title:gsub("[\r\n]", " "):match("^%s*(.-)%s*$") or ""

    local text = record.text or ""
    local first, rest = text:match("^([^\n]*)\n?(.*)$")
    local hasTitle = first and first:match("^#%s+%S") ~= nil
    local body = hasTitle and rest or text
    if title == "" then
        record.text = body
    elseif body == "" then
        record.text = "# " .. title
    else
        record.text = "# " .. title .. "\n" .. body
    end
    host.Commit()
    N.Render(shell)
end

--- Asks for a new title. Not in combat: the prompt takes the keyboard.
function N.PromptTitle(shell)
    local record = shell._record
    if not record or shell._editing or InCombatLockdown() then return end
    local current = shell._title:GetText()
    addon.Dialogs:Show("NOTE_TITLE", {
        editBoxText = current ~= DEFAULT_TITLE and current or "",
        onAccept = function(_, title)
            -- The shell may hold another note by the time the player answers.
            if shell._record == record then N.SetTitle(shell, title) end
        end,
    })
end

--- fn(shell) for every shell that holds a note.
function N.ForEach(fn)
    for _, shell in pairs(byId) do fn(shell) end
end

pool = addon.Pool.New(CreateShell, ResetShell)

--------------------------------------------------------------------------------
-- Component registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local component = Component:New({
        id = "notes",
        name = "Notes",
        settings = {
            -- The look every note shares (ApplyLook). These defaults draw the
            -- tooltip window; a host may register a look of its own over them.
            windowBackdropTexture   = { type = "addon", default = "solid" },
            windowBackdropOpacity   = { type = "addon", default = 100 },
            windowBorderStyle       = { type = "addon", default = "tooltip" },
            titleBarBackdropTexture = { type = "addon", default = "none" },
            titleBarBackdropOpacity = { type = "addon", default = 100 },
            scale       = { type = "addon", default = 1.0 },
            headerColor = { type = "addon", default = { 0.1, 1.0, 0.1, 1 } },
            bodyColor   = { type = "addon", default = { 1, 1, 1, 1 } },
            -- True once the player has made a note.
            created     = { type = "addon", default = false },
            -- The id the next note takes, for a host that counts in settings.
            nextNoteId  = { type = "addon", default = 1 },
        },
        ApplyStyling = function() N.Refresh() end,
    })
    self:RegisterComponent(component)

    addon.Dialogs:Register("NOTE_DELETE", {
        text = "Delete this note?",
        acceptText = "Delete",
    })
    addon.Dialogs:Register("NOTE_TITLE", {
        text = "Note title",
        acceptText = "Save",
        hasEditBox = true,
        maxLetters = TITLE_MAX_LETTERS,
    })

    if addon.MinimapMenu then
        addon.MinimapMenu.RegisterAction({
            id = "createNote",
            label = "Create Note",
            order = 10,
            -- No editing surface opens in combat.
            isEnabled = function() return not InCombatLockdown() end,
            Run = function() N.Create() end,
        })
    end
end)

-- Typing ends when a fight starts: the box would hold the keyboard.
addon.Events.On("Notes", "PLAYER_REGEN_DISABLED", function()
    N.ForEach(function(shell)
        if shell._editing then N.EndEdit(shell) end
    end)
end)
