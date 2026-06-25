#!/bin/bash
set -euxo pipefail

# Redirect logs
exec > >(tee -a /var/log/ollama-startup.log) 2>&1

echo "Starting Ollama setup..."

# 1. Update and install basic tools
apt-get update
apt-get install -y curl ca-certificates jq

# 2. Disk Mount configuration
DISK="/dev/disk/by-id/google-ollama-model-disk"
MOUNT="/var/lib/ollama"

echo "Waiting for persistent disk $DISK to attach..."
for i in $(seq 1 30); do
  if [ -e "$DISK" ]; then
    echo "Disk found!"
    break
  fi
  sleep 2
done

if [ ! -e "$DISK" ]; then
  echo "ERROR: Persistent disk not found: $DISK"
  exit 1
fi

# Format disk if it doesn't have a filesystem
if ! blkid "$DISK"; then
  echo "Formatting disk $DISK to ext4..."
  mkfs.ext4 -F "$DISK"
fi

# Create mount directory
mkdir -p "$MOUNT"

# Mount disk
if ! mountpoint -q "$MOUNT"; then
  echo "Mounting disk to $MOUNT..."
  mount "$DISK" "$MOUNT"
fi

# Add to fstab for persistency
if ! grep -q "$MOUNT" /etc/fstab; then
  echo "$DISK $MOUNT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
fi

# 3. Install Ollama natively
echo "Installing native Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Configure correct directory permissions
mkdir -p "$MOUNT/models"
chown -R ollama:ollama "$MOUNT" || true

# 4. Configure Ollama to listen on all interfaces and use the persistent disk
echo "Configuring Ollama service..."
mkdir -p /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/var/lib/ollama/models"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# 5. Wait for Ollama API to be ready
echo "Waiting for Ollama service to start..."
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:11434/api/tags; then
    echo "Ollama API is ready!"
    break
  fi
  sleep 5
done

# 6. Pull the model
echo "Pulling tinyllama model..."
sudo -u ollama env OLLAMA_HOST=127.0.0.1:11434 OLLAMA_MODELS=/var/lib/ollama/models ollama pull tinyllama || ollama pull tinyllama

# Log state
echo "Verification:"
curl -s http://127.0.0.1:11434/api/tags
df -h "$MOUNT"
echo "Ollama setup complete!"
