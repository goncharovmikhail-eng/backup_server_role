#!/bin/bash
# Usage: ./restore_psql_basebackup.sh <hostname> <backup_file.tar.gz>
# будет бэкапится по дефолту /var/lib/postgresql/15/main . выбрать кластер можно через --claster 
# оставить slave после restore можно с помощью --slave
set -euo pipefail

# --- Конфигурация по умолчанию ---
PG_VERSION="15"
DEFAULT_CLUSTER_DIR="/var/lib/postgresql/$PG_VERSION/main"
TARGET_CLUSTER_DIR="$DEFAULT_CLUSTER_DIR"
MODE="master"

# --- Обработка аргументов ---
show_help() {
    echo "Usage: $0 <target_host> <backup.tar.gz> [--cluster /path/to/dir] [--slave]"
    exit 1
}

if [ $# -lt 2 ]; then show_help; fi

TARGET_HOST="$1"; shift
BACKUP_ARCHIVE="$1"; shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster) TARGET_CLUSTER_DIR="$2"; shift; shift ;;
        --slave)   MODE="slave"; shift ;;
        *)         show_help ;;
    esac
done

TMP_VERIFY_DIR="/tmp/pg_verify_$(date +%s)"

echo "=== ШАГ 1: Локальная проверка валидности ==="
mkdir -p "$TMP_VERIFY_DIR"
tar -xzf "$BACKUP_ARCHIVE" -C "$TMP_VERIFY_DIR" --strip-components=1
export PATH="/usr/lib/postgresql/$PG_VERSION/bin:$PATH"

if pg_verifybackup "$TMP_VERIFY_DIR"; then
    echo "SUCCESS: Бэкап валиден."
    rm -rf "$TMP_VERIFY_DIR"
else
    echo "ERROR: Бэкап ПОВРЕЖДЕН!"
    rm -rf "$TMP_VERIFY_DIR"
    exit 2
fi

echo "=== ШАГ 2: Передача архива через rsync ==="
# Копируем сразу в корень раздела /var/lib/postgresql/, чтобы mv был быстрым
rsync -ravz "$BACKUP_ARCHIVE" "$TARGET_HOST:/var/lib/postgresql/"
ARCHIVE_NAME=$(basename "$BACKUP_ARCHIVE")
REMOTE_ARCHIVE="/var/lib/postgresql/$ARCHIVE_NAME"

echo "=== ШАГ 3: Удаленное восстановление ==="
ssh "$TARGET_HOST" bash -s -- "$TARGET_CLUSTER_DIR" "$REMOTE_ARCHIVE" "$MODE" <<'EOF'
set -euo pipefail
TARGET_DIR="$1"
ARCHIVE_PATH="$2"
MODE="$3"
PARENT_DIR=$(dirname "$TARGET_DIR")
OLD_DATA="${TARGET_DIR}.old"

# 1. Проверка места на разделе /var/lib/postgresql
ARCHIVE_SIZE=$(du -b "$ARCHIVE_PATH" | cut -f1)
FREE_SPACE=$(df -B1 --output=avail "$PARENT_DIR" | tail -n1)

if [ "$FREE_SPACE" -lt $((ARCHIVE_SIZE * 2)) ]; then
    echo "ERROR: Недостаточно места в $PARENT_DIR! Нужно минимум x2 от размера архива."
    exit 1
fi

echo "Остановка PostgreSQL..."
sudo systemctl stop postgresql || true

# 2. Ротация (убираем старый .old если остался и двигаем текущий)
sudo rm -rf "$OLD_DATA"
if [ -d "$TARGET_DIR" ]; then
    echo "Сохраняем текущий кластер в $OLD_DATA"
    sudo mv "$TARGET_DIR" "$OLD_DATA"
fi

# 3. Распаковка
sudo mkdir -p "$TARGET_DIR"
sudo chown postgres:postgres "$TARGET_DIR"
sudo chmod 700 "$TARGET_DIR"

echo "Распаковка..."
if sudo tar -xzf "$ARCHIVE_PATH" -C "$TARGET_DIR" --strip-components=1; then
    sudo chown -R postgres:postgres "$TARGET_DIR"
    
    # Настройка режима (Slave/Master)
    if [ "$MODE" == "master" ]; then
        [ -f "$TARGET_DIR/standby.signal" ] && sudo rm -f "$TARGET_DIR/standby.signal"
        echo "Режим: Master (standby.signal удален)"
    else
        sudo touch "$TARGET_DIR/standby.signal"
        echo "Режим: Slave (standby.signal сохранен/создан)"
    fi

    sync
    echo "Запуск PostgreSQL..."
    if sudo systemctl start postgresql && sleep 5 && sudo -iu postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
        echo "=== ВОССТАНОВЛЕНИЕ УСПЕШНО ==="
        sudo rm -f "$ARCHIVE_PATH"
        sudo rm -rf "$OLD_DATA"
    else
        echo "!!! ОШИБКА ЗАПУСКА: ОТКАТ !!!"
        sudo systemctl stop postgresql || true
        sudo rm -rf "$TARGET_DIR"
        [ -d "$OLD_DATA" ] && sudo mv "$OLD_DATA" "$TARGET_DIR"
        sudo systemctl start postgresql
        sudo rm -f "$ARCHIVE_PATH"
        exit 3
    fi
else
    echo "!!! ОШИБКА РАСПАКОВКИ: ОТКАТ !!!"
    [ -d "$OLD_DATA" ] && sudo mv "$OLD_DATA" "$TARGET_DIR"
    sudo rm -f "$ARCHIVE_PATH"
    exit 4
fi
EOF
