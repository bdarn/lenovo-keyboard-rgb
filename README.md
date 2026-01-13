# RGB Device Controller

Pure Bash toolset for controlling RGB lighting on Lenovo Legion laptop keyboards, Razer external keyboards, and Razer mice. Supports automatic color synchronization with Omarchy themes.

## Hardware Support

- Lenovo Legion laptops with ITE RGB controllers (USB IDs: 048d:c101, 048d:c965)
- Razer keyboards via OpenRazer driver (tested with BlackWidow Elite, USB ID: 1532:0228)
- Razer mice via OpenRazer driver (tested with DeathAdder Essential, USB ID: 1532:0098)

## Installation

### 1. Install Dependencies

For Razer keyboard and mouse support:

```bash
# Arch Linux
sudo pacman -S openrazer-daemon

# Add yourself to the openrazer group
sudo gpasswd -a $USER openrazer

# Log out and log back in for group to take effect
```

### 2. Install Udev Rules

```bash
sudo cp 99-legion-rgb.rules /etc/udev/rules.d/
sudo cp 99-razer-keyboard.rules /etc/udev/rules.d/
sudo cp 99-razer-mouse.rules /etc/udev/rules.d/

sudo udevadm control --reload-rules
sudo udevadm trigger
```

Unplug and replug your devices or reboot.

### 3. Test Control

```bash
# Legion keyboard
./legion-rgb.sh static red

# Razer keyboard
./razer-rgb.sh static blue

# Razer mouse
./razer-mouse-rgb.sh static green
```

## Usage

### Control Both Keyboards

```bash
# Sync with current Omarchy theme (useful at startup)
./rgb-sync.sh auto

# Set both keyboards to same color
./rgb-sync.sh set cyan
./rgb-sync.sh set "#e20342"

# Sync with specific Omarchy theme
./rgb-sync.sh theme aetheria
```

### Control Individual Keyboards

Legion keyboard:
```bash
./legion-rgb.sh static red
./legion-rgb.sh effect breath
./legion-rgb.sh effect wave
./legion-rgb.sh effect hue
```

Razer keyboard:
```bash
./razer-rgb.sh static blue
./razer-rgb.sh breath cyan
./razer-rgb.sh spectrum
./razer-rgb.sh reactive green
```

Razer mouse:
```bash
./razer-mouse-rgb.sh static green 255
./razer-mouse-rgb.sh static green 128
./razer-mouse-rgb.sh off
```

Note: Mouse LED is green-only and controlled automatically by theme via rgb-sync.sh

## Automation

### Startup Sync (Hyprland)

Add to your `~/.config/hypr/autostart.conf`:

```bash
exec-once = /home/me/documents/lenovo-keyboard-rgb/lenovo-keyboard-rgb/rgb-sync.sh auto
```

This syncs keyboards/mouse with your current theme at boot.

### Omarchy Theme Integration

```bash
mkdir -p ~/.config/omarchy/hooks
cp omarchy-hook-theme-set ~/.config/omarchy/hooks/theme-set
chmod +x ~/.config/omarchy/hooks/theme-set

# Note: Edit SCRIPT_DIR in the hook file if your installation path differs
```

Updates keyboard colors automatically when changing Omarchy themes.

## Configuration

### Legion Keyboard Defaults

Edit `rgb-config.conf`:

```bash
RGB_MODE="static"
RGB_COLOR="green"
RGB_BRIGHTNESS="high"
```

### Mouse Theme Whitelist

By default, mouse LED is OFF for all themes. To enable green LED for specific themes, edit `rgb-config.conf`:

```bash
MOUSE_ENABLED_THEMES=("hackerman" "mars" "matrix")
```

The mouse script will automatically enable green LED only for themes in this list.

## Troubleshooting

**Permission Denied**: Reinstall udev rules and reboot

**Keyboard Not Found**: Check with `lsusb | grep 048d` (Legion) or `lsusb | grep 1532` (Razer)

**OpenRazer Daemon**: Start with `systemctl --user start openrazer-daemon.service`
