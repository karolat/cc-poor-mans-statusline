#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Extract model information
model_name=$(echo "$input" | jq -r '.model.id // "unknown"')

# Extract directory information
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

# Get git branch if in a git repo (using -C to avoid cd)
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)

# Get basename of directory
dir_name=$(basename "$cwd")

# ============================================
# HELPER FUNCTIONS
# ============================================

# Function to calculate visible length (strip ANSI codes)
visible_length() {
    local string="$1"
    # Remove ANSI escape sequences (both \033 and \x1b formats) and count characters
    local clean
    clean=$(printf "%b" "$string" | sed $'s/\033\[[0-9;]*m//g')
    echo "${#clean}"
}

# Powerline arrow character (U+E0B0)
PL_ARROW=""

# Powerline segment: bg color, fg color, text, next segment's bg color
# Uses 256-color ANSI codes
pl_segment() {
    local bg=$1 fg=$2 text=$3 next_bg=$4
    # Background + foreground for text, then transition arrow
    printf "\033[48;5;%dm\033[38;5;%dm %s \033[48;5;%dm\033[38;5;%dm%s" \
        "$bg" "$fg" "$text" "$next_bg" "$bg" "$PL_ARROW"
}

# Final powerline segment (no arrow, just reset)
pl_segment_end() {
    local bg=$1 fg=$2 text=$3
    printf "\033[48;5;%dm\033[38;5;%dm %s \033[0m\033[38;5;%dm%s\033[0m" \
        "$bg" "$fg" "$text" "$bg" "$PL_ARROW"
}

# ============================================
# TIME FORMATTING FUNCTIONS
# ============================================

# Format countdown from epoch timestamp (e.g., "4h23m" or "2d5h")
# Args: $1 = epoch seconds, $2 = type ("5h" or "7d")
format_countdown() {
    local reset_epoch=$1
    local type=$2

    if [ -z "$reset_epoch" ]; then
        echo ""
        return
    fi

    local now_epoch
    now_epoch=$(date +%s)
    local diff=$((reset_epoch - now_epoch))

    # If already past, show 0
    if [ "$diff" -le 0 ]; then
        echo "0m"
        return
    fi

    # Format based on type
    if [ "$type" = "5h" ]; then
        # Short format: hours and minutes
        local hours=$((diff / 3600))
        local mins=$(((diff % 3600) / 60))
        if [ "$hours" -gt 0 ]; then
            echo "${hours}h${mins}m"
        else
            echo "${mins}m"
        fi
    else
        # Long format: days and hours
        local days=$((diff / 86400))
        local hours=$(((diff % 86400) / 3600))
        if [ "$days" -gt 0 ]; then
            echo "${days}d${hours}h"
        else
            echo "${hours}h"
        fi
    fi
}

# Format absolute time from epoch timestamp (e.g., "6PM" or "Dec 5")
# Args: $1 = epoch seconds, $2 = type ("5h" or "7d")
format_absolute_time() {
    local epoch=$1
    local type=$2

    if [ -z "$epoch" ]; then
        echo ""
        return
    fi

    # Format the epoch in local time
    if [ "$type" = "5h" ]; then
        # Short-term: show time like "6pm" or "6:30pm"
        local mins
        mins=$(date -r "$epoch" "+%M" 2>/dev/null)
        local result
        if [ "$mins" = "00" ]; then
            result=$(date -r "$epoch" "+%-I%p" 2>/dev/null)
        else
            result=$(date -r "$epoch" "+%-I:%M%p" 2>/dev/null)
        fi
        # Convert to lowercase and remove periods (AM/PM → am/pm)
        echo "$result" | tr '[:upper:]' '[:lower:]' | sed 's/\.//g'
    else
        # Long-term: show date like "Dec 5"
        date -r "$epoch" "+%b %-d" 2>/dev/null
    fi
}

# ============================================
# CONTEXT USAGE FUNCTIONS
# ============================================

CONTEXT_WINDOW=200000  # Claude Sonnet 4.5 context window
AUTO_COMPACT_THRESHOLD=160000  # 80% of context window

# Function to format percentage with color coding
format_percentage() {
    local percentage=$1

    # Convert percentage to integer
    local pct_int=${percentage%.*}

    # Choose color based on percentage
    local color
    if [ "$pct_int" -le 50 ]; then
        color="\033[1;32m"  # Green
    elif [ "$pct_int" -le 80 ]; then
        color="\033[1;33m"  # Yellow
    else
        color="\033[1;31m"  # Red
    fi

    # Return colored percentage only (no bar)
    printf "${color}%d%%\033[0m" "$pct_int"
}

# Function to format token count (e.g., 35234 → "35.2K")
format_token_count() {
    local tokens=$1

    if [ -z "$tokens" ] || [ "$tokens" -eq 0 ]; then
        echo "0"
        return
    fi

    # Convert to K format if >= 1000
    if [ "$tokens" -ge 1000 ]; then
        # Calculate with one decimal place
        local k_value
        k_value=$(echo "scale=1; $tokens / 1000" | bc 2>/dev/null)
        echo "${k_value}K"
    else
        echo "$tokens"
    fi
}

# Function to calculate context tokens from transcript
calculate_context_tokens() {
    local transcript_path="$1"

    # Check if transcript exists
    if [ ! -f "$transcript_path" ]; then
        return 1
    fi

    # Read last 100 lines in reverse, find first valid usage
    local context_tokens=0
    while IFS= read -r line; do
        # Skip sidechain and error messages
        if echo "$line" | grep -q '"isSidechain":true'; then
            continue
        fi
        if echo "$line" | grep -q '"isApiErrorMessage":true'; then
            continue
        fi

        # Check if line has usage object
        if echo "$line" | grep -q '"usage":{'; then
            # Extract tokens
            local input_tokens
            input_tokens=$(echo "$line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)
            local cache_read
            cache_read=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)
            local cache_create
            cache_create=$(echo "$line" | jq -r '.message.usage.cache_creation_input_tokens // 0' 2>/dev/null)

            # Calculate context (input side only)
            context_tokens=$((input_tokens + cache_read + cache_create))
            break  # Found most recent, stop
        fi
    done < <(tail -n 100 "$transcript_path" 2>/dev/null | tail -r 2>/dev/null || tail -n 100 "$transcript_path" 2>/dev/null | awk '{lines[NR]=$0} END {for(i=NR;i>0;i--) print lines[i]}')

    echo "$context_tokens"
}

# Function to format context display (returns string)
format_context() {
    # Extract transcript path from input
    local transcript_path
    transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

    if [ -z "$transcript_path" ]; then
        echo ""  # Return empty string if no transcript
        return
    fi

    # Calculate context tokens
    local context_tokens
    context_tokens=$(calculate_context_tokens "$transcript_path")

    if [ -z "$context_tokens" ] || [ "$context_tokens" -eq 0 ]; then
        echo ""  # Return empty string if no context data
        return
    fi

    # Calculate percentage
    local percentage
    percentage=$((context_tokens * 100 / CONTEXT_WINDOW))

    # Format token count
    local formatted_tokens
    formatted_tokens=$(format_token_count "$context_tokens")

    # Check if approaching auto-compact threshold (> 80%)
    local warning=""
    if [ "$context_tokens" -gt "$AUTO_COMPACT_THRESHOLD" ]; then
        warning=" ⚠️"
    fi

    # Build and return context string
    local ctx_pct
    ctx_pct=$(format_percentage "$percentage")
    printf "CTX: %s %s%s" "$formatted_tokens" "$ctx_pct" "$warning"
}

# ============================================
# BUILD THE POWERLINE STATUS LINE
# ============================================

# Color definitions (256-color palette) - Dark theme optimized
C_PURPLE=97    # Dusty purple - Model name, Opus
C_SLATE=54     # Very dark purple - Project, Usage limits
C_DARK=53      # Darkest purple - Branch
C_STEEL=55     # Dark purple-blue - Reset times, Sonnet
C_GRAY=238     # Very dark gray - Context
C_WHITE=252    # Off-white text
C_BLACK=232    # Near-black text

# Shorten model name (e.g., "claude-sonnet-4-5-20250929" → "sonnet-4-5")
short_model=$(echo "$model_name" | sed 's/^claude-//' | sed 's/-[0-9]\{8\}$//')
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
[ -n "$effort_level" ] && short_model="${short_model}-${effort_level}"

# ============================================
# ROW 1: Model → Project → Branch
# ============================================
row1=""
if [ -n "$branch" ]; then
    row1=$(pl_segment $C_PURPLE $C_WHITE "$short_model" $C_SLATE)
    row1="${row1}$(pl_segment $C_SLATE $C_WHITE "$dir_name" $C_DARK)"
    row1="${row1}$(pl_segment_end $C_DARK $C_WHITE "$branch")"
else
    row1=$(pl_segment $C_PURPLE $C_WHITE "$short_model" $C_SLATE)
    row1="${row1}$(pl_segment_end $C_SLATE $C_WHITE "$dir_name")"
fi
printf "%b\n" "$row1"

# ============================================
# ROW 2: Usage Limits with Reset Times
# ============================================
# Usage limits come straight from Claude Code's statusline input (no API call needed)
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$five_hour" ]; then
    # Format 5h percentage
    five_h_int=${five_hour%.*}

    # Build 5h reset info
    five_h_countdown=$(format_countdown "$five_hour_resets" "5h")
    five_h_absolute=$(format_absolute_time "$five_hour_resets" "5h")

    row2=""
    if [ -n "$seven_day" ]; then
        # Full display: 5h and 7d
        seven_d_int=${seven_day%.*}
        seven_d_countdown=$(format_countdown "$seven_day_resets" "7d")
        seven_d_absolute=$(format_absolute_time "$seven_day_resets" "7d")

        # Build 5h segment
        if [ -n "$five_h_countdown" ] && [ -n "$five_h_absolute" ]; then
            row2=$(pl_segment $C_SLATE $C_WHITE "5h ${five_h_int}%" $C_STEEL)
            row2="${row2}$(pl_segment $C_STEEL $C_WHITE "${five_h_countdown} @ ${five_h_absolute}" $C_SLATE)"
        else
            row2=$(pl_segment $C_SLATE $C_WHITE "5h ${five_h_int}%" $C_SLATE)
        fi

        # Build 7d segment
        if [ -n "$seven_d_countdown" ] && [ -n "$seven_d_absolute" ]; then
            row2="${row2}$(pl_segment $C_SLATE $C_WHITE "7d ${seven_d_int}%" $C_STEEL)"
            row2="${row2}$(pl_segment_end $C_STEEL $C_WHITE "${seven_d_countdown} @ ${seven_d_absolute}")"
        else
            row2="${row2}$(pl_segment_end $C_SLATE $C_WHITE "7d ${seven_d_int}%")"
        fi
    else
        # Basic tier: only 5h
        if [ -n "$five_h_countdown" ] && [ -n "$five_h_absolute" ]; then
            row2=$(pl_segment $C_SLATE $C_WHITE "5h ${five_h_int}%" $C_STEEL)
            row2="${row2}$(pl_segment_end $C_STEEL $C_WHITE "${five_h_countdown} @ ${five_h_absolute}")"
        else
            row2=$(pl_segment_end $C_SLATE $C_WHITE "5h ${five_h_int}%")
        fi
    fi

    printf "%b\n" "$row2"
fi

# ============================================
# ROW 3: Context
# ============================================
row3=""
has_row3=false

# Context usage
context_result=$(format_context)
if [ -n "$context_result" ]; then
    # Extract just the values from the formatted context
    ctx_tokens=$(echo "$context_result" | sed 's/CTX: //' | awk '{print $1}')
    ctx_pct=$(echo "$context_result" | grep -oE '[0-9]+%')
    ctx_warning=""
    if echo "$context_result" | grep -q "⚠️"; then
        ctx_warning=" ⚠️"
    fi

    if [ "$has_row3" = true ]; then
        row3="${row3}$(pl_segment_end $C_GRAY $C_WHITE "CTX ${ctx_tokens} ${ctx_pct}${ctx_warning}")"
    else
        has_row3=true
        row3=$(pl_segment_end $C_GRAY $C_WHITE "CTX ${ctx_tokens} ${ctx_pct}${ctx_warning}")
    fi
fi

if [ "$has_row3" = true ]; then
    printf "%b\n" "$row3"
fi
