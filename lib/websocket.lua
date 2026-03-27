-- lib/websocket.lua
-- Minimal pure-Lua WebSocket client (RFC 6455) built on luasocket + luasec.
-- Supports wss:// (TLS) and ws://, text and binary frames, ping/pong.

local socket = require("socket")
local ssl    = require("ssl")

local websocket = {}
websocket.__index = websocket

local OPCODE_CONT   = 0x0
local OPCODE_TEXT   = 0x1
local OPCODE_BINARY = 0x2
local OPCODE_CLOSE  = 0x8
local OPCODE_PING   = 0x9
local OPCODE_PONG   = 0xA

--- Parse a WebSocket URL into components.
local function parse_url(url)
    local scheme, host, port, path = url:match("^(wss?)://([^:/]+):?(%d*)(.*)")
    if not scheme then return nil, "invalid WebSocket URL" end
    local is_tls = (scheme == "wss")
    port = tonumber(port) or (is_tls and 443 or 80)
    if path == "" then path = "/" end
    return { scheme = scheme, host = host, port = port, path = path, is_tls = is_tls }
end

--- Generate a 16-byte random masking key.
local function random_key()
    local bytes = {}
    for i = 1, 16 do
        bytes[i] = string.char(math.random(0, 255))
    end
    return table.concat(bytes)
end

--- Generate a 4-byte random mask for data framing.
local function random_mask()
    local bytes = {}
    for i = 1, 4 do
        bytes[i] = string.char(math.random(0, 255))
    end
    return table.concat(bytes)
end

--- Base64 encode (for Sec-WebSocket-Key).
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64_encode(data)
    local result = {}
    local pad = (3 - #data % 3) % 3
    data = data .. string.rep("\0", pad)
    for i = 1, #data, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        local n = b1 * 65536 + b2 * 256 + b3
        result[#result + 1] = b64chars:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
        result[#result + 1] = b64chars:sub(n % 64 + 1, n % 64 + 1)
    end
    local encoded = table.concat(result)
    return encoded:sub(1, #encoded - pad) .. string.rep("=", pad)
end

--- Apply XOR mask to data.
local function apply_mask(data, mask)
    local out = {}
    for i = 1, #data do
        local j = ((i - 1) % 4) + 1
        out[i] = string.char(bit.bxor(data:byte(i), mask:byte(j)))
    end
    return table.concat(out)
end

--- Read exactly n bytes from socket.
local function read_bytes(sock, n, timeout)
    local data = ""
    local deadline = socket.gettime() + (timeout or 10)
    while #data < n do
        local remaining = deadline - socket.gettime()
        if remaining <= 0 then return nil, "timeout" end
        sock:settimeout(remaining)
        local chunk, err, partial = sock:receive(n - #data)
        if chunk then
            data = data .. chunk
        elseif partial and #partial > 0 then
            data = data .. partial
        elseif err == "timeout" then
            -- continue trying until deadline
        else
            return nil, err
        end
    end
    return data
end

--- Create a new WebSocket client.
-- @param url  WebSocket URL (ws:// or wss://)
-- @param opts Optional table: { headers = {}, timeout = seconds }
function websocket.new(url, opts)
    opts = opts or {}
    local parsed, err = parse_url(url)
    if not parsed then return nil, err end

    local self = setmetatable({}, websocket)
    self.url = url
    self.parsed = parsed
    self.headers = opts.headers or {}
    self.timeout = opts.timeout or 10
    self.sock = nil
    self.closed = false
    return self
end

--- Connect to the WebSocket server (performs TCP + TLS + HTTP upgrade handshake).
function websocket:connect()
    local p = self.parsed

    -- TCP connect
    local tcp = socket.tcp()
    tcp:settimeout(self.timeout)
    local ok, err = tcp:connect(p.host, p.port)
    if not ok then
        tcp:close()
        return nil, "TCP connect failed: " .. tostring(err)
    end

    -- TLS wrap if wss://
    if p.is_tls then
        local params = {
            mode = "client",
            protocol = "any",
            verify = "none",
            options = {"all"},
        }
        local wrapped, wrap_err = ssl.wrap(tcp, params)
        if not wrapped then
            tcp:close()
            return nil, "TLS wrap failed: " .. tostring(wrap_err)
        end
        wrapped:settimeout(self.timeout)
        local hs_ok, hs_err = wrapped:dohandshake()
        if not hs_ok then
            wrapped:close()
            return nil, "TLS handshake failed: " .. tostring(hs_err)
        end
        self.sock = wrapped
    else
        self.sock = tcp
    end

    -- WebSocket HTTP upgrade handshake
    local key = base64_encode(random_key())
    local host_header = p.host
    if (p.is_tls and p.port ~= 443) or (not p.is_tls and p.port ~= 80) then
        host_header = p.host .. ":" .. p.port
    end

    local req_lines = {
        "GET " .. p.path .. " HTTP/1.1",
        "Host: " .. host_header,
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Key: " .. key,
        "Sec-WebSocket-Version: 13",
    }
    for k, v in pairs(self.headers) do
        req_lines[#req_lines + 1] = k .. ": " .. v
    end
    req_lines[#req_lines + 1] = ""
    req_lines[#req_lines + 1] = ""

    local request = table.concat(req_lines, "\r\n")
    self.sock:settimeout(self.timeout)
    local _, send_err = self.sock:send(request)
    if send_err then
        self.sock:close()
        return nil, "handshake send failed: " .. tostring(send_err)
    end

    -- Read HTTP response (line by line until empty line)
    local status_line, recv_err = self.sock:receive("*l")
    if not status_line then
        self.sock:close()
        return nil, "handshake receive failed: " .. tostring(recv_err)
    end

    local status_code = tonumber(status_line:match("HTTP/1%.1 (%d+)"))
    if status_code ~= 101 then
        self.sock:close()
        return nil, "handshake failed with HTTP " .. tostring(status_code) .. ": " .. status_line
    end

    -- Consume remaining headers
    while true do
        local line = self.sock:receive("*l")
        if not line or line == "" then break end
    end

    self.closed = false
    return true
end

--- Send a WebSocket frame.
-- @param data    The payload string
-- @param opcode  "text" (default), "binary", "ping", "pong", "close", or numeric opcode
function websocket:send(data, opcode)
    if self.closed then return nil, "closed" end

    local op
    if opcode == "text" or opcode == nil then op = OPCODE_TEXT
    elseif opcode == "binary" then op = OPCODE_BINARY
    elseif opcode == "ping"   then op = OPCODE_PING
    elseif opcode == "pong"   then op = OPCODE_PONG
    elseif opcode == "close"  then op = OPCODE_CLOSE
    elseif type(opcode) == "number" then op = opcode
    else return nil, "unknown opcode: " .. tostring(opcode)
    end

    data = data or ""
    local len = #data
    local mask = random_mask()

    -- Build frame header
    local header = string.char(bit.bor(0x80, op))  -- FIN + opcode
    if len < 126 then
        header = header .. string.char(bit.bor(0x80, len))  -- MASK bit + length
    elseif len < 65536 then
        header = header .. string.char(bit.bor(0x80, 126))
        header = header .. string.char(math.floor(len / 256), len % 256)
    else
        header = header .. string.char(bit.bor(0x80, 127))
        -- 8-byte extended length (we only use lower 4 bytes for practical sizes)
        header = header .. "\0\0\0\0"
        header = header .. string.char(
            math.floor(len / 16777216) % 256,
            math.floor(len / 65536) % 256,
            math.floor(len / 256) % 256,
            len % 256
        )
    end

    local masked_data = apply_mask(data, mask)
    local frame = header .. mask .. masked_data

    self.sock:settimeout(self.timeout)
    local _, err = self.sock:send(frame)
    if err then return nil, err end
    return true
end

--- Receive a WebSocket frame.
-- @param timeout  Optional timeout in seconds (default: self.timeout)
-- @return data, opcode_name  or  nil, error_string
--   opcode_name is "text", "binary", "close", "ping", or "pong"
function websocket:receive(timeout)
    if self.closed then return nil, "closed" end
    timeout = timeout or self.timeout

    -- Read first 2 bytes of frame header
    local header, err = read_bytes(self.sock, 2, timeout)
    if not header then return nil, err end

    local b1, b2 = header:byte(1, 2)
    local opcode = bit.band(b1, 0x0F)
    local masked = bit.band(b2, 0x80) ~= 0
    local payload_len = bit.band(b2, 0x7F)

    -- Extended payload length
    if payload_len == 126 then
        local ext, ext_err = read_bytes(self.sock, 2, timeout)
        if not ext then return nil, ext_err end
        payload_len = ext:byte(1) * 256 + ext:byte(2)
    elseif payload_len == 127 then
        local ext, ext_err = read_bytes(self.sock, 8, timeout)
        if not ext then return nil, ext_err end
        payload_len = 0
        for i = 1, 8 do
            payload_len = payload_len * 256 + ext:byte(i)
        end
    end

    -- Masking key (server frames are typically unmasked)
    local mask_key
    if masked then
        mask_key, err = read_bytes(self.sock, 4, timeout)
        if not mask_key then return nil, err end
    end

    -- Payload
    local data = ""
    if payload_len > 0 then
        data, err = read_bytes(self.sock, payload_len, timeout)
        if not data then return nil, err end
        if masked then
            data = apply_mask(data, mask_key)
        end
    end

    -- Handle control frames
    if opcode == OPCODE_PING then
        self:send(data, "pong")
        return data, "ping"
    elseif opcode == OPCODE_CLOSE then
        if not self.closed then
            self.closed = true
            pcall(function() self:send(data, "close") end)
        end
        return data, "close"
    elseif opcode == OPCODE_PONG then
        return data, "pong"
    elseif opcode == OPCODE_TEXT then
        return data, "text"
    elseif opcode == OPCODE_BINARY then
        return data, "binary"
    else
        return data, "unknown"
    end
end

--- Close the WebSocket connection.
function websocket:close(code, reason)
    if self.closed then return end
    self.closed = true

    local payload = ""
    if code then
        payload = string.char(math.floor(code / 256), code % 256) .. (reason or "")
    end

    pcall(function() self:send(payload, "close") end)
    pcall(function() self.sock:close() end)
end

return websocket
