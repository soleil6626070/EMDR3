-- screens/ident_review.lua
-- Sectioned review of the captured assessment before the cue-in script is
-- generated. Every section can be corrected: text sections are editable
-- (append-style editing, as cue_in_review), spoken stages can be re-recorded
-- (jumps back into ident_stage, returns here), ratings adjust with ←/→.
-- Sections the AI is unsure about are badged: an unconfirmed image (capped-out
-- call) or a stage that exhausted its follow-ups.
--
-- Enter confirms: marks the record completed, clears the resume marker, and
-- kicks off cue-in generation in the background (menu shows progress).
-- Escape pauses (resumable); D discards (record stays on disk, not resumable).

local identification  = require("modules.identification")
local assessment_json = require("modules.assessment_json")
local cue_in          = require("modules.cue_in")

local ident_review = {}

local record
local sections
local selected
local editMode, editText, suppressNextTextinput
local fontTitle, fontLabel, fontValue, fontHint
local statusMsg

local STAGE_META = {
    { id = "nc",      stage = "negative_cognition", label = "Negative cognition" },
    { id = "pc",      stage = "positive_cognition", label = "Positive cognition" },
    { id = "emotion", stage = "emotion",            label = "Emotions" },
    { id = "body",    stage = "body",               label = "Body sensations" },
}

local function refreshRecord()
    record = identification.record() or { stages = {}, image = {} }
end

local function buildSections()
    sections = {}

    sections[#sections + 1] = {
        kind = "text", label = "Target image",
        value = function() return record.image and record.image.description or "" end,
        badge = function()
            return (record.image and record.image.confirmed) ~= true and "unconfirmed" or nil
        end,
        save = function(text)
            assessment_json.merge(identification.recordPath(), {
                image = { description = text, confirmed = true },
            })
        end,
    }

    local function stageSection(meta)
        return {
            kind = "stage", label = meta.label, stepId = meta.id,
            value = function()
                local s = record.stages[meta.stage]
                return s and s.answer or "(not captured)"
            end,
            badge = function()
                local s = record.stages[meta.stage]
                return (s and s.flagged) and "flagged — please check" or nil
            end,
            save = function(text)
                local s = record.stages[meta.stage] or {}
                identification.setAnswer(meta.stage, {
                    answer    = text,
                    flagged   = false,   -- user corrected it by hand
                    attempts  = s.attempts or 1,
                    exchanges = s.exchanges or {},
                })
            end,
        }
    end

    sections[#sections + 1] = stageSection(STAGE_META[1])
    sections[#sections + 1] = stageSection(STAGE_META[2])
    sections[#sections + 1] = {
        kind = "rating", label = "VoC — how true the positive belief feels (1–7)",
        key = "voc", min = 1, max = 7,
        value = function() return record.voc and tostring(record.voc) or "-" end,
        badge = function() return nil end,
    }
    sections[#sections + 1] = stageSection(STAGE_META[3])
    sections[#sections + 1] = {
        kind = "rating", label = "SUD — how disturbing it feels (0–10)",
        key = "sud", min = 0, max = 10,
        value = function() return record.sud and tostring(record.sud) or "-" end,
        badge = function() return nil end,
    }
    sections[#sections + 1] = stageSection(STAGE_META[4])
end

function ident_review.load()
    refreshRecord()
    buildSections()
    selected  = 1
    editMode  = false
    editText  = ""
    statusMsg = nil
    suppressNextTextinput = false

    fontTitle = love.graphics.newFont(26)
    fontLabel = love.graphics.newFont(15)
    fontValue = love.graphics.newFont(17)
    fontHint  = love.graphics.newFont(14)
end

function ident_review.update(dt) end

function ident_review.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    love.graphics.setFont(fontTitle)
    love.graphics.setColor(0.85, 0.90, 1.0)
    local title = "Review — " .. tostring(identification.targetName or ""):gsub("_", " ")
    love.graphics.print(title, (W - fontTitle:getWidth(title)) / 2, 28)

    local y = 90
    for i, sec in ipairs(sections) do
        local isSel = (i == selected)
        local x = W * 0.1
        local width = W * 0.8

        -- Label + badge
        love.graphics.setFont(fontLabel)
        love.graphics.setColor(isSel and {1, 1, 1} or {0.55, 0.62, 0.75})
        love.graphics.print((isSel and "> " or "  ") .. sec.label, x, y)
        local badge = sec.badge()
        if badge then
            love.graphics.setColor(1.0, 0.75, 0.35)
            love.graphics.print("⚠ " .. badge, x + width - 220, y)
        end
        y = y + 20

        -- Value (or edit buffer)
        love.graphics.setFont(fontValue)
        local text
        if isSel and editMode then
            text = editText .. "|"
            love.graphics.setColor(1, 1, 0.85)
        else
            text = sec.value()
            if #text > 220 then text = text:sub(1, 220) .. "…" end
            love.graphics.setColor(isSel and {0.95, 0.97, 1.0} or {0.7, 0.75, 0.85})
        end
        love.graphics.printf(text, x + 16, y, width - 32)
        local _, wrapped = fontValue:getWrap(text, width - 32)
        y = y + #wrapped * fontValue:getHeight() + 14
    end

    if statusMsg then
        love.graphics.setFont(fontHint)
        love.graphics.setColor(0.9, 0.6, 0.5)
        love.graphics.print(statusMsg, (W - fontHint:getWidth(statusMsg)) / 2, H - 64)
    end

    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.4, 0.45, 0.55)
    local hint
    if editMode then
        hint = "Type to append   Backspace — delete   Enter — save   Escape — cancel edit"
    else
        local sec = sections[selected]
        local parts = { "↑↓ select" }
        if sec.kind == "rating" then parts[#parts + 1] = "← → adjust"
        else parts[#parts + 1] = "E — edit" end
        if sec.kind == "stage" then parts[#parts + 1] = "R — re-record" end
        parts[#parts + 1] = "Enter — confirm & generate cue-in"
        parts[#parts + 1] = "D — discard"
        parts[#parts + 1] = "Escape — pause"
        hint = table.concat(parts, "   ")
    end
    love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
end

local function confirmAndGenerate()
    -- Read the raw record text for the cue-in prompt BEFORE complete() resets state
    local path = identification.recordPath()
    local slug = identification.targetName
    local f = io.open(path, "r")
    local raw = f and f:read("*a") or nil
    if f then f:close() end

    if not raw then
        statusMsg = "Could not read the assessment record."
        return
    end

    cue_in.generate({ slug = slug, assessment = raw })
    identification.complete()
    switchScreen("menu")
end

function ident_review.keypressed(k)
    local sec = sections[selected]

    if editMode then
        if k == "escape" then
            editMode = false
        elseif k == "backspace" then
            editText = editText:sub(1, -2)
        elseif k == "return" or k == "kpenter" then
            if editText ~= "" then
                sec.save(editText)
                refreshRecord()
            end
            editMode = false
        end
        return
    end

    if k == "escape" then
        switchScreen("menu")   -- marker stays: resumable
    elseif k == "up" then
        selected = selected > 1 and selected - 1 or #sections
    elseif k == "down" then
        selected = selected < #sections and selected + 1 or 1
    elseif k == "e" and sec.kind ~= "rating" then
        editMode = true
        editText = sec.value()
        if editText == "(not captured)" then editText = "" end
        suppressNextTextinput = true
    elseif k == "r" and sec.kind == "stage" then
        identification.rerunStep(sec.stepId)
    elseif k == "d" then
        identification.discard()
        switchScreen("menu")
    elseif (k == "left" or k == "right") and sec.kind == "rating" then
        local current = tonumber(sec.value()) or sec.min
        local value = k == "left" and math.max(sec.min, current - 1)
                                   or math.min(sec.max, current + 1)
        identification.setRating(sec.key, value)
        refreshRecord()
    elseif k == "return" or k == "kpenter" then
        confirmAndGenerate()
    end
end

function ident_review.textinput(t)
    if suppressNextTextinput then
        suppressNextTextinput = false
        return
    end
    if editMode then
        editText = editText .. t
    end
end

return ident_review
