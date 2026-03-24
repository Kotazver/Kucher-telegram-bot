FROM ubuntu:latest

# Pupuntu kulyochki
RUN apt-get update && apt-get install -y \
    lua5.4 \
    liblua5.4-dev \
    luarocks \
    git \
    libssl-dev \
    build-essential \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home/ubuntu/maindir

# Copying files from repo
COPY . .

# Luarocks libs
RUN luarocks install --lua-version 5.4 dkjson \
    && luarocks install --lua-version 5.4 copas \
    && luarocks install --lua-version 5.4 telegram-bot-lua \
    && luarocks install --lua-version 5.4 lsqlite3

# Path libs to make libs to work on poopuntu
ENV LUA_PATH="/usr/local/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua;./?.lua;./src/?.lua;;"
ENV LUA_CPATH="/usr/local/lib/lua/5.4/?.so;/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;./?.so;;"

# Running bot
CMD ["lua5.4", "src/main.lua"]