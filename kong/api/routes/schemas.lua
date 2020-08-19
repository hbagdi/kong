local api_helpers = require "kong.api.api_helpers"
local Schema = require "kong.db.schema"
local Errors = require "kong.db.errors"
local kong = kong
local errors = Errors.new()


local strip_foreign_schemas = function(fields)
  for _, field in ipairs(fields) do
    local fname = next(field)
    local fdata = field[fname]
    if fdata["type"] == "foreign" then
      fdata.schema = nil
    end
  end
end


return {
  ["/schemas/:name"] = {
    GET = function(self, db, helpers)
      local entity = kong.db[self.params.name]
      local schema = entity and entity.schema or nil
      if not schema then
        return kong.response.exit(404, { message = "No entity named '"
                                      .. self.params.name .. "'" })
      end
      local copy = api_helpers.schema_to_jsonable(schema)
      strip_foreign_schemas(copy.fields)
      return kong.response.exit(200, copy)
    end
  },
  ["/schemas/:db_entity_name/validate"] = {
    POST = function(self, db, helpers)
      local db_entity_name = self.params.db_entity_name
      -- What happens when db_entity_name is a field name in the schema?
      self.params.db_entity_name = nil
      local entity = kong.db[db_entity_name]
      local schema = entity and entity.schema or nil
      if not schema then
        return kong.response.exit(404, { message = "No entity named '"
                                  .. db_entity_name .. "'" })
      end
      local schema = assert(Schema.new(schema))
      local _, err_t = schema:validate(schema:process_auto_fields(
                                        self.params, "insert"))
      if err_t then
        return kong.response.exit(400, errors:schema_violation(err_t))
      end
      return kong.response.exit(200, { message = "schema validation successful" })
    end
  },
  ["/schemas/plugins/:name"] = {
    GET = function(self, db, helpers)
      local subschema = kong.db.plugins.schema.subschemas[self.params.name]
      if not subschema then
        return kong.response.exit(404, { message = "No plugin named '"
                                  .. self.params.name .. "'" })
      end

      local copy = api_helpers.schema_to_jsonable(subschema)
      strip_foreign_schemas(copy.fields)
      return kong.response.exit(200, copy)
    end
  },
}
