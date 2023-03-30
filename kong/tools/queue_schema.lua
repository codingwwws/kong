local Schema = require "kong.db.schema"

-- TODO: enable the descriptions once they are accepted in Schemas
return Schema.define {
  type = "record",
  fields = {
    { name = {
      type = "string",
      -- description = "name of the queue, unique across one workspace.",
      -- If two plugin instances use the same queue name, they will
      -- share one queue and their queue related configuration must match.
    } },
    { batch_max_size = {
      type = "number",
      default = 1,
      -- description = "maximum number of entries to be that can be processed at a time"
    } },
    { max_delay = {
      type = "number",
      default = 1,
      -- description = "maximum number of (fractional) seconds to elapse after the first entry was queued before the queue starts calling the handler",
      -- This parameter has no effect if `batch_max_size` is 1, as queued entries will be sent
      -- immediately in that case.
    } },
    { max_entries = {
      type = "number",
      default = 10000,
      -- description = "maximum number of entries that can be waiting on the queue",
    } },
    { max_bytes = {
      type = "number",
      default = nil,
      -- description = "maximum number of bytes that can be waiting on a queue, requires string content",
    } },
    { max_retry_time = {
      type = "number",
      default = 60,
      -- description = "time in seconds before the queue gives up calling a failed handler for a batch",
    } },
    { max_retry_delay = {
      type = "number",
      default = 60,
      -- description = "maximum time in seconds between retries, caps exponential backoff"
    } },
  }
}