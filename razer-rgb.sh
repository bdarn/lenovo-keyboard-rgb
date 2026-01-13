#!/bin/bash
#
# Razer Keyboard RGB Controller
# Uses sysfs interface for Razer keyboards (via razerkbd driver)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Razer keyboard identification
VENDOR_ID="1532"
PRODUCT_ID="0228"  # BlackWidow Elite
RAZER_DEVICE=""

# Color database (same as Legion keyboard)
declare -A COLORS=(
    ["red"]="255,0,0"
    ["green"]="0,255,0"
    ["blue"]="0,0,255"
    ["white"]="255,255,255"
    ["cyan"]="0,255,255"
    ["magenta"]="255,0,255"
    ["yellow"]="255,255,0"
    ["orange"]="255,165,0"
    ["purple"]="128,0,128"
    ["pink"]="255,192,203"
    ["off"]="0,0,0"
)

#=============================================================================
# HELPER FUNCTIONS
#=============================================================================

msg_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }
msg_info() { echo -e "\033[34m[INFO]\033[0m $*"; }
msg_ok() { echo -e "\033[32m[OK]\033[0m $*"; }

# Parse color (same logic as Legion keyboard)
parse_color() {
    local input=$1

    # Check if it's a preset color name
    if [ -n "${COLORS[$input]:-}" ]; then
        echo "${COLORS[$input]}"
        return 0
    fi

    # Check if it's already RGB format (255,0,0)
    if [[ $input =~ ^([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})$ ]]; then
        echo "$input"
        return 0
    fi

    # Check if it's hex format (#FF0000 or FF0000)
    if [[ $input =~ ^#?([0-9a-fA-F]{6})$ ]]; then
        local hex="${BASH_REMATCH[1]}"
        local r=$((16#${hex:0:2}))
        local g=$((16#${hex:2:2}))
        local b=$((16#${hex:4:2}))
        echo "$r,$g,$b"
        return 0
    fi

    msg_error "Invalid color: $input"
    return 1
}

#=============================================================================
# KEYBOARD DETECTION
#=============================================================================

find_razer_keyboard() {
    # Find the Razer keyboard sysfs path with RGB controls
    # RGB controls are on interface 1.2, so we need to find the device with matrix_effect_static
    for device in /sys/bus/hid/drivers/razerkbd/*; do
        [ -d "$device" ] || continue
        [ -e "$device/uevent" ] || continue

        # Check if this is our keyboard
        if grep -q "HID_ID=0003:0000${VENDOR_ID^^}:0000${PRODUCT_ID^^}" "$device/uevent" 2>/dev/null; then
            # Check if this interface has RGB controls
            if [ -e "$device/matrix_effect_static" ]; then
                RAZER_DEVICE="$device"
                msg_info "Found Razer keyboard with RGB: $(basename $device)"
                return 0
            fi
        fi
    done

    msg_error "Razer keyboard RGB interface not found"
    msg_info "Looking for vendor:$VENDOR_ID, product:$PRODUCT_ID with RGB controls"
    return 1
}

check_permissions() {
    if [ ! -w "$RAZER_DEVICE/matrix_effect_static" ]; then
        msg_error "No write permission to Razer keyboard"
        msg_info "Run: sudo cp 99-razer-keyboard.rules /etc/udev/rules.d/"
        msg_info "Then: sudo udevadm control --reload-rules && sudo udevadm trigger"
        return 1
    fi
    return 0
}

#=============================================================================
# RGB CONTROL
#=============================================================================

# Set static color
cmd_static() {
    local color=$1
    local brightness=${2:-255}  # Default: max brightness (0-255)

    # Parse color to RGB
    local rgb
    rgb=$(parse_color "$color") || return 1
    IFS=',' read -r r g b <<< "$rgb"

    msg_info "Setting static: RGB($r,$g,$b) brightness=$brightness"

    # Set brightness (0-255)
    echo "$brightness" > "$RAZER_DEVICE/matrix_brightness"

    # Set static color (RGB as binary data)
    printf "\x$(printf '%02x' $r)\x$(printf '%02x' $g)\x$(printf '%02x' $b)" > "$RAZER_DEVICE/matrix_effect_static"
}

# Set breathing effect
cmd_breath() {
    local color=$1
    local brightness=${2:-255}

    local rgb
    rgb=$(parse_color "$color") || return 1
    IFS=',' read -r r g b <<< "$rgb"

    msg_info "Setting breathing effect: RGB($r,$g,$b)"

    echo "$brightness" > "$RAZER_DEVICE/matrix_brightness"
    printf "\x$(printf '%02x' $r)\x$(printf '%02x' $g)\x$(printf '%02x' $b)" > "$RAZER_DEVICE/matrix_effect_breath"
}

# Set spectrum effect (rainbow cycling)
cmd_spectrum() {
    local brightness=${1:-255}

    msg_info "Setting spectrum effect (rainbow)"

    echo "$brightness" > "$RAZER_DEVICE/matrix_brightness"
    echo "1" > "$RAZER_DEVICE/matrix_effect_spectrum"
}

# Set wave effect
cmd_wave() {
    local brightness=${1:-255}
    local direction=${2:-1}  # 1=right, 2=left

    msg_info "Setting wave effect"

    echo "$brightness" > "$RAZER_DEVICE/matrix_brightness"
    echo "$direction" > "$RAZER_DEVICE/matrix_effect_wave"
}

# Set reactive effect (lights up on keypress)
cmd_reactive() {
    local color=$1
    local brightness=${2:-255}
    local speed=${3:-2}  # 1=fast, 2=medium, 3=slow

    local rgb
    rgb=$(parse_color "$color") || return 1
    IFS=',' read -r r g b <<< "$rgb"

    msg_info "Setting reactive effect: RGB($r,$g,$b)"

    echo "$brightness" > "$RAZER_DEVICE/matrix_brightness"
    printf "\x$(printf '%02x' $speed)\x$(printf '%02x' $r)\x$(printf '%02x' $g)\x$(printf '%02x' $b)" > "$RAZER_DEVICE/matrix_effect_reactive"
}

# Turn off lights
cmd_off() {
    msg_info "Turning off keyboard lights"
    echo "1" > "$RAZER_DEVICE/matrix_effect_none"
}

#=============================================================================
# COMMAND LINE INTERFACE
#=============================================================================

show_help() {
    cat << EOF
Razer Keyboard RGB Controller

Usage:
  $0 static <color> [brightness]
  $0 breath <color> [brightness]
  $0 spectrum [brightness]
  $0 wave [brightness] [direction]
  $0 reactive <color> [brightness] [speed]
  $0 off
  $0 help

Commands:
  static <color>              Set solid color
  breath <color>              Breathing effect with color
  spectrum                    Rainbow cycling effect
  wave                        Wave effect
  reactive <color>            Lights up on keypress
  off                         Turn off all lights

Examples:
  $0 static red               # Red keyboard
  $0 static "#e20342" 255     # Pink at max brightness
  $0 breath blue 200          # Breathing blue
  $0 spectrum                 # Rainbow effect
  $0 wave 255 1               # Wave effect (right)
  $0 reactive cyan            # Cyan reactive
  $0 off                      # Lights off

Colors: red, green, blue, white, cyan, magenta, yellow, orange, purple, pink
Brightness: 0-255 (default: 255)
Wave Direction: 1=right, 2=left
Reactive Speed: 1=fast, 2=medium, 3=slow

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    local command=${1:-help}

    # Find keyboard
    find_razer_keyboard || exit 1
    check_permissions || exit 1

    # Execute command
    case "$command" in
        static)
            [ -n "${2:-}" ] || { msg_error "Missing color"; show_help; exit 1; }
            cmd_static "$2" "${3:-255}"
            ;;
        breath)
            [ -n "${2:-}" ] || { msg_error "Missing color"; show_help; exit 1; }
            cmd_breath "$2" "${3:-255}"
            ;;
        spectrum)
            cmd_spectrum "${2:-255}"
            ;;
        wave)
            cmd_wave "${2:-255}" "${3:-1}"
            ;;
        reactive)
            [ -n "${2:-}" ] || { msg_error "Missing color"; show_help; exit 1; }
            cmd_reactive "$2" "${3:-255}" "${4:-2}"
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

    msg_ok "Done!"
}

main "$@"
