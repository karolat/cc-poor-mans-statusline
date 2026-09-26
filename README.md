# Poor Man's Statusline

Lightweight custom statusline for Claude Code with Powerline-style segments, usage limits, reset timers, and context monitoring.

## Features

- **Powerline-style segments** with colored backgrounds and smooth arrow transitions
- **Reset timers** showing countdown AND absolute time until limits reset (e.g., "2h11m @ 10pm")
- 5-hour and 7-day usage limits, read from the data Claude Code passes to the statusline (no credentials or API calls)
- Model name with current effort level (e.g., `opus-5-5-high`)
- Context window monitoring with auto-compact warning
- Automatically adapts to your plan (shows 7-day limits only when present)

## Example Output

**With 7-day limits:**
```
 opus-5-5-high  project  main
 5h 27%  2h11m @ 10pm   7d 34%  4d2h @ Dec 2
 CTX 35.2K 17%
```

**5-hour limit only:**
```
 sonnet-5-medium  project  main
 5h 45%  3h30m @ 2pm
```

**Color scheme:**
Dark purple theme: model name, project, branch, usage limits and reset countdowns each get their own shade; context info is gray.

## Prerequisites

- Claude Code (a version that passes `rate_limits` to the statusline; usage rows are hidden otherwise)
- `jq` - JSON processor
- Terminal with 256-color support

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

## Installation

```bash
# 1. Clone the repository
git clone https://github.com/karolat/cc-poor-mans-statusline.git
cd cc-poor-mans-statusline

# 2. Make the script executable
chmod +x statusline.sh
```

### 3. Configure Claude Code

Add the statusline to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/cc-poor-mans-statusline/statusline.sh"
  }
}
```

Replace `/path/to/` with the actual location where you cloned the repo. For example:
- `~/Documents/GitHub/cc-poor-mans-statusline/statusline.sh`
- `~/projects/cc-poor-mans-statusline/statusline.sh`

> **Tip:** You can also use `~` for your home directory in the path.

## Customization

Edit `statusline.sh`:

```bash
CONTEXT_WINDOW=200000  # Model context window size
AUTO_COMPACT_THRESHOLD=160000  # Warning threshold (80%)
```

## Troubleshooting

**No usage data showing?**
- Usage limits come from the `rate_limits` field Claude Code sends to the statusline. It may be missing until the first response of a session, or on older Claude Code versions (update with `claude update`)

**Context not showing?**
- Context only appears during active conversations

**Powerline arrows not rendering?**
- Ensure your terminal supports Unicode (U+E0B0)
- Most modern terminals work out of the box

## Security

The script never reads your credentials or makes network requests. Everything it shows comes from the JSON Claude Code pipes to it, plus `git` for the branch name.
