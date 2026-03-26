#!/bin/bash
#для юнита в вызывать с ./backup_scripts/backup_psql_full.sh svx-express-postgres.ar.int

set -euo pipefail
source ~/backup_scripts/.env

# 1. Проверка аргументов
if [ $# -lt 1 ]; then
  echo "Usage: $0 <db_server>"
  exit 1
fi

db_server="$1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASE_DIR="/backups/postgres"
BACKUP_NAME="pg_full_basebackup_${db_server}_${TIMESTAMP}"
BACKUP_DIR="$BASE_DIR/$BACKUP_NAME"

mkdir -p "$BASE_DIR"

# Проверяем, установлена ли утилита pg_verifybackup, прежде чем начинать
if ! command -v pg_verifybackup &> /dev/null; then
    echo "ERROR: pg_verifybackup не найдена в PATH или не установлена!"
    echo "Установите пакет: apt install postgresql-15"
    exit 1
fi

echo "=== Starting psql backup for $db_server: $(date '+%Y-%m-%d %H:%M:%S') ==="

# 3. Создание бэкапа
# Используем временную переменную для статуса, чтобы корректно выйти при сбое
if pg_basebackup \
  -h "$db_server" \
  -p 5432 \
  -U replicator \
  -D "$BACKUP_DIR" \
  -Fp -Xs -P -R -v; then

    echo "=== pg_basebackup finished. Starting verification... ==="

    # 4. Проверка на валидность через манифест
    if pg_verifybackup "$BACKUP_DIR"; then
        echo "SUCCESS: Backup integrity verified."

        # 5. Архивация
        echo "=== Archiving backup... ==="
        tar -czf "$BASE_DIR/$BACKUP_NAME.tar.gz" -C "$BASE_DIR" "$BACKUP_NAME"

        # 6. Очистка временной папки
        rm -rf "$BACKUP_DIR"
        echo "=== Finished psql backup for $db_server: $(date '+%Y-%m-%d %H:%M:%S') ==="
    else
        echo "ERROR: Backup integrity check FAILED!"
        rm -rf "$BACKUP_DIR"
        echo "Бэкап не валидный. Запустите скрипт руками еще раз."
        exit 2
    fi
else
    echo "ERROR: pg_basebackup failed!"
    [ -d "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
    exit 1
fi

echo "=== Current backups state ==="
