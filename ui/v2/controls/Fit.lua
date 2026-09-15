-- Fit.lua - text measurement and field sizing for settings rows
-- Contract: Controls.MeasureText returns the natural width of a string in a
-- skin font role; Controls.FieldNeed turns an option list into the width a
-- selector field needs from the active skin's field chrome metrics. Both work
-- on plain strings only. /scoot debug fit reports every field, label,
-- mini-label, and truncated string on the open settings page that does not
-- fit; 'fit all' walks every page.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.Controls = addon.UI.Controls or {}
local Controls = addon.UI.Controls

local function GetTheme()
    return addon.UI.Theme
end

--------------------------------------------------------------------------------
-- MeasureText
--------------------------------------------------------------------------------

-- The ruler is parented and anchored only to UIParent, a chain that is never
-- secret, and a single anchor point leaves the width unbounded.
local ruler
local warmedAt = {}   -- face .. size -> GetTime() of its warm-up
local cache = {}      -- face .. size .. text -> width

local function EnsureRuler()
    if ruler then return ruler end
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    holder:Hide()
    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", holder, "CENTER", 0, 0)
    fs:SetWordWrap(false)
    ruler = fs
    return fs
end

-- Natural width of text in a font role, at the role's size or an override.
-- Returns nil when the width cannot be read; callers keep their floor then.
-- A face read in the same frame as its warm-up is not cached, so the next
-- frame's re-measure sees the loaded metrics.
function Controls.MeasureText(role, text, size)
    if type(text) ~= "string" or text == "" then return 0 end
    -- A secret poured into the shared ruler would stamp it for every caller.
    if issecretvalue and issecretvalue(text) then return nil end

    local theme = GetTheme()
    if not theme then return nil end
    local face, roleSize = theme:GetFontRole(role)
    size = size or roleSize
    local faceKey = face .. "\0" .. size
    local key = faceKey .. "\0" .. text
    local hit = cache[key]
    if hit then return hit end

    local fs = EnsureRuler()
    theme:ApplyFont(fs, role, size)
    if not warmedAt[faceKey] then
        fs:SetText("The quick brown fox 0123456789")
        pcall(fs.GetUnboundedStringWidth, fs)
        warmedAt[faceKey] = GetTime()
    end

    fs:SetText(text)
    local ok, w = pcall(fs.GetUnboundedStringWidth, fs)
    fs:SetText("")
    if not ok or type(w) ~= "number" or w <= 0 then return nil end
    if GetTime() > warmedAt[faceKey] then
        cache[key] = w
    end
    return w
end

--------------------------------------------------------------------------------
-- FieldNeed
--------------------------------------------------------------------------------

-- The pixels around a selector's value text: border insets, both arrows with
-- their separators, and on each side the text inset plus the drop indicator's
-- room, so centered text stays centered. A gear or token icon adds its width
-- on both sides for the same reason.
function Controls.FieldChrome(opts)
    opts = opts or {}
    local f = Controls.Metrics().field
    local scale = opts.scale or 1
    local chrome = (2 * f.arrowWidth + 4) * scale
        + 2 * (f.textInset + f.indicatorWidth + f.indicatorGap) * scale
    if opts.gear then
        chrome = chrome + 2 * f.gearWidth
    end
    if opts.tokenIcon then
        chrome = chrome + 2 * (f.tokenIconWidth + f.indicatorGap)
    end
    return chrome
end

-- Widest label in a key -> label map, limited to order when given.
local function WidestLabel(values, order, size)
    local widest, widestText = 0, nil
    local function consider(label)
        if type(label) ~= "string" then return true end
        local w = Controls.MeasureText("value", label, size)
        if not w then return false end
        if w > widest then
            widest, widestText = w, label
        end
        return true
    end
    if order then
        for _, k in ipairs(order) do
            if values[k] ~= nil and not consider(values[k]) then return nil end
        end
    else
        for _, label in pairs(values) do
            if not consider(label) then return nil end
        end
    end
    return widest, widestText
end

-- The width a selector field needs to show every option in full: the larger
-- of the floor and the chrome plus the widest label, rounded up to the skin's
-- width step. kind names the floor in metrics.slots; opts.floor overrides it.
--
-- opts: order, floor, scale, size (value text size), gear, tokenIcon
--
-- Returns need, widest label width, widest label text. An unmeasurable label
-- returns the floor.
function Controls.FieldNeed(kind, values, opts)
    opts = opts or {}
    local m = Controls.Metrics()
    local floor = opts.floor or (m.slots and m.slots[kind]) or 0
    if type(values) ~= "table" then return floor, 0, nil end

    local widest, widestText = WidestLabel(values, opts.order, opts.size)
    if not widest then return floor, 0, nil end

    local step = m.field.widthStep
    local raw = Controls.FieldChrome(opts) + widest
    local need = math.ceil(raw / step) * step
    return math.max(floor, need), widest, widestText
end

--------------------------------------------------------------------------------
-- Audit: /scoot debug fit
--------------------------------------------------------------------------------

-- Extra roots the audit walks when shown, beside the settings panel content:
-- label -> function returning a frame.
local auditRoots = {}

function Controls.RegisterFitRoot(label, getFrame)
    auditRoots[label] = getFrame
end

local function Width(frame)
    if not frame or not frame.GetWidth then return 0 end
    local ok, w = pcall(frame.GetWidth, frame)
    return (ok and type(w) == "number") and w or 0
end

local function FontSize(fs)
    local ok, _, size = pcall(fs.GetFont, fs)
    return ok and size or nil
end

-- The nearest row label above a frame, for context in the report.
local function OwnerLabel(frame)
    local f = frame
    for _ = 1, 12 do
        if not f then break end
        if f._label and f._label.GetText then
            local t = f._label:GetText()
            if type(t) == "string" and t ~= "" then return t end
        end
        if type(f._searchLabel) == "string" then return f._searchLabel end
        f = f.GetParent and f:GetParent() or nil
    end
    return "?"
end

local function Round(v)
    return math.floor((v or 0) + 0.5)
end

-- A selector-family field: a frame carrying _keyList and _values, with its
-- value button on itself (the minis) or on its _selector (full rows).
local function CheckField(f, report)
    if type(f._keyList) ~= "table" or type(f._values) ~= "table" then return end
    local field = f._valueBtn and f or f._selector
    local valueBtn = field and field._valueBtn
    local textFS = valueBtn and valueBtn._text
    if not textFS then return end

    local fieldW = Width(field)
    if fieldW <= 0 then fieldW = Width(field:GetParent()) end
    if fieldW <= 0 then
        report.unresolved = report.unresolved + 1
        return
    end

    local f_ = Controls.Metrics().field
    local scale = 1
    if field._leftArrow then
        local aw = Width(field._leftArrow)
        if aw > 0 then scale = aw / f_.arrowWidth end
    end
    local need, widest, widestText = Controls.FieldNeed("selector", f._values, {
        order = f._keyList,
        floor = 0,
        scale = scale,
        size = FontSize(textFS),
        gear = f._gear ~= nil,
    })
    report.fields = report.fields + 1
    if not widestText then return end

    -- The list takes the field's width today; its option text is inset 12
    -- on both sides.
    local listShort = widest + 24 - fieldW
    local fieldShort = need - fieldW
    if fieldShort > 0 or listShort > 0 then
        report.push(string.format("  FIELD   %-28s %4d wide, needs %4d (%+d); list %+d  \"%s\"",
            OwnerLabel(f):sub(1, 28), Round(fieldW), Round(need), Round(fieldShort),
            Round(listShort), widestText))
        report.shortFields = report.shortFields + 1
    end
end

-- A row with a label and an anchored control cluster: the label's natural
-- right edge against the cluster's left edge, both from the row's widths.
local function CheckRow(f, report)
    local label = f._label
    local anchors = f._clusterAnchors
    if not (label and anchors and label.GetText) then return end
    local text = label:GetText()
    if type(text) ~= "string" or text == "" then return end

    local rowW = Width(f)
    if rowW <= 0 then
        report.unresolved = report.unresolved + 1
        return
    end
    report.rows = report.rows + 1

    if (f.GetHeight and (f:GetHeight() or 0) < 1) then
        report.push(string.format("  HEIGHT  %-28s row is 0 tall", text:sub(1, 28)))
        report.zeroRows = report.zeroRows + 1
    end

    local labelW = Controls.MeasureText("label", text, FontSize(label)) or 0
    local _, _, _, labelX = label:GetPoint(1)
    local labelRight = (labelX or 0) + labelW
    if f._infoIcon then
        labelRight = labelRight + 4 + Width(f._infoIcon)
    end

    local m = Controls.Metrics()
    for _, a in ipairs(anchors) do
        if a.point == "RIGHT" then
            local clusterLeft = rowW + (a.x or 0) - Width(a.frame)
            local gap = clusterLeft - labelRight
            if gap < m.slotGap then
                report.push(string.format("  LABEL   %-28s %s the cluster by %d (row %d, cluster %d)",
                    text:sub(1, 28), gap < 0 and "runs under" or "is tight to",
                    Round(math.abs(gap < 0 and gap or m.slotGap - gap)), Round(rowW), Round(Width(a.frame))))
                if gap < 0 then report.overlaps = report.overlaps + 1 end
            end
        end
    end

    local desc = f._description
    if desc and desc.IsShown and desc:IsShown() then
        local dw = Width(desc)
        if dw > 0 and dw < m.minDescWidth then
            report.push(string.format("  DESC    %-28s description wraps at %d", text:sub(1, 28), Round(dw)))
            report.narrowDescs = report.narrowDescs + 1
        end
    end
end

-- A slot row's mini-labels, from their drawn edges: neighbours closer than
-- slotGap, or a label past the cluster's edges. BuildSlotRow spaces them from
-- a build-time measure; this catches a measure that missed.
local function CheckMiniLabels(f, report)
    local slots, container = f._slots, f._slotContainer
    if type(slots) ~= "table" or not container then return end
    local okC, cLeft, cRight = pcall(function() return container:GetLeft(), container:GetRight() end)
    if not okC or type(cLeft) ~= "number" or type(cRight) ~= "number" then return end

    local gap = Controls.Metrics().slotGap
    local owner = OwnerLabel(f):sub(1, 28)
    local prevRight, prevText
    for _, slot in ipairs(slots) do
        local fs = slot._miniLabel
        local ok, left, right
        if fs then
            ok, left, right = pcall(function() return fs:GetLeft(), fs:GetRight() end)
        end
        if ok and type(left) == "number" and type(right) == "number" then
            local text = fs:GetText() or "?"
            report.miniLabels = report.miniLabels + 1
            if prevRight and left - prevRight < gap then
                report.push(string.format("  MINI    %-28s \"%s\" and \"%s\" are %d apart, need %d",
                    owner, prevText, text, Round(left - prevRight), gap))
                report.crowdedMinis = report.crowdedMinis + 1
            end
            if left < cLeft - 0.5 or right > cRight + 0.5 then
                report.push(string.format("  MINI    %-28s \"%s\" runs %d past the cluster",
                    owner, text, Round(math.max(cLeft - left, right - cRight))))
                report.crowdedMinis = report.crowdedMinis + 1
            end
            prevRight, prevText = right, text
        end
    end
end

local function CheckRegions(f, report)
    if not f.GetRegions then return end
    for _, region in ipairs({ f:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" and region.IsTruncated then
            local ok, truncated = pcall(region.IsTruncated, region)
            if ok and truncated == true then
                local t = region:GetText()
                report.push(string.format("  CUT     %-28s \"%s\"", OwnerLabel(f):sub(1, 28),
                    type(t) == "string" and t or "?"))
                report.truncated = report.truncated + 1
            end
        end
    end
end

local function Walk(frame, report, depth)
    if not frame or depth > 40 then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    CheckRow(frame, report)
    CheckMiniLabels(frame, report)
    CheckField(frame, report)
    CheckRegions(frame, report)
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            Walk(child, report, depth + 1)
        end
    end
end

local function NewReport(lines, push)
    return {
        lines = lines, push = push,
        fields = 0, rows = 0, miniLabels = 0, unresolved = 0,
        shortFields = 0, overlaps = 0, crowdedMinis = 0, zeroRows = 0, narrowDescs = 0, truncated = 0,
    }
end

local function AuditRoot(title, root, report)
    local before = #report.lines
    report.push(title)
    Walk(root, report, 0)
    if #report.lines == before + 1 then
        report.push("  (fits)")
    end
end

local function PanelContent()
    local panel = addon.UI.SettingsPanel
    local frame = panel and panel.frame
    local pane = frame and frame._contentPane
    return panel, pane and pane._scrollContent
end

local function Summary(report)
    local s = string.format(
        "%d fields, %d labelled rows, %d mini-labels checked; %d short fields, %d label overlaps, %d crowded mini-labels, %d narrow descriptions, %d zero-height rows, %d truncated strings",
        report.fields, report.rows, report.miniLabels, report.shortFields, report.overlaps,
        report.crowdedMinis, report.narrowDescs, report.zeroRows, report.truncated)
    if report.unresolved > 0 then
        s = s .. string.format("; %d unresolved (no layout yet: open the tab or section)", report.unresolved)
    end
    return s
end

local function ShowReport(report)
    local skinName = addon.UI.Skin and addon.UI.Skin.ActiveName() or "?"
    table.insert(report.lines, 1, "skin: " .. tostring(skinName))
    table.insert(report.lines, 2, Summary(report))
    table.insert(report.lines, 3, "")
    addon.DebugShowWindow("Fit", report.lines)
end

local function AuditExtraRoots(report)
    for label, getFrame in pairs(auditRoots) do
        local ok, frame = pcall(getFrame)
        if ok and frame and frame.IsShown and frame:IsShown() then
            AuditRoot(label, frame, report)
        end
    end
end

local function AuditOpenPage()
    local lines, push = addon.DebugLines()
    local report = NewReport(lines, push)
    local panel, content = PanelContent()
    if content and panel.frame:IsShown() then
        AuditRoot("page " .. tostring(panel._currentCategoryKey), content, report)
    else
        push("The settings panel is closed; open a page first.")
    end
    AuditExtraRoots(report)
    ShowReport(report)
end

-- Pages that open a confirmation or hold no rows.
local SKIP_PAGES = { search = true, startHere = true }

local function AuditAllPages()
    local panel, content = PanelContent()
    local lines, push = addon.DebugLines()
    local report = NewReport(lines, push)
    if not (content and panel.frame:IsShown() and panel._renderers) then
        push("The settings panel is closed; open it first.")
        ShowReport(report)
        return
    end

    local keys = {}
    for key in pairs(panel._renderers) do
        if not SKIP_PAGES[key] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    local returnKey = panel._currentCategoryKey

    -- One page per step: render, let the next-frame re-measure run, audit.
    local i = 0
    local function step()
        i = i + 1
        local key = keys[i]
        if not key then
            if returnKey then panel:OnNavigationSelect(returnKey) end
            ShowReport(report)
            return
        end
        local ok = pcall(panel.OnNavigationSelect, panel, key)
        C_Timer.After(0.25, function()
            local _, pageContent = PanelContent()
            if ok and pageContent then
                AuditRoot("page " .. key, pageContent, report)
            else
                push("page " .. key .. ": render failed")
            end
            step()
        end)
    end
    step()
end

addon:RegisterDebugCommand({
    name = "fit",
    help = "Fields, labels, and truncated text that do not fit on the open settings page; 'fit all' walks every page",
    handler = function(sub)
        if sub == "all" then
            AuditAllPages()
        else
            AuditOpenPage()
        end
    end,
})
