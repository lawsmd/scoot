-- unitframesz/ping.lua - Unit Frames Z: the 12.1 ping receiver
--
-- Split out of engine.lua. The engine reaches the three workers here at call
-- time (UFZ._BuildPingReceiver from ensureFrame, _WirePingReceiver from
-- _ApplyAll, _ApplyPingRect from applyEnvelope and resolveNameInk), so this
-- file loads after it. The one engine internal it needs, the name row's rect,
-- is captured below.

local addonName, addon = ...
local UFZ = addon.UnitFramesZ
local nameRowRect = UFZ._NameRowRect

--------------------------------------------------------------------------------
-- Ping receiver (12.1)
--------------------------------------------------------------------------------
-- 12.1 rebuilt the ping system around an opt-in attribute.
-- C_PingSecure.GetTargetPingReceiver runs a C-side hit test for the frame under
-- the cursor carrying "ping-receiver", then PingManager calls GetIsPingable /
-- GetAllowRadialWheel / GetTargetInfo on it inside securecallfunction and
-- securecopies the answer (Blizzard_PingManager.lua:109-134). C_PingSecure is
-- SecureOnly, so Scoot can never SEND a ping; it can only satisfy the contract
-- and let Blizzard's own code send it. UFZ parks PlayerFrame, TargetFrame and
-- BossTargetFrameContainer, so without this the frames it replaces lose both the
-- plain unit ping and 12.1's health/mana callout.
--
-- MIXIN PURITY, every unit but the player. Blizzard's PingableType_UnitFrameMixin
-- is used verbatim and never overridden. Addon Lua in that gather makes a SECRET
-- GUID inaccessible to the securecopy at the secure boundary, which hard-errors
-- and wedges the ping listener; guarding with issecretvalue instead kills pings
-- outright in every restricted instance. Both shapes were tried in the field by
-- another addon and both failed. For the same reason the receiver must never
-- carry a .unit FIELD: the mixin reads self.unit before it reads the attribute,
-- and the field is the tainted read. The attribute is the channel that works.
--
-- The receiver is a PLAIN frame seated on the VISIBLE CONTENT rather than the
-- click overlay. The ping hit test is a separate channel from the mouse
-- (PingListenerFrame owns the mouse while the key is held, and Blizzard's CDM
-- items stay receivers with tooltips off, which leaves them fully mouse-dead,
-- CooldownViewer.lua:322-325), so the two rects are free to differ: clicks keep
-- the whole envelope, pings fall through its reserve to the world. And the
-- content rect moves with the subject where the envelope never does, so a
-- protected frame could not be resized for it in combat.

-- The player's split mirrors PlayerFrame's, and the direction of that split is
-- the part worth stating plainly:
--
--   isPlayerResource = self.unit == "player"
--       and not self.PlayerFrameContainer.PlayerPortrait:IsMouseOver()
--       (PingableType.lua:43-58)
--
-- One carve-out inside a resource default, not a resource carve-out inside a
-- plain default. Everywhere on PlayerFrame except the portrait reports a
-- resource. UFZ has no portrait, so the NAME ROW plays it: the name identifies
-- the player where every other part of the element reports a number, and it is
-- the part the user chose to keep the radial wheel on (decision 2026-08-27).
-- Everything else -- health, primary power, alternate power, absorb, level, and
-- the empty rect between them -- reports.
--
-- An earlier round had this inverted, resource ONLY over the numbers box, which
-- put the alternate power number (mana on a Shadow Priest) on the wrong side of
-- the line: pinging it announced the player rather than the resource (reported
-- in-game 2026-08-27). There is no per-resource ping to reach for instead.
-- isPlayerResource is a single bool and the client composes the sentence,
-- "the player's health and in some cases mana"
-- (PingManagerSecureDocumentation.lua:122), so every number on the element gives
-- the same callout and none of them can ask for a specific resource.
--
-- The carve-out is tested through a PLAIN PROXY, inst.pingNameBox, and never
-- through the FontStrings themselves. IsMouseOver is SecretWhenAnchoringSecret
-- (SimpleScriptRegionAPIDocumentation.lua:469-472), and by this addon's own live
-- proof that predicate means "secret when the OBJECT holds a secret aspect"
-- rather than "anchored to something secret" (docs/debugging/secrets.md,
-- "Anchor Secrecy Propagation"): a FontString holding a secret string poisons
-- itself, so powerFS:IsMouseOver() answers with a SECRET bool. A secret in the
-- returned table is precisely what breaks the securecopy at the secure boundary.
-- The proxy is anchored to the outer frame with pure-config numbers and holds
-- nothing secret, so its answer is plain by construction; overNameRow normalises
-- it to a literal true or false regardless, so nothing else can reach the
-- gather's result.
--
-- This is the one Scoot GetTargetInfo that runs inside the gather, and it is safe
-- for the reason the purity rule exists: the local player's own identity is never
-- restricted, so UnitGUID("player") is plain and nothing secret reaches
-- securecopy. IsMouseOver is rect containment and needs no mouse flag, which is
-- how Blizzard can call it on a Texture.
local function overNameRow(rec)
    local box = rec._pingNameBox
    if not box or type(box.IsMouseOver) ~= "function" then return false end
    local ok, over = pcall(box.IsMouseOver, box)
    if not ok then return false end
    if issecretvalue and issecretvalue(over) then return false end
    return over == true
end

local UFZ_PLAYER_PING = {}

function UFZ_PLAYER_PING:GetIsPingable()
    return true
end

function UFZ_PLAYER_PING:GetAllowRadialWheel()
    return overNameRow(self)
end

function UFZ_PLAYER_PING:GetTargetInfo()
    return {
        guid = UnitGUID("player"),
        isPlayerResource = not overNameRow(self),
    }
end

-- Below this the span is treated as no measurement at all and the receiver falls
-- back to the whole envelope: a receiver nobody can hit is the worse failure, and
-- a zero-size region has no rect for the engine to test at all.
local PING_MIN_SPAN = 8

--- Seats the receiver on the visible content: _AuraContentSpan horizontally (the
--- same ink-true span the aura rows align to), the one-line envelope band
--- vertically (computeEnvelope's snugTop/snugBottom). Then seats the name-row
--- proxy inside it, which is the player's radial-wheel carve-out. Both are
--- skip-compared separately -- the name's ink moves on a subject change that
--- leaves the envelope alone -- and both are unprotected throughout, so neither
--- needs a regen slot.
local function applyPingRect(inst)
    local rec, frame, env = inst.pingReceiver, inst.frame, inst.appliedEnv
    if not (rec and frame and env) then return end

    local l, r = UFZ._AuraContentSpan(inst)
    local top, bottom = env.snugTop or 0, env.snugBottom or 0
    if (r - l) < PING_MIN_SPAN or (env.H - top - bottom) < PING_MIN_SPAN then
        l, r, top, bottom = 0, env.W, 0, 0
    end
    local applied = inst.appliedPingRect
    if not (applied and applied.l == l and applied.r == r
        and applied.top == top and applied.bottom == bottom) then
        rec:ClearAllPoints()
        rec:SetPoint("TOPLEFT", frame, "TOPLEFT", l, -top)
        rec:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", r, bottom)
        inst.appliedPingRect = { l = l, r = r, top = top, bottom = bottom }
    end

    local nb = inst.pingNameBox
    if not nb then return end
    local nl, nr, nt, nbot = nameRowRect(inst, env)
    local an = inst.appliedPingName
    if an and an.l == nl and an.r == nr and an.t == nt and an.b == nbot then
        return
    end
    nb:ClearAllPoints()
    nb:SetPoint("TOPLEFT", frame, "TOPLEFT", nl, -nt)
    nb:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", nr, -nbot)
    inst.appliedPingName = { l = nl, r = nr, t = nt, b = nbot }
end
UFZ._ApplyPingRect = applyPingRect

--- Creation-time wiring, idempotent so _ApplyAll can use it as a self-heal. The
--- whole receiver contract lives in this one function: if a plain frame ever
--- turns out not to be honoured by the hit test, the fallback is to point these
--- two writes at inst.clickButton (the shape two other addons ship) and accept
--- the envelope-sized ping area.
local function wirePingReceiver(inst)
    local rec = inst.pingReceiver
    if not rec then return end
    if not rec._pingWired then
        if inst.unit == "player" then
            Mixin(rec, UFZ_PLAYER_PING)
        elseif PingableType_UnitFrameMixin then
            Mixin(rec, PingableType_UnitFrameMixin)
        else
            return  -- no ping system on this client; retry on the next _ApplyAll
        end
        rec:SetAttribute("ping-receiver", true)
        rec._pingWired = true
    end
    -- Re-asserted rather than set once at wire time: ensureFrame wires the
    -- receiver before it builds the proxy, and _ApplyAll heals both.
    rec._pingNameBox = inst.pingNameBox
    -- The attribute, never a field. Unprotected frame, so the write is legal in
    -- combat and needs no queue.
    if rec:GetAttribute("unit") ~= inst.unit then
        rec:SetAttribute("unit", inst.unit)
    end
end
UFZ._WirePingReceiver = wirePingReceiver

--- Creation, once per instance from ensureFrame after the click overlay exists.
--- Plain, mouse-dead, and seated on the visible content rather than on the
--- overlay's envelope (the rationale above). The full-frame anchors here are a
--- stand-in; applyPingRect replaces them as soon as an envelope has been applied.
function UFZ._BuildPingReceiver(inst)
    local frame = inst.frame
    local ping = CreateFrame("Frame", inst.frameName .. "Ping", frame)
    inst.pingReceiver = ping
    ping:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    ping:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    -- The name row's plain stand-in, the player's radial-wheel carve-out. Never
    -- drawn, never mouse-enabled: its rect exists only so IsMouseOver has a plain
    -- region to answer about. A child of the receiver so it follows it into and
    -- out of Edit Mode, anchored to the outer frame so nothing secret is in its
    -- chain. nameRowRect replaces these stand-in anchors on the first apply.
    inst.pingNameBox = CreateFrame("Frame", nil, ping)
    inst.pingNameBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    inst.pingNameBox:SetSize(1, 1)
    wirePingReceiver(inst)
end
