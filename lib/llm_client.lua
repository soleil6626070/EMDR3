-- lib/llm_client.lua
-- Shared LLM chat helper for worker threads (cue_in_thread, llm_thread).
-- The requiring thread must already have lib/ on package.path/cpath so that
-- require("https") and require("json") resolve.

local https = require("https")
local json  = require("json")

local llm_client = {}

--- Call a chat LLM with a system + user message.
-- opts: {
--   provider    = "openai" | "anthropic"  (anything else falls back to openai)
--   model       = model id string
--   api_key     = key for the chosen provider
--   system      = system prompt text
--   user        = user message text
--   max_tokens  = Anthropic max_tokens (default 512)
--   temperature = OpenAI temperature (default 0.3)
-- }
-- Returns response text, or nil + error string.
function llm_client.chat(opts)
    if opts.provider == "anthropic" then
        return llm_client.callAnthropic(opts)
    end
    return llm_client.callOpenAI(opts)
end

function llm_client.callOpenAI(opts)
    local url = "https://api.openai.com/v1/chat/completions"

    local body = json.encode({
        model = opts.model,
        messages = {
            { role = "system", content = opts.system },
            { role = "user",   content = opts.user },
        },
        temperature = opts.temperature or 0.3,
    })

    local code, respBody = https.request(url, {
        method  = "POST",
        headers = {
            ["Content-Type"]  = "application/json",
            ["Authorization"] = "Bearer " .. tostring(opts.api_key),
        },
        data = body,
    })

    if code ~= 200 then
        return nil, "OpenAI HTTP " .. tostring(code) .. ": " .. tostring(respBody):sub(1, 300)
    end

    local ok, parsed = pcall(json.decode, respBody)
    if not ok or type(parsed) ~= "table" then
        return nil, "OpenAI: failed to parse response"
    end

    local choices = parsed.choices
    if not choices or not choices[1] then
        return nil, "OpenAI: no choices in response"
    end

    return choices[1].message.content
end

function llm_client.callAnthropic(opts)
    local url = "https://api.anthropic.com/v1/messages"

    local body = json.encode({
        model      = opts.model,
        max_tokens = opts.max_tokens or 512,
        system     = opts.system,
        messages   = {
            { role = "user", content = opts.user },
        },
    })

    local code, respBody = https.request(url, {
        method  = "POST",
        headers = {
            ["Content-Type"]      = "application/json",
            ["x-api-key"]         = tostring(opts.api_key),
            ["anthropic-version"] = "2023-06-01",
        },
        data = body,
    })

    if code ~= 200 then
        return nil, "Anthropic HTTP " .. tostring(code) .. ": " .. tostring(respBody):sub(1, 300)
    end

    local ok, parsed = pcall(json.decode, respBody)
    if not ok or type(parsed) ~= "table" then
        return nil, "Anthropic: failed to parse response"
    end

    local content = parsed.content
    if not content or not content[1] then
        return nil, "Anthropic: no content in response"
    end

    return content[1].text
end

--- Parse an LLM response expected to be a JSON object, stripping any accidental
-- markdown fences. Returns table, or nil + error string.
function llm_client.parse_json(text)
    local cleaned = text:match("```json%s*(.-)%s*```") or
                    text:match("```%s*(.-)%s*```") or
                    text

    local ok, parsed = pcall(json.decode, cleaned)
    if not ok or type(parsed) ~= "table" then
        return nil, "unexpected LLM response format: " .. tostring(text):sub(1, 200)
    end
    return parsed
end

return llm_client
