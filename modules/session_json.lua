-- modules/session_json.lua
-- Read/merge/write helpers for the per-session JSON record.
-- Pure Lua + io/os only (no love.* calls). All record writes happen on the
-- main thread — the whisper worker only returns text, it never writes records.
--
-- Record shape:
-- {
--   session_id, target, started, total_cycles,
--   pre_sud, post_sud, completed,
--   responses = { { cycle, text }, ... }   -- kept sorted by cycle
-- }

local json = require("json")

local session_json = {}

--- Load a session record from disk. Returns nil if missing or unparseable.
function session_json.load(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local ok, record = pcall(json.decode, content)
    if not ok or type(record) ~= "table" then return nil end
    record.responses = record.responses or {}
    return record
end

--- Serialize with fixed field order + indentation so the file stays pleasant
--- to read; individual values go through json.encode for correct escaping.
local function encodeRecord(r)
    table.sort(r.responses, function(a, b) return (a.cycle or 0) < (b.cycle or 0) end)

    local lines = {
        "{",
        '  "session_id": '   .. json.encode(r.session_id) .. ",",
        '  "target": '       .. json.encode(r.target) .. ",",
        '  "started": '      .. json.encode(r.started) .. ",",
        '  "total_cycles": ' .. json.encode(r.total_cycles) .. ",",
        '  "pre_sud": '      .. json.encode(r.pre_sud) .. ",",
        '  "post_sud": '     .. json.encode(r.post_sud) .. ",",
        '  "completed": '    .. json.encode(r.completed or false) .. ",",
        '  "responses": [',
    }
    for i, resp in ipairs(r.responses) do
        lines[#lines + 1] = string.format('    { "cycle": %d, "text": %s }%s',
            resp.cycle, json.encode(resp.text), i < #r.responses and "," or "")
    end
    lines[#lines + 1] = "  ]"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

--- Create the parent directory for a record path. Called once when a record
--- is created — not in save(), which runs on the main thread per write and
--- shouldn't spawn a shell each time.
function session_json.ensureDir(path)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then os.execute('mkdir -p "' .. dir .. '"') end
end

function session_json.save(path, record)
    local f = io.open(path, "w")
    if not f then
        print("[SessionJSON] Could not open for writing: " .. path)
        return false
    end
    f:write(encodeRecord(record))
    f:close()
    return true
end

--- Merge top-level fields into the record at path (created if absent), then save.
function session_json.merge(path, fields)
    local record = session_json.load(path) or { responses = {} }
    for k, v in pairs(fields) do record[k] = v end
    return session_json.save(path, record)
end

--- Insert or replace the response for a cycle, then save. Idempotent on retry.
function session_json.upsertResponse(path, session_id, cycle, text)
    local record = session_json.load(path)
        or { session_id = session_id, responses = {} }

    for _, resp in ipairs(record.responses) do
        if resp.cycle == cycle then
            resp.text = text
            return session_json.save(path, record)
        end
    end
    table.insert(record.responses, { cycle = cycle, text = text })
    return session_json.save(path, record)
end

return session_json
