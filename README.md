# ASIAIR Sync

ASIAIR Sync is a simple macOS menu bar app that copies your ASIAIR FITS files to a local folder on your Mac.

## What It Does

- Connects to your ASIAIR over SMB (Guest mode)
- Syncs FITS files to a folder you choose
- Runs in the background while you image
- Shows sync status, progress, speed, and current file
- Can optionally remove local files that were deleted on ASIAIR

## What to Expect

ASIAIR Sync works as a background sync tool, but it is not 100% stable.

You may occasionally see disconnects from ASIAIR, even on a direct connection.  
If that happens, keep the app running (or press **Resume Sync**) and it will reconnect and continue syncing.

For larger sessions, full sync can take time. Consider setting up your ASIAIR using LAN (personally didn't test it yet).

## Screenshots

![Status popover](./assets/examples/Screenshot%202026-02-27%20at%2019.29.17.png)
![Settings expanded](./assets/examples/Screenshot%202026-02-27%20at%2019.29.14.png)
![Pause state](./assets/examples/Screenshot%202026-02-27%20at%2019.29.23.png)

## Download

Download the latest DMG here:

- [Latest Release](https://github.com/serhiiboreiko/asiair-sync/releases/latest)

## Install

1. Download the `.dmg` file.
2. Open it.
3. Drag `ASIAIRSync.app` to `Applications`.
4. Open `ASIAIRSync.app`.

## First-Time Setup

1. Click the ASIAIR Sync icon in the menu bar.
2. Open **Settings**.
3. Enter your ASIAIR host IP
4. Keep share name as `EMMC Images` (unless you changed it somehow).
5. Choose your destination folder on Mac.
6. Set sync interval (default `10s` is fine).
7. Choose whether local deletes should mirror ASIAIR deletes.
8. Click **Apply Settings & Start**.

On first launch, the app asks whether to start at login.

## Daily Use

- Use **Pause Sync** / **Resume Sync** anytime.
- Keep the app running while you image.

Status fields:

- `Speed`: Current transfer speed
- `Progress`: Total progress based on local FITS count vs ASIAIR FITS count
- `Files left`: Estimated remaining files in this cycle
- `Local FITS files`: How many FITS files are in your selected folder
- `Current`: File being synced right now

## Updates

- The app automatically checks GitHub Releases for new versions.
- You can also click **Check for Updates** inside the app.
- If an update is available, click **Download Update** and install the latest DMG.

## Tips For Better Results

- Keep Mac and ASIAIR on the same stable network.
- Start syncing early in your session and let it run.
- Keep your Mac awake.

## Quick Troubleshooting

### "Could not mount ..."

- Confirm ASIAIR and Mac are on the same network.
- Recheck host IP and share name.
- Try opening the ASIAIR SMB share in Finder once.

### Sync seems slow

- This is expected for large datasets over Wi-Fi.
- Leave it running; it is built for steady background syncing.

### App starts but nothing syncs

- Make sure a destination folder is selected.
- Check that there are FITS files on ASIAIR.

## Known Limits

- Guest SMB auth only (no username/password UI yet).
- App is not notarized yet, so first launch may need manual approval.

## Privacy

Everything runs on your Mac and local network. No cloud upload.

## License

MIT (see [LICENSE](./LICENSE)).
