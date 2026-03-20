local utils = require("utils")
local json = require("dkjson")
local sqlite = require("lsqlite3")

-----------------
--- BOT SETUP --- 
-----------------

-- Config loading --
local ACTIVE_DIALOGUES = {}
local LOADED_USERS = {}

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
    else
        io.write("Successfully loaded configuration file\n")
    end
end

local api = require("telegram-bot-lua").configure(CONFIG.bot_token)

-- Database setup --
local db = sqlite.open("../database/AFipedia.db")
local res = db:exec([[
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    
    CREATE TABLE IF NOT EXISTS users (
        user_id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        language TEXT NOT NULL
    );
    
    CREATE TABLE IF NOT EXISTS videos (
        video_id INTEGER PRIMARY KEY,
        author_id INTEGER NOT NULL,
        file_id INTEGER NOT NULL,
        video_title TEXT NOT NULL,
        posting_date INTEGER NOT NULL,

        FOREIGN KEY(author_id) REFERENCES users(user_id)
    )
]])

if res == sqlite.ERROR then
    io.write("Error while setting up database, err: " .. db:errmsg())
    os.exit()
else
    io.write("Successfully set up database\n")
end


-- Functions --
local function helloName(user_id)
    api.send_message(user_id,"Enter your name")

    local res = coroutine.yield().message.text

    api.send_message(user_id,"Hello, " .. res .. "!")
end

local function postVideo(user_id)
    if not user_id then return false,"Invalid arguments" end
    local index = tostring(user_id)

    local file_id = nil
    local video_title = nil
    while not file_id do
        api.send_message(user_id,"Please send video to upload")
        local response = coroutine.yield()
        if response.message and response.message.video then
            file_id = response.message.video.file_id
            print(utf8.len(response.message.caption))
            if response.message.caption and utf8.len(response.message.caption) <= 100 then
                video_title = response.message.caption
            end
        end
    end

    while not video_title do
        api.send_message(user_id,"Please send video title. Video title must be shorter than 100 symbols")
        local response = coroutine.yield()
        if response.message and response.message.text and utf8.len(response.message.text) <= 100 then
            video_title = response.message.text
        elseif response.message and response.message.text and utf8.len(response.message.text) > 100 then
            api.send_message(user_id,"Too long video title")
        end
    end

    local posting_date = os.time()

    local insert = db:prepare("INSERT INTO videos (author_id,file_id,video_title,posting_date) VALUES (?,?,?,?)")
    insert:bind_values(user_id,file_id,video_title,posting_date)
    local res = insert:step()
    if res == sqlite.DONE then
        api.send_message(user_id,"Video successfully loaded")
        io.write(user_id .. " | Successfully loaded video with title " .. video_title .. "\n")
    end
end

local function newUserCreate(user)
    local user_id = user.id
    local user_lang = user.language_code
    local username = nil
    if user.username then
        username = user.username
    else
        username = user.first_name
    end

    local insert = db:prepare("INSERT INTO users (user_id,username,language) VALUES (?,?,?)")
    if not insert then io.write(user_id .. " | Error while inserting into table " .. db:errmsg() .. "\n") end
    insert:bind_values(user_id,username,user_lang)
    local succ = insert:step()
    if succ == sqlite.DONE then
        return true
    else
        return nil
    end
    insert:finalize()
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

    -- Check if user exists in database ---
    if not LOADED_USERS[index] and message then
        local check = db:prepare("SELECT 1 FROM users WHERE user_id = ? LIMIT 1")
        check:bind_values(user_id)
        local res = check:step()

        if res == sqlite.DONE then
            local succ = newUserCreate(message.from)
            if succ then
                io.write(user_id .. " | New user!\n")
            else
                io.write(user_id .. " | Failed when trying to add new user to db\n")
            end
        end
    end

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
        elseif cmd == "/post" then
            co = coroutine.create(postVideo)
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