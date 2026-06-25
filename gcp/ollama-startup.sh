#!/bin/bash
set -euxo pipefail

# Redirect logs
exec > >(tee -a /var/log/ollama-startup.log) 2>&1

echo "Starting Ollama setup..."

# 1. Update and install basic tools
apt-get update
apt-get install -y curl ca-certificates jq zstd

# 2. Install Ollama natively
echo "Installing native Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# 3. Configure Ollama to listen on all interfaces
echo "Configuring Ollama service..."
mkdir -p /etc/systemd/system/ollama.service.d
cat >/etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# 4. Wait for Ollama API to be ready
echo "Waiting for Ollama service to start..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:11434/api/tags; then
    echo "Ollama API is ready!"
    break
  fi
  sleep 5
done

# 5. Pull the model
echo "Pulling tinyllama model..."
ollama pull tinyllama

# Log state
echo "Verification:"
curl -s http://localhost:11434/api/tags
echo "Ollama setup complete!"
