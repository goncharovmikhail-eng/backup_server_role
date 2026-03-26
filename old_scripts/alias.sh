#~/alias.sh
#!/usr/bin/env bash

#psql
#restore_psql в /usr/local/bin/restore_psql
alias log_psql_restore="cat /var/log/pgbackrest/main-restore.log"
alias log_psql_backup="cat /var/log/pgbackrest/main-backup.log"
alias backup_psql_incr="pgbackrest --stanza=main --type=incr backup"
alias backup_psql_full="pgbackrest --stanza=main --repo1-path=/backups/postgres/ --type=full backup"

#etcd
#backup_etcd в /usr/local/bin/backup_etcd
#etcd_restore в /usr/local/bin/etcd_restore

#docker_volumes от svx-express-back.ar.int
alias backup_volumes="ssh svx-express-back.ar.int 'tar czpf - -C / var/lib/docker/volumes' | cat > /backups/docker_volumes/backup_docker_volumes$(date +%F-%H%M%S).tar.gz ; tree  /backups/docker_volumes"

#configs
backup_config_f() {
    if [ -z "${1:-}" ]; then
        echo "Usage: collect <server> [archive_prefix]"
        return 1
    fi

    local SERVER="$1"
    local ARCHIVE_PREFIX="${2:-$SERVER}"
    local BACKUP_DIR="/backups/"

    mkdir -p "$BACKUP_DIR"

    local TIMESTAMP=$(date +%F-%H%M%S)
    local ARCHIVE_NAME="${ARCHIVE_PREFIX}_${TIMESTAMP}.tar.gz"

    echo "=== Collecting from $SERVER ==="
    echo "Archive name: $ARCHIVE_NAME"

    ssh "$SERVER" "bash -s -- \"$ARCHIVE_NAME\"" < ~/backup_scripts/backup_config.sh

    echo "Downloading to: $BACKUP_DIR/$ARCHIVE_NAME"
    scp "$SERVER:/tmp/$ARCHIVE_NAME" "$BACKUP_DIR/"

    # Чистим временные файлы на сервере
    ssh "$SERVER" "rm -f /tmp/$ARCHIVE_NAME"

    echo "Done! Saved to: $BACKUP_DIR/$ARCHIVE_NAME"
}
alias backup_configs="time systemctl start backup_config.service && tree /backups"
alias log_backup_config="cat /var/log/config_backup.log"

#очистка
alias clear_backups="rm -rf /backups/etcd/* /backups/postgres/* /backups/svx-express* /backups/docker_volumes/* tree /backups"
cl() {
  echo '' > "$1" && vim "$1"
}

#прочее
aliasw() {
    nano "$HOME/alias.sh" || return
    source "$HOME/alias.sh"
    echo "Aliases reloaded"
}
alias res="source ~/.zshrc"
#alias res="source ~/.bashrc"
alias scc="less ~/.ssh/config"
alias sc="vim ~/.ssh/config"
alias md="mkdir -p"
#alias cbl="journalctl -u backup_config.service --since today"
alias gitup="git fetch && git pull"