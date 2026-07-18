-- modules/llm_thread.lua
-- Background worker for generic LLM calls. Pure request/response over channels;
-- never touches files. One request at a time, FIFO.

local requestChannel  = love.thread.getChannel("llm_request")
local responseChannel = love.thread.getChannel("llm_response")
local configChannel   = love.thread.getChannel("llm_config")

local cfg = configChannel:demand()

package.cpath = cfg.source_path .. "/lib/?.so;" .. cfg.source_path .. "/lib/?.dll;" .. package.cpath
package.path  = cfg.source_path .. "/lib/?.lua;" .. cfg.source_path .. "/lib/?/init.lua;" .. package.path

local llm_client = require("llm_client")

local apiKey = cfg.provider == "anthropic" and cfg.anthropic_api_key or cfg.openai_api_key

while true do
    local req = requestChannel:demand()
    if req == "quit" then break end

    local text, err = llm_client.chat({
        provider   = cfg.provider,
        model      = cfg.model,
        api_key    = apiKey,
        system     = req.system,
        user       = req.user,
        max_tokens = req.max_tokens,
    })

    if not text then
        responseChannel:push({ request_id = req.request_id, success = false, error = err })
    elseif req.expect_json then
        local parsed, perr = llm_client.parse_json(text)
        if parsed then
            responseChannel:push({ request_id = req.request_id, success = true, parsed = parsed, text = text })
        else
            responseChannel:push({ request_id = req.request_id, success = false, error = perr })
        end
    else
        responseChannel:push({ request_id = req.request_id, success = true, text = text })
    end
end
