#!/bin/bash

# Nano ISO Creator - Minimal Live System ISO Builder
# Auto-chainloads from ISOLINUX to GRUB2 instantly
# Modified workflow: immediate file copying and user editing phase

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Download hybrid bootfiles directly to target directory
download_bootfiles() {
    local target_dir="$1"
    local temp_dir="/tmp/nano_bootfiles_$$"
    
    echo -e "${BLUE}Downloading bootfiles to: $target_dir${NC}"
    mkdir -p "$temp_dir"
    
    if ! wget -q --progress=bar:force \
        "https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BOOTFILES.tar.lzma" \
        -O "$temp_dir/bootfiles.tar.lzma"; then
        echo -e "${RED}Error: Failed to download bootfiles${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo -e "${BLUE}Extracting bootfiles...${NC}"
    unlzma "$temp_dir/bootfiles.tar.lzma"
    tar -xf "$temp_dir/bootfiles.tar" -C "$target_dir" --strip-components=1
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ Bootfiles installed in: $target_dir${NC}"
}

# Create GRUB config with user-defined menu entries
create_grub_config() {
    local iso_dir="$1"
    local system_name="$2"
    local vmlinuz="$3"
    local initrd="$4"
    local live_dir="$5"
    local menu_entries="$6"
    
    mkdir -p "$iso_dir/boot/grub"
    
    # Copy splash.png to boot/grub directory
    if [ -f "$iso_dir/isolinux/splash.png" ]; then
        echo -e "${BLUE}Copying splash screen for GRUB...${NC}"
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/boot/grub/splash.png" 2>/dev/null
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/splash.png" 2>/dev/null
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
    
    # Create main GRUB configuration header
    cat > "$iso_dir/boot/grub/grub.cfg" <<EOF
# GRUB2 Configuration - $system_name

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

# Live System Menu Entries
EOF

    # Add user-defined menu entries
    echo "$menu_entries" >> "$iso_dir/boot/grub/grub.cfg"

    # Add standard system entries
    cat >> "$iso_dir/boot/grub/grub.cfg" <<'EOF'

menuentry "Reboot" {
    reboot
}

menuentry "Power Off" {
    halt
}
EOF

    echo -e "${GREEN}✅ GRUB configuration created${NC}"
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
icon=glitch.ico
label=$name
EOF
}

# Get menu entries from user
get_menu_entries() {
    local live_dir="$1"
    local system_name="$2"
    local vmlinuz="$3"
    local initrd="$4"
    
    echo -e "\n${CYAN}=== Configure GRUB Menu Entries ===${NC}"
    echo -e "${YELLOW}Choose menu entry configuration:${NC}"
    echo -e "1) Default entries (Live, Safe Mode, RAM Boot)"
    echo -e "2) Minimal entries (Live only)"
    echo -e "3) Custom entries (manual input)"
    
    read -p "Select option (1-3): " menu_choice
    
    local menu_entries=""
    
    case $menu_choice in
        1)
            if [ "$live_dir" = "casper" ]; then
                menu_entries=$(cat <<EOF
menuentry "$system_name - LIVE" {
    linux /casper/$vmlinuz boot=casper quiet splash
    initrd /casper/$initrd
}

menuentry "$system_name - Boot to RAM" {
    linux /casper/$vmlinuz boot=casper quiet splash toram
    initrd /casper/$initrd
}

menuentry "$system_name - Safe Graphics" {
    linux /casper/$vmlinuz boot=casper quiet splash nomodeset
    initrd /casper/$initrd
}
EOF
)
            else
                menu_entries=$(cat <<EOF
menuentry "$system_name - LIVE" {
    linux /live/$vmlinuz boot=live config quiet splash
    initrd /live/$initrd
}

menuentry "$system_name - Boot to RAM" {
    linux /live/$vmlinuz boot=live config quiet splash toram
    initrd /live/$initrd
}

menuentry "$system_name - Safe Graphics" {
    linux /live/$vmlinuz boot=live config quiet splash nomodeset
    initrd /live/$initrd
}
EOF
)
            fi
            ;;
        2)
            if [ "$live_dir" = "casper" ]; then
                menu_entries=$(cat <<EOF
menuentry "$system_name - LIVE" {
    linux /casper/$vmlinuz boot=casper quiet splash
    initrd /casper/$initrd
}
EOF
)
            else
                menu_entries=$(cat <<EOF
menuentry "$system_name - LIVE" {
    linux /live/$vmlinuz boot=live config quiet splash
    initrd /live/$initrd
}
EOF
)
            fi
            ;;
        3)
            echo -e "${BLUE}Enter custom menu entries (end with empty line):${NC}"
            menu_entries=""
            while true; do
                read -r line
                if [ -z "$line" ]; then
                    break
                fi
                menu_entries+="$line"$'\n'
            done
            ;;
        *)
            echo -e "${YELLOW}Invalid choice, using default entries${NC}"
            menu_choice=1
            ;;
    esac
    
    echo "$menu_entries"
}

# Create ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local volume_label="$3"
    
    echo -e "${BLUE}Creating ISO: $output_file${NC}"
    
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
        echo -e "${GREEN}✅ ISO created successfully!${NC}"
        echo -e "${YELLOW}📁 Location: $output_file${NC}"
        echo -e "${YELLOW}📏 Size: $size${NC}"
        return 0
    else
        echo -e "${RED}❌ ISO creation failed${NC}"
        return 1
    fi
}

# Main creation function with new workflow
create_live_iso() {
    echo -e "\n${CYAN}=== Step 1: Enter Project Directory ===${NC}"
    read -p "Enter target directory path (will be created if doesn't exist): " target_dir
    
    if [ -z "$target_dir" ]; then
        echo -e "${YELLOW}Empty path. Exiting.${NC}"
        return 1
    fi
    
    # Expand tilde and resolve path
    target_dir="${target_dir/#\~/$HOME}"
    target_dir=$(realpath -m "$target_dir")
    
    # Create directory if it doesn't exist
    if [ ! -d "$target_dir" ]; then
        echo -e "${BLUE}Creating directory: $target_dir${NC}"
        mkdir -p "$target_dir"
    fi
    
    echo -e "${GREEN}✅ Working directory: $target_dir${NC}"
    
    # Step 2: Download and copy bootfiles immediately
    echo -e "\n${CYAN}=== Step 2: Downloading ISO Build Files ===${NC}"
    download_bootfiles "$target_dir"
    
    # Step 3: Allow user to make edits
    echo -e "\n${CYAN}=== Step 3: Manual Editing Phase ===${NC}"
    echo -e "${YELLOW}ISO structure has been created in: $target_dir${NC}"
    echo -e "${BLUE}You can now:${NC}"
    echo -e "  • Add your live system files (/live or /casper directory)"
    echo -e "  • Customize splash.png"
    echo -e "  • Add additional files"
    echo -e "  • Modify existing files (including GRUB configs)"
    echo -e "\n${RED}⚠️  WARNING: Script will overwrite these files during build:${NC}"
    echo -e "  • /boot/grub/grub.cfg"
    echo -e "  • /boot/grub/theme.cfg"
    echo -e "  • /isolinux/isolinux.cfg"
    echo -e "  • /autorun.inf"
    echo -e "\n${YELLOW}Press ENTER when you're done editing the ISO structure...${NC}"
    read -r
    
    # Step 4: Check for existing configs and get user preference
    echo -e "\n${CYAN}=== Step 4: Configuration Management ===${NC}"
    
    local use_custom_configs=false
    local has_custom_grub=false
    local has_custom_isolinux=false
    
    # Check if user has custom configs
    if [ -f "$target_dir/boot/grub/grub.cfg" ]; then
        has_custom_grub=true
        echo -e "${YELLOW}Found existing GRUB config: $target_dir/boot/grub/grub.cfg${NC}"
    fi
    
    if [ -f "$target_dir/isolinux/isolinux.cfg" ]; then
        has_custom_isolinux=true
        echo -e "${YELLOW}Found existing ISOLINUX config: $target_dir/isolinux/isolinux.cfg${NC}"
    fi
    
    if [ "$has_custom_grub" = true ] || [ "$has_custom_isolinux" = true ]; then
        echo -e "\n${BLUE}Configuration Options:${NC}"
        echo -e "1) Use your custom configs (preserve your files)"
        echo -e "2) Generate new configs (overwrite your files)"
        echo -e "3) Backup your configs and generate new ones"
        
        read -p "Select option (1-3): " config_choice
        
        case $config_choice in
            1)
                use_custom_configs=true
                echo -e "${GREEN}✅ Using your custom configurations${NC}"
                ;;
            2)
                echo -e "${YELLOW}⚠️  Will overwrite your custom configs${NC}"
                ;;
            3)
                # Backup existing configs
                if [ "$has_custom_grub" = true ]; then
                    cp "$target_dir/boot/grub/grub.cfg" "$target_dir/boot/grub/grub.cfg.backup"
                    echo -e "${GREEN}✅ Backed up GRUB config to grub.cfg.backup${NC}"
                fi
                if [ "$has_custom_isolinux" = true ]; then
                    cp "$target_dir/isolinux/isolinux.cfg" "$target_dir/isolinux/isolinux.cfg.backup"
                    echo -e "${GREEN}✅ Backed up ISOLINUX config to isolinux.cfg.backup${NC}"
                fi
                ;;
            *)
                echo -e "${YELLOW}Invalid choice, using custom configs${NC}"
                use_custom_configs=true
                ;;
        esac
    fi
    
    # Auto-detect live system type and directory
    local live_dir=""
    local live_path=""
    local system_type=""
    
    if [ -d "$target_dir/live" ]; then
        live_dir="live"
        live_path="$target_dir/live"
        system_type="Debian Live"
        echo -e "${GREEN}✅ Detected: Debian Live system${NC}"
    elif [ -d "$target_dir/casper" ]; then
        live_dir="casper"
        live_path="$target_dir/casper"
        system_type="Ubuntu/Casper"
        echo -e "${GREEN}✅ Detected: Ubuntu/Casper system${NC}"
    else
        echo -e "${RED}Error: No live system found in $target_dir${NC}"
        echo -e "${YELLOW}Expected: $target_dir/live or $target_dir/casper${NC}"
        echo -e "${BLUE}Please add your live system files and run the script again${NC}"
        return 1
    fi
    
    # Find kernel and initrd
    local vmlinuz=""
    local initrd=""
    
    for file in "$live_path"/vmlinuz*; do
        [ -f "$file" ] && vmlinuz=$(basename "$file") && break
    done
    
    for file in "$live_path"/initrd*; do
        [ -f "$file" ] && initrd=$(basename "$file") && break
    done
    
    if [ -z "$vmlinuz" ] || [ -z "$initrd" ]; then
        echo -e "${RED}Error: Missing kernel or initrd in $live_path${NC}"
        echo -e "${YELLOW}Expected: vmlinuz* and initrd* files${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Found: $vmlinuz, $initrd${NC}"
    
    # Step 5: Get configuration details (only if generating new configs)
    local iso_name=""
    local system_name=""
    local volume_name=""
    local menu_entries=""
    
    if [ "$use_custom_configs" = false ]; then
        echo -e "\n${CYAN}=== Step 5: New Configuration Details ===${NC}"
        
        local dir_name=$(basename "$target_dir")
        
        read -p "Enter ISO filename (press ENTER for \"${dir_name}.iso\"): " iso_name
        iso_name=${iso_name:-"${dir_name}.iso"}
        [[ "$iso_name" != *.iso ]] && iso_name="${iso_name}.iso"
        
        read -p "Enter system name for menu (press ENTER for \"${dir_name}\"): " system_name
        system_name=${system_name:-"$dir_name"}
        
        local volume_default=$(echo "$dir_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
        read -p "Enter ISO volume label (press ENTER for \"${volume_default}\"): " volume_name
        volume_name=${volume_name:-"$volume_default"}
        volume_name=$(echo "$volume_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
        
        # Get menu entries
        menu_entries=$(get_menu_entries "$live_dir" "$system_name" "$vmlinuz" "$initrd")
    else
        echo -e "\n${CYAN}=== Step 5: Using Custom Configurations ===${NC}"
        
        local dir_name=$(basename "$target_dir")
        
        read -p "Enter ISO filename (press ENTER for \"${dir_name}.iso\"): " iso_name
        iso_name=${iso_name:-"${dir_name}.iso"}
        [[ "$iso_name" != *.iso ]] && iso_name="${iso_name}.iso"
        
        read -p "Enter system name (press ENTER for \"${dir_name}\"): " system_name
        system_name=${system_name:-"$dir_name"}
        
        local volume_default=$(echo "$dir_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
        read -p "Enter ISO volume label (press ENTER for \"${volume_default}\"): " volume_name
        volume_name=${volume_name:-"$volume_default"}
        volume_name=$(echo "$volume_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
        
        echo -e "${GREEN}✅ Using your existing GRUB and ISOLINUX configurations${NC}"
    fi
    
    
    # Step 6: Final confirmation
    echo -e "\n${CYAN}=== Step 6: Final Configuration Summary ===${NC}"
    echo -e "${YELLOW}System Type:${NC} $system_type"
    echo -e "${YELLOW}Source Dir:${NC} $target_dir"
    echo -e "${YELLOW}Live Path:${NC} $live_path"
    echo -e "${YELLOW}ISO Name:${NC} $iso_name"
    echo -e "${YELLOW}System Name:${NC} $system_name"
    echo -e "${YELLOW}Volume Label:${NC} $volume_name"
    echo -e "${YELLOW}Kernel:${NC} $vmlinuz"
    echo -e "${YELLOW}Initrd:${NC} $initrd"
    if [ "$use_custom_configs" = true ]; then
        echo -e "${YELLOW}Configs:${NC} Using your custom configurations"
    else
        echo -e "${YELLOW}Configs:${NC} Will generate new configurations"
    fi
    
    echo -e "\n${CYAN}=== START ISO BUILD? ===${NC}"
    read -p "Proceed with ISO creation? (Y/n): " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Build cancelled by user${NC}"
        return 1
    fi
    
    # Step 7: Build ISO
    echo -e "\n${CYAN}=== Step 7: Building ISO ===${NC}"
    
    local parent_dir=$(dirname "$target_dir")
    local output_file="$parent_dir/$iso_name"
    
    # Create configurations only if not using custom ones
    if [ "$use_custom_configs" = false ]; then
        echo -e "${BLUE}Generating new configurations...${NC}"
        create_grub_config "$target_dir" "$system_name" "$vmlinuz" "$initrd" "$live_dir" "$menu_entries"
        create_isolinux_config "$target_dir"
        create_autorun "$target_dir" "$system_name"
    else
        echo -e "${GREEN}Using your existing configurations...${NC}"
        # Still create autorun.inf if it doesn't exist
        if [ ! -f "$target_dir/autorun.inf" ]; then
            create_autorun "$target_dir" "$system_name"
        fi
    fi
    
    # Create ISO
    if create_iso "$target_dir" "$output_file" "$volume_name"; then
        echo -e "\n${GREEN}🎉 ISO BUILD COMPLETED! 🎉${NC}"
        echo -e "${GREEN}📁 ISO Location: $output_file${NC}"
        echo -e "${GREEN}📁 Source Files: $target_dir${NC}"
        return 0
    else
        echo -e "\n${RED}💥 ISO BUILD FAILED! 💥${NC}"
        return 1
    fi
}

# Main loop
main() {
    echo -e "${YELLOW}=== Nano ISO Creator - Live System Builder ===${NC}"
    echo -e "${BLUE}Enhanced workflow with immediate file setup and editing phase${NC}"
    echo -e "${BLUE}Supports both Debian Live (/live) and Ubuntu (/casper) systems${NC}"
    echo -e "${GREEN}Features: Immediate setup, manual editing, custom GRUB menus${NC}\n"
    
    # Check dependencies
    install_dependencies
    
    while true; do
        if create_live_iso; then
            echo -e "\n${GREEN}🎉 Project completed successfully!${NC}"
        else
            echo -e "\n${RED}💥 Project failed or cancelled!${NC}"
        fi
        
        echo -e "\n${YELLOW}=== Start New Project? ===${NC}"
        read -p "Create another ISO project? (y/n): " continue_choice
        
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Thanks for using Nano ISO Creator!${NC}"
            break
        fi
    done
}

# Run main function
main "$@"