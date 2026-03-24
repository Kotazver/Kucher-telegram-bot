FROM ubuntu:latest

# 1. Устанавливаем ВСЕ зависимости сразу
# Обязательно liblua5.4-dev и build-essential
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

# 2. Копируем файлы
COPY . .

# 3. Ставим либы ПРАВИЛЬНО. 
# В Ubuntu для 5.4 luarocks должен использовать дерево /usr/local
RUN luarocks install --lua-version 5.4 dkjson \
    && luarocks install --lua-version 5.4 copas \
    && luarocks install --lua-version 5.4 telegram-bot-lua \
    && luarocks install --lua-version 5.4 lsqlite3

# 4. Прописываем пути, где Ubuntu реально хранит пакеты 5.4
ENV LUA_PATH="/usr/local/share/lua/5.4/?.lua;/usr/local/share/lua/5.4/?/init.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua;./?.lua;./src/?.lua;;"
ENV LUA_CPATH="/usr/local/lib/lua/5.4/?.so;/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;./?.so;;"

# 5. Проверка (если упадет здесь, сборка не закончится — это сэкономит время)
RUN lua5.4 -e "require('dkjson'); print('SUCCESS: dkjson loaded')"

# Запуск
CMD ["lua5.4", "src/main.lua"]