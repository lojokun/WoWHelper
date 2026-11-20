-- Minimal JSON decoder (Lua 5.1). Guides are shipped and imported as JSON text
-- and decoded here at login. JSON null becomes nil.
local _, ns = ...

local JSON = {}
ns.JSON = JSON

local byte, sub, find, char = string.byte, string.sub, string.find, string.char
local floor, tonumber, concat = math.floor, tonumber, table.concat

local function fail(pos, msg)
    error(("JSON error at character %d: %s"):format(pos, msg), 0)
end

local function skip(str, pos)
    local _, e = find(str, "^[ \n\r\t]*", pos)
    return e + 1
end

local ESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function utf8char(cp)
    if cp < 0x80 then
        return char(cp)
    elseif cp < 0x800 then
        return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
        0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local parseValue

local function parseString(str, pos)
    local buf, i = {}, pos + 1
    while true do
        local s = find(str, '["\\]', i)
        if not s then fail(pos, "unterminated string") end
        if s > i then buf[#buf + 1] = sub(str, i, s - 1) end
        if byte(str, s) == 34 then -- closing quote
            return concat(buf), s + 1
        end
        local c = sub(str, s + 1, s + 1)
        if c == "u" then
            local cp = tonumber(sub(str, s + 2, s + 5), 16)
            if not cp then fail(s, "bad \\u escape") end
            local nexti = s + 6
            if cp >= 0xD800 and cp <= 0xDBFF and sub(str, nexti, nexti + 1) == "\\u" then
                local lo = tonumber(sub(str, nexti + 2, nexti + 5), 16)
                if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    nexti = nexti + 6
                end
            end
            buf[#buf + 1] = utf8char(cp)
            i = nexti
        else
            local r = ESCAPES[c]
            if not r then fail(s, "bad escape \\" .. c) end
            buf[#buf + 1] = r
            i = s + 2
        end
    end
end

local function parseNumber(str, pos)
    local s, e = find(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not s then fail(pos, "bad number") end
    local n = tonumber(sub(str, s, e))
    if not n then fail(pos, "bad number") end
    return n, e + 1
end

local function parseArray(str, pos)
    local arr, n = {}, 0
    pos = skip(str, pos + 1)
    if byte(str, pos) == 93 then return arr, pos + 1 end -- ]
    while true do
        local v
        v, pos = parseValue(str, pos)
        n = n + 1
        arr[n] = v
        pos = skip(str, pos)
        local c = byte(str, pos)
        if c == 93 then return arr, pos + 1 end
        if c ~= 44 then fail(pos, "expected ',' or ']'") end
        pos = skip(str, pos + 1)
    end
end

local function parseObject(str, pos)
    local obj = {}
    pos = skip(str, pos + 1)
    if byte(str, pos) == 125 then return obj, pos + 1 end -- }
    while true do
        if byte(str, pos) ~= 34 then fail(pos, "expected string key") end
        local key
        key, pos = parseString(str, pos)
        pos = skip(str, pos)
        if byte(str, pos) ~= 58 then fail(pos, "expected ':'") end
        pos = skip(str, pos + 1)
        local v
        v, pos = parseValue(str, pos)
        obj[key] = v
        pos = skip(str, pos)
        local c = byte(str, pos)
        if c == 125 then return obj, pos + 1 end
        if c ~= 44 then fail(pos, "expected ',' or '}'") end
        pos = skip(str, pos + 1)
    end
end

parseValue = function(str, pos)
    pos = skip(str, pos)
    local c = sub(str, pos, pos)
    if c == "{" then return parseObject(str, pos) end
    if c == "[" then return parseArray(str, pos) end
    if c == '"' then return parseString(str, pos) end
    if c == "-" or c:match("%d") then return parseNumber(str, pos) end
    if sub(str, pos, pos + 3) == "true" then return true, pos + 4 end
    if sub(str, pos, pos + 4) == "false" then return false, pos + 5 end
    if sub(str, pos, pos + 3) == "null" then return nil, pos + 4 end
    fail(pos, "unexpected character '" .. c .. "'")
end

-- Returns value, or nil and an error message.
function JSON.decode(str)
    if type(str) ~= "string" then return nil, "expected a string" end
    local ok, value, pos = pcall(parseValue, str, 1)
    if not ok then return nil, value end
    pos = skip(str, pos)
    if pos <= #str then return nil, ("JSON error at character %d: trailing data"):format(pos) end
    return value
end
