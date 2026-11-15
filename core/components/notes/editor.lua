--------------------------------------------------------------------------------
-- notes/editor.lua - a note's editing mode.
--
-- The pencil hides the rows and shows the note's raw markdown in an edit box
-- at the note's full width. An edit box draws all its text in one font, so
-- nothing renders while the player types; the check mark the pencil turns
-- into, or Escape, saves the text and draws the note again.
--
-- Enter repeats a list marker on the new line ("- ", "[ ] ", the next
-- number), and Enter on a line that holds only its marker clears the marker.
--
-- One note is edited at a time. Editing does not start in combat, and a
-- fight starting saves and closes it (notes/core.lua).
--------------------------------------------------------------------------------

local _, addon = ...

local N = addon.Notes

local MIN_HEIGHT = 48
local PLACEHOLDER = "# Title\n- a bullet\n[ ] a task"

local editingShell

-- The marker for the line the cursor just opened, when the player pressed
-- Enter at the end of a list line.
local function ContinueList(box)
    local text = box:GetText() or ""
    local cursor = box:GetCursorPosition() or 0
    if cursor < 1 or text:sub(cursor, cursor) ~= "\n" then return end

    local before = text:sub(1, cursor - 1)
    local lineStart = 1
    for position in before:gmatch("()\n") do
        lineStart = position + 1
    end
    local prefix, bare = addon.Markdown.ListPrefix(before:sub(lineStart))
    if not prefix then return end

    box._changing = true
    if bare then
        -- An empty item ends the list: the marker goes, the line stays.
        box:SetText(text:sub(1, lineStart - 1) .. text:sub(cursor + 1))
        box:SetCursorPosition(lineStart - 1)
    else
        box:Insert(prefix)
    end
    box._changing = false
end

local function CreateBox(shell)
    local box = CreateFrame("EditBox", nil, shell._body)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetPoint("TOPLEFT", shell._body, "TOPLEFT", 0, 0)
    box:SetWidth(N.MAX_WIDTH)
    box:SetFont(addon.GetGameFontNormalFace(), 12, "")
    box:SetJustifyH("LEFT")

    local hint = box:CreateFontString(nil, "OVERLAY")
    hint:SetFont(addon.GetGameFontNormalFace(), 12, "")
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetTextColor(1, 1, 1, 0.35)
    hint:SetText(PLACEHOLDER)
    box._hint = hint

    box:SetScript("OnEscapePressed", function() N.EndEdit(shell) end)
    box:SetScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        self._hint:SetShown(text == "")
        if userInput and not self._changing and #text == (self._length or 0) + 1 then
            -- Ctrl+Enter saves. The box has already taken the Enter as a new
            -- line, so that line break goes first.
            local cursor = self:GetCursorPosition() or 0
            if IsControlKeyDown() and cursor >= 1 and text:sub(cursor, cursor) == "\n" then
                self._changing = true
                self:SetText(text:sub(1, cursor - 1) .. text:sub(cursor + 1))
                self._changing = false
                N.EndEdit(shell)
                return
            end
            ContinueList(self)
        end
        self._length = #(self:GetText() or "")
        N.Layout(shell)
    end)
    -- A click anywhere in the body's rect puts the cursor back in the box.
    shell._body:SetScript("OnMouseDown", function()
        if shell._editing then addon.Keyboard.TakeFocus(box) end
    end)

    shell._editBox = box
    return box
end

--- The edit box's width and height, for the shell's layout.
function N.LayoutEditor(shell)
    local box = shell._editBox
    if not box then return 0, 0 end
    local height = math.max(math.ceil(box:GetHeight() or 0), MIN_HEIGHT)
    if (box:GetText() or "") == "" then
        height = math.max(height, math.ceil(box._hint:GetStringHeight() or 0))
    end
    shell._body:SetSize(N.MAX_WIDTH, height)
    return N.MAX_WIDTH, height
end

function N.BeginEdit(shell)
    local record = shell._record
    if not record or shell._editing or InCombatLockdown() then return end
    if editingShell and editingShell ~= shell then N.EndEdit(editingShell) end

    -- A collapsed note opens to be written in.
    if record.collapsed then
        record.collapsed = nil
        if addon.NotesHost then addon.NotesHost.Commit() end
    end

    local box = shell._editBox or CreateBox(shell)
    local face, size = N.BodyFont()
    if not pcall(box.SetFont, box, face, size, "") then
        box:SetFont(addon.GetGameFontNormalFace(), size, "")
    end
    box:SetTextColor(N.BodyColor())
    pcall(box._hint.SetFont, box._hint, face, size, "")

    shell._editing = true
    editingShell = shell
    if shell._rows then shell._rows:HideFrom(1) end
    shell._body:EnableMouse(true)
    shell._body:Show()
    box:Show()
    N.Render(shell)

    -- An edit box lays its text out when the text is set, against the rect
    -- it has then, so the text goes in once the shell has its editing size.
    box._changing = true
    box:SetText("")
    box._changing = false
    C_Timer.After(0, function()
        if shell._editing and shell._record == record then
            box._changing = true
            box:SetText(record.text or "")
            box._changing = false
            box._length = #(record.text or "")
            box:SetCursorPosition(box._length)
            addon.Keyboard.TakeFocus(box)
            N.Layout(shell)
        end
    end)
end

--- Leaves editing mode. The text is saved unless `discard` is set, which is
--- for a shell that is being released.
function N.EndEdit(shell, discard)
    if not shell._editing then return end
    local box = shell._editBox
    local record = shell._record

    shell._editing = false
    if editingShell == shell then editingShell = nil end

    if box then
        if not discard and record then
            local text = (box:GetText() or ""):gsub("%s+$", "")
            record.text = text
            if addon.NotesHost then addon.NotesHost.Commit() end
        end
        box:ClearFocus()
        box:Hide()
    end
    shell._body:EnableMouse(false)

    if not discard and record then N.Render(shell) end
end
