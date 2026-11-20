-- Minimal World of Warcraft API mock for running WoWHelper outside the game.
-- Only what the addon touches is modelled; everything else is a no-op.

MOCK = {
    level = 1,
    race = { "Undead", "Scourge" },
    class = { "Warlock", "WARLOCK" },
    faction = "Horde",
    log = {},               -- array of { questID=, title=, complete= }
    completed = {},         -- questID -> true
    map = 1420, x = 0.30, y = 0.70,
    bind = "Deathknell",
    timers = {},
    printed = {},
    frames = {},
}

local function noop() end

local Widget = {}
Widget.__index = function(t, k)
    local v = rawget(Widget, k)
    if v ~= nil then return v end
    return noop
end

local function newWidget(kind, name)
    local w = setmetatable({ _kind = kind, _shown = true, _scripts = {}, _events = {},
        _w = 100, _h = 20, _text = "" }, Widget)
    if name then _G[name] = w end
    MOCK.frames[#MOCK.frames + 1] = w
    return w
end

function Widget:SetScript(k, fn) self._scripts[k] = fn end
function Widget:GetScript(k) return self._scripts[k] end
function Widget:RegisterEvent(e) self._events[e] = true end
function Widget:UnregisterEvent(e) self._events[e] = nil end
function Widget:Show() self._shown = true end
function Widget:Hide() self._shown = false end
function Widget:SetShown(s) self._shown = s and true or false end
function Widget:IsShown() return self._shown end
function Widget:SetText(t) self._text = t or "" end
function Widget:GetText() return self._text end
function Widget:SetWidth(w) self._w = w end
function Widget:SetHeight(h) self._h = h end
function Widget:SetSize(w, h) self._w, self._h = w, h end
function Widget:GetWidth() return self._w end
function Widget:GetHeight() return self._h end
function Widget:GetLeft() return 20 end
function Widget:GetBottom() return 300 end
function Widget:GetStringHeight()
    local n = math.max(1, math.ceil(#(self._text or "") / 60))
    return 12 * n
end
function Widget:CreateFontString(name) return newWidget("FontString", name) end
function Widget:CreateTexture(name) return newWidget("Texture", name) end
function Widget:GetChecked() return self._checked end
function Widget:SetChecked(c) self._checked = c end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:GetVerticalScroll() return 0 end

function CreateFrame(kind, name, parent, template)
    return newWidget(kind, name)
end

UIParent = newWidget("Frame", "UIParent")
ChatFrame1 = newWidget("Frame", "ChatFrame1")
GameTooltip = newWidget("GameTooltip", "GameTooltip")
ChatFontNormal = {}
GameTooltip_Hide = noop
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) MOCK.printed[#MOCK.printed + 1] = msg end }

tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function issecretvalue() return false end

C_Timer = {
    After = function(_, fn) MOCK.timers[#MOCK.timers + 1] = fn end,
    NewTicker = function(_, fn) MOCK.ticker = fn return {} end,
}
function MOCK.runTimers()
    local guard = 0
    while #MOCK.timers > 0 and guard < 100 do
        local list = MOCK.timers
        MOCK.timers = {}
        for _, fn in ipairs(list) do fn() end
        guard = guard + 1
    end
end

C_QuestLog = {
    GetNumQuestLogEntries = function() return #MOCK.log end,
    GetInfo = function(i)
        local q = MOCK.log[i]
        return q and { title = q.title, questID = q.questID, isHeader = false }
    end,
    IsOnQuest = function(id)
        for _, q in ipairs(MOCK.log) do if q.questID == id then return true end end
        return false
    end,
    IsComplete = function(id)
        for _, q in ipairs(MOCK.log) do if q.questID == id then return q.complete == true end end
        return false
    end,
    IsQuestFlaggedCompleted = function(id) return MOCK.completed[id] == true end,
    GetTitleForQuestID = function(id)
        for _, q in ipairs(MOCK.log) do if q.questID == id then return q.title end end
        return nil
    end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(MOCK.log) do
            if q.questID == id then return q.objectives or {} end
        end
        return {}
    end,
}

local Vec = {}
Vec.__index = Vec
function Vec:GetXY() return self.x, self.y end
function CreateVector2D(x, y) return setmetatable({ x = x, y = y }, Vec) end

-- Every zone pretends to be a 1000 x 1000 yard square on one continent,
-- laid side by side by map ID so cross-zone distances are finite.
C_Map = {
    GetBestMapForUnit = function() return MOCK.map end,
    GetPlayerMapPosition = function() return CreateVector2D(MOCK.x, MOCK.y) end,
    GetMapWorldSize = function() return 1000, 1000 end,
    GetWorldPosFromMapPos = function(map, pos)
        local x, y = pos:GetXY()
        -- world x = north, world y = west
        return 0, CreateVector2D(-(y * 1000), -(x * 1000 + (map - 1400) * 1000))
    end,
    GetMapInfo = function(id) return { name = "Map" .. id } end,
    GetMapChildrenInfo = function() return { { mapID = 2001, name = "The Riverglades" }, { mapID = 2002, name = "Mount Hyjal" } } end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) MOCK.waypoint = p end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) MOCK.superTracked = v end }

Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { ID = 42, GetID = function() return 42 end } end,
    RegisterAddOnCategory = noop,
    OpenToCategory = function(id) MOCK.openedSettings = id end,
}

function UnitRace() return MOCK.race[1], MOCK.race[2] end
function UnitClass() return MOCK.class[1], MOCK.class[2] end
function UnitLevel() return MOCK.level end
function UnitFactionGroup() return MOCK.faction end
function UnitExists() return true end
function UnitIsPlayer() return false end
function UnitName() return "Undertaker Mordo" end
function UnitOnTaxi() return false end
function GetPlayerFacing() return 0 end
function GetBindLocation() return MOCK.bind end
function GetSubZoneText() return MOCK.subzone or "" end
function GetZoneText() return MOCK.zoneText or "" end
function GetMinimapZoneText() return MOCK.subzone or "" end

-- Event helpers
function MOCK.fire(event, ...)
    for _, f in ipairs(MOCK.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

function MOCK.accept(id, title)
    MOCK.log[#MOCK.log + 1] = { questID = id, title = title }
    MOCK.fire("QUEST_ACCEPTED", id)
    MOCK.runTimers()
end

function MOCK.finish(id)
    for _, q in ipairs(MOCK.log) do if q.questID == id then q.complete = true end end
    MOCK.fire("QUEST_LOG_UPDATE")
    MOCK.runTimers()
end

function MOCK.turnin(id)
    MOCK.fire("QUEST_TURNED_IN", id, 100, 0)
    for i, q in ipairs(MOCK.log) do if q.questID == id then table.remove(MOCK.log, i) break end end
    MOCK.completed[id] = true
    MOCK.fire("QUEST_REMOVED", id)
    MOCK.runTimers()
end
