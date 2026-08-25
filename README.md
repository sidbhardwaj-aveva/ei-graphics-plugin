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

## Keeping the plugin up to date

VS Code installs the plugin into `~/.vscode/agent-plugins/`. That clone does not auto-update.
After new commits land on `origin/main`, pull in the installed copy:

```powershell
git -C "$env:USERPROFILE\.vscode\agent-plugins\github.com\sidbhardwaj-aveva\ei-graphics-plugin" pull
```

Then press **`Ctrl+Shift+P`** → **Developer: Reload Window**.

