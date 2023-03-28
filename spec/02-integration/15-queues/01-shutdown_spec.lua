local helpers    = require "spec.helpers"


local HTTP_SERVER_PORT = helpers.get_available_port()


for _, strategy in helpers.each_strategy() do
  describe("queue graceful shutdown [#" .. strategy .. "]", function()
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
      })

      local service1 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route1 = bp.routes:insert {
        hosts   = { "shutdown.flush.test" },
        service = service1
      }

      bp.plugins:insert {
        route = { id = route1.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://127.0.0.1:" .. HTTP_SERVER_PORT,
          queue = {
            max_delay = 0.01,
          },
        }
      }

      local service2 = bp.services:insert{
        protocol = "http",
        host     = helpers.mock_upstream_host,
        port     = helpers.mock_upstream_port,
      }

      local route2 = bp.routes:insert {
        hosts   = { "shutdown.dns.test" },
        service = service2
      }

      bp.plugins:insert {
        route = { id = route2.id },
        name     = "http-log",
        config   = {
          http_endpoint = "http://konghq.com:80",
          queue = {
            batch_max_size = 10,
            max_delay = 10,
          },
        }
      }
    end)

    before_each(function()
      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
      helpers.stop_kong()
    end)

    it("queue is flushed before kong exits", function()

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "shutdown.flush.test"
        }
      }))
      assert.res_status(200, res)

      -- We request a graceful shutdown, then start the HTTP server to consume the queued log entries
      local pid_file, cleanup = helpers.stop_kong_gracefully()
      assert(pid_file)

      local thread = helpers.http_server(HTTP_SERVER_PORT, { timeout = 10 })
      local ok, _, body = thread:join()
      assert(ok)
      assert(body)

      helpers.wait_pid(pid_file)
      cleanup()

    end)

    it("DNS queries can be performed when shutting down", function()

      local res = assert(proxy_client:send({
        method = "GET",
        path = "/status/200",
        headers = {
          ["Host"] = "shutdown.dns.test"
        }
      }))
      assert.res_status(200, res)

      -- We request a graceful shutdown, which will flush the queue
      local pid_file, cleanup = helpers.stop_kong_gracefully()
      assert(pid_file)
      helpers.wait_pid(pid_file)

      assert.logfile().has.line("http-log sent data to upstream, konghq.com:80 HTTP status 301")

      cleanup()
    end)
  end)
end
