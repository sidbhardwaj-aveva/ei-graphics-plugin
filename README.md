# EI Graphics Plugin

For full documentation — prerequisites, usage, repository layout, tests, and contribution notes —
see [PLUGIN-INFO.md](PLUGIN-INFO.md).

## Installation

1. Press **`Ctrl+Shift+P`** and type **`Preferences: Open User Settings (JSON)`**, then press Enter.

2. Locate the `chat.plugins.marketplaces` array. If it does not exist yet, add it.
   `https://github.com/AVEVA-Copilot-Access/aveva-agent-plugins` **must already be present**
   (it provides the required `aveva-rnd` and `aveva-core` plugins).
   Add this repository so the entry looks like:

   ```jsonc
   "chat.plugins.marketplaces": [
       "https://github.com/AVEVA-Copilot-Access/aveva-agent-plugins",
       "https://github.com/sidbhardwaj-aveva/ei-graphics-plugin"
   ]
   ```

3. Save the file, then press **`Ctrl+Shift+P`** → **Developer: Reload Window**.

4. Open the plugin picker and install **`aveva-ei-graphics`**.

## Shared session records

To share completed session bundles with the team, set this value before starting the agent:

```powershell
$env:EI_GRAPHICS_SHARE_PATH = "\\INHYDD1510\Share\ei-graphics-plugin-sessions"
```

The agent copies a completed session to this approved internal share. Leave the variable unset to
keep the session only on your computer.

## Existing installations

People who installed the previous version need this reset once. The previous plugin history was
replaced, so `git pull` cannot merge it with the current plugin. This replaces tracked files in
the installed plugin cache. It does not remove untracked files.

```powershell
git -C "$env:USERPROFILE\.vscode\agent-plugins\github.com\sidbhardwaj-aveva\ei-graphics-plugin" fetch origin
git -C "$env:USERPROFILE\.vscode\agent-plugins\github.com\sidbhardwaj-aveva\ei-graphics-plugin" reset --hard origin/main
```

Then press **`Ctrl+Shift+P`** → **Developer: Reload Window**. New installations do not need this
reset.

## Keeping the plugin up to date

VS Code installs the plugin into `~/.vscode/agent-plugins/`. That clone does not auto-update.
After new commits land on `origin/main`, pull in the installed copy:

```powershell
git -C "$env:USERPROFILE\.vscode\agent-plugins\github.com\sidbhardwaj-aveva\ei-graphics-plugin" pull
git -C "$env:USERPROFILE\.vscode\agent-plugins\github.com/AVEVA-Copilot-Access/aveva-agent-plugins" pull
```

Then press **`Ctrl+Shift+P`** → **Developer: Reload Window**.
