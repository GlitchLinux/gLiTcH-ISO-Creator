#!/bin/bash

# Combined ISO Creation Script with Bootfile Download
# Creates BIOS+UEFI bootable ISO from directory structure

# Install required dependencies
install_dependencies() {
    echo "Installing required packages..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y xorriso isolinux syslinux-utils mtools wget grub-efi-amd64-bin grub-pc-bin
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso syslinux mtools wget grub2-efi-x64 grub2-pc
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso syslinux mtools wget grub2-efi-x64 grub2-pc
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso syslinux mtools wget grub
    else
        echo "ERROR: Could not detect package manager to install dependencies."
        exit 1
    fi
}

# Download and extract bootfiles
download_bootfiles() {
    local iso_dir="$1"
    local bootfiles_url="https://github.com/GlitchLinux/gLiTcH-ISO-Creator/blob/main/BOOTFILES.tar.gz?raw=true"
    local temp_dir="/tmp/bootfiles_$$"
    
    echo "Downloading bootfiles from GitHub..."
    mkdir -p "$temp_dir"
    if ! wget -q "$bootfiles_url" -O "$temp_dir/BOOTFILES.tar.gz"; then
        echo "Error: Failed to download bootfiles"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo "Extracting bootfiles to $iso_dir..."
    tar -xzf "$temp_dir/BOOTFILES.tar.gz" -C "$temp_dir"
    cp -r "$temp_dir"/* "$iso_dir/"
    rm -rf "$temp_dir"
    
    echo "Bootfiles installed successfully"
}

# Create the ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    echo "Creating hybrid ISO image..."
    
    # Ensure required directories exist
    mkdir -p "$source_dir/EFI/boot"
    mkdir -p "$source_dir/boot/grub"
    
    # Create EFI boot image (if not already present)
    if [ ! -f "$source_dir/EFI/boot/efi.img" ]; then
        echo "Creating EFI boot image..."
        dd if=/dev/zero of="$source_dir/EFI/boot/efi.img" bs=1M count=32
        mkfs.vfat "$source_dir/EFI/boot/efi.img"
        
        # Mount and populate the EFI image
        local efi_mount="/tmp/efi_mount_$$"
        mkdir -p "$efi_mount"
        sudo mount -o loop "$source_dir/EFI/boot/efi.img" "$efi_mount"
        sudo mkdir -p "$efi_mount/EFI/BOOT"
        
        # Copy EFI bootloaders
        if [ -f "$source_dir/EFI/boot/bootx64.efi" ]; then
            sudo cp "$source_dir/EFI/boot/bootx64.efi" "$efi_mount/EFI/BOOT/"
        elif [ -f "$source_dir/EFI/boot/grubx64.efi" ]; then
            sudo cp "$source_dir/EFI/boot/grubx64.efi" "$efi_mount/EFI/BOOT/bootx64.efi"
        fi
        
        # Copy grub.cfg to EFI partition
        if [ -f "$source_dir/boot/grub/grub.cfg" ]; then
            sudo mkdir -p "$efi_mount/boot/grub"
            sudo cp "$source_dir/boot/grub/grub.cfg" "$efi_mount/boot/grub/"
        fi
        
        sudo umount "$efi_mount"
        rm -rf "$efi_mount"
    fi

    # Create ISO with both BIOS and UEFI support
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$iso_label" \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -isohybrid-mbr "$source_dir/isolinux/isohdpfx.bin" \
        -eltorito-alt-boot \
        -e EFI/boot/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -output "$output_file" \
        "$source_dir"

    # Check if ISO was created successfully
    if [ $? -eq 0 ]; then
        echo "ISO created successfully at: $output_file"
        
        # Make the ISO bootable from USB
        isohybrid --uefi "$output_file"
        
        # Add checksum for verification
        implantisomd5 "$output_file"
    else
        echo "Error: Failed to create ISO"
        exit 1
    fi
}

# Generate boot configurations
generate_boot_configs() {
    local ISO_DIR="$1"
    local NAME="$2"
    local VMLINUZ="$3"
    local INITRD="$4"
    local SQUASHFS="$5"
    
    # Create boot/grub directory if it doesn't exist
    mkdir -p "$ISO_DIR/boot/grub"

    # Generate grub.cfg
    cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
set timeout=10
set default=0

if loadfont /boot/grub/font.pf2 ; then
  set gfxmode=auto
  insmod efi_gop
  insmod efi_uga
  insmod gfxterm
  terminal_output gfxterm
fi

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "$NAME - LIVE" {
    search --set=root --file /live/$VMLINUZ
    linux /live/$VMLINUZ boot=live config quiet
    initrd /live/$INITRD
}

menuentry "$NAME - Boot ISO to RAM" {
    search --set=root --file /live/$VMLINUZ
    linux /live/$VMLINUZ boot=live config quiet toram
    initrd /live/$INITRD
}

menuentry "$NAME - Encrypted Persistence" {
    search --set=root --file /live/$VMLINUZ
    linux /live/$VMLINUZ boot=live components quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$INITRD
}

menuentry "GRUBFM - (UEFI)" {
    search --set=root --file /EFI/GRUB-FM/E2B-bootx64.efi
    chainloader /EFI/GRUB-FM/E2B-bootx64.efi
}
EOF

    # Create isolinux directory if it doesn't exist
    mkdir -p "$ISO_DIR/isolinux"

    # Generate isolinux.cfg
    cat > "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
default vesamenu.c32
prompt 0
timeout 100

menu title $NAME-LIVE
menu tabmsg Press TAB key to edit
menu background splash.png

label live
  menu label $NAME - LIVE
  kernel /live/$VMLINUZ
  append boot=live config quiet initrd=/live/$INITRD

label live_ram
  menu label $NAME - Boot ISO to RAM
  kernel /live/$VMLINUZ
  append boot=live config quiet toram initrd=/live/$INITRD

label encrypted_persistence
  menu label $NAME - Encrypted Persistence
  kernel /live/$VMLINUZ
  append boot=live components quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence initrd=/live/$INITRD

label netboot_bios
  menu label Netboot.xyz (BIOS)
  kernel /boot/grub/netboot.xyz/netboot.xyz.lkrn
EOF

    echo "Configuration files created successfully:"
    echo " - $ISO_DIR/boot/grub/grub.cfg"
    echo " - $ISO_DIR/isolinux/isolinux.cfg"
}

# Verify boot files
verify_boot_files() {
    local ISO_DIR="$1"
    
    echo "Verifying required boot files..."
    
    # Check BIOS boot files
    if [ ! -f "$ISO_DIR/isolinux/isolinux.bin" ]; then
        echo "Error: Missing isolinux.bin - BIOS bootloader not found"
        exit 1
    fi
    
    if [ ! -f "$ISO_DIR/isolinux/isohdpfx.bin" ]; then
        echo "Error: Missing isohdpfx.bin - BIOS hybrid MBR not found"
        exit 1
    fi
    
    # Check UEFI boot files
    if [ ! -f "$ISO_DIR/EFI/boot/bootx64.efi" ] && [ ! -f "$ISO_DIR/EFI/boot/grubx64.efi" ]; then
        echo "Warning: Missing UEFI bootloader (bootx64.efi or grubx64.efi)"
        echo "Attempting to generate one..."
        
        # Try to generate GRUB EFI bootloader
        if command -v grub-mkstandalone &>/dev/null; then
            grub-mkstandalone \
                --format=x86_64-efi \
                --output="$ISO_DIR/EFI/boot/bootx64.efi" \
                --locales="" \
                --fonts="" \
                "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"
        else
            echo "Error: grub-mkstandalone not found - cannot create UEFI bootloader"
            exit 1
        fi
    fi
    
    echo "Boot files verified successfully"
}

# Main script
main() {
    echo "=== ISO Creation Script ==="
    
    # Check and install dependencies
    if ! command -v xorriso &>/dev/null || ! command -v mkfs.vfat &>/dev/null || ! command -v wget &>/dev/null; then
        install_dependencies
    fi
    
    # Get source directory
    read -p "Enter the directory path to make bootable: " ISO_DIR
    ISO_DIR=$(realpath "$ISO_DIR")
    
    # Verify the directory exists
    if [ ! -d "$ISO_DIR" ]; then
        echo "Error: Directory $ISO_DIR does not exist."
        exit 1
    fi
    
    # Check if the live directory exists
    if [ ! -d "$ISO_DIR/live" ]; then
        echo "Error: $ISO_DIR/live directory not found. This doesn't appear to be a live system directory."
        exit 1
    fi
    
    # Download bootfiles
    download_bootfiles "$ISO_DIR"
    
    # Scan for kernel and initrd files
    VMLINUZ=""
    INITRD=""
    SQUASHFS=""
    
    # Look for vmlinuz file
    for file in "$ISO_DIR/live"/vmlinuz*; do
        if [ -f "$file" ]; then
            VMLINUZ=$(basename "$file")
            break
        fi
    done
    
    # Look for initrd file
    for file in "$ISO_DIR/live"/initrd*; do
        if [ -f "$file" ]; then
            INITRD=$(basename "$file")
            break
        fi
    done
    
    # Look for filesystem.squashfs
    for file in "$ISO_DIR/live"/*.squashfs; do
        if [ -f "$file" ]; then
            SQUASHFS=$(basename "$file")
            break
        fi
    done
    
    # Verify we found the necessary files
    if [ -z "$VMLINUZ" ]; then
        echo "Error: Could not find vmlinuz file in $ISO_DIR/live/"
        exit 1
    fi
    
    if [ -z "$INITRD" ]; then
        echo "Error: Could not find initrd file in $ISO_DIR/live/"
        exit 1
    fi
    
    if [ -z "$SQUASHFS" ]; then
        echo "Warning: Could not find squashfs file in $ISO_DIR/live/"
    fi
    
    # Ask for system name
    read -p "Enter the name of the system in the ISO: " NAME
    
    # Confirm detected files or allow user to override
    echo "Detected files:"
    echo "vmlinuz: $VMLINUZ"
    echo "initrd: $INITRD"
    echo "squashfs: $SQUASHFS"
    read -p "Press enter to accept these or enter new values (vmlinuz initrd): " -r OVERRIDE
    
    if [ ! -z "$OVERRIDE" ]; then
        read -ra OVERRIDE_ARRAY <<< "$OVERRIDE"
        VMLINUZ=${OVERRIDE_ARRAY[0]:-$VMLINUZ}
        INITRD=${OVERRIDE_ARRAY[1]:-$INITRD}
    fi
    
    # Generate boot configurations
    generate_boot_configs "$ISO_DIR" "$NAME" "$VMLINUZ" "$INITRD" "$SQUASHFS"
    
    # Verify boot files
    verify_boot_files "$ISO_DIR"
    
    # Get output filename
    read -p "Enter the output ISO filename (e.g., MyDistro.iso): " iso_name
    
    # Set output directory to parent of ISO_DIR
    output_dir=$(dirname "$ISO_DIR")
    output_file="$output_dir/$iso_name"
    
    # Get volume label
    read -p "Enter ISO volume label (max 32 chars, no spaces/special chars): " iso_label
    iso_label=$(echo "$iso_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-')
    iso_label=${iso_label:0:32}
    
    # Confirm and create ISO
    echo -e "\n=== Summary ==="
    echo "Source Directory: $ISO_DIR"
    echo "Output ISO: $output_file"
    echo "Volume Label: $iso_label"
    echo -e "\nRequired files verified:"
    echo "- $ISO_DIR/isolinux/isolinux.bin [✔]"
    echo "- $ISO_DIR/isolinux/isohdpfx.bin [✔]"
    echo "- $ISO_DIR/EFI/boot/bootx64.efi or grubx64.efi [✔]"
    
    read -p "Proceed with ISO creation? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_iso "$ISO_DIR" "$output_file" "$iso_label"
    else
        echo "ISO creation cancelled."
        exit 0
    fi
}

# Run main function
main
