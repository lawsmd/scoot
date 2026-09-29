--------------------------------------------------------------------------------
-- forever/actionbars/mixins.lua
-- The two globals frames.xml names in its mixin= attributes. They have to
-- exist before the XML parses, so this file loads before it; events.lua
-- loads before both, because a button registers with its tick from its own
-- load, inside the XML parse.
--
-- A Camelot bar is Blizzard's ActionBarTemplate and a Camelot button is
-- Blizzard's action button template, both under Camelot names, with the
-- mixins below listed last so each key here shadows the same key from the
-- Blizzard mixins on the instance. Nothing is copied from those mixins: a
-- copied key would be one more entry written under this addon's load, and
-- the point of every override is to keep a Camelot button out of the lists
-- Blizzard's own code loops over, and to keep every write a fight can
-- trigger legal in lockdown. The XML scripts name their handlers by method,
-- so the keys those scripts look up are the ones overridden.
--
-- Each override names the function it replaces in Blizzard_ActionBar/Shared/
-- ActionButton.lua or ActionBar.lua.
--------------------------------------------------------------------------------

local _, addon = ...

local function Events()
    return addon.ActionBars.Events
end

local function queue(fn, key)
    addon.Events.RunOutOfCombat(fn, key)
end

-- A boolean that is plain and true. Cooldown info tables carry secret
-- timings in a fight while their flags stay plain; this reads a flag
-- without a boolean test on anything else.
local function plainTrue(v)
    if type(v) ~= "boolean" then return false end
    if issecretvalue(v) then return false end
    return v
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

CamelotActionButtonMixin = {}

-- Replaces ActionButtonCastingAnimFrameMixin:OnHide on the button's cast
-- animation frame, a Camelot child. Blizzard's handler ends the animation
-- with the global ActionButton_UpdateCooldown, whose numeric SetCooldown is
-- refused secret timings in a fight, and the swipe it had made transparent
-- for the animation stayed so. The duration path stands in, after the same
-- reticle clear and swipe restore.
local function CastAnimOnHide(anim)
    local button = anim:GetParent()
    button:ClearReticle()
    button.cooldown:SetSwipeColor(0, 0, 0, 1)
    button:UpdateCooldownFromDurations()
end

-- Replaces ActionBarButtonMixin:ActionBarButtonMixin_OnLoad, which runs
-- ActionBarActionButtonMixin:OnLoad. Two attributes are left out: the
-- useparent pair makes every click walk to frame.bar, a field written under
-- this addon's load. One registration is left out: the action bar
-- controller loops ActionBarButtonEventsFrame's list from an untainted
-- context, and a Camelot entry taints every button after it, ending in a
-- protected Show on the main bar. The Camelot event frame forwards the same
-- events. UpdateAction stays: the bar's OnLoad reads HasAction on every
-- button right after they exist.
function CamelotActionButtonMixin:ActionBarButtonMixin_OnLoad()
    BaseActionButtonMixin.BaseActionButtonMixin_OnLoad(self)

    self.SetButtonStateBase = self.SetButtonState
    self.SetButtonState = self.SetButtonStateOverride

    self.flashing = 0
    self.flashtime = 0
    self:SetAttribute("type", "action")
    self:SetAttribute("typerelease", "actionrelease")
    self:SetAttribute("checkselfcast", true)
    self:SetAttribute("checkfocuscast", true)
    self:SetAttribute("checkmouseovercast", true)
    self:RegisterForDrag("LeftButton", "RightButton")
    self:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")
    if self.SpellCastAnimFrame then
        self.SpellCastAnimFrame:SetScript("OnHide", CastAnimOnHide)
    end
    self:UpdateAction()
    self:UpdateHotkeys(self.buttonType)

    self.QuickKeybindHighlightTexture:ClearAllPoints()
    self.QuickKeybindHighlightTexture:SetPoint("CENTER")
    self.QuickKeybindHighlightTexture:SetSize(46, 45)

    ActionButton_UpdateCooldownNumberHidden(self)
end

-- Replaces ActionBarActionButtonMixin:UpdateAction. Left out: the assisted
-- combat rotation frame, an EventRegistry consumer, and the
-- EventRegistry:TriggerEvent, whose dispatch loop a Camelot call would
-- taint. In lockdown the ping attribute and the bar's shown pass wait for
-- regen, since a SetAttribute or a SetShown on a protected frame is blocked
-- there. The casting animation reads the player's cast, which can be secret
-- in a fight, so it runs guarded and a refusal costs that animation only.
function CamelotActionButtonMixin:UpdateAction(force)
    local action = self:CalculateAction()
    if action == self.action and not force then return end

    if self.action then
        self:UnregisterActionBarButtonCheckFrames(self.action)
    end
    self.action = action
    if self.action and self:IsVisible() then
        self:RegisterActionBarButtonCheckFrames(self.action)
    end

    C_ActionBar.RegisterActionUIButton(self, action, self.cooldown)

    local ok, err = pcall(self.UpdateCastingAnimation, self)
    if not ok then Events().Note("casting animation", err) end
    self:ClearInterruptDisplay()

    self:Update()

    if InCombatLockdown() then
        queue(function()
            self:UpdatePingAttributes()
            if self.index and self.bar then
                self.bar:UpdateShownButtons()
            end
        end, "camelotActionBars.action." .. self:GetName())
    else
        self:UpdatePingAttributes()
        if self.index and self.bar then
            self.bar:UpdateShownButtons()
        end
    end
end

-- Replaces ActionBarActionButtonMixin:Update. Left out: the registration in
-- ActionBarActionEventsFrame, whose place the eventsRegistered flag keeps
-- for the Camelot forwarder; the global ActionButton_UpdateCooldown, whose
-- numeric SetCooldown is refused secret timings, replaced by the duration
-- objects below; and the press-and-hold attribute write waits for regen in
-- lockdown.
function CamelotActionButtonMixin:Update()
    local action = self.action
    local icon = self.icon
    local texture = C_ActionBar.GetActionTexture(action)

    icon:SetDesaturated(false)
    if C_ActionBar.HasAction(action) then
        self.eventsRegistered = true
        self:UpdateState()
        self:UpdateUsable()
        self:UpdateProfessionQuality()
        self:UpdateTypeOverlay()
        self:UpdateCooldownFromDurations()
        self:UpdateFlash()
        self:UpdateHighlightMark()
        self:UpdateSpellHighlightMark()
    else
        self.eventsRegistered = nil

        ClearActionButtonCooldowns(self.cooldown, self.chargeCooldown, self.lossOfControlCooldown)

        self:ClearFlash()
        self:SetChecked(false)
        self:ClearProfessionQuality()
        self:ClearTypeOverlay()

        if self.LevelLinkLockIcon then
            self.LevelLinkLockIcon:SetShown(false)
        end
    end

    if InCombatLockdown() then
        queue(function() self:UpdatePressAndHoldAction() end,
            "camelotActionBars.pressHold." .. self:GetName())
    else
        self:UpdatePressAndHoldAction()
    end

    local border = self.Border
    if border then
        if C_ActionBar.IsEquippedAction(action) then
            border:SetVertexColor(0, 1.0, 0, 0.5)
            border:Show()
        else
            border:Hide()
        end
    end

    local actionName = self.Name
    if actionName then
        if C_ActionBar.UsesActionText(action) then
            actionName:SetText(C_ActionBar.GetActionText(action))
        else
            actionName:SetText("")
        end
    end

    if texture then
        icon:SetTexture(texture)
        icon:Show()
        self:UpdateCount()
    else
        self.Count:SetText("")
        icon:Hide()
        ClearActionButtonCooldowns(self.cooldown, self.chargeCooldown, self.lossOfControlCooldown)
        local hotkey = self.HotKey
        if hotkey:GetText() == RANGE_INDICATOR then
            hotkey:Hide()
        else
            hotkey:SetVertexColor(ACTIONBAR_HOTKEY_FONT_COLOR:GetRGB())
        end
    end

    self:UpdateFlyout()
    self:UpdateSpellAlert()

    if GameTooltip:GetOwner() == self then
        self:SetTooltip()
    end

    self.feedback_action = action
end

-- Replaces the pair ActionButton_UpdateCooldown and ActionButton_ApplyCooldown
-- for a Camelot button. Blizzard's path ends in Cooldown:SetCooldown with
-- numbers, and that call refuses the secret timings a fight hands this
-- addon's context. A duration object carries the secrecy through instead,
-- so every swipe comes from one. Which of the three cooldown frames shows is
-- decided from the isActive and shouldReplaceNormalCooldown flags, which
-- stay plain. Nothing here compares a timing value. The spellID branch of
-- Blizzard's function is not carried: a slot button never sets it.
function CamelotActionButtonMixin:UpdateCooldownFromDurations()
    local action = self.action
    local cooldownInfo = C_ActionBar.GetActionCooldown(action)
    local chargeInfo = C_ActionBar.GetActionCharges(action)
    local lossInfo = self.enableLOCCooldown and C_ActionBar.GetActionLossOfControlCooldownInfo(action) or nil

    local showLoss = lossInfo ~= nil and plainTrue(lossInfo.isActive)
    local replace = lossInfo ~= nil and plainTrue(lossInfo.shouldReplaceNormalCooldown)
    local showCharge = not replace and chargeInfo ~= nil and plainTrue(chargeInfo.isActive)
    local showNormal = not replace and cooldownInfo ~= nil and plainTrue(cooldownInfo.isActive)

    if self.lossOfControlCooldown then
        if showLoss then
            self.lossOfControlCooldown:SetCooldownFromDurationObject(
                C_ActionBar.GetActionLossOfControlCooldownDuration(action))
        else
            self.lossOfControlCooldown:Clear()
        end
    end
    if showCharge then
        self.chargeCooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionChargeDuration(action))
    else
        self.chargeCooldown:Clear()
    end
    if showNormal then
        self.cooldown:SetCooldownFromDurationObject(C_ActionBar.GetActionCooldownDuration(action))
    else
        self.cooldown:Clear()
    end
end

-- Replaces ActionBarActionButtonMixin:CheckNeedsUpdate: the Camelot tick
-- frame in events.lua stands in for ActionBarButtonUpdateFrame.
function CamelotActionButtonMixin:CheckNeedsUpdate()
    local needsUpdate = ((self.stateDirty or self.flashDirty or self:IsFlashing()) and self:IsVisible())
        and true or false
    if needsUpdate ~= self.needsUpdate then
        Events().SetTicking(self, needsUpdate)
        self.needsUpdate = needsUpdate
    end
end

-- Replaces ActionBarActionButtonMixin:OnEvent for the three cooldown events,
-- which Blizzard routes to the numeric path; everything else goes to
-- Blizzard's handler, whose calls to Update, UpdateAction and
-- CheckNeedsUpdate resolve to the overrides above. The forwarder and the
-- range check frame both call OnEvent by that name; the XML script name is
-- the same function in case a Blizzard path registers an event on the
-- button itself.
function CamelotActionButtonMixin:OnEvent(event, ...)
    if event == "LOSS_OF_CONTROL_UPDATE" then
        self:UpdateCooldownFromDurations()
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "LOSS_OF_CONTROL_ADDED" then
        self:UpdateCooldownFromDurations()
        if GameTooltip:GetOwner() == self then
            self:SetTooltip()
        end
    else
        ActionBarActionButtonMixin.OnEvent(self, event, ...)
    end
end
CamelotActionButtonMixin.ActionBarActionButtonDerivedMixin_OnEvent = CamelotActionButtonMixin.OnEvent

-- Replaces ActionBarButtonMixin:ActionBarButtonMixin_OnEnter and the leave
-- half. Blizzard's write a tooltipOwner field on its two event frames and
-- trigger the binding highlight registry, which a Camelot call would taint;
-- the Camelot forwarder reads the tooltip's owner off the tooltip instead.
function CamelotActionButtonMixin:ActionBarButtonMixin_OnEnter()
    BaseActionButtonMixin.BaseActionButtonMixin_OnEnter(self)
    if self.NewActionTexture then
        ClearNewActionHighlight(self.action)
        self:UpdateAction(true)
    end
    self:SetTooltip()
    QuickKeybindButtonTemplateMixin.QuickKeybindButtonOnEnter(self)
end

function CamelotActionButtonMixin:ActionBarButtonMixin_OnLeave()
    BaseActionButtonMixin.BaseActionButtonMixin_OnLeave(self)
    GameTooltip:Hide()
    QuickKeybindButtonTemplateMixin.QuickKeybindButtonOnLeave(self)
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

CamelotActionBarMixin = {}

-- Replaces ActionBarMixin:UpdateShownButtons. SetShown on a button or its
-- container is blocked in lockdown, both being protected, so a pass that
-- lands in a fight changes alpha instead and the pass queued here puts the
-- real shown state back at regen.
function CamelotActionBarMixin:UpdateShownButtons()
    if InCombatLockdown() then
        for _, actionButton in pairs(self.actionButtons) do
            local showButton = actionButton.index <= self.numButtonsShowable
                and not actionButton:GetAttribute("statehidden")
                and (actionButton:GetShowGrid() or actionButton:HasAction())
            actionButton:SetAlpha(showButton and 1 or 0)
        end
        queue(function() self:UpdateShownButtons() end, "camelotActionBars.shown." .. self:GetName())
        return
    end

    wipe(self.shownButtonContainers)
    for i, actionButton in pairs(self.actionButtons) do
        local showButton = actionButton.index <= self.numButtonsShowable
            and not actionButton:GetAttribute("statehidden")
            and (actionButton:GetShowGrid() or actionButton:HasAction())
        actionButton:SetAlpha(1)
        actionButton:SetShown(showButton)

        local showButtonContainer = showButton or (not self.noSpacers and i <= self.numButtonsShowable)
        actionButton.container:SetShown(showButtonContainer)
        if showButtonContainer then
            table.insert(self.shownButtonContainers, actionButton.container)
        end
    end

    if self.UpdateDividers then
        self:UpdateDividers()
    end
end

-- Replaces ActionBarMixin:UpdateFrameStrata, a SetFrameStrata the grid path
-- runs when an action is picked up or dropped; blocked on this bar in
-- lockdown, so skipped there.
function CamelotActionBarMixin:UpdateFrameStrata(showGrid, reason)
    if InCombatLockdown() then return end
    ActionBarMixin.UpdateFrameStrata(self, showGrid, reason)
end
