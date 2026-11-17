#!/bin/bash
# IDrive container entrypoint
#  - seeds/repairs the persistent idriveIt volume
#  - keeps the scheduler file (/etc/idrivecrontab.json) on the volume
#  - starts the IDrive cron + dashboard services WITHOUT needing the interactive menu
#  - watches them and restarts them if they die
set -u

IDRIVE_BIN="/opt/IDriveForLinux/bin"
IDRIVE_IT="/opt/IDriveForLinux/idriveIt"
DEFAULTS="/opt/idriveIt.defaults"
CRONTAB_PERSIST="$IDRIVE_IT/idrivecrontab.json"
CHECK_INTERVAL="${IDRIVE_CHECK_INTERVAL:-60}"

log() { echo "[$(date '+%F %T')] $*"; }

log "IDrive for Linux container starting ($(. /etc/os-release; echo "$PRETTY_NAME"))"

# --- Timezone (configurable from the Unraid template) ----------------------
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime && echo "$TZ" > /etc/timezone
fi

# --- Seed / refresh the persistent volume -----------------------------------
mkdir -p "$IDRIVE_IT"
# Copy anything missing from the image defaults (never overwrites your data)
cp -an "$DEFAULTS/." "$IDRIVE_IT/" 2>/dev/null
# The transfer engines must match the installed package version, so always refresh them
for f in idevsutil idevsutil_dedup; do
    [ -f "$DEFAULTS/$f" ] && cp -f "$DEFAULTS/$f" "$IDRIVE_IT/$f"
done

# --- Persist the scheduler -----------------------------------------------------
# IDrive keeps its schedule in /etc/idrivecrontab.json, which is lost on every
# container recreate. Point it at the volume instead (IDrive supports a linked path).
if [ ! -s "$CRONTAB_PERSIST" ]; then
    if [ -f /etc/idrivecrontab.json ] && [ ! -L /etc/idrivecrontab.json ]; then
        cp -a /etc/idrivecrontab.json "$CRONTAB_PERSIST"
    elif [ -s "$IDRIVE_IT/user_profile/idrivecrontab.json" ]; then
        # one-time migration from the old user_profile-only layout
        cp -a "$IDRIVE_IT/user_profile/idrivecrontab.json" "$CRONTAB_PERSIST"
        log "Migrated scheduler file from user_profile"
    fi
fi
touch "$CRONTAB_PERSIST" && chmod 666 "$CRONTAB_PERSIST"
ln -snf "$CRONTAB_PERSIST" /etc/idrivecrontab.json
ln -snf "$IDRIVE_BIN/idrive" /etc/idrivecron

# --- Service management --------------------------------------------------------
account_configured() { compgen -G "$IDRIVE_IT/user_profile/*/*" >/dev/null; }

start_cron() {
    if ! pgrep -f 'idrivecron --cron' >/dev/null; then
        log "Starting IDrive cron service"
        (cd "$IDRIVE_BIN" && nohup /etc/idrivecron --cron >/dev/null 2>&1 &)
        sleep 20   # cron brings up the watcher service; give it a moment before the dashboard
    fi
}

start_dashboard() {
    if ! pgrep -f 'python/dashboard' >/dev/null; then
        log "Starting IDrive dashboard service"
        (cd "$IDRIVE_BIN" && nohup ./Idrivelib/dependencies/python/dashboard start >/dev/null 2>&1 &)
    fi
}

stop_all() {
    log "Stopping IDrive services"
    pkill -TERM -f 'python/dashboard' 2>/dev/null
    pkill -TERM -f "$IDRIVE_BIN/idrive" 2>/dev/null
    pkill -TERM -f 'idrivecron' 2>/dev/null
    sleep 3
    exit 0
}
trap stop_all SIGTERM SIGINT

if account_configured; then
    log "Existing IDrive account found in $IDRIVE_IT/user_profile"
else
    log "No IDrive account configured yet. Open the container console and run:"
    log "  cd $IDRIVE_BIN && ./idrive    (log in, then set your backup set + schedule)"
fi

# --- Supervise ----------------------------------------------------------------
while true; do
    if account_configured; then
        start_cron
        start_dashboard
    fi
    sleep "$CHECK_INTERVAL" &
    wait $!
done
