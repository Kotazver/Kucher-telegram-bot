utils = {}

local json = require("dkjson")

utils.getJsonContent = function (path)
    local content = nil
    local file = io.open(path,"r")

    if file then
        local json_string = file:read("a")
        content = json.decode(json_string)
        return content
    end
end