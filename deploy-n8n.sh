#!/bin/bash

# =============================================================================
# n8n Deployment Script for Azure Ubuntu VM
# Features:
# - Docker & Docker Compose installation
# - n8n deployment on port 80
# - Azure DNS integration
# - GitHub workflow synchronization
# =============================================================================

set -e

# Configuration Variables
N8N_VERSION="latest"
N8N_PORT="80"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
AZURE_DNS_ZONE="${AZURE_DNS_ZONE:-}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"
VM_PUBLIC_IP="${VM_PUBLIC_IP:-}"
N8N_HOSTNAME="${N8N_HOSTNAME:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root or use sudo"
        exit 1
    fi
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    apt-get install -y curl git wget apt-transport-https ca-certificates software-properties-common
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    
    # Remove old versions if any
    apt-get remove -y docker docker-engine docker.io containerd runc || true
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Set up the repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log_info "Docker installed successfully"
}

# Install Docker Compose (standalone)
install_docker_compose() {
    log_info "Installing Docker Compose..."
    
    DOCKER_COMPOSE_VERSION="v2.24.0"
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log_info "Docker Compose installed successfully"
}

# Configure Azure CLI (optional)
install_azure_cli() {
    log_info "Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    log_info "Azure CLI installed successfully"
}

# Configure Azure DNS
configure_azure_dns() {
    if [ -z "$AZURE_DNS_ZONE" ] || [ -z "$AZURE_RESOURCE_GROUP" ] || [ -z "$VM_PUBLIC_IP" ]; then
        log_warn "Azure DNS configuration skipped. Missing required variables."
        log_warn "Set AZURE_DNS_ZONE, AZURE_RESOURCE_GROUP, and VM_PUBLIC_IP to configure DNS"
        return 0
    fi
    
    log_info "Configuring Azure DNS..."
    
    # Login to Azure (if not already logged in)
    if ! az account show &> /dev/null; then
        log_info "Please login to Azure CLI"
        az login
    fi
    
    # Create A record for n8n
    if [ -n "$N8N_HOSTNAME" ]; then
        log_info "Creating DNS A record for $N8N_HOSTNAME.$AZURE_DNS_ZONE"
        az network dns record-set a add-record \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --zone-name "$AZURE_DNS_ZONE" \
            --record-set-name "$N8N_HOSTNAME" \
            --ipv4-address "$VM_PUBLIC_IP"
        
        log_info "DNS record created successfully"
    else
        # Use @ (root domain)
        log_info "Creating DNS A record for @$AZURE_DNS_ZONE"
        az network dns record-set a add-record \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --zone-name "$AZURE_DNS_ZONE" \
            --record-set-name "@" \
            --ipv4-address "$VM_PUBLIC_IP"
        
        log_info "DNS record created successfully"
    fi
}

# Create n8n directory structure
create_directories() {
    log_info "Creating n8n directory structure..."
    
    mkdir -p /opt/n8n/{data,workflows,backups}
    mkdir -p /opt/n8n/github-workflows
    
    # Set permissions
    chown -R 1000:1000 /opt/n8n/data
    chmod -R 755 /opt/n8n
    
    log_info "Directories created successfully"
}

# Clone GitHub repository for workflows
clone_github_workflows() {
    if [ -z "$GITHUB_REPO_URL" ]; then
        log_warn "GitHub repository URL not provided. Skipping workflow sync."
        log_warn "Set GITHUB_REPO_URL to sync workflows from GitHub"
        return 0
    fi
    
    log_info "Cloning GitHub repository for workflows..."
    
    cd /opt/n8n
    git clone "$GITHUB_REPO_URL" github-workflows || {
        log_warn "Failed to clone repository. You can clone it manually later."
        return 0
    }
    
    cd github-workflows
    git checkout "$GITHUB_BRANCH" || git checkout main
    
    log_info "GitHub repository cloned successfully"
}

# Create Docker Compose file
create_docker_compose() {
    log_info "Creating Docker Compose configuration..."
    
    cat > /opt/n8n/docker-compose.yml << 'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:${N8N_VERSION}
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      - N8N_HOST=${N8N_HOSTNAME:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:80/}
      - GENERIC_TIMEZONE=${TZ:-UTC}
      # Data persistence
      - N8N_USER_FOLDER=/home/node/.n8n
      # Database (SQLite by default, can be changed to PostgreSQL)
      - DB_TYPE=sqlite
      - DB_SQLITE_PATH=/home/node/.n8n/database.sqlite
      # Security
      - N8N_BASIC_AUTH_ACTIVE=false
      # Workflow storage
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
    volumes:
      - ./data:/home/node/.n8n
      - ./workflows:/home/node/.n8n/workflows
      - ./backups:/home/node/.n8n/backups
      - ./github-workflows:/home/node/.n8n/github-workflows:ro
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  n8n-network:
    driver: bridge
EOF

    # Replace variables in docker-compose.yml
    sed -i "s/\${N8N_VERSION}/${N8N_VERSION}/g" /opt/n8n/docker-compose.yml
    sed -i "s/\${N8N_PORT}/${N8N_PORT}/g" /opt/n8n/docker-compose.yml
    
    log_info "Docker Compose configuration created"
}

# Create environment file
create_env_file() {
    log_info "Creating environment file..."
    
    cat > /opt/n8n/.env << EOF
# n8n Configuration
N8N_VERSION=${N8N_VERSION}
N8N_PORT=${N8N_PORT}
N8N_HOSTNAME=${N8N_HOSTNAME:-localhost}
WEBHOOK_URL=http://${N8N_HOSTNAME:-localhost}:${N8N_PORT}/
TZ=UTC

# GitHub Configuration
GITHUB_REPO_URL=${GITHUB_REPO_URL}
GITHUB_BRANCH=${GITHUB_BRANCH:-main}

# Azure Configuration
AZURE_DNS_ZONE=${AZURE_DNS_ZONE}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
VM_PUBLIC_IP=${VM_PUBLIC_IP}
EOF

    log_info "Environment file created"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > /etc/systemd/system/n8n.service << 'EOF'
[Unit]
Description=n8n Workflow Automation
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload
    systemctl enable n8n.service
    
    log_info "Systemd service created and enabled"
}

# Start n8n
start_n8n() {
    log_info "Starting n8n..."
    
    cd /opt/n8n
    docker-compose up -d
    
    # Wait for n8n to be ready
    log_info "Waiting for n8n to start..."
    sleep 10
    
    # Check if n8n is running
    if docker ps | grep -q n8n; then
        log_info "n8n started successfully!"
    else
        log_error "Failed to start n8n. Check logs with: docker logs n8n"
        exit 1
    fi
}

# Create workflow sync script
create_sync_script() {
    log_info "Creating workflow synchronization script..."
    
    cat > /opt/n8n/sync-workflows.sh << 'EOF'
#!/bin/bash

# Workflow Synchronization Script
# This script pulls latest changes from GitHub and syncs workflows

set -e

WORKFLOW_DIR="/opt/n8n/github-workflows"
GITHUB_REPO_URL="${GITHUB_REPO_URL:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

if [ -z "$GITHUB_REPO_URL" ]; then
    echo "Error: GITHUB_REPO_URL not set"
    exit 1
fi

cd "$WORKFLOW_DIR"

# Pull latest changes
git pull origin "$GITHUB_BRANCH"

# Copy workflows to n8n workflows directory
cp -r *.json /opt/n8n/workflows/ 2>/dev/null || true

echo "Workflows synchronized successfully"
EOF

    chmod +x /opt/n8n/sync-workflows.sh
    
    # Create cron job for automatic sync (every hour)
    echo "0 * * * * /opt/n8n/sync-workflows.sh >> /var/log/n8n-sync.log 2>&1" | crontab -
    
    log_info "Workflow sync script created with hourly cron job"
}

# Display setup information
display_info() {
    echo ""
    echo "=================================================="
    echo "          n8n Deployment Complete!"
    echo "=================================================="
    echo ""
    
    if [ -n "$N8N_HOSTNAME" ]; then
        echo "Access n8n at: http://${N8N_HOSTNAME}"
    else
        echo "Access n8n at: http://${VM_PUBLIC_IP:-localhost}"
    fi
    
    echo ""
    echo "Important paths:"
    echo "  - Installation: /opt/n8n"
    echo "  - Workflows: /opt/n8n/workflows"
    echo "  - GitHub workflows: /opt/n8n/github-workflows"
    echo "  - Backups: /opt/n8n/backups"
    echo ""
    echo "Useful commands:"
    echo "  - View logs: docker logs n8n"
    echo "  - Stop n8n: cd /opt/n8n && docker-compose down"
    echo "  - Start n8n: cd /opt/n8n && docker-compose up -d"
    echo "  - Restart n8n: systemctl restart n8n"
    echo "  - Sync workflows: /opt/n8n/sync-workflows.sh"
    echo ""
    echo "=================================================="
}

# Main execution
main() {
    log_info "Starting n8n deployment on Azure Ubuntu VM..."
    
    check_root
    update_system
    install_docker
    install_docker_compose
    install_azure_cli
    configure_azure_dns
    create_directories
    clone_github_workflows
    create_docker_compose
    create_env_file
    create_systemd_service
    start_n8n
    create_sync_script
    display_info
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --github-repo)
            GITHUB_REPO_URL="$2"
            shift 2
            ;;
        --github-branch)
            GITHUB_BRANCH="$2"
            shift 2
            ;;
        --dns-zone)
            AZURE_DNS_ZONE="$2"
            shift 2
            ;;
        --resource-group)
            AZURE_RESOURCE_GROUP="$2"
            shift 2
            ;;
        --vm-ip)
            VM_PUBLIC_IP="$2"
            shift 2
            ;;
        --hostname)
            N8N_HOSTNAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --github-repo URL       GitHub repository URL for workflows"
            echo "  --github-branch BRANCH  GitHub branch (default: main)"
            echo "  --dns-zone ZONE         Azure DNS zone name"
            echo "  --resource-group RG     Azure resource group"
            echo "  --vm-ip IP              VM public IP address"
            echo "  --hostname HOSTNAME     n8n hostname (subdomain)"
            echo "  --help                  Show this help message"
            echo ""
            echo "Or set environment variables:"
            echo "  export GITHUB_REPO_URL='https://github.com/user/repo.git'"
            echo "  export AZURE_DNS_ZONE='example.com'"
            echo "  export AZURE_RESOURCE_GROUP='my-rg'"
            echo "  export VM_PUBLIC_IP='x.x.x.x'"
            echo "  export N8N_HOSTNAME='n8n'"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main
