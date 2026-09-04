--------------------------------------------------------------------------------
-- groupauras/animengine.lua
-- Animation controller registry and pool for code-driven animated aura icons.
--
-- Each controller ticks on its OWN frame's OnUpdate rather than a shared one.
-- On group frames a controller lives under an engine AuraButton whose shown
-- state is a secret, and OnUpdate only runs while a frame is visible, so a
-- controller under an absent aura costs nothing and nothing ever has to ask
-- whether the aura is present. Asking is not possible: the button's visibility
-- is secret and a truthiness test on it throws.
--
-- Rainbow hue comes from GetTime() rather than an accumulator, so every
-- controller and every static rainbow icon share one phase with no shared state.
--
-- Duration-linked modes (shrink / descend / ascend) were removed in the 12.1
-- port. They needed a plain remaining/total ratio, which no longer exists:
-- 12.1 binds durations to StatusBar, Cooldown and FontString only, and nothing
-- binds scale or position. Duration feedback is the Show Duration swipe.
--
-- Depends on groupauras/core.lua (HA namespace, HSVtoRGB)
--------------------------------------------------------------------------------
local addonName, addon = ...

local HA = addon.AuraTracking
if not HA then return end

HA.AnimEngine = {}
local AE = HA.AnimEngine

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_TEXTURES = 12          -- Fading Ring uses the most (10-12 dots)
local POOL_PREALLOC = 12
local RAINBOW_CYCLE_PERIOD = 3.0 -- Match the static rainbow engine in core.lua
local WHITE8X8 = "Interface\\BUTTONS\\WHITE8X8"

--------------------------------------------------------------------------------
-- Animation Definition Registry
--------------------------------------------------------------------------------

local animDefs = {}
local animOrder = {}  -- ordered array of def ids for picker display

function AE.RegisterAnim(def)
    if not def or not def.id then return end
    animDefs[def.id] = def
    table.insert(animOrder, def.id)
end

function AE.GetDef(animId)
    return animDefs[animId]
end

function AE.GetAllDefs()
    local result = {}
    for _, id in ipairs(animOrder) do
        local def = animDefs[id]
        if def then
            table.insert(result, def)
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Controller Metatable
--------------------------------------------------------------------------------

local controllerMT = {}
controllerMT.__index = controllerMT

function controllerMT:Configure(animId, size)
    local def = animDefs[animId]
    if not def then return end

    self.animId = animId
    self.size = size or 28
    self.period = def.period or 1.0
    self.progress = 0

    -- Show only the textures this animation needs, hide the rest
    local needed = def.numTextures or 1
    for i = 1, MAX_TEXTURES do
        local tex = self.textures[i]
        if i <= needed then
            tex:SetTexture(WHITE8X8)
            tex:SetRotation(0)
            tex:ClearAllPoints()
            tex:Show()
        else
            tex:Hide()
        end
    end

    -- Size the container frame; center-anchor for easy offset adjustments
    self.frame:SetScale(1)
    self.frame:SetSize(size, size)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", self.frame:GetParent(), "CENTER", 0, 0)

    -- Let the definition position its textures
    if def.setup then
        def.setup(self, size)
    end
end

function controllerMT:SetColor(r, g, b, a)
    self.colorR = r or 1
    self.colorG = g or 1
    self.colorB = b or 1
    self.colorA = a or 1
    self.rainbowMode = false

    local def = animDefs[self.animId]
    if def and def.applyColor then
        def.applyColor(self, self.colorR, self.colorG, self.colorB, self.colorA)
    end
end

function controllerMT:SetSize(size)
    if self.size == size then return end
    self.size = size
    self.frame:SetSize(size, size)

    local def = animDefs[self.animId]
    if def and def.setup then
        def.setup(self, size)
    end
end

function controllerMT:Play()
    self.playing = true
    self.frame:Show()
end

function controllerMT:Stop()
    self.playing = false
    self.frame:Hide()
end

--- Duration-linked animation was removed in the 12.1 port; kept as a no-op so a
--- stale caller cannot error. See the file header.
function controllerMT:SetDuration()
end

function controllerMT:Recycle()
    self.playing = false
    self.animId = nil
    self.progress = 0
    self.rainbowMode = false
    self.colorR, self.colorG, self.colorB, self.colorA = 1, 1, 1, 1

    self.frame:SetScale(1)
    self.frame:Hide()
    self.frame:ClearAllPoints()

    for i = 1, MAX_TEXTURES do
        local tex = self.textures[i]
        tex:Hide()
        tex:ClearAllPoints()
        tex:SetRotation(0)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetSize(1, 1)
    end
end

--------------------------------------------------------------------------------
-- Per-controller tick
--------------------------------------------------------------------------------
-- On its own frame, so a controller under a hidden button never runs. That is
-- the whole reason this is not a shared OnUpdate any more: on group frames the
-- button's shown state is a secret and cannot be tested from Lua, but the
-- engine's own visibility rule answers it for free.

local function ControllerOnUpdate(frame, elapsed)
    local ctrl = frame.scootAnimCtrl
    if not ctrl or not ctrl.playing then return end

    ctrl.progress = (ctrl.progress + elapsed / ctrl.period) % 1

    local def = animDefs[ctrl.animId]
    if def and def.update then
        def.update(ctrl, ctrl.progress)
    end

    if ctrl.rainbowMode and HA.HSVtoRGB and def and def.applyColor then
        local r, g, b = HA.HSVtoRGB((GetTime() / RAINBOW_CYCLE_PERIOD) % 1, 0.75, 1)
        def.applyColor(ctrl, r, g, b, 1)
    end
end

--------------------------------------------------------------------------------
-- Controller Creation
--------------------------------------------------------------------------------

local function CreateController(parent)
    local ctrl = setmetatable({}, controllerMT)

    ctrl.frame = CreateFrame("Frame", nil, parent)
    ctrl.frame:SetSize(28, 28)
    ctrl.frame:EnableMouse(false)
    ctrl.frame.scootAnimCtrl = ctrl
    ctrl.frame:SetScript("OnUpdate", ControllerOnUpdate)
    ctrl.frame:Hide()

    ctrl.textures = {}
    for i = 1, MAX_TEXTURES do
        local tex = ctrl.frame:CreateTexture(nil, "OVERLAY", nil, 0)
        tex:SetTexture(WHITE8X8)
        tex:SetSize(1, 1)
        tex:Hide()
        ctrl.textures[i] = tex
    end

    ctrl.animId = nil
    ctrl.progress = 0
    ctrl.period = 1.0
    ctrl.playing = false
    ctrl.size = 28
    ctrl.colorR, ctrl.colorG, ctrl.colorB, ctrl.colorA = 1, 1, 1, 1
    ctrl.rainbowMode = false

    return ctrl
end

--------------------------------------------------------------------------------
-- Controller Pool (settings previews only)
--------------------------------------------------------------------------------
-- The icon picker's preview buttons acquire and release from here. Group-frame
-- controllers are NOT pooled: they are created once under their aura button and
-- live as long as it does, because a frame created inside initializeFrame can
-- never be re-parented afterwards.

local function CreatePooledController()
    -- No frame creation in combat: the caller sees nil and skips the preview.
    if InCombatLockdown() then return nil end
    return CreateController(UIParent)
end

local function ResetController(ctrl)
    ctrl:Stop()
    ctrl:Recycle()
    ctrl.frame:SetParent(UIParent)
end

local controllerPool = addon.Pool.New(CreatePooledController, ResetController)
local activeControllers = {}  -- owner -> ctrl (explicit release required)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Pooled acquire, for settings previews. Re-parents, so never use this for a
--- controller that must live under an engine aura button.
function AE.Acquire(owner, parentFrame)
    if not owner or not parentFrame then return nil end

    local ctrl = controllerPool:Acquire()
    if not ctrl then return nil end

    ctrl.frame:SetParent(parentFrame)
    ctrl.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
    ctrl.frame:Show()

    activeControllers[owner] = ctrl

    return ctrl
end

function AE.Release(owner)
    local ctrl = activeControllers[owner]
    if not ctrl then return end

    activeControllers[owner] = nil
    controllerPool:Release(ctrl)
end

function AE.GetActive(owner)
    return activeControllers[owner]
end

--- Un-pooled create, for a controller that must be born under a specific parent
--- and stay there. This is the group-frame path: the parent is an engine aura
--- button and creation only ever happens inside its initializeFrame.
function AE.CreateOwned(parentFrame)
    if not parentFrame then return nil end
    local ctrl = CreateController(parentFrame)
    local ok, level = pcall(parentFrame.GetFrameLevel, parentFrame)
    if ok and type(level) == "number" and not issecretvalue(level) then
        ctrl.frame:SetFrameLevel(level + 1)
    end
    return ctrl
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

controllerPool:Preallocate(POOL_PREALLOC)
