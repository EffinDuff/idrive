#!/bin/bash
# Unraid User Script: run an IDrive backup inside the iDrive container and
# send an Unraid notification with the result.
#
# Install: Settings > User Scripts > Add New Script > paste this file.
# Schedule: "Scheduled Daily" (Unraid runs daily scripts at 04:40) or Custom cron.
#
# Edit the two settings below if your container name or appdata path differ.

CONTAINER="iDrive"
APPDATA="/mnt/user/appdata/idrive"     # host path mapped to /opt/IDriveForLinux/idriveIt

NOTIFY=/usr/local/emhttp/webGui/scripts/notify

# Find the backup log folder automatically (user_profile/<linux user>/<idrive account>/...)
LOGDIR=$(ls -d "$APPDATA"/user_profile/*/*/Backup/DefaultBackupSet/LOGS 2>/dev/null | head -1)
if [ -z "$LOGDIR" ]; then
    $NOTIFY -i alert -s "iDrive Backup FAILED" -d "No IDrive account/log folder found under $APPDATA"
    exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
    $NOTIFY -i alert -s "iDrive Backup FAILED" -d "Container $CONTAINER is not running"
    exit 1
fi

START=$(date +%s)
echo "$(date) starting IDrive backup"
docker exec "$CONTAINER" /bin/bash -c "cd /opt/IDriveForLinux/bin && ./idrive -b"
RC=$?
echo "$(date) idrive exited rc=$RC"

# Newest log written since this run started that has a final status in its name
LATEST=$(find "$LOGDIR" -newermt "@$START" -type f \
    \( -name "*_Success_*" -o -name "*_Failed_*" -o -name "*_Aborted_*" -o -name "*_Canceled_*" \) \
    | sort | tail -1)

if [ -z "$LATEST" ]; then
    $NOTIFY -i alert -s "iDrive Backup UNKNOWN" -d "No completed log found after run start (rc=$RC)"
    exit 1
elif [[ "$LATEST" == *_Success_* ]]; then
    $NOTIFY -i normal -s "iDrive Backup" -d "Completed: $(basename "$LATEST")"
else
    $NOTIFY -i alert -s "iDrive Backup FAILED" -d "$(basename "$LATEST") (rc=$RC)"
    exit 1
fi
