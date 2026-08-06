-- hover.lua — /scoot debug hover [seconds]
--
-- Answers one question: "what is eating my mouse at this spot?"
--
-- Frame LEVEL orders mouse hit-testing, not just drawing (see
-- ADDONCONTEXT/docs/framestrata.md). When a tooltip silently stops appearing,
-- nothing errors and nothing is visible -- some other mouse-enabled frame is
-- simply higher in the (strata -> level -> insertion order) sort at that pixel.
-- This probe names it.
--
-- Usage: /scoot debug hover        -- 5s to park the cursor, then reports
--        /scoot debug hover 10     -- longer arming window
--
-- Two independent readings, because they answer different halves:
--   1. GetMouseFoci() -- the game's own verdict. Whatever is first here is what
--      actually receives OnEnter. Authoritative, but only lists winners.
--   2. A full UIParent tree walk for every mouse-enabled frame whose rect
--      contains the cursor, sorted the way WoW sorts them. This is where the
--      LOSER shows up, which is the thing you are usually looking for.
local addonName, addon = ...

local STRATA_RANK = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local MAX_NODES = 40000      -- runaway guard for the tree walk
local MAX_REPORTED = 40

--------------------------------------------------------------------------------
-- Secret-safe accessors (type() -> issecretvalue() -> use; never compare raw)
--------------------------------------------------------------------------------

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function safeNum(frame, method)
    local v = safe(frame[method], frame)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function safeStr(frame, method)
    local v = safe(frame[method], frame)
    if type(v) ~= "string" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Unnamed frames are the norm for pooled icons, so identify by the nearest
-- named ancestor: "<unnamed> < <unnamed> < ScootCustomGroup1" is instantly
-- readable, where a raw table address is not.
local function ancestry(frame)
    local parts, node, hops = {}, frame, 0
    while node and hops < 12 do
        local n = safeStr(node, "GetName")
        if n and n ~= "" then
            table.insert(parts, n)
            return table.concat(parts, " < ")
        end
        table.insert(parts, "<unnamed>")
        node = safe(node.GetParent, node)
        hops = hops + 1
    end
    table.insert(parts, "?")
    return table.concat(parts, " < ")
end

--------------------------------------------------------------------------------
-- Tree walk
--------------------------------------------------------------------------------

local nodeCount = 0

-- Rects come back in the frame's own coordinate space; multiply by its
-- effective scale to compare against GetCursorPosition(), which is screen px.
local function containsCursor(frame, cx, cy)
    local l = safeNum(frame, "GetLeft")
    local r = safeNum(frame, "GetRight")
    local t = safeNum(frame, "GetTop")
    local b = safeNum(frame, "GetBottom")
    if not (l and r and t and b) then return false, nil end

    local scale = safeNum(frame, "GetEffectiveScale") or 1
    l, r, t, b = l * scale, r * scale, t * scale, b * scale
    if cx >= l and cx <= r and cy >= b and cy <= t then
        return true, { w = (r - l) / scale, h = (t - b) / scale }
    end
    return false, nil
end

-- Mouse input is TWO independent flags in modern WoW, and conflating them hides
-- exactly the bugs this probe exists to find. Blizzard's Cooldown Viewer items
-- are motion-only (CooldownViewer.lua:350-351), and the legacy IsMouseEnabled()
-- reports the CLICK flag -- so a click-only reading calls them mouse-dead and
-- they vanish from the report while still owning every tooltip in their rect.
-- A frame that is click-only is transparent to hover; a frame that is
-- motion-only is transparent to clicks. Report both, always.
local function mouseState(frame)
    local click, motion
    if frame.IsMouseClickEnabled then click = safe(frame.IsMouseClickEnabled, frame) end
    if frame.IsMouseMotionEnabled then motion = safe(frame.IsMouseMotionEnabled, frame) end
    if click == nil and motion == nil then
        local legacy = frame.IsMouseEnabled and safe(frame.IsMouseEnabled, frame)
        click, motion = legacy, legacy
    end
    return click and true or false, motion and true or false
end

local function mouseTag(click, motion)
    if click and motion then return "click+motion" end
    if motion then return "motion-only (hover, no clicks)" end
    if click then return "click-only (transparent to hover)" end
    return "none"
end

local function visit(frame, cx, cy, out)
    if nodeCount > MAX_NODES then return end
    nodeCount = nodeCount + 1

    if frame.IsForbidden and safe(frame.IsForbidden, frame) then return end
    -- A hidden frame hides its whole subtree, so this prunes as well as filters.
    if frame.IsVisible and not safe(frame.IsVisible, frame) then return end

    local inside, dims = containsCursor(frame, cx, cy)
    if inside then
        local click, motion = mouseState(frame)
        if click or motion then
            table.insert(out, {
                label   = ancestry(frame),
                strata  = safeStr(frame, "GetFrameStrata") or "?",
                level   = safeNum(frame, "GetFrameLevel") or 0,
                w       = dims and dims.w or 0,
                h       = dims and dims.h or 0,
                mouse   = mouseTag(click, motion),
                motion  = motion,
                onEnter = frame.GetScript and safe(frame.GetScript, frame, "OnEnter") ~= nil,
                onClick = frame.GetScript and safe(frame.GetScript, frame, "OnClick") ~= nil,
            })
        end
    end

    -- Recurse regardless of containment: children can extend past the parent rect.
    if frame.GetChildren then
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok and children then
            for _, child in ipairs(children) do
                if child then visit(child, cx, cy, out) end
            end
        end
    end
end

local function sortHits(hits)
    table.sort(hits, function(a, b)
        local ra = STRATA_RANK[a.strata] or 0
        local rb = STRATA_RANK[b.strata] or 0
        if ra ~= rb then return ra > rb end
        if a.level ~= b.level then return a.level > b.level end
        return (a.label or "") < (b.label or "")
    end)
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function buildReport(cx, cy, foci, hits)
    local lines = {}
    local function add(fmt, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    add("Hover probe — what owns the mouse at this pixel")
    add(string.rep("=", 68))
    add("Cursor: %.1f, %.1f (screen px)   UIParent scale: %.3f",
        cx, cy, UIParent:GetEffectiveScale())
    add("")

    add("1. GetMouseFoci() — the game's own verdict (first = receives OnEnter)")
    add(string.rep("-", 68))
    if not foci or #foci == 0 then
        add("  (nothing — cursor is over no mouse-enabled frame)")
    else
        for i, region in ipairs(foci) do
            add("  %d. %s", i, ancestry(region))
            add("       strata %s  level %s",
                safeStr(region, "GetFrameStrata") or "?",
                tostring(safeNum(region, "GetFrameLevel") or "?"))
        end
    end
    add("")

    add("2. Every mouse-enabled frame containing the cursor (UIParent + WorldFrame)")
    add(string.rep("-", 68))
    add("   (topmost first: strata, then level. Mouse input is two independent")
    add("    flags -- only motion-enabled frames compete for HOVER, only")
    add("    click-enabled frames compete for CLICKS, so a click-only frame can")
    add("    sit at #1 and still let every tooltip through.)")
    add("")
    if #hits == 0 then
        add("  (none)")
    else
        local hoverWinnerSeen = false
        for i, h in ipairs(hits) do
            if i > MAX_REPORTED then
                add("  ... and %d more", #hits - MAX_REPORTED)
                break
            end
            local scripts = {}
            if h.onEnter then table.insert(scripts, "OnEnter") end
            if h.onClick then table.insert(scripts, "OnClick") end

            -- Only motion-enabled frames compete for hover, so the first one of
            -- those is the frame that owns the tooltip here -- which is not
            -- necessarily #1 overall.
            local marker = ""
            if h.motion and not hoverWinnerSeen then
                hoverWinnerSeen = true
                marker = "   <== OWNS HOVER HERE"
            end

            add("  %2d. [%s %d] %s%s", i, h.strata, h.level, h.label, marker)
            add("        %.0fx%.0f   mouse: %s%s", h.w, h.h, h.mouse,
                #scripts > 0 and ("   scripts: " .. table.concat(scripts, ", ")) or "")
        end
    end
    add("")
    add("Ladder reference: ADDONCONTEXT/docs/framestrata.md")
    add("Frames walked: %d%s", nodeCount, nodeCount > MAX_NODES and " (CAPPED)" or "")

    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

local armed = false

function addon.DebugHover(arg)
    if armed then
        addon:Print("Hover probe already armed.")
        return
    end

    local delay = tonumber(arg) or 5
    if delay < 1 then delay = 1 end
    if delay > 60 then delay = 60 end

    armed = true
    addon:Print(string.format(
        "Hover probe armed — park the cursor on the frame in question. Sampling in %ds.", delay))

    -- Sample repeatedly and keep the last reading that found anything, so a
    -- slightly-off cursor at the exact deadline does not waste the run.
    local best = nil
    local ticker
    ticker = C_Timer.NewTicker(0.1, function()
        local cx, cy = GetCursorPosition()
        if type(cx) ~= "number" or type(cy) ~= "number" then return end

        local foci = GetMouseFoci and GetMouseFoci() or nil
        if (foci and #foci > 0) then
            best = { cx = cx, cy = cy, foci = foci }
        elseif not best then
            best = { cx = cx, cy = cy, foci = foci }
        end
    end, math.floor(delay / 0.1))

    C_Timer.After(delay + 0.05, function()
        armed = false
        if ticker then ticker:Cancel() end

        local cx, cy = GetCursorPosition()
        local foci = GetMouseFoci and GetMouseFoci() or nil
        if best and (not foci or #foci == 0) then
            cx, cy, foci = best.cx, best.cy, best.foci
        end

        nodeCount = 0
        local hits = {}
        -- Both roots: nameplates (and therefore the Personal Resource Display)
        -- are children of WorldFrame, not UIParent, so a UIParent-only walk
        -- would silently miss the most likely competitor under the player.
        visit(UIParent, cx, cy, hits)
        if WorldFrame then visit(WorldFrame, cx, cy, hits) end
        sortHits(hits)

        local text = buildReport(cx, cy, foci, hits)
        if addon.DebugShowWindow then
            addon.DebugShowWindow("Hover Probe", text)
        else
            addon:Print("DebugShowWindow not available.")
        end
    end)
end
