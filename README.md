# 🚀 Supabase Self-Host on AWS Ubuntu EC2

A complete, hang-free deployment guide for self-hosting Supabase on an AWS Ubuntu EC2 instance — from zero to running in one command.

---

## 📁 Repository Structure

```
supabase-selfhost/
├── shellscript.sh      ← Deployment script (run this on your EC2)
└── README.md           ← This guide
```

---

## 📋 Table of Contents

1. [Requirements](#-requirements)
2. [Step 1 — Launch EC2 Instance](#-step-1--launch-ec2-instance)
3. [Step 2 — Configure Security Group](#-step-2--configure-security-group)
4. [Step 3 — Connect via SSH from Local Machine](#-step-3--connect-via-ssh-from-local-machine)
5. [Step 4 — Start a Screen Session](#-step-4--start-a-screen-session)
6. [Step 5 — Run the Deployment Script](#-step-5--run-the-deployment-script)
7. [Step 6 — Access Your Dashboard](#-step-6--access-your-dashboard)
8. [Managing Supabase](#-managing-supabase)
9. [Troubleshooting](#-troubleshooting)
10. [Production Checklist](#-production-checklist)

---

## ✅ Requirements

Before you start, make sure you have:

- An **AWS account** with EC2 access
- A **key pair** (`.pem` file) downloaded to your local machine
- A terminal on your local machine (Mac/Linux Terminal or Windows PowerShell)

> 💰 **Cost estimate:** A `t3.medium` runs ~$0.04/hr (~$30/month).

---

## 🖥️ Step 1 — Launch EC2 Instance

Go to **AWS Console → EC2 → Launch Instance** and configure as below.

### Name
```
supabase-server
```

### AMI (Operating System)
Select **Ubuntu Server 22.04 LTS (HVM), SSD Volume Type**
- Architecture: `64-bit (x86)`

> ✅ Ubuntu 20.04 and 24.04 also work.

### Instance Type

| Instance | RAM | Verdict |
|----------|-----|---------|
| t3.micro | 1 GB | ❌ Too small — will OOM crash |
| t3.small | 2 GB | ⚠️ Risky — not recommended |
| **t3.medium** | **4 GB** | **✅ Minimum recommended** |
| t3.large | 8 GB | ✅ Best for production |

### Key Pair
- Click **Create new key pair**
- Name it anything (e.g. `supabase-key`)
- Type: `RSA` → Format: `.pem`
- Click **Create** — the `.pem` file downloads automatically
- **Save it somewhere safe — you cannot download it again**

### Storage
- Size: **30 GB**
- Volume type: `gp3`

Click **Launch Instance** and wait ~1 minute.

---

## 🔒 Step 2 — Configure Security Group

Go to **EC2 → Instances → your instance → Security tab → click the Security Group link**

Click **Edit inbound rules** and add:

| Type | Port | Source | Purpose |
|------|------|--------|---------|
| SSH | 22 | My IP | Your SSH access from local machine |
| Custom TCP | 8000 | 0.0.0.0/0 | Supabase Dashboard + all APIs |

Click **Save rules**.

> ⚠️ Port 22 is restricted to **My IP** only for security. Port 8000 is open publicly so anyone can reach your Supabase API.

---

## 🔗 Step 3 — Connect via SSH from Local Machine

Find your **Public IPv4 address** from the EC2 console (listed under your instance).

---

### Mac / Linux

Open your terminal and run:

```bash
# Step 1 — Fix key file permissions (SSH requires this)
chmod 400 /path/to/supabase-key.pem

# Step 2 — Connect
ssh -i /path/to/supabase-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

**Example:**
```bash
chmod 400 ~/Downloads/supabase-key.pem
ssh -i ~/Downloads/supabase-key.pem ubuntu@54.123.45.67
```

---

### Windows (PowerShell)

Open **PowerShell** and run:

```powershell
# Step 1 — Fix key file permissions
icacls "C:\Users\YourName\Downloads\supabase-key.pem" /inheritance:r /grant:r "$($env:USERNAME):(R)"

# Step 2 — Connect
ssh -i "C:\Users\YourName\Downloads\supabase-key.pem" ubuntu@YOUR_EC2_PUBLIC_IP
```

**Example:**
```powershell
ssh -i "C:\Users\John\Downloads\supabase-key.pem" ubuntu@54.123.45.67
```

---

### Windows (PuTTY)

> PuTTY does not support `.pem` files directly — you need to convert it to `.ppk` first.

**1. Convert `.pem` → `.ppk` using PuTTYgen:**
- Open **PuTTYgen**
- Click **Load** → select your `supabase-key.pem` file
  *(change file filter to "All Files" to see `.pem`)*
- Click **Save private key** → save as `supabase-key.ppk`

**2. Connect using PuTTY:**
- Open **PuTTY**
- Host Name: `ubuntu@YOUR_EC2_PUBLIC_IP`
- Port: `22`
- Go to **Connection → SSH → Auth → Credentials**
- Browse and select your `supabase-key.ppk` file
- Click **Open**

---

> ✅ **Success looks like this:**
> ```
> ubuntu@ip-172-31-xx-xx:~$
> ```
> You're connected and ready!

---

## 🖥️ Step 4 — Start a Screen Session

**This step is critical.** If your SSH disconnects mid-install, `screen` keeps your session alive so the script continues running.

```bash
# Install screen
sudo apt-get update -y && sudo apt-get install -y screen

# Start a named session
screen -S supabase
```

> 💡 **If your SSH drops at any point**, simply reconnect via SSH and run:
> ```bash
> screen -r supabase
> ```
> Your installation continues exactly where it left off.

---

## 🚀 Step 5 — Run the Deployment Script

### Download and run in one command

```bash
curl -fsSL https://raw.githubusercontent.com/PriyanshuValiya/supabase-selfhost/main/shellscript.sh \
  -o shellscript.sh && chmod +x shellscript.sh && ./shellscript.sh
```

That's it — the script handles everything automatically.

---

### What the script does (all automatic)

| Step | What It Does | Time |
|------|-------------|------|
| Step 0 | Validates Ubuntu OS, RAM, and disk space | ~5 sec |
| Step 1 | Refreshes apt package lists (no upgrade) | ~30 sec |
| Step 2 | Installs git, curl, openssl, screen, etc. | ~30 sec |
| Step 3 | Creates 4 GB swap file | ~15 sec |
| Step 4 | Installs Docker via official repo | ~1 min |
| Step 5 | Installs latest Docker Compose | ~20 sec |
| Step 6 | Clones Supabase GitHub repo | ~30 sec |
| Step 7 | Generates secrets & configures .env | ~5 sec |
| Step 8 | Pulls all Docker images & starts services | ~5–10 min |
| Step 9 | Health check & prints summary | ~25 sec |

> ⏱️ **Total time:** ~10–15 minutes on a fresh instance.

---

### Successful deployment looks like this

```
  ╔══════════════════════════════════════════════════════════╗
  ║        🚀  SUPABASE DEPLOYED SUCCESSFULLY!  🚀           ║
  ╠══════════════════════════════════════════════════════════╣
  ║                                                          ║
  ║  Dashboard   →  http://XX.XX.XX.XX:8000                  ║
  ║  REST API    →  http://XX.XX.XX.XX:8000/rest/v1/         ║
  ║  Auth API    →  http://XX.XX.XX.XX:8000/auth/v1/         ║
  ║  Storage     →  http://XX.XX.XX.XX:8000/storage/v1/      ║
  ║  Realtime    →  http://XX.XX.XX.XX:8000/realtime/v1/     ║
  ║                                                          ║
  ║  Credentials →  ~/supabase-credentials.txt               ║
  ╚══════════════════════════════════════════════════════════╝
```

---

## 🌐 Step 6 — Access Your Dashboard

### View your credentials
```bash
cat ~/supabase-credentials.txt
```

### Open in your browser
```
http://YOUR_EC2_PUBLIC_IP:8000
```

Login with:
- **Username:** `supabase`
- **Password:** *(from the credentials file)*

### Apply Docker group (one-time, no re-login needed)
```bash
newgrp docker
```

---

## 🛠️ Managing Supabase

All management commands run from:
```bash
cd ~/supabase/docker
```

### Common commands

```bash
# Check status of all containers
docker-compose ps

# View live logs (all services)
docker-compose logs -f

# View logs for one service
docker-compose logs -f kong        # API gateway
docker-compose logs -f auth        # Authentication
docker-compose logs -f db          # Postgres database
docker-compose logs -f studio      # Dashboard UI
docker-compose logs -f storage     # File storage
docker-compose logs -f realtime    # Realtime subscriptions

# Stop everything
docker-compose down

# Start everything
docker-compose up -d

# Restart a specific service
docker-compose restart kong

# Check memory usage
free -h

# Check per-container CPU/RAM
docker stats --no-stream

# Update Supabase to latest version
cd ~/supabase && git pull
cd docker && docker-compose pull && docker-compose up -d
```

---

## 🔧 Troubleshooting

### ❌ Script hangs and doesn't progress

The script suppresses interactive prompts automatically. If it still hangs:

```bash
# Press Ctrl+C, then run this fix
sudo NEEDRESTART_MODE=a apt-get install -y needrestart

# Re-run the script
./shellscript.sh
```

---

### ❌ Can't reach port 8000 in browser

Check in this order:

1. **Security Group** — port 8000 must have inbound rule for `0.0.0.0/0`
2. **Containers running:**
   ```bash
   cd ~/supabase/docker && docker-compose ps
   ```
3. **Services still starting** — wait 30–60 sec after launch, then retry
4. **Test from inside EC2:**
   ```bash
   curl -I http://localhost:8000
   ```

---

### ❌ One or more containers show "Exit" status

```bash
cd ~/supabase/docker

# See which containers exited
docker-compose ps

# Read logs for the failing service
docker-compose logs db
docker-compose logs auth
docker-compose logs kong
```

Most common cause is low memory. Check:
```bash
free -h
swapon --show
```

If swap is missing:
```bash
sudo swapon /swapfile
```

---

### ❌ SSH disconnects mid-install

If you used `screen` in Step 4:
```bash
# Reconnect SSH, then re-attach
screen -r supabase
```

If you skipped `screen`, just re-run the script — it's safe to run multiple times:
```bash
./shellscript.sh
```

---

### ❌ Permission denied running Docker

```bash
newgrp docker

# Test
docker ps
```

If still failing, log out and reconnect via SSH.

---

### ❌ EC2 freezes / becomes unresponsive

This is an OOM kill (out of memory). Happens on `t3.micro` or `t3.small`.

1. Reboot from AWS Console → EC2 → Actions → Reboot
2. Reconnect via SSH
3. Check swap: `free -h`
4. If missing: `sudo swapon /swapfile`
5. Re-run: `./shellscript.sh`
6. **Long-term fix:** Upgrade to `t3.medium` or larger

---

## ✅ Production Checklist

- [ ] Assign an **Elastic IP** so your server IP doesn't change on reboot
- [ ] Point a **domain name** to your Elastic IP
- [ ] Set up **HTTPS** via Nginx reverse proxy + Let's Encrypt (Certbot)
- [ ] Update `SITE_URL` and `API_EXTERNAL_URL` in `~/supabase/docker/.env` to your domain
- [ ] Configure an **SMTP provider** in `.env` for auth emails (e.g. Resend, SendGrid)
- [ ] Schedule **automated backups** (EBS snapshots or `pg_dump` cron)
- [ ] Restrict **port 5432** in Security Group to your IP only
- [ ] Set up **CloudWatch alerts** for CPU, memory, and disk

---

## 📁 File Reference

| File | Location | Purpose |
|------|----------|---------|
| Credentials | `~/supabase-credentials.txt` | All passwords + URLs |
| Environment config | `~/supabase/docker/.env` | All Supabase settings |
| Docker Compose | `~/supabase/docker/docker-compose.yml` | Service definitions |
| Deployment script | `~/shellscript.sh` | This installer |

---

## 🔗 Links

- **This repo:** [github.com/PriyanshuValiya/supabase-selfhost](https://github.com/PriyanshuValiya/supabase-selfhost)
- **Supabase Docs:** [supabase.com/docs](https://supabase.com/docs)
- **Supabase Self-Hosting Guide:** [supabase.com/docs/guides/self-hosting](https://supabase.com/docs/guides/self-hosting/docker)

---

*Built for Ubuntu 20.04 / 22.04 / 24.04 on AWS EC2*
