#!/bin/bash

# Combined ISO Creation Script with Bootfile Download
# Creates BIOS+UEFI bootable ISO from directory structure

# Install required dependencies
install_dependencies() {
    echo "Installing required packages..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y xorriso isolinux syslinux-utils mtools wget grub-efi-amd64-bin
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso syslinux mtools wget grub2-efi-x64-modules
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso syslinux mtools wget grub2-efi-x64-modules
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
    rm -f "$iso_dir/BOOTFILES.tar.gz"
    
    # Ensure required UEFI directories exist
    mkdir -p "$iso_dir/EFI/BOOT"
    mkdir -p "$iso_dir/BOOT"
    
    echo "Bootfiles installed successfully"
}

# Create the ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    echo "Creating EFI boot image..."
    mkdir -p "$source_dir/EFI/boot"
    dd if=/dev/zero of="$source_dir/EFI/boot/efi.img" bs=1M count=10
    mkfs.vfat "$source_dir/EFI/boot/efi.img"
    mmd -i "$source_dir/EFI/boot/efi.img" ::/EFI ::/EFI/BOOT
    
    # Copy or create required UEFI boot files
    if [ -f "$source_dir/EFI/boot/grubx64.efi" ]; then
        echo "Using existing grubx64.efi"
    elif [ -x "$(command -v grub-mkimage)" ]; then
        echo "Generating grubx64.efi..."
        grub-mkimage -o "$source_dir/EFI/boot/grubx64.efi" -p /boot/grub -O x86_64-efi \
            boot linux ext2 fat iso9660 part_gpt part_msdos normal configfile loopback chain efifwsetup \
            efi_gop efi_uga ls search search_label search_fs_uuid search_fs_file gfxterm gfxmenu png
    else
        echo "Warning: grubx64.efi not found and couldn't generate it"
    fi
    
    # Copy bootx64.efi (fallback)
    if [ -f "$source_dir/EFI/boot/grubx64.efi" ]; then
        cp "$source_dir/EFI/boot/grubx64.efi" "$source_dir/EFI/boot/bootx64.efi"
        cp "$source_dir/EFI/boot/grubx64.efi" "$source_dir/BOOT/bootx64.efi"
    fi
    
    # Copy files to EFI image
    if [ -f "$source_dir/EFI/boot/bootx64.efi" ]; then
        mcopy -i "$source_dir/EFI/boot/efi.img" "$source_dir/EFI/boot/bootx64.efi" ::/EFI/BOOT/
        mcopy -i "$source_dir/EFI/boot/efi.img" "$source_dir/EFI/boot/bootx64.efi" ::/EFI/BOOT/grubx64.efi
    fi
    
    # Ensure BOOT/bootx64.efi exists
    mkdir -p "$source_dir/BOOT"
    if [ -f "$source_dir/EFI/boot/bootx64.efi" ]; then
        cp "$source_dir/EFI/boot/bootx64.efi" "$source_dir/BOOT/bootx64.efi"
    fi

    echo "Creating hybrid ISO image..."
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$iso_label" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -isohybrid-mbr "$source_dir/isolinux/isohdpfx.bin" \
        -eltorito-alt-boot \
        -e EFI/boot/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -append_partition 2 0xEF "$source_dir/EFI/boot/efi.img" \
        -o "$output_file" \
        "$source_dir"

    echo "ISO created successfully at: $output_file"
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
# GRUB.CFG 

if loadfont \$prefix/font.pf2 ; then
  set gfxmode=800x600
  set gfxpayload=keep
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  insmod png
  terminal_output gfxterm
fi

if background_image /boot/grub/splash.png; then
  set color_normal=light-gray/black
  set color_highlight=white/black
elif background_image /splash.png; then
  set color_normal=light-gray/black
  set color_highlight=white/black
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi

menuentry "$NAME - LIVE" {
    linux /live/$VMLINUZ boot=live config quiet
    initrd /live/$INITRD
}

menuentry "$NAME - Boot ISO to RAM" {
    linux /live/$VMLINUZ boot=live config quiet toram
    initrd /live/$INITRD
}

menuentry "$NAME - Encrypted Persistence" {
    linux /live/$VMLINUZ boot=live components quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$INITRD
}

menuentry "GRUBFM - (UEFI)" {
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
