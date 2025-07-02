# LINUX LIVE - BIOS & UEFI 
# Isolinux & grub2 Chainload

sudo apt update && sudo apt install -y syslinux-utils grub-efi-amd64-bin mtools wget lzma

sudo mkdir /tmp/bootfiles && cd /tmp/bootfiles
wget https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BASE.tar.lzma
tar.lzma HYBRID-BASE.tar.lzma
