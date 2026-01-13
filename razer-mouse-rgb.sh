#!/bin/bash
#
# Razer Mouse RGB Controller
# Controls LED on Razer mice via OpenRazer sysfs interface
# Supports green-only LED (DeathAdder Essential)
#

set -euo pipefail

# Mouse identification
VENDOR_ID="1532"
PRODUCT_ID="0098"  # DeathAdder Essential
RAZER_DEVICE=""

#=============================================================================
# MOUSE THEME CONFIGURATION
# Add theme names below to enable green LED for specific themes.
# By default, mouse LED is OFF for all themes except those listed here.
# NOTE: You can also configure this in rgb-config.conf
#=============================================================================
MOUSE_ENABLED_THEMES=(
    "hackerman"
    # Add more themes here, one per line:
    # "mars"
    # "aetheria"
)

# Load config file if it exists (overrides defaults above)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/rgb-config.conf" ]; then
    source "$SCRIPT_DIR/rgb-config.conf"
fi

# Color database (only green and off needed for single-color LED)
declare -A COLORS=(
    ["green"]="0,255,0"
    ["off"]="0,0,0"
)

#=============================================================================
# HELPER FUNCTIONS
#=============================================================================

msg_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }
msg_info() { echo -e "\033[34m[INFO]\033[0m $*"; }
msg_ok() { echo -e "\033[32m[OK]\033[0m $*"; }

# Parse color (simplified for green-only LED)
parse_color() {
    local input=$1

    # Check if it's a preset color name
    if [ -n "${COLORS[$input]:-}" ]; then
        echo "${COLORS[$input]}"
        return 0
    fi

    # Check if it's already RGB format (0,255,0)
    if [[ $input =~ ^([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})$ ]]; then
        echo "$input"
        return 0
    fi

    # For any other input, default to green (since LED is green-only)
    echo "0,255,0"
    return 0
}

#=============================================================================
# MOUSE DETECTION
#=============================================================================

find_razer_mouse() {
    # Check both razermouse and razerkbd drivers (mouse may be under either)
    for driver_path in /sys/bus/hid/drivers/razermouse /sys/bus/hid/drivers/razerkbd; do
        [ -d "$driver_path" ] || continue

        for device in "$driver_path"/*; do
            [ -d "$device" ] || continue
            [ -e "$device/uevent" ] || continue

            # Check if this is our mouse
            if grep -q "HID_ID=0003:0000${VENDOR_ID^^}:0000${PRODUCT_ID^^}" "$device/uevent" 2>/dev/null; then
                # Check if this interface has LED controls (logo LED)
                if [ -e "$device/logo_matrix_effect_static" ] || [ -e "$device/logo_led_state" ]; then
                    RAZER_DEVICE="$device"
                    msg_info "Found Razer mouse with LED: $(basename $device)"
                    return 0
                fi
            fi
        done
    done

    msg_error "Razer mouse LED interface not found"
    msg_info "Looking for vendor:$VENDOR_ID, product:$PRODUCT_ID with LED controls"
    return 1
}

check_permissions() {
    # Check for logo_matrix_effect_static first (preferred)
    if [ -e "$RAZER_DEVICE/logo_matrix_effect_static" ]; then
        if [ ! -w "$RAZER_DEVICE/logo_matrix_effect_static" ]; then
            msg_error "No write permission to Razer mouse LED"
            msg_info "Run: sudo cp 99-razer-mouse.rules /etc/udev/rules.d/"
            msg_info "Then: sudo udevadm control --reload-rules && sudo udevadm trigger"
            return 1
        fi
    elif [ -e "$RAZER_DEVICE/logo_led_state" ]; then
        if [ ! -w "$RAZER_DEVICE/logo_led_state" ]; then
            msg_error "No write permission to Razer mouse LED"
            msg_info "Run: sudo cp 99-razer-mouse.rules /etc/udev/rules.d/"
            msg_info "Then: sudo udevadm control --reload-rules && sudo udevadm trigger"
            return 1
        fi
    fi
    return 0
}

#=============================================================================
# LED CONTROL
#=============================================================================

# Set static color
cmd_static() {
    local color=${1:-green}
    local brightness=${2:-255}  # Default: max brightness (0-255)

    # Parse color to RGB
    local rgb
    rgb=$(parse_color "$color") || return 1
    IFS=',' read -r r g b <<< "$rgb"

    msg_info "Setting static: RGB($r,$g,$b) brightness=$brightness"

    # Set brightness if attribute exists
    if [ -e "$RAZER_DEVICE/logo_led_brightness" ]; then
        echo "$brightness" > "$RAZER_DEVICE/logo_led_brightness"
    fi

    # Set static color (RGB as binary data)
    if [ -e "$RAZER_DEVICE/logo_matrix_effect_static" ]; then
        printf "\x$(printf '%02x' $r)\x$(printf '%02x' $g)\x$(printf '%02x' $b)" > "$RAZER_DEVICE/logo_matrix_effect_static"
    elif [ -e "$RAZER_DEVICE/logo_led_state" ]; then
        # Fallback for devices without matrix effect
        echo "1" > "$RAZER_DEVICE/logo_led_state"
    fi

    msg_ok "Mouse LED set to green"
}

# Turn off LED
cmd_off() {
    msg_info "Turning off mouse LED"

    if [ -e "$RAZER_DEVICE/logo_matrix_effect_none" ]; then
        echo "1" > "$RAZER_DEVICE/logo_matrix_effect_none"
    elif [ -e "$RAZER_DEVICE/logo_led_state" ]; then
        echo "0" > "$RAZER_DEVICE/logo_led_state"
    elif [ -e "$RAZER_DEVICE/logo_led_brightness" ]; then
        echo "0" > "$RAZER_DEVICE/logo_led_brightness"
    fi

    msg_ok "Mouse LED off"
}

# Check if mouse should be enabled for a theme
cmd_should_enable() {
    local theme=$1

    for enabled_theme in "${MOUSE_ENABLED_THEMES[@]}"; do
        if [ "$theme" = "$enabled_theme" ]; then
            return 0  # Enable mouse
        fi
    done

    return 1  # Disable mouse
}

#=============================================================================
# COMMAND LINE INTERFACE
#=============================================================================

show_help() {
    cat << EOF
Razer Mouse RGB Controller

Usage:
  $0 static [color] [brightness]   Set static color (default: green, 255)
  $0 off                           Turn off LED
  $0 should-enable <theme>         Check if theme should enable LED (exit 0=yes, 1=no)
  $0 help                          Show this help

Color:
  green                            Green LED (default)
  off                              Turn off

Brightness:
  0-255                            LED brightness (default: 255)

Theme Configuration:
  Mouse LED is enabled only for specific themes.
  Current enabled themes: ${MOUSE_ENABLED_THEMES[*]}

  To add more themes, edit MOUSE_ENABLED_THEMES array in this script.

Examples:
  $0 static green 255              # Full brightness green
  $0 static green 128              # Half brightness green
  $0 off                           # Turn off LED
  $0 should-enable hackerman       # Check if hackerman theme enables LED

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local command=${1:-help}

    # Special command that doesn't need device detection
    if [ "$command" = "should-enable" ]; then
        [ -n "${2:-}" ] || { msg_error "Missing theme name"; exit 1; }
        cmd_should_enable "$2"
        exit $?
    fi

    # For all other commands, find and check device
    find_razer_mouse || exit 1
    check_permissions || exit 1

    case "$command" in
        static)
            cmd_static "${2:-green}" "${3:-255}"
            ;;
        off)
            cmd_off
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
