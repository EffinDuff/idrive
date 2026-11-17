# IDrive for Linux — Docker image for Unraid

Runs the official [IDrive for Linux](https://www.idrive.com/online-backup-linux-scripts) package in a container so an Unraid server can back up its shares to IDrive.

- Ubuntu 26.04 LTS base, newest IDrive package installed at build time
- Rebuilt automatically every Monday by GitHub Actions
- All IDrive settings (account, backup set, scheduler, logs) live in one appdata folder, so they survive image updates and container rebuilds
- IDrive's scheduler and dashboard services start on boot and are restarted if they stop
- Backups are triggered nightly by an Unraid User Script that sends an Unraid notification with the result

## Images

| Registry | Image |
|---|---|
| Docker Hub | `effinduff/idrive:latest` |
| GitHub | `ghcr.io/effinduff/idrive:latest` |

Each build is also tagged with its date (`:YYYYMMDD`) so you can pin or roll back. `:legacy-2026-06` is the last image before this rework.

---

## 1. Install on Unraid

### Option A — template (recommended)
1. **Docker** tab → bottom of page → **Template repositories**, add:
   `https://github.com/EffinDuff/idrive`
   and click **Save**.
2. **Docker** → **Add Container** → pick **iDrive** from the template dropdown.
3. Review the settings (below) and click **Apply**.

### Option B — manual
**Docker** → **Add Container**, then:

| Field | Value |
|---|---|
| Name | `iDrive` |
| Repository | `effinduff/idrive:latest` |
| Network Type | `Host` |
| Console shell command | `Bash` |

and add the paths/variables below.

### Settings

**Config path (required)**

| Container path | Host path | Mode |
|---|---|---|
| `/opt/IDriveForLinux/idriveIt` | `/mnt/user/appdata/idrive` | Read/Write |

**Source paths — one per share you want backed up.** Mount each one *read-only* under `/mnt/backup/`:

| Container path | Host path (example) | Mode |
|---|---|---|
| `/mnt/backup/Photos` | `/mnt/user/Photos/` | Read Only |
| `/mnt/backup/Documents` | `/mnt/user/Documents/` | Read Only |

If your IDrive backup set is `/mnt/backup/`, any share you add here later is picked up automatically — no change inside IDrive needed.

**Variables**

| Name | Default | Purpose |
|---|---|---|
| `TZ` | `America/New_York` | Timezone for logs and schedules |
| `IDRIVE_CHECK_INTERVAL` | `60` | Seconds between checks that the IDrive services are running |

---

## 2. First-time IDrive setup

1. Start the container, then click its icon → **Console**.
2. Run:
   ```bash
   cd /opt/IDriveForLinux/bin
   ./idrive
   ```
3. Log in with your IDrive account and follow the prompts.
4. Set the **backup set** to `/mnt/backup/`.
5. If you'll use the User Script below for scheduling, **turn off IDrive's own backup schedule** in the menu (otherwise you'll get two backups a night).

After this, restarting or updating the container needs no further interaction — the container log should show `Starting IDrive cron service`.

---

## 3. Nightly backup with an Unraid User Script

Requires the **User Scripts** plugin (Apps tab).

1. **Settings** → **User Scripts** → **Add New Script**, name it e.g. `Initiate idrive backup`.
2. Click the gear → **Edit Script**, paste the contents of [`unraid/userscript-idrive-backup.sh`](unraid/userscript-idrive-backup.sh), and **Save Changes**.
3. If your container isn't named `iDrive` or your appdata path differs, edit `CONTAINER` / `APPDATA` at the top of the script.
4. Set the schedule to **Scheduled Daily** (Unraid runs these at 04:40) or **Custom** with your own cron expression.
5. Click **Run Script** once to test.

What it does:
- Fails with a notification if the container isn't running or no IDrive account is found
- Runs `./idrive -b` inside the container
- Finds the IDrive log written by that run and sends an Unraid notification: **Completed**, **FAILED** (Failed/Aborted/Canceled), or **UNKNOWN** (no log written)
- Script output is kept in the User Scripts log (**Show Log**)

The log folder is found automatically under `appdata/idrive/user_profile/`, so no account name needs to be hard-coded.

---

## 4. Updating

- New images are published every Monday (and on every merge to `main`).
- Unraid's **Docker** tab shows **update ready** — click it, or use the **Auto Update Applications** plugin.
- Your settings are untouched because they live in `/mnt/user/appdata/idrive`.

**Rolling back:** set the Repository field to a dated tag, e.g. `effinduff/idrive:20261116`, or `effinduff/idrive:legacy-2026-06`.

---

## 5. Migrating from the old layout

Older versions mapped only `user_profile`:
`/mnt/user/appdata/idrive/user_profile` → `/opt/IDriveForLinux/idriveIt/user_profile`

1. *(Before updating)* save the current schedule file into appdata — in the container console:
   ```bash
   cp /etc/idrivecrontab.json /opt/IDriveForLinux/idriveIt/user_profile/
   ```
   The new image moves it into place on first start.
2. Edit the container and change that one path mapping to:

   | | Old | New |
   |---|---|---|
   | Host path | `/mnt/user/appdata/idrive/user_profile` | `/mnt/user/appdata/idrive` |
   | Container path | `/opt/IDriveForLinux/idriveIt/user_profile` | `/opt/IDriveForLinux/idriveIt` |

   Your existing data stays exactly where it is on disk.
3. Apply. Check the container log and the next backup notification.

---

## 6. Building it yourself

```bash
docker build -t idrive:local .
docker build --build-arg UBUNTU_VERSION=24.04 -t idrive:noble .   # older Ubuntu base
```

### GitHub Actions
`.github/workflows/build.yml` builds on push to `main`, every Monday, or manually (**Actions** → **Build & publish image** → **Run workflow**, optional Ubuntu version).

Repository secrets needed for Docker Hub (**Settings** → **Secrets and variables** → **Actions**):

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub personal access token with **Read & Write** |

GHCR uses the built-in `GITHUB_TOKEN`; no secret needed. Make the GHCR package public (profile → **Packages** → **idrive** → **Package settings**) if Unraid should pull it without logging in.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Backups stop after a container restart | Container log should show `Starting IDrive cron service`. In the console: `ps aux \| grep idrivecron` |
| Notification says UNKNOWN | The run wrote no final log. Look in `appdata/idrive/user_profile/*/*/Backup/DefaultBackupSet/LOGS/` and the User Script log |
| Two backups per night | IDrive's internal schedule is still on — disable it in `./idrive` |
| Container marked unhealthy | IDrive scheduler isn't running; restart the container and check the log |

## How it works

- `Dockerfile` installs IDrive from `idrivedownloads.com` (always the current release) and keeps a clean copy of `idriveIt` to seed an empty appdata folder.
- `entrypoint.sh` (run under `tini`):
  - copies any missing default files into the appdata volume without overwriting yours, and refreshes the IDrive transfer engine binaries to match the installed package
  - links `/etc/idrivecrontab.json` (IDrive's scheduler file) to the appdata volume so schedules persist
  - starts `idrivecron --cron` and the IDrive dashboard, and restarts them if they stop
- `unraid/idrive.xml` — Unraid container template
- `unraid/userscript-idrive-backup.sh` — nightly backup User Script

IDrive is a trademark of IDrive Inc. This project is not affiliated with IDrive.
