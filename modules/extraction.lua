-- modules/extraction.lua
-- Post-call extraction: turns the agent-call transcript into the confirmed
-- target image + slug via one LLM call (prompts/extraction.md). This is the
-- output side of the agent seam — swap the agent vendor and this contract
-- ("transcript in, {slug, image, confirmed} out") is all that must survive.

local llm = require("modules.llm")

local extraction = {}

local PROMPT_FILE = "prompts/extraction.md"

--- Run extraction on a transcript.
-- @param transcript array of { role = "agent"|"user", text } (agent.getTranscript())
-- @param cb function(success, { slug, image, confirmed } or nil, error_or_nil)
function extraction.run(transcript, cb)
    local system = love.filesystem.read(PROMPT_FILE)
    if not system then
        cb(false, nil, "missing prompt file: " .. PROMPT_FILE)
        return
    end

    local lines = {}
    for _, msg in ipairs(transcript) do
        lines[#lines + 1] = (msg.role == "user" and "User: " or "Agent: ") .. (msg.text or "")
    end
    if #lines == 0 then
        cb(false, nil, "empty transcript")
        return
    end

    llm.request({
        system      = system,
        user        = table.concat(lines, "\n"),
        expect_json = true,
        max_tokens  = 500,
    }, function(ok, parsed, err)
        if not ok then
            cb(false, nil, err)
            return
        end
        if type(parsed) ~= "table" or type(parsed.slug) ~= "string"
           or type(parsed.image) ~= "string" or parsed.image == "" then
            cb(false, nil, "extraction returned unexpected format")
            return
        end
        local slug = parsed.slug:gsub("[^%w_%-]", "_"):lower()
        if slug == "" then slug = "unnamed_target" end
        cb(true, {
            slug      = slug,
            image     = parsed.image,
            confirmed = parsed.confirmed == true,
        })
    end)
end

return extraction
