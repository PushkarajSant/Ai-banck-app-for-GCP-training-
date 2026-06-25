# GCP 2-Hour Demo Runbook - Console-Based Spring Boot AI Bank

This runbook guides the trainer and students through deploying a real Spring Boot 3 + Java 21 banking application on Google Cloud Platform (GCP). The application runs on private Compute Engine VMs in a Managed Instance Group (MIG) behind an external Application Load Balancer (ALB), connecting to a private Cloud SQL MySQL instance and a private Ollama VM.

---

## Final Architecture

```text
Student Browser
  -> Global External Application Load Balancer (HTTP Port 80)
  -> Regional Managed Instance Group (Port 8080)
       -> Cloud SQL MySQL (Private IP Port 3306)
       -> Private Ollama VM (Private IP Port 11434)
```

### Key Concepts Taught
- **Zero Public IPs**: Both the app VMs, the database, and the Ollama VM are private.
- **Cloud NAT**: Allows outbound access for package installations, git clones, and model pulls.
- **Security Boundaries**: Firewall rules isolate the tiers. Only the load balancer is public.
- **High Availability**: Regional MIG across multiple zones with automatic self-healing.
- **Simplified Credentials**: App parameters are loaded directly inside the GCE startup script (or via GCE metadata).

---

## Resource Naming Cheat Sheet

| Resource | Value |
|---|---|
| Region | `asia-south1` |
| Zone 1 | `asia-south1-a` |
| Zone 2 | `asia-south1-b` |
| VPC | `production-vpc` |
| App Subnet | `app-subnet`, `10.10.1.0/24` |
| AI Subnet | `ai-subnet`, `10.10.2.0/24` |
| Cloud Router | `prod-router` |
| Cloud NAT | `prod-nat` |
| Service Account | `bankapp-sa` |
| DB Password Value | `BankDemo@12345` |
| Cloud SQL Instance | `bankdb` |
| Cloud SQL Database | `bankapp` |
| Cloud SQL User | `bankuser` |
| Ollama VM | `ollama-vm` |
| App Template | `bankapp-template-v1` |
| Managed Instance Group | `bankapp-mig` |
| Health Check | `bankapp-hc` (HTTP, port `8080`, path `/actuator/health`) |
| Backend Service | `bankapp-backend` |
| Load Balancer IP | `bankapp-lb-ip` |

---

## Setup Walkthrough

### 1. Select Project and Enable APIs

Navigate to **APIs & Services -> Library** in the Google Cloud Console. Search and enable these APIs:
1. `Compute Engine API`
2. `Cloud SQL Admin API`
3. `Service Networking API`
4. `Secret Manager API` (Optional)
5. `Cloud Logging API`

---

### 2. Create Custom VPC

1. Go to **VPC network -> VPC networks -> Create VPC network**.
2. **Name**: `production-vpc`
3. **Subnet creation mode**: Custom
4. **App Subnet**:
   - Name: `app-subnet`
   - Region: `asia-south1`
   - IPv4 range: `10.10.1.0/24`
   - Private Google Access: **On**
5. Click **Add subnet** for **AI Subnet**:
   - Name: `ai-subnet`
   - Region: `asia-south1`
   - IPv4 range: `10.10.2.0/24`
   - Private Google Access: **On**
6. Keep other settings default and click **Create**.

---

### 3. Create Cloud NAT

1. Go to **VPC network -> Cloud NAT -> Create Cloud NAT gateway**.
2. **Gateway name**: `prod-nat`
3. **VPC network**: `production-vpc`
4. **Region**: `asia-south1`
5. **Cloud Router**: Select **Create new router** -> Name: `prod-router` -> click **Create**.
6. **Source**: Custom (Select `app-subnet` and `ai-subnet` to restrict NAT only to our subnets)
7. Click **Create**.

---

### 4. Configure Firewall Rules

Create the following three Ingress rules under **VPC network -> Firewall -> Create firewall rule**:

#### Rule 1: Allow Identity-Aware Proxy (IAP) SSH
- **Name**: `allow-iap-ssh`
- **Network**: `production-vpc`
- **Direction**: Ingress
- **Action**: Allow
- **Targets**: Specified target tags -> `iap-ssh`
- **Source IPv4 range**: `35.235.240.0/20`
- **Protocols & ports**: TCP `22`

#### Rule 2: Allow Load Balancer to Application
- **Name**: `allow-lb-to-bankapp`
- **Network**: `production-vpc`
- **Direction**: Ingress
- **Action**: Allow
- **Targets**: Specified target tags -> `bankapp`
- **Source IPv4 range**: `35.191.0.0/16`, `130.211.0.0/22`
- **Protocols & ports**: TCP `8080`

#### Rule 3: Allow Application Subnet to Ollama
- **Name**: `allow-app-to-ollama`
- **Network**: `production-vpc`
- **Direction**: Ingress
- **Action**: Allow
- **Targets**: Specified target tags -> `ollama`
- **Source IPv4 range**: `10.10.1.0/24` (App Subnet)
- **Protocols & ports**: TCP `11434`

---

### 5. Create Service Account

1. Go to **IAM & Admin -> Service Accounts -> Create service account**.
   - Name & ID: `bankapp-sa`
   - Roles:
     - `Logs Writer` (To write system logs)

---

### 6. Create Cloud SQL MySQL with Private IP

1. Go to **Cloud SQL -> Create instance -> Choose MySQL**.
2. **Instance ID**: `bankdb`
3. **Password**: `BankDemo@12345`
4. **Database version**: MySQL 8.0
5. **Region**: `asia-south1`
6. **Zone**: `asia-south1-a`
7. **Machine Configuration**: Shared core (`db-f1-micro` or `db-g1-small` for demo speed)
8. **Connections**:
   - Uncheck **Public IP**.
   - Check **Private IP**.
   - Associated network: `production-vpc`.
   - If prompted to set up **Private services access**: Click **Set up connection**, automatically allocate IP range (e.g. `cloud-sql-psa-range`), and click **Continue**.
9. Click **Create instance**. (Takes ~5-10 minutes).
10. Once created:
    - Go to **Databases -> Create Database** -> Name: `bankapp`.
    - Go to **Users -> Add user account** -> Username: `bankuser`, Password: `BankDemo@12345`.
    - Copy the **Private IP address** of the database (e.g. `10.20.0.X`) and note it down as `DB_HOST`.

---

### 7. Create Private Ollama VM

1. Go to **Compute Engine -> VM instances -> Create instance**.
   - Name: `ollama-vm`
   - Zone: `asia-south1-a`
   - Machine type: `e2-standard-4` (4 vCPUs, 16 GB RAM)
   - Boot disk: 
     - Operating System: `Debian GNU/Linux 12 (bookworm)`
     - Size: **Change from 10 GB to 30 GB** (CRITICAL: The `ollama/ollama` Docker image and model files require significant space; leaving the default 10 GB size will cause extraction to fail with a "no space left on device" error).
   - Service account: `bankapp-sa`
   - **Networking** (under Advanced options):
     - Network tags: `ollama`, `iap-ssh`
     - Network: `production-vpc`
     - Subnetwork: `ai-subnet`
     - External IP: **None**
   - **Management** (under Advanced options -> Automation):
     - Paste the content of `gcp/ollama-startup.sh` in the Startup script text area.
   - Click **Create**.
2. Copy the **Internal IP** of `ollama-vm` (e.g. `10.10.2.X`) and note it down as `OLLAMA_IP`.

---

### 8. Create App Instance Template

1. Go to **Compute Engine -> Instance templates -> Create instance template**.
2. **Name**: `bankapp-template-v1`
3. **Machine type**: `e2-small`
4. **Boot disk**: `Debian GNU/Linux 12 (bookworm)`
5. **Service account**: `bankapp-sa`
6. **Networking** (under Advanced options):
   - Network tags: `bankapp`, `iap-ssh`
   - Network: `production-vpc`
   - Subnetwork: `app-subnet`
   - External IP: **None**
7. **Startup script** (under Advanced options -> Management -> Automation):
   Open `gcp/bankapp-startup.sh` and edit the values at the top of the file before pasting:
   ```bash
   DB_HOST="[YOUR_CLOUD_SQL_PRIVATE_IP]" # Replace with Cloud SQL Private IP
   OLLAMA_URL="http://[YOUR_OLLAMA_VM_PRIVATE_IP]:11434" # Replace with Ollama VM Private IP
   ```
   Paste the modified script in the GCE Startup script box.
   
   *(Alternative: If you leave the script placeholder keys intact, you must configure GCE Custom Metadata under **Advanced Options -> Management -> Metadata** with keys `DB_HOST` and `OLLAMA_URL` set to their respective private IPs).*
8. Click **Create**.

---

### 9. Create Regional Managed Instance Group

1. Go to **Compute Engine -> Instance groups -> Create instance group**.
2. **Name**: `bankapp-mig`
3. **Instance template**: `bankapp-template-v1`
4. **Location**: Multiple zones -> `asia-south1` -> Zones `asia-south1-a`, `asia-south1-b`
5. **Autoscaling**: Off (Set fixed size to `2` instances)
6. **Autohealing**:
   - Health check: Select **Create a health check**
   - Name: `bankapp-hc`
   - Protocol: **HTTP**
   - Port: `8080`
   - Request path: `/actuator/health`
   - Click **Save**.
7. Click **Create**.
8. Once the MIG is created, select it, click **Edit**, and configure a **Named Port**:
    - Name: `http`
    - Port: `8080`
    - Click **Save**.

---

### 10. Create External HTTP Load Balancer

1. Go to **Network services -> Load balancing -> Create load balancer**.
2. Select **Application Load Balancer (HTTP/S)** -> **Public facing (external)** -> **Global external Application Load Balancer**.
3. **Frontend configuration**:
   - Name: `bankapp-frontend`
   - Protocol: `HTTP`
   - Port: `80`
   - IP address: Create IP address -> Name: `bankapp-lb-ip` -> **Reserve**
4. **Backend configuration**:
   - Click **Create a backend service**.
   - Name: `bankapp-backend`
   - Backend type: **Instance group**
   - Protocol: `HTTP`
   - Named port: `http`
   - Backends: Select `bankapp-mig` -> Port numbers: `8080`
   - Health check: `bankapp-hc`
   - Click **Create**.
5. **Routing rules**: Simple host and path rule -> maps all traffic to `bankapp-backend`.
6. Click **Create** and wait for the Load Balancer to provision (~3-5 minutes).

---

## Testing & High Availability Demo

### Step 1: Verify the Frontend
1. Copy the reserved Load Balancer frontend IP address.
2. Open it in your browser: `http://[LOAD_BALANCER_IP]`
3. Register a test user and log in.
4. Try a transaction (Deposit/Withdraw) and use the Chat Assistant (ask about interest rates or security). The AI assistant response will query `tinyllama` on the private `ollama-vm` over the VPC.

### Step 2: Database Check
1. Go to **Cloud SQL -> bankdb -> Cloud SQL Studio**.
2. Log in using database name `bankapp`, user `bankuser`, password `BankDemo@12345`.
3. Verify that the app initialized the tables and your registration/chat logs are persisted.
   ```sql
   SELECT * FROM users;
   SELECT * FROM transactions;
   ```

### Step 3: High Availability (HA) Demo
1. Stop the application on one of the app instances using SSH:
   - Go to **VM Instances** -> Click **SSH** on `bankapp-mig-XXXX` (using IAP).
   - Stop the Docker container:
     ```bash
     sudo docker stop bankapp
     ```
2. In another tab, refresh your browser at `http://[LOAD_BALANCER_IP]`.
3. Notice that the page loads seamlessly. The Load Balancer automatically routes requests to the second healthy VM instance.
4. Look at the MIG dashboard. The instance group auto-healing will notice the `/actuator/health` failure on the stopped instance and will recreate/restart the container automatically.

---

## Cleanup Checklist
Delete resources in the following order to avoid dependency locks:
1. **Load Balancer**: Network services -> Load balancing -> Delete.
2. **Managed Instance Group**: Compute Engine -> Instance groups -> Delete `bankapp-mig`.
3. **Instance Template**: Compute Engine -> Instance templates -> Delete `bankapp-template-v1`.
4. **Ollama VM**: Compute Engine -> VM instances -> Delete `ollama-vm`.
5. **Cloud SQL**: Cloud SQL -> Delete `bankdb`.
6. **Cloud NAT & Router**: VPC network -> Cloud NAT -> Delete `prod-nat`, then Routers -> Delete `prod-router`.
7. **Firewall Rules**: VPC network -> Firewall -> Delete the three rules.
8. **VPC Network**: VPC network -> VPC networks -> Delete `production-vpc`.
9. **Service Account**: IAM & Admin -> Service accounts -> Delete `bankapp-sa`.
