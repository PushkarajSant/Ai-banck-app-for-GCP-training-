# AI-Powered Bank Application - GCP Bootcamp Version

A secure, high-performance, containerized banking platform built with **Spring Boot 3**, **Java 21**, and integrated **Contextual AI (Ollama)**. 

This repository is customized specifically for Google Cloud Platform (GCP) deployment architectures, featuring private subnet networking, Managed Instance Groups (MIG), External HTTP Load Balancing, private Cloud SQL integration, and private local LLM endpoints.

---

## Technical Architecture (GCP Production Blueprint)

```text
Student Browser
  -> Global External Application Load Balancer (HTTP Port 80)
  -> Regional Managed Instance Group (Port 8080)
       -> Cloud SQL MySQL (Private IP Port 3306)
       -> Private Ollama VM (Private IP Port 11434)
            -> Persistent Disk mounted at /var/lib/ollama
```

### Infrastructure Highlights
- **Zero Public IPs**: All compute instances, database instances, and AI engines reside in private subnets with no public exposure.
- **Cloud NAT**: Directs outbound connectivity for VM package installations and model pulls without exposing the VMs to ingress traffic.
- **VPC Isolation**: Strict firewall rules separate the web application tier, the database tier, and the AI tier.
- **High Availability**: Application instances run across multiple zones inside a regional Managed Instance Group with configured health checks and auto-healing.
- **Sensitive Data Protection**: Database credentials are stored and fetched dynamically from Secret Manager at runtime.

---

## GCP Bootcamp Deployment Guide

For a complete step-by-step walkthrough of deploying this application using the Google Cloud Console, see:

👉 **[gcp/GCP_CONSOLE_DEPLOYMENT_RUNBOOK.md](gcp/GCP_CONSOLE_DEPLOYMENT_RUNBOOK.md)**

This runbook covers:
1. VPC network, subnetworks, NAT, and firewall rules setup.
2. Secret Manager password protection.
3. Cloud SQL instance provisioned with Private IP.
4. Persistent Disk mount and Ollama AI engine configuration.
5. Regional Managed Instance Group and HTTP Load Balancer deployment.
6. Self-healing/High Availability demonstration.

---

## Local Development Setup

To run the complete system (App + Database + AI Engine) on your local developer machine, follow these instructions:

### Prerequisites
- Docker and Docker Compose installed.

### Running the Services
1. Clone this repository locally.
2. Spin up the application stack using Docker Compose:
   ```bash
   docker compose up --build
   ```
3. Docker Compose will automatically start:
   - A MySQL 8 database (`bankapp-mysql`)
   - An Ollama container (`bankapp-ollama`)
   - A pull-model helper container that installs the `tinyllama` model
   - The Spring Boot application (`bankapp`), running on port `8080`
4. Access the web dashboard in your browser:
   ```text
   http://localhost:8080
   ```

---

## Technology Stack

- **Backend Framework**: Java 21, Spring Boot 3.4.13, Spring Security
- **Local AI Engine**: Ollama, TinyLlama model
- **Database**: MySQL 8.0
- **Containerization**: Docker, Docker Compose
- **GCP Core Services**: VPC, Compute Engine (MIG), Cloud SQL, Secret Manager, Cloud NAT/Router, External Application Load Balancer

---

<div align="center">

Happy Learning!

</div>
