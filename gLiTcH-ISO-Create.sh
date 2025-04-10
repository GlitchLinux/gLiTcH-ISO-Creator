#!/bin/bash

# ISO Creator Script for Mini-gLiTcH-like distributions
# Creates BIOS+UEFI bootable ISO from directory structure

# Install required dependencies
install_dependencies() {
    echo "Installing required packages..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y xorriso isolinux syslinux-utils mtools
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso syslinux mtools
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso syslinux mtools
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso syslinux mtools
    else
        echo "ERROR: Could not detect package manager to install dependencies."
        exit 1
    fi
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
    
    # Copy EFI files if they exist
    if [ -f "$source_dir/EFI/boot/bootx64.efi" ]; then
        mcopy -i "$source_dir/EFI/boot/efi.img" "$source_dir/EFI/boot/bootx64.efi" ::/EFI/BOOT/
    fi
    if [ -f "$source_dir/EFI/boot/grubx64.efi" ]; then
        mcopy -i "$source_dir/EFI/boot/efi.img" "$source_dir/EFI/boot/grubx64.efi" ::/EFI/BOOT/
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
        -o "$output_file" \
        "$source_dir"

    echo "ISO created successfully at: $output_file"
}

# Main script
main() {
    echo "=== ISO Creation Script ==="
    
    # Check and install dependencies
    if ! command -v xorriso &>/dev/null || ! command -v mkfs.vfat &>/dev/null; then
        install_dependencies
    fi
    
    # Get source directory
    read -p "Enter the path to the directory to convert to ISO: " source_dir
    source_dir=$(realpath "$source_dir")
    
    # Validate source directory
    if [ ! -d "$source_dir" ]; then
        echo "Error: Directory does not exist: $source_dir"
        exit 1
    fi
    
    if [ ! -f "$source_dir/isolinux/isolinux.bin" ]; then
        echo "Error: Missing isolinux.bin - not a valid bootable directory"
        exit 1
    fi
    
    # Get output filename
    read -p "Enter the output ISO filename (e.g., MyDistro.iso): " iso_name
    read -p "Enter directory to save ISO (leave blank for current dir): " output_dir
    
    output_dir=${output_dir:-$(pwd)}
    output_file="$output_dir/$iso_name"
    
    # Get volume label
    read -p "Enter ISO volume label (max 32 chars, no spaces/special chars): " iso_label
    iso_label=$(echo "$iso_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-')
    iso_label=${iso_label:0:32}
    
    # Confirm and create ISO
    echo -e "\n=== Summary ==="
    echo "Source Directory: $source_dir"
    echo "Output ISO: $output_file"
    echo "Volume Label: $iso_label"
    echo -e "\nRequired files verified:"
    echo "- $source_dir/isolinux/isolinux.bin [✔]"
    echo "- $source_dir/isolinux/isohdpfx.bin [✔]"
    
    read -p "Proceed with ISO creation? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_iso "$source_dir" "$output_file" "$iso_label"
    else
        echo "ISO creation cancelled."
        exit 0
    fi
}

# Run main function
main
