local utils = require("utils")
local json = require("dkjson")
local sqlite = require("lsqlite3")

-----------------
--- BOT SETUP --- 
-----------------

-- Config loading --
local ACTIVE_DIALOGUES = {}

local CONFIG = nil
if not utils.getJsonContent("../config.json") then
    utils.createJsonFile("../config.json",{
        bot_token = ""
    })
    io.write("Can't load configuration file, generating new, to start bot set bot token\n")
    os.exit()
else
    CONFIG = utils.getJsonContent("../config.json")
    if not CONFIG then
        io.write("Failed while loading configuration :(\n")
        os.exit()
    end
end

local api = require("telegram-bot-lua").configure(CONFIG.bot_token)

-- Database setup --
local db = sqlite.open("../database/AFipedia.db")
db:exec([[
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS users (
        user_id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        language TEXT NOT NULL,
        last_activity_time INTEGER NOT NULL,
    )
]])

-- Functions --
local function helloName(user_id)
    api.send_message(user_id,"Enter your name")

    local res = coroutine.yield().message.text

    api.send_message(user_id,"Hello, " .. res .. "!")
end


-------------------
--- BOT RUNTIME ---
-------------------

-- Bot handling function --
function api.on_update(update)
    local user_id = nil

    local message = nil
    local callback_query = nil
    if update.message then
        message = update.message
        user_id = message.from.id
    elseif update.callback_query then
        callback_query = update.callback_query
        user_id = callback_query.from.id
    end

    local index = tostring(user_id)

    if ACTIVE_DIALOGUES[index] and not api.is_command(update.message) then
        local co = ACTIVE_DIALOGUES[index]
        coroutine.resume(co,update)
        if coroutine.status(co) == "dead" then
            ACTIVE_DIALOGUES[index] = nil
            io.write(user_id .. " | Coroutine finished and removed from active dialogues\n")
        end
    end

    -- Command handling --
    if message and api.is_command(update.message) then
        local cmd = string.lower(message.text)
        local co = nil
        if cmd == "/hello" then
            co = coroutine.create(helloName)
            coroutine.resume(co,update.message.from.id)
        end
        
        if co then
            ACTIVE_DIALOGUES[index] = co
            io.write(user_id .. " | Coroutine started and added to active dialogues\n")
        end
    end
end


-- Polling --
local opts = {}
local limit = tonumber(opts.limit) or 1
local timeout = tonumber(opts.timeout) or 0
local offset = tonumber(opts.offset) or 0
local allowed_updates = opts.allowed_updates
local use_beta_endpoint = opts.use_beta_endpoint
while true do
    local updates = api.get_updates({
        timeout = timeout,
        offset = offset,
        limit = limit,
        allowed_updates = allowed_updates,
        use_beta_endpoint = use_beta_endpoint
    })
    if updates and type(updates) == 'table' and updates.result then
        for _, v in pairs(updates.result) do
            api.process_update(v)
            offset = v.update_id + 1
        end
    end
end