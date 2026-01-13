#!/bin/bash
#
# RGB Sync - Control multiple RGB devices simultaneously
#
# Sync Legion laptop keyboard, Razer external keyboard, and Razer mouse
# with manual colors or Omarchy themes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEGION_RGB="$SCRIPT_DIR/legion-rgb.sh"
RAZER_RGB="$SCRIPT_DIR/razer-rgb.sh"
MOUSE_RGB="$SCRIPT_DIR/razer-mouse-rgb.sh"
THEME_DIR_CUSTOM="$HOME/.config/omarchy/themes"
THEME_DIR_DEFAULT="$HOME/.local/share/omarchy/themes"

# Configuration
BRIGHTNESS="${RGB_BRIGHTNESS:-255}"              # Brightness (0-255 for Razer sysfs, 1-2 for Legion)

# Color output
msg_info() { echo -e "\033[34m[INFO]\033[0m $*"; }
msg_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }
msg_ok() { echo -e "\033[32m[OK]\033[0m $*"; }

#=============================================================================
# THEME DETECTION
#=============================================================================

# Find theme path in either custom or default directory
find_theme_path() {
    local theme=$1

    # Check custom themes first
    if [ -d "$THEME_DIR_CUSTOM/$theme" ]; then
        echo "$THEME_DIR_CUSTOM/$theme"
        return 0
    fi

    # Check default themes
    if [ -d "$THEME_DIR_DEFAULT/$theme" ]; then
        echo "$THEME_DIR_DEFAULT/$theme"
        return 0
    fi

    return 1
}

# Get current Omarchy theme
get_current_theme() {
    # Method 1: Check if there's a current_theme file
    if [ -f "$HOME/.config/omarchy/current_theme" ]; then
        cat "$HOME/.config/omarchy/current_theme"
        return 0
    fi

    # Method 2: Check which theme's hyprland.conf is sourced
    local active=$(grep "source.*themes" "$HOME/.config/hypr/hyprland.conf" 2>/dev/null | \
                   grep -oP 'themes/\K[^/]+' | head -1)

    if [ -n "$active" ]; then
        echo "$active"
        return 0
    fi

    return 1
}

#=============================================================================
# RGB CONTROL
#=============================================================================

# Set colors for both keyboards
set_keyboards() {
    local color=$1
    local context=$2

    msg_info "$context - Setting keyboards to: $color"

    # Set Legion laptop keyboard
    if [ -x "$LEGION_RGB" ]; then
        # Legion uses brightness 1=low, 2=high
        local legion_brightness=2
        "$LEGION_RGB" static "$color" $legion_brightness &>/dev/null || msg_error "Failed to set Legion keyboard"
    fi

    # Set Razer external keyboard
    if [ -x "$RAZER_RGB" ]; then
        "$RAZER_RGB" static "$color" $BRIGHTNESS &>/dev/null || msg_error "Failed to set Razer keyboard"
    fi

    # Turn mouse off (manual color mode doesn't use mouse)
    if [ -x "$MOUSE_RGB" ]; then
        "$MOUSE_RGB" off &>/dev/null || true
    fi

    msg_ok "Keyboards updated!"
}

# Sync with Omarchy theme
sync_with_theme() {
    local theme=$1

    msg_info "Syncing keyboards with Omarchy theme: $theme"

    # Extract theme color from config files
    local theme_path
    theme_path=$(find_theme_path "$theme") || {
        msg_error "Theme not found: $theme"
        return 1
    }

    local color=""

    # Try hyprland.conf first (look for any rgb() color)
    if [ -f "$theme_path/hyprland.conf" ]; then
        color=$(grep -oP 'rgba?\(\K[0-9a-fA-F]+' "$theme_path/hyprland.conf" | head -1 | cut -c1-6)
    fi

    # Fallback to waybar.css
    if [ -z "$color" ] && [ -f "$theme_path/waybar.css" ]; then
        color=$(grep -E "@define-color|--accent|--primary" "$theme_path/waybar.css" | \
                grep -oP '#\K[0-9a-fA-F]{6}' | head -1)
    fi

    # Fallback to colors.toml (for source theme definitions)
    if [ -z "$color" ] && [ -f "$theme_path/colors.toml" ]; then
        color=$(grep "^accent" "$theme_path/colors.toml" | \
                grep -oP '#\K[0-9a-fA-F]{6}' | head -1)
    fi

    # Apply color to both keyboards
    if [ -n "$color" ]; then
        msg_info "Extracted theme color: #$color"

        # Legion keyboard (brightness 2 = high)
        if [ -x "$LEGION_RGB" ]; then
            "$LEGION_RGB" static "#$color" 2 || msg_error "Failed to set Legion keyboard"
        fi

        # Razer keyboard
        if [ -x "$RAZER_RGB" ]; then
            "$RAZER_RGB" static "#$color" $BRIGHTNESS || msg_error "Failed to set Razer keyboard"
        fi

        # Razer mouse (theme-aware)
        if [ -x "$MOUSE_RGB" ]; then
            if "$MOUSE_RGB" should-enable "$theme" &>/dev/null; then
                msg_info "Enabling mouse RGB (green) for theme: $theme"
                "$MOUSE_RGB" static green $BRIGHTNESS || true
            else
                "$MOUSE_RGB" off || true
            fi
        fi

        msg_ok "Theme sync complete!"
    else
        msg_error "Could not extract color from theme: $theme"
        return 1
    fi
}

#=============================================================================
# MAIN MODES
#=============================================================================

# Auto mode - sync with current theme (for startup)
cmd_auto() {
    local theme
    theme=$(get_current_theme)

    if [ -n "$theme" ]; then
        msg_info "Detected current theme: $theme"
        sync_with_theme "$theme"
    else
        msg_error "Could not detect current theme"
        return 1
    fi
}

# Manual mode - set both keyboards to a specific color
cmd_set() {
    local color=$1
    set_keyboards "$color" "MANUAL"
}

#=============================================================================
# CLI
#=============================================================================

show_help() {
    cat << EOF
RGB Sync - Control multiple RGB devices

Devices:
  - Legion laptop keyboard (ITE RGB controller)
  - Razer external keyboard (OpenRazer)
  - Razer mouse (OpenRazer, theme-specific)

Usage:
  $0 auto                     Sync with current Omarchy theme (for startup)
  $0 set <color>              Set keyboards to a color (mouse OFF)
  $0 theme <name>             Sync keyboards/mouse with Omarchy theme
  $0 help                     Show this help

Mouse Behavior:
  Mouse RGB is OFF by default for all themes.
  Theme-specific: Mouse LED enabled only for whitelisted themes.
  To configure: Edit MOUSE_ENABLED_THEMES in rgb-config.conf

Examples:
  $0 auto                     # Sync with current theme (use at startup)
  $0 set red                  # Keyboards red, mouse off
  $0 set "#e20342"            # Keyboards pink, mouse off
  $0 theme hackerman          # Keyboards sync, mouse green
  $0 theme catppuccin         # Keyboards sync, mouse off

Environment Variables:
  RGB_BRIGHTNESS              Razer brightness 0-255 (default: 255)

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local command=${1:-help}

    case "$command" in
        auto)
            cmd_auto
            ;;
        set)
            [ -n "${2:-}" ] || { msg_error "Missing color"; show_help; exit 1; }
            cmd_set "$2"
            ;;
        theme)
            [ -n "${2:-}" ] || { msg_error "Missing theme name"; show_help; exit 1; }
            sync_with_theme "$2"
            ;;
        help|--help|-h)
            show_help
            exit 0
            ;;
        *)
            msg_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
