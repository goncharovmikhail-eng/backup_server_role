#!/usr/bin/env bash
set -euo pipefail

# =====================
# ПАРАМЕТРЫ
# =====================
STANZA="main"
PGDATA="/var/lib/postgresql/15/main"   # путь к PGDATA
PGSERVICE="postgresql"                 # systemctl service name
SSH_HOST="svx-express-postgres.ar.int" # ssh хост postgres сервера

READONLY=true   # по умолчанию после restore включаем read-only

# =====================
# АРГУМЕНТЫ
# =====================
BACKUP_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      BACKUP_NAME="$2"
      shift 2
      ;;
    --rw)
      READONLY=false
      shift
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$BACKUP_NAME" ]]; then
  echo "Использование: $0 --name <backup_name> [--rw]"
  exit 1
fi

echo "=== START RESTORE: $BACKUP_NAME ==="

# =====================
# СТОП PostgreSQL
# =====================
echo "=== STOP PostgreSQL ==="
ssh root@"$SSH_HOST" "systemctl stop $PGSERVICE"

# =====================
# ОЧИСТКА DATA DIR (безопасно для bash/zsh)
# =====================
echo "=== CLEAN DATA DIR ==="
ssh root@"$SSH_HOST" "
  if [[ -d $PGDATA && \"$PGDATA\" != \"/\" ]]; then
    find $PGDATA -mindepth 1 -delete
  else
    echo 'Ошибка: PGDATA не существует или это /'
    exit 1
  fi
"

# =====================
# RESTORE через pgBackRest
# =====================
echo "=== RUN pgBackRest restore ==="
ssh root@"$SSH_HOST" "
  pgbackrest \
    --stanza=$STANZA \
    --set=$BACKUP_NAME \
    restore
"

# =====================
# Исправляем владельца PGDATA на postgres
# =====================
echo "=== FIX PERMISSIONS ==="
ssh root@"$SSH_HOST" "chown -R postgres:postgres $PGDATA"

# =====================
# СТАРТ PostgreSQL
# =====================
echo "=== START PostgreSQL ==="
ssh root@"$SSH_HOST" "systemctl start $PGSERVICE"

# =====================
# READ-ONLY режим
# =====================
if [[ "$READONLY" == true ]]; then
  echo "=== SET READ ONLY MODE ==="
  ssh root@"$SSH_HOST" "
    sudo -iu postgres psql -c \"
      ALTER SYSTEM SET default_transaction_read_only = on;
    \"
    sudo -iu postgres psql -c \"SELECT pg_reload_conf();\"
  "
else
  echo "=== READ-WRITE MODE (MASTER) ==="
fi

echo "=== RESTORE COMPLETE ==="