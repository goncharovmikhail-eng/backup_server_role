#!/bin/bash

if [ -z "${1:-}" ]; then
    echo "ERROR: archive name not provided"
    exit 1
fi

ARCHIVE_NAME="$1"
REMOTE_TMP="/tmp/${ARCHIVE_NAME%.tar.gz}"
REMOTE_ARCHIVE="/tmp/$ARCHIVE_NAME"

# --- Список директорий для архивации ---
#CONFIG_DIRS=(/opt/express /opt/express-voice /var/lib/docker/volumes /opt/express-my /opt/express_etlon /var/log/audit /opt/docker-registry /etc/systemd /opt/kafka /etcd-data /etc/redis /etc/etcd /opt/zookeeper /opt/ex_data/etcd /var/log /etc/patroni /etc/postgresql/15/main)
CONFIG_DIRS=(
    /opt/express
    /opt/express-voice
    # /var/log/audit
    # /opt/docker-registry

    # # Systemd unit files
    # /etc/systemd

    # # Kafka и Zookeeper
    # /opt/kafka
    # /opt/zookeeper

    # # etcd
    # /var/lib/etcd
    # /opt/ex_data/etcd/data
    # /etc/etcd
    # /etcd-data

    # # Redis
    # /var/lib/redis
    # /var/log/redis
    # /etc/redis

    # # Patroni и PostgreSQL
    # /etc/patroni
    # /etc/postgresql/15/main

    # # Общие логи
    # /var/log

    # # Бинарники
    # /usr/local/bin/etcd
    # /usr/local/bin/etcdctl
    # /usr/local/bin/redis-server
    # /usr/local/bin/redis-cli
    # /usr/local/bin/redis-benchmark
    # /usr/local/bin/redis-check-aof
    # /usr/local/bin/redis-check-rdb
    # /usr/local/bin/redis-sentinel
)

# --- Проверка места на диске перед созданием архива ---
RED='\033[0;31m'
NC='\033[0m' # сброс цвета

# список существующих директорий
EXISTING_DIRS=()
for DIR in "${CONFIG_DIRS[@]}"; do
    [ -d "$DIR" ] && EXISTING_DIRS+=("$DIR")
done

# считаем суммарный размер существующих директорий
TOTAL_SIZE=0
for DIR in "${EXISTING_DIRS[@]}"; do
    SIZE=$(du -sb "$DIR" 2>/dev/null | awk '{print $1}')
    TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
done

# порог: умножаем на 2 для временных файлов и логов контейнеров
REQUIRED=$((TOTAL_SIZE * 2))

# свободное место на корне (/tmp входит в корень)
FREE=$(df --output=avail / | tail -1)
FREE_BYTES=$((FREE * 1024))

# переводим в гигабайты для отображения
REQUIRED_GB=$((REQUIRED / 1024 / 1024 / 1024))
FREE_GB=$((FREE_BYTES / 1024 / 1024 / 1024))

# предупреждение, но скрипт продолжает работу
if [ "$FREE_BYTES" -lt "$REQUIRED" ]; then
    echo -e "${RED}WARNING: На сервере мало места!${NC}"
    echo -e "${RED}минимально необходимо: ${REQUIRED_GB} ГБ${NC}"
    echo -e "${RED}Свободно: ${FREE_GB} ГБ${NC}"
    echo -e "${RED}Рекомендуется${NC} добавить ${RED}ещё 10 ГБ${NC} к минимумальному значению"
    echo -e "__NO_SPACE__"
    exit 2
fi

# --- Создаём временную директорию ---
mkdir -p "$REMOTE_TMP"

echo "=== CTS Log Collector (remote) started ==="
echo "Temporary remote dir: $REMOTE_TMP"
echo

# --- 1. Docker logs ---
echo "[1/3] Collecting Docker logs..."
docker ps --format "{{.ID}} {{.Names}}" | while read -r ID NAME; do
    LOGFILE="$REMOTE_TMP/${NAME}_${ID}.log"
    echo " → $NAME ($ID)"
    docker logs "$ID" &> "$LOGFILE"
done
echo

# --- 2. Configs ---
echo "[2/3] Collecting configs..."
for DIR in "${CONFIG_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        echo " → Copying $DIR"
        cp -a "$DIR" "$REMOTE_TMP" 2>/dev/null || echo " ! Не удалось скопировать $DIR"
    fi
done
echo

# --- 3. Archive ---
echo "[3/3] Creating archive..."
if ! tar -czf "$REMOTE_ARCHIVE" -C /tmp "$(basename "$REMOTE_TMP")"; then
    echo -e "${RED}ERROR: Не удалось создать архив! Возможно, не хватает места.${NC}"
    echo "Архив может быть неполным, продолжаем работу..."
fi

echo "Remote archive created: $REMOTE_ARCHIVE"