-- modules/transcript_list.lua
-- Singly-linked list of {cycle, response_text} nodes sorted by cycle number.

local TranscriptList = {}
TranscriptList.__index = TranscriptList

function TranscriptList.new()
    return setmetatable({ head = nil, length = 0 }, TranscriptList)
end

--- Insert a response in cycle-sorted order.
function TranscriptList:insert(cycle, response_text)
    local node = { cycle = cycle, text = response_text, next = nil }

    if not self.head or cycle < self.head.cycle then
        node.next = self.head
        self.head = node
    else
        local prev = self.head
        while prev.next and prev.next.cycle < cycle do
            prev = prev.next
        end
        node.next = prev.next
        prev.next = node
    end

    self.length = self.length + 1
end

--- Iterator returning cycle, text for each node.
function TranscriptList:iter()
    local current = self.head
    return function()
        if not current then return nil end
        local cycle, text = current.cycle, current.text
        current = current.next
        return cycle, text
    end
end

--- Write the list to a text file.
function TranscriptList:save(filepath, timestamp)
    local f = io.open(filepath, "w")
    if not f then
        print("[TranscriptList] Could not open for writing: " .. filepath)
        return false
    end

    f:write("Session: " .. timestamp .. "\n")

    for cycle, text in self:iter() do
        f:write("\n---\n\nResponse " .. cycle .. ": " .. text .. "\n")
    end

    f:close()
    return true
end

return TranscriptList
