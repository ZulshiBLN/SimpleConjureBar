-- SimpleConjureBar - what a bug report may carry (ruleset plan 2026-10-17-bug-report-details)
-- Everything the addon collects passes an allowlist (D.REPORT_SAFE): a string not on it is
-- reported by its length only. Free text and error messages cannot be allowlisted - they are
-- the bug - so they pass a filter for the names the client knows, GUIDs, BattleTags and file
-- paths. The report is built out of combat, where names are readable (phase 1 research).

local _, ns = ...
if not ns.enabled then return end

local D = ns.D

---------------------------------------------------------------------------
-- Allowlist
---------------------------------------------------------------------------
function ns.IsSafe(s)
    s = tostring(s)
    if D.VALUE_DEFAULTS[s] ~= nil then return true end -- a settings key
    for _, p in ipairs(D.REPORT_SAFE) do
        if s:find(p) then return true end
    end
    return false
end

-- The value as the report may show it: itself if allowlisted, else its length
function ns.SafeValue(v)
    if type(v) ~= "string" then return tostring(v) end
    if ns.IsSafe(v) then return v end
    return ("<text:%d>"):format(#v)
end

-- A macro text, line by line (the gem macro has several "/use item:N" lines)
function ns.SafeMacro(text)
    local out = {}
    for line in tostring(text):gmatch("[^\n]+") do out[#out + 1] = ns.SafeValue(line) end
    return table.concat(out, " / ")
end

---------------------------------------------------------------------------
-- Names the client knows now: the player, realm, guild, group, target, focus, mouseover, the
-- trade partner. nil when one of them is secret - the filter could not compare it.
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) end

function ns.KnownNames()
    local names, secret = {}, false
    local function Add(v)
        if v == nil then return end
        if Secret(v) then secret = true return end
        if type(v) == "string" and #v >= 2 then names[#names + 1] = v end
    end
    local units = { "player", "target", "focus", "mouseover", "NPC" }
    for i = 1, 4 do units[#units + 1] = "party" .. i end
    for i = 1, 40 do units[#units + 1] = "raid" .. i end
    for _, u in ipairs(units) do
        local name, realm = UnitName(u)
        Add(name); Add(realm)
        if name and realm and not Secret(name) and not Secret(realm) and realm ~= "" then
            Add(name .. "-" .. realm)
        end
    end
    Add(GetRealmName())
    Add(GetNormalizedRealmName())
    Add((GetGuildInfo("player")))
    if secret then return nil end
    -- longest first, so "Name-Realm" goes before "Name"
    table.sort(names, function(a, b) return #a > #b end)
    return names
end

---------------------------------------------------------------------------
-- Filter for free text, error messages, stack lines and addon names
---------------------------------------------------------------------------
-- Letters, digits, "_" and every byte of a non-ASCII character count as part of a word
local function IsWord(b)
    return b ~= nil and (b >= 128 or b == 95 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
        or (b >= 97 and b <= 122))
end

-- Whole words only, ASCII letters in any case, found as plain text (realm names hold "-", "'")
local function ReplaceName(text, name)
    local lowText, lowName = text:lower(), name:lower()
    local out, pos, from = {}, 1, 1
    while true do
        local s, e = lowText:find(lowName, from, true)
        if not s then break end
        if not IsWord(lowText:byte(s - 1)) and not IsWord(lowText:byte(e + 1)) then
            out[#out + 1] = text:sub(pos, s - 1)
            out[#out + 1] = "<name>"
            pos = e + 1
        end
        from = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

local GUID_KINDS = { "Player", "Pet", "Creature", "Vehicle", "GameObject", "Item" }

function ns.Scrub(text, names)
    text = tostring(text or "")
    -- A path ends at Interface/AddOns, whatever drive or folder the game sits in
    text = text:gsub("%a:[\\/][^%[%]\"'\n]-[\\/][Ii]nterface[\\/][Aa]dd[Oo]ns[\\/]", "Interface/AddOns/")
    text = text:gsub("Interface[\\/]AddOns[\\/][^%]%s\"']*", function(p) return (p:gsub("\\", "/")) end)
    text = text:gsub("%a:[\\/][^%s%]\"']*", "<path>")
    text = text:gsub("/Users/[^%s%]\"']*", "<path>")
    text = text:gsub("/home/[^%s%]\"']*", "<path>")
    for _, kind in ipairs(GUID_KINDS) do
        text = text:gsub(kind .. "%-%d+%-[%x%-]+", "<guid>")
    end
    text = text:gsub("[^%s#<>\"'=%[%]]+#%d%d%d%d+", "<tag>")
    for _, name in ipairs(names or {}) do text = ReplaceName(text, name) end
    return text
end

---------------------------------------------------------------------------
-- Locals: BugGrabber's text, one "name=value" per line, strings unescaped (phase 1 research).
-- Each line is rebuilt from its parts; a line that does not parse is dropped.
---------------------------------------------------------------------------
local MAX_LOCALS = 20

local function SafeLocalValue(v)
    if v:find('^".*"$') and #v >= 2 then return '"' .. ns.SafeValue(v:sub(2, -2)) .. '"' end
    if v:find("^%-?%d+%.?%d*$") or v == "true" or v == "false" or v == "nil" then return v end
    local kind = v:match("^<(%a+)>")
    if kind then return "<" .. kind .. ">" .. (v:find("{%s*$") and " {" or "") end
    if v:find("{%s*$") then return "<table> {" end -- a frame or table printed by its name
    return nil
end

function ns.SafeLocals(text, names)
    local out = {}
    for line in tostring(text or ""):gmatch("[^\n]+") do
        if #out >= MAX_LOCALS then break end
        local indent, key, value = line:match("^(%s*)([^=]-)%s*=%s*(.-)%s*$")
        if line:find("^%s*}%s*$") then
            out[#out + 1] = line:match("^%s*") .. "}"
        elseif key and key ~= "" then
            local safeKey
            if indent == "" then
                -- a local variable's name, from the addon's source
                if key:find("^[%a_][%w_]*$") then safeKey = ns.Scrub(key, names) end
            elseif key:find("^%[?%d+%]?$") or ns.IsSafe(key) then
                safeKey = key
            else
                safeKey = "<key>"
            end
            local safeValue = SafeLocalValue(value)
            if safeKey and safeValue then out[#out + 1] = indent .. safeKey .. "=" .. safeValue end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Size: at most D.REPORT_MAX_BYTES, cut at the start of a character, the cut marked
---------------------------------------------------------------------------
function ns.CapReport(text)
    if #text <= D.REPORT_MAX_BYTES then return text end
    local limit = D.REPORT_MAX_BYTES - #D.REPORT_CUT - 1
    while limit > 0 do
        local b = text:byte(limit + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end -- the next byte starts a character
        limit = limit - 1
    end
    return text:sub(1, limit) .. "\n" .. D.REPORT_CUT
end
