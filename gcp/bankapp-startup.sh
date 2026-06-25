#!/bin/bash
set -euxo pipefail

# Redirect logs
exec > >(tee -a /var/log/bankapp-startup.log) 2>&1

echo "Starting BankApp setup..."

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

# 2. Retrieve GCE metadata attributes
metadata() {
  curl -sf -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" || echo ""
}

PROJECT_ID="$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id" || echo "")"
# If project ID is still empty, try reading instance metadata attribute
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID="$(metadata PROJECT_ID)"
fi

DB_HOST="$(metadata DB_HOST)"
DB_NAME="$(metadata DB_NAME)"
DB_USER="$(metadata DB_USER)"
DB_PASSWORD_SECRET="$(metadata DB_PASSWORD_SECRET)"
OLLAMA_URL="$(metadata OLLAMA_URL)"
DOCKER_IMAGE="$(metadata DOCKER_IMAGE)"

# Set defaults if empty
DB_NAME="${DB_NAME:-bankappdb}"
DB_USER="${DB_USER:-bankuser}"
DB_PASSWORD_SECRET="${DB_PASSWORD_SECRET:-bankapp-db-password}"

echo "Metadata parameters retrieved:"
echo "PROJECT_ID: $PROJECT_ID"
echo "DB_HOST: $DB_HOST"
echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"
echo "DB_PASSWORD_SECRET: $DB_PASSWORD_SECRET"
echo "OLLAMA_URL: $OLLAMA_URL"
echo "DOCKER_IMAGE: $DOCKER_IMAGE"

# 3. Retrieve DB password from Secret Manager
DB_PASSWORD=""
if command -v gcloud &> /dev/null; then
  echo "Attempting to retrieve secret using gcloud CLI..."
  DB_PASSWORD=$(gcloud secrets versions access latest --secret="${DB_PASSWORD_SECRET}" --project="${PROJECT_ID}" 2>/dev/null || echo "")
fi

if [ -z "$DB_PASSWORD" ]; then
  echo "gcloud failed or not available. Using curl & metadata token..."
  TOKEN=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token' || echo "")
  if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
    PAYLOAD=$(curl -sf -H "Authorization: Bearer ${TOKEN}" "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${DB_PASSWORD_SECRET}/versions/latest:access" || echo "")
    if [ -n "$PAYLOAD" ]; then
      DB_PASSWORD=$(echo "$PAYLOAD" | jq -r '.payload.data' | base64 -d || echo "")
    fi
  fi
fi

if [ -z "$DB_PASSWORD" ]; then
  echo "WARNING: Failed to retrieve DB password from Secret Manager. Using default fallback password."
  DB_PASSWORD="BankDemo@12345"
fi

# 4. Handle Docker Image Retrieval
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
  echo "No DOCKER_IMAGE metadata specified. Falling back to local build from GitHub..."
  CLONE_DIR="/opt/AI-BankApp-DevOps"
  rm -rf "$CLONE_DIR"
  git clone "https://github.com/TrainWithShubham/AI-BankApp-DevOps.git" "$CLONE_DIR"
  cd "$CLONE_DIR"
  docker build -t bankapp:gcp-demo .
fi

# 5. Run the Docker container
echo "Running the bankapp container..."
# Stop and remove existing container if running
docker stop bankapp &>/dev/null || true
docker rm bankapp &>/dev/null || true

docker run -d \
  --name bankapp \
  --restart always \
  -p 8080:8080 \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="3306" \
  -e DB_NAME="$DB_NAME" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e MYSQL_HOST="$DB_HOST" \
  -e MYSQL_PORT="3306" \
  -e MYSQL_DATABASE="$DB_NAME" \
  -e MYSQL_USER="$DB_USER" \
  -e MYSQL_PASSWORD="$DB_PASSWORD" \
  -e OLLAMA_URL="$OLLAMA_URL" \
  bankapp:gcp-demo

# 6. Verify health check
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
