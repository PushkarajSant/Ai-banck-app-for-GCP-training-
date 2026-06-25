#!/bin/bash
set -euxo pipefail

# Redirect logs
exec > >(tee -a /var/log/bankapp-startup.log) 2>&1

echo "Starting BankApp setup..."

# ==============================================================================
# CONFIGURATION (Edit these values directly or use GCE Metadata)
# ==============================================================================
DB_HOST="[YOUR_CLOUD_SQL_PRIVATE_IP]"
DB_PORT="3306"
DB_NAME="bankapp"
DB_USER="bankuser"
DB_PASSWORD="BankDemo@12345"
OLLAMA_URL="http://[YOUR_OLLAMA_VM_PRIVATE_IP]:11434"
DOCKER_IMAGE="" # Optional: prebuilt Docker image URL
# ==============================================================================

# 1. Install Docker using convenience script
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  systemctl enable --now docker
else
  echo "Docker already installed."
fi

# Install Git and JQ
apt-get update
apt-get install -y git jq curl

# 2. GCE Metadata Fallback logic
metadata() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" || echo ""
}

# If placeholders are left in the script, attempt to load them from VM Metadata
if [ "$DB_HOST" = "[YOUR_CLOUD_SQL_PRIVATE_IP]" ] || [ -z "$DB_HOST" ]; then
  echo "Placeholder detected for DB_HOST, reading from metadata..."
  DB_HOST="$(metadata DB_HOST)"
fi

if [ "$OLLAMA_URL" = "http://[YOUR_OLLAMA_VM_PRIVATE_IP]:11434" ] || [ -z "$OLLAMA_URL" ]; then
  echo "Placeholder detected for OLLAMA_URL, reading from metadata..."
  OLLAMA_URL="$(metadata OLLAMA_URL)"
fi

# Check optional overrides from metadata
META_DB_NAME="$(metadata DB_NAME)"
if [ -n "$META_DB_NAME" ]; then DB_NAME="$META_DB_NAME"; fi

META_DB_USER="$(metadata DB_USER)"
if [ -n "$META_DB_USER" ]; then DB_USER="$META_DB_USER"; fi

META_DB_PASSWORD="$(metadata DB_PASSWORD)"
if [ -n "$META_DB_PASSWORD" ]; then DB_PASSWORD="$META_DB_PASSWORD"; fi

META_DOCKER_IMAGE="$(metadata DOCKER_IMAGE)"
if [ -n "$META_DOCKER_IMAGE" ]; then DOCKER_IMAGE="$META_DOCKER_IMAGE"; fi

echo "Final parameters used for execution:"
echo "DB_HOST: $DB_HOST"
echo "DB_PORT: $DB_PORT"
echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"
echo "OLLAMA_URL: $OLLAMA_URL"
echo "DOCKER_IMAGE: $DOCKER_IMAGE"

# 3. Handle Docker Image Retrieval
if [ -n "$DOCKER_IMAGE" ]; then
  echo "Using prebuilt Docker image: $DOCKER_IMAGE"
  REGISTRY_HOST=$(echo "$DOCKER_IMAGE" | cut -d'/' -f1)
  if [[ "$REGISTRY_HOST" == *"docker.pkg.dev"* ]]; then
    echo "Configuring docker credentials helper for $REGISTRY_HOST..."
    gcloud auth configure-docker "$REGISTRY_HOST" --quiet || true
  fi
  docker pull "$DOCKER_IMAGE"
  docker tag "$DOCKER_IMAGE" bankapp:gcp-demo
else
  echo "No DOCKER_IMAGE specified. Falling back to local build from GitHub..."
  CLONE_DIR="/opt/AI-BankApp-DevOps"
  rm -rf "$CLONE_DIR"
  git clone "https://github.com/TrainWithShubham/AI-BankApp-DevOps.git" "$CLONE_DIR"
  cd "$CLONE_DIR"
  docker build -t bankapp:gcp-demo .
fi

# 4. Run the Docker container
echo "Running the bankapp container..."
# Stop and remove existing container if running
docker stop bankapp &>/dev/null || true
docker rm bankapp &>/dev/null || true

docker run -d \
  --name bankapp \
  --restart always \
  -p 8080:8080 \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="$DB_PORT" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e MYSQL_HOST="$DB_HOST" \
  -e MYSQL_PORT="$DB_PORT" \
  -e MYSQL_DATABASE="$DB_NAME" \
  -e MYSQL_USER="$DB_USER" \
  -e MYSQL_PASSWORD="$DB_PASSWORD" \
  -e OLLAMA_URL="$OLLAMA_URL" \
  bankapp:gcp-demo

# 5. Verify health check
echo "Verifying application health..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/actuator/health; then
    echo "Application successfully started and is healthy!"
    break
  fi
  sleep 5
done

docker ps
echo "BankApp setup complete!"
