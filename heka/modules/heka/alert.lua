-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Heka Alert Module

## Sample Configuration
```lua
alert = {
    disabled = false, -- optional
    prefix   = false, -- optional prefix plugin information to the summary and detail strings
    throttle = 60,    -- optional number of minutes before another alert with this ID will be sent
    modules  = {
      -- module_name = {}, -- see the heka.alert.modules_name documentation for the configuration options
      -- e.g., email = {recipients = {"foo@example.com"}},
    }
}

```

## Functions

### send

Send an alert message

*Arguments*
- id (string) - unique id for alert throttling
- summary (string) - alert summary
- detail (string) - alert detail

*Return*
- sent (boolean) - true if sent, false if throttled/disabled/empty
--]]

-- Imports
local string = require "string"
local time   = require "os".time

local error     = error
local ipairs    = ipairs
local pairs     = pairs
local pcall     = pcall
local require   = require

local logger    = read_config("Logger")
local hostname  = read_config("Hostname")
local pid       = read_config("Pid")

local inject_message = inject_message

local alert_cfg = read_config("alert")
assert(type(alert_cfg) == "table", "alert configuration must be a table")
assert(type(alert_cfg.modules) == "table", "alert.modules configuration must be a table")

alert_cfg.throttle = alert_cfg.throttle or 60
assert(type(alert_cfg.throttle) == "number" and alert_cfg.throttle > 0, "alert.throttle configuration must be a number > 0 ")
alert_cfg.throttle = alert_cfg.throttle * 60

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {
    Type = "alert",
    Payload = "",
    Severity = 1,
    Fields = {
        {name = "id"        , value = ""},
        {name = "summary"   , value = ""},
    }
}

-- load alert specific configuration settings into the message
if not alert_cfg.disabled then
    local empty = true
    for k,v in pairs(alert_cfg.modules) do
        local ok, mod = pcall(require, "heka.alert." .. k)
        if ok then
            for i,v in ipairs(mod) do
                msg.Fields[#msg.Fields + 1] = v;
            end
        else
            error(mod)
        end
        empty = false
    end
    if empty then error("No alert modules were specified") end
end

local alert_times = {}

local function throttled(id)
    local time_t = time()
    local at = alert_times[id]
    if not at or time_t - at > alert_cfg.throttle then
        alert_times[id] = time_t
        return false
    end
    return true
end

function send(id, summary, detail)
    if alert_cfg.disabled or not summary or summary == "" or throttled(id) then
        return false
    end

    msg.Fields[1].value = id
    if alert_cfg.prefix then
        msg.Fields[2].value = string.format("Hindsight [%s#%s] - %s", logger, id, summary)
        msg.Payload         = string.format("Hostname: %s\nPid: %d\n\n%s\n", hostname, pid, detail)
    else
        msg.Fields[2].value = summary
        msg.Payload         = detail
    end

    inject_message(msg)
    return true
end

return M
