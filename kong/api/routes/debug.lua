local set_log_level = require("resty.kong.log").set_log_level
local cjson = require("cjson.safe")

local LOG_LEVELS = require("kong.constants").LOG_LEVELS

local ngx = ngx
local kong = kong
local pcall = pcall
local type = type
local tostring = tostring

local get_log_level = require("resty.kong.log").get_log_level

local NODE_LEVEL_BROADCAST = false
local CLUSTER_LEVEL_BROADCAST = true
local DEFAULT_LOG_LEVEL_TIMEOUT = 60 * 10 -- 10 minutes

local function handle_put_log_level(self, broadcast)
  if kong.configuration.database == "off" then
    local message = "cannot change log level when not using a database"
    return kong.response.exit(405, { message = message })
  end

  local log_level = LOG_LEVELS[self.params.log_level]
  local timeout = tonumber(self.params.timeout) or DEFAULT_LOG_LEVEL_TIMEOUT

  if type(log_level) ~= "number" then
    return kong.response.exit(400, { message = "unknown log level: " .. self.params.log_level })
  end

  local cur_log_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])

  if cur_log_level == log_level then
    local message = "log level is already " .. self.params.log_level
    return kong.response.exit(200, { message = message })
  end

  local ok, err = pcall(set_log_level, log_level, 30)

  if not ok then
    local message = "failed setting log level: " .. err
    return kong.response.exit(500, { message = message })
  end

  -- broadcast to all workers in a node
  ok, err = kong.worker_events.post("debug", "log_level", {
    log_level = log_level,
    timeout = timeout,
  })

  if not ok then
    local message = "failed broadcasting to workers: " .. err
    return kong.response.exit(500, { message = message })
  end

  if broadcast then
    -- broadcast to all nodes in a cluster
    ok, err = kong.cluster_events:broadcast("log_level", cjson.encode({
      log_level = log_level,
      timeout = timeout,
    }))

    if not ok then
      local message = "failed broadcasting to cluster: " .. err
      return kong.response.exit(500, { message = message })
    end
  end

  -- store in shm so that newly spawned workers can update their log levels
  ok, err = ngx.shared.kong:set("kong:log_level", log_level)

  if not ok then
    local message = "failed storing log level in shm: " .. err
    return kong.response.exit(500, { message = message })
  end

  return kong.response.exit(200, { message = "log level changed" })
end

local routes = {
  ["/debug/node/log-level"] = {
    GET = function(self)
      local cur_level = get_log_level(LOG_LEVELS[kong.configuration.log_level])

      if type(LOG_LEVELS[cur_level]) ~= "string" then
        local message = "unknown log level: " .. tostring(LOG_LEVELS[cur_level])
        return kong.response.exit(500, { message = message })
      end

      return kong.response.exit(200, { message = "log level: " .. LOG_LEVELS[cur_level] })
    end,
  },
  ["/debug/node/log-level/:log_level"] = {
    PUT = function(self)
      return handle_put_log_level(self, NODE_LEVEL_BROADCAST)
    end
  },
}

local cluster_name

if kong.configuration.role == "control_plane" then
  cluster_name = "/debug/cluster/control-planes-nodes/log-level/:log_level"
else
  cluster_name = "/debug/cluster/log-level/:log_level"
end

routes[cluster_name] = {
  PUT = function(self)
    return handle_put_log_level(self, CLUSTER_LEVEL_BROADCAST)
  end
}

return routes
