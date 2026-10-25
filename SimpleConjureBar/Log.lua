-- SimpleConjureBar - action log for the bug report (ruleset plan 2026-10-17-bug-report-details)
-- The last presses and events, in memory only, so a report shows what happened before a bug
-- without asking the player. Entries hold unit tokens, IDs and keys, never names. A write
-- never raises an error: logging must not break a click.

local _, ns = ...
if not ns.enabled then return end

local D_VALUE_DEFAULTS = ns.D.VALUE_DEFAULTS
local MAX_ENTRIES = 50
local entries, first = {}, 1 -- a ring: entries[first] is the oldest
-- The clock starts when the addon loads - after a /reload too, not only at login
local loadAt, loadClock = GetTime(), time()
ns.logStartClock = loadClock -- the report's fallback to tell this session's errors apart
local combats = {} -- { start = clock, stop = clock or nil }, kept apart from the ring

-- How an entry reads in the report: seconds since load, then the text. A field of ns, so a
-- spec can make it fail.
function ns.LogFormat(e)
    return ("+%.1fs %s"):format(e.since, e.text)
end

function ns.Log(text)
    pcall(function()
        local e = { since = GetTime() - loadAt, clock = time(), text = text }
        if #entries < MAX_ENTRIES then
            entries[#entries + 1] = e
        else
            entries[first] = e
            first = first % MAX_ENTRIES + 1
        end
    end)
end

-- The entries, oldest first, as the report prints them
function ns.LogLines()
    local lines = {}
    for i = 0, #entries - 1 do
        local e = entries[(first - 1 + i) % #entries + 1]
        local ok, line = pcall(ns.LogFormat, e)
        lines[#lines + 1] = ok and line or "?"
    end
    return lines
end

-- Whether a moment (time() scale, as BugGrabber stores an error's time) fell in combat:
-- "unknown" before the log began - BugGrabber offers no callback on this client to ask at
-- the moment itself (phase 1 research)
function ns.CombatAt(clock)
    if clock < loadClock then return "unknown" end
    for _, c in ipairs(combats) do
        if clock >= c.start and (not c.stop or clock <= c.stop) then return "yes" end
    end
    return "no"
end

---------------------------------------------------------------------------
-- Clicks. The buttons register down and up: the entry is for the half the client acts on, set
-- by ActionButtonUseKeyDown. A button clicked only through a macro's "/click Name Button 1"
-- receives the down alone (downOnly).
---------------------------------------------------------------------------
local SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }

local function Attr(b, name, suffix)
    local v = b:GetAttribute(name .. suffix)
    if v == nil then v = b:GetAttribute(name) end
    return v
end

function ns.LogClicks(b, label, downOnly)
    b:HookScript("OnClick", function(self, mouse, down)
        if downOnly then
            if not down then return end
        elseif (down == true) ~= (GetCVar("ActionButtonUseKeyDown") == "1") then
            return
        end
        local suffix = SUFFIX[mouse] or ""
        local parts = { "click", label, tostring(mouse) }
        for _, a in ipairs({ "type", "spell", "item", "unit" }) do
            local v = Attr(self, a, suffix)
            if v ~= nil then parts[#parts + 1] = a .. "=" .. ns.SafeValue(v) end
        end
        ns.Log(table.concat(parts, " "))
    end)
end

---------------------------------------------------------------------------
-- Settings: the plain values that changed since the last look - when the settings window
-- closes, after a chat command and when a report is built
---------------------------------------------------------------------------
local db, seen = nil, {}
local function Plain(v) local t = type(v) return t == "number" or t == "boolean" or t == "string" end
ns.OnDBReady(function(d)
    db = d
    for k, v in pairs(d) do if Plain(v) then seen[k] = v end end
end)

function ns.LogSettings()
    if not db then return end
    local changed = {}
    for k, v in pairs(db) do
        if Plain(v) and seen[k] ~= v then changed[#changed + 1] = k end
    end
    table.sort(changed)
    for _, k in ipairs(changed) do
        seen[k] = db[k]
        -- a key the addon does not know is not named: it could be anything
        if D_VALUE_DEFAULTS[k] ~= nil then ns.Log("setting " .. k .. "=" .. ns.SafeValue(db[k])) end
    end
end

---------------------------------------------------------------------------
-- Events: combat, group size
---------------------------------------------------------------------------
local lastGroup
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        combats[#combats + 1] = { start = time() }
        if #combats > MAX_ENTRIES then table.remove(combats, 1) end
        ns.Log("combat start")
    elseif event == "PLAYER_REGEN_ENABLED" then
        local c = combats[#combats]
        if c and not c.stop then c.stop = time() end
        ns.Log("combat end")
    else
        local group = (IsInRaid() and "raid" or IsInGroup() and "party" or "solo") .. " size="
            .. (IsInGroup() and GetNumGroupMembers() or 1)
        if group ~= lastGroup then
            lastGroup = group
            ns.Log("group " .. group)
        end
    end
end)
