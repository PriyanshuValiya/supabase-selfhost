# 🚀 Supabase Self-Host on AWS EC2

This repository contains an automation script to deploy a self-hosted **Supabase** stack on an AWS EC2 instance. It handles the installation of Docker, Docker Compose, and all necessary Supabase containers (GoTrue, PostgREST, Realtime, and PostgreSQL).

---

## 🛠 Prerequisites: AWS EC2 Configuration

Before running the script, launch an EC2 instance with the following specifications to ensure compatibility and performance.

### 1. Instance Settings
| Feature | Recommended Setting |
| :--- | :--- |
| **Name** | supabase |
| **AMI** | Amazon Linux 2023 |
| **Instance Type** | t3.small (Minimum 2GB RAM required) |
| **Storage** | 30 GiB (gp3) |
| **Key Pair** | Create / Use an existing `.pem` or `.ppk` |

### 2. Security Group (Inbound Rules)
You **must** open the following ports in your Security Group to access the dashboard and database:

| Type | Protocol | Port | Description |
| :--- | :--- | :--- | :--- |
| **SSH** | TCP | 22 | Remote Terminal Access |
| **HTTP** | TCP | 80 | Web Traffic |
| **HTTPS** | TCP | 443 | Secure Web Traffic |
| **Custom TCP** | TCP | 8000 | **Supabase Dashboard (Studio)** |
| **PostgreSQL** | TCP | 5432 | Database Direct Access |

---

## ⚡ Installation Steps

Once your instance is running, connect via SSH and run the following command:

```bash
git clone https://github.com/PriyanshuValiya/supabase-selfhost.git && \
cd supabase-selfhost && \
chmod +x shellscript.sh && \
./shellscript.sh
