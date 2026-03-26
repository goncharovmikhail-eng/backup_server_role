#!/bin/bash
chmod +x -R .
apt install -y tree postgresql-15 || dnf install -y tree postgresql-15
cp moth.sh /etc/profile.d/.
cp alias.sh ~/.
mkdir -p ~/backup_scripts
cp backup_config.sh ~/backup_scripts/.
cp backup_psql.sh  ~/backup_scripts/.
cp backup_config_unit /etc/systemd/system/backup_config.service
cp backup_config_unit_timer /etc/systemd/system/backup_config.timer
cp db_backup.sh ~/backup_scripts/.
cp restore_psql.sh  ~/backup_scripts/.
cp -r sql_backup ~/backup_scripts/.
cp ssh_config ~/.ssh/config
cp usr_local_bin_backup_config.sh /usr/local/bin/backup_config
cp usr_local_bin_etcd_restore.sh /usr/local/bin/etcd_restore
mkdir -p /backups/etcd/
mkdir -p /backups/postgres

echo "source ~/alias.sh" >> .bashrc
echo "source ~/alias.sh" >> .zshrc

systemctl daemon-reload
systemctl enable backup_config.timer
systemctl start backup_config.timer

systemctl status backup_config.service
systemctl list-timers | grep backup_config || true

TMP_CURRENT=$(mktemp)
TMP_NEW=$(mktemp)

crontab -l 2>/dev/null > "$TMP_CURRENT" || true
cp "$TMP_CURRENT" "$TMP_NEW"

while IFS= read -r line; do
[[ -z "$line" || "$line" =~ ^# ]] && continue
grep -Fxq "$line" "$TMP_CURRENT" || echo "$line" >> "$TMP_NEW"
done < ./crontab

crontab "$TMP_NEW"

rm -f "$TMP_CURRENT" "$TMP_NEW"

grep -qxF "source ~/alias.sh" ~/.bashrc || echo "source ~/alias.sh" >> ~/.bashrc
grep -qxF "source ~/alias.sh" ~/.zshrc 2>/dev/null || echo "source ~/alias.sh" >> ~/.zshrc

crontab -l
