local utils = require("src.utils")
local json = require("dkjson")
local sqlite = require("lsqlite3")

-----------------
--- BOT SETUP --- 
-----------------

-- Global variables --
local ACTIVE_DIALOGUES = {}
local LOADED_USERS = {}
local TEMP_MESSAGES = {}

-- Config loading --
local CONFIG = nil
-- Trying to load configuration from json if failing creating new
if not utils.getJsonContent("config.json") then
    utils.createJsonFile("config.json",{
        bot_token = "YOUR_BOT_TOKEN"
    })
    utils.logMsg("Can't load configuration file, generating new, to start bot set bot token")
    os.exit()
else
    CONFIG = utils.getJsonContent("config.json")
    if not CONFIG then
        io.write("Failed while loading configuration :(\n")
        os.exit()
    else
        utils.logMsg("Successfully loaded configuration file")
    end
end

-- Getting token from user -- 
if CONFIG.bot_token == "YOUR_BOT_TOKEN" then
    io.write("Please enter telegram bot api token:\n")
    local token = io.read()
    utils.createJsonFile("config.json",{bot_token = token})
    os.exit()
end
local api = require("telegram-bot-lua").configure(CONFIG.bot_token)

-- Command list loading --
local COMMAND_LIST = require("commandList")

-- Database setup --
local db = sqlite.open("database/AFipedia.db")
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

-- In case of failing write error message --
if res == sqlite.ERROR then
    io.write("Error while setting up database, err: " .. db:errmsg())
    os.exit()
else
    utils.logMsg("Successfully set up database")
end


-- Functions --
local function helloName(user_id) -- Just testing func that I left here for fun
    utils.logMsg(user_id .. " | User called hellomsg")

    api.send_message(user_id,"Enter your name")

    local res = coroutine.yield().message.text

    api.send_message(user_id,"Hello, " .. res .. "!")
end

local function postVideo(user_id)
    utils.logMsg(user_id .. " | User posting video")

    if not user_id then return false,"Invalid arguments" end
    local index = tostring(user_id)

    local file_id = nil
    local video_title = nil
    while not file_id do -- Getting video from user if video with caption save it like video title --
        api.send_message(user_id,"Please send video to upload")
        local response = coroutine.yield()
        if response.message and response.message.video then
            file_id = response.message.video.file_id
            if response.message.caption and utf8.len(response.message.caption) <= 100 then
                video_title = response.message.caption
            end
        end
    end

    while not video_title do -- Getting video title from user --
        api.send_message(user_id,"Please send video title. Video title must be shorter than 100 symbols")
        local response = coroutine.yield()
        if response.message and response.message.text and utf8.len(response.message.text) <= 100 then
            video_title = response.message.text
        elseif response.message and response.message.text and utf8.len(response.message.text) > 100 then
            api.send_message(user_id,"Too long video title")
        end
    end

    -- Posting date --
    local posting_date = os.time()

    -- Inserting data about video into database --
    local insert = db:prepare("INSERT INTO videos (author_id,file_id,video_title,posting_date) VALUES (?,?,?,?)")
    insert:bind_values(user_id,file_id,video_title,posting_date)
    local res = insert:step()
    insert:finalize()

    -- Check if all done --
    if res == sqlite.DONE then
        api.send_message(user_id,"Video successfully loaded")
        utils.logMsg(user_id .. " | Successfully loaded video with title " .. video_title)
    else
        api.send_message(user_id,"Something went wrong:(")
        utils.logMsg(user_id .. " | Something went wrong while inserting data about video into database, " .. db:errmsg())
    end
end

local function newUserCreate(user) -- Function to save new users into database --
    local user_id = user.id
    local user_lang = user.language_code
    local username = user.first_name

    local insert = db:prepare("INSERT INTO users (user_id,username,language) VALUES (?,?,?)")
    if not insert then return nil end
    insert:bind_values(user_id,username,user_lang)
    local succ = insert:step()
    insert:finalize()
    if succ == sqlite.DONE then
        return true
    else
        return nil
    end
end

local function getUserVideos(user_id) -- Func to get table with user's videos --
    local videos = {}

    for video in db:nrows("SELECT * FROM videos WHERE author_id = " .. user_id) do
        table.insert(videos,video)
    end

    return videos
end

local function videosSelector(videos,selector_text) -- Func to get content of selector message -- 
    local selector = {}
    if not videos or type(videos) ~= "table" then return nil end
    if type(selector_text) ~= "string" then return nil end

    -- Separating videos for several pages --
    local pages = {}
    for i = 1,#videos,10 do
        local page = {}
        for j = i,i + 9 do
            table.insert(page,videos[j])
        end
        table.insert(pages,page)
    end

    -- Selector message content for every page --
    selector.page_text = {}
    for i,page in ipairs(pages) do
        selector.page_text[i] = "Select video:" .. "\n\n"
        for j,video in ipairs(pages[i]) do
            if j == 10 then
                selector.page_text[i] = selector.page_text[i] .. "[" .. j .. "]   " .. video.video_title .. "\n"
            else
                selector.page_text[i] = selector.page_text[i] .. "[ " .. j .. " ]   " .. video.video_title .. "\n"
            end
        end
    end

    -- Reply markups for every page --
    selector.kbs = {}
    for i,page in ipairs(pages) do
        local keys = {}
        for j = 1,10 do
            if page[j] then
                keys[j] = tostring(j)
            else
                keys[j] = ""
            end

            if pages[i - 1] then
                keys.previous = "<<<"
            else
                keys.previous = ""
            end

            if pages[i + 1] then
                keys.next = ">>>"
            else
                keys.next = ""
            end
        end
        
        local kb = api.inline_keyboard()
            :row(api.row()
                :callback_data_button(keys[1], "page" .. tostring(i) .. "video" .. 1)
                :callback_data_button(keys[2], "page" .. tostring(i) .. "video" .. 2)
                :callback_data_button(keys[3], "page" .. tostring(i) .. "video" .. 3)
                :callback_data_button(keys[4], "page" .. tostring(i) .. "video" .. 4)
                :callback_data_button(keys[5], "page" .. tostring(i) .. "video" .. 5)
            )
            :row(api.row()
                :callback_data_button(keys[6], "page" .. tostring(i) .. "video" .. 6)
                :callback_data_button(keys[7], "page" .. tostring(i) .. "video" .. 7)
                :callback_data_button(keys[8], "page" .. tostring(i) .. "video" .. 8)
                :callback_data_button(keys[9], "page" .. tostring(i) .. "video" .. 9)
                :callback_data_button(keys[10], "page" .. tostring(i) .. "video" .. 10)
            )
            :row(api.row()
                :callback_data_button(keys.previous,"previous_page")
                :callback_data_button(keys.next,"next_page")
            )

        table.insert(selector.kbs,kb)
    end

    return selector
end

local function checkUserVideos(user_id,videos_author) -- Func to check user's videos by username --
    local index = tostring(user_id)

    utils.logMsg(user_id .. " | User checking video by author name")
    -- Trying to get username from user if it isn't user with that name in db say about that --
    while not videos_author do
        api.send_message(user_id,"Please enter username")
        local select = db:prepare("SELECT user_id FROM users WHERE username = ?")
        local response = coroutine.yield()
        if response.message.text:sub(1,1) == "@" then
            response.message.text = response.message.text:sub(2,#response.message.text)
        end
        
        select:bind_values(response.message.text)
        local result = select:step()
        if result == sqlite.ROW then
            videos_author = select:get_values()[1]
            utils.logMsg(user_id .. " | Found user by name: " .. response.message.text .. " with user id: " .. videos_author)
        else
            api.send_message(user_id,"Can't found user with that username")
            utils.logMsg(user_id .. " | Failed when trying to found user")
        end
    end

    -- Getting user's videos and sending selector message --
    local videos = getUserVideos(videos_author)
    local selector = videosSelector(videos,"Please select video")
    if not selector then return nil end
    local msg_id = api.send_message(user_id,selector.page_text[1],{reply_markup=selector.kbs[1]}).result.message_id
    TEMP_MESSAGES[index] = msg_id

    local current_page = 1
    local media_message_id = nil
    while true do
        local callback_query = coroutine.yield().callback_query
        if not callback_query then goto continue end
        local data = callback_query.data
        if data == "previous_page" then
            api.answer_callback_query(callback_query.id, {text = "<<<"})
            if current_page - 1 >= 1 then
                current_page = current_page - 1
            end
        elseif data == "next_page" then
            api.answer_callback_query(callback_query.id, {text = ">>>"})
            if current_page + 1 <= 10 then
                current_page = current_page + 1
            end
        elseif data:sub(1,4) == "page" then
            local video_num = data:sub(5,5) * 10 + data:sub(11,12) - 10
            local video = videos[video_num]
            if not media_message_id then
                media_message_id = api.send_video(user_id,video.file_id,{caption = video.video_title}).result.message_id
                api.answer_callback_query(callback_query.id, {text = video.video_title})
            else
                api.edit_message_media(user_id,media_message_id,{type = "video",media = video.file_id,caption = video.video_title})
                api.answer_callback_query(callback_query.id, {text = video.video_title})
            end
        end

        api.edit_message_text(user_id,msg_id,selector.page_text[current_page],{reply_markup = selector.kbs[current_page]})
        ::continue::
    end                                             
end

function api.is_command(message) -- Simplification version of telegram-bot-lua lib function --
    if not message or not message.text then return false end
    if message.text:sub(1,1) == "/" then
        return true
    else
        return false
    end
end

local function deletePost(user_id) -- Func to delete loaded video --
    utils.logMsg(user_id .. " | User removing video")
    
    local videos = getUserVideos(user_id)
    local selector = videosSelector(videos,"Please select video to delete")
    if not selector then return nil end
    local msg_id = api.send_message(user_id,selector.page_text[1],{reply_markup=selector.kbs[1]}).result.message_id
    local current_page = 1
    while true do
        local callback_query = coroutine.yield().callback_query
        if not callback_query then goto continue end
        local data = callback_query.data
        if data == "previous_page" then
            api.answer_callback_query(callback_query.id, {text = "<<<"})
            if current_page - 1 >= 1 then
                current_page = current_page - 1
            end
        elseif data == "next_page" then
            api.answer_callback_query(callback_query.id, {text = ">>>"})
            if current_page + 1 <= 10 then
                current_page = current_page + 1
            end
        elseif data:sub(1,4) == "page" then
            local video_num = data:sub(5,5) * 10 + data:sub(11,12) - 10
            db:execute("DELETE FROM videos WHERE video_id = " .. videos[video_num].video_id)
            utils.logMsg(user_id .. " | User removed video with id " .. videos[video_num].video_id)
            api.answer_callback_query(callback_query.id, {text = videos[video_num].video_title .. " removed"})
            api.edit_message_text(user_id,msg_id,"Video successfully deleted")
            return
        end
        ::continue::
    end  
end

local function help(user_id)
    utils.logMsg(user_id .. " | Called helping message")
    local helping_msg = "Bot provides abillity to share funny videos with other users\n\n"
    for i,group in pairs(COMMAND_LIST) do
        local len = nil
        for command,description in pairs(group) do
            helping_msg = helping_msg .. "/" .. command .. " ~=> " .. description .. "\n"
        end
        helping_msg = helping_msg .. "\n"
    end
    api.send_message(user_id,helping_msg)
end

local function showRandomVids(user_id)
    -- Here we're sending random video to user if '🛑' haven't pressed do it again --
    utils.logMsg(user_id .. " |  The user has started watching the videos")
    for row in db:nrows("SELECT video_title,file_id,author_id FROM videos ORDER BY RANDOM()") do
        local kb = api.keyboard(true, true)
            :row({'🆕'})
            :row({'🛑'})
        local author_name = "unknown"
        for author in db:nrows("SELECT username FROM users WHERE user_id = " .. row.author_id .. " LIMIT 1") do
            author_name = author.username
        end
        api.send_video(user_id,row.file_id,{caption = row.video_title .. "\n\nLoaded by: " .. api.fmt.mention(row.author_id,author_name),
            reply_markup = kb,
            parse_mode = "html"})
        local res = coroutine.yield()
        if res.message.text ~= "🆕" then
            break
        end
    end
    api.send_message(user_id,"You have been watched all loaded videos")
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

    -- Command handling --
    if api.is_command(update.message) then
        local cmd = string.lower(update.message.text)
        local co = nil
        if TEMP_MESSAGES[index] then
            api.delete_message(user_id,TEMP_MESSAGES[index])
            TEMP_MESSAGES[index] = nil
        end

        if cmd == "/start" then
            if not LOADED_USERS[index] and message then
                local check = db:prepare("SELECT 1 FROM users WHERE user_id = ? LIMIT 1")
                check:bind_values(user_id)
                local res = check:step()

                if res == sqlite.DONE then
                    local succ = newUserCreate(message.from)
                    if succ then
                        utils.logMsg(user_id .. " | New user")
                    else
                        utils.logMsg(user_id .. " | Failed when trying to add new user to db")
                        print(db:errmsg())
                    end
                end
            end
        elseif cmd == "/back" then
            ACTIVE_DIALOGUES[index] = nil
        elseif cmd == "/hello" then
            co = coroutine.create(helloName)
            coroutine.resume(co,update.message.from.id)
        elseif cmd == "/post" then
            co = coroutine.create(postVideo)
            coroutine.resume(co,update.message.from.id)
        elseif cmd == "/myvids" then
            co = coroutine.create(checkUserVideos)
            coroutine.resume(co,update.message.from.id,update.message.from.id)
        elseif cmd == "/uservids" then
            co = coroutine.create(checkUserVideos)
            coroutine.resume(co,user_id)
        elseif cmd == "/deletepost" then
            co = coroutine.create(deletePost)
            coroutine.resume(co,user_id)
        elseif cmd == "/help" then
            help(user_id)
        elseif cmd == "/scroll" then
            co = coroutine.create(showRandomVids)
            coroutine.resume(co,user_id)
        end
        
        if co then
            ACTIVE_DIALOGUES[index] = co
            utils.logMsg(user_id .. " | Coroutine started and added to active dialogues")
        end
    elseif ACTIVE_DIALOGUES[index] then
        local co = ACTIVE_DIALOGUES[index]
        local succ,err = coroutine.resume(co,update)

        if not succ then
            print(user_id .. " | Error while resuming coroutine: " .. err)
        end

        if coroutine.status(co) == "dead" then
            ACTIVE_DIALOGUES[index] = nil
            api.delete_message(user_id,TEMP_MESSAGES[index])
            TEMP_MESSAGES[index] = nil
            utils.logMsg(user_id .. " | Coroutine finished and removed from active dialogues")
        end
    else
        api.send_message(user_id,"Unknown command")
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