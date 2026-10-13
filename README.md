# Moly

Moly restores a small, explicitly allow-listed part of your Mac profile on shared Macs. The public GitHub repository contains only the generic bootstrap and example manifest. Your real `manifest.json`, app bundles, settings, and files belong in your private Dropbox folder at `Mac-Profile-Sync`.

## What the one-line setup does

```sh
curl -fsSL https://raw.githubusercontent.com/GiyeopKim1993/moly/main/install.sh | bash
```

It downloads the generic sync script, restores the items listed in your Dropbox `manifest.json`, then registers a per-user LaunchAgent that copies listed local items to Dropbox every five minutes while you are logged in. If there is no manifest yet, it copies an empty example to Dropbox and exits; add your items, then run the command again.

The repository's weekly GitHub Actions workflow downloads Dropbox's current Mac DMG from its official download endpoint and refreshes the `dropbox-latest` release asset. If Dropbox is missing, the setup script downloads that DMG and copies `Dropbox.app` into `~/Applications`, opens it, and exits so you can sign in. Run the one-line setup again after signing in and syncing `Mac-Profile-Sync`. A Dropbox connection inside ChatGPT does not connect a Mac's local filesystem. On managed Macs, installation or updating may still require IT approval. If the folder is in a different location, set `MOLY_CLOUD_ROOT` to its local path before running the command.

## Manifest format

Create `manifest.json` inside the local Dropbox `Mac-Profile-Sync` folder. All `source` paths are relative to that folder. Destinations must be inside your home folder.

```json
{
  "version": 1,
  "apps": [
    {"source": "apps/Visual Studio Code.app", "destination": "~/Applications/Visual Studio Code.app"}
  ],
  "settings": [
    {"source": "settings/zsh/.zshrc", "destination": "~/.zshrc"}
  ],
  "files": [
    {"source": "files/Documents", "destination": "~/Documents"}
  ],
  "brew_packages": ["awscli", "micromamba"],
  "brew_casks": ["anaconda"]
}
```

Copy app bundles into `apps/`, selected configuration into `settings/`, and durable personal files into `files/`. App preferences are often under `~/Library/Preferences`, `~/Library/Application Support`, `~/Library/Containers`, or `~/Library/Group Containers`; discover and test each app's paths before adding them. Do not add Keychains, caches, browser sessions, tokens, or whole `~/Library` trees.

## Commands

After setup, these commands are available:

```sh
python3 ~/.local/share/moly/sync.py backup
python3 ~/.local/share/moly/sync.py restore
python3 ~/.local/share/moly/sync.py backup --dry-run
```

The periodic job backs up only declared items. It merges changed files and does not delete files from Dropbox or the Mac. Dropbox desktop sync uploads changes from the local sync folder.

## Limits

- macOS stops user LaunchAgents during logout. Moly therefore cannot guarantee a final upload when you click Log Out; the periodic job's last run may be up to five minutes earlier. Confirm Dropbox reports fully synced before leaving when recent work matters.
- Homebrew packages are installed only if `brew` is already available. Installing Homebrew or system-level applications may require an administrator.
- Some app settings are stored in databases or Keychain and cannot safely be copied as ordinary files. Add only tested, app-specific paths.
- The script does not upload personal content to GitHub. GitHub hosts the public generic code; Dropbox stores your private manifest and allow-listed data.
