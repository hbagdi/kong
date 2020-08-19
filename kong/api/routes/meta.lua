local utils = require "kong.tools.utils"
local singletons = require "kong.singletons"
local conf_loader = require "kong.conf_loader"
local cjson = require "cjson"

local sub = string.sub
local kong = kong
local knode  = (kong and kong.node) and kong.node or
               require "kong.pdk.node".new()


local tagline = "Welcome to " .. _KONG._NAME
local version = _KONG._VERSION
local lua_version = jit and jit.version or _VERSION


return {
  ["/"] = {
    GET = function(self, dao, helpers)
      local distinct_plugins = setmetatable({}, cjson.array_mt)
      local prng_seeds = {}

      do
        local set = {}
        for row, err in kong.db.plugins:each() do
          if err then
            kong.log.err(err)
            return kong.response.exit(500, { message = "An unexpected error happened" })
          end

          if not set[row.name] then
            distinct_plugins[#distinct_plugins+1] = row.name
            set[row.name] = true
          end
        end
      end

      do
        local kong_shm = ngx.shared.kong
        local shm_prefix = "pid: "
        local keys, err = kong_shm:get_keys()
        if not keys then
          ngx.log(ngx.ERR, "could not get kong shm keys: ", err)
        else
          for i = 1, #keys do
            if sub(keys[i], 1, #shm_prefix) == shm_prefix then
              prng_seeds[keys[i]], err = kong_shm:get(keys[i])
              if err then
                ngx.log(ngx.ERR, "could not get PRNG seed from kong shm")
              end
            end
          end
        end
      end

      local node_id, err = knode.get_id()
      if node_id == nil then
        ngx.log(ngx.ERR, "could not get node id: ", err)
      end

      return kong.response.exit(200, {
        tagline = tagline,
        version = version,
        hostname = utils.get_hostname(),
        node_id = node_id,
        timers = {
          running = ngx.timer.running_count(),
          pending = ngx.timer.pending_count()
        },
        plugins = {
          available_on_server = singletons.configuration.loaded_plugins,
          enabled_in_cluster = distinct_plugins
        },
        lua_version = lua_version,
        configuration = conf_loader.remove_sensitive(singletons.configuration),
        prng_seeds = prng_seeds,
      })
    end
  },
  ["/endpoints"] = {
    GET = function(self, dao, helpers)
      local endpoints = setmetatable({}, cjson.array_mt)
      local lapis_endpoints = require("kong.api").ordered_routes

      for k, v in pairs(lapis_endpoints) do
        if type(k) == "string" then -- skip numeric indices
          endpoints[#endpoints + 1] = k:gsub(":([^/:]+)", function(m)
              return "{" .. m .. "}"
            end)
        end
      end
      table.sort(endpoints, function(a, b)
        -- when sorting use lower-ascii char for "/" to enable segment based
        -- sorting, so not this:
        --   /a
        --   /ab
        --   /ab/a
        --   /a/z
        -- But this:
        --   /a
        --   /a/z
        --   /ab
        --   /ab/a
        return a:gsub("/", "\x00") < b:gsub("/", "\x00")
      end)

      return kong.response.exit(200, { data = endpoints })
    end
  },
}
