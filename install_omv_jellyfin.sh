#!/bin/bash
# =========================================================
# OpenMediaVault + Jellyfin Installer for Raspberry Pi 4
# (Jellyfin reads media directly from local OMV storage)
# =========================================================
# Works on Raspberry Pi OS 64-bit or Debian-based system
# Run as root (sudo ./install_omv_jellyfin_local.sh)
# =========================================================

#
# wget https://raw.githubusercontent.com/205101-retr0/omvfinny/refs/heads/main/install_omv_jellyfin.sh && chmod +x install_omv_jellyfin.sh && sudo ./install_omv_jellyfin.sh
#

set -e

if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root (sudo ./install_omv_jellyfin_local.sh)"
  exit 1
fi

# --- Check Debian version compatibility ---
echo "🔍 Checking system compatibility..."
if [ -f /etc/debian_version ]; then
  DEBIAN_CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"')
  if [ -z "$DEBIAN_CODENAME" ]; then
    # Fallback method using debian_version file
    DEBIAN_VERSION=$(cat /etc/debian_version)
    case $DEBIAN_VERSION in
      11*) DEBIAN_CODENAME="bullseye" ;;
      12*) DEBIAN_CODENAME="bookworm" ;;
      *) DEBIAN_CODENAME="unknown" ;;
    esac
  fi
  
  if [[ "$DEBIAN_CODENAME" != "bookworm" && "$DEBIAN_CODENAME" != "bullseye" ]]; then
    echo "❌ OpenMediaVault is only supported on Debian Bookworm (12) or Bullseye (11)"
    echo "   Current system: $DEBIAN_CODENAME"
    echo "   Please use a supported Debian/Raspberry Pi OS version."
    exit 1
  fi
  echo "✅ System compatibility verified: Debian $DEBIAN_CODENAME"
else
  echo "❌ This script requires a Debian-based system (Bookworm or Bullseye)"
  exit 1
fi

# --- Clean up any conflicting Docker configurations early ---
echo "🧹 Cleaning up any existing Docker repository conflicts..."
# Remove Docker repository files
rm -f /etc/apt/sources.list.d/docker.list*
rm -f /etc/apt/sources.list.d/docker.sources*
# Remove all Docker GPG keys from various locations
rm -f /etc/apt/keyrings/docker.asc
rm -f /etc/apt/keyrings/docker.gpg
rm -f /usr/share/keyrings/docker.gpg
rm -f /usr/share/keyrings/docker-archive-keyring.gpg
# Remove Docker entries from main sources.list
sed -i '/download\.docker\.com/d' /etc/apt/sources.list
# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "🚀 Updating system..."
apt update && apt upgrade -y

echo "📦 Installing prerequisites..."
apt install -y curl wget sudo apt-transport-https ca-certificates software-properties-common

# --- Check if OpenMediaVault is already installed ---
echo "🔍 Checking for existing OpenMediaVault installation..."
if command -v omv-confdbadm >/dev/null 2>&1 || [ -f /etc/openmediavault/config.xml ] || dpkg -l | grep -q "openmediavault"; then
  echo "✅ OpenMediaVault is already installed, skipping installation"
  OMV_INSTALLED="true"
else
  echo "🧱 Installing OpenMediaVault..."
  wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | sudo bash
  echo "✅ OMV installed! Access it at: http://<your_pi_ip>/"
  echo "Login: admin / openmediavault"
  OMV_INSTALLED="false"
fi

# --- Install Docker ---
echo "🐳 Installing Docker..."

# Remove any existing Docker packages
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install Docker using official method
echo "📥 Installing Docker from official repository..."
apt-get update
apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Aggressive cleanup of all Docker repositories
echo "🧹 Performing aggressive Docker repository cleanup..."
find /etc/apt -type f \( -name "*.list" -o -name "*.sources" \) -exec grep -l "download\.docker\.com" {} \; 2>/dev/null | while read file; do
  echo "Removing Docker repository file: $file"
  rm -f "$file"
done

# Also clean main sources.list again
sed -i '/download\.docker\.com/d' /etc/apt/sources.list

# Verify cleanup
echo "🔍 Verifying all Docker repositories are removed..."
if grep -r "download.docker.com" /etc/apt/ 2>/dev/null; then
  echo "❌ Still found Docker repositories. Manual cleanup may be needed."
  echo "Run: find /etc/apt -name '*.list' -o -name '*.sources' | xargs grep -l docker"
  exit 1
else
  echo "✅ All Docker repositories successfully removed"
fi

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
usermod -aG docker pi || usermod -aG docker $SUDO_USER || true

# Docker Compose is now installed as a plugin with Docker
echo "✅ Docker Compose plugin installed with Docker"

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
docker compose up -d

echo ""
echo "✅ Jellyfin installed and configured!"
echo "🌐 Access Jellyfin at: http://<your_pi_ip>:8096"
echo "📂 Your media folder is mounted from: ${MEDIA_PATH}"
echo ""
echo "🎉 Setup complete! OMV manages your storage, Jellyfin streams it locally."
