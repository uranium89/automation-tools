# n8n Deployment on Azure Ubuntu VM

Complete deployment solution for n8n with Docker, Nginx reverse proxy, and Let's Encrypt SSL certificate support.

## Features

- ✅ **Docker & Docker Compose** - Containerized deployment
- ✅ **Nginx Reverse Proxy** - Professional reverse proxy with WebSocket support
- ✅ **Let's Encrypt HTTPS** - Automatic SSL certificate on port 443
- ✅ **Azure DNS Compatible** - Works with `*.cloudapp.azure.com` or custom domains
- ✅ **GitHub Workflow Sync** - Store workflows in GitHub for Qwen Coder access
- ✅ **Auto-renewal** - Automatic SSL certificate renewal
- ✅ **Persistent Storage** - Data stored in `/opt/n8n/`

## Prerequisites

1. Fresh Ubuntu Server (20.04 or 22.04)
2. Public IP address for your VM
3. DNS record pointing to your VM:
   - For Azure default domain: `n8n.<region>.cloudapp.azure.com` (already configured by Azure)
   - For custom domain: Create A record pointing to VM IP
4. Email address for Let's Encrypt certificate

## Quick Start

### 1. Clone this repository to your Ubuntu VM

```bash
git clone <your-repo-url>
cd <repository-folder>
```

### 2. Run the deployment script

```bash
sudo ./deploy-n8n.sh \
  --hostname n8n.eastus.cloudapp.azure.com \
  --email your-email@example.com \
  --timezone Asia/Ho_Chi_Minh \
  --workflows-repo https://github.com/youruser/n8n-workflows.git
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--hostname` | ✅ | Full hostname (e.g., `n8n.eastus.cloudapp.azure.com`) |
| `--email` | ✅ | Email for Let's Encrypt certificate |
| `--timezone` | ❌ | Timezone (default: `UTC`) |
| `--workflows-repo` | ❌ | GitHub repository URL for workflows |

## Azure DNS Configuration

### For Azure Default Domain (*.cloudapp.azure.com)

Azure automatically creates a DNS entry for your VM. Find your FQDN:
```bash
hostname -f
# or
curl http://169.254.169.254/metadata/instance/compute/publicFqdn?api-version=2021-02-01&format=text
```

Use this FQDN as the `--hostname` parameter.

### For Custom Domain with Azure DNS

If using Azure DNS service:

```bash
# Create DNS zone (if not exists)
az network dns zone create \
  --resource-group <your-resource-group> \
  --name yourdomain.com

# Create A record
az network dns record-set a create \
  --resource-group <your-resource-group> \
  --zone-name yourdomain.com \
  --name n8n \
  --ttl 3600

az network dns record-set a add-record \
  --resource-group <your-resource-group> \
  --zone-name yourdomain.com \
  --record-set-name n8n \
  --ipv4-address <your-vm-public-ip>
```

Then use `n8n.yourdomain.com` as the hostname.

## Directory Structure

After deployment, files are located in `/opt/n8n/`:

```
/opt/n8n/
├── docker-compose.yml      # Docker Compose configuration
├── .env                    # Environment variables
├── nginx/
│   ├── nginx.conf          # Main Nginx configuration
│   └── conf.d/
│       └── n8n.conf        # n8n virtual host configuration
├── certbot/
│   ├── www/                # ACME challenge files
│   └── conf/               # SSL certificates
└── workflows/              # n8n workflows (synced from GitHub)
```

## GitHub Workflows Integration

### Setup

1. Create a GitHub repository for your workflows
2. Add workflow JSON files to the repository
3. Pass the repository URL with `--workflows-repo` parameter

### Manual Sync

```bash
cd /opt/n8n/workflows
git pull
docker restart n8n
```

### For Qwen Coder Access

Qwen Coder can:
1. Read existing workflows from the GitHub repository
2. Create new workflow JSON files
3. Commit changes to the repository
4. Changes will be automatically available after git pull

Example workflow structure in GitHub repo:
```
n8n-workflows/
├── webhook-processor.json
├── daily-report.json
├── api-integration.json
└── README.md
```

## Access n8n

After successful deployment:
- **URL**: `https://your-hostname` (port 443 with HTTPS)
- **First login**: Create your admin account

## SSL Certificate Auto-Renewal

Certificates are automatically renewed via cron job (monthly check).

Manual renewal:
```bash
cd /opt/n8n
docker-compose run --rm certbot renew
docker-compose restart nginx
```

## Troubleshooting

### Certificate Generation Fails

1. Verify DNS is properly configured:
   ```bash
   nslookup your-hostname
   ```

2. Check if port 80 is accessible:
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. In Azure Portal, ensure Network Security Group allows:
   - Port 80 (HTTP)
   - Port 443 (HTTPS)

### View Logs

```bash
# All services
cd /opt/n8n
docker-compose logs -f

# Specific service
docker-compose logs n8n
docker-compose logs nginx
docker-compose logs certbot
```

### Restart Services

```bash
cd /opt/n8n
docker-compose restart
```

## Security Notes

- HTTPS is enforced (HTTP redirects to HTTPS)
- Security headers are configured (HSTS, X-Frame-Options, etc.)
- WebSocket support enabled for real-time features
- Secure cookies enabled

## Backup

Backup your n8n data:
```bash
docker run --rm \
  -v /opt/n8n/n8n_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/n8n-backup-$(date +%Y%m%d).tar.gz -C /data .
```

## Update n8n

```bash
cd /opt/n8n
docker-compose pull
docker-compose up -d
```
