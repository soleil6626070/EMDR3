-- modules/assessment_json.lua
-- Read/merge/write helpers for the per-target assessment record produced by the
-- identification flow. Pure Lua + io/os only (no love.* calls); the main thread
-- is the sole writer, same single-writer rule as session records.
--
-- Record shape (output_data/targets/<slug>/assessment.json):
-- {
--   version, target, started, conversation_id,
--   image = { description, confirmed },
--   stages = {
--     negative_cognition = { answer, flagged, attempts,
--                            exchanges = { { question, response }, ... } },
--     positive_cognition = { ... }, emotion = { ... }, body = { ... },
--   },
--   voc, sud, completed
-- }

local json = require("json")

local assessment_json = {}

local STAGE_ORDER = { "negative_cognition", "positive_cognition", "emotion", "body" }

--- Load an assessment record from disk. Returns nil if missing or unparseable.
function assessment_json.load(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local ok, record = pcall(json.decode, content)
    if not ok or type(record) ~= "table" then return nil end
    record.stages = record.stages or {}
    return record
end

local function encodeStage(s)
    local lines = {
        '      "answer": '   .. json.encode(s.answer) .. ",",
        '      "flagged": '  .. json.encode(s.flagged or false) .. ",",
        '      "attempts": ' .. json.encode(s.attempts or 1) .. ",",
        '      "exchanges": [',
    }
    local exchanges = s.exchanges or {}
    for i, ex in ipairs(exchanges) do
        lines[#lines + 1] = string.format('        { "question": %s, "response": %s }%s',
            json.encode(ex.question), json.encode(ex.response),
            i < #exchanges and "," or "")
    end
    lines[#lines + 1] = "      ]"
    return table.concat(lines, "\n")
end

--- Serialize with fixed field order + indentation so the file stays pleasant
--- to read; individual values go through json.encode for correct escaping.
local function encodeRecord(r)
    local image = r.image or {}
    local lines = {
        "{",
        '  "version": '         .. json.encode(r.version or 1) .. ",",
        '  "target": '          .. json.encode(r.target) .. ",",
        '  "started": '         .. json.encode(r.started) .. ",",
        '  "conversation_id": ' .. json.encode(r.conversation_id) .. ",",
        '  "image": {',
        '    "description": '   .. json.encode(image.description) .. ",",
        '    "confirmed": '     .. json.encode(image.confirmed or false),
        "  },",
        '  "stages": {',
    }

    local present = {}
    for _, key in ipairs(STAGE_ORDER) do
        if r.stages[key] then present[#present + 1] = key end
    end
    for i, key in ipairs(present) do
        lines[#lines + 1] = '    ' .. json.encode(key) .. ": {"
        lines[#lines + 1] = encodeStage(r.stages[key])
        lines[#lines + 1] = "    }" .. (i < #present and "," or "")
    end

    lines[#lines + 1] = "  },"
    lines[#lines + 1] = '  "voc": '       .. json.encode(r.voc) .. ","
    lines[#lines + 1] = '  "sud": '       .. json.encode(r.sud) .. ","
    lines[#lines + 1] = '  "completed": ' .. json.encode(r.completed or false)
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

--- Create the parent directory for a record path (called once at creation).
function assessment_json.ensureDir(path)
    local dir = path:match("^(.*)/[^/]+$")
    if dir then os.execute('mkdir -p "' .. dir .. '"') end
end

function assessment_json.save(path, record)
    local f = io.open(path, "w")
    if not f then
        print("[AssessmentJSON] Could not open for writing: " .. path)
        return false
    end
    f:write(encodeRecord(record))
    f:close()
    return true
end

--- Merge top-level fields into the record at path (created if absent), then save.
function assessment_json.merge(path, fields)
    local record = assessment_json.load(path) or { stages = {} }
    for k, v in pairs(fields) do record[k] = v end
    return assessment_json.save(path, record)
end

--- Replace one stage's table wholesale, then save. Idempotent on retry.
function assessment_json.setStage(path, stageKey, stageTable)
    local record = assessment_json.load(path) or { stages = {} }
    record.stages[stageKey] = stageTable
    return assessment_json.save(path, record)
end

return assessment_json
