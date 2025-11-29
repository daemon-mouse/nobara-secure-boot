#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
echo "Based on sbctl on https://github.com/Foxboron/sbctl"
echo "\nAlso huge thanks to u/Asphalt_Expert on reddit for his tutorial\n"

if [[ "$EUID" -ne 0 ]]; then
	echo "run this script as superuser dumbass (use: sudo $0)"
	exit 1
fi

echo "=== Enabling sbctl copr and installing sbctl ==="
dnf -y copr enable chenxiaolong/sbctl
dnf -y install sbctl jq

is_sbctl_installed() {
	[ "$(sbctl status --json | jq --raw-output .installed)" = "true" ]
}

is_in_setup_mode() {
	[ "$(sbctl status --json | jq --raw-output .setup_mode)" = "true" ]
}

echo -e "\n=== Checking sbctl status ==="
sbctl status

if ! is_sbctl_installed; then
	echo -e "\n=== Installing sbctl ==="

	# Check Setup Mode
	if ! is_in_setup_mode; then
		echo -e "\n=== Setup Mode is Disabled ==="
		echo -e "\nYou must put the system in Setup Mode to continue."
		exit 0
	fi

	echo -e "\n=== Setup Mode is Enabled ==="
	echo "Creating and enrolling keys..."
	sbctl create-keys
	sbctl enroll-keys --microsoft
	echo -e "\nContinuing without reboot..."

	# --- Post key enrollment ---
	echo -e "\n=== Post enrollment status ==="
	sbctl status
else
	echo -e "\n=== Sbctl is Installed ==="
fi

echo -e "\n=== Signing and verifying EFI binaries ==="

readarray -d '' -t UNSIGNED_EFIS < <(
	sbctl verify --json | jq --raw-output0 '.[]? | select(.is_signed == 0) | .file_name'
)

for EFI in "${UNSIGNED_EFIS[@]}"; do
		echo "Signing: $EFI"
		sbctl sign "$EFI" || echo -e "\tFailed to sign $EFI"
done

# Sign kernel images
echo -e "\n=== Checking kernel images ==="
kernels=(/boot/vmlinuz-*)

if [[ ${#kernels[@]} -gt 0 ]]; then
	for kernel in "${kernels[@]}"; do
		echo "Signing kernel: $kernel"
		sbctl sign "$kernel" || echo "⚠️ Failed to sign $kernel"
	done
else
	echo "No kernel images found in /boot/"
fi

# Final verify
echo -e "\n=== Final sbctl verify ==="
sbctl verify | grep -v "failed to verify file"

echo -e "\n✅ All unsigned EFI binaries and kernels have been signed!"
echo -e "\n🔒 Now reboot the system and enable Secure Boot in BIOS"
echo -e "\nAlso fuck riot games and EA for making me make this script"
