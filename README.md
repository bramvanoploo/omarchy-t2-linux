# Omarchy T2 Linux

An [Omarchy](https://omarchy.org) status bar plugin designed to optimize Linux installations on Apple MacBooks equipped with the **Apple T2 Security Chip** (2018–2020 Intel MacBook Pro, MacBook Air, and Mac mini).

Clicking the bar icon (``) opens a dedicated settings panel featuring vertical tabs for tuning hardware power profiles, sleep states, wake behaviors, and peripheral battery drain.

![Omarchy T2 Linux Preview](preview.png)

---

## Features & Categorized Options

The panel organizes all hardware tunables into two primary vertical tabs:

### 1. Battery Life
- **Live Battery Telemetry**: Real-time battery charge percentage, charging/discharging status, real-time power discharge rate in Watts, and battery health percentage with cycle count.
- **CPU Energy Performance Preference (EPP)**: Set Intel CPU energy bias between `Power` (maximum battery life / throttles boost clocks), `Balanced` (recommended daily efficiency), `Responsive`, and `Performance`.
- **PCIe Active State Power Management (ASPM)**: Configure link power states across NVMe storage, Apple T2 bridge controllers, and PCIe lanes (`Powersave [L0s/L1]`, `Default`, or `Full Power`). Powersave drastically cuts idle package wattage.
- **Wi-Fi Power Management**: Toggle IEEE 802.11 power saving on the Broadcom wireless interface during network idle.
- **Audio Controller Power Save**: Powers down Apple/HDA Intel audio codecs when inactive (`power_save=1`) to eliminate audio controller background drain.
- **USB Device Autosuspend**: Allows idle USB devices and internal VHCI bridges to enter low-power sleep states.
- **Keyboard Backlight Auto-Dim**: Configurable idle timeout for keyboard illumination (`30s`, `1m`, `2m`, `5m`, or `Never`).

### 2. Suspend Behaviour
- **System Sleep Mode (`mem_sleep`)**:
  - `Deep (S3)`: Full Suspend-to-RAM. Completely powers off CPU and PCIe devices. Recommended on T2 MacBooks to prevent heat buildup and battery drain while stored in a backpack.
  - `Modern Standby (s2idle)`: Freeze standby mode with faster wake times.
- **Lid Close Action (On Battery)**: Choose between `Suspend`, `Do Nothing`, `Lock Screen`, or `Hibernate` when closing the MacBook display on battery power.
- **Clamshell Mode (On External Power / Display)**: Keep the MacBook awake when the lid is closed while connected to an external display and AC charger (`HandleLidSwitchExternalPower=ignore`), or always suspend.
- **Wake on Lid Open (LID0)**: Automatically resume the laptop from sleep as soon as the display lid is opened.
- **Wake on Charger Connect (ADP1)**: Wake the system from sleep whenever a USB-C or MagSafe charger is connected.
- **Hibernate Delay (Suspend-Then-Hibernate)**: Automatically transitions from suspend to hibernation after a set duration (`30 min`, `1 hour`, `2 hours`, or `Never`) to avoid battery exhaustion during long sleep intervals.
- **Touch Bar Blanking on Sleep**: Powers off the OLED Touch Bar display immediately before system sleep.

---

## Hardware Compatibility & Non-T2 Protection

The plugin performs low-level hardware verification upon activation:
- Probes `/sys/bus/pci/devices/*/device` for PCI Vendor `0x106b` and Device IDs `0x1801` / `0x1802` (Apple T2 Bridge Controller & Secure Enclave Processor).
- Checks DMI system identifiers (`product_name` and `sys_vendor`).

### Incompatible System Notification Dialog
If a user clicks the bar icon on an Omarchy installation that is **not** running on a T2 MacBook, the settings panel will **not** open. Instead, an interactive modal notification dialog is presented:

> **Omarchy T2 Linux — Incompatible Hardware Detected**  
> *"This plugin is intended for use with Macbooks with the T2 chip and that chip has not been found in your computer."*

The dialog clearly informs the user that the Apple T2 Security Chip was not found and allows dismissing the notification safely.

---

## Installation & Setup

### 1. Enable in Omarchy Shell
```bash
omarchy plugin add https://github.com/bramvanoploo/omarchy-t2-linux.git --enable
```

### 2. (Optional) Install System Polkit Rule
To allow modifying privileged hardware settings (such as PCIe ASPM, CPU EPP, and sleep modes) without repetitive authentication prompts:
```bash
sudo ~/.config/omarchy/plugins/bramvanoploo.omarchy-t2-linux/setup-system
```
To remove the polkit rule and privileged helper:
```bash
sudo ~/.config/omarchy/plugins/bramvanoploo.omarchy-t2-linux/teardown-system
```
---

## Uninstall

### 1. Remove System Polkit Rule (if added)
```bash
sudo ~/.config/omarchy/plugins/bramvanoploo.omarchy-t2-linux/teardown-system
```

### 2. Remove plugin from Omarchy Shell
```bash
omarchy plugin remove bramvanoploo.omarchy-t2-linux
```

---

## Shell IPC Controls

You can trigger panel actions directly via Quickshell IPC:
```bash
# Open centered panel
qs -p /usr/share/omarchy/shell ipc call bramvanoploo.omarchy-t2-linux open

# Toggle centered panel
qs -p /usr/share/omarchy/shell ipc call bramvanoploo.omarchy-t2-linux toggle

# Close panel
qs -p /usr/share/omarchy/shell ipc call bramvanoploo.omarchy-t2-linux close
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
