#!/bin/bash
#
# Simplified Lenovo Legion RGB Keyboard Controller
# Much easier to read and understand!
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${LEGION_RGB_CONFIG:-$SCRIPT_DIR/rgb-config.conf}"

# Keyboard identification
VENDOR_ID="048d"
PRODUCT_IDS=("c101" "c965")
KEYBOARD_DEVICE=""

# Effect codes (from ITE protocol)
EFFECT_STATIC=0x01
EFFECT_BREATH=0x03
EFFECT_WAVE=0x04
EFFECT_HUE=0x06

# Simple color database
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

# Print colored messages
msg_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }
msg_info() { echo -e "\033[34m[INFO]\033[0m $*"; }
msg_ok() { echo -e "\033[32m[OK]\033[0m $*"; }

# Convert color name or hex to RGB values
# Input: "red" or "#FF0000" or "255,0,0"
# Output: "255,0,0"
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
        local r=$((16#${hex:0:2}))  # First 2 chars
        local g=$((16#${hex:2:2}))  # Middle 2 chars
        local b=$((16#${hex:4:2}))  # Last 2 chars
        echo "$r,$g,$b"
        return 0
    fi

    msg_error "Invalid color: $input"
    msg_info "Use: red, blue, #FF0000, or 255,0,0"
    return 1
}

#=============================================================================
# KEYBOARD DETECTION
#=============================================================================

# Find the Legion keyboard in /dev/hidraw*
find_keyboard() {
    # Prefer c965 (Device 8295) over c101 (Device 8910)
    # The c965 device with input0 controls the actual RGB lighting
    local preferred_device=""
    local fallback_device=""

    # Loop through all hidraw devices
    for hidraw_sys in /sys/class/hidraw/hidraw*; do
        # Check if this device has a uevent file
        local uevent="$hidraw_sys/device/uevent"
        [ -f "$uevent" ] || continue

        # Read the HID_ID line (example: HID_ID=0003:0000048D:0000C965)
        local hid_id=$(grep "^HID_ID=" "$uevent" | cut -d= -f2)
        [ -n "$hid_id" ] || continue

        # Extract vendor and product IDs from HID_ID
        local vendor=$(echo "$hid_id" | cut -d: -f2 | sed 's/^0000//' | tr '[:upper:]' '[:lower:]')
        local product=$(echo "$hid_id" | cut -d: -f3 | sed 's/^0000//' | tr '[:upper:]' '[:lower:]')

        # Check if this is a Legion keyboard
        if [ "$vendor" = "$VENDOR_ID" ]; then
            for target_product in "${PRODUCT_IDS[@]}"; do
                if [ "$product" = "$target_product" ]; then
                    local device_path="/dev/$(basename "$hidraw_sys")"

                    # Prefer c965 with input0 interface
                    local phys=$(grep "^HID_PHYS=" "$uevent" | cut -d= -f2)
                    if [ "$product" = "c965" ] && [[ "$phys" == *"input0"* ]]; then
                        preferred_device="$device_path"
                        break 2
                    elif [ "$product" = "c965" ]; then
                        # c965 but not input0
                        [ -z "$fallback_device" ] && fallback_device="$device_path"
                    elif [ "$product" = "c101" ]; then
                        # c101 is lowest priority
                        [ -z "$fallback_device" ] && fallback_device="$device_path"
                    fi
                fi
            done
        fi
    done

    # Use preferred device, otherwise fallback
    if [ -n "$preferred_device" ]; then
        KEYBOARD_DEVICE="$preferred_device"
        msg_info "Found keyboard: $KEYBOARD_DEVICE"
        return 0
    elif [ -n "$fallback_device" ]; then
        KEYBOARD_DEVICE="$fallback_device"
        msg_info "Found keyboard: $KEYBOARD_DEVICE"
        return 0
    fi

    msg_error "Legion keyboard not found"
    msg_info "Looking for vendor:$VENDOR_ID, products:${PRODUCT_IDS[*]}"
    return 1
}

# Check if we can write to the keyboard
check_permissions() {
    if [ ! -w "$KEYBOARD_DEVICE" ]; then
        msg_error "No write permission: $KEYBOARD_DEVICE"
        msg_info "Run: sudo cp 99-legion-rgb.rules /etc/udev/rules.d/"
        msg_info "Then: sudo udevadm control --reload-rules && sudo udevadm trigger"
        return 1
    fi
    return 0
}

#=============================================================================
# RGB CONTROL
#=============================================================================

# Send 32-byte HID packet to keyboard
# This is the low-level function that talks to the hardware
send_packet() {
    local packet=$1
    echo -ne "$packet" > "$KEYBOARD_DEVICE"
    sleep 0.1  # Small delay for device to process
}

# Build a 32-byte RGB packet
# Packet structure:
#   Byte 0-1:   Header (0xCC 0x16)
#   Byte 2:     Effect code
#   Byte 3:     Speed (1-4, where 1=fastest)
#   Byte 4:     Brightness (1=low, 2=high)
#   Byte 5-16:  Colors for 4 zones (R,G,B × 4)
#   Byte 17:    Unused (0x00)
#   Byte 18-19: Wave direction (0x00 0x00)
#   Byte 20-31: Padding (0x00...)
build_packet() {
    local effect=$1
    local speed=$2
    local brightness=$3
    local r=$4
    local g=$5
    local b=$6

    # Start with header
    local packet="\xcc\x16"

    # Add effect, speed, brightness
    packet+="\x$(printf '%02x' $effect)"
    packet+="\x$(printf '%02x' $speed)"
    packet+="\x$(printf '%02x' $brightness)"

    # Add colors for all 4 zones (we use same color for all)
    for zone in 1 2 3 4; do
        packet+="\x$(printf '%02x' $r)"
        packet+="\x$(printf '%02x' $g)"
        packet+="\x$(printf '%02x' $b)"
    done

    # Add unused byte and wave direction
    packet+="\x00\x00\x00"

    # Pad to 32 bytes total (we have 20, need 12 more)
    packet+="\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

    echo -n "$packet"
}

# Set static color
cmd_static() {
    local color=$1
    local brightness=${2:-2}  # Default: high brightness

    # Parse color to RGB
    local rgb
    rgb=$(parse_color "$color") || return 1
    IFS=',' read -r r g b <<< "$rgb"

    msg_info "Setting static: RGB($r,$g,$b) brightness=$brightness"

    # Build and send packet
    local packet=$(build_packet $EFFECT_STATIC 1 $brightness $r $g $b)
    send_packet "$packet"
}

# Set effect
cmd_effect() {
    local effect_name=$1
    local color=${2:-red}
    local speed=${3:-2}
    local brightness=${4:-2}

    # Map effect name to code
    local effect_code
    case "$effect_name" in
        static) effect_code=$EFFECT_STATIC ;;
        breath) effect_code=$EFFECT_BREATH ;;
        wave)   effect_code=$EFFECT_WAVE ;;
        hue)    effect_code=$EFFECT_HUE ;;
        *)
            msg_error "Unknown effect: $effect_name"
            msg_info "Available: static, breath, wave, hue"
            return 1
            ;;
    esac

    # Parse color
    local rgb
    rgb=$(parse_color "$color") || return 1
    IFS=',' read -r r g b <<< "$rgb"

    msg_info "Setting effect: $effect_name, speed=$speed, brightness=$brightness"

    # Build and send packet
    local packet=$(build_packet $effect_code $speed $brightness $r $g $b)
    send_packet "$packet"
}

# Load and apply config file
cmd_config() {
    [ -f "$CONFIG_FILE" ] || {
        msg_error "Config not found: $CONFIG_FILE"
        return 1
    }

    msg_info "Loading config: $CONFIG_FILE"

    # Source the config file
    source "$CONFIG_FILE"

    # Apply settings based on RGB_MODE
    case "${RGB_MODE:-static}" in
        static)
            local rgb=$(parse_color "${RGB_COLOR:-white}") || return 1
            IFS=',' read -r r g b <<< "$rgb"
            local brightness=2
            [ "${RGB_BRIGHTNESS:-high}" = "low" ] && brightness=1
            local packet=$(build_packet $EFFECT_STATIC 1 $brightness $r $g $b)
            send_packet "$packet"
            ;;
        breath|wave|hue)
            local rgb=$(parse_color "${RGB_COLOR:-red}") || return 1
            IFS=',' read -r r g b <<< "$rgb"

            # Map speed
            local speed=2
            case "${RGB_SPEED:-medium}" in
                fast) speed=1 ;;
                medium) speed=2 ;;
                slow) speed=4 ;;
            esac

            # Map brightness
            local brightness=2
            [ "${RGB_BRIGHTNESS:-high}" = "low" ] && brightness=1

            # Map effect
            local effect_code
            case "$RGB_MODE" in
                breath) effect_code=$EFFECT_BREATH ;;
                wave) effect_code=$EFFECT_WAVE ;;
                hue) effect_code=$EFFECT_HUE ;;
            esac

            local packet=$(build_packet $effect_code $speed $brightness $r $g $b)
            send_packet "$packet"
            ;;
        *)
            msg_error "Unknown mode: $RGB_MODE"
            return 1
            ;;
    esac
}

#=============================================================================
# COMMAND LINE INTERFACE
#=============================================================================

show_help() {
    cat << EOF
Lenovo Legion RGB Keyboard Controller (Simplified)

Usage:
  $0 static <color> [brightness]
  $0 effect <name> [color] [speed] [brightness]
  $0 config
  $0 help

Commands:
  static <color>              Set solid color
  effect <name>               Apply effect
  config                      Load rgb-config.conf

Examples:
  $0 static red               # Red keyboard
  $0 static "#FF0000"         # Red (hex)
  $0 static 255,0,0 2         # Red, high brightness
  $0 effect hue               # Rainbow effect
  $0 effect breath red 2 2    # Breathing red
  $0 config                   # Load config file

Colors: red, green, blue, white, cyan, magenta, yellow, orange, purple, pink
Effects: static, breath, wave, hue
Speed: 1=fast, 2=medium, 4=slow
Brightness: 1=low, 2=high

EOF
}

#=============================================================================
# MAIN
#=============================================================================

main() {
    # Parse command
    local command=${1:-help}

    # Find keyboard
    find_keyboard || exit 1
    check_permissions || exit 1

    # Execute command
    case "$command" in
        static)
            [ -n "${2:-}" ] || { msg_error "Missing color"; show_help; exit 1; }
            cmd_static "$2" "${3:-2}"
            ;;
        effect)
            [ -n "${2:-}" ] || { msg_error "Missing effect name"; show_help; exit 1; }
            cmd_effect "$2" "${3:-red}" "${4:-2}" "${5:-2}"
            ;;
        config)
            cmd_config
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
