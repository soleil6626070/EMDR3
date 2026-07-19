-- modules/check.lua
-- Adequacy check for spoken assessment answers. Assembles the stage's editable
-- prompt file (+ the EMDR cognition examples list for the cognition stages),
-- the running assessment context, and this stage's Q&A exchanges, then asks the
-- LLM worker to judge the latest answer.
--
-- Expected LLM response (contract stated inside each prompt file):
--   { "adequate": bool, "refined_answer": "..."|null, "followup": "..."|null }

local llm            = require("modules.llm")
local identification = require("modules.identification")

local check = {}

local COGNITION_LIST = "emdr_knowledge/positive_negative_cognitions.md"

local CONTEXT_LABELS = {
    { key = "negative_cognition", label = "Negative cognition" },
    { key = "positive_cognition", label = "Positive cognition" },
    { key = "emotion",            label = "Emotions" },
    { key = "body",               label = "Body sensations" },
}

local promptCache = {}

local function readCached(path)
    if promptCache[path] == nil then
        promptCache[path] = love.filesystem.read(path) or false
    end
    return promptCache[path] or nil
end

--- Build the user message: running context + this stage's exchanges, with the
--- last exchange marked as the answer to judge.
local function buildContext(step, exchanges)
    local parts = {}

    local record = identification.record()
    if record then
        parts[#parts + 1] = "# Running context\n\nTarget image: "
            .. (record.image and record.image.description or "(none)")
        for _, entry in ipairs(CONTEXT_LABELS) do
            if entry.key ~= step.stage then
                local s = record.stages and record.stages[entry.key]
                if s and s.answer then
                    parts[#parts + 1] = entry.label .. ": " .. s.answer
                end
            end
        end
    end

    local lines = { "# This stage's exchanges" }
    for i, ex in ipairs(exchanges) do
        lines[#lines + 1] = "Question: " .. (ex.question or "")
        if i == #exchanges then
            lines[#lines + 1] = "Answer (JUDGE THIS ONE): " .. (ex.response or "")
        else
            lines[#lines + 1] = "Answer: " .. (ex.response or "")
        end
    end
    parts[#parts + 1] = table.concat(lines, "\n")

    return table.concat(parts, "\n\n")
end

--- Judge the latest answer for a stage.
-- @param step      the identification step table (stage, check_prompt, ...)
-- @param exchanges this stage's { question, response } list, latest included
-- @param cb        function(success, resultTable_or_nil, error_or_nil)
function check.evaluate(step, exchanges, cb)
    local system = readCached(step.check_prompt)
    if not system then
        cb(false, nil, "missing prompt file: " .. tostring(step.check_prompt))
        return
    end

    if step.use_cognition_list then
        local list = readCached(COGNITION_LIST)
        if list then
            system = system .. "\n\n# Reference: example cognitions from the EMDR literature\n\n" .. list
        end
    end

    llm.request({
        system      = system,
        user        = buildContext(step, exchanges),
        expect_json = true,
        max_tokens  = 400,
    }, cb)
end

return check
