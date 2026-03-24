#!/bin/bash
set -euo pipefail

if [ -z "${1-}" ]; then
    echo "Usage: $0 <backup_file>"
    exit 1
fi

BACKUP_FILE="$1"
ETCD_HOST="{{ hostname_ekr }}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REMOTE_TMP="/tmp/$(basename "$BACKUP_FILE")"

echo "Reading etcd configuration from $ETCD_HOST..."

read ETCD_DATA_DIR ETCD_NAME ETCD_CLUSTER ETCD_PEER_URL <<< $(ssh $ETCD_HOST '
set -a
source /etc/etcd/etcd.env
echo "$ETCD_DATA_DIR $ETCD_NAME $ETCD_INITIAL_CLUSTER $ETCD_INITIAL_ADVERTISE_PEER_URLS"
')

echo "ETCD_DATA_DIR = $ETCD_DATA_DIR"
echo "ETCD_NAME     = $ETCD_NAME"
echo "ETCD_PEER_URL = $ETCD_PEER_URL"

echo
echo "Copying backup $BACKUP_FILE..."
scp "$BACKUP_FILE" "$ETCD_HOST:$REMOTE_TMP"

echo
echo "Stopping etcd..."
ssh "$ETCD_HOST" "systemctl stop etcd"

echo
echo "Backing up current data..."
ssh "$ETCD_HOST" "
if [ -d $ETCD_DATA_DIR ]; then
    mv $ETCD_DATA_DIR ${ETCD_DATA_DIR}.bak_$TIMESTAMP
    echo 'Old etcd data backed up'
fi
"

echo
echo "Restoring snapshot..."
ssh "$ETCD_HOST" "
ETCDCTL_API=3 etcdctl snapshot restore $REMOTE_TMP \
  --data-dir ${ETCD_DATA_DIR}_restored \
  --name $ETCD_NAME \
  --initial-cluster \"$ETCD_CLUSTER\" \
  --initial-advertise-peer-urls \"$ETCD_PEER_URL\"
"

echo
echo "Replacing data dir..."
ssh "$ETCD_HOST" "
mv ${ETCD_DATA_DIR}_restored $ETCD_DATA_DIR
chown -R etcd:etcd $ETCD_DATA_DIR
"

echo
echo "Starting etcd..."
ssh "$ETCD_HOST" "systemctl start etcd"

echo
echo "Cleaning temp files..."
ssh "$ETCD_HOST" "rm -f $REMOTE_TMP"

echo
echo "Done. Endpoint status:"
ETCDCTL_API=3 etcdctl \
  --endpoints=http://$ETCD_HOST:"{{ etcd_port }}" \
  endpoint status
