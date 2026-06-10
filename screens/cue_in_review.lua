-- screens/cue_in_review.lua
-- Shows the cue-in script for the selected target. The user can read it,
-- edit it with basic text editing, then regenerate the TTS audio.
-- session.selectedTargetDir must be set before switching to this screen.

local config  = require("config")
local session = require("modules.session")

local cue_in_review = {}

local fontTitle, fontBody, fontHint, fontEdit
local scriptText = ""
local editMode   = false
local statusMsg  = nil
local statusCol  = {1, 1, 1}

-- Regeneration state
local regenThread   = nil
local regenReqCh    = nil
local regenRespCh   = nil
local regenCfgCh    = nil
local regenerating  = false

----------------------------------------------------------------------
-- File I/O helpers
----------------------------------------------------------------------

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function writeFile(path, text)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

----------------------------------------------------------------------
-- TTS regeneration (inline thread, avoids cue_in module complexity)
----------------------------------------------------------------------

local REGEN_THREAD_CODE = [[
local reqCh  = love.thread.getChannel("cir_request")
local respCh = love.thread.getChannel("cir_response")
local cfgCh  = love.thread.getChannel("cir_config")

local cfg = cfgCh:demand()
package.cpath = cfg.src .. "/lib/?.so;" .. cfg.src .. "/lib/?.dll;" .. package.cpath

local https = require("https")

local req = reqCh:demand()
local url = cfg.base_url .. "/text-to-speech/" .. cfg.voice_id

local escaped = req.text:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
local body = string.format(
    '{"text":"%s","model_id":"%s","voice_settings":{"stability":0.5,"similarity_boost":0.75}}',
    escaped, cfg.model_id
)

local code, respBody = https.request(url, {
    method  = "POST",
    headers = {
        ["Accept"]       = "audio/mpeg",
        ["Content-Type"] = "application/json",
        ["xi-api-key"]   = cfg.api_key,
    },
    data = body,
})

if code == 200 then
    local f = io.open(req.out_path, "wb")
    if f then
        f:write(respBody)
        f:close()
        respCh:push({ success = true })
    else
        respCh:push({ success = false, error = "Cannot write " .. req.out_path })
    end
else
    respCh:push({ success = false, error = "HTTP " .. tostring(code) })
end
]]

local function startRegen(text, outPath)
    regenReqCh  = love.thread.getChannel("cir_request")
    regenRespCh = love.thread.getChannel("cir_response")
    regenCfgCh  = love.thread.getChannel("cir_config")

    regenCfgCh:push({
        src      = love.filesystem.getSource(),
        base_url = config.ELEVENLABS_BASE_URL,
        voice_id = config.ELEVENLABS_VOICE_ID,
        model_id = config.ELEVENLABS_MODEL_ID,
        api_key  = config.ELEVENLABS_API_KEY,
    })
    regenReqCh:push({ text = text, out_path = outPath })

    regenThread = love.thread.newThread(REGEN_THREAD_CODE)
    regenThread:start()
    regenerating = true
    statusMsg = "Regenerating audio..."
    statusCol = {0.9, 0.8, 0.3}
end

----------------------------------------------------------------------
-- Screen lifecycle
----------------------------------------------------------------------

function cue_in_review.load()
    fontTitle = love.graphics.newFont(24)
    fontBody  = love.graphics.newFont(16)
    fontHint  = love.graphics.newFont(13)
    fontEdit  = love.graphics.newFont(16)
    editMode  = false
    statusMsg = nil
    regenerating = false

    local dir = session.selectedTargetDir
    if not dir then
        scriptText = "(No target selected)"
        return
    end

    local text = readFile(dir .. "/script.txt")
    scriptText = text or "(script.txt not found)"
end

function cue_in_review.update(dt)
    if not regenerating then return end

    local err = regenThread and regenThread:getError()
    if err then
        statusMsg  = "Thread error: " .. err
        statusCol  = {0.9, 0.3, 0.3}
        regenerating = false
        return
    end

    local resp = regenRespCh and regenRespCh:pop()
    if resp then
        regenerating = false
        if resp.success then
            statusMsg = "Audio regenerated successfully."
            statusCol = {0.3, 0.9, 0.4}
        else
            statusMsg = "TTS error: " .. tostring(resp.error)
            statusCol = {0.9, 0.3, 0.3}
        end
    end
end

function cue_in_review.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Title
    love.graphics.setFont(fontTitle)
    love.graphics.setColor(1, 1, 1)
    local name = session.selectedTargetName or "target"
    local title = "Cue-In Script: " .. name:gsub("_", " ")
    love.graphics.print(title, (W - fontTitle:getWidth(title)) / 2, 24)

    -- Script text area
    local areaX, areaY, areaW, areaH = 60, 80, W - 120, H - 180

    local bgCol = editMode and {0.10, 0.12, 0.16} or {0.07, 0.07, 0.10}
    love.graphics.setColor(bgCol[1], bgCol[2], bgCol[3])
    love.graphics.rectangle("fill", areaX, areaY, areaW, areaH, 8, 8)

    if editMode then
        love.graphics.setColor(0.4, 0.6, 0.9, 0.8)
    else
        love.graphics.setColor(0.2, 0.3, 0.5, 0.6)
    end
    love.graphics.rectangle("line", areaX, areaY, areaW, areaH, 8, 8)

    love.graphics.setScissor(areaX + 8, areaY + 8, areaW - 16, areaH - 16)
    love.graphics.setFont(fontEdit)
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.printf(scriptText .. (editMode and "|" or ""), areaX + 16, areaY + 16, areaW - 32)
    love.graphics.setScissor()

    -- Edit mode label
    if editMode then
        love.graphics.setFont(fontHint)
        love.graphics.setColor(0.4, 0.7, 1.0)
        love.graphics.print("[EDITING]", areaX + 8, areaY + areaH - 22)
    end

    -- Status message
    if statusMsg then
        love.graphics.setFont(fontHint)
        love.graphics.setColor(statusCol[1], statusCol[2], statusCol[3])
        local sw = fontHint:getWidth(statusMsg)
        love.graphics.print(statusMsg, (W - sw) / 2, H - 60)
    end

    -- Hints
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.4, 0.4, 0.5)
    local hint
    if editMode then
        hint = "Type to edit   Escape — stop editing   Enter — save & regenerate audio"
    elseif regenerating then
        hint = "Regenerating audio, please wait..."
    else
        hint = "E — edit script   G — regenerate audio   Escape — back to target list"
    end
    love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
end

function cue_in_review.keypressed(k)
    if editMode then
        if k == "escape" then
            editMode = false
        elseif k == "return" or k == "kpenter" then
            -- Save and regenerate
            editMode = false
            local dir = session.selectedTargetDir
            if dir then
                writeFile(dir .. "/script.txt", scriptText)
                startRegen(scriptText, dir .. "/cue_in.mp3")
            end
        elseif k == "backspace" then
            scriptText = scriptText:sub(1, -2)
        end
        return
    end

    -- Normal mode
    if k == "escape" then
        switchScreen("target_select")
    elseif k == "e" then
        editMode = true
        statusMsg = nil
    elseif k == "g" then
        if not regenerating then
            local dir = session.selectedTargetDir
            if dir then
                writeFile(dir .. "/script.txt", scriptText)
                startRegen(scriptText, dir .. "/cue_in.mp3")
            end
        end
    end
end

function cue_in_review.textinput(t)
    if editMode then
        scriptText = scriptText .. t
    end
end

return cue_in_review
