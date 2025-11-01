#!/bin/bash
# =========================================================
# OpenMediaVault + Jellyfin Installer for Raspberry Pi 4
# (Jellyfin reads media directly from local OMV storage)
# =========================================================
# Works on Raspberry Pi OS 64-bit or Debian-based system
# Run as root (sudo ./install_omv_jellyfin_local.sh)
# =========================================================

set -e

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root (sudo ./install_omv_jellyfin_local.sh)"
  exit 1
fi

echo "🚀 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing prerequisites..."
apt install -y curl wget sudo apt-transport-https ca-certificates software-properties-common

# --- Install OpenMediaVault ---
echo "🧱 Installing OpenMediaVault..."
wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash

echo "✅ OMV installed! Access it at: http://<your_pi_ip>/"
echo "Login: admin / openmediavault"

# --- Install Docker ---
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker pi || true

# --- Install Docker Compose ---
echo "🧩 Installing Docker Compose..."
apt install -y python3-pip
pip3 install docker-compose

# --- Jellyfin setup directories ---
echo "📂 Creating Jellyfin directories..."
mkdir -p /srv/jellyfin/{config,cache}

# --- Detect available OMV drives ---
echo "🔍 Available storage under /srv/dev-disk-by-uuid-*:"
ls -d /srv/dev-disk-by-uuid-* || echo "⚠️ No OMV drives detected yet. You can edit the compose file later."

# Ask user for OMV media folder path
read -p "Enter your OMV media folder path (e.g. /srv/dev-disk-by-uuid-xxxx/Media): " MEDIA_PATH

if [ ! -d "$MEDIA_PATH" ]; then
  echo "❌ The specified path does not exist. Please create it in OMV first."
  exit 1
fi

# --- Create Docker Compose file ---
echo "📝 Creating Jellyfin Docker Compose setup..."
cat <<EOF > /srv/jellyfin/docker-compose.yml
version: "3.5"
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    network_mode: "host"
    environment:
      - TZ=Etc/UTC
    volumes:
      - /srv/jellyfin/config:/config
      - /srv/jellyfin/cache:/cache
      - ${MEDIA_PATH}:/media
    restart: unless-stopped
EOF

# --- Start Jellyfin ---
cd /srv/jellyfin
docker-compose up -d

echo ""
echo "✅ Jellyfin installed and configured!"
echo "🌐 Access Jellyfin at: http://<your_pi_ip>:8096"
echo "📂 Your media folder is mounted from: ${MEDIA_PATH}"
echo ""
echo "🎉 Setup complete! OMV manages your storage, Jellyfin streams it locally."
