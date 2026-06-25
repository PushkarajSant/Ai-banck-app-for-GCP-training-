#!/bin/bash
set -euxo pipefail

# Redirect logs
exec > >(tee -a /var/log/ollama-startup.log) 2>&1

echo "Starting Ollama setup via Docker..."

# 1. Install Docker using convenience script
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  systemctl enable --now docker
else
  echo "Docker already installed."
fi

# 2. Run Ollama Docker container
echo "Starting Ollama container..."
# Stop and remove existing container if running
docker stop ollama &>/dev/null || true
docker rm ollama &>/dev/null || true

docker run -d \
  --name ollama \
  --restart always \
  -p 11434:11434 \
  -v ollama-data:/root/.ollama \
  ollama/ollama

# 3. Wait for Ollama service to start
echo "Waiting for Ollama to start..."
for i in $(seq 1 30); do
  if docker exec ollama ollama list &>/dev/null; then
    echo "Ollama is ready!"
    break
  fi
  sleep 5
done

# 4. Pull tinyllama model inside the container
echo "Pulling tinyllama model..."
docker exec ollama ollama pull tinyllama

# Log state
docker ps
echo "Verification:"
docker exec ollama ollama list
echo "Ollama setup complete!"
