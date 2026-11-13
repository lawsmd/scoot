--------------------------------------------------------------------------------
-- core/boxhost.lua
-- A Blizzard edit box drawn inside a window the addon owns.
--
-- The client reads some text (a group listing's comment, a search's text)
-- from its own registered edit boxes and from nowhere else, and those boxes
-- refuse SetText from addon code. A window that needs such text shows
-- Blizzard's box in place of drawing its own: the box is anchored into a
-- holder frame of the window with SetIgnoreParentAlpha and
-- SetIgnoreParentScale, at the holder's effective scale and strata, so it
-- draws there while its own Blizzard parent is out of sight. On release the
-- box goes back to the points, strata, level, scale, font, color and insets
-- it was taken with.
--
-- Every call here is a method on a Blizzard frame outside the Edit Mode
-- system set; nothing writes a field on one. The caller owns the Blizzard
-- panel the box belongs to: a box renders only while every ancestor is
-- shown, so the caller keeps that chain shown and out of sight.
--------------------------------------------------------------------------------

local addonName, addon = ...

local SS = addon.SecretSafe

local BoxHost = {}
addon.BoxHost = BoxHost

local taken = {}          -- key -> the record of a hosted box
local focusHooked = {}    -- box -> true once its focus scripts are hooked
local hoverHooked = {}    -- art child -> true once its hover scripts are hooked

-- The border pieces of a scrolling text box's template, put at alpha 0
-- while the box is hosted in a holder with a look of its own
BoxHost.SCROLL_BOX_ART = {
    "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex", "BottomRightTex",
    "BottomTex", "LeftTex", "RightTex", "MiddleTex",
}

local function Theme()
    return addon.UI.Theme
end

local function Controls()
    return addon.UI.Controls
end

local function plainBool(v)
    if type(v) ~= "boolean" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

--------------------------------------------------------------------------------
-- The holder: the single-line edit box's flat look around a hosted box
--------------------------------------------------------------------------------

-- fill, optional: AddBackground's color, the edit box's near black if nil
function BoxHost.DressHolder(holder, fill)
    local C = Controls()
    holder._bg = C.AddBackground(holder, { inset = 1, color = fill })
    holder._border = C.CreateBorder(holder, {
        thickness = 1,
        alpha = 0.6,
        getAlpha = function() return holder._focused and 1 or 0.6 end,
    })
    holder._focused = false
    return holder
end

local function SetHolderFocus(holder, focused)
    if not holder then return end
    holder._focused = focused and true or false
    if holder._border and holder._border.Refresh then holder._border:Refresh() end
end

--------------------------------------------------------------------------------
-- Take and release
--------------------------------------------------------------------------------

-- A region's points, read under pcall; a point that comes back secret is
-- dropped
local function CapturePoints(region)
    local points = {}
    local okN, n = pcall(region.GetNumPoints, region)
    if okN and type(n) == "number" then
        for i = 1, n do
            local ok, point, rel, relPoint, x, y = pcall(region.GetPoint, region, i)
            point = ok and SS.plainString(point) or nil
            if point then
                points[#points + 1] = {
                    point, SS.plainFrame(rel), SS.plainString(relPoint), SS.safeOffset(x), SS.safeOffset(y),
                }
            end
        end
    end
    return points
end

local function RestorePoints(region, points)
    region:ClearAllPoints()
    for _, p in ipairs(points) do
        region:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
    end
end

-- The points, strata and level the box had, read under pcall; a value that
-- comes back secret is dropped and the caller's fallback points stand in
local function Capture(box)
    local rec = { points = CapturePoints(box), regions = {} }
    local okS, strata = pcall(box.GetFrameStrata, box)
    if okS then rec.strata = SS.plainString(strata) end
    local okL, level = pcall(box.GetFrameLevel, box)
    if okL then rec.level = SS.safeNumber(level) end
    local okC, scale = pcall(box.GetScale, box)
    if okC then rec.scale = SS.safeNumber(scale) end
    return rec
end

-- A hosted box ignores its parents' scale, since its parked panel is a dot;
-- on its own it would render at scale 1 while the window renders at the UI
-- scale, so it takes the holder's effective scale as its own
local function MatchScale(rec)
    local holder = rec.holder
    if not (holder and rec.box and rec.box.SetScale) then return end
    local scale = holder:GetEffectiveScale()
    if type(scale) == "number" and scale > 0 then
        rec.box:SetScale(scale)
    end
end

local function BlankRegion(rec, region)
    if not region or not region.SetAlpha then return end
    local ok, alpha = pcall(region.GetAlpha, region)
    rec.regions[#rec.regions + 1] = { region = region, alpha = (ok and SS.safeNumber(alpha)) or 1 }
    region:SetAlpha(0)
end

-- A child's own hover scripts put its art back (the clear button's icon
-- comes up at half alpha on leave), so while the box is hosted the art goes
-- back down after each
local function HookChildHover(key, child)
    if hoverHooked[child] or not child.HookScript then return end
    hoverHooked[child] = true
    local function reblank()
        local live = taken[key]
        if not live then return end
        for _, entry in ipairs(live.regions) do
            entry.region:SetAlpha(0)
        end
    end
    child:HookScript("OnEnter", reblank)
    child:HookScript("OnLeave", reblank)
end

-- The template's own art: the named regions of the box, and every texture of
-- the child frames named (the clear button)
local function BlankArt(rec, box, opts)
    for _, key in ipairs(opts.artKeys or {}) do
        BlankRegion(rec, box[key])
    end
    for _, key in ipairs(opts.artFrames or {}) do
        local child = box[key]
        if child and child.GetRegions then
            for _, region in ipairs({ child:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") then
                    BlankRegion(rec, region)
                end
            end
            HookChildHover(rec.key, child)
        end
    end
end

-- A region's font and text color as they stand, for the release to put
-- back; a value that reads secret is dropped and that part stays
local function CaptureText(region)
    local font, color
    local okF, path, size, flags = pcall(region.GetFont, region)
    if okF and SS.plainString(path) then
        font = { path, SS.safeNumber(size), SS.plainString(flags) }
    end
    local okC, r, g, b, a = pcall(region.GetTextColor, region)
    if okC and SS.safeNumber(r) then
        color = { SS.safeNumber(r), SS.safeNumber(g) or 1, SS.safeNumber(b) or 1, SS.safeNumber(a) or 1 }
    end
    return font, color
end

local function RestoreText(region, font, color)
    if not region then return end
    if font and region.SetFont then
        pcall(region.SetFont, region, font[1], font[2] or 12, font[3] or "")
    end
    if color and region.SetTextColor then
        region:SetTextColor(color[1], color[2], color[3], color[4])
    end
end

-- The box's text insets as they stand, for the release to put back; a
-- value that reads secret is dropped and the insets stay
local function CaptureInsets(editBox)
    if not editBox.GetTextInsets then return nil end
    local ok, left, right, top, bottom = pcall(editBox.GetTextInsets, editBox)
    if not ok then return nil end
    left, right, top, bottom = SS.safeNumber(left), SS.safeNumber(right), SS.safeNumber(top), SS.safeNumber(bottom)
    if not (left and right and top and bottom) then return nil end
    return { left, right, top, bottom }
end

-- The skin's value face on the text, at the caller's size when it names
-- one, primary color, and the instructions line dim. The style is named
-- so no companion string is attached to a box the player types into. The
-- box's and the instructions' own font and color, and the box's text
-- insets, are kept for the release, so Blizzard's window reads as its own
-- again: the search box's template keeps its text clear of the glass.
-- A caller whose window wears Blizzard's look passes opts.style false and
-- the box keeps its own face, color and instructions.
local function Style(rec, opts)
    local editBox = rec.editBox
    if not editBox then return end
    if opts.textInsets then
        rec.textInsets = CaptureInsets(editBox)
        editBox:SetTextInsets(unpack(opts.textInsets))
    end
    if opts.style == false then return end
    local theme = Theme()
    rec.font, rec.textColor = CaptureText(editBox)
    theme:ApplyFont(editBox, "value", opts.fontSize, "NONE")
    local pr, pg, pb = theme:GetPrimaryTextColor()
    editBox:SetTextColor(pr, pg, pb, 1)
    local instructions = editBox.Instructions
    if instructions and instructions.SetFont then
        rec.instructionsFont, rec.instructionsColor = CaptureText(instructions)
        theme:ApplyFont(instructions, "value", opts.fontSize, "NONE")
        local dr, dg, db = theme:GetDimTextColor()
        instructions:SetTextColor(dr, dg, db, 0.7)
        -- A box whose template lays the instructions over its whole rect
        -- (the finder's single-line boxes) gets them inset as its text is,
        -- on one line
        if opts.instructionsInsets then
            local points = CapturePoints(instructions)
            if #points > 0 then
                rec.instructionsPoints = points
                local okW, wrap = pcall(instructions.GetWordWrap, instructions)
                rec.instructionsWrap = okW and plainBool(wrap) or nil
            end
            local left, right, top, bottom = unpack(opts.instructionsInsets)
            instructions:ClearAllPoints()
            instructions:SetPoint("TOPLEFT", editBox, "TOPLEFT", left, -top)
            instructions:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", -right, bottom)
            instructions:SetWordWrap(false)
        end
    end
end

local function HookFocus(rec)
    local editBox = rec.editBox
    if not editBox or focusHooked[editBox] then return end
    focusHooked[editBox] = true
    local key = rec.key
    editBox:HookScript("OnEditFocusGained", function()
        local live = taken[key]
        if live then SetHolderFocus(live.holder, true) end
    end)
    editBox:HookScript("OnEditFocusLost", function()
        local live = taken[key]
        if live then SetHolderFocus(live.holder, false) end
    end)
end

-- key        the host's name for the box ("search", "note"); one namespace
--            for the addon, so a caller prefixes its own
-- box        the Blizzard frame moved: the EditBox itself, or the ScrollFrame
--            that holds one
-- holder     the addon's frame it fills
-- opts.editBox      the text region to style when box is a ScrollFrame
-- opts.inset        { left, right, top, bottom } inside the holder; default 1
-- opts.artKeys      region keys on box to put at alpha 0
-- opts.artFrames    child frame keys whose textures go to alpha 0
-- opts.style        false to leave the box's own font, color and
--                   instructions as Blizzard drew them
-- opts.textInsets   { left, right, top, bottom } for SetTextInsets
-- opts.instructionsInsets  { left, right, top, bottom }: the instructions
--                   line anchored this far inside the box, unwrapped; its
--                   own points and wrap come back on release
-- opts.fontSize     the text's size in the value face, in place of the role's
-- opts.editBoxWidth the width for the text region inside a ScrollFrame box,
--                   which takes its width once at load and not from its
--                   frame; its own width comes back on release
-- opts.scrollBarScale  the scale of a ScrollFrame box's bar, for a holder
--                   smaller than the box's own window; 1 again on release
-- opts.fallbackPoints  the points to restore when none could be read
function BoxHost.Take(key, box, holder, opts)
    opts = opts or {}
    if not box or not holder then return false end
    local rec = taken[key]
    if not (rec and rec.box == box) then
        if rec then BoxHost.Release(key) end
        rec = Capture(box)
        rec.key = key
        rec.box = box
        rec.editBox = opts.editBox or box
        rec.fallbackPoints = opts.fallbackPoints
        taken[key] = rec
        BlankArt(rec, box, opts)
        Style(rec, opts)
        HookFocus(rec)
    end
    rec.holder = holder
    local inset = opts.inset or {}
    local left, right = inset.left or 1, inset.right or 1
    local top, bottom = inset.top or 1, inset.bottom or 1
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", holder, "TOPLEFT", left, -top)
    box:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -right, bottom)
    box:SetIgnoreParentAlpha(true)
    -- The parked panel is a dot; the box renders at the window's scale
    if box.SetIgnoreParentScale then box:SetIgnoreParentScale(true) end
    MatchScale(rec)
    -- A box whose chain is not in the window's strata takes it here
    local okS, boxStrata = pcall(box.GetFrameStrata, box)
    if not (okS and boxStrata == holder:GetFrameStrata()) then
        box:SetFrameStrata(holder:GetFrameStrata())
    end
    box:SetFrameLevel(holder:GetFrameLevel() + 1)
    local editBox = rec.editBox
    if opts.editBoxWidth and editBox ~= box and editBox.SetWidth then
        if not rec.editBoxWidth then
            local okW, w = pcall(editBox.GetWidth, editBox)
            rec.editBoxWidth = (okW and SS.safeNumber(w)) or 0
        end
        editBox:SetWidth(math.max(1, opts.editBoxWidth))
        if editBox.Instructions and editBox.Instructions.SetWidth then
            editBox.Instructions:SetWidth(math.max(1, opts.editBoxWidth))
        end
    end
    local bar = box.ScrollBar
    if opts.scrollBarScale and bar and bar.SetScale then
        bar:SetScale(opts.scrollBarScale)
        rec.scrollBar = bar
    end
    -- An ancestor that clips its children to its own rect would clip the box
    -- out of the window; none is known, and one found is opened for the stay
    rec.unclipped = rec.unclipped or {}
    local f = box
    for _ = 1, 10 do
        local okP, parent = pcall(f.GetParent, f)
        f = okP and parent or nil
        if not f or f == UIParent then break end
        local okC, clips = pcall(f.DoesClipChildren, f)
        if okC and clips == true then
            f:SetClipsChildren(false)
            rec.unclipped[#rec.unclipped + 1] = f
        end
    end
    SetHolderFocus(holder, box.HasFocus and box:HasFocus() or (rec.editBox.HasFocus and rec.editBox:HasFocus()))
    return true
end

function BoxHost.IsTaken(key)
    return taken[key] ~= nil
end

function BoxHost.AnyTaken()
    return next(taken) ~= nil
end

function BoxHost.Release(key)
    local rec = taken[key]
    if not rec then return end
    local box = rec.box
    taken[key] = nil
    box:ClearAllPoints()
    local points = (#rec.points > 0) and rec.points or rec.fallbackPoints
    for _, p in ipairs(points or {}) do
        box:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
    end
    box:SetIgnoreParentAlpha(false)
    if box.SetScale then box:SetScale(rec.scale or 1) end
    if box.SetIgnoreParentScale then box:SetIgnoreParentScale(false) end
    if rec.strata then box:SetFrameStrata(rec.strata) end
    if rec.level then box:SetFrameLevel(rec.level) end
    for _, entry in ipairs(rec.regions) do
        entry.region:SetAlpha(entry.alpha)
    end
    RestoreText(rec.editBox, rec.font, rec.textColor)
    if rec.editBox then
        local instructions = rec.editBox.Instructions
        RestoreText(instructions, rec.instructionsFont, rec.instructionsColor)
        if instructions and rec.instructionsPoints then
            RestorePoints(instructions, rec.instructionsPoints)
            if rec.instructionsWrap ~= nil then instructions:SetWordWrap(rec.instructionsWrap) end
        end
        if rec.textInsets and rec.editBox.SetTextInsets then
            rec.editBox:SetTextInsets(unpack(rec.textInsets))
        end
    end
    if rec.editBoxWidth and rec.editBoxWidth > 0 and rec.editBox and rec.editBox.SetWidth then
        rec.editBox:SetWidth(rec.editBoxWidth)
        if rec.editBox.Instructions and rec.editBox.Instructions.SetWidth then
            rec.editBox.Instructions:SetWidth(rec.editBoxWidth)
        end
    end
    if rec.scrollBar then rec.scrollBar:SetScale(1) end
    for _, f in ipairs(rec.unclipped or {}) do
        if f.SetClipsChildren then f:SetClipsChildren(true) end
    end
    SetHolderFocus(rec.holder, false)
end

function BoxHost.ReleaseAll()
    for key in pairs(taken) do
        BoxHost.Release(key)
    end
end

-- Every hosted box back to its holder's scale, after the UI scale or the
-- display size changes under an open window
function BoxHost.SyncScale()
    for _, rec in pairs(taken) do
        MatchScale(rec)
    end
end

--------------------------------------------------------------------------------
-- Debug: lines for a caller's own debug window
--------------------------------------------------------------------------------

function BoxHost.Describe(push, label, frame)
    if not frame then
        push("%s: nil", label)
        return
    end
    local function get(method, ...)
        if not frame[method] then return "-" end
        local ok, a, b, c, d = pcall(frame[method], frame, ...)
        if not ok then return "err" end
        if b ~= nil then return tostring(a) .. "," .. tostring(b) .. "," .. tostring(c) .. "," .. tostring(d) end
        return tostring(a)
    end
    push("%s: %s shown=%s visible=%s alpha=%s eff=%s ignoreParent=%s strata=%s level=%s mouse=%s clips=%s scale=%s",
        label, get("GetName"), get("IsShown"), get("IsVisible"), get("GetAlpha"), get("GetEffectiveAlpha"),
        get("IsIgnoringParentAlpha"), get("GetFrameStrata"), get("GetFrameLevel"), get("IsMouseEnabled"),
        get("DoesClipChildren"), get("GetEffectiveScale"))
    push("    rect left=%s bottom=%s w=%s h=%s points=%s",
        get("GetLeft"), get("GetBottom"), get("GetWidth"), get("GetHeight"), get("GetNumPoints"))
end

function BoxHost.DumpChain(push, label, frame)
    local depth = 0
    local f = frame
    while f and depth < 10 do
        BoxHost.Describe(push, string.format("%s[%d]", label, depth), f)
        local ok, parent = pcall(f.GetParent, f)
        f = ok and parent or nil
        depth = depth + 1
    end
end

-- Every hosted box: its holder, its chain of parents, its text region
function BoxHost.DumpTaken(push)
    for key, rec in pairs(taken) do
        push("")
        push("hosted %s: points captured=%d regions blanked=%d font=%s",
            key, #rec.points, #rec.regions, rec.font and (tostring(rec.font[1]) .. " " .. tostring(rec.font[2])) or "-")
        BoxHost.Describe(push, "holder", rec.holder)
        BoxHost.DumpChain(push, "box", rec.box)
        if rec.editBox and rec.editBox ~= rec.box then
            BoxHost.Describe(push, "editBox", rec.editBox)
        end
        local eb = rec.editBox
        if eb then
            local okF, path, size, flags = pcall(eb.GetFont, eb)
            push("    editBox font=%s %s %s focus=%s insets=%s",
                okF and tostring(path) or "err", tostring(size), tostring(flags),
                eb.HasFocus and tostring(eb:HasFocus()) or "-",
                eb.GetTextInsets and table.concat({ eb:GetTextInsets() }, ",") or "-")
            if eb.Instructions then
                BoxHost.Describe(push, "    instructions", eb.Instructions)
                local okT, text = pcall(eb.Instructions.GetText, eb.Instructions)
                push("    instructions text=%s", okT and tostring(text) or "err")
            end
            local okText, boxText = pcall(eb.GetText, eb)
            push("    editBox text=%s textColor=%s", okText and tostring(boxText) or "err",
                eb.GetTextColor and table.concat({ eb:GetTextColor() }, ",") or "-")
        end
    end
end
