#!/bin/bash

# Enhanced GRUB2 + ISOLINUX ISO Creation Script (BIOS+UEFI)
# Creates bootable ISO using GRUB2 for UEFI and ISOLINUX for BIOS systems

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
        sudo apt-get install -y xorriso mtools wget grub2-common grub-efi-amd64-bin isolinux syslinux-utils unzip
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso mtools wget grub2-tools grub2-efi-x64 syslinux unzip
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso mtools wget grub2-tools grub2-efi-x64 syslinux unzip
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso mtools wget grub efibootmgr syslinux unzip
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

# Download and extract isolinux files
download_isolinux_files() {
    local iso_dir="$1"
    local isolinux_url="https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/isolinux.zip"
    local temp_dir="/tmp/isolinux_files_$RANDOM"
    
    echo -e "${BLUE}Downloading ISOLINUX files from GitHub...${NC}"
    mkdir -p "$temp_dir"
    
    if ! wget --progress=bar:force "$isolinux_url" -O "$temp_dir/isolinux.zip"; then
        echo -e "${RED}Error: Failed to download ISOLINUX files${NC}"
        echo -e "${YELLOW}Please ensure isolinux.zip exists in your GitHub repository${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo -e "${BLUE}Extracting ISOLINUX files...${NC}"
    unzip -q "$temp_dir/isolinux.zip" -d "$iso_dir"
    
    # Verify essential isolinux files exist in the expected structure
    # isolinux.zip contains: isolinux/ directory with files inside
    if [ ! -f "$iso_dir/isolinux/isolinux.bin" ] || [ ! -f "$iso_dir/isolinux/vesamenu.c32" ]; then
        echo -e "${RED}Error: Essential ISOLINUX files missing${NC}"
        echo -e "${YELLOW}Expected structure: isolinux/isolinux.bin and isolinux/vesamenu.c32${NC}"
        echo -e "${BLUE}Found files:${NC}"
        find "$iso_dir/isolinux" -type f 2>/dev/null || echo "No isolinux directory found"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # List extracted files for confirmation
    echo -e "${GREEN}ISOLINUX files extracted:${NC}"
    ls -la "$iso_dir/isolinux/" | while read -r line; do
        echo -e "  $line"
    done
    
    rm -rf "$temp_dir"
    echo -e "${GREEN}ISOLINUX files installed successfully${NC}"
}

# Handle splash screen selection
handle_splash_screen() {
    local iso_dir="$1"
    local splash_path=""
    
    echo -e "\n${YELLOW}=== Splash Screen Configuration ===${NC}"
    echo "Would you like to add a custom splash.png for boot menus?"
    read -p "Enter 'y' for custom splash or 'n' for default: " use_custom
    
    if [[ "$use_custom" =~ ^[Yy]$ ]]; then
        read -p "Enter the full path to your splash.png file: " splash_path
        splash_path=$(realpath "$splash_path" 2>/dev/null)
        
        if [ -f "$splash_path" ]; then
            echo -e "${GREEN}Copying custom splash screen...${NC}"
            mkdir -p "$iso_dir/boot/grub"
            mkdir -p "$iso_dir/isolinux"
            cp "$splash_path" "$iso_dir/boot/grub/splash.png"
            cp "$splash_path" "$iso_dir/isolinux/splash.png"
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

# Generate ISOLINUX configuration
generate_isolinux_config() {
    local ISO_DIR="$1"
    local NAME="$2"
    local VMLINUZ="$3"
    local INITRD="$4"
    local HAS_LIVE="$5"
    
    mkdir -p "$ISO_DIR/isolinux"

    cat > "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
default vesamenu.c32
prompt 0
timeout 100

menu title $NAME LIVE - BIOS Boot
menu tabmsg Press TAB key to edit menu options
menu background splash.png
menu color title        1;36;44    #FFFFFFFF #00000000 std
menu color border       30;44      #40ffffff #a0000000 std
menu color sel          7;37;40    #e0ffffff #20ffffff all
menu color unsel        37;44      #50ffffff #a0000000 std
menu color help         37;40      #c0ffffff #00000000 std
menu color timeout_msg  37;40      #80ffffff #00000000 std
menu color timeout      1;37;40    #c0ffffff #00000000 std
menu color msg07        37;40      #90ffffff #a0000000 std
menu color tabmsg       31;40      #30ffffff #00000000 std

EOF

    if [ "$HAS_LIVE" = "true" ]; then
        cat >> "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
label live
  menu label ^$NAME - LIVE
  menu default
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live config quiet splash

label live_ram
  menu label $NAME - Boot ^to RAM
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live config quiet toram

label encrypted_persistence
  menu label $NAME - ^Encrypted Persistence
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence

label live_nomodeset
  menu label $NAME - Safe ^Graphics Mode
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live config quiet splash nomodeset

label live_failsafe
  menu label $NAME - ^Failsafe Mode
  kernel /live/$VMLINUZ
  append initrd=/live/$INITRD boot=live config noquiet nosplash

EOF
    else
        cat >> "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
label info
  menu label ^No Live System Detected
  kernel vesamenu.c32
  append isolinux/isolinux.cfg

EOF
    fi

    # Add utility entries if files exist
    if [ -f "$ISO_DIR/boot/grub/netboot.xyz/netboot.xyz.lkrn" ]; then
        cat >> "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
label netboot_bios
  menu label ^Netboot.xyz (BIOS)
  kernel /boot/grub/netboot.xyz/netboot.xyz.lkrn

EOF
    fi

    cat >> "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
label grub_uefi
  menu label Switch to ^GRUB2 (UEFI Mode)
  com32 chain.c32
  append efi=/EFI/BOOT/bootx64.efi

label separator1
  menu label ---

label memtest
  menu label ^Memory Test
  kernel /boot/memtest86+/memtest.bin

label hdt
  menu label ^Hardware Detection Tool
  com32 hdt.c32

label separator2
  menu label ---

label reboot
  menu label ^Reboot
  com32 reboot.c32

label poweroff
  menu label ^Power Off
  com32 poweroff.c32

EOF

    echo -e "${GREEN}ISOLINUX configuration created: $ISO_DIR/isolinux/isolinux.cfg${NC}"
}

# Scan directory for WIM files and create boot configuration
scan_and_create_wim_boot() {
    local iso_dir="$1"
    local wim_config="$iso_dir/boot/grub/WIM-Boot.cfg"
    local wim_files_found=0
    
    echo -e "${BLUE}Scanning for WIM files to create boot entries...${NC}"
    
    # Create the WIM boot configuration file
    mkdir -p "$iso_dir/boot/grub"
    cat > "$wim_config" <<'EOF'
# Auto-generated WIM Boot Configuration
# This file contains boot entries for discovered WIM files

set timeout=30
set default=0

# Load modules
insmod all_video
insmod gfxterm
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

EOF

    # Function to add menu entry for WIM file
    add_wim_entry() {
        local wim_path="$1"
        local display_name="$2"
        
        cat >> "$wim_config" <<EOF
menuentry "$display_name" {
    echo "Loading $display_name..."
    echo "WIM file: $wim_path"
    if [ -f /boot/wimboot ]; then
        linux /boot/wimboot
        initrd $wim_path
    elif [ -f /wimboot ]; then
        linux /wimboot
        initrd $wim_path
    else
        echo "Error: wimboot not found!"
        echo "Please ensure wimboot is available in /boot/ or root directory"
        echo "Press any key to return to menu..."
        read
        configfile /boot/grub/grub.cfg
    fi
}

EOF
        ((wim_files_found++))
    }
    
    # Search for WIM files and create menu entries
    echo -e "${YELLOW}Searching for WIM files in ISO directory...${NC}"
    
    # Search for .wim files recursively
    while IFS= read -r -d '' wim_file; do
        # Convert absolute path to relative path from ISO root
        rel_path="${wim_file#$iso_dir}"
        
        # Extract directory and filename for intelligent naming
        wim_dir=$(dirname "$rel_path")
        filename=$(basename "$wim_file" .wim)
        
        # Create intelligent display names based on path and filename
        case "$rel_path" in
            */[Hh]irens*/*|*/[Hh]iren*/*|*/HBCD*/*|*/hbcd*/*)
                if [[ "$filename" == "boot" ]]; then
                    display_name="Hiren's BootCD PE"
                else
                    display_name="Hiren's BootCD - $(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
                fi
                ;;
            */[Ww]indows*/*|*/WIN*/*|*/win*/*)
                if [[ "$filename" == "boot" ]]; then
                    display_name="Windows Boot Environment"
                elif [[ "$filename" =~ [Pp][Ee] ]]; then
                    display_name="Windows PE"
                else
                    display_name="Windows - $(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
                fi
                ;;
            */[Pp][Ee]/*|*/winpe*/*|*/WinPE*/*)
                if [[ "$filename" == "boot" ]]; then
                    display_name="Windows PE"
                else
                    display_name="Windows PE - $(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
                fi
                ;;
            */[Rr]escue*/*|*/RESCUE*/*)
                display_name="System Rescue Environment"
                ;;
            */[Aa]ntivirus*/*|*/AV*/*|*/av*/*)
                display_name="Antivirus Rescue Disk"
                ;;
            */[Pp]artition*/*|*/[Gg]parted*/*)
                display_name="Partition Management Tools"
                ;;
            */[Cc]lonezilla*/*|*/CLONEZILLA*/*)
                display_name="Clonezilla Live PE"
                ;;
            */[Dd]iagnostic*/*|*/[Tt]est*/*)
                display_name="Hardware Diagnostic Tools"
                ;;
            */[Uu]efi*/*|*/EFI*/*)
                display_name="UEFI Tools Environment"
                ;;
            */[Tt]ools*/*|*/TOOLS*/*)
                display_name="System Tools - $(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
                ;;
            *)
                # Generic naming based on directory and filename
                if [[ "$filename" == "boot" ]]; then
                    # Use directory name for boot.wim files
                    dir_name=$(basename "$wim_dir")
                    if [[ "$dir_name" == "." ]] || [[ "$dir_name" == "/" ]]; then
                        display_name="Windows Boot Environment"
                    else
                        display_name="$(echo "$dir_name" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g') PE"
                    fi
                else
                    # Use filename for other WIM files
                    display_name="$(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
                fi
                ;;
        esac
        
        echo -e "  Found: ${GREEN}$rel_path${NC} → $display_name"
        add_wim_entry "$rel_path" "$display_name"
        
    done < <(find "$iso_dir" -name "*.wim" -type f -print0 2>/dev/null)
    
    # Add return to main menu option
    cat >> "$wim_config" <<'EOF'
menuentry "Return to Main Menu" {
    configfile /boot/grub/grub.cfg
}

EOF
    
    if [ $wim_files_found -eq 0 ]; then
        echo -e "${YELLOW}No WIM files found to boot${NC}"
        cat >> "$wim_config" <<'EOF'
menuentry "No WIM Files Found" {
    echo "No WIM files were discovered in this ISO."
    echo "WIM files are Windows Imaging Format files that can be booted"
    echo "using wimboot. Please ensure:"
    echo "1. WIM files are present in the ISO"
    echo "2. wimboot binary is available in /boot/ directory"
    echo ""
    echo "Press any key to return to main menu..."
    read
    configfile /boot/grub/grub.cfg
}

EOF
    else
        echo -e "${GREEN}Created boot entries for $wim_files_found WIM files${NC}"
        echo -e "${YELLOW}Note: WIM booting requires wimboot binary in /boot/ directory${NC}"
    fi
    
    echo -e "${GREEN}WIM Boot configuration saved: $wim_config${NC}"
}

# Scan directory for EFI files and create chainloader configuration
scan_and_create_efi_chainloader() {
    local iso_dir="$1"
    local efi_config="$iso_dir/boot/grub/EFI-Chainloader.cfg"
    local efi_files_found=0
    
    echo -e "${BLUE}Scanning for EFI files to create chainloader entries...${NC}"
    
    # Create the EFI chainloader configuration file
    mkdir -p "$iso_dir/boot/grub"
    cat > "$efi_config" <<'EOF'
# Auto-generated EFI Chainloader Configuration
# This file contains chainloader entries for discovered EFI files

set timeout=30
set default=0

# Load modules
insmod all_video
insmod gfxterm
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

EOF

    # Function to add menu entry for EFI file
    add_efi_entry() {
        local efi_path="$1"
        local display_name="$2"
        
        cat >> "$efi_config" <<EOF
menuentry "$display_name" {
    chainloader $efi_path
}

EOF
        ((efi_files_found++))
    }
    
    # Search for EFI files and create menu entries
    echo -e "${YELLOW}Searching for EFI files in ISO directory...${NC}"
    
    # Search for .efi files recursively, excluding common system locations we don't want
    while IFS= read -r -d '' efi_file; do
        # Convert absolute path to relative path from ISO root
        rel_path="${efi_file#$iso_dir}"
        
        # Skip if it's our own bootx64.efi or GRUB modules
        if [[ "$rel_path" == "/EFI/BOOT/bootx64.efi" ]] || [[ "$rel_path" == /boot/grub/x86_64-efi/* ]]; then
            continue
        fi
        
        # Extract filename without extension for display name
        filename=$(basename "$efi_file" .efi)
        
        # Create a user-friendly display name
        case "$rel_path" in
            */grubfm*|*/GRUB-FM*|*/grub-fm*)
                display_name="GRUB File Manager"
                ;;
            */supergrub*|*/SUPERGRUB*|*/sgd*)
                display_name="Super GRUB2 Disk"
                ;;
            */netboot*|*/NETBOOT*)
                display_name="Netboot.xyz"
                ;;
            */memtest*|*/MEMTEST*)
                display_name="Memory Test (UEFI)"
                ;;
            */gparted*|*/GPARTED*)
                display_name="GParted Live"
                ;;
            */clonezilla*|*/CLONEZILLA*)
                display_name="Clonezilla Live"
                ;;
            */rescue*|*/RESCUE*)
                display_name="System Rescue"
                ;;
            */windows*|*/WINDOWS*)
                display_name="Windows Boot Manager"
                ;;
            */microsoft*|*/MICROSOFT*)
                display_name="Microsoft Boot Manager"
                ;;
            *)
                # Generic name based on filename
                display_name=$(echo "$filename" | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')
                ;;
        esac
        
        echo -e "  Found: ${GREEN}$rel_path${NC} → $display_name"
        add_efi_entry "$rel_path" "$display_name"
        
    done < <(find "$iso_dir" -name "*.efi" -type f -print0 2>/dev/null)
    
    # Add return to main menu option
    cat >> "$efi_config" <<'EOF'
menuentry "Return to Main Menu" {
    configfile /boot/grub/grub.cfg
}

EOF
    
    if [ $efi_files_found -eq 0 ]; then
        echo -e "${YELLOW}No additional EFI files found to chainload${NC}"
        cat >> "$efi_config" <<'EOF'
menuentry "No EFI Files Found" {
    echo "No additional EFI files were discovered in this ISO."
    echo "Press any key to return to main menu..."
    read
    configfile /boot/grub/grub.cfg
}

EOF
    else
        echo -e "${GREEN}Created chainloader entries for $efi_files_found EFI files${NC}"
    fi
    
    echo -e "${GREEN}EFI Chainloader configuration saved: $efi_config${NC}"
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

menuentry "GRUBFM (UEFI)" {
    chainloader /EFI/GRUB-FM/E2B-bootx64.efi
}

menuentry "SUPERGRUB (UEFI)" {
    configfile /boot/grub/sgd/main.cfg
}

menuentry "Netboot.xyz (UEFI)" {
    chainloader /boot/grub/netboot.xyz/EFI/BOOT/BOOTX64.EFI
}

menuentry "EFI Chainloader Menu" {
    configfile /boot/grub/EFI-Chainloader.cfg
}

menuentry "WIM Boot Menu" {
    configfile /boot/grub/WIM-Boot.cfg
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

menuentry "GRUBFM (UEFI)" {
    chainloader /EFI/GRUB-FM/E2B-bootx64.efi
}

menuentry "SUPERGRUB (UEFI)" {
    configfile /boot/grub/sgd/main.cfg
}

menuentry "Netboot.xyz (UEFI)" {
    chainloader /boot/grub/netboot.xyz/EFI/BOOT/BOOTX64.EFI
}

menuentry "EFI Chainloader Menu" {
    configfile /boot/grub/EFI-Chainloader.cfg
}

menuentry "WIM Boot Menu" {
    configfile /boot/grub/WIM-Boot.cfg
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

# Create hybrid ISO with both ISOLINUX and GRUB2
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    echo -e "${BLUE}Creating hybrid ISO with ISOLINUX (BIOS) + GRUB2 (UEFI)...${NC}"
    
    # Verify isolinux files exist
    if [ ! -f "$source_dir/isolinux/isolinux.bin" ]; then
        echo -e "${RED}Error: isolinux.bin not found${NC}"
        exit 1
    fi
    
    # Check for isohybrid MBR in isolinux directory first, then system location
    local mbr_file=""
    if [ -f "$source_dir/isolinux/isohdpfx.bin" ]; then
        mbr_file="$source_dir/isolinux/isohdpfx.bin"
        echo -e "${GREEN}Using MBR from isolinux directory${NC}"
    elif [ -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]; then
        mbr_file="/usr/lib/ISOLINUX/isohdpfx.bin"
        echo -e "${GREEN}Using system MBR file${NC}"
    elif [ -f "/usr/lib/syslinux/bios/isohdpfx.bin" ]; then
        mbr_file="/usr/lib/syslinux/bios/isohdpfx.bin"
        echo -e "${GREEN}Using syslinux MBR file${NC}"
    else
        echo -e "${YELLOW}Warning: isohdpfx.bin not found, creating ISO without isohybrid MBR${NC}"
    fi
    
    # Create the ISO with multiple boot methods
    local xorriso_cmd=(
        xorriso -as mkisofs
        -iso-level 3
        -volid "$iso_label"
        -full-iso9660-filenames
        -R -J -joliet-long
    )
    
    # Add MBR if available
    if [ -n "$mbr_file" ]; then
        xorriso_cmd+=(-isohybrid-mbr "$mbr_file")
    fi
    
    # Add BIOS boot options
    xorriso_cmd+=(
        -b isolinux/isolinux.bin
        -c isolinux/boot.cat
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
    )
    
    # Add UEFI boot options
    xorriso_cmd+=(
        -eltorito-alt-boot
        -e boot/grub/efi.img
        -no-emul-boot
    )
    
    # Add isohybrid GPT support if MBR is available
    if [ -n "$mbr_file" ]; then
        xorriso_cmd+=(-isohybrid-gpt-basdat)
    fi
    
    # Add EFI partition and output
    xorriso_cmd+=(
        -append_partition 2 0xEF "$source_dir/boot/grub/efi.img"
        -o "$output_file"
        "$source_dir"
    )
    
    # Execute the command
    "${xorriso_cmd[@]}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Hybrid ISO created successfully!${NC}"
        echo -e "${BLUE}Output file: $output_file${NC}"
        echo -e "${YELLOW}File size: $(du -h "$output_file" | cut -f1)${NC}"
        echo ""
        echo -e "${GREEN}Boot Methods:${NC}"
        echo -e "  ${BLUE}BIOS Legacy:${NC} ISOLINUX with vesamenu"
        echo -e "  ${BLUE}UEFI:${NC} GRUB2 with graphical menu"
        echo -e "  ${BLUE}USB/HDD:${NC} Hybrid mode supported"
        
        # Add isohybrid for better compatibility if available and not already applied
        if command -v isohybrid &>/dev/null && [ -n "$mbr_file" ]; then
            echo -e "${BLUE}Optimizing for USB/HDD boot...${NC}"
            isohybrid --uefi "$output_file" 2>/dev/null || echo -e "${YELLOW}Note: isohybrid UEFI optimization failed (non-critical)${NC}"
        fi
    else
        echo -e "${RED}Error creating ISO${NC}"
        exit 1
    fi
}

# Main script
main() {
    echo -e "${YELLOW}=== Enhanced ISO Creation Script (ISOLINUX + GRUB2) ===${NC}"
    echo -e "${BLUE}Creates hybrid ISO with ISOLINUX (BIOS) and GRUB2 (UEFI) support${NC}\n"
    
    # Check for root privileges for some operations
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Warning: Running as root. Consider running as regular user.${NC}"
    fi
    
    # Check dependencies
    missing_deps=()
    for cmd in xorriso mkfs.vfat grub-mkimage unzip wget; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${BLUE}Installing dependencies...${NC}"
        install_dependencies
    fi
    
    # Get source directory
    read -p "Enter the directory path to make bootable: " ISO_DIR
    ISO_DIR=$(realpath "$ISO_DIR" 2>/dev/null)
    
    if [ ! -d "$ISO_DIR" ]; then
        echo -e "${RED}Error: Directory $ISO_DIR does not exist.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Working with directory: $ISO_DIR${NC}"
    
    # Download bootfiles
    download_bootfiles "$ISO_DIR"
    download_isolinux_files "$ISO_DIR"
    
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
            echo -e "  Kernel: $VMLINUZ"
            echo -e "  Initrd: $INITRD"
        else
            echo -e "${YELLOW}Live directory found but missing kernel/initrd files${NC}"
        fi
    else
        echo -e "${YELLOW}No live system directory found${NC}"
    fi
    
    # Ask for system name
    read -p "Enter the name of the system/distro: " NAME
    NAME=${NAME:-"Custom-ISO"}
    
    # Create boot images and configurations
    echo -e "\n${BLUE}Setting up boot systems...${NC}"
    create_grub_uefi_image "$ISO_DIR"
    scan_and_create_efi_chainloader "$ISO_DIR"
    scan_and_create_wim_boot "$ISO_DIR"
    generate_isolinux_config "$ISO_DIR" "$NAME" "$VMLINUZ" "$INITRD" "$HAS_LIVE"
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
    echo -e "\n${YELLOW}=== Build Summary ===${NC}"
    echo -e "Source Directory: ${BLUE}$ISO_DIR${NC}"
    echo -e "Output ISO: ${BLUE}$output_file${NC}"
    echo -e "Volume Label: ${BLUE}$iso_label${NC}"
    echo -e "System Name: ${BLUE}$NAME${NC}"
    echo -e "Live System: ${GREEN}${HAS_LIVE^^}${NC}"
    echo -e "BIOS Boot: ${GREEN}ISOLINUX${NC}"
    echo -e "UEFI Boot: ${GREEN}GRUB2${NC}"
    
    read -p $'\nProceed with ISO creation? (y/n): ' confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_iso "$ISO_DIR" "$output_file" "$iso_label"
        echo -e "\n${GREEN}=== ISO Creation Complete ===${NC}"
        echo -e "Your bootable ISO is ready at: ${BLUE}$output_file${NC}"
    else
        echo -e "${YELLOW}ISO creation cancelled.${NC}"
        exit 0
    fi
}

# Run main function
main "$@"
