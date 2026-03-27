UTILS = {}

local json = require("dkjson")

UTILS.getJsonContent = function (path)
    local content = nil
    local file = io.open(path,"r")

    if file then
        local json_string = file:read("a")
        content = json.decode(json_string)
        file:close()
        return content
    else
        return false, "can't open file " .. path
    end
end

UTILS.createJsonFile = function (path,table)
    if not table or not path then return false, "invalid arguments" end

    local file = io.open(path,"w+")
    if file then
        file:write(json.encode(table,{indent = true}))
        file:close()
        return true
    else
        return false,"can't write file " .. path
    end
end

UTILS.logMsg = function (text)
    if not text or type(text) ~= "string" then
        return nil
    else
        io.write(text .. "\n")
        io.flush()
    end
end

return UTILS