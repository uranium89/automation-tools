# n8n Deployment on Azure Ubuntu VM

This repository contains deployment scripts and workflow templates for running n8n on Azure Ubuntu VM with Docker.

## Features

- ✅ Docker & Docker Compose installation
- ✅ n8n deployment on port 80
- ✅ Azure DNS integration
- ✅ GitHub workflow synchronization
- ✅ Automatic workflow sync via cron
- ✅ Persistent data storage
- ✅ Systemd service for auto-start

## Quick Start

### Prerequisites

- Azure Ubuntu VM (20.04 or later)
- SSH access to the VM
- Azure CLI installed locally (for DNS configuration)
- GitHub repository for storing workflows

### Deployment Steps

1. **Clone this repository to your Azure VM:**

```bash
git clone <this-repo-url>
cd <repo-folder>
```

2. **Run the deployment script:**

#### Option A: Using command-line arguments

```bash
sudo ./deploy-n8n.sh \
  --github-repo "https://github.com/yourusername/your-n8n-workflows.git" \
  --github-branch "main" \
  --dns-zone "yourdomain.com" \
  --resource-group "your-resource-group" \
  --vm-ip "your-vm-public-ip" \
  --hostname "n8n"
```

#### Option B: Using environment variables

```bash
export GITHUB_REPO_URL="https://github.com/yourusername/your-n8n-workflows.git"
export GITHUB_BRANCH="main"
export AZURE_DNS_ZONE="yourdomain.com"
export AZURE_RESOURCE_GROUP="your-resource-group"
export VM_PUBLIC_IP="your-vm-public-ip"
export N8N_HOSTNAME="n8n"

sudo ./deploy-n8n.sh
```

#### Option C: Minimal deployment (without Azure DNS)

```bash
sudo ./deploy-n8n.sh
```

Then access n8n via `http://<your-vm-ip>`

## Directory Structure

```
/opt/n8n/
├── docker-compose.yml      # Docker Compose configuration
├── .env                    # Environment variables
├── data/                   # n8n data directory
├── workflows/              # n8n workflows storage
├── backups/                # Workflow backups
├── github-workflows/       # Synced GitHub repository
└── sync-workflows.sh       # Manual sync script
```

## GitHub Workflow Integration

### Storing Workflows in GitHub

1. Create a GitHub repository for your n8n workflows
2. Export workflows from n8n as JSON files
3. Commit and push to your repository

### Workflow Structure

Store your workflow JSON files in the root of your GitHub repository:

```
your-github-repo/
├── workflow-1.json
├── workflow-2.json
├── automation-pipeline.json
└── README.md
```

### Automatic Synchronization

The deployment script sets up an hourly cron job that:
- Pulls latest changes from your GitHub repository
- Copies workflow JSON files to n8n's workflows directory

Manual sync:
```bash
/opt/n8n/sync-workflows.sh
```

### Qwen Coder Access

To enable Qwen Coder or other AI assistants to create workflows:

1. Give the AI assistant access to your GitHub repository
2. The assistant can commit workflow JSON files directly
3. Changes will be automatically synced to n8n every hour

Example workflow JSON structure:
```json
{
  "name": "My Automation",
  "nodes": [...],
  "connections": {...},
  "active": true,
  "settings": {}
}
```

## Azure DNS Configuration

The script automatically creates DNS records if you provide:
- `AZURE_DNS_ZONE`: Your DNS zone name (e.g., `example.com`)
- `AZURE_RESOURCE_GROUP`: Resource group containing the DNS zone
- `VM_PUBLIC_IP`: Your VM's public IP address
- `N8N_HOSTNAME`: Subdomain for n8n (e.g., `n8n` → `n8n.example.com`)

### Manual DNS Setup

If you prefer to set up DNS manually:

```bash
az network dns record-set a add-record \
  --resource-group "your-resource-group" \
  --zone-name "yourdomain.com" \
  --record-set-name "n8n" \
  --ipv4-address "your-vm-ip"
```

## Management Commands

### View Logs
```bash
docker logs n8n
docker logs -f n8n  # Follow logs
```

### Start/Stop/Restart
```bash
# Using systemd
sudo systemctl start n8n
sudo systemctl stop n8n
sudo systemctl restart n8n

# Using docker-compose
cd /opt/n8n
docker-compose up -d
docker-compose down
```

### Check Status
```bash
sudo systemctl status n8n
docker ps | grep n8n
```

### Update n8n
```bash
cd /opt/n8n
docker-compose pull
docker-compose up -d
```

## Security Considerations

### Enable Basic Authentication

Edit `/opt/n8n/docker-compose.yml`:

```yaml
environment:
  - N8N_BASIC_AUTH_ACTIVE=true
  - N8N_BASIC_AUTH_USER=admin
  - N8N_BASIC_AUTH_PASSWORD=your-secure-password
```

Then restart:
```bash
cd /opt/n8n && docker-compose down && docker-compose up -d
```

### HTTPS Setup (Recommended)

For production, consider adding nginx with SSL:

1. Install nginx and certbot
2. Configure reverse proxy to n8n container
3. Obtain SSL certificate with Let's Encrypt

## Troubleshooting

### n8n won't start
```bash
docker logs n8n
cd /opt/n8n && docker-compose config  # Validate compose file
```

### Port 80 already in use
Check what's using port 80:
```bash
sudo netstat -tlnp | grep :80
```

Stop conflicting services or change the port in `docker-compose.yml`.

### GitHub sync fails
```bash
cd /opt/n8n/github-workflows
git status
git pull
```

## Backup Strategy

Workflows are automatically stored in:
- `/opt/n8n/data/` - n8n database and user data
- `/opt/n8n/workflows/` - Exported workflows
- `/opt/n8n/backups/` - Manual backups

Create regular backups:
```bash
tar -czf n8n-backup-$(date +%Y%m%d).tar.gz /opt/n8n
```

## License

MIT License

## Support

For issues or questions, please open an issue in this repository.