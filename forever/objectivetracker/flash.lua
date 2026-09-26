--------------------------------------------------------------------------------
-- forever/objectivetracker/flash.lua
-- The progress flash in the Current Objectives pane: when an objective's
-- count rises, the count ("5/10") in the pane's line flares white-gold, eases
-- to quest gold, and fades back to the line's own color, while a burst of
-- light plays behind it: the vanilla quest log's selection glow as a gold
-- band across the line, and the cooldown finish star behind the count. Both
-- are additive and drawn under the text, so they light the line without
-- covering it.
--
-- The color is written as a color
-- escape through the line's own SetText: an escape takes no width, so the
-- line wraps and measures as before, and core/fontpair.lua strips escapes
-- before mirroring text into a Deep Shadow copy. The lines are the pane
-- module's own, and the tracker has no protected frame.
--
-- current.lua requests a flash when its diff reads a rise. The pane lays the
-- quest out a frame or more later, so a request waits until the pane's line
-- shows the new count, and is dropped if it never does: the quest did not
-- come to the pane.
--------------------------------------------------------------------------------

local addonName, addon = ...

local OT = addon.ObjectiveTracker
local Style = OT.Style

local Flash = {}
OT.Flash = Flash

local CURRENT_MODULE = "CamelotCurrentQuestObjectiveTracker"

local HOT = { 1, 0.96, 0.72 }
local GOLD = { 1, 0.82, 0 }
local HOLD_END = 0.12  -- hot until here
local GOLD_AT = 0.4    -- hot eases to gold by here
local DURATION = 1.3   -- gold eases to the line's color by here
local REQUEST_TTL = 2

-- The burst: two vanilla textures, both still in the client.
local WASH_TEXTURE = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local STAR_TEXTURE = "Interface\\Cooldown\\star4"
local STAR_TINT = { 1, 0.9, 0.55 }
local WASH_PEAK = 0.6
local WASH_PAD_X, WASH_PAD_Y = 12, 4
local STAR_SIZE = 2.6    -- times the font size
local BURST_LENGTH = 1.2

local pending = {} -- questID -> { index, count, t }
local running = {} -- questID -> { line, index, base, prefix, count, suffix, t }

local function enabled()
    return OT.Current and OT.Current.Enabled() and Style.Get("current", "flashProgress") == true
end

local function isPlain(v)
    return not (issecretvalue and issecretvalue(v))
end

local function smooth(x)
    if x <= 0 then return 0 end
    if x >= 1 then return 1 end
    return x * x * (3 - 2 * x)
end

local function lerp(a, b, x)
    return a[1] + (b[1] - a[1]) * x, a[2] + (b[2] - a[2]) * x, a[3] + (b[3] - a[3]) * x
end

local function colorAt(elapsed, base)
    if elapsed < HOLD_END then return HOT[1], HOT[2], HOT[3] end
    if elapsed < GOLD_AT then
        return lerp(HOT, GOLD, smooth((elapsed - HOLD_END) / (GOLD_AT - HOLD_END)))
    end
    return lerp(GOLD, base, smooth((elapsed - GOLD_AT) / (DURATION - GOLD_AT)))
end

local function hex(v)
    return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
end

local function lineText(line)
    local fs = line and line.Text
    if not fs then return nil end
    local text = fs:GetText()
    if type(text) ~= "string" or not isPlain(text) then return nil end
    return text
end

-- The count as its own number: "5/10" inside "15/100" does not count.
local function findCount(text, count)
    local from = 1
    while true do
        local s, e = string.find(text, count, from, true)
        if not s then return nil end
        local before = s > 1 and text:sub(s - 1, s - 1) or ""
        local after = text:sub(e + 1, e + 1)
        if not before:match("%d") and not after:match("%d") then return s, e end
        from = s + 1
    end
end

local function paneLine(questID, index)
    local module = _G[CURRENT_MODULE]
    if not (module and module.usedBlocks) then return nil end
    local block = module:GetExistingBlock(questID)
    if not block or type(block.GetExistingLine) ~= "function" then return nil end
    return block:GetExistingLine(index)
end

local function lineStillOurs(f, questID)
    local line = f.line
    return line.objectiveKey == f.index and line.parentBlock and line.parentBlock.id == questID
end

--------------------------------------------------------------------------------
-- The burst
--------------------------------------------------------------------------------

local function alphaAnim(group, target, from, to, delay, duration, smoothing)
    local a = group:CreateAnimation("Alpha")
    a:SetTarget(target)
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetStartDelay(delay)
    a:SetDuration(duration)
    a:SetOrder(1)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local burstPool

local function createBurst()
    local f = CreateFrame("Frame")
    f:Hide()

    local wash = f:CreateTexture(nil, "BACKGROUND")
    wash:SetTexture(WASH_TEXTURE)
    wash:SetBlendMode("ADD")
    wash:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    wash:SetAlpha(0)
    f.wash = wash

    local star = f:CreateTexture(nil, "BORDER")
    star:SetTexture(STAR_TEXTURE)
    star:SetBlendMode("ADD")
    star:SetVertexColor(STAR_TINT[1], STAR_TINT[2], STAR_TINT[3])
    star:SetAlpha(0)
    f.star = star

    local group = f:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    -- The band: up fast with the text's white-gold, then a long fade.
    alphaAnim(group, wash, 0, WASH_PEAK, 0, 0.1)
    alphaAnim(group, wash, WASH_PEAK, 0, 0.3, BURST_LENGTH - 0.3, "IN")
    -- The star: flares, opens and turns 50 degrees, gone by the time the text
    -- has eased to gold.
    alphaAnim(group, star, 0, 1, 0, 0.06)
    alphaAnim(group, star, 1, 0, 0.14, 0.5, "IN")
    local grow = group:CreateAnimation("Scale")
    grow:SetTarget(star)
    grow:SetScaleFrom(0.35, 0.35)
    grow:SetScaleTo(1.25, 1.25)
    grow:SetDuration(0.4)
    grow:SetSmoothing("OUT")
    grow:SetOrder(1)
    local turn = group:CreateAnimation("Rotation")
    turn:SetTarget(star)
    turn:SetDegrees(-50)
    turn:SetDuration(0.64)
    turn:SetOrder(1)
    group:SetScript("OnFinished", function() burstPool:Release(f) end)
    f.group = group
    return f
end

burstPool = addon.Pool.New(createBurst, function(f)
    f.group:Stop()
    f:Hide()
    f:ClearAllPoints()
    f.wash:ClearAllPoints()
    f.star:ClearAllPoints()
end)

local function measure(text, face, size)
    if text == "" then return 0 end
    return addon.MeasureTextWidth(text, face, size) or 0
end

-- The band behind the whole line, the star on the count. The count's place is
-- measured from the prefix; when the prefix and count overrun the line's width
-- the text has wrapped, and the star sits on the line's center instead.
local function playBurst(line, prefix, count)
    local fs = line.Text
    local container = _G.CamelotCurrentObjectiveTracker
    if not (fs and container) then return end
    local face, size = fs:GetFont()
    if type(size) ~= "number" or size <= 0 then return end

    local f = burstPool:Acquire()
    f:SetParent(container)
    f:SetFrameStrata(container:GetFrameStrata())
    -- One below the line: under its text, above the block and the background.
    f:SetFrameLevel(math.max(line:GetFrameLevel() - 1, container:GetFrameLevel() + 1))
    f:SetAllPoints(container)

    f.wash:SetPoint("TOPLEFT", fs, "TOPLEFT", -WASH_PAD_X, WASH_PAD_Y)
    f.wash:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", WASH_PAD_X, -WASH_PAD_Y)

    local starSize = size * STAR_SIZE
    f.star:SetSize(starSize, starSize)
    local prefixW, countW = measure(prefix, face, size), measure(count, face, size)
    if face and prefixW + countW <= fs:GetWidth() + 1 then
        f.star:SetPoint("CENTER", fs, "TOPLEFT", prefixW + countW / 2, -size / 2)
    else
        f.star:SetPoint("CENTER", fs, "CENTER")
    end

    f:Show()
    f.group:Play()
end

-- Starts a pending request once the pane's line shows the new count. With the
-- count nowhere in the text (a percentage objective, another format), the
-- whole line flashes.
local function tryStart(questID, req, t)
    local line = paneLine(questID, req.index)
    local text = lineText(line)
    if not text then return false end
    text = addon.FontPair.StripEscapes(text)
    local s, e = findCount(text, req.count)
    if not s then
        -- The line still shows the old count until the pane's next layout.
        if text:find("%d+/%d+") then return false end
        s, e = 1, #text
    end
    local f = {
        line = line, index = req.index, base = text, t = t,
        prefix = text:sub(1, s - 1), count = text:sub(s, e), suffix = text:sub(e + 1),
    }
    running[questID] = f
    playBurst(line, f.prefix, f.count)
    return true
end

-- Returns false once the flash is over.
local function step(questID, f, t)
    local fs = f.line.Text
    if not lineStillOurs(f, questID) then return false end
    local text = lineText(f.line)
    if not text or addon.FontPair.StripEscapes(text) ~= f.base then
        -- Blizzard relaid the line with new text; a newer request owns it.
        return false
    end
    local elapsed = t - f.t
    if elapsed >= DURATION then
        fs:SetText(f.base)
        return false
    end
    local ok, br, bg, bb = pcall(fs.GetTextColor, fs)
    if not (ok and type(br) == "number" and isPlain(br)) then br, bg, bb = 1, 1, 1 end
    local r, g, b = colorAt(elapsed, { br, bg, bb })
    fs:SetText(string.format("%s|cff%02x%02x%02x%s|r%s", f.prefix, hex(r), hex(g), hex(b), f.count, f.suffix))
    return true
end

local driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function(self)
    local t = GetTime()
    for questID, req in pairs(pending) do
        if tryStart(questID, req, t) or t - req.t > REQUEST_TTL then
            pending[questID] = nil
        end
    end
    for questID, f in pairs(running) do
        if not step(questID, f, t) then running[questID] = nil end
    end
    if next(pending) == nil and next(running) == nil then self:Hide() end
end)

--- From current.lua when an objective's count rises. A newer request for
--- the same quest replaces an older one.
function Flash.Request(questID, index, fulfilled, required)
    if not enabled() then return end
    if type(fulfilled) ~= "number" or type(required) ~= "number" then return end
    -- A flash still running on the quest gives its line back plain.
    local old = running[questID]
    if old then
        local text = lineText(old.line)
        if text and lineStillOurs(old, questID) and addon.FontPair.StripEscapes(text) == old.base then
            old.line.Text:SetText(old.base)
        end
        running[questID] = nil
    end
    pending[questID] = { index = index, count = fulfilled .. "/" .. required, t = GetTime() }
    driver:Show()
end

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

function Flash.Dump(push)
    local t = GetTime()
    push("progress flash: %s", enabled() and "on" or "off")
    for questID, req in pairs(pending) do
        push("  pending %d objective %d, count %s, %.1fs old", questID, req.index, req.count, t - req.t)
    end
    for questID, f in pairs(running) do
        push("  running %d objective %d, %q at %.2fs", questID, f.index, f.count, t - f.t)
    end
end
