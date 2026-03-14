local utils = require("utils")
local json = require("dkjson")
local sqlite = require("lsqlite3")

-- Config loading --
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


-- Bot setup and handling function --
local api = require("telegram-bot-lua").configure(CONFIG.bot_token)