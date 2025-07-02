#!/bin/bash

# Pure GRUB2 ISO Creation Script (BIOS+UEFI)
# Creates bootable ISO using GRUB2 for both BIOS and UEFI systems

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Install required dependencies
install_dependencies() {
    echo -e "${BLUE}Installing required packages...${NC}"
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update
        sudo apt-get install -y xorriso mtools wget grub2-common grub-efi-amd64-bin
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso mtools wget grub2-tools grub2-efi-x64
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso mtools wget grub2-tools grub2-efi-x64
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso mtools wget grub efibootmgr
    else
        echo -e "${RED}ERROR: Could not detect package manager to install dependencies.${NC}"
        exit 1
    fi
}

# Download and extract bootfiles
download_bootfiles() {
    local iso_dir="$1"
    local grub_files_url="https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/GRUB2-BOOTFILES.tar.gz"
    local temp_dir="/tmp/grub_bootfiles_$RANDOM"
    
    echo -e "${BLUE}Downloading GRUB2 bootfiles from GitHub...${NC}"
    mkdir -p "$temp_dir"
    
    if ! wget --progress=bar:force "$grub_files_url" -O "$temp_dir/GRUB2-BOOTFILES.tar.gz"; then
        echo -e "${RED}Error: Failed to download GRUB2 bootfiles${NC}"
        echo -e "${YELLOW}Please ensure GRUB2-BOOTFILES.tar.gz exists in your GitHub repository${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo -e "${BLUE}Extracting GRUB2 files...${NC}"
    tar -xzf "$temp_dir/GRUB2-BOOTFILES.tar.gz" -C "$iso_dir"
    
    if [ ! -f "$iso_dir/boot/grub/i386-pc/cdboot.img" ] || [ ! -d "$iso_dir/boot/grub/x86_64-efi" ]; then
        echo -e "${RED}Error: GRUB2 files extraction incomplete${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    rm -rf "$temp_dir"
    echo -e "${GREEN}GRUB2 bootfiles installed successfully${NC}"
}

# Handle splash screen selection
handle_splash_screen() {
    local iso_dir="$1"
    local splash_path=""
    
    echo -e "\n${YELLOW}=== Splash Screen Configuration ===${NC}"
    echo "Would you like to add a custom splash.png for GRUB?"
    read -p "Enter 'y' for custom splash or 'n' for default: " use_custom
    
    if [[ "$use_custom" =~ ^[Yy]$ ]]; then
        read -p "Enter the full path to your splash.png file: " splash_path
        splash_path=$(realpath "$splash_path" 2>/dev/null)
        
        if [ -f "$splash_path" ]; then
            echo -e "${GREEN}Copying custom splash screen...${NC}"
            mkdir -p "$iso_dir/boot/grub"
            cp "$splash_path" "$iso_dir/boot/grub/splash.png"
            cp "$splash_path" "$iso_dir/splash.png"
        else
            echo -e "${RED}Warning: Splash file not found at $splash_path${NC}"
            echo -e "${YELLOW}Using default splash screen...${NC}"
        fi
    else
        echo -e "${BLUE}Using default splash screen...${NC}"
    fi
}

# Create GRUB2 BIOS boot image
create_grub_bios_image() {
    local iso_dir="$1"
    local grub_dir="$iso_dir/boot/grub/i386-pc"
    
    echo -e "${BLUE}Creating GRUB2 BIOS boot image...${NC}"
    
    if [ ! -d "$grub_dir" ]; then
        echo -e "${RED}Error: GRUB i386-pc modules not found in $grub_dir${NC}"
        exit 1
    fi
    
    # Create embedded config for BIOS
    cat > /tmp/grub_embed.cfg <<EOF
search --no-floppy --set=root --file /boot/grub/grub.cfg
set prefix=(\$root)/boot/grub
configfile /boot/grub/grub.cfg
EOF
    
    # Create core.img with essential modules
    grub-mkimage -O i386-pc -o /tmp/core.img -p /boot/grub -c /tmp/grub_embed.cfg \
        -d "$grub_dir" \
        biosdisk iso9660 part_msdos fat ext2 normal boot linux configfile loopback chain \
        search search_label search_fs_file search_fs_uuid
    
    # Combine with cdboot.img to create final BIOS image
    cat "$grub_dir/cdboot.img" /tmp/core.img > "$iso_dir/boot/grub/bios.img"
    
    if [ ! -f "$iso_dir/boot/grub/bios.img" ]; then
        echo -e "${RED}Error: Failed to create BIOS boot image${NC}"
        exit 1
    fi
    
    rm -f /tmp/core.img /tmp/grub_embed.cfg
    echo -e "${GREEN}GRUB2 BIOS boot image created${NC}"
}

# Create GRUB2 UEFI boot image
create_grub_uefi_image() {
    local iso_dir="$1"
    local grub_efi_dir="$iso_dir/boot/grub/x86_64-efi"
    
    echo -e "${BLUE}Creating GRUB2 UEFI boot image...${NC}"
    
    if [ ! -d "$grub_efi_dir" ]; then
        echo -e "${RED}Error: GRUB x86_64-efi modules not found in $grub_efi_dir${NC}"
        exit 1
    fi
    
    # Create UEFI bootloader
    mkdir -p "$iso_dir/EFI/BOOT"
    grub-mkimage -O x86_64-efi -o "$iso_dir/EFI/BOOT/bootx64.efi" -p /boot/grub \
        -d "$grub_efi_dir" \
        boot linux ext2 fat iso9660 part_gpt part_msdos normal configfile loopback chain \
        efifwsetup efi_gop efi_uga ls search search_label search_fs_uuid search_fs_file \
        gfxterm gfxmenu gfxterm_background font echo video all_video test true loadenv
    
    # Create EFI boot image
    mkdir -p "$iso_dir/boot/grub"
    dd if=/dev/zero of="$iso_dir/boot/grub/efi.img" bs=1M count=10
    mkfs.vfat -F 12 "$iso_dir/boot/grub/efi.img"
    
    # Mount and copy files to EFI image
    mmd -i "$iso_dir/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
    mcopy -i "$iso_dir/boot/grub/efi.img" "$iso_dir/EFI/BOOT/bootx64.efi" ::/EFI/BOOT/
    
    echo -e "${GREEN}GRUB2 UEFI boot image created${NC}"
}

# Generate GRUB configuration
generate_grub_config() {
    local ISO_DIR="$1"
    local NAME="$2"
    local VMLINUZ="$3"
    local INITRD="$4"
    local HAS_LIVE="$5"
    
    mkdir -p "$ISO_DIR/boot/grub"

    cat > "$ISO_DIR/boot/grub/grub.cfg" <<'EOF'
# GRUB2 Configuration File

# Load modules
insmod all_video
insmod gfxterm
insmod gfxmenu
insmod png
insmod font

# Set graphics mode
if loadfont $prefix/fonts/unicode.pf2 ; then
  set gfxmode=auto
  set gfxpayload=keep
  terminal_output gfxterm
fi

# Theme configuration
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

# Set default and timeout
set default=0
set timeout=10
EOF

    if [ "$HAS_LIVE" = "true" ]; then
        cat >> "$ISO_DIR/boot/grub/grub.cfg" <<EOF

# Live System Entries
menuentry "$NAME - LIVE" {
    linux /live/$VMLINUZ boot=live config quiet splash
    initrd /live/$INITRD
}

menuentry "$NAME - Boot to RAM" {
    linux /live/$VMLINUZ boot=live config quiet splash toram
    initrd /live/$INITRD
}

menuentry "$NAME - Encrypted Persistence" {
    linux /live/$VMLINUZ boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$INITRD
}

menuentry "GRUBFM - (UEFI)" {
    chainloader /EFI/GRUB-FM/E2B-bootx64.efi
}

menuentry "Power Off" {
    halt
}

menuentry "Reboot" {
    reboot
}

EOF
    else
        cat >> "$ISO_DIR/boot/grub/grub.cfg" <<EOF

# Custom ISO - No Live System Detected

menuentry "GRUBFM - (UEFI)" {
    chainloader /EFI/GRUB-FM/E2B-bootx64.efi
}

menuentry "Load /boot/grub/sgd/main.cfg" {
    configfile /boot/grub/sgd/main.cfg
}

menuentry "Netboot.xyz (UEFI)" {
    chainloader /boot/grub/netboot.xyz/EFI/BOOT/BOOTX64.EFI
}

menuentry "Power Off" {
    halt
}

menuentry "Reboot" {
    reboot
}
EOF
    fi

    cat >> "$ISO_DIR/boot/grub/grub.cfg" <<'EOF'

EOF

    echo -e "${GREEN}GRUB configuration created: $ISO_DIR/boot/grub/grub.cfg${NC}"
}

#CREATE ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    echo -e "${BLUE}Creating hybrid GRUB2 ISO image...${NC}"
    
    # Use boot_hybrid.img if available, otherwise boot.img
    local boot_img="$source_dir/boot/grub/i386-pc/boot_hybrid.img"
    if [ ! -f "$boot_img" ]; then
        boot_img="$source_dir/boot/grub/i386-pc/boot.img"
        echo -e "${YELLOW}Using boot.img instead of boot_hybrid.img${NC}"
    fi
    
    # Create boot catalog directory if it doesn't exist
    mkdir -p "$source_dir/boot"
    
    # Create boot catalog (simpler approach that actually works)
    echo -e "${BLUE}Creating boot catalog...${NC}"
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$iso_label" \
        -output /dev/null \
        -graft-points "$source_dir" \
        -eltorito-boot boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/boot.catalog \
        -o /dev/null
    
    # Main ISO creation command
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$iso_label" \
        -full-iso9660-filenames \
        -R -J -joliet-long \
        -b boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        --grub2-mbr "$boot_img" \
        --eltorito-catalog boot/boot.catalog \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -append_partition 2 0xEF "$source_dir/boot/grub/efi.img" \
        -o "$output_file" \
        -graft-points \
            "$source_dir" \
            /boot/grub/bios.img="$source_dir/boot/grub/bios.img" \
            /boot/grub/efi.img="$source_dir/boot/grub/efi.img"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}ISO created successfully at: $output_file${NC}"
        echo -e "${YELLOW}File size: $(du -h "$output_file" | cut -f1)${NC}"
        
        # Add isohybrid MBR for better BIOS compatibility
        if command -v isohybrid &>/dev/null; then
            echo -e "${BLUE}Making ISO hybrid for better BIOS compatibility...${NC}"
            isohybrid "$output_file"
        fi
    else
        echo -e "${RED}Error creating ISO${NC}"
        exit 1
    fi
}

# Main script
main() {
    echo -e "${YELLOW}=== Pure GRUB2 ISO Creation Script ===${NC}"
    echo -e "${BLUE}This script creates a hybrid ISO using GRUB2 for both BIOS and UEFI${NC}\n"
    
    # Check dependencies
    if ! command -v xorriso &>/dev/null || ! command -v mkfs.vfat &>/dev/null || ! command -v grub-mkimage &>/dev/null; then
        echo -e "${YELLOW}Missing dependencies detected. Installing...${NC}"
        install_dependencies
    fi
    
    # Get source directory
    read -p "Enter the directory path to make bootable: " ISO_DIR
    ISO_DIR=$(realpath "$ISO_DIR" 2>/dev/null)
    
    if [ ! -d "$ISO_DIR" ]; then
        echo -e "${RED}Error: Directory $ISO_DIR does not exist.${NC}"
        exit 1
    fi
    
    # Download bootfiles
    download_bootfiles "$ISO_DIR"
    
    # Handle splash screen
    handle_splash_screen "$ISO_DIR"
    
    # Check for live system
    HAS_LIVE="false"
    VMLINUZ=""
    INITRD=""
    
    if [ -d "$ISO_DIR/live" ]; then
        echo -e "\n${YELLOW}Scanning for live system files...${NC}"
        
        for file in "$ISO_DIR/live"/vmlinuz*; do
            [ -f "$file" ] && VMLINUZ=$(basename "$file") && break
        done
        
        for file in "$ISO_DIR/live"/initrd*; do
            [ -f "$file" ] && INITRD=$(basename "$file") && break
        done
        
        if [ -n "$VMLINUZ" ] && [ -n "$INITRD" ]; then
            HAS_LIVE="true"
            echo -e "${GREEN}Live system detected:${NC}"
            echo -e "  vmlinuz: $VMLINUZ"
            echo -e "  initrd: $INITRD"
        else
            echo -e "${YELLOW}Live directory found but missing kernel/initrd files${NC}"
        fi
    else
        echo -e "${YELLOW}No live system directory found - creating standard bootable ISO${NC}"
    fi
    
    # Ask for system name
    read -p "Enter the name of the system/distro: " NAME
    NAME=${NAME:-"Custom-ISO"}
    
    # Create GRUB boot images
    create_grub_bios_image "$ISO_DIR"
    create_grub_uefi_image "$ISO_DIR"
    
    # Generate GRUB configuration
    generate_grub_config "$ISO_DIR" "$NAME" "$VMLINUZ" "$INITRD" "$HAS_LIVE"
    
    # Get output filename
    read -p "Enter the output ISO filename (e.g., MyDistro.iso): " iso_name
    iso_name=${iso_name:-"output.iso"}
    [[ "$iso_name" != *.iso ]] && iso_name="${iso_name}.iso"
    
    # Set output directory to parent of ISO_DIR
    output_dir=$(dirname "$ISO_DIR")
    output_file="$output_dir/$iso_name"
    
    # Get volume label
    read -p "Enter ISO volume label (max 32 chars, default: ${NAME^^}): " iso_label
    iso_label=${iso_label:-"${NAME^^}"}
    iso_label=$(echo "$iso_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    
    # Confirm and create ISO
    echo -e "\n${YELLOW}=== Summary ===${NC}"
    echo -e "Source Directory: ${BLUE}$ISO_DIR${NC}"
    echo -e "Output ISO: ${BLUE}$output_file${NC}"
    echo -e "Volume Label: ${BLUE}$iso_label${NC}"
    echo -e "Boot Method: ${GREEN}GRUB2 (BIOS + UEFI)${NC}"
    echo -e "Live System: ${HAS_LIVE^^}"
    
    read -p $'\nProceed with ISO creation? (y/n): ' confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_iso "$ISO_DIR" "$output_file" "$iso_label"
    else
        echo -e "${YELLOW}ISO creation cancelled.${NC}"
        exit 0
    fi
}

# Run main function
main
