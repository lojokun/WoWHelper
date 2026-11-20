-- WoWHelper: step completion tracking.
-- Steps are matched by quest ID first and by quest title as a fallback, because
-- WoW Forever reworked some quests and gave them new IDs.
local _, ns = ...
local WH = ns.WH

local logById, logByTitle = {}, {}
local LOOKAHEAD = 15    -- how far ahead quest events may mark steps done

---------------------------------------------------------------------------
-- Quest log cache
---------------------------------------------------------------------------
function WH:ScanQuestLog()
    wipe(logById)
    wipe(logByTitle)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.questID > 0 and info.title then
            logById[info.questID] = info.title
            logByTitle[info.title] = info.questID
            self.char.titleToId[info.title] = info.questID
        end
    end
end

-- Quest ID currently in the log for this step, if any.
local function logQuestId(s)
    if s.questId and logById[s.questId] then return s.questId end
    if s.quest and logByTitle[s.quest] then return logByTitle[s.quest] end
    return nil
end

local function isTurnedIn(self, s)
    local id = s.questId
    if id then
        if self.char.turnedIn[id] then return true end
        if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then return true end
    end
    return false
end

local function isQuestComplete(qid, objective)
    if objective and C_QuestLog.GetQuestObjectives then
        local objs = C_QuestLog.GetQuestObjectives(qid)
        local o = objs and objs[objective]
        if o then return o.finished == true end
    end
    if C_QuestLog.IsComplete then return C_QuestLog.IsComplete(qid) == true end
    return false
end

---------------------------------------------------------------------------
-- Position helpers (also used by the UI)
---------------------------------------------------------------------------
function WH:GetPlayerPosition()
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos:GetXY()
    if not x or (issecretvalue and issecretvalue(x)) then return map end
    return map, x * 100, y * 100
end

local function worldPos(mapId, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapId, CreateVector2D(x / 100, y / 100))
    if not ok or not continent or not pos then return nil end
    local wx, wy = pos:GetXY()
    return continent, wx, wy
end

-- Distance in yards plus bearing (radians, counter-clockwise from north) from
-- the player to a step's coordinates. Returns nil when it can't be computed.
function WH:GetStepDistance(s)
    if not (s and s.mapId and s.x and s.y) then return nil end
    local map, px, py = self:GetPlayerPosition()
    if not px then return nil end
    local c1, wx1, wy1 = worldPos(map, px, py)
    local c2, wx2, wy2 = worldPos(s.mapId, s.x, s.y)
    if c1 and c2 and c1 == c2 then
        local dNorth, dWest = wx2 - wx1, wy2 - wy1
        return math.sqrt(dNorth * dNorth + dWest * dWest), math.atan2(dWest, dNorth)
    end
    if map == s.mapId and C_Map.GetMapWorldSize then
        local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
        if ok and w and h and w > 0 then
            local dEast = (s.x - px) / 100 * w
            local dSouth = (s.y - py) / 100 * h
            return math.sqrt(dEast * dEast + dSouth * dSouth), math.atan2(-dEast, -dSouth)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Step state
---------------------------------------------------------------------------
function WH:GetGuide()
    return self.guides[self.char.guideId]
end

function WH:GetStepIndex()
    local g = self:GetGuide()
    if not g then return nil end
    return self.char.progress[g.id] or 1
end

function WH:GetCurrentStep()
    local g, i = self:GetGuide(), self:GetStepIndex()
    return g and g.steps[i], i
end

local function manualSet(self, g)
    local m = self.char.manual[g.id]
    if not m then
        m = {}
        self.char.manual[g.id] = m
    end
    return m
end

-- Whether a step is done. `isCurrent` enables title-only checks, which are
-- ambiguous for multi-part quests and so only trusted on the active step.
function WH:IsStepDone(g, i, isCurrent)
    local s = g.steps[i]
    if manualSet(self, g)[i] then return true end
    local a = s.action
    -- Optional quests the player never picked up are skipped automatically.
    if s.optional and isCurrent and (a == "complete" or a == "turnin")
        and not logQuestId(s) and not isTurnedIn(self, s) then
        return true
    end
    if a == "accept" then
        if isTurnedIn(self, s) then return true end
        if s.questId and logById[s.questId] then return true end
        return isCurrent and s.quest ~= nil and logByTitle[s.quest] ~= nil
    elseif a == "complete" then
        if isTurnedIn(self, s) then return true end
        local qid = isCurrent and logQuestId(s) or (s.questId and logById[s.questId] and s.questId)
        return qid ~= nil and isQuestComplete(qid, s.objective)
    elseif a == "turnin" then
        return isTurnedIn(self, s)
    elseif a == "level" then
        return (UnitLevel("player") or 1) >= s.level
    elseif isCurrent and (a == "goto" or a == "fly" or a == "hearth") and s.location
        and not (s.x and s.y) and not (UnitOnTaxi and UnitOnTaxi("player")) then
        -- No coordinates: done once the zone or subzone name matches the location.
        local want = s.location:lower():gsub("^the ", "")
        local function same(name) return name and name ~= "" and name:lower():gsub("^the ", "") == want end
        return same(GetSubZoneText and GetSubZoneText()) or same(GetZoneText and GetZoneText())
            or same(GetMinimapZoneText and GetMinimapZoneText())
    elseif isCurrent and (a == "goto" or a == "flightpath") then
        local d = self:GetStepDistance(s)
        return d ~= nil and d <= (s.radius or (a == "goto" and 15 or 8))
    elseif isCurrent and (a == "fly" or a == "hearth") then
        if UnitOnTaxi and UnitOnTaxi("player") then return false end
        local d = self:GetStepDistance(s)
        return d ~= nil and d <= (s.radius or 250)
    elseif isCurrent and a == "sethearth" and s.location then
        return GetBindLocation and GetBindLocation() == s.location
    end
    return false
end

-- Moves the current index forward past every finished or non-applicable step.
function WH:Advance()
    local g = self:GetGuide()
    if not g then return end
    local i = self.char.progress[g.id] or 1
    while i <= #g.steps do
        if self:StepApplies(g.steps[i]) and not self:IsStepDone(g, i, true) then break end
        i = i + 1
    end
    local changed = self.char.progress[g.id] ~= i
    self.char.progress[g.id] = i
    if i > #g.steps then
        self:OnGuideFinished(g)
        return true
    end
    return changed
end

function WH:OnGuideFinished(g)
    if g.next and self.guides[g.next] and self.char.guideId == g.id then
        self:Print("Finished %s. Next guide: %s", g.title, self.guides[g.next].title)
        self.char.guideId = g.next
        self:Advance()
    end
end

-- Marks the first open step of `action` that matches the quest, starting at
-- the current step. Used for quest events and hand-ins.
function WH:MarkQuestStep(action, questID, title)
    local g = self:GetGuide()
    if not g then return end
    local start = self.char.progress[g.id] or 1
    local m = manualSet(self, g)
    for i = start, math.min(#g.steps, start + LOOKAHEAD) do
        local s = g.steps[i]
        if s.action == action and not m[i] and self:StepApplies(s)
            and ((questID and s.questId == questID) or (title and s.quest == title)) then
            m[i] = true
            return i
        end
    end
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------
function WH:OnQuestAccepted(questID)
    self:ScanQuestLog()
    local title = logById[questID] or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
    self:MarkQuestStep("accept", questID, title)
    self:Refresh()
end

function WH:OnQuestTurnedIn(questID)
    self.char.turnedIn[questID] = true
    local title = logById[questID] or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
    -- A hand-in also finishes the matching "complete" step if it was still open.
    self:MarkQuestStep("complete", questID, title)
    self:MarkQuestStep("turnin", questID, title)
    -- The quest leaves the log after this event; rescan on the next frame.
    C_Timer.After(0.1, function()
        self:ScanQuestLog()
        self:Refresh()
    end)
end

local pendingLogRefresh = false
function WH:OnQuestLogChanged()
    if pendingLogRefresh then return end
    pendingLogRefresh = true
    C_Timer.After(0.25, function()
        pendingLogRefresh = false
        self:ScanQuestLog()
        self:Refresh()
    end)
end

function WH:CompleteCurrentIf(action)
    local s, i = self:GetCurrentStep()
    if s and s.action == action then
        manualSet(self, self:GetGuide())[i] = true
        self:Refresh()
    end
end

function WH:CompleteCurrentStep()
    local g = self:GetGuide()
    local s, i = self:GetCurrentStep()
    if not s then return end
    manualSet(self, g)[i] = true
    self:Refresh()
end

function WH:ToggleStepDone(i)
    local g = self:GetGuide()
    if not g or not g.steps[i] then return end
    local m = manualSet(self, g)
    m[i] = not m[i] or nil
    self:Refresh()
end

-- Goes back to the previous applicable step and clears its manual mark.
function WH:PreviousStep()
    local g = self:GetGuide()
    if not g then return end
    local i = (self.char.progress[g.id] or 1) - 1
    while i >= 1 and not self:StepApplies(g.steps[i]) do i = i - 1 end
    if i < 1 then return end
    manualSet(self, g)[i] = nil
    self.char.progress[g.id] = i
    self.holdIndex = i      -- don't auto-advance past it until something changes
    self:UpdateUI()
    self:SetWaypointForStep(g.steps[i])
end

-- Where to start a guide for a character that may already be part-way through
-- it: just after the last step whose quest is already done, or after the last
-- level checkpoint the character has already reached, whichever is further.
function WH:FindResumeStep(g)
    if not next(logById) then self:ScanQuestLog() end
    local level = UnitLevel("player") or 1
    local resume = 0
    for i, s in ipairs(g.steps) do
        local a = s.action
        if s.questId and (a == "accept" or a == "complete" or a == "turnin") then
            if isTurnedIn(self, s) or (a == "accept" and logById[s.questId]) then resume = i end
        elseif a == "level" and s.level <= level then
            resume = i
        end
    end
    return math.min(resume + 1, #g.steps)
end

-- Starts `g` at the resume point unless the character already has progress in it.
function WH:StartGuide(g, forceResume)
    if forceResume or not self.char.progress[g.id] then
        self.char.progress[g.id] = self:FindResumeStep(g)
    end
    self.char.guideId = g.id
    self.holdIndex = nil
end

-- Best guide for the character's current level (nil if none applies).
function WH:GuideForLevel()
    local level = UnitLevel("player") or 1
    local list = self:GetGuidesForPlayer(false)
    for _, g in ipairs(list) do
        if level >= g.minLevel and level < g.maxLevel then return g end
    end
    local last = list[#list]
    if last and level >= last.maxLevel then return last end
    return list[1]
end

-- /wh auto: switch to the guide for the current level and skip finished steps.
function WH:AutoSelectGuide()
    local g = self:GuideForLevel()
    if not g then
        self:Print("No guide matches this character.")
        return
    end
    self:StartGuide(g, true)
    self:Refresh(true)
    local _, i = self:GetCurrentStep()
    self:Print("Guide: %s, starting at step %d.", g.title, i or 1)
end

-- Tells the player once per level when they have outleveled the current guide.
function WH:CheckOutleveled()
    local g = self:GetGuide()
    local level = UnitLevel("player") or 1
    if not g or level < g.maxLevel + 1 or self.warnedLevel == level then return end
    local better = self:GuideForLevel()
    if better and better.id ~= g.id then
        self.warnedLevel = level
        self:Print("You are level %d, above %s (%d-%d). Type |cffffd100/wh auto|r to jump to %s.",
            level, g.title, g.minLevel, g.maxLevel, better.title)
    end
end

-- Recomputes the current step and redraws. `force` re-sets the waypoint.
function WH:Refresh(force)
    if not self.db then return end
    if not next(logById) then self:ScanQuestLog() end
    local g = self:GetGuide()
    if g and self.holdIndex and self.char.progress[g.id] == self.holdIndex
        and not manualSet(self, g)[self.holdIndex] then
        -- The player stepped back on purpose; only leave once they confirm it.
        self:UpdateUI()
        return
    end
    self.holdIndex = nil
    local before = self:GetCurrentStep()
    self:Advance()
    local s = self:GetCurrentStep()
    if force or s ~= before then self:SetWaypointForStep(s) end
    self:UpdateUI()
end

-- Periodic check for location-based steps (called by the UI ticker).
function WH:CheckLocationStep()
    local s = self:GetCurrentStep()
    if not s or self.holdIndex then return end
    local a = s.action
    if a == "goto" or a == "fly" or a == "hearth" or a == "flightpath" then
        local g = self:GetGuide()
        if self:IsStepDone(g, self:GetStepIndex(), true) then self:Refresh() end
    end
end
