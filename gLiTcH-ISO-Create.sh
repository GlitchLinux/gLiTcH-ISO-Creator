#!/bin/bash

# Combined ISO Creation Script with Bootfile Download
# Creates BIOS+UEFI bootable ISO from directory structure

# Install required dependencies
install_dependencies() {
    echo "Installing required packages..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y xorriso isolinux syslinux-utils mtools wget squashfs-tools grub-efi-amd64-bin
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso syslinux mtools wget squashfs-tools grub2-efi-x64
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso syslinux mtools wget squashfs-tools grub2-efi-x64
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso syslinux mtools wget squashfs-tools grub
    else
        echo "ERROR: Could not detect package manager to install dependencies."
        exit 1
    fi
}

# Create squashfs filesystem directly without using rsync and temp directory
create_squashfs() {
    local iso_name="$1"
    local iso_dir="/home/$iso_name"
    
    echo "Creating filesystem.squashfs..."
    
    # Remove previous directory if exists
    if [ -d "$iso_dir" ]; then
        echo "Removing previous $iso_dir..."
        sudo rm -rf "$iso_dir"
    fi
    
    # Create directory structure
    mkdir -p "$iso_dir/live"
    
    # Create a tmpfs for the exclude list to avoid writing to disk
    mkdir -p /tmp/squashfs-excludes
    
    # Create exclude list for mksquashfs
    cat > /tmp/squashfs-excludes/exclude.list << EOF
/dev/*
/proc/*
/sys/*
/tmp/*
/run/*
/mnt/*
/media/*
/lost+found
/var/tmp/*
/var/cache/apt/archives/*
/var/lib/apt/lists/*
/home/$iso_name
/home/*.iso
/root/.bash_history
/root/.cache/*
/usr/src/*
/boot/*rescue*
/boot/System.map*
/boot/vmlinuz.old
/swapfile
/swap.img
EOF

    # Create squashfs directly from root filesystem with exclusions
    echo "Creating filesystem.squashfs directly (this may take a while)..."
    sudo mksquashfs \
        / \
        "$iso_dir/live/filesystem.squashfs" \
        -comp xz \
        -b 1048576 \
        -noappend \
        -ef /tmp/squashfs-excludes/exclude.list
    
    local squashfs_result=$?
    
    # Clean up excludes
    rm -rf /tmp/squashfs-excludes
    
    if [ $squashfs_result -ne 0 ]; then
        echo "Error creating squashfs filesystem"
        exit 1
    fi
    
    echo "filesystem.squashfs created successfully at $iso_dir/live/"
}

# Copy kernel and initrd files
copy_kernel_initrd() {
    local iso_name="$1"
    local iso_dir="/home/$iso_name"
    
    echo "Copying kernel and initrd files..."
    
    # Find and copy vmlinuz
    vmlinuz_file=$(find /boot -name 'vmlinuz-*' -not -name '*-rescue-*' | sort -V | tail -n 1)
    if [ -z "$vmlinuz_file" ]; then
        echo "Error: Could not find vmlinuz file in /boot"
        exit 1
    fi
    
    cp "$vmlinuz_file" "$iso_dir/live/vmlinuz"
    
    # Find and copy initrd
    initrd_file=$(find /boot -name 'initrd.img-*' -not -name '*-rescue-*' | sort -V | tail -n 1)
    if [ -z "$initrd_file" ]; then
        # Try initramfs if initrd not found
        initrd_file=$(find /boot -name 'initramfs-*' -not -name '*-rescue-*' | sort -V | tail -n 1)
        if [ -z "$initrd_file" ]; then
            echo "Error: Could not find initrd/initramfs file in /boot"
            exit 1
        fi
    fi
    
    cp "$initrd_file" "$iso_dir/live/initrd.img"
    chmod 644 "$iso_dir/live/vmlinuz" "$iso_dir/live/initrd.img"
    
    echo "Kernel and initrd files copied successfully:"
    echo " - $iso_dir/live/vmlinuz"
    echo " - $iso_dir/live/initrd.img"
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
    
    echo "Bootfiles installed successfully"
}

# Configure EFI boot
configure_efi_boot() {
    local iso_dir="$1"
    local iso_name="$2"
    
    echo "Configuring EFI boot..."
    
    # Create EFI directory structure
    mkdir -p "$iso_dir/EFI/boot"
    
    # Copy GRUB EFI files
    if [ -f /usr/lib/grub/x86_64-efi/core.efi ]; then
        cp /usr/lib/grub/x86_64-efi/core.efi "$iso_dir/EFI/boot/bootx64.efi"
    elif [ -f /usr/share/grub/x86_64-efi/core.efi ]; then
        cp /usr/share/grub/x86_64-efi/core.efi "$iso_dir/EFI/boot/bootx64.efi"
    elif [ -f /boot/efi/EFI/debian/grubx64.efi ]; then
        cp /boot/efi/EFI/debian/grubx64.efi "$iso_dir/EFI/boot/bootx64.efi"
    elif [ -f /boot/efi/EFI/ubuntu/grubx64.efi ]; then
        cp /boot/efi/EFI/ubuntu/grubx64.efi "$iso_dir/EFI/boot/bootx64.efi"
    else
        # Try to generate it
        echo "GRUB EFI binary not found, attempting to generate one..."
        if command -v grub-mkstandalone &>/dev/null; then
            grub-mkstandalone -O x86_64-efi -o "$iso_dir/EFI/boot/bootx64.efi" \
                --modules="part_gpt part_msdos fat iso9660" \
                --fonts="unicode" \
                --locales="" \
                --themes="" \
                "/boot/grub/grub.cfg=$iso_dir/boot/grub/grub.cfg"
        else
            echo "WARNING: Unable to find or create GRUB EFI binary, EFI boot may not work!"
        fi
    fi
    
    # Create EFI image if not using the bootfiles' version
    if [ ! -f "$iso_dir/EFI/boot/efi.img" ]; then
        echo "Creating EFI boot image..."
        dd if=/dev/zero of="$iso_dir/EFI/boot/efi.img" bs=1M count=16
        mkfs.vfat "$iso_dir/EFI/boot/efi.img"
        
        # Create EFI directory structure on FAT image
        mmd -i "$iso_dir/EFI/boot/efi.img" ::/EFI ::/EFI/BOOT
        
        # Copy EFI file to FAT image
        if [ -f "$iso_dir/EFI/boot/bootx64.efi" ]; then
            mcopy -i "$iso_dir/EFI/boot/efi.img" "$iso_dir/EFI/boot/bootx64.efi" ::/EFI/BOOT/
        fi
    fi
}

# Create the ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    # Verify we have the necessary files
    if [ ! -f "$source_dir/isolinux/isolinux.bin" ]; then
        echo "Error: Required file isolinux.bin not found"
        return 1
    fi
    
    if [ ! -f "$source_dir/isolinux/isohdpfx.bin" ]; then
        echo "Error: Required file isohdpfx.bin not found"
        return 1
    fi
    
    echo "Creating hybrid ISO image..."
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$iso_label" \
        -appid "GlitchLinux Live" \
        -publisher "GlitchLinux" \
        -preparer "GlitchLinux ISO Creator" \
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

    local iso_result=$?
    if [ $iso_result -ne 0 ]; then
        echo "Error creating ISO image"
        return 1
    fi
    
    echo "ISO created successfully at: $output_file"
    return 0
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

set default="0"
set timeout=10

search --set=root --file /live/vmlinuz

function load_video {
    insmod vbe
    insmod vga
    insmod video_bochs
    insmod video_cirrus
}

loadfont /usr/share/grub/unicode.pf2

set gfxmode=640x480
load_video
insmod gfxterm
set locale_dir=/boot/grub/locale
set lang=C
insmod gettext
if [ -f /boot/grub/splash.png ]; then
    background_image -m stretch /boot/grub/splash.png
    terminal_output gfxterm
    insmod png
fi

menuentry "$NAME - LIVE" {
    linux /live/$VMLINUZ boot=live quiet splash
    initrd /live/$INITRD
}

menuentry "$NAME - Boot ISO to RAM" {
    linux /live/$VMLINUZ boot=live quiet splash toram
    initrd /live/$INITRD
}

menuentry "$NAME - Encrypted Persistence" {
    linux /live/$VMLINUZ boot=live quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
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
  append initrd=/live/$INITRD boot=live quiet splash

label live_ram
  menu label $NAME - Boot ISO to RAM
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live quiet splash toram

label encrypted_persistence
  menu label $NAME - Encrypted Persistence
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence

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
    if ! command -v xorriso &>/dev/null || ! command -v mkfs.vfat &>/dev/null || ! command -v wget &>/dev/null || ! command -v mksquashfs &>/dev/null; then
        install_dependencies
    fi
    
    # Get ISO name
    read -p "Enter the name for your ISO (this will be used for directory and ISO name): " iso_name
    
    # Create squashfs and copy kernel files
    create_squashfs "$iso_name"
    copy_kernel_initrd "$iso_name"
    
    # Set ISO directory
    ISO_DIR="/home/$iso_name"
    cd "$ISO_DIR" || exit 1
    
    # Download bootfiles
    download_bootfiles "$ISO_DIR"
    
    # Configure EFI boot
    configure_efi_boot "$ISO_DIR" "$iso_name"
    
    # Set detected files
    VMLINUZ="vmlinuz"
    INITRD="initrd.img"
    SQUASHFS="filesystem.squashfs"
    
    # Verify we found the necessary files
    if [ ! -f "$ISO_DIR/live/$VMLINUZ" ]; then
        echo "Error: Could not find vmlinuz file in $ISO_DIR/live/"
        exit 1
    fi
    
    if [ ! -f "$ISO_DIR/live/$INITRD" ]; then
        echo "Error: Could not find initrd file in $ISO_DIR/live/"
        exit 1
    fi
    
    if [ ! -f "$ISO_DIR/live/$SQUASHFS" ]; then
        echo "Warning: Could not find squashfs file in $ISO_DIR/live/"
    fi
    
    # Use ISO name as system name
    NAME="$iso_name"
    
    # Generate boot configurations
    generate_boot_configs "$ISO_DIR" "$NAME" "$VMLINUZ" "$INITRD" "$SQUASHFS"
    
    # Set output filename (same as directory name)
    output_file="/home/${iso_name}.iso"
    
    # Set volume label (same as directory name, sanitized)
    iso_label=$(echo "$iso_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-')
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
