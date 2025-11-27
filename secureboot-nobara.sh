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

echo -e "\n=== Signing and verifying EFI binaries ==="

while true; do
	# Run verify and strip bogus "invalid pe header" lines
	verify_output=$(sbctl verify 2>&1 | grep -v "failed to verify file")

	echo "$verify_output"

	# Extract unsigned .efi / .EFI files
	unsigned_efi=$(echo "$verify_output" | grep "✗" | awk '{print $2}' | grep -E "\.efi$|\.EFI$" || true)

	if [[ -z "$unsigned_efi" ]]; then
		echo -e "\n✅ All EFI binaries are signed!"
		break
	fi

	echo -e "\n=== Found unsigned EFI binaries ==="
	echo "$unsigned_efi"

	while read -r file; do
		[[ -z "$file" ]] && continue
		echo "Signing: $file"
		sbctl sign -s "$file" || echo "⚠️ Failed to sign $file"
	done <<<"$unsigned_efi"
done

# Sign kernel images
echo -e "\n=== Checking kernel images ==="
kernels=(/boot/vmlinuz-*)

if [[ ${#kernels[@]} -gt 0 ]]; then
	for kernel in "${kernels[@]}"; do
		echo "Signing kernel: $kernel"
		sbctl sign -s "$kernel" || echo "⚠️ Failed to sign $kernel"
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
