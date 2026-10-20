-- PopupList.lua - Shared floating option list for selector-family controls
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls
local Theme -- Will be set after Theme.lua loads

-- Lazy Theme accessor
local function GetTheme()
    if not Theme then
        Theme = addon.UI.Theme
    end
    return Theme
end

-- The floating option list every selector-family control opens: one frame on
-- UIParent above everything, rebuilt from the caller's keys on every open,
-- dismissed by ESC or any click outside. The caller owns the current value
-- and the field that displays it; the list reads state through the callbacks
-- and reports a choice through onSelect. The list opens under the field, and
-- above it when the screen has no room below; OpenAt and OpenAtCursor open
-- it at a point instead, for a context menu on a row.
--
-- The popupList chrome role decides the draw. Flat is the framework's own:
-- a solid fill inside the accent border, the chosen row on an accent wash
-- with its text in the accent, the row under the cursor on a fainter wash.
-- An atlas kind is a skin's box stretched over the rows, reaching past the
-- frame by spec.reach where the art carries a margin, with the rows kept off
-- the edge by spec.padding; the rows are then text alone, colored by
-- spec.labelColors (normal, hover, selected, disabled), and spec.highlight,
-- an atlas at an alpha, lies over the row under the cursor. A skin that
-- names metrics.popupList (optionHeight, fontSize, textInset, fontRole, gap)
-- puts every list on those numbers over the caller's, so the rows read the
-- same under every field.
--
-- Three modes beyond the single choice. multiSelect draws a check box
-- (CheckBox.lua) before each row, in the row's own text color, and keeps
-- the list open: a click flips the row and reports it through onToggle,
-- and isChecked says which rows are on.
-- filter puts a box above the rows that narrows them to the labels holding
-- the typed text; Enter takes the one row left, Escape closes. maxRows caps
-- the rows drawn, for a list long enough to need the filter.
--
-- A list may come in sections, each of one or more columns: getSections
-- names them, and the rows then stand in their sections from the top, a
-- rule or a space between sections, a caption over a section or over each
-- of its columns, a row of buttons under the caption, and each section's
-- keys down its columns in turn. The filter box and maxRows do not apply
-- to a sectioned list.
--
-- A list may also stand inside a host instead of floating: embed names the
-- frame, and the list then draws no surface, takes no click outside and no
-- Escape, and Open builds the rows at the host's top-left and returns
-- their height, for a drawer or a pane that holds a check list.
--
-- A list in the contextMenu role is the box a right-click opens, and its
-- rows may be of kinds beyond the choice: a title, a submenu row that opens
-- another list beside it on hover, a radio or check row with its mark on
-- the left, a swatch row with a color square on the right, and a row that
-- runs a secure action on its click (an Edit Mode entry). The skin's role
-- decides the art for each; flat draws the framework's own.
--
-- opts:
--   role            the chrome role and the metrics key the list draws
--                   with (default "popupList"); "contextMenu" is the box a
--                   right-click opens, Blizzard's own on the forever skin
--   anchor          the field frame the list opens against; also the width
--                   source when width is nil
--   align           "right" stands the list's right edge on the anchor's,
--                   for a list wider than its field
--   embed           the frame the list stands in, in place of floating
--   width           fixed width; nil measures anchor:GetWidth() at open and
--                   falls back to 150 while the anchor has no layout yet
--   optionHeight    default 26
--   fontSize        option label size (default 12)
--   textInset       option label inset from both edges (default 12)
--   levelFrom       frame tracked at open so the list clears a host that sits
--                   at or above this strata's base level (a Flyout raises
--                   itself); nil keeps the fixed base level
--   getKeys         function() -> ordered key list
--   getValues       function() -> key-to-label map
--   getSections     function() -> { { label, labels, keys, columns,
--                   buttons, separator }, ... } or nil for the flat list;
--                   label is one caption, labels one per column, columns
--                   the count (default 1), buttons { { label, onClick } }
--                   a row of small buttons under the caption, separator
--                   "rule" (default), "space" or "none" above a section
--                   after the first
--   captionSize     the captions' point size over the miniLabel role's
--   captionTop      extra room above a caption that follows a separator
--   getSelectedKey  function() -> the current key, for the highlight
--   isInert         function(key) -> true lists the option dimmed, with hover
--                   and click ignored
--   infoIcons       key -> { tooltipTitle, tooltipText } info icon per option
--   onSelect        function(key) -> commit; the list closes and plays the
--                   click sound afterwards
--   multiSelect     true for check rows; then isChecked(key) and
--                   onToggle(key, checked)
--   filter          true for the box above the rows; filterLetters caps it
--                   (default 32)
--   maxRows         the most rows drawn
--   silent          true opens without the open sound, for a list rebuilt
--                   on every keystroke
--   getKind         function(key) -> nil for a choice, "title" (a heading in
--                   the role's title color, no hover, no click), "submenu"
--                   (the arrow on the right; the list getSubmenu returns
--                   opens beside the row on hover), "radio" (a mark on the
--                   left, on when isChecked(key); a click reports through
--                   onSelect), "check" (a box on the left flipped in place,
--                   reported through onToggle, the list kept open) or
--                   "swatch" (a color square on the right from getSwatch)
--   getSubmenu      function(key) -> the opts of the list a submenu row
--                   opens, built once per key; it closes with this list,
--                   and a pick in it closes both
--   getSwatch       function(key) -> r, g, b for a swatch row
--   secureActions   key -> a table of SecureActionButton attributes; the
--                   row is then a secure button, the attributes run on the
--                   click before the list closes and onSelect runs after
--   openSound       the sound kit the open plays (default IG_MAINMENU_OPEN)
--
-- Returns a handle: Open (the rows' height), OpenAt(x, y), OpenAtCursor,
-- Close, Toggle, IsShown, Refresh (the rows rebuilt in place while shown,
-- the height), Destroy, frame.
function Controls.CreatePopupList(opts)
    local theme = GetTheme()
    local Chrome = addon.UI.Chrome
    local role = opts.role or "popupList"
    local spec = Chrome.Spec(role)
    local art = spec.kind ~= "flat"
    local pm = Controls.Metrics()[role] or Controls.Metrics().popupList or {}
    local anchor = opts.anchor
    local optionHeight = pm.optionHeight or opts.optionHeight or 26
    local fontSize = pm.fontSize or opts.fontSize or 12
    local textInset = pm.textInset or opts.textInset or 12
    local fontRole = pm.fontRole or "value"
    -- The room between the field's edge and the list's
    local gap = pm.gap or 2
    local getKeys = opts.getKeys
    local getValues = opts.getValues
    local getSections = opts.getSections
    local align = opts.align
    local embed = opts.embed
    local getSelectedKey = opts.getSelectedKey
    local isInert = opts.isInert
    local infoIcons = opts.infoIcons
    local onSelect = opts.onSelect
    local multi = opts.multiSelect and true or false
    local isChecked = opts.isChecked
    local onToggle = opts.onToggle
    local withFilter = opts.filter and true or false
    local maxRows = opts.maxRows
    local getKind = opts.getKind
    local getSubmenu = opts.getSubmenu
    local getSwatch = opts.getSwatch
    local secureActions = opts.secureActions
    -- A submenu list: no dismiss or Escape of its own, closed by its parent,
    -- and a pick in it closes the root
    local child = opts.child and true or false
    local root = opts.root
    -- The room a context menu's rows keep past their widest text, and the
    -- mark's room before a radio or check row's text
    local extent = pm.extent or 0
    local markWidth = pm.markWidth or 20
    local filterHeight = pm.filterHeight or 22
    -- A sectioned list's caption row, the room around a rule, the rule's
    -- alpha on the dim text color, and a section's buttons
    local captionSize = opts.captionSize
    local captionHeight = math.max(pm.captionHeight or 18, (captionSize or 0) + 6)
    local captionTop = opts.captionTop or 0
    local sectionGap = pm.sectionGap or 4
    local ruleAlpha = pm.ruleAlpha or 0.25
    local buttonHeight = pm.buttonHeight or 22
    local buttonGap = pm.buttonGap or 6

    local popup = CreateFrame("Frame", nil, embed or UIParent)
    if embed then
        popup:SetPoint("TOPLEFT", embed, "TOPLEFT", 0, 0)
    else
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(100)
        popup:SetClampedToScreen(true)
    end
    popup:Hide()

    -- What the rows keep off the frame's edge: the role's padding, else the
    -- flat draw's one unit inside the border across and four above and below
    local padding = spec.padding
    if type(padding) == "number" then
        padding = { left = padding, right = padding, top = padding, bottom = padding }
    elseif type(padding) ~= "table" then
        padding = { left = 1, right = 1, top = 4, bottom = 4 }
    end
    local padL, padR = padding.left or 0, padding.right or 0
    local padT, padB = padding.top or 0, padding.bottom or 0

    -- An embedded list stands on its host's surface
    if embed then
        popup._backdrop = nil
    elseif art then
        popup._backdrop = Chrome.Backdrop(role, popup)
    else
        -- Popup chrome: solid fill plus a 1px accent border
        Controls.AddBackground(popup, { alpha = 0.98 })
        popup._border = Controls.CreateBorder(popup, { alpha = 0.8 })
    end
    local colors = art and spec.labelColors or nil
    local highlight = art and spec.highlight or nil

    popup._optionButtons = {}

    local list = { frame = popup }
    root = root or list
    popup._children = {}
    -- What a parent reads to stand a child list beside one of its rows
    list.reachLeft = (art and type(spec.reach) == "table") and (spec.reach.left or 0) or 0
    list.padTop = padT
    local dismiss
    local filterBox
    local filterText = ""

    function list:IsShown()
        return popup:IsShown()
    end

    function list:Close()
        if list._openChild then
            list._openChild:Close()
            list._openChild = nil
        end
        popup:Hide()
        if filterBox then filterBox:ClearFocus() end
        if dismiss then
            dismiss:Hide()
        end
    end

    -- A floating list goes on a click outside or Escape; an embedded one
    -- goes with its host
    if not embed and not child then
        dismiss = Controls.AttachDismissOnClickOutside(function()
            list:Close()
        end)
        addon.EscapeKey.Attach(popup, function()
            list:Close()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end)
    end

    local function RowOn(btn)
        if multi or btn._kind == "radio" or btn._kind == "check" then
            return (isChecked and isChecked(btn._key)) and true or false
        end
        return getSelectedKey ~= nil and btn._key == getSelectedKey()
    end

    -- A row's text and wash for its state. Under the role's colors the
    -- chosen row keeps its color under the cursor and only the wash comes
    -- up, as Blizzard's own list does; flat lifts both.
    -- The row's text and its check box take one color
    local function Tint(btn, r, g, b, a)
        btn._text:SetTextColor(r, g, b, a)
        if btn._check then btn._check:SetColor(r, g, b, a) end
        if btn._arrowText then btn._arrowText:SetTextColor(r, g, b, a) end
    end

    local function Paint(btn, hover)
        local selected = RowOn(btn)
        if btn._check then
            btn._check:SetChecked(selected)
        end
        if btn._markOn then
            btn._markOn:SetShown(selected)
        end
        -- A radio or check row says it is on by its mark, not its text
        local marked = btn._kind == "radio" or btn._kind == "check"
        if colors then
            local state
            if btn._kind == "title" then
                state = "title"
            else
                state = btn._inert and "disabled" or (selected and not marked and "selected") or (hover and "hover") or "normal"
            end
            local r, g, b, a = Chrome.Color(colors[state] or (state == "title" and colors.selected) or colors.normal or "white")
            Tint(btn, r, g, b, a)
            btn._bg:SetShown(hover and not btn._inert and btn._kind ~= "title")
            return
        end
        local accentR, accentG, accentB = theme:GetAccentColor()
        if btn._kind == "title" then
            Tint(btn, accentR, accentG, accentB, 1)
            btn._bg:SetColorTexture(0, 0, 0, 0)
        elseif btn._inert then
            local dr, dg, dbl = theme:GetDimTextColor()
            Tint(btn, dr, dg, dbl, 0.6)
        elseif selected and not marked then
            -- A checked row of a check list shows it by its box and its
            -- text; the wash marks the one chosen row of a single choice
            if multi then
                btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.15 or 0)
            else
                btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.35 or 0.3)
            end
            Tint(btn, accentR, accentG, accentB, 1)
        else
            btn._bg:SetColorTexture(accentR, accentG, accentB, hover and 0.15 or 0)
            Tint(btn, 1, 1, 1, 1)
        end
    end

    -- The captions, rules and buttons of a sectioned list, kept and reused
    -- across builds since a region cannot be released
    popup._captions, popup._rules, popup._buttons = {}, {}, {}

    local function ClearRows()
        for _, btn in ipairs(popup._optionButtons) do
            if btn._infoIcon then
                btn._infoIcon:Cleanup()
            end
            btn:Hide()
            btn:SetParent(nil)
        end
        wipe(popup._optionButtons)
        for _, fs in ipairs(popup._captions) do fs:Hide() end
        for _, tex in ipairs(popup._rules) do tex:Hide() end
        for _, btn in ipairs(popup._buttons) do btn:Hide() end
    end

    -- A section's button, the subtle look of a button inside content; the
    -- click runs whatever the last build put on it
    local function SectionButton(index)
        local btn = popup._buttons[index]
        if not btn then
            btn = Controls:CreateButton({
                parent = popup,
                text = "",
                height = buttonHeight,
                fontSize = fontSize,
                borderWidth = 1,
                borderAlpha = 0.6,
                onClick = function(b, mouseButton)
                    if b._run then b._run(b, mouseButton) end
                end,
            })
            popup._buttons[index] = btn
        end
        return btn
    end

    local function Caption(index)
        local fs = popup._captions[index]
        if not fs then
            fs = popup:CreateFontString(nil, "OVERLAY")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            popup._captions[index] = fs
        end
        theme:ApplyFont(fs, "miniLabel", captionSize)
        local dr, dg, dbl = theme:GetDimTextColor()
        fs:SetTextColor(dr, dg, dbl, 1)
        fs:ClearAllPoints()
        fs:Show()
        return fs
    end

    local function Rule(index)
        local tex = popup._rules[index]
        if not tex then
            tex = popup:CreateTexture(nil, "ARTWORK")
            tex:SetHeight(1)
            popup._rules[index] = tex
        end
        local dr, dg, dbl = theme:GetDimTextColor()
        tex:SetColorTexture(dr, dg, dbl, ruleAlpha)
        tex:ClearAllPoints()
        tex:Show()
        return tex
    end

    local function Matches(label)
        if filterText == "" then return true end
        return string.find(string.lower(tostring(label)), string.lower(filterText), 1, true) ~= nil
    end

    -- The child list a submenu row opens, beside the row with its rows level
    -- with it and its art meeting this list's; built once per key. Entering
    -- any other row closes it; a pick in it closes the root.
    local function CloseChild()
        local open = list._openChild
        if open then
            open:Close()
            list._openChild = nil
        end
    end

    local function OpenChild(btn)
        local key = btn._key
        local open = list._openChild
        if open and list._openChildKey == key and open:IsShown() then return end
        CloseChild()
        local sub = popup._children[key]
        if not sub then
            local subOpts = getSubmenu and getSubmenu(key)
            if type(subOpts) ~= "table" then return end
            subOpts.child = true
            subOpts.root = root
            subOpts.role = subOpts.role or role
            subOpts.silent = true
            sub = Controls.CreatePopupList(subOpts)
            popup._children[key] = sub
        end
        list._openChild, list._openChildKey = sub, key
        local reach = (art and type(spec.reach) == "table") and spec.reach or {}
        local x = popup:GetRight() + (reach.right or 0) - (sub.reachLeft or 0)
        local y = btn:GetTop() + (sub.padTop or 0)
        sub:OpenAt(x, y)
        sub.frame:SetFrameLevel(popup:GetFrameLevel() + 10)
    end

    -- One option, its top-left at (x, y) from the frame's top-left corner
    -- and w wide; geometry holds the text's inset and the check box's room.
    -- A row of a kind carries its mark, arrow or swatch, and a row with a
    -- secure action is a secure button whose own handler takes the click.
    local function MakeOption(key, label, x, y, w, geometry)
        local kind = getKind and getKind(key) or nil
        local secure = secureActions and secureActions[key] or nil
        -- The secure row stands on the list's own frame, never a Blizzard one
        local optBtn = CreateFrame("Button", nil, popup, secure and "SecureActionButtonTemplate" or nil)
        optBtn:SetSize(w, optionHeight)
        optBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -y)
        optBtn:EnableMouse(true)
        optBtn:RegisterForClicks("AnyUp")
        optBtn._key = key
        optBtn._kind = kind
        optBtn._inert = (isInert and isInert(key)) and true or false
        if secure then
            pcall(function()
                optBtn:SetAttribute("useOnKeyDown", false)
                for attribute, value in pairs(secure) do optBtn:SetAttribute(attribute, value) end
            end)
        end

        local optBg = optBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
        optBg:SetAllPoints()
        if highlight then
            if highlight.atlas then
                optBg:SetAtlas(highlight.atlas)
            else
                optBg:SetTexture(highlight.texture)
            end
            if highlight.blend then optBg:SetBlendMode(highlight.blend) end
            optBg:SetAlpha(highlight.alpha or 1)
            optBg:Hide()
        else
            optBg:SetColorTexture(0, 0, 0, 0)
        end
        optBtn._bg = optBg

        -- The mark before a radio or check row's text: the role's two
        -- atlases, the second over the first while the row is on; the
        -- framework's check box under flat, and for a check list's rows
        local textLeft = geometry.textLeftOffset + geometry.checkWidth
        local mark = (kind == "radio" or kind == "check") and art and spec[kind] or nil
        local textAnchor, textGap, textY = nil, 0, 0
        if mark and mark.off then
            local off = optBtn:CreateTexture(nil, "ARTWORK")
            off:SetAtlas(mark.off, true)
            off:SetPoint("LEFT", optBtn, "LEFT", geometry.textLeftOffset + (mark.x or 0), 0)
            local on = optBtn:CreateTexture(nil, "ARTWORK", nil, 1)
            on:SetAtlas(mark.on, true)
            on:SetPoint(mark.onPoint or "CENTER", off, mark.onPoint or "CENTER", mark.onX or 0, mark.onY or 0)
            on:Hide()
            optBtn._mark, optBtn._markOn = off, on
            textAnchor, textGap, textY = off, mark.gap or 1, mark.textY or 0
        elseif multi or kind == "radio" or kind == "check" then
            local check = Controls.CreateCheckBox(optBtn, { size = geometry.checkSize })
            check:SetPoint("LEFT", optBtn, "LEFT", geometry.textLeftOffset, 0)
            optBtn._check = check
            textLeft = geometry.textLeftOffset + geometry.checkSize + textInset
        end

        -- What stands at the row's right: a submenu's arrow, or the swatch
        -- (Blizzard's ColorSwatchTemplate: white, black, then the color)
        local textRight = textInset
        if kind == "submenu" then
            local arrow = art and spec.arrow or nil
            if arrow and (arrow.texture or arrow.atlas) then
                local tex = optBtn:CreateTexture(nil, "ARTWORK")
                if arrow.atlas then tex:SetAtlas(arrow.atlas, true) else tex:SetTexture(arrow.texture) end
                tex:SetSize(arrow.size or 16, arrow.size or 16)
                tex:SetPoint("RIGHT", optBtn, "RIGHT", -(arrow.inset or 0), 0)
                textRight = textInset + (arrow.size or 16)
            else
                local fs = optBtn:CreateFontString(nil, "OVERLAY")
                theme:ApplyFont(fs, fontRole, fontSize)
                fs:SetText(">")
                fs:SetPoint("RIGHT", optBtn, "RIGHT", -textInset, 0)
                optBtn._arrowText = fs
                textRight = textInset + 12
            end
        elseif kind == "swatch" then
            local size = (art and spec.swatch and spec.swatch.size) or 16
            local r, g, b = 0, 0, 0
            if getSwatch then
                local sr, sg, sb = getSwatch(key)
                if type(sr) == "number" then r, g, b = sr, sg or 0, sb or 0 end
            end
            local outer = optBtn:CreateTexture(nil, "ARTWORK", nil, 0)
            outer:SetSize(size - 2, size - 2)
            outer:SetPoint("RIGHT", optBtn, "RIGHT", -(textInset + 1), 0)
            outer:SetColorTexture(1, 1, 1, 1)
            local inner = optBtn:CreateTexture(nil, "ARTWORK", nil, 1)
            inner:SetSize(size - 4, size - 4)
            inner:SetPoint("CENTER", outer, "CENTER", 0, 0)
            inner:SetColorTexture(0, 0, 0, 1)
            local color = optBtn:CreateTexture(nil, "ARTWORK", nil, 2)
            color:SetSize(size - 6, size - 6)
            color:SetPoint("CENTER", outer, "CENTER", 0, 0)
            color:SetColorTexture(r, g, b, 1)
            optBtn._swatch = color
            textRight = textInset + size
        end

        local optText = optBtn:CreateFontString(nil, "OVERLAY")
        theme:ApplyFont(optText, fontRole, fontSize)
        if textAnchor then
            optText:SetPoint("LEFT", textAnchor, "RIGHT", textGap, textY)
        else
            optText:SetPoint("LEFT", optBtn, "LEFT", textLeft, 0)
        end
        optText:SetPoint("RIGHT", optBtn, "RIGHT", -textRight, 0)
        optText:SetJustifyH("LEFT")
        optText:SetWordWrap(false)
        optText:SetText(label)
        optBtn._text = optText

        if infoIcons and infoIcons[key] then
            local iconData = infoIcons[key]
            local infoIcon = Controls:CreateInfoIcon({
                parent = optBtn,
                tooltipText = iconData.tooltipText,
                tooltipTitle = iconData.tooltipTitle,
                size = 14,
            })
            if infoIcon then
                infoIcon:SetPoint("LEFT", optBtn, "LEFT", 8, 0)
                optBtn._infoIcon = infoIcon
            end
        end

        Paint(optBtn, false)

        if kind == "title" then
            -- A heading: read, never hovered or clicked
            optBtn:EnableMouse(false)
        elseif optBtn._inert then
            -- Listed, not selectable: no hover, click ignored; crossing it
            -- still closes an open submenu
            optBtn:SetScript("OnClick", function() end)
            optBtn:SetScript("OnEnter", function() CloseChild() end)
        else
            optBtn:SetScript("OnEnter", function(btn)
                Paint(btn, true)
                if btn._kind == "submenu" then OpenChild(btn) else CloseChild() end
            end)
            optBtn:SetScript("OnLeave", function(btn) Paint(btn, false) end)
            local function Pick(btn)
                if multi or btn._kind == "check" then
                    local now = not RowOn(btn)
                    if onToggle then onToggle(btn._key, now) end
                    Paint(btn, true)
                    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    return
                end
                if btn._kind == "submenu" then
                    OpenChild(btn)
                    return
                end
                if onSelect then onSelect(btn._key) end
                root:Close()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end
            if secure then
                -- The template's secure handler owns OnClick; the list's
                -- work follows it
                optBtn:HookScript("PostClick", Pick)
            else
                optBtn:SetScript("OnClick", Pick)
            end
        end

        table.insert(popup._optionButtons, optBtn)
        return optBtn
    end

    -- The rows from the top down, the flat list's for the keys the filter
    -- leaves, or the sections' with their captions and rules; returns the
    -- frame's height for them
    local function BuildRows(width)
        ClearRows()
        local vMap = getValues()
        local sections = getSections and getSections() or nil

        local top = padT + (withFilter and (filterHeight + gap) or 0)
        -- Text moves right when any option carries an info icon
        local hasAnyInfoIcons = infoIcons and next(infoIcons)
        -- The check box stands a point short of the text's size, with the
        -- text inset again after it
        local checkSize = fontSize - 1
        local geometry = {
            textLeftOffset = hasAnyInfoIcons and 28 or textInset,
            checkSize = checkSize,
            checkWidth = multi and (checkSize + textInset) or 0,
        }
        local inner = width - padL - padR

        if not sections then
            local keys = {}
            for _, key in ipairs(getKeys()) do
                if Matches(vMap[key] or key) then
                    keys[#keys + 1] = key
                    if maxRows and #keys >= maxRows then break end
                end
            end
            for i, key in ipairs(keys) do
                MakeOption(key, vMap[key] or key, padL, top + (i - 1) * optionHeight, inner, geometry)
            end
            local totalHeight = top + (#keys * optionHeight) + padB
            popup:SetHeight(totalHeight)
            return totalHeight
        end

        local captions, rules, buttons = 0, 0, 0
        for s, section in ipairs(sections) do
            local cols = math.max(1, section.columns or 1)
            local colW = inner / cols
            if s > 1 then
                local separator = section.separator or "rule"
                if separator == "rule" then
                    top = top + sectionGap
                    rules = rules + 1
                    local rule = Rule(rules)
                    rule:SetPoint("TOPLEFT", popup, "TOPLEFT", padL + textInset, -top)
                    rule:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -(padR + textInset), -top)
                    top = top + 1 + sectionGap
                elseif separator == "space" then
                    top = top + sectionGap * 3
                end
            end
            local labels = section.labels or (section.label and { section.label }) or nil
            if labels then
                if s > 1 and (section.separator or "rule") ~= "none" then top = top + captionTop end
                for c = 1, cols do
                    if labels[c] then
                        captions = captions + 1
                        local fs = Caption(captions)
                        fs:SetPoint("TOPLEFT", popup, "TOPLEFT", padL + (c - 1) * colW + textInset, -top)
                        fs:SetSize(colW - textInset * 2, captionHeight)
                        fs:SetText(labels[c])
                    end
                end
                top = top + captionHeight
            end
            if section.buttons and #section.buttons > 0 then
                local x = padL + textInset
                for _, def in ipairs(section.buttons) do
                    buttons = buttons + 1
                    local btn = SectionButton(buttons)
                    btn:SetText(def.label or "")
                    btn._run = def.onClick
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -top)
                    btn:Show()
                    x = x + (btn:GetWidth() or 0) + buttonGap
                end
                top = top + buttonHeight + sectionGap
            end
            -- Down each column in turn
            local keys = section.keys or {}
            local perCol = math.max(1, math.ceil(#keys / cols))
            for i, key in ipairs(keys) do
                local col = math.floor((i - 1) / perCol)
                local r = (i - 1) % perCol
                MakeOption(key, vMap[key] or key, padL + col * colW, top + r * optionHeight, colW, geometry)
            end
            top = top + (#keys > 0 and perCol or 0) * optionHeight
        end

        local totalHeight = top + padB
        popup:SetHeight(totalHeight)
        return totalHeight
    end

    local function EnsureFilterBox(width)
        if filterBox then
            filterBox:SetWidth(width - padL - padR - 8)
            return
        end
        filterBox = Controls.CreateValueInput(popup, {
            width = width - padL - padR - 8, height = filterHeight - 4,
            maxLetters = opts.filterLetters or 32, justifyH = "LEFT", textInset = 6,
        })
        filterBox:SetPoint("TOPLEFT", popup, "TOPLEFT", padL + 4, -padT - 2)
        filterBox:SetScript("OnEditFocusGained", function(self) self._setFocusLook(true) end)
        filterBox:SetScript("OnEditFocusLost", function(self) self._setFocusLook(false) end)
        filterBox:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            filterText = self:GetText() or ""
            BuildRows(popup:GetWidth())
        end)
        filterBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            list:Close()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        end)
        filterBox:SetScript("OnEnterPressed", function()
            local only
            for _, btn in ipairs(popup._optionButtons) do
                if not btn._inert then
                    if only then only = nil break end
                    only = btn
                end
            end
            if only then only:Click() end
        end)
    end

    -- Where the list stands: under the anchor with room below it, above it
    -- otherwise; or at a point, its top-left corner there, lifted when it
    -- would run off the bottom
    local widened = false
    local function Place(totalHeight, at)
        popup:ClearAllPoints()
        if at then
            if at.y - totalHeight < 0 then
                popup:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", at.x, at.y)
            else
                popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at.x, at.y)
            end
            return
        end
        local anchorBottom = select(2, anchor:GetCenter()) - (anchor:GetHeight() / 2)
        local scale = UIParent:GetEffectiveScale()
        local spaceBelow = anchorBottom * scale
        local side = (align == "right" or widened) and "RIGHT" or "LEFT"
        if spaceBelow > totalHeight + 10 then
            popup:SetPoint("TOP" .. side, anchor, "BOTTOM" .. side, 0, -gap)
        else
            popup:SetPoint("BOTTOM" .. side, anchor, "TOP" .. side, 0, gap)
        end
    end

    -- The width the flat list's longest option takes in one line: the text's
    -- insets, the info icon's or check box's room, and the frame's padding,
    -- up to field.popupMaxWidth
    local function ListNeed()
        local vMap = getValues() or {}
        local widest = 0
        for _, key in ipairs(getKeys() or {}) do
            local label = vMap[key] or key
            if type(label) == "string" then
                local w = Controls.MeasureText(fontRole, label, fontSize) or 0
                local kind = getKind and getKind(key)
                if kind == "radio" or kind == "check" then w = w + markWidth end
                widest = math.max(widest, w)
            end
        end
        local left = (infoIcons and next(infoIcons)) and 28 or textInset
        local check = multi and (fontSize - 1 + textInset) or 0
        local need = math.ceil(widest + left + check + textInset + padL + padR + extent)
        local cap = Controls.Metrics().field.popupMaxWidth
        return cap and math.min(need, cap) or need
    end

    local function OpenWith(at)
        if opts.levelFrom then
            popup:SetFrameLevel(math.max(100, opts.levelFrom:GetFrameLevel() + 10))
        end
        local width = opts.width
        if not width then
            local source = embed or anchor
            width = source and source:GetWidth() or 0
            if width < 60 then width = 150 end
            -- A field narrower than its longest option opens a wider list,
            -- standing on the field's right edge so it grows toward the label
            widened = false
            if not embed and not getSections then
                local need = ListNeed()
                if at then
                    -- A list at a point fits its rows
                    width = need
                elseif need > width then
                    width = need
                    widened = true
                end
            end
        end
        popup:SetWidth(width)
        filterText = ""
        if withFilter then
            EnsureFilterBox(width)
            filterBox:SetText("")
        end
        local totalHeight = BuildRows(width)
        if embed then
            popup:Show()
            return totalHeight
        end
        Place(totalHeight, at)
        Controls.ClosePickers()

        if dismiss then
            dismiss:Show()
            dismiss:SetFrameLevel(popup:GetFrameLevel() - 1)
        end

        popup:Show()
        if withFilter then filterBox:SetFocus() end
        if not opts.silent then PlaySound(opts.openSound or SOUNDKIT.IG_MAINMENU_OPEN) end
        return totalHeight
    end

    function list:Open()
        return OpenWith(nil)
    end

    -- The rows built again in place, for a change that moves more than the
    -- clicked row; nothing while the list is closed
    function list:Refresh()
        if not popup:IsShown() then return nil end
        return BuildRows(popup:GetWidth())
    end

    -- x and y in UIParent's space, from its bottom-left corner
    function list:OpenAt(x, y)
        OpenWith({ x = x, y = y })
    end

    function list:OpenAtCursor()
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        OpenWith({ x = x / scale, y = y / scale })
    end

    function list:Toggle()
        if popup:IsShown() then
            list:Close()
        else
            list:Open()
        end
    end

    -- Eager teardown for owners that rebuild on re-render
    function list:Destroy()
        list:Close()
        for _, sub in pairs(popup._children) do sub:Destroy() end
        wipe(popup._children)
        if dismiss then dismiss:SetParent(nil) end
        ClearRows()
        if filterBox then
            filterBox:Hide()
            filterBox:SetParent(nil)
            filterBox = nil
        end
        popup:Hide()
        popup:SetParent(nil)
    end

    return list
end
