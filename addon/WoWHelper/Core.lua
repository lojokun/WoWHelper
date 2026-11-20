-- WoWHelper: core namespace, saved variables, events and slash commands.
local ADDON, ns = ...

local WH = {}
ns.WH = WH
_G.WoWHelper = WH

WH.name = ADDON
WH.version = "0.1.0"
WH.pendingGuides = {}   -- raw JSON registered by the generated guide files
WH.pendingZones = nil
WH.guides = {}          -- id -> normalized guide table
WH.guideOrder = {}      -- ids in registration order

local DEFAULTS = {
    locked = false,
    hidden = false,
    scale = 1,
    width = 360,
    stepsShown = 4,
    autoWaypoint = true,
    superTrack = true,
    showCoords = true,
    showNotes = true,
    point = nil,            -- saved position {point, relPoint, x, y}; nil = above the chat frame
    customGuides = {},      -- id -> JSON string imported in game
}

local CHAR_DEFAULTS = {
    guideId = nil,
    progress = {},          -- guideId -> current step index
    manual = {},            -- guideId -> { [stepIndex] = true } for steps marked done by hand or by events
    turnedIn = {},          -- questID -> true
    titleToId = {},         -- quest title -> last questID seen with that title
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                applyDefaults(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
    return dst
end

function WH:Print(msg, ...)
    if select("#", ...) > 0 then msg = msg:format(...) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WoWHelper|r: " .. tostring(msg))
end

-- Called from the generated Guides\*.lua files.
function WH:RegisterGuideJSON(json)
    self.pendingGuides[#self.pendingGuides + 1] = json
end

function WH:RegisterZonesJSON(json)
    self.pendingZones = json
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
WH.eventFrame = eventFrame

local handlers = {}

-- Some events may not exist on every client build; registering an unknown
-- event raises an error, so every registration is protected.
local function safeRegister(event, fn)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if ok then handlers[event] = fn end
    return ok
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then fn(WH, ...) end
end)

safeRegister("ADDON_LOADED", function(self, name)
    if name ~= ADDON then return end
    WoWHelperDB = applyDefaults(WoWHelperDB or {}, DEFAULTS)
    WoWHelperCharDB = applyDefaults(WoWHelperCharDB or {}, CHAR_DEFAULTS)
    self.db = WoWHelperDB
    self.char = WoWHelperCharDB
end)

safeRegister("PLAYER_LOGIN", function(self)
    self:LoadZones()
    self:LoadAllGuides()
    self:CreateUI()
    self:CreateOptions()
    self:SelectInitialGuide()
    self:RegisterGameplayEvents()
    self:Refresh(true)
    self:CheckOutleveled()
end)

function WH:RegisterGameplayEvents()
    local function questChanged(self) self:OnQuestLogChanged() end
    safeRegister("QUEST_ACCEPTED", function(self, questID) self:OnQuestAccepted(questID) end)
    safeRegister("QUEST_TURNED_IN", function(self, questID) self:OnQuestTurnedIn(questID) end)
    safeRegister("QUEST_REMOVED", questChanged)
    safeRegister("QUEST_LOG_UPDATE", questChanged)
    safeRegister("UNIT_QUEST_LOG_CHANGED", function(self, unit) if unit == "player" then self:OnQuestLogChanged() end end)
    safeRegister("PLAYER_LEVEL_UP", function(self)
        C_Timer.After(0.2, function()
            self:Refresh()
            self:CheckOutleveled()
        end)
    end)
    safeRegister("ZONE_CHANGED_NEW_AREA", function(self) self:Refresh() end)
    safeRegister("HEARTHSTONE_BOUND", function(self) self:CompleteCurrentIf("sethearth") end)
    safeRegister("TAXIMAP_OPENED", function(self) self:CompleteCurrentIf("flightpath") end)
    safeRegister("TRAINER_CLOSED", function(self) self:CompleteCurrentIf("train") end)
    safeRegister("MERCHANT_CLOSED", function(self) self:CompleteCurrentIf("buy") end)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "/wh - toggle the guide window",
    "/wh lock | unlock - lock or unlock the window (drag to move when unlocked)",
    "/wh reset - move the window back above the chat frame",
    "/wh next | prev - mark the current step done / go back one step",
    "/wh guides - pick a guide",
    "/wh auto - jump to the guide for your level, skipping quests you have done",
    "/wh import - paste a JSON guide",
    "/wh where - print your map, coordinates and target as a JSON step",
    "/wh waypoint - set a waypoint for the current step",
    "/wh options - open the options panel",
}

SLASH_WOWHELPER1 = "/wh"
SLASH_WOWHELPER2 = "/wowhelper"
SlashCmdList.WOWHELPER = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if cmd == "" or cmd == "toggle" then
        WH:SetShown(WH.db.hidden)
    elseif cmd == "show" then
        WH:SetShown(true)
    elseif cmd == "hide" then
        WH:SetShown(false)
    elseif cmd == "lock" then
        WH:SetLocked(true)
    elseif cmd == "unlock" then
        WH:SetLocked(false)
    elseif cmd == "reset" then
        WH:ResetPosition()
    elseif cmd == "next" or cmd == "skip" then
        WH:CompleteCurrentStep()
    elseif cmd == "prev" or cmd == "back" then
        WH:PreviousStep()
    elseif cmd == "guides" or cmd == "guide" then
        WH:ToggleGuidePicker()
    elseif cmd == "auto" or cmd == "resume" then
        WH:AutoSelectGuide()
    elseif cmd == "import" then
        WH:ShowImport()
    elseif cmd == "where" then
        WH:PrintWhere(rest)
    elseif cmd == "waypoint" or cmd == "wp" then
        WH:SetWaypointForStep(WH:GetCurrentStep(), true)
    elseif cmd == "options" or cmd == "config" then
        WH:OpenOptions()
    else
        WH:Print("Commands:")
        for _, line in ipairs(HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
    end
end
