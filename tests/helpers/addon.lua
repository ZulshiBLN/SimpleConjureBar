-- Loads the addon as the client does: the mocked WoW API first, then every
-- file the TOC lists, in the TOC's order, each called with the addon's name
-- and one shared namespace. The file list is read from the TOC, never retyped.
local M = {}

local ADDON = "SimpleConjureBar"

function M.read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

-- The Lua files of the TOC, in load order.
function M.tocFiles()
    local files = {}
    for line in M.read(ADDON .. "/" .. ADDON .. ".toc"):gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%S") then
            files[#files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    return files
end

-- A fresh mocked client with the addon loaded; `locale` is what GetLocale
-- answers. `adjust`, if given, runs between the mock and the addon - the
-- addon captures API functions while it loads, so changes must come first.
-- Returns the addon's namespace.
function M.load(locale, adjust)
    assert(loadfile("tests/helpers/mock.lua"))()
    STATE.locale = locale or "deDE"
    if adjust then adjust() end
    local ns = {}
    for _, file in ipairs(M.tocFiles()) do
        local chunk = assert(loadstring(M.read(ADDON .. "/" .. file), "@" .. ADDON .. "/" .. file))
        chunk(ADDON, ns)
    end
    return ns
end

return M
