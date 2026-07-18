-- modules/llm.lua
-- Main-thread API for generic LLM text calls. Screens/modules call
-- llm.request({system=..., user=..., expect_json=true}, callback) and receive the
-- result via callback on a later frame — same id-keyed callback pattern as tts.lua.
-- Provider/model/keys come from config (config.LLM_PROVIDER / LLM_MODEL).

local llm = {}

local thread
local requestChannel
local responseChannel
local configChannel
local callbacks = {}
local nextId = 1

function llm.init(cfg)
    requestChannel  = love.thread.getChannel("llm_request")
    responseChannel = love.thread.getChannel("llm_response")
    configChannel   = love.thread.getChannel("llm_config")

    thread = love.thread.newThread("modules/llm_thread.lua")
    configChannel:push({
        source_path       = love.filesystem.getSource(),
        provider          = cfg.LLM_PROVIDER,
        model             = cfg.LLM_MODEL,
        openai_api_key    = cfg.OPENAI_API_KEY,
        anthropic_api_key = cfg.ANTHROPIC_API_KEY,
    })
    thread:start()
end

--- Request an LLM completion.
-- @param req      table: { system = "...", user = "...", expect_json = bool,
--                          max_tokens = optional number }
-- @param callback function(success, result, error) — result is a decoded table
--                 when expect_json, else the raw text. An expect_json request
--                 whose response fails to parse comes back as success = false.
function llm.request(req, callback)
    local id = nextId
    nextId = nextId + 1
    callbacks[id] = callback

    requestChannel:push({
        request_id  = id,
        system      = req.system,
        user        = req.user,
        expect_json = req.expect_json or false,
        max_tokens  = req.max_tokens,
    })
end

--- Call every frame from love.update(dt).
function llm.update()
    local err = thread:getError()
    if err then
        print("[LLM] Thread error: " .. err)
    end

    while true do
        local resp = responseChannel:pop()
        if not resp then break end

        local cb = callbacks[resp.request_id]
        callbacks[resp.request_id] = nil

        if resp.success then
            if cb then cb(true, resp.parsed or resp.text, nil) end
        else
            print("[LLM] Request failed: " .. tostring(resp.error))
            if cb then cb(false, nil, resp.error) end
        end
    end
end

function llm.shutdown()
    if thread and thread:isRunning() then
        requestChannel:push("quit")
        thread:wait()
    end
end

return llm
