#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
echo "Based on sbctl on https://github.com/Foxboron/sbctl"
echo -e "Also huge thanks to u/Asphalt_Expert on reddit for his tutorial\n"

if [[ "$EUID" -ne 0 ]]; then
	echo "You must run this script as user root (use: sudo $0)"
	exit 1
fi

echo "=== Enabling sbctl copr and installing sbctl ==="
dnf -y copr enable chenxiaolong/sbctl
dnf -y install sbctl jq

is_sbctl_installed() {
	[ "$(sbctl status --json | jq .installed)" = "true" ]
}

is_in_setup_mode() {
	[ "$(sbctl status --json | jq .setup_mode)" = "true" ]
}

is_secure_boot_on() {
	[ "$(sbctl status --json | jq .secure_boot)" = "true" ]
}

echo -e "\n=== Checking sbctl status ==="
sbctl status

if ! is_sbctl_installed; then
	echo -e "\n=== Installing sbctl ==="

	# Check Setup Mode
	if ! is_in_setup_mode; then
		echo -e "\n=== Setup Mode is Disabled ===\n"
		cat <<-'EOF'
			To use custom Secure Boot keys, you must reboot into BIOS and enter Setup
			Mode by navigating to the Secure Boot menu. Without completing this step,
			enrolling custom keys will be rejected by the firmware.

			Unfortunately, the exact steps to enable Setup Mode are specific to each BIOS
			vendor. Hopefully, you have a clearly labelled menu entry for it.

			If you're having trouble, try the following:
			  - Delete/clear the Secure Boot keys (or at minimum the Platform Key)
			  - Turn Secure Boot mode off or on

			Warning: Some BIOSes have a 'Custom Mode' which only disables signature
			verification and should NOT be enabled unless no other way to enter key
			management is provided.

			Note: You can attempt to reboot into BIOS with the following command:
			        systemctl reboot --firmware-setup
		EOF
		exit 0
	fi

	echo -e "\n=== Creating custom key ==="
	sbctl create-keys
else
	echo -e "\n=== Sbctl is Installed ==="
fi

if is_in_setup_mode; then
	echo -e "\n=== Enrolling custom key and Microsoft's keys ==="
	sbctl enroll-keys --microsoft

	# --- Post key enrollment ---
	echo -e "\n=== Post enrollment status ==="
	sbctl status
fi

echo -e "\n=== Signing and verifying EFI binaries ==="

readarray -d '' -t UNSIGNED_EFIS < <(
	sbctl verify --json | jq --raw-output0 '.[]? | select(.is_signed == 0) | .file_name'
)

echo "Found ${#UNSIGNED_EFIS[@]} unsigned EFI binaries."

for EFI in "${UNSIGNED_EFIS[@]}"; do
	echo "Signing: $EFI"
	sbctl sign "$EFI" || printf "\tFailed to sign %s\n" "$EFI"
done

# Sign kernel images
echo -e "\n=== Checking kernel images ==="
kernels=(/boot/vmlinuz-*)

if [[ ${#kernels[@]} -gt 0 ]]; then
	for kernel in "${kernels[@]}"; do
		echo "Signing kernel: $kernel"
		sbctl sign "$kernel" || printf "\tFailed to sign %s\n" "$kernel"
	done
else
	echo "No kernel images found in /boot/"
fi

# Final verify
echo -e "\n=== Final sbctl verify ==="
sbctl verify | grep -v "failed to verify file"

echo -e "\nAll unsigned EFI binaries and kernels have been signed!"

if ! is_secure_boot_on; then
	echo -e "\nSecure Boot has been successfully configured."
	echo -e "You may now reboot the system and enable Secure Boot in BIOS."
	echo -e "\nNote: You can attempt to reboot into BIOS with the following command:"
	echo -e "\tsystemctl reboot --firmware-setup"
fi
