#!/bin/bash
# IDrive container entrypoint
#  - seeds/repairs the persistent idriveIt volume
#  - keeps the scheduler file (/etc/idrivecrontab.json) on the volume
#  - starts the IDrive cron service (which starts the dashboard) WITHOUT the interactive menu
#  - restarts cron if it dies (gives up after 5 attempts) and logs dashboard state changes
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
for f in "$DEFAULTS"/idevsutil*; do
    [ -f "$f" ] && cp -f "$f" "$IDRIVE_IT/"
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

CRON_FAILS=0
MAX_CRON_RESTARTS=5
DASH_REPORTED=""

# The IDrive cron service starts the dashboard itself
# (3.16: "idrive --dashboard"; older builds: "python/dashboard start").
dashboard_running() { pgrep -f -- 'idrive --dashboard|python/dashboard' >/dev/null; }

start_cron() {
    pgrep -f 'idrivecron --cron' >/dev/null && { CRON_FAILS=0; return; }
    if [ "$CRON_FAILS" -ge "$MAX_CRON_RESTARTS" ]; then
        return   # already gave up; error was logged once
    fi
    CRON_FAILS=$((CRON_FAILS + 1))
    log "Starting IDrive cron service (attempt $CRON_FAILS/$MAX_CRON_RESTARTS)"
    (cd "$IDRIVE_BIN" && nohup /etc/idrivecron --cron >/dev/null 2>&1 &)
    sleep 20
    if ! pgrep -f 'idrivecron --cron' >/dev/null && [ "$CRON_FAILS" -ge "$MAX_CRON_RESTARTS" ]; then
        log "ERROR: IDrive cron service keeps exiting. Open the console and run ./idrive to check the account; restart the container afterwards."
    fi
}

report_dashboard() {
    if dashboard_running; then
        [ "$DASH_REPORTED" = up ] || log "IDrive dashboard service is running"
        DASH_REPORTED=up
    else
        [ "$DASH_REPORTED" = down ] || log "IDrive dashboard service is not running (it is started by the cron service; check the account login with ./idrive)"
        DASH_REPORTED=down
    fi
}

stop_all() {
    log "Stopping IDrive services"
    pkill -TERM -f -- 'idrive --dashboard|python/dashboard' 2>/dev/null
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
        report_dashboard
    fi
    sleep "$CHECK_INTERVAL" &
    wait $!
done
