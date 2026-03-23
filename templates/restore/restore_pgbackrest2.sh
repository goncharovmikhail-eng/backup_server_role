#!/bin/bash

# --- ПАРСИНГ АРГУМЕНТОВ ---
TARGET_TIME=""
MODE="rw"   # rw | readonly | replica

while [[ $# -gt 0 ]]; do
  case "$1" in
    --time)
      TARGET_TIME="$2"
      shift 2
      ;;
    --readonly)
      MODE="readonly"
      shift
      ;;
    --replica)
      MODE="replica"
      shift
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      exit 1
      ;;
  esac
done

if [[ "$MODE" != "replica" && -z "$TARGET_TIME" ]]; then
  echo "Использование: $0 --time \"YYYY-MM-DD HH:MM:SS\" [--readonly|--replica]"
  exit 1
fi

REMOTE_HOST="{{  }}"
PRIMARY_HOST="192.168.221.10"   # мастер
REPL_USER="replicator"

# echo "=== ШАГ 1: Проверка репозитория ==="
# pgbackrest info --stanza=main || exit 1

echo "=== Удаленное восстановление на $REMOTE_HOST ==="

ssh root@$REMOTE_HOST bash -s <<EOF
set -e

PGDATA="/var/lib/postgresql/15/main"
MODE="$MODE"
TARGET_TIME="$TARGET_TIME"
PRIMARY_HOST="$PRIMARY_HOST"
REPL_USER="$REPL_USER"

echo "Остановка PostgreSQL..."
systemctl stop postgresql || true

# убиваем оставшиеся процессы, если есть
if pgrep -u postgres postgres > /dev/null; then
  echo "PostgreSQL всё ещё работает, убиваем процессы..."
  pkill -9 -u postgres postgres
  sleep 2
fi

# проверяем postmaster.pid
if [ -f "\$PGDATA/postmaster.pid" ]; then
  echo "Удаляем stale postmaster.pid"
  rm -f "\$PGDATA/postmaster.pid"
fi

# --- TARGET ACTION ---
if [[ "\$MODE" == "rw" ]]; then
  TARGET_ACTION="--target-action=promote"
elif [[ "\$MODE" == "readonly" ]]; then
  TARGET_ACTION="--target-action=pause --target-exclusive"
else
  TARGET_ACTION=""
fi

echo "Запуск pgBackRest restore..."
if [[ "\$MODE" == "replica" ]]; then
  sudo -u postgres /usr/local/bin/pgbackrest --stanza=main --delta restore
else
  sudo -u postgres /usr/local/bin/pgbackrest --stanza=main --delta restore --type=time --target="\$TARGET_TIME" \$TARGET_ACTION
fi

# --- Настройка replica ---
if [[ "\$MODE" == "replica" ]]; then
  echo "Пробуем подключиться к мастеру..."
  if ping -c 1 -W 1 $PRIMARY_HOST &> /dev/null; then
    echo "Мастер доступен, настраиваем standby..."
    echo "primary_conninfo = 'host=$PRIMARY_HOST user=$REPL_USER'" >> \$PGDATA/postgresql.auto.conf
    touch \$PGDATA/standby.signal
  else
    echo "⚠️ Мастер недоступен, поднимаем readonly snapshot"
    TARGET_ACTION="--target-action=pause --target-exclusive"
    sudo -u postgres /usr/local/bin/pgbackrest --stanza=main --delta restore --type=time --target="\$TARGET_TIME" \$TARGET_ACTION
    MODE="readonly"
  fi
fi

echo "Запуск PostgreSQL..."
systemctl start postgresql
sleep 3

# --- Проверка режима ---
RECOVERY_STATUS=\$(sudo -iu postgres psql -t -c "SELECT pg_is_in_recovery();" | xargs)

if [[ "\$MODE" == "replica" ]]; then
  if [[ "\$RECOVERY_STATUS" == "t" ]]; then
    echo "✅ БАЗА В РЕЖИМЕ REPLICA (standby, streaming)"
  else
    echo "❌ БАЗА НЕ смогла стать standby, сейчас readonly"
  fi
elif [[ "\$MODE" == "readonly" ]]; then
  echo "✅ БАЗА В RECOVERY (readonly snapshot)"
else
  echo "✅ БАЗА В READ-WRITE"
fi

EOF
