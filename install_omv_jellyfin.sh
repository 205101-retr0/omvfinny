#!/bin/bash
# =========================================================
# OpenMediaVault + Jellyfin Installer for Raspberry Pi 4
# =========================================================
# Tested on Raspberry Pi OS Lite (64-bit)
# Run as root or with sudo privileges
# =========================================================

set -e

# --- Check for root privileges ---
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run this script as root (sudo ./install_omv_jellyfin.sh)"
  exit 1
fi

echo "🚀 Updating system..."
apt update && apt upgrade -y

# --- Install prerequisites ---
echo "📦 Installing prerequisites..."
apt install -y curl wget sudo apt-transport-https ca-certificates software-properties-common

# --- Install OpenMediaVault ---
echo "🧱 Installing OpenMediaVault..."
wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash

echo "✅ OpenMediaVault installation complete!"
echo "🌐 Access OMV at: http://<your_pi_ip>/"
echo "Default login: admin / openmediavault"

# --- Install Docker ---
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker pi || true

# --- Install Docker Compose ---
echo "🧩 Installing Docker Compose..."
apt install -y python3-pip
pip3 install docker-compose

# --- Create Jellyfin Docker setup ---
echo "🎬 Setting up Jellyfin container..."

mkdir -p /srv/jellyfin/{config,cache,media}

cat <<EOF > /srv/jellyfin/docker-compose.yml
version: "3.5"
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    network_mode: "host"
    volumes:
      - /srv/jellyfin/config:/config
      - /srv/jellyfin/cache:/cache
      - /srv/jellyfin/media:/media
    restart: unless-stopped
EOF

# --- Start Jellyfin ---
cd /srv/jellyfin
docker-compose up -d

echo "✅ Jellyfin installed and running!"
echo "🌐 Access Jellyfin at: http://<your_pi_ip>:8096"
echo ""
echo "🎉 Setup complete! You now have OMV + Jellyfin running on your Raspberry Pi 4."
<D-s>
