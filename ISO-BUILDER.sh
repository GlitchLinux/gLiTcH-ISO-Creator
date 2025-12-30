#!/bin/bash

# Nano ISO Creator - Minimal Live System ISO Builder
# Auto-chainloads from ISOLINUX to GRUB2 instantly

# Color codes
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;35m'
BLUE='\033[1;35m'
NC='\033[0m'

# Install minimal dependencies
install_dependencies() {
    local missing_deps=()
    for cmd in xorriso wget lzma tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${BLUE}Installing required packages: ${missing_deps[*]}${NC}"
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update && sudo apt-get install -y xorriso wget lzma tar
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y xorriso wget lzma tar
        elif [ -x "$(command -v pacman)" ]; then
            sudo pacman -S --noconfirm xorriso wget lzma tar
        else
            echo -e "${RED}Error: Cannot install dependencies automatically${NC}"
            exit 1
        fi
    fi
}

# Download hybrid bootfiles
download_bootfiles() {
    local target_dir="$1"
    local temp_dir="/tmp/nano_bootfiles_$$"
    
    echo -e "${NC}   ->${GREEN} Downloading Bootfiles${NC}"
    mkdir -p "$temp_dir"
    
    if ! wget --quiet \
        "https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/ISO-Hybrid-Base-2.tar.lzma" \
        -O "$temp_dir/bootfiles.tar.lzma" 2>/dev/null; then
        echo -e "${RED}Error: Failed to download bootfiles${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo -e "${NC}   ->${GREEN} Extracting bootfiles${NC}"
    unlzma "$temp_dir/bootfiles.tar.lzma" 2>/dev/null
    tar -xf "$temp_dir/bootfiles.tar" -C "$target_dir" --strip-components=1 2>/dev/null
    rm -rf "$temp_dir"
    chmod -R 755 "$target_dir" 2>/dev/null
}

# Create minimal GRUB config with proven theme approach
create_grub_config() {
    local iso_dir="$1"
    local name="$2"
    local vmlinuz="$3"
    local initrd="$4"
    local live_dir="$5"
    
    mkdir -p "$iso_dir/boot/grub"
    
    # Copy splash.png to boot/grub directory
    if [ -f "$iso_dir/isolinux/splash.png" ]; then
        echo -e "${NC}   ->${GREEN}Copying splash screen for GRUB ${NC}"
        cp "/boot/grub/splash.png" "$iso_dir/boot/grub/splash.png" 2>/dev/null
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/isolinux/grub.png" 2>/dev/null
    fi
    
    # Create theme configuration
    cat > "$iso_dir/boot/grub/theme.cfg" <<'EOF'
title-color: "white"
title-text: " "
title-font: "Sans Regular 16"
desktop-color: "black"
desktop-image: "/boot/grub/splash.png"
message-color: "white"
message-bg-color: "black"
terminal-font: "Sans Regular 12"

+ boot_menu {
  top = 150
  left = 15%
  width = 75%
  height = 150
  item_font = "Sans Regular 12"
  item_color = "grey"
  selected_item_color = "white"
  item_height = 20
  item_padding = 15
  item_spacing = 5
}

+ vbox {
  top = 100%
  left = 2%
  + label {text = "Press 'E' key to edit" font = "Sans 10" color = "white" align = "left"}
}
EOF
    
    # Create main GRUB configuration using proven approach
    cat > "$iso_dir/boot/grub/grub.cfg" <<EOF
# GRUB2 Configuration - Proven Theme Approach

# Font path and graphics setup
if loadfont \$prefix/fonts/font.pf2 ; then
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

# Background and color setup
if background_image "/boot/grub/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
elif background_image "/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi

# Load theme if available
if [ -s \$prefix/theme.cfg ]; then
  set theme=\$prefix/theme.cfg
fi

# Basic settings
set default=0
set timeout=10

# Live System Entries
EOF

    if [ "$live_dir" = "casper" ]; then
        # Ubuntu/Casper configuration
        cat >> "$iso_dir/boot/grub/grub.cfg" <<EOF
menuentry "$name - LIVE" {
    linux /casper/$vmlinuz boot=casper quiet splash
    initrd /casper/$initrd
}

menuentry "$name - Boot to RAM" {
    linux /casper/$vmlinuz boot=casper quiet splash toram
    initrd /casper/$initrd
}

menuentry "$name - Encrypted Persistence" {
    linux /casper/$vmlinuz boot=casper components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /casper/$initrd
}

if [ -f /boot/grub/custom.cfg ]; then
    menuentry "Custom Options" {
        configfile /boot/grub/custom.cfg
    }
fi

EOF
    else
        # Debian Live configuration
        cat >> "$iso_dir/boot/grub/grub.cfg" <<EOF
menuentry "$name - LIVE" {
    linux /live/$vmlinuz boot=live config quiet splash
    initrd /live/$initrd
}

menuentry "$name - Boot to RAM" {
    linux /live/$vmlinuz boot=live config quiet splash toram
    initrd /live/$initrd
}

menuentry "$name - Encrypted Persistence" {
    linux /live/$vmlinuz boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$initrd
}

menuentry "$name - Unencrypted Persistence" {
    linux /live/$vmlinuz boot=live components quiet splash components quiet splash persistence
    initrd /live/$initrd
}

if [ -f /boot/grub/custom.cfg ]; then
    menuentry "Custom Options" {
        configfile /boot/grub/custom.cfg
    }
fi

EOF
    fi

    cat >> "$iso_dir/boot/grub/grub.cfg" <<'EOF'

EOF

    #echo -e "${GREEN}Created GRUB configuration with proven theme approach${NC}"
}

# Create auto-chainloading ISOLINUX config
create_isolinux_config() {
    local iso_dir="$1"
    
    cat > "$iso_dir/isolinux/isolinux.cfg" <<'EOF'
default grub2_chainload
timeout 1
prompt 0

label grub2_chainload
  linux /boot/grub/lnxboot.img
  initrd /boot/grub/core.img
EOF
}

# Create autorun.inf
create_autorun() {
    local iso_dir="$1"
    local name="$2"
    
    cat > "$iso_dir/autorun.inf" <<EOF
[Autorun]
icon=iso.ico
label=$name
EOF
}

# Create ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local volume_label="$3"
    #clear
    echo ""
    echo -e "${GREEN}   ╭─────────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}   │${NC} You can now add custom files include in ISO ${GREEN}│${NC}"
    echo -e "${GREEN}   │${NC}    press ENTER to complete the ISO build    ${GREEN}│${NC}" 
    echo -e "${GREEN}   ╰─────────────────────────────────────────────╯${NC}"
    echo ""
    read -p "    "
    #echo -e "${NC}   -> ${NC}${GREEN} Output File:${NC} $output_file${NC}"
    # Use isohdpfx.bin from bootfiles if available
    local mbr_file="$source_dir/isolinux/isohdpfx.bin"
    if [ ! -f "$mbr_file" ]; then
        mbr_file="/usr/lib/ISOLINUX/isohdpfx.bin"
    fi
    
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$volume_label" \
        -full-iso9660-filenames \
        -R -J -joliet-long \
        -isohybrid-mbr "$mbr_file" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -append_partition 2 0xEF "$source_dir/boot/grub/efi.img" \
        -o "$output_file" \
        "$source_dir" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$output_file" | cut -f1)
        echo -e "${NC}     ${GREEN} ISO Created Successfully!${NC}${GREEN} ✅ ${NC}"
        echo ""
	echo -e "${NC}     ${YELLOW} Path: ${NC}$output_file${NC}"
        echo -e "${NC}     ${YELLOW} Size: ${NC}$size${NC}"
	#sleep 2
        return 0
    else
        echo -e "${RED}❌ ISO creation failed${NC}"
        return 1
    fi
}

# Main creation function
create_live_iso() {
    local parent_dir="$1"
    
    # Validate parent directory
    if [ ! -d "$parent_dir" ]; then
        echo -e "${RED}Error: Directory not found: $parent_dir${NC}"
        return 1
    fi
    
    # Auto-detect live system type and directory
    local live_dir=""
    local live_path=""
    local system_type=""
    
    # First determine which live system type we have
    if [ -d "$parent_dir/live" ]; then
        live_dir="live"
        live_path="$parent_dir/live"
        system_type="Debian Live"
    elif [ -d "$parent_dir/casper" ]; then
        live_dir="casper"
        live_path="$parent_dir/casper"
        system_type="Ubuntu/Casper"
    else
        echo -e "${RED}Error: No live system found in $parent_dir${NC}"
        echo -e "${NC}Expected: $parent_dir/live or $parent_dir/casper${NC}"
        return 1
    fi
    
    # Now find kernel and initrd files in the correct live path
    local vmlinuz=""
    local initrd=""
    
    # Find vmlinuz (kernel) file
    for file in "$live_path"/vmlinuz*; do
        if [ -f "$file" ]; then
            vmlinuz=$(basename "$file")
            break
        fi
    done
    
    # Find initrd file - handle different naming conventions
    if [ "$live_dir" = "casper" ]; then
        # Ubuntu/Casper: Look for initrd files
        for file in "$live_path"/initrd* "$live_path"/initrd.img* "$live_path"/initramfs*; do
            if [ -f "$file" ]; then
                initrd=$(basename "$file")
                break
            fi
        done
    else
        # Debian Live: Look for initrd files
        for file in "$live_path"/initrd* "$live_path"/initramfs*; do
            if [ -f "$file" ]; then
                initrd=$(basename "$file")
                break
            fi
        done
    fi
    
    # Verify we found both files
    if [ -z "$vmlinuz" ] || [ -z "$initrd" ]; then
        echo -e "${RED}Error: Missing kernel or initrd in $live_path${NC}"
        echo -e "${YELLOW}Found files in $live_path:${NC}"
        ls -la "$live_path"/ | grep -E 'vmlinuz|initrd|initramfs'
        echo -e "${YELLOW}Expected: vmlinuz* and initrd*/initramfs* files${NC}"
        return 1
    fi
    
    echo -e "${GREEN}   Identified Bootfiles & Distro ${NC}"
    echo ""   
    echo -e "${NC}   $vmlinuz ${GREEN}✅${NC}"
    echo -e "${NC}   $initrd ${GREEN}✅${NC}"
    echo -e "${NC}   Distro: $system_type ${NC}${GREEN}✅${NC}"

    # Get grandparent directory for output and customization
    local grandparent_dir=$(dirname "$parent_dir")
    local dir_name=$(basename "$parent_dir")
    local customize_dir="$grandparent_dir/ISO_CUSTOMIZE"
    
    # Get filenames from user
    echo ""
    echo -e "${GREEN}   ISO Naming:${NC}"
    echo ""
    echo -e "${GREEN}   ENTER${NC} to use ${YELLOW}\"${dir_name}.iso\"${NC} as iso name${NC}"
    read -p "   -> Or enter new name: " iso_name
    echo ""
    iso_name=${iso_name:-"${dir_name}.iso"}
    [[ "$iso_name" != *.iso ]] && iso_name="${iso_name}.iso"
    echo -e "${GREEN}   ENTER${NC} to use ${YELLOW}\"${dir_name}\"${NC} as system name${NC}" 
    read -p "   -> Or enter new name: " system_name 
    echo ""
    system_name=${system_name:-"$dir_name"}
    local volume_default=$(echo "$dir_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    echo -e "${GREEN}   ENTER${NC} to use ${YELLOW}\"${volume_default}\"${NC} as volume name${NC}"
    read -p "   -> Or enter new name: " volume_name   
    echo "" 
    volume_name=${volume_name:-"$volume_default"}
    volume_name=$(echo "$volume_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    echo ""

    # Set output path in grandparent directory
    local output_file="$grandparent_dir/$iso_name"
    
    # Create working directory
    rm -r -f /tmp/nano_iso/
    local work_dir="/tmp/nano_iso"
    mkdir -p "$work_dir"
    
    clear
    echo ""
    echo -e "${NC}     ${YELLOW} Starting ISO Build! ${NC}"
    echo -e "${NC}   ->${GREEN} Output File:${NC}${NC} $output_file${NC}"
    
    # Copy entire parent directory structure
    echo -e "${NC}   ->${GREEN} Copying system files ${NC}"
    cp -r "$parent_dir"/* "$work_dir/"
    
    # Download and setup bootfiles
    download_bootfiles "$work_dir"
    
    # Create configurations
    create_grub_config "$work_dir" "$system_name" "$vmlinuz" "$initrd" "$live_dir"
    create_isolinux_config "$work_dir"
    create_autorun "$work_dir" "$system_name"
    
    # Create ISO
    if create_iso "$work_dir" "$output_file" "$volume_name"; then
        rm -rf "$work_dir"
        return 0
    else
        rm -rf "$work_dir"
        return 1
    fi
}

# Main loop
main() {
    echo ""
    echo -e "${YELLOW} ╭──── gLiTcH ISO Compiler ────╮${NC}"
    echo -e "${YELLOW} │${NC} BY: ${GREEN}https://glitchlinux.wtf${NC} ${YELLOW}│${NC}"
    echo -e "${YELLOW} │${NC} BIOS & EFI live ISO builder ${YELLOW}│${NC}"
    echo -e "${YELLOW} │${NC} grub2 syslinux chainloading ${YELLOW}│${NC}"
    echo -e "${YELLOW} │${NC} For Debian & Ubuntu distros ${YELLOW}│${NC}"
    echo -e "${YELLOW} ╰─────────────────────────────╯${NC}"
    #echo ""
    # Check dependencies
    install_dependencies
    
    while true; do
        echo -e "${GREEN}  ╭──────────────────────────╮ ${NC}"
	echo -e "${GREEN}  │${NC} Prepare: /mydistro/live/ ${GREEN}│${NC}"
	echo -e "${GREEN}  │${NC} live dir must contain -> ${GREEN}│${NC}"
	echo -e "${GREEN}  │${NC} initrd vmlinuz .squashfs ${GREEN}│${NC}"
        echo -e "${GREEN}  ╰──────────────────────────╯${NC}"
	echo ""
        echo -e "${GREEN}   Enter parent dir of ${NC}live${NC}"
        echo ""        
	read -p "   -> " parent_dir
	echo ""        

        if [ -z "$parent_dir" ]; then
            echo -e "${YELLOW}Empty path. Exiting.${NC}"
            break
        fi
        
        # Expand tilde and resolve path
        parent_dir="${parent_dir/#\~/$HOME}"
        parent_dir=$(realpath "$parent_dir" 2>/dev/null)
        
        if create_live_iso "$parent_dir"; then
            echo ""
        else
            echo -e "\n${RED} ISO project failed!${NC}"
        fi
        
        read -p "      Create another ISO? (y/n): " continue_choice
        
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Thanks for using Nano ISO Creator!${NC}"
            break
        fi
    done
}

# Run main function
main "$@"
