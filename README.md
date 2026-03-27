Роль предназначена для развертывания backup-сервера с поддержкой:

- PostgreSQL (pgBackRest: full + incremental)
- etcd
- Docker volumes (через tar stream по SSH)
- резервного копирования конфигураций серверов
- автоматической очистки старых бэкапов
- systemd timers для расписания

Роль ориентирована на использование в production-среде.

---

## Возможности

- Настройка pgBackRest (backup server + remote PostgreSQL)
- Инкрементальные и полные бэкапы PostgreSQL
- Бэкап Docker volumes по SSH
- Бэкап etcd
- Сбор конфигураций с удалённых серверов
- Автоматическая ротация бэкапов
- systemd unit + timer для:
  - ежедневных бэкапов
  - еженедельного полного бэкапа
- Удобные алиасы для ручного управления

## Сейчас роль заточена под проект месседжера Express в конфигурации: ( Front + docker registry) + BMT + psql + bot_server + ekr , но со временем буду делать гибче

---
