# Poor Man's Statusline

A lightweight, zero-dependency custom statusline for Claude Code that displays real-time usage limits, model availability, and context window information.

## Features

- **Real-time API usage tracking** - 5-hour and 7-day utilization limits
- **Per-model availability** - Separate limits for Opus and Sonnet models
- **Context window monitoring** - Track token usage with auto-compact warning at 80%
- **Smart caching** - 1-minute cache to minimize API calls
- **Color-coded indicators** - Green (≤50%), Yellow (51-80%), Red (>80%)
- **Git-aware** - Automatically displays current branch when in a repository
- **Performance optimized** - Fast execution with minimal overhead

## Screenshot

```
[claude-sonnet-4-5-20250929] alex@hostname:project (main)
  Opus: 18% | Sonnet: 13%
  5h: 32% | 7d: 18%
  CTX: 98.8K 49%
```

## How It Works

The statusline script fetches your current Claude API usage from Anthropic's OAuth endpoint and displays:

1. **Model-specific limits** - Opus uses overall 7-day limit, Sonnet has dedicated limit
2. **Time-based limits** - 5-hour and 7-day utilization percentages
3. **Context usage** - Current conversation tokens vs 200K window, with warning when approaching auto-compact threshold

All data is cached for 60 seconds to avoid hammering the API on every prompt.

## Prerequisites

- **Claude Code** - Must be installed and authenticated
- **jq** - JSON processor for parsing API responses
- **curl** - For making API requests
- **git** - For branch detection (optional, degrades gracefully)

### Installing jq

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Fedora
sudo dnf install jq
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/poor-mans-statusline.git
cd poor-mans-statusline
```

### 2. Copy script to Claude config directory

```bash
cp statusline.sh ~/.claude/
chmod +x ~/.claude/statusline.sh
```

### 3. Set up credentials

The script needs your Claude OAuth access token to fetch usage data.

#### Option A: If you already use Claude Code

Your credentials file already exists at `~/.claude/.credentials.json` and the script will use it automatically. No additional setup needed.

#### Option B: Manual setup

If the credentials file doesn't exist, you'll need to extract your access token from Claude Code:

1. Find your token in Claude Code's storage (location varies by platform)
2. Create credentials file:

```bash
cp credentials.json.example ~/.claude/.credentials.json
```

3. Edit `~/.claude/.credentials.json` and replace `YOUR_ACCESS_TOKEN_HERE` with your actual token:

```json
{
  "claudeAiOauth": {
    "accessToken": "your-actual-token-here"
  }
}
```

4. Secure the file:

```bash
chmod 600 ~/.claude/.credentials.json
```

### 4. Configure Claude Code

Add the statusline script to your Claude Code settings:

1. Open Claude Code settings
2. Find the "Statusline" configuration option
3. Set the path to: `~/.claude/statusline.sh`
4. Restart Claude Code

## Usage

Once configured, the statusline will automatically appear in your Claude Code interface. It updates every 60 seconds when the cache expires.

### Understanding the Display

```
[model-name] user@hostname:directory (branch)
  Model1: XX% | Model2: XX%
  5h: XX% | 7d: XX%
  CTX: XX.XK XX%
```

- **Line 1**: Current model, user, hostname, directory, and git branch
- **Line 2**: Model-specific limits (Opus uses overall 7d, Sonnet has dedicated limit)
- **Line 3**: Time-based usage limits (5-hour and 7-day rolling windows)
- **Line 4**: Context window usage (only shown when conversation exists)
  - Warning emoji (⚠️) appears when approaching 80% of 200K context window

### Color Coding

- **Green** - ≤50% utilization (healthy)
- **Yellow** - 51-80% utilization (moderate)
- **Red** - >80% utilization (approaching limit)
- **Gray** - Data unavailable or model limit doesn't apply

## Customization

Edit `~/.claude/statusline.sh` to customize behavior:

### Adjust Cache Duration

```bash
CACHE_TTL=60  # Change to desired seconds (default: 60)
```

Longer cache = fewer API calls but less frequent updates.

### Modify Context Window

```bash
CONTEXT_WINDOW=200000  # Adjust for different models
AUTO_COMPACT_THRESHOLD=160000  # 80% of context window
```

### Change Color Thresholds

In the `format_percentage()` function (around line 144):

```bash
if [ "$pct_int" -le 50 ]; then
    color="\033[1;32m"  # Green - change 50 to adjust threshold
elif [ "$pct_int" -le 80 ]; then
    color="\033[1;33m"  # Yellow - change 80 to adjust threshold
else
    color="\033[1;31m"  # Red
fi
```

### Disable Context Display

Comment out lines 374-376 in the main display section:

```bash
# if [ -n "$context_result" ]; then
#     printf "  %b\n" "$context_result"
# fi
```

## Troubleshooting

### Statusline shows no usage data

**Problem**: Lines 2-4 are missing (only model/directory line shows).

**Solutions**:
1. Check credentials file exists: `ls -la ~/.claude/.credentials.json`
2. Verify token format: `jq . ~/.claude/.credentials.json`
3. Test API manually:
   ```bash
   curl -s -H "Authorization: Bearer $(jq -r '.claudeAiOauth.accessToken' ~/.claude/.credentials.json)" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" | jq .
   ```
4. Check cache file permissions: `ls -la /tmp/claude-usage-cache.json`

### Usage data shows "--" for models

**Problem**: Model limits show gray dashes instead of percentages.

**Explanation**: This is normal. When `seven_day_opus` is `null` (Opus has no dedicated limit anymore), Opus displays the overall 7-day limit. If Sonnet shows "--", it means the API didn't return `seven_day_sonnet` data.

### Script runs slowly

**Problem**: Noticeable delay when statusline updates.

**Solutions**:
1. Increase cache TTL to reduce API calls: `CACHE_TTL=300`
2. Check network latency: `time curl -s https://api.anthropic.com/api/oauth/usage`
3. Verify jq is installed: `which jq`

### Context shows 0 or missing

**Problem**: CTX line is missing or shows 0%.

**Explanation**: Context data only appears during active conversations with Claude. It reads from the transcript file. If you just started Claude Code or started a new conversation, there's no context yet.

### Git branch not showing

**Problem**: Branch name missing even though you're in a git repo.

**Solutions**:
1. Verify git is installed: `which git`
2. Check you're in a git repo: `git status`
3. Ensure current directory is within repo: `pwd`

### Permission denied errors

**Problem**: Script fails with permission errors.

**Solutions**:
1. Make script executable: `chmod +x ~/.claude/statusline.sh`
2. Check credentials file permissions: `chmod 600 ~/.claude/.credentials.json`
3. Verify cache directory is writable: `ls -ld /tmp`

## How Usage Limits Work (as of November 2025)

Anthropic provides three types of usage limits:

1. **5-hour limit** (`five_hour`) - Short-term usage across all models
2. **7-day overall limit** (`seven_day`) - Used by Opus and as fallback
3. **7-day Sonnet limit** (`seven_day_sonnet`) - Dedicated limit for Sonnet models

The statusline displays:
- **Opus**: Uses overall 7-day limit (since `seven_day_opus` is null after November 24, 2025 changes)
- **Sonnet**: Uses dedicated `seven_day_sonnet` limit when available, falls back to overall if not

## Security Notes

**Never commit these files to version control:**
- `~/.claude/.credentials.json` - Contains your OAuth access token
- `/tmp/claude-usage-cache.json` - May contain personal usage data
- Screenshots showing your username, hostname, or directory names

This repository's `.gitignore` is configured to prevent accidental commits of sensitive files.

## Contributing

Contributions welcome! Please ensure:
- No credentials or tokens in commits
- Shellcheck passes with no warnings
- All changes tested on macOS and Linux
- Update README if adding features

## License

MIT License - See LICENSE file for details

## Credits

Created for the Claude Code community by users who wanted better visibility into their API usage without switching contexts.

## Changelog

### 2025-01 (Current)
- Added separate Opus/Sonnet model limits
- Reduced cache TTL from 5 minutes to 1 minute
- Improved visual hierarchy with indentation
- Fixed model name spacing (removed fixed-width padding)
- Updated display order: Models → Usage → Context

### Initial Release
- Basic usage tracking (5h and 7d limits)
- Context window monitoring
- Color-coded percentages
- Git branch detection
